class_name RallyGaragePanel
extends Control
## Real Godot Control-node Garage & Setup panel (migrated from immediate-mode _draw() / _hit_regions).
## Composes UITabBar, GarageStageTab, GarageChassisTab, GaragePowertrainTab, GarageStrategyTab,
## GarageSetupPresenter, and RallyGarageStrategyBoard (3D pool board).

signal garage_closed(applied: bool)

const LOGICAL_SIZE := Vector2(1280.0, 800.0)
const StrategyBoardScript := preload("res://scripts/rally/rally_garage_strategy_board.gd")
const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _Presenter := preload("res://scripts/ui/services/garage_setup_presenter.gd")
const _Catalog := preload("res://scripts/ui/services/menu_catalog_service.gd")
const _TabBarScene := preload("res://ui/molecules/ui_tab_bar.tscn")
const _StageTabScene := preload("res://ui/screens/garage/garage_stage_tab.tscn")
const _ChassisTabScene := preload("res://ui/screens/garage/garage_chassis_tab.tscn")
const _PowertrainTabScene := preload("res://ui/screens/garage/garage_powertrain_tab.tscn")
const _StrategyTabScene := preload("res://ui/screens/garage/garage_strategy_tab.tscn")

const PAD_NAME_CHARACTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_"
const CHASSIS_PATHS: Array[String] = [
	"garage.suspension",
	"garage.front_arb",
	"garage.rear_arb",
	"brakes.front_brake_bias",
	"suspension.front.camber",
	"suspension.rear.camber",
	"suspension.front.toe",
	"suspension.rear.toe",
]
const POWERTRAIN_PATHS: Array[String] = [
	"powertrain.final_drive",
	"powertrain.max_rpm",
	"garage.cooling",
	"garage.lsd",
	"powertrain.differential.clutches",
	"powertrain.differential.power_ramp_angle_deg",
	"powertrain.differential.coast_ramp_angle_deg",
]
const STRATEGY_PATHS: Array[String] = [
	"fuel.initial_kg",
	"garage.front_pressure",
	"garage.rear_pressure",
]
const INVERTED_DISCRETE_PATHS: Array[String] = [
	"garage.suspension",
	"garage.front_arb",
	"garage.rear_arb",
]
const ESTIMATED_FUEL_BURN_L_PER_KM := 0.42

@export var vehicle_path: NodePath
@export var input_controller_path: NodePath
@export_enum("rally", "gp") var mode: String = "rally"
@export var circuit_id: String = "russia-stage-1"
@export var circuit_name: String = "Rusia Stage 1"
@export var circuit_country: String = "Russia"
@export var circuit_length_m: float = 5500.0
@export var team_id: String = "rally-works"
@export var team_name: String = "Ford Rally Works"
@export var stage_route_path: String = ""
@export var stage_weather_label: String = ""

var _cached_route_key: String = ""
var _cached_route_points: PackedVector2Array = PackedVector2Array()
var _cached_route_heights: PackedFloat32Array = PackedFloat32Array()
var _cached_profile_altitudes: PackedFloat32Array = PackedFloat32Array()
var _cached_route_length_m: float = 0.0
var _stage_length_explicit: bool = false
var _stage_sectors: Array = []
var _stage_terrain: Dictionary = {}
var _briefing_cache_key: String = ""

var mandatory_confirmation := false
var compound_change_allowed := true
var allowed_compound_ids: Array = []
var compound_label_overrides: Dictionary = {}
var default_event_compound_id: String = RallyTireCompound.DEFAULT_ID
var draft_wheel_compounds: Dictionary = {}
var draft_compound_id: String:
	get:
		return str(draft_wheel_compounds.get("FL", RallyTireCompound.DEFAULT_ID))
	set(value):
		for corner in ["FL", "FR", "RL", "RR"]:
			draft_wheel_compounds[corner] = value
var opening_wheel_compounds: Dictionary = {}
var draft_spare_wheels := 1
var opening_spares := 1
var confirmed_setup: Dictionary = {}
var event_forecast := ""
var draft_mounted_ids: Array[int] = []
var draft_spare_ids: Array[int] = []
var draft_stock_ids: Array[int] = []
var opening_mounted_ids: Array[int] = []
var opening_spare_ids: Array[int] = []
var selected_pool_tire_id: int = -1
var _pool_plan_dirty: bool = false
var _opening_for_event: bool = false

var vehicle: RallyEscortVehicle
var input_controller: RallyVehicleInputController
var database := RallySetupDatabase.new()
var database_ready: bool = false
var database_status: String = ""
var page: int = 0
var selected_field_path: String = ""
var selected_setup_index: int = 0
var selected_setup_id: int = -1
var active_setup_id: int = -1
var active_setup_name: String = "REGLAJE ACTUAL"
var setup_rows: Array[Dictionary] = []
var draft_values: Dictionary = {}
var opening_values: Dictionary = {}
var new_tires_service: bool = false
var modal_mode: String = ""
var modal_text: String = ""
var notice: String = ""
var notice_time: float = 0.0
var notice_is_error: bool = false
var profile_dropdown_open: bool = false
var pad_character_index: int = 0

var _page_field_paths: Array[String] = []
var _canvas_scale: float = 1.0
var _canvas_offset: Vector2 = Vector2.ZERO
var _restore_tree_paused: bool = false
var _restore_controls_enabled: bool = true
var _strategy_board: StrategyBoardScript = null

# Real Control node tree
var _logical_root: Control
var _overlay_root: Control
var _car_title_lbl: Label
var _stage_title_lbl: Label
var _profile_btn: Button
var _save_btn: Button
var _tab_bar: Control
var _dirty_badge_lbl: Label
var _stage_tab: Control
var _chassis_tab: Control
var _powertrain_tab: Control
var _strategy_tab: Control
var _profile_dropdown_panel: PanelContainer
var _profile_list_vbox: VBoxContainer
var _modal_overlay: ColorRect
var _modal_title_lbl: Label
var _modal_msg_lbl: Label
var _modal_input: LineEdit
var _notice_lbl: Label
var reset_button: Button
var cancel_button: Button
var apply_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process_input(false)
	theme = _Theme.get_menu_theme()

	_build_ui_tree()

	_strategy_board = StrategyBoardScript.new()
	_strategy_board.name = "StrategyBoard3D"
	_strategy_board.garage = self
	_strategy_board.visible = false
	add_child(_strategy_board)

	_build_overlays()
	_resize_canvas()
	call_deferred("_resize_canvas")

	if vehicle == null and not vehicle_path.is_empty():
		vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	if vehicle == null and get_parent() != null:
		vehicle = get_parent().find_child("FordEscortRS2000", true, false) as RallyEscortVehicle
		if vehicle == null:
			vehicle = get_parent().find_child("LanciaFulvia", true, false) as RallyEscortVehicle
	if input_controller == null and not input_controller_path.is_empty():
		input_controller = get_node_or_null(input_controller_path) as RallyVehicleInputController
	if input_controller != null and not input_controller.garage_menu_requested.is_connected(open_garage):
		input_controller.garage_menu_requested.connect(open_garage)
	if vehicle == null:
		database_status = "Vehículo no encontrado"
		push_error(database_status)
		return
	var opened := database.open_database()
	database_ready = bool(opened.get("ok", false))
	database_status = "" if database_ready else str(opened.get("error", "Error SQLite"))
	if not database_ready:
		push_error("Rally setup database: " + database_status)
	_resize_canvas()


func _exit_tree() -> void:
	if _strategy_board != null and is_instance_valid(_strategy_board):
		_strategy_board.clear_board()
	database.close_database()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_resize_canvas()


