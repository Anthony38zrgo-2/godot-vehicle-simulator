class_name UISliderRow
extends PanelContainer
## Technical setup slider row with label, [-] stepper, HSlider, [+] stepper, formatted readout,
## dirty/modified indicator, and disabled/blocked visual state.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")

signal value_changed(param_path: String, new_value: float)

var param_path: String = ""
var step_size: float = 0.05
var unit_suffix: String = ""
var decimals: int = 2
var inverted_display: bool = false
var custom_formatter: Callable = Callable()

var label: Label
var minus_button: Button
var slider: HSlider
var plus_button: Button
var value_label: Label
var _row: HBoxContainer
var _suppress_signal: bool = false
var _baseline_value: float = 0.0
var _styled: bool = false
var _highlighted: bool = false


func _ready() -> void:
	_ensure_nodes()
	_apply_style()


func _ensure_nodes() -> void:
	if _row != null:
		return
	_row = get_node_or_null("Row") as HBoxContainer
	if _row == null:
		_row = HBoxContainer.new()
		_row.name = "Row"
		_row.add_theme_constant_override("separation", 6)
		add_child(_row)

	label = _row.get_node_or_null("ParamLabel") as Label
	if label == null:
		label = Label.new()
		label.name = "ParamLabel"
		label.custom_minimum_size = Vector2(124, 0)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		_row.add_child(label)

	minus_button = _row.get_node_or_null("MinusButton") as Button
	if minus_button == null:
		minus_button = Button.new()
		minus_button.name = "MinusButton"
		minus_button.text = "-"
		minus_button.custom_minimum_size = Vector2(28, 26)
		minus_button.focus_mode = Control.FOCUS_NONE
		_row.add_child(minus_button)

	slider = _row.get_node_or_null("Slider") as HSlider
	if slider == null:
		slider = HSlider.new()
		slider.name = "Slider"
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size = Vector2(100, 20)
		slider.focus_mode = Control.FOCUS_NONE
		_row.add_child(slider)

	plus_button = _row.get_node_or_null("PlusButton") as Button
	if plus_button == null:
		plus_button = Button.new()
		plus_button.name = "PlusButton"
		plus_button.text = "+"
		plus_button.custom_minimum_size = Vector2(28, 26)
		plus_button.focus_mode = Control.FOCUS_NONE
		_row.add_child(plus_button)

	value_label = _row.get_node_or_null("ValueLabel") as Label
	if value_label == null:
		value_label = Label.new()
		value_label.name = "ValueLabel"
		value_label.custom_minimum_size = Vector2(82, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_row.add_child(value_label)

	if not minus_button.pressed.is_connected(_on_minus):
		minus_button.pressed.connect(_on_minus)
	if not plus_button.pressed.is_connected(_on_plus):
		plus_button.pressed.connect(_on_plus)
	if not slider.value_changed.is_connected(_on_slider_changed):
		slider.value_changed.connect(_on_slider_changed)


func _apply_style(force: bool = false) -> void:
	if _styled and not force:
		return
	_styled = true
	var r := _Tokens.get_radius("technical")
	add_theme_stylebox_override("panel", _Theme.make_flat_panel("bg_hover" if _highlighted else "bg_card", "border_focus" if _highlighted else "border_subtle", 1, r, 10, 5))
	_Theme.apply_label(label, "primary", 12, false, false)
	_Theme.apply_label(value_label, "data", 12, true, true)
	_Theme.apply_tone_button(minus_button, "chrome", 13, 6, 2)
	_Theme.apply_tone_button(plus_button, "chrome", 13, 6, 2)
	slider.add_theme_stylebox_override("slider", _Theme.make_flat_panel("bg_well", "border_subtle", 1, r, 0, 3))
	slider.add_theme_stylebox_override("grabber_area", _Theme.make_flat_panel("slider_fill", "slider_fill", 0, r, 0, 3))
	slider.add_theme_stylebox_override("grabber_area_highlight", _Theme.make_flat_panel("accent_rally", "accent_rally", 0, r, 0, 3))


func set_highlighted(val: bool) -> void:
	_ensure_nodes()
	if _highlighted == val and _styled:
		return
	_highlighted = val
	var r := _Tokens.get_radius("technical")
	add_theme_stylebox_override("panel", _Theme.make_flat_panel("bg_hover" if _highlighted else "bg_card", "border_focus" if _highlighted else "border_subtle", 1, r, 10, 5))


func configure(
	path: String,
	title_text: String,
	min_v: float,
	max_v: float,
	step_v: float,
	current_v: float,
	baseline_v: float = INF,
	unit: String = "",
	precision: int = 2,
	disabled_state: bool = false
) -> void:
	_ensure_nodes()
	_apply_style(false)
	param_path = path
	step_size = maxf(step_v, 0.0001)
	unit_suffix = unit
	decimals = precision
	_baseline_value = current_v if is_inf(baseline_v) else baseline_v
	if label.text != title_text:
		label.text = title_text
	_suppress_signal = true
	if not is_equal_approx(slider.min_value, min_v):
		slider.min_value = min_v
	if not is_equal_approx(slider.max_value, max_v):
		slider.max_value = max_v
	if not is_equal_approx(slider.step, step_size):
		slider.step = step_size
	var clamped := clampf(current_v, min_v, max_v)
	if not is_equal_approx(slider.value, clamped):
		slider.value = clamped
	_suppress_signal = false
	set_disabled(disabled_state)
	_update_readout()


func set_value_silent(new_v: float) -> void:
	_ensure_nodes()
	_suppress_signal = true
	slider.value = clampf(new_v, slider.min_value, slider.max_value)
	_suppress_signal = false
	_update_readout()


func get_value() -> float:
	_ensure_nodes()
	return float(slider.value)


func set_disabled(is_disabled: bool) -> void:
	_ensure_nodes()
	slider.editable = not is_disabled
	minus_button.disabled = is_disabled
	plus_button.disabled = is_disabled
	modulate.a = 0.55 if is_disabled else 1.0


func _on_minus() -> void:
	slider.value = clampf(slider.value - step_size, slider.min_value, slider.max_value)


func _on_plus() -> void:
	slider.value = clampf(slider.value + step_size, slider.min_value, slider.max_value)


func _on_slider_changed(v: float) -> void:
	_update_readout()
	if not _suppress_signal:
		value_changed.emit(param_path, v)


func _update_readout() -> void:
	var v := float(slider.value)
	if custom_formatter.is_valid():
		value_label.text = str(custom_formatter.call(v))
	else:
		var fmt := "%." + str(maxi(0, decimals)) + "f"
		var txt := fmt % v
		value_label.text = (txt + " " + unit_suffix).strip_edges()
	var is_dirty := absf(v - _baseline_value) > step_size * 0.25
	value_label.add_theme_color_override("font_color", _Tokens.get_color("accent_rally" if is_dirty else "text_white"))
