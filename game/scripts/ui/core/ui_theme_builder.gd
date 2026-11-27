class_name UIThemeBuilder
extends RefCounted
## Builds and caches the unified Godot Theme and applies semantic styling via UITokenRegistry.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")

static var _cached_theme: Theme = null
static var _checkbox_icons: Dictionary = {}


static func invalidate_cache() -> void:
	_cached_theme = null
	_checkbox_icons.clear()


static func make_flat_panel(
	bg: Variant = "bg_surface",
	border_col: Variant = "border_subtle",
	border_w: int = 1,
	corner_r: int = -1,
	pad_h: int = -1,
	pad_v: int = -1
) -> StyleBoxFlat:
	var r := _Tokens.get_radius("technical") if corner_r < 0 else corner_r
	return _Tokens.get_flat_stylebox(
		_Tokens.get_color(bg),
		_Tokens.get_color(border_col),
		border_w,
		r,
		pad_h,
		pad_v
	)


static func make_panel_from_preset(preset_id: String, overrides: Dictionary = {}) -> StyleBoxFlat:
	var p := _Tokens.resolve_preset(preset_id)
	for k in overrides:
		p[str(k)] = overrides[k]
	return make_flat_panel(
		p.get("bg", "bg_surface"),
		p.get("border", "border_subtle"),
		int(p.get("border_w", 1)),
		int(p.get("corner_r", _Tokens.get_radius("technical"))),
		int(p.get("pad_h", -1)),
		int(p.get("pad_v", -1))
	)


static func apply_tone_button(
	btn: Button,
	tone: String = "chrome",
	font_size: int = 14,
	pad_h: int = 14,
	pad_v: int = 8,
	corner_r: int = -1,
	font_res: Font = null
) -> void:
	if btn == null:
		return
	var r := _Tokens.get_radius("technical") if corner_r < 0 else corner_r
	var spec := _Tokens.get_tone_spec(tone)
	var bg: Color = spec.get("bg", _Tokens.get_color("bg_card"))
	var bg_hover: Color = spec.get("bg_hover", _Tokens.get_color("bg_hover"))
	var bg_pressed: Color = spec.get("bg_pressed", _Tokens.get_color("bg_pressed"))
	var border: Color = spec.get("border", _Tokens.get_color("border_card"))
	var border_hover: Color = spec.get("border_hover", _Tokens.get_color("border_hover"))
	var accent := _Tokens.get_color("accent_rally")
	var focus_border := _Tokens.get_color("border_focus")
	var bg_surface := _Tokens.get_color("bg_surface")

	var normal := _Tokens.get_flat_stylebox(bg, border, 1, r, pad_h, pad_v)
	var hover := _Tokens.get_flat_stylebox(bg_hover, border_hover, 1, r, pad_h, pad_v)
	var pressed := _Tokens.get_flat_stylebox(bg_pressed, accent if tone == "chrome" else border_hover, 1, r, pad_h, pad_v)
	var focus := _Tokens.get_flat_stylebox(bg_hover, focus_border, 2, r, pad_h, pad_v)
	var disabled := _Tokens.get_flat_stylebox(
		Color(bg_surface.r, bg_surface.g, bg_surface.b, 0.55),
		Color(1.0, 1.0, 1.0, 0.05),
		1,
		r,
		pad_h,
		pad_v
	)

	var used_font := font_res if font_res != null else _Tokens.get_font("button")
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_stylebox_override("disabled", disabled)
	if used_font != null:
		btn.add_theme_font_override("font", used_font)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", spec.get("text", _Tokens.get_color("text_primary")))
	btn.add_theme_color_override("font_hover_color", spec.get("text_hover", _Tokens.get_color("text_white")))
	btn.add_theme_color_override("font_pressed_color", spec.get("text_pressed", accent))
	btn.add_theme_color_override("font_focus_color", _Tokens.get_color("text_white"))
	btn.add_theme_color_override("font_disabled_color", _Tokens.get_color("text_dim"))
	btn.add_theme_constant_override("outline_size", 0)
	btn.remove_theme_color_override("font_shadow_color")


