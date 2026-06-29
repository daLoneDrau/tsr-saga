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


# ---------------------------------------------------------------------------
# Entity factories
# All entity construction goes through these methods so that component layout
# for each entity type is defined in exactly one place.
# Each method returns the new entity's ID for immediate use by the caller.
# ---------------------------------------------------------------------------

## Creates a hero entity from a HeroKindTable entry.
## is_player: true for the human-controlled hero, false for AI opponents.
## Stamps: SagaHeroComponent, SagaGloryComponent, SagaEventLogComponent,
##         SagaEquipmentComponent, InventoryComponent.
## Tags:   TAG_PLAYER or TAG_AI.
func create_hero(kind_id: int, is_player: bool) -> String:
	var kind_data: Dictionary = HeroKindTable.get_hero(kind_id)

	var entity: SagaEntity = SagaEntity.new()
	entity.id = uuidv4()

	# Name
	entity.set_component(NameComponent.new(kind_data["name"]))

	# Combat stats
	var stats_comp := SagaStatsComponent.new()
	stats_comp.add_stat(SagaStatsComponent.COMBAT_STRENGTH, kind_data["combat_strength"])
	stats_comp.add_stat(SagaStatsComponent.MOVEMENT_SPEED,  kind_data["movement_speed"])
	stats_comp.add_stat(SagaStatsComponent.LUCK,            3)
	entity.set_component(stats_comp)

	# Hero instance data
	var hero_comp := SagaHeroComponent.new()
	entity.set_component(hero_comp)

	# Glory tracking
	entity.set_component(SagaGloryComponent.new())

	# Event log
	entity.set_component(SagaEventLogComponent.new())

	# Equipment slot for magic sword (MAIN_HAND, starts empty)
	entity.set_component(SagaEquipmentComponent.new())

	# Inventory for treasure (4 untyped slots)
	var inv_comp := InventoryComponent.new()
	inv_comp.capacity = 4
	inv_comp.slots    = []
	inv_comp.slots.resize(4)
	entity.set_component(inv_comp)

	# Script — handles AI turn decisions
	var script_comp := SagaScriptComponent.new()
	script_comp.main_script = HeroEntityScript.new()
	entity.set_component(script_comp)

	# Tag
	entity.tags.add(TAG_PLAYER if is_player else TAG_AI)

	add_entity(entity)
	return entity.id


## Creates a jarl entity from a JarlKindTable entry.
## Stamps: SagaJarlComponent, SagaEquipmentComponent, InventoryComponent.
## Tags:   TAG_JARL.
func create_jarl(kind_id: int) -> String:
	var kind_data: Dictionary = JarlKindTable.get_jarl(kind_id)

	var entity: SagaEntity = SagaEntity.new()
	entity.id = uuidv4()

	# Name
	entity.set_component(NameComponent.new(kind_data["name"]))

	# Combat stats
	var stats_comp := SagaStatsComponent.new()
	stats_comp.add_stat(SagaStatsComponent.COMBAT_STRENGTH, kind_data["combat_strength"])
	stats_comp.add_stat(SagaStatsComponent.MOVEMENT_SPEED,  kind_data["movement_speed"])
	entity.set_component(stats_comp)

	# Jarl instance data
	var jarl_comp := SagaJarlComponent.new()
	jarl_comp.kind_id = kind_id
	entity.set_component(jarl_comp)

	# Equipment slot for magic sword (MAIN_HAND, starts empty)
	entity.set_component(SagaEquipmentComponent.new())

	# Inventory for treasure (4 untyped slots)
	var inv_comp := InventoryComponent.new()
	inv_comp.capacity = 4
	inv_comp.slots    = []
	inv_comp.slots.resize(4)
	entity.set_component(inv_comp)

	# Script — handles wound and death reactions
	var script_comp := SagaScriptComponent.new()
	script_comp.main_script = JarlEntityScript.new()
	entity.set_component(script_comp)

	entity.tags.add(TAG_JARL)

	add_entity(entity)
	return entity.id


## Creates a monster entity from a MonsterKindTable entry.
## Stamps: SagaMonsterComponent.
## Tags:   TAG_MONSTER.
func create_monster(kind_id: int) -> String:
	var kind_data: Dictionary = MonsterKindTable.get_monster(kind_id)

	var entity: SagaEntity = SagaEntity.new()
	entity.id = uuidv4()

	# Name
	entity.set_component(NameComponent.new(kind_data["name"]))

	# Combat stats
	var stats_comp := SagaStatsComponent.new()
	stats_comp.add_stat(SagaStatsComponent.COMBAT_STRENGTH, kind_data["combat_strength"])
	stats_comp.add_stat(SagaStatsComponent.MOVEMENT_SPEED,  kind_data["movement_speed"])
	entity.set_component(stats_comp)

	# Monster instance data
	var monster_comp := SagaMonsterComponent.new()
	monster_comp.kind = kind_id
	entity.set_component(monster_comp)

	# Script — handles wound and death reactions
	var script_comp := SagaScriptComponent.new()
	script_comp.main_script = MonsterEntityScript.new()
	entity.set_component(script_comp)

	entity.tags.add(TAG_MONSTER)

	add_entity(entity)
	return entity.id


## Creates a magic sword entity from a MagicSwordTable entry.
## The sword is not equipped by this method — the caller is responsible for
## placing the returned entity ID into the wielder's SagaEquipmentComponent.
## Stamps: SagaMagicSwordComponent, SagaItemComponent.
## Tags:   TAG_ITEM.
func create_magic_sword(kind_id: int) -> String:
	var kind_data: Dictionary = MagicSwordTable.get_sword(kind_id)

	var entity: SagaEntity = SagaEntity.new()
	entity.id = uuidv4()

	# Name
	entity.set_component(NameComponent.new(kind_data["name"]))

	# Sword identity and special ability
	var sword_comp := SagaMagicSwordComponent.new()
	sword_comp.kind_id = kind_id
	sword_comp.ability = kind_data["ability"]
	entity.set_component(sword_comp)

	# Combat strength modifier — applied to wielder's StatsComponent on equip,
	# removed on unequip or drop. Managed by CombatSystem.
	var mod_entry := StatModifierEntry.create(
		&"magic_sword",
		kind_data["combat_bonus"],
		false
	)
	var bundle := ItemModifierBundle.new()
	bundle.stat_modifiers.append(mod_entry)

	var item_comp := SagaItemComponent.new()
	item_comp.modifiers = bundle
	entity.set_component(item_comp)

	# Script — handles equip/unequip modifier application and combat ability triggers
	var script_comp := SagaScriptComponent.new()
	script_comp.main_script = SwordEntityScript.new()
	entity.set_component(script_comp)

	entity.tags.add(TAG_ITEM)

	add_entity(entity)
	return entity.id
