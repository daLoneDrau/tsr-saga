# game_scene.gd
# Minimal controller for the main game loop screen. Extends Scene — registered
# as the root script on GameScene.tscn.
#
# Visually matches TitleScene/SetupScene: WindowBorder frame, black top/bottom
# banner bars with a violet divider, a PanelBox card in the middle, and a CRT
# scanline overlay. Reachable regions are rendered as MenuItem-styled rows
# (PanelContainer + arrow + label) built at runtime — same hover/click
# pattern as TitleScene's menu, since the set of reachable regions changes
# every time the current mover changes.
#
# This is intentionally bare on GAMEPLAY scope, even though it's now styled:
# a status readout plus a clickable list of reachable regions, enough to
# exercise SagaTurnSystem/SagaMovementSystem end to end from the editor. It
# is NOT the real board UI — that's a later step (3D board, region picking
# on the map itself). Combat, taxes, and the monster/jarl placement phases
# aren't wired yet; this only drives the movement phase, then reports the
# phase complete and stops.
#
# Responsibilities:
#   - Register SagaMapSystem, SagaBoardSystem, SagaGlorySystem,
#     SagaTurnSystem, SagaMovementSystem.
#   - Kick off turn 1's movement phase on enter.
#   - Show whose turn it is to move and what regions they can reach.
#   - Let the player click a region to move there, or press Pass.
#   - Refresh after every move/pass; report when the movement phase ends.
#   - Let the player open a dossier popup showing their own hero's data.

class_name GameScene
extends Scene


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const ARROW_GLYPH: String = "▶"

# Duplicated from setup_scene.gd's STUBBLE_BY_HAIR — only Starkad's model has
# a stubble surface, keyed by which hair material is currently applied. This
# is small and hero-agnostic enough that duplicating it here was judged
# cheaper than a shared-materials-table refactor, but it IS a second copy:
# if stubble options ever change, update both places.
const STUBBLE_BY_HAIR: Dictionary = {
	"res://assets/art/materials/heroes/hair/blonde.tres": "res://assets/art/materials/heroes/stubble/stubble_blonde.tres",
	"res://assets/art/materials/heroes/hair/auburn.tres": "res://assets/art/materials/heroes/stubble/stubble_auburn.tres",
	"res://assets/art/materials/heroes/hair/red.tres": "res://assets/art/materials/heroes/stubble/stubble_red.tres",
	"res://assets/art/materials/heroes/hair/black.tres": "res://assets/art/materials/heroes/stubble/stubble_black.tres",
	"res://assets/art/materials/heroes/hair/platinum.tres": "res://assets/art/materials/heroes/stubble/stubble_platinum.tres",
	}


# ---------------------------------------------------------------------------
# Region row descriptor
# ---------------------------------------------------------------------------

## Represents one dynamically-built reachable-region row.
class RegionRow:
	var panel:       PanelContainer
	var arrow_label: Label
	var entity_id:   String

	func _init(p: PanelContainer, a: Label, id: String) -> void:
		panel       = p
		arrow_label = a
		entity_id   = id


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var _banner_right:        Label          = %BannerRight
@onready var _mover_label:         Label          = %MoverLabel
@onready var _location_label:      Label          = %LocationLabel
@onready var _regions_header:      Label          = %RegionsHeader
@onready var _regions_scroll:      ScrollContainer = %RegionsScroll
@onready var _region_list:         VBoxContainer  = %RegionList
@onready var _pass_btn:            Button         = %PassBtn
@onready var _hero_info_btn:       Button         = %HeroInfoBtn
@onready var _hero_info_popup:     PopupPanel     = %HeroInfoPopup
@onready var _hero_info_text:      RichTextLabel  = %HeroInfoText
@onready var _hero_info_close_btn: Button         = %HeroInfoCloseBtn
@onready var _combat_pips:         HBoxContainer  = %CombatPips
@onready var _speed_pips:          HBoxContainer  = %SpeedPips
@onready var _portrait_widget:     PortraitWidget = %PortraitWidget


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

# Rebuilt every _refresh(). Rows are ephemeral — freed and recreated each
# time, since the reachable set changes whenever the current mover changes.
var _rows: Array[RegionRow] = []


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

