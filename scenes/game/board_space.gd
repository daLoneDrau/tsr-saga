# board_space.gd
# Board rendering foundation for the rebuilt GameScene — replaces
# map_preview.gd's role as of the board/camera-first redesign pass.
#
# Camera: locked Board Overview (yaw 0°, pitch 45°, margin 1%,
# orthographic). Angle is a fixed design constant (pure trig, no mesh
# dependency); pan position and zoom are computed live from the board
# mesh's real AABB every load, using the fitting math validated in
# board_camera_test.gd, rather than baking in specific numbers that could
# go stale if the board mesh changes.
#
# Entity markers: place_entity_markers() places one marker per entity
# (hero/jarl/monster), grouped by region and spaced so entities sharing a
# region don't crowd each other — same cell-selection, entry-animation,
# and outline-scaling logic validated in the board_camera_test.gd scratch
# scene, ported here as the production path. This widget does NOT resolve
# which region an entity belongs to — that's game-system knowledge
# (SagaBoardSystem/SagaMapSystem) and stays GameScene's job, matching the
# same "rendering widget doesn't know game systems" discipline
# map_preview.gd's own header already established. BoardSpace only ever
# receives region_id strings + entity descriptors, never entity_ids it
# has to resolve locations for itself.
#
# NOT a preview/prototype widget — board_space.tscn is the actual
# production board rendering surface GameScene.tscn uses.

class_name BoardSpace
extends SubViewportContainer

const VIEWPORT_SIZE := Vector2(640.0, 480.0)
const RIG_BACK_DISTANCE := 200.0  # orthographic — ortho ignores distance for scale, just needs to clear the board

# Locked Board Overview framing — see 5.2.3 Default Camera Framing.
const YAW_DEGREES := 0.0
const PITCH_DEGREES := 45.0
const MARGIN_FRACTION := 0.01  # 1%

# Name of the region-border overlay mesh inside saga_map.glb, hidden at
# Board Overview scale — reads cleanly close-up but is visual noise here.
const REGION_BORDERS_NODE_NAME := "Region_Borders_Thin"

# --- Entity marker placement ---
const CELL_MARKERS_PATH := "res://saga/data/cell_markers.json"

const MARKER_SCENE_PATHS: Dictionary = {
	"hero":    "res://assets/art/models/map/hero_marker_v_2.tscn",
	"jarl":    "res://assets/art/models/map/jarl_marker_v_2.tscn",
	"monster": "res://assets/art/models/map/monster_marker_v_2.tscn",
}

# Minimum Chebyshev distance (max of |dx|,|dy|) between two marker cells
# that guarantees at least one empty cell buffer in every direction around
# each — adjacency (distance 1) means the markers touch with no buffer at
# all, so the target is >= 2. Only relaxed down to "not the same cell" if
# a region has too few cells to satisfy that for everyone placed there.
const MIN_MARKER_CELL_SPACING := 2

# 5.2.30 — Piece Entry: "New pieces descend into their final anchor and
# settle." Straight vertical descend from above the anchor (accelerating,
# like a dropped object — not a linear glide), then a brief squash-and-
# recover on landing so it reads as settling rather than stopping dead.
const MARKER_DROP_HEIGHT := 3.0
const MARKER_DESCEND_DURATION := 0.35
const MARKER_SETTLE_DURATION := 0.18
const MARKER_SETTLE_SQUASH := Vector3(1.15, 0.75, 1.15)

@onready var _board_root: Node3D = %BoardRoot
@onready var _yaw_pivot: Node3D = %IsoCameraRig
@onready var _pitch_pivot: Node3D = %PitchPivot
@onready var _camera: Camera3D = %Camera3D

var _board_aabb: AABB
var _board_center: Vector3

var _cells_by_region: Dictionary = {}          # region_id -> Array[Dictionary] (raw cell_markers.json land cells)
var _entity_markers: Dictionary = {}           # entity_id -> Node3D, so future moves/removals can find a marker by entity


func _ready() -> void:
	_camera.current = true
	_board_aabb = _compute_board_aabb(_board_root)
	if _board_aabb.size == Vector3.ZERO:
		push_warning("BoardSpace: board AABB came back empty — check BoardRoot has the saga_map instance with visible MeshInstance3D children.")
		return
	_board_center = _board_aabb.position + _board_aabb.size / 2.0

	_hide_region_borders()
	_apply_overview_framing()
	_load_cells_by_region()


