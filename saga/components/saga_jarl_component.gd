# saga_jarl_component.gd
# Instance data for a jarl entity.
# Managed by: JarlSystem
# Combat stats (combat_strength, movement_speed) live on SagaStatsComponent.
# Name lives on NameComponent.
# Pure data — no methods.

class_name SagaJarlComponent
extends EntityComponent


# Key into JarlKindTable. Set at entity creation, never changes.
var kind_id: int = 0

# UUID of the hero entity that recruited this jarl.
# Empty string ("") means the jarl is unowned and available for recruitment.
# Set by JarlSystem on recruitment; cleared to "" when the jarl is killed
# or wounded and returned to the spawn pool.
var owner_hero_id: String = ""
