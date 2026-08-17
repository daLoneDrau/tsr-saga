# hero_select_scene.gd
# Controller for the Hero Selection screen — PROTOTYPE A (line art + blue
# field, spec 1.4/1.16/1.33). Registered as the root script on
# HeroSelectScene.tscn.
#
# STANDALONE REVIEW BUILD: this scene currently runs independently of
# SetupScene/SagaSetupSystem so it can be opened and critiqued on its own in
# the Godot editor. It registers no GameSystems and never calls
# SagaSetupSystem.run() — confirming a hero just prints a debug summary and
# emits hero_confirmed(). Wiring into the real setup flow is a deliberately
# separate follow-up step once this screen's UX is approved.
#
# Responsibilities:
#   - Roll a fixed skin/hair/stubble palette for every hero once per screen
#     load (spec 1.10/1.11) — ported from SetupScene._roll_palette().
#   - Own the focused-gallery browsing state (spec 1.3, 1.8, 1.9, 1.12).
#   - Drive the three HeroDisplaySlot instances (prev/focus/next) without
#     knowing which representation they use (line art here; a 3D-model slot
#     would satisfy the same contract — see hero_display_line_art.gd).
#   - Handle SELECT HERO / BACK confirmation (spec 1.6, 1.7, 1.21).
#
# Node references are resolved once in _ready() via unique-name shortcuts
# (%NodeName), matching TitleScene/SetupScene convention.

class_name HeroSelectScene
extends Scene


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when SELECT HERO is activated. Payload mirrors the four values
## SagaSetupSystem.run() will eventually need (kind_id, skin, hair, stubble).
signal hero_confirmed(kind_id: int, skin_path: String, hair_path: String, stubble_path: String)

## Emitted when BACK is activated. No payload — the eventual host flow
## decides what "back" means once this screen is wired into it.
signal back_requested


# ---------------------------------------------------------------------------
# Roster — canonical order per HeroKindTable's declared order (spec 1.9).
# ---------------------------------------------------------------------------

const ROSTER_KIND_IDS: Array[int] = [
	HeroKindTable.BEOWULF,
	HeroKindTable.EGIL,
	HeroKindTable.BRUNHILD,
	HeroKindTable.SIEGFRIED,
	HeroKindTable.STARKAD,
	HeroKindTable.RAGNAR,
	]


# ---------------------------------------------------------------------------
# Palette pools — ported verbatim from SetupScene.gd so both screens roll
# from the same source of truth. If SetupScene's pools ever change, update
# both until this prototype graduates into the real flow.
# ---------------------------------------------------------------------------

const SKIN_MATERIAL_PATHS: Array[String] = [
	"res://assets/art/materials/heroes/skin/fair_rosy.tres",
	"res://assets/art/materials/heroes/skin/light_tan.tres",
	"res://assets/art/materials/heroes/skin/florid.tres",
	"res://assets/art/materials/heroes/skin/olive.tres",
	]
const HAIR_MATERIAL_PATHS: Array[String] = [
	"res://assets/art/materials/heroes/hair/blonde.tres",
	"res://assets/art/materials/heroes/hair/auburn.tres",
	"res://assets/art/materials/heroes/hair/red.tres",
	"res://assets/art/materials/heroes/hair/black.tres",
	"res://assets/art/materials/heroes/hair/platinum.tres",
	]
const HAIR_MATERIAL_PATHS_OLIVE: Array[String] = [
	"res://assets/art/materials/heroes/hair/auburn.tres",
	"res://assets/art/materials/heroes/hair/black.tres",
	]
const STUBBLE_BY_HAIR: Dictionary = {
	"res://assets/art/materials/heroes/hair/blonde.tres": "res://assets/art/materials/heroes/stubble/stubble_blonde.tres",
	"res://assets/art/materials/heroes/hair/auburn.tres": "res://assets/art/materials/heroes/stubble/stubble_auburn.tres",
	"res://assets/art/materials/heroes/hair/red.tres": "res://assets/art/materials/heroes/stubble/stubble_red.tres",
	"res://assets/art/materials/heroes/hair/black.tres": "res://assets/art/materials/heroes/stubble/stubble_black.tres",
	"res://assets/art/materials/heroes/hair/platinum.tres": "res://assets/art/materials/heroes/stubble/stubble_platinum.tres",
	}


