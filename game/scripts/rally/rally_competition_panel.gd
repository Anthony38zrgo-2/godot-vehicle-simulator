extends Control

signal retire_requested
signal retry_requested
signal next_requested
signal workshop_requested
signal new_rally_requested

# Tipografía exclusiva del HUD en pista (preservada sin cambios)
const HUD_FONT: Font = preload("res://fonts/montserrat/Montserrat-Regular.ttf")
const HUD_BOLD: Font = preload("res://fonts/montserrat/Montserrat-Bold.ttf")

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _StageResultsViewScene := preload("res://ui/screens/competition/stage_results_view.tscn")
const _FinalPodiumViewScene := preload("res://ui/screens/competition/final_podium_view.tscn")

const BLOCK_RECT := Rect2(1620, 168, 276, 150)

## Live top-right compact standings card is superseded by the top-left CMR2 3-row split standings.
var show_live_corner_block: bool = false

# Nodos principales de interfaz (preservando contrato público)
var results: PanelContainer
var title: Label
var header_subtitle: Label
var badge_label: Label
var badge_value: Label

var hero_panel: PanelContainer
var hero_header_label: Label
var hero_content_vbox: VBoxContainer

var table_panel: PanelContainer
var table_title: Label
var table_legend: Label
var table: Tree
var notice: Label

var retry_button: Button
var next_button: Button
var workshop_button: Button
var restart_button: Button
var shortcuts_label: Label

var _stage_results_view: Control = null
var _final_podium_view: Control = null

var last_signature: String = ""
var rows_cache: Array = []
var state_cache: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_results_view = _StageResultsViewScene.instantiate()
	_final_podium_view = _FinalPodiumViewScene.instantiate()
	_build_ui()


func _exit_tree() -> void:
	if _stage_results_view != null and not _stage_results_view.is_inside_tree():
		_stage_results_view.free()
	if _final_podium_view != null and not _final_podium_view.is_inside_tree():
		_final_podium_view.free()


