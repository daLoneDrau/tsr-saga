# title_scene.gd
# Controller for the title screen.
# Extends Scene — registered as the root script on TitleScene.tscn.
#
# Responsibilities:
#   - Register keyboard actions (Up / Down / Return / Escape)
#   - Build the menu item list from the scene tree on _ready()
#   - Drive MenuItemSelected / MenuItemUnselected style swaps and the ▶ arrow
#   - Accept mouse hover (moves selection) and mouse click (confirms)
#   - Route confirmed selections to SagaGameEngine via do_action()

class_name TitleScene
extends Scene


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const ACTION_MENU_UP:    String = "menu_up"
const ACTION_MENU_DOWN:  String = "menu_down"
const ACTION_CONFIRM:    String = "menu_confirm"
const ACTION_QUIT:       String = "quit"

const ARROW_GLYPH: String = "▶"

# Stub path — replace when GameScene exists.
const SETUP_SCENE_PATH: String = "res://scenes/setup/SetupScene.tscn"


# ---------------------------------------------------------------------------
# Menu item descriptor
# ---------------------------------------------------------------------------

## Represents one selectable row in the menu.
class MenuItem:
	## The PanelContainer node (MenuItemSelected / MenuItemUnselected target).
	var panel: PanelContainer
	## The arrow Label (first Label inside panel/HBoxContainer).
	var arrow_label: Label
	## Action name fired when this item is confirmed.
	var action: String

	func _init(p: PanelContainer, a: Label, act: String) -> void:
		panel       = p
		arrow_label = a
		action      = act


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _items:          Array[MenuItem] = []
var _selected_index: int             = 0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_menu()
	_register_actions()
	_refresh_visuals()


func on_enter() -> void:
	_refresh_visuals()


func on_exit() -> void:
	_disconnect_mouse_signals()


# ---------------------------------------------------------------------------
# Menu construction
# ---------------------------------------------------------------------------

## Walks the scene tree to collect the four PanelContainer rows in order,
## wires mouse signals, and populates _items.
##
## Expected structure under UI/Main/Content/CenterRow/Column/MenuRow/Menu:
##   HBoxContainer  → HBoxContainer/NewSaga     (PanelContainer)
##   HBoxContainer2 → HBoxContainer2/HowToPlay  (PanelContainer)
##   HBoxContainer3 → HBoxContainer3/Settings   (PanelContainer)
##   HBoxContainer4 → HBoxContainer4/Credits    (PanelContainer)
func _build_menu() -> void:
	var menu_root := $UI/Main/Content/CenterRow/Column/MenuRow/Menu as VBoxContainer
	if menu_root == null:
		push_error("TitleScene: could not find Menu VBoxContainer")
		return

	# Node name → action string
	var action_for := {
		"NewSaga":  "new_saga",
		"HowToPlay": "how_to_play",
		"Settings": "settings",
		"Credits":  "credits",
	}

	for hbox in menu_root.get_children():
		if not hbox is HBoxContainer:
			continue
		# Each HBoxContainer has exactly one PanelContainer child.
		for child in hbox.get_children():
			if not child is PanelContainer:
				continue
			var panel := child as PanelContainer
			var act: String = action_for.get(panel.name, "")
			if act.is_empty():
				push_warning("TitleScene: unrecognised menu panel '%s'" % panel.name)
				continue

			# Arrow label is the first Label inside panel/HBoxContainer.
			var inner_hbox := panel.get_child(0) as HBoxContainer
			if inner_hbox == null:
				push_error("TitleScene: panel '%s' missing inner HBoxContainer" % panel.name)
				continue
			var arrow_label: Label = null
			for lbl in inner_hbox.get_children():
				if lbl is Label:
					arrow_label = lbl as Label
					break
			if arrow_label == null:
				push_error("TitleScene: panel '%s' missing arrow Label" % panel.name)
				continue

			var item := MenuItem.new(panel, arrow_label, act)
			_items.append(item)

			# Wire mouse signals — capture the index at bind time.
			var idx := _items.size() - 1
			panel.gui_input.connect(_on_panel_gui_input.bind(idx))
			panel.mouse_entered.connect(_on_panel_mouse_entered.bind(idx))


## Disconnects all mouse signals (called on exit to avoid dangling connections).
func _disconnect_mouse_signals() -> void:
	for i in _items.size():
		var item := _items[i]
		if item.panel.gui_input.is_connected(_on_panel_gui_input.bind(i)):
			item.panel.gui_input.disconnect(_on_panel_gui_input.bind(i))
		if item.panel.mouse_entered.is_connected(_on_panel_mouse_entered.bind(i)):
			item.panel.mouse_entered.disconnect(_on_panel_mouse_entered.bind(i))


# ---------------------------------------------------------------------------
# Action registration
# ---------------------------------------------------------------------------

func _register_actions() -> void:
	register_action("any_key", "any_key")


# ---------------------------------------------------------------------------
# Scene.do_action — required override
# ---------------------------------------------------------------------------

func do_action(action: GameAction) -> void:
	if not action.is_pressed():
		pass # sometimes you want to skip key release events

	match action.name:
		"new_saga":
			SagaGameEngine_auto.change_scene("SetupScene", SETUP_SCENE_PATH)
		"how_to_play", "settings", "credits":
			# Stubs — implement when scenes exist.
			print("TitleScene: '%s' not yet implemented" % action.name)
		"any_key":
			match action.phase:
				"END":
					var key_entry: String = OS.get_keycode_string(SagaGameEngine_auto.last_keycode)
					match key_entry:
						"Up", "Kp 8":
							_move_selection(-1)
						"Down", "Kp 2":
							_move_selection(1)
						"Enter", "Kp Enter":
							_confirm_selection()
						"Escape":
							SagaGameEngine_auto.quit()
						_:
							#print("any key ", key_entry)
							pass


# ---------------------------------------------------------------------------
# Selection logic
# ---------------------------------------------------------------------------

func _move_selection(delta: int) -> void:
	_selected_index = wrapi(_selected_index + delta, 0, _items.size())
	_refresh_visuals()


func _confirm_selection() -> void:
	if _items.is_empty():
		return
	var act: String = _items[_selected_index].action
	do_action(GameAction.new(act, GameAction.PHASE_START))


# ---------------------------------------------------------------------------
# Visual refresh
# ---------------------------------------------------------------------------

## Applies MenuItemSelected / MenuItemUnselected theme variations and
## sets the ▶ arrow on the active row; clears it on all others.
func _refresh_visuals() -> void:
	for i in _items.size():
		var item := _items[i]
		if i == _selected_index:
			item.panel.theme_type_variation = &"MenuItemSelected"
			item.arrow_label.text = ARROW_GLYPH
		else:
			item.panel.theme_type_variation = &"MenuItemUnselected"
			item.arrow_label.text = ""


# ---------------------------------------------------------------------------
# Mouse signal handlers
# ---------------------------------------------------------------------------

func _on_panel_mouse_entered(idx: int) -> void:
	_selected_index = idx
	_refresh_visuals()


func _on_panel_gui_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# Move selection to clicked item then confirm.
			_selected_index = idx
			_refresh_visuals()
			_confirm_selection()