func _build_ui_tree() -> void:
	var r := _Tokens.get_radius("default")
	var c_shell := _Tokens.get_color("bg_shell")
	var c_surf := _Tokens.get_color("bg_surface")
	var c_content := _Tokens.get_color("bg_content")
	var c_well := _Tokens.get_color("bg_well")
	var c_border := _Tokens.get_color("border_card")
	var c_subtle := _Tokens.get_color("border_subtle")
	var c_accent := _Tokens.get_color("accent_rally")

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = c_shell
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_logical_root = Control.new()
	_logical_root.name = "LogicalRoot"
	_logical_root.size = LOGICAL_SIZE
	_logical_root.custom_minimum_size = LOGICAL_SIZE
	_logical_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logical_root)

	# 1. Header bar (24, 14, 1232, 82)
	var header_panel := PanelContainer.new()
	header_panel.position = Vector2(24, 14)
	header_panel.size = Vector2(1232, 82)
	header_panel.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_surf, c_border, 1, r, 16, 10))
	_logical_root.add_child(header_panel)

	var header_h := HBoxContainer.new()
	header_h.add_theme_constant_override("separation", 14)
	header_panel.add_child(header_h)

	_car_title_lbl = Label.new()
	_car_title_lbl.custom_minimum_size = Vector2(300, 0)
	_car_title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_car_title_lbl.clip_text = true
	_Theme.apply_label(_car_title_lbl, "primary", 20, false, true)
	header_h.add_child(_car_title_lbl)

	var hsep1 := ColorRect.new()
	hsep1.custom_minimum_size = Vector2(1, 52)
	hsep1.color = c_subtle
	header_h.add_child(hsep1)

	_stage_title_lbl = Label.new()
	_stage_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage_title_lbl.clip_text = true
	_Theme.apply_label(_stage_title_lbl, "primary", 19, false, true)
	header_h.add_child(_stage_title_lbl)

	var hsep2 := ColorRect.new()
	hsep2.custom_minimum_size = Vector2(1, 52)
	hsep2.color = c_subtle
	header_h.add_child(hsep2)

	_profile_btn = Button.new()
	_profile_btn.custom_minimum_size = Vector2(290, 54)
	_profile_btn.focus_mode = Control.FOCUS_NONE
	_Theme.apply_tone_button(_profile_btn, "chrome", 13, 12, 6)
	_profile_btn.pressed.connect(func() -> void:
		profile_dropdown_open = not profile_dropdown_open
		if profile_dropdown_open:
			_refresh_setups()
		_sync_ui()
	)
	header_h.add_child(_profile_btn)

	_save_btn = Button.new()
	_save_btn.custom_minimum_size = Vector2(138, 54)
	_save_btn.focus_mode = Control.FOCUS_NONE
	_Theme.apply_tone_button(_save_btn, "chrome", 13, 10, 6)
	_save_btn.pressed.connect(func() -> void: _run_button("save"))
	header_h.add_child(_save_btn)

	# 2. Main panel backdrop (24, 102, 1232, 584)
	var main_panel := Panel.new()
	main_panel.position = Vector2(24, 102)
	main_panel.size = Vector2(1232, 584)
	main_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_panel.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_content, c_border, 1, r))
	_logical_root.add_child(main_panel)

	# Tabs row (UITabBar) + dirty badge
	_tab_bar = _TabBarScene.instantiate()
	_tab_bar.position = Vector2(34, 104)
	_tab_bar.size = Vector2(840, 42)
	_logical_root.add_child(_tab_bar)
	var layout_tabs: Array = _Catalog.get_garage_layout().get("tabs", [])
	var tab_specs: Array = []
	if not layout_tabs.is_empty():
		for t in layout_tabs:
			if t is Dictionary:
				tab_specs.append({"id": str(t.get("id", "")), "label": str(t.get("label", ""))})
	else:
		tab_specs = [
			{"id": "stage", "label": "1 · TRAMO"},
			{"id": "chassis", "label": "2 · CHASIS Y FRENOS"},
			{"id": "powertrain", "label": "3 · MOTOR Y CAJA"},
			{"id": "strategy", "label": "4 · RUEDAS Y CARGA"},
		]
	_tab_bar.set_tabs(tab_specs, 0)
	_tab_bar.tab_selected.connect(func(idx: int, _tid: String) -> void:
		profile_dropdown_open = false
		_set_page(idx)
	)

	_dirty_badge_lbl = Label.new()
	_dirty_badge_lbl.position = Vector2(900, 114)
	_dirty_badge_lbl.size = Vector2(340, 24)
	_dirty_badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_Theme.apply_label(_dirty_badge_lbl, "accent", 11, true, true)
	_logical_root.add_child(_dirty_badge_lbl)

	# 3. Four modular tab views
	_stage_tab = _StageTabScene.instantiate()
	_logical_root.add_child(_stage_tab)

	_chassis_tab = _ChassisTabScene.instantiate()
	_chassis_tab.value_changed.connect(_update_value)
	_chassis_tab.field_selected.connect(func(p: String) -> void:
		selected_field_path = p
		_refresh_footer_notice()
	)
	_logical_root.add_child(_chassis_tab)

	_powertrain_tab = _PowertrainTabScene.instantiate()
	_powertrain_tab.value_changed.connect(_update_value)
	_powertrain_tab.field_selected.connect(func(p: String) -> void:
		selected_field_path = p
		_refresh_footer_notice()
	)
	_logical_root.add_child(_powertrain_tab)

	_strategy_tab = _StrategyTabScene.instantiate()
	_strategy_tab.value_changed.connect(_update_value)
	_strategy_tab.field_selected.connect(func(p: String) -> void:
		selected_field_path = p
		_refresh_footer_notice()
	)
	_strategy_tab.fit_fuel_requested.connect(_fit_fuel_to_stage)
	_strategy_tab.all_compound_selected.connect(func(cid: String) -> void:
		if not _may_service_tires():
			_show_notice("Asistencia bloqueada en tramo: cambia ruedas desde Pausa.", true)
		elif compound_change_allowed:
			_pool_plan_dirty = false
			for corner in ["FL", "FR", "RL", "RR"]:
				draft_wheel_compounds[corner] = cid
			_sync_ui()
	)
	_strategy_tab.corner_compound_cycled.connect(func(corner: String) -> void:
		if not _may_service_tires():
			_show_notice("Asistencia bloqueada en tramo: cambia ruedas desde Pausa.", true)
		elif compound_change_allowed:
			_pool_plan_dirty = false
			var ids := _available_compound_ids()
			if not ids.is_empty():
				var cur := ids.find(str(draft_wheel_compounds.get(corner, "")))
				draft_wheel_compounds[corner] = str(ids[(cur + 1) % ids.size()])
			_sync_ui()
	)
	_strategy_tab.spare_count_changed.connect(func(cnt: int) -> void:
		if not _may_service_tires():
			_show_notice("Asistencia bloqueada en tramo.", true)
		else:
			_pool_plan_dirty = false
			draft_spare_wheels = clampi(cnt, 0, 2)
			_sync_ui()
	)
	_strategy_tab.new_tires_toggled.connect(func() -> void:
		new_tires_service = not new_tires_service
		_sync_ui()
	)
	_logical_root.add_child(_strategy_tab)

	# 4. Footer bar (24, 692, 1232, 88)
	var footer_panel := PanelContainer.new()
	footer_panel.position = Vector2(24, 692)
	footer_panel.size = Vector2(1232, 88)
	footer_panel.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_surf, c_border, 1, r, 20, 14))
	_logical_root.add_child(footer_panel)

	var foot_h := HBoxContainer.new()
	foot_h.add_theme_constant_override("separation", 14)
	footer_panel.add_child(foot_h)

	reset_button = Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "VOLVER A SERIE"
	reset_button.custom_minimum_size = Vector2(174, 46)
	reset_button.focus_mode = Control.FOCUS_NONE
	_Theme.apply_tone_button(reset_button, "chrome", 14, 14, 8)
	reset_button.pressed.connect(func() -> void: _run_button("reset"))
	foot_h.add_child(reset_button)

	_notice_lbl = Label.new()
	_notice_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notice_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notice_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_Theme.apply_label(_notice_lbl, "primary", 10, false, false)
	foot_h.add_child(_notice_lbl)

	cancel_button = Button.new()
	cancel_button.name = "CancelButton"
	cancel_button.text = "CANCELAR"
	cancel_button.custom_minimum_size = Vector2(150, 46)
	cancel_button.focus_mode = Control.FOCUS_NONE
	_Theme.apply_tone_button(cancel_button, "chrome", 14, 14, 8)
	cancel_button.pressed.connect(func() -> void: _run_button("cancel"))
	foot_h.add_child(cancel_button)

	apply_button = Button.new()
	apply_button.name = "ApplyButton"
	apply_button.text = "APLICAR"
	apply_button.custom_minimum_size = Vector2(168, 46)
	apply_button.focus_mode = Control.FOCUS_NONE
	_Theme.apply_tone_button(apply_button, "gold", 15, 16, 8)
	apply_button.pressed.connect(func() -> void: _run_button("apply"))
	foot_h.add_child(apply_button)


