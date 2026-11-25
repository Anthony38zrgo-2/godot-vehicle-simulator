class_name RallyGaragePanel
extends Control

signal garage_closed(applied: bool)

const LOGICAL_SIZE := Vector2(1280.0, 800.0)
const StrategyBoardScript := preload("res://scripts/rally/rally_garage_strategy_board.gd")

const FONT_SERIF: Font = RallyUITheme.FONT_REGULAR
const FONT_SERIF_BOLD: Font = RallyUITheme.FONT_MEDIUM
const FONT_UI: Font = RallyUITheme.FONT_MEDIUM_TIGHT
const FONT_UI_BOLD: Font = RallyUITheme.FONT_DATA_BOLD_TIGHT
const FONT_TITLE: Font = RallyUITheme.FONT_TITLE
const FONT_SUBTITLE: Font = RallyUITheme.FONT_SUBTITLE
const FONT_BUTTON: Font = RallyUITheme.FONT_BUTTON

const BG_BASE := RallyUITheme.BG_BASE
const BG_SURFACE := RallyUITheme.BG_SURFACE
const BG_HOVER := RallyUITheme.BG_HOVER
const BORDER_SUBTLE := RallyUITheme.BORDER_SUBTLE
const BORDER_FOCUS := RallyUITheme.BORDER_FOCUS
const TEXT_PRIMARY := RallyUITheme.TEXT_PRIMARY
const TEXT_MUTED := RallyUITheme.TEXT_MUTED
const ACCENT_RALLY := RallyUITheme.ACCENT_RALLY
const ACCENT_ALERT := RallyUITheme.ACCENT_ALERT
const STATUS_DANGER := RallyUITheme.STATUS_DANGER
const STATUS_SUCCESS := RallyUITheme.STATUS_SUCCESS

const WB_BG_SHELL := RallyUITheme.WB_BG_SHELL
const WB_BG_HEADER := RallyUITheme.WB_BG_HEADER
const WB_BG_FOOTER := RallyUITheme.WB_BG_FOOTER
const WB_BG_TAB_INACTIVE := RallyUITheme.WB_BG_TAB_INACTIVE
const WB_BG_TAB_ACTIVE := RallyUITheme.WB_BG_TAB_ACTIVE
const WB_BG_CONTENT := RallyUITheme.WB_BG_CONTENT
const WB_BG_CARD := RallyUITheme.WB_BG_CARD
const WB_BG_CARD_HOVER := RallyUITheme.WB_BG_CARD_HOVER
const WB_BG_WELL := RallyUITheme.WB_BG_WELL
const WB_BORDER_SUBTLE := RallyUITheme.WB_BORDER_SUBTLE
const WB_BORDER_HOVER := RallyUITheme.WB_BORDER_HOVER
const WB_BORDER_FOCUS := RallyUITheme.WB_BORDER_FOCUS
const WB_BORDER_ACCENT := RallyUITheme.WB_BORDER_ACCENT
const WB_SLIDER_TRACK := RallyUITheme.WB_SLIDER_TRACK
const WB_SLIDER_FILL := RallyUITheme.WB_SLIDER_FILL
const WB_SLIDER_THUMB := RallyUITheme.WB_SLIDER_THUMB
const WB_SLIDER_STEPPER := RallyUITheme.WB_SLIDER_STEPPER
const WB_TEXT_TITLE := RallyUITheme.WB_TEXT_TITLE
const WB_TEXT_LABEL := RallyUITheme.WB_TEXT_LABEL
const WB_TEXT_DATA := RallyUITheme.WB_TEXT_DATA
const WB_TEXT_ACCENT := RallyUITheme.WB_TEXT_ACCENT

const C_BACK := WB_BG_SHELL
const C_GLASS := WB_BG_HEADER
const C_GLASS_DEEP := WB_BG_WELL
const C_RIM := WB_BORDER_SUBTLE
const C_CHROME_TEXT := WB_TEXT_TITLE
const C_CHROME_DIM := WB_TEXT_LABEL
const C_BLUE := WB_SLIDER_FILL
const C_BLUE_DEEP := Color("#2a2010")

const C_FACE := WB_BG_CONTENT
const C_FACE_HI := WB_BG_CARD_HOVER
const C_FACE_LO := WB_BG_CARD
const C_FIELD := WB_BG_WELL
const C_HI := WB_BORDER_HOVER
const C_LIGHT := WB_BORDER_SUBTLE
const C_SHADOW := Color(0.0, 0.0, 0.0, 0.25)
const C_DARK := Color("#060a0f")
const C_TEXT := WB_TEXT_TITLE
const C_DIM := WB_TEXT_LABEL
const C_GOLD := ACCENT_RALLY
const C_GOLD_HI := RallyUITheme.TEXT_GOLD_SOFT
const C_ROSE := STATUS_DANGER
const C_SEL := RallyUITheme.BG_ELEVATED

const PAD_NAME_CHARACTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_"

const PANEL := Rect2(24.0, 102.0, 1232.0, 584.0)
const PAGE_TOP := 156.0
const PAGE_BOTTOM := 674.0

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
const PROFILE_VISIBLE_ROWS := 5
const ESTIMATED_FUEL_BURN_L_PER_KM := 0.42

const SURFACE_PRESETS: Array[Dictionary] = [
	{
		"id": "gravel",
		"title": "BASE GRAVA / MIXTO",
		"subtitle": "Equilibrada · +altura · 55% frenada",
		"values": {
			"garage.suspension": 3.0,
			"garage.front_arb": 3.0,
			"garage.rear_arb": 3.0,
			"brakes.front_brake_bias": 0.55,
			"suspension.front.camber": -1.2 * PI / 180.0,
			"suspension.rear.camber": -0.8 * PI / 180.0,
			"suspension.front.toe": 0.0,
			"suspension.rear.toe": 0.2 * PI / 180.0,
			"garage.cooling": 1.0,
		},
	},
	{
		"id": "tarmac",
		"title": "BASE ASFALTO LISO",
		"subtitle": "Rígida · barras firmes · 60% frenada",
		"values": {
			"garage.suspension": 1.0,
			"garage.front_arb": 1.0,
			"garage.rear_arb": 2.0,
			"brakes.front_brake_bias": 0.60,
			"suspension.front.camber": -2.2 * PI / 180.0,
			"suspension.rear.camber": -1.4 * PI / 180.0,
			"suspension.front.toe": -0.1 * PI / 180.0,
			"suspension.rear.toe": 0.25 * PI / 180.0,
			"garage.cooling": 2.0,
		},
	},
	{
		"id": "wet_rough",
		"title": "BASE LLUVIA / BACHES",
		"subtitle": "Blanda · tracción suave · 52% frenada",
		"values": {
			"garage.suspension": 5.0,
			"garage.front_arb": 5.0,
			"garage.rear_arb": 5.0,
			"brakes.front_brake_bias": 0.52,
			"suspension.front.camber": -0.8 * PI / 180.0,
			"suspension.rear.camber": -0.5 * PI / 180.0,
			"suspension.front.toe": 0.05 * PI / 180.0,
			"suspension.rear.toe": 0.2 * PI / 180.0,
			"garage.cooling": 0.0,
		},
	},
]

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

var _vehicle_registry_cache: Array = []
var _vehicle_registry_loaded: bool = false
var _cached_route_path: String = ""
var _cached_route_points: PackedVector2Array = PackedVector2Array()
var _cached_route_heights: PackedFloat32Array = PackedFloat32Array()
var _cached_profile_altitudes: PackedFloat32Array = PackedFloat32Array()
var _cached_route_length_m: float = 0.0
var _stage_length_explicit: bool = false
var _stage_sectors: Array = []
var _stage_terrain: Dictionary = {}
var _briefing_cache_key: String = ""

var advanced_section := 0
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
var setup_scroll_offset: int = 0
var pad_character_index: int = 0
var active_setup_id: int = -1
var active_setup_name: String = "REGLAJE ACTUAL"
var setup_rows: Array[Dictionary] = []
var draft_values: Dictionary = {}
var opening_values: Dictionary = {}
var pending_values: Dictionary = {}
var new_tires_service: bool = false
var modal_mode: String = ""
var modal_text: String = ""
var notice: String = ""
var notice_time: float = 0.0
var notice_is_error: bool = false
var profile_dropdown_open: bool = false
var profile_scroll_offset: int = 0
var _hit_regions: Array[Dictionary] = []
var _page_field_paths: Array[String] = []
var _canvas_scale: float = 1.0
var _canvas_offset: Vector2 = Vector2.ZERO
var _restore_tree_paused: bool = false
var _restore_controls_enabled: bool = true
var _hover_point := Vector2(-4000.0, -4000.0)
var _dragging_path: String = ""
var _dragging_rect := Rect2()
var _last_click_path: String = ""
var _last_click_msec: int = 0
var _strategy_board: StrategyBoardScript = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_process_input(false)
	_strategy_board = StrategyBoardScript.new()
	_strategy_board.name = "StrategyBoard3D"
	_strategy_board.garage = self
	_strategy_board.visible = false
	add_child(_strategy_board)
	vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	if vehicle == null and get_parent() != null:
		vehicle = get_parent().find_child("FordEscortRS2000", true, false) as RallyEscortVehicle
		if vehicle == null:
			vehicle = get_parent().find_child("LanciaFulvia", true, false) as RallyEscortVehicle
	input_controller = get_node_or_null(input_controller_path) as RallyVehicleInputController
	if input_controller != null and not input_controller.garage_menu_requested.is_connected(
		open_garage
	):
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


func _resize_canvas() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_canvas_scale = minf(size.x / LOGICAL_SIZE.x, size.y / LOGICAL_SIZE.y)
	_canvas_offset = (size - LOGICAL_SIZE * _canvas_scale) * 0.5
	if _strategy_board != null and is_instance_valid(_strategy_board):
		_strategy_board.position = _canvas_offset
		_strategy_board.scale = Vector2.ONE * _canvas_scale
	queue_redraw()


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
	allowed_compound_ids = (
		options.get("allowed_compound_ids", []) as Array
	).duplicate()
	var overrides_var: Variant = options.get("compound_label_overrides", {})
	compound_label_overrides = (
		(overrides_var as Dictionary).duplicate(true)
		if overrides_var is Dictionary
		else {}
	)
	default_event_compound_id = str(
		options.get(
			"default_compound_id",
			RallyTireCompound.DEFAULT_ID
		)
	)
	event_forecast = (
		str(options.get("forecast_summary", "")) + "  " + str(options.get("forecast_advice", ""))
	).strip_edges()
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
	opening_values["fuel.initial_kg"] = vehicle.simulation.thermal_model.fuel_remaining_litres * vehicle \
			.simulation \
			.mass_model \
			.fuel_density_kg_per_litre
	draft_values = opening_values.duplicate(true)
	vehicle.ensure_tire_inventory()
	_sync_draft_pool_from_inventory()
	opening_wheel_compounds = draft_wheel_compounds.duplicate()
	opening_spares = draft_spare_wheels
	confirmed_setup = {}
	pending_values = {}
	new_tires_service = false
	selected_pool_tire_id = -1
	_pool_plan_dirty = false
	profile_dropdown_open = false
	profile_scroll_offset = 0
	page = 0
	advanced_section = 0
	selected_field_path = ""
	_set_page(0, false)
	_ensure_stage_route_cache()
	active_setup_id = -1
	active_setup_name = "REGLAJE ACTUAL"
	modal_mode = ""
	modal_text = ""
	notice = ""
	notice_time = 0.0
	notice_is_error = false
	_dragging_path = ""
	_hover_point = Vector2(-4000.0, -4000.0)
	_refresh_setups()
	visible = true
	set_process_input(true)
	if input_controller != null:
		input_controller.set_controls_enabled(false)
	get_tree().paused = true
	_sync_strategy_board()
	queue_redraw()


func close_garage(apply_changes: bool, confirmed_discard: bool = false) -> void:
	if not visible:
		return
	if mandatory_confirmation and not apply_changes:
		_show_notice("Confirma reglajes para continuar.", true)
		return
	if not apply_changes and _has_unapplied_changes() and not confirmed_discard:
		profile_dropdown_open = false
		modal_mode = "discard"
		_sync_strategy_board()
		queue_redraw()
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
					var corner := str(k).trim_prefix("strategy.wheel_compound.")
					draft_wheel_compounds[corner] = str(setup_to_apply[k])
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
	set_process_input(false)
	_dragging_path = ""
	selected_pool_tire_id = -1
	_pool_plan_dirty = false
	if _strategy_board != null and is_instance_valid(_strategy_board):
		_strategy_board.visible = false
		_strategy_board.clear_board()
	get_tree().paused = _restore_tree_paused
	if input_controller != null:
		input_controller.set_controls_enabled(_restore_controls_enabled)
	garage_closed.emit(apply_changes)
	queue_redraw()


func _has_unapplied_changes() -> bool:
	var pool_changed := (
		_pool_plan_dirty
		and (draft_mounted_ids != opening_mounted_ids or draft_spare_ids != opening_spare_ids)
	)
	var service_flag_dirty := new_tires_service and not _is_pool_mode()
	return (
		draft_values != opening_values
		or service_flag_dirty
		or pool_changed
		or draft_wheel_compounds != opening_wheel_compounds
		or draft_spare_wheels != opening_spares
	)


func _is_pool_mode() -> bool:
	return (
		is_instance_valid(vehicle)
		and vehicle.tire_inventory != null
		and (vehicle.tire_inventory as RallyTireInventory).is_pool_mode()
	)


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


func _draft_pool_tire_id(slot_kind: String, slot_index: int) -> int:
	match slot_kind:
		"mounted":
			if slot_index >= 0 and slot_index < draft_mounted_ids.size():
				return draft_mounted_ids[slot_index]
		"spare":
			if slot_index >= 0 and slot_index < draft_spare_ids.size():
				return draft_spare_ids[slot_index]
		"stock":
			if slot_index >= 0 and slot_index < draft_stock_ids.size():
				return draft_stock_ids[slot_index]
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
	_sync_strategy_board()
	queue_redraw()
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
		_sync_strategy_board()
		queue_redraw()
		return
	if target_id == selected_pool_tire_id:
		selected_pool_tire_id = -1
		_sync_strategy_board()
		queue_redraw()
		return
	if _find_draft_pool_loc(selected_pool_tire_id).is_empty():
		selected_pool_tire_id = -1
		_sync_strategy_board()
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
	_sync_strategy_board()
	queue_redraw()


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
		"mounted":
			draft_mounted_ids[index] = tid
		"spare":
			draft_spare_ids[index] = tid
		"stock":
			draft_stock_ids[index] = tid


func _remove_draft_pool_loc(kind: String, index: int) -> void:
	match kind:
		"spare":
			draft_spare_ids.remove_at(index)
		"stock":
			draft_stock_ids.remove_at(index)


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


func _input(event: InputEvent) -> void:
	if not visible:
		if (
			event is InputEventKey and event.pressed and not event.echo
			and event.ctrl_pressed and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]
			and is_instance_valid(vehicle) and not get_tree().paused
		):
			vehicle.simulation.adjust_live_tire_pressure(
				5.0 if event.keycode == KEY_PAGEUP else -5.0
			)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)
		accept_event()
		return
	if event is InputEventJoypadButton and event.pressed:
		_handle_pad_button(event as InputEventJoypadButton)
		accept_event()
		return
	if event is InputEventMouseMotion:
		if _dragging_path != "":
			_drag_to(_to_logical((event as InputEventMouseMotion).position))
			accept_event()
			return
		var previous := _hover_point
		_hover_point = _to_logical((event as InputEventMouseMotion).position)
		if previous.distance_squared_to(_hover_point) > 0.5:
			queue_redraw()
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if not mouse_event.pressed:
				if _dragging_path != "":
					_dragging_path = ""
					accept_event()
				return
			if (
				page == 3 and modal_mode == "" and _is_pool_mode() and not profile_dropdown_open
				and _strategy_board != null and _strategy_board.visible
				and _dragging_path == ""
				and _strategy_board.has_pointer_control(get_global_mouse_position())
			):
				return
			_handle_click(_to_logical(mouse_event.position))
			accept_event()
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			if _dragging_path == "" and modal_mode == "" and not profile_dropdown_open:
				_handle_right_click(_to_logical(mouse_event.position))
				accept_event()
		elif mouse_event.pressed and mouse_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if profile_dropdown_open and setup_rows.size() > PROFILE_VISIBLE_ROWS:
				var delta := -1 if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
				profile_scroll_offset = clampi(
					profile_scroll_offset + delta,
					0,
					maxi(setup_rows.size() - PROFILE_VISIBLE_ROWS, 0)
				)
				queue_redraw()
				accept_event()


func _handle_key(event: InputEventKey) -> void:
	if modal_mode == "name":
		if event.keycode == KEY_ESCAPE:
			modal_mode = ""
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_commit_new_setup()
		elif event.keycode == KEY_BACKSPACE:
			modal_text = modal_text.left(maxi(0, modal_text.length() - 1))
		elif event.unicode > 0 and modal_text.length() < 40:
			modal_text += String.chr(event.unicode)
		_sync_strategy_board()
		queue_redraw()
		return
	if modal_mode == "delete":
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_delete_selected_setup()
		elif event.keycode == KEY_ESCAPE:
			modal_mode = ""
		_sync_strategy_board()
		queue_redraw()
		return
	if modal_mode == "discard":
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			close_garage(false, true)
		elif event.keycode == KEY_ESCAPE:
			modal_mode = ""
		_sync_strategy_board()
		queue_redraw()
		return
	if profile_dropdown_open:
		if event.keycode == KEY_ESCAPE:
			profile_dropdown_open = false
			_sync_strategy_board()
			queue_redraw()
			return
		elif event.keycode in [KEY_UP, KEY_W]:
			_navigate_profile(-1)
			queue_redraw()
			return
		elif event.keycode in [KEY_DOWN, KEY_S]:
			_navigate_profile(1)
			queue_redraw()
			return
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_load_selected_setup()
			profile_dropdown_open = false
			_sync_strategy_board()
			queue_redraw()
			return
		elif event.keycode == KEY_DELETE:
			profile_dropdown_open = false
			_begin_delete_setup()
			_sync_strategy_board()
			queue_redraw()
			return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_confirm_selection()
		queue_redraw()
		return
	match event.keycode:
		KEY_ESCAPE:
			close_garage(false)
		KEY_F5:
			close_garage(true)
		KEY_PAGEUP:
			_set_page(page - 1)
		KEY_PAGEDOWN:
			_set_page(page + 1)
		KEY_TAB:
			_set_page(page + 1)
		KEY_LEFT, KEY_Q:
			_adjust_selected(-1.0)
		KEY_RIGHT, KEY_E:
			_adjust_selected(1.0)
		KEY_UP, KEY_W:
			_navigate_selection(-1)
		KEY_DOWN, KEY_S:
			_navigate_selection(1)
		KEY_R:
			if not selected_field_path.is_empty():
				_reset_single_field(selected_field_path)
		KEY_X:
			if page == 3 and _is_pool_mode() and selected_field_path.begins_with("spare:"):
				_unload_spare_slot(int(selected_field_path.trim_prefix("spare:")))
			elif selected_pool_tire_id >= 0:
				selected_pool_tire_id = -1
	_sync_strategy_board()
	queue_redraw()


