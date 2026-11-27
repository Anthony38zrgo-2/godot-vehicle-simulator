class_name RallyTireTunerPanel
extends CanvasLayer

## Real-time tire parameter editor (F8) paused cleanly like the pause menu.
## Displays Front and Rear axle tables with plain explanations, editable values,
## live physics reload, official JSON persistence, and automatic timestamped backups.

const _CatalogSvc := preload("res://scripts/ui/services/tire_tuner_catalog_service.gd")
const _ChartScript := preload("res://ui/organisms/ui_telemetry_chart.gd")
const OFFICIAL_CATALOG_RES := _CatalogSvc.OFFICIAL_CATALOG_RES
const BACKUP_DIR_RES := _CatalogSvc.BACKUP_DIR_RES
const HISTORY_INDEX_RES := _CatalogSvc.HISTORY_INDEX_RES
const SURFACES := _CatalogSvc.SURFACES
const MAX_HISTORY_ENTRIES := _CatalogSvc.MAX_HISTORY_ENTRIES

var session: Node = null

var _screen: Control
var _overlay_root: Control
var _backdrop: ColorRect
var _modal: PanelContainer
var _sound_player: AudioStreamPlayer
var _header_subtitle: Label
var _search_edit: LineEdit
var _history_panel: PanelContainer
var _history_option: OptionButton
var _history_detail_label: Label
var _load_history_button: Button
var _restore_history_button: Button
var _manual_backup_button: Button
var _status_label: Label
var _apply_button: Button
var _discard_button: Button
var _tab_hint_label: Label

var _specs: Array[Dictionary] = []
var _filter_specs: Array[Dictionary] = []
var _views: Dictionary = {}
var _rows_by_param: Dictionary = {"front": {}, "rear": {}}
var _active_tab: String = "filters"
var _syncing_edits: bool = false
var _loaded_values: Dictionary = {"front": {}, "rear": {}}
var _loaded_compound_id: String = RallyTireCompound.DEFAULT_ID
var _catalog: Dictionary = {}
var _routes: Dictionary = {}
var _wheel_side := 0
var _curve_surface := "Gravel"
var _curve_mode := 0
var _curve_plots: Dictionary = {}
var _curve_timer: Timer
var _history_entries: Array = []
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 102
	_specs = _build_parameter_specs()
	_filter_specs = _build_filter_specs(_specs)
	_build_ui()
	_curve_timer = Timer.new()
	_curve_timer.one_shot = true
	_curve_timer.wait_time = 0.25
	_curve_timer.timeout.connect(_refresh_curves)
	add_child(_curve_timer)
	_set_active_tab("filters")


func is_open() -> bool:
	return _overlay_root != null and _overlay_root.visible


func allowed() -> bool:
	if session == null or session.get("session_ready") != true:
		return false
	if session.get("awaiting_setup") == true or session.get("stage_transition_running") == true:
		return false
	var comp: Variant = session.get("competition")
	if comp != null and comp.get("complete") == true:
		return false
	var garage: Variant = session.get("garage_panel")
	if garage != null and garage is Control and (garage as Control).visible:
		return false
	var pause_inv: Variant = session.get("pause_inventory")
	if pause_inv != null and pause_inv.get("modal") is Control and (pause_inv.get("modal") as Control).visible:
		return false
	return true


func toggle() -> void:
	if is_open():
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	if is_open() or not allowed() or get_tree().paused:
		return
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_sync_pause_audio_and_pacenotes(true)
	_reload_from_disk_into_ui()
	_refresh_history_ui()
	_overlay_root.show()
	_refresh_curves()
	_play_window_sound(true)


func close_panel() -> void:
	if not is_open():
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	_overlay_root.hide()
	_play_window_sound(false)
	get_tree().paused = false
	_sync_pause_audio_and_pacenotes(false)
	Input.mouse_mode = _previous_mouse_mode


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if key_ev.pressed and not key_ev.echo and (key_ev.keycode == KEY_F8 or key_ev.physical_keycode == KEY_F8):
			if is_open() or (allowed() and not get_tree().paused):
				toggle()
				get_viewport().set_input_as_handled()
			return
	if not is_open():
		return
	if (event.is_action_pressed("ui_cancel") or event.is_action_pressed(InputBindings.UI_BACK_TO_MENU)) and not event.is_echo():
		close_panel()
		get_viewport().set_input_as_handled()


func _sync_pause_audio_and_pacenotes(paused_state: bool) -> void:
	var music := get_node_or_null("/root/RallyMusic")
	if music != null:
		var method_name := "on_pause_opened" if paused_state else "on_pause_closed"
		if music.has_method(method_name):
			music.call(method_name)
	if session != null:
		var pacenotes: Variant = session.get("pacenotes")
		if pacenotes != null and pacenotes.has_method("on_pause"):
			pacenotes.on_pause(paused_state)


func _play_window_sound(opening: bool) -> void:
	if _sound_player == null:
		return
	_sound_player.stream = preload("res://sounds/rally_service/WindowOpen.wav") if opening else preload("res://sounds/rally_service/WindowClose.wav")
	_sound_player.play()


# =============================================================================
# UI CONSTRUCTION
# =============================================================================

func _build_ui() -> void:
	_sound_player = AudioStreamPlayer.new()
	_sound_player.volume_db = -5.0
	add_child(_sound_player)

	_screen = Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.theme = RallyUITheme.build_menu_theme()
	add_child(_screen)

	_overlay_root = Control.new()
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_root.visible = false
	_screen.add_child(_overlay_root)

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = RallyUITheme.BG_OVERLAY
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_root.add_child(_backdrop)

	var frame_margin := MarginContainer.new()
	frame_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame_margin.add_theme_constant_override("margin_left", 26)
	frame_margin.add_theme_constant_override("margin_right", 26)
	frame_margin.add_theme_constant_override("margin_top", 20)
	frame_margin.add_theme_constant_override("margin_bottom", 20)
	_overlay_root.add_child(frame_margin)

	_modal = PanelContainer.new()
	_modal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_modal.clip_contents = true
	_modal.add_theme_stylebox_override("panel", RallyUITheme.make_window_panel(RallyUITheme.BG_SHELL, RallyUITheme.BORDER_CARD))
	frame_margin.add_child(_modal)

	var root_margin := MarginContainer.new()
	root_margin.add_theme_constant_override("margin_left", 16)
	root_margin.add_theme_constant_override("margin_right", 16)
	root_margin.add_theme_constant_override("margin_top", 12)
	root_margin.add_theme_constant_override("margin_bottom", 12)
	_modal.add_child(root_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 10)
	root_margin.add_child(root_vbox)

	root_vbox.add_child(_build_header_panel())
	_history_panel = _build_history_panel()
	_history_panel.hide()
	root_vbox.add_child(_history_panel)
	root_vbox.add_child(_build_tab_bar())

	root_vbox.add_child(_create_tab_view("filters", _filter_specs))
	root_vbox.add_child(_create_tab_view("all", _specs))

	root_vbox.add_child(_build_footer_panel())