func _build_overlays() -> void:
	var r := _Tokens.get_radius("default")
	var c_surf := _Tokens.get_color("bg_surface")
	var c_accent := _Tokens.get_color("accent_rally")

	_overlay_root = Control.new()
	_overlay_root.name = "OverlayRoot"
	_overlay_root.size = LOGICAL_SIZE
	_overlay_root.custom_minimum_size = LOGICAL_SIZE
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay_root)

	# 5. Profile Dropdown Overlay (above StrategyBoard3D)
	_profile_dropdown_panel = PanelContainer.new()
	_profile_dropdown_panel.position = Vector2(780, 88)
	_profile_dropdown_panel.size = Vector2(458, 434)
	_profile_dropdown_panel.visible = false
	_profile_dropdown_panel.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_surf, c_accent, 1, r, 14, 12))
	_overlay_root.add_child(_profile_dropdown_panel)
	var pd_v := VBoxContainer.new()
	pd_v.add_theme_constant_override("separation", 8)
	_profile_dropdown_panel.add_child(pd_v)

	var p_hdr := Label.new()
	p_hdr.text = "BASES RÁPIDAS (1 CLIC)"
	_Theme.apply_label(p_hdr, "accent", 12, false, true)
	pd_v.add_child(p_hdr)

	var preset_grid := GridContainer.new()
	preset_grid.columns = 2
	preset_grid.add_theme_constant_override("h_separation", 8)
	preset_grid.add_theme_constant_override("v_separation", 6)
	pd_v.add_child(preset_grid)
	for preset in _Presenter.get_surface_presets():
		var pb := Button.new()
		pb.text = str(preset.get("title", "BASE"))
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.custom_minimum_size = Vector2(0, 38)
		pb.focus_mode = Control.FOCUS_NONE
		_Theme.apply_tone_button(pb, "chrome", 11, 8, 4)
		var pid := str(preset.get("id", ""))
		pb.pressed.connect(func() -> void:
			_apply_surface_preset(pid)
			profile_dropdown_open = false
			_sync_ui()
		)
		preset_grid.add_child(pb)
	var factory_btn := Button.new()
	factory_btn.text = "DE SERIE (BASE)"
	factory_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	factory_btn.custom_minimum_size = Vector2(0, 38)
	factory_btn.focus_mode = Control.FOCUS_NONE
	_Theme.apply_tone_button(factory_btn, "chrome", 11, 8, 4)
	factory_btn.pressed.connect(func() -> void:
		profile_dropdown_open = false
		_run_button("reset")
	)
	preset_grid.add_child(factory_btn)

	var my_row := HBoxContainer.new()
	pd_v.add_child(my_row)
	var my_lbl := Label.new()
	my_lbl.text = "MIS PERFILES"
	my_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_Theme.apply_label(my_lbl, "primary", 12, false, true)
	my_row.add_child(my_lbl)
	var new_p_btn := Button.new()
	new_p_btn.text = "+ NUEVO PERFIL"
	new_p_btn.focus_mode = Control.FOCUS_NONE
	_Theme.apply_tone_button(new_p_btn, "gold", 11, 10, 4)
	new_p_btn.pressed.connect(func() -> void:
		profile_dropdown_open = false
		_run_button("new")
	)
	my_row.add_child(new_p_btn)

	var p_scroll := ScrollContainer.new()
	p_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pd_v.add_child(p_scroll)
	_profile_list_vbox = VBoxContainer.new()
	_profile_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_list_vbox.add_theme_constant_override("separation", 4)
	p_scroll.add_child(_profile_list_vbox)

	# 6. Modal Overlay (Name / Delete / Discard)
	_modal_overlay = ColorRect.new()
	_modal_overlay.size = LOGICAL_SIZE
	_modal_overlay.color = _Tokens.get_color("bg_overlay")
	_modal_overlay.visible = false
	_overlay_root.add_child(_modal_overlay)
	var m_box := PanelContainer.new()
	m_box.position = Vector2(390, 262)
	m_box.size = Vector2(500, 250)
	m_box.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_surf, c_accent, 1, r, 18, 14))
	_modal_overlay.add_child(m_box)
	var m_v := VBoxContainer.new()
	m_v.add_theme_constant_override("separation", 12)
	m_box.add_child(m_v)
	_modal_title_lbl = Label.new()
	_Theme.apply_label(_modal_title_lbl, "accent", 16, false, true)
	m_v.add_child(_modal_title_lbl)
	_modal_msg_lbl = Label.new()
	_modal_msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_Theme.apply_label(_modal_msg_lbl, "primary", 12, false, false)
	m_v.add_child(_modal_msg_lbl)
	_modal_input = LineEdit.new()
	_modal_input.placeholder_text = "Nombre del reglaje..."
	_modal_input.text_changed.connect(func(t: String) -> void: modal_text = t)
	_modal_input.text_submitted.connect(func(_t: String) -> void: _run_modal("accept"))
	m_v.add_child(_modal_input)
	var m_sp := Control.new()
	m_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m_v.add_child(m_sp)
	var m_btns := HBoxContainer.new()
	m_btns.alignment = BoxContainer.ALIGNMENT_END
	m_btns.add_theme_constant_override("separation", 12)
	m_v.add_child(m_btns)
	var m_cancel := Button.new()
	m_cancel.text = "CANCELAR"
	m_cancel.custom_minimum_size = Vector2(130, 40)
	_Theme.apply_tone_button(m_cancel, "chrome", 14, 12, 6)
	m_cancel.pressed.connect(func() -> void: _run_modal("cancel"))
	m_btns.add_child(m_cancel)
	var m_ok := Button.new()
	m_ok.text = "ACEPTAR"
	m_ok.custom_minimum_size = Vector2(140, 40)
	_Theme.apply_tone_button(m_ok, "gold", 14, 12, 6)
	m_ok.pressed.connect(func() -> void: _run_modal("accept"))
	m_btns.add_child(m_ok)


func _resize_canvas() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_canvas_scale = minf(size.x / LOGICAL_SIZE.x, size.y / LOGICAL_SIZE.y)
	_canvas_offset = (size - LOGICAL_SIZE * _canvas_scale) * 0.5
	if _logical_root != null and is_instance_valid(_logical_root):
		_logical_root.position = _canvas_offset
		_logical_root.scale = Vector2.ONE * _canvas_scale
	if _strategy_board != null and is_instance_valid(_strategy_board):
		_strategy_board.position = _canvas_offset
		_strategy_board.scale = Vector2.ONE * _canvas_scale
	if _overlay_root != null and is_instance_valid(_overlay_root):
		_overlay_root.position = _canvas_offset
		_overlay_root.scale = Vector2.ONE * _canvas_scale


func set_stage_metadata(options: Dictionary) -> void:
	var prev_id := circuit_id
	if options.has("stage_id") and not str(options.get("stage_id", "")).is_empty():
		circuit_id = str(options["stage_id"])
	if circuit_id != prev_id:
		_stage_sectors.clear()
		_stage_terrain.clear()
	if options.has("stage_country") and not str(options.get("stage_country", "")).is_empty():
		circuit_country = str(options["stage_country"])
	if options.has("stage_length_m") and float(options.get("stage_length_m", 0.0)) > 0.0:
		circuit_length_m = float(options["stage_length_m"])
		_stage_length_explicit = true
	if options.has("stage_route_path") and not str(options.get("stage_route_path", "")).is_empty():
		stage_route_path = str(options["stage_route_path"])
	if options.has("stage_weather_label") and not str(options.get("stage_weather_label", "")).is_empty():
		stage_weather_label = str(options["stage_weather_label"])
	if options.has("window_label") and not str(options.get("window_label", "")).is_empty():
		circuit_name = str(options["window_label"])
	if options.has("stage_sectors") and options["stage_sectors"] is Array:
		_stage_sectors = (options["stage_sectors"] as Array).duplicate(true)
	if options.has("stage_terrain") and options["stage_terrain"] is Dictionary:
		_stage_terrain = (options["stage_terrain"] as Dictionary).duplicate(true)
	_briefing_cache_key = ""


func open_garage_for_event(options: Dictionary = {}) -> void:
	mandatory_confirmation = bool(options.get("confirmation_required", false))
	set_stage_metadata(options)
	compound_change_allowed = bool(options.get("compound_change_allowed", true))
	allowed_compound_ids = (options.get("allowed_compound_ids", []) as Array).duplicate()
	var overrides_var: Variant = options.get("compound_label_overrides", {})
	compound_label_overrides = (overrides_var as Dictionary).duplicate(true) if overrides_var is Dictionary else {}
	default_event_compound_id = str(options.get("default_compound_id", RallyTireCompound.DEFAULT_ID))
	event_forecast = (str(options.get("forecast_summary", "")) + "  " + str(options.get("forecast_advice", ""))).strip_edges()
	_opening_for_event = true
	open_garage()
	_opening_for_event = false
	for corner in ["FL", "FR", "RL", "RR"]:
		if not str(draft_wheel_compounds.get(corner, "")) in _available_compound_ids():
			draft_wheel_compounds[corner] = default_event_compound_id
	var initial_tab := str(options.get("initial_tab", ""))
	if initial_tab in ["tires", "strategy"]:
		_set_page(3, false)
	elif initial_tab == "powertrain":
		_set_page(2, false)
	elif initial_tab == "chassis":
		_set_page(1, false)
	elif initial_tab in ["quick", "stage", "tramo"]:
		_set_page(0, false)


func get_confirmed_setup() -> Dictionary:
	return confirmed_setup.duplicate(true)


func open_garage() -> void:
	var music := get_node_or_null("/root/RallyMusic")
	if music != null and music.has_method("on_enter_garage"):
		music.call("on_enter_garage")
	if visible or vehicle == null:
		return
	if not _opening_for_event:
		mandatory_confirmation = false
		compound_change_allowed = true
		allowed_compound_ids.clear()
		compound_label_overrides.clear()
		default_event_compound_id = RallyTireCompound.DEFAULT_ID
		event_forecast = ""
	_restore_tree_paused = get_tree().paused
	_restore_controls_enabled = input_controller.controls_enabled if input_controller != null else true
	opening_values = vehicle.simulation.current_setup_values()
	opening_values["fuel.initial_kg"] = vehicle.simulation.thermal_model.fuel_remaining_litres * vehicle.simulation.mass_model.fuel_density_kg_per_litre
	draft_values = opening_values.duplicate(true)
	vehicle.ensure_tire_inventory()
	_sync_draft_pool_from_inventory()
	opening_wheel_compounds = draft_wheel_compounds.duplicate()
	opening_spares = draft_spare_wheels
	confirmed_setup = {}
	new_tires_service = false
	selected_pool_tire_id = -1
	_pool_plan_dirty = false
	profile_dropdown_open = false
	page = 0
	selected_field_path = ""
	_ensure_stage_route_cache()
	active_setup_id = -1
	active_setup_name = "REGLAJE ACTUAL"
	modal_mode = ""
	modal_text = ""
	notice = ""
	notice_time = 0.0
	notice_is_error = false
	_refresh_setups()
	visible = true
	_resize_canvas()
	set_process_input(true)
	if input_controller != null:
		input_controller.set_controls_enabled(false)
	get_tree().paused = true
	_set_page(0, false)


