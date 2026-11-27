class_name CarSelectView
extends VBoxContainer
## Editorial car selector view with livery palette and inline technical specs strip.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")

signal car_pressed(car_key: String)
signal confirm_pressed
signal back_requested
signal livery_selected(livery_id: String)
signal livery_cycled(delta: int)

var car_title: Label
var car_scroll: ScrollContainer
var car_buttons: Array[Button] = []
var btn_back: Button
var btn_confirm: Button

var livery_panel: PanelContainer
var livery_name_label: Label
var livery_hex_label: Label
var livery_buttons: Array[Button] = []
var btn_livery_prev: Button
var btn_livery_next: Button

var preview_car_title: Label
var preview_car_category: Label
var preview_layout_badge: Label

var spec_power_val: Label
var spec_power_sub: Label
var spec_gears_val: Label
var spec_gears_sub: Label
var spec_wb_val: Label
var spec_wb_sub: Label
var spec_track_val: Label
var spec_track_sub: Label
var spec_mass_val: Label
var spec_mass_sub: Label
var spec_layout_val: Label
var spec_layout_sub: Label

var _car_header: HBoxContainer
var _car_sub: Label
var _cars_vbox: VBoxContainer
var _swatch_row: HBoxContainer
var _initialized: bool = false


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _initialized:
		return
	_initialized = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)

	var c_accent := _Tokens.get_color("accent_rally")
	var c_text := _Tokens.get_color("text_primary")
	var c_muted := _Tokens.get_color("text_muted")
	var c_gold_soft := _Tokens.get_color("text_gold_soft")

	_car_header = get_node_or_null("CarHeader") as HBoxContainer
	if _car_header == null:
		_car_header = HBoxContainer.new()
		_car_header.name = "CarHeader"
		add_child(_car_header)

	car_title = _car_header.get_node_or_null("CarTitle") as Label
	if car_title == null:
		car_title = Label.new()
		car_title.name = "CarTitle"
		_car_header.add_child(car_title)
	car_title.text = "Select Car"
	car_title.add_theme_font_override("font", _Tokens.get_font("title"))
	car_title.add_theme_font_size_override("font_size", 18)
	car_title.add_theme_color_override("font_color", c_accent)

	_car_sub = _car_header.get_node_or_null("CarSubtitle") as Label
	if _car_sub == null:
		_car_sub = Label.new()
		_car_sub.name = "CarSubtitle"
		_car_header.add_child(_car_sub)
	_car_sub.text = "   · Selección de vehículo y especificaciones de homologación"
	_car_sub.add_theme_font_override("font", _Tokens.get_font("subtitle"))
	_car_sub.add_theme_font_size_override("font_size", 13)
	_car_sub.add_theme_color_override("font_color", c_muted)

	var main_split := get_node_or_null("MainSplit") as HBoxContainer
	if main_split == null:
		main_split = HBoxContainer.new()
		main_split.name = "MainSplit"
		add_child(main_split)
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.add_theme_constant_override("separation", 28)

	# Left column: vehicle list
	var list_vbox := main_split.get_node_or_null("ListColumn") as VBoxContainer
	if list_vbox == null:
		list_vbox = VBoxContainer.new()
		list_vbox.name = "ListColumn"
		main_split.add_child(list_vbox)
	list_vbox.custom_minimum_size = Vector2(280, 0)
	list_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 8)

	car_scroll = list_vbox.get_node_or_null("CarScroll") as ScrollContainer
	if car_scroll == null:
		car_scroll = ScrollContainer.new()
		car_scroll.name = "CarScroll"
		list_vbox.add_child(car_scroll)
	car_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	car_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	car_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	car_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	car_scroll.follow_focus = true
	_Theme.apply_scroll_container(car_scroll)

	var cars_margin := car_scroll.get_node_or_null("CarsMargin") as MarginContainer
	if cars_margin == null:
		cars_margin = MarginContainer.new()
		cars_margin.name = "CarsMargin"
		car_scroll.add_child(cars_margin)
	cars_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cars_margin.add_theme_constant_override("margin_left", 0)
	cars_margin.add_theme_constant_override("margin_right", 8)
	cars_margin.add_theme_constant_override("margin_top", 4)
	cars_margin.add_theme_constant_override("margin_bottom", 4)

	_cars_vbox = cars_margin.get_node_or_null("CarsVBox") as VBoxContainer
	if _cars_vbox == null:
		_cars_vbox = VBoxContainer.new()
		_cars_vbox.name = "CarsVBox"
		cars_margin.add_child(_cars_vbox)
	_cars_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cars_vbox.add_theme_constant_override("separation", 4)

	# Right column: showroom title, livery bar, specs strip
	var right_vbox := main_split.get_node_or_null("RightColumn") as VBoxContainer
	if right_vbox == null:
		right_vbox = VBoxContainer.new()
		right_vbox.name = "RightColumn"
		main_split.add_child(right_vbox)
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 10)

	var title_bar := right_vbox.get_node_or_null("TitleBar") as HBoxContainer
	if title_bar == null:
		title_bar = HBoxContainer.new()
		title_bar.name = "TitleBar"
		right_vbox.add_child(title_bar)
	title_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	title_bar.add_theme_constant_override("separation", 12)

	var balance_sp := title_bar.get_node_or_null("BalanceSpacer") as Control
	if balance_sp == null:
		balance_sp = Control.new()
		balance_sp.name = "BalanceSpacer"
		title_bar.add_child(balance_sp)
	balance_sp.custom_minimum_size = Vector2(54, 0)
	balance_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title_vbox := title_bar.get_node_or_null("TitleVBox") as VBoxContainer
	if title_vbox == null:
		title_vbox = VBoxContainer.new()
		title_vbox.name = "TitleVBox"
		title_bar.add_child(title_vbox)
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 2)

	preview_car_title = title_vbox.get_node_or_null("PreviewTitle") as Label
	if preview_car_title == null:
		preview_car_title = Label.new()
		preview_car_title.name = "PreviewTitle"
		title_vbox.add_child(preview_car_title)
	preview_car_title.text = "---"
	preview_car_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_car_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_car_title.add_theme_font_override("font", _Tokens.get_font("subtitle"))
	preview_car_title.add_theme_font_size_override("font_size", 28)
	preview_car_title.add_theme_color_override("font_color", c_text)

	preview_car_category = title_vbox.get_node_or_null("PreviewCategory") as Label
	if preview_car_category == null:
		preview_car_category = Label.new()
		preview_car_category.name = "PreviewCategory"
		title_vbox.add_child(preview_car_category)
	preview_car_category.text = "HISTORIC RALLY SPECIFICATION"
	preview_car_category.add_theme_font_override("font", _Tokens.get_font("regular"))
	preview_car_category.add_theme_font_size_override("font_size", 10)
	preview_car_category.add_theme_color_override("font_color", c_muted)
	preview_car_category.hide()

	var badge_box := title_bar.get_node_or_null("LayoutBadgeBox") as PanelContainer
	if badge_box == null:
		badge_box = PanelContainer.new()
		badge_box.name = "LayoutBadgeBox"
		title_bar.add_child(badge_box)
	badge_box.custom_minimum_size = Vector2(54, 30)
	badge_box.add_theme_stylebox_override(
		"panel",
		_Tokens.get_flat_stylebox(_Tokens.get_color("bg_card"), Color(c_accent, 0.75), 1, _Tokens.get_radius("default"), 8, 2)
	)

	preview_layout_badge = badge_box.get_node_or_null("LayoutBadge") as Label
	if preview_layout_badge == null:
		preview_layout_badge = Label.new()
		preview_layout_badge.name = "LayoutBadge"
		badge_box.add_child(preview_layout_badge)
	preview_layout_badge.text = "FR"
	preview_layout_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_layout_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_layout_badge.add_theme_font_override("font", _Tokens.get_font("subtitle"))
	preview_layout_badge.add_theme_font_size_override("font_size", 16)
	preview_layout_badge.add_theme_color_override("font_color", c_gold_soft)

	var showroom_sp := right_vbox.get_node_or_null("ShowroomSpacer") as Control
	if showroom_sp == null:
		showroom_sp = Control.new()
		showroom_sp.name = "ShowroomSpacer"
		right_vbox.add_child(showroom_sp)
	showroom_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Livery bar
	livery_panel = right_vbox.get_node_or_null("LiveryPanel") as PanelContainer
	if livery_panel == null:
		livery_panel = PanelContainer.new()
		livery_panel.name = "LiveryPanel"
		right_vbox.add_child(livery_panel)
	livery_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	livery_panel.add_theme_stylebox_override(
		"panel",
		_Tokens.get_flat_stylebox(Color(0.04, 0.055, 0.08, 0.90), _Tokens.get_color("border_subtle"), 1, _Tokens.get_radius("default"), 16, 9)
	)

	var livery_vbox := livery_panel.get_node_or_null("LiveryVBox") as VBoxContainer
	if livery_vbox == null:
		livery_vbox = VBoxContainer.new()
		livery_vbox.name = "LiveryVBox"
		livery_panel.add_child(livery_vbox)
	livery_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	livery_vbox.add_theme_constant_override("separation", 7)

	var livery_header := livery_vbox.get_node_or_null("LiveryHeader") as HBoxContainer
	if livery_header == null:
		livery_header = HBoxContainer.new()
		livery_header.name = "LiveryHeader"
		livery_vbox.add_child(livery_header)
	livery_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	livery_header.add_theme_constant_override("separation", 10)

	var livery_tag := Label.new()
	livery_tag.text = "COLOR / LIVERY"
	livery_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	livery_tag.add_theme_font_override("font", _Tokens.get_font("medium"))
	livery_tag.add_theme_font_size_override("font_size", 9)
	livery_tag.add_theme_color_override("font_color", c_muted)
	livery_header.add_child(livery_tag)

	livery_name_label = Label.new()
	livery_name_label.text = "---"
	livery_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	livery_name_label.add_theme_font_override("font", _Tokens.get_font("subtitle"))
	livery_name_label.add_theme_font_size_override("font_size", 15)
	livery_name_label.add_theme_color_override("font_color", c_text)
	livery_header.add_child(livery_name_label)

	livery_hex_label = Label.new()
	livery_hex_label.text = ""
	livery_hex_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	livery_hex_label.add_theme_font_override("font", _Tokens.get_font("medium"))
	livery_hex_label.add_theme_font_size_override("font_size", 10)
	livery_hex_label.add_theme_color_override("font_color", c_gold_soft)
	livery_header.add_child(livery_hex_label)

	var liv_sp := Control.new()
	liv_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	livery_header.add_child(liv_sp)

	var livery_hint := Label.new()
	livery_hint.text = "◀ / ▶  CAMBIAR COLOR"
	livery_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	livery_hint.add_theme_font_override("font", _Tokens.get_font("medium"))
	livery_hint.add_theme_font_size_override("font_size", 9)
	livery_hint.add_theme_color_override("font_color", Color(c_muted, 0.80))
	livery_header.add_child(livery_hint)

	btn_livery_prev = Button.new()
	btn_livery_prev.text = "◀"
	btn_livery_prev.custom_minimum_size = Vector2(28, 22)
	btn_livery_prev.focus_mode = Control.FOCUS_NONE
	_Theme.apply_tone_button(btn_livery_prev, "chrome", 11, 4, 2)
	btn_livery_prev.add_theme_color_override("font_hover_color", c_accent)
	btn_livery_prev.add_theme_color_override("font_focus_color", c_accent)
	btn_livery_prev.pressed.connect(func() -> void: livery_cycled.emit(-1))
	livery_header.add_child(btn_livery_prev)

	btn_livery_next = Button.new()
	btn_livery_next.text = "▶"
	btn_livery_next.custom_minimum_size = Vector2(28, 22)
	btn_livery_next.focus_mode = Control.FOCUS_NONE
	_Theme.apply_tone_button(btn_livery_next, "chrome", 11, 4, 2)
	btn_livery_next.add_theme_color_override("font_hover_color", c_accent)
	btn_livery_next.add_theme_color_override("font_focus_color", c_accent)
	btn_livery_next.pressed.connect(func() -> void: livery_cycled.emit(1))
	livery_header.add_child(btn_livery_next)

	_swatch_row = HBoxContainer.new()
	_swatch_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_swatch_row.add_theme_constant_override("separation", 6)
	livery_vbox.add_child(_swatch_row)

	# Technical specs strip
	var specs_panel := right_vbox.get_node_or_null("SpecsPanel") as PanelContainer
	if specs_panel == null:
		specs_panel = PanelContainer.new()
		specs_panel.name = "SpecsPanel"
		right_vbox.add_child(specs_panel)
	specs_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	specs_panel.add_theme_stylebox_override(
		"panel",
		_Tokens.get_flat_stylebox(Color(0.04, 0.055, 0.08, 0.90), _Tokens.get_color("border_subtle"), 1, _Tokens.get_radius("default"), 16, 10)
	)

	var specs_strip := HBoxContainer.new()
	specs_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	specs_strip.add_theme_constant_override("separation", 12)
	specs_panel.add_child(specs_strip)

	spec_power_val = Label.new()
	spec_power_sub = Label.new()
	specs_strip.add_child(_make_spec_item("Potencia", spec_power_val, spec_power_sub, 1.25))
	specs_strip.add_child(_make_spec_divider())

	spec_gears_val = Label.new()
	spec_gears_sub = Label.new()
	specs_strip.add_child(_make_spec_item("Marchas", spec_gears_val, spec_gears_sub, 1.05))
	specs_strip.add_child(_make_spec_divider())

	spec_wb_val = Label.new()
	spec_wb_sub = Label.new()
	specs_strip.add_child(_make_spec_item("Batalla", spec_wb_val, spec_wb_sub, 1.05))
	specs_strip.add_child(_make_spec_divider())

	spec_track_val = Label.new()
	spec_track_sub = Label.new()
	specs_strip.add_child(_make_spec_item("Trochas", spec_track_val, spec_track_sub, 1.15))
	specs_strip.add_child(_make_spec_divider())

	spec_mass_val = Label.new()
	spec_mass_sub = Label.new()
	specs_strip.add_child(_make_spec_item("Peso Mínimo", spec_mass_val, spec_mass_sub, 1.15))
	specs_strip.add_child(_make_spec_divider())

	spec_layout_val = Label.new()
	spec_layout_sub = Label.new()
	specs_strip.add_child(_make_spec_item("Configuración", spec_layout_val, spec_layout_sub, 2.0))

	# Bottom bar
	var bottom_bar := get_node_or_null("BottomBar") as HBoxContainer
	if bottom_bar == null:
		bottom_bar = HBoxContainer.new()
		bottom_bar.name = "BottomBar"
		add_child(bottom_bar)
	bottom_bar.add_theme_constant_override("separation", 16)

	btn_back = bottom_bar.get_node_or_null("BackButton") as Button
	if btn_back == null:
		btn_back = Button.new()
		btn_back.name = "BackButton"
		bottom_bar.add_child(btn_back)
	btn_back.text = "◀ Volver"
	btn_back.custom_minimum_size = Vector2(140, 42)
	_Theme.apply_tone_button(btn_back, "chrome", 16, 18, 10)
	btn_back.pressed.connect(func() -> void: back_requested.emit())

	var bot_sp := bottom_bar.get_node_or_null("Spacer") as Control
	if bot_sp == null:
		bot_sp = Control.new()
		bot_sp.name = "Spacer"
		bottom_bar.add_child(bot_sp)
	bot_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	btn_confirm = bottom_bar.get_node_or_null("ConfirmButton") as Button
	if btn_confirm == null:
		btn_confirm = Button.new()
		btn_confirm.name = "ConfirmButton"
		bottom_bar.add_child(btn_confirm)
	btn_confirm.text = "Seleccionar y Conducir ▶"
	btn_confirm.custom_minimum_size = Vector2(264, 44)
	_Theme.apply_tone_button(btn_confirm, "gold", 17, 24, 11)
	btn_confirm.pressed.connect(func() -> void: confirm_pressed.emit())


