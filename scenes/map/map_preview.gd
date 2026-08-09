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

var _hovered_region_id: String = ""
var _highlight_mesh: MeshInstance3D = null
var _highlight_material: StandardMaterial3D


func _ready() -> void:
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
# Raycasting
# ---------------------------------------------------------------------------

func _update_hover(local_pos: Vector2) -> void:
	_update_hover_region(_raycast_region_id(local_pos))


func _update_hover_region(region_id: String) -> void:
	if region_id == _hovered_region_id:
		return
	_hovered_region_id = region_id
	_set_highlight(region_id)
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


# ---------------------------------------------------------------------------
# Hover highlight
# ---------------------------------------------------------------------------

func _set_highlight(region_id: String) -> void:
	if _highlight_mesh != null:
		_highlight_mesh.queue_free()
		_highlight_mesh = null

	if region_id == "":
		return

	var collider := _find_collider_for_region(region_id)
	if collider == null:
		return

	var shape_node := collider.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		return

	var concave := shape_node.shape as ConcavePolygonShape3D
	if concave == null:
		return

	var faces: PackedVector3Array = concave.get_faces()
	if faces.is_empty():
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

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