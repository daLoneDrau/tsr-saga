# saga_board_system.gd
# Owns the authoritative mapping of entity IDs to board location entity IDs.
# Board locations are themselves entities — land locations have SagaLandComponent,
# sea locations have SagaSeaComponent. Any number of entities may share a location.
#
# All reads and writes to board location state must go through this system.
# CombatSystem, MovementSystem, and SetupSystem never hold location state directly.
#
# Internal structure:
#   _grid: Dictionary      location_entity_id -> Array[String occupant_entity_id]  (primary index)
#   _locations: Dictionary occupant_entity_id -> String location_entity_id         (reverse index, read-only shadow)
#
# _locations is never written directly. All writes to either dictionary go
# through _add_to_grid and _remove_from_grid, which keep both in sync atomically.

class_name SagaBoardSystem
extends GameSystem


# ---------------------------------------------------------------------------
# Internal storage
# ---------------------------------------------------------------------------

# Primary index: location_entity_id -> Array[String occupant_entity_id]
var _grid: Dictionary = {}

# Reverse index (read-only shadow): occupant_entity_id -> location_entity_id
# Never write to this directly. Use _add_to_grid / _remove_from_grid only.
var _locations: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _on_ready() -> void:
	pass

func _on_cleanup() -> void:
	clear()

func _on_initialize() -> void:
	pass

func _process_system(_delta: float) -> void:
	pass

func handle_event(_event_name: String, _payload: Dictionary = {}) -> void:
	pass


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Place entity_id at location_entity_id. If the entity is already on the
## board, it is removed from its current location first.
func place_entity(entity_id: String, location_entity_id: String) -> void:
	if entity_id == "" or location_entity_id == "":
		push_error("SagaBoardSystem.place_entity: invalid arguments")
		return
	if _locations.has(entity_id):
		_remove_from_grid(entity_id, _locations[entity_id])
	_add_to_grid(entity_id, location_entity_id)


## Remove entity_id from the board entirely.
## Safe to call if the entity is not currently on the board.
func remove_entity(entity_id: String) -> void:
	if not _locations.has(entity_id):
		return
	_remove_from_grid(entity_id, _locations[entity_id])


## Move entity_id to a new location. Equivalent to remove + place.
func move_entity(entity_id: String, location_entity_id: String) -> void:
	place_entity(entity_id, location_entity_id)


## Returns an Array of occupant entity_id Strings at the given location.
## Returns an empty Array if nothing is there — never null.
func get_entities_at(location_entity_id: String) -> Array:
	if location_entity_id == "":
		return []
	if not _grid.has(location_entity_id):
		return []
	return _grid[location_entity_id].duplicate()


## Returns the location entity_id for the given occupant, or "" if not on board.
func get_location_of(entity_id: String) -> String:
	return _locations.get(entity_id, "")


## Returns true if entity_id is currently on the board.
func is_on_board(entity_id: String) -> bool:
	return _locations.has(entity_id)


## Returns a random land location entity ID.
## All random placement of monsters, jarls, heroes, and treasure goes through
## here so the land-only constraint is enforced in one place.
func random_land_location() -> String:
	var land_entities: Array = SagaEntityManager_auto.get_entities_by_tag(SagaEntityManager.TAG_LAND)
	if land_entities.is_empty():
		push_error("SagaBoardSystem.random_land_location: no land location entities found")
		return ""
	return land_entities[randi_range(0, land_entities.size() - 1)].id


## Wipe all placement data.
func clear() -> void:
	_grid.clear()
	_locations.clear()


# ---------------------------------------------------------------------------
# Internal helpers — the only place either dictionary is written
# ---------------------------------------------------------------------------

func _add_to_grid(entity_id: String, location_entity_id: String) -> void:
	if not _grid.has(location_entity_id):
		_grid[location_entity_id] = []
	_grid[location_entity_id].append(entity_id)
	_locations[entity_id] = location_entity_id


func _remove_from_grid(entity_id: String, location_entity_id: String) -> void:
	if _grid.has(location_entity_id):
		_grid[location_entity_id].erase(entity_id)
		if _grid[location_entity_id].is_empty():
			_grid.erase(location_entity_id)
	_locations.erase(entity_id)
