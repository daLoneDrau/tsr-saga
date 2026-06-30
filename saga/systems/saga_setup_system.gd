# saga_setup_system.gd
# One-shot orchestrator for the game setup sequence. Called once by SetupScene
# on load; never runs again.
#
# Sequence:
#   1. Shuffle all four kind-table pools.
#   2. Assign hero to the player (create entity, tagged TAG_PLAYER).
#   3. Create magic sword and broadcast "equip_item" for SagaEquipmentSystem.
#   4. Place N monsters on random land locations (N = player count, currently 1).
#   5. Place N jarls on random land locations.
#   6. Place hero on a random land location; record as home_country.
#   7. luck = 3 already set by create_hero via SagaStatsComponent.
#   8. Write remaining monster/jarl/treasure kind IDs to SagaGameEngine pools.
#   9. Emit setup_complete with summary payload for SetupScene to display.
#
# All cross-system communication goes through broadcast_event — this system
# holds no references to other systems.

class_name SagaSetupSystem
extends GameSystem


## Emitted when the full setup sequence is complete.
## Payload keys:
##   hero_name:          String
##   sword_name:         String
##   sword_bonus:        int
##   home_country_name:  String
##   home_country_code:  String   e.g. "3:4"
##   monsters:           Array[Dictionary]  each: { name, location_name }
##   jarls:              Array[Dictionary]  each: { name, location_name }
signal setup_complete(payload: Dictionary)


func _on_ready() -> void:
	Switchboard_auto.add_node_broadcaster(self, &"setup_complete")


func _on_initialize() -> void:
	pass


func _on_cleanup() -> void:
	Switchboard_auto.remove_node_broadcaster(self, &"setup_complete")


func _process_system(_delta: float) -> void:
	pass


