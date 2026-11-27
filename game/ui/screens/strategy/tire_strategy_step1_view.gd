class_name TireStrategyStep1View
extends Control
## Real Godot Control tree for Tire Strategy Step 1/2 (Weather Forecast, Compound Presets, Mounted Bay backdrop).

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _Tire3DView := preload("res://scripts/rally/rally_tire_3d_view.gd")

signal preset_selected(compound_id: String)

var _s1_value: Label
var _s2_value: Label
var _prob_label: Label
var _selector_title: Label
var _preset_row: HBoxContainer
var _preset_buttons: Array[Button] = []
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
	var c_well := _Tokens.get_color("bg_well")
	var c_border := _Tokens.get_color("border_card")
	var c_subtle := _Tokens.get_color("border_subtle")
	var c_text := _Tokens.get_color("text_primary")
	var c_muted := _Tokens.get_color("text_muted")
	var c_accent := _Tokens.get_color("accent_rally")
	var c_gold_hi := _Tokens.get_color("text_gold_soft")
	var c_info := _Tokens.get_color("status_info")

	# 1. Weather panel (56, 104, 552, 250)
	var weather_panel := _make_box_panel(Rect2(56, 104, 552, 250), c_surf, c_border, r)
	add_child(weather_panel)
	var w_vbox := VBoxContainer.new()
	w_vbox.add_theme_constant_override("separation", 10)
	weather_panel.add_child(w_vbox)

	var w_title := Label.new()
	w_title.text = "INFORMACIÓN CLIMÁTICA DEL EVENTO"
	_Theme.apply_label(w_title, "muted", 15, false, true)
	w_vbox.add_child(w_title)

	var w_sep := ColorRect.new()
	w_sep.custom_minimum_size = Vector2(0, 1)
	w_sep.color = Color(c_border, 0.45)
	w_vbox.add_child(w_sep)

	var row1 := PanelContainer.new()
	row1.custom_minimum_size = Vector2(0, 72)
	row1.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_well, c_subtle, 1, r, 14, 10))
	w_vbox.add_child(row1)
	var r1_h := HBoxContainer.new()
	r1_h.add_theme_constant_override("separation", 12)
	row1.add_child(r1_h)
	var r1_k := Label.new()
	r1_k.text = "STAGE 1 (ACTUAL):"
	r1_k.custom_minimum_size = Vector2(175, 0)
	r1_k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_Theme.apply_label(r1_k, "primary", 10, false, false)
	r1_h.add_child(r1_k)
	_s1_value = Label.new()
	_s1_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_s1_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_Theme.apply_label(_s1_value, "accent", 13, true, true)
	_s1_value.add_theme_color_override("font_color", c_gold_hi)
	r1_h.add_child(_s1_value)

	var row2 := PanelContainer.new()
	row2.custom_minimum_size = Vector2(0, 88)
	row2.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_well, c_subtle, 1, r, 14, 10))
	w_vbox.add_child(row2)
	var r2_h := HBoxContainer.new()
	r2_h.add_theme_constant_override("separation", 12)
	row2.add_child(r2_h)
	var r2_k := Label.new()
	r2_k.text = "STAGE 2 (PRONÓSTICO):"
	r2_k.custom_minimum_size = Vector2(175, 0)
	r2_k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_Theme.apply_label(r2_k, "primary", 10, false, false)
	r2_h.add_child(r2_k)
	var r2_right := VBoxContainer.new()
	r2_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2_right.alignment = BoxContainer.ALIGNMENT_CENTER
	r2_right.add_theme_constant_override("separation", 6)
	r2_h.add_child(r2_right)
	_s2_value = Label.new()
	_Theme.apply_label(_s2_value, "info", 12, true, true)
	_s2_value.add_theme_color_override("font_color", c_info)
	r2_right.add_child(_s2_value)

	var prob_box := PanelContainer.new()
	prob_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	prob_box.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(_Tokens.get_color("accent_rally_soft"), Color(c_accent, 0.70), 1, r, 12, 4))
	r2_right.add_child(prob_box)
	_prob_label = Label.new()
	_Theme.apply_label(_prob_label, "accent", 10, true, true)
	_prob_label.add_theme_color_override("font_color", c_gold_hi)
	prob_box.add_child(_prob_label)

	# 2. Compound selector panel (56, 370, 552, 300)
	var sel_panel := _make_box_panel(Rect2(56, 370, 552, 300), c_surf, c_border, r)
	sel_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sel_panel)
	var sel_vbox := VBoxContainer.new()
	sel_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel_vbox.add_theme_constant_override("separation", 8)
	sel_panel.add_child(sel_vbox)

	_selector_title = Label.new()
	_selector_title.text = "SELECTOR DE NEUMÁTICOS"
	_Theme.apply_label(_selector_title, "muted", 15, false, true)
	sel_vbox.add_child(_selector_title)

	var sel_sep := ColorRect.new()
	sel_sep.custom_minimum_size = Vector2(0, 1)
	sel_sep.color = Color(c_border, 0.45)
	sel_sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel_vbox.add_child(sel_sep)

	# Spacer leaving exact room for the 3D compound brush cards (y 434..560)
	var brush_spacer := Control.new()
	brush_spacer.custom_minimum_size = Vector2(0, 146)
	brush_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel_vbox.add_child(brush_spacer)

	var quick_lbl := Label.new()
	quick_lbl.text = "APLICACIÓN RÁPIDA AL COCHE COMPLETO (4×):"
	_Theme.apply_label(quick_lbl, "muted", 10, false, false)
	sel_vbox.add_child(quick_lbl)

	_preset_row = HBoxContainer.new()
	_preset_row.add_theme_constant_override("separation", 12)
	_preset_row.custom_minimum_size = Vector2(0, 50)
	sel_vbox.add_child(_preset_row)

	# 3. Mounted bay backdrop panel (624, 104, 600, 566)
	var mount_panel := _make_box_panel(Rect2(624, 104, 600, 566), c_surf, c_border, r)
	mount_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mount_panel)
	var m_title := Label.new()
	m_title.text = "RUEDAS MONTADAS DE SALIDA"
	_Theme.apply_label(m_title, "muted", 15, false, true)
	m_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mount_panel.add_child(m_title)

	var bay := Panel.new()
	bay.position = Vector2(832, 166)
	bay.size = Vector2(188, 484)
	bay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bay.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_well, c_subtle, 1, r))
	add_child(bay)

	var axle_col := Color(c_accent, 0.24)
	for rect_def in [Rect2(824, 280, 202, 2), Rect2(824, 534, 202, 2), Rect2(925, 281, 2, 254)]:
		var line := ColorRect.new()
		line.position = (rect_def as Rect2).position
		line.size = (rect_def as Rect2).size
		line.color = axle_col
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)