func close_garage(apply_changes: bool, confirmed_discard: bool = false) -> void:
	if not visible:
		return
	if mandatory_confirmation and not apply_changes:
		_show_notice("Confirma reglajes para continuar.", true)
		return
	if not apply_changes and _has_unapplied_changes() and not confirmed_discard:
		profile_dropdown_open = false
		modal_mode = "discard"
		_sync_ui()
		return
	if apply_changes:
		var setup_to_apply := draft_values.duplicate(true)
		var has_strategy_override := false
		for k in setup_to_apply.keys():
			if str(k).begins_with("strategy."):
				has_strategy_override = true
				if str(k) == "strategy.spare_wheels":
					draft_spare_wheels = int(setup_to_apply[k])
				elif str(k).begins_with("strategy.wheel_compound."):
					draft_wheel_compounds[str(k).trim_prefix("strategy.wheel_compound.")] = str(setup_to_apply[k])
				setup_to_apply.erase(k)
		var tire_modified := (
			has_strategy_override
			or _pool_plan_dirty
			or draft_wheel_compounds != opening_wheel_compounds
			or draft_spare_wheels != opening_spares
			or (not _is_pool_mode() and new_tires_service)
		)
		if tire_modified and not _may_service_tires():
			_show_notice("Asistencia bloqueada en tramo: cambia ruedas desde Pausa.", true)
			return
		var available_ids := _available_compound_ids()
		if tire_modified:
			for corner in ["FL", "FR", "RL", "RR"]:
				if not str(draft_wheel_compounds.get(corner, "")) in available_ids:
					_show_notice("Compuesto no permitido en este evento.", true)
					return
		var applied := vehicle.apply_setup_values(setup_to_apply)
		if not bool(applied.get("ok", false)):
			_show_notice(str(applied.get("error", "Error al aplicar.")), true)
			return
		if tire_modified:
			var svc_result: Variant
			if _is_pool_mode() and _pool_plan_dirty and not has_strategy_override:
				svc_result = vehicle.apply_pool_plan(draft_mounted_ids, draft_spare_ids)
			else:
				svc_result = vehicle.service_tire_inventory(draft_wheel_compounds, draft_spare_wheels, new_tires_service)
			if svc_result is Dictionary and not bool((svc_result as Dictionary).get("ok", true)):
				_show_notice(str((svc_result as Dictionary).get("error", "Error en inventario de neumaticos.")), true)
				return
			_sync_draft_pool_from_inventory()
		confirmed_setup = {
			"compound_id": draft_compound_id,
			"values": draft_values.duplicate(true),
			"wheel_compounds": draft_wheel_compounds.duplicate(true),
		}
	else:
		vehicle.apply_setup_values(opening_values)
	visible = false
	profile_dropdown_open = false
	modal_mode = ""
	set_process_input(false)
	selected_pool_tire_id = -1
	_pool_plan_dirty = false
	if _strategy_board != null and is_instance_valid(_strategy_board):
		_strategy_board.visible = false
		_strategy_board.clear_board()
	get_tree().paused = _restore_tree_paused
	if input_controller != null:
		input_controller.set_controls_enabled(_restore_controls_enabled)
	garage_closed.emit(apply_changes)


func _has_unapplied_changes() -> bool:
	var pool_changed := _pool_plan_dirty and (draft_mounted_ids != opening_mounted_ids or draft_spare_ids != opening_spare_ids)
	var service_flag_dirty := new_tires_service and not _is_pool_mode()
	return draft_values != opening_values or service_flag_dirty or pool_changed or draft_wheel_compounds != opening_wheel_compounds or draft_spare_wheels != opening_spares


func _is_pool_mode() -> bool:
	return is_instance_valid(vehicle) and vehicle.tire_inventory != null and (vehicle.tire_inventory as RallyTireInventory).is_pool_mode()


func _may_service_tires() -> bool:
	if get_parent() != null and get_parent().has_method("may_service_tires"):
		return bool(get_parent().call("may_service_tires"))
	return true


func _sync_draft_pool_from_inventory() -> void:
	draft_mounted_ids.clear()
	draft_spare_ids.clear()
	draft_stock_ids.clear()
	draft_wheel_compounds.clear()
	if not is_instance_valid(vehicle) or vehicle.tire_inventory == null:
		return
	var inv: RallyTireInventory = vehicle.tire_inventory
	for i in mini(4, inv.mounted.size()):
		var td: Dictionary = inv.mounted[i]
		draft_wheel_compounds[["FL", "FR", "RL", "RR"][i]] = str(td.get("compound_id", RallyTireCompound.DEFAULT_ID))
		draft_mounted_ids.append(int(td.get("id", i + 1)))
	for td in inv.spares:
		if td is Dictionary:
			draft_spare_ids.append(int((td as Dictionary).get("id", -1)))
	for td in inv.service_stock:
		if td is Dictionary:
			draft_stock_ids.append(int((td as Dictionary).get("id", -1)))
	opening_mounted_ids = draft_mounted_ids.duplicate()
	opening_spare_ids = draft_spare_ids.duplicate()
	draft_spare_wheels = inv.spares.size()


func _sync_legacy_summary_from_draft_pool() -> void:
	if not is_instance_valid(vehicle) or vehicle.tire_inventory == null:
		return
	var inv: RallyTireInventory = vehicle.tire_inventory
	for i in mini(4, draft_mounted_ids.size()):
		var td := inv.find_tire(draft_mounted_ids[i])
		if not td.is_empty():
			draft_wheel_compounds[["FL", "FR", "RL", "RR"][i]] = str(td.get("compound_id", RallyTireCompound.DEFAULT_ID))
	draft_spare_wheels = draft_spare_ids.size()


func _tire_capacity() -> int:
	if is_instance_valid(vehicle) and vehicle.tire_inventory != null:
		return clampi(vehicle.tire_inventory.capacity, 0, 2)
	return 2


func _sync_strategy_board() -> void:
	if _strategy_board == null or not is_instance_valid(_strategy_board):
		return
	var show_board := visible and page == 3 and modal_mode == "" and _is_pool_mode() and not profile_dropdown_open
	_strategy_board.visible = show_board
	if show_board:
		_strategy_board.position = _canvas_offset
		_strategy_board.scale = Vector2.ONE * _canvas_scale
		_strategy_board.sync_from_garage()


func _sync_ui() -> void:
	if _logical_root == null:
		return
	_car_title_lbl.text = _get_vehicle_display_name()
	_stage_title_lbl.text = circuit_name.to_upper()
	_profile_btn.text = "PERFIL: %s  %s" % [active_setup_name.to_upper(), "▲" if profile_dropdown_open else "▼"]
	_save_btn.text = "GUARDAR" if (selected_setup_id >= 0 or active_setup_id >= 0) else "GUARDAR COMO"
	_tab_bar.select_tab(page, false)

	var changed := _dirty_field_count()
	_dirty_badge_lbl.text = ("%d CAMBIO%s SIN APLICAR" % [changed, "" if changed == 1 else "S"]) if changed > 0 else ""

	_stage_tab.visible = (page == 0)
	_chassis_tab.visible = (page == 1)
	_powertrain_tab.visible = (page == 2)
	_strategy_tab.visible = (page == 3)

	if page == 0:
		_ensure_stage_briefing()
		_ensure_stage_route_cache()
		_stage_tab.populate({
			"sectors": _stage_sectors,
			"terrain": _stage_terrain,
			"route_points": _cached_route_points,
			"altitudes": _cached_profile_altitudes if _cached_profile_altitudes.size() >= 2 else _cached_route_heights,
			"distance_text": _get_stage_distance_text(),
			"weather_text": _get_stage_weather_text(),
			"length_m": _effective_stage_length_m(),
		})
	elif page == 1:
		_chassis_tab.sync_values(draft_values, _setup_field, _format_field, selected_field_path, opening_values)
	elif page == 2:
		_powertrain_tab.sync_values(draft_values, vehicle, _setup_field, _format_field, selected_field_path, opening_values)
	elif page == 3:
		var p_sum := 0.0
		var corner_p: Array = []
		var corner_t: Array = []
		for i in 4:
			var wp := _wheel_pressure(i)
			p_sum += wp
			corner_p.append(wp)
			corner_t.append(_wheel_temperature(i))
		var status_txt := "MALETERO %d/%d (+%d KG) · PARQUE %d" % [draft_spare_ids.size(), _tire_capacity(), draft_spare_ids.size() * 18, draft_stock_ids.size()]
		var status_col := _Tokens.get_color("text_muted")
		if selected_pool_tire_id >= 0:
			status_txt += " · ELIGE DESTINO PARA #%d" % selected_pool_tire_id
			status_col = _Tokens.get_color("accent_rally")
		elif not _may_service_tires():
			status_txt += " · BLOQUEADO EN TRAMO"
			status_col = _Tokens.get_color("status_danger")
		elif not compound_change_allowed:
			status_txt += " · BLOQUEADO EN ESTA PARADA"
			status_col = _Tokens.get_color("status_danger")
		var comp_labels := {}
		for cid in _available_compound_ids():
			comp_labels[cid] = _compound_label(str(cid), false)
		_strategy_tab.sync_view({
			"draft_values": draft_values,
			"opening_values": opening_values,
			"selected_path": selected_field_path,
			"is_pool": _is_pool_mode(),
			"pool_total": vehicle.tire_inventory.total_count() if (_is_pool_mode()) else 10,
			"pool_status_text": status_txt,
			"pool_status_color": status_col,
			"avg_pressure": p_sum * 0.25,
			"can_service": _may_service_tires() and compound_change_allowed,
			"may_service": _may_service_tires(),
			"available_compounds": _available_compound_ids(),
			"wheel_compounds": draft_wheel_compounds,
			"compound_labels": comp_labels,
			"new_tires_service": new_tires_service,
			"draft_spare_wheels": draft_spare_wheels,
			"corner_pressures": corner_p,
			"corner_temps": corner_t,
		}, _setup_field, _format_field)

	if _profile_dropdown_panel != null:
		_profile_dropdown_panel.visible = profile_dropdown_open and modal_mode == ""
		if _profile_dropdown_panel.visible:
			_rebuild_profile_list()

	if _modal_overlay != null:
		_modal_overlay.visible = not modal_mode.is_empty()
		if _modal_overlay.visible:
			_modal_title_lbl.text = "PERFIL" if modal_mode == "name" else "CONFIRMACIÓN"
			_modal_input.visible = (modal_mode == "name")
			if modal_mode == "name":
				_modal_msg_lbl.text = "NOMBRE DEL REGLAJE (ENTER GUARDA · ESC CANCELA)"
				if _modal_input.text != modal_text:
					_modal_input.text = modal_text
				if not _modal_input.has_focus():
					_modal_input.grab_focus()
					_modal_input.caret_column = _modal_input.text.length()
			elif modal_mode == "delete":
				var sname := "seleccionado"
				for row in setup_rows:
					if int(row.get("id", -1)) == selected_setup_id:
						sname = str(row.get("name", sname))
				_modal_msg_lbl.text = "¿ELIMINAR «%s»?\nESTA ACCIÓN NO SE PUEDE DESHACER." % sname.to_upper()
			else:
				_modal_msg_lbl.text = "¿DESCARTAR CAMBIOS SIN APLICAR?\nSE PERDERÁN LOS AJUSTES DE ESTA SESIÓN."

	_refresh_footer_notice()
	_sync_strategy_board()


