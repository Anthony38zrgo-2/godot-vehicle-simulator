class_name RallyTireTunerPanel
extends CanvasLayer

## Real-time tire parameter editor (F8) paused cleanly like the pause menu.
## Displays Front and Rear axle tables with plain explanations, editable values,
## live physics reload, official JSON persistence, and automatic timestamped backups.

const OFFICIAL_CATALOG_RES := RallyTireCompound.CATALOG_PATH
const BACKUP_DIR_RES := "res://data/tires/backups"
const HISTORY_INDEX_RES := "res://data/tires/backups/tire_tuning_history.json"
const SURFACES := [
	{"key": "Gravel", "label": "GRAVA (Gravel)"},
	{"key": "Dirt", "label": "TIERRA (Dirt)"},
	{"key": "Road", "label": "ASFALTO (Road)"},
	{"key": "Sand", "label": "ARENA (Sand)"},
	{"key": "Grass", "label": "HIERBA (Grass)"},
	{"key": "Curb", "label": "PIANO / BORDE (Curb)"},
]
const COMPOUND_FORCE_KEYS := [
	"slip_loss_tau_s",
	"combined_lateral_peak_migration",
	"combined_longitudinal_peak_migration",
]
const TIRE_FILTER_SCALAR_KEYS := [
	"surface_transition_tau_s",
	"load_sensitivity_per_newton",
	"load_sensitivity_axle_mult",
	"relaxation_length_scale",
	"contact_patch_load_gain",
	"contact_patch_deflection_gain",
]
const MAX_HISTORY_ENTRIES := 100

var session: Node = null

var _screen: Control
var _overlay_root: Control
var _backdrop: ColorRect
var _modal: PanelContainer
var _sound_player: AudioStreamPlayer
var _header_subtitle: Label
var _search_edit: LineEdit
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
var _history_entries: Array = []
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 102
	_specs = _build_parameter_specs()
	_filter_specs = _build_filter_specs(_specs)
	_build_ui()
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
	root_vbox.add_child(_build_history_panel())
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
	btn_filters.text = "1 · AJUSTES DE FILTROS"
	btn_filters.custom_minimum_size = Vector2(220, 32)
	btn_filters.pressed.connect(func() -> void:
		_set_active_tab("filters")
	)
	hbox.add_child(btn_filters)

	var btn_all := Button.new()
	btn_all.text = "2 · TODOS LOS PARÁMETROS"
	btn_all.custom_minimum_size = Vector2(240, 32)
	btn_all.pressed.connect(func() -> void:
		_set_active_tab("all")
	)
	hbox.add_child(btn_all)

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
	tables_hbox.add_child(_create_axle_table_panel("front", "EJE DELANTERO (FRONT)", specs_list, view_key))
	tables_hbox.add_child(_create_axle_table_panel("rear", "EJE TRASERO (REAR)", specs_list, view_key))
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
		if tab_key == "filters":
			_tab_hint_label.text = "18 filtros por eje (sincronizado con vista completa)"
		else:
			_tab_hint_label.text = "60 parámetros por eje (vista completa)"
		_tab_hint_label.tooltip_text = _tab_hint_label.text


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
		row_margin.add_theme_constant_override("margin_top", 4)
		row_margin.add_theme_constant_override("margin_bottom", 4)
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
		edit.custom_minimum_size = Vector2(108, 28)
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
	_discard_button.text = "Recargar JSON"
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

func _active_compound_id() -> String:
	if session != null:
		var vehicle: Variant = session.get("vehicle")
		if vehicle != null:
			var sim: Variant = vehicle.get("simulation")
			if sim != null:
				var cid := str(sim.get("active_compound_id"))
				if not cid.is_empty():
					return cid
	return RallyTireCompound.DEFAULT_ID


func _resolve_read_path(res_path: String) -> String:
	var global := ProjectSettings.globalize_path(res_path)
	if not global.is_empty() and FileAccess.file_exists(global):
		return global
	return res_path


func _resolve_write_path(res_path: String) -> String:
	var global := ProjectSettings.globalize_path(res_path)
	return global if not global.is_empty() else res_path


func _read_json_dict(res_path: String) -> Dictionary:
	var path := _resolve_read_path(res_path)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (parsed as Dictionary) if parsed is Dictionary else {}


