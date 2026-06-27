# saga/data/jarl_kind_table.gd
class_name JarlKindTable

# Shared model — palette assigned randomly at spawn time
const MODEL: String = "res://assets/models/jarls/jarl.glb"

# Individual jarl kind IDs
const KARI       = 0
const IVAR       = 1
const HROLFWULF  = 2
const BJARKL     = 3
const WELLAND    = 4
const WIGLAR     = 5
const ERIK       = 6
const THOROLF    = 7
const GRETTER    = 8
const HARALD     = 9
const AMLETH     = 10
const THORVALD   = 11
const HELGI      = 12
const SKALLAGRIM = 13
const HENGIST    = 14
const HAGEN      = 15
const EYJOLF     = 16
const HORSA      = 17

const TABLE: Dictionary = {
	KARI:       { "name": "Kari",       "combat_strength": 4, "movement_speed": 3 },
	IVAR:       { "name": "Ivar",       "combat_strength": 4, "movement_speed": 2 },
	HROLFWULF:  { "name": "Hrolfwulf",  "combat_strength": 4, "movement_speed": 2 },
	BJARKL:     { "name": "Bjarkl",     "combat_strength": 3, "movement_speed": 3 },
	WELLAND:    { "name": "Welland",    "combat_strength": 3, "movement_speed": 3 },
	WIGLAR:     { "name": "Wiglar",     "combat_strength": 3, "movement_speed": 3 },
	ERIK:       { "name": "Erik",       "combat_strength": 3, "movement_speed": 3 },
	THOROLF:    { "name": "Thorolf",    "combat_strength": 3, "movement_speed": 3 },
	GRETTER:    { "name": "Gretter",    "combat_strength": 3, "movement_speed": 2 },
	HARALD:     { "name": "Harald",     "combat_strength": 2, "movement_speed": 3 },
	AMLETH:     { "name": "Amleth",     "combat_strength": 2, "movement_speed": 3 },
	THORVALD:   { "name": "Thorvald",   "combat_strength": 2, "movement_speed": 3 },
	HELGI:      { "name": "Helgi",      "combat_strength": 2, "movement_speed": 3 },
	SKALLAGRIM: { "name": "Skallagrim", "combat_strength": 2, "movement_speed": 3 },
	HENGIST:    { "name": "Hengist",    "combat_strength": 2, "movement_speed": 2 },
	HAGEN:      { "name": "Hagen",      "combat_strength": 2, "movement_speed": 2 },
	EYJOLF:     { "name": "Eyjolf",     "combat_strength": 2, "movement_speed": 2 },
	HORSA:      { "name": "Horsa",      "combat_strength": 2, "movement_speed": 2 },
}

# Rewards are derived at runtime from combat_strength by CombatSystem.
# After defeating a jarl the player chooses glory or luck — not stored here.

static func get_jarl(kind: int) -> Dictionary:
	return TABLE[kind]

static func all_kinds() -> Array:
	return TABLE.keys()