func _handle_pad_button(event: InputEventJoypadButton) -> void:
	if modal_mode == "name":
		match event.button_index:
			JOY_BUTTON_DPAD_LEFT:
				pad_character_index = posmod(pad_character_index - 1, PAD_NAME_CHARACTERS.length())
			JOY_BUTTON_DPAD_RIGHT:
				pad_character_index = posmod(pad_character_index + 1, PAD_NAME_CHARACTERS.length())
			JOY_BUTTON_DPAD_UP:
				pad_character_index = posmod(pad_character_index - 8, PAD_NAME_CHARACTERS.length())
			JOY_BUTTON_DPAD_DOWN:
				pad_character_index = posmod(pad_character_index + 8, PAD_NAME_CHARACTERS.length())
			JOY_BUTTON_A:
				if modal_text.length() < 40:
					modal_text += PAD_NAME_CHARACTERS.substr(pad_character_index, 1)
			JOY_BUTTON_LEFT_SHOULDER:
				modal_text = modal_text.left(maxi(0, modal_text.length() - 1))
			JOY_BUTTON_Y:
				_commit_new_setup()
			JOY_BUTTON_B, JOY_BUTTON_START:
				modal_mode = ""
		_sync_strategy_board()
		queue_redraw()
		return
	if modal_mode == "delete":
		if event.button_index == JOY_BUTTON_A:
			_delete_selected_setup()
		elif event.button_index in [JOY_BUTTON_B, JOY_BUTTON_START]:
			modal_mode = ""
		_sync_strategy_board()
		queue_redraw()
		return
	if modal_mode == "discard":
		if event.button_index == JOY_BUTTON_A:
			close_garage(false, true)
		elif event.button_index in [JOY_BUTTON_B, JOY_BUTTON_START]:
			modal_mode = ""
		_sync_strategy_board()
		queue_redraw()
		return
	if profile_dropdown_open:
		if event.button_index in [JOY_BUTTON_B, JOY_BUTTON_START]:
			profile_dropdown_open = false
		elif event.button_index == JOY_BUTTON_DPAD_UP:
			_navigate_profile(-1)
		elif event.button_index == JOY_BUTTON_DPAD_DOWN:
			_navigate_profile(1)
		elif event.button_index == JOY_BUTTON_A:
			_load_selected_setup()
			profile_dropdown_open = false
		_sync_strategy_board()
		queue_redraw()
		return
	match event.button_index:
		JOY_BUTTON_Y:
			close_garage(true)
		JOY_BUTTON_B, JOY_BUTTON_START:
			close_garage(false)
		JOY_BUTTON_A:
			_confirm_selection()
		JOY_BUTTON_X:
			if page == 3 and _is_pool_mode() and selected_field_path.begins_with("spare:"):
				_unload_spare_slot(int(selected_field_path.trim_prefix("spare:")))
			elif selected_pool_tire_id >= 0:
				selected_pool_tire_id = -1
			elif not selected_field_path.is_empty():
				_reset_single_field(selected_field_path)
		JOY_BUTTON_DPAD_UP:
			_navigate_selection(-1)
		JOY_BUTTON_DPAD_DOWN:
			_navigate_selection(1)
		JOY_BUTTON_DPAD_LEFT:
			_adjust_selected(-1.0)
		JOY_BUTTON_DPAD_RIGHT:
			_adjust_selected(1.0)
		JOY_BUTTON_LEFT_SHOULDER:
			_set_page(page - 1)
		JOY_BUTTON_RIGHT_SHOULDER:
			_set_page(page + 1)
	_sync_strategy_board()
	queue_redraw()


func _handle_right_click(point: Vector2) -> void:
	for index in range(_hit_regions.size() - 1, -1, -1):
		var region: Dictionary = _hit_regions[index]
		if bool(region.get("modal", false)) or bool(region.get("dropdown", false)):
			continue
		if not (region.rect as Rect2).has_point(point):
			continue
		var path := str(region.get("path", ""))
		if not path.is_empty():
			_reset_single_field(path)
			queue_redraw()
			return


# Las regiones se registran de fuera hacia dentro: la fila primero y sus
# controles después, de modo que al recorrerlas al revés los botones ganan.
func _handle_click(point: Vector2) -> void:
	var modal_open := modal_mode != ""
	var dropdown_open := (not modal_open) and profile_dropdown_open
	for index in range(_hit_regions.size() - 1, -1, -1):
		var region: Dictionary = _hit_regions[index]
		if bool(region.get("modal", false)) != modal_open:
			continue
		if dropdown_open and not bool(region.get("dropdown", false)) and str(region.kind) != "toggle_profile_menu":
			continue
		if not (region.rect as Rect2).has_point(point):
			continue
		match str(region.kind):
			"toggle_profile_menu":
				profile_dropdown_open = not profile_dropdown_open
				if profile_dropdown_open:
					_refresh_setups()
				_sync_strategy_board()
			"apply_preset":
				_apply_surface_preset(str(region.preset_id))
				profile_dropdown_open = false
				_sync_strategy_board()
			"profile_load":
				selected_setup_index = int(region.index)
				selected_setup_id = int(setup_rows[selected_setup_index].get("id", -1))
				_load_selected_setup()
				profile_dropdown_open = false
				_sync_strategy_board()
			"profile_save":
				selected_setup_index = int(region.index)
				selected_setup_id = int(setup_rows[selected_setup_index].get("id", -1))
				_save_selected_setup()
				profile_dropdown_open = false
				_sync_strategy_board()
			"profile_delete":
				selected_setup_index = int(region.index)
				selected_setup_id = int(setup_rows[selected_setup_index].get("id", -1))
				profile_dropdown_open = false
				_begin_delete_setup()
				_sync_strategy_board()
			"profile_new":
				profile_dropdown_open = false
				_run_button("new")
			"profile_reset":
				profile_dropdown_open = false
				_run_button("reset")
			"set_value":
				selected_field_path = str(region.path)
				if not bool(region.get("disabled", false)):
					_update_value(str(region.path), float(region.value))
			"fuel_fit_stage":
				_fit_fuel_to_stage()
			"all_compound":
				if not _may_service_tires():
					_show_notice("Asistencia bloqueada en tramo: cambia ruedas desde Pausa.", true)
				elif compound_change_allowed:
					_pool_plan_dirty = false
					for corner in ["FL", "FR", "RL", "RR"]:
						draft_wheel_compounds[corner] = str(region.compound)
			"compound":
				if not _may_service_tires():
					_show_notice("Asistencia bloqueada en tramo: cambia ruedas desde Pausa.", true)
				elif compound_change_allowed:
					_pool_plan_dirty = false
					var corner: String = str(region.corner)
					var ids := _available_compound_ids()
					if not ids.is_empty():
						var current := ids.find(str(draft_wheel_compounds.get(corner, "")))
						draft_wheel_compounds[corner] = str(ids[(current + 1) % ids.size()])
			"spares":
				if not _may_service_tires():
					_show_notice("Asistencia bloqueada en tramo.", true)
				else:
					_pool_plan_dirty = false
					draft_spare_wheels = posmod(draft_spare_wheels + int(region.get("delta", 1)), 3)
			"pool_slot":
				selected_field_path = "%s:%d" % [str(region.slot_kind), int(region.slot_index)]
				_pool_interact(str(region.slot_kind), int(region.slot_index))
			"pool_unload_spare":
				_unload_spare_slot(int(region.slot_index))
			"tab":
				profile_dropdown_open = false
				_set_page(int(region.page))
			"select":
				var path := str(region.path)
				var now := Time.get_ticks_msec()
				if path == _last_click_path and (now - _last_click_msec) <= 380:
					_reset_single_field(path)
					_last_click_path = ""
				else:
					selected_field_path = path
					_last_click_path = path
					_last_click_msec = now
			"slide":
				if not bool(region.get("disabled", false)):
					selected_field_path = str(region.path)
					_dragging_path = str(region.path)
					_dragging_rect = region.get("track", region.rect) as Rect2
					_drag_to(point)
			"adjust":
				if not bool(region.get("disabled", false)):
					selected_field_path = str(region.path)
					_adjust_field(str(region.path), float(region.amount))
			"button":
				_run_button(str(region.action))
			"service":
				new_tires_service = not new_tires_service
			"modal":
				_run_modal(str(region.action))
		queue_redraw()
		return
	if dropdown_open:
		profile_dropdown_open = false
		_sync_strategy_board()
		queue_redraw()


func _drag_to(point: Vector2) -> void:
	if _dragging_path.is_empty():
		return
	_set_from_slider(_dragging_path, point.x, _dragging_rect)


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
		1:
			source = CHASSIS_PATHS
		2:
			source = POWERTRAIN_PATHS
		3:
			source = STRATEGY_PATHS
	for path in source:
		if not _page_field_paths.has(path):
			_page_field_paths.append(path)
	if page == 3:
		_refresh_strategy_nav_paths()
	if not _page_field_paths.has(selected_field_path):
		selected_field_path = _page_field_paths[0] if not _page_field_paths.is_empty() else ""
	_sync_strategy_board()
	queue_redraw()


func _navigate_profile(direction: int) -> void:
	if setup_rows.is_empty():
		selected_setup_index = 0
		return
	selected_setup_index = posmod(selected_setup_index + direction, setup_rows.size())
	selected_setup_id = int(setup_rows[selected_setup_index].get("id", -1))
	if selected_setup_index < profile_scroll_offset:
		profile_scroll_offset = selected_setup_index
	elif selected_setup_index >= profile_scroll_offset + PROFILE_VISIBLE_ROWS:
		profile_scroll_offset = selected_setup_index - PROFILE_VISIBLE_ROWS + 1


func _navigate_selection(direction: int) -> void:
	if _page_field_paths.is_empty():
		_set_page(page)
		return
	var nav_paths := _active_nav_paths()
	if nav_paths.is_empty():
		return
	var index := nav_paths.find(selected_field_path)
	if index < 0:
		selected_field_path = nav_paths[0]
		return
	selected_field_path = nav_paths[posmod(index + direction, nav_paths.size())]


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
	var effective_dir := direction
	if selected_field_path in INVERTED_DISCRETE_PATHS:
		effective_dir = -direction
	_adjust_field(selected_field_path, effective_dir)


func _adjust_field(path: String, direction: float) -> void:
	if path.begins_with(RallySetupCatalog.DIFFERENTIAL_PREFIX) and not bool(draft_values.get("garage.lsd", 0.0)):
		return
	if page == 3:
		if path == "spares" and not _is_pool_mode():
			if _may_service_tires():
				draft_spare_wheels = posmod(draft_spare_wheels + int(signf(direction)), 3)
			return
		if path.begins_with("mounted:") and not _is_pool_mode():
			if _may_service_tires() and compound_change_allowed:
				var idx := int(path.trim_prefix("mounted:"))
				var corner: String = str(["FL", "FR", "RL", "RR"][clampi(idx, 0, 3)])
				var ids := _available_compound_ids()
				if not ids.is_empty():
					var cur := ids.find(str(draft_wheel_compounds.get(corner, "")))
					draft_wheel_compounds[corner] = str(ids[posmod(cur + int(signf(direction)), ids.size())])
			return
	var field := _setup_field(path)
	if field.is_empty():
		return
	var current := float(draft_values.get(path, 0.0))
	var next_value := current + float(field.step) * direction
	_update_value(path, next_value)


func _set_from_slider(path: String, x: float, rect: Rect2) -> void:
	if path.begins_with(RallySetupCatalog.DIFFERENTIAL_PREFIX) and not bool(draft_values.get("garage.lsd", 0.0)):
		return
	var field := _setup_field(path)
	if field.is_empty():
		return
	var normalized := clampf((x - rect.position.x) / maxf(rect.size.x, 1.0), 0.0, 1.0)
	_update_value(path, lerpf(float(field.min), float(field.max), normalized))


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
		if path == "garage.lsd" and not bool(draft_values.get("garage.lsd", 0.0)):
			if selected_field_path.begins_with(RallySetupCatalog.DIFFERENTIAL_PREFIX):
				selected_field_path = "garage.lsd"
		if page == 3:
			_sync_strategy_board()
	queue_redraw()


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
	for p in SURFACE_PRESETS:
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
	if page == 3:
		if _is_pool_mode():
			if selected_field_path.begins_with("mounted:"):
				_pool_interact("mounted", int(selected_field_path.trim_prefix("mounted:")))
			elif selected_field_path.begins_with("spare:"):
				_pool_interact("spare", int(selected_field_path.trim_prefix("spare:")))
			elif selected_field_path.begins_with("stock:"):
				_pool_interact("stock", int(selected_field_path.trim_prefix("stock:")))
		else:
			if selected_field_path == "service":
				if _may_service_tires():
					new_tires_service = not new_tires_service
			elif selected_field_path == "spares":
				if _may_service_tires():
					draft_spare_wheels = posmod(draft_spare_wheels + 1, 3)
			elif selected_field_path.begins_with("mounted:"):
				_adjust_field(selected_field_path, 1.0)
	elif selected_field_path == "garage.lsd":
		var next_lsd := 0.0 if bool(draft_values.get("garage.lsd", 0.0)) else 1.0
		_update_value("garage.lsd", next_lsd)
	elif selected_field_path.is_empty() and not _page_field_paths.is_empty():
		selected_field_path = _page_field_paths[0]
	_sync_strategy_board()
	queue_redraw()


func _run_button(action: String) -> void:
	match action:
		"reset":
			draft_values = vehicle.simulation.setup_design_values.duplicate(true)
			active_setup_id = -1
			active_setup_name = "DE SERIE"
			var restored := vehicle.apply_setup_values(draft_values)
			if bool(restored.get("ok", false)):
				draft_values = restored.values
				_show_notice("Reglaje de serie restaurado.")
			else:
				_show_notice(str(restored.get("error", "Error al restaurar.")), true)
		"cancel":
			close_garage(false)
		"apply":
			close_garage(true)
		"new":
			modal_mode = "name"
			modal_text = ""
		"save":
			_save_selected_setup()
		"load":
			_load_selected_setup()
		"delete":
			_begin_delete_setup()
	_sync_strategy_board()
	queue_redraw()


func _run_modal(action: String) -> void:
	match action:
		"accept":
			match modal_mode:
				"name":
					_commit_new_setup()
				"delete":
					_delete_selected_setup()
				"discard":
					close_garage(false, true)
		"cancel":
			modal_mode = ""
	_sync_strategy_board()
	queue_redraw()


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
	setup_scroll_offset = clampi(
		setup_scroll_offset, 0, maxi(setup_rows.size() - _setup_visible_rows(), 0)
	)
	profile_scroll_offset = clampi(
		profile_scroll_offset, 0, maxi(setup_rows.size() - PROFILE_VISIBLE_ROWS, 0)
	)
	selected_setup_id = int(setup_rows[selected_setup_index].get("id", -1)) if not setup_rows.is_empty() else -1


func _setup_visible_rows() -> int:
	return PROFILE_VISIBLE_ROWS


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
		modal_text = active_setup_name if not (active_setup_name in ["REGLAJE ACTUAL", "DE SERIE", "GRAVA / MIXTO", "ASFALTO LISO", "LLUVIA / BACHES"]) else ""
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
	queue_redraw()


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
	queue_redraw()


func _begin_delete_setup() -> void:
	if selected_setup_id < 0:
		_show_notice("Selecciona un perfil.", true)
		return
	modal_mode = "delete"
	queue_redraw()


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
	queue_redraw()


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
	queue_redraw()


func _process(delta: float) -> void:
	if notice_time > 0.0:
		notice_time = maxf(notice_time - delta, 0.0)
		queue_redraw()


func _to_logical(point: Vector2) -> Vector2:
	return (point - _canvas_offset) / maxf(_canvas_scale, 0.0001)


# =============================================================================
# RENDERIZADO
# =============================================================================


func _draw() -> void:
	_hit_regions.clear()
	if not visible:
		return
	if _canvas_scale <= 0.0:
		_resize_canvas()

	draw_rect(Rect2(Vector2.ZERO, size), C_BACK)
	draw_set_transform(_canvas_offset, 0.0, Vector2.ONE * _canvas_scale)

	_draw_backdrop()
	_draw_chrome_header()
	_draw_classic_panel()
	_draw_tabs()

	match page:
		0:
			_draw_stage_page()
		1:
			_draw_chassis_page()
		2:
			_draw_powertrain_page()
		3:
			_draw_wheels_and_load_page()

	_draw_chrome_footer()

	if profile_dropdown_open and modal_mode == "":
		_draw_profile_dropdown()

	if modal_mode != "":
		_draw_modal()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_backdrop() -> void:
	draw_rect(Rect2(0, 0, LOGICAL_SIZE.x, LOGICAL_SIZE.y), C_BACK)


func _get_vehicle_registry_entries() -> Array:
	if _vehicle_registry_loaded:
		return _vehicle_registry_cache
	_vehicle_registry_loaded = true
	const REG_PATH := "res://data/vehicles/registry.json"
	if not FileAccess.file_exists(REG_PATH):
		return _vehicle_registry_cache
	var file := FileAccess.open(REG_PATH, FileAccess.READ)
	if file == null:
		return _vehicle_registry_cache
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var pd := parsed as Dictionary
		var lower_v: Variant = pd.get("vehicles")
		if lower_v is Dictionary:
			_vehicle_registry_cache = (lower_v as Dictionary).values()
		elif lower_v is Array:
			_vehicle_registry_cache = lower_v as Array
		elif pd.get("Vehicles") is Array:
			_vehicle_registry_cache = pd.get("Vehicles") as Array
	elif parsed is Array:
		_vehicle_registry_cache = parsed as Array
	return _vehicle_registry_cache