## Called when the node enters the [SceneTree].
func _enter_tree() -> void:
	# GameEngine.change_scene() only calls set_engine() via call_deferred(),
	# which fires AFTER this scene's _ready() has already run synchronously.
	# _ready() here calls _start_movement_phase() immediately (no user-input
	# gate to wait out the deferred call, unlike SetupScene), so _game_engine
	# would still be null the whole time without this. _enter_tree() always
	# runs before _ready(), and SagaGameEngine_auto is a true autoload
	# (initialized before any regular scene node), so this is always safe.
	set_engine(SagaGameEngine_auto)


func _ready() -> void:
	_register_systems()
	_wire_ui()
	_start_movement_phase()


func on_exit() -> void:
	_unwire_ui()
	_clear_region_rows()


func do_action(_action: GameAction) -> void:
	pass  # This debug screen is mouse-driven only; no keyboard actions yet.


# ---------------------------------------------------------------------------
#region System registration
# ---------------------------------------------------------------------------

func _register_systems() -> void:
	# Map and Board alias into SagaGameEngine_auto's persistent storage
	# (see saga_map_system.gd / saga_board_system.gd headers) — this just
	# picks up the graph and placements SetupScene already built.
	var map := SagaMapSystem.new()
	map.name = "SagaMapSystem"
	add_child(map)
	register_system(map)

	var board := SagaBoardSystem.new()
	board.name = "SagaBoardSystem"
	add_child(board)
	register_system(board)

	var glory := SagaGlorySystem.new()
	glory.name = "SagaGlorySystem"
	add_child(glory)
	register_system(glory)

	var turn := SagaTurnSystem.new()
	turn.name = "SagaTurnSystem"
	add_child(turn)
	register_system(turn)

	var movement := SagaMovementSystem.new()
	movement.name = "SagaMovementSystem"
	add_child(movement)
	register_system(movement)

#endregion


# ---------------------------------------------------------------------------
#region UI wiring
# ---------------------------------------------------------------------------

func _wire_ui() -> void:
	_pass_btn.pressed.connect(_on_pass_pressed)
	_hero_info_btn.pressed.connect(_on_hero_info_pressed)
	_hero_info_close_btn.pressed.connect(_on_hero_info_close_pressed)


func _unwire_ui() -> void:
	if _pass_btn.pressed.is_connected(_on_pass_pressed):
		_pass_btn.pressed.disconnect(_on_pass_pressed)
	if _hero_info_btn.pressed.is_connected(_on_hero_info_pressed):
		_hero_info_btn.pressed.disconnect(_on_hero_info_pressed)
	if _hero_info_close_btn.pressed.is_connected(_on_hero_info_close_pressed):
		_hero_info_close_btn.pressed.disconnect(_on_hero_info_close_pressed)

#endregion


# ---------------------------------------------------------------------------
#region Movement phase driving
# ---------------------------------------------------------------------------

func _start_movement_phase() -> void:
	var movement_sys := get_registered_system(&"SagaMovementSystem") as SagaMovementSystem
	movement_sys.start_movement_phase()
	_refresh()


func _refresh() -> void:
	var movement_sys := get_registered_system(&"SagaMovementSystem") as SagaMovementSystem
	var turn_sys := get_registered_system(&"SagaTurnSystem") as SagaTurnSystem
	var turn: int = turn_sys.get_current_turn()

	if movement_sys.is_movement_phase_complete():
		_banner_right.text = "TURN %d — COMPLETE" % turn
		_mover_label.text = "MOVEMENT PHASE COMPLETE"
		_location_label.text = "(COMBAT PHASE NOT YET IMPLEMENTED)"
		_regions_header.visible = false
		_regions_scroll.visible = false
		_clear_region_rows()
		_pass_btn.disabled = true
		return

	_banner_right.text = "TURN %d — MOVEMENT" % turn
	_regions_header.visible = true
	_regions_scroll.visible = true

	var mover_id: String = movement_sys.get_current_mover()
	var mover_name: String = _entity_display_name(mover_id)
	_mover_label.text = "%s'S TURN TO MOVE" % mover_name.to_upper()

	var board := get_registered_system(&"SagaBoardSystem") as SagaBoardSystem
	var current_location := board.get_location_of(mover_id) if board else ""
	_location_label.text = "AT: %s" % _entity_display_name(current_location).to_upper()

	var reachable: Array = movement_sys.get_reachable_regions(mover_id)
	_rebuild_region_rows(reachable)
	_pass_btn.disabled = false


func _on_pass_pressed() -> void:
	var movement_sys := get_registered_system(&"SagaMovementSystem") as SagaMovementSystem
	var mover_id: String = movement_sys.get_current_mover()
	if mover_id == "":
		return
	movement_sys.pass_movement(mover_id)
	_refresh()


