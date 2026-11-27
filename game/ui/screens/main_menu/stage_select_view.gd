class_name StageSelectView
extends VBoxContainer
## Data-Driven stage selection view with country selector and 4-card carousel.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _RoutePreviewScript := preload("res://ui/organisms/ui_route_preview.gd")

signal stage_selected(stage_id: String)
signal country_selected(country: String)
signal back_requested

var stage_title_label: Label
var country_row: HBoxContainer
var country_buttons: Array[Button] = []
var stage_scroll: ScrollContainer
var stage_strip: HBoxContainer
var stage_buttons: Array[Button] = []
var stage_previews: Array = []
var btn_carousel_prev: Button
var btn_carousel_next: Button
var carousel_page_label: Label
var btn_stage_back: Button
var carousel_scroll_index: int = 0

var _stage_header: HBoxContainer
var _stage_count: int = 10
var _cdi_mode: bool = false
var _selected_country: String = "russia"
var _initialized: bool = false


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _initialized:
		return
	_initialized = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)

	_stage_header = get_node_or_null("StageHeader") as HBoxContainer
	if _stage_header == null:
		_stage_header = HBoxContainer.new()
		_stage_header.name = "StageHeader"
		add_child(_stage_header)

	stage_title_label = _stage_header.get_node_or_null("TitleLabel") as Label
	if stage_title_label == null:
		stage_title_label = Label.new()
		stage_title_label.name = "TitleLabel"
		_stage_header.add_child(stage_title_label)
	stage_title_label.add_theme_font_override("font", _Tokens.get_font("title"))
	stage_title_label.add_theme_font_size_override("font_size", 18)
	stage_title_label.add_theme_color_override("font_color", _Tokens.get_color("accent_rally"))

	var stage_sub := _stage_header.get_node_or_null("SubtitleLabel") as Label
	if stage_sub == null:
		stage_sub = Label.new()
		stage_sub.name = "SubtitleLabel"
		_stage_header.add_child(stage_sub)
	stage_sub.text = "   · Elige el tramo de entrada"
	stage_sub.add_theme_font_override("font", _Tokens.get_font("subtitle"))
	stage_sub.add_theme_font_size_override("font_size", 13)
	stage_sub.add_theme_color_override("font_color", _Tokens.get_color("text_muted"))

	country_row = get_node_or_null("CountryRow") as HBoxContainer
	if country_row == null:
		country_row = HBoxContainer.new()
		country_row.name = "CountryRow"
		add_child(country_row)
	country_row.add_theme_constant_override("separation", 6)

	var carousel_row := get_node_or_null("CarouselRow") as HBoxContainer
	if carousel_row == null:
		carousel_row = HBoxContainer.new()
		carousel_row.name = "CarouselRow"
		add_child(carousel_row)
	carousel_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	carousel_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	carousel_row.add_theme_constant_override("separation", 10)

	btn_carousel_prev = carousel_row.get_node_or_null("PrevButton") as Button
	if btn_carousel_prev == null:
		btn_carousel_prev = Button.new()
		btn_carousel_prev.name = "PrevButton"
		carousel_row.add_child(btn_carousel_prev)
	btn_carousel_prev.text = "◀"
	btn_carousel_prev.custom_minimum_size = Vector2(40, 0)
	btn_carousel_prev.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_arrow_button(btn_carousel_prev)
	btn_carousel_prev.pressed.connect(scroll_prev)

	stage_scroll = carousel_row.get_node_or_null("StageScroll") as ScrollContainer
	if stage_scroll == null:
		stage_scroll = ScrollContainer.new()
		stage_scroll.name = "StageScroll"
		carousel_row.add_child(stage_scroll)
	stage_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_scroll.clip_contents = true
	stage_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	stage_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stage_scroll.follow_focus = true
	stage_scroll.scroll_deadzone = 12
	_Theme.apply_scroll_container(stage_scroll)

	stage_strip = stage_scroll.get_node_or_null("StageStrip") as HBoxContainer
	if stage_strip == null:
		stage_strip = HBoxContainer.new()
		stage_strip.name = "StageStrip"
		stage_scroll.add_child(stage_strip)
	stage_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_strip.add_theme_constant_override("separation", 16)

	btn_carousel_next = carousel_row.get_node_or_null("NextButton") as Button
	if btn_carousel_next == null:
		btn_carousel_next = Button.new()
		btn_carousel_next.name = "NextButton"
		carousel_row.add_child(btn_carousel_next)
	btn_carousel_next.text = "▶"
	btn_carousel_next.custom_minimum_size = Vector2(40, 0)
	btn_carousel_next.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_arrow_button(btn_carousel_next)
	btn_carousel_next.pressed.connect(scroll_next)

	var bottom_bar := get_node_or_null("BottomBar") as HBoxContainer
	if bottom_bar == null:
		bottom_bar = HBoxContainer.new()
		bottom_bar.name = "BottomBar"
		add_child(bottom_bar)
	bottom_bar.add_theme_constant_override("separation", 16)

	btn_stage_back = bottom_bar.get_node_or_null("BackButton") as Button
	if btn_stage_back == null:
		btn_stage_back = Button.new()
		btn_stage_back.name = "BackButton"
		bottom_bar.add_child(btn_stage_back)
	btn_stage_back.text = "◀ Volver"
	btn_stage_back.custom_minimum_size = Vector2(150, 40)
	_Theme.apply_tone_button(btn_stage_back, "chrome", 16, 18, 10)
	btn_stage_back.pressed.connect(func() -> void: back_requested.emit())

	var spacer := bottom_bar.get_node_or_null("Spacer") as Control
	if spacer == null:
		spacer = Control.new()
		spacer.name = "Spacer"
		bottom_bar.add_child(spacer)
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	carousel_page_label = bottom_bar.get_node_or_null("PageLabel") as Label
	if carousel_page_label == null:
		carousel_page_label = Label.new()
		carousel_page_label.name = "PageLabel"
		bottom_bar.add_child(carousel_page_label)
	carousel_page_label.add_theme_font_override("font", _Tokens.get_font("medium"))
	carousel_page_label.add_theme_font_size_override("font_size", 11)
	carousel_page_label.add_theme_color_override("font_color", _Tokens.get_color("accent_rally"))