func _get_vehicle_display_name() -> String:
	if vehicle != null:
		var manifest_val: Variant = vehicle.get("rally_asset_manifest")
		if manifest_val is Dictionary:
			var source_val: Variant = (manifest_val as Dictionary).get("source", {})
			if source_val is Dictionary:
				var recipe_val: Variant = (source_val as Dictionary).get("recipe", {})
				if recipe_val is Dictionary:
					var recipe_name := str((recipe_val as Dictionary).get("display_name", "")).strip_edges()
					if not recipe_name.is_empty():
						return recipe_name.to_upper()

		var profile_id := str(vehicle.rally_profile.get("profile_id", "")).strip_edges().to_lower()
		var profile_path := str(vehicle.rally_profile_path).strip_edges().to_lower()
		var node_name := str(vehicle.name).strip_edges().to_lower()
		for entry in _get_vehicle_registry_entries():
			if not entry is Dictionary:
				continue
			var d := entry as Dictionary
			var eid := str(d.get("Id", "")).strip_edges().to_lower()
			var eprof := str(d.get("Profile", "")).strip_edges().to_lower()
			var disp := str(d.get("DisplayName", "")).strip_edges()
			if disp.is_empty():
				continue
			if (not profile_id.is_empty() and (profile_id == eid or profile_id == eprof or profile_id == eprof.get_file())) \
					or (not profile_path.is_empty() and not eprof.is_empty() and profile_path.contains("/%s/" % eprof)) \
					or (not node_name.is_empty() and node_name != "vehicle" and (node_name == eid or (not eprof.is_empty() and node_name.contains(eprof.get_file())))):
				return disp.to_upper()

		var direct_name := str(vehicle.rally_profile.get("display_name", vehicle.rally_profile.get("profile_name", ""))).strip_edges()
		if not direct_name.is_empty():
			return direct_name.to_upper()
		if node_name.contains("fulvia") or profile_path.contains("fulvia"):
			return "LANCIA FULVIA HF"
		if node_name.contains("escort") or profile_path.contains("escort"):
			return "FORD ESCORT RS2000"
	if not team_name.is_empty() and team_name != "Ford Rally Works":
		return team_name.to_upper()
	return "FORD ESCORT RS2000"


func _get_team_display_name() -> String:
	if not team_name.is_empty() and team_name != "Ford Rally Works":
		return team_name.to_upper()
	if vehicle != null and (vehicle.name.to_lower().contains("fulvia") or vehicle.rally_profile_path.to_lower().contains("fulvia")):
		return "LANCIA HF"
	return "FORD RALLY WORKS"


func _draw_chrome_header() -> void:
	_glass_window(Rect2(24, 14, 1232, 82), RallyUITheme.CORNER_RADIUS)

	# 1) Bloque izquierdo: Solo nombre del coche
	var car_title := _get_vehicle_display_name()
	var title_size := 25
	while title_size > 15 and FONT_SUBTITLE.get_string_size(car_title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > 300.0:
		title_size -= 1
	_text_with(FONT_SUBTITLE, _box(42, 22, 300, 66), car_title, title_size, C_CHROME_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0)

	draw_line(Vector2(354, 24), Vector2(354, 86), BORDER_SUBTLE, 1.0)

	# 2) Bloque central: Solo título del stage
	_ensure_stage_route_cache()
	var st_title := circuit_name.to_upper()
	var st_size := 22
	while st_size > 15 and FONT_SUBTITLE.get_string_size(st_title, HORIZONTAL_ALIGNMENT_LEFT, -1, st_size).x > 384.0:
		st_size -= 1
	_text_with(FONT_SUBTITLE, _box(372, 22, 384, 66), st_title, st_size, C_CHROME_TEXT, HORIZONTAL_ALIGNMENT_LEFT, 384.0)

	draw_line(Vector2(766, 24), Vector2(766, 86), BORDER_SUBTLE, 1.0)

	# 3) Bloque derecho: Selector de Perfil / Bases + Guardar rápido
	var drop_rect := Rect2(780, 26, 306, 56)
	var drop_hover := _mouse_over(drop_rect)
	var drop_fill := C_FACE_HI if (profile_dropdown_open or drop_hover) else C_GLASS_DEEP
	var drop_rim := C_GOLD if profile_dropdown_open else (BORDER_FOCUS if drop_hover else RallyUITheme.BORDER_CARD)
	_glass_box(drop_rect, RallyUITheme.CORNER_RADIUS, drop_fill, drop_rim, 0.0)
	_text_with(FONT_SUBTITLE, _box(794, 30, 180, 18), "PERFIL / BASE ACTIVA", 11, C_CHROME_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0)
	_text_title(
		_box(794, 48, 252, 28),
		active_setup_name.to_upper(),
		16,
		C_GOLD,
		HORIZONTAL_ALIGNMENT_LEFT,
		252.0
	)
	_text_with(FONT_BUTTON, _box(drop_rect.end.x - 32, 34, 24, 38), "▲" if profile_dropdown_open else "▼", 13, C_GOLD if profile_dropdown_open else C_DIM, HORIZONTAL_ALIGNMENT_CENTER, -1.0)
	_hit_regions.append({ "rect": drop_rect, "kind": "toggle_profile_menu" })

	var save_rect := Rect2(1096, 26, 142, 56)
	var save_lbl := "GUARDAR" if (selected_setup_id >= 0 or active_setup_id >= 0) else "GUARDAR COMO"
	_chrome_button_sized(save_rect, save_lbl, "save", 13)


func _draw_profile_dropdown() -> void:
	var panel_rect := Rect2(780, 86, 458, 434)
	draw_style_box(RallyUITheme.make_flat_panel(BG_SURFACE, C_GOLD, 1, RallyUITheme.CORNER_RADIUS), panel_rect)

	var inner_x := panel_rect.position.x + 14.0
	var inner_w := panel_rect.size.x - 28.0
	var y := panel_rect.position.y + 12.0

	_text_with(FONT_SUBTITLE, _box(inner_x, y, inner_w, 18), "BASES RÁPIDAS (1 CLIC)", 12, C_GOLD_HI, HORIZONTAL_ALIGNMENT_LEFT, -1.0)
	y += 22.0

	var card_w := floorf((inner_w - 8.0) * 0.5)
	var card_h := 46.0
	for i in SURFACE_PRESETS.size():
		var preset: Dictionary = SURFACE_PRESETS[i]
		var col := i % 2
		var row := i / 2
		var r := Rect2(inner_x + float(col) * (card_w + 8.0), y + float(row) * (card_h + 6.0), card_w, card_h)
		var hovered := _mouse_over(r)
		draw_style_box(RallyUITheme.make_flat_panel(C_FACE_HI if hovered else C_FACE_LO, C_GOLD if hovered else BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS), r)
		_text(_box(r.position.x + 10, r.position.y + 4, r.size.x - 20, 18), str(preset.title), 10, C_TEXT, true)
		_text(_box(r.position.x + 10, r.position.y + 23, r.size.x - 20, 16), str(preset.subtitle), 9, C_DIM)
		_hit_regions.append({ "rect": r, "kind": "apply_preset", "preset_id": str(preset.id), "dropdown": true })

	var reset_card := Rect2(inner_x + (card_w + 8.0), y + (card_h + 6.0), card_w, card_h)
	var reset_hover := _mouse_over(reset_card)
	draw_style_box(RallyUITheme.make_flat_panel(C_FACE_HI if reset_hover else C_FACE_LO, C_GOLD if reset_hover else BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS), reset_card)
	_text(_box(reset_card.position.x + 10, reset_card.position.y + 4, reset_card.size.x - 20, 18), "DE SERIE (FÁBRICA)", 10, C_TEXT, true)
	_text(_box(reset_card.position.x + 10, reset_card.position.y + 23, reset_card.size.x - 20, 16), "Restaura valores originales", 9, C_DIM)
	_hit_regions.append({ "rect": reset_card, "kind": "profile_reset", "dropdown": true })

	y += (card_h + 6.0) * 2.0 + 10.0
	draw_line(Vector2(inner_x, y), Vector2(inner_x + inner_w, y), BORDER_SUBTLE, 1.0)
	y += 8.0

	_text_with(FONT_SUBTITLE, _box(inner_x, y, 260, 26), "MIS PERFILES (%d)" % setup_rows.size(), 12, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0)
	var new_btn := Rect2(inner_x + inner_w - 134.0, y, 134.0, 26)
	var new_hover := _mouse_over(new_btn)
	draw_style_box(RallyUITheme.make_flat_panel(Color("#f2bb54") if new_hover else ACCENT_RALLY, Color("#f6c96e"), 1, RallyUITheme.CORNER_RADIUS), new_btn)
	_text_with(FONT_BUTTON, new_btn, "+ NUEVO PERFIL", 12, BG_BASE, HORIZONTAL_ALIGNMENT_CENTER, -1.0)
	_hit_regions.append({ "rect": new_btn, "kind": "profile_new", "dropdown": true })
	y += 32.0

	var list_rect := Rect2(inner_x, y, inner_w, panel_rect.end.y - y - 12.0)
	draw_rect(list_rect, C_FIELD)
	_sunken(list_rect)

	if setup_rows.is_empty():
		_text(_box(list_rect.position.x, list_rect.position.y, list_rect.size.x, list_rect.size.y), "SIN PERFILES GUARDADOS PARA ESTE TRAMO", 10, C_DIM, false, HORIZONTAL_ALIGNMENT_CENTER)
		return

	var row_h := floorf(list_rect.size.y / float(PROFILE_VISIBLE_ROWS))
	for slot in PROFILE_VISIBLE_ROWS:
		var idx := profile_scroll_offset + slot
		if idx >= setup_rows.size():
			break
		var row: Dictionary = setup_rows[idx]
		var r := Rect2(list_rect.position.x, list_rect.position.y + float(slot) * row_h, list_rect.size.x, row_h)
		var is_active := int(row.get("id", -1)) == active_setup_id
		var is_sel := idx == selected_setup_index
		_row_frame(r, is_sel or is_active, slot == PROFILE_VISIBLE_ROWS - 1, _mouse_over(r), C_FIELD)
		if is_active:
			draw_rect(Rect2(r.position.x + 4, r.position.y + 8, 4, row_h - 16), C_GOLD)

		var load_rect := Rect2(r.position.x + 14, r.position.y, r.size.x - 122, row_h)
		_text(_box(load_rect.position.x, r.position.y + 4, load_rect.size.x, 20), str(row.get("name", "Reglaje")), 11, C_TEXT, is_active or is_sel)
		_num(_box(load_rect.position.x, r.position.y + 22, load_rect.size.x, 16), _short_timestamp(str(row.get("modified_at", ""))), 9, C_DIM)
		_hit_regions.append({ "rect": load_rect, "kind": "profile_load", "index": idx, "dropdown": true })

		var save_here := Rect2(r.end.x - 104, r.position.y + (row_h - 24.0) * 0.5, 62, 24)
		var sh_hover := _mouse_over(save_here)
		draw_style_box(RallyUITheme.make_flat_panel(C_FACE_HI if sh_hover else WB_BG_CARD, BORDER_FOCUS if sh_hover else BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS), save_here)
		_text_with(FONT_BUTTON, save_here, "ACT.", 11, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, -1.0)
		_hit_regions.append({ "rect": save_here, "kind": "profile_save", "index": idx, "dropdown": true })

		var del_rect := Rect2(r.end.x - 36, r.position.y + (row_h - 24.0) * 0.5, 28, 24)
		var del_hover := _mouse_over(del_rect)
		draw_style_box(RallyUITheme.make_flat_panel(Color("#3c1a1f") if del_hover else Color("#241216"), C_ROSE if del_hover else Color(C_ROSE, 0.45), 1, RallyUITheme.CORNER_RADIUS), del_rect)
		_text_with(FONT_BUTTON, del_rect, "×", 13, C_ROSE if not del_hover else RallyUITheme.TEXT_WHITE, HORIZONTAL_ALIGNMENT_CENTER, -1.0)
		_hit_regions.append({ "rect": del_rect, "kind": "profile_delete", "index": idx, "dropdown": true })


func _draw_chrome_footer() -> void:
	_glass_window(Rect2(24, 692, 1232, 88), RallyUITheme.CORNER_RADIUS)

	_chrome_button_sized(Rect2(46, 714, 174, 46), "VOLVER A SERIE", "reset", 14)

	var lane := Rect2(238, 700, 646, 72)
	if notice_time > 0.0 and not notice.is_empty():
		var tone := C_ROSE if _notice_is_error() else C_GOLD
		_glass_box(lane, RallyUITheme.CORNER_RADIUS, Color(C_GLASS_DEEP, 0.92), Color(tone, 0.55), 0.0)
		_text_serif(
			_box(lane.position.x + 12, lane.position.y, lane.size.x - 24, lane.size.y),
			notice.to_upper(),
			11,
			tone,
			true,
			HORIZONTAL_ALIGNMENT_CENTER
		)
	else:
		var desc := _field_description(selected_field_path)
		if not desc.is_empty():
			_text_with(
				FONT_SERIF,
				_box(lane.position.x + 8, lane.position.y, lane.size.x - 16, lane.size.y),
				desc,
				10,
				C_CHROME_TEXT,
				HORIZONTAL_ALIGNMENT_CENTER,
				lane.size.x - 16.0
			)

	var cancel_rect := Rect2(900, 714, 150, 46)
	var apply_rect := Rect2(1066, 714, 168, 46)
	_chrome_button_sized(cancel_rect, "CANCELAR", "cancel", 14)
	_gold_button(apply_rect, "APLICAR", "apply")


func _field_description(path: String) -> String:
	match path:
		"garage.suspension":
			return "Suspensión: BLANDA absorbe baches en tierra; RÍGIDA da precisión en asfalto liso."
		"garage.front_arb":
			return "Estabilizadora del.: más RÍGIDA reduce balanceo pero aumenta el subviraje al entrar."
		"garage.rear_arb":
			return "Estabilizadora tras.: más RÍGIDA ayuda a rotar el coche en curva (más sobreviraje)."
		"brakes.front_brake_bias":
			return "Frenada: más DELANTERA da estabilidad; más TRASERA mete el morro en horquillas."
		"suspension.front.camber":
			return "Caída del.: valores negativos mejoran apoyo en curva; cercanos a 0° mejoran frenada recta."
		"suspension.rear.camber":
			return "Caída tras.: negativa sujeta la trasera en apoyo lateral; 0° maximiza tracción recta."
		"suspension.front.toe":
			return "Convergencia del.: abierta (-) agiliza entrada en giro; cerrada (+) estabiliza en recta."
		"suspension.rear.toe":
			return "Convergencia tras.: cerrada (+) estabiliza la zaga; abierta (-) hace la trasera más viva."
		"powertrain.final_drive":
			return "Relación final: valores BAJOS alargan marchas (vel. punta); ALTOS acortan (aceleración)."
		"powertrain.max_rpm":
			return "Limitador RPM: bajar el corte reduce consumo, calor y desgaste mecánico del motor en tramos largos."
		"garage.cooling":
			return "Refrigeración: abrir el conducto baja temperatura de agua/aceite a costa de algo de resistencia."
		"garage.lsd":
			return "Diferencial: ABIERTO gira libre; AUTOBLOCANTE reparte par para traccionar en salida."
		"powertrain.differential.clutches":
			return "Discos de fricción: más superficies aumentan la fuerza máxima de bloqueo del autoblocante."
		"powertrain.differential.power_ramp_angle_deg":
			return "Rampa aceleración: 45° bloquea FUERTE al dar gas (+tracción); 90° deja girar más libre."
		"powertrain.differential.coast_ramp_angle_deg":
			return "Rampa retención: 45° estabiliza al soltar gas/frenar; 90° permite girar con más agilidad."
		"fuel.initial_kg":
			return "Combustible: cada litro extra añade peso (~0.74 kg/L). Ajusta lo necesario para el tramo."
		"garage.front_pressure":
			return "Presión del.: baja (130-160 kPa) da agarre en tierra; alta (180+ kPa) da precisión en asfalto."
		"garage.rear_pressure":
			return "Presión tras.: ajusta el agarre y temperatura de trabajo del eje trasero."
	if path.begins_with("mounted:") or path.begins_with("spare:") or path.begins_with("stock:"):
		return "Ruedas 3D: arrastra para mover entre coche, maletero (+18 kg c/u) y parque. Clic origen -> destino."
	return ""


func _notice_is_error() -> bool:
	return notice_is_error


func _draw_classic_panel() -> void:
	draw_style_box(RallyUITheme.make_flat_panel(C_FACE, RallyUITheme.BORDER_CARD, 1, RallyUITheme.CORNER_RADIUS), PANEL)
	draw_line(Vector2(PANEL.position.x, 146), Vector2(PANEL.end.x, 146), BORDER_SUBTLE, 1.0)


func _draw_tabs() -> void:
	var titles := ["1 · TRAMO", "2 · CHASIS Y FRENOS", "3 · MOTOR Y CAJA", "4 · RUEDAS Y CARGA"]
	var x := 34.0
	for index in titles.size():
		var label: String = titles[index]
		var width: float = maxf(148.0, FONT_BUTTON.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 42.0)
		var rect := Rect2(x, 102, width, 44)
		_tab(rect, label, index == page)
		_hit_regions.append({ "rect": rect, "kind": "tab", "page": index })
		x += width + 6.0

	var changed := _dirty_field_count()
	if changed > 0:
		var banner := "%d CAMBIO%s SIN APLICAR" % [changed, "" if changed == 1 else "S"]
		var banner_w := _ui_width(banner, 10, true)
		var banner_x := 1244.0 - banner_w
		draw_circle(Vector2(banner_x - 14.0, 124.0), 4.0, C_GOLD)
		_num(_box(banner_x, 106, banner_w + 4, 36), banner, 10, C_GOLD)


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


func _tab(rect: Rect2, label: String, active: bool) -> void:
	var bottom := rect.end.y + 1.0 if active else rect.end.y
	var top := rect.position.y + 4.0 if active else rect.position.y + 8.0
	var tab_rect := Rect2(rect.position.x, top, rect.size.x, bottom - top)
	var faced := WB_BG_CONTENT if active else RallyUITheme.BG_SHELL
	if not active and _mouse_over(rect):
		faced = WB_BG_CARD
	var sb := StyleBoxFlat.new()
	sb.bg_color = faced
	sb.border_color = RallyUITheme.BORDER_CARD if active else BORDER_SUBTLE
	sb.border_width_left = 1
	sb.border_width_top = 2 if active else 1
	sb.border_width_right = 1
	sb.border_width_bottom = 0 if active else 1
	sb.corner_radius_top_left = RallyUITheme.CORNER_RADIUS
	sb.corner_radius_top_right = RallyUITheme.CORNER_RADIUS
	draw_style_box(sb, tab_rect)
	if active:
		draw_rect(Rect2(tab_rect.position.x + 1, tab_rect.position.y, tab_rect.size.x - 2, 2), C_GOLD)

	_text_with(
		FONT_BUTTON,
		_box(tab_rect.position.x, tab_rect.position.y + 2.0, tab_rect.size.x, tab_rect.size.y - 4.0),
		label,
		14,
		C_GOLD_HI if active else C_DIM,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1.0
	)


# =============================================================================
# PÁGINA 0 — TRAMO (CLIMATOLOGÍA DE 5 SECTORES + COMPOSICIÓN DEL TERRENO)
# =============================================================================


func _resolve_briefing_stage_id() -> String:
	var cid := circuit_id.strip_edges().to_lower().replace("-", "_")
	var regex := RegEx.new()
	regex.compile("^([a-z_]+)_stage_(\\d+)$")
	var m := regex.search(cid)
	if m != null:
		return "%s_stage%s" % [m.get_string(1), m.get_string(2)]
	return cid


func _ensure_stage_briefing() -> void:
	var sid := _resolve_briefing_stage_id()
	var key := "%s|%s|%0.1f" % [sid, stage_weather_label, _effective_stage_length_m()]
	if key == _briefing_cache_key and _stage_sectors.size() == 5 and not _stage_terrain.is_empty():
		return
	_briefing_cache_key = key

	var total_m := maxf(_effective_stage_length_m(), 500.0)
	var stage_cfg_path := "res://data/competition/stages/%s.json" % sid
	var stage_cfg: Dictionary = {}
	if not sid.is_empty() and FileAccess.file_exists(stage_cfg_path):
		var p_cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(stage_cfg_path))
		if p_cfg is Dictionary:
			stage_cfg = p_cfg as Dictionary

	var manifest_path := "res://assets/rally/%s/manifest.json" % sid
	var manifest: Dictionary = {}
	if not sid.is_empty() and FileAccess.file_exists(manifest_path):
		var p_man: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if p_man is Dictionary:
			manifest = p_man as Dictionary
	var src: Dictionary = manifest.get("source", {})

	var raw_surface := str(stage_cfg.get("surface", "gravel_mud")).to_lower()
	var is_asphalt := raw_surface == "asphalt"

	# Si el padre es la sesión con event_weather activo, leer directo si faltaban datos
	var parent_node := get_parent()
	var ew: Variant = parent_node.get("event_weather") if parent_node != null else null
	if _stage_sectors.is_empty() and ew != null and ew.has_method("sector_summary"):
		var ew_sectors: Array = ew.call("sector_summary") as Array
		if not ew_sectors.is_empty():
			_stage_sectors = ew_sectors.duplicate(true)

	# Si el tramo tiene clima procedural Rust y aún no tenemos sectores, instanciar snapshot Rust
	if _stage_sectors.is_empty():
		var proc_cfg: Variant = stage_cfg.get("procedural_climate", {})
		if proc_cfg is Dictionary and bool((proc_cfg as Dictionary).get("enabled", false)):
			var w_lbl := stage_weather_label.strip_edges().to_lower()
			var regime := ""
			if "lluvia" in w_lbl or "rain" in w_lbl or "húmedo" in w_lbl:
				regime = "wet_front"
			elif "nubl" in w_lbl or "cloud" in w_lbl:
				regime = "cloudy"
			elif "sol" in w_lbl or "desp" in w_lbl or "clear" in w_lbl:
				regime = "clear"
			var surf_arg := "asphalt" if is_asphalt else "gravel"
			var built := RallyWeatherScheduler.build_five_sector_snapshot_for_stage(
				sid, 2026, "transition", 34800.0, 35220.0, surf_arg, regime
			)
			if bool(built.get("ok", false)):
				var eng: RefCounted = built.get("engine") as RefCounted
				if eng != null:
					_stage_sectors = (eng.call("sector_summary") as Array).duplicate(true)
					var l_sum := 0.0
					var m_sum := 0.0
					var w_sum := 0.0
					var sn_sum := 0.0
					var ic_sum := 0.0
					var samples := 0
					for si in _stage_sectors.size():
						var s_row: Dictionary = _stage_sectors[si]
						var s0 := float(s_row.get("start_m", float(si) * total_m / 5.0))
						var s1 := float(s_row.get("end_m", float(si + 1) * total_m / 5.0))
						var sl := 0.0
						var sm := 0.0
						var sw := 0.0
						var ss := 0.0
						var sic := 0.0
						for k in 5:
							var d := lerpf(s0, s1, (float(k) + 0.5) / 5.0)
							var samp: Variant = eng.call("sample_surface_at", d, 0.0)
							if samp is Dictionary and bool((samp as Dictionary).get("ok", false)):
								var sd := samp as Dictionary
								sl += float(sd.get("loose_gravel_coverage", 0.0))
								sm += float(sd.get("mud_factor", 0.0))
								sw += float(sd.get("water_coverage", 0.0))
								ss += float(sd.get("snow_coverage", 0.0))
								sic += float(sd.get("ice_coverage", 0.0))
								samples += 1
						s_row["loose_gravel_coverage"] = sl / 5.0
						s_row["mud_factor"] = sm / 5.0
						s_row["water_coverage"] = sw / 5.0
						s_row["snow_coverage"] = ss / 5.0
						s_row["ice_coverage"] = sic / 5.0
						_stage_sectors[si] = s_row
						l_sum += sl
						m_sum += sm
						w_sum += sw
						sn_sum += ss
						ic_sum += sic
					if _stage_terrain.is_empty() and samples > 0:
						_stage_terrain = {
							"source": "rust",
							"is_asphalt": is_asphalt,
							"surface_raw": raw_surface,
							"loose_gravel_avg": l_sum / float(samples),
							"mud_avg": m_sum / float(samples),
							"water_avg": w_sum / float(samples),
							"snow_avg": sn_sum / float(samples),
							"ice_avg": ic_sum / float(samples),
						}

	# Respaldo determinista si el stage no tiene snapshot Rust 5-sectores
	if _stage_sectors.size() != 5:
		_stage_sectors.clear()
		var w_low := _get_stage_weather_text().to_lower()
		var is_sweden := sid.begins_with("sweden_") or sid == "russia_stage7" or sid == "russia_stage8"
		var is_rain := "lluvia" in w_low or "rain" in w_low or "tormenta" in w_low or "llovizna" in w_low
		var is_cloud := "nubl" in w_low or "cubiert" in w_low or "niebla" in w_low
		var base_temp := -3.0 if is_sweden else (13.0 if is_rain else 18.0)
		var wetness_cfg := float(stage_cfg.get("wetness", 0.25))
		for si in 5:
			var s0 := float(si) * total_m / 5.0
			var s1 := float(si + 1) * total_m / 5.0
			var rain_v := 0.0
			var water_v := 0.0
			var snow_v := 0.0
			var ice_v := 0.0
			var cloud_v := 0.2
			if is_sweden:
				snow_v = 2.8 if si < 4 else 1.5
				ice_v = 0.6 if (si == 1 or si == 3) else 0.15
				cloud_v = 0.65
			elif is_rain:
				rain_v = 1.6 if si in [1, 2, 3] else 0.5
				water_v = 0.8 + float(si % 2) * 0.4 + wetness_cfg
				cloud_v = 0.85
			elif is_cloud:
				water_v = wetness_cfg * 0.6 if si in [2, 3] else 0.05
				cloud_v = 0.7
			else:
				water_v = wetness_cfg * 0.4 if (si == 2 and float(stage_cfg.get("water", 0.0)) > 0.2) else 0.0
				cloud_v = 0.22
			_stage_sectors.append({
				"sector_index": si,
				"start_m": s0,
				"end_m": s1,
				"air_c": base_temp - float(si) * 0.3,
				"ground_c": base_temp + (1.5 if not is_rain and not is_sweden else 0.0),
				"cloud_cover": cloud_v,
				"rain_mm_h": rain_v,
				"snow_mm_h": 0.4 if is_sweden else 0.0,
				"water_mm": water_v,
				"snow_mm": snow_v,
				"ice_mm": ice_v,
			})

	if _stage_terrain.is_empty():
		var roughness := float(stage_cfg.get("roughness", 0.35))
		var wetness := float(stage_cfg.get("wetness", 0.2))
		var water_cfg := float(stage_cfg.get("water", 0.1))
		var w_low := _get_stage_weather_text().to_lower()
		var is_sweden := sid.begins_with("sweden_") or sid == "russia_stage7" or sid == "russia_stage8"
		var is_rain := "lluvia" in w_low or "rain" in w_low or "llovizna" in w_low
		var loose_est := clampf(0.18 + roughness * 0.35, 0.10, 0.50) if not is_asphalt else 0.0
		var mud_est := clampf((wetness * 0.45 + water_cfg * 0.35) * (1.4 if is_rain else 0.5), 0.0, 0.42) if not is_asphalt else 0.0
		var water_est := clampf((wetness * 0.5 + (0.35 if is_rain else 0.0)), 0.0, 0.75) if is_asphalt else 0.0
		var snow_est := 0.72 if is_sweden else 0.0
		var ice_est := 0.18 if (is_sweden or sid == "russia_stage8") else 0.0
		_stage_terrain = {
			"source": "stage_data",
			"is_asphalt": is_asphalt,
			"surface_raw": raw_surface,
			"loose_gravel_avg": loose_est,
			"mud_avg": mud_est,
			"water_avg": water_est,
			"snow_avg": snow_est,
			"ice_avg": ice_est,
			"roughness": roughness,
			"water_cfg": water_cfg,
			"wetness_cfg": wetness,
			"jumps": float(stage_cfg.get("jumps", 0.0)),
			"pothole_count": int(src.get("pothole_count", 0)),
			"rocks_count": 200 if sid in ["cdi_stage1", "cdi_stage2"] else 0,
			"has_rock_slope": (src.get("slope_texture") is Dictionary and "pedregal" in str((src.get("slope_texture") as Dictionary).get("file", "")).to_lower()),
			"puddles_active": 0,
		}
	else:
		if not _stage_terrain.has("roughness"):
			_stage_terrain["roughness"] = float(stage_cfg.get("roughness", 0.35))
		if not _stage_terrain.has("water_cfg"):
			_stage_terrain["water_cfg"] = float(stage_cfg.get("water", 0.1))
		if not _stage_terrain.has("pothole_count"):
			_stage_terrain["pothole_count"] = int(src.get("pothole_count", 0))
		if not _stage_terrain.has("rocks_count") or int(_stage_terrain.get("rocks_count", 0)) == 0:
			if sid in ["cdi_stage1", "cdi_stage2"]:
				_stage_terrain["rocks_count"] = 200
		if not _stage_terrain.has("has_rock_slope"):
			_stage_terrain["has_rock_slope"] = (src.get("slope_texture") is Dictionary and "pedregal" in str((src.get("slope_texture") as Dictionary).get("file", "")).to_lower())


