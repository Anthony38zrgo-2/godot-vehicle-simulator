extends Control
signal retire_requested
signal retry_requested
signal next_requested
signal new_rally_requested

const FONT := preload("res://fonts/libron/Libron-Regular.ttf")
var compact: PanelContainer
var heading: Label
var standings: VBoxContainer
var retire_button: Button
var results: PanelContainer
var title: Label
var table: Tree
var next_button: Button
var notice: Label
var last_signature: String = ""

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
	standings = VBoxContainer.new()
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
	if compact == null or state.is_empty():
		return
	var factor := minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0)
	compact.position = Vector2(14, 170) * factor
	compact.scale = Vector2.ONE * factor
	compact.custom_minimum_size = Vector2(355, 205)
	results.visible = bool(state.complete)
	compact.visible = not results.visible
	var signature := JSON.stringify(state)
	if signature == last_signature:
		return
	last_signature = signature
	heading.text = "GENERAL · Parcial %d/%d" % [state.sector, state.sector_count] if int(state.sector) > 0 else "GENERAL · Sin parcial"
	if int(state.sector) > 0 and not state.player_retired:
		heading.text += "   Δ %+.3f s" % (float(state.delta_ms) / 1000.0)
	for child in standings.get_children():
		standings.remove_child(child)
		child.queue_free()
	var player_index := 0
	for i in state.rows.size():
		if state.rows[i].player:
			player_index = i
	var selected: Array = [0]
	for i in range(maxi(1, player_index - 1), mini(state.rows.size(), player_index + 3)):
		selected.append(i)
	for i in state.rows.size():
		if selected.size() >= 5:
			break
		if i not in selected:
			selected.append(i)
	selected.sort()
	for i: int in selected:
		var row: Dictionary = state.rows[i]
		var line := Label.new()
		var rank := str(row.position) if int(row.position) > 0 and int(state.sector) > 0 else "—"
		line.text = "%s  %s  %s" % [rank, row.name, clock(row.stage_ms) if int(state.sector) > 0 else row.status]
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.custom_minimum_size.x = 350
		if row.player:
			line.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		standings.add_child(line)
	if not results.visible:
		return
	title.text = "RESULTADOS · Especial %d · Rusia Stage 1 · Clasificación general" % state.leg
	next_button.disabled = bool(state.player_retired)
	notice.text = "El rally termina para el jugador al abandonar. Reintentar conserva la preparación y semilla." if state.player_retired else "Continuar conserva acumulados y aplica asistencia limitada. La siguiente especial reutiliza Rusia Stage 1."
	if not str(state.get("error", "")).is_empty():
		notice.text += "  " + str(state.error)
	table.clear()
	var root := table.create_item()
	for row: Dictionary in state.rows:
		var item := table.create_item(root)
		var columns := [str(row.position) if int(row.position) > 0 else "—", row.name, row.car + " - " + row.team, clock(row.stage_ms), clock(row.total_ms), row.status]
		for i in columns.size():
			item.set_text(i, columns[i])
			item.set_tooltip_text(i, columns[i])
			if row.player:
				item.set_custom_color(i, Color(1.0, 0.85, 0.3))
