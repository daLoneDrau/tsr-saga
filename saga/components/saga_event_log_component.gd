# saga_event_log_component.gd
# Records a narrative history of significant events for the player's hero.
# Attached to the hero entity only — NPCs do not get an event log.
# Managed by: any system that fires a loggable event (GlorySystem, CombatSystem, etc.)
# Pure data — no methods beyond entry construction.

class_name SagaEventLogComponent
extends EntityComponent


# ---------------------------------------------------------------------------
# Entry type enum — stubbed; extend as new event categories are designed.
# ---------------------------------------------------------------------------

enum EntryType {
	MOVEMENT,
	COMBAT_RESULT,
	GODS_INTERVENTION,
	GLORY_AWARDED,
	GLORY_LOST,
}


# ---------------------------------------------------------------------------
# Inner class — a single log entry.
# ---------------------------------------------------------------------------

class EventLogEntry:
	## Category of event. Uses EntryType enum.
	var entry_type: int

	## Human-readable description of what happened.
	var description: String

	## The entity that caused or was involved in the event (may be null for
	## world events such as god interventions with no specific source entity).
	var source_entity: SagaEntity

	## The turn number on which this event occurred.
	var turn: int

	func _init(
		p_type: int,
		p_description: String,
		p_source: SagaEntity,
		p_turn: int
	) -> void:
		entry_type = p_type
		description = p_description
		source_entity = p_source
		turn = p_turn


# ---------------------------------------------------------------------------
# Component data
# ---------------------------------------------------------------------------

## All recorded events in chronological order. Unbounded — the game lasts
## at most 20 turns, so growth is naturally constrained.
var entries: Array = []  # Array[EventLogEntry]