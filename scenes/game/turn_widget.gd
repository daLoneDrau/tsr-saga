# turn_widget.gd
# Restrained "TURN X OF 20" indicator shown briefly at the top of the
# screen at the start of a turn, then faded away. Not a persistent HUD
# element — GameScene controls exactly when it shows/hides as part of the
# turn-start beat sequence (see GameScene._play_turn_intro_sequence()).
#
# Deliberately simple: a parchment-toned badge with a plain border, no
# ornamentation, no animation beyond the fade — this is meant to read as
# a quiet status readout, not a fanfare moment.

class_name TurnWidget
extends Control

@onready var _turn_label: Label = %TurnLabel


func set_turn(current_turn: int, max_turns: int) -> void:
	_turn_label.text = "TURN %d OF %d" % [current_turn, max_turns]


func show_widget() -> void:
	modulate.a = 1.0
	visible = true


func fade_out(duration: float = 0.6) -> void:
	if not visible:
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished
	visible = false
