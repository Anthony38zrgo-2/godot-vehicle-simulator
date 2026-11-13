extends Control
class_name RallyTireStrategyScreen
## Pantalla inicial en 2 pasos para configurar el pool de 10 neumáticos del evento:
## Paso 1/2: Clima previsto + selector de compuestos + montaje inicial (4 ruedas).
## Paso 2/2: Maletero (0-2 repuestos, +18 kg c/u) e inventario de reserva (resto del pool).
## No toca get_tree().paused: la sesión la congela con vehicle.freeze + event_clock,
## así el garaje posterior guarda/restaura _restore_tree_paused=false y no congela el HUD.

signal strategy_confirmed(initial_inventory_data: Dictionary)

const StrategyBoard3DScript := preload("res://scripts/rally/rally_strategy_screen_3d_board.gd")
const Tire3DViewScript := preload("res://scripts/rally/rally_tire_3d_view.gd")
const LOGICAL_SIZE := Vector2(1280.0, 800.0)
const FONT_TITLE: Font = RallyUITheme.FONT_TITLE
const FONT_REGULAR: Font = RallyUITheme.FONT_REGULAR
const FONT_DATA: Font = RallyUITheme.FONT_DATA_BOLD

const C_BG := RallyUITheme.BG_BASE
const C_GLASS := RallyUITheme.BG_SURFACE
const C_FIELD := RallyUITheme.BG_WELL
const C_GOLD := RallyUITheme.ACCENT_RALLY
const C_GOLD_HI := RallyUITheme.TEXT_GOLD_SOFT
const C_ROSE := RallyUITheme.STATUS_DANGER
const C_BLUE := RallyUITheme.STATUS_INFO
const C_TEXT := RallyUITheme.TEXT_PRIMARY
const C_DIM := RallyUITheme.TEXT_MUTED
const C_BORDER := RallyUITheme.BORDER_CARD

const POOL_SIZE := 10
const MOUNTED_COUNT := 4

var manager: RallyEventManager
var vehicle: Node3D = null
var vehicle_name: String = "FORD ESCORT RS2000"
var allowed_compounds: Array = []
var compound_labels: Dictionary = {}

var step: int = 0
var mounted_compounds: Array = ["gravel_normal", "gravel_normal", "gravel_normal", "gravel_normal"]
var carried_spares_count: int = 2
var spare_compounds: Array = ["gravel_normal", "gravel_normal"]
var service_extra_compounds: Array = []

var forecast_stage1 := {}
var forecast_stage2 := {}

var _canvas_scale := 1.0
var _canvas_offset := Vector2.ZERO
var _focus_id := "mounted:0"
var _board_3d: StrategyBoard3DScript = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_3d = StrategyBoard3DScript.new()
	_board_3d.name = "StrategyBoard3D"
	_board_3d.screen = self
	add_child(_board_3d)
	_init_data()
	_resize_canvas()
	_sync_board()
	set_process_input(true)
	grab_focus()
	queue_redraw()


func _exit_tree() -> void:
	if _board_3d != null and is_instance_valid(_board_3d):
		_board_3d.clear_board()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_resize_canvas()


func _resize_canvas() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_canvas_scale = minf(size.x / LOGICAL_SIZE.x, size.y / LOGICAL_SIZE.y)
	_canvas_offset = (size - LOGICAL_SIZE * _canvas_scale) * 0.5
	if _board_3d != null and is_instance_valid(_board_3d):
		_board_3d.position = _canvas_offset
		_board_3d.scale = Vector2.ONE * _canvas_scale
	queue_redraw()


func _to_logical(point: Vector2) -> Vector2:
	return (point - _canvas_offset) / maxf(_canvas_scale, 0.001)


func _stock_count() -> int:
	return POOL_SIZE - MOUNTED_COUNT - carried_spares_count


