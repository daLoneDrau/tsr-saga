# hero_select.gd
# Controller for the Hero Selection screen — REBUILD IN PROGRESS.
#
# @tool is required here: the prototype toggle below needs to run inside
# the editor (not just at play time) so switching the exported dropdown
# updates the open scene immediately, per the request to preview both
# prototypes without pressing Play.
#
# Layout is fixed and lives entirely in hero_select.tscn — this script
# still does not compute layout. What it DOES own now is purely cosmetic:
# which of two prototype color schemes is currently applied. Everything
# else (roster/palette state, gallery browsing, transitions, SELECT HERO/
# BACK actions) is still out of scope, unchanged from before.
#
# Prototype color schemes (see _apply_prototype()):
#   - A: blue background, single flat gold tint (#c5a35a) on the frame/
#     ornaments via the outline shader with outline_px = 0 (i.e. no
#     synthesized outline — a plain recolor, equivalent to the old
#     `modulate` approach it replaces).
#   - B: parchment background, dark primary (#59442D) + a synthesized
#     outline/shadow in #211D18. The source art (frame.png, wolf_left/
#     right.png) was checked directly — it's flat single-tone white with
#     no real tonal structure, so a genuine two-tone recolor isn't
#     recoverable from the pixels themselves; the "outline" here is
#     synthesized by silhouette_outline.gdshader via alpha-neighbor
#     sampling, not sampled from the source.
#
# HeroNameLabel is a RichTextLabel (not a plain Label) specifically so its
# ornament ("—◇—") and the hero's name can carry two different colors in
# Prototype B — a plain Label can only have one font_color for its whole
# string.

@tool
class_name HeroSelect
extends Scene


# ---------------------------------------------------------------------------
# Prototype toggle
# ---------------------------------------------------------------------------

enum PrototypeVariant { A, B }

## Editor-visible toggle. The setter re-applies colors immediately, in the
## editor as well as at runtime, so switching this dropdown in the
## Inspector updates the open scene without pressing Play.
@export var prototype: PrototypeVariant = PrototypeVariant.A:
	set(value):
		prototype = value
		if is_node_ready():
			_apply_prototype()

const A_ORNAMENT_COLOR := Color("c5a35a")
const A_TITLE_COLOR := Color("c5a35a")
const A_TEXT_COLOR := Color("f0e2bc")  # PrevArrow, NextArrow, HeroNameLabel, BackButton

const B_ORNAMENT_PRIMARY := Color("59442d")
const B_ORNAMENT_SECONDARY := Color("211d18")
const B_TITLE_COLOR := Color("211d18")
const B_NAME_COLOR := Color("211d18")
const B_NAME_ORNAMENT_COLOR := Color("59442d")

const HERO_NAME_ORNAMENT := "—◇—"

# ---------------------------------------------------------------------------
# Roster & palette — canonical order per HeroKindTable's declared order
# (matches the earlier decision this whole rebuild has used throughout).
# Rolled once per _ready() for the entire six-hero roster, not just the
# three currently displayed — matches spec 1.10/1.11 (generate cosmetic
# appearances for the whole roster up front, not per-hero-on-demand) and
# keeps this scene ready for when browsing brings the other three heroes
# into view without needing to re-roll anything at that point.
# ---------------------------------------------------------------------------

const ROSTER_KIND_IDS: Array[int] = [
	HeroKindTable.BEOWULF,
	HeroKindTable.EGIL,
	HeroKindTable.BRUNHILD,
	HeroKindTable.SIEGFRIED,
	HeroKindTable.STARKAD,
	HeroKindTable.RAGNAR,
	]

# Palette pools — ported from SetupScene.gd so both screens roll from the
# same source of truth. If SetupScene's pools ever change, update both
# until this prototype graduates into the real flow and one of them can
# just reference the other.
const SKIN_MATERIAL_PATHS: Array[String] = [
	"res://assets/art/materials/heroes/skin/fair_rosy.tres",
	"res://assets/art/materials/heroes/skin/light_tan.tres",
	"res://assets/art/materials/heroes/skin/florid.tres",
	"res://assets/art/materials/heroes/skin/olive.tres",
	]
const HAIR_MATERIAL_PATHS: Array[String] = [
	"res://assets/art/materials/heroes/hair/blonde.tres",
	"res://assets/art/materials/heroes/hair/auburn.tres",
	"res://assets/art/materials/heroes/hair/red.tres",
	"res://assets/art/materials/heroes/hair/black.tres",
	"res://assets/art/materials/heroes/hair/platinum.tres",
	]
const HAIR_MATERIAL_PATHS_OLIVE: Array[String] = [
	"res://assets/art/materials/heroes/hair/auburn.tres",
	"res://assets/art/materials/heroes/hair/black.tres",
	]
