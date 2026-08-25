# top_banner.gd
# Persistent top-of-screen banner combining what were previously two
# separate toast widgets (TurnWidget, HeroPlaqueWidget) into one fixture:
# turn info on the right, current hero (rune + name) on the left. The
# banner frame itself is a constant, persistent HUD element — it does NOT
# fade in or out. Only its two content halves stage in independently
# (reveal_turn() then, after a pause, reveal_hero()), via each side's own
# modulate.a rather than the whole banner's visibility.
#
# GameScene still owns exactly when each side reveals — see
# GameScene._play_turn_intro_sequence()/_announce_current_hero().
#
# HERO_RUNES is presentation-only content (a display glyph per hero), not
# game data — kept here rather than in HeroKindTable for that reason.
# Same font-coverage risk as before: the rune glyphs are real Unicode
# runic characters (U+16xx block); whether the assigned font actually
# contains glyphs for that block is unverified from here.

class_name TopBanner
extends Control

const HERO_RUNES: Dictionary = {
	HeroKindTable.BEOWULF:   "ᛒ",
	HeroKindTable.BRUNHILD:  "ᚦ",
	HeroKindTable.EGIL:      "ᛖ",
	HeroKindTable.RAGNAR:    "ᚱ",
	HeroKindTable.SIEGFRIED: "ᛋ",
	HeroKindTable.STARKAD:   "ᛏ",
}

@onready var _hero_side: Control = %HeroSide
@onready var _turn_label: Label = %TurnLabel
@onready var _rune_label: Label = %RuneLabel
@onready var _hero_name_label: Label = %HeroNameLabel


func _ready() -> void:
	# Frame is always visible; content starts hidden until GameScene
	# reveals each side in sequence.
	_hero_side.modulate.a = 0.0
	_turn_label.modulate.a = 0.0


func set_turn(current_turn: int, max_turns: int) -> void:
	_turn_label.text = "TURN %d OF %d" % [current_turn, max_turns]


func set_hero(kind_id: int) -> void:
	var hero_data: Dictionary = HeroKindTable.get_hero(kind_id)
	_hero_name_label.text = String(hero_data.get("name", "")).to_upper()
	_rune_label.text = HERO_RUNES.get(kind_id, "?")


func reveal_turn() -> void:
	_turn_label.modulate.a = 1.0


func reveal_hero() -> void:
	_hero_side.modulate.a = 1.0