func _write_json_dict(res_path: String, doc: Dictionary) -> bool:
	var write_path := _resolve_write_path(res_path)
	var parent_dir := write_path.get_base_dir()
	if not parent_dir.is_empty():
		var dir_err := DirAccess.make_dir_recursive_absolute(parent_dir)
		if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
			return false
	var serialized := JSON.stringify(doc, "  ", false) + "\n"
	var check: Variant = JSON.parse_string(serialized)
	if not check is Dictionary:
		return false
	var file := FileAccess.open(write_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(serialized)
	file.close()
	return true


func _reload_from_disk_into_ui() -> void:
	RallyTireCompound.invalidate_cache()
	var catalog := _read_json_dict(OFFICIAL_CATALOG_RES)
	_loaded_compound_id = _active_compound_id()
	_loaded_values = _extract_axle_values_from_catalog(catalog, _loaded_compound_id)
	_populate_tables(_loaded_values, _loaded_values)
	_update_header_summary()
	_set_status("Valores cargados desde rally_compounds.json. Edita los números y pulsa APLICAR Y GUARDAR.", RallyUITheme.TEXT_MUTED)


func _extract_axle_values_from_catalog(catalog: Dictionary, compound_id: String) -> Dictionary:
	var out := {"front": {}, "rear": {}}
	var def_profile: Dictionary = catalog.get("default_tire_profile", {}) if catalog.get("default_tire_profile", {}) is Dictionary else {}
	var tires: Dictionary = def_profile.get("tires", {}) if def_profile.get("tires", {}) is Dictionary else {}
	var tire_filters: Dictionary = def_profile.get("tire_filters", {}) if def_profile.get("tire_filters", {}) is Dictionary else {}
	var compounds: Dictionary = catalog.get("compounds", {}) if catalog.get("compounds", {}) is Dictionary else {}
	var comp_def: Dictionary = compounds.get(compound_id, {}) if compounds.get(compound_id, {}) is Dictionary else {}
	var comp_fm_root: Dictionary = comp_def.get("force_model", {}) if comp_def.get("force_model", {}) is Dictionary else {}

	var tires_fm_root: Dictionary = tires.get("force_model", {}) if tires.get("force_model", {}) is Dictionary else {}
	var global_pm: Dictionary = tires.get("pressure_mechanics", {}) if tires.get("pressure_mechanics", {}) is Dictionary else {}
	var global_radial: Dictionary = tires.get("radial_model", {}) if tires.get("radial_model", {}) is Dictionary else {}
	var global_surfaces: Dictionary = tires.get("surfaces", {}) if tires.get("surfaces", {}) is Dictionary else {}

	for axle: String in ["front", "rear"]:
		var is_front: bool = (axle == "front")
		var axle_vals := {}
		var axle_tires: Dictionary = tires.get(axle, {}) if tires.get(axle, {}) is Dictionary else {}
		var axle_filters: Dictionary = tire_filters.get(axle, {}) if tire_filters.get(axle, {}) is Dictionary else {}
		var axle_tires_fm: Dictionary = tires_fm_root.get(axle, {}) if tires_fm_root.get(axle, {}) is Dictionary else {}
		var axle_comp_fm: Dictionary = comp_fm_root.get(axle, {}) if comp_fm_root.get(axle, {}) is Dictionary else {}
		var axle_pm: Dictionary = axle_tires.get("pressure_mechanics", {}) if axle_tires.get("pressure_mechanics", {}) is Dictionary else {}
		var axle_radial: Dictionary = axle_tires.get("radial_model", {}) if axle_tires.get("radial_model", {}) is Dictionary else {}
		var axle_surf_root: Dictionary = axle_tires.get("surfaces", {}) if axle_tires.get("surfaces", {}) is Dictionary else {}
		var flt_surf_root: Dictionary = axle_filters.get("surfaces", {}) if axle_filters.get("surfaces", {}) is Dictionary else {}

		for spec in _specs:
			if str(spec.get("kind", "")) != "param":
				continue
			var id := str(spec.get("id", ""))
			var source := str(spec.get("source", ""))
			var field := str(spec.get("field", ""))
			var val := float(spec.get("default", 0.0))

			match source:
				"force_model":
					if axle_comp_fm.has(field):
						val = float(axle_comp_fm.get(field, val))
					elif axle_tires_fm.has(field):
						val = float(axle_tires_fm.get(field, val))
					elif axle_filters.has(field):
						val = float(axle_filters.get(field, val))
				"axle_scalar":
					if axle_filters.has(field):
						val = float(axle_filters.get(field, val))
					elif axle_tires.has(field):
						val = float(axle_tires.get(field, val))
					elif tires.has(field):
						val = float(tires.get(field, val))
					elif tire_filters.has(field):
						val = float(tire_filters.get(field, val))
				"pressure_mechanics":
					if axle_pm.has(field):
						val = float(axle_pm.get(field, val))
					elif global_pm.has(field):
						val = float(global_pm.get(field, val))
				"radial_model":
					if axle_radial.has(field):
						val = float(axle_radial.get(field, val))
					elif global_radial.has(field):
						val = float(global_radial.get(field, val))
				"surface":
					var surf_name := str(spec.get("surface", ""))
					val = _resolve_surface_value(global_surfaces, axle_surf_root, flt_surf_root, surf_name, field, is_front)

			axle_vals[id] = val
		out[axle] = axle_vals
	return out


func _resolve_surface_value(
	global_surfaces: Dictionary,
	axle_surfaces: Dictionary,
	filter_surfaces: Dictionary,
	surf_name: String,
	field: String,
	is_front: bool,
) -> float:
	var g_surf: Dictionary = global_surfaces.get(surf_name, {}) if global_surfaces.get(surf_name, {}) is Dictionary else {}
	var ax_surf: Dictionary = axle_surfaces.get(surf_name, {}) if axle_surfaces.get(surf_name, {}) is Dictionary else {}
	var flt_surf: Dictionary = filter_surfaces.get(surf_name, {}) if filter_surfaces.get(surf_name, {}) is Dictionary else {}
	if flt_surf.has(field):
		return float(flt_surf.get(field, 0.0))
	if ax_surf.has(field):
		return float(ax_surf.get(field, 0.0))
	if is_front and field == "lateral_grip_assist":
		return 0.0
	if g_surf.has(field):
		return float(g_surf.get(field, 0.0))
	var defaults := {
		"friction": 1.0,
		"stiffness": 1.0,
		"rolling_resistance": 1.0,
		"longitudinal_grip_ratio": 1.0,
		"lateral_grip_assist": 0.0,
	}
	return float(defaults.get(field, 0.0))


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
				var v := float(vals.get(id, 0.0))
				var base_v := float(base_vals.get(id, v))
				edit.text = _format_float(v)
				var spec: Dictionary = row["spec"]
				edit.tooltip_text = "JSON actual: %s  |  Rango permitido: [%s .. %s]" % [
					_format_float(base_v),
					_format_float(float(spec.get("min", -1e9))),
					_format_float(float(spec.get("max", 1e9))),
				]
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
		var parsed := _parse_row_float(sibling_rows[0])
		var current_v := float(parsed.get("value", base_v))
		var valid := bool(parsed.get("ok", false))
		for r in sibling_rows:
			_style_row_state(r, current_v, base_v, valid)
	_syncing_edits = false
	_update_header_summary()


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


func _parse_row_float(row: Dictionary) -> Dictionary:
	var edit: LineEdit = row["edit"]
	var spec: Dictionary = row["spec"]
	var raw := edit.text.strip_edges().replace(",", ".")
	if raw.is_empty() or not raw.is_valid_float():
		return {"ok": false, "error": "Valor no numérico en '%s'" % str(spec.get("key", ""))}
	var v := raw.to_float()
	if not is_finite(v):
		return {"ok": false, "error": "Valor infinito o inválido en '%s'" % str(spec.get("key", ""))}
	var min_v := float(spec.get("min", -1e12))
	var max_v := float(spec.get("max", 1e12))
	var strict_pos := bool(spec.get("strict_positive", false))
	if strict_pos and v <= 0.0:
		return {"ok": false, "error": "'%s' debe ser mayor que 0." % str(spec.get("key", ""))}
	if v < min_v or v > max_v:
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
	for axle: String in ["front", "rear"]:
		var axle_map := {}
		for row in _canonical_rows_for_axle(axle):
			if str(row.get("kind", "")) != "param":
				continue
			var res := _parse_row_float(row)
			if not bool(res.get("ok", false)):
				return {"ok": false, "error": "[%s] %s" % [axle.to_upper(), str(res.get("error", "Error"))]}
			axle_map[str(row["id"])] = float(res["value"])
		values[axle] = axle_map
	return {"ok": true, "values": values}


func _count_pending_changes() -> int:
	var count := 0
	for axle: String in ["front", "rear"]:
		var base_vals: Dictionary = _loaded_values.get(axle, {})
		for row in _canonical_rows_for_axle(axle):
			if str(row.get("kind", "")) != "param":
				continue
			var parsed := _parse_row_float(row)
			if not bool(parsed.get("ok", false)):
				count += 1
				continue
			var base_v := float(base_vals.get(str(row["id"]), 0.0))
			if absf(float(parsed["value"]) - base_v) > 1e-9:
				count += 1
	return count


func _update_header_summary() -> void:
	if _header_subtitle == null:
		return
	var comp_label := _loaded_compound_id
	var cat := _read_json_dict(OFFICIAL_CATALOG_RES)
	var comp_def: Variant = (cat.get("compounds", {}) as Dictionary).get(_loaded_compound_id, {})
	if comp_def is Dictionary and not str((comp_def as Dictionary).get("label", "")).is_empty():
		comp_label = "%s (%s)" % [str((comp_def as Dictionary).get("label", "")), _loaded_compound_id]
	var pending := _count_pending_changes()
	var pending_text := "Sin cambios pendientes" if pending == 0 else ("%d cambios sin aplicar" % pending)
	_header_subtitle.text = "Compuesto activo: %s  ·  JSON oficial: %s  ·  %s" % [comp_label, OFFICIAL_CATALOG_RES, pending_text]


func _build_diff_summary(old_values: Dictionary, new_values: Dictionary) -> String:
	var diffs: Array[String] = []
	for axle in ["front", "rear"]:
		var prefix := "Del" if axle == "front" else "Tras"
		var old_map: Dictionary = old_values.get(axle, {})
		var new_map: Dictionary = new_values.get(axle, {})
		for spec in _specs:
			if str(spec.get("kind", "")) != "param":
				continue
			var id := str(spec["id"])
			var a := float(old_map.get(id, 0.0))
			var b := float(new_map.get(id, 0.0))
			if absf(a - b) > 1e-9:
				diffs.append("%s %s: %s→%s" % [prefix, str(spec["key"]), _format_float(a), _format_float(b)])
	if diffs.is_empty():
		return "Sin cambios en parámetros de tabla"
	if diffs.size() <= 4:
		return "; ".join(diffs)
	return "%s (+%d más)" % ["; ".join(diffs.slice(0, 4)), diffs.size() - 4]


func _apply_values_to_catalog(catalog: Dictionary, values: Dictionary, compound_id: String) -> Dictionary:
	var doc := catalog.duplicate(true)
	if not doc.get("default_tire_profile") is Dictionary:
		doc["default_tire_profile"] = {}
	var def_profile: Dictionary = doc["default_tire_profile"]
	if not def_profile.get("tires") is Dictionary:
		def_profile["tires"] = {}
	if not def_profile.get("tire_filters") is Dictionary:
		def_profile["tire_filters"] = {}
	var tires: Dictionary = def_profile["tires"]
	var tire_filters: Dictionary = def_profile["tire_filters"]
	if not tires.get("force_model") is Dictionary:
		tires["force_model"] = {}
	var tires_fm_root: Dictionary = tires["force_model"]
	var global_surfaces: Dictionary = tires.get("surfaces", {}) if tires.get("surfaces", {}) is Dictionary else {}
	var compounds: Dictionary = doc.get("compounds", {}) if doc.get("compounds", {}) is Dictionary else {}
	var active_comp: Dictionary = compounds.get(compound_id, {}) if compounds.get(compound_id, {}) is Dictionary else {}

	for axle: String in ["front", "rear"]:
		var is_front: bool = (axle == "front")
		var axle_vals: Dictionary = values.get(axle, {})
		if not tires.get(axle) is Dictionary:
			tires[axle] = {}
		if not tire_filters.get(axle) is Dictionary:
			tire_filters[axle] = {}
		if not tires_fm_root.get(axle) is Dictionary:
			tires_fm_root[axle] = {}
		var axle_tires: Dictionary = tires[axle]
		var axle_filters: Dictionary = tire_filters[axle]
		var axle_fm: Dictionary = tires_fm_root[axle]

		if not axle_tires.get("pressure_mechanics") is Dictionary:
			axle_tires["pressure_mechanics"] = (tires.get("pressure_mechanics", {}) as Dictionary).duplicate(true)
		var axle_pm: Dictionary = axle_tires["pressure_mechanics"]

		if not axle_tires.get("radial_model") is Dictionary:
			axle_tires["radial_model"] = (tires.get("radial_model", {}) as Dictionary).duplicate(true)
		var axle_radial: Dictionary = axle_tires["radial_model"]

		if not axle_tires.get("surfaces") is Dictionary:
			axle_tires["surfaces"] = {}
		if not axle_filters.get("surfaces") is Dictionary:
			axle_filters["surfaces"] = {}
		var axle_surf_root: Dictionary = axle_tires["surfaces"]
		var flt_surf_root: Dictionary = axle_filters["surfaces"]

		var comp_axle_fm: Dictionary = {}
		var sync_comp_fm := active_comp.get("force_model") is Dictionary
		if sync_comp_fm:
			var comp_fm_root: Dictionary = active_comp["force_model"]
			if not comp_fm_root.get(axle) is Dictionary:
				comp_fm_root[axle] = {}
			comp_axle_fm = comp_fm_root[axle]

		for spec in _specs:
			if str(spec.get("kind", "")) != "param":
				continue
			var id := str(spec["id"])
			if not axle_vals.has(id):
				continue
			var v := float(axle_vals[id])
			var source := str(spec["source"])
			var field := str(spec["field"])

			match source:
				"force_model":
					axle_fm[field] = v
					axle_filters[field] = v
					if sync_comp_fm and (COMPOUND_FORCE_KEYS.has(field) or comp_axle_fm.has(field)):
						comp_axle_fm[field] = v
				"axle_scalar":
					axle_tires[field] = v
					if TIRE_FILTER_SCALAR_KEYS.has(field) or axle_filters.has(field):
						axle_filters[field] = v
				"pressure_mechanics":
					axle_pm[field] = v
				"radial_model":
					axle_radial[field] = v
				"surface":
					var surf_name := str(spec["surface"])
					var base_v := _resolve_surface_value(global_surfaces, {}, {}, surf_name, field, is_front)
					var already_present := axle_surf_root.has(surf_name) or flt_surf_root.has(surf_name)
					if already_present or absf(v - base_v) > 1e-9:
						if not axle_surf_root.get(surf_name) is Dictionary:
							axle_surf_root[surf_name] = {}
						if not flt_surf_root.get(surf_name) is Dictionary:
							flt_surf_root[surf_name] = {}
						(axle_surf_root[surf_name] as Dictionary)[field] = v
						(flt_surf_root[surf_name] as Dictionary)[field] = v

	return doc


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
# HISTORY & BACKUP MANAGEMENT
# =============================================================================

func _load_history_index() -> Array:
	var doc := _read_json_dict(HISTORY_INDEX_RES)
	var entries: Variant = doc.get("entries", [])
	return (entries as Array).duplicate(true) if entries is Array else []


func _save_history_index(entries: Array) -> bool:
	return _write_json_dict(HISTORY_INDEX_RES, {"format_version": 1, "entries": entries})


func _ensure_initial_baseline_backup(current_catalog: Dictionary) -> void:
	var existing := _load_history_index()
	if not existing.is_empty():
		return
	_create_backup_snapshot(current_catalog, "Baseline inicial", "Copia automática inicial previa a ediciones", _loaded_compound_id)


func _create_backup_snapshot(catalog: Dictionary, label_text: String, changes_summary: String, compound_id: String) -> Dictionary:
	var dt := Time.get_datetime_dict_from_system()
	var ms := Time.get_ticks_msec() % 1000
	var stamp_human := "%04d-%02d-%02d %02d:%02d:%02d" % [
		int(dt.get("year", 2026)), int(dt.get("month", 1)), int(dt.get("day", 1)),
		int(dt.get("hour", 0)), int(dt.get("minute", 0)), int(dt.get("second", 0)),
	]
	var stamp_file := "%04d-%02d-%02d_%02d-%02d-%02d_%03d" % [
		int(dt.get("year", 2026)), int(dt.get("month", 1)), int(dt.get("day", 1)),
		int(dt.get("hour", 0)), int(dt.get("minute", 0)), int(dt.get("second", 0)), ms,
	]
	var filename := "rally_compounds_%s.json" % stamp_file
	var backup_res := BACKUP_DIR_RES.path_join(filename)
	if not _write_json_dict(backup_res, catalog):
		return {"ok": false, "error": "No se pudo escribir el archivo de backup en %s" % backup_res}

	var entries := _load_history_index()
	var entry := {
		"id": stamp_file,
		"timestamp": stamp_human,
		"label": label_text,
		"compound_id": compound_id,
		"backup_file": filename,
		"changes_summary": changes_summary,
	}
	entries.push_front(entry)
	if entries.size() > MAX_HISTORY_ENTRIES:
		entries.resize(MAX_HISTORY_ENTRIES)
	_save_history_index(entries)
	return {"ok": true, "entry": entry}


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
	var preview_vals := _extract_axle_values_from_catalog(backup_doc, _loaded_compound_id)
	_populate_tables(preview_vals, _loaded_values)
	_update_header_summary()
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
	_set_status("Tablas recargadas desde el JSON oficial (cambios no guardados descartados).", RallyUITheme.TEXT_MUTED)


func _on_apply_pressed() -> void:
	var validation := _collect_validated_values()
	if not bool(validation.get("ok", false)):
		_set_status(str(validation.get("error", "Error de validación")), RallyUITheme.STATUS_DANGER)
		return

	var current_doc := _read_json_dict(OFFICIAL_CATALOG_RES)
	if current_doc.is_empty():
		_set_status("Error: no se pudo leer %s." % OFFICIAL_CATALOG_RES, RallyUITheme.STATUS_DANGER)
		return

	var new_values: Dictionary = validation["values"]
	var old_values := _extract_axle_values_from_catalog(current_doc, _loaded_compound_id)
	var diff_summary := _build_diff_summary(old_values, new_values)

	_ensure_initial_baseline_backup(current_doc)
	var backup_res := _create_backup_snapshot(current_doc, "Pre-aplicación (auto)", diff_summary, _loaded_compound_id)
	if not bool(backup_res.get("ok", false)):
		_set_status(str(backup_res.get("error", "Fallo al crear backup antes de guardar")), RallyUITheme.STATUS_DANGER)
		return

	var updated_doc := _apply_values_to_catalog(current_doc, new_values, _loaded_compound_id)
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
	if not is_finite(v):
		return "0"
	if is_zero_approx(v):
		return "0"
	var text := "%.10f" % v
	if text.contains("."):
		while text.ends_with("0"):
			text = text.substr(0, text.length() - 1)
		if text.ends_with("."):
			text = text.substr(0, text.length() - 1)
	return text if text != "-0" else "0"


# =============================================================================
# TIRE PARAMETER SCHEMA
# =============================================================================

static func _param(
	id: String, key: String, desc: String, source: String, field: String,
	min_v: float, max_v: float, default_v: float, strict_positive: bool = false, surface_name: String = "",
) -> Dictionary:
	return {
		"kind": "param",
		"id": id,
		"key": key,
		"description": desc,
		"source": source,
		"field": field,
		"min": min_v,
		"max": max_v,
		"default": default_v,
		"strict_positive": strict_positive,
		"surface": surface_name,
	}


static func _build_parameter_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = [
		{"kind": "section", "title": "CURVA DE AGARRE Y DESLIZAMIENTO (force_model)"},
		_param("fm.lateral_peak_slip_angle_rad", "lateral_peak_slip_angle_rad", "Ángulo (rad) donde alcanza el pico de agarre lateral; mayor = dirección más progresiva.", "force_model", "lateral_peak_slip_angle_rad", 0.02, 1.2, 0.18),
		_param("fm.lateral_slide_mu_ratio", "lateral_slide_mu_ratio", "Fracción de agarre lateral tras superar el pico; mayor = trasera más noble y menos brusca.", "force_model", "lateral_slide_mu_ratio", 0.2, 1.5, 0.92),
		_param("fm.longitudinal_peak_slip_ratio", "longitudinal_peak_slip_ratio", "Deslizamiento óptimo en tracción/freno; mayor = más margen antes de patinar o bloquear.", "force_model", "longitudinal_peak_slip_ratio", 0.02, 1.0, 0.2),
		_param("fm.longitudinal_slide_mu_ratio", "longitudinal_slide_mu_ratio", "Fracción de agarre longitudinal más allá del pico; empuje residual al patinar o bloquear.", "force_model", "longitudinal_slide_mu_ratio", 0.2, 1.5, 0.91),
		_param("fm.falloff_sharpness", "falloff_sharpness", "Brusquedad de pérdida de agarre tras el pico; menor = transición más suave y controlable.", "force_model", "falloff_sharpness", 0.05, 5.0, 1.0),
		_param("fm.combined_lateral_peak_migration", "combined_lateral_peak_migration", "Migración del pico lateral al frenar o acelerar en curva; ayuda en trail-braking.", "force_model", "combined_lateral_peak_migration", 0.0, 1.0, 0.3),
		_param("fm.combined_longitudinal_peak_migration", "combined_longitudinal_peak_migration", "Migración del pico longitudinal al girar; evita corte brusco al dar gas doblando.", "force_model", "combined_longitudinal_peak_migration", 0.0, 1.0, 0.35),
		_param("fm.budget_blend_width", "budget_blend_width", "Ancho de transición al límite combinado lat+lon; mayor = paso más dulce al límite.", "force_model", "budget_blend_width", 0.01, 2.0, 0.2),
		_param("fm.peak_load_sensitivity", "peak_load_sensitivity", "Desplazamiento del pico según carga vertical; modula cambios por transferencia de peso.", "force_model", "peak_load_sensitivity", -0.5, 1.0, 0.05),

		{"kind": "section", "title": "TRANSITORIOS, RELAJACIÓN Y HUELLA"},
		_param("fm.slip_loss_tau_s", "slip_loss_tau_s", "Tiempo (s) en soltar relajación al entrar en derrape; menor = giro más vivo al romper agarre.", "force_model", "slip_loss_tau_s", 0.001, 2.0, 0.08),
		_param("fm.slip_recovery_tau_s", "slip_recovery_tau_s", "Tiempo (s) en recuperar agarre al salir del derrape; menor = cambia de apoyo en S más rápido.", "force_model", "slip_recovery_tau_s", 0.001, 2.0, 0.09),
		_param("fm.contact_ramp_tau_s", "contact_ramp_tau_s", "Tiempo (s) de asentamiento del apoyo tras baches o saltos; menor = mordida más inmediata.", "force_model", "contact_ramp_tau_s", 0.0, 2.0, 0.05),
		_param("fm.min_relaxation_tau_s", "min_relaxation_tau_s", "Retardo mínimo (s) de deformación del flanco; menor = respuesta más directa al volante.", "force_model", "min_relaxation_tau_s", 0.001, 1.0, 0.01),
		_param("fm.relaxation_recovery_scale", "relaxation_recovery_scale", "Escala de retorno de relajación al estabilizar; <1 agiliza recuperación entre curvas.", "force_model", "relaxation_recovery_scale", 0.1, 3.0, 0.9),
		_param("ax.relaxation_length_scale", "relaxation_length_scale", "Longitud de relajación respecto a la huella; mayor = respuesta más filtrada y dócil.", "axle_scalar", "relaxation_length_scale", 0.2, 5.0, 1.25),
		_param("ax.surface_transition_tau_s", "surface_transition_tau_s", "Suavizado (s) al cambiar entre superficies; menor = adaptación más instantánea.", "axle_scalar", "surface_transition_tau_s", 0.0, 2.0, 0.09),
		_param("ax.contact_patch_load_gain", "contact_patch_load_gain", "Crecimiento de la huella dinámica con el peso vertical; aporta apoyo bajo carga.", "axle_scalar", "contact_patch_load_gain", 0.0, 1.0, 0.12),
		_param("ax.contact_patch_deflection_gain", "contact_patch_deflection_gain", "Crecimiento de huella según la compresión de carcasa en apoyos y aterrizajes.", "axle_scalar", "contact_patch_deflection_gain", 0.0, 1.0, 0.2),

		{"kind": "section", "title": "SENSIBILIDAD A CARGA Y PRESIÓN"},
		_param("ax.load_sensitivity_axle_mult", "load_sensitivity_axle_mult", "Caída de agarre del eje al aumentar peso; subirlo delante da subviraje, atrás provoca rotación.", "axle_scalar", "load_sensitivity_axle_mult", 0.1, 8.0, 2.275),
		_param("ax.load_sensitivity_per_newton", "load_sensitivity_per_newton", "Pérdida base de μ por cada newton extra; menor conserva más agarre en apoyos fuertes.", "axle_scalar", "load_sensitivity_per_newton", 0.0, 0.001, 1.5e-5),
		_param("ax.airborne_spin_decay_torque", "airborne_spin_decay_torque", "Par de frenado que desacelera la rueda en el aire durante saltos.", "axle_scalar", "airborne_spin_decay_torque", 0.0, 50.0, 1.5),
		_param("pm.compliance_sensitivity", "pressure_mechanics.compliance_sensitivity", "Sensibilidad de elasticidad y absorción de carcasa ante cambios de presión.", "pressure_mechanics", "compliance_sensitivity", -3.0, 3.0, 0.6),
		_param("pm.response_sensitivity", "pressure_mechanics.response_sensitivity", "Influencia de la presión de aire sobre la rapidez de respuesta y relajación.", "pressure_mechanics", "response_sensitivity", -3.0, 3.0, -0.15),
		_param("pm.rolling_resistance_sensitivity", "pressure_mechanics.rolling_resistance_sensitivity", "Variación de la resistencia a la rodadura según la presión en caliente.", "pressure_mechanics", "rolling_resistance_sensitivity", -3.0, 3.0, -0.3),

		{"kind": "section", "title": "CARCASA RADIAL (radial_model)"},
		_param("rad.carcass_stiffness_n_m", "radial_model.carcass_stiffness_n_m", "Rigidez base de carcasa (N/m); mayor = flanco firme y directo, menor = más absorción.", "radial_model", "carcass_stiffness_n_m", 1000.0, 500000.0, 30000.0, true),
		_param("rad.pressure_stiffness_n_m_per_kpa", "radial_model.pressure_stiffness_n_m_per_kpa", "Rigidez extra por kPa de presión (N/m/kPa); controla cuánto endurece al inflar.", "radial_model", "pressure_stiffness_n_m_per_kpa", 1.0, 10000.0, 666.6667, true),
		_param("rad.damping_ratio", "radial_model.damping_ratio", "Amortiguamiento vertical de carcasa; mayor = menos rebote en rizado y baches.", "radial_model", "damping_ratio", 0.0, 2.0, 0.12),
		_param("rad.damping_contact_ramp_m", "radial_model.damping_contact_ramp_m", "Rampa inicial (m) de contacto para suavizar impactos verticales tras un salto.", "radial_model", "damping_contact_ramp_m", 0.0001, 0.1, 0.005, true),
		_param("rad.rim_stop_start_sidewall_fraction", "radial_model.rim_stop_start_sidewall_fraction", "Fracción comprimida del flanco donde entra el tope de llanta (entre 0 y 1).", "radial_model", "rim_stop_start_sidewall_fraction", 0.05, 0.98, 0.75),
		_param("rad.rim_stop_stiffness_n_m", "radial_model.rim_stop_stiffness_n_m", "Rigidez del tope metálico de llanta (N/m) en compresiones extremas.", "radial_model", "rim_stop_stiffness_n_m", 1000.0, 2000000.0, 300000.0, true),
	]

	for s_info in SURFACES:
		var s_key := str(s_info["key"])
		var s_label := str(s_info["label"])
		specs.append({"kind": "section", "title": "SUPERFICIE · " + s_label})
		specs.append(_param(
			"surf.%s.friction" % s_key,
			"surfaces.%s.friction" % s_key,
			"Agarre global del eje sobre %s. Sube para más grip total o baja para soltar antes." % s_key,
			"surface", "friction", 0.05, 3.0, 1.0, false, s_key,
		))
		specs.append(_param(
			"surf.%s.stiffness" % s_key,
			"surfaces.%s.stiffness" % s_key,
			"Mordida inicial a poco volante sobre %s. Mayor = respuesta inicial más incisiva." % s_key,
			"surface", "stiffness", 0.05, 10.0, 1.0, false, s_key,
		))
		specs.append(_param(
			"surf.%s.longitudinal_grip_ratio" % s_key,
			"surfaces.%s.longitudinal_grip_ratio" % s_key,
			"Balance tracción/freno frente a giro en %s (>1 prioriza acelerar/frenar; <1 prioriza lateral)." % s_key,
			"surface", "longitudinal_grip_ratio", 0.1, 3.0, 1.0, false, s_key,
		))
		specs.append(_param(
			"surf.%s.lateral_grip_assist" % s_key,
			"surfaces.%s.lateral_grip_assist" % s_key,
			"Asistencia extra de apoyo lateral en %s para estabilizar derrapes en suelto." % s_key,
			"surface", "lateral_grip_assist", -0.5, 1.0, 0.0, false, s_key,
		))
		specs.append(_param(
			"surf.%s.rolling_resistance" % s_key,
			"surfaces.%s.rolling_resistance" % s_key,
			"Resistencia al avance y hundimiento en %s; mayor frena más el coche al rodar." % s_key,
			"surface", "rolling_resistance", 0.0, 20.0, 1.0, false, s_key,
		))

	return specs


static func _build_filter_specs(all_specs: Array[Dictionary]) -> Array[Dictionary]:
	var by_id := {}
	for s in all_specs:
		if str(s.get("kind", "")) == "param":
			by_id[str(s["id"])] = s
	var groups := [
		{
			"title": "CURVA COMBINADA (tire_filters)",
			"ids": [
				"fm.combined_lateral_peak_migration",
				"fm.combined_longitudinal_peak_migration",
			],
		},
		{
			"title": "TRANSITORIOS, RELAJACIÓN Y HUELLA (tire_filters)",
			"ids": [
				"fm.slip_loss_tau_s",
				"fm.slip_recovery_tau_s",
				"fm.contact_ramp_tau_s",
				"fm.min_relaxation_tau_s",
				"fm.relaxation_recovery_scale",
				"ax.surface_transition_tau_s",
				"ax.relaxation_length_scale",
				"ax.contact_patch_load_gain",
				"ax.contact_patch_deflection_gain",
			],
		},
		{
			"title": "SENSIBILIDAD A CARGA (tire_filters)",
			"ids": [
				"ax.load_sensitivity_axle_mult",
				"ax.load_sensitivity_per_newton",
			],
		},
		{
			"title": "SUPERFICIE GRAVA (tire_filters · Gravel)",
			"ids": [
				"surf.Gravel.friction",
				"surf.Gravel.stiffness",
				"surf.Gravel.longitudinal_grip_ratio",
				"surf.Gravel.lateral_grip_assist",
				"surf.Gravel.rolling_resistance",
			],
		},
	]
	var out: Array[Dictionary] = []
	for g in groups:
		out.append({"kind": "section", "title": str(g["title"])})
		for pid in g["ids"]:
			if by_id.has(pid):
				out.append(by_id[pid])
	return out
