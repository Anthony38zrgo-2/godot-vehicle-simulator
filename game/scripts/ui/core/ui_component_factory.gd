class_name UIComponentFactory
extends RefCounted
## Builds preset-styled Godot UI nodes from UITokenRegistry presets and UIThemeBuilder.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")


static func create_button(
	text: String,
	preset_or_tone: String = "button.secondary_chrome",
	callback: Callable = Callable(),
	overrides: Dictionary = {}
) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_ALL
	apply_button_preset(btn, preset_or_tone, overrides)
	if callback.is_valid():
		btn.pressed.connect(callback)
	return btn


static func apply_button_preset(btn: Button, preset_or_tone: String, overrides: Dictionary = {}) -> void:
	if btn == null:
		return
	var spec := {}
	if _Tokens.has_preset(preset_or_tone):
		spec = _Tokens.resolve_preset(preset_or_tone)
	else:
		spec = _Tokens.resolve_preset("button.base")
		spec["tone"] = preset_or_tone
	for k in overrides:
		spec[str(k)] = overrides[k]
	var font_key := str(spec.get("font", "button"))
	_Theme.apply_tone_button(
		btn,
		str(spec.get("tone", "chrome")),
		int(spec.get("font_size", 14)),
		int(spec.get("pad_h", 14)),
		int(spec.get("pad_v", 8)),
		int(spec.get("corner_r", _Tokens.get_radius("technical"))),
		_Tokens.get_font(font_key)
	)


static func create_label(
	text: String = "",
	tone: String = "primary",
	font_size: int = 14,
	use_data_font: bool = false,
	bold: bool = false
) -> Label:
	var lbl := Label.new()
	lbl.text = text
	_Theme.apply_label(lbl, tone, font_size, use_data_font, bold)
	return lbl


static func create_panel(preset_id: String = "panel.card", overrides: Dictionary = {}) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _Theme.make_panel_from_preset(preset_id, overrides))
	return panel


static func create_divider(vertical: bool = false, color_token: Variant = "border_subtle") -> ColorRect:
	var rect := ColorRect.new()
	rect.color = _Tokens.get_color(color_token)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		rect.custom_minimum_size = Vector2(1, 0)
		rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		rect.custom_minimum_size = Vector2(0, 1)
		rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rect
