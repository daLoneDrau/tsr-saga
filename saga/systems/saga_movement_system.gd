# saga_movement_system.gd
# Resolves the movement phase for heroes, in the turn order locked by
# SagaTurnSystem. Movement is player-selected: this system validates a
# chosen destination against reachability (SagaMapSystem, bounded by the
# hero's MOVEMENT_SPEED stat) and, if valid, performs the move through
# SagaBoardSystem — the only system allowed to write location state.
#
# Scope note: actually EXECUTING jarl movement (aligned jarls moving in the
# same turn-order slot as their hero, using either the hero's or their own
# MOVEMENT_SPEED depending on whether they move together) is out of scope
# here and will be added alongside the combat/recruitment phase. Tracking
# which pieces (hero + recruited jarls) are currently ELIGIBLE to move —
# i.e. owned by the current mover and not yet moved this phase — is in
# scope now (see get_available_pieces()), since the move-availability
# board highlight needs it even before jarl movement itself is executable.
#
# Resolution model, per design discussion:
#   - Heroes move one at a time, strictly in SagaTurnSystem's locked order.
#   - A hero may move "up to" their MOVEMENT_SPEED — stopping short, or not
#     moving at all (pass), is always legal.
#   - No destination restriction beyond distance — a hero may end movement
#     in a region already occupied by a rival hero, monster, or jarl.
#     Occupancy fallout (mandatory/optional combat) is resolved in the
#     combat phase, not here.
#   - Paths are free and cannot be interrupted, so reachability is pure
#     unweighted shortest-hop-count — see SagaMapSystem.get_reachable().
#   - The whole phase resolves for every hero before combat begins; nothing
#     here triggers combat mid-phase even if a hero lands on a monster.
#   - A piece (hero or jarl) may only move once per movement phase — see
#     has_moved()/mark_moved(). This is distinct from _current_index (whose
#     TURN SLOT is active): a hero and their recruited jarls can each move
#     independently within the same slot per 5.2.26/5.2.27, so per-piece
#     move tracking and per-slot turn-order tracking are separate concerns.
#
# Managed by: SagaMovementSystem exclusively (mover index / phase-complete
# state, and per-piece has-moved state). Location state itself is owned by
# SagaBoardSystem — this system never writes to it directly, only through
# SagaBoardSystem's public API.
#
# Listens for:
#   "start_movement_phase" payload: {}
#   "move_hero"  payload: { entity_id: String, location_id: String }
#   "pass_movement" payload: { entity_id: String }

class_name SagaMovementSystem
extends GameSystem


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

# Snapshot of SagaTurnSystem.get_turn_order() taken at start_movement_phase().
# Array[String hero_entity_id].
var _movement_order: Array = []

# Index into _movement_order of the hero currently resolving movement.
# Equal to _movement_order.size() once every hero has moved.
var _current_index: int = 0

# entity_id -> true for every piece (hero or jarl) that has already
# performed a move action this movement phase. A piece may only move once
# per phase — this is the tracking that enforces/reports that, separate
# from _current_index (which tracks whose TURN SLOT is active, not which
# individual pieces within that slot have already acted). Reset at the
# start of every movement phase.
var _moved_entities: Dictionary = {}

var _phase_started: bool = false


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _on_ready() -> void:
	pass

func _on_cleanup() -> void:
	_movement_order.clear()
	_current_index = 0
	_moved_entities.clear()
	_phase_started = false

func _on_initialize() -> void:
	pass

func _process_system(_delta: float) -> void:
	pass

func handle_event(event_name: String, payload: Dictionary = {}) -> bool:
	match event_name:
		"start_movement_phase":
			start_movement_phase()
			return true
		"move_hero":
			var entity_id: String = payload.get("entity_id", "")
			var location_id: String = payload.get("location_id", "")
			if entity_id == "" or location_id == "":
				return false
			return move_hero(entity_id, location_id)
		"pass_movement":
			var entity_id: String = payload.get("entity_id", "")
			if entity_id == "":
				return false
			return pass_movement(entity_id)
	return true


# ---------------------------------------------------------------------------
# Phase control
# ---------------------------------------------------------------------------

## Begins the movement phase: snapshots the current turn order from
## SagaTurnSystem, resets the mover cursor to the first hero, and clears
## per-piece has-moved tracking for the new phase.
func start_movement_phase() -> void:
	var turn_sys := get_system(&"SagaTurnSystem") as SagaTurnSystem
	if turn_sys == null:
		push_error("SagaMovementSystem.start_movement_phase: SagaTurnSystem not registered")
		return
	_movement_order = turn_sys.get_turn_order()
	_current_index = 0
	_moved_entities.clear()
	_phase_started = true
	broadcast_event("movement_phase_started", {"order": _movement_order.duplicate()})
	if _movement_order.is_empty():
		broadcast_event("movement_phase_complete", {})


## Returns the hero_entity_id whose turn it is to move, or "" if the phase
## hasn't started or every hero has already moved this turn.
func get_current_mover() -> String:
	if not _phase_started or _current_index >= _movement_order.size():
		return ""
	return _movement_order[_current_index]