func populate_vehicles(vehicles: Dictionary, cdi_mode: bool, cdi_cars: Array) -> void:
	_ensure_nodes()
	_car_header.visible = cdi_mode
	_car_sub.visible = not cdi_mode
	for child in _cars_vbox.get_children():
		_cars_vbox.remove_child(child)
		child.queue_free()
	car_buttons.clear()
	for car_key in vehicles:
		if cdi_mode and car_key not in cdi_cars:
			continue
		var v_data: Dictionary = vehicles[car_key]
		var btn := Button.new()
		btn.text = str(v_data.get("DisplayName", car_key))
		btn.set_meta("car_key", str(car_key))
		btn.custom_minimum_size = Vector2(0, 46)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var k := str(car_key)
		btn.pressed.connect(func() -> void: car_pressed.emit(k))
		_cars_vbox.add_child(btn)
		car_buttons.append(btn)


func populate_liveries(liveries: Array) -> void:
	_ensure_nodes()
	for child in _swatch_row.get_children():
		_swatch_row.remove_child(child)
		child.queue_free()
	livery_buttons.clear()
	for entry in liveries:
		var lid := str(entry.get("id", ""))
		var lname := str(entry.get("name", lid))
		var lhex := str(entry.get("hex", "#FFFFFF"))
		var sbtn := Button.new()
		sbtn.text = ""
		sbtn.tooltip_text = "%s (%s)" % [lname, lhex]
		sbtn.custom_minimum_size = Vector2(24, 24)
		sbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sbtn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		sbtn.set_meta("livery_id", lid)
		sbtn.set_meta("livery_name", lname)
		sbtn.set_meta("livery_hex", lhex)
		var target_lid := lid
		sbtn.pressed.connect(func() -> void: livery_selected.emit(target_lid))
		sbtn.focus_entered.connect(func() -> void: livery_selected.emit(target_lid))
		_swatch_row.add_child(sbtn)
		livery_buttons.append(sbtn)