## Hides the region-border overlay mesh — reads cleanly in a future
## close-up view but is visual noise at full Board Overview scale.
## Deliberately done AFTER _compute_board_aabb() runs, not before: hiding
## it first could make get_aabb() calls on it return zero/skip it in some
## Godot versions, and this mesh may legitimately be part of what defines
## the board's true edge extent. Hiding only affects rendering, not the
## framing math.
func _hide_region_borders() -> void:
	var borders := _board_root.find_child(REGION_BORDERS_NODE_NAME, true, false)
	if borders and borders is MeshInstance3D:
		(borders as MeshInstance3D).visible = false
	elif not borders:
		push_warning("BoardSpace: no '%s' node found under BoardRoot — check the exact node name in saga_map.glb." % REGION_BORDERS_NODE_NAME)


## Sets the locked yaw/pitch rotation, positions the rig at the board's
## true center, and solves Camera3D.size so the whole board fits the
## 640x480 frame with MARGIN_FRACTION of breathing space — identical
## math to board_camera_test.gd's _apply_orthographic().
func _apply_overview_framing() -> void:
	_yaw_pivot.global_position = _board_center
	_yaw_pivot.rotation = Vector3.ZERO
	_yaw_pivot.rotate_y(deg_to_rad(YAW_DEGREES))

	_pitch_pivot.rotation = Vector3.ZERO
	_pitch_pivot.rotate_x(deg_to_rad(-PITCH_DEGREES))

	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.transform = Transform3D(Basis(), Vector3(0.0, 0.0, RIG_BACK_DISTANCE))

	var rig_basis: Basis = _pitch_pivot.global_transform.basis
	var right: Vector3 = rig_basis.x.normalized()
	var up: Vector3 = rig_basis.y.normalized()
	var aspect: float = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y

	var min_r := INF
	var max_r := -INF
	var min_u := INF
	var max_u := -INF
	for corner in _aabb_corners(_board_aabb):
		var rel: Vector3 = corner - _board_center
		var r: float = rel.dot(right)
		var u: float = rel.dot(up)
		min_r = minf(min_r, r)
		max_r = maxf(max_r, r)
		min_u = minf(min_u, u)
		max_u = maxf(max_u, u)

	var extent_w: float = max_r - min_r
	var extent_h: float = max_u - min_u
	var size_from_height := extent_h
	var size_from_width := extent_w / aspect
	var fitted_size: float = maxf(size_from_height, size_from_width) * (1.0 + MARGIN_FRACTION)

	_camera.size = fitted_size
	_camera.near = 0.1
	_camera.far = RIG_BACK_DISTANCE + _board_aabb.size.length() + 50.0


# ---------------------------------------------------------------------------
#region Entity marker placement
# ---------------------------------------------------------------------------

## Places one marker per entry in `entities`, grouped by region so
## entities sharing a region get spaced apart rather than potentially
## stacking on the same cell. All markers are placed together (same call,
## same frame) — this is initial spawn placement, not a piece arriving on
## its own, so there's no reason to stagger them relative to each other.
##
## entities: Array[Dictionary], each: { "entity_id": String,
## "kind": "hero"|"jarl"|"monster", "region_id": String }. BoardSpace never
## resolves entity_id -> region_id itself — the caller (GameScene) already
## did that via SagaBoardSystem/SagaMapSystem, matching the same
## "rendering widget doesn't touch game systems" split map_preview.gd uses.
func place_entity_markers(entities: Array) -> void:
	var by_region: Dictionary = {}  # region_id -> Array[Dictionary] (entity entries)
	for entry: Dictionary in entities:
		var region_id: String = entry.get("region_id", "")
		if region_id == "":
			push_warning("BoardSpace: entity '%s' has no region_id, skipping." % entry.get("entity_id", "?"))
			continue
		if not by_region.has(region_id):
			by_region[region_id] = []
		by_region[region_id].append(entry)

	for region_id: String in by_region.keys():
		_place_region_markers(region_id, by_region[region_id])


func _place_region_markers(region_id: String, region_entities: Array) -> void:
	var cells: Array = _cells_by_region.get(region_id, [])
	if cells.is_empty():
		push_warning("BoardSpace: region '%s' has no cells in cell_markers.json — can't place %d entit%s there." % [region_id, region_entities.size(), "y" if region_entities.size() == 1 else "ies"])
		return

	var chosen_cells: Array = _pick_spaced_marker_cells(cells, region_entities.size())
	if chosen_cells.size() < region_entities.size():
		push_warning("BoardSpace: region '%s' only has %d usable cell(s) for %d entit%s." % [region_id, chosen_cells.size(), region_entities.size(), "y" if region_entities.size() == 1 else "ies"])

	for i in range(min(chosen_cells.size(), region_entities.size())):
		var cell: Dictionary = chosen_cells[i]
		var entry: Dictionary = region_entities[i]
		_place_single_marker(entry, cell)


