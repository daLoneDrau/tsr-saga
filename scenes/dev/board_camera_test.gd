# board_camera_test.gd
# SCRATCH SCENE — not part of the game. Isolated rig for deriving 5.2.3
# Default Camera Framing from scratch: board mesh + camera only, no UI,
# no pieces, no game systems.
#
# NOTE ON PROJECTION MODE: defaults to ORTHOGRAPHIC, matching the locked
# design spec (3.3, 5.2.3 — "already-locked angled orthographic
# projection"). A perspective mode was tried and is still available via
# the P toggle for future comparison, but was set aside: perspective's
# near/far size distortion made pieces near the top of the board render
# smaller and shifted relative to their true position, which works
# against consistent click targeting. Orthographic keeps every piece at
# true scale/position regardless of board depth, so it stays the default.
#
# The board's true AABB is computed at runtime by walking every
# MeshInstance3D under BoardRoot (the instanced saga_map.glb) and unioning
# their world-space bounds. This deliberately includes ALL board geometry
# — terrain, borders, any decorative frame/rim mesh — not just the
# terrain-only AABB used elsewhere in the codebase for pan-clamping.
#
# ORTHOGRAPHIC fitting: the AABB's 8 corners are projected onto the
# camera's own right/up axes (NOT simply world width x depth, since the
# view is angled). Godot's Camera3D.size under default keep_aspect =
# KEEP_HEIGHT is the world-space VERTICAL extent shown; horizontal is
# size * aspect. 640x480 is 4:3 (wider than tall), so KEEP_HEIGHT is the
# relevant mode.
#
# PERSPECTIVE fitting: translating the camera straight back along its own
# view axis does NOT change a point's lateral (right/up) offset from that
# axis — only its depth. So for each AABB corner we compute its fixed
# lateral offset and the minimum depth required for that offset to stay
# inside the FOV cone at that depth (depth >= lateral / tan(half_fov)),
# then solve for the camera distance that satisfies the worst-case corner
# on both axes. This is exact for a rigid backward translation at fixed
# orientation, which is exactly what "move the camera farther back" is.
#
# Defaults: Orthographic, yaw=0°, pitch=45°, margin=1%. LOCKED as of the
# 5.2.3 Default Camera Framing pass — these are the values that belong in
# the real IsoCameraRig. No longer runtime-adjustable here: yaw/pitch/
# margin are fixed constants, not exported vars, and there's no on-screen
# readout — this scene now just shows the framed board + a random hero
# marker placement, nothing else.
#
# Controls at runtime (Play this scene directly, F6):
#   [ / ]   — adjust FOV (perspective mode only)
#   P       — toggle Perspective <-> Orthographic (comparison only; not the locked mode)
#   M       — re-roll the random hero marker to a new region + reframe to its Regional Focus
#   O       — return camera to Board Overview (smooth reframe, same as M/O both drive)
#   R       — reset FOV/projection mode to defaults (yaw/pitch/margin are fixed, nothing to reset there)

extends Node3D
class_name BoardCameraTest

const VIEWPORT_SIZE := Vector2(640.0, 480.0)
const RIG_BACK_DISTANCE := 200.0  # orthographic only; ortho ignores distance for scale

# Locked camera framing values — see header. No longer @export/runtime-tunable.
const YAW_DEGREES := 0.0
const PITCH_DEGREES := 45.0
const MARGIN_FRACTION := 0.01  # 1%

const FOV_DEFAULT := 30.0
const USE_PERSPECTIVE_DEFAULT := false

# --- Random hero marker placement ---
# Deliberately reads map.json / cell_markers.json directly rather than going
# through SagaMapSystem/SagaBoardSystem — this scratch scene stays "no game
# systems" per the header above. Region entity_ids and the ECS aren't needed
# to answer "which land region, which cell, where in the world" — just the
# raw region_id strings both data files already share.
const MAP_DATA_PATH := "res://saga/data/map.json"
const CELL_MARKERS_PATH := "res://saga/data/cell_markers.json"
const HERO_MARKER_SCENE_PATH := "res://assets/art/models/map/hero_marker.tscn"

