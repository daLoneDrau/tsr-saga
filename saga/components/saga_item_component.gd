# saga_item_component.gd
# Thin subclass of ItemComponent scoped to Saga's needs.
# Only modifiers are used — price, weight, stack size, and all other
# ItemComponent fields are irrelevant to this game and left at defaults.
# Modifiers are typed as ItemModifierBundle to integrate with StatsComponent.
# CombatSystem calls modifiers.apply_stat_modifiers / remove_stat_modifiers
# when a sword is equipped or unequipped.

class_name SagaItemComponent
extends ItemComponent
