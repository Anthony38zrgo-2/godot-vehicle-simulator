class_name GaragePowertrainTab
extends Control
## Real Control tree for Garage Tab 2 (Final Drive, Max RPM, Cooling, Live Gear Speeds, Differential).

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _Presenter := preload("res://scripts/ui/services/garage_setup_presenter.gd")
const _SliderRowScript := preload("res://ui/molecules/ui_slider_row.gd")

signal value_changed(path: String, new_value: float)
signal field_selected(path: String)

var _seg_buttons: Dictionary = {}
var _sliders: Dictionary = {}
var _gear_top_lbl: Label
var _gears_hbox: HBoxContainer
var _diff_summary_vbox: VBoxContainer
var _initialized: bool = false


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _initialized:
		return
	_initialized = true
	size = Vector2(1280.0, 800.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var r := _Tokens.get_radius("default")
	var c_card := _Tokens.get_color("bg_card")
	var c_well := _Tokens.get_color("bg_well")
	var c_subtle := _Tokens.get_color("border_subtle")

	# Top-left: Engine & Final Drive (36, 156, 600, 272)
	var eng_panel := _make_group(Rect2(36, 156, 600, 272), "MOTOR Y DESARROLLO", c_card, c_subtle, r)
	add_child(eng_panel)
	var e_body := eng_panel.get_meta("body") as VBoxContainer
	_add_slider(e_body, "powertrain.final_drive", "Relación final")
	_add_slider(e_body, "powertrain.max_rpm", "Limitador de RPM")
	_add_segmented_row(e_body, "garage.cooling", "Refrigeración", ["Mín.", "Serie", "25%", "50%", "75%", "100%"], [-1.0, 0.0, 1.0, 2.0, 3.0, 4.0])

	# Bottom-left: Gear Speeds (36, 440, 600, 234)
	var gear_panel := _make_group(Rect2(36, 440, 600, 234), "VELOCIDAD POR MARCHA (EN VIVO)", c_card, c_subtle, r)
	add_child(gear_panel)
	var g_body := gear_panel.get_meta("body") as VBoxContainer
	_gear_top_lbl = Label.new()
	_gear_top_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_Theme.apply_label(_gear_top_lbl, "accent", 11, true, true)
	g_body.add_child(_gear_top_lbl)
	_gears_hbox = HBoxContainer.new()
	_gears_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_gears_hbox.add_theme_constant_override("separation", 8)
	g_body.add_child(_gears_hbox)

	# Right: Differential (652, 156, 592, 518)
	var diff_panel := _make_group(Rect2(652, 156, 592, 518), "DIFERENCIAL", c_card, c_subtle, r)
	add_child(diff_panel)
	var d_body := diff_panel.get_meta("body") as VBoxContainer
	_add_segmented_row(d_body, "garage.lsd", "Tipo de diferencial", ["Abierto", "Autoblocante"], [0.0, 1.0])
	_add_segmented_row(d_body, "powertrain.differential.clutches", "Superficies fricción", ["2 discos", "4 discos", "6 discos", "8 discos"], [2.0, 4.0, 6.0, 8.0])
	_add_slider(d_body, "powertrain.differential.power_ramp_angle_deg", "Rampa aceleración")
	_add_slider(d_body, "powertrain.differential.coast_ramp_angle_deg", "Rampa retención")

	var sum_box := PanelContainer.new()
	sum_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sum_box.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_well, c_subtle, 1, r, 12, 10))
	d_body.add_child(sum_box)
	_diff_summary_vbox = VBoxContainer.new()
	_diff_summary_vbox.add_theme_constant_override("separation", 5)
	sum_box.add_child(_diff_summary_vbox)


