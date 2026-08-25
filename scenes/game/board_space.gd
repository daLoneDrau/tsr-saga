# board_space.gd
# Board rendering foundation for the rebuilt GameScene — replaces
# map_preview.gd's role as of the board/camera-first redesign pass.
#
# Deliberately minimal for this pass: just the board mesh + the locked
# Board Overview camera (yaw 0°, pitch 45°, margin 1%, orthographic).
# No click handling, no occupant markers, no Regional Focus reframe yet —
# those get layered back in as their own steps, same as they were built
# up individually in the board_camera_test.gd scratch scene that
# validated this framing against the real board mesh.
#
# NOT a preview/prototype widget — board_space.tscn is the actual
# production board rendering surface GameScene.tscn uses.
#
# Camera angle (yaw/pitch) is a locked design constant — pure trig, no
# mesh dependency, so it's safe as a fixed value. Pan position and zoom
# (Camera3D.size) are instead computed live from the board mesh's real
# AABB every time this scene loads, using the exact same fitting math
# validated in board_camera_test.gd, rather than baking in the specific
# numbers that math happened to produce for one measurement. This avoids
# a magic-number drift risk if the board mesh ever changes slightly —
# the framing self-corrects instead of silently going stale.

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
# Ported as-is from the validated scratch-scene behavior.
const REGION_BORDERS_NODE_NAME := "Region_Borders_Thin"

@onready var _board_root: Node3D = %BoardRoot
@onready var _yaw_pivot: Node3D = %IsoCameraRig
@onready var _pitch_pivot: Node3D = %PitchPivot
@onready var _camera: Camera3D = %Camera3D

var _board_aabb: AABB
var _board_center: Vector3


func _ready() -> void:
	_camera.current = true
	_board_aabb = _compute_board_aabb(_board_root)
	if _board_aabb.size == Vector3.ZERO:
		push_warning("BoardSpace: board AABB came back empty — check BoardRoot has the saga_map instance with visible MeshInstance3D children.")
		return
	_board_center = _board_aabb.position + _board_aabb.size / 2.0

	_hide_region_borders()
	_apply_overview_framing()


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
## math to board_camera_test.gd's _apply_orthographic(), just without the
## perspective-comparison branch this production version doesn't need.
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