func _build_ui() -> void:
	var c_base := _Tokens.get_color("bg_base")
	var c_header := _Tokens.get_color("bg_header")
	var c_well := _Tokens.get_color("bg_well")
	var c_border := _Tokens.get_color("border_card")
	var c_text := _Tokens.get_color("text_primary")
	var c_muted := _Tokens.get_color("text_muted")
	var c_accent := _Tokens.get_color("accent_rally")
	var c_info := _Tokens.get_color("status_info")
	var r := _Tokens.get_radius("default")

	results = PanelContainer.new()
	results.theme = _Theme.get_menu_theme()
	results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results.mouse_filter = Control.MOUSE_FILTER_STOP
	results.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_base, _Tokens.get_color("transparent"), 0, 0))
	add_child(results)

	var root_margin := MarginContainer.new()
	root_margin.add_theme_constant_override("margin_left", 28)
	root_margin.add_theme_constant_override("margin_right", 28)
	root_margin.add_theme_constant_override("margin_top", 18)
	root_margin.add_theme_constant_override("margin_bottom", 18)
	results.add_child(root_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	root_margin.add_child(root_vbox)

	# 1. Cabecera
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_header, c_border, 1, r, 18, 10))
	root_vbox.add_child(header_panel)

	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 16)
	header_panel.add_child(header_hbox)

	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 2)
	header_hbox.add_child(title_vbox)

	title = Label.new()
	title.add_theme_font_override("font", _Tokens.get_font("title"))
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", c_text)
	title_vbox.add_child(title)

	header_subtitle = Label.new()
	header_subtitle.add_theme_font_override("font", _Tokens.get_font("medium"))
	header_subtitle.add_theme_font_size_override("font_size", 10)
	header_subtitle.add_theme_color_override("font_color", c_muted)
	title_vbox.add_child(header_subtitle)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(header_spacer)

	var status_badge := PanelContainer.new()
	status_badge.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_well, c_border, 1, r, 14, 4))
	header_hbox.add_child(status_badge)

	var status_vbox := VBoxContainer.new()
	status_vbox.add_theme_constant_override("separation", 1)
	status_badge.add_child(status_vbox)

	badge_label = Label.new()
	badge_label.text = "ESTADO DE PRUEBA"
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_label.add_theme_font_override("font", _Tokens.get_font("subtitle"))
	badge_label.add_theme_font_size_override("font_size", 11)
	badge_label.add_theme_color_override("font_color", c_muted)
	status_vbox.add_child(badge_label)

	badge_value = Label.new()
	badge_value.text = "OFICIAL"
	badge_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_value.add_theme_font_override("font", _Tokens.get_font("data_bold_tight"))
	badge_value.add_theme_font_size_override("font_size", 13)
	badge_value.add_theme_color_override("font_color", c_info)
	status_vbox.add_child(badge_value)

	# 2. Cuerpo dividido (Hero Cards + Tabla)
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 14)
	root_vbox.add_child(body_hbox)

	hero_panel = PanelContainer.new()
	hero_panel.custom_minimum_size = Vector2(360, 0)
	hero_panel.add_theme_stylebox_override("panel", _Theme.make_panel_from_preset("panel.window"))
	body_hbox.add_child(hero_panel)

	var hero_margin := MarginContainer.new()
	hero_margin.add_theme_constant_override("margin_left", 14)
	hero_margin.add_theme_constant_override("margin_right", 14)
	hero_margin.add_theme_constant_override("margin_top", 12)
	hero_margin.add_theme_constant_override("margin_bottom", 12)
	hero_panel.add_child(hero_margin)

	var hero_vbox := VBoxContainer.new()
	hero_vbox.add_theme_constant_override("separation", 10)
	hero_margin.add_child(hero_vbox)

	hero_header_label = Label.new()
	hero_header_label.text = "RESUMEN DEL PILOTO"
	hero_header_label.add_theme_font_override("font", _Tokens.get_font("subtitle"))
	hero_header_label.add_theme_font_size_override("font_size", 15)
	hero_header_label.add_theme_color_override("font_color", c_accent)
	hero_vbox.add_child(hero_header_label)

	var hero_line := ColorRect.new()
	hero_line.custom_minimum_size = Vector2(0, 1)
	hero_line.color = Color(_Tokens.get_color("border_hover"), 0.25)
	hero_vbox.add_child(hero_line)

	var hero_scroll := ScrollContainer.new()
	hero_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hero_vbox.add_child(hero_scroll)

	hero_content_vbox = VBoxContainer.new()
	hero_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_content_vbox.add_theme_constant_override("separation", 8)
	hero_scroll.add_child(hero_content_vbox)

	# Panel Derecho (Tabla + Aviso)
	table_panel = PanelContainer.new()
	table_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_panel.add_theme_stylebox_override("panel", _Theme.make_panel_from_preset("panel.window"))
	body_hbox.add_child(table_panel)

	var table_margin := MarginContainer.new()
	table_margin.add_theme_constant_override("margin_left", 14)
	table_margin.add_theme_constant_override("margin_right", 14)
	table_margin.add_theme_constant_override("margin_top", 12)
	table_margin.add_theme_constant_override("margin_bottom", 12)
	table_panel.add_child(table_margin)

	var table_vbox := VBoxContainer.new()
	table_vbox.add_theme_constant_override("separation", 8)
	table_margin.add_child(table_vbox)

	var table_header_hbox := HBoxContainer.new()
	table_vbox.add_child(table_header_hbox)

	table_title = Label.new()
	table_title.text = "CLASIFICACIÓN OFICIAL"
	table_title.add_theme_font_override("font", _Tokens.get_font("subtitle"))
	table_title.add_theme_font_size_override("font_size", 15)
	table_title.add_theme_color_override("font_color", c_text)
	table_header_hbox.add_child(table_title)

	var table_spacer := Control.new()
	table_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_header_hbox.add_child(table_spacer)

	table_legend = Label.new()
	table_legend.text = "FILA DESTACADA: TU VEHÍCULO"
	table_legend.add_theme_font_override("font", _Tokens.get_font("medium"))
	table_legend.add_theme_font_size_override("font_size", 10)
	table_legend.add_theme_color_override("font_color", c_accent)
	table_header_hbox.add_child(table_legend)

	table = Tree.new()
	table.focus_mode = Control.FOCUS_NONE
	table.columns = 6
	table.hide_root = true
	table.column_titles_visible = true
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_Theme.apply_tree(table, 12)
	table.add_theme_font_override("font", _Tokens.get_font("medium_tight"))
	table.add_theme_font_size_override("title_button_font_size", 13)
	table.add_theme_color_override("title_button_color", c_text)
	table.add_theme_constant_override("v_separation", 4)
	table.add_theme_constant_override("h_separation", 8)
	table.add_theme_constant_override("item_margin", 6)
	var headers := ["Posición", "Piloto", "Coche - equipo", "Tiempo del stage", "Tiempo acumulado", "Estado"]
	for i in headers.size():
		table.set_column_title(i, headers[i])
		table.set_column_expand(i, true)
		table.set_column_clip_content(i, true)
		table.set_column_custom_minimum_width(i, [55, 145, 200, 130, 145, 200][i])
		table.set_column_expand_ratio(i, [1, 3, 5, 2, 2, 5][i])
	table_vbox.add_child(table)

	var notice_panel := PanelContainer.new()
	notice_panel.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_well, c_border, 1, r, 12, 6))
	table_vbox.add_child(notice_panel)

	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_font_override("font", _Tokens.get_font("regular"))
	notice.add_theme_font_size_override("font_size", 10)
	notice.add_theme_color_override("font_color", c_text)
	notice_panel.add_child(notice)

	# 3. Pie de página
	var footer_panel := PanelContainer.new()
	footer_panel.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_header, c_border, 1, r, 18, 8))
	root_vbox.add_child(footer_panel)

	var footer_hbox := HBoxContainer.new()
	footer_hbox.add_theme_constant_override("separation", 14)
	footer_panel.add_child(footer_hbox)

	retry_button = Button.new()
	retry_button.text = "REINTENTAR ESPECIAL (PRÁCTICA)"
	_Theme.apply_tone_button(retry_button, "chrome", 15, 18, 8)
	retry_button.pressed.connect(func(): retry_requested.emit())
	footer_hbox.add_child(retry_button)

	var footer_spacer1 := Control.new()
	footer_spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(footer_spacer1)

	shortcuts_label = Label.new()
	shortcuts_label.text = "[ ENTER / A ] CONTINUAR  ·  [ R / X ] REINTENTAR  ·  [ ESC / B ] SALIR"
	shortcuts_label.add_theme_font_override("font", _Tokens.get_font("regular"))
	shortcuts_label.add_theme_font_size_override("font_size", 10)
	shortcuts_label.add_theme_color_override("font_color", Color(c_muted, 0.8))
	footer_hbox.add_child(shortcuts_label)

	var footer_spacer2 := Control.new()
	footer_spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(footer_spacer2)

	restart_button = Button.new()
	restart_button.text = "NUEVO RALLY"
	_style_muted_button(restart_button)
	restart_button.pressed.connect(func(): new_rally_requested.emit())
	footer_hbox.add_child(restart_button)

	workshop_button = Button.new()
	workshop_button.text = "RUEDAS Y REPARACIONES"
	_Theme.apply_tone_button(workshop_button, "gold", 16, 24, 8)
	workshop_button.hide()
	workshop_button.pressed.connect(func(): workshop_requested.emit())
	footer_hbox.add_child(workshop_button)

	next_button = Button.new()
	next_button.text = "CONTINUAR A LA SIGUIENTE ESPECIAL ▶"
	_Theme.apply_tone_button(next_button, "gold", 16, 24, 8)
	next_button.pressed.connect(func(): next_requested.emit())
	footer_hbox.add_child(next_button)

	results.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not results.visible:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	var button_has_focus := (
		focus_owner is BaseButton
		and not (focus_owner as BaseButton).disabled
		and (focus_owner as Control).is_visible_in_tree()
	)
	if event.is_action_pressed("ui_accept"):
		if button_has_focus:
			return
		if workshop_button != null and workshop_button.visible and not workshop_button.disabled:
			workshop_requested.emit()
			get_viewport().set_input_as_handled()
		elif next_button != null and next_button.visible and not next_button.disabled:
			next_requested.emit()
			get_viewport().set_input_as_handled()
		elif restart_button != null and restart_button.visible and not next_button.visible:
			new_rally_requested.emit()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if not next_button.visible and restart_button != null and restart_button.visible:
			new_rally_requested.emit()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			if retry_button != null and retry_button.visible and not retry_button.disabled:
				retry_requested.emit()
				get_viewport().set_input_as_handled()