func _place_single_marker(entry: Dictionary, cell: Dictionary) -> void:
	print("_place_single_marker(", entry)
	var entity_id: String = entry.get("entity_id", "")
	var kind: String = entry.get("kind", "")
	var cell_name: String = cell.get("name", "")

	var scene_path: String = MARKER_SCENE_PATHS.get(kind, "")
	if scene_path == "":
		push_error("BoardSpace: unknown entity kind '%s' for entity '%s' — no marker scene mapped." % [kind, entity_id])
		return
	if not ResourceLoader.exists(scene_path):
		push_error("BoardSpace: marker scene not found at %s" % scene_path)
		return

	var marker_point := _board_root.find_child(cell_name, true, false)
	if marker_point == null or not (marker_point is Node3D):
		push_warning("BoardSpace: no Node3D named '%s' found under BoardRoot for entity '%s'." % [cell_name, entity_id])
		return
	var world_pos: Vector3 = (marker_point as Node3D).global_position

	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("BoardSpace: failed to load %s as PackedScene" % scene_path)
		return

	var existing: Node3D = _entity_markers.get(entity_id)
	if existing != null and is_instance_valid(existing):
		existing.queue_free()

	var marker := packed.instantiate() as Node3D
	if marker == null:
		push_error("BoardSpace: marker scene root is not a Node3D at %s" % scene_path)
		return

	add_child(marker)
	_apply_outline_scale_to_marker(marker)
	_animate_marker_entry(marker, world_pos)
	_entity_markers[entity_id] = marker


## Parses cell_markers.json once and groups every LAND cell entry by its
## region_id. Sea-type cells are dropped here even though callers only
## ever pass region_ids that setup already placed entities on as land —
## this is a second, explicit check on the cell's own "type" field, same
## safety net validated in board_camera_test.gd.
func _load_cells_by_region() -> void:
	var file := FileAccess.open(CELL_MARKERS_PATH, FileAccess.READ)
	if file == null:
		push_error("BoardSpace: failed to open %s" % CELL_MARKERS_PATH)
		return
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed.has("cells"):
		push_error("BoardSpace: malformed cell marker data at %s" % CELL_MARKERS_PATH)
		return

	_cells_by_region.clear()
	for cell: Dictionary in parsed["cells"]:
		if cell.get("type", "") != "land":
			continue
		var region_id: String = cell.get("region", "")
		if region_id == "":
			continue
		if not _cells_by_region.has(region_id):
			_cells_by_region[region_id] = []
		_cells_by_region[region_id].append(cell)


## Returns every cell in `cells` sorted by distance to their own x/y
## centroid, nearest first — NOT the bounding-box center, which can fall
## outside an irregularly shaped or concave region entirely (or even
## inside a neighboring sea cell).
func _cells_sorted_by_centroid_distance(cells: Array) -> Array:
	var sum_x := 0.0
	var sum_y := 0.0
	for cell: Dictionary in cells:
		sum_x += float(cell.get("x", 0))
		sum_y += float(cell.get("y", 0))
	var centroid_x: float = sum_x / cells.size()
	var centroid_y: float = sum_y / cells.size()

	var sorted_cells: Array = cells.duplicate()
	sorted_cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var adx: float = float(a.get("x", 0)) - centroid_x
		var ady: float = float(a.get("y", 0)) - centroid_y
		var bdx: float = float(b.get("x", 0)) - centroid_x
		var bdy: float = float(b.get("y", 0)) - centroid_y
		return (adx * adx + ady * ady) < (bdx * bdx + bdy * bdy)
	)
	return sorted_cells


## Chebyshev distance (max of |dx|, |dy|) between two cells' grid
## coordinates — the right metric for "how many empty cells of buffer sit
## between them" on a square grid, since it treats the 8 neighbors around
## a cell as equally distance 1.
func _cell_chebyshev_distance(a: Dictionary, b: Dictionary) -> int:
	var dx: int = absi(int(a.get("x", 0)) - int(b.get("x", 0)))
	var dy: int = absi(int(a.get("y", 0)) - int(b.get("y", 0)))
	return maxi(dx, dy)


