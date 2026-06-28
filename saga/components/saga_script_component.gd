# saga_script_component.gd
# Thin subclass of ScriptComponent for Saga entities.
# ScriptSystem auto-attaches and detaches scripts when entities are added/removed.
# Set main_script to the appropriate EntityScript subclass in SagaEntityManager.

class_name SagaScriptComponent
extends ScriptComponent
