extends Control
signal retire_requested
signal retry_requested
signal next_requested
signal new_rally_requested

# Clasificación en carrera: bloque de tres filas (jugador ±1) a la derecha,
# con el estilo de la HUD. La tabla completa vive en el panel de resultados.

const FONT := preload("res://fonts/libron/Libron-Regular.ttf")
const BOLD := preload("res://fonts/libron/Libron-Bold.ttf")
const DIN_BOLD := preload("res://fonts/D-DIN-Bold.ttf")

const C_FACE := Color("#2b3d4d")
const C_FIELD := Color("#0c151d")
const C_HI := Color("#93afc8")
const C_LIGHT := Color("#5d7890")
const C_SHADOW := Color("#101b25")
const C_DARK := Color("#000000")
const C_TEXT := Color("#e2edf6")
const C_DIM := Color("#9eb3c5")
const C_ROSE := Color("#ff6b61")
const C_GLASS := Color("#16232f")
const C_RIM := Color("#7fa8c9")
const C_SEL := Color("#3b3324")
const C_GOLD := Color("#e3b23c")

const BLOCK_RECT := Rect2(1620, 168, 276, 150)

var results: PanelContainer
var title: Label
var table: Tree
var next_button: Button
var notice: Label
var last_signature: String = ""
var retry_button: Button
var rows_cache: Array = []
var state_cache: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var custom_theme := Theme.new()
	custom_theme.default_font = FONT
	custom_theme.default_font_size = 16
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.055, 0.07, 0.085, 0.98)
	background.border_color = Color(0.35, 0.46, 0.53)
	background.set_border_width_all(1)
	background.content_margin_left = 10
	background.content_margin_right = 10
	background.content_margin_top = 8
	background.content_margin_bottom = 8
	custom_theme.set_stylebox("panel", "PanelContainer", background)
	theme = custom_theme

	results = PanelContainer.new()
	add_child(results)
	results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results.offset_left = 36
	results.offset_top = 40
	results.offset_right = -36
	results.offset_bottom = -40
	var result_box := VBoxContainer.new()
	results.add_child(result_box)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_box.add_child(title)
	table = Tree.new()
	table.columns = 6
	table.hide_root = true
	table.column_titles_visible = true
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var headers := ["Posición", "Piloto", "Coche - equipo", "Tiempo del stage", "Tiempo acumulado", "Estado"]
	for i in headers.size():
		table.set_column_title(i, headers[i])
		table.set_column_expand(i, true)
		table.set_column_clip_content(i, true)
		table.set_column_custom_minimum_width(i, [55, 145, 200, 130, 145, 200][i])
		table.set_column_expand_ratio(i, [1, 3, 5, 2, 2, 5][i])
	result_box.add_child(table)
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_box.add_child(notice)
	var buttons := HBoxContainer.new()
	result_box.add_child(buttons)
	var retry := Button.new()
	retry_button = retry
	retry.text = "Reintentar especial (práctica)"
	retry.pressed.connect(func(): retry_requested.emit())
	buttons.add_child(retry)
	next_button = Button.new()
	next_button.text = "Siguiente especial — Rusia"
	next_button.pressed.connect(func(): next_requested.emit())
	buttons.add_child(next_button)
	var restart := Button.new()
	restart.text = "Nuevo rally"
	restart.pressed.connect(func(): new_rally_requested.emit())
	buttons.add_child(restart)
	results.visible = false


func clock(milliseconds: Variant) -> String:
	if milliseconds == null:
		return "—"
	var value := int(milliseconds)
	return "%d:%02d.%03d" % [value / 60000, (value / 1000) % 60, value % 1000]


func present(state: Dictionary, viewport_size: Vector2) -> void:
	visible = not state.is_empty()
	if state.is_empty():
		return
	state_cache = state
	rows_cache = state.get("rows", [])
	results.visible = bool(state.complete)
	var signature := JSON.stringify(state)
	if signature == last_signature:
		return
	last_signature = signature
	if results.visible:
		_present_results(state)
	queue_redraw()


func _present_results(state: Dictionary) -> void:
	var final_result := str(state.get("event_status", "")) == "finished"
	next_button.visible = not final_result
	retry_button.visible = not state.has("event_stage_id")
	if final_result:
		_present_final(state)
		return
	title.text = _event_title(state)
	next_button.disabled = _next_disabled(state)
	next_button.text = _next_label(state)
	notice.text = _event_notice(state)
	table.clear()
	var root := table.create_item()
	for row: Dictionary in state.rows:
		var item := table.create_item(root)
		var columns := [
			str(row.position) if int(row.position) > 0 else "—",
			row.name,
			row.car + " - " + row.team,
			clock(row.stage_ms),
			clock(row.total_ms),
			row.status + (" (+%.0f s)" % (float(row.get("penalty_ms", 0)) / 1000.0) if int(row.get("penalty_ms", 0)) > 0 else "")
		]
		for i in columns.size():
			item.set_text(i, columns[i])
			item.set_tooltip_text(i, columns[i])
			if row.player:
				item.set_custom_color(i, Color(1.0, 0.85, 0.3))


