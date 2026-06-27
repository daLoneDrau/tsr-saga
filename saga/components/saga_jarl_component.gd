# saga_jarl_component.gd
# Instance data for a jarl entity.
# Managed by: JarlSystem
# Name is stored on NameComponent, not here.
# Pure data — no methods.

class_name SagaJarlComponent
extends EntityComponent


# Key into JarlKindTable. Set at entity creation, never changes.
var kind_id: int = 0

# Combat strength. Set from JarlKindTable at entity creation, never changes.
# Added to the controlling hero's total force when co-located with that hero.
var combat_strength: int = 0

# Movement speed. Set from JarlKindTable at entity creation, never changes.
var movement_speed: int = 0

# UUID of the hero entity that recruited this jarl.
# Empty string ("") means the jarl is unowned and available for recruitment.
# Set by JarlSystem on recruitment; cleared to "" when the jarl is killed
# or wounded and returned to the spawn pool.
var owner_hero_id: String = ""
