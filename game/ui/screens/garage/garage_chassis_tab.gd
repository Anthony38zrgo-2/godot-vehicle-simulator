class_name GarageChassisTab
extends Control
## Real Control tree for Garage Tab 1 (Suspension, ARBs, Brakes, Geometry, Chassis Balance).

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _SliderRowScript := preload("res://ui/molecules/ui_slider_row.gd")
const _ChartScript := preload("res://ui/organisms/ui_telemetry_chart.gd")

signal value_changed(path: String, new_value: float)
signal field_selected(path: String)

var _seg_buttons: Dictionary = {}
var _sliders: Dictionary = {}
var _brake_balance_lbl: Label
var _stiff_chart: Control
var _turn_chart: Control
var _balance_note: Label
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

	# Top-left: Suspension & ARBs (36, 156, 600, 296)
	var susp_panel := _make_group(Rect2(36, 156, 600, 296), "SUSPENSIÓN Y ESTABILIZADORAS", c_card, c_subtle, r)
	add_child(susp_panel)
	var s_body := susp_panel.get_meta("body") as VBoxContainer
	_add_segmented_row(s_body, "garage.suspension", "Tarado y altura", ["Blanda", "Semi-B", "Equil.", "Semi-R", "Rígida"], [5.0, 4.0, 3.0, 2.0, 1.0])
	_add_segmented_row(s_body, "garage.front_arb", "Estabilizadora del.", ["Blanda", "Semi-B", "Equil.", "Semi-R", "Rígida"], [5.0, 4.0, 3.0, 2.0, 1.0])
	_add_segmented_row(s_body, "garage.rear_arb", "Estabilizadora tras.", ["Blanda", "Semi-B", "Equil.", "Semi-R", "Rígida"], [5.0, 4.0, 3.0, 2.0, 1.0])

	# Bottom-left: Brakes (36, 464, 600, 210)
	var brakes_panel := _make_group(Rect2(36, 464, 600, 210), "FRENOS", c_card, c_subtle, r)
	add_child(brakes_panel)
	var b_body := brakes_panel.get_meta("body") as VBoxContainer
	_add_slider(b_body, "brakes.front_brake_bias", "Reparto de frenada")
	var note_box := PanelContainer.new()
	note_box.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_well, c_subtle, 1, r, 10, 8))
	b_body.add_child(note_box)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 3)
	note_box.add_child(nv)
	_brake_balance_lbl = Label.new()
	_Theme.apply_label(_brake_balance_lbl, "accent", 11, false, true)
	nv.add_child(_brake_balance_lbl)
	var bh := Label.new()
	bh.text = "Adelantarlo evita bloqueos atrás; retrasarlo ayuda a cruzar el coche al entrar."
	_Theme.apply_label(bh, "muted", 10, false, false)
	nv.add_child(bh)

	# Top-right: Geometry (652, 156, 592, 296)
	var geom_panel := _make_group(Rect2(652, 156, 592, 296), "GEOMETRÍA (POR EJE)", c_card, c_subtle, r)
	add_child(geom_panel)
	var g_body := geom_panel.get_meta("body") as VBoxContainer
	_add_slider(g_body, "suspension.front.camber", "Caída delantera")
	_add_slider(g_body, "suspension.rear.camber", "Caída trasera")
	_add_slider(g_body, "suspension.front.toe", "Convergencia del.")
	_add_slider(g_body, "suspension.rear.toe", "Convergencia tras.")

	# Bottom-right: Balance (652, 464, 592, 210)
	var bal_panel := _make_group(Rect2(652, 464, 592, 210), "BALANCE RESULTANTE DEL CHASIS", c_card, c_subtle, r)
	add_child(bal_panel)
	var bal_body := bal_panel.get_meta("body") as VBoxContainer
	_stiff_chart = _ChartScript.new()
	_stiff_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bal_body.add_child(_stiff_chart)
	_turn_chart = _ChartScript.new()
	_turn_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bal_body.add_child(_turn_chart)
	_balance_note = Label.new()
	_Theme.apply_label(_balance_note, "accent", 10, false, true)
	bal_body.add_child(_balance_note)


func sync_values(draft_values: Dictionary, field_resolver: Callable, format_cb: Callable, selected_path: String, opening_values: Dictionary = {}) -> void:
	_ensure_nodes()
	var r := _Tokens.get_radius("default")
	var c_accent := _Tokens.get_color("accent_rally")
	var c_gold_hi := _Tokens.get_color("text_gold_soft")
	var c_well := _Tokens.get_color("bg_well")
	var c_subtle := _Tokens.get_color("border_subtle")
	var c_dim := _Tokens.get_color("text_muted")

	for path: String in _seg_buttons:
		var cur := float(draft_values.get(path, 3.0))
		var entries: Array = _seg_buttons[path]
		for entry in entries:
			var btn: Button = entry["btn"]
			var val: float = entry["val"]
			var active := is_equal_approx(cur, val)
			var sb := _Tokens.get_flat_stylebox(Color("#2a2010") if active else c_well, c_accent if active else c_subtle, 1, r, 6, 4)
			for st in ["normal", "hover", "pressed", "focus"]:
				btn.add_theme_stylebox_override(st, sb)
			btn.add_theme_color_override("font_color", c_gold_hi if active else c_dim)
			btn.add_theme_color_override("font_hover_color", Color.WHITE)

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

	var susp := float(draft_values.get("garage.suspension", 3.0))
	var f_arb := float(draft_values.get("garage.front_arb", 3.0))
	var r_arb := float(draft_values.get("garage.rear_arb", 3.0))
	var f_bias := float(draft_values.get("brakes.front_brake_bias", 0.55))
	var front_pct := roundi(f_bias * 100.0)
	_brake_balance_lbl.text = "BALANCE ACTUAL: %d%% DELANTERO  /  %d%% TRASERO" % [front_pct, 100 - front_pct]

	var stiff_frac := clampf((5.0 - susp) / 4.0, 0.0, 1.0)
	_stiff_chart.set_balance_meter("RIGIDEZ Y ALTURA", "Blanda · Baches", "Rígida · Asfalto", stiff_frac)
	var oversteer_frac := clampf(0.5 + (f_arb - r_arb) * 0.12 + (0.55 - f_bias) * 1.2, 0.05, 0.95)
	_turn_chart.set_balance_meter("TENDENCIA EN CURVA", "Subviraje (Estable)", "Sobreviraje (Ágil)", oversteer_frac)
	if oversteer_frac < 0.40:
		_balance_note.text = "Tendencia SUBVIRADORA: entra estable, le cuesta cerrar giro."
	elif oversteer_frac > 0.60:
		_balance_note.text = "Tendencia SOBREVIRADORA: morro ágil, zaga viva al soltar o frenar."
	else:
		_balance_note.text = "Balance EQUILIBRADO entre entrada en curva y tracción a la salida."


func _add_segmented_row(parent: VBoxContainer, path: String, label_txt: String, labels: Array, values: Array) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(h)
	var lbl := Label.new()
	lbl.text = label_txt
	lbl.custom_minimum_size = Vector2(162, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_Theme.apply_label(lbl, "muted", 11, false, false)
	h.add_child(lbl)
	var btns: Array = []
	for i in labels.size():
		var b := Button.new()
		b.text = str(labels[i]).to_upper()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 32)
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