# ---------------------------------------------------------------------------
# Layout constants — spec 1.23/1.24/1.29 pixel-region allocation at 640x480.
# ---------------------------------------------------------------------------

const SCREEN_SIZE: Vector2 = Vector2(640, 480)

const HEADER_TOP: float = 0.0
const HEADER_HEIGHT: float = 56.0

const GALLERY_TOP: float = 56.0
const GALLERY_HEIGHT: float = 295.0
const GALLERY_PREV_WIDTH: float = 150.0
const GALLERY_FOCUS_WIDTH: float = 340.0
const GALLERY_NEXT_WIDTH: float = 150.0

const IDENTITY_TOP: float = 351.0
const IDENTITY_HEIGHT: float = 45.0

const ACTION_TOP: float = 396.0
const ACTION_HEIGHT: float = 52.0

const PERIPHERAL_TOP: float = 448.0
const PERIPHERAL_HEIGHT: float = 32.0

const GROUND_LINE_Y: float = GALLERY_TOP + GALLERY_HEIGHT - 25.0  # margin above Identity band

const ARROW_PREV_CENTER_X: float = 30.0
const ARROW_NEXT_CENTER_X: float = 610.0

const TRANSITION_SECONDS: float = 0.16
const TRANSITION_TRAVEL_PX: float = 26.0

# --- Ornament placeholder sizing (spec revision: assets 1-4) ---------------
# These are provisional guesses at footprint only, so the placeholders sit
# in roughly the right place and don't overlap functional controls. Real
# dimensions come from the art once it exists — nothing here should be
# treated as final.
const NAME_ORNAMENT_SIZE: Vector2 = Vector2(22, 22)   # "—◇—" terminal piece, each side
const NAME_ORNAMENT_GAP: float = 8.0                  # gap between ornament and name text
const FOCUS_CUE_SIZE: Vector2 = Vector2(40, 14)        # small mark at the focused hero's feet
const SELECT_BORDER_PADDING: float = 10.0              # border art overhangs the button a bit


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _focused_idx: int = 0

var _hero_skin_paths: Array[String] = []
var _hero_hair_paths: Array[String] = []
var _hero_stubble_paths: Array[String] = []

var _is_transitioning: bool = false


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var _title_label: Label = %TitleLabel
@onready var _prev_slot: HeroDisplayLineArt = %PrevSlot
@onready var _focus_slot: HeroDisplayLineArt = %FocusSlot
@onready var _next_slot: HeroDisplayLineArt = %NextSlot
@onready var _focus_cue: TextureRect = %FocusCue
@onready var _prev_arrow: Button = %PrevArrow
@onready var _next_arrow: Button = %NextArrow
@onready var _name_ornament_left: TextureRect = %NameOrnamentLeft
@onready var _hero_name_label: Label = %HeroNameLabel
@onready var _name_ornament_right: TextureRect = %NameOrnamentRight
@onready var _select_button: Button = %SelectHeroButton
@onready var _select_border: TextureRect = %SelectHeroBorder
@onready var _back_button: Button = %BackButton
@onready var _presentation_frame: TextureRect = %PresentationFrame


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_roll_palette()
	_apply_layout()
	_wire_input()
	_register_actions()
	_focused_idx = 0  # spec 1.9 — always opens on the first roster entry (Beowulf)
	_refresh_gallery()


func on_enter() -> void:
	_focused_idx = 0
	_refresh_gallery()


func on_exit() -> void:
	_unwire_input()


## Rolls an independent skin/hair/stubble combo for every hero, once per
## screen load. Highlighting a different hero afterward only looks up its
## already-rolled combo — nothing re-rolls (spec 1.10/1.11). Ported from
## SetupScene._roll_palette().
func _roll_palette() -> void:
	_hero_skin_paths = []
	_hero_hair_paths = []
	_hero_stubble_paths = []

	for i in ROSTER_KIND_IDS.size():
		var skin_path: String = SKIN_MATERIAL_PATHS[randi_range(0, SKIN_MATERIAL_PATHS.size() - 1)]

		var hair_pool: Array[String] = HAIR_MATERIAL_PATHS_OLIVE if skin_path == SKIN_MATERIAL_PATHS[3] else HAIR_MATERIAL_PATHS
		var hair_path: String = hair_pool[randi_range(0, hair_pool.size() - 1)]

		var stubble_path: String = STUBBLE_BY_HAIR.get(hair_path, "")

		_hero_skin_paths.append(skin_path)
		_hero_hair_paths.append(hair_path)
		_hero_stubble_paths.append(stubble_path)