## Picks `count` cells from `cells`, all favoring proximity to the
## region's centroid, while trying to keep every pair at least
## MIN_MARKER_CELL_SPACING apart (Chebyshev) so each marker has a full
## empty-cell buffer in all directions. Greedy: takes the centroid-
## nearest cell first, then repeatedly takes the next centroid-nearest
## cell that's still properly spaced from everything already chosen. If
## the region is too small/cramped to satisfy full spacing for every
## slot, falls back to the closest still-available cell that isn't an
## exact duplicate of one already chosen — adjacency is allowed as a last
## resort, but two markers stacked on the same cell never is.
func _pick_spaced_marker_cells(cells: Array, count: int) -> Array:
	var ranked := _cells_sorted_by_centroid_distance(cells)
	var chosen: Array = []

	for cell: Dictionary in ranked:
		if chosen.size() >= count:
			break
		var far_enough := true
		for picked: Dictionary in chosen:
			if _cell_chebyshev_distance(cell, picked) < MIN_MARKER_CELL_SPACING:
				far_enough = false
				break
		if far_enough:
			chosen.append(cell)

	if chosen.size() < count:
		for cell: Dictionary in ranked:
			if chosen.size() >= count:
				break
			var already_chosen := false
			for picked: Dictionary in chosen:
				if picked.get("name", "") == cell.get("name", ""):
					already_chosen = true
					break
			if not already_chosen:
				chosen.append(cell)

	return chosen


## Keeps each marker's inverted-hull outline a constant on-screen pixel
## width regardless of world-space scale — needed because our camera is
## orthographic, so outline thickness in world units would otherwise look
## thinner/thicker depending on how far a cell happens to sit from camera
## center on an angled view.
func _update_outline_scale(outline_material: ShaderMaterial) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.projection != Camera3D.PROJECTION_ORTHOGONAL:
		return
	var viewport_height := get_viewport().get_visible_rect().size.y
	var world_units_per_pixel := cam.size / viewport_height
	outline_material.set_shader_parameter("world_units_per_pixel", world_units_per_pixel)


## Finds every MeshInstance3D under a freshly-placed marker and, for
## whichever material actually carries the outline shader as its
## next_pass, feeds it through _update_outline_scale(). Checks
## material_override first (whole-instance override), falling back to
## each surface's own material if no override is set, since the exact
## material setup isn't known in advance for any of the three marker
## scenes.
func _apply_outline_scale_to_marker(marker: Node3D) -> void:
	for mesh_instance: MeshInstance3D in _find_mesh_instances(marker):
		var materials: Array = []
		if mesh_instance.material_override != null:
			materials.append(mesh_instance.material_override)
		elif mesh_instance.mesh != null:
			for i in range(mesh_instance.mesh.get_surface_count()):
				var surface_mat := mesh_instance.get_surface_override_material(i)
				if surface_mat == null:
					surface_mat = mesh_instance.mesh.surface_get_material(i)
				if surface_mat != null:
					materials.append(surface_mat)

		for mat in materials:
			var outline_mat := mat.next_pass as ShaderMaterial
			if outline_mat != null:
				_update_outline_scale(outline_mat)


## 5.2.30 Piece Entry: descend into final anchor, then settle.
func _animate_marker_entry(marker: Node3D, final_pos: Vector3) -> void:
	var base_scale: Vector3 = marker.scale
	marker.global_position = final_pos + Vector3(0.0, MARKER_DROP_HEIGHT, 0.0)

	var tween := create_tween()
	tween.tween_property(marker, "global_position", final_pos, MARKER_DESCEND_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(marker, "scale", base_scale * MARKER_SETTLE_SQUASH, MARKER_SETTLE_DURATION * 0.4) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(marker, "scale", base_scale, MARKER_SETTLE_DURATION * 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

#endregion


func _aabb_corners(aabb: AABB) -> Array:
	var corners: Array = []
	for i in range(8):
		corners.append(aabb.position + Vector3(
				aabb.size.x * float(i & 1),
				aabb.size.y * float((i >> 1) & 1),
				aabb.size.z * float((i >> 2) & 1)
		))
	return corners


## Walks node's subtree, unions the world-space AABB of every
## MeshInstance3D found — the FULL modeled board (terrain, borders, any
## frame/ornament geometry), not the terrain-only box used elsewhere for
## pan-clamping.
func _compute_board_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mesh_instance in _find_mesh_instances(node):
		var local_aabb: AABB = mesh_instance.get_aabb()
		var xform: Transform3D = mesh_instance.global_transform
		for corner in _aabb_corners(local_aabb):
			var world_corner: Vector3 = xform * corner
			if first:
				result = AABB(world_corner, Vector3.ZERO)
				first = false
			else:
				result = result.expand(world_corner)
	return result


func _find_mesh_instances(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_mesh_instances(child))
	return found