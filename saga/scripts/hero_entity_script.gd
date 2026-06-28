# hero_entity_script.gd
# Logic script for hero entities.
# Handles AI turn management — stub until AISystem is implemented.
# Subscribes to: INITIALIZED, TURN_STARTED

class_name HeroEntityScript
extends EntityScript


# Called when the hero entity is first initialized.
# Future: seed any AI state variables here.
func on_initialized(_ctx: Dictionary) -> Dictionary:
	return {}


# Called at the start of this hero's turn.
# Future: AI decision-making entry point when the hero is computer-controlled.
# Check TAG_AI on the entity to determine if this hero needs AI handling.
func on_turn_started(_ctx: Dictionary) -> Dictionary:
	return {}
