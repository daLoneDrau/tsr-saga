# saga_stats_component.gd
# Thin subclass of StatsComponent that defines Saga's stat ID constants.
# All systems must reference these constants rather than freehand StringNames
# to ensure consistent keying across the codebase.
# Stat initialization is handled by SagaEntityManager factory methods.

class_name SagaStatsComponent
extends StatsComponent


# Stat ID constants — use these everywhere instead of raw strings.
const COMBAT_STRENGTH: StringName = &"combat_strength"
const MOVEMENT_SPEED:  StringName = &"movement_speed"
const LUCK:            StringName = &"luck"