func _sector_weather_badge(sector: Dictionary) -> Dictionary:
	var has_cov := sector.has("ice_coverage")
	var ice_cov := float(sector.get("ice_coverage", 0.0))
	var snow_cov := float(sector.get("snow_coverage", 0.0))
	var water_cov := float(sector.get("water_coverage", 0.0))
	var ice := float(sector.get("ice_mm", 0.0))
	var snow := float(sector.get("snow_mm", 0.0))
	var snow_rate := float(sector.get("snow_mm_h", 0.0))
	var rain_rate := float(sector.get("rain_mm_h", 0.0))
	var water := float(sector.get("water_mm", 0.0))
	var cloud := float(sector.get("cloud_cover", 0.0))
	var ground_c := float(sector.get("ground_c", 5.0))

	if (has_cov and ice_cov >= 0.08) or (not has_cov and ice >= 0.25 and ground_c <= 0.0):
		return { "label": "HIELO", "color": Color("#22d3ee"), "detail": "%.1f mm hielo" % maxf(ice, snow) }
	if snow_cov >= 0.08 or snow_rate >= 0.35 or (snow >= 0.45 and ground_c <= 2.0):
		return { "label": "NIEVE", "color": Color("#e0f2fe"), "detail": "%.1f mm nieve" % snow }
	if rain_rate >= 0.35:
		return { "label": "LLUVIA", "color": Color("#38bdf8"), "detail": "%.1f mm/h · %.1f mm" % [rain_rate, water] }
	if water >= 0.20 or water_cov >= 0.15:
		return { "label": "HÚMEDO", "color": Color("#60a5fa"), "detail": "%.1f mm agua" % water }
	if cloud >= 0.50:
		return { "label": "NUBLADO", "color": Color("#94a3b8"), "detail": "Piso seco" }
	return { "label": "SECO", "color": C_GOLD, "detail": "Piso seco" }


func _draw_stage_page() -> void:
	_ensure_stage_briefing()
	_ensure_stage_route_cache()

	# Columna izquierda: Trazado y Meteorología (mapa amplio + 5 tarjetas S1..S5)
	var left_panel := Rect2(36, PAGE_TOP, 636, 518)
	_group(left_panel, "TRAZADO Y METEOROLOGÍA")
	var l_inner := _group_inner(left_panel)

	# 3 Mini-pastillas arriba (Distancia, Clima, Aire/Pista)
	var air_sum := 0.0
	var gnd_sum := 0.0
	for s in _stage_sectors:
		air_sum += float((s as Dictionary).get("air_c", 15.0))
		gnd_sum += float((s as Dictionary).get("ground_c", 15.0))
	var n_sec := float(maxi(_stage_sectors.size(), 1))
	var chips := [
		{ "k": "DISTANCIA", "v": _get_stage_distance_text(), "col": C_TEXT },
		{ "k": "CLIMA", "v": _get_stage_weather_text(), "col": C_GOLD },
		{ "k": "AIRE / PISTA", "v": "%d° / %d°C" % [roundi(air_sum / n_sec), roundi(gnd_sum / n_sec)], "col": C_TEXT },
	]
	var chip_gap := 8.0
	var chip_w := floorf((l_inner.size.x - chip_gap * 2.0) / 3.0)
	for i in chips.size():
		var cr := Rect2(l_inner.position.x + float(i) * (chip_w + chip_gap), l_inner.position.y, chip_w, 42)
		draw_rect(cr, C_FIELD)
		_sunken(cr)
		_text(_box(cr.position.x + 10, cr.position.y + 3, cr.size.x - 20, 14), str(chips[i].k), 9, C_DIM, true)
		_text(_box(cr.position.x + 10, cr.position.y + 19, cr.size.x - 20, 20), str(chips[i].v), 11, chips[i].col, true)

	# Mapa ampliado del trazado coloreado por los 5 sectores (sin leyenda inferior)
	var map_rect := Rect2(l_inner.position.x, l_inner.position.y + 50, l_inner.size.x, 314)
	_draw_five_sector_route_preview(map_rect)

	# Tira limpia de 5 sectores (S1..S5): solo código, estado y temperatura
	var strip_y := map_rect.end.y + 10.0
	var sec_gap := 8.0
	var sec_w := floorf((l_inner.size.x - sec_gap * 4.0) / 5.0)
	var strip_h := l_inner.end.y - strip_y
	for si in mini(5, _stage_sectors.size()):
		var sd: Dictionary = _stage_sectors[si]
		var badge := _sector_weather_badge(sd)
		var col: Color = badge["color"]
		var card := Rect2(l_inner.position.x + float(si) * (sec_w + sec_gap), strip_y, sec_w, strip_h)
		draw_rect(card, C_FIELD)
		_sunken(card)
		draw_rect(Rect2(card.position.x, card.position.y, card.size.x, 3), col)

		_text_with(FONT_SUBTITLE, _box(card.position.x + 8, card.position.y + 8, card.size.x - 16, 20), "S%d" % (si + 1), 15, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, card.size.x - 16)

		var pill := Rect2(card.position.x + 8, card.position.y + 34, card.size.x - 16, 26)
		draw_style_box(RallyUITheme.make_flat_panel(Color(col, 0.16), Color(col, 0.70), 1, RallyUITheme.CORNER_RADIUS), pill)
		_text_with(FONT_BUTTON, pill, str(badge["label"]), 11, col, HORIZONTAL_ALIGNMENT_CENTER, -1.0)

		var air_i := roundi(float(sd.get("air_c", 15.0)))
		_num(_box(card.position.x + 8, card.position.y + 68, card.size.x - 16, 24), "%d °C" % air_i, 13, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, card.size.x - 16)

	# Columna derecha arriba: Composición del terreno
	var terrain_panel := Rect2(684, PAGE_TOP, 560, 256)
	_draw_terrain_composition_group(terrain_panel)

	# Columna derecha abajo: Perfil de altitud del trazado
	var alt_panel := Rect2(684, 424, 560, 250)
	_draw_altitude_profile_group(alt_panel)


func _draw_five_sector_route_preview(rect: Rect2) -> void:
	draw_rect(rect, C_FIELD)
	_sunken(rect)

	if _cached_route_points.size() < 2:
		_hint(_box(rect.position.x + 12, rect.position.y, rect.size.x - 24, rect.size.y), "SIN TRAZADO DISPONIBLE", HORIZONTAL_ALIGNMENT_CENTER)
		return

	var pad_side := 24.0
	var pad_vert := 20.0
	var avail_w := rect.size.x - pad_side * 2.0
	var avail_h := rect.size.y - pad_vert * 2.0
	if avail_w <= 10.0 or avail_h <= 10.0:
		return

	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for p in _cached_route_points:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var extent := max_p - min_p
	extent.x = maxf(extent.x, 0.001)
	extent.y = maxf(extent.y, 0.001)

	var fit_scale := minf(avail_w / extent.x, avail_h / extent.y)
	var draw_size := extent * fit_scale
	var origin := rect.position + Vector2(pad_side, pad_vert) + (Vector2(avail_w, avail_h) - draw_size) * 0.5 - min_p * fit_scale

	var screen_pts := PackedVector2Array()
	for p in _cached_route_points:
		screen_pts.append(origin + p * fit_scale)

	var total_pts := screen_pts.size()
	for si in 5:
		var i0 := floori(float(si) * float(total_pts - 1) / 5.0)
		var i1 := floori(float(si + 1) * float(total_pts - 1) / 5.0)
		if si == 4:
			i1 = total_pts - 1
		if i1 <= i0:
			continue
		var seg := PackedVector2Array()
		for k in range(i0, i1 + 1):
			seg.append(screen_pts[k])
		var sd: Dictionary = _stage_sectors[si] if si < _stage_sectors.size() else {}
		var col: Color = _sector_weather_badge(sd).get("color", C_GOLD)
		draw_polyline(seg, Color(col, 0.25), 8.0, true)
		draw_polyline(seg, col, 3.4, true)

	for si in 5:
		var idx := floori((float(si) + 0.5) * float(total_pts - 1) / 5.0)
		var pt := screen_pts[clampi(idx, 0, total_pts - 1)]
		var sd: Dictionary = _stage_sectors[si] if si < _stage_sectors.size() else {}
		var col: Color = _sector_weather_badge(sd).get("color", C_GOLD)
		draw_circle(pt, 9.5, Color(BG_BASE, 0.90))
		draw_arc(pt, 9.5, 0.0, TAU, 16, col, 1.4, true)
		_num(_box(pt.x - 10, pt.y - 7, 20, 14), "S%d" % (si + 1), 8, col, HORIZONTAL_ALIGNMENT_CENTER, 20.0)

	var start_pt := screen_pts[0]
	var finish_pt := screen_pts[total_pts - 1]
	draw_circle(start_pt, 5.5, STATUS_SUCCESS)
	draw_arc(start_pt, 5.5, 0.0, TAU, 16, C_TEXT, 1.3, true)
	draw_circle(finish_pt, 5.5, C_ROSE)
	draw_arc(finish_pt, 5.5, 0.0, TAU, 16, C_TEXT, 1.3, true)