func _style_muted_button(btn: Button) -> void:
	var c_danger := _Tokens.get_color("status_danger")
	var r := _Tokens.get_radius("default")
	_Theme.apply_tone_button(btn, "muted", 15, 16, 8, r)
	var hover := _Tokens.get_flat_stylebox(Color("#2b1316"), c_danger, 1, r, 16, 8)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_hover_color", c_danger)
	btn.add_theme_color_override("font_pressed_color", c_danger)


func clock(milliseconds: Variant) -> String:
	if milliseconds == null:
		return "—"
	var value := int(milliseconds)
	return "%d:%02d.%03d" % [value / 60000, (value / 1000) % 60, value % 1000]


func present(state: Dictionary, _viewport_size: Vector2) -> void:
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
		var _rm := get_node_or_null("/root/RallyMusic")
		if _rm != null and _rm.has_method("on_enter_results"):
			_rm.call("on_enter_results")
		_present_results(state)
	queue_redraw()


func _present_results(state: Dictionary) -> void:
	var final_result := str(state.get("event_status", "")) == "finished"
	var allow_next: bool = bool(state.get("allow_next", true))
	var is_single_stage: bool = bool(state.get("single_stage_mode", false))
	var mode_name: String = str(state.get("session_mode", "rally"))
	var workshop_available := not final_result and bool(state.get("allow_workshop", false))
	var focus_workshop := workshop_available and not workshop_button.visible
	workshop_button.visible = workshop_available
	if focus_workshop:
		workshop_button.grab_focus()
	next_button.visible = not final_result and allow_next
	retry_button.visible = (not state.has("event_stage_id") or is_single_stage) and not final_result
	if final_result:
		_present_final(state)
		return

	title.text = _event_title(state)
	var num := _stage_number(state)
	var total := int(state.get("event_total", 10))
	var sid := _stage_id(state).to_upper()
	if is_single_stage:
		header_subtitle.text = "TRAMO ÚNICO · %s · CRONOMETRAJE INDEPENDIENTE" % sid
	elif mode_name == "championship":
		header_subtitle.text = "CAMPEONATO · ESPECIAL %d DE %d · %s · CRONOMETRAJE OFICIAL" % [num, total, sid]
	else:
		header_subtitle.text = "ESPECIAL %d DE %d · %s · CRONOMETRAJE OFICIAL" % [num, total, sid]

	var retired := bool(state.get("event_player_retired", state.get("player_retired", false)))
	if retired:
		badge_label.text = "SITUACIÓN DEL PILOTO"
		badge_value.text = "REENGANCHE (+300s)"
		badge_value.add_theme_color_override("font_color", _Tokens.get_color("status_danger"))
	elif is_single_stage:
		badge_label.text = "MODO DE PRUEBA"
		badge_value.text = "SINGLE STAGE"
		badge_value.add_theme_color_override("font_color", _Tokens.get_color("status_info"))
	elif mode_name == "championship":
		badge_label.text = "ESTADO DE PRUEBA"
		badge_value.text = "CAMPEONATO · COMPLETADO"
		badge_value.add_theme_color_override("font_color", _Tokens.get_color("accent_rally"))
	else:
		badge_label.text = "ESTADO DE PRUEBA"
		badge_value.text = "OFICIAL · COMPLETADO"
		badge_value.add_theme_color_override("font_color", _Tokens.get_color("status_info"))

	if is_single_stage:
		retry_button.text = "REINTENTAR TRAMO"
		_Theme.apply_tone_button(retry_button, "chrome", 15, 18, 8)
	next_button.disabled = _next_disabled(state)
	next_button.text = _next_label(state)
	_Theme.apply_tone_button(next_button, "gold", 16, 24, 8)
	_style_muted_button(restart_button)
	restart_button.text = "NUEVO RALLY"
	var shortcut_parts: Array[String] = []
	if workshop_available:
		shortcut_parts.append("[ ENTER / A ] TALLER")
	if allow_next:
		shortcut_parts.append("[ CONTINUAR ]")
	if retry_button.visible:
		shortcut_parts.append("[ R ] REINTENTAR")
	shortcuts_label.text = "  ·  ".join(shortcut_parts) if not shortcut_parts.is_empty() else "[ A / ENTER ] CONFIRMAR"
	notice.text = _event_notice(state)

	hero_header_label.text = "RENDIMIENTO DEL PILOTO"
	_stage_results_view.populate_stage_cards(hero_content_vbox, state, clock)

	table_title.text = "CLASIFICACIÓN GENERAL TRAS ESPECIAL %d" % num
	table.clear()
	table.columns = 6
	var headers := ["Pos.", "Piloto", "Coche - equipo", "Tiempo stage", "Tiempo total", "Estado"]
	for i in headers.size():
		table.set_column_title(i, headers[i])
		table.set_column_expand(i, true)
		table.set_column_clip_content(i, true)
		table.set_column_custom_minimum_width(i, [45, 130, 160, 95, 95, 120][i])
		table.set_column_expand_ratio(i, [1, 3, 4, 2, 2, 3][i])

	var root := table.create_item()
	var row_idx := 0
	var font_data := _Tokens.get_font("data_bold_tight")
	var c_text := _Tokens.get_color("text_primary")
	var c_dim := _Tokens.get_color("text_muted")
	for row: Dictionary in state.rows:
		var item := table.create_item(root)
		var is_player := bool(row.get("player", false))
		var rank_val := int(row.get("position", 0))
		var rank_str := "%d" % rank_val if rank_val > 0 else "—"
		var car_team := str(row.get("car", "")) + " - " + str(row.get("team", ""))
		var pen := float(row.get("penalty_ms", 0)) / 1000.0
		var status_str := str(row.get("status", ""))
		if pen > 0.0:
			status_str += " (+%.0f s)" % pen

		var columns := [
			rank_str, str(row.get("name", "")), car_team,
			clock(row.get("stage_ms")), clock(row.get("total_ms")), status_str
		]
		var base_bg := Color(0.06, 0.09, 0.12, 0.7) if (row_idx % 2 == 0) else Color(0.045, 0.065, 0.085, 0.7)
		for i in columns.size():
			item.set_text(i, columns[i])
			item.set_tooltip_text(i, columns[i])
			if i == 0 or i == 3 or i == 4:
				item.set_custom_font(i, font_data)
			if is_player:
				item.set_custom_color(i, Color("#ffd700"))
				item.set_custom_bg_color(i, Color("#3b3324"))
			else:
				item.set_custom_bg_color(i, base_bg)
				if i == 0:
					item.set_custom_color(0, _rank_color(rank_val))
				elif i == 2:
					item.set_custom_color(2, c_dim)
				else:
					item.set_custom_color(i, c_text)
		row_idx += 1


