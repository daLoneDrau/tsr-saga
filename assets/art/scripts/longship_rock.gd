extends MeshInstance3D

@export var amplitude_degrees: float = 2.5
@export var period: float = 3.5

var _time: float = 0.0

func _process(delta: float) -> void:
	_time += delta
	var angle = sin((_time / period) * TAU) * deg_to_rad(amplitude_degrees)
	rotation.z = angle