func _terrain_composition_bars() -> Array[Dictionary]:
	var is_asphalt := bool(_stage_terrain.get("is_asphalt", false))
	var loose := clampf(float(_stage_terrain.get("loose_gravel_avg", 0.0)), 0.0, 1.0)
	var mud := clampf(float(_stage_terrain.get("mud_avg", 0.0)), 0.0, 1.0)
	var water := clampf(float(_stage_terrain.get("water_avg", 0.0)), 0.0, 1.0)
	var snow := clampf(float(_stage_terrain.get("snow_avg", 0.0)), 0.0, 1.0)
	var ice := clampf(float(_stage_terrain.get("ice_avg", 0.0)), 0.0, 1.0)

	# Incorporar sectores activos (lluvia / agua / nieve) para coherencia visual con el mapa S1..S5
	if not _stage_sectors.is_empty():
		var sec_wet := 0.0
		var sec_snow := 0.0
		for sd in _stage_sectors:
			var lbl := str(_sector_weather_badge(sd as Dictionary).get("label", "SECO"))
			if lbl in ["LLUVIA", "HÚMEDO"]:
				sec_wet += 1.0
			elif lbl in ["NIEVE", "HIELO"]:
				sec_snow += 1.0
		var n_s := float(_stage_sectors.size())
		water = maxf(water, (sec_wet / n_s) * (0.65 if is_asphalt else 0.35))
		snow = maxf(snow, (sec_snow / n_s) * 0.25)

	var winter_frac := clampf(snow + ice, 0.0, 1.0)
	var rem := maxf(1.0 - winter_frac, 0.0)
	var bars: Array[Dictionary] = []

	if is_asphalt:
		var wet_frac := clampf(water, 0.0, rem)
		var dry_frac := maxf(rem - wet_frac, 0.0)
		bars.append({ "label": "ASFALTO SECO", "pct": roundi(dry_frac * 100.0), "color": Color("#94a3b8") })
		bars.append({ "label": "ASFALTO MOJADO", "pct": roundi(wet_frac * 100.0), "color": Color("#38bdf8") })
		bars.append({ "label": "NIEVE / HIELO", "pct": roundi(winter_frac * 100.0), "color": Color("#bae6fd") })
	else:
		var loose_frac := clampf(loose * (1.0 - mud) * rem, 0.0, rem)
		var mud_frac := clampf(maxf(mud, water * 0.65) * rem, 0.0, maxf(rem - loose_frac, 0.0))
		var compact_frac := maxf(rem - loose_frac - mud_frac, 0.0)
		bars.append({ "label": "GRAVA COMPACTA", "pct": roundi(compact_frac * 100.0), "color": Color("#c89b54") })
		bars.append({ "label": "GRAVILLA SUELTA", "pct": roundi(loose_frac * 100.0), "color": C_GOLD })
		bars.append({ "label": "BARRO / MOJADO", "pct": roundi(mud_frac * 100.0), "color": Color("#38bdf8") })
		bars.append({ "label": "NIEVE / HIELO", "pct": roundi(winter_frac * 100.0), "color": Color("#bae6fd") })

	# Ajuste exacto para sumar 100%
	var total := 0
	var max_idx := 0
	for i in bars.size():
		total += int(bars[i]["pct"])
		if int(bars[i]["pct"]) > int(bars[max_idx]["pct"]):
			max_idx = i
	if total != 100 and not bars.is_empty():
		bars[max_idx]["pct"] = maxi(0, int(bars[max_idx]["pct"]) + (100 - total))
	return bars


func _draw_terrain_composition_group(rect: Rect2) -> void:
	_group(rect, "COMPOSICIÓN DEL TERRENO")
	var inner := _group_inner(rect)

	var bars := _terrain_composition_bars()
	# Barra apilada 100%
	var stack_rect := Rect2(inner.position.x, inner.position.y + 2, inner.size.x, 16)
	draw_rect(stack_rect, C_FIELD)
	_sunken(stack_rect)
	var cur_x := stack_rect.position.x + 1.0
	var avail_w := stack_rect.size.x - 2.0
	for b in bars:
		var pct := int(b["pct"])
		if pct <= 0:
			continue
		var seg_w := avail_w * (float(pct) / 100.0)
		draw_rect(Rect2(cur_x, stack_rect.position.y + 1, seg_w, stack_rect.size.y - 2), b["color"], true)
		cur_x += seg_w

	# Barras individuales redistribuidas en la altura disponible
	var y := stack_rect.end.y + 10.0
	var row_gap := 6.0
	var n_bars := maxi(bars.size(), 1)
	var row_h := floorf((inner.end.y - y - row_gap * float(n_bars - 1)) / float(n_bars))
	for b in bars:
		var pct := int(b["pct"])
		var row_r := Rect2(inner.position.x, y, inner.size.x, row_h)
		draw_rect(row_r, C_FIELD)
		_sunken(row_r)
		draw_rect(Rect2(row_r.position.x, row_r.position.y, 4, row_r.size.y), b["color"])
		var content_y := row_r.position.y + maxf((row_r.size.y - 30.0) * 0.5, 4.0)
		_text(_box(row_r.position.x + 12, content_y, 200, 16), str(b["label"]), 11, C_TEXT if pct > 0 else C_DIM, pct > 0)
		_num(_box(row_r.end.x - 76, content_y, 64, 16), "%d%%" % pct, 12, b["color"] if pct > 0 else C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 64)
		var bar_bg := Rect2(row_r.position.x + 12, content_y + 21.0, row_r.size.x - 24, 8)
		draw_rect(bar_bg, BG_BASE)
		if pct > 0:
			draw_rect(Rect2(bar_bg.position.x, bar_bg.position.y, bar_bg.size.x * (float(pct) / 100.0), bar_bg.size.y), b["color"], true)
		y += row_h + row_gap


func _draw_altitude_profile_group(rect: Rect2) -> void:
	_group(rect, "PERFIL DE ALTITUD")
	var inner := _group_inner(rect)
	var heights := _cached_profile_altitudes if _cached_profile_altitudes.size() >= 2 else _cached_route_heights
	if heights.size() < 2:
		_hint(_box(inner.position.x, inner.position.y, inner.size.x, inner.size.y), "SIN PERFIL DE ALTITUD", HORIZONTAL_ALIGNMENT_CENTER)
		return

	var min_h := INF
	var max_h := -INF
	for h in heights:
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)
	var span_h := maxf(max_h - min_h, 1.0)
	var total_km := maxf(_effective_stage_length_m() / 1000.0, 0.1)

	var plot := Rect2(inner.position.x, inner.position.y + 2, inner.size.x, inner.size.y - 4)
	draw_rect(plot, C_FIELD)
	_sunken(plot)

	var left_pad := 58.0
	var right_pad := 14.0
	var top_pad := 10.0
	var bottom_pad := 22.0
	var chart_x0 := plot.position.x + left_pad
	var chart_x1 := plot.end.x - right_pad
	var chart_y0 := plot.position.y + top_pad
	var chart_y1 := plot.end.y - bottom_pad
	var pw := chart_x1 - chart_x0
	var ph := chart_y1 - chart_y0

	# Eje Y (altitud en metros) + guías horizontales
	var axis_col := Color(1.0, 1.0, 1.0, 0.24)
	draw_line(Vector2(chart_x0, chart_y0), Vector2(chart_x0, chart_y1), axis_col, 1.0)
	draw_line(Vector2(chart_x0, chart_y1), Vector2(chart_x1, chart_y1), axis_col, 1.0)

	for yi in 4:
		var frac := float(yi) / 3.0
		var ty := chart_y1 - frac * ph
		var alt_val := roundi(lerpf(min_h, max_h, frac))
		draw_line(Vector2(chart_x0 - 4, ty), Vector2(chart_x0, ty), axis_col, 1.0)
		if yi > 0:
			draw_line(Vector2(chart_x0, ty), Vector2(chart_x1, ty), Color(1.0, 1.0, 1.0, 0.06), 1.0)
		_num(_box(plot.position.x + 2, ty - 7, left_pad - 9, 14), "%d m" % alt_val, 9, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, left_pad - 9)

	# Eje X (distancia en kilómetros) + guías verticales
	for xi in 5:
		var frac := float(xi) * 0.25
		var tx := chart_x0 + frac * pw
		var dist_km := total_km * frac
		draw_line(Vector2(tx, chart_y1), Vector2(tx, chart_y1 + 4), axis_col, 1.0)
		if xi > 0 and xi < 4:
			draw_line(Vector2(tx, chart_y0), Vector2(tx, chart_y1), Color(1.0, 1.0, 1.0, 0.06), 1.0)
		var km_txt := "%.1f km" % dist_km
		if xi == 0:
			_num(_box(tx, chart_y1 + 4, 56, 14), km_txt, 9, C_DIM, HORIZONTAL_ALIGNMENT_LEFT, 56)
		elif xi == 4:
			_num(_box(tx - 56, chart_y1 + 4, 56, 14), km_txt, 9, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 56)
		else:
			_num(_box(tx - 28, chart_y1 + 4, 56, 14), km_txt, 9, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 56)

	# Muestreo a ~64 puntos para curva limpia alineada a los ejes
	var n_pts := mini(64, heights.size())
	var line_pts := PackedVector2Array()
	var poly_pts := PackedVector2Array()
	for i in n_pts:
		var t := float(i) / float(n_pts - 1)
		var src_idx := clampi(roundi(t * float(heights.size() - 1)), 0, heights.size() - 1)
		var norm_y := (heights[src_idx] - min_h) / span_h
		var pt := Vector2(chart_x0 + t * pw, chart_y1 - norm_y * ph)
		line_pts.append(pt)
		poly_pts.append(pt)
	poly_pts.append(Vector2(chart_x1, chart_y1))
	poly_pts.append(Vector2(chart_x0, chart_y1))

	draw_colored_polygon(poly_pts, Color(C_GOLD, 0.16))
	draw_polyline(line_pts, C_GOLD, 2.2, true)
	draw_circle(line_pts[0], 3.5, STATUS_SUCCESS)
	draw_circle(line_pts[line_pts.size() - 1], 3.5, C_ROSE)


# =============================================================================
# PÁGINA 1 — CHASIS Y FRENOS
# =============================================================================


func _draw_chassis_page() -> void:
	# Columna izquierda: Suspensión + Estabilizadoras (arriba) y Frenos (abajo)
	var susp_panel := Rect2(36, PAGE_TOP, 600, 296)
	_group(susp_panel, "SUSPENSIÓN Y ESTABILIZADORAS")
	var s_inner := _group_inner(susp_panel)
	var s_row_h := floorf(s_inner.size.y / 3.0)
	_segmented_5_row(
		Rect2(s_inner.position.x, s_inner.position.y, s_inner.size.x, s_row_h),
		"garage.suspension",
		"Tarado y altura",
		["Blanda", "Semi-B", "Equil.", "Semi-R", "Rígida"],
		[5.0, 4.0, 3.0, 2.0, 1.0],
		"◀ BACHES / TIERRA",
		"ASFALTO LISO ▶",
		false
	)
	_segmented_5_row(
		Rect2(s_inner.position.x, s_inner.position.y + s_row_h, s_inner.size.x, s_row_h),
		"garage.front_arb",
		"Estabilizadora del.",
		["Blanda", "Semi-B", "Equil.", "Semi-R", "Rígida"],
		[5.0, 4.0, 3.0, 2.0, 1.0],
		"◀ + AGARRE DEL.",
		"+ PRECISIÓN GIRO ▶",
		false
	)
	_segmented_5_row(
		Rect2(s_inner.position.x, s_inner.position.y + s_row_h * 2.0, s_inner.size.x, s_row_h),
		"garage.rear_arb",
		"Estabilizadora tras.",
		["Blanda", "Semi-B", "Equil.", "Semi-R", "Rígida"],
		[5.0, 4.0, 3.0, 2.0, 1.0],
		"◀ + TRACCIÓN",
		"+ ROTACIÓN TRASERA ▶",
		true
	)

	var brakes_panel := Rect2(36, 464, 600, 210)
	_group(brakes_panel, "FRENOS")
	var b_inner := _group_inner(brakes_panel)
	_slider_row(
		Rect2(b_inner.position.x, b_inner.position.y + 4, b_inner.size.x, 86),
		"brakes.front_brake_bias",
		"Reparto de frenada",
		"◀ MÁS TRASERA",
		"MÁS DELANTERA ▶",
		true
	)
	var brake_note := Rect2(b_inner.position.x, b_inner.position.y + 98, b_inner.size.x, 66)
	draw_rect(brake_note, C_FIELD)
	_sunken(brake_note)
	var front_pct := roundi(float(draft_values.get("brakes.front_brake_bias", 0.55)) * 100.0)
	var rear_pct := 100 - front_pct
	_text(_box(brake_note.position.x + 12, brake_note.position.y + 8, brake_note.size.x - 24, 20), "BALANCE ACTUAL: %d%% DELANTERO  /  %d%% TRASERO" % [front_pct, rear_pct], 10, C_GOLD_HI, true)
	_text(_box(brake_note.position.x + 12, brake_note.position.y + 32, brake_note.size.x - 24, 24), "Adelantarlo evita bloqueos atrás; retrasarlo ayuda a cruzar el coche al entrar.", 10, C_DIM)

	# Columna derecha: Geometría (arriba) y Trazado del Tramo (abajo)
	var geom_panel := Rect2(652, PAGE_TOP, 592, 296)
	_group(geom_panel, "GEOMETRÍA (POR EJE)")
	var g_inner := _group_inner(geom_panel)
	var g_row_h := floorf(g_inner.size.y / 4.0)
	_slider_row(
		Rect2(g_inner.position.x, g_inner.position.y, g_inner.size.x, g_row_h),
		"suspension.front.camber",
		"Caída delantera",
		"◀ + APOYO CURVA",
		"RECTA ▶",
		false,
		"camber"
	)
	_slider_row(
		Rect2(g_inner.position.x, g_inner.position.y + g_row_h, g_inner.size.x, g_row_h),
		"suspension.rear.camber",
		"Caída trasera",
		"◀ + ESTABLE CURVA",
		"RECTA ▶",
		false,
		"camber"
	)
	_slider_row(
		Rect2(g_inner.position.x, g_inner.position.y + g_row_h * 2.0, g_inner.size.x, g_row_h),
		"suspension.front.toe",
		"Convergencia del.",
		"◀ ÁGIL (-)",
		"ESTABLE (+) ▶",
		false,
		"toe"
	)
	_slider_row(
		Rect2(g_inner.position.x, g_inner.position.y + g_row_h * 3.0, g_inner.size.x, g_row_h),
		"suspension.rear.toe",
		"Convergencia tras.",
		"◀ SUELTA (-)",
		"ESTABLE (+) ▶",
		true,
		"toe"
	)

	var balance_panel := Rect2(652, 464, 592, 210)
	_draw_chassis_balance_group(balance_panel)


func _draw_chassis_balance_group(rect: Rect2) -> void:
	_group(rect, "BALANCE RESULTANTE DEL CHASIS")
	var inner := _group_inner(rect)
	var susp := float(draft_values.get("garage.suspension", 3.0))
	var f_arb := float(draft_values.get("garage.front_arb", 3.0))
	var r_arb := float(draft_values.get("garage.rear_arb", 3.0))
	var f_bias := float(draft_values.get("brakes.front_brake_bias", 0.55))

	# 1) Rigidez: 5 (blanda) -> 0.0, 1 (rígida) -> 1.0
	var stiff_frac := clampf((5.0 - susp) / 4.0, 0.0, 1.0)
	_draw_balance_meter(
		Rect2(inner.position.x, inner.position.y + 4, inner.size.x, 54),
		"RIGIDEZ Y ALTURA",
		"Blanda · Baches",
		"Rígida · Asfalto",
		stiff_frac
	)

	# 2) Tendencia en curva: ARB trasera rígida (bajo num) - ARB del rígida (bajo num)
	var arb_delta := (f_arb - r_arb) * 0.12
	var brake_delta := (0.55 - f_bias) * 1.2
	var oversteer_frac := clampf(0.5 + arb_delta + brake_delta, 0.05, 0.95)
	_draw_balance_meter(
		Rect2(inner.position.x, inner.position.y + 66, inner.size.x, 54),
		"TENDENCIA EN CURVA",
		"Subviraje (Estable)",
		"Sobreviraje (Ágil)",
		oversteer_frac
	)

	var note_r := Rect2(inner.position.x, inner.position.y + 128, inner.size.x, 40)
	draw_rect(note_r, C_FIELD)
	_sunken(note_r)
	var char_txt := "Neutro y predecible"
	if oversteer_frac < 0.40:
		char_txt = "Tendencia SUBVIRADORA: entra estable, le cuesta cerrar giro."
	elif oversteer_frac > 0.60:
		char_txt = "Tendencia SOBREVIRADORA: morro ágil, zaga viva al soltar o frenar."
	else:
		char_txt = "Balance EQUILIBRADO entre entrada en curva y tracción a la salida."
	_text(_box(note_r.position.x + 12, note_r.position.y, note_r.size.x - 24, note_r.size.y), char_txt, 10, C_GOLD_HI)