func _on_region_chosen(destination_entity_id: String) -> void:
	var movement_sys := get_registered_system(&"SagaMovementSystem") as SagaMovementSystem
	var mover_id: String = movement_sys.get_current_mover()
	if mover_id == "":
		return
	movement_sys.move_hero(mover_id, destination_entity_id)
	_refresh()

#endregion


# ---------------------------------------------------------------------------
#region Region row list (dynamic, MenuItem-styled — same pattern as TitleScene)
# ---------------------------------------------------------------------------

func _clear_region_rows() -> void:
	for row in _rows:
		if is_instance_valid(row.panel):
			row.panel.queue_free()
	_rows.clear()


func _rebuild_region_rows(reachable_entity_ids: Array) -> void:
	_clear_region_rows()
	for entity_id in reachable_entity_ids:
		_add_region_row(entity_id)


func _add_region_row(entity_id: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"MenuItemUnselected"
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	panel.add_child(hbox)

	var arrow := Label.new()
	arrow.custom_minimum_size = Vector2(16, 16)
	arrow.add_theme_color_override("font_color", Color(1, 0.8862745, 0.2901961, 1))
	arrow.add_theme_font_size_override("font_size", 14)
	arrow.text = ""
	hbox.add_child(arrow)

	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.theme_type_variation = &"MenuItem"
	label.text = _entity_display_name(entity_id).to_upper()
	hbox.add_child(label)

	var row := RegionRow.new(panel, arrow, entity_id)
	_rows.append(row)
	_region_list.add_child(panel)

	panel.gui_input.connect(_on_row_gui_input.bind(row))
	panel.mouse_entered.connect(_on_row_mouse_entered.bind(row))
	panel.mouse_exited.connect(_on_row_mouse_exited.bind(row))


func _on_row_mouse_entered(row: RegionRow) -> void:
	row.panel.theme_type_variation = &"MenuItemSelected"
	row.arrow_label.text = ARROW_GLYPH


func _on_row_mouse_exited(row: RegionRow) -> void:
	row.panel.theme_type_variation = &"MenuItemUnselected"
	row.arrow_label.text = ""


func _on_row_gui_input(event: InputEvent, row: RegionRow) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_region_chosen(row.entity_id)

#endregion


# ---------------------------------------------------------------------------
#region Hero info popup
# ---------------------------------------------------------------------------

func _on_hero_info_pressed() -> void:
	var hero := _get_player_hero()
	var stats: SagaStatsComponent = hero.get_component("StatsComponent", false) as SagaStatsComponent if hero else null
	var hero_comp: SagaHeroComponent = hero.get_component("SagaHeroComponent", false) as SagaHeroComponent if hero else null
	_fill_pips(_combat_pips, stats.get_value(SagaStatsComponent.COMBAT_STRENGTH) if stats else 0)
	_fill_pips(_speed_pips, stats.get_value(SagaStatsComponent.MOVEMENT_SPEED) if stats else 0)
	_show_hero_portrait(hero_comp)
	_hero_info_text.text = _build_hero_info_text(hero)
	_hero_info_popup.popup_centered()


func _on_hero_info_close_pressed() -> void:
	_hero_info_popup.hide()


## Sets the first `filled` pips in container to PipFull, the rest PipEmpty.
## Identical to SetupScene's _fill_pips — same pip widget, same convention.
func _fill_pips(container: HBoxContainer, filled: int) -> void:
	var children: Array = container.get_children()
	for i in children.size():
		var pip := children[i] as PanelContainer
		if pip == null:
			continue
		pip.theme_type_variation = &"PipFull" if i < filled else &"PipEmpty"


## Loads this hero's 3D model into the portrait viewport, using the same
## PortraitWidget rig SetupScene's dossier uses. Model path now comes from
## HeroKindTable (single source of truth — see hero_kind_table.gd); skin
## and hair are the palette actually rolled for this hero at setup, stored
## on SagaHeroComponent and never re-rolled. Animation: PortraitWidget always
## plays "idle" (the only clip baked into every hero glTF export) — the
## right choice here too, since this is a passive info/dossier view, not
## combat; there's no other clip to choose from even if a livelier one were
## wanted for this context.
func _show_hero_portrait(hero_comp: SagaHeroComponent) -> void:
	if hero_comp == null or hero_comp.kind_id < 0:
		_portrait_widget.clear_hero()
		return

	var kind_data: Dictionary = HeroKindTable.get_hero(hero_comp.kind_id)
	var stubble_path: String = ""
	if hero_comp.kind_id == HeroKindTable.STARKAD:
		stubble_path = STUBBLE_BY_HAIR.get(hero_comp.hair_material_path, "")

	_portrait_widget.show_hero(
			kind_data["model"],
			hero_comp.skin_material_path,
			hero_comp.hair_material_path,
			stubble_path,
			)


## Returns the human player's hero entity (TAG_PLAYER), or null if not found.
func _get_player_hero() -> Entity:
	var players: Array = SagaEntityManager_auto.get_entities_by_tag(SagaEntityManager.TAG_PLAYER)
	return players[0] if not players.is_empty() else null


## Gathers and formats the human player's hero data (everything except
## combat strength and movement speed, which are shown as pip rows instead —
## see _on_hero_info_pressed). Always shows THE player's hero specifically,
## regardless of whose turn it currently is to move.
func _build_hero_info_text(hero: Entity) -> String:
	if hero == null:
		return "No player hero found."

	var hero_comp: SagaHeroComponent = hero.get_component("SagaHeroComponent", false) as SagaHeroComponent
	var stats: SagaStatsComponent = hero.get_component("StatsComponent", false) as SagaStatsComponent
	var glory_comp: SagaGloryComponent = hero.get_component("SagaGloryComponent", false) as SagaGloryComponent
	var equip_comp: SagaEquipmentComponent = hero.get_component("EquipmentComponent", false) as SagaEquipmentComponent

	var board := get_registered_system(&"SagaBoardSystem") as SagaBoardSystem

	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % _entity_display_name(hero.id))

	if hero_comp:
		lines.append("Home country: %s" % (_entity_display_name(hero_comp.home_country) if hero_comp.home_country != "" else "—"))

	var current_location := board.get_location_of(hero.id) if board else ""
	lines.append("Current location: %s" % (_entity_display_name(current_location) if current_location != "" else "—"))

	if stats:
		lines.append("Luck: %d" % stats.get_value(SagaStatsComponent.LUCK))

	lines.append("Glory: %d" % (glory_comp.current if glory_comp else 0))

	lines.append("Sword equipped: %s" % _sword_display_text(equip_comp))

	if hero_comp:
		lines.append("Gold: %d" % hero_comp.gold)
		lines.append("Jarls: %d / 4" % hero_comp.jarls.size())
		lines.append("Kingdom: %d region%s" % [hero_comp.kingdom.size(), "" if hero_comp.kingdom.size() == 1 else "s"])
		lines.append("Wounded: %s" % ("Yes" if hero_comp.is_wounded else "No"))

	return "\n".join(lines)


