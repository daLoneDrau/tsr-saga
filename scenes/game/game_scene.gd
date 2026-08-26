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
#   - Once the sword reveal is dismissed: pause on the board, then fade in
#     TopBanner's turn side, pause, fade in its hero side, pause, then run
#     the movement phase intro on BottomBanner (phase label fades in/out,
#     then helper text + Finish Movement button appear instantly).
# Deliberately NOT yet doing (comes back in later steps):
#   - Any other HUD/UI — mover card, Hero Info, Close-Up modal.
#   - Region click handling / move selection.
#   - Regional Focus reframing.
#   - Actually handling Finish Movement — the button exists and its press
#     is wired to a signal, but nothing consumes it yet.

class_name GameScene
extends Scene


@onready var _board_space: BoardSpace = %BoardSpace
@onready var _sword_reveal_overlay: SwordRevealOverlay = %SwordRevealOverlay
@onready var _top_banner: TopBanner = %TopBanner
@onready var _bottom_banner: BottomBanner = %BottomBanner

# How long to pause on the fully-revealed board before showing anything,
# how long to pause after the banner appears before revealing the turn
# side, how long to pause between revealing the turn side and the hero
# side, how long to pause after the hero is revealed before the bottom
# banner appears, and how long to leave the phase label up before fading
# it out — all "a beat," not precisely specified, so treat these as
# first-guess timing to adjust once seen in motion rather than exact
# values.
const REVIEW_BOARD_BEAT_SECONDS := 1.0
const AFTER_BANNER_APPEARS_BEAT_SECONDS := 0.5
const BETWEEN_TURN_AND_HERO_BEAT_SECONDS := 1.0
const AFTER_HERO_REVEAL_BEAT_SECONDS := 1.0
const READ_PHASE_LABEL_BEAT_SECONDS := 1.5


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
	_bottom_banner.finish_movement_pressed.connect(_on_finish_movement_pressed)
	_place_all_entity_markers()


func on_exit() -> void:
	if is_instance_valid(_sword_reveal_overlay) and _sword_reveal_overlay.acknowledged.is_connected(_on_sword_reveal_acknowledged):
		_sword_reveal_overlay.acknowledged.disconnect(_on_sword_reveal_acknowledged)
	if is_instance_valid(_bottom_banner) and _bottom_banner.finish_movement_pressed.is_connected(_on_finish_movement_pressed):
		_bottom_banner.finish_movement_pressed.disconnect(_on_finish_movement_pressed)


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
	_play_turn_intro_sequence()

#endregion


# ---------------------------------------------------------------------------
#region Turn intro
# ---------------------------------------------------------------------------

## Board opens with the sword reveal dismissed and every entity's marker
## already in place (no entry animation — see _place_all_entity_markers()).
## Sequence: pause on the fully-revealed board -> make the banner visible
## (it stays hidden entirely until this pause completes — see
## TopBanner.tscn's visible=false default; it was previously rendering its
## frame on top of the sword reveal overlay, since it's the last child in
## the tree) -> pause -> fade in the turn side -> pause -> fade in the
## hero side -> pause -> movement phase intro (see
## _play_movement_phase_intro()). Only makes sense once the board is
## actually visible, so this runs from the sword reveal's dismissal, not
## from _ready() directly.
func _play_turn_intro_sequence() -> void:
	await get_tree().create_timer(REVIEW_BOARD_BEAT_SECONDS).timeout

	_top_banner.visible = true

	await get_tree().create_timer(AFTER_BANNER_APPEARS_BEAT_SECONDS).timeout

	var turn_sys := get_registered_system(&"SagaTurnSystem") as SagaTurnSystem
	if turn_sys == null:
		push_warning("GameScene: SagaTurnSystem not available — skipping turn banner.")
		return

	_top_banner.set_turn(turn_sys.get_current_turn(), SagaTurnSystem.MAX_TURNS)
	await _top_banner.reveal_turn()

	await get_tree().create_timer(BETWEEN_TURN_AND_HERO_BEAT_SECONDS).timeout

	await _announce_current_hero()

	await get_tree().create_timer(AFTER_HERO_REVEAL_BEAT_SECONDS).timeout
	_play_movement_phase_intro()


