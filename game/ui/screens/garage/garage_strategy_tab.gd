class_name GarageStrategyTab
extends Control
## Real Control tree for Garage Tab 3 (Fuel, Tire Pressures, and Pool 3D backdrops OR Non-Pool compound/spare cards).

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _SliderRowScript := preload("res://ui/molecules/ui_slider_row.gd")

signal value_changed(path: String, new_value: float)
signal field_selected(path: String)
signal fit_fuel_requested
signal all_compound_selected(compound_id: String)
signal corner_compound_cycled(corner: String)
signal spare_count_changed(new_count: int)
signal new_tires_toggled

var _sliders: Dictionary = {}
var _pool_backdrop: Control
var _pool_title: Label
var _pool_status: Label
var _pool_pressure_lbl: Label
var _classic_root: Control
var _classic_compounds_grid: GridContainer
var _classic_new_tires_btn: Button
var _classic_spare_btns: Array[Button] = []
var _classic_corners_grid: GridContainer
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

	# Top-left: Fuel & Pressures (36, 156, 596, 228) — leaves 394..674 completely clear for 3D board!
	var fp_panel := _make_group(Rect2(36, 156, 596, 228), "COMBUSTIBLE Y PRESIONES", c_card, c_subtle, r)
	add_child(fp_panel)
	var fp_body := fp_panel.get_meta("body") as VBoxContainer
	var fuel_h := HBoxContainer.new()
	fuel_h.add_theme_constant_override("separation", 6)
	fp_body.add_child(fuel_h)
	var fuel_slider := _SliderRowScript.new()
	fuel_slider.set_meta("label", "Combustible")
	fuel_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fuel_slider.value_changed.connect(func(_p: String, v: float) -> void:
		field_selected.emit("fuel.initial_kg")
		value_changed.emit("fuel.initial_kg", v)
	)
	fuel_h.add_child(fuel_slider)
	_sliders["fuel.initial_kg"] = fuel_slider

	var fit_btn := Button.new()
	fit_btn.text = "AJUSTAR TRAMO"
	fit_btn.custom_minimum_size = Vector2(106, 28)
	fit_btn.focus_mode = Control.FOCUS_NONE
	_Theme.apply_tone_button(fit_btn, "chrome", 11, 8, 4)
	fit_btn.pressed.connect(func() -> void: fit_fuel_requested.emit())
	fuel_h.add_child(fit_btn)

	for pair in [["garage.front_pressure", "Presión del."], ["garage.rear_pressure", "Presión tras."]]:
		var p: String = pair[0]
		var s := _SliderRowScript.new()
		s.set_meta("label", pair[1])
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.value_changed.connect(func(_p: String, v: float) -> void:
			field_selected.emit(p)
			value_changed.emit(p, v)
		)
		fp_body.add_child(s)
		_sliders[p] = s

	# Pool mode backdrop (non-interactive panels behind StrategyBoard3D)
	_pool_backdrop = Control.new()
	_pool_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pool_backdrop.size = size
	add_child(_pool_backdrop)

	var left_pool := PanelContainer.new()
	left_pool.position = Vector2(36, 394)
	left_pool.size = Vector2(596, 280)
	left_pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_pool.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_card, c_subtle, 1, r, 14, 6))
	_pool_backdrop.add_child(left_pool)
	var lp_v := VBoxContainer.new()
	lp_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lp_v.add_theme_constant_override("separation", 2)
	left_pool.add_child(lp_v)
	_pool_title = Label.new()
	_pool_title.text = "MALETERO Y PARQUE 3D (10/10)"
	_Theme.apply_label(_pool_title, "primary", 13, false, true)
	lp_v.add_child(_pool_title)
	_pool_status = Label.new()
	_Theme.apply_label(_pool_status, "muted", 9, false, true)
	lp_v.add_child(_pool_status)

	var right_pool := PanelContainer.new()
	right_pool.position = Vector2(648, 156)
	right_pool.size = Vector2(596, 518)
	right_pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_pool.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_card, c_subtle, 1, r, 14, 6))
	_pool_backdrop.add_child(right_pool)
	var rp_v := VBoxContainer.new()
	rp_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_pool.add_child(rp_v)
	var rp_t := Label.new()
	rp_t.text = "MONTAJE 3D EN EL COCHE"
	_Theme.apply_label(rp_t, "primary", 13, false, true)
	rp_v.add_child(rp_t)
	var rp_h := Label.new()
	rp_h.text = "ARRASTRA RUEDAS 3D ENTRE COCHE, MALETERO Y PARQUE  ·  CLIC O D-PAD SELECCIONA"
	_Theme.apply_label(rp_h, "muted", 9, false, true)
	rp_v.add_child(rp_h)
	var rp_sp := Control.new()
	rp_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rp_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rp_v.add_child(rp_sp)
	_pool_pressure_lbl = Label.new()
	_pool_pressure_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_Theme.apply_label(_pool_pressure_lbl, "muted", 9, false, true)
	rp_v.add_child(_pool_pressure_lbl)

	var bay := Panel.new()
	bay.position = Vector2(848, 198)
	bay.size = Vector2(196, 444)
	bay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bay.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_well, c_subtle, 1, r))
	_pool_backdrop.add_child(bay)

	# Classic non-pool root
	_classic_root = Control.new()
	_classic_root.size = size
	_classic_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_classic_root)

	var cl_left := _make_group(Rect2(36, 394, 596, 280), "COMPUESTO Y SERVICIO", c_card, c_subtle, r)
	_classic_root.add_child(cl_left)
	var cl_body := cl_left.get_meta("body") as VBoxContainer
	_classic_compounds_grid = GridContainer.new()
	_classic_compounds_grid.columns = 2
	_classic_compounds_grid.add_theme_constant_override("h_separation", 10)
	_classic_compounds_grid.add_theme_constant_override("v_separation", 8)
	cl_body.add_child(_classic_compounds_grid)

	var srv_row := HBoxContainer.new()
	cl_body.add_child(srv_row)
	var srv_lbl := Label.new()
	srv_lbl.text = "MONTAR NEUMÁTICOS NUEVOS"
	srv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_Theme.apply_label(srv_lbl, "primary", 11, false, false)
	srv_row.add_child(srv_lbl)
	_classic_new_tires_btn = Button.new()
	_classic_new_tires_btn.custom_minimum_size = Vector2(120, 30)
	_classic_new_tires_btn.focus_mode = Control.FOCUS_NONE
	_classic_new_tires_btn.pressed.connect(func() -> void: new_tires_toggled.emit())
	srv_row.add_child(_classic_new_tires_btn)

	var sp_row := HBoxContainer.new()
	sp_row.add_theme_constant_override("separation", 6)
	cl_body.add_child(sp_row)
	var sp_lbl := Label.new()
	sp_lbl.text = "RUEDAS DE REPUESTO (+18 KG C/U)"
	sp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_Theme.apply_label(sp_lbl, "primary", 11, false, false)
	sp_row.add_child(sp_lbl)
	for s in 3:
		var sb_btn := Button.new()
		sb_btn.text = str(s)
		sb_btn.custom_minimum_size = Vector2(44, 30)
		sb_btn.focus_mode = Control.FOCUS_NONE
		var cnt: int = s
		sb_btn.pressed.connect(func() -> void: spare_count_changed.emit(cnt))
		sp_row.add_child(sb_btn)
		_classic_spare_btns.append(sb_btn)

	var cl_right := _make_group(Rect2(648, 156, 596, 518), "MONTAJE Y TELEMETRÍA", c_card, c_subtle, r)
	_classic_root.add_child(cl_right)
	var cr_body := cl_right.get_meta("body") as VBoxContainer
	_classic_corners_grid = GridContainer.new()
	_classic_corners_grid.columns = 2
	_classic_corners_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_classic_corners_grid.add_theme_constant_override("h_separation", 12)
	_classic_corners_grid.add_theme_constant_override("v_separation", 12)
	cr_body.add_child(_classic_corners_grid)