static func apply_card_surface(
	btn: Button,
	selected: bool = false,
	font_size: int = 14,
	pad_h: int = 14,
	pad_v: int = 10,
	accent_col: Color = Color(-1, -1, -1, -1)
) -> void:
	if btn == null:
		return
	var accent := _Tokens.get_color("accent_rally") if accent_col.r < 0.0 else accent_col
	var r := _Tokens.get_radius("technical")
	var bg := _Tokens.get_color("bg_elevated") if selected else _Tokens.get_color("bg_card")
	var border := accent if selected else _Tokens.get_color("border_card")
	var bw := 2 if selected else 1
	var normal := _Tokens.get_flat_stylebox(bg, border, bw, r, pad_h, pad_v)
	var hover := _Tokens.get_flat_stylebox(_Tokens.get_color("bg_hover"), accent if selected else _Tokens.get_color("border_hover"), bw, r, pad_h, pad_v)
	var pressed := _Tokens.get_flat_stylebox(_Tokens.get_color("bg_pressed"), accent, bw, r, pad_h, pad_v)
	var focus := _Tokens.get_flat_stylebox(_Tokens.get_color("bg_hover"), _Tokens.get_color("border_focus"), 2, r, pad_h, pad_v)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_font_override("font", _Tokens.get_font("button"))
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", _Tokens.get_color("text_white") if selected else _Tokens.get_color("text_primary"))
	btn.add_theme_color_override("font_hover_color", _Tokens.get_color("text_white"))
	btn.add_theme_color_override("font_focus_color", _Tokens.get_color("text_white"))
	btn.add_theme_color_override("font_pressed_color", accent)


static func apply_editorial_item(
	btn: Button,
	is_active: bool,
	font_size: int = 14,
	pad_v: int = 10
) -> void:
	if btn == null:
		return
	var accent := _Tokens.get_color("accent_rally")
	var white := _Tokens.get_color("text_white")
	var normal := (
		_Tokens.get_flat_stylebox(Color(1.0, 1.0, 1.0, 0.05), accent, 0, 0, 14, pad_v, 3, 0, 0, 0, 18)
		if is_active
		else _Tokens.get_flat_stylebox(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), 0, 0, 14, pad_v, 0, 0, 0, 0, 14)
	)
	var hover := _Tokens.get_flat_stylebox(
		Color(1.0, 1.0, 1.0, 0.07),
		white,
		0,
		0,
		14,
		pad_v,
		3,
		0,
		0,
		0,
		18 if is_active else 14
	)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", _Tokens.get_font("menu_option"))
	btn.add_theme_font_size_override("font_size", font_size + 1 if is_active else font_size)
	btn.add_theme_color_override("font_color", white if is_active else _Tokens.get_color("text_muted"))
	btn.add_theme_color_override("font_hover_color", white)
	btn.add_theme_color_override("font_focus_color", white)


static func apply_option_button(opt: OptionButton, font_size: int = 12, pad_h: int = 12, pad_v: int = 7) -> void:
	if opt == null:
		return
	apply_tone_button(opt, "chrome", font_size, pad_h, pad_v)
	var popup := opt.get_popup()
	if popup != null:
		var r := _Tokens.get_radius("technical")
		popup.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(_Tokens.get_color("bg_surface"), _Tokens.get_color("border_card"), 1, r, 6, 6))
		popup.add_theme_stylebox_override("hover", _Tokens.get_flat_stylebox(_Tokens.get_color("bg_hover"), _Tokens.get_color("accent_rally"), 1, r))
		popup.add_theme_font_override("font", _Tokens.get_font("medium"))
		popup.add_theme_font_size_override("font_size", maxi(10, font_size - 1))
		popup.add_theme_color_override("font_color", _Tokens.get_color("text_primary"))
		popup.add_theme_color_override("font_hover_color", _Tokens.get_color("text_white"))


