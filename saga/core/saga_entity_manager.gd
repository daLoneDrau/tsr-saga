class_name SagaEntityManager
extends EntityManager


## Entity tags for Warlock-specific entities
const TAG_PLAYER: int = 1 << 0
const TAG_MONSTER: int = 1 << 1
const TAG_ITEM: int = 1 << 2
const TAG_JARL: int = 1 << 3
const TAG_LAND: int = 1 << 4
const TAG_SEA: int = 1 << 5
const TAG_AI: int = 1 << 6
const TAG_UNIQUE: int = 1 << 8
const TAG_EQUIPPED: int = 1 << 9


## Determines if an Entity is tagged as a PC
func is_pc(e: Entity) -> bool:
	return e.tags.has(TAG_PLAYER)


## Determines if an Entity is tagged as an item
func is_item(e: Entity) -> bool:
	return e.tags.has(TAG_ITEM)


## Determines if an Entity is tagged as unique
func is_unique(e: Entity) -> bool:
	return e.tags.has(TAG_UNIQUE)


## Kill all active combat effects/spells on an entity
func kill_spells_on(e_id: String) -> void:
	var entity := get_entity_by_id(e_id)
	if not entity:
		return

	var effects_comp: EffectsComponent = entity.get_component("EffectsComponent") as EffectsComponent
	if effects_comp:
		# Remove all combat-duration effects
		effects_comp.on_combat_end()


## Send initialization script event (placeholder for future scripting)
func send_init_script_event(entity: Entity) -> void:
	# TODO: Implement scripting system if needed
	print("SagaEntityManager: Script event for entity %s (not implemented)" % entity.id)


## Unequip an item from a player's inventory
func unequip_from_inventory(player_entity: Entity, item_entity: Entity) -> bool:
	if not player_entity or not item_entity:
		return false

	var inv_comp: InventoryComponent = player_entity.get_component("InventoryComponent") as InventoryComponent
	if not inv_comp:
		return false

	var item_comp: ItemComponent = item_entity.get_component("ItemComponent") as ItemComponent
	if not item_comp:
		return false

	# Unequip based on type
	match item_comp.item_type:
		"weapon":
			if inv_comp.equipped_weapon == item_entity.id:
				inv_comp.equipped_weapon = ""
				item_entity.tags.remove(TAG_EQUIPPED)

				# Remove modifiers from player
				var stats_comp: SagaStatsComponent = player_entity.get_component("SagaStatsComponent") as SagaStatsComponent
				if stats_comp and item_comp.modifiers:
					item_comp.modifiers.remove_stat_modifiers(stats_comp, item_entity.id)

				return true

		"armor":
			if inv_comp.equipped_armor == item_entity.id:
				inv_comp.equipped_armor = ""
				item_entity.tags.remove(TAG_EQUIPPED)

				# Remove modifiers from player
				var stats_comp: SagaStatsComponent = player_entity.get_component("SagaStatsComponent") as SagaStatsComponent
				if stats_comp and item_comp.modifiers:
					item_comp.modifiers.remove_stat_modifiers(stats_comp, item_entity.id)

				return true

	return false