func update_view(data: Dictionary) -> void:
	_ensure_nodes()
	var s1: Dictionary = data.get("forecast_stage1", {})
	var s2: Dictionary = data.get("forecast_stage2", {})
	_s1_value.text = "%s %s · %0.0f °C" % [str(s1.get("icon", "")), str(s1.get("name", "Despejado")).to_upper(), float(s1.get("temp_c", 18.0))]
	_s2_value.text = "%s %s · %0.0f °C" % [str(s2.get("icon", "")), str(s2.get("name", "Pronóstico")).to_upper(), float(s2.get("temp_c", 15.0))]
	_prob_label.text = "Probabilidad : %% %d" % int(data.get("prob_pct", 80))

	var allowed: Array = data.get("allowed_compounds", [])
	var labels: Dictionary = data.get("compound_labels", {})
	var mounted: Array = data.get("mounted_compounds", [])
	var focus_id := str(data.get("focus_id", ""))

	var has_wet := false
	for cid in allowed:
		if str(cid).ends_with("_wet"):
			has_wet = true
			break
	_selector_title.text = "SELECTOR DE NEUMÁTICOS (SECO / LLUVIA)" if has_wet else "SELECTOR DE NEUMÁTICOS"

	var count := mini(allowed.size(), 4)
	if _preset_buttons.size() != count:
		for child in _preset_row.get_children():
			_preset_row.remove_child(child)
			child.queue_free()
		_preset_buttons.clear()
		for i in count:
			var btn := Button.new()
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
			btn.focus_mode = Control.FOCUS_NONE
			var cid := str(allowed[i])
			btn.pressed.connect(func() -> void: preset_selected.emit(cid))
			_preset_row.add_child(btn)
			_preset_buttons.append(btn)

	var r := _Tokens.get_radius("default")
	var c_card := _Tokens.get_color("bg_card")
	var c_border := _Tokens.get_color("border_card")
	var c_focus := _Tokens.get_color("border_focus")
	var c_text := _Tokens.get_color("text_primary")
	for i in _preset_buttons.size():
		var btn := _preset_buttons[i]
		var cid := str(allowed[i])
		var lbl := str(labels.get(cid, cid)).to_upper()
		btn.text = "4× %s" % lbl
		var all_match := mounted.size() == 4
		for m in mounted:
			if str(m) != cid:
				all_match = false
				break
		var focused := focus_id == ("preset:%d" % i)
		var ring: Color = _Tire3DView.compound_ring_color(cid)
		var sb := _Tokens.get_flat_stylebox(Color(ring, 0.20) if all_match else c_card, c_focus if focused else (ring if all_match else c_border), 2 if (focused or all_match) else 1, r, 8, 6)
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, sb)
		btn.add_theme_font_override("font", _Tokens.get_font("button"))
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", ring if all_match else c_text)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)


func _make_box_panel(rect: Rect2, bg: Color, border: Color, radius: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(bg, border, 1, radius, 18, 12))
	return p
