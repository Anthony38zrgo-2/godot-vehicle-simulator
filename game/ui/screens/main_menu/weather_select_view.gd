class_name WeatherSelectView
extends VBoxContainer
## Data-Driven initial weather selection screen driven by res://data/ui/menus/weather_options.json.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _Catalog := preload("res://scripts/ui/services/menu_catalog_service.gd")

signal weather_selected(weather_id: String)
signal weather_confirmed(weather_id: String)
signal back_requested

var weather_buttons: Array[Button] = []
var btn_back: Button
var btn_confirm: Button
var selected_weather: String = "random"
var _cards_hbox: HBoxContainer


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _cards_hbox != null:
		return
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 16)

	var header := get_node_or_null("WeatherHeader") as HBoxContainer
	if header == null:
		header = HBoxContainer.new()
		header.name = "WeatherHeader"
		add_child(header)

	var title_lbl := header.get_node_or_null("TitleLabel") as Label
	if title_lbl == null:
		title_lbl = Label.new()
		title_lbl.name = "TitleLabel"
		header.add_child(title_lbl)
	title_lbl.text = "CLIMA INICIAL"
	title_lbl.add_theme_font_override("font", _Tokens.get_font("title"))
	title_lbl.add_theme_font_size_override("font_size", 19)
	title_lbl.add_theme_color_override("font_color", _Tokens.get_color("accent_rally"))

	var top_sp := get_node_or_null("TopSpacer") as Control
	if top_sp == null:
		top_sp = Control.new()
		top_sp.name = "TopSpacer"
		top_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		top_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(top_sp)

	_cards_hbox = get_node_or_null("CardsHBox") as HBoxContainer
	if _cards_hbox == null:
		_cards_hbox = HBoxContainer.new()
		_cards_hbox.name = "CardsHBox"
		_cards_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cards_hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_cards_hbox.add_theme_constant_override("separation", 18)
		add_child(_cards_hbox)

	_populate_cards()

	var bot_sp := get_node_or_null("BottomSpacer") as Control
	if bot_sp == null:
		bot_sp = Control.new()
		bot_sp.name = "BottomSpacer"
		bot_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		bot_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bot_sp)

	var bottom_bar := get_node_or_null("BottomBar") as HBoxContainer
	if bottom_bar == null:
		bottom_bar = HBoxContainer.new()
		bottom_bar.name = "BottomBar"
		bottom_bar.add_theme_constant_override("separation", 16)
		add_child(bottom_bar)

	btn_back = bottom_bar.get_node_or_null("BackButton") as Button
	if btn_back == null:
		btn_back = Button.new()
		btn_back.name = "BackButton"
		bottom_bar.add_child(btn_back)
	btn_back.text = "◀ Volver"
	btn_back.custom_minimum_size = Vector2(140, 40)
	_Theme.apply_tone_button(btn_back, "chrome", 16, 18, 10)
	if not btn_back.pressed.is_connected(func() -> void: back_requested.emit()):
		btn_back.pressed.connect(func() -> void: back_requested.emit())

	var bar_sp := bottom_bar.get_node_or_null("BarSpacer") as Control
	if bar_sp == null:
		bar_sp = Control.new()
		bar_sp.name = "BarSpacer"
		bar_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom_bar.add_child(bar_sp)

	btn_confirm = bottom_bar.get_node_or_null("ConfirmButton") as Button
	if btn_confirm == null:
		btn_confirm = Button.new()
		btn_confirm.name = "ConfirmButton"
		bottom_bar.add_child(btn_confirm)
	btn_confirm.text = "Comenzar Rally ▶"
	btn_confirm.custom_minimum_size = Vector2(240, 40)
	_Theme.apply_tone_button(btn_confirm, "gold", 16, 22, 10)
	if not btn_confirm.pressed.is_connected(func() -> void: weather_confirmed.emit(selected_weather)):
		btn_confirm.pressed.connect(func() -> void: weather_confirmed.emit(selected_weather))

	update_cards_visuals()


