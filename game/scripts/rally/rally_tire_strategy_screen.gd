extends Control
class_name RallyTireStrategyScreen
## Pantalla única inicial: reparte el pool fijo de 10 (4 montados + 0-2 maletera + resto parque).
## No toca get_tree().paused: la sesión la congela con vehicle.freeze + event_clock,
## así el garaje posterior guarda/restore _restore_tree_paused=false y no se congela la HUD.

signal strategy_confirmed(initial_inventory_data: Dictionary)

const LOGICAL_SIZE := Vector2(1280.0, 800.0)
const FONT_TITLE: Font = preload("res://fonts/montserrat/Montserrat-Bold.ttf")
const FONT_REGULAR: Font = preload("res://fonts/montserrat/Montserrat-Regular.ttf")
const FONT_DATA: Font = preload("res://fonts/D-DIN-Bold.ttf")

const C_BG := Color("#0e141c")
const C_GLASS := Color("#151d28")
const C_GOLD := Color("#e5a93c")
const C_GOLD_HI := Color("#ffd57a")
const C_ROSE := Color("#ef4444")
const C_BLUE := Color("#60a5fa")
const C_TEXT := Color("#f0f4f8")
const C_DIM := Color("#8a99a8")
const C_BORDER := Color("#2a3848")

const POOL_SIZE := 10
const MOUNTED_COUNT := 4

var manager: RallyEventManager
var vehicle_name: String = "FORD ESCORT RS2000"
var allowed_compounds: Array = []
var compound_labels: Dictionary = {}

var mounted_compounds: Array = ["gravel_normal", "gravel_normal", "gravel_normal", "gravel_normal"]
var carried_spares_count: int = 2
var spare_compounds: Array = ["gravel_normal", "gravel_normal"]
var service_extra_compounds: Array = []

var forecast_stage1 := {}
var forecast_stage2 := {}

var _canvas_scale := 1.0
var _canvas_offset := Vector2.ZERO
var _focus_id := "mounted:0"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_init_data()
	_resize_canvas()
	set_process_input(true)
	grab_focus()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_resize_canvas()

func _resize_canvas() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_canvas_scale = minf(size.x / LOGICAL_SIZE.x, size.y / LOGICAL_SIZE.y)
	_canvas_offset = (size - LOGICAL_SIZE * _canvas_scale) * 0.5
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

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.08, 0.96))
	draw_set_transform(_canvas_offset, 0.0, Vector2(_canvas_scale, _canvas_scale))
	var win_rect := Rect2(30, 24, LOGICAL_SIZE.x - 60, LOGICAL_SIZE.y - 48)
	_draw_glass(win_rect)
	draw_string(FONT_TITLE, Vector2(56, 68), "ESTRATEGIA DE NEUMÁTICOS", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, C_TEXT)
	draw_string(FONT_REGULAR, Vector2(56, 92), "RALLY  ·  %s  ·  POOL: 10 NEUMÁTICOS PARA TODO EL EVENTO" % vehicle_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_GOLD)
	draw_line(Vector2(56, 106), Vector2(win_rect.end.x - 26, 106), Color(C_BORDER, 0.7), 1.0)
	_draw_weather_panel(Rect2(56, 120, 540, 110))
	_draw_notice_panel(Rect2(616, 120, win_rect.end.x - 642, 110))
	_draw_mounted_selection(Rect2(56, 246, 1168, 116))
	_draw_trunk_selection(Rect2(56, 376, 1168, 126))
	_draw_stock_selection(Rect2(56, 516, 1168, 150))
	_draw_footer(Rect2(56, 684, 1168, 60))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_glass(rect: Rect2) -> void:
	draw_rect(rect, C_GLASS)
	draw_rect(rect, C_BORDER, false, 1.5)

