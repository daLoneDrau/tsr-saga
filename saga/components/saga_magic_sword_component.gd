# SagaMagicSwordComponent.gd
# Instance data for a magic sword entity.
# Managed by: InventorySystem (placement in/out of inventory slots),
#             CombatSystem (reading combat_bonus and ability during combat resolution)
# Pure data — no methods.

class_name SagaMagicSwordComponent
extends EntityComponent


# Key into MagicSwordTable. Set at entity creation, never changes.
var kind_id: int = 0

# Sword's name. Set from MagicSwordTable at entity creation, never changes.
var sword_name: String = ""

# Flat combat strength bonus applied when the sword is in the inventory of
# the active combatant. +1 or +2. Set from MagicSwordTable, never changes.
var combat_bonus: int = 0

# Ability identifier for CombatSystem to key on during combat resolution.
# "" means no special ability.
# Known values: "cancel_magic_armor", "alter_combat_result", "jarl_slayer"
# Set from MagicSwordTable at entity creation, never changes.
var ability: String = ""
