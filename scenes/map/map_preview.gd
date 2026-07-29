extends Node3D
## SAGA Map Viewer — sample display scene.
##
## Setup (in the Godot editor):
##   1. Create a new 3D Scene (Node3D root).
##   2. Drag your imported .glb into the scene tree as a child of the root.
##   3. Rename that child node to exactly "Map".
##   4. Attach this script to the ROOT node (not the Map child).
##   5. Run the scene (F6).
##
## This script auto-detects the map's actual size via its combined visual
## bounding box, so it isn't dependent on hardcoded map dimensions — if you
## regenerate/re-export the map later with a different footprint, this
## still frames it correctly with no changes needed here.

@export var camera_distance_padding: float = 1.25  # headroom multiplier around the framed area
@export var sun_energy: float = 1.2
@export var ambient_energy: float = 0.35

@export_group("Camera Framing")
@export var map_cells_x: int = 88   # total cell columns across the whole map
@export var map_cells_y: int = 64   # total cell rows across the whole map
@export var view_cells: int = 15    # how many cells (in each direction) the camera should cover


func _ready() -> void:
	var map_node := get_node_or_null("Map")
	if map_node == null:
		push_error("SAGA Map Viewer: no child named 'Map' found. Drag your imported .glb into the scene as a child named 'Map'.")
		return

	var bounds := _get_combined_aabb(map_node)
	if bounds.size == Vector3.ZERO:
		push_error("SAGA Map Viewer: couldn't find any visible mesh geometry under 'Map'.")
		return

	_setup_lighting()
	_setup_camera(bounds.get_center(), bounds.size)


func _get_combined_aabb(node: Node) -> AABB:
	var result := AABB()
	var has_result := false

	for child in node.get_children():
		if child is VisualInstance3D:
			var child_aabb: AABB = (child as VisualInstance3D).get_aabb()
			var world_aabb: AABB = child.global_transform * child_aabb
			if not has_result:
				result = world_aabb
				has_result = true
			else:
				result = result.merge(world_aabb)

		if child.get_child_count() > 0:
			var sub_aabb := _get_combined_aabb(child)
			if sub_aabb.size != Vector3.ZERO:
				if not has_result:
					result = sub_aabb
					has_result = true
				else:
					result = result.merge(sub_aabb)

	return result


func _setup_lighting() -> void:
	if get_node_or_null("Sun") == null:
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation_degrees = Vector3(-50, -35, 0)
		sun.light_energy = sun_energy
		sun.shadow_enabled = true
		add_child(sun)

	if get_node_or_null("Env") == null:
		var env_node := WorldEnvironment.new()
		env_node.name = "Env"
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("6c8fd6")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(1, 1, 1)
		env.ambient_light_energy = ambient_energy
		env_node.environment = env
		add_child(env_node)


func _setup_camera(center: Vector3, extents: Vector3) -> void:
	var rig := get_node_or_null("IsoCameraRig") as Node3D
	if rig == null:
		rig = Node3D.new()
		rig.name = "IsoCameraRig"
		add_child(rig)

	rig.position = center
	rig.rotation_degrees = Vector3(0, 45, 0)

	var pitch_pivot := rig.get_node_or_null("PitchPivot") as Node3D
	if pitch_pivot == null:
		pitch_pivot = Node3D.new()
		pitch_pivot.name = "PitchPivot"
		rig.add_child(pitch_pivot)

	pitch_pivot.position = Vector3.ZERO
	pitch_pivot.rotation_degrees = Vector3(-35.264, 0, 0)

	var cam := pitch_pivot.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		cam = Camera3D.new()
		cam.name = "Camera3D"
		pitch_pivot.add_child(cam)

	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# No rotation needed on the camera itself — its orientation is fully
	# determined by the rig's yaw + pivot's pitch above it, and since its
	# position offset below is along the SAME local Z axis, it automatically
	# looks back at the pivot origin regardless of distance.
	cam.rotation_degrees = Vector3.ZERO

	# Cell size derived from the map's actual world extents / known cell
	# counts, so the framed area stays correct even if the map's physical
	# size changes later.
	var cell_size_x: float = extents.x / map_cells_x
	var cell_size_z: float = extents.z / map_cells_y
	var view_width: float = view_cells * cell_size_x
	var view_depth: float = view_cells * cell_size_z

	var diagonal: float = extents.length()
	cam.size = max(view_width, view_depth) * camera_distance_padding
	cam.near = 0.05
	cam.far = diagonal * 4.0
	cam.position = Vector3(0, 0, diagonal * 1.5)
	cam.current = true