# Name of the region-border overlay mesh inside saga_map.glb, hidden at
# Board Overview scale — reads cleanly close-up but is visual noise here.
const REGION_BORDERS_NODE_NAME := "Region_Borders_Thin"

@export_range(15.0, 60.0, 0.5) var fov_degrees: float = FOV_DEFAULT
@export var use_perspective: bool = USE_PERSPECTIVE_DEFAULT

@onready var _yaw_pivot: Node3D = $YawPivot
@onready var _pitch_pivot: Node3D = $YawPivot/PitchPivot
@onready var _camera: Camera3D = $YawPivot/PitchPivot/Camera3D
@onready var _board_root: Node3D = $BoardRoot

var _board_aabb: AABB
var _board_center: Vector3

var _land_region_ids: Array = []          # Array[String] — every land region_id from map.json
var _cells_by_region: Dictionary = {}     # region_id -> Array[Dictionary] (raw cell_markers.json entries)
var _hero_markers: Array[Node3D] = []     # all currently placed markers; re-rolled as a group, not stacked

const MARKERS_PER_REGION := 1
# Minimum Chebyshev distance (max of |dx|,|dy|) between two marker cells
# that guarantees at least one empty cell buffer in every direction around
# each — adjacency (distance 1) means the markers touch with no buffer at
# all, so the target is >= 2. Only relaxed down to "not the same cell" if
# the region is too small to satisfy that.
const MIN_MARKER_CELL_SPACING := 2

# 5.2.30 — Piece Entry: "New pieces descend into their final anchor and
# settle." Two-part motion: a straight vertical descend from above the
# anchor (accelerating like a dropped physical object, not a linear
# glide), then a brief settle — a small squash on landing that eases back
# to resting scale, giving the piece some physical weight instead of
# stopping dead. This is entry-only per 5.2.30, not the lift/elevated
# travel/descend/settle full movement animation from 5.2.29 — there's no
# prior position to lift from, a piece is simply arriving.
const MARKER_DROP_HEIGHT := 3.0        # world units above the anchor to start the descend
const MARKER_DESCEND_DURATION := 0.35
const MARKER_SETTLE_DURATION := 0.18
const MARKER_SETTLE_SQUASH := Vector3(1.15, 0.75, 1.15)

# TESTING ONLY — the very first marker placement happens in _ready(),
# before the scene/viewport has necessarily finished its first frame, so
# the entry animation could start (or even resolve) before anything is
# visibly on screen. This delay just gives the scene a moment to actually
# render before the drop-and-settle plays, so it's visible when testing.
# Not a real gameplay concern — mid-game marker placement happens well
# after the scene is already up and running. Remove once this scratch
# scene stops being used to eyeball the entry animation directly.
const TEST_INITIAL_PLACEMENT_DELAY := 0.5

# --- 5.2.4 Regional Focus ---
# Reframes (pans AND zooms) to the smallest area covering the mover's
# current region plus every region reachable within movement speed —
# NOT a single-region isolate. Reuses the exact same "project AABB
# corners onto camera right/up axes, solve size" math as Board Overview
# fitting, just fed a smaller AABB and a more generous margin, since the
# explicit goal here is preserving surrounding context, not maximizing
# fill. Camera angle (yaw/pitch) never changes — Regional Focus is a
# different framing bound at the same locked angle, not a different shot.
#
# TESTING ONLY: this scratch scene has no live hero stats, so there's no
# real MOVEMENT_SPEED to test with. TEST_MOVEMENT_SPEED substitutes a
# fixed hop count for SagaMovementSystem.get_reachable_regions()'s
# stat-driven lookup — same BFS, same map.json adjacency, just a stand-in
# for the number a real hero's stats would supply.
const TEST_MOVEMENT_SPEED := 4