## True once every hero in this turn's order has moved (or passed).
func is_movement_phase_complete() -> bool:
	return _phase_started and _current_index >= _movement_order.size()


# ---------------------------------------------------------------------------
#region Per-piece move tracking
# ---------------------------------------------------------------------------

## True if entity_id (hero or jarl) has already performed a move action
## this movement phase.
func has_moved(entity_id: String) -> bool:
	return _moved_entities.get(entity_id, false)


## Marks entity_id as having moved this phase. Called automatically by
## move_hero() on a successful hero move; jarl movement will call this too
## once it's implemented (see the scope note at the top of this file) —
## the tracking itself doesn't care which kind of piece moved.
func mark_moved(entity_id: String) -> void:
	_moved_entities[entity_id] = true


## Returns hero_entity_id plus every jarl entity_id they've recruited
## (SagaJarlComponent.owner_hero_id == hero_entity_id), filtered to only
## pieces that haven't moved yet this phase. This is the exact "which
## pieces can still act" set the move-availability board highlight needs —
## ownership alone isn't enough (an owned piece that already moved isn't
## available), and has_moved() alone isn't enough either (it doesn't know
## which pieces belong to this hero in the first place).
func get_available_pieces(hero_entity_id: String) -> Array:
	var pieces: Array = []
	if not has_moved(hero_entity_id):
		pieces.append(hero_entity_id)

	for jarl_entity: Entity in SagaEntityManager_auto.get_entities_by_tag(SagaEntityManager.TAG_JARL):
		var jarl_comp: SagaJarlComponent = jarl_entity.get_component("SagaJarlComponent", false) as SagaJarlComponent
		if jarl_comp == null or jarl_comp.owner_hero_id != hero_entity_id:
			continue
		if has_moved(jarl_entity.id):
			continue
		pieces.append(jarl_entity.id)

	return pieces

#endregion


# ---------------------------------------------------------------------------
#region Reachability
# ---------------------------------------------------------------------------

## Returns every location entity_id the given hero could legally move to
## this turn: every region reachable within the hero's MOVEMENT_SPEED stat
## from their current location. Does NOT include their current location —
## staying put is always legal via pass_movement() regardless of this list.
func get_reachable_regions(hero_entity_id: String) -> Array:
	var board := get_system(&"SagaBoardSystem") as SagaBoardSystem
	var map_sys := get_system(&"SagaMapSystem") as SagaMapSystem
	if board == null or map_sys == null:
		return []

	var current_location: String = board.get_location_of(hero_entity_id)
	if current_location == "":
		return []

	var hero_entity := SagaEntityManager_auto.get_entity_by_id(hero_entity_id)
	if hero_entity == null:
		return []
	var stats: SagaStatsComponent = hero_entity.get_component("StatsComponent") as SagaStatsComponent
	if stats == null:
		return []
	var speed: int = stats.get_value(SagaStatsComponent.MOVEMENT_SPEED)

	return map_sys.get_reachable(current_location, speed)

#endregion


# ---------------------------------------------------------------------------
#region Movement resolution
# ---------------------------------------------------------------------------

## Moves hero_entity_id to destination_entity_id, if it is currently that
## hero's turn to move and the destination is within their reachable set.
## Marks the hero as moved (has_moved()) and advances the mover cursor on
## success. Returns false (no state changed) if it isn't this hero's turn
## or the destination is illegal.
func move_hero(hero_entity_id: String, destination_entity_id: String) -> bool:
	if hero_entity_id != get_current_mover():
		push_warning("SagaMovementSystem.move_hero: not %s's turn to move" % hero_entity_id)
		return false

	var reachable: Array = get_reachable_regions(hero_entity_id)
	if not reachable.has(destination_entity_id):
		push_warning("SagaMovementSystem.move_hero: %s is not reachable this turn" % destination_entity_id)
		return false

	var board := get_system(&"SagaBoardSystem") as SagaBoardSystem
	board.move_entity(hero_entity_id, destination_entity_id)

	mark_moved(hero_entity_id)
	broadcast_event("hero_moved", {"entity_id": hero_entity_id, "location_id": destination_entity_id})
	_advance_mover()
	return true


## Explicitly declines to move this turn. Legal even though movement is
## always optional — advances the mover cursor without touching location.
## Deliberately does NOT call mark_moved(): passing means the hero didn't
## move, so has_moved() should stay false for them (matters if pass ever
## needs to be distinguishable from "moved" for the availability highlight
## — right now both end this hero's turn slot via _advance_mover() either
## way, but only an actual move should ever read as "already moved").
func pass_movement(hero_entity_id: String) -> bool:
	if hero_entity_id != get_current_mover():
		push_warning("SagaMovementSystem.pass_movement: not %s's turn to move" % hero_entity_id)
		return false

	broadcast_event("hero_passed_movement", {"entity_id": hero_entity_id})
	_advance_mover()
	return true


func _advance_mover() -> void:
	_current_index += 1
	if _current_index >= _movement_order.size():
		broadcast_event("movement_phase_complete", {})

#endregion
