# saga_monster_component.gd
# Core instance data for a monster entity.
# Managed by: CombatSystem (status)
# Combat stats (combat_strength, movement_speed) live on SagaStatsComponent.
# Name lives on NameComponent.
# Archetype data (glory yield, abilities) lives in MonsterKindTable, not here.
# Pure data — no methods.

class_name SagaMonsterComponent
extends EntityComponent


# Key into MonsterKindTable. Determines archetype data for this instance.
# Set at spawn, never changes.
var kind: int = 0

# Current survivability state. Managed by CombatSystem.
# Uses Enums.MonsterStatus: ACTIVE | WOUNDED | SLAIN
var status: int = Enums.MonsterStatus.ACTIVE
