# Enums.gd
# Autoload: add to Project > Project Settings > Autoload as "Enums"
# All shared enums and value types for SAGA: Age of Heroes.
# Pure data — no methods, no logic.
class_name Enums
extends Resource


# ---------------------------------------------------------------------------
# Entity classification
# ---------------------------------------------------------------------------

enum EntityType {
	HERO = 1 << 0,
	JARL = 1 << 3,
	MONSTER = 1 << 1,
	LAND = 1 << 4,
}


# ---------------------------------------------------------------------------
# Monster instance state
# ---------------------------------------------------------------------------

enum MonsterStatus {
	ACTIVE,
	WOUNDED,
	SLAIN,
}


# ---------------------------------------------------------------------------
# Rune types (stubbed — variants to be defined in a later phase)
# ---------------------------------------------------------------------------

enum RuneType {
	RUNE_A,
	RUNE_B,
	RUNE_C,
	RUNE_D,
	RUNE_E,
	RUNE_F,
}


# ---------------------------------------------------------------------------
# LocationCode — value type for grid coordinates
# x and y are each constrained to 1–6 by convention; enforcement is the
# responsibility of the system that writes this value.
# ---------------------------------------------------------------------------

class LocationCode:
	var x: int
	var y: int

	func _init(p_x: int, p_y: int) -> void:
		x = p_x
		y = p_y