## Turn order (highest glory first, ties re-shuffled randomly, every turn)
## is already fully handled by SagaTurnSystem.compute_turn_order() — this
## just surfaces whoever that order already put first.
## SagaMovementSystem.get_current_mover() reflects that order directly,
## since start_movement_phase() already snapshotted it and set the mover
## cursor to index 0.
func _announce_current_hero() -> void:
	var movement_sys := get_registered_system(&"SagaMovementSystem") as SagaMovementSystem
	if movement_sys == null:
		push_warning("GameScene: SagaMovementSystem not available — skipping hero announcement.")
		return

	var hero_entity_id: String = movement_sys.get_current_mover()
	if hero_entity_id == "":
		push_warning("GameScene: no current mover to announce.")
		return

	var hero_entity: Entity = SagaEntityManager_auto.get_entity_by_id(hero_entity_id)
	if hero_entity == null:
		push_warning("GameScene: current mover entity '%s' not found." % hero_entity_id)
		return

	var hero_comp: SagaHeroComponent = hero_entity.get_component("SagaHeroComponent", false) as SagaHeroComponent
	if hero_comp == null:
		push_warning("GameScene: current mover entity '%s' has no SagaHeroComponent." % hero_entity_id)
		return

	_top_banner.set_hero(hero_comp.kind_id)
	await _top_banner.reveal_hero()

#endregion


# ---------------------------------------------------------------------------
#region Movement phase intro
# ---------------------------------------------------------------------------

## BottomBanner appears, its phase label fades in with the current phase
## name, holds long enough to read, fades back out — then the persistent
## controls (helper text + Finish Movement button) appear instantly, per
## spec ("instantly reveal" is a deliberate contrast with the phase
## label's fade). Movement is currently the only phase this scene drives
## (see _start_movement_phase()), so the text is hardcoded here rather
## than derived from SagaTurnSystem.Phase — revisit once other phases are
## wired in.
func _play_movement_phase_intro() -> void:
	_bottom_banner.visible = true
	_bottom_banner.set_phase_text("MOVEMENT PHASE")
	await _bottom_banner.fade_in_phase()

	await get_tree().create_timer(READ_PHASE_LABEL_BEAT_SECONDS).timeout

	await _bottom_banner.fade_out_phase()

	_bottom_banner.set_helper_text("Select one or more pieces to move. All movement is optional")
	_bottom_banner.reveal_controls()

	_update_move_availability()

#endregion


## Not implemented yet — no move selection exists, so there's nothing real
## for this to do. Exists so the button's press goes somewhere explicit
## rather than silently nowhere.
func _on_finish_movement_pressed() -> void:
	push_warning("GameScene: Finish Movement pressed — not yet implemented.")


# ---------------------------------------------------------------------------
#region Move availability
# ---------------------------------------------------------------------------

## Highlights (via BoardSpace's MoveAvailableHighlight child on each
## marker) every piece the current mover can still act with this phase.
## SagaMovementSystem owns the actual tracking (has_moved()/mark_moved(),
## and jarl ownership via SagaJarlComponent.owner_hero_id) — this just
## queries it and hands the result to BoardSpace. Call again any time
## availability could have changed (a move resolves, the active hero
## changes) — there's no such trigger yet since move selection isn't
## built, so for now this only runs once, right when the movement controls
## first appear.
func _update_move_availability() -> void:
	var movement_sys := get_registered_system(&"SagaMovementSystem") as SagaMovementSystem
	if movement_sys == null:
		push_warning("GameScene: SagaMovementSystem not available — skipping move availability highlight.")
		return

	var current_mover: String = movement_sys.get_current_mover()
	if current_mover == "":
		_board_space.update_move_availability([])
		return

	_board_space.update_move_availability(movement_sys.get_available_pieces(current_mover))

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

	# animate=false: this is initial game setup, not a piece arriving
	# mid-game (5.2.30's descend-and-settle is for that case) — the board
	# should already look populated the moment it opens.
	_board_space.place_entity_markers(entities, false)

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