# ---------------------------------------------------------------------------
#region Scene.do_action — required override
# ---------------------------------------------------------------------------

func do_action(action: GameAction) -> void:
	if not action.is_pressed():
		pass

	match action.name:
		"browse_prev":
			_navigate(-1)
		"browse_next":
			_navigate(1)
		"select_hero":
			_on_select_hero()
		"back":
			_on_back()
		"any_key":
			match action.phase:
				"END":
					var key_entry: String = OS.get_keycode_string(SagaGameEngine_auto.last_keycode)
					match key_entry:
						"Left", "Kp 4":
							_navigate(-1)
						"Right", "Kp 6":
							_navigate(1)
						"Enter", "Kp Enter", "Space":
							_on_select_hero()
						"Escape":
							_on_back()
						_:
							pass

#endregion


# ---------------------------------------------------------------------------
#region Input wiring
# ---------------------------------------------------------------------------

func _register_actions() -> void:
	register_action("any_key", "any_key")


func _wire_input() -> void:
	_prev_arrow.pressed.connect(do_action.bind(GameAction.new("browse_prev", GameAction.PHASE_END)))
	_next_arrow.pressed.connect(do_action.bind(GameAction.new("browse_next", GameAction.PHASE_END)))
	_select_button.pressed.connect(do_action.bind(GameAction.new("select_hero", GameAction.PHASE_END)))
	_back_button.pressed.connect(do_action.bind(GameAction.new("back", GameAction.PHASE_END)))
	_prev_slot.slot_clicked.connect(_on_adjacent_slot_clicked)
	_next_slot.slot_clicked.connect(_on_adjacent_slot_clicked)


func _unwire_input() -> void:
	if _prev_arrow.pressed.is_connected(do_action):
		_prev_arrow.pressed.disconnect(do_action)
	if _next_arrow.pressed.is_connected(do_action):
		_next_arrow.pressed.disconnect(do_action)
	if _select_button.pressed.is_connected(do_action):
		_select_button.pressed.disconnect(do_action)
	if _back_button.pressed.is_connected(do_action):
		_back_button.pressed.disconnect(do_action)
	if _prev_slot.slot_clicked.is_connected(_on_adjacent_slot_clicked):
		_prev_slot.slot_clicked.disconnect(_on_adjacent_slot_clicked)
	if _next_slot.slot_clicked.is_connected(_on_adjacent_slot_clicked):
		_next_slot.slot_clicked.disconnect(_on_adjacent_slot_clicked)


## Adjacent-hero click (spec 1.12) — bring the clicked slot into focus.
## Since the gallery only ever shows prev/focus/next, a click on either
## adjacent slot is always exactly one step away.
func _on_adjacent_slot_clicked(kind_id: int) -> void:
	var clicked_idx: int = ROSTER_KIND_IDS.find(kind_id)
	if clicked_idx == -1:
		return
	if clicked_idx == wrapi(_focused_idx - 1, 0, ROSTER_KIND_IDS.size()):
		_navigate(-1)
	elif clicked_idx == wrapi(_focused_idx + 1, 0, ROSTER_KIND_IDS.size()):
		_navigate(1)

#endregion


# ---------------------------------------------------------------------------
#region Browsing (spec 1.3, 1.8, 1.12, 1.17)
# ---------------------------------------------------------------------------

func _navigate(direction: int) -> void:
	if _is_transitioning:
		return  # browsing never confirms, and never queues mid-slide (spec 1.17)
	_focused_idx = wrapi(_focused_idx + direction, 0, ROSTER_KIND_IDS.size())
	_play_transition(direction)


