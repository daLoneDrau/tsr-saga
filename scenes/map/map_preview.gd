class_name MapPreview
extends SubViewportContainer
## SAGA Map View — Phase 2: click-to-select + hover raycasting.
##
## Purely a rendering/input widget — knows nothing about game systems.
## Raycasts against the map's `-colonly` collision bodies (imported as
## StaticBody3D nodes named "land_<region_id>" / "sea_<region_id>", suffix
## already stripped by Godot's glTF importer — see the map widget roadmap
## notes) and emits region_id strings (map.json keys, e.g. "1_1_Finmark",
## "01"). The caller (GameScene) is responsible for resolving region_id ->
## entity_id via SagaMapSystem.get_entity_for_region_id() and calling
## whatever game logic follows — this script never touches SagaMapSystem,
## SagaMovementSystem, etc. directly, so it stays reusable/testable in
## isolation.
##
## Hover highlight: reconstructs a renderable mesh from the hovered
## region's own ConcavePolygonShape3D.get_faces() data at runtime — the
## `-colonly` import convention deliberately has NO visual MeshInstance3D
## per region (that's the whole point of "colonly"), so there is no
## ready-made mesh to just toggle visible. Building one on demand from the
## collision shape's own face data keeps this to a single dynamic overlay
## mesh rather than 66 pre-built ones sitting in memory unused.

signal region_clicked(region_id: String)
signal region_hover_changed(region_id: String)  # "" when hover leaves every region


@onready var _svp: SubViewport = $SubViewport
@onready var _cam: Camera3D = $SubViewport/IsoCameraRig/PitchPivot/Camera3D
@onready var _camera_rig: Node3D = $SubViewport/IsoCameraRig

var _hovered_region_id: String = ""
var _highlight_mesh: MeshInstance3D = null
var _highlight_material: StandardMaterial3D
var _reachable_meshes: Dictionary = {}
var _reachable_material: StandardMaterial3D

# entity_id -> MeshInstance3D. Reused across refreshes rather than
# destroyed/recreated every time, so occupants that haven't moved don't
# visibly flicker.
var _occupant_markers: Dictionary = {}
var _hero_mesh: CapsuleMesh
var _jarl_mesh: SphereMesh
var _monster_mesh: BoxMesh
var _outline_shader: Shader

# Phase 4 — camera centering. Tracks the last region actually centered on
# so repeated _refresh() calls with an unchanged mover don't retrigger a
# pan every time (same stability principle as occupant markers).
var _centered_region_id: String = ""
var _camera_tween: Tween