func update_car_list_visuals(selected_car_key: String) -> void:
	for btn in car_buttons:
		var is_sel := (str(btn.get_meta("car_key", "")) == selected_car_key)
		_Theme.apply_editorial_item(btn, is_sel, 17, 9)
		btn.add_theme_font_override("font", _Tokens.get_font("subtitle"))
		if is_sel:
			btn.add_theme_font_size_override("font_size", 19)


func update_livery_visuals(selected_livery_id: String, livery_entry: Dictionary) -> void:
	if livery_name_label != null:
		livery_name_label.text = str(livery_entry.get("name", "---")).to_upper()
	if livery_hex_label != null:
		livery_hex_label.text = str(livery_entry.get("hex", ""))
	var accent := _Tokens.get_color("accent_rally")
	var r := _Tokens.get_radius("technical")
	for btn in livery_buttons:
		var lid := str(btn.get_meta("livery_id", ""))
		var lhex := str(btn.get_meta("livery_hex", "#FFFFFF"))
		var swatch_color := Color.from_string(lhex, Color.WHITE)
		var is_sel := (lid == selected_livery_id)
		var normal := _Tokens.get_flat_stylebox(swatch_color, accent if is_sel else Color(1.0, 1.0, 1.0, 0.28), 2 if is_sel else 1, r)
		var hover := _Tokens.get_flat_stylebox(swatch_color, accent if is_sel else Color.WHITE, 2, r)
		var focus := _Tokens.get_flat_stylebox(swatch_color, accent, 2, r)
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("focus", focus)
		btn.add_theme_stylebox_override("pressed", focus)
		btn.add_theme_stylebox_override("disabled", normal)


