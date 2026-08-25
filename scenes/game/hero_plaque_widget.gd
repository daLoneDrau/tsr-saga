# hero_plaque_widget.gd
# Restrained "current hero" plaque — rune + name — shown briefly after the
# turn widget fades, then faded away itself. Same role/lifecycle as
# turn_widget.gd (GameScene controls exactly when it shows/hides), just a
# second beat in the same turn-intro sequence rather than a separate one.
#
# HERO_RUNES is presentation-only content (a display glyph per hero), not
# game data — kept here rather than in HeroKindTable for that reason.
#
# FONT RISK: the rune glyphs below are real Unicode runic characters
# (U+16xx block), not stylized Latin letters. Whether NorseBold-2Kge.otf
# actually contains glyphs for that Unicode block is unverified — if it
# doesn't, Godot will render tofu boxes (or silently fall back to a system
# font, which could look inconsistent) instead of the runes. Worth
# checking in the editor before treating this as done; a dedicated runic
# Unicode font may be needed if NorseBold doesn't cover it.

class_name HeroPlaqueWidget
extends Control

const HERO_RUNES: Dictionary = {
	HeroKindTable.BEOWULF:   "ᛒ",
	HeroKindTable.BRUNHILD:  "ᚦ",
	HeroKindTable.EGIL:      "ᛖ",
	HeroKindTable.RAGNAR:    "ᚱ",
	HeroKindTable.SIEGFRIED: "ᛋ",
	HeroKindTable.STARKAD:   "ᛏ",
	}

@onready var _rune_label: Label = %RuneLabel
@onready var _name_label: Label = %HeroNameLabel


func set_hero(kind_id: int) -> void:
	var hero_data: Dictionary = HeroKindTable.get_hero(kind_id)
	_name_label.text = String(hero_data.get("name", "")).to_upper()
	_rune_label.text = HERO_RUNES.get(kind_id, "?")


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