func _present_final(state: Dictionary) -> void:
	var rows: Array = state.get("event_final_rows", [])
	var points: Dictionary = state.get("event_points", {})
	var mode_name: String = str(state.get("session_mode", "rally"))
	title.text = "RESULTADO FINAL · CAMPEONATO DE RUSIA" if mode_name == "championship" else "RESULTADO FINAL · RALLY DE RUSIA"
	header_subtitle.text = "EVENTO DE 10 ESPECIALES FINALIZADO · PUNTUACIÓN SEGÚN BAREMO OFICIAL WRC"

	var winner_id := str(points.get("winner", ""))
	var winner_name := ""
	for row: Dictionary in rows:
		if str(row.id) == winner_id:
			winner_name = str(row.name)

	badge_label.text = "GANADOR DEL RALLY"
	badge_value.text = winner_name if not winner_name.is_empty() else "SIN GANADOR"
	badge_value.add_theme_color_override("font_color", _Tokens.get_color("accent_rally"))

	notice.text = "Ganador: %s · Diez especiales completadas · Puntos: general + domingo + Power Stage." % winner_name if not winner_name.is_empty() else "Rally finalizado sin participantes clasificados."

	restart_button.text = "FINALIZAR / NUEVO RALLY ▶"
	_Theme.apply_tone_button(restart_button, "gold", 16, 24, 8)
	shortcuts_label.text = "[ ENTER / ESC ] FINALIZAR EVENTO"
	table_title.text = "CLASIFICACIÓN FINAL Y PUNTOS DE CAMPEONATO"

	hero_header_label.text = "PODIO FINAL DEL EVENTO"
	_final_podium_view.populate_podium_cards(hero_content_vbox, rows, points, clock)

	table.clear()
	table.columns = 7
	var headers := ["Pos.", "Piloto", "Tiempo acumulado", "General", "Domingo", "Power Stage", "Puntos"]
	for i in headers.size():
		table.set_column_title(i, headers[i])
		table.set_column_expand(i, true)
		table.set_column_clip_content(i, true)
		table.set_column_custom_minimum_width(i, [45, 130, 110, 65, 65, 85, 65][i])
		table.set_column_expand_ratio(i, [1, 3, 3, 1, 1, 1, 1][i])

	var root := table.create_item()
	var row_idx := 0
	var font_data := _Tokens.get_font("data_bold_tight")
	var c_text := _Tokens.get_color("text_primary")
	for row: Dictionary in rows:
		var id := str(row.id)
		var is_player := (id == "player")
		var rank_val := int(row.get("position", 0))
		var columns := [str(row.position), str(row.name), clock(row.grand_total_ms)]
		for category in ["general", "sunday", "power", "total"]:
			columns.append(str((points.get(category, {}) as Dictionary).get(id, 0)))

		var item := table.create_item(root)
		var base_bg := Color(0.06, 0.09, 0.12, 0.7) if (row_idx % 2 == 0) else Color(0.045, 0.065, 0.085, 0.7)
		for i in columns.size():
			item.set_text(i, columns[i])
			item.set_tooltip_text(i, columns[i])
			if i == 0 or i >= 2:
				item.set_custom_font(i, font_data)
			if is_player:
				item.set_custom_color(i, Color("#ffd700"))
				item.set_custom_bg_color(i, Color("#3b3324"))
			else:
				item.set_custom_bg_color(i, base_bg)
				item.set_custom_color(i, _rank_color(rank_val) if i == 0 else c_text)
		row_idx += 1