# How much extra room beyond the tight-fit bounds to leave around the
# current+reachable region set, so neighboring geography stays legible
# as context rather than the view feeling cropped right at the relevant
# regions' edges. Deliberately much larger than Board Overview's locked
# 1% — Overview wants maximum fill, Regional Focus wants breathing room.
const REGIONAL_FOCUS_MARGIN_FRACTION := 0.25

const REGIONAL_FOCUS_TRANSITION_DURATION := 0.8

# region_id -> Array[String] of adjacent region_ids, both land and sea —
# mirrors SagaMapSystem's adjacency graph, built directly from map.json
# here since this scratch scene doesn't run the full ECS/ SagaMapSystem.
var _adjacency: Dictionary = {}

var _camera_tween: Tween = null
var _o_held := false

var _p_held := false
var _r_held := false
var _m_held := false


func _ready() -> void:
	_camera.current = true
	_board_aabb = _compute_board_aabb(_board_root)
	_board_center = _board_aabb.position + _board_aabb.size / 2.0
	if _board_aabb.size == Vector3.ZERO:
		push_warning("BoardCameraTest: board AABB came back empty — check BoardRoot has the saga_map instance with visible MeshInstance3D children.")
	_hide_region_borders()
	_apply_rig()
	_print_locked_overview_transforms()

	_load_map_regions()
	_load_cells_by_region()

	if TEST_INITIAL_PLACEMENT_DELAY > 0.0:
		await get_tree().create_timer(TEST_INITIAL_PLACEMENT_DELAY).timeout
	#_place_random_hero_markers()


## Hides the region-border overlay mesh — reads cleanly in the close-up
## view but is visual noise at full Board Overview scale. Deliberately
## done AFTER _compute_board_aabb() runs, not before: hiding it first
## would make get_aabb() calls on it return zero/skip it (mesh visibility
## affects AABB queries in some Godot versions), and this mesh may
## legitimately be part of what defines the board's true edge extent.
## Hiding only affects rendering, not the framing math.
func _hide_region_borders() -> void:
	var borders := _board_root.find_child(REGION_BORDERS_NODE_NAME, true, false)
	if borders and borders is MeshInstance3D:
		(borders as MeshInstance3D).visible = false
	elif not borders:
		push_warning("BoardCameraTest: no '%s' node found under BoardRoot — check the exact node name in saga_map.glb." % REGION_BORDERS_NODE_NAME)


func _process(delta: float) -> void:
	var changed := false
	var fov_speed := 15.0 * delta

	if Input.is_key_pressed(KEY_BRACKETRIGHT):
		fov_degrees = clampf(fov_degrees + fov_speed, 15.0, 60.0)
		changed = true
	if Input.is_key_pressed(KEY_BRACKETLEFT):
		fov_degrees = clampf(fov_degrees - fov_speed, 15.0, 60.0)
		changed = true

	if Input.is_key_pressed(KEY_R):
		if not _r_held:
			fov_degrees = FOV_DEFAULT
			use_perspective = USE_PERSPECTIVE_DEFAULT
			changed = true
		_r_held = true
	else:
		_r_held = false

	if Input.is_key_pressed(KEY_P):
		if not _p_held:
			use_perspective = not use_perspective
			changed = true
		_p_held = true
	else:
		_p_held = false

	if Input.is_key_pressed(KEY_M):
		if not _m_held:
			_place_random_hero_markers()
		_m_held = true
	else:
		_m_held = false

	if Input.is_key_pressed(KEY_O):
		if not _o_held:
			_reframe_camera_to_aabb(_board_aabb, MARGIN_FRACTION, REGIONAL_FOCUS_TRANSITION_DURATION)
		_o_held = true
	else:
		_o_held = false

	if changed:
		_apply_rig()