static func apply_tree(tree: Tree, font_size: int = 13) -> void:
	if tree == null:
		return
	var r := _Tokens.get_radius("technical")
	var bg_well := _Tokens.get_color("bg_well")
	var bg_shell := _Tokens.get_color("bg_shell")
	var bg_card := _Tokens.get_color("bg_card")
	var border_subtle := _Tokens.get_color("border_subtle")
	var border_hover := _Tokens.get_color("border_hover")
	var border_focus := _Tokens.get_color("border_focus")
	var accent := _Tokens.get_color("accent_rally")
	var accent_soft := _Tokens.get_color("accent_rally_soft")
	tree.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(bg_well, border_subtle, 1, r, 8, 8))
	tree.add_theme_stylebox_override("focus", _Tokens.get_flat_stylebox(bg_well, border_hover, 1, r, 8, 8))
	tree.add_theme_stylebox_override("selected", _Tokens.get_flat_stylebox(accent_soft, accent, 1, r))
	tree.add_theme_stylebox_override("selected_focus", _Tokens.get_flat_stylebox(accent_soft, border_focus, 1, r))
	tree.add_theme_stylebox_override("title_button_normal", _Tokens.get_flat_stylebox(bg_shell, border_subtle, 1, r, 8, 6))
	tree.add_theme_stylebox_override("title_button_hover", _Tokens.get_flat_stylebox(bg_card, border_hover, 1, r, 8, 6))
	tree.add_theme_stylebox_override("title_button_pressed", _Tokens.get_flat_stylebox(bg_card, accent, 1, r, 8, 6))
	tree.add_theme_font_override("font", _Tokens.get_font("medium_tight"))
	tree.add_theme_font_override("title_button_font", _Tokens.get_font("subtitle"))
	tree.add_theme_font_size_override("font_size", maxi(10, font_size - 2))
	tree.add_theme_font_size_override("title_button_font_size", font_size)
	tree.add_theme_color_override("font_color", _Tokens.get_color("text_primary"))
	tree.add_theme_color_override("font_selected_color", _Tokens.get_color("text_white"))
	tree.add_theme_color_override("title_button_color", _Tokens.get_color("text_muted"))
	tree.add_theme_color_override("guide_color", _Tokens.get_color("guide_line"))


static func apply_label(
	lbl: Label,
	tone: String = "primary",
	font_size: int = 14,
	use_data_font: bool = false,
	bold: bool = false
) -> void:
	if lbl == null:
		return
	var col := _Tokens.get_color("text_primary")
	match tone:
		"white", "title", "data":
			col = _Tokens.get_color("text_white")
		"muted", "label":
			col = _Tokens.get_color("text_muted")
		"dim":
			col = _Tokens.get_color("text_dim")
		"accent", "gold":
			col = _Tokens.get_color("accent_rally")
		"success":
			col = _Tokens.get_color("status_success")
		"danger":
			col = _Tokens.get_color("status_danger")
		"alert":
			col = _Tokens.get_color("accent_alert")
		"info":
			col = _Tokens.get_color("status_info")
	var font_key := "data_bold" if (use_data_font and bold) else ("data" if use_data_font else ("subtitle" if bold else "regular"))
	lbl.add_theme_font_override("font", _Tokens.get_font(font_key))
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 0)
	lbl.add_theme_constant_override("outline_size", 0)
	lbl.remove_theme_color_override("font_shadow_color")