func _rank_color(rank_val: int) -> Color:
	if rank_val == 1:
		return Color("#ffd700")
	if rank_val == 2:
		return _Tokens.get_color("podium_silver")
	if rank_val == 3:
		return _Tokens.get_color("podium_bronze")
	return _Tokens.get_color("text_muted")


func _draw() -> void:
	if not show_live_corner_block or state_cache.is_empty() or results.visible:
		return
	var factor := minf(size.x / 1920.0, size.y / 1080.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * factor)
	draw_style_box(_Tokens.get_flat_stylebox(Color(_Tokens.get_color("bg_header"), 0.90), Color(_Tokens.get_color("border_subtle"), 0.40), 1, 10), BLOCK_RECT)
	var body := Rect2(BLOCK_RECT.position.x + 8, BLOCK_RECT.position.y + 8, BLOCK_RECT.size.x - 16, BLOCK_RECT.size.y - 16)
	draw_rect(body, _Tokens.get_color("bg_well"))
	var c_shadow := Color(0.0, 0.0, 0.0, 0.25)
	var c_hi := _Tokens.get_color("border_hover")
	draw_rect(Rect2(body.position.x, body.position.y, body.size.x, 1), c_shadow)
	draw_rect(Rect2(body.position.x, body.position.y, 1, body.size.y), c_shadow)
	draw_rect(Rect2(body.position.x, body.end.y - 1, body.size.x, 1), c_hi)
	draw_rect(Rect2(body.end.x - 1, body.position.y, 1, body.size.y), c_hi)

	var sector := int(state_cache.get("sector", 0))
	var sector_count := int(state_cache.get("sector_count", 0))
	var heading := "GENERAL" if sector <= 0 else "GENERAL · PARCIAL %d/%d" % [sector, sector_count]
	_text(Rect2(body.position.x + 4, body.position.y + 2, 210, 14), heading, 9, _Tokens.get_color("status_info"), true)
	draw_rect(Rect2(body.position.x + 3, body.position.y + 18, body.size.x - 6, 1), c_shadow)

	var c_sel := _Tokens.get_color("bg_elevated")
	var c_gold := _Tokens.get_color("accent_rally")
	var c_text := _Tokens.get_color("text_primary")
	var c_dim := _Tokens.get_color("text_muted")
	var visible_rows := _window_rows()
	var row_h := 37.0
	for slot in visible_rows.size():
		var entry: Dictionary = visible_rows[slot]
		var row: Dictionary = entry.row
		var row_rect := Rect2(body.position.x + 3, body.position.y + 21 + float(slot) * (row_h + 1.0), body.size.x - 6, row_h)
		var is_player := bool(row.player)
		if is_player:
			draw_rect(row_rect, c_sel)
			draw_rect(Rect2(row_rect.position.x, row_rect.position.y, 3, row_rect.size.y), c_gold)
			draw_rect(Rect2(row_rect.position.x, row_rect.position.y, row_rect.size.x, 1), c_gold)
			draw_rect(Rect2(row_rect.position.x, row_rect.end.y - 1, row_rect.size.x, 1), c_gold)
			draw_rect(Rect2(row_rect.end.x - 1, row_rect.position.y, 1, row_rect.size.y), c_gold)
		var rank := "%d" % int(row.get("position", 0)) if int(row.get("position", 0)) > 0 else "—"
		_num(Rect2(row_rect.position.x + 8, row_rect.position.y, 22, row_h), rank, 14, c_text if is_player else c_dim)
		_text(Rect2(row_rect.position.x + 32, row_rect.position.y, 130, row_h), str(row.get("name", "")), 11, c_text if is_player else c_dim, is_player)
		var partial_index := int(row.get("partial_index", 0))
		var partial := clock(row.get("partial_ms")) if partial_index > 0 else "—"
		_num(Rect2(row_rect.position.x + 158, row_rect.position.y, 78, row_h), partial, 13, c_text if is_player else c_dim, HORIZONTAL_ALIGNMENT_RIGHT, 78)
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