func _build_tab_bar() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", RallyUITheme.make_flat_panel(RallyUITheme.BG_WELL, RallyUITheme.BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS, 10, 6))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	var btn_filters := Button.new()
	btn_filters.text = "CALIBRACIÓN"
	btn_filters.custom_minimum_size = Vector2(132, 32)
	btn_filters.pressed.connect(func() -> void:
		_set_active_tab("filters")
	)
	hbox.add_child(btn_filters)

	var btn_all := Button.new()
	btn_all.text = "AVANZADO"
	btn_all.custom_minimum_size = Vector2(106, 32)
	btn_all.pressed.connect(func() -> void:
		_set_active_tab("all")
	)
	hbox.add_child(btn_all)

	var surface_picker := OptionButton.new()
	for surface in SURFACES:
		surface_picker.add_item(str(surface["label"]))
	surface_picker.tooltip_text = "Superficie del ensayo de curva pura"
	surface_picker.item_selected.connect(func(index: int) -> void:
		_curve_surface = str(SURFACES[index]["key"])
		_refresh_curves()
	)
	hbox.add_child(surface_picker)

	var mode_picker := OptionButton.new()
	for title in ["Lateral", "Frenada", "Tracción"]:
		mode_picker.add_item(title)
	mode_picker.item_selected.connect(func(index: int) -> void:
		_curve_mode = index
		_refresh_curves()
	)
	hbox.add_child(mode_picker)

	var wheel_picker := OptionButton.new()
	wheel_picker.add_item("Ruedas izquierdas")
	wheel_picker.add_item("Ruedas derechas")
	wheel_picker.tooltip_text = "Ruedas de referencia. Los ajustes de catálogo se guardan por eje."
	wheel_picker.item_selected.connect(func(index: int) -> void:
		if _count_pending_changes() != 0:
			wheel_picker.select(_wheel_side)
			_set_status("Aplica o descarta los cambios antes de cambiar de rueda.", RallyUITheme.STATUS_DANGER)
			return
		_wheel_side = index
		_reload_from_disk_into_ui()
	)
	hbox.add_child(wheel_picker)

	_tab_hint_label = Label.new()
	_tab_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tab_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tab_hint_label.custom_minimum_size = Vector2(10, 0)
	_tab_hint_label.clip_text = true
	_tab_hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_set_label_style(_tab_hint_label, 11, RallyUITheme.TEXT_MUTED, RallyUITheme.FONT_REGULAR)
	hbox.add_child(_tab_hint_label)

	_views["filters"] = {"button": btn_filters, "rows": {"front": [], "rear": []}}
	_views["all"] = {"button": btn_all, "rows": {"front": [], "rear": []}}
	return panel


func _create_tab_view(view_key: String, specs_list: Array[Dictionary]) -> HBoxContainer:
	var tables_hbox := HBoxContainer.new()
	tables_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tables_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tables_hbox.add_theme_constant_override("separation", 12)
	tables_hbox.add_child(_create_axle_table_panel("front", "EJE DELANTERO", specs_list, view_key))
	tables_hbox.add_child(_create_axle_table_panel("rear", "EJE TRASERO", specs_list, view_key))
	(_views[view_key] as Dictionary)["root"] = tables_hbox
	return tables_hbox


func _set_active_tab(tab_key: String) -> void:
	if not _views.has(tab_key):
		return
	_active_tab = tab_key
	for k: String in _views:
		var view: Dictionary = _views[k]
		var is_active: bool = (k == tab_key)
		var root_node: Variant = view.get("root")
		if root_node is Control:
			(root_node as Control).visible = is_active
		var btn: Variant = view.get("button")
		if btn is Button:
			if is_active:
				RallyUITheme.style_selected_button(btn as Button, 12, 16, 6)
			else:
				RallyUITheme.style_chrome_button(btn as Button, 12, 16, 6)
	if _tab_hint_label != null:
		_tab_hint_label.text = "Curvas puras en seco" if tab_key == "filters" else "Coeficientes por eje y superficie"
	_refresh_curves()


static func _set_label_style(lbl: Label, size: int, col: Color, font_res: Font) -> void:
	lbl.add_theme_font_override("font", font_res)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_constant_override("outline_size", 0)


func _build_header_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", RallyUITheme.make_window_panel(RallyUITheme.BG_SURFACE, RallyUITheme.BORDER_CARD))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	var title_vbox := VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(title_vbox)

	var title := Label.new()
	title.text = "AJUSTE DE NEUMÁTICOS EN TIEMPO REAL"
	_set_label_style(title, 18, RallyUITheme.TEXT_WHITE, RallyUITheme.FONT_TITLE)
	title_vbox.add_child(title)

	_header_subtitle = Label.new()
	_header_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_subtitle.custom_minimum_size = Vector2(10, 0)
	_header_subtitle.clip_text = true
	_header_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_set_label_style(_header_subtitle, 11, RallyUITheme.TEXT_MUTED, RallyUITheme.FONT_MEDIUM)
	title_vbox.add_child(_header_subtitle)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Filtrar parámetro..."
	_search_edit.custom_minimum_size = Vector2(210, 32)
	_search_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(_on_search_changed)
	hbox.add_child(_search_edit)

	var history_toggle := Button.new()
	history_toggle.text = "Historial"
	history_toggle.toggle_mode = true
	history_toggle.toggled.connect(func(expanded: bool) -> void:
		_history_panel.visible = expanded
	)
	RallyUITheme.style_chrome_button(history_toggle, 12, 12, 6)
	hbox.add_child(history_toggle)

	var badge := Label.new()
	badge.text = "[F8 / ESC] REANUDAR"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_set_label_style(badge, 12, RallyUITheme.ACCENT_RALLY, RallyUITheme.FONT_BUTTON)
	hbox.add_child(badge)

	return panel


