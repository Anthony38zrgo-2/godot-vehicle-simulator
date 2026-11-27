class_name TireStrategyStep2View
extends Control
## Real Godot Control tree for Tire Strategy Step 2/2 (Palette backdrop, Weight rules, Trunk count selector, Stock bay).

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")

signal spare_count_selected(count: int)

var _mass_label: Label
var _count_buttons: Array[Button] = []
var _initialized: bool = false


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _initialized:
		return
	_initialized = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(1280.0, 800.0)

	var r := _Tokens.get_radius("default")
	var c_surf := _Tokens.get_color("bg_surface")
	var c_border := _Tokens.get_color("border_card")

	# 1. Palette panel backdrop (56, 104, 552, 114)
	var pal_panel := _make_box_panel(Rect2(56, 104, 552, 114), c_surf, c_border, r)
	pal_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pal_panel)
	var pal_title := Label.new()
	pal_title.text = "COMPUESTOS PERMITIDOS (ARRASTRA A MALETERO O RESERVA)"
	_Theme.apply_label(pal_title, "muted", 14, false, true)
	pal_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pal_panel.add_child(pal_title)

	# 2. Rules & weight notice panel (624, 104, 600, 114)
	var rules_panel := _make_box_panel(Rect2(624, 104, 600, 114), c_surf, c_border, r)
	rules_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rules_panel)
	var rules_vbox := VBoxContainer.new()
	rules_vbox.add_theme_constant_override("separation", 4)
	rules_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rules_panel.add_child(rules_vbox)
	var r_title := Label.new()
	r_title.text = "REGLAMENTO Y PESO EN MALETERO"
	_Theme.apply_label(r_title, "accent", 14, false, true)
	rules_vbox.add_child(r_title)
	for line_txt in [
		"• Cada rueda en el maletero añade +18 KG sobre el eje trasero.",
		"• Mueve repuestos al Inventario de Reserva si buscas aligerar el coche.",
		"• Pinchazos/rines se reparan en servicio.",
	]:
		var l := Label.new()
		l.text = line_txt
		_Theme.apply_label(l, "primary", 10, false, false)
		rules_vbox.add_child(l)

	# 3. Trunk panel (56, 228, 552, 442)
	var trunk_panel := _make_box_panel(Rect2(56, 228, 552, 442), c_surf, c_border, r)
	trunk_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(trunk_panel)
	var trunk_vbox := VBoxContainer.new()
	trunk_vbox.add_theme_constant_override("separation", 10)
	trunk_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trunk_panel.add_child(trunk_vbox)

	var trunk_head := HBoxContainer.new()
	trunk_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trunk_vbox.add_child(trunk_head)
	var trunk_title := Label.new()
	trunk_title.text = "MALETERO DEL COCHE (0, 1 O 2 REPUESTOS)"
	trunk_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_Theme.apply_label(trunk_title, "muted", 14, false, true)
	trunk_head.add_child(trunk_title)
	_mass_label = Label.new()
	_mass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_Theme.apply_label(_mass_label, "accent", 11, true, true)
	trunk_head.add_child(_mass_label)

	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 10)
	count_row.custom_minimum_size = Vector2(0, 34)
	trunk_vbox.add_child(count_row)
	_count_buttons.clear()
	for c in [0, 1, 2]:
		var btn := Button.new()
		btn.text = "%d REP." % c
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		var target_c: int = c
		btn.pressed.connect(func() -> void: spare_count_selected.emit(target_c))
		count_row.add_child(btn)
		_count_buttons.append(btn)

	# 4. Stock bay backdrop (624, 228, 600, 442)
	var stock_panel := _make_box_panel(Rect2(624, 228, 600, 442), c_surf, c_border, r)
	stock_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stock_panel)
	var s_title := Label.new()
	s_title.text = "INVENTARIO DE RESERVA"
	_Theme.apply_label(s_title, "muted", 15, false, true)
	s_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stock_panel.add_child(s_title)


func update_view(carried_spares_count: int, focus_id: String) -> void:
	_ensure_nodes()
	var mass_kg := carried_spares_count * 18.0
	_mass_label.text = "PESO EXTRA: +%0.0f KG" % mass_kg
	_mass_label.add_theme_color_override("font_color", _Tokens.get_color("accent_rally") if carried_spares_count > 0 else _Tokens.get_color("status_info"))

	var r := _Tokens.get_radius("default")
	var c_gold := _Tokens.get_color("accent_rally")
	var c_card := _Tokens.get_color("bg_card")
	var c_border := _Tokens.get_color("border_card")
	var c_focus := _Tokens.get_color("border_focus")
	var c_bg := _Tokens.get_color("bg_base")
	var c_text := _Tokens.get_color("text_primary")
	for c in _count_buttons.size():
		var btn := _count_buttons[c]
		var sel := carried_spares_count == c
		var is_focused := focus_id == ("count:%d" % c)
		var sb := _Tokens.get_flat_stylebox(c_gold if sel else c_card, c_focus if is_focused else (Color("#f6c96e") if sel else c_border), 2 if is_focused else 1, r, 8, 4)
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, sb)
		btn.add_theme_font_override("font", _Tokens.get_font("button"))
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", c_bg if sel else c_text)
		btn.add_theme_color_override("font_hover_color", c_bg if sel else Color.WHITE)


func _make_box_panel(rect: Rect2, bg: Color, border: Color, radius: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(bg, border, 1, radius, 14, 10))
	return p