func update_specs(display_name: String, specs: Dictionary) -> void:
	if preview_car_title != null:
		preview_car_title.text = display_name
	if preview_car_category != null:
		preview_car_category.text = "HISTORIC RALLY SPECIFICATION · " + str(specs.get("layout_name", "")).to_upper()
	if preview_layout_badge != null:
		preview_layout_badge.text = str(specs.get("layout_code", "FR"))
	if spec_power_val != null:
		spec_power_val.text = str(specs.get("power_str", "---"))
		spec_power_sub.text = str(specs.get("power_sub", ""))
	if spec_gears_val != null:
		spec_gears_val.text = str(specs.get("gears_str", "---"))
		spec_gears_sub.text = str(specs.get("gears_sub", ""))
	if spec_wb_val != null:
		spec_wb_val.text = str(specs.get("wb_str", "---"))
		spec_wb_sub.text = str(specs.get("wb_sub", ""))
	if spec_track_val != null:
		spec_track_val.text = str(specs.get("track_str", "---"))
		spec_track_sub.text = str(specs.get("track_sub", ""))
	if spec_mass_val != null:
		spec_mass_val.text = str(specs.get("mass_str", "---"))
		spec_mass_sub.text = str(specs.get("mass_sub", ""))
	if spec_layout_val != null:
		spec_layout_val.text = str(specs.get("layout_code", "---")) + " · " + str(specs.get("layout_name", ""))
		spec_layout_sub.text = str(specs.get("layout_sub", ""))


