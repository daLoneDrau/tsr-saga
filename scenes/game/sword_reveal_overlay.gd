# SwordRevealOverlay.gd
# Controller for the Magic Sword Reveal overlay (5.2.33 — "each randomly
# assigned Magic Sword is explicitly revealed and acknowledged" between
# Hero Selection and the Strategic Board opening).
#
# NOT a Scene — this is a plain Control meant to be instanced as a child
# of GameScene, layered on top of BoardSpace, and shown from the moment
# GameScene first loads. The board is already there underneath (matching
# 5.2.33's "the Strategic Board then opens directly..." — it's already
# open, this just sits above it briefly), dimmed by a scrim while this is
# up. Dismissal is a signal, not a scene change — GameScene owns freeing
# this node once the player acknowledges.
#
# Self-contained data-wise: rather than requiring a payload from whoever
# instances it, this reads the player hero's already-equipped sword
# straight from persisted ECS state (SagaEntityManager_auto) on _ready() —
# the same pattern game_scene.gd's old _sword_display_text() used.
# SagaSetupSystem.run() has already created and equipped the sword by the
# time GameScene loads, so the data is simply sitting there to be read.
#
# Content hierarchy (per design): Hero -> Sword identity -> Sword visual ->
# concise effect/rules information. The sword visual is the dominant
# element in the card; no rarity glow, spin, particle burst, or
# "LEGENDARY!" treatment — a calm, static reveal, acknowledged by a single
# CONTINUE button (not a timer or auto-advance).
#
# PLACEHOLDER NOTE: no real per-sword artwork exists yet ("the adaptation's
# representation of the original counter/artwork"). %SwordSilhouette is a
# plain geometric placeholder (see SwordRevealOverlay.tscn) standing in
# for that art. Swapping in real art later means replacing that one node
# with a TextureRect — nothing in this script needs to change.

class_name SwordRevealOverlay
extends Control

## Emitted when the player clicks CONTINUE. GameScene listens for this and
## frees the overlay — this node never removes itself.
signal acknowledged

@onready var _hero_line: Label = %HeroLine
@onready var _sword_name_label: RichTextLabel = %SwordNameLabel
@onready var _rules_text_label: Label = %RulesTextLabel
@onready var _continue_button: Button = %ContinueButton

var _sword_kind_id: int = -1


func _ready() -> void:
	_continue_button.pressed.connect(_on_continue_pressed)
	_populate_reveal()


# ---------------------------------------------------------------------------
# Reveal content
# ---------------------------------------------------------------------------

func _populate_reveal() -> void:
	var hero := _get_player_hero()
	if hero == null:
		push_error("SwordRevealOverlay: no player hero found — was SagaSetupSystem.run() called before GameScene loaded?")
		return

	var hero_name := _entity_display_name(hero.id)
	_hero_line.text = "%s has been granted..." % hero_name

	var equip_comp: SagaEquipmentComponent = hero.get_component("EquipmentComponent", false) as SagaEquipmentComponent
	var sword_id: String = equip_comp.slots.get(EquipmentSlot.Enum.MAIN_HAND, "") if equip_comp else ""
	if sword_id == "":
		push_error("SwordRevealOverlay: player hero has no sword equipped.")
		return

	var sword_entity: Entity = SagaEntityManager_auto.get_entity_by_id(sword_id)
	if sword_entity == null:
		push_error("SwordRevealOverlay: equipped sword entity '%s' not found." % sword_id)
		return

	var sword_comp: SagaMagicSwordComponent = sword_entity.get_component("SagaMagicSwordComponent", false) as SagaMagicSwordComponent
	if sword_comp == null:
		push_error("SwordRevealOverlay: equipped item has no SagaMagicSwordComponent.")
		return

	_sword_kind_id = sword_comp.kind_id
	var sword_data: Dictionary = MagicSwordTable.get_sword(_sword_kind_id)

	_sword_name_label.text = "[color=#59442d]—◇—[/color] [color=#211d18]%s[/color] [color=#59442d]—◇—[/color]" % String(sword_data["name"]).to_upper()

	var bonus_line := "+%d combat strength" % int(sword_data["combat_bonus"])
	_rules_text_label.text = "%s\n%s" % [bonus_line, String(sword_data["rules_text"])]


func _get_player_hero() -> Entity:
	var players: Array = SagaEntityManager_auto.get_entities_by_tag(SagaEntityManager.TAG_PLAYER)
	return players[0] if not players.is_empty() else null


func _entity_display_name(entity_id: String) -> String:
	var entity: Entity = SagaEntityManager_auto.get_entity_by_id(entity_id)
	if entity == null:
		return entity_id
	var name_comp: NameComponent = entity.get_component("NameComponent", false) as NameComponent
	if name_comp and name_comp.has_name():
		return name_comp.get_display_name()
	return entity_id


# ---------------------------------------------------------------------------
# Acknowledgment
# ---------------------------------------------------------------------------

## The explicit "acknowledged" step 5.2.33 requires — a real click, not a
## timer or auto-advance. This node does not free itself; GameScene owns
## that, matching the "GameScene decides what's on screen" pattern the
## rest of this rebuild uses.
func _on_continue_pressed() -> void:
	acknowledged.emit()