func populate(config: Dictionary) -> void:
	_ensure_nodes()
	_cdi_mode = bool(config.get("cdi_mode", false))
	_selected_country = str(config.get("selected_country", "russia"))
	var country_order: Array = config.get("country_order", [])
	var country_labels: Dictionary = config.get("country_labels", {})
	var stage_ids: Array = config.get("stage_ids", [])
	var stage_metadata: Dictionary = config.get("stage_metadata", {})
	var cdi_stages: Dictionary = config.get("cdi_stages", {})
	var routes_cache: Dictionary = config.get("routes_cache", {})
	_stage_count = stage_ids.size()

	_stage_header.visible = _cdi_mode
	stage_title_label.text = str(config.get("title", ""))
	country_row.visible = not _cdi_mode
	btn_stage_back.visible = not _cdi_mode

	# Rebuild country tabs
	for child in country_row.get_children():
		country_row.remove_child(child)
		child.queue_free()
	country_buttons.clear()
	for i in country_order.size():
		var country := str(country_order[i])
		var cbtn := Button.new()
		cbtn.text = str(country_labels.get(country, country.capitalize()))
		cbtn.set_meta("country", country)
		cbtn.custom_minimum_size = Vector2(0, 44)
		cbtn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var target_c := country
		cbtn.pressed.connect(func() -> void: country_selected.emit(target_c))
		country_row.add_child(cbtn)
		country_buttons.append(cbtn)
		if i < country_order.size() - 1:
			var sep := ColorRect.new()
			sep.custom_minimum_size = Vector2(2, 22)
			sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sep.color = Color(_Tokens.get_color("accent_rally"), 0.72)
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			country_row.add_child(sep)
	update_country_buttons(_selected_country)

	# Rebuild stage cards
	for child in stage_strip.get_children():
		stage_strip.remove_child(child)
		child.queue_free()
	stage_buttons.clear()
	stage_previews.clear()
	carousel_scroll_index = 0
	if stage_scroll != null:
		stage_scroll.scroll_horizontal = 0

	var country_label := str(country_labels.get(_selected_country, _selected_country.capitalize()))
	var c_accent := _Tokens.get_color("accent_rally")
	var c_text := _Tokens.get_color("text_primary")
	var c_muted := _Tokens.get_color("text_muted")
	var c_gold_soft := _Tokens.get_color("text_gold_soft")

	for pos in stage_ids.size():
		var i := pos + 1
		var sid := str(stage_ids[pos])
		var s_text := "%s Stage %d" % [country_label, i]
		var meta_info: Dictionary = stage_metadata.get(sid, {"km": "5.0 KM", "surface": "Grava", "tag": "Tramo"})
		if _cdi_mode and cdi_stages.has(sid):
			meta_info = cdi_stages[sid]
			s_text = str(meta_info.get("name", s_text))

		var btn := Button.new()
		btn.text = s_text
		btn.set_meta("stage_id", sid)
		btn.custom_minimum_size = Vector2(258, 360)
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_style_stage_card(btn)

		var target_sid := sid
		btn.pressed.connect(func() -> void: stage_selected.emit(target_sid))

		var card_inner := MarginContainer.new()
		card_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_inner.add_theme_constant_override("margin_left", 14)
		card_inner.add_theme_constant_override("margin_right", 14)
		card_inner.add_theme_constant_override("margin_top", 12)
		card_inner.add_theme_constant_override("margin_bottom", 12)
		btn.add_child(card_inner)

		var card_vbox := VBoxContainer.new()
		card_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card_vbox.add_theme_constant_override("separation", 6)
		card_inner.add_child(card_vbox)

		var card_top_row := HBoxContainer.new()
		card_vbox.add_child(card_top_row)

		var lbl_stage_num := Label.new()
		lbl_stage_num.text = ("SS%02d" if _cdi_mode else "STAGE %02d") % i
		lbl_stage_num.add_theme_font_override("font", _Tokens.get_font("subtitle"))
		lbl_stage_num.add_theme_font_size_override("font_size", 12)
		lbl_stage_num.add_theme_color_override("font_color", c_accent)
		card_top_row.add_child(lbl_stage_num)

		var spacer_top := Control.new()
		spacer_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_top_row.add_child(spacer_top)

		var lbl_km := Label.new()
		lbl_km.text = str(meta_info.get("km", "5.0 KM"))
		if _cdi_mode:
			var cfg_path := "res://data/competition/stages/%s.json" % sid
			lbl_km.text = ""
			if FileAccess.file_exists(cfg_path):
				var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(cfg_path))
				if cfg is Dictionary:
					var distance := 0.0
					for sector in cfg.get("sector_lengths_km", []):
						distance += float(sector)
					lbl_km.text = "%.2f KM" % distance
		lbl_km.add_theme_font_override("font", _Tokens.get_font("data_bold_tight"))
		lbl_km.add_theme_font_size_override("font_size", 15)
		lbl_km.add_theme_color_override("font_color", c_text)
		card_top_row.add_child(lbl_km)

		var sep1 := ColorRect.new()
		sep1.custom_minimum_size = Vector2(0, 1)
		sep1.color = Color(1, 1, 1, 0.08)
		card_vbox.add_child(sep1)

		var norm_pts: PackedVector2Array = routes_cache.get(sid, PackedVector2Array())
		var route_preview := _RoutePreviewScript.new(norm_pts)
		route_preview.custom_minimum_size = Vector2(0, 160)
		route_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card_vbox.add_child(route_preview)
		stage_previews.append(route_preview)

		var sep2 := ColorRect.new()
		sep2.custom_minimum_size = Vector2(0, 1)
		sep2.color = Color(1, 1, 1, 0.06)
		card_vbox.add_child(sep2)

		var lbl_title := Label.new()
		lbl_title.text = s_text
		lbl_title.add_theme_font_override("font", _Tokens.get_font("subtitle"))
		lbl_title.add_theme_font_size_override("font_size", 18)
		lbl_title.add_theme_color_override("font_color", Color.WHITE)
		card_vbox.add_child(lbl_title)

		var bottom_info_row := HBoxContainer.new()
		card_vbox.add_child(bottom_info_row)

		var lbl_surface := Label.new()
		lbl_surface.text = str(meta_info.get("surface", "Grava"))
		lbl_surface.add_theme_font_override("font", _Tokens.get_font("regular"))
		lbl_surface.add_theme_font_size_override("font_size", 10)
		lbl_surface.add_theme_color_override("font_color", c_muted)
		bottom_info_row.add_child(lbl_surface)

		var spacer_bot := Control.new()
		spacer_bot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom_info_row.add_child(spacer_bot)

		var lbl_tag := Label.new()
		lbl_tag.text = "" if _cdi_mode else str(meta_info.get("tag", "Rally")).to_upper()
		lbl_tag.add_theme_font_override("font", _Tokens.get_font("subtitle"))
		lbl_tag.add_theme_font_size_override("font_size", 11)
		lbl_tag.add_theme_color_override("font_color", c_gold_soft)
		bottom_info_row.add_child(lbl_tag)

		var preview_ref := route_preview
		var stage_idx := pos
		btn.mouse_entered.connect(func() -> void: preview_ref.set_highlight(true))
		btn.mouse_exited.connect(func() -> void: preview_ref.set_highlight(btn.has_focus()))
		btn.focus_entered.connect(func() -> void:
			preview_ref.set_highlight(true)
			sync_carousel_on_focus(stage_idx)
		)
		btn.focus_exited.connect(func() -> void: preview_ref.set_highlight(false))

		_set_mouse_filter_recursive(card_inner, Control.MOUSE_FILTER_IGNORE)
		stage_strip.add_child(btn)
		stage_buttons.append(btn)

	update_carousel_ui()


