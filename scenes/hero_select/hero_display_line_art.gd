# hero_display_line_art.gd
# Prototype A representation of a single hero slot in the Hero Selection
# gallery (spec 1.4, candidate 1): reconstructed 1981-style line art.
#
# Implements the HeroDisplaySlot contract that hero_select_scene.gd talks to.
# Any future representation (e.g. a 3D-model slot wrapping PortraitWidget)
# only needs to implement these same three methods with the same signatures
# for the gallery/browsing/transition logic to keep working unmodified.
#
# Contract:
#   assign(kind_id, skin_path, hair_path, stubble_path) -> void
#   clear() -> void
#   set_focused(is_focused: bool) -> void
#
# NOTE — known asset gap (see README): the only art that exists per hero is
# a single flat line-art PNG (assets/modeling/heroes/<name>/<name>_line_art.png).
# There are no separate skin/hair mask layers to recolor, so this prototype
# currently displays the line art as-is and does NOT visually apply the
# rolled skin/hair palette (skin_path/hair_path are accepted and stored for
# forward-compatibility but unused below). Spec 1.10 requires real per-hero
# recoloring once colorable art exists.

class_name HeroDisplayLineArt
extends TextureRect


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const LINE_ART_DIR: String = "res://assets/modeling/heroes/"

# Hero kind_id -> folder/file slug under LINE_ART_DIR.
# Mirrors HeroKindTable's declared order/spelling.
const SLUG_BY_KIND: Dictionary = {
	0: "beowulf",   # HeroKindTable.BEOWULF
	1: "egil",      # HeroKindTable.EGIL
	2: "brunhild",  # HeroKindTable.BRUNHILD
	3: "siegfried", # HeroKindTable.SIEGFRIED
	4: "starkad",   # HeroKindTable.STARKAD
	5: "ragnar",    # HeroKindTable.RAGNAR
}

# Focused-scale slot target height in px (spec 1.25: ~265-275 max).
const FOCUSED_HEIGHT: float = 270.0

# Adjacent (prev/next) slot scale relative to focused (spec 1.25: ~65-70%).
const SIDE_SCALE_FACTOR: float = 0.68


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _kind_id: int = -1

# Emitted when the player clicks this slot (used for adjacent-hero click
# navigation per spec 1.12). Not emitted for the focused slot.
signal slot_clicked(kind_id: int)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


# ---------------------------------------------------------------------------
# HeroDisplaySlot contract
# ---------------------------------------------------------------------------

## Loads and displays the given hero's line art. skin_path/hair_path/
## stubble_path are accepted for contract parity with the 3D representation
## but are currently unused — see the file-level note above.
func assign(kind_id: int, _skin_path: String, _hair_path: String, _stubble_path: String = "") -> void:
	_kind_id = kind_id

	var slug: String = SLUG_BY_KIND.get(kind_id, "")
	if slug.is_empty():
		push_error("HeroDisplayLineArt: unknown kind_id %d" % kind_id)
		clear()
		return

	var path := "%s%s/%s_line_art.png" % [LINE_ART_DIR, slug, slug]
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		push_error("HeroDisplayLineArt: could not load %s" % path)
		clear()
		return

	texture = tex
	visible = true


## Clears the slot back to empty (no hero shown).
func clear() -> void:
	_kind_id = -1
	texture = null
	visible = false


## Applies the focused vs. adjacent visual treatment (spec 1.15, 1.30).
## Scale is driven here; position is owned by the gallery zone container.
## Focus cue is restrained: a slight brightness lift, no frame/box.
func set_focused(is_focused: bool) -> void:
	var target_scale: float = 1.0 if is_focused else SIDE_SCALE_FACTOR
	scale = Vector2(target_scale, target_scale)
	modulate = Color(1, 1, 1, 1) if is_focused else Color(0.82, 0.82, 0.82, 1.0)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			slot_clicked.emit(_kind_id)


## Restrained hover emphasis for adjacent heroes (spec 1.30: hover increases
## emphasis without changing scale, never reads as fully selected).
func _on_mouse_entered() -> void:
	if scale.x < 1.0:  # only for non-focused slots
		modulate = Color(0.95, 0.95, 0.95, 1.0)


func _on_mouse_exited() -> void:
	if scale.x < 1.0:
		modulate = Color(0.82, 0.82, 0.82, 1.0)