func _make_spec_item(title: String, val_label: Label, sub_label: Label, stretch: float) -> VBoxContainer:
	var item_vbox := VBoxContainer.new()
	item_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_vbox.size_flags_stretch_ratio = stretch
	item_vbox.add_theme_constant_override("separation", 1)

	var c_muted := _Tokens.get_color("text_muted")
	var lbl_title := Label.new()
	lbl_title.text = title.to_upper()
	lbl_title.add_theme_font_override("font", _Tokens.get_font("medium"))
	lbl_title.add_theme_font_size_override("font_size", 9)
	lbl_title.add_theme_color_override("font_color", c_muted)
	item_vbox.add_child(lbl_title)

	val_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_label.add_theme_font_override("font", _Tokens.get_font("data_bold_tight"))
	val_label.add_theme_font_size_override("font_size", 12)
	val_label.add_theme_color_override("font_color", _Tokens.get_color("text_primary"))
	item_vbox.add_child(val_label)

	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_label.add_theme_font_override("font", _Tokens.get_font("regular"))
	sub_label.add_theme_font_size_override("font_size", 8)
	sub_label.add_theme_color_override("font_color", Color(c_muted, 0.70))
	item_vbox.add_child(sub_label)
	return item_vbox


func _make_spec_divider() -> ColorRect:
	var div := ColorRect.new()
	div.custom_minimum_size = Vector2(1, 28)
	div.color = Color(1, 1, 1, 0.08)
	div.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return div
