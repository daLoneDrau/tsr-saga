extends MeshInstance3D

@export var steps: int = 3
@export var amplitude: float = 0.08
@export var period: float = 3.6

var _time: float = 0.0

func _process(delta: float) -> void:
	_time += delta
	var t = fmod(_time, period * 2.0) / (period * 2.0)
	if t > 0.5:
		t = 1.0 - t
	t = t * 2.0
	var stepped = floor(t * steps) / steps
	position.y = _base_y + stepped * amplitude

var _base_y: float

func _ready() -> void:
	_base_y = position.y