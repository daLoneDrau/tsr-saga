# setup_scene.gd
# Controller for the new-game setup screen.
# Extends Scene — registered as the root script on SetupScene.tscn.
#
# Responsibilities:
#   - Register and own the four game systems needed for setup.
#   - Step 1: collect AI opponent count via the +/- stepper.
#   - Step 2: present the alphabetical hero list; show stats in the dossier
#             panel when a hero is highlighted; confirm selection via Accept.
#   - On Accept: call SagaSetupSystem.run() with chosen hero kind ID and
#                total player count, then transition to GameScene.
#
# Node references are resolved once in _ready() via unique-name shortcuts
# (%NodeName) and stored in typed vars. No $path lookups after _ready().

class_name SetupScene
extends Scene


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const GAME_SCENE_PATH: String = "res://scenes/game/GameScene.tscn"

const AI_MIN: int = 1
const AI_MAX: int = 5

# One distinct stub colour per hero, matched to the alphabetical display order:
# Beowulf, Brunhild, Egil, Ragnar, Siegfried, Starkad
const HERO_STUB_COLORS: Array[Color] = [
	Color(0.85, 0.55, 0.20),   # Beowulf   — amber
	Color(0.40, 0.70, 0.90),   # Brunhild  — ice blue
	Color(0.55, 0.85, 0.45),   # Egil      — sage green
	Color(0.90, 0.35, 0.35),   # Ragnar    — crimson
	Color(0.75, 0.55, 0.90),   # Siegfried — violet
	Color(0.90, 0.80, 0.30),   # Starkad   — gold
]

# Hero kind IDs in the same alphabetical order as the scene's Hero0–Hero5 panels.
# This maps list index → HeroKindTable constant so the script never hard-codes
# names — it reads everything from the kind table at runtime.
const HERO_KIND_IDS: Array[int] = [
	HeroKindTable.BEOWULF,
	HeroKindTable.BRUNHILD,
	HeroKindTable.EGIL,
	HeroKindTable.RAGNAR,
	HeroKindTable.SIEGFRIED,
	HeroKindTable.STARKAD,
]

# Maximum pip count rendered in the dossier (matches the scene's P0–P5 nodes).
const MAX_PIPS: int = 6

# Bottom-bar text per step.
const BAR_STEP1_MSG1: String = "HOW MANY RIVAL JARLS WILL CONTEST THE NORTH?"
const BAR_STEP1_MSG2: String = "CHOOSE 1 TO 5 OPPONENTS, THEN CONTINUE."
const BAR_STEP2_MSG1: String = "CHOOSE THE HERO YOU WILL PLAY."
const BAR_STEP2_MSG2: String = "HIGHLIGHT A HERO, THEN ACCEPT TO MUSTER."


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _ai_count:          int = 1
var _selected_hero_idx: int = 0   # index into HERO_KIND_IDS / scene list


# ---------------------------------------------------------------------------
# Node references — Step 1
# ---------------------------------------------------------------------------

@onready var _step1:       CenterContainer = %Step1
@onready var _minus_btn:   Button          = %MinusBtn
@onready var _count_label: Label           = %CountLabel
@onready var _plus_btn:    Button          = %PlusBtn
@onready var _continue_btn: Button         = %ContinueBtn


# ---------------------------------------------------------------------------
# Node references — Step 2
# ---------------------------------------------------------------------------

@onready var _step2:      Control    = %Step2
@onready var _back_btn:   Button     = %BackBtn
@onready var _hero_list:  VBoxContainer = %HeroList
@onready var _hero_mesh:  MeshInstance3D = %HeroMesh
@onready var _hero_name:  Label      = %HeroName   # dossier name label
@onready var _combat_pips: HBoxContainer = %CombatPips
@onready var _speed_pips:  HBoxContainer = %SpeedPips
@onready var _accept_btn: Button     = %AcceptBtn


# ---------------------------------------------------------------------------
# Node references — chrome
# ---------------------------------------------------------------------------

@onready var _msg1: Label = $UI/Main/Content/BottomRow/Column/Msg1
@onready var _msg2: Label = $UI/Main/Content/BottomRow/Column/Msg2


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_selected_hero_idx = DiceTower_auto.roll("d6-1")
	_register_systems()
	_wire_step1()
	_wire_step2()
	_show_step(1)


