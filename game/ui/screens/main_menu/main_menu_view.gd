class_name MainMenuView
extends VBoxContainer
## Reusable main menu title & horizontal action dock view configured via main_menu.json.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Focus := preload("res://scripts/ui/core/ui_focus_navigator.gd")

signal mode_selected(mode_id: String)
signal exit_requested

var title_label: Label
var btn_championship: Button
var btn_rally: Button
var btn_single_stage: Button
var btn_exit: Button
var buttons_box: HBoxContainer
var _bar_wrapper: Control
var _bar_margin: MarginContainer


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if buttons_box != null:
		return
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 10)

	title_label = get_node_or_null("TitleLabel") as Label
	if title_label == null:
		title_label = Label.new()
		title_label.name = "TitleLabel"
		add_child(title_label)
	title_label.text = "Rally Maniac"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", _Tokens.get_font("logo_inline"))
	title_label.add_theme_font_size_override("font_size", 56)
	title_label.add_theme_color_override("font_color", _Tokens.get_color("text_white"))
	title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	title_label.add_theme_constant_override("shadow_offset_x", 0)
	title_label.add_theme_constant_override("shadow_offset_y", 2)

	var line := get_node_or_null("AccentLine") as ColorRect
	if line == null:
		line = ColorRect.new()
		line.name = "AccentLine"
		add_child(line)
	line.custom_minimum_size = Vector2(0, 1)
	line.color = Color(_Tokens.get_color("accent_rally"), 0.45)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var spacer_top := get_node_or_null("SpacerTop") as Control
	if spacer_top == null:
		spacer_top = Control.new()
		spacer_top.name = "SpacerTop"
		spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(spacer_top)

	_bar_wrapper = get_node_or_null("BarWrapper") as Control
	if _bar_wrapper == null:
		_bar_wrapper = Control.new()
		_bar_wrapper.name = "BarWrapper"
		_bar_wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_bar_wrapper.custom_minimum_size = Vector2(0, 68)
		add_child(_bar_wrapper)

	var bar_backdrop := _bar_wrapper.get_node_or_null("BarBackdrop") as TextureRect
	if bar_backdrop == null:
		bar_backdrop = TextureRect.new()
		bar_backdrop.name = "BarBackdrop"
		bar_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bar_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bar_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
		bar_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar_wrapper.add_child(bar_backdrop)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.16, 0.84, 1.0])
	grad.colors = PackedColorArray([
		Color(0.03, 0.05, 0.08, 0.0),
		Color(0.03, 0.05, 0.08, 0.56),
		Color(0.03, 0.05, 0.08, 0.56),
		Color(0.03, 0.05, 0.08, 0.0),
	])
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.width = 256
	grad_tex.height = 1
	bar_backdrop.texture = grad_tex

	_bar_margin = _bar_wrapper.get_node_or_null("BarMargin") as MarginContainer
	if _bar_margin == null:
		_bar_margin = MarginContainer.new()
		_bar_margin.name = "BarMargin"
		_bar_margin.add_theme_constant_override("margin_left", 48)
		_bar_margin.add_theme_constant_override("margin_right", 48)
		_bar_margin.add_theme_constant_override("margin_top", 8)
		_bar_margin.add_theme_constant_override("margin_bottom", 8)
		_bar_wrapper.add_child(_bar_margin)

	buttons_box = _bar_margin.get_node_or_null("ButtonsBox") as HBoxContainer
	if buttons_box == null:
		buttons_box = HBoxContainer.new()
		buttons_box.name = "ButtonsBox"
		buttons_box.alignment = BoxContainer.ALIGNMENT_CENTER
		buttons_box.add_theme_constant_override("separation", 8)
		_bar_margin.add_child(buttons_box)

	btn_championship = _make_action_btn("Campeonato", func() -> void: mode_selected.emit("championship"))
	buttons_box.add_child(btn_championship)
	buttons_box.add_child(_make_sep())
	btn_rally = _make_action_btn("Rally", func() -> void: mode_selected.emit("rally"))
	buttons_box.add_child(btn_rally)
	buttons_box.add_child(_make_sep())
	btn_single_stage = _make_action_btn("Tramo Único", func() -> void: mode_selected.emit("single_stage"))
	buttons_box.add_child(btn_single_stage)
	buttons_box.add_child(_make_sep())
	btn_exit = _make_action_btn("Salir", func() -> void: exit_requested.emit())
	buttons_box.add_child(btn_exit)

	_bar_margin.resized.connect(func() -> void: _bar_wrapper.custom_minimum_size = _bar_margin.size)
	_bar_wrapper.custom_minimum_size = _bar_margin.get_combined_minimum_size()

	var spacer_bot := get_node_or_null("SpacerBottom") as Control
	if spacer_bot == null:
		spacer_bot = Control.new()
		spacer_bot.name = "SpacerBottom"
		spacer_bot.custom_minimum_size = Vector2(0, 12)
		add_child(spacer_bot)


func wire_focus() -> void:
	_ensure_nodes()
	_Focus.wire_horizontal_cycle([btn_championship, btn_rally, btn_single_stage, btn_exit])


func get_default_focus_control() -> Control:
	return btn_championship


func _make_sep() -> ColorRect:
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(2, 28)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.color = Color(_Tokens.get_color("accent_rally"), 0.72)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep


func _make_action_btn(label_text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(0, 56)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	apply_minimal_text_style(btn, 28, 34, 10, false)
	btn.pressed.connect(cb)
	return btn


static func apply_minimal_text_style(btn: Button, font_size: int, pad_h: int, pad_v: int, is_selected: bool) -> void:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = pad_h
	empty.content_margin_right = pad_h
	empty.content_margin_top = pad_v
	empty.content_margin_bottom = pad_v
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state_name, empty)
	btn.add_theme_font_override("font", _Tokens.get_font("menu_option"))
	btn.add_theme_font_size_override("font_size", font_size)
	var accent := _Tokens.get_color("accent_rally")
	var base_color := accent if is_selected else _Tokens.get_color("text_primary")
	btn.add_theme_color_override("font_color", base_color)
	btn.add_theme_color_override("font_focus_color", base_color)
	btn.add_theme_color_override("font_hover_color", accent)
	btn.add_theme_color_override("font_hover_pressed_color", accent)
	btn.add_theme_color_override("font_pressed_color", _Tokens.get_color("accent_rally_dark"))
	btn.add_theme_color_override("font_disabled_color", accent if is_selected else _Tokens.get_color("text_dim"))
	btn.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	btn.add_theme_constant_override("shadow_offset_x", 0)
	btn.add_theme_constant_override("shadow_offset_y", 2)
	btn.add_theme_constant_override("shadow_outline_size", 5)
	btn.mouse_default_cursor_shape = Control.CURSOR_ARROW if is_selected else Control.CURSOR_POINTING_HAND