# =============================================================================
# DIBUJO DEL BLOQUE EN CARRERA
# =============================================================================


func _draw() -> void:
	if state_cache.is_empty() or results.visible:
		return
	var factor := minf(size.x / 1920.0, size.y / 1080.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * factor)
	_glass(BLOCK_RECT)
	var body := Rect2(
		BLOCK_RECT.position.x + 8, BLOCK_RECT.position.y + 8, BLOCK_RECT.size.x - 16, BLOCK_RECT.size.y - 16
	)
	draw_rect(body, C_FIELD)
	_sunken(body)

	var sector := int(state_cache.get("sector", 0))
	var sector_count := int(state_cache.get("sector_count", 0))
	var heading := "GENERAL" if sector <= 0 else "GENERAL · PARCIAL %d/%d" % [sector, sector_count]
	_text(Rect2(body.position.x + 4, body.position.y + 2, 210, 14), heading, 9, Color("#6db2e8"), true)
	draw_rect(Rect2(body.position.x + 3, body.position.y + 18, body.size.x - 6, 1), C_SHADOW)

	var visible_rows := _window_rows()
	var row_h := 37.0
	for slot in visible_rows.size():
		var entry: Dictionary = visible_rows[slot]
		var row: Dictionary = entry.row
		var row_rect := Rect2(
			body.position.x + 3, body.position.y + 21 + float(slot) * (row_h + 1.0), body.size.x - 6, row_h
		)
		var player := bool(row.player)
		if player:
			draw_rect(row_rect, C_SEL)
			draw_rect(Rect2(row_rect.position.x, row_rect.position.y, 3, row_rect.size.y), C_GOLD)
			draw_rect(Rect2(row_rect.position.x, row_rect.position.y, row_rect.size.x, 1), C_GOLD)
			draw_rect(Rect2(row_rect.position.x, row_rect.end.y - 1, row_rect.size.x, 1), C_GOLD)
			draw_rect(Rect2(row_rect.end.x - 1, row_rect.position.y, 1, row_rect.size.y), C_GOLD)
		var rank := "%d" % int(row.get("position", 0)) if int(row.get("position", 0)) > 0 else "—"
		_num(Rect2(row_rect.position.x + 8, row_rect.position.y, 22, row_h), rank, 14, C_TEXT if player else C_DIM)
		_text(
			Rect2(row_rect.position.x + 32, row_rect.position.y, 130, row_h),
			str(row.get("name", "")),
			11,
			C_TEXT if player else C_DIM,
			player
		)
		var partial_index := int(row.get("partial_index", 0))
		var partial := clock(row.get("partial_ms")) if partial_index > 0 else "—"
		_num(
			Rect2(row_rect.position.x + 158, row_rect.position.y, 78, row_h),
			partial,
			13,
			C_TEXT if player else C_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT,
			78
		)
	draw_set_transform(Vector2.ZERO)


func _window_rows() -> Array:
	var rows: Array = rows_cache
	if rows.is_empty():
		return []
	var player_index := -1
	for i in rows.size():
		if bool(rows[i].get("player", false)):
			player_index = i
			break
	if player_index < 0:
		player_index = 0
	var result: Array = []
	for offset in [-1, 0, 1]:
		var index: int = player_index + offset
		if index >= 0 and index < rows.size():
			result.append({"row": rows[index], "offset": offset})
	return result


# =============================================================================
# PRIMITIVAS
# =============================================================================


func _glass(rect: Rect2) -> void:
	var body := StyleBoxFlat.new()
	body.bg_color = Color(C_GLASS, 0.90)
	body.border_color = Color(C_RIM, 0.40)
	body.set_border_width_all(1)
	body.set_corner_radius_all(10)
	draw_style_box(body, rect)


func _sunken(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 1), C_SHADOW)
	draw_rect(Rect2(rect.position.x, rect.position.y, 1, rect.size.y), C_SHADOW)
	draw_rect(Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1), C_HI)
	draw_rect(Rect2(rect.end.x - 1, rect.position.y, 1, rect.size.y), C_HI)


func _num(
	rect: Rect2,
	value: String,
	size_px: int,
	color: Color,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	width_override: float = -1.0
) -> void:
	if value.is_empty():
		return
	var width: float = rect.size.x if width_override < 0.0 else width_override
	var line_height := BOLD.get_height(size_px)
	var baseline := rect.position.y + (rect.size.y + line_height) * 0.5 - BOLD.get_descent(size_px)
	draw_string(BOLD, Vector2(round(rect.position.x), round(baseline)), value, align, width, size_px, color)