func _refresh_gallery() -> void:
	var prev_idx: int = wrapi(_focused_idx - 1, 0, ROSTER_KIND_IDS.size())
	var next_idx: int = wrapi(_focused_idx + 1, 0, ROSTER_KIND_IDS.size())

	_assign_slot(_prev_slot, prev_idx, false)
	_assign_slot(_focus_slot, _focused_idx, true)
	_assign_slot(_next_slot, next_idx, false)

	var kind_id: int = ROSTER_KIND_IDS[_focused_idx]
	_hero_name_label.text = HeroKindTable.get_hero(kind_id)["name"].to_upper()


func _assign_slot(slot: HeroDisplayLineArt, idx: int, is_focused: bool) -> void:
	var kind_id: int = ROSTER_KIND_IDS[idx]
	slot.assign(kind_id, _hero_skin_paths[idx], _hero_hair_paths[idx], _hero_stubble_paths[idx])
	slot.set_focused(is_focused)


## Short, restrained crossfade + scale pulse in the direction of travel.
## This is a first-pass approximation of spec 1.17 — the first thing worth
## tuning once this is open in the editor is whether the slide should be a
## true cross-zone translation instead of this in-place pulse. Kept simple
## and correct here so the browsing/selection logic underneath is solid.
func _play_transition(direction: int) -> void:
	_is_transitioning = true

	var offset_x: float = TRANSITION_TRAVEL_PX * direction
	var slots: Array[HeroDisplayLineArt] = [_prev_slot, _focus_slot, _next_slot]

	var out_tween := create_tween()
	out_tween.set_parallel(true)
	for slot in slots:
		out_tween.tween_property(slot, "position:x", slot.position.x - offset_x, TRANSITION_SECONDS * 0.5)
		out_tween.tween_property(slot, "modulate:a", 0.0, TRANSITION_SECONDS * 0.5)

	out_tween.chain().tween_callback(_refresh_gallery)

	out_tween.chain().tween_callback(func() -> void:
		var in_tween := create_tween()
		in_tween.set_parallel(true)
		for slot in slots:
			slot.position.x += offset_x * 2.0
			in_tween.tween_property(slot, "position:x", slot.position.x - offset_x, TRANSITION_SECONDS * 0.5)
			in_tween.tween_property(slot, "modulate:a", 1.0, TRANSITION_SECONDS * 0.5)
		in_tween.chain().tween_callback(func() -> void: _is_transitioning = false)
	)

#endregion


# ---------------------------------------------------------------------------
#region Confirmation (spec 1.6, 1.7, 1.20, 1.21)
# ---------------------------------------------------------------------------

func _on_select_hero() -> void:
	if _is_transitioning:
		return

	var kind_id: int = ROSTER_KIND_IDS[_focused_idx]
	var skin_path: String = _hero_skin_paths[_focused_idx]
	var hair_path: String = _hero_hair_paths[_focused_idx]
	var stubble_path: String = _hero_stubble_paths[_focused_idx]

	# STANDALONE REVIEW BUILD — no SagaSetupSystem.run() call yet.
	# Region/sword remain unrevealed here per spec 1.20; this is intentional.
	print("HeroSelectScene: SELECT HERO -> %s (skin=%s, hair=%s, stubble=%s)" % [
		HeroKindTable.get_hero(kind_id)["name"], skin_path, hair_path, stubble_path
	])
	hero_confirmed.emit(kind_id, skin_path, hair_path, stubble_path)


func _on_back() -> void:
	# STANDALONE REVIEW BUILD — no prior scene to return to yet.
	print("HeroSelectScene: BACK pressed")
	back_requested.emit()

#endregion


# ---------------------------------------------------------------------------
#region Layout (spec 1.22-1.32) — computed here rather than baked into the
# .tscn so the whole pixel-region table lives in one place and is easy to
# re-tune during 640x480 testing (spec 1.15, 1.23).
# ---------------------------------------------------------------------------

