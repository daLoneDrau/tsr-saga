# saga_map_marker_component.gd
# Tracks which specific 3D spawn-point marker (a named empty in
# saga_map.glb, e.g. "spawn_4_2_Armorica_face17") an entity is currently
# pinned to on the map widget, so it renders at a stable position across
# repeated _refresh() calls instead of re-picking a candidate point every
# time (regions can have anywhere from ~18 to 200+ candidate face/corner
# points — see the map widget roadmap, Phase 3).
# Managed by: SagaMapMarkerSystem
# Pure data — no methods.

class_name SagaMapMarkerComponent
extends EntityComponent


## Exact glb node name this entity is currently assigned to, e.g.
## "spawn_4_2_Armorica_face17". Empty string ("") means unassigned.
var marker_node_name: String = ""

## The region_id (map.json key, e.g. "4_2_Armorica") this assignment
## belongs to. Compared against the entity's current board location each
## refresh to detect "did this entity move to a different region" without
## needing to re-derive it from marker_node_name via string parsing.
var region_id: String = ""
