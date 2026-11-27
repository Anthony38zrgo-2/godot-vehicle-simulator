class_name UIConfirmDialog
extends Control
## Reusable modal dialog supporting confirmation prompts and single-line text input (e.g., setup profile naming).

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _Focus := preload("res://scripts/ui/core/ui_focus_navigator.gd")

signal confirmed(input_text: String)
signal cancelled

var backdrop: ColorRect
var window_panel: PanelContainer
var title_label: Label
var message_label: Label
var input_field: LineEdit
var confirm_button: Button
var cancel_button: Button


func _ready() -> void:
	_ensure_nodes()
	_apply_style()


func _ensure_nodes() -> void:
	if window_panel != null:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	backdrop = get_node_or_null("Backdrop") as ColorRect
	if backdrop == null:
		backdrop = ColorRect.new()
		backdrop.name = "Backdrop"
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(backdrop)

	var center := get_node_or_null("Center") as CenterContainer
	if center == null:
		center = CenterContainer.new()
		center.name = "Center"
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(center)

	window_panel = center.get_node_or_null("Window") as PanelContainer
	if window_panel == null:
		window_panel = PanelContainer.new()
		window_panel.name = "Window"
		window_panel.custom_minimum_size = Vector2(420, 0)
		center.add_child(window_panel)

	var vbox := window_panel.get_node_or_null("VBox") as VBoxContainer
	if vbox == null:
		vbox = VBoxContainer.new()
		vbox.name = "VBox"
		vbox.add_theme_constant_override("separation", 12)
		window_panel.add_child(vbox)

	title_label = vbox.get_node_or_null("TitleLabel") as Label
	if title_label == null:
		title_label = Label.new()
		title_label.name = "TitleLabel"
		vbox.add_child(title_label)

	message_label = vbox.get_node_or_null("MessageLabel") as Label
	if message_label == null:
		message_label = Label.new()
		message_label.name = "MessageLabel"
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(message_label)

	input_field = vbox.get_node_or_null("InputField") as LineEdit
	if input_field == null:
		input_field = LineEdit.new()
		input_field.name = "InputField"
		input_field.visible = false
		vbox.add_child(input_field)

	var btns := vbox.get_node_or_null("Buttons") as HBoxContainer
	if btns == null:
		btns = HBoxContainer.new()
		btns.name = "Buttons"
		btns.alignment = BoxContainer.ALIGNMENT_END
		btns.add_theme_constant_override("separation", 10)
		vbox.add_child(btns)

	cancel_button = btns.get_node_or_null("CancelButton") as Button
	if cancel_button == null:
		cancel_button = Button.new()
		cancel_button.name = "CancelButton"
		cancel_button.text = "Cancelar"
		btns.add_child(cancel_button)

	confirm_button = btns.get_node_or_null("ConfirmButton") as Button
	if confirm_button == null:
		confirm_button = Button.new()
		confirm_button.name = "ConfirmButton"
		confirm_button.text = "Confirmar"
		btns.add_child(confirm_button)

	if not confirm_button.pressed.is_connected(_on_confirm):
		confirm_button.pressed.connect(_on_confirm)
	if not cancel_button.pressed.is_connected(_on_cancel):
		cancel_button.pressed.connect(_on_cancel)
	if not input_field.text_submitted.is_connected(func(_t: String) -> void: _on_confirm()):
		input_field.text_submitted.connect(func(_t: String) -> void: _on_confirm())


func _apply_style() -> void:
	backdrop.color = _Tokens.get_color("bg_overlay")
	window_panel.add_theme_stylebox_override("panel", _Theme.make_flat_panel("bg_surface", "accent_rally", 1, _Tokens.get_radius("technical"), 20, 16))
	_Theme.apply_label(title_label, "title", 18, false, true)
	_Theme.apply_label(message_label, "muted", 13, false, false)
	_Theme.apply_tone_button(cancel_button, "muted", 13, 14, 8)
	_Theme.apply_tone_button(confirm_button, "gold", 13, 18, 8)


func open_dialog(title_text: String, body_text: String, show_input: bool = false, initial_text: String = "", confirm_text: String = "Confirmar", cancel_text: String = "Cancelar", danger_confirm: bool = false) -> void:
	_ensure_nodes()
	_apply_style()
	title_label.text = title_text
	message_label.text = body_text
	message_label.visible = not body_text.is_empty()
	input_field.visible = show_input
	input_field.text = initial_text
	confirm_button.text = confirm_text
	cancel_button.text = cancel_text
	_Theme.apply_tone_button(confirm_button, "danger" if danger_confirm else "gold", 13, 18, 8)
	visible = true
	_Theme.transition_control(self, true, 0.10)
	if show_input:
		_Focus.focus_safe(input_field)
		input_field.caret_column = input_field.text.length()
	else:
		_Focus.focus_safe(confirm_button)


func close_dialog() -> void:
	visible = false


func _on_confirm() -> void:
	var txt := input_field.text.strip_edges() if input_field.visible else ""
	visible = false
	confirmed.emit(txt)


func _on_cancel() -> void:
	visible = false
	cancelled.emit()
