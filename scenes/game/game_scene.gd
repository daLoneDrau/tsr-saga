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
# Deliberately NOT yet doing (comes back in later steps):
#   - Any HUD/UI — banner, mover card, Hero Info, Close-Up modal.
#   - Region click handling / move selection.
#   - Occupant markers on the board.
#   - Regional Focus reframing.

class_name GameScene
extends Scene


@onready var _board_space: BoardSpace = %BoardSpace


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


func on_exit() -> void:
	pass  # nothing wired yet to unwire — comes back with the redesigned UI


func do_action(_action: GameAction) -> void:
	pass  # no keyboard-driven actions yet — board/UI interaction comes back in later steps


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