## Resolves the MAIN_HAND slot to a display string: sword name and its
## combat bonus, or "None" if the slot is empty.
func _sword_display_text(equip_comp: SagaEquipmentComponent) -> String:
	if equip_comp == null:
		return "None"
	var sword_id: String = equip_comp.slots.get(EquipmentSlot.Enum.MAIN_HAND, "")
	if sword_id == "":
		return "None"
	var sword_entity: Entity = SagaEntityManager_auto.get_entity_by_id(sword_id)
	if sword_entity == null:
		return "None"
	var sword_name := _entity_display_name(sword_id)
	var sword_comp: SagaMagicSwordComponent = sword_entity.get_component("SagaMagicSwordComponent", false) as SagaMagicSwordComponent
	if sword_comp:
		return "%s (+%d combat)" % [sword_name, sword_comp.combat_bonus]
	return sword_name

#endregion


# ---------------------------------------------------------------------------
#region Helpers
# ---------------------------------------------------------------------------

func _entity_display_name(entity_id: String) -> String:
	var entity: Entity = get_entity(entity_id)
	if entity == null:
		return entity_id
	var name_comp: NameComponent = entity.get_component("NameComponent", false) as NameComponent
	if name_comp and name_comp.has_name():
		return name_comp.get_display_name()
	var land_comp: SagaLandComponent = entity.get_component("SagaLandComponent", false) as SagaLandComponent
	if land_comp:
		return land_comp.name
	var sea_comp: SagaSeaComponent = entity.get_component("SagaSeaComponent", false) as SagaSeaComponent
	if sea_comp:
		return sea_comp.name
	return entity_id

#endregion
