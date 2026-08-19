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

	_apply_prototype()
	# TitleGroup's final auto-sized rect may not be settled the instant
	# _ready() runs (container layout resolves within the same frame) —
	# recompute once more after layout has actually flushed.
	_update_frame_cutout.call_deferred()


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
## space (0.0-1.0 across its width) and feeds it to _frame_material's
## cutout uniforms, so the frame's border doesn't render underneath
## TitleGroup regardless of the title's current width. Runs independently
## of the prototype toggle (via TitleGroup.resized) since the title's
## width can change on its own — see _ready().
func _update_frame_cutout() -> void:
	if _frame_material == null:
		return

	var frame_rect := _presentation_frame.get_global_rect()
	if frame_rect.size.x <= 0.0:
		return

	var title_rect := _title_group.get_global_rect()
	var uv_left: float = clampf((title_rect.position.x - frame_rect.position.x) / frame_rect.size.x, 0.0, 1.0)
	var uv_right: float = clampf((title_rect.position.x + title_rect.size.x - frame_rect.position.x) / frame_rect.size.x, 0.0, 1.0)

	_frame_material.set_shader_parameter("cutout_uv_left", uv_left)
	_frame_material.set_shader_parameter("cutout_uv_right", uv_right)


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