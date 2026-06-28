# saga_equipment_system.gd
# Concrete implementation of EquipmentSystem for Saga.
# Saga has no slot restrictions beyond what EquipmentComponent.allowed_slots
# enforces, and no set bonuses, so both abstract methods are trivially
# implemented.
#
# Listens for:
#   "equip_item"   payload: { entity_id: String, item_id: String, slot: int }
#   "unequip_item" payload: { entity_id: String, slot: int }

class_name SagaEquipmentSystem
extends EquipmentSystem


func _on_ready() -> void:
	_entity_manager = SagaEntityManager_auto


func _on_cleanup() -> void:
	pass


func _on_initialize() -> void:
	pass


func _process_system(_delta: float) -> void:
	pass


func handle_event(event_name: String, payload: Dictionary = {}) -> bool:
	match event_name:
		"equip_item":
			return equip(payload["entity_id"], payload["item_id"], payload.get("slot", -1))
		"unequip_item":
			return unequip(payload["entity_id"], payload["slot"])
	return true


# All sword→MAIN_HAND assignments are valid in Saga — no proficiency or
# subtype restrictions exist.
func _slot_accepts_item(_entity_id: StringName, _slot: int, _item_id: StringName, _reasons: Array[String]) -> bool:
	return true


# Saga has no set-bonus mechanic.
func _find_any_set_bonuses(_set_id: StringName) -> Array:
	return []
