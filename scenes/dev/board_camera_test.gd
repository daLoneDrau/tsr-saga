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
# Controls at runtime (Play this scene directly, F6):
#   Left / Right arrow   — adjust yaw
#   Up / Down arrow      — adjust pitch (elevation from horizontal)
#   , / .                — adjust margin / breathing-space fraction
#   [ / ]                — adjust FOV (perspective mode only)
#   P                     — toggle Perspective <-> Orthographic
#   R                     — reset to defaults
# Values (including solved camera distance/size) are shown on-screen, so
# you can copy the final numbers into a real scene once you're happy.
#
# Defaults: Orthographic, yaw=0°, pitch=35°, margin=0%.
# Margin at 0% means the board's AABB corners touch the frame edge with
# no slack — useful as a "how tight can this get" baseline, but the
# spec's "narrow breathing space" requirement wants a small nonzero
# value before this is final in either projection mode.

extends Node3D
class_name BoardCameraTest

const VIEWPORT_SIZE := Vector2(640.0, 480.0)
const RIG_BACK_DISTANCE := 200.0  # orthographic only; ortho ignores distance for scale
const YAW_DEFAULT := 0.0
const PITCH_DEFAULT := 35.0
const MARGIN_DEFAULT := 0.0  # 0% — see header note on breathing space
const FOV_DEFAULT := 30.0
const USE_PERSPECTIVE_DEFAULT := false

@export_range(-180.0, 180.0, 0.5) var yaw_degrees: float = YAW_DEFAULT
@export_range(10.0, 85.0, 0.5) var pitch_degrees: float = PITCH_DEFAULT
@export_range(0.0, 0.25, 0.005) var margin_fraction: float = MARGIN_DEFAULT
@export_range(15.0, 60.0, 0.5) var fov_degrees: float = FOV_DEFAULT
@export var use_perspective: bool = USE_PERSPECTIVE_DEFAULT

@onready var _yaw_pivot: Node3D = $YawPivot
@onready var _pitch_pivot: Node3D = $YawPivot/PitchPivot
@onready var _camera: Camera3D = $YawPivot/PitchPivot/Camera3D
@onready var _board_root: Node3D = $BoardRoot
@onready var _readout: Label = $CanvasLayer/Readout

var _board_aabb: AABB
var _board_center: Vector3


func _ready() -> void:
	_camera.current = true
	_board_aabb = _compute_board_aabb(_board_root)
	_board_center = _board_aabb.position + _board_aabb.size / 2.0
	if _board_aabb.size == Vector3.ZERO:
		push_warning("BoardCameraTest: board AABB came back empty — check BoardRoot has the saga_map instance with visible MeshInstance3D children.")
	_hide_region_borders()
	_apply_rig()


## Hides the white grid overlay from Region_Borders — reads cleanly in
## the close-up view but is visual noise at full Board Overview scale.
## Deliberately done AFTER _compute_board_aabb() runs, not before: hiding
## it first would make get_aabb() calls on it return zero/skip it (mesh
## visibility affects AABB queries in some Godot versions), and this
## mesh may legitimately be part of what defines the board's true edge
## extent. Hiding only affects rendering, not the framing math.
func _hide_region_borders() -> void:
	var borders := _board_root.find_child("Region_Borders_Thin", true, false)
	if borders and borders is MeshInstance3D:
		(borders as MeshInstance3D).visible = false
	elif not borders:
		push_warning("BoardCameraTest: no 'Region_Borders_Thin' node found under BoardRoot — check the exact node name in saga_map.glb.")


func _process(delta: float) -> void:
	var changed := false
	var yaw_speed := 30.0 * delta
	var pitch_speed := 20.0 * delta
	var margin_speed := 0.05 * delta
	var fov_speed := 15.0 * delta

	if Input.is_key_pressed(KEY_LEFT):
		yaw_degrees -= yaw_speed
		changed = true
	if Input.is_key_pressed(KEY_RIGHT):
		yaw_degrees += yaw_speed
		changed = true
	if Input.is_key_pressed(KEY_UP):
		pitch_degrees = clampf(pitch_degrees + pitch_speed, 10.0, 85.0)
		changed = true
	if Input.is_key_pressed(KEY_DOWN):
		pitch_degrees = clampf(pitch_degrees - pitch_speed, 10.0, 85.0)
		changed = true
	if Input.is_key_pressed(KEY_PERIOD):
		margin_fraction = clampf(margin_fraction + margin_speed, 0.0, 0.25)
		changed = true
	if Input.is_key_pressed(KEY_COMMA):
		margin_fraction = clampf(margin_fraction - margin_speed, 0.0, 0.25)
		changed = true
	if Input.is_key_pressed(KEY_BRACKETRIGHT):
		fov_degrees = clampf(fov_degrees + fov_speed, 15.0, 60.0)
		changed = true
	if Input.is_key_pressed(KEY_BRACKETLEFT):
		fov_degrees = clampf(fov_degrees - fov_speed, 15.0, 60.0)
		changed = true
	if Input.is_key_pressed(KEY_R):
		if not _r_held:
			yaw_degrees = YAW_DEFAULT
			pitch_degrees = PITCH_DEFAULT
			margin_fraction = MARGIN_DEFAULT
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

	if changed:
		_apply_rig()

var _p_held := false
var _r_held := false


func _apply_rig() -> void:
	if _board_aabb.size == Vector3.ZERO:
		return

	_yaw_pivot.global_position = _board_center
	_yaw_pivot.rotation = Vector3.ZERO
	_yaw_pivot.rotate_y(deg_to_rad(yaw_degrees))

	_pitch_pivot.rotation = Vector3.ZERO
	_pitch_pivot.rotate_x(deg_to_rad(-pitch_degrees))

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

	_update_readout()


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
	fitted_size *= (1.0 + margin_fraction)

	_camera.size = fitted_size
	_camera.near = 0.1
	_camera.far = RIG_BACK_DISTANCE + _board_aabb.size.length() + 50.0


func _apply_perspective(right: Vector3, up: Vector3, view: Vector3, aspect: float) -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = fov_degrees
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT

	var half_v: float = deg_to_rad(fov_degrees) / 2.0
	var half_h: float = atan(tan(half_v) * aspect)
	var margin_scale: float = 1.0 + margin_fraction

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

	_last_perspective_distance = distance


var _last_perspective_distance: float = 0.0


func _update_readout() -> void:
	if not _readout:
		return
	var mode_str := "PERSPECTIVE" if use_perspective else "ORTHOGRAPHIC"
	var extra_line := ""
	if use_perspective:
		extra_line = "fov=%.1f°  solved distance=%.3f" % [fov_degrees, _last_perspective_distance]
	else:
		extra_line = "fitted Camera3D.size=%.4f" % _camera.size

	_readout.text = "[%s]  yaw=%.1f°  pitch=%.1f°  margin=%.0f%%\n%s\nboard AABB size=(%.2f, %.2f, %.2f)\nboard center=(%.2f, %.2f, %.2f)\n[arrows: yaw/pitch] [, . : margin] [ [ ] : fov] [P: toggle proj] [R: reset]" % [
		mode_str, yaw_degrees, pitch_degrees, margin_fraction * 100.0,
		extra_line,
		_board_aabb.size.x, _board_aabb.size.y, _board_aabb.size.z,
		_board_center.x, _board_center.y, _board_center.z,
		]


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


func _find_mesh_instances(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_mesh_instances(child))
	return found