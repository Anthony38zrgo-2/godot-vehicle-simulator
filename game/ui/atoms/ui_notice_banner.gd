class_name UINoticeBanner
extends PanelContainer
## Reusable status/error notification banner replacing duplicated notice panels across menus.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")

var label: Label
var is_error: bool = false


func _init() -> void:
	_ensure_nodes()


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if label != null:
		return
	visible = false
	label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	_apply_visual_state(false)


func show_notice(message: String, error_state: bool = false) -> void:
	_ensure_nodes()
	is_error = error_state
	var clean := message.strip_edges()
	label.text = clean
	if clean.is_empty():
		visible = false
		return
	_apply_visual_state(error_state)
	visible = true


func clear_notice() -> void:
	_ensure_nodes()
	is_error = false
	label.text = ""
	visible = false


func _apply_visual_state(error_state: bool) -> void:
	var bg := Color("#2b1316") if error_state else Color("#2a2010")
	var border := _Tokens.get_color("status_danger" if error_state else "accent_rally")
	add_theme_stylebox_override("panel", _Theme.make_flat_panel(bg, border, 1, _Tokens.get_radius("technical"), 14, 8))
	_Theme.apply_label(label, "danger" if error_state else "accent", 13, false, true)