func _refresh_footer_notice() -> void:
	if _notice_lbl == null:
		return
	if notice_time > 0.0 and not notice.is_empty():
		_notice_lbl.text = notice.to_upper()
		_notice_lbl.add_theme_color_override("font_color", _Tokens.get_color("status_danger") if notice_is_error else _Tokens.get_color("accent_rally"))
	else:
		_notice_lbl.text = _Presenter.field_description(selected_field_path)
		_notice_lbl.add_theme_color_override("font_color", _Tokens.get_color("text_primary"))


func _rebuild_profile_list() -> void:
	for child in _profile_list_vbox.get_children():
		child.queue_free()
	if setup_rows.is_empty():
		var empty_l := Label.new()
		empty_l.text = "SIN PERFILES GUARDADOS PARA ESTE TRAMO"
		empty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_Theme.apply_label(empty_l, "muted", 10, false, false)
		_profile_list_vbox.add_child(empty_l)
		return
	for i in setup_rows.size():
		var row: Dictionary = setup_rows[i]
		var row_id := int(row.get("id", -1))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		_profile_list_vbox.add_child(h)
		var load_b := Button.new()
		load_b.text = str(row.get("name", "Reglaje"))
		load_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		load_b.focus_mode = Control.FOCUS_NONE
		_Theme.apply_tone_button(load_b, "accent" if row_id == active_setup_id else "chrome", 11, 8, 4)
		var idx: int = i
		load_b.pressed.connect(func() -> void:
			selected_setup_index = idx
			selected_setup_id = row_id
			_load_selected_setup()
			profile_dropdown_open = false
			_sync_ui()
		)
		h.add_child(load_b)
		var upd_b := Button.new()
		upd_b.text = "ACT."
		upd_b.focus_mode = Control.FOCUS_NONE
		_Theme.apply_tone_button(upd_b, "chrome", 10, 6, 4)
		upd_b.pressed.connect(func() -> void:
			selected_setup_index = idx
			selected_setup_id = row_id
			_save_selected_setup()
			profile_dropdown_open = false
			_sync_ui()
		)
		h.add_child(upd_b)
		var del_b := Button.new()
		del_b.text = "×"
		del_b.focus_mode = Control.FOCUS_NONE
		_Theme.apply_tone_button(del_b, "danger", 11, 6, 4)
		del_b.pressed.connect(func() -> void:
			selected_setup_index = idx
			selected_setup_id = row_id
			profile_dropdown_open = false
			_begin_delete_setup()
		)
		h.add_child(del_b)


# =============================================================================
# POOL INTERACTIONS (3D BOARD & CONTRACT API)
# =============================================================================

func _draft_pool_tire_id(slot_kind: String, slot_index: int) -> int:
	match slot_kind:
		"mounted":
			return draft_mounted_ids[slot_index] if (slot_index >= 0 and slot_index < draft_mounted_ids.size()) else -1
		"spare":
			return draft_spare_ids[slot_index] if (slot_index >= 0 and slot_index < draft_spare_ids.size()) else -1
		"stock":
			return draft_stock_ids[slot_index] if (slot_index >= 0 and slot_index < draft_stock_ids.size()) else -1
	return -1


func can_pool_drop_from_id(src_id: int, slot_kind: String, slot_index: int) -> Dictionary:
	if not _is_pool_mode():
		return {"ok": false, "error": ""}
	if not _may_service_tires():
		return {"ok": false, "error": "Asistencia bloqueada en tramo: intercambia ruedas desde Pausa."}
	if not compound_change_allowed:
		return {"ok": false, "error": "Cambio de neumaticos bloqueado en esta parada."}
	if src_id <= 0:
		return {"ok": false, "error": ""}
	var src_loc := _find_draft_pool_loc(src_id)
	if src_loc.is_empty():
		return {"ok": false, "error": ""}
	var target_id := _draft_pool_tire_id(slot_kind, slot_index)
	if target_id == src_id:
		return {"ok": false, "error": ""}
	var src_kind := str(src_loc["kind"])
	var inv: RallyTireInventory = vehicle.tire_inventory
	var src_td := inv.find_tire(src_id)
	var dst_td := inv.find_tire(target_id) if target_id > 0 else {}
	var allowed_ids := _available_compound_ids()

	if slot_kind == "mounted":
		if slot_index < 0 or slot_index >= draft_mounted_ids.size():
			return {"ok": false, "error": ""}
		if inv.is_carcass_destroyed(src_td):
			return {"ok": false, "error": "Rueda #%d destalonada: no se puede montar." % src_id}
		if not str(src_td.get("compound_id", "")) in allowed_ids:
			return {"ok": false, "error": "Compuesto no permitido en este evento."}
	elif slot_kind == "spare":
		var cap := _tire_capacity()
		if slot_index < 0 or slot_index >= cap:
			return {"ok": false, "error": ""}
		if slot_index >= draft_spare_ids.size():
			if src_kind == "mounted":
				return {"ok": false, "error": "El coche siempre debe llevar 4 ruedas montadas."}
		elif src_kind == "mounted" and not dst_td.is_empty():
			if inv.is_carcass_destroyed(dst_td):
				return {"ok": false, "error": "Rueda #%d destalonada: no se puede montar." % target_id}
			if not str(dst_td.get("compound_id", "")) in allowed_ids:
				return {"ok": false, "error": "Compuesto no permitido en este evento."}
	elif slot_kind == "stock":
		if target_id < 0:
			return {"ok": false, "error": ""}
		if src_kind == "mounted" and not dst_td.is_empty():
			if inv.is_carcass_destroyed(dst_td):
				return {"ok": false, "error": "Rueda #%d destalonada: no se puede montar." % target_id}
			if not str(dst_td.get("compound_id", "")) in allowed_ids:
				return {"ok": false, "error": "Compuesto no permitido en este evento."}
	else:
		return {"ok": false, "error": ""}
	return {"ok": true, "error": ""}


func perform_pool_drop(src_id: int, slot_kind: String, slot_index: int) -> bool:
	var verdict := can_pool_drop_from_id(src_id, slot_kind, slot_index)
	if not bool(verdict.get("ok", false)):
		var err := str(verdict.get("error", ""))
		if not err.is_empty():
			_show_notice(err, true)
		return false
	var src_loc := _find_draft_pool_loc(src_id)
	var src_kind := str(src_loc["kind"])
	var src_idx := int(src_loc["index"])
	var target_id := _draft_pool_tire_id(slot_kind, slot_index)
	if slot_kind == "mounted":
		var displaced_id := draft_mounted_ids[slot_index]
		draft_mounted_ids[slot_index] = src_id
		_assign_draft_pool_loc(src_kind, src_idx, displaced_id)
	elif slot_kind == "spare":
		if slot_index >= draft_spare_ids.size():
			_remove_draft_pool_loc(src_kind, src_idx)
			draft_spare_ids.append(src_id)
		else:
			var prev_spare := draft_spare_ids[slot_index]
			draft_spare_ids[slot_index] = src_id
			_assign_draft_pool_loc(src_kind, src_idx, prev_spare)
	elif slot_kind == "stock" and target_id >= 0:
		var prev_stock := draft_stock_ids[slot_index]
		draft_stock_ids[slot_index] = src_id
		_assign_draft_pool_loc(src_kind, src_idx, prev_stock)
	_pool_plan_dirty = true
	selected_pool_tire_id = -1
	_sync_legacy_summary_from_draft_pool()
	_refresh_strategy_nav_paths()
	_sync_ui()
	return true


func _pool_interact(slot_kind: String, slot_index: int) -> void:
	if not _is_pool_mode():
		return
	if not _may_service_tires():
		_show_notice("Asistencia bloqueada en tramo: intercambia ruedas desde Pausa.", true)
		return
	if not compound_change_allowed:
		_show_notice("Cambio de neumaticos bloqueado en esta parada.", true)
		return
	var target_id := _draft_pool_tire_id(slot_kind, slot_index)
	if selected_pool_tire_id < 0:
		if target_id < 0:
			_show_notice("Selecciona primero una rueda del parque o montaje.")
			return
		selected_pool_tire_id = target_id
		_sync_ui()
		return
	if target_id == selected_pool_tire_id:
		selected_pool_tire_id = -1
		_sync_ui()
		return
	if _find_draft_pool_loc(selected_pool_tire_id).is_empty():
		selected_pool_tire_id = -1
		_sync_ui()
		return
	perform_pool_drop(selected_pool_tire_id, slot_kind, slot_index)


