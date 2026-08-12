class_name RegionCloseUpViewport
extends SubViewportContainer
## The 3D half of the region close-up modal — a dedicated SubViewport +
## Camera3D sharing the main map's World3D (see share_world()) rather than
## repositioning the eagle's-eye camera in place. This is what used to
## live in map_preview.gd's own "Phase 3.5" section; moved here wholesale
## as part of the modal rebuild — see the map widget roadmap for that
## discussion. Reuses the exact proven IsoCameraRig/PitchPivot/Camera3D
## transform values from map_preview.tscn (same fixed isometric angle),
## just with its own independent position/size, so there's zero risk of
## this camera ever affecting the eagle's-eye one.
##
## Deliberately dumb about game data, same as MapPreview: entries handed
## to set_occupants() carry entity_id/type/color/model_path/skin_path/
## hair_path, decided entirely by the caller (GameScene).

signal close_requested()
signal occupant_hover_changed(entity_id: String)  # "" when hover leaves every occupant

const OCCUPANT_HOVER_PIXEL_RADIUS: float = 40.0

@onready var _svp: SubViewport = $CloseUpSubViewport
@onready var _camera_rig: Node3D = $CloseUpSubViewport/IsoCameraRig
@onready var _cam: Camera3D = $CloseUpSubViewport/IsoCameraRig/PitchPivot/Camera3D

var _outline_shader: Shader
var _close_up_nodes: Dictionary = {}  # entity_id -> Node3D (real model or fallback primitive)
var _hovered_occupant_id: String = ""


func _ready() -> void:
	_outline_shader = load("res://shaders/toon_outline.gdshader")


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_update_occupant_hover_id("")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			close_requested.emit()


## Shares the eagle's-eye map's World3D so this viewport's camera renders
## the same saga_map geometry (and occupant markers) without needing to
## reload or duplicate any of it — same technique PortraitWidget already
## uses for its own diorama, just deliberate here rather than the
## accidental version that caused the yellow-bleed bug earlier in this
## project's history. find_world_3d() (not the raw world_3d property) is
## required — that property can be null when a viewport's own world was
## created implicitly rather than assigned explicitly.
func share_world(main_viewport: SubViewport) -> void:
	_svp.world_3d = main_viewport.find_world_3d()


## Points the camera at target_position (region_id's "banner_<region_id>"
## anchor — resolved by MapPreview.get_region_anchor_position(), since
## sharing world_3d shares the rendering scenario, not this viewport's own
## node tree, so there's no "saga_map" child here to search directly). No
## tween: the popup itself already animates in (scale-in, see
## region_close_up_modal.gd), so an additional camera pan on top would
## just be two motions competing for attention. No pan-tolerance clamping
## either, unlike the eagle's-eye camera — there's no "map edge stranded
## mid-frame" concern for a small, isolated close-up shot.
func focus_on_region(target_position: Vector3) -> void:
	_camera_rig.position = Vector3(target_position.x, _camera_rig.position.y, target_position.z)


# ---------------------------------------------------------------------------
#region Occupant models
# ---------------------------------------------------------------------------

## Shows real 3D models — falling back to a bigger primitive when no model
## is available yet — for every occupant entry. marker_positions maps
## entity_id -> the exact world position its eagle's-eye marker sits at
## (see MapPreview.hide_occupant_markers_and_get_positions), so a model
## appears in exactly the same spot the primitive was, rather than an
## independently-computed layout that could visibly disagree with it.
func set_occupants(entries: Array, marker_positions: Dictionary) -> void:
	clear_occupants()

	for entry in entries:
		var entity_id: String = entry.get("entity_id", "")
		if entity_id == "" or not marker_positions.has(entity_id):
			continue
		_place_occupant(entity_id, entry, marker_positions[entity_id])


func clear_occupants() -> void:
	for node in _close_up_nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	_close_up_nodes.clear()
	_update_occupant_hover_id("")


