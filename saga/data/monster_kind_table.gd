# saga/data/monster_kind_table.gd
class_name MonsterKindTable

# Monster type constants
const TYPE_DRAGON = 0
const TYPE_DROW   = 1
const TYPE_GHOST  = 2
const TYPE_GIANT  = 3
const TYPE_TROLL  = 4
const TYPE_WITCH  = 5

# Per-type glory, luck rewards, and shared model
const TYPE_DATA: Dictionary = {
	TYPE_DRAGON: { "glory": 6, "luck": 5, "model": "res://assets/models/monsters/dragon.glb" },
	TYPE_DROW:   { "glory": 3, "luck": 2, "model": "res://assets/models/monsters/drow.glb" },
	TYPE_GHOST:  { "glory": 2, "luck": 2, "model": "res://assets/models/monsters/ghost.glb" },
	TYPE_GIANT:  { "glory": 4, "luck": 3, "model": "res://assets/models/monsters/giant.glb" },
	TYPE_TROLL:  { "glory": 3, "luck": 3, "model": "res://assets/models/monsters/troll.glb" },
	TYPE_WITCH:  { "glory": 5, "luck": 4, "model": "res://assets/models/monsters/witch.glb" },
}

# Individual monster kind IDs
const STIGANDI        = 0
const FAFNIR          = 1
const GLERION         = 2
const HALLBJORN_DRAGON = 3
const ALUDRENG        = 4
const ISTVAN          = 5
const HALLGERD        = 6
const GIZUR           = 7
const ALTI            = 8
const GIZAR           = 9
const GLAM            = 10
const MORD            = 11
const TROGRIER        = 12
const HRAP            = 13
const GUNNAR          = 14
const STORVICK        = 15
const ANGANTYR        = 16
const HALL            = 17
const GRENDALL        = 18
const HOGSHEAD        = 19
const ONUND           = 20
const SVINAFELL       = 21
const HALLBJORN_TROLL = 22
const HAUK            = 23
const HEDIN           = 24
const GRUNNHILD       = 25
const GERDRAK         = 26

const TABLE: Dictionary = {
	# --- Dragons ---
	STIGANDI:         { "name": "Stigandi",  "type": TYPE_DRAGON, "combat_strength": 11, "movement_speed": 2 },
	FAFNIR:           { "name": "Fafnir",    "type": TYPE_DRAGON, "combat_strength": 11, "movement_speed": 2 },
	GLERION:          { "name": "Glerion",   "type": TYPE_DRAGON, "combat_strength": 10, "movement_speed": 2 },
	HALLBJORN_DRAGON: { "name": "Hallbjorn", "type": TYPE_DRAGON, "combat_strength": 10, "movement_speed": 2 },
	ALUDRENG:         { "name": "Aludreng",  "type": TYPE_DRAGON, "combat_strength": 10, "movement_speed": 1 },
	ISTVAN:           { "name": "Istvan",    "type": TYPE_DRAGON, "combat_strength":  9, "movement_speed": 3 },
	# --- Drow ---
	HALLGERD:         { "name": "Hallgerd",  "type": TYPE_DROW,   "combat_strength":  3, "movement_speed": 1 },
	GIZUR:            { "name": "Gizur",     "type": TYPE_DROW,   "combat_strength":  3, "movement_speed": 1 },
	ALTI:             { "name": "Alti",      "type": TYPE_DROW,   "combat_strength":  2, "movement_speed": 2 },
	# --- Ghosts ---
	GIZAR:            { "name": "Gizar",     "type": TYPE_GHOST,  "combat_strength":  4, "movement_speed": 2 },
	GLAM:             { "name": "Glam",      "type": TYPE_GHOST,  "combat_strength":  4, "movement_speed": 1 },
	MORD:             { "name": "Mord",      "type": TYPE_GHOST,  "combat_strength":  4, "movement_speed": 1 },
	TROGRIER:         { "name": "Trogrier",  "type": TYPE_GHOST,  "combat_strength":  4, "movement_speed": 1 },
	HRAP:             { "name": "Hrap",      "type": TYPE_GHOST,  "combat_strength":  4, "movement_speed": 0 },
	GUNNAR:           { "name": "Gunnar",    "type": TYPE_GHOST,  "combat_strength":  4, "movement_speed": 0 },
	# --- Giants ---
	STORVICK:         { "name": "Storvick",  "type": TYPE_GIANT,  "combat_strength":  8, "movement_speed": 1 },
	ANGANTYR:         { "name": "Angantyr",  "type": TYPE_GIANT,  "combat_strength":  7, "movement_speed": 0 },
	HALL:             { "name": "Hall",      "type": TYPE_GIANT,  "combat_strength":  6, "movement_speed": 1 },
	# --- Trolls ---
	GRENDALL:         { "name": "Grendall",  "type": TYPE_TROLL,  "combat_strength":  6, "movement_speed": 2 },
	HOGSHEAD:         { "name": "Hogshead",  "type": TYPE_TROLL,  "combat_strength":  6, "movement_speed": 1 },
	ONUND:            { "name": "Onund",     "type": TYPE_TROLL,  "combat_strength":  5, "movement_speed": 3 },
	SVINAFELL:        { "name": "Svinafell", "type": TYPE_TROLL,  "combat_strength":  5, "movement_speed": 2 },
	HALLBJORN_TROLL:  { "name": "Hallbjorn", "type": TYPE_TROLL,  "combat_strength":  5, "movement_speed": 2 },
	HAUK:             { "name": "Hauk",      "type": TYPE_TROLL,  "combat_strength":  5, "movement_speed": 1 },
	# --- Witches ---
	HEDIN:            { "name": "Hedin",     "type": TYPE_WITCH,  "combat_strength":  4, "movement_speed": 4 },
	GRUNNHILD:        { "name": "Grunnhild", "type": TYPE_WITCH,  "combat_strength":  3, "movement_speed": 5 },
	GERDRAK:          { "name": "Gerdrak",   "type": TYPE_WITCH,  "combat_strength":  3, "movement_speed": 4 },
}

static func get_monster(kind: int) -> Dictionary:
	return TABLE[kind]

static func get_type_data(kind: int) -> Dictionary:
	return TYPE_DATA[TABLE[kind]["type"]]

static func get_model(kind: int) -> String:
	return TYPE_DATA[TABLE[kind]["type"]]["model"]

static func all_kinds() -> Array:
	return TABLE.keys()

static func kinds_of_type(type: int) -> Array:
	return TABLE.keys().filter(func(k): return TABLE[k]["type"] == type)