func sync_values(draft_values: Dictionary, vehicle: Node, field_resolver: Callable, format_cb: Callable, selected_path: String, opening_values: Dictionary = {}) -> void:
	_ensure_nodes()
	var lsd_enabled := bool(draft_values.get("garage.lsd", 0.0))
	var r := _Tokens.get_radius("default")
	var c_accent := _Tokens.get_color("accent_rally")
	var c_gold_hi := _Tokens.get_color("text_gold_soft")
	var c_well := _Tokens.get_color("bg_well")
	var c_subtle := _Tokens.get_color("border_subtle")
	var c_dim := _Tokens.get_color("text_muted")

	for path: String in _seg_buttons:
		var disabled := path.begins_with(RallySetupCatalog.DIFFERENTIAL_PREFIX) and not lsd_enabled
		var cur := float(draft_values.get(path, 0.0))
		for entry in _seg_buttons[path]:
			var btn: Button = entry["btn"]
			var val: float = entry["val"]
			btn.disabled = disabled
			var active := is_equal_approx(cur, val) and not disabled
			var sb := _Tokens.get_flat_stylebox(Color("#2a2010") if active else c_well, c_accent if active else c_subtle, 1, r, 6, 4)
			for st in ["normal", "hover", "pressed", "focus", "disabled"]:
				btn.add_theme_stylebox_override(st, sb)
			btn.add_theme_color_override("font_color", c_gold_hi if active else c_dim)
			btn.add_theme_color_override("font_disabled_color", Color(c_dim, 0.4))

	for path: String in _sliders:
		var row: Control = _sliders[path]
		var disabled := path.begins_with(RallySetupCatalog.DIFFERENTIAL_PREFIX) and not lsd_enabled
		var field: Dictionary = field_resolver.call(path)
		if field.is_empty():
			continue
		var cur := float(draft_values.get(path, float(field.get("min", 0.0))))
		var base_v := float(opening_values.get(path, cur))
		var formatted := str(format_cb.call(field, path))
		row.custom_formatter = func(_v: float) -> String: return formatted
		row.configure(
			path,
			str(row.get_meta("label", path)),
			float(field.get("min", 0.0)),
			float(field.get("max", 1.0)),
			float(field.get("step", 0.01)),
			cur,
			base_v,
			"",
			2,
			disabled
		)
		row.set_highlighted(path == selected_path and not disabled)

	# Gear speeds
	for child in _gears_hbox.get_children():
		child.queue_free()
	var gears: Array = []
	var max_rpm := float(draft_values.get("powertrain.max_rpm", 7000.0))
	var final_drive := maxf(float(draft_values.get("powertrain.final_drive", 4.0)), 0.1)
	if is_instance_valid(vehicle) and vehicle.get("simulation") != null:
		var pm = vehicle.simulation.powertrain_model
		if max_rpm <= 0.0:
			max_rpm = pm.maximum_rpm
		var wheel_radius: float = maxf(pm.front_wheel_radius_m if pm.front_torque_split >= 0.5 else pm.rear_wheel_radius_m, 0.15)
		for idx in pm.gear_ratios.size():
			var gr := absf(float(pm.gear_ratios[idx]))
			gears.append({"label": "%dª" % (idx + 1), "ratio": gr, "kmh": _Presenter.gear_top_kmh(max_rpm, gr, final_drive, wheel_radius)})
		if absf(pm.reverse_ratio) > 0.01:
			var rev_r := absf(float(pm.reverse_ratio))
			gears.append({"label": "R", "ratio": rev_r, "kmh": _Presenter.gear_top_kmh(max_rpm, rev_r, final_drive, wheel_radius)})
	var top_fwd := 0.0
	for g in gears:
		if str(g["label"]) != "R":
			top_fwd = maxf(top_fwd, float(g["kmh"]))
	_gear_top_lbl.text = "V. MÁX AL CORTE: %0.0f KM/H" % top_fwd
	for g in gears:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_well, c_subtle, 1, r, 6, 6))
		_gears_hbox.add_child(card)
		var gv := VBoxContainer.new()
		gv.alignment = BoxContainer.ALIGNMENT_CENTER
		gv.add_theme_constant_override("separation", 4)
		card.add_child(gv)
		var g_lbl := Label.new()
		g_lbl.text = str(g["label"])
		g_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_Theme.apply_label(g_lbl, "accent" if str(g["label"]) != "R" else "muted", 14, false, true)
		gv.add_child(g_lbl)
		var r_lbl := Label.new()
		r_lbl.text = "%0.2f" % float(g["ratio"])
		r_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_Theme.apply_label(r_lbl, "muted", 10, true, false)
		gv.add_child(r_lbl)
		var bar := ProgressBar.new()
		bar.max_value = maxf(top_fwd, 1.0)
		bar.value = float(g["kmh"])
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		bar.add_theme_stylebox_override("background", _Tokens.get_flat_stylebox(_Tokens.get_color("bg_base"), c_subtle, 1, r))
		bar.add_theme_stylebox_override("fill", _Tokens.get_flat_stylebox(c_accent if str(g["label"]) != "R" else c_dim, c_accent, 0, r))
		gv.add_child(bar)
		var k_lbl := Label.new()
		k_lbl.text = "%0.0f km/h" % float(g["kmh"])
		k_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_Theme.apply_label(k_lbl, "primary", 11, true, true)
		gv.add_child(k_lbl)

	# Differential summary
	for child in _diff_summary_vbox.get_children():
		child.queue_free()
	var sum_t := Label.new()
	sum_t.text = "COMPORTAMIENTO RESULTANTE"
	_Theme.apply_label(sum_t, "accent" if lsd_enabled else "muted", 10, false, true)
	_diff_summary_vbox.add_child(sum_t)
	var lines := _Presenter.differential_behavior_lines(draft_values, lsd_enabled)
	for i in lines.size():
		var l := Label.new()
		l.text = lines[i]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_Theme.apply_label(l, "primary" if i == 0 else "muted", 10, false, false)
		_diff_summary_vbox.add_child(l)


func _add_segmented_row(parent: VBoxContainer, path: String, label_txt: String, labels: Array, values: Array) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	parent.add_child(h)
	var lbl := Label.new()
	lbl.text = label_txt
	lbl.custom_minimum_size = Vector2(150, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_Theme.apply_label(lbl, "muted", 11, false, false)
	h.add_child(lbl)
	var btns: Array = []
	for i in labels.size():
		var b := Button.new()
		b.text = str(labels[i]).to_upper()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 30)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", _Tokens.get_font("button"))
		b.add_theme_font_size_override("font_size", 11)
		var target_val: float = float(values[i])
		var target_path := path
		b.pressed.connect(func() -> void:
			field_selected.emit(target_path)
			value_changed.emit(target_path, target_val)
		)
		h.add_child(b)
		btns.append({"btn": b, "val": target_val})
	_seg_buttons[path] = btns


func _add_slider(parent: VBoxContainer, path: String, label_txt: String) -> void:
	var row := _SliderRowScript.new()
	row.set_meta("label", label_txt)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var target_path := path
	row.value_changed.connect(func(_p: String, v: float) -> void:
		field_selected.emit(target_path)
		value_changed.emit(target_path, v)
	)
	parent.add_child(row)
	_sliders[path] = row


func _make_group(rect: Rect2, caption: String, bg: Color, border: Color, radius: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(bg, border, 1, radius, 14, 10))
	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 6)
	p.add_child(root_v)
	var lbl := Label.new()
	lbl.text = caption
	_Theme.apply_label(lbl, "primary", 14, false, true)
	root_v.add_child(lbl)
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = border
	root_v.add_child(sep)
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root_v.add_child(body)
	p.set_meta("body", body)
	return p