func _num(rect: Rect2, value: String, size_px: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width_override: float = -1.0) -> void:
	if value.is_empty():
		return
	var width: float = rect.size.x if width_override < 0.0 else width_override
	var line_height := HUD_BOLD.get_height(size_px)
	var baseline := rect.position.y + (rect.size.y + line_height) * 0.5 - HUD_BOLD.get_descent(size_px)
	draw_string(HUD_BOLD, Vector2(round(rect.position.x), round(baseline)), value, align, width, size_px, color)


func _text(rect: Rect2, value: String, size_px: int, color: Color, bold: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width_override: float = -1.0) -> void:
	if value.is_empty():
		return
	var font: Font = HUD_BOLD if bold else HUD_FONT
	var width: float = rect.size.x if width_override < 0.0 else width_override
	var line_height := font.get_height(size_px)
	var baseline := rect.position.y + (rect.size.y + line_height) * 0.5 - font.get_descent(size_px)
	draw_string(font, Vector2(round(rect.position.x), round(baseline)), value, align, width, size_px, color)


func _stage_number(state: Dictionary) -> int:
	if state.has("event_cursor"):
		return int(state["event_cursor"]) + 1
	return int(state.get("leg", 1))


func _stage_id(state: Dictionary) -> String:
	if state.has("event_stage_id"):
		return str(state["event_stage_id"])
	return "russia_stage%d" % int(state.get("leg", 1))


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
		return "REPETIR ESPECIAL (PRÁCTICA)"
	if bool(state.get("event_is_last", false)) or _stage_number(state) >= int(state.get("event_total", 10)):
		return "VER RESULTADO FINAL ▶"
	if bool(state.get("event_next_is_service", false)):
		return "CONTINUAR AL SERVICIO ▶"
	return "CONTINUAR A STAGE %d ▶" % (_stage_number(state) + 1)