static func apply_scroll_container(scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	var vbar := scroll.get_v_scroll_bar()
	if vbar != null:
		var r := _Tokens.get_radius("technical")
		var border_subtle := _Tokens.get_color("border_subtle")
		var accent := _Tokens.get_color("accent_rally")
		vbar.custom_minimum_size.x = 6
		vbar.add_theme_stylebox_override("scroll", _Tokens.get_flat_stylebox(_Tokens.get_color("bg_well"), border_subtle, 0, r))
		vbar.add_theme_stylebox_override("grabber", _Tokens.get_flat_stylebox(_Tokens.get_color("scrollbar_grabber"), border_subtle, 0, r))
		vbar.add_theme_stylebox_override("grabber_highlight", _Tokens.get_flat_stylebox(accent, border_subtle, 0, r))
		vbar.add_theme_stylebox_override("grabber_pressed", _Tokens.get_flat_stylebox(accent, border_subtle, 0, r))


static func get_menu_theme() -> Theme:
	if _cached_theme != null:
		return _cached_theme
	var t := Theme.new()
	var r := _Tokens.get_radius("technical")
	var bg_surface := _Tokens.get_color("bg_surface")
	var bg_card := _Tokens.get_color("bg_card")
	var bg_hover := _Tokens.get_color("bg_hover")
	var bg_pressed := _Tokens.get_color("bg_pressed")
	var bg_well := _Tokens.get_color("bg_well")
	var border_subtle := _Tokens.get_color("border_subtle")
	var border_card := _Tokens.get_color("border_card")
	var border_hover := _Tokens.get_color("border_hover")
	var border_focus := _Tokens.get_color("border_focus")
	var accent := _Tokens.get_color("accent_rally")
	var text_primary := _Tokens.get_color("text_primary")
	var text_white := _Tokens.get_color("text_white")
	var text_dim := _Tokens.get_color("text_dim")

	t.default_font = _Tokens.get_font("regular")
	t.default_font_size = 12

	t.set_color("font_color", "Label", text_primary)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 0)

	var win_panel := _Tokens.get_flat_stylebox(bg_surface, border_card, 1, r)
	t.set_stylebox("panel", "PanelContainer", win_panel)
	t.set_stylebox("panel", "Panel", win_panel)
	t.set_stylebox("panel", "PopupMenu", _Tokens.get_flat_stylebox(bg_surface, border_card, 1, r, 6, 6))
	t.set_stylebox("hover", "PopupMenu", _Tokens.get_flat_stylebox(bg_hover, accent, 1, r))
	t.set_font("font", "PopupMenu", _Tokens.get_font("medium"))
	t.set_font_size("font_size", "PopupMenu", 11)
	t.set_color("font_color", "PopupMenu", text_primary)
	t.set_color("font_hover_color", "PopupMenu", text_white)

	t.set_font("font", "Button", _Tokens.get_font("button"))
	t.set_font_size("font_size", "Button", 15)
	t.set_color("font_color", "Button", text_primary)
	t.set_color("font_hover_color", "Button", text_white)
	t.set_color("font_pressed_color", "Button", accent)
	t.set_color("font_focus_color", "Button", text_white)
	t.set_color("font_disabled_color", "Button", text_dim)
	t.set_stylebox("normal", "Button", _Tokens.get_flat_stylebox(bg_card, border_card, 1, r, 14, 8))
	t.set_stylebox("hover", "Button", _Tokens.get_flat_stylebox(bg_hover, border_hover, 1, r, 14, 8))
	t.set_stylebox("pressed", "Button", _Tokens.get_flat_stylebox(bg_pressed, accent, 1, r, 14, 8))
	t.set_stylebox("focus", "Button", _Tokens.get_flat_stylebox(bg_hover, border_focus, 2, r, 14, 8))
	t.set_stylebox("disabled", "Button", _Tokens.get_flat_stylebox(Color(bg_surface, 0.55), Color(1, 1, 1, 0.05), 1, r, 14, 8))

	t.set_stylebox("normal", "LineEdit", _Tokens.get_flat_stylebox(bg_well, border_card, 1, r, 10, 6))
	t.set_stylebox("focus", "LineEdit", _Tokens.get_flat_stylebox(bg_well, accent, 1, r, 10, 6))
	t.set_font("font", "LineEdit", _Tokens.get_font("regular"))
	t.set_color("font_color", "LineEdit", text_white)
	t.set_color("font_placeholder_color", "LineEdit", text_dim)

	t.set_stylebox("scroll", "VScrollBar", _Tokens.get_flat_stylebox(bg_well, border_subtle, 0, r))
	t.set_stylebox("grabber", "VScrollBar", _Tokens.get_flat_stylebox(_Tokens.get_color("scrollbar_grabber"), border_subtle, 0, r))
	t.set_stylebox("grabber_highlight", "VScrollBar", _Tokens.get_flat_stylebox(accent, border_subtle, 0, r))
	t.set_stylebox("grabber_pressed", "VScrollBar", _Tokens.get_flat_stylebox(accent, border_subtle, 0, r))

	t.set_icon("unchecked", "CheckBox", _get_checkbox_icon(false, false))
	t.set_icon("checked", "CheckBox", _get_checkbox_icon(true, false))
	t.set_icon("unchecked_disabled", "CheckBox", _get_checkbox_icon(false, true))
	t.set_icon("checked_disabled", "CheckBox", _get_checkbox_icon(true, true))
	t.set_constant("h_separation", "CheckBox", 8)
	t.set_font("font", "CheckBox", _Tokens.get_font("medium"))
	t.set_font_size("font_size", "CheckBox", 11)
	t.set_color("font_color", "CheckBox", text_primary)
	t.set_color("font_hover_color", "CheckBox", text_white)
	t.set_color("font_pressed_color", "CheckBox", text_white)
	t.set_color("font_hover_pressed_color", "CheckBox", text_white)
	t.set_color("font_focus_color", "CheckBox", text_white)
	t.set_color("font_disabled_color", "CheckBox", text_dim)
	t.set_stylebox("normal", "CheckBox", _Tokens.get_flat_stylebox(bg_card, border_card, 1, r, 10, 6))
	t.set_stylebox("hover", "CheckBox", _Tokens.get_flat_stylebox(bg_hover, border_hover, 1, r, 10, 6))
	t.set_stylebox("pressed", "CheckBox", _Tokens.get_flat_stylebox(Color("#2a2010"), accent, 1, r, 10, 6))
	t.set_stylebox("hover_pressed", "CheckBox", _Tokens.get_flat_stylebox(Color("#2a2010"), accent, 1, r, 10, 6))
	t.set_stylebox("focus", "CheckBox", _Tokens.get_flat_stylebox(bg_hover, border_focus, 2, r, 10, 6))

	_cached_theme = t
	return _cached_theme


