# saga/data/magic_sword_table.gd
class_name MagicSwordTable

const BALMUNG    = 0
const HRUNTING   = 1
const LOVI       = 2
const DRAGVENDILL = 3
const GRAM       = 4
const TYRFING    = 5

# ability: String identifier for CombatSystem to key on. "" means no special ability.
const TABLE: Dictionary = {
	BALMUNG:     { "name": "Balmung",     "combat_bonus": 1, "ability": "cancel_magic_armor" },
	HRUNTING:    { "name": "Hrunting",    "combat_bonus": 1, "ability": "alter_combat_result" },
	LOVI:        { "name": "Lovi",        "combat_bonus": 1, "ability": "jarl_slayer" },
	DRAGVENDILL: { "name": "Dragvendill", "combat_bonus": 2, "ability": "" },
	GRAM:        { "name": "Gram",        "combat_bonus": 2, "ability": "" },
	TYRFING:     { "name": "Tyrfing",     "combat_bonus": 2, "ability": "" },
}

static func get_sword(kind: int) -> Dictionary:
	return TABLE[kind]

static func has_ability(kind: int) -> bool:
	return TABLE[kind]["ability"] != ""

static func all_kinds() -> Array:
	return TABLE.keys()