func _apply_layout() -> void:
	custom_minimum_size = SCREEN_SIZE
	size = SCREEN_SIZE

	# Title
	_title_label.position = Vector2(0, HEADER_TOP)
	_title_label.size = Vector2(SCREEN_SIZE.x, HEADER_HEIGHT)

	# Gallery zones — prev / focus / next, continuous, no dividers (1.24).
	_position_slot(_prev_slot, 0.0, GALLERY_PREV_WIDTH)
	_position_slot(_focus_slot, GALLERY_PREV_WIDTH, GALLERY_FOCUS_WIDTH)
	_position_slot(_next_slot, GALLERY_PREV_WIDTH + GALLERY_FOCUS_WIDTH, GALLERY_NEXT_WIDTH)

	_prev_arrow.position = Vector2(ARROW_PREV_CENTER_X - 16, GALLERY_TOP + GALLERY_HEIGHT * 0.5 - 20)
	_prev_arrow.size = Vector2(32, 40)
	_next_arrow.position = Vector2(ARROW_NEXT_CENTER_X - 16, GALLERY_TOP + GALLERY_HEIGHT * 0.5 - 20)
	_next_arrow.size = Vector2(32, 40)

	# Identity
	_hero_name_label.position = Vector2(0, IDENTITY_TOP)
	_hero_name_label.size = Vector2(SCREEN_SIZE.x, IDENTITY_HEIGHT)
	_hero_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Name ornament placeholders ("—◇— NAME —◇—", asset 3). Fixed symmetric
	# offset from screen center for now — TODO once the real asset and its
	# rendered width are known, hug the label's actual text width instead
	# of this fixed offset (label width varies: "EGIL" vs "BRUNHILD").
	var name_ornament_offset: float = 90.0
	var ornament_y: float = IDENTITY_TOP + (IDENTITY_HEIGHT - NAME_ORNAMENT_SIZE.y) * 0.5
	_name_ornament_left.size = NAME_ORNAMENT_SIZE
	_name_ornament_left.position = Vector2(SCREEN_SIZE.x * 0.5 - name_ornament_offset - NAME_ORNAMENT_SIZE.x, ornament_y)
	_name_ornament_right.size = NAME_ORNAMENT_SIZE
	_name_ornament_right.position = Vector2(SCREEN_SIZE.x * 0.5 + name_ornament_offset, ornament_y)

	# Primary action
	var select_size := Vector2(165, 32)
	_select_button.position = Vector2((SCREEN_SIZE.x - select_size.x) * 0.5, ACTION_TOP + (ACTION_HEIGHT - select_size.y) * 0.5)
	_select_button.size = select_size

	# Border art (asset 2) layers directly over the button, slightly larger
	# so the ornamental outline reads outside the button's own edge.
	_select_border.position = _select_button.position - Vector2.ONE * SELECT_BORDER_PADDING
	_select_border.size = select_size + Vector2.ONE * SELECT_BORDER_PADDING * 2.0

	# Peripheral
	var back_size := Vector2(80, 22)
	_back_button.position = Vector2(16, PERIPHERAL_TOP + (PERIPHERAL_HEIGHT - back_size.y) * 0.5)
	_back_button.size = back_size

	# Focused-hero selection cue (asset 4) — sits at the focused hero's feet,
	# not a surrounding rectangle. Centered under the focus zone, just below
	# the shared ground line.
	var focus_zone_center_x: float = GALLERY_PREV_WIDTH + GALLERY_FOCUS_WIDTH * 0.5
	_focus_cue.size = FOCUS_CUE_SIZE
	_focus_cue.position = Vector2(focus_zone_center_x - FOCUS_CUE_SIZE.x * 0.5, GROUND_LINE_Y + 2.0)

	# Presentation frame (asset 1) — full-screen ornamental overlay, drawn
	# last so it sits on top of every other layer.
	_presentation_frame.position = Vector2.ZERO
	_presentation_frame.size = SCREEN_SIZE


## Slots anchor their bottom edge to GROUND_LINE_Y so all three heroes share
## a common ground line regardless of individual art height (spec 1.25).
## Each slot gets its full gallery-zone width/height; STRETCH_KEEP_ASPECT_
## CENTERED then centers the line art within that rect on its own.
## pivot_offset is set to bottom-center so set_focused()'s scale change
## (side vs. focused) shrinks/grows around the ground line instead of the
## rect's top-left corner.
func _position_slot(slot: HeroDisplayLineArt, left_x: float, zone_width: float) -> void:
	var h: float = HeroDisplayLineArt.FOCUSED_HEIGHT
	slot.custom_minimum_size = Vector2(zone_width, h)
	slot.size = Vector2(zone_width, h)
	slot.pivot_offset = Vector2(zone_width * 0.5, h)
	slot.position = Vector2(left_x, GROUND_LINE_Y - h)

	#endregion