func _unload_spare_slot(spare_index: int) -> void:
	if not _is_pool_mode():
		return
	if not _may_service_tires():
		_show_notice("Asistencia bloqueada en tramo.", true)
		return
	if not compound_change_allowed:
		_show_notice("Cambio de neumaticos bloqueado en esta parada.", true)
		return
	if spare_index < 0 or spare_index >= draft_spare_ids.size():
		return
	var tid := draft_spare_ids[spare_index]
	draft_spare_ids.remove_at(spare_index)
	draft_stock_ids.append(tid)
	if selected_pool_tire_id == tid:
		selected_pool_tire_id = -1
	_pool_plan_dirty = true
	_sync_legacy_summary_from_draft_pool()
	_refresh_strategy_nav_paths()
	_sync_ui()


func _find_draft_pool_loc(tid: int) -> Dictionary:
	var idx := draft_mounted_ids.find(tid)
	if idx >= 0:
		return {"kind": "mounted", "index": idx}
	idx = draft_spare_ids.find(tid)
	if idx >= 0:
		return {"kind": "spare", "index": idx}
	idx = draft_stock_ids.find(tid)
	if idx >= 0:
		return {"kind": "stock", "index": idx}
	return {}


func _assign_draft_pool_loc(kind: String, index: int, tid: int) -> void:
	match kind:
		"mounted": draft_mounted_ids[index] = tid
		"spare": draft_spare_ids[index] = tid
		"stock": draft_stock_ids[index] = tid


func _remove_draft_pool_loc(kind: String, index: int) -> void:
	match kind:
		"spare": draft_spare_ids.remove_at(index)
		"stock": draft_stock_ids.remove_at(index)


func _refresh_strategy_nav_paths() -> void:
	if page != 3:
		return
	var prev := selected_field_path
	_page_field_paths.clear()
	for p in STRATEGY_PATHS:
		_page_field_paths.append(p)
	if _is_pool_mode():
		for s in _tire_capacity():
			_page_field_paths.append("spare:%d" % s)
		for k in draft_stock_ids.size():
			_page_field_paths.append("stock:%d" % k)
	else:
		_page_field_paths.append("service")
		_page_field_paths.append("spares")
	for c in 4:
		_page_field_paths.append("mounted:%d" % c)
	if not _page_field_paths.has(prev):
		selected_field_path = _page_field_paths[0]


# =============================================================================
# INPUT & NAVIGATION
# =============================================================================

func _input(event: InputEvent) -> void:
	if not visible:
		if (
			event is InputEventKey and event.pressed and not event.echo
			and event.ctrl_pressed and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]
			and is_instance_valid(vehicle) and not get_tree().paused
		):
			vehicle.simulation.adjust_live_tire_pressure(5.0 if event.keycode == KEY_PAGEUP else -5.0)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if modal_mode == "name" and _modal_input.has_focus():
			if ke.keycode == KEY_ESCAPE:
				modal_mode = ""
				_sync_ui()
				get_viewport().set_input_as_handled()
			return
		_handle_key(ke)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		_handle_pad_button(event as InputEventJoypadButton)
		get_viewport().set_input_as_handled()


func _handle_key(event: InputEventKey) -> void:
	if modal_mode != "":
		if event.keycode == KEY_ESCAPE:
			modal_mode = ""
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_run_modal("accept")
		_sync_ui()
		return
	if profile_dropdown_open and event.keycode == KEY_ESCAPE:
		profile_dropdown_open = false
		_sync_ui()
		return
	match event.keycode:
		KEY_ESCAPE: close_garage(false)
		KEY_F5: close_garage(true)
		KEY_PAGEUP: _set_page(page - 1)
		KEY_PAGEDOWN, KEY_TAB: _set_page(page + 1)
		KEY_LEFT, KEY_Q: _adjust_selected(-1.0)
		KEY_RIGHT, KEY_E: _adjust_selected(1.0)
		KEY_UP, KEY_W: _navigate_selection(-1)
		KEY_DOWN, KEY_S: _navigate_selection(1)
		KEY_R:
			if not selected_field_path.is_empty():
				_reset_single_field(selected_field_path)
		KEY_X:
			if page == 3 and _is_pool_mode() and selected_field_path.begins_with("spare:"):
				_unload_spare_slot(int(selected_field_path.trim_prefix("spare:")))
			elif selected_pool_tire_id >= 0:
				selected_pool_tire_id = -1
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_confirm_selection()
	_sync_ui()


func _handle_pad_button(event: InputEventJoypadButton) -> void:
	if modal_mode != "":
		if event.button_index == JOY_BUTTON_A:
			_run_modal("accept")
		elif event.button_index in [JOY_BUTTON_B, JOY_BUTTON_START]:
			modal_mode = ""
		_sync_ui()
		return
	match event.button_index:
		JOY_BUTTON_Y: close_garage(true)
		JOY_BUTTON_B, JOY_BUTTON_START: close_garage(false)
		JOY_BUTTON_A: _confirm_selection()
		JOY_BUTTON_X:
			if page == 3 and _is_pool_mode() and selected_field_path.begins_with("spare:"):
				_unload_spare_slot(int(selected_field_path.trim_prefix("spare:")))
			elif selected_pool_tire_id >= 0:
				selected_pool_tire_id = -1
			elif not selected_field_path.is_empty():
				_reset_single_field(selected_field_path)
		JOY_BUTTON_DPAD_UP: _navigate_selection(-1)
		JOY_BUTTON_DPAD_DOWN: _navigate_selection(1)
		JOY_BUTTON_DPAD_LEFT: _adjust_selected(-1.0)
		JOY_BUTTON_DPAD_RIGHT: _adjust_selected(1.0)
		JOY_BUTTON_LEFT_SHOULDER: _set_page(page - 1)
		JOY_BUTTON_RIGHT_SHOULDER: _set_page(page + 1)
	_sync_ui()


func _set_page(next_page: int, play_sound: bool = true) -> void:
	var previous_page := page
	page = posmod(next_page, 4)
	if play_sound and page != previous_page:
		var audio := get_node_or_null("/root/UIButtonAudio")
		if audio != null:
			audio.call("play_tab_click")
	_page_field_paths.clear()
	var source: Array[String] = []
	match page:
		1: source = CHASSIS_PATHS
		2: source = POWERTRAIN_PATHS
		3: source = STRATEGY_PATHS
	for path in source:
		if not _page_field_paths.has(path):
			_page_field_paths.append(path)
	if page == 3:
		_refresh_strategy_nav_paths()
	if not _page_field_paths.has(selected_field_path):
		selected_field_path = _page_field_paths[0] if not _page_field_paths.is_empty() else ""
	_sync_ui()


func _navigate_selection(direction: int) -> void:
	if _page_field_paths.is_empty():
		return
	var nav_paths := _active_nav_paths()
	if nav_paths.is_empty():
		return
	var index := nav_paths.find(selected_field_path)
	selected_field_path = nav_paths[0] if index < 0 else nav_paths[posmod(index + direction, nav_paths.size())]


func _active_nav_paths() -> Array[String]:
	if page != 2 or bool(draft_values.get("garage.lsd", 0.0)):
		return _page_field_paths
	var filtered: Array[String] = []
	for p in _page_field_paths:
		if not p.begins_with(RallySetupCatalog.DIFFERENTIAL_PREFIX):
			filtered.append(p)
	return filtered


func _adjust_selected(direction: float) -> void:
	if selected_field_path.is_empty() and not _page_field_paths.is_empty():
		selected_field_path = _page_field_paths[0]
	var effective_dir := -direction if (selected_field_path in INVERTED_DISCRETE_PATHS) else direction
	_adjust_field(selected_field_path, effective_dir)


func _adjust_field(path: String, direction: float) -> void:
	if path.begins_with(RallySetupCatalog.DIFFERENTIAL_PREFIX) and not bool(draft_values.get("garage.lsd", 0.0)):
		return
	var field := _setup_field(path)
	if field.is_empty():
		return
	_update_value(path, float(draft_values.get(path, 0.0)) + float(field.step) * direction)


func _setup_field(path: String) -> Dictionary:
	if vehicle == null:
		return RallySetupCatalog.field_for_path(path)
	return RallySetupCatalog.field_for_vehicle(path, vehicle.simulation.setup_design_values)


func _update_value(path: String, value: float) -> void:
	var field := _setup_field(path)
	if field.is_empty():
		return
	var next_value := RallySetupCatalog.clamp_field(field, value, vehicle.simulation.setup_design_values)
	if is_equal_approx(next_value, float(draft_values.get(path, INF))):
		return
	var next := draft_values.duplicate()
	next[path] = next_value
	var result := vehicle.apply_setup_values(next)
	if not bool(result.get("ok", false)):
		_show_notice(str(result.get("error", "Error de ajuste.")), true)
	else:
		draft_values = result.values
		if path == "garage.lsd" and not bool(draft_values.get("garage.lsd", 0.0)) and selected_field_path.begins_with(RallySetupCatalog.DIFFERENTIAL_PREFIX):
			selected_field_path = "garage.lsd"
	_sync_ui()


