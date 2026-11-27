class_name UITireSlotCard
extends PanelContainer
## Unified interactive tire slot card supporting 2D/3D previews, wear readout, drag & drop,
## and keyboard/D-Pad selection across Garage, Strategy, Pause, and Service boards.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _MeterScript := preload("res://ui/atoms/ui_progress_meter.gd")

signal slot_clicked(group_name: String, slot_index: int)
signal slot_drop_requested(source_payload: Dictionary, target_group: String, target_index: int)

var group_name: String = "mounted"
var slot_index: int = 0
var slot_title: String = ""
var tire_data: Dictionary = {}
var is_selected: bool = false
var is_highlighted: bool = false
var allow_drag: bool = true

var title_label: Label
var compound_label: Label
var status_label: Label
var wear_meter: _MeterScript
var preview_holder: Control
var _vbox: VBoxContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(126, 118)
	_ensure_nodes()


func _ready() -> void:
	_ensure_nodes()
	_refresh_border()


func _ensure_nodes() -> void:
	if _vbox != null:
		return
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 3)
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vbox)

	title_label = Label.new()
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_Theme.apply_label(title_label, "muted", 10, true, true)
	_vbox.add_child(title_label)

	preview_holder = Control.new()
	preview_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_holder.custom_minimum_size = Vector2(0, 44)
	preview_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vbox.add_child(preview_holder)

	compound_label = Label.new()
	compound_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compound_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_Theme.apply_label(compound_label, "white", 11, false, true)
	_vbox.add_child(compound_label)

	status_label = Label.new()
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_Theme.apply_label(status_label, "muted", 10, true, false)
	_vbox.add_child(status_label)

	wear_meter = _MeterScript.new()
	wear_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(wear_meter)


func configure_slot(p_group: String, p_index: int, p_title: String, p_tire_data: Dictionary, compound_text: String = "") -> void:
	_ensure_nodes()
	group_name = p_group
	slot_index = p_index
	slot_title = p_title
	tire_data = p_tire_data
	title_label.text = p_title
	if tire_data.is_empty():
		compound_label.text = "VACÍO"
		status_label.text = "—"
		wear_meter.visible = false
	else:
		var cid := str(tire_data.get("compound_id", ""))
		compound_label.text = compound_text if not compound_text.is_empty() else cid
		var st: Dictionary = tire_data.get("state", {}) as Dictionary
		var wear := clampf(float(st.get("wear_fraction", 0.0)), 0.0, 1.0)
		var life := 1.0 - wear
		var punctured := bool(st.get("punctured", false))
		var rim_bent := float(st.get("rim_damage", 0.0)) > 0.15
		status_label.text = "PINCHADA" if punctured else ("LLANTA DAÑADA" if rim_bent else ("ID #%d" % int(tire_data.get("id", 0))))
		_Theme.apply_label(status_label, "danger" if (punctured or rim_bent) else "muted", 10, true, punctured or rim_bent)
		wear_meter.visible = true
		wear_meter.set_meter("Vida", life, "%d%%" % int(roundf(life * 100.0)), false)
	_refresh_border()


func set_selected_state(selected: bool, highlighted: bool = false) -> void:
	is_selected = selected
	is_highlighted = highlighted
	_refresh_border()


func _refresh_border() -> void:
	var bg := "bg_elevated" if is_selected else "bg_card"
	var border := "accent_rally" if is_selected else ("status_info" if is_highlighted else "border_card")
	var bw := 2 if (is_selected or is_highlighted) else 1
	add_theme_stylebox_override("panel", _Theme.make_flat_panel(bg, border, bw, _Tokens.get_radius("technical"), 8, 6))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		slot_clicked.emit(group_name, slot_index)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not allow_drag or tire_data.is_empty():
		return null
	var preview := Label.new()
	preview.text = "%s · %s" % [slot_title, compound_label.text]
	_Theme.apply_label(preview, "accent", 12, false, true)
	set_drag_preview(preview)
	return {
		"group": group_name,
		"index": slot_index,
		"tire_id": int(tire_data.get("id", -1)),
		"compound_id": str(tire_data.get("compound_id", "")),
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("group")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary:
		slot_drop_requested.emit(data as Dictionary, group_name, slot_index)
