# saga_glory_system.gd
# Manages all reads and writes to SagaGloryComponent.
# Subscribes to the glory_changed signal via Switchboard.
# Enforces the floor of 0 on all glory totals.
# Writes an EventLogEntry to SagaEventLogComponent on every award or loss.

class_name SagaGlorySystem
extends GameSystem


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _on_ready() -> void:
	Switchboard_auto.connect_subscriber(self, "glory_changed", _on_glory_changed)


## Override for system-specific cleanup
func _on_cleanup() -> void:
	pass


## Override for system-specific initialization (after scene is set)
func _on_initialize() -> void:
	pass


# GlorySystem has no per-frame work — all logic is event-driven.
func _process_system(_delta: float) -> void:
	pass


# ---------------------------------------------------------------------------
# Signal handler
# ---------------------------------------------------------------------------

## Receives glory_changed(entity, delta, source) from CombatSystem (and any
## future broadcaster). Applies the delta to the entity's GloryComponent,
## enforces the floor, and appends an EventLogEntry on the hero's log.
##
## entity  — the hero receiving (or losing) glory
## delta   — signed integer; positive = award, negative = loss
## source  — the entity that caused the change (slain monster, recruited jarl,
##            defeated hero, etc.). May be null for non-entity sources.
func _on_glory_changed(entity: SagaEntity, delta: int, source: SagaEntity) -> void:
	if entity == null or delta == 0:
		return

	var glory_comp: SagaGloryComponent = entity.get_component("SagaGloryComponent") as SagaGloryComponent
	if glory_comp == null:
		return

	# Apply delta, clamping to floor of 0.
	var previous: int = glory_comp.current
	glory_comp.current = max(0, glory_comp.current + delta)
	glory_comp.source_entity = source

	# Determine actual change after clamping (may differ from raw delta).
	var actual_delta: int = glory_comp.current - previous
	if actual_delta == 0:
		return

	# Append to the hero's event log if one is present.
	_append_log_entry(entity, actual_delta, source)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _append_log_entry(
	entity: SagaEntity,
	actual_delta: int,
	source: SagaEntity
) -> void:
	var log_comp: SagaEventLogComponent = entity.get_component("SagaEventLogComponent") as SagaEventLogComponent
	if log_comp == null:
		return

	var entry_type: int = (
		SagaEventLogComponent.EntryType.GLORY_AWARDED
		if actual_delta > 0
		else SagaEventLogComponent.EntryType.GLORY_LOST
	)

	var description: String = _build_description(actual_delta, source)

	var turn: int = _get_current_turn()

	var entry := SagaEventLogComponent.EventLogEntry.new(
		entry_type,
		description,
		source,
		turn
	)
	log_comp.entries.append(entry)


## Builds a human-readable log description from the delta and source entity.
## Source entity naming is intentionally minimal here — richer descriptions
## can be composed by CombatSystem before emitting the signal and passed
## through a dedicated description parameter if needed in a later phase.
func _build_description(actual_delta: int, source: SagaEntity) -> String:
	var source_name: String = "unknown"
	if source != null:
		# Attempt to read a name from HeroComponent or fall back to entity id.
		var hero_comp: SagaHeroComponent = source.get_component("SagaHeroComponent") as SagaHeroComponent
		if hero_comp != null and hero_comp.name != "":
			source_name = hero_comp.name
		else:
			source_name = source.id

	if actual_delta > 0:
		return "Gained %d glory from %s." % [actual_delta, source_name]
	else:
		return "Lost %d glory fleeing from %s." % [abs(actual_delta), source_name]


## Returns the current turn number from SagaGameEngine.
## Falls back to 0 if the engine is not yet initialised.
func _get_current_turn() -> int:
	if SagaGameEngine_auto == null:
		return 0
	# Turn tracking will be added to SagaGameEngine in Phase 3 (TurnSystem).
	# This call is future-proofed; replace with the actual property when ready.
	if SagaGameEngine_auto.has_method("get_current_turn"):
		return SagaGameEngine_auto.get_current_turn()
	return 0


# ---------------------------------------------------------------------------
# Public API — called by CombatSystem to compute glory deltas before emitting.
# These are pure calculations; CombatSystem owns the decision to emit.
# ---------------------------------------------------------------------------

## Glory for slaying a monster. Looks up fixed reward from MonsterKindTable.
## Returns 0 if the kind is not registered.
static func glory_for_monster_slay(kind_id: int) -> int:
	# MonsterKindTable will be implemented in Phase 2 data work.
	# Placeholder: return kind_id as a stub value so callers can be written now.
	# Replace with: return MonsterKindTable.get_glory_reward(kind_id)
	push_warning("SagaGlorySystem: MonsterKindTable not yet implemented — returning 0 for kind %d" % kind_id)
	return 0


## Glory for slaying a rival hero.
## total_force = hero.combat_strength + sum of all jarls' combat_strength
## physically present on the same tile at time of combat.
static func glory_for_hero_slay(total_force_at_tile: int) -> int:
	return total_force_at_tile / 2


## Glory for wounding a rival hero (same total force formula).
static func glory_for_hero_wound(total_force_at_tile: int) -> int:
	return total_force_at_tile / 4


## Glory for slaying a rival jarl directly.
static func glory_for_jarl_slay(jarl_combat_strength: int) -> int:
	return jarl_combat_strength / 2


## Glory for recruiting a jarl.
static func glory_for_jarl_recruit(jarl_combat_strength: int) -> int:
	return jarl_combat_strength / 2


## Glory loss for fleeing combat.
static func glory_loss_for_fleeing() -> int:
	return -2


## Handle discrete game events (override in subclass)
func handle_event(_event_name: String, _payload: Dictionary = {}) -> void:
	pass