func _reset_single_field(path: String) -> void:
	if not opening_values.has(path):
		return
	var base_val := float(opening_values[path])
	if is_equal_approx(base_val, float(draft_values.get(path, base_val))):
		return
	_update_value(path, base_val)
	_show_notice("Valor inicial restaurado.")


func _fit_fuel_to_stage() -> void:
	var stage_km := maxf(_effective_stage_length_m() / 1000.0, 1.0)
	var needed_litres := maxf(stage_km * ESTIMATED_FUEL_BURN_L_PER_KM * 1.20, 8.0)
	var target_kg := needed_litres * _fuel_density()
	_update_value("fuel.initial_kg", target_kg)
	_show_notice("Combustible ajustado al tramo (+20%% margen): %.1f L" % (float(draft_values.get("fuel.initial_kg", target_kg)) / _fuel_density()))


func _apply_surface_preset(preset_id: String) -> void:
	if not is_instance_valid(vehicle):
		return
	for p in _Presenter.get_surface_presets():
		if str(p.get("id", "")) == preset_id:
			var next := draft_values.duplicate(true)
			var vals: Dictionary = p.get("values", {})
			for k in vals:
				var f := _setup_field(str(k))
				if not f.is_empty():
					next[str(k)] = RallySetupCatalog.clamp_field(f, float(vals[k]), vehicle.simulation.setup_design_values)
			var applied := vehicle.apply_setup_values(next)
			if bool(applied.get("ok", false)):
				draft_values = applied.values
				active_setup_id = -1
				active_setup_name = str(p.get("title", "BASE")).replace("BASE ", "")
				_show_notice("Aplicada %s" % str(p.get("title", "")).to_lower())
			else:
				_show_notice(str(applied.get("error", "Error al aplicar base.")), true)
			return


func _confirm_selection() -> void:
	if page == 3 and _is_pool_mode():
		if selected_field_path.begins_with("mounted:"):
			_pool_interact("mounted", int(selected_field_path.trim_prefix("mounted:")))
		elif selected_field_path.begins_with("spare:"):
			_pool_interact("spare", int(selected_field_path.trim_prefix("spare:")))
		elif selected_field_path.begins_with("stock:"):
			_pool_interact("stock", int(selected_field_path.trim_prefix("stock:")))
	elif page == 3 and not _is_pool_mode():
		if selected_field_path == "service" and _may_service_tires():
			new_tires_service = not new_tires_service
		elif selected_field_path == "spares" and _may_service_tires():
			draft_spare_wheels = (draft_spare_wheels + 1) % 3
	elif selected_field_path == "garage.lsd":
		_update_value("garage.lsd", 0.0 if bool(draft_values.get("garage.lsd", 0.0)) else 1.0)


func _run_button(action: String) -> void:
	match action:
		"reset":
			draft_values = vehicle.simulation.setup_design_values.duplicate(true)
			active_setup_id = -1
			active_setup_name = "BASE"
			var restored := vehicle.apply_setup_values(draft_values)
			if bool(restored.get("ok", false)):
				draft_values = restored.values
				_show_notice("Reglaje base restaurado.")
			else:
				_show_notice(str(restored.get("error", "Error al restaurar.")), true)
		"cancel":
			close_garage(false)
			return
		"apply":
			close_garage(true)
			return
		"new":
			modal_mode = "name"
			modal_text = ""
		"save":
			_save_selected_setup()
		"load":
			_load_selected_setup()
		"delete":
			_begin_delete_setup()
	_sync_ui()


func _run_modal(action: String) -> void:
	if action == "accept":
		match modal_mode:
			"name": _commit_new_setup()
			"delete": _delete_selected_setup()
			"discard":
				close_garage(false, true)
				return
	else:
		modal_mode = ""
	_sync_ui()


# =============================================================================
# SQLITE SETUP STORE
# =============================================================================

func _refresh_setups() -> void:
	if not database_ready or vehicle == null:
		setup_rows.clear()
		return
	var result := database.list_setups(_database_context())
	if not bool(result.get("ok", false)):
		setup_rows.clear()
		return
	setup_rows.clear()
	for row in result.get("rows", []):
		if row is Dictionary:
			setup_rows.append(row)
	if selected_setup_index >= setup_rows.size():
		selected_setup_index = maxi(setup_rows.size() - 1, 0)
	selected_setup_id = int(setup_rows[selected_setup_index].get("id", -1)) if not setup_rows.is_empty() else -1


func _build_savable_setup_values() -> Dictionary:
	var payload := draft_values.duplicate(true)
	for corner in ["FL", "FR", "RL", "RR"]:
		payload["strategy.wheel_compound." + corner] = str(draft_wheel_compounds.get(corner, RallyTireCompound.DEFAULT_ID))
	payload["strategy.spare_wheels"] = draft_spare_wheels
	return payload


func _save_selected_setup() -> void:
	if not database_ready:
		_show_notice("SQLite no disponible", true)
		return
	var target_id := selected_setup_id
	var target_name := active_setup_name
	if active_setup_id >= 0 and target_id < 0:
		target_id = active_setup_id
	if target_id >= 0:
		for row in setup_rows:
			if int(row.get("id", -1)) == target_id:
				target_name = str(row.get("name", target_name))
				break
	if target_id < 0:
		modal_mode = "name"
		modal_text = active_setup_name if not (active_setup_name in ["REGLAJE ACTUAL", "BASE", "DE SERIE", "GRAVA / MIXTO", "ASFALTO LISO", "LLUVIA / BACHES"]) else ""
		return
	var result := database.update_setup(_database_context(), target_id, target_name, _build_savable_setup_values())
	if bool(result.get("ok", false)):
		active_setup_id = target_id
		active_setup_name = target_name
		_show_notice("Guardado: " + target_name)
		_refresh_setups()
	else:
		_show_notice(str(result.get("error", "Error al guardar.")), true)


func _commit_new_setup() -> void:
	var setup_name := modal_text.strip_edges()
	if setup_name.is_empty():
		_show_notice("Ingresa un nombre.", true)
		return
	if not database_ready:
		modal_mode = ""
		_show_notice("SQLite no disponible", true)
		return
	var result := database.create_setup(_database_context(), setup_name, _build_savable_setup_values())
	modal_mode = ""
	if bool(result.get("ok", false)):
		active_setup_id = int(result.get("id", -1))
		active_setup_name = setup_name
		_show_notice("Creado: " + setup_name)
		_refresh_setups()
		for index in setup_rows.size():
			if int(setup_rows[index].get("id", -1)) == active_setup_id:
				selected_setup_index = index
				selected_setup_id = active_setup_id
				break
	else:
		_show_notice(str(result.get("error", "Error al crear.")), true)


func _load_selected_setup() -> void:
	if selected_setup_id < 0:
		_show_notice("Selecciona un perfil.", true)
		return
	var result := database.load_setup(_database_context(), selected_setup_id)
	if not bool(result.get("ok", false)):
		_show_notice(str(result.get("error", "Error al cargar.")), true)
		return
	var raw_stored: Dictionary = (result as Dictionary).get("values", {})
	var stored := raw_stored.duplicate(true)
	var stored_compounds: Dictionary = {}
	var has_stored_spares := stored.has("strategy.spare_wheels")
	var stored_spares := int(stored.get("strategy.spare_wheels", draft_spare_wheels))
	if has_stored_spares:
		stored.erase("strategy.spare_wheels")
	for k in stored.keys():
		if str(k).begins_with("strategy.wheel_compound."):
			stored_compounds[str(k).trim_prefix("strategy.wheel_compound.")] = str(stored[k])
			stored.erase(k)
	var available_ids := _available_compound_ids()
	for corner in stored_compounds:
		if not str(stored_compounds[corner]) in available_ids:
			_show_notice("Compuesto no permitido en este evento.", true)
			return
	var applied := vehicle.apply_setup_values(stored)
	if not bool(applied.get("ok", false)):
		_show_notice(str(applied.get("error", "Error al aplicar.")), true)
		return
	if not stored_compounds.is_empty():
		if not _may_service_tires() or not compound_change_allowed:
			_show_notice("Reglaje mecanico cargado; estrategia de ruedas bloqueada aqui.")
		else:
			for corner in stored_compounds:
				draft_wheel_compounds[corner] = stored_compounds[corner]
			_pool_plan_dirty = false
	if has_stored_spares and _may_service_tires():
		draft_spare_wheels = clampi(stored_spares, 0, _tire_capacity())
		_pool_plan_dirty = false
	draft_values = applied.values
	active_setup_id = selected_setup_id
	active_setup_name = str(result.get("name", "REGLAJE"))
	if not (not stored_compounds.is_empty() and (not _may_service_tires() or not compound_change_allowed)):
		_show_notice("Cargado: " + active_setup_name)


func _begin_delete_setup() -> void:
	if selected_setup_id < 0:
		_show_notice("Selecciona un perfil.", true)
		return
	modal_mode = "delete"
	_sync_ui()


func _delete_selected_setup() -> void:
	var result := database.delete_setup(_database_context(), selected_setup_id)
	modal_mode = ""
	if bool(result.get("ok", false)):
		if active_setup_id == selected_setup_id:
			active_setup_id = -1
			active_setup_name = "REGLAJE ACTUAL"
		_show_notice("Eliminado.")
		_refresh_setups()
	else:
		_show_notice(str(result.get("error", "Error al eliminar.")), true)


func _database_context() -> Dictionary:
	return {
		"circuit_id": circuit_id,
		"team_id": team_id,
		"car_id": str(vehicle.rally_profile.get("profile_id", "ford_escort_rs2000_1971")),
		"physics_backend": RallySetupDatabase.PHYSICS_BACKEND,
		"base_profile_sha256": "",
		"mode": mode,
	}


