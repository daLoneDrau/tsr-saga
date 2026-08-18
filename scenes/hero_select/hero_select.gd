# hero_select.gd
# Controller for the Hero Selection screen — REBUILD IN PROGRESS.
#
# This file was trimmed to match the current scaffold in hero_select.tscn,
# which currently only contains: Background, PresentationFrame, TitleGroup
# (an HBoxContainer holding OrnamentPanelLeft [wraps TitleOrnamentLeft],
# TitleBackingPanel [wraps TitleLabel], OrnamentPanelRight [wraps
# TitleOrnamentRight] — all three are PanelContainers using a StyleBoxFlat
# in the Background color, so PresentationFrame never shows through behind
# any of them). Earlier work (roster/palette state, gallery browsing,
# transitions, SELECT HERO/BACK, name/select-button ornaments, focus cue)
# is being rebuilt node-by-node rather than carried over wholesale — see
# project conversation history for the full spec (design doc section 1)
# once those pieces come back into scope.
#
# Current goal only (spec 1.13, 1.31, 1.32): establish the header band and
# the decorative perimeter frame around the whole screen.
#
# Layout is fixed and lives entirely in hero_select.tscn — this script does
# not compute or apply layout. If the layout needs to change, edit the
# .tscn. The header specifically is NOT fixed-offset like the rest of the
# scene: it's built from Godot's own Container system (HBoxContainer +
# PanelContainer) so it auto-sizes to its content declaratively, with no
# script involved. This is deliberate — the header needs to stay correct
# if the title font/text changes, and containers handle that natively:
#   - TitleGroup (HBoxContainer): centered horizontally (anchor 0.5/0.5,
#     grow_horizontal = BOTH), pinned to the top (anchor/grow_vertical =
#     END so it only grows downward), width/height driven entirely by its
#     children's minimum size. Vertically centers shorter children via
#     size_flags_vertical = SHRINK_CENTER on each direct child.
#   - OrnamentPanelLeft / OrnamentPanelRight sit as direct siblings of
#     TitleBackingPanel inside TitleGroup, so they always bookend the
#     title cluster's actual current edges — including if the label's
#     rendered width changes — rather than sitting at a fixed offset that
#     can drift out of alignment with the text.
#   - Two StyleBoxFlat variants share the same Background color: one with
#     8/4px content margins for the text panel, one with zero margins for
#     the two ornament panels (so they hug the 40x40 texture exactly, no
#     extra padding around the wolf art).
#
# Frame asset architecture (the frame is a single bespoke 640x480 render
# from Blender, not a repeatable strip, so it's a plain TextureRect rather
# than a NinePatchRect):
#   - PresentationFrame (TextureRect): the full-screen frame render.

class_name HeroSelect
extends Scene


# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var _presentation_frame: TextureRect = %PresentationFrame
@onready var _title_group: HBoxContainer = %TitleGroup
@onready var _title_backing_panel: PanelContainer = %TitleBackingPanel
@onready var _ornament_panel_left: PanelContainer = %OrnamentPanelLeft
@onready var _ornament_panel_right: PanelContainer = %OrnamentPanelRight
@onready var _title_ornament_left: TextureRect = %TitleOrnamentLeft
@onready var _title_ornament_right: TextureRect = %TitleOrnamentRight
@onready var _title_label: Label = %TitleLabel


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