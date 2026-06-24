# LandComponent.gd
# Represents a territory (country) entity on the game map.
# Managed by: KingdomSystem (turns_undefended, kingdom membership),
#             CombatSystem (conquest, reads tax_value)
# Pure data — no methods.
# Ownership is derived via KingdomSystem traversal — no back-reference to owner.

class_name SagaLandComponent
extends EntityComponent


# Display name of the territory. Set at game creation, never changes.
var name: String = ""

# Tax value. Set at game creation, never changes.
# CombatSystem uses this to derive the territory's defending combat strength.
var tax_value: int = 0

# Grid position. x and y each constrained to 1–6.
# Set at game creation, never changes.
# Type: Enums.LocationCode
var location: Enums.LocationCode = null

# True at game start (territory has never been conquered).
# Set to false on first conquest by a hero. Never reverts to true.
var is_neutral: bool = true

# Counts consecutive turns this territory has been unoccupied by its
# owning hero or one of their jarls. Starts at 0.
# Incremented by KingdomSystem each turn no qualifying occupant is present.
# Reset to 0 when a qualifying occupant is present.
# When it reaches 2, KingdomSystem removes the territory from the hero's kingdom.
var turns_undefended: int = 0