func _apply_rig() -> void:
	if _board_aabb.size == Vector3.ZERO:
		return

	_yaw_pivot.global_position = _board_center
	_yaw_pivot.rotation = Vector3.ZERO
	_yaw_pivot.rotate_y(deg_to_rad(YAW_DEGREES))

	_pitch_pivot.rotation = Vector3.ZERO
	_pitch_pivot.rotate_x(deg_to_rad(-PITCH_DEGREES))

	# Orientation only — translation doesn't affect this, so it's safe to
	# read before deciding the camera's actual distance below.
	var rig_basis: Basis = _pitch_pivot.global_transform.basis
	var right: Vector3 = rig_basis.x.normalized()
	var up: Vector3 = rig_basis.y.normalized()
	var view: Vector3 = -rig_basis.z.normalized()  # forward, camera-into-scene
	var aspect: float = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y

	if use_perspective:
		_apply_perspective(right, up, view, aspect)
	else:
		_apply_orthographic(right, up, aspect)


func _apply_orthographic(right: Vector3, up: Vector3, aspect: float) -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.transform = Transform3D(Basis(), Vector3(0.0, 0.0, RIG_BACK_DISTANCE))

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
	var fitted_size: float = maxf(size_from_height, size_from_width)
	fitted_size *= (1.0 + MARGIN_FRACTION)

	_camera.size = fitted_size
	_camera.near = 0.1
	_camera.far = RIG_BACK_DISTANCE + _board_aabb.size.length() + 50.0


func _apply_perspective(right: Vector3, up: Vector3, view: Vector3, aspect: float) -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = fov_degrees
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT

	var half_v: float = deg_to_rad(fov_degrees) / 2.0
	var half_h: float = atan(tan(half_v) * aspect)
	var margin_scale: float = 1.0 + MARGIN_FRACTION

	# For each corner, find the depth (distance along `view` from the
	# board center's own plane) needed for that corner's fixed lateral
	# offset to sit inside the FOV cone, then take the worst case. This
	# depth is measured relative to the board-center plane, so once
	# solved we still need to add the extra backward shift D such that
	# camera_position = board_center - view*D places the camera at
	# exactly that required depth from each corner (see derivation in
	# the header comment: lateral offset is invariant to shifts along
	# `view`, only depth changes).
	var max_required_extra_depth := -INF
	var max_forward_offset := -INF  # for far-plane sizing

	for corner in _aabb_corners(_board_aabb):
		var rel: Vector3 = corner - _board_center
		var lateral_r: float = absf(rel.dot(right)) * margin_scale
		var lateral_u: float = absf(rel.dot(up)) * margin_scale
		var forward_offset: float = rel.dot(view)  # can be + or -

		var req_depth_r: float = lateral_r / tan(half_h)
		var req_depth_u: float = lateral_u / tan(half_v)
		var req_depth: float = maxf(req_depth_r, req_depth_u)

		# depth(corner) = D + forward_offset  (D = camera's backward
		# distance from board_center along view). Need depth >= req_depth
		# for every corner => D >= req_depth - forward_offset.
		var required_D: float = req_depth - forward_offset
		max_required_extra_depth = maxf(max_required_extra_depth, required_D)
		max_forward_offset = maxf(max_forward_offset, forward_offset)

	var distance: float = maxf(max_required_extra_depth, 1.0)  # guard against degenerate/negative

	_camera.transform = Transform3D(Basis(), Vector3(0.0, 0.0, distance))
	_camera.near = 0.1
	_camera.far = distance + max_forward_offset + 50.0


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
## MeshInstance3D found. This is the FULL modeled board — whatever meshes
## actually exist under BoardRoot, including any frame/ornament geometry
## beyond the terrain-only box used elsewhere for pan-clamping.
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