func _init_data() -> void:
	if manager != null:
		allowed_compounds = manager.get_allowed_compound_ids()
		if allowed_compounds.is_empty():
			allowed_compounds = ["gravel_normal", "gravel_wet"]
		var cat := RallyTireCompound.load_catalog()
		for cid in allowed_compounds:
			compound_labels[cid] = RallyTireCompound.get_compound(cat, str(cid)).get("label", cid)
		if not manager.weather_schedule.is_empty():
			forecast_stage1 = RallyWeatherScheduler.get_stage_dominant_weather(manager.weather_schedule[0])
		if manager.stage_forecasts.size() > 1:
			forecast_stage2 = (manager.stage_forecasts[1] as Dictionary).get("weather", {})
		elif manager.weather_schedule.size() > 1:
			forecast_stage2 = RallyWeatherScheduler.get_stage_dominant_weather(manager.weather_schedule[1])
	else:
		allowed_compounds = ["gravel_normal", "gravel_wet"]
		compound_labels["gravel_normal"] = "Grava Normal"
		compound_labels["gravel_wet"] = "Grava Lluvia"
		forecast_stage1 = {"name": "Soleado", "icon": "☀️", "temp_c": 19.0, "precip_mm": 0.0}
		forecast_stage2 = {"name": "Lluvia estimada", "icon": "🌧️", "temp_c": 14.0, "precip_mm": 2.5}
	var def_cid: String = str(allowed_compounds[0]) if not allowed_compounds.is_empty() else "gravel_normal"
	var alt_cid: String = str(allowed_compounds[1]) if allowed_compounds.size() > 1 else def_cid
	mounted_compounds = [def_cid, def_cid, def_cid, def_cid]
	carried_spares_count = 2
	spare_compounds = [def_cid, def_cid]
	service_extra_compounds.clear()
	for i in _stock_count():
		service_extra_compounds.append(alt_cid)
	_focus_id = "mounted:0" if step == 0 else "count:%d" % carried_spares_count
	_sync_board()


func set_step(next_step: int) -> void:
	step = clampi(next_step, 0, 1)
	if step == 0:
		if not (_focus_id.begins_with("mounted:") or _focus_id.begins_with("preset:") or _focus_id in ["reset", "next"]):
			_focus_id = "mounted:0"
	else:
		if not (_focus_id.begins_with("count:") or _focus_id.begins_with("spare:") or _focus_id.begins_with("stock:") or _focus_id in ["back", "reset", "confirm"]):
			_focus_id = "count:%d" % carried_spares_count
	_sync_board()
	queue_redraw()


func _sync_board() -> void:
	if _board_3d != null and is_instance_valid(_board_3d):
		_board_3d.sync_from_screen()


func _preset_btn_rect(idx: int) -> Rect2:
	var count := maxi(1, mini(allowed_compounds.size(), 4))
	var gap := 12.0
	var total_w := 516.0
	var w := floorf((total_w - gap * float(count - 1)) / float(count))
	return Rect2(74.0 + float(idx) * (w + gap), 598.0, w, 50.0)


func _count_btn_rect(c: int) -> Rect2:
	var gap := 10.0
	var total_w := 524.0
	var w := floorf((total_w - gap * 2.0) / 3.0)
	return Rect2(70.0 + float(c) * (w + gap), 268.0, w, 34.0)


func _back_btn_rect() -> Rect2:
	return Rect2(604.0, 690.0, 168.0, 48.0)


func _reset_btn_rect() -> Rect2:
	return Rect2(786.0, 690.0, 170.0, 48.0)


func _primary_btn_rect() -> Rect2:
	return Rect2(970.0, 690.0, 254.0, 48.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), RallyUITheme.BG_OVERLAY)
	draw_set_transform(_canvas_offset, 0.0, Vector2(_canvas_scale, _canvas_scale))
	var win_rect := Rect2(30, 24, LOGICAL_SIZE.x - 60, LOGICAL_SIZE.y - 48)
	_draw_glass(win_rect)
	_draw_header(win_rect)
	if step == 0:
		_draw_step1_layout()
	else:
		_draw_step2_layout()
	_draw_footer(Rect2(56, 684, 1168, 60))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_glass(rect: Rect2) -> void:
	draw_style_box(RallyUITheme.make_flat_panel(C_GLASS, C_BORDER, 1, RallyUITheme.CORNER_RADIUS), rect)