func _build_history_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", RallyUITheme.make_card_panel(RallyUITheme.BG_CARD, RallyUITheme.BORDER_SUBTLE))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(top_hbox)

	var hist_title := Label.new()
	hist_title.text = "HISTORIAL Y BACKUPS:"
	_set_label_style(hist_title, 12, RallyUITheme.ACCENT_RALLY, RallyUITheme.FONT_BUTTON)
	top_hbox.add_child(hist_title)

	_history_option = OptionButton.new()
	_history_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_option.custom_minimum_size = Vector2(180, 32)
	_history_option.fit_to_longest_item = false
	_history_option.clip_text = true
	_history_option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	RallyUITheme.style_option_button(_history_option)
	var hist_popup := _history_option.get_popup()
	if hist_popup != null:
		hist_popup.max_size = Vector2(780, 420)
	_history_option.item_selected.connect(_on_history_selected)
	top_hbox.add_child(_history_option)

	_load_history_button = Button.new()
	_load_history_button.text = "Cargar en tablas"
	_load_history_button.custom_minimum_size = Vector2(138, 32)
	_load_history_button.pressed.connect(_on_load_history_pressed)
	RallyUITheme.style_chrome_button(_load_history_button)
	top_hbox.add_child(_load_history_button)

	_restore_history_button = Button.new()
	_restore_history_button.text = "Restaurar y Aplicar"
	_restore_history_button.custom_minimum_size = Vector2(158, 32)
	_restore_history_button.pressed.connect(_on_restore_history_pressed)
	RallyUITheme.style_caution_button(_restore_history_button)
	top_hbox.add_child(_restore_history_button)

	_manual_backup_button = Button.new()
	_manual_backup_button.text = "Crear Backup"
	_manual_backup_button.custom_minimum_size = Vector2(124, 32)
	_manual_backup_button.pressed.connect(_on_create_manual_backup_pressed)
	RallyUITheme.style_chrome_button(_manual_backup_button)
	top_hbox.add_child(_manual_backup_button)

	_history_detail_label = Label.new()
	_history_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_detail_label.custom_minimum_size = Vector2(10, 0)
	_history_detail_label.clip_text = true
	_history_detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_set_label_style(_history_detail_label, 11, RallyUITheme.TEXT_MUTED, RallyUITheme.FONT_REGULAR)
	vbox.add_child(_history_detail_label)

	return panel


