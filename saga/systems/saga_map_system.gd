# saga_map_system.gd
# Loads the hand-authored map graph (res://saga/data/map.json) and creates one
# land or sea entity per region. Owns the adjacency graph — this is distinct
# from SagaBoardSystem, which only tracks which entities currently occupy
# which locations. SagaMapSystem answers "what connects to what"; SagaBoardSystem
# answers "who is standing where right now."
#
# Adjacency is fully hand-authored in the source data (not derived from x/y —
# the x/y on a land region is display/LocationCode metadata only). Sea regions
# have no coordinates at all, matching SagaSeaComponent.
#
# Region IDs in map.json (e.g. "1_1_Finmark", "06") are load-time keys only.
# Once loaded, everything else in the engine addresses locations by entity ID,
# the same as every other entity. Use get_entity_for_region_id() only if you
# need to resolve a raw map-data key (rare — mainly debugging/tests).
#
# Managed by: SagaMapSystem exclusively. Other systems (SagaMovementSystem,
# SagaBoardSystem, future SagaCombatSystem/SagaKingdomSystem) read adjacency
# through the public API below and never parse map.json themselves.
#
# This system is registered fresh in every scene that needs it (SetupScene —
# so random land placement has entities to place onto — and GameScene).
# Godot destroys the old scene's node instances on change_scene_to_file, so
# _region_id_to_entity_id / _entity_id_to_region_id / _adjacency / _is_land
# are aliased (not copied) to SagaGameEngine_auto's map_* fields in
# _on_initialize(). load_map() only actually parses the file and creates
# entities the first time (guarded by SagaGameEngine_auto.map_loaded) — a
# later scene's SagaMapSystem instance just inherits the already-built graph.
# _on_cleanup() deliberately does not clear this data.
#
# Listens for: nothing yet. Loading happens once, during _on_initialize.

class_name SagaMapSystem
extends GameSystem


const MAP_DATA_PATH: String = "res://saga/data/map.json"


# ---------------------------------------------------------------------------
# Internal storage — aliased to SagaGameEngine_auto in _on_initialize(), not
# owned locally. See header comment.
# ---------------------------------------------------------------------------

# region_id (map.json key) -> entity_id
var _region_id_to_entity_id: Dictionary = {}

# entity_id -> region_id (reverse lookup, debugging/tests only)
var _entity_id_to_region_id: Dictionary = {}

# entity_id -> Array[String entity_id] of adjacent locations (land or sea)
var _adjacency: Dictionary = {}

# entity_id -> true for land regions, absent/false for sea
var _is_land: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _on_ready() -> void:
	pass

func _on_cleanup() -> void:
	# Deliberately does not clear the aliased dicts — see header comment.
	pass

func _on_initialize() -> void:
	_region_id_to_entity_id = SagaGameEngine_auto.map_region_id_to_entity_id
	_entity_id_to_region_id = SagaGameEngine_auto.map_entity_id_to_region_id
	_adjacency = SagaGameEngine_auto.map_adjacency
	_is_land = SagaGameEngine_auto.map_is_land
	if not SagaGameEngine_auto.map_loaded:
		load_map(MAP_DATA_PATH)

func _process_system(_delta: float) -> void:
	pass

func handle_event(_event_name: String, _payload: Dictionary = {}) -> bool:
	return true


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

