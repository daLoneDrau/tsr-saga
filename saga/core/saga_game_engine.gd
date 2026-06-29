class_name SagaGameEngine
extends GameEngine


# ---------------------------------------------------------------------------
# Persistent pools — written once by SagaSetupSystem at game start.
# Consumed during play as monsters/jarls are placed; wounded entities are
# returned via the return_* methods. All reads and writes go through the
# methods below — never mutate these arrays directly.
# ---------------------------------------------------------------------------

## Remaining unplaced monster kind IDs.
var monster_pool: Array[int] = []

## Remaining unplaced jarl kind IDs.
var jarl_pool: Array[int] = []

## Remaining undrawn treasure kind IDs.
var treasure_pool: Array[int] = []


# --- Monster pool ---

## Draw the next monster kind ID from the pool.
## Returns -1 if the pool is empty (caller must handle this).
func draw_monster() -> int:
	if monster_pool.is_empty():
		push_warning("SagaGameEngine.draw_monster: pool is empty")
		return -1
	return monster_pool.pop_front()


## Return a wounded monster's kind ID to the back of the pool.
func return_monster(kind_id: int) -> void:
	monster_pool.append(kind_id)


# --- Jarl pool ---

## Draw the next jarl kind ID from the pool.
## Returns -1 if the pool is empty (caller must handle this).
func draw_jarl() -> int:
	if jarl_pool.is_empty():
		push_warning("SagaGameEngine.draw_jarl: pool is empty")
		return -1
	return jarl_pool.pop_front()


## Return a wounded jarl's kind ID to the back of the pool.
func return_jarl(kind_id: int) -> void:
	jarl_pool.append(kind_id)


# --- Treasure pool ---

## Draw the next treasure kind ID from the pool.
## Returns -1 if the pool is empty (caller must handle this).
func draw_treasure() -> int:
	if treasure_pool.is_empty():
		push_warning("SagaGameEngine.draw_treasure: pool is empty")
		return -1
	return treasure_pool.pop_front()


## Treasure is never returned to the pool — heroes keep it until the game ends.


## Called when the node enters the scene tree
func _ready() -> void:
	super._ready()
	print("SagaGameEngine._ready()")
	run()


## Initialize Saga-specific systems
func _initialize_systems() -> void:
	print("SagaGameEngine: Initializing core services...")

	# Create entity manager
	entity_manager = SagaEntityManager.new()
	entity_manager.name = "SagaEntityManager"
	add_child(entity_manager)

	# Create assets library
	assets = AssetsLibrary.new()
	assets.name = "AssetsLibrary"
	add_child(assets)

	print("SagaGameEngine: Core services initialized")


## Configure window for C64-style retro display
func _setup_window() -> void:
	print("SagaGameEngine: Setting up window...")

	if window:
		# Set base resolution (C64 style: 320x200)
		# window.content_scale_size = Vector2i(640, 480)
		# window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		# window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP

		# Desktop window size (2x scale for comfortable viewing)
		# window.size = Vector2i(1280, 960)

		# Set title
		window.title = "Saga - Age of Heroes Minigame"

		# Windowed mode by default
		window.mode = Window.MODE_WINDOWED

		# Disable window resizing to maintain pixel-perfect scaling
		window.unresizable = false

		print("SagaGameEngine: Window configured - 640x480 @ 1x scale")
	else:
		push_error("SagaGameEngine: Window reference is null!")


## Start the game - transition to title screen
func _start_game() -> void:
	print("SagaGameEngine: Starting game...")

	# Register scenes
	register_scene("TitleScene", "res://scenes/title/TitleScene.tscn")
	register_scene("SetupScene", "res://scenes/setup/SetupScene.tscn")

	# Change to title scene
	# change_scene("TitleScene")


## Load core game resources (fonts, UI, sounds)
func load_resources() -> void:
	print("SagaGameEngine: Loading resources...")

	# Load C64 font
	var font_loaded := assets.add_font("petme", "res://assets/fonts/PetMe.ttf")
	if not font_loaded:
		push_warning("SagaGameEngine: Failed to load C64 font, using default")
