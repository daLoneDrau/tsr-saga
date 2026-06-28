# jarl_entity_script.gd
# Logic script for jarl entities.
# Handles reactions to being hit and dying in combat.
# Subscribes to: DAMAGED, DIED

class_name JarlEntityScript
extends EntityScript


# Called when this jarl takes damage in combat.
# Future: CombatSystem fires this; script handles wound state and board removal.
func on_damaged(_ctx: Dictionary) -> Dictionary:
	return {}


# Called when this jarl is killed in combat.
# Future: drop equipped sword at combat location, clear owner_hero_id,
#         return jarl to spawn pool.
func on_died(_ctx: Dictionary) -> Dictionary:
	return {}
