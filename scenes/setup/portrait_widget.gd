# portrait_widget.gd
# Controller for PortraitWidget.tscn — a self-contained hero portrait rig.
# Root node IS the SubViewport, so this scene can be instanced directly as
# the child of a SubViewportContainer with no extra wrapping.
#
# Responsibilities:
#   - Load a hero's full-body model and parent it under `characterMark`,
#     the anchor node positioned/rotated for the isometric camera rig.
#   - Apply the chosen skin/hair/(optional) stubble materials to the
#     hero's single MeshInstance3D via surface material overrides.
#   - Own the mesh-walking and surface-slot logic so callers (e.g.
#     SetupScene) never need to know how a hero model is structured.
#
# Surface slot convention (glTF material order, consistent across heroes):
#   0 = skin, 1 = hair, ..., stubble (Starkad only) = last surface index.

class_name PortraitWidget
extends SubViewport


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Animation clip name baked into every hero glTF export.
const IDLE_ANIM_NAME: String = "idle"


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var _character_mark: Node3D = $characterMark


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

# Holds the currently instanced hero model so it can be removed on swap.
# Null when no hero is loaded.
var _hero_instance: Node3D = null


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Load the hero model at `model_path`, parent it under `characterMark`, and
## apply the given palette. Pass an empty `stubble_path` for heroes with no
## stubble surface (i.e. everyone except Starkad).
func show_hero(model_path: String, skin_path: String, hair_path: String, stubble_path: String = "") -> void:
	clear_hero()

	var packed: PackedScene = load(model_path) as PackedScene
	if packed == null:
		push_error("PortraitWidget: could not load hero model at %s" % model_path)
		return

	_hero_instance = packed.instantiate() as Node3D
	if _hero_instance == null:
		push_error("PortraitWidget: hero scene root is not Node3D at %s" % model_path)
		return

	# characterMark already carries the position/rotation the camera rig
	# expects — the hero model sits at its local origin.
	_hero_instance.position = Vector3.ZERO
	_hero_instance.rotation = Vector3.ZERO

	_character_mark.add_child(_hero_instance)
	_apply_palette(skin_path, hair_path, stubble_path)
	_play_idle(_hero_instance)

	# Force a fresh frame now that materials/geometry have changed.
	render_target_update_mode = SubViewport.UPDATE_ALWAYS


## Remove the current hero instance, if any.
func clear_hero() -> void:
	if _hero_instance != null and is_instance_valid(_hero_instance):
		_hero_instance.queue_free()
	_hero_instance = null


# ---------------------------------------------------------------------------
# Internal — palette application
# ---------------------------------------------------------------------------

func _apply_palette(skin_path: String, hair_path: String, stubble_path: String) -> void:
	var mesh_node: MeshInstance3D = _find_mesh(_hero_instance)
	if mesh_node == null:
		push_error("PortraitWidget: no MeshInstance3D found in hero instance")
		return

	var skin_mat: StandardMaterial3D = load(skin_path) as StandardMaterial3D
	if skin_mat == null:
		push_error("PortraitWidget: could not load skin material at %s" % skin_path)
	else:
		mesh_node.set_surface_override_material(0, skin_mat)

	var hair_mat: StandardMaterial3D = load(hair_path) as StandardMaterial3D
	if hair_mat == null:
		push_error("PortraitWidget: could not load hair material at %s" % hair_path)
	else:
		mesh_node.set_surface_override_material(1, hair_mat)

	if stubble_path.is_empty():
		return

	var stubble_mat: StandardMaterial3D = load(stubble_path) as StandardMaterial3D
	if stubble_mat == null:
		push_error("PortraitWidget: could not load stubble material at %s" % stubble_path)
		return

	# Stubble only exists on Starkad's model, and only as the LAST surface —
	# never hardcode its index, since every other hero's mesh doesn't have it.
	var mesh: Mesh = mesh_node.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		push_error("PortraitWidget: hero mesh has no surfaces to apply stubble to")
		return
	var last_idx: int = mesh.get_surface_count() - 1
	mesh_node.set_surface_override_material(last_idx, stubble_mat)


## Recursively find the first MeshInstance3D in the subtree.
func _find_mesh(node: Node) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var result: MeshInstance3D = _find_mesh(child)
		if result != null:
			return result
	return null


# ---------------------------------------------------------------------------
# Internal — idle animation
# ---------------------------------------------------------------------------

## Find the hero's AnimationPlayer, force its idle clip to loop, and play it.
## Every hero glTF is exported with an "idle" clip, but the importer doesn't
## set it to loop by default — that's forced here rather than relying on
## per-asset import settings that could drift between heroes.
func _play_idle(hero_root: Node3D) -> void:
	var anim_player: AnimationPlayer = _find_animation_player(hero_root)
	if anim_player == null:
		push_error("PortraitWidget: no AnimationPlayer found in hero instance")
		return

	if not anim_player.has_animation(IDLE_ANIM_NAME):
		push_error("PortraitWidget: hero has no '%s' animation" % IDLE_ANIM_NAME)
		return

	var idle_anim: Animation = anim_player.get_animation(IDLE_ANIM_NAME)
	idle_anim.loop_mode = Animation.LOOP_LINEAR

	anim_player.play(IDLE_ANIM_NAME)


## Recursively find the first AnimationPlayer in the subtree.
func _find_animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result: AnimationPlayer = _find_animation_player(child)
		if result != null:
			return result
	return null
