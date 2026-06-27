# saga/data/treasure_table.gd
class_name TreasureTable

const BROSUNG_NECKLACE = 0
const FREY_FAXI        = 1
const MAGIC_SHIRT      = 2
const MAIL_COAT        = 3

# Stat modifiers are 0 where the treasure has no passive bonus.
# ability: String identifier for the relevant system to key on.
# Frey Faxi's use_limit is tracked at runtime on the item entity, not here.
const TABLE: Dictionary = {
	BROSUNG_NECKLACE: {
		"name": "Brosung Necklace",
		"combat_bonus_attack":  0,
		"combat_bonus_defense": 0,
		"movement_bonus":       0,
		"ability": "trade_with_dragons",
	},
	FREY_FAXI: {
		"name": "Frey Faxi",
		"combat_bonus_attack":  0,
		"combat_bonus_defense": 0,
		"movement_bonus":       0,
		"ability": "double_speed",
	},
	MAGIC_SHIRT: {
		"name": "Magic Shirt",
		"combat_bonus_attack":  0,
		"combat_bonus_defense": 1,
		"movement_bonus":       1,
		"ability": "defense_bonus",
	},
	MAIL_COAT: {
		"name": "Mail Coat",
		"combat_bonus_attack":  0,
		"combat_bonus_defense": 2,
		"movement_bonus":       0,
		"ability": "defense_bonus",
	},
}

static func get_treasure(kind: int) -> Dictionary:
	return TABLE[kind]

static func has_ability(kind: int) -> bool:
	return TABLE[kind]["ability"] != ""

static func all_kinds() -> Array:
	return TABLE.keys()