## Parses map.json, collecting both:
##  - every region_id whose "type" is "land" (the same set
##    SagaBoardSystem.random_land_location() draws from)
##  - the full adjacency graph (region_id -> Array[String] neighbor
##    region_ids, land AND sea), mirroring SagaMapSystem's own adjacency —
##    needed for Regional Focus's reachable-region BFS.
## Read directly here since this scene has no ECS entities/SagaMapSystem
## to draw from.
func _load_map_regions() -> void:
	var file := FileAccess.open(MAP_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("BoardCameraTest: failed to open %s" % MAP_DATA_PATH)
		return
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed.has("regions"):
		push_error("BoardCameraTest: malformed map data at %s" % MAP_DATA_PATH)
		return

	var regions: Dictionary = parsed["regions"]
	_land_region_ids.clear()
	_adjacency.clear()
	for region_id: String in regions.keys():
		var info: Dictionary = regions[region_id]
		if info.get("type", "") == "land":
			_land_region_ids.append(region_id)
		_adjacency[region_id] = info.get("neighbors", [])


## Parses cell_markers.json once and groups every LAND cell entry by its
## region_id, so picking a random cell for a given region is an O(1)
## lookup + random index rather than a scan through every cell every time.
## Sea-type cells are dropped here even though _land_region_ids already
## restricts which region gets picked — this is a second, explicit check
## on the cell's own "type" field, so a marker can never land on a sea
## cell even if a land region ever turns out to contain a stray coastal/
## sea-tagged cell in the data.
func _load_cells_by_region() -> void:
	var file := FileAccess.open(CELL_MARKERS_PATH, FileAccess.READ)
	if file == null:
		push_error("BoardCameraTest: failed to open %s" % CELL_MARKERS_PATH)
		return
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed.has("cells"):
		push_error("BoardCameraTest: malformed cell marker data at %s" % CELL_MARKERS_PATH)
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
## centroid, nearest first — NOT the bounding-box center. A raw
## bounding-box center can fall outside an irregularly shaped or concave
## region entirely (or even inside a neighboring sea cell), since it only
## looks at the region's min/max extent, not its actual footprint.
## Averaging every land cell's own x/y gives a centroid pulled toward
## wherever the region's mass actually is, and sorting by distance to it
## (rather than just taking the single nearest) is what lets the caller
## pick more than one marker cell while still favoring cells close to the
## region's center.
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
## a cell (orthogonal and diagonal alike) as equally distance 1.
func _cell_chebyshev_distance(a: Dictionary, b: Dictionary) -> int:
	var dx: int = absi(int(a.get("x", 0)) - int(b.get("x", 0)))
	var dy: int = absi(int(a.get("y", 0)) - int(b.get("y", 0)))
	return maxi(dx, dy)


## Picks MARKERS_PER_REGION cells from `cells`, all favoring proximity to
## the region's centroid, while trying to keep every pair at least
## MIN_MARKER_CELL_SPACING apart (Chebyshev) so each marker has a full
## empty-cell buffer in all 8 directions. Greedy: takes the centroid-
## nearest cell first, then repeatedly takes the next centroid-nearest
## cell that's still properly spaced from everything already chosen. If
## the region is too small/cramped to satisfy full spacing for every slot,
## falls back to the closest still-available cell that isn't an exact
## duplicate of one already chosen — adjacency is allowed as a last
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


## The placement: random land region -> MARKERS_PER_REGION cells in that
## region, all near its centroid and spaced apart per
## _pick_spaced_marker_cells() -> hero_marker.tscn at each cell's matching
## Node3D point in the glb. Region choice is random each roll; cell choice
## within the region is deterministic for a given region (always the same
## ranked set), so re-rolling moves the markers to a different region
## rather than jittering them within the same one. No on-screen readout —
## results print to the Output panel instead.
func _place_random_hero_markers() -> void:
	if _land_region_ids.is_empty():
		push_warning("BoardCameraTest: no land regions loaded, can't place markers.")
		return

	var region_id: String = _land_region_ids[randi_range(0, _land_region_ids.size() - 1)]
	var cells: Array = _cells_by_region.get(region_id, [])
	if cells.is_empty():
		push_warning("BoardCameraTest: region '%s' has no cells in cell_markers.json." % region_id)
		return

	if not ResourceLoader.exists(HERO_MARKER_SCENE_PATH):
		push_error("BoardCameraTest: hero marker scene not found at %s" % HERO_MARKER_SCENE_PATH)
		return
	var packed := load(HERO_MARKER_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("BoardCameraTest: failed to load %s as PackedScene" % HERO_MARKER_SCENE_PATH)
		return

	for marker in _hero_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_hero_markers.clear()

	var chosen_cells: Array = _pick_spaced_marker_cells(cells, MARKERS_PER_REGION)
	if chosen_cells.size() < MARKERS_PER_REGION:
		push_warning("BoardCameraTest: region '%s' only has %d land cell(s) — placing fewer than %d markers." % [region_id, chosen_cells.size(), MARKERS_PER_REGION])

	for cell: Dictionary in chosen_cells:
		var cell_name: String = cell.get("name", "")
		var marker_point := _board_root.find_child(cell_name, true, false)
		if marker_point == null or not (marker_point is Node3D):
			push_warning("BoardCameraTest: no Node3D named '%s' found under BoardRoot — check saga_map.glb has this marker point." % cell_name)
			continue

		var world_pos: Vector3 = (marker_point as Node3D).global_position

		var marker := packed.instantiate() as Node3D
		if marker == null:
			push_error("BoardCameraTest: hero_marker.tscn root is not a Node3D")
			continue

		add_child(marker)
		_apply_outline_scale_to_marker(marker)
		_animate_marker_entry(marker, world_pos)
		_hero_markers.append(marker)

		print("BoardCameraTest: placed hero marker — region=%s cell=%s pos=%s" % [region_id, cell_name, world_pos])

	_focus_on_region_and_reachable(region_id)


## Keeps each marker's inverted-hull outline a constant on-screen pixel
## width regardless of world-space scale — needed because our camera is
## orthographic, so outline thickness in world units would otherwise look
## thinner/thicker depending on how far a cell happens to sit from camera
## center on an angled view. No-ops outside orthographic (nothing to
## convert if there's no fixed cam.size to derive pixels-per-world-unit
## from).
func _update_outline_scale(outline_material: ShaderMaterial) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.projection != Camera3D.PROJECTION_ORTHOGONAL:
		return
	var viewport_height := get_viewport().get_visible_rect().size.y
	# Assumes default keep_aspect = KEEP_HEIGHT, where cam.size is the
	# vertical extent of the frustum in world units.
	var world_units_per_pixel := cam.size / viewport_height
	outline_material.set_shader_parameter("world_units_per_pixel", world_units_per_pixel)


## Finds every MeshInstance3D under a freshly-placed marker and, for
## whichever material actually carries the outline shader as its
## next_pass, feeds it through _update_outline_scale(). Checks
## material_override first (whole-instance override, same convention
## map_preview.gd's outline markers use), falling back to each surface's
## own material if no override is set, since we don't know hero_marker.tscn's
## exact material setup in advance.
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


## 5.2.30 Piece Entry: descend into final anchor, then settle. Starts the
## marker above `final_pos` and drops it in with an accelerating ease (a
## dropped object speeds up, it doesn't glide at constant speed), then
## does a quick squash-and-recover on landing so it reads as settling
## rather than stopping dead. Runs on the marker's own scale, so it composes
## fine with whatever base scale hero_marker.tscn already has.
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


## Unweighted BFS from origin_region_id, mirroring
## SagaMapSystem.get_reachable() exactly (same "free movement, cannot be
## interrupted" rule -> shortest hop-count is all that matters). Returns
## every region_id reachable within max_hops, NOT including origin_region_id
## itself. Works over the full adjacency graph (land and sea alike), same
## as the real system — Regional Focus shouldn't need to know or care
## which of those are land vs sea to compute reachability correctly.
func _get_reachable_region_ids(origin_region_id: String, max_hops: int) -> Array:
	if max_hops <= 0 or not _adjacency.has(origin_region_id):
		return []

	var distances: Dictionary = {origin_region_id: 0}
	var queue: Array = [origin_region_id]
	var reachable: Array = []

	while not queue.is_empty():
		var current: String = queue.pop_front()
		var current_dist: int = distances[current]
		if current_dist >= max_hops:
			continue
		for neighbor in _adjacency.get(current, []):
			if not distances.has(neighbor):
				distances[neighbor] = current_dist + 1
				reachable.append(neighbor)
				queue.append(neighbor)

	return reachable


## Returns region_id's TRUE world-space footprint, taken from its actual
## click/highlight collider (land_<region_id> / sea_<region_id>, the same
## StaticBody3D + ConcavePolygonShape3D geometry map_preview.gd's
## _build_region_overlay_mesh() reconstructs into a visual mesh) rather
## than approximating from cell_markers.json's coarse grid. This is the
## authoritative shape already trusted for hit-testing and region
## highlighting, so it's the right source for "does this framing actually
## contain the region," not a stand-in. Returns a zero-size AABB if the
## collider/shape isn't found (region_id typo, or the region has no
## collider for some reason) — callers should treat that as "skip this
## region" rather than a hard failure.
func _region_footprint_aabb(region_id: String) -> AABB:
	var collider := _board_root.find_child("land_" + region_id, true, false)
	if collider == null:
		collider = _board_root.find_child("sea_" + region_id, true, false)
	if collider == null:
		push_warning("BoardCameraTest: no land_/sea_ collider found for region '%s'." % region_id)
		return AABB()

	var shape_node := collider.find_child("CollisionShape3D", true, false) as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		push_warning("BoardCameraTest: region '%s' collider has no CollisionShape3D/shape." % region_id)
		return AABB()

	var concave := shape_node.shape as ConcavePolygonShape3D
	if concave == null:
		push_warning("BoardCameraTest: region '%s' collision shape isn't a ConcavePolygonShape3D." % region_id)
		return AABB()

	var faces: PackedVector3Array = concave.get_faces()
	if faces.is_empty():
		return AABB()

	var xform: Transform3D = shape_node.global_transform
	var result := AABB()
	var first := true
	for local_v in faces:
		var world_v: Vector3 = xform * local_v
		if first:
			result = AABB(world_v, Vector3.ZERO)
			first = false
		else:
			result = result.expand(world_v)
	return result


## Unions the true footprint AABBs of every region in region_ids. Skips
## (rather than fails on) any region whose footprint couldn't be found,
## since one missing/misnamed collider shouldn't block framing the rest.
func _union_region_footprints(region_ids: Array) -> AABB:
	var result := AABB()
	var first := true
	for region_id: String in region_ids:
		var footprint := _region_footprint_aabb(region_id)
		if footprint.size == Vector3.ZERO:
			continue
		if first:
			result = footprint
			first = false
		else:
			result = result.merge(footprint)
	return result


## Animates the camera rig to pan AND zoom (Camera3D.size) to fit
## target_aabb, with margin_fraction of extra room, over duration seconds.
## Orthographic only — camera angle (yaw/pitch) is never touched, only
## where the rig sits and how tight its ortho size is, matching "Regional
## Focus is a different framing bound at the same locked angle." Shares
## its fitting math with the Board Overview path (project AABB corners
## onto the camera's own right/up axes — see the header comment on why
## that's needed for an angled, non-top-down view), just parameterized by
## whatever AABB and margin the caller passes in — Board Overview itself
## is really just a call to this with _board_aabb and MARGIN_FRACTION.
func _reframe_camera_to_aabb(target_aabb: AABB, margin_fraction: float, duration: float) -> void:
	if use_perspective:
		push_warning("BoardCameraTest: reframe currently only supports orthographic; skipping.")
		return
	if target_aabb.size == Vector3.ZERO:
		push_warning("BoardCameraTest: reframe target AABB is empty; skipping.")
		return

	var rig_basis: Basis = _pitch_pivot.global_transform.basis  # rotation only — stable regardless of rig position
	var right: Vector3 = rig_basis.x.normalized()
	var up: Vector3 = rig_basis.y.normalized()
	var aspect: float = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y

	var new_center: Vector3 = target_aabb.position + target_aabb.size / 2.0

	var min_r := INF
	var max_r := -INF
	var min_u := INF
	var max_u := -INF
	for corner in _aabb_corners(target_aabb):
		var rel: Vector3 = corner - new_center
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
	var fitted_size: float = maxf(size_from_height, size_from_width) * (1.0 + margin_fraction)

	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = create_tween()
	_camera_tween.set_parallel(true)
	_camera_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(_yaw_pivot, "global_position", new_center, duration)
	_camera_tween.tween_property(_camera, "size", fitted_size, duration)


## 5.2.4 Regional Focus: reframes to the smallest area covering
## region_id plus every region reachable from it within
## TEST_MOVEMENT_SPEED hops — not an isolate-single-region frame. Prints
## the resolved region set to the Output panel since there's no on-screen
## readout anymore.
func _focus_on_region_and_reachable(region_id: String) -> void:
	var reachable: Array = _get_reachable_region_ids(region_id, TEST_MOVEMENT_SPEED)
	var region_ids_to_include: Array = [region_id]
	region_ids_to_include.append_array(reachable)

	var union_aabb := _union_region_footprints(region_ids_to_include)
	if union_aabb.size == Vector3.ZERO:
		push_warning("BoardCameraTest: couldn't resolve any footprint geometry for region '%s' or its reachable set." % region_id)
		return

	print("BoardCameraTest: Regional Focus — region=%s reachable=%s (%d regions total)" % [region_id, reachable, region_ids_to_include.size()])
	_reframe_camera_to_aabb(union_aabb, REGIONAL_FOCUS_MARGIN_FRACTION, REGIONAL_FOCUS_TRANSITION_DURATION)


## Prints the locked Board Overview rig's exact transforms + fitted zoom,
## formatted exactly as Godot's .tscn "transform = Transform3D(...)" lines,
## so they can be copied straight into map_preview.tscn's IsoCameraRig /
## PitchPivot / Camera3D nodes with no hand transcription — and therefore
## no risk of a sign/axis error creeping in between this validated scratch
## rig and the real one. IsoCameraRig's origin is forced to (0,0,0) here
## even though this scene positions the rig at the board's own center for
## its own framing math — in map_preview.tscn, panning is a separate,
## already-existing runtime concern (center_on_region tweens
## _camera_rig.position), so the AUTHORED baseline transform should carry
## only the locked rotation, matching how the original rig was authored.
func _print_locked_overview_transforms() -> void:
	var yaw_basis: Basis = _yaw_pivot.transform.basis
	var pitch_basis: Basis = _pitch_pivot.transform.basis
	var cam_local_z: float = _camera.transform.origin.z

	print("--- Locked Board Overview camera values (copy into map_preview.tscn) ---")
	print("IsoCameraRig transform = %s" % _format_transform3d(yaw_basis, Vector3.ZERO))
	print("PitchPivot   transform = %s" % _format_transform3d(pitch_basis, Vector3.ZERO))
	print("Camera3D     transform = %s" % _format_transform3d(Basis(), Vector3(0.0, 0.0, cam_local_z)))
	print("Camera3D     projection = 1  (PROJECTION_ORTHOGONAL)")
	print("Camera3D     size = %.6f" % _camera.size)
	print("Camera3D     near = %.3f" % _camera.near)
	print("Camera3D     far = %.3f" % _camera.far)
	print("--- end locked values ---")


func _format_transform3d(basis: Basis, origin: Vector3) -> String:
	return "Transform3D(%.8f, %.8f, %.8f, %.8f, %.8f, %.8f, %.8f, %.8f, %.8f, %.8f, %.8f, %.8f)" % [
		basis.x.x, basis.x.y, basis.x.z,
		basis.y.x, basis.y.y, basis.y.z,
		basis.z.x, basis.z.y, basis.z.z,
		origin.x, origin.y, origin.z,
		]


func _find_mesh_instances(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_mesh_instances(child))
	return found