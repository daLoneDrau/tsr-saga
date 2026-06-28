# sword_entity_script.gd
# Logic script for magic sword entities.
# Handles equip/unequip modifier application and combat ability triggers.
# Subscribes to: ITEM_EQUIPPED, ITEM_UNEQUIPPED, ATTACK_HIT

class_name SwordEntityScript
extends EntityScript


# Called when this sword is equipped by a hero or jarl.
# Future: call SagaItemComponent.modifiers.apply_stat_modifiers() on the wielder's
#         SagaStatsComponent to apply the combat_bonus.
func on_item_equipped(_ctx: Dictionary) -> Dictionary:
	return {}


# Called when this sword is unequipped (trade or death drop).
# Future: call SagaItemComponent.modifiers.remove_stat_modifiers() on the
#         previous wielder's SagaStatsComponent.
func on_item_unequipped(_ctx: Dictionary) -> Dictionary:
	return {}


# Called when the wielder lands a hit in combat.
# Future: check SagaMagicSwordComponent.ability and trigger the appropriate
#         special effect (cancel_magic_armor, alter_combat_result, jarl_slayer).
func on_attack_hit(_ctx: Dictionary) -> Dictionary:
	return {}
