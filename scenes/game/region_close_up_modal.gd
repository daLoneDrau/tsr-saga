class_name RegionCloseUpModal
extends PopupPanel
## Region close-up view, rebuilt as a true modal — see the map widget
## roadmap for the discussion that led here. A real PopupPanel isolates
## input by construction: clicks/hovers here never leak through to the
## eagle's-eye map underneath, which is what a batch of manual guard
## clauses in map_preview.gd used to exist to prevent by hand.
##
## Deliberately dumb about game data — GameScene gathers region/occupant
## info and hands it to open(); this script only knows how to display
## whatever it's given and report back when it's closed or an occupant is
## hovered.

signal closed()
signal occupant_hover_changed(entity_id: String)

const SCALE_IN_DURATION: float = 0.5

@onready var _dim: ColorRect = get_node("../RegionCloseUpDim")
@onready var _scale_root: Control = $ScaleRoot
@onready var _viewport: RegionCloseUpViewport = $ScaleRoot/HBox/ViewportFrame/ViewportContainer
@onready var _name_label: Label = %ModalNameLabel
@onready var _type_label: Label = %ModalTypeLabel
@onready var _tax_label: Label = %ModalTaxLabel
@onready var _status_label: Label = %ModalStatusLabel
@onready var _occupants_label: Label = %ModalOccupantsLabel
@onready var _hovered_label: Label = %ModalHoveredLabel
@onready var _close_btn: Button = %ModalCloseBtn

var _scale_tween: Tween


func _ready() -> void:
	hide()
	if _dim != null:
		_dim.hide()
	_close_btn.pressed.connect(close)
	_viewport.close_requested.connect(close)
	_viewport.occupant_hover_changed.connect(_on_occupant_hover_changed)


## Opens the modal, framed on anchor_position (region_id's
## "banner_<region_id>" anchor — resolved by the caller via
## MapPreview.get_region_anchor_position(), since sharing world_3d shares
## the rendering scenario, not the node tree, so this script has no way
## to look it up itself). main_viewport is MapPreview's own SubViewport
## (see MapPreview.get_world_viewport()), shared so the close-up camera
## can render the same saga_map geometry. region_info: {name, type
## ("LAND"/"SEA"), tax_text, status_text} — status_text/tax_text may be ""
## to hide those lines (sea regions have neither). entries/
## marker_positions are passed straight through to the viewport's
## set_occupants() — see its own header for their shape.
func open(anchor_position: Vector3, main_viewport: SubViewport, region_info: Dictionary, entries: Array, marker_positions: Dictionary) -> void:
	_name_label.text = region_info.get("name", "")
	_type_label.text = region_info.get("type", "")

	var tax_text: String = region_info.get("tax_text", "")
	_tax_label.text = tax_text
	_tax_label.visible = tax_text != ""

	var status_text: String = region_info.get("status_text", "")
	_status_label.text = status_text
	_status_label.visible = status_text != ""

	_occupants_label.text = region_info.get("occupants_text", "NO ONE HERE")
	_hovered_label.text = ""

	_viewport.share_world(main_viewport)
	_viewport.focus_on_region(anchor_position)
	_viewport.set_occupants(entries, marker_positions)

	popup_centered()
	if _dim != null:
		_dim.show()
	_scale_in()


func close() -> void:
	if not visible:
		return
	_viewport.clear_occupants()
	hide()
	if _dim != null:
		_dim.hide()
	closed.emit()


func _on_occupant_hover_changed(entity_id: String) -> void:
	occupant_hover_changed.emit(entity_id)


## Called back by GameScene after it resolves entity_id's display name —
## this script never touches SagaEntityManager itself (see class header).
func set_hovered_occupant_name(name: String) -> void:
	_hovered_label.text = name


## Grows the popup's content from a small point to full size — the "zoom"
## effect. Scales _scale_root (a plain Control), not the PopupPanel/Window
## itself: Window has no scale property the way a Control does, so the
## popup itself pops in at full size instantly while its content visually
## grows inside it — same net effect, much simpler than resizing a Window
## through a tween. pivot_offset is set to the control's own center so it
## grows from the middle rather than the top-left corner.
func _scale_in() -> void:
	_scale_root.pivot_offset = _scale_root.size / 2.0
	_scale_root.scale = Vector2(0.1, 0.1)

	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.set_ease(Tween.EASE_OUT)
	_scale_tween.set_trans(Tween.TRANS_BACK)
	_scale_tween.tween_property(_scale_root, "scale", Vector2(1.0, 1.0), SCALE_IN_DURATION)