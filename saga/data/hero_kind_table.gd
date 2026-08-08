# saga/data/hero_kind_table.gd
class_name HeroKindTable

const BEOWULF   = 0
const EGIL      = 1
const BRUNHILD  = 2
const SIEGFRIED = 3
const STARKAD   = 4
const RAGNAR    = 5

const TABLE: Dictionary = {
	BEOWULF: {
		"name": "Beowulf",
		"combat_strength": 5,
		"movement_speed": 4,
		"model": "res://assets/art/models/heroes/beowulf/beowulf.tscn",
	},
	EGIL: {
		"name": "Egil",
		"combat_strength": 5,
		"movement_speed": 4,
		"model": "res://assets/art/models/heroes/egil/egil.tscn",
	},
	BRUNHILD: {
		"name": "Brunhild",
		"combat_strength": 5,
		"movement_speed": 4,
		"model": "res://assets/art/models/heroes/brunhild/brunhild.tscn",
	},
	SIEGFRIED: {
		"name": "Siegfried",
		"combat_strength": 5,
		"movement_speed": 4,
		"model": "res://assets/art/models/heroes/siegfried/siegfried.tscn",
	},
	STARKAD: {
		"name": "Starkad",
		"combat_strength": 5,
		"movement_speed": 4,
		"model": "res://assets/art/models/heroes/starkad/starkad.tscn",
	},
	RAGNAR: {
		"name": "Ragnar",
		"combat_strength": 5,
		"movement_speed": 4,
		"model": "res://assets/art/models/heroes/ragnar/ragnar.tscn",
	},
}

static func get_hero(kind: int) -> Dictionary:
	return TABLE[kind]

static func all_kinds() -> Array:
	return TABLE.keys()