func _create_axle_table_panel(
	axle: String,
	title_text: String,
	specs_list: Array[Dictionary],
	view_key: String,
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(100, 100)
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", RallyUITheme.make_window_panel(RallyUITheme.BG_SURFACE, RallyUITheme.BORDER_CARD))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var table_title := Label.new()
	table_title.text = title_text
	_set_label_style(table_title, 15, RallyUITheme.ACCENT_RALLY, RallyUITheme.FONT_TITLE)
	vbox.add_child(table_title)
	if view_key == "filters":
		var plot := _ChartScript.new()
		plot.custom_minimum_size.y = 113.0
		plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(plot)
		_curve_plots[axle] = plot

	var col_header_panel := PanelContainer.new()
	col_header_panel.add_theme_stylebox_override("panel", RallyUITheme.make_flat_panel(RallyUITheme.BG_ELEVATED, RallyUITheme.BORDER_SUBTLE, 1, 0))
	vbox.add_child(col_header_panel)

	var col_margin := MarginContainer.new()
	col_margin.add_theme_constant_override("margin_left", 8)
	col_margin.add_theme_constant_override("margin_right", 16)
	col_margin.add_theme_constant_override("margin_top", 5)
	col_margin.add_theme_constant_override("margin_bottom", 5)
	col_header_panel.add_child(col_margin)

	var col_hbox := HBoxContainer.new()
	col_hbox.add_theme_constant_override("separation", 8)
	col_margin.add_child(col_hbox)

	var h_param := Label.new()
	h_param.text = "PARÁMETRO"
	h_param.custom_minimum_size = Vector2(215, 0)
	_set_label_style(h_param, 11, RallyUITheme.TEXT_GOLD_SOFT, RallyUITheme.FONT_BUTTON)
	col_hbox.add_child(h_param)

	var h_desc := Label.new()
	h_desc.text = "EFECTO"
	h_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_label_style(h_desc, 11, RallyUITheme.TEXT_GOLD_SOFT, RallyUITheme.FONT_BUTTON)
	col_hbox.add_child(h_desc)

	var h_val := Label.new()
	h_val.text = "VALOR ACTUAL"
	h_val.custom_minimum_size = Vector2(108, 0)
	h_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_set_label_style(h_val, 11, RallyUITheme.TEXT_GOLD_SOFT, RallyUITheme.FONT_BUTTON)
	col_hbox.add_child(h_val)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var rows_vbox := VBoxContainer.new()
	rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(rows_vbox)

	var row_refs: Array = []
	var zebra := 0
	for spec in specs_list:
		if str(spec.get("kind", "")) == "section":
			var sec_panel := PanelContainer.new()
			sec_panel.add_theme_stylebox_override("panel", RallyUITheme.make_flat_panel(RallyUITheme.BG_WELL, RallyUITheme.BORDER_SUBTLE, 1, 0))
			var sec_margin := MarginContainer.new()
			sec_margin.add_theme_constant_override("margin_left", 8)
			sec_margin.add_theme_constant_override("margin_right", 8)
			sec_margin.add_theme_constant_override("margin_top", 4)
			sec_margin.add_theme_constant_override("margin_bottom", 4)
			sec_panel.add_child(sec_margin)
			var sec_label := Label.new()
			sec_label.text = str(spec.get("title", ""))
			_set_label_style(sec_label, 11, RallyUITheme.TEXT_GOLD_SOFT, RallyUITheme.FONT_BUTTON)
			sec_margin.add_child(sec_label)
			rows_vbox.add_child(sec_panel)
			row_refs.append({"kind": "section", "node": sec_panel})
			zebra = 0
			continue

		var row_bg := RallyUITheme.BG_CARD if (zebra % 2 == 0) else Color(0.085, 0.095, 0.11, 1.0)
		zebra += 1
		var row_panel := PanelContainer.new()
		row_panel.add_theme_stylebox_override("panel", RallyUITheme.make_flat_panel(row_bg, Color(0, 0, 0, 0), 0, 0))
		rows_vbox.add_child(row_panel)

		var row_margin := MarginContainer.new()
		row_margin.add_theme_constant_override("margin_left", 8)
		row_margin.add_theme_constant_override("margin_right", 8)
		var row_padding := 1 if view_key == "filters" else 4
		row_margin.add_theme_constant_override("margin_top", row_padding)
		row_margin.add_theme_constant_override("margin_bottom", row_padding)
		row_panel.add_child(row_margin)

		var row_hbox := HBoxContainer.new()
		row_hbox.add_theme_constant_override("separation", 8)
		row_margin.add_child(row_hbox)

		var param_label := Label.new()
		param_label.text = str(spec.get("key", ""))
		param_label.custom_minimum_size = Vector2(215, 0)
		param_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		param_label.clip_text = true
		param_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		param_label.tooltip_text = str(spec.get("key", ""))
		_set_label_style(param_label, 12, RallyUITheme.TEXT_WHITE, RallyUITheme.FONT_DATA)
		row_hbox.add_child(param_label)

		var desc_label := Label.new()
		desc_label.text = str(spec.get("description", ""))
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		desc_label.custom_minimum_size = Vector2(40, 0)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_set_label_style(desc_label, 11, RallyUITheme.TEXT_MUTED, RallyUITheme.FONT_REGULAR)
		row_hbox.add_child(desc_label)

		var edit := LineEdit.new()
		edit.custom_minimum_size = Vector2(108, 26 if view_key == "filters" else 28)
		edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		edit.select_all_on_focus = true
		edit.add_theme_font_override("font", RallyUITheme.FONT_DATA)
		edit.add_theme_font_size_override("font_size", 12)
		var param_id := str(spec.get("id", ""))
		edit.text_changed.connect(func(new_text: String) -> void:
			_on_row_value_edited(axle, param_id, new_text, edit)
		)
		row_hbox.add_child(edit)

		var row_ref := {
			"kind": "param",
			"id": param_id,
			"spec": spec,
			"node": row_panel,
			"param_label": param_label,
			"description_label": desc_label,
			"edit": edit,
		}
		row_refs.append(row_ref)
		var param_map: Dictionary = _rows_by_param[axle]
		if not param_map.has(param_id):
			param_map[param_id] = []
		(param_map[param_id] as Array).append(row_ref)

	((_views[view_key] as Dictionary)["rows"] as Dictionary)[axle] = row_refs
	return panel


func _build_footer_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", RallyUITheme.make_window_panel(RallyUITheme.BG_SURFACE, RallyUITheme.BORDER_CARD))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_label.custom_minimum_size = Vector2(10, 0)
	_status_label.clip_text = true
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_set_label_style(_status_label, 12, RallyUITheme.TEXT_PRIMARY, RallyUITheme.FONT_REGULAR)
	hbox.add_child(_status_label)

	_discard_button = Button.new()
	_discard_button.text = "Descartar cambios"
	_discard_button.custom_minimum_size = Vector2(142, 36)
	_discard_button.pressed.connect(_on_discard_pressed)
	RallyUITheme.style_chrome_button(_discard_button)
	hbox.add_child(_discard_button)

	_apply_button = Button.new()
	_apply_button.text = "APLICAR Y GUARDAR"
	_apply_button.custom_minimum_size = Vector2(190, 36)
	_apply_button.pressed.connect(_on_apply_pressed)
	RallyUITheme.style_gold_button(_apply_button)
	hbox.add_child(_apply_button)

	var close_btn := Button.new()
	close_btn.text = "Cerrar [F8]"
	close_btn.custom_minimum_size = Vector2(118, 36)
	close_btn.pressed.connect(close_panel)
	RallyUITheme.style_chrome_button(close_btn)
	hbox.add_child(close_btn)

	return panel


# =============================================================================
# DATA EXTRACTION, VALIDATION & PERSISTENCE
# =============================================================================

func _active_simulation() -> FordRallyVehicleSimulation:
	if session != null:
		var vehicle: Variant = session.get("vehicle")
		if vehicle != null:
			return vehicle.get("simulation") as FordRallyVehicleSimulation
	return null


func _wheel_index(axle: String) -> int:
	return (0 if axle == "front" else 2) + _wheel_side


func _resolve_read_path(res_path: String) -> String:
	return _CatalogSvc.resolve_read_path(res_path)


func _resolve_write_path(res_path: String) -> String:
	return _CatalogSvc.resolve_write_path(res_path)


func _read_json_dict(res_path: String) -> Dictionary:
	return _CatalogSvc.read_json_dict(res_path)


func _write_json_dict(res_path: String, doc: Dictionary) -> bool:
	return _CatalogSvc.write_json_dict(res_path, doc)


func _reload_from_disk_into_ui() -> void:
	_catalog = _read_json_dict(OFFICIAL_CATALOG_RES)
	var sim := _active_simulation()
	_loaded_compound_id = sim.active_compound_id if sim != null else RallyTireCompound.DEFAULT_ID
	_routes.clear()
	_loaded_values = {"front": {}, "rear": {}}
	if sim != null and not _catalog.is_empty() and sim.tire_model.wheel_compounds.size() == 4:
		var live_catalog := sim.tire_model.compound_catalog
		if not live_catalog.is_empty() and live_catalog != _catalog:
			_catalog = live_catalog
		_loaded_values = _extract_axle_values(sim.tire_model, _catalog, sim.tire_sources, true)
	_populate_tables(_loaded_values, _loaded_values)
	_update_header_summary()
	_refresh_curves()
	_set_status("Solo se guardan los campos editados. Cada fila indica su origen y destino.", RallyUITheme.TEXT_MUTED)


func _extract_axle_values(model: TireModel, catalog: Dictionary, sources: Dictionary, record_routes: bool = false) -> Dictionary:
	var out := {"front": {}, "rear": {}}
	for axle: String in out:
		var wheel := _wheel_index(axle)
		var compound: Dictionary = model.wheel_compounds[wheel] if wheel < model.wheel_compounds.size() else {}
		var compound_id := str(compound.get("id", ""))
		var compound_force: Dictionary = compound.get("force_model", {}).get(axle, {})
		var radial := RallyTireCompound.merge_dict(model.radial_tires.get("radial_model", {}), model.radial_tires.get(axle, {}).get("radial_model", {}))
		var raw_tires: Dictionary = sources.get("tires", {}).get("tires", {})
		var raw_axle: Dictionary = raw_tires.get(axle, {})
		var raw_filter: Dictionary = sources.get("tire_filters", {}).get("tire_filters", {})
		var raw_filter_axle: Dictionary = raw_filter.get(axle, {})
		var base_filter := ["default_tire_profile", "tire_filters", axle]
		var base_tire := ["default_tire_profile", "tires", axle]
		var defaults: Dictionary = catalog.get("default_tire_profile", {})
		var catalog_tires: Dictionary = defaults.get("tires", {})
		var catalog_axle: Dictionary = catalog_tires.get(axle, {})
		var catalog_filters: Dictionary = defaults.get("tire_filters", {})
		var catalog_filter: Dictionary = catalog_filters.get(axle, {})
		var routes := {}
		for spec in _specs:
			if spec["kind"] != "param":
				continue
			var field: String = spec["field"]
			var id: String = spec["id"]
			var value := float(spec["default"])
			var path := base_filter + [field]
			var origin := "Valor por defecto del motor"
			var blocked := false
			var factor := 1.0
			match spec["source"]:
				"force_model":
					var axle_catalog_force: Dictionary = catalog_tires.get("force_model", {}).get(axle, {})
					origin = "Perfil base · force_model" if axle_catalog_force.has(field) else origin
					if raw_tires.get("force_model", {}).get(axle, {}).has(field):
						origin = "Vehículo · tires"
					if catalog_filter.has(field):
						origin = "Perfil base · tire_filters"
					if raw_filter_axle.has(field):
						origin = "Vehículo · tire_filters"
						blocked = true
					if compound_force.has(field):
						origin = "Compuesto · " + compound_id
						path = ["compounds", compound_id, "force_model", axle, field]
						blocked = false
					value = float(model.axle_profiles[wheel].get(field, value))
				"axle_scalar":
					origin = "Perfil base · tires" if catalog_axle.has(field) or catalog_tires.has(field) else origin
					if raw_axle.has(field) or (not catalog_axle.has(field) and raw_tires.has(field)):
						origin = "Vehículo · tires"
					if field == "surface_transition_tau_s" and not raw_axle.has(field) and not catalog_axle.has(field):
						if raw_filter.has(field):
							origin = "Vehículo · tire_filters"
						elif catalog_filters.has(field):
							origin = "Perfil base · tire_filters"
					if catalog_filter.has(field):
						origin = "Perfil base · tire_filters"
					if raw_filter_axle.has(field):
						origin = "Vehículo · tire_filters"
						blocked = true
					match field:
						"load_sensitivity_per_newton":
							factor = model.axle_load_mult[wheel] * 1.0e6
							value = model.axle_load_sensitivity[wheel] * factor
						"relaxation_length_scale":
							factor = model.base_contact_patch_m[wheel]
							value = model.base_relaxation_length_m[wheel]
						"surface_transition_tau_s":
							value = model.axle_surface_tau_s[wheel]
						"contact_patch_load_gain":
							value = model.axle_contact_load_gain[wheel]
						"contact_patch_deflection_gain":
							value = model.axle_contact_deflection_gain[wheel]
				"pressure_mechanics":
					path = base_filter + ["pressure_mechanics", field]
					origin = "Perfil base · tires" if catalog_axle.get("pressure_mechanics", {}).has(field) or catalog_tires.get("pressure_mechanics", {}).has(field) else origin
					if raw_axle.get("pressure_mechanics", {}).has(field) or (
						not catalog_axle.get("pressure_mechanics", {}).has(field) and raw_tires.get("pressure_mechanics", {}).has(field)
					):
						origin = "Vehículo · tires"
					if catalog_filter.get("pressure_mechanics", {}).has(field):
						origin = "Perfil base · tire_filters"
					if raw_filter_axle.get("pressure_mechanics", {}).has(field):
						origin = "Vehículo · tire_filters"
						blocked = true
					value = model.axle_pressure_relaxation[wheel] if field == "response_sensitivity" else model.axle_pressure_rolling[wheel]
				"radial_model":
					path = base_tire + ["radial_model", field]
					origin = "Perfil base · tires" if catalog_axle.get("radial_model", {}).has(field) or catalog_tires.get("radial_model", {}).has(field) else origin
					blocked = raw_axle.get("radial_model", {}).has(field)
					if blocked or (not catalog_axle.get("radial_model", {}).has(field) and raw_tires.get("radial_model", {}).has(field)):
						origin = "Vehículo · tires"
					value = float(radial.get(field, value))
					match field:
						"damping_ratio":
							value = maxf(value, TireRadialModel.MIN_DAMPING_RATIO)
						"damping_contact_ramp_m":
							value = maxf(float(radial.get(field, 0.015)), TireRadialModel.MIN_DAMPING_RAMP_M)
						"rim_stop_start_sidewall_fraction":
							value = clampf(value, 0.4, 0.95)
				"surface":
					var surface: String = spec["surface"]
					path = base_filter + ["surfaces", surface, field]
					if catalog_tires.get("surfaces", {}).get(surface, {}).has(field) or catalog_axle.get("surfaces", {}).get(surface, {}).has(field):
						origin = "Perfil base · tires"
					if raw_axle.get("surfaces", {}).get(surface, {}).has(field) or (
						not catalog_axle.get("surfaces", {}).get(surface, {}).has(field)
						and raw_tires.get("surfaces", {}).get(surface, {}).has(field)
					):
						origin = "Vehículo · tires"
					if catalog_filter.get("surfaces", {}).get(surface, {}).has(field):
						origin = "Perfil base · tire_filters"
					if raw_filter_axle.get("surfaces", {}).get(surface, {}).has(field):
						origin = "Vehículo · tire_filters"
						blocked = true
					value = float(model.axle_surfaces[wheel].get(surface, {}).get(field, value))
			out[axle][id] = value
			routes[id] = {"path": path, "origin": origin, "blocked": blocked, "factor": factor}
		if record_routes:
			_routes[axle] = routes
	return out


func _canonical_rows_for_axle(axle: String) -> Array:
	var all_view: Dictionary = _views.get("all", {})
	var rows_map: Dictionary = all_view.get("rows", {})
	var rows: Variant = rows_map.get(axle, [])
	return rows if rows is Array else []


func _populate_tables(values_by_axle: Dictionary, baseline_by_axle: Dictionary) -> void:
	_syncing_edits = true
	for view_key: String in _views:
		var view: Dictionary = _views[view_key]
		var view_rows: Dictionary = view.get("rows", {})
		for axle: String in ["front", "rear"]:
			var vals: Dictionary = values_by_axle.get(axle, {})
			var base_vals: Dictionary = baseline_by_axle.get(axle, {})
			for row in view_rows.get(axle, []):
				if str(row.get("kind", "")) != "param":
					continue
				var id := str(row.get("id", ""))
				var edit: LineEdit = row["edit"]
				var route: Dictionary = _routes.get(axle, {}).get(id, {})
				var v := float(vals.get(id, 0.0))
				var base_v := float(base_vals.get(id, v))
				edit.editable = not route.is_empty() and not bool(route["blocked"])
				if not edit.editable:
					v = base_v
				edit.text = _format_float(v)
				var spec: Dictionary = row["spec"]
				var factor := float(route.get("factor", 1.0))
				var destination := "Edición en el perfil del vehículo" if route.get("blocked", false) else ".".join(route.get("path", []))
				edit.tooltip_text = "Origen: %s\nDestino: %s\nRango: %s a %s" % [
					str(route.get("origin", "Sin perfil activo")), destination,
					_format_float(float(spec["min"]) * factor),
					_format_float(float(spec["max"]) * factor),
				]
				var desc: Label = row["description_label"]
				desc.text = str(spec["description"])
				if view_key == "all":
					desc.text += "\n" + str(route.get("origin", ""))
				desc.tooltip_text = edit.tooltip_text
				(row["param_label"] as Label).tooltip_text = edit.tooltip_text
				_style_row_state(row, v, base_v, true)
	_syncing_edits = false


func _on_row_value_edited(axle: String, param_id: String, new_text: String, source_edit: LineEdit) -> void:
	if _syncing_edits:
		return
	_syncing_edits = true
	var sibling_rows: Array = _rows_by_param.get(axle, {}).get(param_id, [])
	for r in sibling_rows:
		var ed: LineEdit = r["edit"]
		if ed != source_edit:
			ed.text = new_text
	if not sibling_rows.is_empty():
		var base_vals: Dictionary = _loaded_values.get(axle, {})
		var base_v := float(base_vals.get(param_id, 0.0))
		var parsed := _parse_row_float(sibling_rows[0], axle)
		var current_v := float(parsed.get("value", base_v))
		var valid := bool(parsed.get("ok", false))
		for r in sibling_rows:
			_style_row_state(r, current_v, base_v, valid)
	_syncing_edits = false
	_update_header_summary()
	if is_open() and _active_tab == "filters":
		_curve_timer.start()


func _style_row_state(row: Dictionary, current_v: float, base_v: float, valid: bool) -> void:
	var lbl: Label = row["param_label"]
	var edit: LineEdit = row["edit"]
	if not valid:
		lbl.add_theme_color_override("font_color", RallyUITheme.STATUS_DANGER)
		edit.add_theme_color_override("font_color", RallyUITheme.STATUS_DANGER)
	elif absf(current_v - base_v) > 1e-9:
		lbl.add_theme_color_override("font_color", RallyUITheme.ACCENT_RALLY)
		edit.add_theme_color_override("font_color", RallyUITheme.ACCENT_RALLY)
	else:
		lbl.add_theme_color_override("font_color", RallyUITheme.TEXT_WHITE)
		edit.add_theme_color_override("font_color", RallyUITheme.TEXT_WHITE)


func _parse_row_float(row: Dictionary, axle: String) -> Dictionary:
	var edit: LineEdit = row["edit"]
	var spec: Dictionary = row["spec"]
	var raw := edit.text.strip_edges().replace(",", ".")
	if raw.is_empty() or not raw.is_valid_float():
		return {"ok": false, "error": "Valor no numérico en '%s'" % str(spec.get("key", ""))}
	var v := raw.to_float()
	if not is_finite(v):
		return {"ok": false, "error": "Valor infinito o inválido en '%s'" % str(spec.get("key", ""))}
	var route: Dictionary = _routes.get(axle, {}).get(row["id"], {})
	var factor := float(route.get("factor", 1.0))
	var min_v := float(spec["min"]) * factor
	var max_v := float(spec["max"]) * factor
	var strict_pos := bool(spec.get("strict_positive", false))
	if strict_pos and v <= 0.0:
		return {"ok": false, "error": "'%s' debe ser mayor que 0." % str(spec.get("key", ""))}
	if v < min_v - 1e-10 or v > max_v + 1e-10:
		return {
			"ok": false,
			"error": "'%s' fuera de rango [%s .. %s]." % [
				str(spec.get("key", "")),
				_format_float(min_v),
				_format_float(max_v),
			],
		}
	return {"ok": true, "value": v}


func _collect_validated_values() -> Dictionary:
	var values := {"front": {}, "rear": {}}
	for axle: String in values:
		for row in _canonical_rows_for_axle(axle):
			if row["kind"] != "param":
				continue
			var edit: LineEdit = row["edit"]
			var id: String = row["id"]
			var original := float(_loaded_values.get(axle, {}).get(id, 0.0))
			if not edit.editable or edit.text.strip_edges().replace(",", ".") == _format_float(original):
				continue
			var result := _parse_row_float(row, axle)
			if not result["ok"]:
				return {"ok": false, "error": "[%s] %s" % [axle.to_upper(), result["error"]]}
			if absf(float(result["value"]) - original) > 1.0e-10:
				values[axle][id] = result["value"]
	return {"ok": true, "values": values}


func _count_pending_changes() -> int:
	var validation := _collect_validated_values()
	if not validation["ok"]:
		return -1
	return validation["values"]["front"].size() + validation["values"]["rear"].size()


func _update_header_summary() -> void:
	var pending := _count_pending_changes()
	var pending_text := "%d cambios sin aplicar" % pending
	if pending == 0:
		pending_text = "Sin cambios pendientes"
	elif pending == 1:
		pending_text = "1 cambio sin aplicar"
	if pending < 0:
		pending_text = "Revisa los valores marcados"
	var sim := _active_simulation()
	if sim == null or _routes.is_empty():
		_header_subtitle.text = "Sin perfil de neumáticos activo"
		_apply_button.disabled = true
		return
	var front := _wheel_index("front")
	var rear := _wheel_index("rear")
	var compounds := sim.tire_model.wheel_compounds
	var label_overrides: Dictionary = session.get_session_compound_label_overrides() if (session != null and session.has_method("get_session_compound_label_overrides")) else {}
	var front_cid := str(compounds[front].get("id", ""))
	var rear_cid := str(compounds[rear].get("id", ""))
	var front_compound := RallyTireCompound.compound_label(front_cid, false, label_overrides) if not front_cid.is_empty() else str(compounds[front].get("label", ""))
	var rear_compound := RallyTireCompound.compound_label(rear_cid, false, label_overrides) if not rear_cid.is_empty() else str(compounds[rear].get("label", ""))
	_header_subtitle.text = "%s  ·  Del. %s  ·  Tras. %s  ·  %s" % [
		str(sim.profile.get("vehicle_identifier", "")), front_compound, rear_compound, pending_text,
	]
	_header_subtitle.tooltip_text = _header_subtitle.text
	_apply_button.disabled = pending <= 0


func _build_diff_summary(old_values: Dictionary, new_values: Dictionary) -> String:
	return _CatalogSvc.build_diff_summary(_specs, old_values, new_values)


func _apply_values_to_catalog(catalog: Dictionary, changes: Dictionary) -> Dictionary:
	return _CatalogSvc.apply_values_to_catalog(catalog, changes, _routes)


func _reload_vehicle_tire_runtime() -> bool:
	if session == null:
		return false
	var vehicle: Variant = session.get("vehicle")
	if vehicle == null:
		return false
	var sim: Variant = vehicle.get("simulation")
	if sim != null and sim.has_method("reload_tire_catalog_runtime"):
		return bool(sim.reload_tire_catalog_runtime())
	return false


# =============================================================================
# HISTORY & BACKUP MANAGEMENT (delegated to TireTunerCatalogService)
# =============================================================================

func _load_history_index() -> Array:
	return _CatalogSvc.load_history_index()


func _save_history_index(entries: Array) -> bool:
	return _CatalogSvc.save_history_index(entries)


func _ensure_initial_baseline_backup(current_catalog: Dictionary) -> void:
	_CatalogSvc.ensure_initial_baseline_backup(current_catalog, _loaded_compound_id)


func _create_backup_snapshot(catalog: Dictionary, label_text: String, changes_summary: String, compound_id: String) -> Dictionary:
	return _CatalogSvc.create_backup_snapshot(catalog, label_text, changes_summary, compound_id)


func _refresh_history_ui() -> void:
	if _history_option == null:
		return
	_history_entries = _load_history_index()
	_history_option.clear()
	if _history_entries.is_empty():
		_history_option.add_item("Sin backups guardados aún (se creará uno automático al aplicar)")
		_history_option.set_item_disabled(0, true)
		_load_history_button.disabled = true
		_restore_history_button.disabled = true
		_history_detail_label.text = "Carpeta de backups: %s" % _resolve_write_path(BACKUP_DIR_RES)
		return

	_load_history_button.disabled = false
	_restore_history_button.disabled = false
	for i in _history_entries.size():
		var e: Dictionary = _history_entries[i] if _history_entries[i] is Dictionary else {}
		var summary := str(e.get("changes_summary", ""))
		if summary.length() > 54:
			summary = summary.substr(0, 51) + "..."
		var text := "%s · %s · [%s] · %s" % [
			str(e.get("timestamp", "")),
			str(e.get("label", "Snapshot")),
			str(e.get("compound_id", "")),
			summary,
		]
		_history_option.add_item(text)
	_history_option.select(0)
	_on_history_selected(0)


func _selected_history_entry() -> Dictionary:
	if _history_option == null or _history_entries.is_empty():
		return {}
	var idx := _history_option.selected
	if idx < 0 or idx >= _history_entries.size():
		return {}
	var e: Variant = _history_entries[idx]
	return (e as Dictionary) if e is Dictionary else {}


# =============================================================================
# UI SIGNAL HANDLERS
# =============================================================================

func _on_search_changed(filter_text: String) -> void:
	var needle := filter_text.strip_edges().to_lower()
	for view_key: String in _views:
		var view_rows: Dictionary = (_views[view_key] as Dictionary).get("rows", {})
		for axle: String in ["front", "rear"]:
			var rows: Array = view_rows.get(axle, [])
			var last_section: Dictionary = {}
			var section_has_visible := false
			for row in rows:
				if str(row.get("kind", "")) == "section":
					if not last_section.is_empty():
						(last_section["node"] as Control).visible = section_has_visible or needle.is_empty()
					last_section = row
					section_has_visible = false
					continue
				var spec: Dictionary = row["spec"]
				var haystack := "%s %s" % [str(spec.get("key", "")).to_lower(), str(spec.get("description", "")).to_lower()]
				var visible_row := needle.is_empty() or haystack.contains(needle)
				(row["node"] as Control).visible = visible_row
				if visible_row:
					section_has_visible = true
			if not last_section.is_empty():
				(last_section["node"] as Control).visible = section_has_visible or needle.is_empty()


func _on_history_selected(_index: int) -> void:
	var entry := _selected_history_entry()
	if entry.is_empty():
		_history_detail_label.text = ""
		return
	var detail := "Backup: %s  |  Compuesto: %s  |  %s" % [
		str(entry.get("backup_file", "")),
		str(entry.get("compound_id", "")),
		str(entry.get("changes_summary", "")),
	]
	_history_detail_label.text = detail
	_history_detail_label.tooltip_text = detail


func _on_load_history_pressed() -> void:
	var entry := _selected_history_entry()
	if entry.is_empty():
		return
	var backup_res := BACKUP_DIR_RES.path_join(str(entry.get("backup_file", "")))
	var backup_doc := _read_json_dict(backup_res)
	if backup_doc.is_empty():
		_set_status("Error: no se pudo leer el backup %s." % str(entry.get("backup_file", "")), RallyUITheme.STATUS_DANGER)
		return
	var sim := _active_simulation()
	if sim == null or _routes.is_empty():
		return
	if not sim.supports_tire_calibration_catalog(backup_doc):
		_set_status("El respaldo no contiene todos los compuestos montados.", RallyUITheme.STATUS_DANGER)
		return
	var preview_vals := _extract_axle_values(sim.make_tire_calibration_model(backup_doc), backup_doc, sim.tire_sources)
	_populate_tables(preview_vals, _loaded_values)
	_update_header_summary()
	_refresh_curves()
	_set_status("Valores del backup cargados en las tablas (aún sin guardar). Pulsa APLICAR Y GUARDAR para confirmarlos.", RallyUITheme.ACCENT_RALLY)


func _on_restore_history_pressed() -> void:
	var entry := _selected_history_entry()
	if entry.is_empty():
		return
	var backup_file := str(entry.get("backup_file", ""))
	var backup_res := BACKUP_DIR_RES.path_join(backup_file)
	var backup_doc := _read_json_dict(backup_res)
	if backup_doc.is_empty():
		_set_status("Error: el archivo de backup '%s' está vacío o no existe." % backup_file, RallyUITheme.STATUS_DANGER)
		return
	var sim := _active_simulation()
	if sim != null and not sim.supports_tire_calibration_catalog(backup_doc):
		_set_status("El respaldo no contiene todos los compuestos montados.", RallyUITheme.STATUS_DANGER)
		return

	var current_doc := _read_json_dict(OFFICIAL_CATALOG_RES)
	if not current_doc.is_empty():
		_ensure_initial_baseline_backup(current_doc)
		var safety := _create_backup_snapshot(
			current_doc,
			"Pre-restauración (auto)",
			"Respaldo automático antes de restaurar %s" % backup_file,
			_loaded_compound_id,
		)
		if not bool(safety.get("ok", false)):
			_set_status(str(safety.get("error", "Error creando backup previo")), RallyUITheme.STATUS_DANGER)
			return

	if not _write_json_dict(OFFICIAL_CATALOG_RES, backup_doc):
		_set_status("Error: no se pudo restaurar el JSON oficial.", RallyUITheme.STATUS_DANGER)
		return

	var reloaded := _reload_vehicle_tire_runtime()
	_reload_from_disk_into_ui()
	_refresh_history_ui()
	_set_status(
		"Backup '%s' restaurado (%s)." % [
			backup_file,
			"física recargada en tiempo real" if reloaded else "guardado en JSON oficial",
		],
		RallyUITheme.STATUS_SUCCESS,
	)


func _on_create_manual_backup_pressed() -> void:
	var current_doc := _read_json_dict(OFFICIAL_CATALOG_RES)
	if current_doc.is_empty():
		_set_status("Error: no se pudo leer el JSON oficial para respaldar.", RallyUITheme.STATUS_DANGER)
		return
	var res := _create_backup_snapshot(current_doc, "Backup manual", "Copia manual del JSON oficial actual", _loaded_compound_id)
	if not bool(res.get("ok", false)):
		_set_status(str(res.get("error", "Error al crear backup")), RallyUITheme.STATUS_DANGER)
		return
	_refresh_history_ui()
	var entry: Dictionary = res["entry"]
	_set_status("Backup manual creado: %s" % str(entry.get("backup_file", "")), RallyUITheme.STATUS_SUCCESS)


func _on_discard_pressed() -> void:
	_reload_from_disk_into_ui()
	_set_status("Cambios descartados. Se muestran los valores activos.", RallyUITheme.TEXT_MUTED)


func _on_apply_pressed() -> void:
	var validation := _collect_validated_values()
	if not bool(validation.get("ok", false)):
		_set_status(str(validation.get("error", "Error de validación")), RallyUITheme.STATUS_DANGER)
		return

	var current_doc := _read_json_dict(OFFICIAL_CATALOG_RES)
	if current_doc.is_empty():
		_set_status("Error: no se pudo leer %s." % OFFICIAL_CATALOG_RES, RallyUITheme.STATUS_DANGER)
		return

	if _count_pending_changes() == 0:
		return
	if current_doc != _catalog:
		_set_status("El archivo cambió fuera de la sesión. Reinicia la sesión para editar esa versión.", RallyUITheme.STATUS_DANGER)
		return
	var sim := _active_simulation()
	if sim == null:
		return
	var changes: Dictionary = validation["values"]
	var updated_doc := _apply_values_to_catalog(current_doc, changes)
	var resolved := _extract_axle_values(sim.make_tire_calibration_model(updated_doc), updated_doc, sim.tire_sources)
	for axle: String in changes:
		for id: String in changes[axle]:
			if absf(float(changes[axle][id]) - float(resolved[axle][id])) > 1.0e-9:
				_set_status("El perfil efectivo no admite este valor para %s (%s)." % [id, axle], RallyUITheme.STATUS_DANGER)
				return
	var diff_summary := _build_diff_summary(_loaded_values, changes)

	_ensure_initial_baseline_backup(current_doc)
	var backup_res := _create_backup_snapshot(current_doc, "Pre-aplicación (auto)", diff_summary, _loaded_compound_id)
	if not bool(backup_res.get("ok", false)):
		_set_status(str(backup_res.get("error", "Fallo al crear backup antes de guardar")), RallyUITheme.STATUS_DANGER)
		return

	if not _write_json_dict(OFFICIAL_CATALOG_RES, updated_doc):
		_set_status("Error escribiendo %s en disco." % OFFICIAL_CATALOG_RES, RallyUITheme.STATUS_DANGER)
		return

	var reloaded := _reload_vehicle_tire_runtime()
	_reload_from_disk_into_ui()
	_refresh_history_ui()
	var backup_file := str((backup_res.get("entry", {}) as Dictionary).get("backup_file", ""))
	_set_status(
		"Guardado en JSON oficial (%s). Backup: %s. %s" % [
			"física aplicada en vivo" if reloaded else "pendiente de vehículo activo",
			backup_file,
			diff_summary,
		],
		RallyUITheme.STATUS_SUCCESS,
	)


func _set_status(msg: String, color: Color) -> void:
	if _status_label == null:
		return
	_status_label.text = msg
	_status_label.tooltip_text = msg
	_status_label.add_theme_color_override("font_color", color)


static func _format_float(v: float) -> String:
	return _CatalogSvc.format_float(v)


static func _build_parameter_specs() -> Array[Dictionary]:
	return _CatalogSvc.build_parameter_specs()


static func _build_filter_specs(all_specs: Array[Dictionary]) -> Array[Dictionary]:
	return _CatalogSvc.build_filter_specs(all_specs)


func _refresh_curves() -> void:
	if not is_open() or _active_tab != "filters" or _routes.is_empty():
		return
	var sim := _active_simulation()
	if sim == null:
		return
	var validation := _collect_validated_values()
	if not validation["ok"]:
		return
	var baseline := sim.make_tire_calibration_model(sim.tire_model.compound_catalog)
	var changes: Dictionary = validation["values"]
	var has_edits: bool = not changes["front"].is_empty() or not changes["rear"].is_empty()
	var candidate := sim.make_tire_calibration_model(_apply_values_to_catalog(_catalog, changes)) if has_edits else baseline
	for axle: String in _curve_plots:
		var wheel := _wheel_index(axle)
		var plot: Control = _curve_plots[axle]
		var previous := _sample_curve(baseline, wheel) if has_edits else PackedVector2Array()
		var current := _sample_curve(candidate, wheel)
		var k_load := candidate.effective_load_sensitivity(wheel)
		var loss := 100.0 * (1.0 - TireModel.load_adjusted_mu(1.0, 2.0, 1.0, k_load))
		plot.set_samples(current, previous, _curve_mode == 0, candidate.static_wheel_load_n[wheel], candidate.reference_hot_pressure_kpa[wheel], k_load, loss)


func _sample_curve(model: TireModel, wheel: int) -> PackedVector2Array:
	# This model is configured for preview, with fresh states and no vehicle body.
	var axle := "front" if wheel < 2 else "rear"
	var load := model.static_wheel_load_n[wheel]
	var pressure := model.reference_hot_pressure_kpa[wheel]
	var temperature := model.axle_optimal_carcass_c[wheel]
	var sidewall := model.maximum_tire_deflection_m[wheel]
	var nominal_radius := float(model.radial_tires[axle].get("radius", 0.28))
	var deflection := TireModel.fallback_deflection_m(model.radial_tires, axle, pressure, temperature, load, temperature, sidewall)
	var radius := TireModel.effective_radius_m(nominal_radius, deflection, sidewall)
	var samples := PackedVector2Array()
	var speed := 20.0
	var slip_max := 0.70 if _curve_mode == 0 else 1.0
	if _curve_mode == 2:
		slip_max = 0.60
	for i in 101:
		var slip := slip_max * float(i) / 100.0
		var lateral_speed := -speed * tan(slip) if _curve_mode == 0 else 0.0
		var rim_speed := speed
		if _curve_mode == 1:
			rim_speed = speed * (1.0 - slip)
		elif _curve_mode == 2:
			rim_speed = speed / (1.0 - slip)
		model.reset_patch(wheel)
		model.states[wheel]["surface_initialized"] = false
		model.states[wheel]["radial_deflection_m"] = deflection
		var result: Dictionary
		for step in 120:
			result = model.evaluate(wheel, load, _curve_surface, speed, lateral_speed, rim_speed / radius, nominal_radius, 0.0, 1.0, pressure, 1.0 / 120.0, temperature, 0.0, 0.0, 20.0)
		var force := float(result["lateral_force_n"] if _curve_mode == 0 else result["longitudinal_force_n"])
		var x := rad_to_deg(slip) if _curve_mode == 0 else slip * 100.0
		samples.append(Vector2(x, -force if _curve_mode == 1 else force))
	return samples