static func _get_checkbox_icon(checked: bool, disabled: bool) -> ImageTexture:
	var key := "%s_%s" % [checked, disabled]
	if _checkbox_icons.has(key):
		return _checkbox_icons[key] as ImageTexture
	var s := 16
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var bg_well := _Tokens.get_color("bg_well")
	var text_dim := _Tokens.get_color("text_dim")
	var accent := _Tokens.get_color("accent_rally")
	var bg := Color(bg_well.r, bg_well.g, bg_well.b, 0.55 if disabled else 1.0)
	var border := Color(text_dim.r, text_dim.g, text_dim.b, 0.45 if disabled else 0.90)
	if checked:
		bg = Color(accent.r, accent.g, accent.b, 0.45 if disabled else 1.0)
		border = bg
	img.fill(bg)
	for x in s:
		img.set_pixel(x, 0, border)
		img.set_pixel(x, s - 1, border)
		img.set_pixel(0, x, border)
		img.set_pixel(s - 1, x, border)
	if checked:
		var bg_base := _Tokens.get_color("bg_base")
		var ink := Color(bg_base.r, bg_base.g, bg_base.b, 0.7 if disabled else 1.0)
		var pts := [
			Vector2i(3, 8), Vector2i(4, 9), Vector2i(5, 10), Vector2i(6, 11),
			Vector2i(7, 10), Vector2i(8, 9), Vector2i(9, 8), Vector2i(10, 7),
			Vector2i(11, 6), Vector2i(12, 5)
		]
		for p in pts:
			for dy in [0, 1]:
				if p.y + dy < s - 1:
					img.set_pixel(p.x, p.y + dy, ink)
	var tex := ImageTexture.create_from_image(img)
	_checkbox_icons[key] = tex
	return tex


static func transition_control(target: Control, fade_in: bool = true, duration: float = 0.14) -> void:
	if target == null or not is_instance_valid(target):
		return
	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		target.modulate.a = 1.0 if fade_in else 0.0
		return
	var from_a := 0.0 if fade_in else target.modulate.a
	var to_a := 1.0 if fade_in else 0.0
	target.modulate.a = from_a
	var tw := target.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(target, "modulate:a", to_a, clampf(duration, 0.05, 0.25)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
