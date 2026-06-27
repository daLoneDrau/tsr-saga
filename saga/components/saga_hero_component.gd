# saga_hero_component.gd
# Core instance data for a hero entity.
# Managed by: CombatSystem (is_wounded), KingdomSystem (kingdom, home_country),
#             JarlSystem (jarls), GlorySystem (glory lives on SagaGloryComponent)
# Combat stats (combat_strength, movement_speed, luck) live on SagaStatsComponent.
# Name lives on NameComponent.
# Pure data — no methods.

class_name SagaHeroComponent
extends EntityComponent


# Gold — starts at 0, never decreases.
# Awarded by combat and taxes.
var gold: int = 0

# The hero's home country. Set once at game start, never changes.
# Not automatically part of the kingdom — requires a jarl to hold like any other territory.
var home_country: Entity = null

# All countries currently in this hero's kingdom.
# Managed exclusively by KingdomSystem — never written directly.
var kingdom: Array = []  # Array[Entity (land entity)]

# Recruited jarls. Maximum 4. Jarls cannot be dismissed — only lost through combat.
# Managed exclusively by JarlSystem — never written directly.
var jarls: Array = []  # Array[Entity (jarl entity)]

# The one rune this hero has learned, or null if none.
# Set once and never changed. Uses Enums.RuneType.
var rune = null  # RuneType | null

# Wounded state. No stat penalties — the only mechanical effect is
# death on a second wound. Managed by CombatSystem.
var is_wounded: bool = false
