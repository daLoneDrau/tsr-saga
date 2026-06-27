# saga_sea_component.gd
# Marker component for a sea location entity.
# All sea locations are equivalent in data — the only meaningful fact
# about a sea entity is that it has this component.
# Neighbor relationships are defined in the map table (added in the play phase).
# Managed by: BoardSystem
# Pure data — no methods.

class_name SagaSeaComponent
extends EntityComponent


# All sea locations share the same name. Set at definition, never changes.
var name: String = "At Sea"