func _draw_balance_meter(rect: Rect2, title: String, left_lbl: String, right_lbl: String, frac: float) -> void:
	draw_rect(rect, C_FIELD)
	_sunken(rect)
	_text(_box(rect.position.x + 12, rect.position.y + 4, 180, 18), title, 10, C_TEXT, true)
	_text(_box(rect.position.x + 190, rect.position.y + 4, 180, 18), left_lbl, 9, C_DIM)
	_text(_box(rect.end.x - 190, rect.position.y + 4, 178, 18), right_lbl, 9, C_DIM, false, HORIZONTAL_ALIGNMENT_RIGHT, 178)
	var track := Rect2(rect.position.x + 12, rect.position.y + 30, rect.size.x - 24, 10)
	draw_rect(track, BG_BASE)
	_sunken(track)
	var center_x := track.position.x + track.size.x * 0.5
	draw_rect(Rect2(center_x - 1, track.position.y - 2, 2, track.size.y + 4), WB_BORDER_HOVER)
	var marker_x := track.position.x + track.size.x * clampf(frac, 0.0, 1.0)
	draw_rect(Rect2(marker_x - 5, track.position.y - 3, 10, track.size.y + 6), C_GOLD)


# =============================================================================
# PÁGINA 1 — MOTOR Y CAJA
# =============================================================================


func _draw_powertrain_page() -> void:
	# Columna izquierda: Motor y Desarrollo (arriba) + Velocidad por marcha en vivo (abajo)
	var engine_panel := Rect2(36, PAGE_TOP, 600, 272)
	_group(engine_panel, "MOTOR Y DESARROLLO")
	var e_inner := _group_inner(engine_panel)
	var e_row_h := floorf(e_inner.size.y / 3.0)
	_slider_row(
		Rect2(e_inner.position.x, e_inner.position.y, e_inner.size.x, e_row_h),
		"powertrain.final_drive",
		"Relación final",
		"◀ VEL. PUNTA (LARGO)",
		"ACELERACIÓN (CORTO) ▶",
		false
	)
	_slider_row(
		Rect2(e_inner.position.x, e_inner.position.y + e_row_h, e_inner.size.x, e_row_h),
		"powertrain.max_rpm",
		"Limitador de RPM",
		"◀ MENOR CONSUMO",
		"MÁX. ESTIRADA ▶",
		false
	)
	_segmented_5_row(
		Rect2(e_inner.position.x, e_inner.position.y + e_row_h * 2.0, e_inner.size.x, e_row_h),
		"garage.cooling",
		"Refrigeración",
		["Serie", "25%", "50%", "75%", "100%"],
		[0.0, 1.0, 2.0, 3.0, 4.0],
		"◀ MENOS RESISTENCIA",
		"MÁS FRÍO ▶",
		true
	)

	_draw_gear_chart(Rect2(36, 440, 600, 234))

	# Columna derecha: Diferencial completo + resumen de comportamiento
	var diff_panel := Rect2(652, PAGE_TOP, 592, 518)
	_group(diff_panel, "DIFERENCIAL")
	var d_inner := _group_inner(diff_panel)
	var lsd_enabled := bool(draft_values.get("garage.lsd", 0.0))

	_segmented_5_row(
		Rect2(d_inner.position.x, d_inner.position.y, d_inner.size.x, 78),
		"garage.lsd",
		"Tipo de diferencial",
		["Abierto", "Autoblocante"],
		[0.0, 1.0],
		"◀ GIRO LIBRE",
		"MÁS TRACCIÓN ▶",
		false
	)
	_segmented_5_row(
		Rect2(d_inner.position.x, d_inner.position.y + 82, d_inner.size.x, 78),
		"powertrain.differential.clutches",
		"Superficies fricción",
		["2 discos", "4 discos", "6 discos", "8 discos"],
		[2.0, 4.0, 6.0, 8.0],
		"◀ BLOQUEO SUAVE",
		"BLOQUEO FUERTE ▶",
		false,
		not lsd_enabled
	)
	_slider_row(
		Rect2(d_inner.position.x, d_inner.position.y + 164, d_inner.size.x, 82),
		"powertrain.differential.power_ramp_angle_deg",
		"Rampa aceleración",
		"◀ + BLOQUEO (45°)",
		"(90°) GIRO LIBRE ▶",
		false,
		"",
		not lsd_enabled
	)
	_slider_row(
		Rect2(d_inner.position.x, d_inner.position.y + 250, d_inner.size.x, 82),
		"powertrain.differential.coast_ramp_angle_deg",
		"Rampa retención",
		"◀ + ESTABLE (45°)",
		"(90°) + AGILIDAD ▶",
		true,
		"",
		not lsd_enabled
	)

	var summary_rect := Rect2(d_inner.position.x, d_inner.position.y + 344, d_inner.size.x, d_inner.end.y - (d_inner.position.y + 348))
	draw_rect(summary_rect, C_FIELD)
	_sunken(summary_rect)
	_text(_box(summary_rect.position.x + 14, summary_rect.position.y + 10, summary_rect.size.x - 28, 18), "COMPORTAMIENTO RESULTANTE", 10, C_GOLD if lsd_enabled else C_DIM, true)
	var summary_lines := _differential_behavior_lines(lsd_enabled)
	for i in summary_lines.size():
		_text(_box(summary_rect.position.x + 14, summary_rect.position.y + 34 + float(i) * 22.0, summary_rect.size.x - 28, 20), summary_lines[i], 10, C_TEXT if i == 0 else C_DIM)


func _differential_behavior_lines(lsd_enabled: bool) -> Array[String]:
	if not lsd_enabled:
		return [
			"Diferencial ABIERTO activo: sin resistencia interna al girar.",
			"Máxima agilidad en curvas lentas, menor tracción si patina una rueda.",
			"Activa AUTOBLOCANTE arriba para habilitar discos y rampas.",
		]
	var clutches := int(draft_values.get("powertrain.differential.clutches", 4.0))
	var power_deg := float(draft_values.get("powertrain.differential.power_ramp_angle_deg", 60.0))
	var coast_deg := float(draft_values.get("powertrain.differential.coast_ramp_angle_deg", 60.0))
	var accel_desc := "ALTO (tracción agresiva)" if power_deg <= 55.0 else ("MEDIO (equilibrado)" if power_deg <= 75.0 else "SUAVE (giro libre)")
	var coast_desc := "ESTABLE al frenar" if coast_deg <= 55.0 else ("EQUILIBRADO en retención" if coast_deg <= 75.0 else "ÁGIL al soltar gas")
	return [
		"Autoblocante %d superficies · Bloqueo en gas: %s." % [clutches, accel_desc],
		"Comportamiento en retención: %s (%0.0f°)." % [coast_desc, coast_deg],
		"Menor ángulo (45°) = mayor bloqueo · Mayor ángulo (90°) = menos bloqueo.",
	]


func _draw_gear_chart(rect: Rect2) -> void:
	_group(rect, "VELOCIDAD POR MARCHA (EN VIVO)")
	var inner := _group_inner(rect)
	var gears: Array = []
	var max_rpm := float(draft_values.get("powertrain.max_rpm", 7000.0))
	var final_drive := maxf(float(draft_values.get("powertrain.final_drive", 4.0)), 0.1)
	var wheel_radius := 0.28
	if is_instance_valid(vehicle):
		var pm := vehicle.simulation.powertrain_model
		if max_rpm <= 0.0:
			max_rpm = pm.maximum_rpm
		wheel_radius = pm.front_wheel_radius_m if pm.front_torque_split >= 0.5 else pm.rear_wheel_radius_m
		wheel_radius = maxf(wheel_radius, 0.15)
		var ratios: Array = pm.gear_ratios
		for index in ratios.size():
			var gr := absf(float(ratios[index]))
			var top_kmh := _gear_top_kmh(max_rpm, gr, final_drive, wheel_radius)
			gears.append({ "label": str(index + 1) + "ª", "ratio": gr, "kmh": top_kmh })
		if absf(pm.reverse_ratio) > 0.01:
			var rev_r := absf(float(pm.reverse_ratio))
			gears.append({ "label": "R", "ratio": rev_r, "kmh": _gear_top_kmh(max_rpm, rev_r, final_drive, wheel_radius) })
	if gears.is_empty():
		_hint(_box(inner.position.x, inner.position.y, inner.size.x, inner.size.y), "SIN DATOS DE CAJA")
		return

	var top_forward_kmh := 0.0
	for g in gears:
		if str(g.label) != "R":
			top_forward_kmh = maxf(top_forward_kmh, float(g.kmh))

	_text(_box(inner.position.x, rect.position.y + 2, inner.size.x, 18), "V. MÁX AL CORTE: %0.0f KM/H" % top_forward_kmh, 11, C_GOLD, true, HORIZONTAL_ALIGNMENT_RIGHT, inner.size.x)

	var gap := 8.0
	var box_w := floorf((inner.size.x - gap * float(gears.size() - 1)) / float(gears.size()))
	var max_kmh := maxf(top_forward_kmh, 1.0)
	for i in gears.size():
		var g: Dictionary = gears[i]
		var box := Rect2(inner.position.x + float(i) * (box_w + gap), inner.position.y + 6, box_w, inner.size.y - 10)
		draw_rect(box, C_FACE_LO)
		_sunken(box)
		_text_with(FONT_SUBTITLE, _box(box.position.x + 8, box.position.y + 6, box.size.x - 16, 20), str(g.label), 15, C_GOLD_HI if str(g.label) != "R" else C_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0)
		_num(_box(box.position.x, box.position.y + 8, box.size.x - 8, 16), "%0.2f" % float(g.ratio), 10, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 8)

		# Barra vertical proporcional de velocidad
		var bar_bg := Rect2(box.position.x + 12, box.position.y + 34, box.size.x - 24, box.size.y - 72)
		draw_rect(bar_bg, C_FIELD)
		_sunken(bar_bg)
		var frac := clampf(float(g.kmh) / max_kmh, 0.05, 1.0)
		var fill_h := maxf((bar_bg.size.y - 2.0) * frac, 4.0)
		var fill_rect := Rect2(bar_bg.position.x + 1, bar_bg.end.y - 1.0 - fill_h, bar_bg.size.x - 2, fill_h)
		var col := C_GOLD if str(g.label) != "R" else C_DIM
		draw_rect(fill_rect, Color(col, 0.45), true)
		draw_rect(fill_rect, Color(col, 0.90), false)

		_num(_box(box.position.x + 2, box.end.y - 30, box.size.x - 4, 24), "%0.0f km/h" % float(g.kmh), 11, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, box.size.x - 4)


func _gear_top_kmh(max_rpm: float, gear_ratio: float, final_drive: float, wheel_radius_m: float) -> float:
	var total_ratio := maxf(gear_ratio * final_drive, 0.05)
	var wheel_rpm := max_rpm / total_ratio
	var circum := TAU * wheel_radius_m
	return (wheel_rpm / 60.0) * circum * 3.6


# =============================================================================
# PÁGINA 2 — RUEDAS Y CARGA
# =============================================================================


func _draw_wheels_and_load_page() -> void:
	var _is_pool := _is_pool_mode()
	var can_service := compound_change_allowed and _may_service_tires()

	# 1) COMBUSTIBLE Y AUTONOMÍA (y=156..264)
	_group(Rect2(36, PAGE_TOP, 596, 108), "COMBUSTIBLE Y AUTONOMÍA")
	var f_inner := _group_inner(Rect2(36, PAGE_TOP, 596, 108))
	_slider_row(Rect2(f_inner.position.x, f_inner.position.y, f_inner.size.x - 108, 38), "fuel.initial_kg", "Combustible", "", "", false)

	var fit_btn := Rect2(f_inner.end.x - 100, f_inner.position.y + 4, 100, 30)
	var fit_hover := _mouse_over(fit_btn)
	draw_style_box(RallyUITheme.make_flat_panel(C_FACE_HI if fit_hover else WB_BG_CARD, C_GOLD if fit_hover else RallyUITheme.BORDER_CARD, 1, RallyUITheme.CORNER_RADIUS), fit_btn)
	_text_with(FONT_BUTTON, fit_btn, "TRAMO +20%", 11, C_GOLD_HI if fit_hover else C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, -1.0)
	_hit_regions.append({ "rect": fit_btn, "kind": "fuel_fit_stage" })

	var capacity := 45.0
	if is_instance_valid(vehicle):
		capacity = maxf(float(vehicle.simulation.mass_model.fuel_capacity_kg), 0.001)
	var current_kg := float(draft_values.get("fuel.initial_kg", 0.0))
	var current_l := current_kg / _fuel_density()
	var cap_l := capacity / _fuel_density()
	var est_km := current_l / ESTIMATED_FUEL_BURN_L_PER_KM
	var stage_km := maxf(_effective_stage_length_m() / 1000.0, 0.1)
	var enough := est_km >= stage_km

	_text(_box(50, 224, 290, 18), "DEPÓSITO (+%0.1f KG) · ALCANCE ~%0.0f KM" % [current_kg, est_km], 10, STATUS_SUCCESS if enough else C_ROSE, true)
	_num(_box(340, 224, 278, 18), "%0.1f / %0.1f L  (TRAMO %0.1f KM)" % [current_l, cap_l, stage_km], 10, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 278)

	var groove := Rect2(50, 245, 568, 12)
	draw_rect(groove, C_FIELD)
	_sunken(groove)
	var fraction := clampf(current_kg / capacity, 0.0, 1.0)
	var fill := Rect2(groove.position + Vector2(1, 1), Vector2(maxf((groove.size.x - 2) * fraction, 1.0), groove.size.y - 2))
	draw_rect(fill, Color(C_BLUE_DEEP, 0.95))
	draw_rect(Rect2(fill.position, Vector2(fill.size.x, maxf(floorf(fill.size.y * 0.5), 1.0))), Color(C_BLUE, 0.55), true)
	for segment in range(1, 10):
		var sx := groove.position.x + groove.size.x * (float(segment) / 10.0)
		draw_rect(Rect2(sx, groove.position.y + 1, 1, groove.size.y - 2), Color(C_DARK, 0.55))

	# 2) PRESIÓN EN FRÍO POR EJE (y=272..386)
	var press_panel := Rect2(36, 272, 596, 114)
	_group(press_panel, "PRESIÓN EN FRÍO (POR EJE)")
	var p_inner := _group_inner(press_panel)
	var p_row_h := 34.0
	_slider_row(Rect2(p_inner.position.x, p_inner.position.y, p_inner.size.x, p_row_h), "garage.front_pressure", "Presión delantera", "", "", false)
	_slider_row(Rect2(p_inner.position.x, p_inner.position.y + p_row_h, p_inner.size.x, p_row_h), "garage.rear_pressure", "Presión trasera", "", "", true)
	_text(_box(p_inner.position.x + 196, p_inner.position.y + p_row_h * 2.0 + 1, p_inner.size.x - 196, 14), "◀ + AGARRE TIERRA", 9, Color(C_DIM, 0.85))
	_text(_box(p_inner.position.x + 196, p_inner.position.y + p_row_h * 2.0 + 1, p_inner.size.x - 310, 14), "+ PRECISIÓN ASFALTO ▶", 9, Color(C_DIM, 0.85), false, HORIZONTAL_ALIGNMENT_RIGHT, p_inner.size.x - 310)

	# 3) MALETERO Y PARQUE 3D (o Servicio Estándar) (y=394..674)
	if _is_pool:
		var inv_ref: RallyTireInventory = vehicle.tire_inventory
		var inv_count: int = inv_ref.total_count()
		_group(Rect2(36, 394, 596, 280), "MALETERO Y PARQUE 3D (%d/10)" % inv_count)
		var drag_tid := _strategy_board._active_drag_tire_id if _strategy_board != null else -1
		var spare_mass := draft_spare_ids.size() * 18
		var mode_note := "ARRASTRA RUEDAS 3D O CLIC ORIGEN -> DESTINO"
		var note_color := C_DIM
		if drag_tid > 0:
			mode_note = "ARRASTRANDO #%d · SUELTA EN COCHE, MALETERO O PARQUE" % drag_tid
			note_color = C_GOLD
		elif selected_pool_tire_id >= 0:
			mode_note = "ELIGE DESTINO PARA #%d (ESC/X CANCELA)" % selected_pool_tire_id
			note_color = C_GOLD
		elif not _may_service_tires():
			mode_note = "BLOQUEADO EN TRAMO — USA PAUSA/INVENTARIO"
			note_color = C_ROSE
		elif not compound_change_allowed:
			mode_note = "BLOQUEADO EN ESTA PARADA"
			note_color = C_ROSE
		_text(
			_box(50, 414, 568, 16),
			"MALETERO %d/%d (+%d KG) · PARQUE %d  ·  %s" % [draft_spare_ids.size(), _tire_capacity(), spare_mass, draft_stock_ids.size(), mode_note],
			9,
			note_color,
			true
		)

		var telemetry := Rect2(648, PAGE_TOP, 596, 518)
		_group(telemetry, "MONTAJE 3D EN EL COCHE")
		_text(
			_box(662, 177, 568, 16),
			"ARRASTRA RUEDAS 3D ENTRE COCHE, MALETERO Y PARQUE  ·  CLIC O D-PAD SELECCIONA",
			9,
			C_DIM,
			true
		)
		var bay := Rect2(848, 198, 196, 444)
		draw_rect(bay, C_FIELD)
		_sunken(bay)
		var axle_col := Color(C_BLUE, 0.28)
		draw_line(Vector2(842, 303), Vector2(1050, 303), axle_col, 2.0)
		draw_line(Vector2(842, 541), Vector2(1050, 541), axle_col, 2.0)
		draw_line(Vector2(946, 303), Vector2(946, 541), axle_col, 2.0)
		var p_sum := 0.0
		for i in 4:
			p_sum += _wheel_pressure(i)
		_text(
			_box(662, 651, 568, 18),
			"PRESIÓN MEDIA %0.0f kPa · DESLIZA SOBRE MONTAJE PARA INTERCAMBIAR" % (p_sum * 0.25),
			9,
			C_DIM,
			true,
			HORIZONTAL_ALIGNMENT_CENTER,
			568
		)
		return

	# Modo no-pool (clásico / proving ground sin pool 10)
	_group(Rect2(36, 394, 596, 280), "COMPUESTO Y SERVICIO")
	var ids := _available_compound_ids()
	var comp_y := 420.0
	for i in ids.size():
		var cid := str(ids[i])
		var option_rect := Rect2(50 + (i % 2) * 286, comp_y + float(i / 2) * 34.0, 276, 28)
		_radio(option_rect, "4× " + _compound_label(cid).to_upper(), _all_compound(cid))
		if can_service:
			_hit_regions.append({"rect": option_rect, "kind": "all_compound", "compound": cid})

	var service_rect := Rect2(50, 520, 568, 52)
	_row_frame(service_rect, selected_field_path == "service", false, _mouse_over(service_rect))
	_text(_box(service_rect.position.x + 12, service_rect.position.y, 320, 52), "MONTAR NEUMÁTICOS NUEVOS", 11, C_TEXT)
	_toggle(Rect2(service_rect.end.x - 132, service_rect.position.y + 11, 120, 30), "SÍ" if new_tires_service else "NO", new_tires_service)
	if _may_service_tires():
		_hit_regions.append({ "rect": service_rect, "kind": "service" })

	var spare_rect := Rect2(50, 580, 568, 56)
	_row_frame(spare_rect, selected_field_path == "spares", true, _mouse_over(spare_rect))
	_text(_box(spare_rect.position.x + 12, spare_rect.position.y, 320, 56), "RUEDAS DE REPUESTO (+18 KG C/U)", 11, C_TEXT)
	for s in 3:
		var button := Rect2(spare_rect.end.x - 144 + float(s) * 48, spare_rect.position.y + 13, 42, 30)
		_toggle(button, str(s), draft_spare_wheels == s)
		if _may_service_tires():
			_hit_regions.append({ "rect": button, "kind": "spares", "delta": s - draft_spare_wheels })

	var telemetry := Rect2(648, PAGE_TOP, 596, 518)
	_group(telemetry, "MONTAJE Y TELEMETRÍA")
	var inner := _group_inner(telemetry)
	var gap := 12.0
	var card_w := floorf((inner.size.x - gap) * 0.5)
	var card_h := floorf((inner.size.y - gap) * 0.5)
	var codes := ["FL", "FR", "RL", "RR"]
	var names := ["DEL. IZQUIERDA", "DEL. DERECHA", "TRAS. IZQUIERDA", "TRAS. DERECHA"]
	for i in 4:
		var col := i % 2
		var row := i / 2
		var card := Rect2(inner.position.x + float(col) * (card_w + gap), inner.position.y + float(row) * (card_h + gap), card_w, card_h)
		var card_focused := selected_field_path == ("mounted:%d" % i)
		draw_rect(card, C_FACE_HI if card_focused else C_FACE_LO)
		_sunken(card)
		var tire_info: Dictionary = {}
		if is_instance_valid(vehicle) and vehicle.tire_inventory != null:
			var inv_ref: RallyTireInventory = vehicle.tire_inventory
			if i < inv_ref.mounted.size():
				tire_info = inv_ref.mounted[i]
		var tid := int(tire_info.get("id", i + 1))
		var cid := str(draft_wheel_compounds.get(codes[i], ""))
		var wear_pct := 0.0
		var status_tag := "OK"
		var status_color: Color = C_DIM
		if is_instance_valid(vehicle) and vehicle.tire_inventory != null and not tire_info.is_empty():
			var st: Dictionary = tire_info.get("state", {})
			wear_pct = float(st.get("wear_fraction", 0.0)) * 100.0
			var st_info := _tire_status_info(vehicle.tire_inventory, tire_info)
			status_tag = str(st_info["tag"])
			status_color = st_info["color"]
		if card_focused:
			draw_rect(card, BORDER_FOCUS, false, 2.0)
		var id_str := "#%d · " % tid if not tire_info.is_empty() else ""
		_text_with(FONT_SUBTITLE, _box(card.position.x + 12, card.position.y + 8, 120, 22), id_str + codes[i], 18, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0)
		_text(_box(card.position.x, card.position.y + 10, card.size.x - 12, 18), "%s · %s" % [names[i], status_tag], 9, status_color if status_tag != "OK" else C_DIM, status_tag != "OK", HORIZONTAL_ALIGNMENT_RIGHT, card.size.x - 12)
		_text(_box(card.position.x + 12, card.position.y + 42, 220, 16), "PRESIÓN · DESGASTE %0.0f%%" % wear_pct, 9, C_DIM, true)
		_field_box(Rect2(card.position.x + 12, card.position.y + 60, card.size.x - 24, 28), "%0.0f kPa" % _wheel_pressure(i), 11, C_TEXT)
		_text(_box(card.position.x + 12, card.position.y + 96, 160, 16), "TEMPERATURA", 9, C_DIM, true)
		_field_box(Rect2(card.position.x + 12, card.position.y + 114, card.size.x - 24, 28), "%0.0f °C" % _wheel_temperature(i), 11, C_BLUE)
		var bar := Rect2(card.position.x + 12, card.position.y + 154, card.size.x - 24, 8)
		var temp_c := _wheel_temperature(i)
		var thermal := clampf((temp_c - 20.0) / 90.0, 0.04, 1.0)
		var thermal_color := C_ROSE if temp_c >= 95.0 else (C_GOLD if temp_c >= 75.0 else Color(C_BLUE, 0.92))
		draw_rect(bar, C_FIELD)
		_sunken(bar)
		draw_rect(Rect2(bar.position + Vector2(1, 1), Vector2(maxf((bar.size.x - 2) * thermal, 2.0), bar.size.y - 2)), thermal_color, true)
		var toggle := Rect2(card.position.x + 12, card.end.y - 42, card.size.x - 24, 30)
		_toggle(toggle, _compound_label(cid, true), can_service)
		if can_service:
			_hit_regions.append({ "rect": toggle, "kind": "compound", "corner": codes[i] })