func _draw_weather_panel(rect: Rect2) -> void:
	_draw_glass(rect)
	draw_string(FONT_TITLE, Vector2(rect.position.x + 16, rect.position.y + 24), "INFORMACIÓN CLIMÁTICA", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_DIM)
	var s1_icon := str(forecast_stage1.get("icon", ""))
	var s1_name := str(forecast_stage1.get("name", "Despejado"))
	var s1_temp := float(forecast_stage1.get("temp_c", 18.0))
	draw_string(FONT_REGULAR, Vector2(rect.position.x + 16, rect.position.y + 54), "STAGE 1 (ACTUAL):", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_TEXT)
	draw_string(FONT_DATA, Vector2(rect.position.x + 178, rect.position.y + 54), "%s %s · %0.0f °C" % [s1_icon, s1_name.to_upper(), s1_temp], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_GOLD_HI)
	var s2_icon := str(forecast_stage2.get("icon", ""))
	var s2_name := str(forecast_stage2.get("name", "Pronóstico"))
	var s2_temp := float(forecast_stage2.get("temp_c", 15.0))
	draw_string(FONT_REGULAR, Vector2(rect.position.x + 16, rect.position.y + 88), "STAGE 2 (PRONÓSTICO):", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_TEXT)
	draw_string(FONT_DATA, Vector2(rect.position.x + 178, rect.position.y + 88), "%s %s · %0.0f °C" % [s2_icon, s2_name.to_upper(), s2_temp], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_BLUE)
	draw_string(FONT_REGULAR, Vector2(rect.position.x + 412, rect.position.y + 88), "(fiabilidad ~80%)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)

func _draw_notice_panel(rect: Rect2) -> void:
	_draw_glass(rect)
	draw_string(FONT_TITLE, Vector2(rect.position.x + 16, rect.position.y + 24), "REGLAMENTO DEL PARQUE Y SERVICIO", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_GOLD)
	draw_string(FONT_REGULAR, Vector2(rect.position.x + 16, rect.position.y + 48), "• Pinchazos y rines se reparan en el Área de Servicio.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TEXT)
	draw_string(FONT_REGULAR, Vector2(rect.position.x + 16, rect.position.y + 70), "• Al reparar, el neumático CONSERVA su desgaste.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TEXT)
	draw_string(FONT_TITLE, Vector2(rect.position.x + 16, rect.position.y + 92), "• ATENCIÓN: DESTALONADO = IRREPARABLE.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_ROSE)

func _draw_mounted_selection(rect: Rect2) -> void:
	_draw_glass(rect)
	draw_string(FONT_TITLE, Vector2(rect.position.x + 16, rect.position.y + 24), "1. MONTADOS (CLIC O ENTER/A PARA CAMBIAR COMPUESTO)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_DIM)
	var corners := ["DELANTERA IZQ (FL)", "DELANTERA DER (FR)", "TRASERA IZQ (RL)", "TRASERA DER (RR)"]
	var w := (rect.size.x - 48.0) / 4.0
	for i in 4:
		var slot_rect := Rect2(rect.position.x + 16 + i * w, rect.position.y + 36, w - 12, 64)
		var is_focused := _focus_id == ("mounted:%d" % i)
		draw_rect(slot_rect, Color(C_BG, 0.85 if is_focused else 0.7))
		draw_rect(slot_rect, C_GOLD_HI if is_focused else C_BORDER, false, 2.0 if is_focused else 1.0)
		draw_string(FONT_REGULAR, Vector2(slot_rect.position.x + 10, slot_rect.position.y + 20), corners[i], HORIZONTAL_ALIGNMENT_LEFT, slot_rect.size.x - 16, 10, C_DIM)
		var cid: String = str(mounted_compounds[i]) if i < mounted_compounds.size() else "gravel_normal"
		var clabel: String = str(compound_labels.get(cid, cid)).to_upper()
		draw_string(FONT_TITLE, Vector2(slot_rect.position.x + 10, slot_rect.position.y + 46), clabel, HORIZONTAL_ALIGNMENT_LEFT, slot_rect.size.x - 16, 13, C_GOLD_HI)

func _draw_trunk_selection(rect: Rect2) -> void:
	_draw_glass(rect)
	var mass_kg := carried_spares_count * 18.0
	draw_string(FONT_TITLE, Vector2(rect.position.x + 16, rect.position.y + 24), "2. REPUESTOS EN MALETERA (0, 1 O 2)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_DIM)
	draw_string(FONT_DATA, Vector2(rect.position.x + rect.size.x - 220, rect.position.y + 24), "PESO EXTRA: +%0.0f KG" % mass_kg, HORIZONTAL_ALIGNMENT_RIGHT, 200, 12, C_GOLD if carried_spares_count > 0 else C_DIM)
	for c in [0, 1, 2]:
		var sel: bool = carried_spares_count == c
		var is_focused := _focus_id == ("count:%d" % c)
		var btn := Rect2(rect.position.x + 16 + c * 86, rect.position.y + 42, 76, 36)
		draw_rect(btn, C_GOLD if sel else Color(C_BG, 0.7))
		draw_rect(btn, C_GOLD_HI if (sel or is_focused) else C_BORDER, false, 2.0 if is_focused else 1.0)
		draw_string(FONT_TITLE, Vector2(btn.position.x + 14, btn.position.y + 24), "%d REP." % c, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_BG if sel else C_TEXT)
	for i in carried_spares_count:
		var slot := Rect2(rect.position.x + 310 + i * 280, rect.position.y + 40, 260, 68)
		var is_focused := _focus_id == ("spare:%d" % i)
		draw_rect(slot, Color(C_BG, 0.85 if is_focused else 0.7))
		draw_rect(slot, C_GOLD_HI if is_focused else C_BORDER, false, 2.0 if is_focused else 1.0)
		draw_string(FONT_REGULAR, Vector2(slot.position.x + 12, slot.position.y + 22), "REPUESTO #%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)
		var cid: String = str(spare_compounds[i]) if i < spare_compounds.size() else str(allowed_compounds[0])
		draw_string(FONT_TITLE, Vector2(slot.position.x + 12, slot.position.y + 50), str(compound_labels.get(cid, cid)).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, slot.size.x - 20, 13, C_GOLD_HI)

func _draw_stock_selection(rect: Rect2) -> void:
	_draw_glass(rect)
	var stock_count := _stock_count()
	draw_string(FONT_TITLE, Vector2(rect.position.x + 16, rect.position.y + 24), "3. PARQUE DE SERVICIO (%d EN STOCK)" % stock_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_DIM)
	if stock_count <= 0:
		return
	var w := (rect.size.x - 48.0) / float(stock_count)
	for i in stock_count:
		var slot := Rect2(rect.position.x + 16 + i * w, rect.position.y + 40, w - 12, 84)
		var is_focused := _focus_id == ("stock:%d" % i)
		draw_rect(slot, Color(C_BG, 0.85 if is_focused else 0.7))
		draw_rect(slot, C_GOLD_HI if is_focused else C_BORDER, false, 2.0 if is_focused else 1.0)
		draw_string(FONT_REGULAR, Vector2(slot.position.x + 10, slot.position.y + 24), "STOCK #%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, slot.size.x - 16, 10, C_DIM)
		var cid: String = str(service_extra_compounds[i]) if i < service_extra_compounds.size() else str(allowed_compounds[0])
		draw_string(FONT_TITLE, Vector2(slot.position.x + 10, slot.position.y + 56), str(compound_labels.get(cid, cid)).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, slot.size.x - 16, 12, C_GOLD_HI)

func _draw_footer(rect: Rect2) -> void:
	draw_string(FONT_DATA, Vector2(rect.position.x + 10, rect.position.y + 24), "TOTAL POOL: 10 / 10", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_GOLD)
	draw_string(FONT_REGULAR, Vector2(rect.position.x + 10, rect.position.y + 46), "FLECHAS / D-PAD MOVER · ENTER / A CAMBIAR · R RESTAURAR · Y / F5 EMPEZAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)
	var reset_rect := Rect2(rect.position.x + 730, rect.position.y + 6, 170, 48)
	var reset_focused := _focus_id == "reset"
	draw_rect(reset_rect, Color(C_BG, 0.9 if reset_focused else 0.8))
	draw_rect(reset_rect, C_GOLD_HI if reset_focused else C_BORDER, false, 2.0 if reset_focused else 1.0)
	draw_string(FONT_TITLE, Vector2(reset_rect.position.x + 42, reset_rect.position.y + 30), "RESTAURAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_TEXT)
	var start_rect := Rect2(rect.position.x + 920, rect.position.y + 6, 248, 48)
	var confirm_focused := _focus_id == "confirm"
	draw_rect(start_rect, C_GOLD)
	draw_rect(start_rect, C_TEXT if confirm_focused else C_GOLD_HI, false, 2.5 if confirm_focused else 1.5)
	draw_string(FONT_TITLE, Vector2(start_rect.position.x + 58, start_rect.position.y + 30), "EMPEZAR RALLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_BG)

func _nav_rows() -> Array:
	var rows: Array = []
	rows.append(["mounted:0", "mounted:1", "mounted:2", "mounted:3"])
	var r1: Array[String] = ["count:0", "count:1", "count:2"]
	for i in carried_spares_count:
		r1.append("spare:%d" % i)
	rows.append(r1)
	var stock_count := _stock_count()
	if stock_count > 0:
		var r2: Array[String] = []
		for i in stock_count:
			r2.append("stock:%d" % i)
		rows.append(r2)
	rows.append(["reset", "confirm"])
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
	queue_redraw()

func _activate_focused() -> void:
	if _focus_id.begins_with("mounted:"):
		_cycle_compound(mounted_compounds, int(_focus_id.trim_prefix("mounted:")))
	elif _focus_id.begins_with("count:"):
		carried_spares_count = int(_focus_id.trim_prefix("count:"))
		_reconcile_pool()
	elif _focus_id.begins_with("spare:"):
		_cycle_compound(spare_compounds, int(_focus_id.trim_prefix("spare:")))
	elif _focus_id.begins_with("stock:"):
		_cycle_compound(service_extra_compounds, int(_focus_id.trim_prefix("stock:")))
	elif _focus_id == "reset":
		_init_data()
	elif _focus_id == "confirm":
		_on_confirm()
	queue_redraw()

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
			KEY_R:
				_init_data()
				queue_redraw()
				get_viewport().set_input_as_handled()
			KEY_F5:
				_on_confirm()
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
			JOY_BUTTON_X:
				_init_data()
				queue_redraw()
				get_viewport().set_input_as_handled()
			JOY_BUTTON_Y:
				_on_confirm()
				get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var pos := _to_logical(mb.position)
	# Botones 0/1/2 repuestos
	for c in [0, 1, 2]:
		var btn := Rect2(56 + 16 + c * 86, 376 + 42, 76, 36)
		if btn.has_point(pos):
			get_viewport().set_input_as_handled()
			carried_spares_count = c
			_reconcile_pool()
			queue_redraw()
			return
	var mw := (1168.0 - 48.0) / 4.0
	for i in 4:
		var slot_rect := Rect2(56 + 16 + i * mw, 246 + 36, mw - 12, 64)
		if slot_rect.has_point(pos):
			get_viewport().set_input_as_handled()
			_cycle_compound(mounted_compounds, i)
			queue_redraw()
			return
	for i in carried_spares_count:
		var slot := Rect2(56 + 310 + i * 280, 376 + 40, 260, 68)
		if slot.has_point(pos):
			get_viewport().set_input_as_handled()
			_cycle_compound(spare_compounds, i)
			queue_redraw()
			return
	var stock_count := _stock_count()
	if stock_count > 0:
		var sw := (1168.0 - 48.0) / float(stock_count)
		for i in stock_count:
			var slot := Rect2(56 + 16 + i * sw, 516 + 40, sw - 12, 84)
			if slot.has_point(pos):
				get_viewport().set_input_as_handled()
				_cycle_compound(service_extra_compounds, i)
				queue_redraw()
				return
	var reset_rect := Rect2(56 + 730, 684 + 6, 170, 48)
	if reset_rect.has_point(pos):
		get_viewport().set_input_as_handled()
		_init_data()
		queue_redraw()
		return
	var start_rect := Rect2(56 + 920, 684 + 6, 248, 48)
	if start_rect.has_point(pos):
		get_viewport().set_input_as_handled()
		_on_confirm()

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
