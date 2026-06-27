# saga_equipment_component.gd
# Thin subclass of EquipmentComponent scoped to Saga's single-slot loadout.
# Heroes and jarls each carry at most one magic sword, held in MAIN_HAND.
# All equipment logic (equip, unequip, trade, drop on death) is handled by CombatSystem.
# Pure data — no methods beyond initialization.

class_name SagaEquipmentComponent
extends EquipmentComponent


func _init() -> void:
	allowed_slots = [&"MAIN_HAND"]
	slots = { EquipmentSlot.Enum.MAIN_HAND: "" }