# =============================================================================
# STAGE ROUTE & TIRE HELPERS
# =============================================================================


func _resolve_stage_route_path() -> String:
	if not stage_route_path.strip_edges().is_empty():
		return stage_route_path.strip_edges()
	var cid := circuit_id.strip_edges().to_lower().replace("-", "_")
	if cid.is_empty():
		return ""
	var regex := RegEx.new()
	regex.compile("^([a-z_]+)_stage_(\\d+)$")
	var m := regex.search(cid)
	if m != null:
		cid = "%s_stage%s" % [m.get_string(1), m.get_string(2)]
	var candidate := "res://data/rally/%s_route.json" % cid
	if FileAccess.file_exists(candidate):
		return candidate
	return ""


func _compute_vertical_stage_points(raw_points: Array) -> PackedVector2Array:
	if raw_points.size() < 2:
		return PackedVector2Array()
	var pts_2d: Array[Vector2] = []
	var center := Vector2.ZERO
	for p in raw_points:
		if p is Array and (p as Array).size() >= 3:
			var arr := p as Array
			var v := Vector2(float(arr[0]), float(arr[2]))
			pts_2d.append(v)
			center += v
	if pts_2d.size() < 2:
		return PackedVector2Array()
	center /= float(pts_2d.size())

	var xx := 0.0
	var yy := 0.0
	var xy := 0.0
	for v in pts_2d:
		var off := v - center
		xx += off.x * off.x
		yy += off.y * off.y
		xy += off.x * off.y

	var angle := -PI * 0.5 - atan2(2.0 * xy, xx - yy) * 0.5
	var route_dir := pts_2d[-1] - pts_2d[0]
	if route_dir.rotated(angle).y > 0.0:
		angle += PI

	var rotated_pts: Array[Vector2] = []
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for v in pts_2d:
		var rot_v := v.rotated(angle)
		rotated_pts.append(rot_v)
		min_v = min_v.min(rot_v)
		max_v = max_v.max(rot_v)

	var extent := max_v - min_v
	var max_dim := maxf(maxf(extent.x, extent.y), 0.001)
	var out := PackedVector2Array()
	for rv in rotated_pts:
		out.append((rv - min_v) / max_dim)
	return out


func _ensure_stage_route_cache() -> void:
	var rpath := _resolve_stage_route_path()
	if rpath == _cached_route_path and not _cached_route_points.is_empty():
		return
	_cached_route_path = rpath
	_cached_route_points = PackedVector2Array()
	_cached_route_heights = PackedFloat32Array()
	_cached_profile_altitudes = PackedFloat32Array()
	_cached_route_length_m = 0.0
	if rpath.is_empty() or not FileAccess.file_exists(rpath):
		return
	var file := FileAccess.open(rpath, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var doc := parsed as Dictionary
	_cached_route_length_m = float(doc.get("total_route_length_m", 0.0))
	var raw_pts: Variant = doc.get("points", [])
	if raw_pts is Array:
		_cached_route_points = _compute_vertical_stage_points(raw_pts as Array)
		for p in (raw_pts as Array):
			if p is Array and (p as Array).size() >= 3:
				_cached_route_heights.append(float((p as Array)[1]))
	var sid := _resolve_briefing_stage_id()
	var prof_path := "res://assets/rally/%s/climate_route_profile.json" % sid
	if not sid.is_empty() and FileAccess.file_exists(prof_path):
		var prof_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(prof_path))
		if prof_parsed is Dictionary:
			var samples: Variant = (prof_parsed as Dictionary).get("samples", [])
			if samples is Array:
				for s in (samples as Array):
					if s is Dictionary and (s as Dictionary).has("altitude_m"):
						_cached_profile_altitudes.append(float((s as Dictionary)["altitude_m"]))


func _get_stage_weather_text() -> String:
	var raw := stage_weather_label.strip_edges()
	if not raw.is_empty():
		return raw.to_upper()
	return "SOLEADO"


func _effective_stage_length_m() -> float:
	if (_stage_length_explicit or absf(circuit_length_m - 5500.0) > 1.0) and circuit_length_m > 0.0:
		return circuit_length_m
	if _cached_route_length_m > 0.0:
		return _cached_route_length_m
	return circuit_length_m


func _get_stage_distance_text() -> String:
	return "%0.1f KM" % (maxf(_effective_stage_length_m(), 0.0) / 1000.0)


func _draw_stage_route_preview(rect: Rect2) -> void:
	draw_rect(rect, C_FIELD)
	_sunken(rect)

	_ensure_stage_route_cache()
	if _cached_route_points.size() < 2:
		_hint(_box(rect.position.x + 12, rect.position.y, rect.size.x - 24, rect.size.y), "SIN TRAZADO DISPONIBLE", HORIZONTAL_ALIGNMENT_CENTER)
		return

	var pad := 16.0
	var avail_w := rect.size.x - pad * 2.0
	var avail_h := rect.size.y - pad * 2.0
	if avail_w <= 10.0 or avail_h <= 10.0:
		return

	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for p in _cached_route_points:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var extent := max_p - min_p
	extent.x = maxf(extent.x, 0.001)
	extent.y = maxf(extent.y, 0.001)

	var fit_scale := minf(avail_w / extent.x, avail_h / extent.y)
	var draw_size := extent * fit_scale
	var origin := rect.position + Vector2(pad, pad) + (Vector2(avail_w, avail_h) - draw_size) * 0.5 - min_p * fit_scale

	var screen_pts := PackedVector2Array()
	for p in _cached_route_points:
		screen_pts.append(origin + p * fit_scale)

	draw_polyline(screen_pts, Color(C_GOLD, 0.22), 6.0, true)
	draw_polyline(screen_pts, Color(C_CHROME_TEXT, 0.92), 2.8, true)

	var start_pt := screen_pts[0]
	var finish_pt := screen_pts[screen_pts.size() - 1]
	draw_circle(start_pt, 5.0, Color(0.28, 0.85, 0.45))
	draw_arc(start_pt, 5.0, 0.0, TAU, 16, Color(C_GOLD, 0.85), 1.4, true)
	draw_circle(finish_pt, 5.0, Color(0.95, 0.34, 0.28))
	draw_arc(finish_pt, 5.0, 0.0, TAU, 16, Color(C_CHROME_TEXT, 0.85), 1.4, true)


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


func _all_compound(compound_id: String) -> bool:
	for corner in ["FL", "FR", "RL", "RR"]:
		if str(draft_wheel_compounds.get(corner, "")) != compound_id:
			return false
	return true


func _vehicle_mass() -> float:
	if not is_instance_valid(vehicle):
		return 0.0
	var mass_state: Dictionary = vehicle.simulation.mass_model.resolve(
		float(draft_values.get("fuel.initial_kg", 0.0))
	)
	return float(mass_state.get("vehicle_total_mass_kg", vehicle.mass))


func _wheel_state(index: int) -> Dictionary:
	if not is_instance_valid(vehicle):
		return {}
	return vehicle.get_tire_thermal_state(index)


func _wheel_pressure(index: int) -> float:
	return float(_wheel_state(index).get("pressure_kpa_gauge", 0.0))


func _wheel_temperature(index: int) -> float:
	return float(_wheel_state(index).get("tread_c", 0.0))


func _tire_status_info(inv: RallyTireInventory, tire_info: Dictionary) -> Dictionary:
	if tire_info.is_empty():
		return {"tag": "OK", "color": C_DIM}
	if inv.is_carcass_destroyed(tire_info):
		return {"tag": "DESTALONADO", "color": C_ROSE}
	if inv.is_punctured(tire_info) and inv.is_rim_damaged(tire_info):
		return {"tag": "FUGA + ARO", "color": C_ROSE}
	if inv.is_punctured(tire_info):
		return {"tag": "FUGA", "color": C_ROSE}
	if inv.is_rim_damaged(tire_info):
		return {"tag": "ARO", "color": C_GOLD}
	return {"tag": "OK", "color": C_DIM}


# =============================================================================
# CONTROLES DE FILA (SLIDER, SEGMENTADO, ICONOS GEOMÉTRICOS)
# =============================================================================


func _is_field_modified(path: String) -> bool:
	if not opening_values.has(path) or not draft_values.has(path):
		return false
	return not is_equal_approx(float(draft_values[path]), float(opening_values[path]))


func _draw_geometry_glyph(rect: Rect2, kind: String, path: String, disabled: bool) -> void:
	var col := Color(C_DIM, 0.4) if disabled else C_GOLD_HI
	var axle_col := Color(BORDER_SUBTLE, 0.6)
	var val := float(draft_values.get(path, 0.0))
	var cy := rect.get_center().y
	if kind == "camber":
		# Vista frontal: eje horizontal + ruedas inclinadas
		draw_line(Vector2(rect.position.x + 2, cy + 5), Vector2(rect.end.x - 2, cy + 5), axle_col, 1.5)
		var tilt := clampf(-val * 10.0, 0.0, 4.5)
		draw_line(Vector2(rect.position.x + 5 + tilt, cy - 6), Vector2(rect.position.x + 5 - tilt * 0.4, cy + 6), col, 2.2)
		draw_line(Vector2(rect.end.x - 5 - tilt, cy - 6), Vector2(rect.end.x - 5 + tilt * 0.4, cy + 6), col, 2.2)
	elif kind == "toe":
		# Vista cenital: eje + ruedas convergentes (+) o divergentes (-)
		draw_line(Vector2(rect.position.x + 3, cy), Vector2(rect.end.x - 3, cy), axle_col, 1.5)
		var angle := clampf(val * 40.0, -3.5, 3.5)
		draw_line(Vector2(rect.position.x + 5 + angle, cy - 6), Vector2(rect.position.x + 5 - angle, cy + 6), col, 2.2)
		draw_line(Vector2(rect.end.x - 5 - angle, cy - 6), Vector2(rect.end.x - 5 + angle, cy + 6), col, 2.2)


func _segmented_5_row(
	rect: Rect2,
	path: String,
	label: String,
	option_labels: Array,
	option_values: Array,
	left_hint: String,
	right_hint: String,
	last: bool,
	disabled: bool = false
) -> void:
	var field := _setup_field(path)
	if field.is_empty():
		return
	var selected := (selected_field_path == path) and not disabled
	_row_frame(rect, selected, last, _mouse_over(rect) and not disabled)
	_hit_regions.append({ "rect": rect, "kind": "select", "path": path })

	var modified := _is_field_modified(path)
	var label_x := rect.position.x + 12.0
	if modified and not disabled:
		draw_circle(Vector2(label_x + 3.0, rect.position.y + rect.size.y * 0.5), 3.0, C_GOLD)
		label_x += 10.0

	var label_col := Color(C_DIM, 0.42) if disabled else (C_TEXT if selected else C_DIM)
	_text_with(FONT_UI, _box(label_x, rect.position.y, 178, rect.size.y), label, 11, label_col, HORIZONTAL_ALIGNMENT_LEFT, -1.0)

	var current_val := float(draft_values.get(path, option_values[0]))
	var base_val := float(opening_values.get(path, current_val))
	var seg_area := Rect2(rect.position.x + 196.0, rect.position.y + 8.0, rect.size.x - 208.0, 32.0)
	var count := option_labels.size()
	var gap := 4.0
	var btn_w := floorf((seg_area.size.x - gap * float(count - 1)) / float(count))

	for i in count:
		var opt_val := float(option_values[i])
		var btn_rect := Rect2(seg_area.position.x + float(i) * (btn_w + gap), seg_area.position.y, btn_w, seg_area.size.y)
		var active := is_equal_approx(current_val, opt_val)
		var is_base := modified and is_equal_approx(base_val, opt_val)
		var hovered := (not disabled) and _mouse_over(btn_rect)

		var fill := Color(C_FIELD, 0.45) if disabled else (C_BLUE_DEEP if active else (C_FACE_HI if hovered else C_FIELD))
		var rim := Color(BORDER_SUBTLE, 0.45) if disabled else (C_GOLD if active else (BORDER_FOCUS if hovered else BORDER_SUBTLE))
		draw_style_box(RallyUITheme.make_flat_panel(fill, rim, 1, RallyUITheme.CORNER_RADIUS), btn_rect)
		if active and not disabled:
			draw_rect(Rect2(btn_rect.position.x + 2, btn_rect.end.y - 2, btn_rect.size.x - 4, 2), C_GOLD)
		if is_base and not disabled:
			draw_circle(Vector2(btn_rect.end.x - 6, btn_rect.position.y + 6), 2.5, C_GOLD_HI)

		var txt_col := Color(C_DIM, 0.40) if disabled else (C_GOLD_HI if active else (C_TEXT if hovered else C_DIM))
		_text_with(FONT_BUTTON, btn_rect, str(option_labels[i]).to_upper(), 12 if count <= 4 else 11, txt_col, HORIZONTAL_ALIGNMENT_CENTER, -1.0)
		if not disabled:
			_hit_regions.append({ "rect": btn_rect, "kind": "set_value", "path": path, "value": opt_val })

	var hint_y := seg_area.end.y + 4.0
	var hint_col := Color(C_DIM, 0.35) if disabled else Color(C_DIM, 0.85)
	_text(_box(seg_area.position.x, hint_y, seg_area.size.x * 0.5, 16), left_hint, 9, hint_col)
	_text(_box(seg_area.position.x + seg_area.size.x * 0.5, hint_y, seg_area.size.x * 0.5, 16), right_hint, 9, hint_col, false, HORIZONTAL_ALIGNMENT_RIGHT, seg_area.size.x * 0.5)