func _draw_header(win_rect: Rect2) -> void:
	draw_string(FONT_TITLE, Vector2(56, 66), "ESTRATEGIA DE NEUMÁTICOS", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, C_TEXT)

	var pill1 := Rect2(win_rect.end.x - 364.0, 42.0, 164.0, 34.0)
	var pill2 := Rect2(win_rect.end.x - 190.0, 42.0, 164.0, 34.0)
	draw_style_box(RallyUITheme.make_flat_panel(C_GOLD if step == 0 else RallyUITheme.BG_CARD, Color("#f6c96e") if step == 0 else C_BORDER, 1, RallyUITheme.CORNER_RADIUS), pill1)
	draw_string(FONT_TITLE, Vector2(pill1.position.x + 12, pill1.position.y + 22), "1 · COCHE (4)", HORIZONTAL_ALIGNMENT_CENTER, pill1.size.x - 24, 11, C_BG if step == 0 else C_DIM)

	draw_style_box(RallyUITheme.make_flat_panel(C_GOLD if step == 1 else RallyUITheme.BG_CARD, Color("#f6c96e") if step == 1 else C_BORDER, 1, RallyUITheme.CORNER_RADIUS), pill2)
	draw_string(FONT_TITLE, Vector2(pill2.position.x + 12, pill2.position.y + 22), "2 · RESERVA (6)", HORIZONTAL_ALIGNMENT_CENTER, pill2.size.x - 24, 11, C_BG if step == 1 else C_DIM)

	draw_line(Vector2(56, 90), Vector2(win_rect.end.x - 26, 90), RallyUITheme.BORDER_SUBTLE, 1.0)


func _draw_step1_layout() -> void:
	_draw_weather_panel(Rect2(56, 104, 552, 250))
	_draw_step1_selector_panel(Rect2(56, 370, 552, 300))
	_draw_mounted_panel(Rect2(624, 104, 600, 566))


func _draw_step2_layout() -> void:
	_draw_step2_palette_panel(Rect2(56, 104, 552, 114))
	_draw_notice_panel(Rect2(624, 104, 600, 114))
	_draw_trunk_panel(Rect2(56, 228, 552, 442))
	_draw_stock_panel(Rect2(624, 228, 600, 442))


func _draw_weather_panel(rect: Rect2) -> void:
	_draw_glass(rect)
	draw_string(FONT_TITLE, Vector2(rect.position.x + 18, rect.position.y + 30), "INFORMACIÓN CLIMÁTICA DEL EVENTO", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_DIM)
	draw_line(Vector2(rect.position.x + 18, rect.position.y + 44), Vector2(rect.end.x - 18, rect.position.y + 44), Color(C_BORDER, 0.45), 1.0)

	var s1_icon := str(forecast_stage1.get("icon", ""))
	var s1_name := str(forecast_stage1.get("name", "Despejado"))
	var s1_temp := float(forecast_stage1.get("temp_c", 18.0))
	var row1 := Rect2(rect.position.x + 18, rect.position.y + 58, rect.size.x - 36, 74)
	draw_style_box(RallyUITheme.make_flat_panel(C_FIELD, RallyUITheme.BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS), row1)
	draw_string(FONT_REGULAR, Vector2(row1.position.x + 16, row1.position.y + 42), "STAGE 1 (ACTUAL):", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_TEXT)
	draw_string(FONT_DATA, Vector2(row1.position.x + 200, row1.position.y + 43), "%s %s · %0.0f °C" % [s1_icon, s1_name.to_upper(), s1_temp], HORIZONTAL_ALIGNMENT_LEFT, row1.size.x - 216, 16, C_GOLD_HI)

	var s2_icon := str(forecast_stage2.get("icon", ""))
	var s2_name := str(forecast_stage2.get("name", "Pronóstico"))
	var s2_temp := float(forecast_stage2.get("temp_c", 15.0))
	var row2 := Rect2(rect.position.x + 18, rect.position.y + 144, rect.size.x - 36, 90)
	draw_style_box(RallyUITheme.make_flat_panel(C_FIELD, RallyUITheme.BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS), row2)
	draw_string(FONT_REGULAR, Vector2(row2.position.x + 16, row2.position.y + 50), "STAGE 2 (PRONÓSTICO):", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_TEXT)
	draw_string(FONT_DATA, Vector2(row2.position.x + 200, row2.position.y + 34), "%s %s · %0.0f °C" % [s2_icon, s2_name.to_upper(), s2_temp], HORIZONTAL_ALIGNMENT_LEFT, row2.size.x - 216, 15, C_BLUE)

	var prob_pct := 80
	if manager != null and manager.has_method("_forecast_accuracy"):
		prob_pct = int(round(float(manager.call("_forecast_accuracy")) * 100.0))
	var prob_rect := Rect2(row2.position.x + 200, row2.position.y + 48, 184, 28)
	draw_style_box(RallyUITheme.make_flat_panel(RallyUITheme.ACCENT_RALLY_SOFT, Color(C_GOLD, 0.70), 1, RallyUITheme.CORNER_RADIUS), prob_rect)
	draw_string(FONT_TITLE, Vector2(prob_rect.position.x + 8, prob_rect.position.y + 19), "Probabilidad : %% %d" % prob_pct, HORIZONTAL_ALIGNMENT_CENTER, prob_rect.size.x - 16, 11, C_GOLD_HI)


