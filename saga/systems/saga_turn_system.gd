# saga_turn_system.gd
# Owns the turn counter and the turn-order sequence for the current turn.
#
# Turn order is recomputed at the start of every turn from each hero's
# current SagaGloryComponent.current (highest glory moves/fights/collects
# taxes first). Ties are broken randomly, re-rolled every turn — even a
# repeat tie between the same two heroes gets a fresh coin flip. Once
# computed, the order is locked for the whole turn and reused by every
# phase (movement, combat, taxes) — SagaMovementSystem and future phase
# systems all read get_turn_order() rather than recomputing it themselves.
#
# Phase implementation status (see project discussion):
#   MOVEMENT        — implemented (SagaMovementSystem)
#   COMBAT          — not yet implemented
#   TAXES           — not yet implemented
#   PLACE_MONSTERS  — not yet implemented
#   PLACE_JARLS     — not yet implemented
#   MARK_TURN       — turn counter only; win-condition check not yet implemented
#
# Managed by: SagaTurnSystem exclusively.
#
# Listens for:
#   "start_turn"   payload: {}  — recomputes turn order, resets phase to MOVEMENT
#   "advance_phase" payload: {} — moves to the next phase in sequence

class_name SagaTurnSystem
extends GameSystem


const MAX_TURNS: int = 20

enum Phase {
	MOVEMENT,
	COMBAT,
	TAXES,
	PLACE_MONSTERS,
	PLACE_JARLS,
	MARK_TURN,
}

const _PHASE_SEQUENCE: Array = [
							   Phase.MOVEMENT,
							   Phase.COMBAT,
							   Phase.TAXES,
							   Phase.PLACE_MONSTERS,
							   Phase.PLACE_JARLS,
							   Phase.MARK_TURN,
							   ]


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

# 1-indexed. Game ends after MAX_TURNS is marked complete.
var _current_turn: int = 1

var _current_phase: Phase = Phase.MOVEMENT

# Locked for the duration of the current turn. Array[String hero_entity_id],
# highest glory first, ties randomized fresh each turn.
var _turn_order: Array = []


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _on_ready() -> void:
	pass

func _on_cleanup() -> void:
	_current_turn = 1
	_current_phase = Phase.MOVEMENT
	_turn_order.clear()

func _on_initialize() -> void:
	compute_turn_order()

func _process_system(_delta: float) -> void:
	pass

func handle_event(event_name: String, _payload: Dictionary = {}) -> bool:
	match event_name:
		"start_turn":
			compute_turn_order()
			_current_phase = Phase.MOVEMENT
			return true
		"advance_phase":
			advance_phase()
			return true
	return true


# ---------------------------------------------------------------------------
# Turn order
# ---------------------------------------------------------------------------

## Recomputes and locks turn order for the current turn: highest glory first,
## ties broken randomly. Called automatically on initialize and on every
## "start_turn" event (i.e. after mark_turn() advances to a new turn).
func compute_turn_order() -> void:
	var em := get_entity_manager()
	var heroes: Array = em.get_entities_with_component("SagaHeroComponent") if em else []

	# Shuffle first, then sort by descending glory. Since the pre-sort order
	# is randomized, any two heroes with equal glory end up in random
	# relative order regardless of sort stability — this is the "re-rolled
	# every turn" tiebreak.
	heroes.shuffle()
	heroes.sort_custom(func(a, b): return _glory_of(a) > _glory_of(b))

	_turn_order = []
	for hero in heroes:
		_turn_order.append(hero.id)


func _glory_of(hero_entity) -> int:
	var glory_comp: SagaGloryComponent = hero_entity.get_component("SagaGloryComponent") as SagaGloryComponent
	return glory_comp.current if glory_comp else 0


## Returns the locked turn order for the current turn: Array[String hero_entity_id].
func get_turn_order() -> Array:
	return _turn_order.duplicate()


# ---------------------------------------------------------------------------
# Turn / phase progression
# ---------------------------------------------------------------------------

func get_current_turn() -> int:
	return _current_turn

func get_current_phase() -> Phase:
	return _current_phase

## Moves to the next phase in the fixed sequence. If called from MARK_TURN,
## use mark_turn() instead — this only advances within a turn.
func advance_phase() -> void:
	var idx: int = _PHASE_SEQUENCE.find(_current_phase)
	if idx == -1 or idx + 1 >= _PHASE_SEQUENCE.size():
		return
	_current_phase = _PHASE_SEQUENCE[idx + 1]
	broadcast_event("phase_changed", {"phase": _current_phase})

## Ends the current turn: increments the turn counter and, if the game
## hasn't reached MAX_TURNS, recomputes turn order and resets to MOVEMENT
## for the next turn. Win-condition resolution (highest glory at turn 20)
## is not yet implemented — that's part of the MARK_TURN phase build-out.
func mark_turn() -> void:
	_current_turn += 1
	if _current_turn > MAX_TURNS:
		broadcast_event("game_over", {"final_turn": MAX_TURNS})
		return
	compute_turn_order()
	_current_phase = Phase.MOVEMENT
	broadcast_event("start_turn", {"turn": _current_turn})

## True once the turn counter has passed MAX_TURNS.
func is_game_over() -> bool:
	return _current_turn > MAX_TURNS
