# game_scene.gd
# Minimal controller for the main game loop screen. Extends Scene — registered
# as the root script on GameScene.tscn.
#
# This is intentionally bare: a status label plus a clickable list of
# reachable regions, enough to exercise SagaTurnSystem/SagaMovementSystem end
# to end from the editor. It is NOT the real board UI — that's a later step
# (3D board, region picking on the map itself). Combat, taxes, and the
# monster/jarl placement phases aren't wired yet; this only drives the
# movement phase, then reports the phase complete and stops.
#
# Responsibilities:
#   - Register SagaMapSystem, SagaBoardSystem, SagaGlorySystem,
#     SagaTurnSystem, SagaMovementSystem.
#   - Kick off turn 1's movement phase on enter.
#   - Show whose turn it is to move and what regions they can reach.
#   - Let the player click a region to move there, or press Pass.
#   - Refresh after every move/pass; report when the movement phase ends.

class_name GameScene
extends Scene


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var _status_label:   Label    = %StatusLabel
@onready var _reachable_list: ItemList = %ReachableList
@onready var _pass_btn:       Button   = %PassBtn
@onready var _hero_info_btn:  Button     = %HeroInfoBtn
@onready var _hero_info_popup: PopupPanel   = %HeroInfoPopup
@onready var _hero_info_text: RichTextLabel = %HeroInfoText
@onready var _hero_info_close_btn: Button   = %HeroInfoCloseBtn


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

# Parallel to _reachable_list's rows: index -> destination entity_id.
var _reachable_entity_ids: Array = []


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
	_reachable_list.item_selected.connect(_on_region_selected)
	_pass_btn.pressed.connect(_on_pass_pressed)
	_hero_info_btn.pressed.connect(_on_hero_info_pressed)
	_hero_info_close_btn.pressed.connect(_on_hero_info_close_pressed)


func _unwire_ui() -> void:
	if _reachable_list.item_selected.is_connected(_on_region_selected):
		_reachable_list.item_selected.disconnect(_on_region_selected)
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

	if movement_sys.is_movement_phase_complete():
		_status_label.text = "Turn %d — movement phase complete. (Combat phase not yet implemented.)" % turn_sys.get_current_turn()
		_reachable_list.clear()
		_reachable_entity_ids.clear()
		_pass_btn.disabled = true
		return

	var mover_id: String = movement_sys.get_current_mover()
	var mover_name: String = _entity_display_name(mover_id)
	_status_label.text = "Turn %d — %s's turn to move. Choose a region or Pass." % [turn_sys.get_current_turn(), mover_name]

	_reachable_entity_ids = movement_sys.get_reachable_regions(mover_id)
	_reachable_list.clear()
	for entity_id in _reachable_entity_ids:
		_reachable_list.add_item(_entity_display_name(entity_id))
	_pass_btn.disabled = false


func _on_region_selected(index: int) -> void:
	var movement_sys := get_registered_system(&"SagaMovementSystem") as SagaMovementSystem
	var mover_id: String = movement_sys.get_current_mover()
	if mover_id == "" or index < 0 or index >= _reachable_entity_ids.size():
		return
	movement_sys.move_hero(mover_id, _reachable_entity_ids[index])
	_refresh()


func _on_pass_pressed() -> void:
	var movement_sys := get_registered_system(&"SagaMovementSystem") as SagaMovementSystem
	var mover_id: String = movement_sys.get_current_mover()
	if mover_id == "":
		return
	movement_sys.pass_movement(mover_id)
	_refresh()

#endregion


# ---------------------------------------------------------------------------
#region Hero info popup
# ---------------------------------------------------------------------------


func _on_hero_info_pressed() -> void:
	_hero_info_text.text = _build_hero_info_text()
	_hero_info_popup.popup_centered()
func _on_hero_info_close_pressed() -> void:
	_hero_info_popup.hide()
	

## Gathers and formats the human player's hero data. Always shows THE
## player's hero specifically (TAG_PLAYER), regardless of whose turn it
## currently is to move.
func _build_hero_info_text() -> String:
	var players: Array = SagaEntityManager_auto.get_entities_by_tag(SagaEntityManager.TAG_PLAYER)
	if players.is_empty():
		return "No player hero found."
	var hero: Entity = players[0]
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
		lines.append("Combat strength: %d" % stats.get_value(SagaStatsComponent.COMBAT_STRENGTH))
		lines.append("Movement factor: %d" % stats.get_value(SagaStatsComponent.MOVEMENT_SPEED))
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