func _ready() -> void:
	_reachable_material = StandardMaterial3D.new()
	_reachable_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_reachable_material.albedo_color = Color(0.3, 1.0, 0.4, 0.35)
	_reachable_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_reachable_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_reachable_material.render_priority = 2

	_highlight_material = StandardMaterial3D.new()
	_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_material.albedo_color = Color(1.0, 0.9, 0.3, 0.45)
	_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Same trick used to fix Region_Borders vs. Grid_001 z-fighting — see
	# BorderThick.tres/BorderThin.tres. The highlight sits at the same
	# height as the terrain/border geometry, so it needs to reliably win
	# the depth tie against both.
	_highlight_material.render_priority = 2

	_hero_mesh = CapsuleMesh.new()
	_hero_mesh.radius = 0.3
	_hero_mesh.height = 2.0

	_jarl_mesh = SphereMesh.new()
	_jarl_mesh.radius = 0.375
	_jarl_mesh.height = 0.75

	_monster_mesh = BoxMesh.new()
	_monster_mesh.size = Vector3(0.75, 0.75, 0.75)

	# Same inverted-hull outline technique already used on hero materials
	# (see assets/art/materials/heroes/skin/*.tres for the established
	# convention: base material's next_pass = a ShaderMaterial using this
	# shader) — makes markers read clearly against the map's own colors.
	_outline_shader = load("res://shaders/toon_outline.gdshader")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var region_id := _raycast_region_id(event.position)
			if region_id != "":
				region_clicked.emit(region_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_update_hover_region("")


# ---------------------------------------------------------------------------
#region Raycasting
# ---------------------------------------------------------------------------

func _update_hover(local_pos: Vector2) -> void:
	_update_hover_region(_raycast_region_id(local_pos))


func _update_hover_region(region_id: String) -> void:
	if region_id == _hovered_region_id:
		return
	_hovered_region_id = region_id
	_set_highlight(region_id)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if region_id != "" else Control.CURSOR_ARROW
	region_hover_changed.emit(region_id)


## Casts a ray from the camera through `local_pos` (in this Control's own
## coordinate space — valid directly as a SubViewport pixel position since
## SubViewportContainer.stretch keeps the two in a 1:1 mapping) and returns
## the region_id of whatever `-colonly` collider it hits, or "" for none.
func _raycast_region_id(local_pos: Vector2) -> String:
	if _cam == null:
		return ""
	var from: Vector3 = _cam.project_ray_origin(local_pos)
	var dir: Vector3 = _cam.project_ray_normal(local_pos)
	var to: Vector3 = from + dir * _cam.far
	var space_state := _svp.find_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return ""
	var collider: Object = result.get("collider")
	if collider == null or not (collider is Node):
		return ""
	return _region_id_from_collider_name((collider as Node).name)


func _region_id_from_collider_name(node_name: String) -> String:
	if node_name.begins_with("land_"):
		return node_name.substr(5)
	if node_name.begins_with("sea_"):
		return node_name.substr(4)
	return ""

#endregion


# ---------------------------------------------------------------------------
#region Hover highlight
# ---------------------------------------------------------------------------

func _set_highlight(region_id: String) -> void:
	if _highlight_mesh != null:
		_highlight_mesh.queue_free()
		_highlight_mesh = null

	if region_id == "":
		return

	var mesh := _build_region_overlay_mesh(region_id)
	if mesh == null:
		return
	var collider := _find_collider_for_region(region_id)

	_highlight_mesh = MeshInstance3D.new()
	_highlight_mesh.mesh = mesh
	_highlight_mesh.material_override = _highlight_material
	_highlight_mesh.position = Vector3(0, 0.05, 0)  # small lift, belt-and-braces against z-fighting
	collider.add_child(_highlight_mesh)


func _find_collider_for_region(region_id: String) -> StaticBody3D:
	var saga_map := _svp.get_node_or_null("saga_map")
	if saga_map == null:
		return null
	var node: Node = saga_map.get_node_or_null("land_" + region_id)
	if node == null:
		node = saga_map.get_node_or_null("sea_" + region_id)
	return node as StaticBody3D


## Reconstructs a renderable mesh from region_id's own collision shape
## data — shared by the hover highlight and reachable-region highlight,
## both of which need "a flat overlay covering exactly this region's
## footprint" and neither of which has a ready-made visual mesh to use
## (see the class header on why `-colonly` regions have none). Returns
## null if region_id doesn't resolve to a real, shaped collider.
func _build_region_overlay_mesh(region_id: String) -> ArrayMesh:
	var collider := _find_collider_for_region(region_id)
	if collider == null:
		return null

	var shape_node := collider.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		return null

	var concave := shape_node.shape as ConcavePolygonShape3D
	if concave == null:
		return null

	var faces: PackedVector3Array = concave.get_faces()
	if faces.is_empty():
		return null

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

#endregion

# ---------------------------------------------------------------------------
#region Reachable-region highlight (Phase 5)
# ---------------------------------------------------------------------------

## Highlights every region in region_ids (map.json keys) as reachable by
## the current mover. Replaces whatever was highlighted before outright —
## unlike occupant markers/hover, there's no reason to preserve identity
## across calls here: the reachable set is fully recomputed by the caller
## every time the mover or their position changes, not incrementally
## updated, so diffing old-vs-new would just be extra bookkeeping for no
## benefit. Pass an empty array to clear (e.g. when the movement phase is
## over and nothing is reachable).
func set_reachable_regions(region_ids: Array) -> void:
	for mesh in _reachable_meshes.values():
		if is_instance_valid(mesh):
			mesh.queue_free()
	_reachable_meshes.clear()

	for region_id in region_ids:
		var mesh := _build_region_overlay_mesh(region_id)
		if mesh == null:
			continue
		var collider := _find_collider_for_region(region_id)

		var overlay := MeshInstance3D.new()
		overlay.mesh = mesh
		overlay.material_override = _reachable_material
		# Sits between the border network (no lift) and the hover
		# highlight (0.05 lift) — see render_priority ordering in _ready():
		# borders < reachable < hover, so hovering a reachable region still
		# shows the hover effect on top rather than the two fighting.
		overlay.position = Vector3(0, 0.03, 0)
		collider.add_child(overlay)
		_reachable_meshes[region_id] = overlay

#endregion


# ---------------------------------------------------------------------------
#region Occupant markers (Phase 3)
# ---------------------------------------------------------------------------

## Renders one placeholder marker per occupant entry. Each entry is a
## Dictionary: {entity_id: String, region_id: String, is_large: bool,
## color: Color}. Deliberately dumb about what these entities actually
## are (hero/jarl/monster) — the caller decides is_large/color, this just
## places colored capsules.
##
## marker_system is handed in rather than looked up, so this stays testable
## without needing a full Scene/system-registry context (same reasoning as
## why click handling only ever emits raw region_id strings) — this is the
## one place this widget talks to a game system at all, and only ever
## through get_or_assign_marker()'s narrow (entity_id, region_id,
## candidate_names) -> node_name contract, never touching game state
## directly.
## marker_system is a SagaMapMarkerSystem, deliberately untyped here (see
## the class header) — statically typing this parameter would force this
## script to compile-time-resolve SagaMapMarkerSystem's full base class
## chain (GameSystem -> Scene -> the autoload-dependent ECS framework)
## every time this widget loads, which is exactly the coupling this file
## is meant to avoid. Duck-typed .get_or_assign_marker() call instead.
func refresh_occupant_markers(occupants: Array, marker_system) -> void:
	var saga_map := _svp.get_node_or_null("saga_map")
	if saga_map == null or marker_system == null:
		return

	var seen_entity_ids: Dictionary = {}

	for entry in occupants:
		var entity_id: String = entry.get("entity_id", "")
		var entity_type: String = entry.get("type", "")
		var region_id: String = entry.get("region_id", "")
		var is_large: bool = entry.get("is_large", false)
		var color: Color = entry.get("color", Color.WHITE)
		if entity_id == "" or region_id == "":
			continue

		var candidates := _candidate_marker_names(saga_map, region_id, is_large)
		var marker_node_name: String = marker_system.get_or_assign_marker(entity_id, region_id, candidates)
		if marker_node_name == "":
			continue

		var anchor := saga_map.get_node_or_null(marker_node_name) as Node3D
		if anchor == null:
			continue

		seen_entity_ids[entity_id] = true
		_place_occupant_marker(entity_id, entity_type, anchor.global_position, color)

	# Drop markers for entities no longer in this refresh's occupant list
	# (moved to a region with no line of sight from here, died, etc.).
	for entity_id in _occupant_markers.keys().duplicate():
		if not seen_entity_ids.has(entity_id):
			var mesh: MeshInstance3D = _occupant_markers[entity_id]
			if is_instance_valid(mesh):
				mesh.queue_free()
			_occupant_markers.erase(entity_id)


func _make_outline_material() -> ShaderMaterial:
	var outline := ShaderMaterial.new()
	outline.shader = _outline_shader
	outline.set_shader_parameter("outline_width", 0.2)
	outline.set_shader_parameter("outline_color", Color(0.05, 0.05, 0.05, 1))
	return outline


func _place_occupant_marker(entity_id: String, entity_type: StringName, world_pos: Vector3, color: Color) -> void:
	var marker: MeshInstance3D = _occupant_markers.get(entity_id)
	if marker == null or not is_instance_valid(marker):
		marker = MeshInstance3D.new()
		if entity_type == &"hero":
			marker.mesh = _hero_mesh
		elif entity_type == &"jarl":
			marker.mesh = _jarl_mesh
		elif entity_type == &"monster":
			marker.mesh = _monster_mesh
		else:
			push_error("map_preview._place_occupant_marker() invalid entity_type")
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.next_pass = _make_outline_material()
		_svp.get_node_or_null("saga_map").add_child(marker)
		marker.material_override = mat
		_occupant_markers[entity_id] = marker

	(marker.material_override as StandardMaterial3D).albedo_color = color
	# Capsule's own half-height keeps it from clipping into the terrain;
	# lift slightly further so it visibly stands above ground level.
	marker.global_position = world_pos + Vector3(0, 1.0, 0)


## Enumerates this region's actual candidate marker node names, filtered
## to "face" (small: hero/jarl/small enemies) or "corner" (large enemies)
## per is_large. Node names look like "spawn_<region_id>_face03" /
## "spawn_<region_id>_corner03" — see the map widget roadmap, Phase 3.
##
## Sorted by numeric suffix rather than left in raw child order: adjacent
## indices correspond to spatially adjacent points on the mesh (checked
## directly against the glb — consecutive indices sit ~0.75 units apart,
## vs. ~7 units for non-consecutive ones), which is what lets
## SagaMapMarkerSystem's index-based spacing check act as a real proxy for
## physical separation instead of an arbitrary ordering.
func _candidate_marker_names(saga_map: Node, region_id: String, is_large: bool) -> Array:
	var infix := "_corner" if is_large else "_face"
	var prefix := "spawn_%s%s" % [region_id, infix]
	var result: Array = []
	for child in saga_map.get_children():
		if child.name.begins_with(prefix):
			result.append(child.name)
	result.sort_custom(func(a: String, b: String):
		return _marker_index(a) < _marker_index(b)
	)
	return result


## Extracts the trailing numeric suffix from a marker node name, e.g.
## "spawn_4_2_Armorica_face03" -> 3. Returns -1 if none found (sorts those
## first, harmless — every real marker name has a numeric suffix).
func _marker_index(marker_name: String) -> int:
	var i: int = marker_name.length()
	while i > 0 and marker_name[i - 1].is_valid_int():
		i -= 1
	if i == marker_name.length():
		return -1
	return marker_name.substr(i).to_int()

#endregion


# ---------------------------------------------------------------------------
#region Camera centering (Phase 4)
# ---------------------------------------------------------------------------

# Combined visual AABB of the map's terrain (Region_Borders + Grid_001),
## measured directly against the glb — see the map widget roadmap. Used
## to keep the camera from panning so far toward an edge region that the
## map's own boundary ends up stranded in the middle of the frame with
## empty background filling the rest.
const MAP_BOUNDS_MIN := Vector2(-32.33642, -23.33373)
const MAP_BOUNDS_MAX := Vector2(32.33663, 23.33679)

## Smoothly pans the camera rig so region_id sits centered in frame,
## keeping the same fixed isometric angle/zoom — this moves the whole rig
## (IsoCameraRig), not the camera's own rotation, so nothing about the
## "look" established in Phase 1 changes, only what point it's aimed at.
##
## No-ops if region_id is already what's centered (same stability
## principle as occupant markers: repeated _refresh() calls with an
## unchanged mover shouldn't retrigger a pan every time).
##
## Uses the region's "banner_<region_id>" anchor as the centering point —
## a single canonical point per land region already authored for the
## conquest-banner feature (held for a later phase), reused here rather
## than computing a centroid ourselves. Sea regions have no banner anchor,
## but movers are always land-placed (see saga_setup_system.gd's
## random_land_location() calls), so this should always resolve in
## practice; no-ops harmlessly if it doesn't.
##
## The raw target is clamped (see _clamp_pan_target) so centering on an
## edge/corner region doesn't push the map's own edge toward the center of
## the screen, leaving empty background filling the rest of the frame.
func center_on_region(region_id: String) -> void:
	if region_id == "" or region_id == _centered_region_id:
		return

	var saga_map := _svp.get_node_or_null("saga_map")
	if saga_map == null:
		return
	var anchor := saga_map.get_node_or_null("banner_" + region_id) as Node3D
	if anchor == null:
		return

	var target := Vector3(anchor.global_position.x, _camera_rig.position.y, anchor.global_position.z)
	target = _clamp_pan_target(target)

	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = create_tween()
	_camera_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_tween.set_trans(Tween.TRANS_SINE)
	_camera_tween.tween_property(_camera_rig, "position", target, 0.5)

	_centered_region_id = region_id


## Clamps a candidate camera-rig target so the visible ground footprint
## (see _pan_footprint_offsets) never extends past the map's own bounds —
## i.e. the camera never pans far enough that the map's edge sits stranded
## in the middle of the frame with empty background filling the rest.
##
## How far (world units) the camera is allowed to pan away from the
## "can't avoid any whitespace" collapse point on an axis where the
## footprint is wider than the map. Ordinary/central targets are already
## within this zone and pass through _clamp_axis() completely unaffected;
## only targets beyond it get pulled back — that's what keeps this a cap
## on genuinely extreme corners rather than a blanket restriction on all
## panning (see the map widget roadmap for the discussion — the earlier
## zero-tolerance version pinned the camera near map-center for every
## region, not just extreme ones, since the footprint currently exceeds
## the map's own size on both axes at the established zoom level).
const PAN_TOLERANCE_MARGIN: float = 20.0

func _clamp_pan_target(target: Vector3) -> Vector3:
	var footprint := _pan_footprint_offsets()
	var min_offset: Vector2 = footprint["min"]
	var max_offset: Vector2 = footprint["max"]

	var clamped := target
	clamped.x = _clamp_axis(target.x, MAP_BOUNDS_MIN.x, MAP_BOUNDS_MAX.x, min_offset.x, max_offset.x)
	clamped.z = _clamp_axis(target.z, MAP_BOUNDS_MIN.y, MAP_BOUNDS_MAX.y, min_offset.y, max_offset.y)
	return clamped


## Clamps a single axis of a pan target against the range where the
## visible footprint stays within [map_lo, map_hi]. If the footprint is
## wider than the map on this axis (lo > hi — mathematically no position
## shows zero whitespace), falls back to a tolerance zone of width
## 2 * PAN_TOLERANCE_MARGIN centered on the collapse point instead of
## pinning to that single point outright.
func _clamp_axis(target_value: float, map_lo: float, map_hi: float, offset_lo: float, offset_hi: float) -> float:
	var lo := map_lo - offset_lo
	var hi := map_hi - offset_hi
	if lo > hi:
		var collapse := (lo + hi) / 2.0
		lo = collapse - PAN_TOLERANCE_MARGIN
		hi = collapse + PAN_TOLERANCE_MARGIN
	return clampf(target_value, lo, hi)


## Casts a ray from each of the current viewport's four screen corners
## through the camera, intersecting the ground plane at the rig's own
## current height, and returns how far those intersection points sit from
## the rig's own position (min/max per axis). Because the camera's
## rotation and size are fixed, this offset shape is invariant under
## translation — it's recomputed from the LIVE current camera/viewport
## state each call (cheap: 4 raycasts) rather than cached, so it stays
## correct even if the viewport is ever resized at runtime.
func _pan_footprint_offsets() -> Dictionary:
	var svp_size: Vector2 = _svp.size
	var corners := [
		Vector2(0, 0), Vector2(svp_size.x, 0),
		Vector2(0, svp_size.y), Vector2(svp_size.x, svp_size.y),
		]
	var rig_pos: Vector3 = _camera_rig.position
	var min_offset := Vector2(INF, INF)
	var max_offset := Vector2(-INF, -INF)

	for corner in corners:
		var from: Vector3 = _cam.project_ray_origin(corner)
		var dir: Vector3 = _cam.project_ray_normal(corner)
		if absf(dir.y) < 0.0001:
			continue
		var t: float = (rig_pos.y - from.y) / dir.y
		var point: Vector3 = from + dir * t
		var offset := Vector2(point.x - rig_pos.x, point.z - rig_pos.z)
		min_offset.x = minf(min_offset.x, offset.x)
		min_offset.y = minf(min_offset.y, offset.y)
		max_offset.x = maxf(max_offset.x, offset.x)
		max_offset.y = maxf(max_offset.y, offset.y)

	return {"min": min_offset, "max": max_offset}

#endregion
