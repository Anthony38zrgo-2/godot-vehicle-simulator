extends Control
signal retire_requested
signal retry_requested
signal next_requested
signal new_rally_requested

const FONT := preload("res://fonts/libron/Libron-Regular.ttf")
var compact: PanelContainer
var heading: Label
var standings: Tree
var penalty_notice: Label
var retire_button: Button
var results: PanelContainer
var title: Label
var table: Tree
var next_button: Button
var notice: Label
var last_signature: String = ""
var retry_button: Button

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
	compact = PanelContainer.new()
	add_child(compact)
	var box := VBoxContainer.new()
	compact.add_child(box)
	heading = Label.new()
	box.add_child(heading)
	penalty_notice = Label.new()
	penalty_notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	penalty_notice.custom_minimum_size.x = 500
	penalty_notice.add_theme_color_override("font_color", Color(1.0, 0.45, 0.15))
	box.add_child(penalty_notice)
	standings = Tree.new()
	standings.hide_root = true
	standings.columns = 4
	standings.column_titles_visible = true
	standings.custom_minimum_size = Vector2(500, 140)
	for i in 4:
		standings.set_column_title(i, ["Pos", "Piloto", "Parcial oficial", "Penal."][i])
		standings.set_column_clip_content(i, true)
		standings.set_column_expand(i, true)
		standings.set_column_custom_minimum_width(i, [35, 185, 135, 80][i])
	box.add_child(standings)
	retire_button = Button.new()
	retire_button.text = "Abandonar especial"
	retire_button.pressed.connect(func(): retire_requested.emit())
	box.add_child(retire_button)
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
	if compact == null:
		return
	visible = not state.is_empty()
	if state.is_empty():
		return
	var factor := minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0)
	compact.position = Vector2(14, 170) * factor
	compact.scale = Vector2.ONE * factor
	compact.custom_minimum_size = Vector2(520, 220)
	results.visible = bool(state.complete)
	compact.visible = not results.visible
	var signature := JSON.stringify(state)
	if signature == last_signature:
		return
	last_signature = signature
	heading.text = "GENERAL · Parcial %d/%d" % [state.sector, state.sector_count] if int(state.sector) > 0 else "GENERAL · Sin parcial"
	if int(state.sector) > 0 and not state.player_retired:
		heading.text += "   Δ %+.3f s" % (float(state.delta_ms) / 1000.0)
	var player_penalty := 0
	var reasons: Array = []
	for row: Dictionary in state.rows:
		if row.player:
			player_penalty = int(row.get("penalty_ms", 0))
			for event: Dictionary in row.get("penalties", []):
				if str(event.reason) not in reasons:
					reasons.append(str(event.reason))
	penalty_notice.text = "PENALIZACIÓN +%.0f s · %s" % [player_penalty / 1000.0, ", ".join(reasons)] if player_penalty > 0 else "Sin penalizaciones"
	standings.clear()
	var standings_root := standings.create_item()
	var player_item: TreeItem = null
	for row: Dictionary in state.rows:
		var item := standings.create_item(standings_root)
		var rank := str(row.position) if int(row.position) > 0 and int(state.sector) > 0 else "—"
		var partial_index := int(row.get("partial_index", 0))
		var partial := "P%d %s" % [partial_index, clock(row.get("partial_ms"))] if partial_index > 0 else "—"
		var sanction := "+%.0f s" % (float(row.get("penalty_ms", 0)) / 1000.0) if int(row.get("penalty_ms", 0)) > 0 else "—"
		var values := [rank, row.name, partial, sanction]
		for i in 4:
			item.set_text(i, values[i])
			item.set_tooltip_text(i, "Parcial oficial (incluye sanciones): %s · %s · %s · %s" % [row.name, partial, sanction, row.status])
			if row.player:
				player_item = item
				item.set_custom_color(i, Color(1.0, 0.85, 0.3))
	if player_item != null:
		standings.scroll_to_item(player_item, true)
	if not results.visible:
		return
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
		var columns := [str(row.position) if int(row.position) > 0 else "—", row.name, row.car + " - " + row.team, clock(row.stage_ms), clock(row.total_ms), row.status + (" (+%.0f s)" % (float(row.get("penalty_ms", 0)) / 1000.0) if int(row.get("penalty_ms", 0)) > 0 else "")]
		for i in columns.size():
			item.set_text(i, columns[i])
			item.set_tooltip_text(i, columns[i])
			if row.player:
				item.set_custom_color(i, Color(1.0, 0.85, 0.3))

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
	if bool(state.get("event_is_last", false)) or num >= total:
		return "RESULTADOS · Especial %d/%d · %s%s · Clasificación general" % [num, total, sid, when]
	return "RESULTADOS · Especial %d/%d · %s%s · Clasificación general" % [num, total, sid, when]

func _next_label(state: Dictionary) -> String:
	if not state.has("event_stage_id"):
		return "Repetir especial (práctica)"
	if bool(state.get("event_is_last", false)) or _stage_number(state) >= int(state.get("event_total", 10)):
		return "Ver resultado final"
	var nxt := _stage_number(state) + 1
	return "Continuar a Stage %d" % nxt

func _next_disabled(state: Dictionary) -> bool:
	# En el evento la continuación tras completar o abandonar siempre está
	# disponible (reenganche). En práctica/legado se conserva el bloqueo.
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