func sync_view(data: Dictionary, field_resolver: Callable, format_cb: Callable) -> void:
	_ensure_nodes()
	var draft_values: Dictionary = data.get("draft_values", {})
	var opening_values: Dictionary = data.get("opening_values", {})
	var selected_path := str(data.get("selected_path", ""))
	for path: String in _sliders:
		var row: Control = _sliders[path]
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
			base_v
		)
		row.set_highlighted(path == selected_path)

	var is_pool := bool(data.get("is_pool", false))
	_pool_backdrop.visible = is_pool
	_classic_root.visible = not is_pool
	if is_pool:
		_pool_title.text = "MALETERO Y PARQUE 3D (%d/10)" % int(data.get("pool_total", 10))
		_pool_status.text = str(data.get("pool_status_text", ""))
		_pool_status.add_theme_color_override("font_color", data.get("pool_status_color", _Tokens.get_color("text_muted")))
		_pool_pressure_lbl.text = "PRESIÓN MEDIA %0.0f kPa · DESLIZA SOBRE MONTAJE PARA INTERCAMBIAR" % float(data.get("avg_pressure", 0.0))
	else:
		_sync_classic(data)


func _sync_classic(data: Dictionary) -> void:
	for child in _classic_compounds_grid.get_children():
		child.queue_free()
	var can_service := bool(data.get("can_service", true))
	var available_ids: Array = data.get("available_compounds", [])
	var wheel_compounds: Dictionary = data.get("wheel_compounds", {})
	var compound_labels: Dictionary = data.get("compound_labels", {})
	for cid_var in available_ids:
		var cid := str(cid_var)
		var all_same := true
		for corner in ["FL", "FR", "RL", "RR"]:
			if str(wheel_compounds.get(corner, "")) != cid:
				all_same = false
				break
		var btn := Button.new()
		btn.text = "4× " + str(compound_labels.get(cid, cid)).to_upper()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = not can_service
		btn.focus_mode = Control.FOCUS_NONE
		_Theme.apply_tone_button(btn, "gold" if all_same else "chrome", 12, 10, 6)
		var t_cid := cid
		btn.pressed.connect(func() -> void: all_compound_selected.emit(t_cid))
		_classic_compounds_grid.add_child(btn)

	var new_tires := bool(data.get("new_tires_service", false))
	_classic_new_tires_btn.text = "SÍ" if new_tires else "NO"
	_classic_new_tires_btn.disabled = not bool(data.get("may_service", true))
	_Theme.apply_tone_button(_classic_new_tires_btn, "gold" if new_tires else "chrome", 12, 10, 4)

	var spares := int(data.get("draft_spare_wheels", 1))
	for s in _classic_spare_btns.size():
		var b := _classic_spare_btns[s]
		b.disabled = not bool(data.get("may_service", true))
		_Theme.apply_tone_button(b, "gold" if spares == s else "chrome", 12, 8, 4)

	for child in _classic_corners_grid.get_children():
		child.queue_free()
	var corners: Array[String] = ["FL", "FR", "RL", "RR"]
	var corner_pressures: Array = data.get("corner_pressures", [0.0, 0.0, 0.0, 0.0])
	var corner_temps: Array = data.get("corner_temps", [20.0, 20.0, 20.0, 20.0])
	var r := _Tokens.get_radius("default")
	for i in 4:
		var code: String = corners[i]
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(_Tokens.get_color("bg_well"), _Tokens.get_color("border_subtle"), 1, r, 10, 8))
		_classic_corners_grid.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		var l_code := Label.new()
		l_code.text = code
		_Theme.apply_label(l_code, "primary", 16, false, true)
		v.add_child(l_code)
		var l_p := Label.new()
		l_p.text = "PRESIÓN: %0.0f kPa" % float(corner_pressures[i])
		_Theme.apply_label(l_p, "data", 11, true, true)
		v.add_child(l_p)
		var l_t := Label.new()
		l_t.text = "TEMP: %0.0f °C" % float(corner_temps[i])
		_Theme.apply_label(l_t, "info", 11, true, true)
		v.add_child(l_t)
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(sp)
		var c_btn := Button.new()
		var cid := str(wheel_compounds.get(code, ""))
		c_btn.text = str(compound_labels.get(cid, cid))
		c_btn.disabled = not can_service
		c_btn.focus_mode = Control.FOCUS_NONE
		_Theme.apply_tone_button(c_btn, "chrome", 12, 8, 5)
		var t_corner: String = code
		c_btn.pressed.connect(func() -> void: corner_compound_cycled.emit(t_corner))
		v.add_child(c_btn)


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
	body.add_theme_constant_override("separation", 6)
	root_v.add_child(body)
	p.set_meta("body", body)
	return p