func handle_event(_event_name: String, _payload: Dictionary = {}) -> bool:
	return true


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Run the full setup sequence. Called once by SetupScene after the player
## has chosen their hero and opponent count.
##
## chosen_hero_kind_id — HeroKindTable constant for the human player's hero.
## total_players       — 1 (human) + N (AI opponents).
## skin_material_path  — resource path of the randomly chosen skin material.
## hair_material_path  — resource path of the randomly chosen hair material.
func run(chosen_hero_kind_id: int, _total_players: int,
skin_material_path: String, hair_material_path: String) -> void:
	var player_count: int = 1 # hardcoded for initial build
	# var player_count: int = total_players

	# ------------------------------------------------------------------
	# 1. Build and shuffle the pools (hero pool excludes the chosen hero)
	# ------------------------------------------------------------------
	var hero_pool:     Array = HeroKindTable.all_kinds()
	hero_pool.erase(chosen_hero_kind_id)
	hero_pool.shuffle()

	var sword_pool:    Array = MagicSwordTable.all_kinds();  sword_pool.shuffle()
	var monster_pool:  Array = MonsterKindTable.all_kinds(); monster_pool.shuffle()
	var jarl_pool:     Array = JarlKindTable.all_kinds();    jarl_pool.shuffle()
	var treasure_pool: Array = TreasureTable.all_kinds();    treasure_pool.shuffle()

	# ------------------------------------------------------------------
	# 2. Create human hero (chosen_hero_kind_id, tagged TAG_PLAYER)
	# ------------------------------------------------------------------
	var hero_kind_id: int = chosen_hero_kind_id
	var hero_id: String = SagaEntityManager_auto.create_hero(hero_kind_id, true)

	# Store the chosen palette on HeroComponent so any future system that
	# renders this hero (board piece, portrait) can apply the same colours.
	var hero_entity: Entity = SagaEntityManager_auto.get_entity_by_id(hero_id)
	var hero_comp: SagaHeroComponent = hero_entity.get_component("SagaHeroComponent") as SagaHeroComponent
	if hero_comp != null:
		hero_comp.skin_material_path = skin_material_path
		hero_comp.hair_material_path = hair_material_path

	# ------------------------------------------------------------------
	# 3. Create magic sword and equip via broadcast
	# ------------------------------------------------------------------
	var sword_kind_id: int = sword_pool.pop_front()
	var sword_id: String = SagaEntityManager_auto.create_magic_sword(sword_kind_id)
	var equipped: bool = broadcast_event("equip_item", {
		"entity_id": hero_id,
		"item_id":   sword_id,
		"slot":      EquipmentSlot.Enum.MAIN_HAND,
	})
	if not equipped:
		push_error("SagaSetupSystem.run: failed to equip sword %s on hero %s" % [sword_id, hero_id])

	# ------------------------------------------------------------------
	# 4. Place monsters
	# ------------------------------------------------------------------
	var placed_monsters: Array[Dictionary] = []
	for i in player_count:
		var kind_id: int = monster_pool.pop_front()
		var monster_id: String = SagaEntityManager_auto.create_monster(kind_id)
		var monster_placed: bool = broadcast_event("place_entity", {
			"entity_id": monster_id,
			"random_land": true,
		})
		if not monster_placed:
			push_error("SagaSetupSystem.run: failed to place monster %s" % monster_id)
			continue
		var loc_id: String  = _get_entity_location(monster_id)
		placed_monsters.append({
			"name":          MonsterKindTable.get_monster(kind_id)["name"],
			"location_name": _land_name(loc_id),
		})

	# ------------------------------------------------------------------
	# 5. Place jarls
	# ------------------------------------------------------------------
	var placed_jarls: Array[Dictionary] = []
	for i in player_count:
		var kind_id: int = jarl_pool.pop_front()
		var jarl_id: String = SagaEntityManager_auto.create_jarl(kind_id)
		var jarl_placed: bool = broadcast_event("place_entity", {
			"entity_id":  jarl_id,
			"random_land": true,
		})
		if not jarl_placed:
			push_error("SagaSetupSystem.run: failed to place jarl %s" % jarl_id)
			continue
		var loc_id: String = _get_entity_location(jarl_id)
		placed_jarls.append({
			"name":          JarlKindTable.get_jarl(kind_id)["name"],
			"location_name": _land_name(loc_id),
		})

	# ------------------------------------------------------------------
	# 6. Place hero; record home country
	# ------------------------------------------------------------------
	var hero_placed: bool = broadcast_event("place_entity", {
		"entity_id":  hero_id,
		"random_land": true,
	})
	if not hero_placed:
		push_error("SagaSetupSystem.run: failed to place hero %s" % hero_id)

	var home_loc_id: String = _get_entity_location(hero_id)
	hero_comp.home_country = home_loc_id

	# ------------------------------------------------------------------
	# 7. luck already set to 3 by create_hero — nothing to do.
	# ------------------------------------------------------------------

	# ------------------------------------------------------------------
	# 8. Write remaining pools to SagaGameEngine
	# ------------------------------------------------------------------
	for kind_id: int in monster_pool:
		SagaGameEngine_auto.monster_pool.append(kind_id)
	for kind_id: int in jarl_pool:
		SagaGameEngine_auto.jarl_pool.append(kind_id)
	for kind_id: int in treasure_pool:
		SagaGameEngine_auto.treasure_pool.append(kind_id)

	# ------------------------------------------------------------------
	# 9. Emit setup_complete
	# ------------------------------------------------------------------
	var land_comp: SagaLandComponent = _get_land_component(home_loc_id)
	var sword_data: Dictionary = MagicSwordTable.get_sword(sword_kind_id)

	setup_complete.emit({
		"hero_name":         HeroKindTable.get_hero(hero_kind_id)["name"],
		"sword_name":        sword_data["name"],
		"sword_bonus":       sword_data["combat_bonus"],
		"home_country_name": land_comp.name if land_comp else "",
		"home_country_code": _location_code_string(land_comp),
		"monsters":          placed_monsters,
		"jarls":             placed_jarls,
	})


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _get_entity_location(entity_id: String) -> String:
	# Read the location back from BoardSystem via a query event rather than a
	# direct reference. BoardSystem stores this; we ask via broadcast.
	# For now we call get_system() as a read-only query — no state change.
	var board_sys: SagaBoardSystem = scene.get_registered_system(&"SagaBoardSystem") as SagaBoardSystem
	if board_sys == null:
		return ""
	return board_sys.get_location_of(entity_id)


func _land_name(loc_id: String) -> String:
	var comp: SagaLandComponent = _get_land_component(loc_id)
	return comp.name if comp else loc_id


func _get_land_component(loc_id: String) -> SagaLandComponent:
	var entity: Entity = SagaEntityManager_auto.get_entity_by_id(loc_id)
	if entity == null:
		return null
	return entity.get_component("SagaLandComponent") as SagaLandComponent


func _location_code_string(land_comp: SagaLandComponent) -> String:
	if land_comp == null or land_comp.location == null:
		return ""
	return "%d:%d" % [land_comp.location.x, land_comp.location.y]