func _place_occupant(entity_id: String, entry: Dictionary, world_pos: Vector3) -> void:
	var model_path: String = entry.get("model_path", "")
	var node: Node3D = null

	if model_path != "" and ResourceLoader.exists(model_path):
		var packed: PackedScene = load(model_path) as PackedScene
		if packed != null:
			node = packed.instantiate() as Node3D
			if node == null:
				push_error("region_close_up_viewport: model root is not Node3D at %s" % model_path)

	if node != null:
		_apply_hero_palette(node, entry)
		_play_counter_pose(node)
	else:
		node = _build_fallback_mesh(entry)

	# No "saga_map" child exists in this viewport's own tree (sharing
	# world_3d shares the rendering scenario, not the node tree) — any
	# Node3D parented anywhere within a viewport sharing that scenario
	# renders correctly regardless of which viewport's tree it sits in,
	# so this just parents directly to our own SubViewport.
	_svp.add_child(node)
	node.global_position = world_pos
	_close_up_nodes[entity_id] = node


## Mirrors PortraitWidget._apply_palette()'s convention exactly (surface 0
## = skin, surface 1 = hair) — skin_path/hair_path are only ever non-empty
## for hero entries, so this is a no-op for jarls/monsters.
func _apply_hero_palette(node: Node3D, entry: Dictionary) -> void:
	var skin_path: String = entry.get("skin_path", "")
	var hair_path: String = entry.get("hair_path", "")
	if skin_path == "" and hair_path == "":
		return

	var mesh_node := _find_mesh_instance(node)
	if mesh_node == null:
		return

	if skin_path != "" and ResourceLoader.exists(skin_path):
		var skin_mat := load(skin_path) as Material
		if skin_mat != null:
			mesh_node.set_surface_override_material(0, skin_mat)

	if hair_path != "" and ResourceLoader.exists(hair_path):
		var hair_mat := load(hair_path) as Material
		if hair_mat != null:
			mesh_node.set_surface_override_material(1, hair_mat)


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var result := _find_mesh_instance(child)
		if result != null:
			return result
	return null


## Plays "counter_pose" if the model has one — a combat-ready stance,
## fitting for "here's who/what stands in this region". Held rather than
## forced to loop: it reads as a pose, not a cycle. Silently does nothing
## if the clip isn't present — not every model is guaranteed to have it.
func _play_counter_pose(node: Node3D) -> void:
	var anim_player := _find_animation_player(node)
	if anim_player == null or not anim_player.has_animation("counter_pose"):
		return
	anim_player.play("counter_pose")


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result != null:
			return result
	return null


## Bigger version of the same capsule/sphere/box eagle's-eye scale uses —
## shown when an occupant has no real model yet, so close-up still shows
## something distinct per type rather than nothing.
func _build_fallback_mesh(entry: Dictionary) -> MeshInstance3D:
	var entity_type: String = entry.get("type", "")
	var color: Color = entry.get("color", Color.WHITE)

	var mesh := MeshInstance3D.new()
	if entity_type == "hero":
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.9
		capsule.height = 3.0
		mesh.mesh = capsule
	elif entity_type == "jarl":
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		mesh.mesh = sphere
	else:
		var box := BoxMesh.new()
		box.size = Vector3(2.0, 2.0, 2.0)
		mesh.mesh = box

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = color
	var outline := ShaderMaterial.new()
	outline.shader = _outline_shader
	outline.set_shader_parameter("outline_width", 0.2)
	outline.set_shader_parameter("outline_color", Color(0.05, 0.05, 0.05, 1))
	mat.next_pass = outline
	mesh.material_override = mat
	return mesh

#endregion


# ---------------------------------------------------------------------------
#region Occupant hover
# ---------------------------------------------------------------------------

## Screen-space proximity rather than a physics raycast — close-up
## occupants (real models or fallback primitives) don't carry collision
## shapes of their own, and it's at most a handful of them at once.
func _update_hover(local_pos: Vector2) -> void:
	var nearest_id := ""
	var nearest_dist := OCCUPANT_HOVER_PIXEL_RADIUS
	for entity_id in _close_up_nodes.keys():
		var node: Node3D = _close_up_nodes[entity_id]
		if not is_instance_valid(node):
			continue
		var screen_pos: Vector2 = _cam.unproject_position(node.global_position)
		var dist: float = screen_pos.distance_to(local_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_id = entity_id
	_update_occupant_hover_id(nearest_id)


func _update_occupant_hover_id(entity_id: String) -> void:
	if entity_id == _hovered_occupant_id:
		return
	_hovered_occupant_id = entity_id
	occupant_hover_changed.emit(entity_id)

#endregion