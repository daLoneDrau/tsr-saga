# monster_entity_script.gd
# Logic script for monster entities.
# Handles reactions to being hit and dying in combat.
# Subscribes to: DAMAGED, DIED

class_name MonsterEntityScript
extends EntityScript


# Called when this monster takes damage in combat.
# Future: CombatSystem fires this; script handles wound state transitions
#         (ACTIVE -> WOUNDED -> SLAIN) per MonsterKindTable rules.
func on_damaged(_ctx: Dictionary) -> Dictionary:
	return {}


# Called when this monster is slain.
# Future: yield glory to the victor, reveal dragon hoard if applicable,
#         remove entity from board.
func on_died(_ctx: Dictionary) -> Dictionary:
	return {}
