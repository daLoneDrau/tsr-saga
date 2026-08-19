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


# ---------------------------------------------------------------------------
# Cross-scene persistent state — board placement and map graph.
#
# SagaBoardSystem and SagaMapSystem are registered fresh in every scene that
# needs them (SetupScene, GameScene, ...). Godot destroys their node
# instances on change_scene_to_file, so any state they held locally would be
# lost at the SetupScene -> GameScene transition. Instead, both systems
# alias their working Dictionaries directly to the fields below in
# _on_initialize() (Dictionaries are reference types in GDScript, so writes
# from any scene's system instance land here and are visible to the next
# scene's instance automatically). Neither system's _on_cleanup() clears
# these — only a deliberate new-game reset should.
# ---------------------------------------------------------------------------

## SagaBoardSystem's primary index: location_entity_id -> Array[String occupant_entity_id].
var board_grid: Dictionary = {}

## SagaBoardSystem's reverse index: occupant_entity_id -> location_entity_id.
var board_locations: Dictionary = {}

## True once SagaMapSystem has parsed map.json and created land/sea entities.
## Guards against re-creating (and duplicating) all 66 region entities if a
## second SagaMapSystem instance initializes in a later scene.
var map_loaded: bool = false

## SagaMapSystem's region_id (map.json key) -> entity_id.
var map_region_id_to_entity_id: Dictionary = {}

## SagaMapSystem's entity_id -> region_id (reverse lookup).
var map_entity_id_to_region_id: Dictionary = {}

## SagaMapSystem's adjacency graph: entity_id -> Array[String entity_id].
var map_adjacency: Dictionary = {}

## SagaMapSystem's land/sea classification: entity_id -> bool (true = land).
var map_is_land: Dictionary = {}


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


# ---------------------------------------------------------------------------
# Hero appearances — the whole roster's rolled cosmetic palette, saved by
# HeroSelect when the player confirms their pick (spec 1.10: appearances
# are generated for the entire roster up front and "preserved for the
# duration of that game and in saves" — not just the chosen hero's).
#
# SagaSetupSystem.run() only writes skin/hair onto the CHOSEN hero's own
# SagaHeroComponent, since the other five heroes never become entities at
# setup time. This dictionary is where any future system recovers the
# other five heroes' appearances — e.g. if they show up as AI opponents
# later. Keyed by HeroKindTable kind_id.
# ---------------------------------------------------------------------------

var hero_appearances: Dictionary[int, Dictionary] = {}


## Records kind_id's rolled palette (skin, hair, and stubble — stubble is
## only ever meaningful for Starkad, but stored uniformly for every hero
## for simplicity; callers/consumers ignore it where it doesn't apply).
## Overwrites any existing entry for the same kind_id.
func set_hero_appearance(kind_id: int, skin_material_path: String, hair_material_path: String, stubble_material_path: String) -> void:
	hero_appearances[kind_id] = {
		"skin_material_path": skin_material_path,
		"hair_material_path": hair_material_path,
		"stubble_material_path": stubble_material_path,
		}


## Returns kind_id's saved appearance, or an empty Dictionary if none was
## ever recorded for it.
func get_hero_appearance(kind_id: int) -> Dictionary:
	return hero_appearances.get(kind_id, {})


## Called when the node enters the scene tree
func _ready() -> void:
	super._ready()
	print("SagaGameEngine._ready()")
	run()


## Initialize Saga-specific systems
func _initialize_systems() -> void:
	print("SagaGameEngine: Initializing core services...")

	# Create entity manager
	entity_manager = SagaEntityManager_auto
	entity_manager.name = "SagaEntityManager"
	# add_child(entity_manager)

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
#TODO - comment this line when testing individual scenes
# change_scene("TitleScene")


## Load core game resources (fonts, UI, sounds)
func load_resources() -> void:
	print("SagaGameEngine: Loading resources...")

	# Load C64 font
	var font_loaded := assets.add_font("petme", "res://assets/fonts/PetMe.ttf")
	if not font_loaded:
		push_warning("SagaGameEngine: Failed to load C64 font, using default")