func _next_disabled(state: Dictionary) -> bool:
	if state.has("event_stage_id"):
		return false
	return bool(state.get("player_retired", false))


func _event_notice(state: Dictionary) -> String:
	if bool(state.get("single_stage_mode", false)):
		var sid := _stage_id(state)
		return "Especial %s completada. Modo Single Stage finalizado. Usa «Reintentar tramo» para reiniciar o «Nuevo Rally» para volver al menú." % sid
	if state.has("event_stage_id"):
		var sid := _stage_id(state)
		var sched: Dictionary = state.get("event_schedule", {})
		var next_info := ""
		if bool(state.get("event_next_is_service", false)):
			next_info = " Área de servicio antes de la próxima especial."
		elif not bool(state.get("event_is_last", false)):
			next_info = " Próxima especial: Stage %d." % (_stage_number(state) + 1)
		else:
			next_info = " Última especial completada: selecciona «Ver resultado final» para la clasificación definitiva."
		var base := "Especial %s completada y cronometrada oficialmente." % sid
		if not sched.is_empty():
			base += " Horario %s %s." % [str(sched.get("day_label", "")), str(sched.get("start", ""))]
		if bool(state.get("event_player_retired", state.get("player_retired", false))):
			base += " Se ha registrado abandono: aplica reenganche (+300 s) para la siguiente especial."
		if not str(state.get("error", "")).is_empty():
			base += "  " + str(state.get("error", ""))
		return base + next_info
	if bool(state.get("player_retired", false)):
		return "El intento de práctica finaliza al abandonar. Usa 'Reintentar especial' para reiniciar con la misma configuración."
	return "Continuar avanza a la siguiente prueba conservando tiempos acumulados; reintentar reinicia la especial de práctica."