func _populate_cards() -> void:
	for child in _cards_hbox.get_children():
		_cards_hbox.remove_child(child)
		child.queue_free()
	weather_buttons.clear()
	var doc := _Catalog.get_weather_options()
	var options: Array = doc.get("options", [])
	for opt_var in options:
		if not (opt_var is Dictionary):
			continue
		var opt := opt_var as Dictionary
		var wid := str(opt.get("id", "random"))
		var wtitle := str(opt.get("title", ""))
		var wicon := str(opt.get("icon", ""))
		var wsvg := str(opt.get("svg", ""))
		var wsummary := str(opt.get("summary", ""))

		var btn := Button.new()
		btn.text = wtitle
		btn.set_meta("weather_id", wid)
		btn.custom_minimum_size = Vector2(230, 320)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var target_wid := wid
		btn.pressed.connect(func() -> void:
			if selected_weather == target_wid:
				weather_confirmed.emit(target_wid)
			else:
				set_selected_weather(target_wid)
				weather_selected.emit(target_wid)
		)
		btn.focus_entered.connect(func() -> void:
			set_selected_weather(target_wid)
			weather_selected.emit(target_wid)
		)

		var card_inner := MarginContainer.new()
		card_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_inner.add_theme_constant_override("margin_left", 18)
		card_inner.add_theme_constant_override("margin_right", 18)
		card_inner.add_theme_constant_override("margin_top", 16)
		card_inner.add_theme_constant_override("margin_bottom", 18)
		btn.add_child(card_inner)

		var card_vbox := VBoxContainer.new()
		card_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card_vbox.add_theme_constant_override("separation", 10)
		card_inner.add_child(card_vbox)

		var mid_top := Control.new()
		mid_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card_vbox.add_child(mid_top)

		var center_block := VBoxContainer.new()
		center_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center_block.add_theme_constant_override("separation", 10)
		card_vbox.add_child(center_block)

		if not wsvg.is_empty() and ResourceLoader.exists(wsvg):
			var icon_rect := TextureRect.new()
			icon_rect.texture = load(wsvg) as Texture2D
			icon_rect.custom_minimum_size = Vector2(56, 56)
			icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.modulate = Color("#f3f6f9")
			center_block.add_child(icon_rect)
		else:
			var lbl_icon := Label.new()
			lbl_icon.text = wicon
			lbl_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl_icon.add_theme_font_override("font", _Tokens.get_font("regular"))
			lbl_icon.add_theme_font_size_override("font_size", 52)
			lbl_icon.add_theme_color_override("font_color", Color("#f3f6f9"))
			center_block.add_child(lbl_icon)

		var lbl_name := Label.new()
		lbl_name.text = wtitle
		lbl_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_name.add_theme_font_override("font", _Tokens.get_font("title"))
		lbl_name.add_theme_font_size_override("font_size", 26)
		lbl_name.add_theme_color_override("font_color", Color.WHITE)
		center_block.add_child(lbl_name)

		var div2 := ColorRect.new()
		div2.custom_minimum_size = Vector2(0, 1)
		div2.color = Color(1, 1, 1, 0.08)
		center_block.add_child(div2)

		var lbl_desc := Label.new()
		lbl_desc.text = wsummary
		lbl_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl_desc.add_theme_font_override("font", _Tokens.get_font("regular"))
		lbl_desc.add_theme_font_size_override("font_size", 11)
		lbl_desc.add_theme_color_override("font_color", Color("#cbd5e1"))
		center_block.add_child(lbl_desc)

		var mid_bot := Control.new()
		mid_bot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card_vbox.add_child(mid_bot)

		_set_mouse_filter_recursive(card_inner, Control.MOUSE_FILTER_IGNORE)
		_cards_hbox.add_child(btn)
		weather_buttons.append(btn)


func set_selected_weather(wid: String) -> void:
	selected_weather = wid
	update_cards_visuals()


func update_cards_visuals() -> void:
	var accent := _Tokens.get_color("accent_rally")
	for btn in weather_buttons:
		var wid := str(btn.get_meta("weather_id", ""))
		var is_sel := (wid == selected_weather)
		_Theme.apply_card_surface(btn, is_sel, 14, 0, 0, accent)
		btn.add_theme_color_override("font_color", Color(0, 0, 0, 0))
		btn.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
		btn.add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
		btn.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))


func _set_mouse_filter_recursive(node: Node, filter_mode: Control.MouseFilter) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter_mode
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter_mode)
