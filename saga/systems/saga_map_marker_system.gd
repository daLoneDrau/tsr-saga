# saga_map_marker_system.gd
# Owns stable assignment of entities to specific 3D marker points on the
# map (see SagaMapMarkerComponent header). This system deliberately knows
# nothing about the 3D scene itself — it only ever receives/returns plain
# node-name strings supplied by the caller (map_preview.gd, which is the
# one thing that actually knows what candidate marker nodes exist in the
# loaded saga_map.glb). That split mirrors the boundary already drawn for
# map click-handling: game systems deal in abstract identifiers, the map
# widget resolves those into real 3D nodes.
#
# All reads and writes of SagaMapMarkerComponent go through this system.

class_name SagaMapMarkerSystem
extends GameSystem


func _on_ready() -> void:
	pass

func _on_cleanup() -> void:
	pass

func _on_initialize() -> void:
	pass

func _process_system(_delta: float) -> void:
	pass

func handle_event(_event_name: String, _payload: Dictionary = {}) -> bool:
	return true


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns the marker node name entity_id should render at within
## region_id, choosing from candidate_node_names.
##
## If the entity already has a stable assignment for this same region and
## that assignment is still a valid candidate, it's returned unchanged —
## this is what keeps an occupant from jumping between candidate points on
## every _refresh(). Otherwise a new one is picked, preferring names not
## already claimed by some other entity in the same region (so a hero and
## a jarl sharing a region don't render on top of each other), falling
## back to the full candidate list if every candidate is already taken
## (better to overlap visually than to render nothing).
##
## Returns "" if candidate_node_names is empty (nothing to assign).
func get_or_assign_marker(entity_id: String, region_id: String, candidate_node_names: Array) -> String:
	if candidate_node_names.is_empty():
		return ""

	var entity: Entity = SagaEntityManager_auto.get_entity_by_id(entity_id)
	if entity == null:
		return ""

	var comp := entity.get_component("SagaMapMarkerComponent", false) as SagaMapMarkerComponent
	if comp == null:
		comp = SagaMapMarkerComponent.new()
		entity.set_component(comp)

	if comp.region_id == region_id and comp.marker_node_name in candidate_node_names:
		return comp.marker_node_name

	var taken := _taken_marker_names(region_id, entity_id)
	var free_candidates: Array = candidate_node_names.filter(func(n): return not taken.has(n))
	var pool: Array = free_candidates if not free_candidates.is_empty() else candidate_node_names

	# Deterministic (not random) so the same entity+region always resolves
	# the same way if this ever needs to be recomputed — makes this
	# testable without needing to seed an RNG.
	var index: int = hash(entity_id) % pool.size()
	var chosen: String = pool[index]

	comp.region_id = region_id
	comp.marker_node_name = chosen
	return chosen


## Clears entity_id's marker assignment, e.g. when it's removed from the
## board entirely (killed, etc.) so a stale assignment can't linger and
## block that marker point from being handed to someone else. Safe to
## call even if the entity has no assignment yet.
func release_marker(entity_id: String) -> void:
	var entity: Entity = SagaEntityManager_auto.get_entity_by_id(entity_id)
	if entity == null:
		return
	var comp := entity.get_component("SagaMapMarkerComponent", false) as SagaMapMarkerComponent
	if comp != null:
		comp.region_id = ""
		comp.marker_node_name = ""


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Returns the set of marker_node_names already claimed by other entities
## (excluding exclude_entity_id) within region_id.
func _taken_marker_names(region_id: String, exclude_entity_id: String) -> Dictionary:
	var taken: Dictionary = {}
	var entities: Array[Entity] = get_entities_with_component("SagaMapMarkerComponent")
	for entity in entities:
		if entity.id == exclude_entity_id:
			continue
		var comp := entity.get_component("SagaMapMarkerComponent", false) as SagaMapMarkerComponent
		if comp != null and comp.region_id == region_id and comp.marker_node_name != "":
			taken[comp.marker_node_name] = true
	return taken