func _show_notice(message: String, is_error: bool = false) -> void:
	notice = message
	notice_time = 4.0
	notice_is_error = is_error
	if is_error:
		push_warning("Rally garage: " + message)
	_refresh_footer_notice()


func _process(delta: float) -> void:
	if notice_time > 0.0:
		notice_time = maxf(notice_time - delta, 0.0)
		if notice_time == 0.0:
			_refresh_footer_notice()


# =============================================================================
# STAGE BRIEFING, ROUTE & HELPER ACCESSORS (DELEGATED TO PRESENTER)
# =============================================================================

func _get_vehicle_display_name() -> String:
	return _Presenter.resolve_vehicle_display_name(vehicle, team_name)


func _ensure_stage_route_cache() -> void:
	var loaded := _Presenter.load_stage_route(stage_route_path, circuit_id)
	var key := str(loaded.get("key", ""))
	if key == _cached_route_key and not _cached_route_points.is_empty():
		return
	_cached_route_key = key
	_cached_route_points = loaded.get("points", PackedVector2Array())
	_cached_route_heights = loaded.get("heights", PackedFloat32Array())
	_cached_profile_altitudes = loaded.get("profile_altitudes", PackedFloat32Array())
	_cached_route_length_m = float(loaded.get("length_m", 0.0))


func _ensure_stage_briefing() -> void:
	var sid := _Presenter.normalize_stage_id(circuit_id)
	var key := "%s|%s|%0.1f" % [sid, stage_weather_label, _effective_stage_length_m()]
	if key == _briefing_cache_key and _stage_sectors.size() == 4 and not _stage_terrain.is_empty():
		return
	_briefing_cache_key = key
	var total_m := maxf(_effective_stage_length_m(), 500.0)
	var stage_cfg_path := "res://data/competition/stages/%s.json" % sid
	var stage_cfg: Dictionary = {}
	if not sid.is_empty() and FileAccess.file_exists(stage_cfg_path):
		var p_cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(stage_cfg_path))
		if p_cfg is Dictionary:
			stage_cfg = p_cfg as Dictionary
	var raw_surface := str(stage_cfg.get("surface", "gravel_mud")).to_lower()
	var is_asphalt := raw_surface == "asphalt"
	var parent_node := get_parent()
	var ew: Variant = parent_node.get("event_weather") if parent_node != null else null
	if _stage_sectors.is_empty() and ew != null and ew.has_method("sector_summary"):
		var ew_sectors: Array = ew.call("sector_summary") as Array
		if not ew_sectors.is_empty():
			_stage_sectors = ew_sectors.duplicate(true)
	if _stage_sectors.size() != 4:
		_stage_sectors.clear()
		var w_low := _get_stage_weather_text().to_lower()
		var is_sweden := sid.begins_with("sweden_") or sid == "russia_stage7" or sid == "russia_stage8"
		var is_rain := "lluvia" in w_low or "rain" in w_low or "tormenta" in w_low or "llovizna" in w_low
		var is_cloud := "nubl" in w_low or "cubiert" in w_low or "niebla" in w_low
		var base_temp := -3.0 if is_sweden else (13.0 if is_rain else 18.0)
		var wetness_cfg := float(stage_cfg.get("wetness", 0.25))
		var sec_lens_v: Variant = stage_cfg.get("sector_lengths_km", [])
		var sec_bounds: Array[float] = [0.0, total_m * 0.25, total_m * 0.50, total_m * 0.75, total_m]
		if sec_lens_v is Array and (sec_lens_v as Array).size() == 4:
			var acc := 0.0
			var ok_lens := true
			for k in 4:
				var km := float((sec_lens_v as Array)[k])
				if km <= 0.01:
					ok_lens = false
					break
				acc += km * 1000.0
				sec_bounds[k + 1] = acc
			if ok_lens and acc > 10.0:
				sec_bounds[4] = maxf(acc, total_m)
		for si in 4:
			_stage_sectors.append({
				"sector_index": si,
				"start_m": sec_bounds[si],
				"end_m": sec_bounds[si + 1],
				"air_c": base_temp - float(si) * 0.3,
				"ground_c": base_temp + (1.5 if not is_rain and not is_sweden else 0.0),
				"cloud_cover": 0.85 if is_rain else (0.7 if is_cloud else 0.22),
				"rain_mm_h": (1.6 if si in [1, 2] else 0.6) if is_rain else 0.0,
				"snow_mm_h": 0.4 if is_sweden else 0.0,
				"water_mm": (0.8 + wetness_cfg) if is_rain else 0.0,
				"snow_mm": 2.5 if is_sweden else 0.0,
				"ice_mm": 0.5 if (is_sweden and (si == 1 or si == 2)) else 0.0,
			})
	if _stage_terrain.is_empty():
		var roughness := float(stage_cfg.get("roughness", 0.35))
		var wetness := float(stage_cfg.get("wetness", 0.2))
		var water_cfg := float(stage_cfg.get("water", 0.1))
		var w_low := _get_stage_weather_text().to_lower()
		var is_sweden := sid.begins_with("sweden_") or sid == "russia_stage7" or sid == "russia_stage8"
		var is_rain := "lluvia" in w_low or "rain" in w_low or "llovizna" in w_low
		_stage_terrain = {
			"source": "stage_data",
			"is_asphalt": is_asphalt,
			"surface_raw": raw_surface,
			"loose_gravel_avg": clampf(0.18 + roughness * 0.35, 0.10, 0.50) if not is_asphalt else 0.0,
			"mud_avg": clampf((wetness * 0.45 + water_cfg * 0.35) * (1.4 if is_rain else 0.5), 0.0, 0.42) if not is_asphalt else 0.0,
			"water_avg": clampf((wetness * 0.5 + (0.35 if is_rain else 0.0)), 0.0, 0.75) if is_asphalt else 0.0,
			"snow_avg": 0.72 if is_sweden else 0.0,
			"ice_avg": 0.18 if (is_sweden or sid == "russia_stage8") else 0.0,
		}


func _get_stage_weather_text() -> String:
	var raw := stage_weather_label.strip_edges()
	return raw.to_upper() if not raw.is_empty() else "SOLEADO"


func _effective_stage_length_m() -> float:
	if (_stage_length_explicit or absf(circuit_length_m - 5500.0) > 1.0) and circuit_length_m > 0.0:
		return circuit_length_m
	if _cached_route_length_m > 0.0:
		return _cached_route_length_m
	return circuit_length_m


func _get_stage_distance_text() -> String:
	return "%0.1f KM" % (maxf(_effective_stage_length_m(), 0.0) / 1000.0)


func _available_compound_ids() -> Array:
	var ids := RallyTireCompound.compound_ids(RallyTireCompound.load_catalog())
	if allowed_compound_ids.is_empty():
		return ids
	var ordered: Array = []
	for cid in allowed_compound_ids:
		if cid in ids and not ordered.has(cid):
			ordered.append(cid)
	return ordered


func _compound_label(compound_id: String, short: bool = false) -> String:
	return RallyTireCompound.compound_label(compound_id, short, compound_label_overrides)


func _fuel_density() -> float:
	if is_instance_valid(vehicle) and vehicle.simulation != null:
		return maxf(vehicle.simulation.mass_model.fuel_density_kg_per_litre, 0.1)
	return 0.74


func _format_field(field: Dictionary, path: String) -> String:
	return _Presenter.format_field(field, path, draft_values, _fuel_density())


func _wheel_state(index: int) -> Dictionary:
	return vehicle.get_tire_thermal_state(index) if is_instance_valid(vehicle) else {}


func _wheel_pressure(index: int) -> float:
	return float(_wheel_state(index).get("pressure_kpa_gauge", 0.0))


func _wheel_temperature(index: int) -> float:
	return float(_wheel_state(index).get("tread_c", 0.0))


func _tire_status_info(inv: RallyTireInventory, tire_info: Dictionary) -> Dictionary:
	var c_dim := _Tokens.get_color("text_dim")
	var c_danger := _Tokens.get_color("status_danger")
	var c_gold := _Tokens.get_color("accent_rally")
	if inv == null or tire_info.is_empty():
		return {"tag": "OK", "color": c_dim}
	if inv.is_carcass_destroyed(tire_info):
		return {"tag": "DESTALONADO", "color": c_danger}
	if inv.is_punctured(tire_info) and inv.is_rim_damaged(tire_info):
		return {"tag": "FUGA + ARO", "color": c_danger}
	if inv.is_punctured(tire_info):
		return {"tag": "FUGA", "color": c_danger}
	if inv.is_rim_damaged(tire_info):
		return {"tag": "ARO", "color": c_gold}
	return {"tag": "OK", "color": c_dim}


func _dirty_field_count() -> int:
	var count := 0
	for path in draft_values:
		var a: Variant = draft_values.get(path, 0.0)
		var b: Variant = opening_values.get(path, 0.0)
		if a is String or b is String:
			if str(a) != str(b):
				count += 1
		elif not is_equal_approx(float(a), float(b)):
			count += 1
	if _pool_plan_dirty and (draft_mounted_ids != opening_mounted_ids or draft_spare_ids != opening_spare_ids):
		count += 1
	elif draft_wheel_compounds != opening_wheel_compounds or draft_spare_wheels != opening_spares:
		count += 1
	if new_tires_service and not _is_pool_mode():
		count += 1
	return count
