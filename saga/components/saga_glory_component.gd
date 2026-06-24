# saga_glory_component.gd
# Tracks a single entity's accumulated glory.
# Managed by: saga_glory_system
# Pure data — no methods.

class_name SagaGloryComponent
extends EntityComponent


# Current glory total. Floor of 0; never goes negative.
# Set and maintained exclusively by GlorySystem.
var current: int = 0

# The entity responsible for the most recent glory change.
# Always set when current is non-zero; GlorySystem must populate this
# on every write — it is never left stale.
var source_entity: SagaEntity = null