# Maps scalp hair material path -> matching stubble path for Starkad.
const STUBBLE_BY_HAIR: Dictionary = {
	"res://assets/art/materials/heroes/hair/blonde.tres": "res://assets/art/materials/heroes/stubble/stubble_blonde.tres",
	"res://assets/art/materials/heroes/hair/auburn.tres": "res://assets/art/materials/heroes/stubble/stubble_auburn.tres",
	"res://assets/art/materials/heroes/hair/red.tres": "res://assets/art/materials/heroes/stubble/stubble_red.tres",
	"res://assets/art/materials/heroes/hair/black.tres": "res://assets/art/materials/heroes/stubble/stubble_black.tres",
	"res://assets/art/materials/heroes/hair/platinum.tres": "res://assets/art/materials/heroes/stubble/stubble_platinum.tres",
	}


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var _background_blue: ColorRect = %BackgroundBlue
@onready var _background_parchment: TextureRect = %BackgroundParchment
@onready var _presentation_frame: TextureRect = %PresentationFrame
@onready var _title_group: HBoxContainer = %TitleGroup
@onready var _title_backing_panel: PanelContainer = %TitleBackingPanel
@onready var _ornament_panel_left: PanelContainer = %OrnamentPanelLeft
@onready var _ornament_panel_right: PanelContainer = %OrnamentPanelRight
@onready var _title_ornament_left: TextureRect = %TitleOrnamentLeft
@onready var _title_ornament_right: TextureRect = %TitleOrnamentRight
@onready var _ornament_material: ShaderMaterial = _title_ornament_left.material
@onready var _frame_material: ShaderMaterial = _presentation_frame.material
@onready var _title_label: Label = %TitleLabel
@onready var _hero_name_label: RichTextLabel = %HeroNameLabel
@onready var _prev_arrow: Button = %PrevArrow
@onready var _next_arrow: Button = %NextArrow
@onready var _back_button: Button = %BackButton
@onready var _current_hero_display: SubViewport = %CurrentHeroDisplay
@onready var _next_hero_display: SubViewport = %NextHeroDisplay
@onready var _prev_hero_display: SubViewport = %PrevHeroDisplay

# Per-roster-index rolled palette — parallel arrays indexed like
# ROSTER_KIND_IDS, populated once by _roll_palette().
var _hero_skin_paths: Array[String] = []
var _hero_hair_paths: Array[String] = []
var _hero_stubble_paths: Array[String] = []

# Captured once in _ready(), before any override is applied — these ARE
# the StyleBoxFlat resources authored in the .tscn (Prototype A's solid
# blue panel backgrounds), just grabbed by reference rather than
# duplicated here, so the tscn stays the source of truth for their exact
# color/margins.
var _ornament_panel_style_a: StyleBox
var _title_panel_style_a: StyleBox
# Reused from the arrows' existing empty stylebox rather than constructing
# a new resource — Prototype B's "no panel background" state.
var _empty_panel_style: StyleBox


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_ornament_panel_style_a = _ornament_panel_left.get_theme_stylebox("panel")
	_title_panel_style_a = _title_backing_panel.get_theme_stylebox("panel")
	_empty_panel_style = _prev_arrow.get_theme_stylebox("normal")

	# TitleGroup's width/position can change (font swap, longer hero name,
	# etc.) independently of the prototype toggle — keep the frame's cutout
	# in sync whenever that happens, not just when _apply_prototype() runs.
	if not _title_group.resized.is_connected(_update_frame_cutout):
		_title_group.resized.connect(_update_frame_cutout)

	_roll_palette()
	_apply_gallery_materials()

	_apply_prototype()
	# TitleGroup's final auto-sized rect may not be settled the instant
	# _ready() runs (container layout resolves within the same frame) —
	# recompute once more after layout has actually flushed.
	_update_frame_cutout.call_deferred()


## Rolls an independent skin/hair/stubble combo for every hero in the
## roster, once per screen load (spec 1.10/1.11) — ported from
## SetupScene._roll_palette(). Highlighting a different hero afterward only
## looks up its already-rolled combo once browsing exists; nothing here
## re-rolls after this point.
func _roll_palette() -> void:
	_hero_skin_paths = []
	_hero_hair_paths = []
	_hero_stubble_paths = []

	for i in ROSTER_KIND_IDS.size():
		var skin_path: String = SKIN_MATERIAL_PATHS[randi_range(0, SKIN_MATERIAL_PATHS.size() - 1)]

		var hair_pool: Array[String] = HAIR_MATERIAL_PATHS_OLIVE if skin_path == SKIN_MATERIAL_PATHS[3] else HAIR_MATERIAL_PATHS
		var hair_path: String = hair_pool[randi_range(0, hair_pool.size() - 1)]

		# Stubble only exists on Starkad's model — resolved for every hero
		# from the same hair roll for storage purposes, but _apply_hero_
		# materials() below only ever uses it when kind_id == STARKAD.
		var stubble_path: String = STUBBLE_BY_HAIR.get(hair_path, "")

		_hero_skin_paths.append(skin_path)
		_hero_hair_paths.append(hair_path)
		_hero_stubble_paths.append(stubble_path)


