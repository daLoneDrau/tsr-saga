# bottom_banner.gd
# Bottom-of-screen banner, same background/frame chrome as TopBanner
# (frame_80_pixelated.png + parchment_frame.png), but a different content
# lifecycle: rather than two permanent halves, it has one transient
# announcement (the current phase, e.g. "MOVEMENT PHASE" — fades in, holds,
# fades out) followed by persistent controls (helper text + action button,
# revealed instantly once the phase announcement is done). PhaseLabel and
# ContentRow occupy the same slot (ContentStack), not sequential rows —
# only one is ever meaningfully visible at a time.
#
# GameScene owns the sequencing — see
# GameScene._play_movement_phase_intro().

class_name BottomBanner
extends Control

signal finish_movement_pressed

@onready var _phase_label: Label = %PhaseLabel
@onready var _content_row: Control = %ContentRow
@onready var _helper_label: Label = %HelperLabel
@onready var _finish_button: Button = %FinishMovementButton


func _ready() -> void:
	_phase_label.modulate.a = 0.0
	_content_row.modulate.a = 0.0
	_finish_button.pressed.connect(_on_finish_pressed)


func set_phase_text(text: String) -> void:
	_phase_label.text = text


func fade_in_phase(duration: float = 0.6) -> void:
	var tween := create_tween()
	tween.tween_property(_phase_label, "modulate:a", 1.0, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished


func fade_out_phase(duration: float = 0.6) -> void:
	var tween := create_tween()
	tween.tween_property(_phase_label, "modulate:a", 0.0, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished


func set_helper_text(text: String) -> void:
	_helper_label.text = text


## Instant, not a fade — matches the spec's "instantly reveal" for the
## helper text + button, as opposed to the phase label's fade in/out.
func reveal_controls() -> void:
	_content_row.modulate.a = 1.0


func _on_finish_pressed() -> void:
	finish_movement_pressed.emit()