func _text(
	rect: Rect2,
	value: String,
	size_px: int,
	color: Color,
	bold: bool = false,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	width_override: float = -1.0
) -> void:
	if value.is_empty():
		return
	var font: Font = BOLD if bold else FONT
	var width: float = rect.size.x if width_override < 0.0 else width_override
	var line_height := font.get_height(size_px)
	var baseline := rect.position.y + (rect.size.y + line_height) * 0.5 - font.get_descent(size_px)
	draw_string(font, Vector2(round(rect.position.x), round(baseline)), value, align, width, size_px, color)


func _present_final(state: Dictionary) -> void:
	var rows: Array = state.get("event_final_rows", [])
	var points: Dictionary = state.get("event_points", {})
	title.text = "RESULTADO FINAL · RALLY DE RUSIA"
	var winner_id := str(points.get("winner", ""))
	var winner_name := ""
	for row: Dictionary in rows:
		if str(row.id) == winner_id:
			winner_name = str(row.name)
	notice.text = "Ganador: %s · Diez especiales completadas · Puntos: general + domingo + Power Stage." % winner_name if not winner_name.is_empty() else "Rally finalizado sin participantes clasificados."
	table.clear()
	table.columns = 7
	var headers := ["Posición", "Piloto", "Tiempo acumulado", "General", "Domingo", "Power Stage", "Puntos totales"]
	for i in headers.size():
		table.set_column_title(i, headers[i])
		table.set_column_expand(i, true)
		table.set_column_clip_content(i, true)
		table.set_column_custom_minimum_width(i, [55, 145, 145, 70, 70, 90, 90][i])
		table.set_column_expand_ratio(i, [1, 3, 3, 1, 1, 1, 1][i])
	var root := table.create_item()
	for row: Dictionary in rows:
		var id := str(row.id)
		var columns := [str(row.position), str(row.name), clock(row.grand_total_ms)]
		for category in ["general", "sunday", "power", "total"]:
			columns.append(str((points.get(category, {}) as Dictionary).get(id, 0)))
		var item := table.create_item(root)
		for i in columns.size():
			item.set_text(i, columns[i])
			item.set_tooltip_text(i, columns[i])
			if id == "player":
				item.set_custom_color(i, Color(1.0, 0.85, 0.3))


func _stage_number(state: Dictionary) -> int:
	if state.has("event_cursor"):
		return int(state["event_cursor"]) + 1
	return int(state.get("leg", 1))


func _stage_id(state: Dictionary) -> String:
	if state.has("event_stage_id"):
		return str(state["event_stage_id"])
	var leg := int(state.get("leg", 1))
	return "russia_stage%d" % leg


func _event_title(state: Dictionary) -> String:
	var total := int(state.get("event_total", 10))
	var num := _stage_number(state)
	var sid := _stage_id(state)
	var sched: Dictionary = state.get("event_schedule", {})
	var when := ""
	if not sched.is_empty():
		when = " · %s %s" % [str(sched.get("day_label", "")), str(sched.get("start", ""))]
	return "RESULTADOS · Especial %d/%d · %s%s · Clasificación general" % [num, total, sid, when]


func _next_label(state: Dictionary) -> String:
	if not state.has("event_stage_id"):
		return "Repetir especial (práctica)"
	if bool(state.get("event_is_last", false)) or _stage_number(state) >= int(state.get("event_total", 10)):
		return "Ver resultado final"
	var nxt := _stage_number(state) + 1
	return "Continuar a Stage %d" % nxt


func _next_disabled(state: Dictionary) -> bool:
	if state.has("event_stage_id"):
		return false
	return bool(state.get("player_retired", false))


func _event_notice(state: Dictionary) -> String:
	if state.has("event_stage_id"):
		var sid := _stage_id(state)
		var sched: Dictionary = state.get("event_schedule", {})
		var next_info := ""
		if not bool(state.get("event_is_last", false)):
			next_info = " Próxima: Stage %d." % (_stage_number(state) + 1)
		else:
			next_info = " Última especial: usa «Ver resultado final»."
		var base := "Cierre idempotente %s. Reenganche con +300 s si abandonaste; sin reintento oficial." % sid
		if not sched.is_empty():
			base += " Horario %s %s." % [str(sched.get("day_label", "")), str(sched.get("start", ""))]
		if bool(state.get("event_player_retired", state.get("player_retired", false))):
			base += " Abandono registrado: puedes continuar a la siguiente."
		if not str(state.get("error", "")).is_empty():
			base += "  " + str(state.get("error", ""))
		return base + next_info
	if bool(state.get("player_retired", false)):
		return "El rally termina para el jugador al abandonar. Reintentar conserva la preparación y semilla."
	return "Continuar conserva acumulados y aplica asistencia limitada."