## Loads and parses map.json, creating one land or sea entity per region.
## Safe to call only once across the whole game (guarded by
## SagaGameEngine_auto.map_loaded) — subsequent calls, even from a fresh
## scene's SagaMapSystem instance, are ignored with a warning.
func load_map(path: String) -> bool:
	if SagaGameEngine_auto.map_loaded:
		push_warning("SagaMapSystem.load_map: map already loaded, ignoring")
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SagaMapSystem.load_map: failed to open %s" % path)
		return false

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed.has("regions"):
		push_error("SagaMapSystem.load_map: malformed map data at %s" % path)
		return false

	var regions: Dictionary = parsed["regions"]

	# Pass 1: create an entity for every region, recording region_id <-> entity_id.
	for region_id: String in regions.keys():
		var info: Dictionary = regions[region_id]
		var entity_id: String
		if info.get("type", "") == "land":
			entity_id = SagaEntityManager_auto.create_land(
				info.get("name", region_id),
				int(info.get("x", 0)),
				int(info.get("y", 0)),
				int(info.get("tax_value", 0))
			)
			_is_land[entity_id] = true
		else:
			entity_id = SagaEntityManager_auto.create_sea()
			_is_land[entity_id] = false

		_region_id_to_entity_id[region_id] = entity_id
		_entity_id_to_region_id[entity_id] = region_id

	# Pass 2: translate neighbor lists (region_id) into adjacency (entity_id).
	# Two passes are required since a region's neighbors may not have been
	# created yet when the region itself is processed in pass 1.
	for region_id: String in regions.keys():
		var info: Dictionary = regions[region_id]
		var entity_id: String = _region_id_to_entity_id[region_id]
		var neighbor_entity_ids: Array = []
		for neighbor_region_id in info.get("neighbors", []):
			if _region_id_to_entity_id.has(neighbor_region_id):
				neighbor_entity_ids.append(_region_id_to_entity_id[neighbor_region_id])
			else:
				push_warning("SagaMapSystem.load_map: %s references unknown neighbor %s" % [region_id, neighbor_region_id])
		_adjacency[entity_id] = neighbor_entity_ids

	SagaGameEngine_auto.map_loaded = true
	return true


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns the Array[String entity_id] of locations directly adjacent to
## location_entity_id. Returns an empty Array if the location is unknown.
func get_neighbors(location_entity_id: String) -> Array:
	return _adjacency.get(location_entity_id, []).duplicate()

## Returns every location entity_id reachable from origin_entity_id within
## max_edges hops (inclusive), NOT including origin_entity_id itself.
## Unweighted BFS — every edge costs exactly 1, matching the "free movement,
## cannot be interrupted" rule, so shortest hop-count is all that matters.
func get_reachable(origin_entity_id: String, max_edges: int) -> Array:
	if max_edges <= 0 or not _adjacency.has(origin_entity_id):
		return []

	var distances: Dictionary = {origin_entity_id: 0}
	var queue: Array = [origin_entity_id]
	var reachable: Array = []

	while not queue.is_empty():
		var current: String = queue.pop_front()
		var current_dist: int = distances[current]
		if current_dist >= max_edges:
			continue
		for neighbor in _adjacency.get(current, []):
			if not distances.has(neighbor):
				distances[neighbor] = current_dist + 1
				reachable.append(neighbor)
				queue.append(neighbor)

	return reachable

## Returns true if location_entity_id is a land region, false if sea or unknown.
func is_land(location_entity_id: String) -> bool:
	return _is_land.get(location_entity_id, false)

## Returns true if location_entity_id is a sea region.
func is_sea(location_entity_id: String) -> bool:
	return _adjacency.has(location_entity_id) and not _is_land.get(location_entity_id, false)

## Resolves a raw map.json region_id (e.g. "1_1_Finmark") to its entity_id.
## Mainly useful for debugging/tests — gameplay code should already be
## working in entity IDs.
func get_entity_for_region_id(region_id: String) -> String:
	return _region_id_to_entity_id.get(region_id, "")

## Resolves an entity_id back to its raw map.json region_id.
## Mainly useful for debugging/tests.
func get_region_id_for_entity(location_entity_id: String) -> String:
	return _entity_id_to_region_id.get(location_entity_id, "")

## Returns every land location entity_id.
func all_land_entity_ids() -> Array:
	var out: Array = []
	for id in _is_land:
		if _is_land[id]:
			out.append(id)
	return out

## Returns every sea location entity_id.
func all_sea_entity_ids() -> Array:
	var out: Array = []
	for id in _is_land:
		if not _is_land[id]:
			out.append(id)
	return out

## True once load_map() has successfully completed (persists across scenes).
func is_loaded() -> bool:
	return SagaGameEngine_auto.map_loaded