func on_enter() -> void:
	_show_step(1)


func on_exit() -> void:
	_unwire_step1()
	_unwire_step2()


# ---------------------------------------------------------------------------
#region Scene.do_action — required override
# ---------------------------------------------------------------------------

func do_action(action: GameAction) -> void:
	if not action.is_pressed():
		pass # sometimes you want to skip key release events

	match action.name:
		"minus_pressed":
			if _ai_count > AI_MIN:
				_ai_count -= 1
				_refresh_stepper()
		"plus_pressed":
			if _ai_count < AI_MAX:
				_ai_count += 1
				_refresh_stepper()
		"show_step":
			_show_step(action.args)
		"accept":
			var chosen_kind_id: int = HERO_KIND_IDS[_selected_hero_idx]
			var total_players: int  = 1 + _ai_count   # 1 human + N AI
		
			var setup_sys := get_registered_system(&"SagaSetupSystem") as SagaSetupSystem
			if setup_sys == null:
				push_error("SetupScene: SagaSetupSystem not registered")

			setup_sys.run(chosen_kind_id, total_players)
			# Transition happens in _on_setup_complete once run() emits setup_complete.
		
#endregion

# ---------------------------------------------------------------------------
#region System registration
# ---------------------------------------------------------------------------

func _register_systems() -> void:
	var board := SagaBoardSystem.new()
	board.name = "SagaBoardSystem"
	add_child(board)
	register_system(board)

	var equipment := SagaEquipmentSystem.new()
	equipment.name = "SagaEquipmentSystem"
	add_child(equipment)
	register_system(equipment)

	var glory := SagaGlorySystem.new()
	glory.name = "SagaGlorySystem"
	add_child(glory)
	register_system(glory)

	var setup := SagaSetupSystem.new()
	setup.name = "SagaSetupSystem"
	add_child(setup)
	register_system(setup)

	setup.setup_complete.connect(_on_setup_complete)
	
#endregion

# ---------------------------------------------------------------------------
#region Step visibility
# ---------------------------------------------------------------------------

func _show_step(step: int) -> void:
	_step1.visible = (step == 1)
	_step2.visible = (step == 2)

	if step == 1:
		_msg1.text = BAR_STEP1_MSG1
		_msg2.text = BAR_STEP1_MSG2
		_refresh_stepper()
	else:
		_msg1.text = BAR_STEP2_MSG1
		_msg2.text = BAR_STEP2_MSG2
		_refresh_hero_list()
		_refresh_dossier(_selected_hero_idx)
		
#endregion


# ---------------------------------------------------------------------------
#region Step 1 — opponent count
# ---------------------------------------------------------------------------

func _wire_step1() -> void:
	_minus_btn.pressed.connect(do_action.bind(GameAction.new("minus_pressed", GameAction.PHASE_END)))
	_plus_btn.pressed.connect(do_action.bind(GameAction.new("plus_pressed", GameAction.PHASE_END)))
	_continue_btn.pressed.connect(do_action.bind(GameAction.new("show_step", GameAction.PHASE_END, 2)))


func _unwire_step1() -> void:
	if _minus_btn.pressed.is_connected(do_action):
		_minus_btn.pressed.disconnect(do_action)
	if _plus_btn.pressed.is_connected(do_action):
		_plus_btn.pressed.disconnect(do_action)
	if _continue_btn.pressed.is_connected(do_action):
		_continue_btn.pressed.disconnect(do_action)


func _refresh_stepper() -> void:
	_count_label.text = str(_ai_count)
	_minus_btn.modulate.a = 0.4 if _ai_count <= AI_MIN else 1.0
	_minus_btn.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if _ai_count <= AI_MIN else Control.CURSOR_POINTING_HAND
	_plus_btn.modulate.a  = 0.4 if _ai_count >= AI_MAX else 1.0
	_plus_btn.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if _ai_count >= AI_MAX else Control.CURSOR_POINTING_HAND

#endregion

