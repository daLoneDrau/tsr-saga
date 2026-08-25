# GameScene.gd
# Minimal controller for the main game loop screen. Extends Scene —
# registered as the root script on GameScene.tscn.
#
# REBUILT as of the board/camera-first redesign pass. The previous
# version's surrounding UI — turn banner, mover/location card + Pass
# button, Hero Info popup, Region Close-Up modal, CRT scanline overlay —
# is being redesigned separately per the UI redesign doc and is
# deliberately NOT carried over here. This starts nearly bare: just the
# board rendering foundation (BoardSpace) plus the same system
# registration and movement-phase kickoff the old scene used, since none
# of that gameplay wiring is part of this redesign — only presentation is
# changing, not the rules. UI gets layered back in piece by piece as each
# redesigned piece is ready, the same incremental way the board/camera
# work itself was built and validated.
#
# Responsibilities (current, intentionally reduced from the old version):
#   - Register SagaMapSystem, SagaBoardSystem, SagaGlorySystem,
#     SagaTurnSystem, SagaMovementSystem, SagaMapMarkerSystem — identical
#     set/order to the previous game_scene.gd.
#   - Kick off turn 1's movement phase on enter.
#   - Render the board via BoardSpace, at the locked Board Overview
#     camera framing.
#   - Show the Magic Sword Reveal overlay on load, and dismiss it once
#     the player acknowledges it (CONTINUE), revealing the board beneath.
#   - Resolve every hero/jarl/monster's starting region and place their
#     markers on the board (BoardSpace.place_entity_markers()), all
#     together in one call.
# Deliberately NOT yet doing (comes back in later steps):
#   - Any other HUD/UI — banner, mover card, Hero Info, Close-Up modal.
#   - Region click handling / move selection.
#   - Regional Focus reframing.

class_name GameScene
extends Scene


@onready var _board_space: BoardSpace = %BoardSpace
@onready var _sword_reveal_overlay: SwordRevealOverlay = %SwordRevealOverlay


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

## Called when the node enters the [SceneTree].
func _enter_tree() -> void:
	# GameEngine.change_scene() only calls set_engine() via call_deferred(),
	# which fires AFTER this scene's _ready() has already run synchronously.
	# _ready() below calls _start_movement_phase() immediately (no
	# user-input gate to wait out the deferred call), so _game_engine would
	# still be null the whole time without this. _enter_tree() always runs
	# before _ready(), and SagaGameEngine_auto is a true autoload
	# (initialized before any regular scene node), so this is always safe.
	# Identical reasoning to the previous game_scene.gd — this part of the
	# lifecycle isn't changing.
	set_engine(SagaGameEngine_auto)


func _ready() -> void:
	_register_systems()
	_start_movement_phase()
	_sword_reveal_overlay.acknowledged.connect(_on_sword_reveal_acknowledged)
	_place_all_entity_markers()


func on_exit() -> void:
	if is_instance_valid(_sword_reveal_overlay) and _sword_reveal_overlay.acknowledged.is_connected(_on_sword_reveal_acknowledged):
		_sword_reveal_overlay.acknowledged.disconnect(_on_sword_reveal_acknowledged)


func do_action(_action: GameAction) -> void:
	pass  # no keyboard-driven actions yet — board/UI interaction comes back in later steps


# ---------------------------------------------------------------------------
#region Sword reveal
# ---------------------------------------------------------------------------

## The overlay never removes itself (see sword_reveal_overlay.gd) — this is
## the "GameScene decides what's on screen" half of that contract. Once
## freed, the Scrim + Card go with it, leaving BoardSpace as the only
## thing left rendering underneath.
func _on_sword_reveal_acknowledged() -> void:
	_sword_reveal_overlay.acknowledged.disconnect(_on_sword_reveal_acknowledged)
	_sword_reveal_overlay.queue_free()

#endregion


# ---------------------------------------------------------------------------
#region Entity marker placement
# ---------------------------------------------------------------------------

## Resolves every hero/jarl/monster entity's region_id (game-system
## knowledge — SagaBoardSystem.get_location_of() + SagaMapSystem's
## entity_id -> region_id reverse lookup) and hands the whole set to
## BoardSpace in a single call, so all newly spawned entities are placed
## together rather than one at a time. BoardSpace only ever receives
## region_id strings + entity descriptors here — it never resolves a
## location itself, matching the same "rendering widget doesn't touch
## game systems" split map_preview.gd's header already established.
func _place_all_entity_markers() -> void:
	var map_sys := get_registered_system(&"SagaMapSystem") as SagaMapSystem
	var board_sys := get_registered_system(&"SagaBoardSystem") as SagaBoardSystem
	if map_sys == null or board_sys == null:
		push_warning("GameScene: SagaMapSystem/SagaBoardSystem not available — skipping entity marker placement.")
		return

	var groups: Dictionary = {
		"hero":    SagaEntityManager.TAG_PLAYER,
		"jarl":    SagaEntityManager.TAG_JARL,
		"monster": SagaEntityManager.TAG_MONSTER,
	}

	var entities: Array = []
	for kind: String in groups.keys():
		var tag: int = groups[kind]
		for entity: Entity in SagaEntityManager_auto.get_entities_by_tag(tag):
			var loc_entity_id: String = board_sys.get_location_of(entity.id)
			if loc_entity_id == "":
				push_warning("GameScene: %s entity '%s' has no location, skipping marker placement." % [kind, entity.id])
				continue
			var region_id: String = map_sys.get_region_id_for_entity(loc_entity_id)
			if region_id == "":
				push_warning("GameScene: could not resolve region_id for %s entity '%s', skipping marker placement." % [kind, entity.id])
				continue
			entities.append({
				"entity_id": entity.id,
				"kind": kind,
				"region_id": region_id,
			})

	_board_space.place_entity_markers(entities)

#endregion


# ---------------------------------------------------------------------------
#region System registration
# ---------------------------------------------------------------------------

## Identical system set and construction order to the previous
## game_scene.gd — this is gameplay wiring, not presentation, and isn't
## part of the UI redesign.
func _register_systems() -> void:
	var map := SagaMapSystem.new()
	map.name = "SagaMapSystem"
	add_child(map)
	register_system(map)

	var board := SagaBoardSystem.new()
	board.name = "SagaBoardSystem"
	add_child(board)
	register_system(board)

	var glory := SagaGlorySystem.new()
	glory.name = "SagaGlorySystem"
	add_child(glory)
	register_system(glory)

	var turn := SagaTurnSystem.new()
	turn.name = "SagaTurnSystem"
	add_child(turn)
	register_system(turn)

	var movement := SagaMovementSystem.new()
	movement.name = "SagaMovementSystem"
	add_child(movement)
	register_system(movement)

	var map_marker := SagaMapMarkerSystem.new()
	map_marker.name = "SagaMapMarkerSystem"
	add_child(map_marker)
	register_system(map_marker)

#endregion


# ---------------------------------------------------------------------------
#region Movement phase driving
# ---------------------------------------------------------------------------

## Starts the movement phase. No UI to refresh yet — movement phase state
## (get_current_mover(), get_reachable_regions(), etc.) is fully live and
## queryable even with nothing on screen reflecting it yet. That comes
## back once the redesigned UI is wired in.
func _start_movement_phase() -> void:
	var movement_sys := get_registered_system(&"SagaMovementSystem") as SagaMovementSystem
	movement_sys.start_movement_phase()

#endregion