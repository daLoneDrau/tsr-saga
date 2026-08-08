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


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

# Parallel to _reachable_list's rows: index -> destination entity_id.
var _reachable_entity_ids: Array = []


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

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


func _unwire_ui() -> void:
	if _reachable_list.item_selected.is_connected(_on_region_selected):
		_reachable_list.item_selected.disconnect(_on_region_selected)
	if _pass_btn.pressed.is_connected(_on_pass_pressed):
		_pass_btn.pressed.disconnect(_on_pass_pressed)

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