func _draw_step1_selector_panel(rect: Rect2) -> void:
	_draw_glass(rect)
	draw_string(FONT_TITLE, Vector2(rect.position.x + 18, rect.position.y + 30), "SELECTOR DE NEUMÁTICOS (SECO / LLUVIA)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_DIM)
	draw_line(Vector2(rect.position.x + 18, rect.position.y + 44), Vector2(rect.end.x - 18, rect.position.y + 44), Color(C_BORDER, 0.45), 1.0)
	draw_string(FONT_REGULAR, Vector2(rect.position.x + 18, rect.position.y + 216), "APLICACIÓN RÁPIDA AL COCHE COMPLETO (4×):", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_DIM)
	var count := mini(allowed_compounds.size(), 4)
	for i in count:
		var cid := str(allowed_compounds[i])
		var lbl := str(compound_labels.get(cid, cid)).to_upper()
		var btn := _preset_btn_rect(i)
		var all_match := _all_mounted_equal(cid)
		var focused := _focus_id == ("preset:%d" % i)
		var ring := Tire3DViewScript.compound_ring_color(cid)
		draw_style_box(RallyUITheme.make_flat_panel(
			Color(ring, 0.20) if all_match else RallyUITheme.BG_CARD,
			RallyUITheme.BORDER_FOCUS if focused else (ring if all_match else C_BORDER),
			2 if (focused or all_match) else 1,
			RallyUITheme.CORNER_RADIUS
		), btn)
		draw_string(FONT_TITLE, Vector2(btn.position.x + 8, btn.position.y + 30), "4× %s" % lbl, HORIZONTAL_ALIGNMENT_CENTER, btn.size.x - 16, 12, ring if all_match else C_TEXT)


func _draw_mounted_panel(rect: Rect2) -> void:
	_draw_glass(rect)
	draw_string(FONT_TITLE, Vector2(rect.position.x + 18, rect.position.y + 30), "RUEDAS MONTADAS DE SALIDA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_DIM)
	draw_line(Vector2(rect.position.x + 18, rect.position.y + 44), Vector2(rect.end.x - 18, rect.position.y + 44), RallyUITheme.BORDER_SUBTLE, 1.0)
	var bay := Rect2(832, 166, 188, 484)
	draw_style_box(RallyUITheme.make_flat_panel(C_FIELD, RallyUITheme.BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS), bay)
	var axle_col := Color(C_GOLD, 0.24)
	draw_line(Vector2(824, 281), Vector2(1026, 281), axle_col, 2.0)
	draw_line(Vector2(824, 535), Vector2(1026, 535), axle_col, 2.0)
	draw_line(Vector2(926, 281), Vector2(926, 535), axle_col, 2.0)


func _draw_step2_palette_panel(rect: Rect2) -> void:
	_draw_glass(rect)
	draw_string(FONT_TITLE, Vector2(rect.position.x + 16, rect.position.y + 24), "COMPUESTOS PERMITIDOS (ARRASTRA A MALETERO O RESERVA)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_DIM)


func _draw_notice_panel(rect: Rect2) -> void:
	_draw_glass(rect)
	draw_string(FONT_TITLE, Vector2(rect.position.x + 16, rect.position.y + 24), "REGLAMENTO Y PESO EN MALETERO", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_GOLD)
	draw_string(FONT_REGULAR, Vector2(rect.position.x + 16, rect.position.y + 50), "• Cada rueda en el maletero añade +18 KG sobre el eje trasero.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TEXT)
	draw_string(FONT_REGULAR, Vector2(rect.position.x + 16, rect.position.y + 74), "• Mueve repuestos al Inventario de Reserva si buscas aligerar el coche.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TEXT)
	draw_string(FONT_REGULAR, Vector2(rect.position.x + 16, rect.position.y + 98), "• Pinchazos/rines se reparan en servicio.", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 32, 11, C_TEXT)


func _draw_trunk_panel(rect: Rect2) -> void:
	_draw_glass(rect)
	var mass_kg := carried_spares_count * 18.0
	draw_string(FONT_TITLE, Vector2(rect.position.x + 14, rect.position.y + 24), "MALETERO DEL COCHE (0, 1 O 2 REPUESTOS)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_DIM)
	draw_string(FONT_DATA, Vector2(rect.position.x + rect.size.x - 216, rect.position.y + 24), "PESO EXTRA: +%0.0f KG" % mass_kg, HORIZONTAL_ALIGNMENT_RIGHT, 200, 13, C_GOLD if carried_spares_count > 0 else C_BLUE)
	for c in [0, 1, 2]:
		var sel: bool = carried_spares_count == c
		var is_focused := _focus_id == ("count:%d" % c)
		var btn := _count_btn_rect(c)
		draw_style_box(RallyUITheme.make_flat_panel(
			C_GOLD if sel else RallyUITheme.BG_CARD,
			RallyUITheme.BORDER_FOCUS if is_focused else (Color("#f6c96e") if sel else C_BORDER),
			2 if is_focused else 1,
			RallyUITheme.CORNER_RADIUS
		), btn)
		var tag := "%d REP." % c
		draw_string(FONT_TITLE, Vector2(btn.position.x + 8, btn.position.y + 22), tag, HORIZONTAL_ALIGNMENT_CENTER, btn.size.x - 16, 11, C_BG if sel else C_TEXT)


func _draw_stock_panel(rect: Rect2) -> void:
	_draw_glass(rect)
	draw_string(FONT_TITLE, Vector2(rect.position.x + 18, rect.position.y + 28), "INVENTARIO DE RESERVA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_DIM)
	draw_line(Vector2(rect.position.x + 18, rect.position.y + 42), Vector2(rect.end.x - 18, rect.position.y + 42), RallyUITheme.BORDER_SUBTLE, 1.0)


func _draw_footer(rect: Rect2) -> void:
	var controls_hint := "FLECHAS / D-PAD MOVER · ENTER / A CAMBIAR · R RESTAURAR · Y / F5 SIGUIENTE" if step == 0 else "ARRASTRA MALETERO ↔ RESERVA · ESC / B VOLVER · Y / F5 CONFIRMAR"
	draw_string(FONT_REGULAR, Vector2(rect.position.x + 6, rect.position.y + 34), controls_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_DIM)

	if step == 1:
		var back_rect := _back_btn_rect()
		var back_focused := _focus_id == "back"
		draw_style_box(RallyUITheme.make_flat_panel(
			RallyUITheme.BG_HOVER if back_focused else RallyUITheme.BG_CARD,
			RallyUITheme.BORDER_FOCUS if back_focused else C_BORDER,
			2 if back_focused else 1,
			RallyUITheme.CORNER_RADIUS
		), back_rect)
		draw_string(FONT_TITLE, Vector2(back_rect.position.x + 8, back_rect.position.y + 29), "← PASO 1", HORIZONTAL_ALIGNMENT_CENTER, back_rect.size.x - 16, 12, C_TEXT)

	var reset_rect := _reset_btn_rect()
	var reset_focused := _focus_id == "reset"
	draw_style_box(RallyUITheme.make_flat_panel(
		RallyUITheme.BG_HOVER if reset_focused else RallyUITheme.BG_CARD,
		RallyUITheme.BORDER_FOCUS if reset_focused else C_BORDER,
		2 if reset_focused else 1,
		RallyUITheme.CORNER_RADIUS
	), reset_rect)
	draw_string(FONT_TITLE, Vector2(reset_rect.position.x + 8, reset_rect.position.y + 29), "RESTAURAR", HORIZONTAL_ALIGNMENT_CENTER, reset_rect.size.x - 16, 12, C_TEXT)

	var primary_rect := _primary_btn_rect()
	var primary_focused := _focus_id == ("next" if step == 0 else "confirm")
	var primary_text := "SIGUIENTE" if step == 0 else "CONFIRMAR"
	draw_style_box(RallyUITheme.make_flat_panel(
		C_GOLD,
		RallyUITheme.BORDER_FOCUS if primary_focused else Color("#f6c96e"),
		2 if primary_focused else 1,
		RallyUITheme.CORNER_RADIUS
	), primary_rect)
	draw_string(FONT_TITLE, Vector2(primary_rect.position.x + 10, primary_rect.position.y + 29), primary_text, HORIZONTAL_ALIGNMENT_CENTER, primary_rect.size.x - 20, 12, C_BG)


func _all_mounted_equal(cid: String) -> bool:
	if mounted_compounds.size() != 4:
		return false
	for m in mounted_compounds:
		if str(m) != cid:
			return false
	return true


func _nav_rows() -> Array:
	var rows: Array = []
	if step == 0:
		rows.append(["mounted:0", "mounted:1", "mounted:2", "mounted:3"])
		var preset_row: Array[String] = []
		for i in mini(allowed_compounds.size(), 4):
			preset_row.append("preset:%d" % i)
		if not preset_row.is_empty():
			rows.append(preset_row)
		rows.append(["reset", "next"])
		return rows

	var r0: Array[String] = ["count:0", "count:1", "count:2"]
	for i in carried_spares_count:
		r0.append("spare:%d" % i)
	rows.append(r0)
	var stock_count := _stock_count()
	if stock_count > 0:
		var r1: Array[String] = []
		for i in stock_count:
			r1.append("stock:%d" % i)
		rows.append(r1)
	rows.append(["back", "reset", "confirm"])
	return rows


func _move_focus(dx: int, dy: int) -> void:
	var rows := _nav_rows()
	var r_idx := 0
	var c_idx := 0
	for ri in rows.size():
		var row: Array = rows[ri]
		var found := row.find(_focus_id)
		if found >= 0:
			r_idx = ri
			c_idx = found
			break
	if dy != 0:
		var next_r := posmod(r_idx + dy, rows.size())
		var target_row: Array = rows[next_r]
		_focus_id = str(target_row[clampi(c_idx, 0, target_row.size() - 1)])
	elif dx != 0:
		var cur_row: Array = rows[r_idx]
		_focus_id = str(cur_row[posmod(c_idx + dx, cur_row.size())])
	_sync_board()
	queue_redraw()


func _activate_focused() -> void:
	if _focus_id.begins_with("mounted:"):
		_cycle_compound(mounted_compounds, int(_focus_id.trim_prefix("mounted:")))
	elif _focus_id.begins_with("preset:"):
		var p_idx := int(_focus_id.trim_prefix("preset:"))
		if p_idx >= 0 and p_idx < allowed_compounds.size():
			apply_compound_to_mounted_all(str(allowed_compounds[p_idx]))
			return
	elif _focus_id.begins_with("count:"):
		carried_spares_count = int(_focus_id.trim_prefix("count:"))
		_reconcile_pool()
	elif _focus_id.begins_with("spare:"):
		_cycle_compound(spare_compounds, int(_focus_id.trim_prefix("spare:")))
	elif _focus_id.begins_with("stock:"):
		_cycle_compound(service_extra_compounds, int(_focus_id.trim_prefix("stock:")))
	elif _focus_id == "back":
		set_step(0)
		return
	elif _focus_id == "next":
		set_step(1)
		return
	elif _focus_id == "reset":
		_init_data()
	elif _focus_id == "confirm":
		_on_confirm()
	_sync_board()
	queue_redraw()


func _advance_or_confirm() -> void:
	if step == 0:
		set_step(1)
	else:
		_on_confirm()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		match ke.keycode:
			KEY_LEFT, KEY_A:
				_move_focus(-1, 0)
				get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_D:
				_move_focus(1, 0)
				get_viewport().set_input_as_handled()
			KEY_UP, KEY_W:
				_move_focus(0, -1)
				get_viewport().set_input_as_handled()
			KEY_DOWN, KEY_S:
				_move_focus(0, 1)
				get_viewport().set_input_as_handled()
			KEY_TAB:
				_move_focus(-1 if ke.shift_pressed else 1, 0)
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate_focused()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if step == 1:
					set_step(0)
					get_viewport().set_input_as_handled()
			KEY_R:
				_init_data()
				queue_redraw()
				get_viewport().set_input_as_handled()
			KEY_F5:
				_advance_or_confirm()
				get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		var jb := event as InputEventJoypadButton
		match jb.button_index:
			JOY_BUTTON_DPAD_LEFT:
				_move_focus(-1, 0)
				get_viewport().set_input_as_handled()
			JOY_BUTTON_DPAD_RIGHT:
				_move_focus(1, 0)
				get_viewport().set_input_as_handled()
			JOY_BUTTON_DPAD_UP:
				_move_focus(0, -1)
				get_viewport().set_input_as_handled()
			JOY_BUTTON_DPAD_DOWN:
				_move_focus(0, 1)
				get_viewport().set_input_as_handled()
			JOY_BUTTON_A:
				_activate_focused()
				get_viewport().set_input_as_handled()
			JOY_BUTTON_B:
				if step == 1:
					set_step(0)
					get_viewport().set_input_as_handled()
			JOY_BUTTON_X:
				_init_data()
				queue_redraw()
				get_viewport().set_input_as_handled()
			JOY_BUTTON_Y:
				_advance_or_confirm()
				get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var pos := _to_logical(mb.position)
	if step == 0:
		for i in mini(allowed_compounds.size(), 4):
			if _preset_btn_rect(i).has_point(pos):
				get_viewport().set_input_as_handled()
				apply_compound_to_mounted_all(str(allowed_compounds[i]))
				return
	else:
		for c in [0, 1, 2]:
			if _count_btn_rect(c).has_point(pos):
				get_viewport().set_input_as_handled()
				_set_spare_count(c)
				return
		if _back_btn_rect().has_point(pos):
			get_viewport().set_input_as_handled()
			set_step(0)
			return
	if _reset_btn_rect().has_point(pos):
		get_viewport().set_input_as_handled()
		_init_data()
		queue_redraw()
		return
	if _primary_btn_rect().has_point(pos):
		get_viewport().set_input_as_handled()
		_advance_or_confirm()


func _pool_array_for(slot_kind: String) -> Array:
	match slot_kind:
		"mounted":
			return mounted_compounds
		"spare":
			return spare_compounds
		"stock":
			return service_extra_compounds
	return []


func _set_spare_count(next_count: int) -> void:
	carried_spares_count = clampi(next_count, 0, 2)
	_focus_id = "count:%d" % carried_spares_count
	_reconcile_pool()
	queue_redraw()


func _cycle_slot(slot_kind: String, slot_index: int) -> void:
	var arr := _pool_array_for(slot_kind)
	if not arr.is_empty():
		_cycle_compound(arr, slot_index)
		_sync_board()
		queue_redraw()


func apply_compound_to_slot(slot_kind: String, slot_index: int, cid: String) -> bool:
	if not allowed_compounds.has(cid):
		return false
	var arr := _pool_array_for(slot_kind)
	if slot_index < 0 or slot_index >= arr.size():
		return false
	if slot_kind == "spare" and slot_index >= carried_spares_count:
		return false
	arr[slot_index] = cid
	_sync_board()
	queue_redraw()
	return true


func apply_compound_to_mounted_all(cid: String) -> bool:
	if not allowed_compounds.has(cid):
		return false
	for i in mounted_compounds.size():
		mounted_compounds[i] = cid
	_sync_board()
	if _board_3d != null and is_instance_valid(_board_3d):
		_board_3d.play_mounted_settle_all()
	queue_redraw()
	return true


func apply_compound_to_stock_all(cid: String) -> bool:
	if not allowed_compounds.has(cid):
		return false
	for i in _stock_count():
		if i < service_extra_compounds.size():
			service_extra_compounds[i] = cid
	_sync_board()
	queue_redraw()
	return true


func unload_spare_to_stock(spare_index: int) -> bool:
	if spare_index < 0 or spare_index >= carried_spares_count or spare_index >= spare_compounds.size():
		return false
	var moved_cid := str(spare_compounds[spare_index])
	spare_compounds.remove_at(spare_index)
	carried_spares_count = maxi(0, carried_spares_count - 1)
	service_extra_compounds.append(moved_cid)
	_focus_id = "count:%d" % carried_spares_count
	_reconcile_pool()
	queue_redraw()
	return true


func load_stock_to_spare(stock_index: int) -> bool:
	if carried_spares_count >= 2 or stock_index < 0 or stock_index >= service_extra_compounds.size():
		return false
	var moved_cid := str(service_extra_compounds[stock_index])
	service_extra_compounds.remove_at(stock_index)
	carried_spares_count += 1
	spare_compounds.append(moved_cid)
	_focus_id = "spare:%d" % maxi(0, spare_compounds.size() - 1)
	_reconcile_pool()
	queue_redraw()
	return true


func swap_pool_slots(src_kind: String, src_index: int, dst_kind: String, dst_index: int) -> bool:
	if src_kind == dst_kind and src_index == dst_index:
		return false
	var src_arr := _pool_array_for(src_kind)
	var dst_arr := _pool_array_for(dst_kind)
	if src_index < 0 or src_index >= src_arr.size() or dst_index < 0 or dst_index >= dst_arr.size():
		return false
	if (src_kind == "spare" and src_index >= carried_spares_count) or (dst_kind == "spare" and dst_index >= carried_spares_count):
		return false
	var tmp: String = str(src_arr[src_index])
	src_arr[src_index] = str(dst_arr[dst_index])
	dst_arr[dst_index] = tmp
	_sync_board()
	queue_redraw()
	return true


func _cycle_compound(arr: Array, idx: int) -> void:
	if allowed_compounds.is_empty() or idx < 0 or idx >= arr.size():
		return
	var cur := str(arr[idx])
	var next_idx := (allowed_compounds.find(cur) + 1) % allowed_compounds.size()
	arr[idx] = allowed_compounds[next_idx]


func _reconcile_pool() -> void:
	var def_cid: String = str(allowed_compounds[0]) if not allowed_compounds.is_empty() else "gravel_normal"
	# Recortar o extender maletera moviendo explicitamente desde/hacia el parque.
	while spare_compounds.size() > carried_spares_count:
		var extra: String = str(spare_compounds.pop_back())
		service_extra_compounds.append(extra)
	while spare_compounds.size() < carried_spares_count:
		if not service_extra_compounds.is_empty():
			spare_compounds.append(str(service_extra_compounds.pop_back()))
		else:
			spare_compounds.append(def_cid)
	var want_stock := _stock_count()
	while service_extra_compounds.size() > want_stock:
		service_extra_compounds.pop_back()
	while service_extra_compounds.size() < want_stock:
		service_extra_compounds.append(def_cid)
	_sync_board()


func _on_confirm() -> void:
	_reconcile_pool()
	var mounted_out: Array = mounted_compounds.duplicate()
	var spares_out: Array = []
	for i in carried_spares_count:
		spares_out.append(str(spare_compounds[i]) if i < spare_compounds.size() else str(allowed_compounds[0]))
	var service_out: Array = []
	for i in _stock_count():
		service_out.append(str(service_extra_compounds[i]) if i < service_extra_compounds.size() else str(allowed_compounds[0]))
	# Invariante dura antes de emitir: 4 + spares + stock == 10.
	if mounted_out.size() + spares_out.size() + service_out.size() != POOL_SIZE:
		return
	strategy_confirmed.emit({
		"mounted_compounds": mounted_out,
		"spares_compounds": spares_out,
		"service_compounds": service_out,
		"carried_spares_count": carried_spares_count
	})