func update_country_buttons(selected_country: String) -> void:
	_selected_country = selected_country
	for b in country_buttons:
		var c := str(b.get_meta("country", ""))
		var is_sel := (c == selected_country)
		b.disabled = is_sel
		b.modulate.a = 1.0
		_apply_minimal_tab_style(b, 22, 24, 8, is_sel)


func update_card_widths(viewport_width: float) -> void:
	if stage_scroll == null or stage_buttons.is_empty():
		return
	var vp_w := viewport_width if viewport_width > 100.0 else 1280.0
	var avail_w := vp_w - 96.0 - 80.0 - 20.0
	var gap := 16.0
	var card_w := maxf(floorf((avail_w - 3.0 * gap) / 4.0), 230.0)
	stage_scroll.custom_minimum_size.x = card_w * 4.0 + gap * 3.0
	for btn in stage_buttons:
		btn.custom_minimum_size.x = card_w


func carousel_max_index() -> int:
	return maxi(0, _stage_count - 4)


func scroll_prev() -> void:
	if carousel_scroll_index > 0:
		scroll_to_index(carousel_scroll_index - 1)


func scroll_next() -> void:
	if carousel_scroll_index < carousel_max_index():
		scroll_to_index(carousel_scroll_index + 1)


func scroll_to_index(idx: int) -> void:
	carousel_scroll_index = clampi(idx, 0, carousel_max_index())
	if stage_scroll == null or stage_buttons.is_empty():
		return
	var card_w: float = stage_buttons[0].custom_minimum_size.x
	var gap: float = 16.0
	var target_x: int = int(carousel_scroll_index * (card_w + gap))
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_property(stage_scroll, "scroll_horizontal", target_x, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		stage_scroll.scroll_horizontal = target_x
	update_carousel_ui()


func sync_carousel_on_focus(card_index: int) -> void:
	if card_index < carousel_scroll_index:
		scroll_to_index(card_index)
	elif card_index > carousel_scroll_index + 3:
		scroll_to_index(card_index - 3)


func update_carousel_ui() -> void:
	if btn_carousel_prev != null:
		btn_carousel_prev.disabled = (carousel_scroll_index <= 0)
		btn_carousel_prev.modulate.a = 0.35 if btn_carousel_prev.disabled else 1.0
	if btn_carousel_next != null:
		btn_carousel_next.disabled = (carousel_scroll_index >= carousel_max_index())
		btn_carousel_next.modulate.a = 0.35 if btn_carousel_next.disabled else 1.0
	if carousel_page_label != null:
		var total := maxi(1, _stage_count)
		carousel_page_label.text = "ETAPAS %d-%d DE %d" % [carousel_scroll_index + 1, mini(carousel_scroll_index + 4, total), total]


func _style_arrow_button(btn: Button) -> void:
	_Theme.apply_tone_button(btn, "chrome", 18, 6, 8)
	var accent := _Tokens.get_color("accent_rally")
	btn.add_theme_color_override("font_hover_color", accent)
	btn.add_theme_color_override("font_focus_color", accent)


func _style_stage_card(btn: Button) -> void:
	var c_card := _Tokens.get_color("bg_card")
	var c_hover := _Tokens.get_color("bg_hover")
	var c_pressed := _Tokens.get_color("bg_pressed")
	var c_border := _Tokens.get_color("border_card")
	var c_focus := _Tokens.get_color("border_focus")
	var c_accent := _Tokens.get_color("accent_rally")
	var r := _Tokens.get_radius("default")
	btn.add_theme_stylebox_override("normal", _Tokens.get_flat_stylebox(Color(c_card, 0.94), c_border, 1, r))
	btn.add_theme_stylebox_override("hover", _Tokens.get_flat_stylebox(Color(c_hover, 0.98), c_accent, 1, r))
	btn.add_theme_stylebox_override("focus", _Tokens.get_flat_stylebox(Color(c_hover, 0.98), c_focus, 2, r))
	btn.add_theme_stylebox_override("pressed", _Tokens.get_flat_stylebox(Color(c_pressed, 0.98), c_accent, 2, r))
	btn.add_theme_font_override("font", _Tokens.get_font("title"))
	btn.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))


func _apply_minimal_tab_style(btn: Button, font_size: int, pad_h: int, pad_v: int, is_selected: bool) -> void:
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
	var accent_dark := _Tokens.get_color("accent_rally_dark")
	var base_color := accent if is_selected else _Tokens.get_color("text_primary")
	btn.add_theme_color_override("font_color", base_color)
	btn.add_theme_color_override("font_focus_color", base_color)
	btn.add_theme_color_override("font_hover_color", accent)
	btn.add_theme_color_override("font_hover_pressed_color", accent)
	btn.add_theme_color_override("font_pressed_color", accent_dark)
	btn.add_theme_color_override("font_disabled_color", accent if is_selected else _Tokens.get_color("text_dim"))
	btn.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	btn.add_theme_constant_override("shadow_offset_x", 0)
	btn.add_theme_constant_override("shadow_offset_y", 2)
	btn.add_theme_constant_override("shadow_outline_size", 5)
	btn.mouse_default_cursor_shape = Control.CURSOR_ARROW if is_selected else Control.CURSOR_POINTING_HAND


func _set_mouse_filter_recursive(node: Node, filter_mode: Control.MouseFilter) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter_mode
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter_mode)