func _slider_row(
	rect: Rect2,
	path: String,
	label: String,
	left_hint: String,
	right_hint: String,
	last: bool,
	glyph_kind: String = "",
	disabled: bool = false
) -> void:
	var field := _setup_field(path)
	if field.is_empty():
		return
	var selected := (selected_field_path == path) and not disabled
	_row_frame(rect, selected, last, _mouse_over(rect) and not disabled)
	_hit_regions.append({ "rect": rect, "kind": "select", "path": path })

	var label_x := rect.position.x + 12.0
	if _is_field_modified(path) and not disabled:
		draw_circle(Vector2(label_x + 3.0, rect.position.y + rect.size.y * 0.5), 3.0, C_GOLD)
		label_x += 10.0

	if not glyph_kind.is_empty():
		var glyph_rect := Rect2(label_x, rect.position.y + (rect.size.y - 20.0) * 0.5, 22, 20)
		_draw_geometry_glyph(glyph_rect, glyph_kind, path, disabled)
		label_x += 28.0

	var label_col := Color(C_DIM, 0.42) if disabled else (C_TEXT if selected else C_DIM)
	var label_w := 178.0 - (label_x - (rect.position.x + 12.0))
	_text_with(FONT_UI, _box(label_x, rect.position.y, maxf(label_w, 96.0), rect.size.y), label, 11, label_col, HORIZONTAL_ALIGNMENT_LEFT, -1.0)

	var has_hints := not (left_hint.is_empty() and right_hint.is_empty())
	var value_width := 112.0 if path == "brakes.front_brake_bias" else 102.0
	var ctrl_y := (rect.position.y + 10.0) if has_hints else (rect.position.y + (rect.size.y - 26.0) * 0.5)
	var field_rect := Rect2(rect.end.x - value_width - 4.0, ctrl_y - 2.0, value_width, 30.0)
	var minus := Rect2(rect.position.x + 196.0, ctrl_y, 26.0, 26.0)
	var plus := Rect2(field_rect.position.x - 34.0, ctrl_y, 26.0, 26.0)
	var track := Rect2(minus.end.x + 8.0, ctrl_y + 7.5, plus.position.x - minus.end.x - 16.0, 11.0)

	var val_col := Color(C_DIM, 0.45) if disabled else (C_GOLD if selected else C_TEXT)
	_field_box(field_rect, _format_field(field, path), 11, val_col, true)
	_stepper(minus, false, disabled)
	var intervals := 5
	if path.begins_with(RallySetupCatalog.DIFFERENTIAL_PREFIX):
		intervals = roundi((float(field.max) - float(field.min)) / float(field.step))
	var base_fraction := -1.0
	if _is_field_modified(path) and opening_values.has(path):
		var span := maxf(float(field.max) - float(field.min), 0.0001)
		base_fraction = clampf((float(opening_values[path]) - float(field.min)) / span, 0.0, 1.0)
	_track(track, _field_fraction(field, path), selected, intervals, base_fraction, disabled)
	_stepper(plus, true, disabled)

	if has_hints:
		var hint_y := minus.end.y + 4.0
		var hint_col := Color(C_DIM, 0.35) if disabled else Color(C_DIM, 0.85)
		var hint_span := plus.end.x - minus.position.x
		var half_w := floorf(hint_span * 0.48)
		_text(_box(minus.position.x, hint_y, half_w, 16), left_hint, 9, hint_col)
		_text(_box(plus.end.x - half_w, hint_y, half_w, 16), right_hint, 9, hint_col, false, HORIZONTAL_ALIGNMENT_RIGHT, half_w)

	if not disabled:
		_hit_regions.append({ "rect": minus, "kind": "adjust", "path": path, "amount": -1.0 })
		_hit_regions.append({ "rect": plus, "kind": "adjust", "path": path, "amount": 1.0 })
		_hit_regions.append({ "rect": track.grow(6.0), "kind": "slide", "path": path, "track": track })


func _format_field(field: Dictionary, path: String) -> String:
	if path == "fuel.initial_kg":
		return "%.1f L" % (float(draft_values.get(path, 0.0)) / _fuel_density())
	if path == "brakes.front_brake_bias":
		var f := roundi(float(draft_values.get(path, 0.55)) * 100.0)
		return "%d/%d%%" % [f, 100 - f]
	var value := float(draft_values.get(path, 0.0))
	if path in INVERTED_DISCRETE_PATHS:
		return RallySetupCatalog.POSITION_LABELS[clampi(int(value) - 1, 0, 4)]
	if path == "garage.cooling":
		return "De serie" if value == 0.0 else "%d %%" % int(value * 25.0)
	if path == "garage.lsd":
		return "Autoblocante" if bool(value) else "Abierto"
	var scaled := value * float(field.scale)
	var pattern := "%." + str(int(field.digits)) + "f"
	var formatted := (pattern % scaled) + str(field.suffix)
	if path.begins_with(RallySetupCatalog.DIFFERENTIAL_PREFIX) and value < float(field.min):
		formatted += " serie"
	return formatted


func _field_fraction(field: Dictionary, path: String) -> float:
	var span := maxf(float(field.max) - float(field.min), 0.0001)
	return clampf((float(draft_values.get(path, 0.0)) - float(field.min)) / span, 0.0, 1.0)


# =============================================================================
# PRIMITIVAS PLANAS MOTORSPORT (2 PX CHAMFER)
# =============================================================================


func _group(rect: Rect2, caption: String) -> void:
	draw_style_box(RallyUITheme.make_flat_panel(C_FACE_LO, BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS), rect)
	var cap_w := _title_width(caption, 14) + 16.0
	_text_with(FONT_SUBTITLE, _box(rect.position.x + 14, rect.position.y + 4, cap_w, 16), caption, 14, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0)
	draw_line(
		Vector2(rect.position.x + 14, rect.position.y + 22),
		Vector2(rect.end.x - 14, rect.position.y + 22),
		BORDER_SUBTLE,
		1.0
	)


func _group_inner(rect: Rect2) -> Rect2:
	return Rect2(rect.position.x + 14, rect.position.y + 26, rect.size.x - 28, rect.size.y - 34)


func _row_frame(rect: Rect2, selected: bool, last: bool, hovered: bool, base: Color = C_FACE_LO) -> void:
	var background := base
	if selected:
		background = C_SEL
	elif hovered:
		background = C_FACE_HI
	draw_rect(rect, background)
	if selected:
		draw_rect(Rect2(rect.position.x, rect.position.y, 3, rect.size.y), C_GOLD)
		draw_rect(rect, Color(C_GOLD, 0.35), false, 1.0)
	if not last:
		draw_line(
			Vector2(rect.position.x + 8, rect.end.y - 1),
			Vector2(rect.end.x - 8, rect.end.y - 1),
			Color(1.0, 1.0, 1.0, 0.05),
			1.0
		)


func _sunken(rect: Rect2) -> void:
	draw_rect(rect, BORDER_SUBTLE, false, 1.0)


func _field_box(rect: Rect2, text: String, size: int, color: Color, numeric: bool = true) -> void:
	draw_style_box(RallyUITheme.make_flat_panel(C_FIELD, BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS), rect)
	var inner := _box(rect.position.x + 6, rect.position.y, rect.size.x - 12, rect.size.y)
	if numeric:
		_num(inner, text, size, color, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 12)
	else:
		_text(inner, text, size, color, true, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 12)


func _stepper(rect: Rect2, plus: bool, disabled: bool = false) -> void:
	var hovered := (not disabled) and _mouse_over(rect)
	var bg := Color(C_FIELD, 0.45) if disabled else (C_FACE_HI if hovered else WB_SLIDER_STEPPER)
	var rim := Color(BORDER_SUBTLE, 0.45) if disabled else (RallyUITheme.BORDER_HOVER if hovered else BORDER_SUBTLE)
	draw_style_box(RallyUITheme.make_flat_panel(bg, rim, 1, RallyUITheme.CORNER_RADIUS), rect)
	var cx: float = round(rect.get_center().x)
	var cy: float = round(rect.get_center().y)
	var glyph: Color = Color(C_DIM, 0.35) if disabled else (C_TEXT if hovered else C_DIM)
	draw_rect(Rect2(cx - 4, cy - 1, 9, 2), glyph)
	if plus:
		draw_rect(Rect2(cx - 1, cy - 4, 2, 9), glyph)


func _track(rect: Rect2, fraction: float, selected: bool, intervals: int, base_fraction: float = -1.0, disabled: bool = false) -> void:
	draw_rect(rect, Color(C_FIELD, 0.5) if disabled else C_FIELD)
	draw_rect(rect, Color(BORDER_SUBTLE, 0.5) if disabled else BORDER_SUBTLE, false, 1.0)
	var inner := rect.grow(-2.0)
	var fill_w: float = maxf(inner.size.x * clampf(fraction, 0.0, 1.0), 2.0)
	draw_rect(Rect2(inner.position, Vector2(fill_w, inner.size.y)), Color(C_DIM, 0.35) if disabled else C_BLUE)
	for i in range(1, intervals):
		var tx := inner.position.x + inner.size.x * float(i) / intervals
		draw_rect(Rect2(tx, inner.position.y, 1, inner.size.y), Color(1.0, 1.0, 1.0, 0.12))

	if base_fraction >= 0.0 and not disabled:
		var bx := inner.position.x + inner.size.x * clampf(base_fraction, 0.0, 1.0)
		draw_rect(Rect2(bx - 1.0, rect.position.y - 3.0, 2.0, rect.size.y + 6.0), Color(C_GOLD_HI, 0.85))

	var thumb := Rect2(inner.position.x + fill_w - 6.0, rect.position.y - 5.0, 12.0, rect.size.y + 10.0)
	draw_rect(thumb, Color(C_DIM, 0.45) if disabled else WB_SLIDER_THUMB)
	draw_rect(thumb, Color("#000000"), false, 1.0)
	if selected and not disabled:
		draw_rect(Rect2(thumb.position.x, thumb.position.y, thumb.size.x, 3), C_GOLD)


func _radio(rect: Rect2, label: String, on: bool) -> void:
	var radius := 6.0
	var center := Vector2(rect.position.x + radius + 1.0, rect.position.y + rect.size.y * 0.5)
	draw_circle(center, radius, C_FIELD)
	draw_arc(center, radius, 0.0, TAU, 24, C_GOLD if on else BORDER_SUBTLE, 1.2)
	if on:
		draw_circle(center, radius - 3.0, C_GOLD)
	_text(_box(rect.position.x + 18, rect.position.y, rect.size.x - 18, rect.size.y), label, 11, C_TEXT if on else C_DIM, on)


func _toggle(rect: Rect2, label: String, on: bool) -> void:
	var fill := C_BLUE_DEEP if on else C_FIELD
	draw_style_box(RallyUITheme.make_flat_panel(fill, C_GOLD if on else BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS), rect)
	_text_with(FONT_BUTTON, _box(rect.position.x, rect.position.y, rect.size.x, rect.size.y), label, 13, C_GOLD_HI if on else C_DIM, HORIZONTAL_ALIGNMENT_CENTER, -1.0)


func _hint(rect: Rect2, text: String, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	_text(rect, text, 10, Color(C_DIM, 0.9), false, align, rect.size.x)


func _glass_window(rect: Rect2, radius: int) -> void:
	_glass_box(rect, mini(radius, RallyUITheme.CORNER_RADIUS), BG_SURFACE, RallyUITheme.BORDER_CARD, 0.0)


func _glass_box(rect: Rect2, radius: int, fill: Color, rim: Color, _gloss_alpha: float) -> void:
	draw_style_box(RallyUITheme.make_flat_panel(fill, rim, 1, mini(radius, RallyUITheme.CORNER_RADIUS)), rect)


func _chrome_button(rect: Rect2, label: String, action: String) -> void:
	_chrome_button_sized(rect, label, action, 15)


func _chrome_button_sized(rect: Rect2, label: String, action: String, font_size: int) -> void:
	var hovered := _mouse_over(rect)
	var fill := WB_BG_CARD_HOVER if hovered else WB_BG_CARD
	draw_style_box(RallyUITheme.make_flat_panel(fill, BORDER_FOCUS if hovered else RallyUITheme.BORDER_CARD, 1, RallyUITheme.CORNER_RADIUS), rect)
	_text_with(FONT_BUTTON, _box(rect.position.x, rect.position.y, rect.size.x, rect.size.y), label, font_size, C_CHROME_TEXT, HORIZONTAL_ALIGNMENT_CENTER, -1.0)
	_hit_regions.append({ "rect": rect, "kind": "button", "action": action })


func _classic_button(rect: Rect2, label: String, action: String, modal: bool = false) -> void:
	var hovered := _mouse_over(rect)
	var fill := C_FACE_HI if hovered else C_FACE_LO
	draw_style_box(RallyUITheme.make_flat_panel(fill, BORDER_FOCUS if hovered else RallyUITheme.BORDER_CARD, 1, RallyUITheme.CORNER_RADIUS), rect)
	_text_with(FONT_BUTTON, _box(rect.position.x, rect.position.y - 1, rect.size.x, rect.size.y), label, 15, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, -1.0)
	_hit_regions.append({ "rect": rect, "kind": "button", "action": action, "modal": modal })


func _gold_button(rect: Rect2, label: String, action: String, modal: bool = false) -> void:
	var hovered := _mouse_over(rect)
	var fill := Color("#f2bb54") if hovered else ACCENT_RALLY
	draw_style_box(RallyUITheme.make_flat_panel(fill, Color("#f6c96e"), 1, RallyUITheme.CORNER_RADIUS), rect)
	_text_with(FONT_BUTTON, _box(rect.position.x, rect.position.y - 1, rect.size.x, rect.size.y), label, 15, BG_BASE, HORIZONTAL_ALIGNMENT_CENTER, -1.0)
	_hit_regions.append({ "rect": rect, "kind": "button", "action": action, "modal": modal })


# =============================================================================
# MODAL
# =============================================================================


func _draw_modal() -> void:
	draw_rect(Rect2(Vector2.ZERO, LOGICAL_SIZE), RallyUITheme.BG_OVERLAY)
	var rect := Rect2(390, 262, 500, 250)
	_glass_window(rect, RallyUITheme.CORNER_RADIUS)
	_text_title(_box(rect.position.x + 18, rect.position.y + 8, rect.size.x - 36, 32), "PERFIL" if modal_mode == "name" else "CONFIRMACIÓN", 16, C_GOLD)
	draw_line(Vector2(rect.position.x + 1, rect.position.y + 44), Vector2(rect.end.x - 1, rect.position.y + 44), BORDER_SUBTLE, 1.0)

	var body := Rect2(rect.position.x + 18, rect.position.y + 58, rect.size.x - 36, 118)
	draw_rect(body, C_FACE)
	_sunken(body)

	if modal_mode == "name":
		_text_with(FONT_SUBTITLE, _box(body.position.x + 12, body.position.y + 10, body.size.x - 24, 20), "NOMBRE DEL REGLAJE", 12, C_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0)
		var input := Rect2(body.position.x + 12, body.position.y + 36, body.size.x - 24, 40)
		draw_rect(input, C_FIELD)
		_sunken(input)
		_text(_box(input.position.x + 8, input.position.y, input.size.x - 16, input.size.y), modal_text, 12, C_TEXT)
		var caret_x := input.position.x + 8.0 + _serif_width(modal_text, 12, false) + 2.0
		draw_rect(Rect2(caret_x, input.position.y + 11, 1, 18), C_TEXT)
		_hint(_box(body.position.x + 12, body.position.y + 84, body.size.x - 24, 18), "ENTER GUARDA · ESC CANCELA")
	elif modal_mode == "delete":
		var selected_name := "seleccionado"
		for row in setup_rows:
			if int(row.get("id", -1)) == selected_setup_id:
				selected_name = str(row.get("name", selected_name))
		_text(_box(body.position.x + 12, body.position.y + 30, body.size.x - 24, 24), "¿ELIMINAR «" + selected_name.to_upper() + "»?", 11, C_TEXT, true)
		_hint(_box(body.position.x + 12, body.position.y + 74, body.size.x - 24, 18), "ESTA ACCIÓN NO SE PUEDE DESHACER")
	else:
		_text(_box(body.position.x + 12, body.position.y + 30, body.size.x - 24, 24), "¿DESCARTAR CAMBIOS SIN APLICAR?", 11, C_TEXT, true)
		_hint(_box(body.position.x + 12, body.position.y + 74, body.size.x - 24, 18), "SE PERDERÁN LOS AJUSTES DE ESTA SESIÓN")

	_classic_button(Rect2(rect.end.x - 300, rect.end.y - 62, 130, 40), "CANCELAR", "cancel", true)
	_gold_button(Rect2(rect.end.x - 158, rect.end.y - 62, 140, 40), "ACEPTAR", "accept", true)


# =============================================================================
# TEXTO
# =============================================================================


func _box(x: float, y: float, width: float, height: float) -> Rect2:
	return Rect2(x, y, width, height)


func _mouse_over(rect: Rect2) -> bool:
	return rect.has_point(_hover_point)


func _text(
	rect: Rect2,
	text: String,
	size: int,
	color: Color,
	bold: bool = false,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	width_override: float = -1.0
) -> void:
	_text_with(FONT_SERIF_BOLD if bold else FONT_SERIF, rect, text, size, color, align, width_override)


func _num(
	rect: Rect2,
	text: String,
	size: int,
	color: Color,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	width_override: float = -1.0
) -> void:
	_text_with(FONT_UI_BOLD, rect, text, size, color, align, width_override)


func _text_serif(
	rect: Rect2,
	text: String,
	size: int,
	color: Color,
	bold: bool = false,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	width_override: float = -1.0
) -> void:
	_text(rect, text, size, color, bold, align, width_override)


func _text_title(
	rect: Rect2,
	text: String,
	size: int,
	color: Color,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	width_override: float = -1.0
) -> void:
	_text_with(FONT_TITLE, rect, text, size, color, align, width_override)


func _title_width(text: String, size: int) -> float:
	return FONT_SUBTITLE.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _text_with(
	font: Font,
	rect: Rect2,
	text: String,
	size: int,
	color: Color,
	align: HorizontalAlignment,
	width_override: float
) -> void:
	if text.is_empty():
		return
	var width: float = rect.size.x if width_override < 0.0 else width_override
	var line_height := font.get_height(size)
	var baseline := rect.position.y + (rect.size.y + line_height) * 0.5 - font.get_descent(size)
	draw_string(font, Vector2(round(rect.position.x), round(baseline)), text, align, width, size, color)


func _ui_width(text: String, size: int, bold: bool) -> float:
	var font := FONT_UI_BOLD if bold else FONT_UI
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _serif_width(text: String, size: int, bold: bool) -> float:
	var font := FONT_SERIF_BOLD if bold else FONT_SERIF
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _short_timestamp(value: String) -> String:
	if value.is_empty():
		return ""
	return value.replace("T", " ").trim_suffix("Z").left(16)


func _fuel_density() -> float:
	return maxf(vehicle.simulation.mass_model.fuel_density_kg_per_litre, 0.000001) if vehicle != null else 0.74