## Applies each currently-instanced static hero's rolled palette to its
## model. Only three slots exist right now (Beowulf/Egil/Ragnar, statically
## instanced in the .tscn) — this doesn't yet handle swapping models on
## browse, just recoloring what's already there.
func _apply_gallery_materials() -> void:
	_apply_hero_materials(_current_hero_display.get_node("CharacterMark"), HeroKindTable.BEOWULF)
	_apply_hero_materials(_next_hero_display.get_node("CharacterMark"), HeroKindTable.EGIL)
	_apply_hero_materials(_prev_hero_display.get_node("CharacterMark"), HeroKindTable.RAGNAR)


## Finds kind_id's rolled palette and applies it to the hero model already
## sitting under character_mark, via surface material overrides — same
## surface convention PortraitWidget uses (0 = skin, 1 = hair, last =
## stubble). Stubble is only ever applied for Starkad: on every other
## hero's 2-surface mesh, "last surface index" IS the hair surface, so
## applying it unconditionally would silently overwrite hair with stubble
## instead of adding it — this mirrors the gating SetupScene's own call
## site already does before reaching PortraitWidget.
func _apply_hero_materials(character_mark: Node3D, kind_id: int) -> void:
	if character_mark == null:
		return

	var roster_idx: int = ROSTER_KIND_IDS.find(kind_id)
	if roster_idx == -1:
		push_error("HeroSelect: kind_id %d not found in ROSTER_KIND_IDS" % kind_id)
		return

	var mesh_node: MeshInstance3D = _find_mesh(character_mark)
	if mesh_node == null:
		push_error("HeroSelect: no MeshInstance3D found under %s" % character_mark.name)
		return

	var skin_mat: StandardMaterial3D = load(_hero_skin_paths[roster_idx]) as StandardMaterial3D
	if skin_mat == null:
		push_error("HeroSelect: could not load skin material at %s" % _hero_skin_paths[roster_idx])
	else:
		mesh_node.set_surface_override_material(0, skin_mat)

	var hair_mat: StandardMaterial3D = load(_hero_hair_paths[roster_idx]) as StandardMaterial3D
	if hair_mat == null:
		push_error("HeroSelect: could not load hair material at %s" % _hero_hair_paths[roster_idx])
	else:
		mesh_node.set_surface_override_material(1, hair_mat)

	if kind_id != HeroKindTable.STARKAD:
		return

	var stubble_path: String = _hero_stubble_paths[roster_idx]
	if stubble_path.is_empty():
		return
	var stubble_mat: StandardMaterial3D = load(stubble_path) as StandardMaterial3D
	if stubble_mat == null:
		push_error("HeroSelect: could not load stubble material at %s" % stubble_path)
		return
	var mesh: Mesh = mesh_node.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return
	mesh_node.set_surface_override_material(mesh.get_surface_count() - 1, stubble_mat)


## Recursively find the first MeshInstance3D in the subtree — same helper
## PortraitWidget uses, duplicated here since PortraitWidget is scoped to
## its own scene rather than a shared utility.
func _find_mesh(node: Node) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var result: MeshInstance3D = _find_mesh(child)
		if result != null:
			return result
	return null