# ---------------------------------------------------------------------------
# Step 2 — hero selection
# ---------------------------------------------------------------------------

func _wire_step2() -> void:
	var panels: Array = _hero_list.get_children()
	for i in panels.size():
		var panel: PanelContainer = panels[i] as PanelContainer
		if panel == null:
			continue
		panel.gui_input.connect(_on_hero_panel_input.bind(i))
		panel.mouse_entered.connect(_on_hero_panel_hover.bind(i))

	_back_btn.pressed.connect(do_action.bind(GameAction.new("show_step", GameAction.PHASE_END, 1)))
	_accept_btn.pressed.connect(do_action.bind(GameAction.new("accept", GameAction.PHASE_END)))


func _unwire_step2() -> void:
	var panels: Array = _hero_list.get_children()
	for i in panels.size():
		var panel: PanelContainer = panels[i] as PanelContainer
		if panel == null:
			continue
		if panel.gui_input.is_connected(_on_hero_panel_input.bind(i)):
			panel.gui_input.disconnect(_on_hero_panel_input.bind(i))
		if panel.mouse_entered.is_connected(_on_hero_panel_hover.bind(i)):
			panel.mouse_entered.disconnect(_on_hero_panel_hover.bind(i))

	if _back_btn.pressed.is_connected(do_action):
		_back_btn.pressed.disconnect(do_action)
	if _accept_btn.pressed.is_connected(do_action):
		_accept_btn.pressed.disconnect(do_action)


func _on_hero_panel_hover(idx: int) -> void:
	_selected_hero_idx = idx
	_refresh_hero_list()
	_refresh_dossier(idx)


func _on_hero_panel_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_selected_hero_idx = idx
			_refresh_hero_list()
			_refresh_dossier(idx)

# ---------------------------------------------------------------------------
# Hero list visual refresh
# ---------------------------------------------------------------------------

func _refresh_hero_list() -> void:
	var panels: Array = _hero_list.get_children()
	for i in panels.size():
		var panel: PanelContainer = panels[i] as PanelContainer
		if panel == null:
			continue
		if i == _selected_hero_idx:
			panel.theme_type_variation = &"HeroActive"
			_set_hero_panel_color(panel, Color(0, 0, 0, 1))
		else:
			panel.theme_type_variation = &"HeroIdle"
			_set_hero_panel_color(panel, Color(0.604, 0.627, 0.847, 1))


## Propagates a font colour to every Label descendant of a hero panel.
## The scene uses per-node theme_override_colors so we update them at runtime
## to match the active/idle state rather than duplicating theme variations.
func _set_hero_panel_color(panel: PanelContainer, color: Color) -> void:
	for node in panel.find_children("*", "Label", true, false):
		var lbl := node as Label
		lbl.add_theme_color_override("font_color", color)


# ---------------------------------------------------------------------------
# Dossier refresh
# ---------------------------------------------------------------------------

func _refresh_dossier(idx: int) -> void:
	var kind_id: int       = HERO_KIND_IDS[idx]
	var data: Dictionary   = HeroKindTable.get_hero(kind_id)

	# Name
	_hero_name.text = data["name"].to_upper()

	# Pips — set PipFull on the first N children, PipEmpty on the rest.
	_fill_pips(_combat_pips, data["combat_strength"])
	_fill_pips(_speed_pips,  data["movement_speed"])

	# Portrait stub mesh color.
	# STUB: replace albedo_color swap with real model load when assets ship.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = HERO_STUB_COLORS[idx]
	mat.roughness    = 0.9
	_hero_mesh.material_override = mat


func _fill_pips(container: HBoxContainer, filled: int) -> void:
	var children: Array = container.get_children()
	for i in children.size():
		var pip := children[i] as PanelContainer
		if pip == null:
			continue
		pip.theme_type_variation = &"PipFull" if i < filled else &"PipEmpty"


# ---------------------------------------------------------------------------
# Setup complete handler
# ---------------------------------------------------------------------------

func _on_setup_complete(_payload: Dictionary) -> void:
	# Board is now populated. Transition to GameScene.
	# STUB path — replace when GameScene exists.
	_game_engine.change_scene("GameScene", GAME_SCENE_PATH)
