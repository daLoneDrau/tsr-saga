class_name SagaGameEngine
extends GameEngine


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
		window.content_scale_size = Vector2i(640, 480)
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP

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

	# Change to title scene
	change_scene("TitleScene")


## Load core game resources (fonts, UI, sounds)
func load_resources() -> void:
	print("SagaGameEngine: Loading resources...")

	# Load C64 font
	var font_loaded := assets.add_font("petme", "res://assets/fonts/PetMe.ttf")
	if not font_loaded:
		push_warning("SagaGameEngine: Failed to load C64 font, using default")
