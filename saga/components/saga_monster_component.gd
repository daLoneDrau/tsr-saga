# MonsterComponent.gd
# Core instance data for a monster entity.
# Managed by: CombatSystem (status), SpawnSystem (kind, stats at creation)
# Pure data — no methods.
# Archetype data (glory yield, abilities, model) lives in MonsterKindTable, not here.

class_name SagaMonsterComponent
extends EntityComponent


# Key into MonsterKindTable. Determines archetype data for this instance.
# Set at spawn, never changes. Type: int (MonsterKindId)
var kind: int = 0

# Instance combat strength. Set from MonsterKindTable at spawn.
var combat_strength: int = 0

# Instance movement speed. Set from MonsterKindTable at spawn.
var movement_speed: int = 0

# Current survivability state. Managed by CombatSystem.
# Uses Enums.MonsterStatus: ACTIVE | WOUNDED | SLAIN
var status: int = Enums.MonsterStatus.ACTIVE