## Applies the current `prototype` value's full color scheme. Safe to call
## repeatedly (e.g. from the exported var's setter every time it changes in
## the Inspector) — it always sets every value it owns rather than
## incrementally diffing against the previous prototype.
func _apply_prototype() -> void:
	var is_b := prototype == PrototypeVariant.B

	_background_blue.visible = not is_b
	_background_parchment.visible = is_b

	var primary := B_ORNAMENT_PRIMARY if is_b else A_ORNAMENT_COLOR
	var secondary := B_ORNAMENT_SECONDARY if is_b else A_ORNAMENT_COLOR
	var outline := 0.5 if is_b else 0.0
	for mat in [_ornament_material, _frame_material]:
		if mat == null:
			continue
		mat.set_shader_parameter("primary_color", primary)
		mat.set_shader_parameter("secondary_color", secondary)
		mat.set_shader_parameter("outline_px", outline)
	# _title_ornament_left / _title_ornament_right share _ornament_material,
	# so updating it once updates both.

	# Prototype A: TitleGroup's three panels keep their solid blue
	# backgrounds, opaque enough on their own to cover the frame border
	# beneath them — no cutout needed there, though it's applied anyway
	# below since it's harmless when something opaque already sits on top.
	# Prototype B: those same panels go fully transparent instead, so the
	# frame border has to actually stop rendering under TitleGroup rather
	# than being hidden by a rectangle — that's what the cutout is for.
	var ornament_panel_style := _empty_panel_style if is_b else _ornament_panel_style_a
	var title_panel_style := _empty_panel_style if is_b else _title_panel_style_a
	_ornament_panel_left.add_theme_stylebox_override("panel", ornament_panel_style)
	_ornament_panel_right.add_theme_stylebox_override("panel", ornament_panel_style)
	_title_backing_panel.add_theme_stylebox_override("panel", title_panel_style)

	_title_label.add_theme_color_override("font_color", B_TITLE_COLOR if is_b else A_TITLE_COLOR)

	var name_color := B_NAME_COLOR if is_b else A_TEXT_COLOR
	var name_ornament_color := B_NAME_ORNAMENT_COLOR if is_b else A_TEXT_COLOR
	_hero_name_label.text = "[color=#%s]%s[/color] [color=#%s]%s[/color] [color=#%s]%s[/color]" % [
		name_ornament_color.to_html(false), HERO_NAME_ORNAMENT,
		name_color.to_html(false), _current_hero_name(),
		name_ornament_color.to_html(false), HERO_NAME_ORNAMENT,
		]

	var arrow_back_color := B_ORNAMENT_PRIMARY if is_b else A_TEXT_COLOR
	_prev_arrow.add_theme_color_override("font_color", arrow_back_color)
	_next_arrow.add_theme_color_override("font_color", arrow_back_color)
	_back_button.add_theme_color_override("font_color", arrow_back_color)

	_update_frame_cutout()


## Computes TitleGroup's current global rect in PresentationFrame's own UV
## space (0.0-1.0 across both axes) and feeds it to _frame_material's
## cutout uniforms, so the frame's border doesn't render underneath
## TitleGroup regardless of the title's current size. Bounded on Y as well
## as X — an X-only cutout would blank the full column height, erasing the
## bottom border directly below TitleGroup along with the top border
## behind it. Runs independently of the prototype toggle (via
## TitleGroup.resized) since the title's size can change on its own — see
## _ready().
func _update_frame_cutout() -> void:
	if _frame_material == null:
		return

	var frame_rect := _presentation_frame.get_global_rect()
	if frame_rect.size.x <= 0.0 or frame_rect.size.y <= 0.0:
		return

	var title_rect := _title_group.get_global_rect()
	var uv_left: float = clampf((title_rect.position.x - frame_rect.position.x) / frame_rect.size.x, 0.0, 1.0)
	var uv_right: float = clampf((title_rect.position.x + title_rect.size.x - frame_rect.position.x) / frame_rect.size.x, 0.0, 1.0)
	var uv_top: float = clampf((title_rect.position.y - frame_rect.position.y) / frame_rect.size.y, 0.0, 1.0)
	var uv_bottom: float = clampf((title_rect.position.y + title_rect.size.y - frame_rect.position.y) / frame_rect.size.y, 0.0, 1.0)

	_frame_material.set_shader_parameter("cutout_uv_left", uv_left)
	_frame_material.set_shader_parameter("cutout_uv_right", uv_right)
	_frame_material.set_shader_parameter("cutout_uv_top", uv_top)
	_frame_material.set_shader_parameter("cutout_uv_bottom", uv_bottom)


## Hardcoded to match the still-static CurrentHeroSlot (Beowulf) — this
## becomes a real lookup once roster/browsing state comes back into scope.
func _current_hero_name() -> String:
	return "BEOWULF"


# ---------------------------------------------------------------------------
# Scene overrides
# ---------------------------------------------------------------------------

## REQUIRED — Scene marks this @abstract, so a concrete Scene subclass will
## not even parse/load without an override. No actions are registered yet
## at this stage of the rebuild (nothing calls register_action() here), so
## there's nothing to route to — this stays a no-op stub until gallery
## browsing / SELECT HERO / BACK come back into scope.
func do_action(_action: GameAction) -> void:
	pass


## Optional hook — Scene's base implementation is already a no-op ("pass"),
## so this stub isn't strictly required, but it's kept here as the landing
## spot for resetting roster/palette state once the gallery is rebuilt.
func on_enter() -> void:
	pass


## Optional hook — same as on_enter: Scene's base is a no-op. Landing spot
## for disconnecting any wired input once the gallery/actions are rebuilt.
func on_exit() -> void:
	pass

	# NOTE: on_pause() / on_resume() are intentionally NOT stubbed here. Unlike
	# on_enter/on_exit, Scene's base implementations aren't no-ops — they set
	# `paused = true` / `paused = false`. An empty override would silently
	# break pausing for this scene, so they're left unoverridden until there's
	# scene-specific pause behavior actually needed.
