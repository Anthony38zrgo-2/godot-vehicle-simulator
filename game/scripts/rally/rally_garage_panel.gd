class_name RallyGaragePanel
extends Control

signal garage_closed(applied: bool)

const LOGICAL_SIZE := Vector2(1280.0, 800.0)
const StrategyBoardScript := preload("res://scripts/rally/rally_garage_strategy_board.gd")
# 2.2. Estandarización Tipográfica (fuente única: RallyUITheme)
# 2.2. Estandarización Tipográfica (Bungee + Big Shoulders + Science Gothic)
const FONT_SERIF: Font = RallyUITheme.FONT_REGULAR
const FONT_SERIF_BOLD: Font = RallyUITheme.FONT_MEDIUM
const FONT_UI: Font = RallyUITheme.FONT_MEDIUM_TIGHT
const FONT_UI_BOLD: Font = RallyUITheme.FONT_DATA_BOLD_TIGHT
const FONT_TITLE: Font = RallyUITheme.FONT_TITLE
const FONT_SUBTITLE: Font = RallyUITheme.FONT_SUBTITLE
const FONT_BUTTON: Font = RallyUITheme.FONT_BUTTON

# 2.1. Paleta de Colores Funcional Unificada (Dark Carbon + Brass Gold)
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

# 2.3. Aliases Workbench consolidados
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

const PANEL := Rect2(24.0, 100.0, 1232.0, 586.0)
const PAGE_TOP := 156.0
const PAGE_BOTTOM := 674.0

const QUICK_PATHS: Array[String] = [
	"balance",
	"brakes.front_brake_bias",
	"height",
	"powertrain.final_drive",
]
const SUSPENSION_PATHS: Array[String] = [
	"suspension.front.ride_frequency_hz",
	"suspension.front.resting_ratio",
	"suspension.front.damping_ratio",
	"suspension.front.bump_damp_multiplier",
	"suspension.front.rebound_damp_multiplier",
	"suspension.front.bump_stop_multiplier",
	"suspension.rear.ride_frequency_hz",
	"suspension.rear.resting_ratio",
	"suspension.rear.damping_ratio",
	"suspension.rear.bump_damp_multiplier",
	"suspension.rear.rebound_damp_multiplier",
	"suspension.rear.bump_stop_multiplier",
	"suspension.geometry_physical.front_arb.ratio",
	"suspension.geometry_physical.rear_arb.ratio",
	"steering.max_steering_angle",
	"steering.steering_speed",
]
const WHEELS_PATHS: Array[String] = [
	"tires.pressure.cold_kpa_gauge.FL",
	"tires.pressure.cold_kpa_gauge.FR",
	"tires.pressure.cold_kpa_gauge.RL",
	"tires.pressure.cold_kpa_gauge.RR",
	"suspension.front.camber",
	"suspension.rear.camber",
	"suspension.front.toe",
	"suspension.rear.toe",
	"aero.model.front_wing.incidence_deg",
	"aero.model.rear_wing.incidence_deg",
	"brakes.front_brake_bias",
	"brakes.max_brake_torque",
]
const POWERTRAIN_PATHS: Array[String] = [
	"powertrain.max_rpm",
	"powertrain.final_drive",
	"powertrain.reverse_ratio",
	"powertrain.gear_ratios.0",
	"powertrain.gear_ratios.1",
	"powertrain.gear_ratios.2",
	"powertrain.gear_ratios.3",
	"steering.max_steering_angle",
	"steering.steering_speed",
]
# v1: el diferencial es selección discreta por preset, no 4 sliders.
const DIFFERENTIAL_PRESET_PATH := "powertrain.differential.preset_id"
# preload directo: no depende de la caché global de clases del editor.
const RallyDifferentialCatalog = preload("res://scripts/rally/rally_differential_catalog.gd")
# Modo modern: LSD libre con los 4 números (como antes de los presets).
const MODERN_DIFFERENTIAL_PATHS: Array[String] = [
	"powertrain.differential.preload_nm",
	"powertrain.differential.power_ramp_angle_deg",
	"powertrain.differential.coast_ramp_angle_deg",
	"powertrain.differential.clutches",
]
const STRATEGY_PATHS: Array[String] = ["fuel.initial_kg", "footer:cancel", "footer:apply"]

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
var _cached_route_length_m: float = 0.0
var _stage_length_explicit: bool = false

var advanced_section := 0
var mandatory_confirmation := false
var compound_change_allowed := true
var allowed_compound_ids: Array = []
var default_event_compound_id: String = RallyTireCompound.DEFAULT_ID
var draft_wheel_compounds: Dictionary = { }
var draft_compound_id: String:
	get:
		# Legacy event summary; mounted wheels remain the source of truth.
		return str(draft_wheel_compounds.get("FL", RallyTireCompound.DEFAULT_ID))
	set(value):
		for corner in ["FL", "FR", "RL", "RR"]:
			draft_wheel_compounds[corner] = value
var opening_wheel_compounds: Dictionary = { }
var draft_spare_wheels := 1
var opening_spares := 1
var confirmed_setup: Dictionary = { }
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
var active_setup_name: String = "BASE"
var setup_rows: Array[Dictionary] = []
var draft_values: Dictionary = { }
var opening_values: Dictionary = { }
var pending_values: Dictionary = { }
var new_tires_service: bool = false
var modal_mode: String = ""
var modal_text: String = ""
var notice: String = ""
var notice_time: float = 0.0
var notice_is_error: bool = false
var _hit_regions: Array[Dictionary] = []
var _page_field_paths: Array[String] = []
var _canvas_scale: float = 1.0
var _canvas_offset: Vector2 = Vector2.ZERO
var _restore_tree_paused: bool = false
var _restore_controls_enabled: bool = true
var _hover_point := Vector2(-4000.0, -4000.0)
var _dragging_path: String = ""
var _dragging_rect := Rect2()
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
	if options.has("stage_id") and not str(options.get("stage_id", "")).is_empty():
		circuit_id = str(options["stage_id"])
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


func open_garage_for_event(options: Dictionary = { }) -> void:
	mandatory_confirmation = bool(options.get("confirmation_required", false))
	set_stage_metadata(options)
	compound_change_allowed = bool(options.get("compound_change_allowed", true))
	allowed_compound_ids = (
		options.get("allowed_compound_ids", []) as Array
	).duplicate()
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
		_set_page(2, false)
	elif initial_tab == "quick":
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
		default_event_compound_id = RallyTireCompound.DEFAULT_ID
		event_forecast = ""
	_restore_tree_paused = get_tree().paused
	_restore_controls_enabled = input_controller.controls_enabled if input_controller != null else true
	opening_values = vehicle.simulation.filter_garage_values(RallySetupCatalog.defaults(vehicle.simulation.domains))
	opening_values["fuel.initial_kg"] = vehicle.simulation.thermal_model.fuel_remaining_litres * vehicle \
			.simulation \
			.mass_model \
			.fuel_density_kg_per_litre
	draft_values = opening_values.duplicate(true)
	vehicle.ensure_tire_inventory()
	_sync_draft_pool_from_inventory()
	opening_wheel_compounds = draft_wheel_compounds.duplicate()
	opening_spares = draft_spare_wheels
	confirmed_setup = { }
	pending_values = { }
	new_tires_service = false
	selected_pool_tire_id = -1
	_pool_plan_dirty = false
	page = 0
	advanced_section = 0
	selected_field_path = ""
	_set_page(0, false)
	_ensure_stage_route_cache()
	active_setup_id = -1
	active_setup_name = "BASE"
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
	var show_board := visible and page == 2 and modal_mode == "" and _is_pool_mode()
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
	if page != 2:
		return
	var prev := selected_field_path
	_page_field_paths.clear()
	_page_field_paths.append("fuel.initial_kg")
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
	_page_field_paths.append("footer:cancel")
	_page_field_paths.append("footer:apply")
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
				page == 2 and modal_mode == "" and _is_pool_mode()
				and _strategy_board != null and _strategy_board.visible
				and _dragging_path == ""
				and _strategy_board.has_pointer_control(get_global_mouse_position())
			):
				return
			_handle_click(_to_logical(mouse_event.position))
			accept_event()
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _dragging_path == "":
				_set_page(page - 1)
				accept_event()
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _dragging_path == "":
				_set_page(page + 1)
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
		KEY_LEFT, KEY_Q:
			_adjust_selected(-1.0)
		KEY_RIGHT, KEY_E:
			_adjust_selected(1.0)
		KEY_UP, KEY_W:
			_navigate_selection(-1)
		KEY_DOWN, KEY_S:
			_navigate_selection(1)
		KEY_TAB:
			if page == 1:
				advanced_section = posmod(advanced_section + 1, 3)
				_set_page(1)
			else:
				_navigate_selection(1)
		KEY_X:
			if page == 2 and _is_pool_mode() and selected_field_path.begins_with("spare:"):
				_unload_spare_slot(int(selected_field_path.trim_prefix("spare:")))
			elif selected_pool_tire_id >= 0:
				selected_pool_tire_id = -1
		KEY_DELETE:
			if page == 3:
				_begin_delete_setup()
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
	match event.button_index:
		JOY_BUTTON_Y:
			close_garage(true)
		JOY_BUTTON_B, JOY_BUTTON_START:
			close_garage(false)
		JOY_BUTTON_A:
			_confirm_selection()
		JOY_BUTTON_X:
			if page == 2 and _is_pool_mode() and selected_field_path.begins_with("spare:"):
				_unload_spare_slot(int(selected_field_path.trim_prefix("spare:")))
			elif selected_pool_tire_id >= 0:
				selected_pool_tire_id = -1
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


# Las regiones se registran de fuera hacia dentro: la fila primero y sus
# controles después, de modo que al recorrerlas al revés los botones ganan.
func _handle_click(point: Vector2) -> void:
	var modal_open := modal_mode != ""
	for index in range(_hit_regions.size() - 1, -1, -1):
		var region: Dictionary = _hit_regions[index]
		if bool(region.get("modal", false)) != modal_open:
			continue
		if not (region.rect as Rect2).has_point(point):
			continue
		match str(region.kind):
			"section":
				advanced_section = int(region.index)
				_set_page(1)
			"quick":
				selected_field_path = str(region.path)
				if bool(region.get("slider", false)):
					_quick_slide(str(region.path), point.x, region.rect as Rect2)
				else:
					_quick_adjust(str(region.path), float(region.amount))
			"quick_slide":
				selected_field_path = str(region.path)
				_dragging_path = str(region.path)
				_dragging_rect = region.get("track", region.rect) as Rect2
				_drag_to(point)
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
				_set_page(int(region.page))
			"select":
				selected_field_path = str(region.path)
			"slide":
				selected_field_path = str(region.path)
				_dragging_path = str(region.path)
				_dragging_rect = region.get("track", region.rect) as Rect2
				_drag_to(point)
			"adjust":
				selected_field_path = str(region.path)
				_adjust_field(str(region.path), float(region.amount))
			"preset_adjust":
				selected_field_path = DIFFERENTIAL_PRESET_PATH
				_cycle_preset(float(region.amount))
			"button":
				_run_button(str(region.action))
			"setup_row":
				selected_setup_index = int(region.index)
				selected_setup_id = int(setup_rows[selected_setup_index].get("id", -1))
				selected_field_path = ""
			"service":
				new_tires_service = not new_tires_service
			"modal":
				_run_modal(str(region.action))
		queue_redraw()
		return


func _drag_to(point: Vector2) -> void:
	if _dragging_path.is_empty():
		return
	if _dragging_path in ["balance", "height"]:
		_quick_slide(_dragging_path, point.x, _dragging_rect)
	else:
		_set_from_slider(_dragging_path, point.x, _dragging_rect)


func _set_page(next_page: int, play_sound: bool = true) -> void:
	var previous_page := page
	page = posmod(next_page, 4)
	if play_sound and page != previous_page:
		get_node("/root/UIButtonAudio").play_tab_click()
	_page_field_paths.clear()
	var source: Array[String] = []
	match page:
		0:
			source = QUICK_PATHS
		1:
			match advanced_section:
				0:
					source = SUSPENSION_PATHS
				1:
					source = WHEELS_PATHS
				_:
					source = POWERTRAIN_PATHS.duplicate()
					if is_instance_valid(vehicle) and vehicle.simulation.is_historic_differential():
						source.append(DIFFERENTIAL_PRESET_PATH)
					else:
						source.append_array(MODERN_DIFFERENTIAL_PATHS)
		2:
			source = STRATEGY_PATHS
	for path in source:
		if not _page_field_paths.has(path):
			_page_field_paths.append(path)
	if page == 2:
		_refresh_strategy_nav_paths()
	if not _page_field_paths.has(selected_field_path):
		selected_field_path = _page_field_paths[0] if not _page_field_paths.is_empty() else ""
	if page == 3:
		_refresh_setups()
	_sync_strategy_board()
	queue_redraw()


func _navigate_selection(direction: int) -> void:
	if page == 3:
		if setup_rows.is_empty():
			selected_setup_index = 0
		else:
			selected_setup_index = posmod(selected_setup_index + direction, setup_rows.size())
			selected_setup_id = int(setup_rows[selected_setup_index].get("id", -1))
			var visible_rows := _setup_visible_rows()
			if selected_setup_index < setup_scroll_offset:
				setup_scroll_offset = selected_setup_index
			elif selected_setup_index >= setup_scroll_offset + visible_rows:
				setup_scroll_offset = selected_setup_index - visible_rows + 1
		return
	if _page_field_paths.is_empty():
		_set_page(page)
		return
	var index := _page_field_paths.find(selected_field_path)
	selected_field_path = _page_field_paths[posmod(index + direction, _page_field_paths.size())]


func _adjust_selected(direction: float) -> void:
	if page == 3:
		_navigate_selection(int(direction))
		return
	if selected_field_path.is_empty() and not _page_field_paths.is_empty():
		selected_field_path = _page_field_paths[0]
	if selected_field_path in ["balance", "height"]:
		_quick_adjust(selected_field_path, direction)
		return
	_adjust_field(selected_field_path, direction)


func _adjust_field(path: String, direction: float) -> void:
	if path == DIFFERENTIAL_PRESET_PATH:
		_cycle_preset(direction)
		return
	if page == 2:
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
	var field := RallySetupCatalog.field_for_path(path)
	if field.is_empty():
		return
	var current := float(draft_values.get(path, 0.0))
	var next_value := current + float(field.step) * direction
	_update_value(path, next_value)


func _set_from_slider(path: String, x: float, rect: Rect2) -> void:
	var field := RallySetupCatalog.field_for_path(path)
	if field.is_empty():
		return
	var normalized := clampf((x - rect.position.x) / maxf(rect.size.x, 1.0), 0.0, 1.0)
	_update_value(path, lerpf(float(field.min), float(field.max), normalized))


func _update_value(path: String, value: float) -> void:
	var field := RallySetupCatalog.field_for_path(path)
	if field.is_empty():
		return
	var clamped := snappedf(clampf(value, float(field.min), float(field.max)), float(field.step))
	draft_values[path] = clamped
	var result := vehicle.apply_setup_values(draft_values)
	if not bool(result.get("ok", false)):
		_show_notice(str(result.get("error", "Error de ajuste.")), true)
	else:
		draft_values = result.values
	queue_redraw()


# --- v1 diferencial por preset (selección discreta) ---
func _garage_profile_id() -> String:
	if vehicle == null or vehicle.simulation == null:
		return ""
	return str(vehicle.simulation.active_differential_profile())


func _preset_options() -> Array[Dictionary]:
	return RallyDifferentialCatalog.list_for_profile(_garage_profile_id())


func _draft_preset_id() -> String:
	var pid := _garage_profile_id()
	var current := str(draft_values.get(DIFFERENTIAL_PRESET_PATH, ""))
	if current.is_empty() or not RallyDifferentialCatalog.is_allowed(pid, current):
		current = vehicle.simulation.active_differential_preset_id
	if current.is_empty():
		current = RallyDifferentialCatalog.default_for_profile(pid)
	return current


func _cycle_preset(direction: float) -> void:
	var options := _preset_options()
	if options.is_empty():
		_show_notice("Este vehículo no tiene catálogo de diferencial.", true)
		return
	var enabled_ids: Array[String] = []
	for p in options:
		if bool(p.get("enabled", false)):
			enabled_ids.append(str(p.get("id", "")))
	if enabled_ids.is_empty():
		_show_notice("Sin presets habilitados (pendiente de calibración).", true)
		return
	var current := _draft_preset_id()
	var index := enabled_ids.find(current)
	if index < 0:
		index = 0
	else:
		index = posmod(index + int(signf(direction)), enabled_ids.size())
	draft_values[DIFFERENTIAL_PRESET_PATH] = enabled_ids[index]
	var result := vehicle.apply_setup_values(draft_values)
	if not bool(result.get("ok", false)):
		_show_notice(str(result.get("error", "Error de diferencial.")), true)
	else:
		draft_values = result.values
	queue_redraw()


func _confirm_selection() -> void:
	if page == 2:
		if selected_field_path == "footer:apply":
			close_garage(true)
			return
		if selected_field_path == "footer:cancel":
			close_garage(false)
			return
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
	elif page == 3:
		_load_selected_setup()
	elif selected_field_path.is_empty() and not _page_field_paths.is_empty():
		selected_field_path = _page_field_paths[0]
	_sync_strategy_board()
	queue_redraw()


func _quick_adjust(path: String, amount: float) -> void:
	if path == "height":
		var current := _average_ride_height()
		var value := clampf(current + amount * 0.02, 0.2, 0.8)
		draft_values["suspension.front.resting_ratio"] = value
		draft_values["suspension.rear.resting_ratio"] = value
	elif path == "balance":
		var front := float(draft_values.get("suspension.geometry_physical.front_arb.ratio", 1.0))
		var rear := float(draft_values.get("suspension.geometry_physical.rear_arb.ratio", 1.0))
		draft_values["suspension.geometry_physical.front_arb.ratio"] = clampf(
			front + amount * 0.04, 0.0, 2.0
		)
		draft_values["suspension.geometry_physical.rear_arb.ratio"] = clampf(
			rear - amount * 0.04, 0.0, 2.0
		)
	else:
		_adjust_field(path, amount)
		return
	_apply_draft()


# Arrastrar una fila rápida traduce la posición a los valores reales que hay
# detrás: el equilibrio es un diferencial de barras y la altura un promedio.
func _quick_slide(path: String, x: float, rect: Rect2) -> void:
	var fraction := clampf((x - rect.position.x) / maxf(rect.size.x, 1.0), 0.0, 1.0)
	match path:
		"balance":
			var front := float(draft_values.get("suspension.geometry_physical.front_arb.ratio", 1.0))
			var rear := float(draft_values.get("suspension.geometry_physical.rear_arb.ratio", 1.0))
			var mean := (front + rear) * 0.5
			var delta := (fraction - 0.5) * 4.0
			draft_values["suspension.geometry_physical.front_arb.ratio"] = clampf(
				mean + delta * 0.5, 0.0, 2.0
			)
			draft_values["suspension.geometry_physical.rear_arb.ratio"] = clampf(
				mean - delta * 0.5, 0.0, 2.0
			)
		"height":
			var value := lerpf(0.2, 0.8, fraction)
			draft_values["suspension.front.resting_ratio"] = value
			draft_values["suspension.rear.resting_ratio"] = value
		"powertrain.final_drive":
			var field := RallySetupCatalog.field_for_path(path)
			if field.is_empty():
				return
			_update_value(path, lerpf(float(field.max), float(field.min), fraction))
			return
		_:
			var field := RallySetupCatalog.field_for_path(path)
			if field.is_empty():
				return
			_update_value(path, lerpf(float(field.min), float(field.max), fraction))
			return
	_apply_draft()


func _apply_draft() -> void:
	var result := vehicle.apply_setup_values(draft_values)
	if bool(result.get("ok", false)):
		draft_values = result.values
	else:
		_show_notice(str(result.get("error", "Error")), true)
	queue_redraw()


func _get_quick_fraction(path: String) -> float:
	match path:
		"balance":
			var front := float(draft_values.get("suspension.geometry_physical.front_arb.ratio", 1.0))
			var rear := float(draft_values.get("suspension.geometry_physical.rear_arb.ratio", 1.0))
			return clampf(0.5 + (front - rear) * 0.25, 0.0, 1.0)
		"height":
			return clampf((_average_ride_height() - 0.2) / 0.6, 0.0, 1.0)
		"powertrain.final_drive":
			var field := RallySetupCatalog.field_for_path(path)
			if field.is_empty():
				return 0.5
			var scaled := (float(draft_values.get(path, 4.0)) - float(field.min)) / maxf(
				float(field.max) - float(field.min), 0.001
			)
			return clampf(1.0 - scaled, 0.0, 1.0)
		_:
			var field := RallySetupCatalog.field_for_path(path)
			if field.is_empty():
				return 0.5
			return _field_fraction(field, path)


func _average_ride_height() -> float:
	return (
		float(draft_values.get("suspension.front.resting_ratio", 0.35))
		+ float(draft_values.get("suspension.rear.resting_ratio", 0.35))
	) * 0.5


func _run_button(action: String) -> void:
	match action:
		"reset":
			draft_values = vehicle.simulation.setup_design_values.duplicate(true)
			active_setup_id = -1
			active_setup_name = "BASE"
			vehicle.apply_setup_values(draft_values)
			_show_notice("Valores restaurados.")
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
	selected_setup_id = int(setup_rows[selected_setup_index].get("id", -1)) if not setup_rows.is_empty() else -1


func _setup_visible_rows() -> int:
	return 9


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
	if target_id >= 0:
		for row in setup_rows:
			if int(row.get("id", -1)) == target_id:
				target_name = str(row.get("name", target_name))
				break
	elif active_setup_id >= 0:
		target_id = active_setup_id
	if target_id < 0:
		modal_mode = "name"
		modal_text = active_setup_name if not (active_setup_name in ["BASE", "FÁBRICA", "RESTAURAR"]) else ""
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
	# Extraer estrategia de neumaticos antes de validate() numerico.
	var stored_compounds: Dictionary = {}
	var has_stored_spares := stored.has("strategy.spare_wheels")
	var stored_spares := int(stored.get("strategy.spare_wheels", draft_spare_wheels))
	if has_stored_spares:
		stored.erase("strategy.spare_wheels")
	for k in stored.keys():
		if str(k).begins_with("strategy.wheel_compound."):
			stored_compounds[str(k).trim_prefix("strategy.wheel_compound.")] = str(stored[k])
			stored.erase(k)
	# v1: el preset es string y no pasa por validate() numérico.
	# Si el campo existe, reenviar su valor original (incluso inválido) a
	# vehicle.apply_setup_values() para validación centralizada.
	# No descartar silenciosamente un preset_id inválido de SQLite.
	var has_stored_preset := stored.has(DIFFERENTIAL_PRESET_PATH)
	var stored_preset: Variant = null
	if has_stored_preset:
		stored_preset = stored[DIFFERENTIAL_PRESET_PATH]
		stored.erase(DIFFERENTIAL_PRESET_PATH)
	var validation := RallySetupCatalog.validate(stored)
	if not bool(validation.get("ok", false)):
		_show_notice(str(validation.get("error", "Incompatible.")), true)
		return
	var to_apply: Dictionary = (validation as Dictionary).get("values", {}).duplicate(true)
	if has_stored_preset and vehicle.simulation.is_historic_differential():
		to_apply[DIFFERENTIAL_PRESET_PATH] = stored_preset
	var available_ids := _available_compound_ids()
	for corner in stored_compounds:
		if not str(stored_compounds[corner]) in available_ids:
			_show_notice("Compuesto no permitido en este evento.", true)
			return
	# En modo modern el preset guardado se ignora: manda el LSD libre.
	var applied := vehicle.apply_setup_values(to_apply)
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
			active_setup_name = "BASE"
		_show_notice("Eliminado.")
		_refresh_setups()
	else:
		_show_notice(str(result.get("error", "Error al eliminar.")), true)
	queue_redraw()


func _database_context() -> Dictionary:
	# Setups belong to the car and circuit, not to a hash of changing JSON.
	# Keep the legacy DB column populated with an empty value for old schemas.
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
			_draw_quick_page()
		1:
			_draw_advanced_page()
		2:
			_draw_strategy_page()
		3:
			_draw_setups_page()

	_draw_chrome_footer()

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
	_glass_window(Rect2(24, 18, 1232, 76), RallyUITheme.CORNER_RADIUS)

	var car_title := _get_vehicle_display_name()
	var title_size := 26
	while title_size > 16 and FONT_SUBTITLE.get_string_size(car_title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > 272.0:
		title_size -= 1
	_text_with(FONT_SUBTITLE, _box(46, 34, 272, 44), car_title, title_size, C_CHROME_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0)

	draw_line(Vector2(330, 34), Vector2(330, 78), BORDER_SUBTLE, 1.0)

	_ensure_stage_route_cache()
	_text_with(FONT_SUBTITLE, _box(354, 22, 0, 34), circuit_name.to_upper(), 21, C_CHROME_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0)
	var subtitle := "%s  ·  %0.1f KM  ·  %s" % [
		circuit_country.to_upper(), _effective_stage_length_m() / 1000.0, mode.to_upper()
	]
	_text_with(FONT_UI, _box(354, 54, 360, 26), subtitle, 10, C_CHROME_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0)

	_glass_box(Rect2(986, 30, 250, 52), RallyUITheme.CORNER_RADIUS, C_GLASS_DEEP, RallyUITheme.BORDER_CARD, 0.0)
	_text_with(FONT_SUBTITLE, _box(1002, 36, 218, 20), "REGLAJE ACTIVO", 11, C_CHROME_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0)
	_text_title(
		_box(1002, 54, 218, 24),
		active_setup_name.to_upper(),
		18,
		C_GOLD,
		HORIZONTAL_ALIGNMENT_RIGHT,
		218
	)


func _draw_chrome_footer() -> void:
	_glass_window(Rect2(24, 692, 1232, 88), RallyUITheme.CORNER_RADIUS)

	_chrome_button(Rect2(46, 714, 168, 46), "RESTAURAR", "reset")

	# Franja reservada para el aviso: nunca se dibuja encima del contenido.
	var lane := Rect2(400, 700, 470, 72)
	if notice_time > 0.0 and not notice.is_empty():
		var tone := C_ROSE if _notice_is_error() else C_GOLD
		_glass_box(lane, RallyUITheme.CORNER_RADIUS, Color(C_GLASS_DEEP, 0.92), Color(tone, 0.55), 0.0)
		_text_serif(
			_box(lane.position.x + 12, lane.position.y, lane.size.x - 24, lane.size.y),
			notice.to_upper(),
			10,
			tone,
			true,
			HORIZONTAL_ALIGNMENT_CENTER
		)
	else:
		_text_with(
			FONT_SERIF,
			_box(lane.position.x, lane.position.y, lane.size.x, lane.size.y),
			"A / ENTER SELECCIONA · W/S NAVEGA · Y / F5 APLICA · B / START / ESC SALIR",
			9,
			Color(C_CHROME_DIM, 0.80),
			HORIZONTAL_ALIGNMENT_CENTER,
			-1.0
		)

	var cancel_rect := Rect2(900, 714, 150, 46)
	var apply_rect := Rect2(1066, 714, 168, 46)
	_chrome_button(cancel_rect, "CANCELAR", "cancel")
	_gold_button(apply_rect, "APLICAR", "apply")
	if selected_field_path == "footer:cancel":
		draw_rect(cancel_rect.grow(2), BORDER_FOCUS, false, 2.0)
	elif selected_field_path == "footer:apply":
		draw_rect(apply_rect.grow(2), BORDER_FOCUS, false, 2.0)


func _notice_is_error() -> bool:
	return notice_is_error


func _draw_classic_panel() -> void:
	draw_style_box(RallyUITheme.make_flat_panel(C_FACE, RallyUITheme.BORDER_CARD, 1, RallyUITheme.CORNER_RADIUS), PANEL)
	draw_line(Vector2(PANEL.position.x, 144), Vector2(PANEL.end.x, 144), BORDER_SUBTLE, 1.0)


func _draw_tabs() -> void:
	var titles := ["RÁPIDO", "AVANZADO", "ESTRATEGIA", "PERFILES"]
	var x := 34.0
	for index in titles.size():
		var label: String = titles[index]
		var width: float = maxf(126.0, FONT_BUTTON.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 52.0)
		var rect := Rect2(x, 100, width, 44)
		_tab(rect, label, index == page)
		_hit_regions.append({ "rect": rect, "kind": "tab", "page": index })
		x += width + 4.0

	var changed := _dirty_field_count()
	if changed > 0:
		var banner := "%d CAMBIO%s SIN APLICAR" % [changed, "" if changed == 1 else "S"]
		var banner_w := _ui_width(banner, 9, true)
		var banner_x := 1244.0 - banner_w
		draw_circle(Vector2(banner_x - 14.0, 122.0), 3.5, C_GOLD)
		_num(_box(banner_x, 104, banner_w + 2, 36), banner, 9, C_GOLD)


func _dirty_field_count() -> int:
	var count := 0
	for path in draft_values:
		var a: Variant = draft_values.get(path, 0.0)
		var b: Variant = opening_values.get(path, 0.0)
		if a is String or b is String:
			if str(a) != str(b):
				count += 1
		elif float(a) != float(b):
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
# PÁGINA 0 — RÁPIDO
# =============================================================================


func _draw_quick_page() -> void:
	var section := Rect2(36, PAGE_TOP, 816, PAGE_BOTTOM - PAGE_TOP)
	_group(section, "AJUSTES RÁPIDOS")

	var rows := [
		{
			"key": "balance",
			"name": "EQUILIBRIO",
			"hint": "SOBREVIRAJE / SUBVIRAJE",
			"left": "SUELTA",
			"right": "DURO",
			"value": _balance_text(),
			"numeric": false,
		},
		{
			"key": "brakes.front_brake_bias",
			"name": "FRENADA",
			"hint": "REPARTO DELANTERO / TRASERO",
			"left": "TRASERA",
			"right": "DELANTERA",
			"value": "%0.1f %%" % (float(draft_values.get("brakes.front_brake_bias", 0.6)) * 100.0),
		},
		{
			"key": "height",
			"name": "ALTURA",
			"hint": "ALTURA DE MARCHA MEDIA",
			"left": "BAJA",
			"right": "ALTA",
			"value": "%0.3f" % _average_ride_height(),
		},
		{
			"key": "powertrain.final_drive",
			"name": "TRANSMISIÓN",
			"hint": "RELACIÓN FINAL",
			"left": "ACELERACIÓN",
			"right": "VEL. PUNTA",
			"value": "%0.2f" % float(draft_values.get("powertrain.final_drive", 4.0)),
		},
	]
	var inner := _group_inner(section)
	var height := floorf(inner.size.y / float(rows.size()))
	var offset := (inner.size.y - height * float(rows.size())) * 0.5
	for i in rows.size():
		_quick_row(
			Rect2(inner.position.x, inner.position.y + float(i) * height + offset, inner.size.x, height),
			rows[i],
			i == rows.size() - 1
		)

	_draw_stage_info_group(Rect2(864, PAGE_TOP, 380, PAGE_BOTTOM - PAGE_TOP))


func _balance_text() -> String:
	var fraction := _get_quick_fraction("balance")
	if absf(fraction - 0.5) < 0.04:
		return "NEUTRO"
	return "SUBVIRAJE" if fraction > 0.5 else "SOBREVIRAJE"


func _quick_row(rect: Rect2, data: Dictionary, last: bool) -> void:
	var key: String = str(data.key)
	var selected := selected_field_path == key
	_row_frame(rect, selected, last, _mouse_over(rect))
	_hit_regions.append({ "rect": rect, "kind": "select", "path": key })

	var mid_y := rect.position.y + rect.size.y * 0.5
	var title_size := 12 if rect.size.y >= 96.0 else 11
	_text(_box(rect.position.x + 14, mid_y - 22.0, 250, 24), str(data.name), title_size, C_TEXT, true)
	_hint(_box(rect.position.x + 14, mid_y + 4.0, 250, 18), str(data.hint))

	var track_x := rect.position.x + 242.0
	var track_w := 340.0
	_text(_box(track_x, mid_y - 22.0, 150, 14), str(data.left), 8, C_DIM, true)
	_text(
		_box(track_x + track_w - 150, mid_y - 22.0, 150, 14),
		str(data.right),
		8,
		C_DIM,
		true,
		HORIZONTAL_ALIGNMENT_RIGHT,
		150
	)

	var stepper_y := mid_y - 3.0
	var track_y := mid_y + 5.5
	_stepper(Rect2(track_x - 36, stepper_y, 28, 28), false)
	_track(Rect2(track_x, track_y, track_w, 11), _get_quick_fraction(key), selected)
	_stepper(Rect2(track_x + track_w + 6, stepper_y, 28, 28), true)

	_field_box(
		Rect2(rect.position.x + 624, mid_y - 19.0, 164, 38),
		str(data.value),
		13,
		C_GOLD if selected else C_TEXT,
		bool(data.get("numeric", true))
	)

	var minus := Rect2(track_x - 38, stepper_y - 4.0, 32, 36)
	var plus := Rect2(track_x + track_w + 4, stepper_y - 4.0, 32, 36)
	_hit_regions.append({ "rect": minus, "kind": "quick", "path": key, "amount": -1.0 })
	_hit_regions.append({ "rect": plus, "kind": "quick", "path": key, "amount": 1.0 })
	_hit_regions.append(
		{
			"rect": Rect2(track_x, stepper_y - 4.0, track_w, 36),
			"kind": "quick_slide",
			"path": key,
			"track": Rect2(track_x, track_y, track_w, 11),
		}
	)
	_hit_regions.append({ "rect": Rect2(track_x - 6, track_y - 6.0, track_w + 12, 23), "kind": "select", "path": key })


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
		_hint(rect, "SIN TRAZADO DISPONIBLE")
		return

	var pad := 22.0
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


func _draw_stage_info_group(rect: Rect2) -> void:
	_group(rect, "INFORMACIÓN DEL TRAMO")
	var inner := _group_inner(rect)
	var info_h := 46.0
	var gap := 10.0
	var map_h := inner.size.y - (info_h * 2.0 + gap * 2.0)

	var map_rect := Rect2(inner.position.x, inner.position.y, inner.size.x, map_h)
	_draw_stage_route_preview(map_rect)

	var val_w := 204.0
	var weather_row := Rect2(inner.position.x, map_rect.end.y + gap, inner.size.x, info_h)
	_row_frame(weather_row, false, false, false)
	_text(_box(weather_row.position.x + 12, weather_row.position.y + 4, 118, weather_row.size.y - 8), "CLIMA", 9, C_DIM, true)
	var weather_txt := _get_stage_weather_text()
	var weather_size := 11
	while weather_size > 9 and maxf(
			FONT_UI_BOLD.get_string_size(weather_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, weather_size).x,
			FONT_SERIF_BOLD.get_string_size(weather_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, weather_size).x
		) > (val_w - 20.0):
		weather_size -= 1
	_field_box(
		Rect2(weather_row.end.x - val_w - 8, weather_row.position.y + 5, val_w, weather_row.size.y - 10),
		weather_txt,
		weather_size,
		C_GOLD,
		false
	)

	var dist_row := Rect2(inner.position.x, weather_row.end.y + gap, inner.size.x, info_h)
	_row_frame(dist_row, false, true, false)
	_text(_box(dist_row.position.x + 12, dist_row.position.y + 4, 128, dist_row.size.y - 8), "KILÓMETROS", 9, C_DIM, true)
	_field_box(
		Rect2(dist_row.end.x - val_w - 8, dist_row.position.y + 5, val_w, dist_row.size.y - 10),
		_get_stage_distance_text(),
		11,
		C_CHROME_TEXT,
		true
	)


func _available_compound_ids() -> Array:
	var ids := RallyTireCompound.compound_ids(
		RallyTireCompound.load_catalog()
	)
	if allowed_compound_ids.is_empty():
		return ids
	return ids.filter(
		func(cid): return cid in allowed_compound_ids
	)


func _compound_label(compound_id: String, short: bool = false) -> String:
	var info := RallyTireCompound.get_compound(RallyTireCompound.load_catalog(), compound_id)
	return str(info.get("short_label" if short else "label", compound_id))


func _all_compound(compound_id: String) -> bool:
	for corner in ["FL", "FR", "RL", "RR"]:
		if str(draft_wheel_compounds.get(corner, "")) != compound_id:
			return false
	return true


func _compound_summary() -> String:
	var first := draft_compound_id
	return _compound_label(first, true) if _all_compound(first) else "MIXTO"


func _draw_compound_group(rect: Rect2) -> void:
	_group(rect, "COMPUESTO")
	var ids := _available_compound_ids()
	var can_service := compound_change_allowed and _may_service_tires()
	var rows := maxi(1, ceili(float(ids.size()) / 2.0))
	for i in ids.size():
		var column := floori(float(i) / float(rows))
		var r := i % rows
		var option_rect := Rect2(52 + column * 365, 548 + r * 30, 340, 25)
		var cid := str(ids[i])
		_radio(option_rect, _compound_label(cid).to_upper(), _all_compound(cid))
		if can_service:
			_hit_regions.append({"rect": option_rect, "kind": "all_compound", "compound": cid})
	_hint(_box(52, 639, 730, 17), "APLICAR A LAS CUATRO RUEDAS · AJUSTE INDIVIDUAL EN AVANZADO")
	if not _may_service_tires():
		_hint(_box(52, 620, 420, 17), "BLOQUEADO EN TRAMO — INTERCAMBIA RUEDAS EN PAUSA")
	elif not compound_change_allowed:
		_hint(_box(52, 620, 340, 17), "BLOQUEADO POR EL EVENTO")


func _draw_state_group(rect: Rect2) -> void:
	_group(rect, "ESTADO DEL COCHE")
	var rows := [
		{"k": "MASA", "v": "%0.0f kg" % _vehicle_mass()},
		{"k": "COMPUESTO", "v": _compound_summary(), "numeric": false},
		{"k": "COMBUSTIBLE", "v": "%0.1f L" % (float(draft_values.get("fuel.initial_kg", 0.0)) / _fuel_density())},
		{"k": "PRESIÓN MEDIA", "v": "%0.0f kPa" % _average_pressure()},
		{"k": "TEMP. MEDIA", "v": "%0.0f °C" % _average_temperature()},
	]
	var inner := _group_inner(rect)
	var height := floorf(inner.size.y / float(rows.size()))
	var offset := (inner.size.y - height * float(rows.size())) * 0.5
	for i in rows.size():
		var y := inner.position.y + float(i) * height + offset
		_text(_box(inner.position.x, y, 150, height), str(rows[i].k), 9, C_DIM, true)
		_field_box(
			Rect2(inner.end.x - 176, y + (height - 34.0) * 0.5, 176, 34),
			str(rows[i].v),
			10,
			WB_TEXT_DATA,
			bool(rows[i].get("numeric", true))
		)


func _vehicle_mass() -> float:
	if not is_instance_valid(vehicle):
		return 0.0
	var mass_state: Dictionary = vehicle.simulation.mass_model.resolve(
		float(draft_values.get("fuel.initial_kg", 0.0))
	)
	return float(mass_state.get("vehicle_total_mass_kg", vehicle.mass))


func _average_pressure() -> float:
	if not is_instance_valid(vehicle):
		return 0.0
	var total := 0.0
	for i in 4:
		total += _wheel_pressure(i)
	return total / 4.0


func _average_temperature() -> float:
	if not is_instance_valid(vehicle):
		return 0.0
	var total := 0.0
	for i in 4:
		total += _wheel_temperature(i)
	return total / 4.0


func _wheel_state(index: int) -> Dictionary:
	if not is_instance_valid(vehicle):
		return { }
	return vehicle.get_tire_thermal_state(index)


func _wheel_pressure(index: int) -> float:
	return float(_wheel_state(index).get("pressure_kpa_gauge", 0.0))


func _wheel_temperature(index: int) -> float:
	return float(_wheel_state(index).get("tread_c", 0.0))


func _draw_tire_group(rect: Rect2) -> void:
	_group(rect, "NEUMÁTICOS")
	var inner := _group_inner(rect)
	var gap := 12.0
	var card_w := floorf((inner.size.x - gap) * 0.5)
	var card_h := floorf((inner.size.y - gap) * 0.5)
	var codes := ["FL", "FR", "RL", "RR"]
	for i in 4:
		var col := i % 2
		var row := i / 2
		var card := Rect2(
			inner.position.x + float(col) * (card_w + gap),
			inner.position.y + float(row) * (card_h + gap),
			card_w,
			card_h
		)
		draw_rect(card, C_FIELD)
		draw_rect(card, BORDER_SUBTLE, false, 1.0)
		var cid := str(draft_wheel_compounds.get(codes[i], ""))
		var details := RallyTireCompound.get_compound(RallyTireCompound.load_catalog(), cid)
		_text_with(FONT_SUBTITLE, _box(card.position.x + 10, card.position.y + 6, 60, 20), codes[i], 15, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0)
		_text(
			_box(card.position.x, card.position.y + 8, card.size.x - 10, 16),
			_compound_label(cid, true),
			8,
			Color(str(details.get("visual_tread_color", "#d9d9d9"))),
			true,
			HORIZONTAL_ALIGNMENT_RIGHT,
			card.size.x - 10
		)
		var bar := Rect2(card.position.x + 10, card.position.y + 32, card.size.x - 20, 10)
		draw_rect(bar, WB_BG_CONTENT)
		draw_rect(bar, BORDER_SUBTLE, false, 1.0)
		var life_fraction := 1.0
		var bar_color := C_BLUE
		if is_instance_valid(vehicle) and vehicle.tire_inventory != null and i < (vehicle.tire_inventory as RallyTireInventory).mounted.size():
			var inv_ref: RallyTireInventory = vehicle.tire_inventory
			var td: Dictionary = inv_ref.mounted[i]
			var st: Dictionary = td.get("state", {})
			var wear := clampf(float(st.get("wear_fraction", 0.0)), 0.0, 1.0)
			life_fraction = clampf(1.0 - wear, 0.05, 1.0)
			if inv_ref.is_carcass_destroyed(td) or inv_ref.is_punctured(td) or life_fraction < 0.25:
				bar_color = C_ROSE
			elif inv_ref.is_rim_damaged(td) or life_fraction < 0.55:
				bar_color = C_GOLD
		draw_rect(
			Rect2(bar.position + Vector2(1, 1), Vector2(maxf((bar.size.x - 2) * life_fraction, 2.0), bar.size.y - 2)),
			bar_color,
			true
		)
		_num(
			_box(card.position.x, card.position.y + 48, card.size.x - 10, 18),
			"%0.0f kPa · %0.0f °C" % [_wheel_pressure(i), _wheel_temperature(i)],
			9,
			WB_TEXT_DATA,
			HORIZONTAL_ALIGNMENT_RIGHT,
			card.size.x - 10
		)


# =============================================================================
# PÁGINA 1 — AVANZADO
# =============================================================================


func _draw_advanced_page() -> void:
	_draw_section_bar()
	match advanced_section:
		0:
			_draw_suspension_section()
		1:
			_draw_wheels_section()
		_:
			_draw_powertrain_section()


func _draw_section_bar() -> void:
	var titles := ["SUSPENSIÓN", "RUEDAS Y FRENOS", "TREN MOTRIZ"]
	var x := 36.0
	for i in titles.size():
		var label: String = titles[i]
		var width: float = maxf(150.0, FONT_BUTTON.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 50.0)
		var rect := Rect2(x, PAGE_TOP, width, 36)
		_segment_button(rect, label, i == advanced_section)
		_hit_regions.append({ "rect": rect, "kind": "section", "index": i })
		x += width + 4.0
	_hint(_box(620, PAGE_TOP, 624, 36), "TAB CAMBIA DE SECCIÓN  ·  W/S RECORRE LOS PARÁMETROS")


func _draw_suspension_section() -> void:
	var top := 200.0
	_group(Rect2(36, top, 592, 322), "TREN DELANTERO")
	_field_rows(
		Rect2(36, top, 592, 322),
		[
			{"p": "suspension.front.ride_frequency_hz", "l": "Frecuencia natural"},
			{"p": "suspension.front.resting_ratio", "l": "Altura de marcha"},
			{"p": "suspension.front.damping_ratio", "l": "Amortiguación"},
			{"p": "suspension.front.bump_damp_multiplier", "l": "Compresión"},
			{"p": "suspension.front.rebound_damp_multiplier", "l": "Rebote"},
			{"p": "suspension.front.bump_stop_multiplier", "l": "Tope de suspensión"},
		]
	)

	_group(Rect2(652, top, 592, 322), "TREN TRASERO")
	_field_rows(
		Rect2(652, top, 592, 322),
		[
			{"p": "suspension.rear.ride_frequency_hz", "l": "Frecuencia natural"},
			{"p": "suspension.rear.resting_ratio", "l": "Altura de marcha"},
			{"p": "suspension.rear.damping_ratio", "l": "Amortiguación"},
			{"p": "suspension.rear.bump_damp_multiplier", "l": "Compresión"},
			{"p": "suspension.rear.rebound_damp_multiplier", "l": "Rebote"},
			{"p": "suspension.rear.bump_stop_multiplier", "l": "Tope de suspensión"},
		]
	)

	_group(Rect2(36, 534, 592, 130), "ESTABILIZADORAS")
	_field_rows(
		Rect2(36, 534, 592, 130),
		[
			{"p": "suspension.geometry_physical.front_arb.ratio", "l": "Barra delantera"},
			{"p": "suspension.geometry_physical.rear_arb.ratio", "l": "Barra trasera"},
		]
	)

	_group(Rect2(652, 534, 592, 130), "DIRECCIÓN")
	_field_rows(
		Rect2(652, 534, 592, 130),
		[
			{"p": "steering.max_steering_angle", "l": "Ángulo máximo"},
			{"p": "steering.steering_speed", "l": "Velocidad de giro"},
		]
	)


func _draw_wheels_section() -> void:
	_group(Rect2(36, 200, 592, 230), "PRESIÓN EN FRÍO")
	_field_rows(
		Rect2(36, 200, 592, 230),
		[
			{"p": "tires.pressure.cold_kpa_gauge.FL", "l": "Delantera izquierda"},
			{"p": "tires.pressure.cold_kpa_gauge.FR", "l": "Delantera derecha"},
			{"p": "tires.pressure.cold_kpa_gauge.RL", "l": "Trasera izquierda"},
			{"p": "tires.pressure.cold_kpa_gauge.RR", "l": "Trasera derecha"},
		]
	)

	_group(Rect2(652, 200, 592, 230), "GEOMETRÍA (POR EJE)")
	_field_rows(
		Rect2(652, 200, 592, 230),
		[
			{"p": "suspension.front.camber", "l": "Caída delantera"},
			{"p": "suspension.rear.camber", "l": "Caída trasera"},
			{"p": "suspension.front.toe", "l": "Convergencia delantera"},
			{"p": "suspension.rear.toe", "l": "Convergencia trasera"},
		]
	)

	var compound_panel := Rect2(36, 442, 592, 230)
	_group(compound_panel, "COMPUESTO POR RUEDA")
	var codes := ["FL", "FR", "RL", "RR"]
	var inner := _group_inner(compound_panel)
	var row_h := floorf(inner.size.y / 4.0)
	var can_service := compound_change_allowed and _may_service_tires()
	for i in 4:
		var rect := Rect2(inner.position.x, inner.position.y + float(i) * row_h, inner.size.x, row_h)
		var cid := str(draft_wheel_compounds.get(codes[i], ""))
		_row_frame(rect, false, i == 3, _mouse_over(rect))
		_text(_box(rect.position.x + 12, rect.position.y, 90, row_h), codes[i], 13, C_TEXT, true)
		_hint(_box(rect.position.x + 52, rect.position.y, 180, row_h), _compound_label(cid))
		_toggle(
			Rect2(rect.end.x - 132, rect.position.y + (row_h - 30.0) * 0.5, 120, 30),
			"CAMBIAR" if can_service else "BLOQUEADO", can_service
		)
		if can_service:
			_hit_regions.append({ "rect": rect, "kind": "compound", "corner": codes[i] })

	_group(Rect2(652, 442, 592, 230), "AERODINÁMICA Y FRENOS")
	_field_rows(
		Rect2(652, 442, 592, 230),
		[
			{"p": "aero.model.front_wing.incidence_deg", "l": "Ala delantera"},
			{"p": "aero.model.rear_wing.incidence_deg", "l": "Ala trasera"},
			{"p": "brakes.front_brake_bias", "l": "Reparto de frenada"},
			{"p": "brakes.max_brake_torque", "l": "Par máximo de freno"},
		]
	)


func _draw_powertrain_section() -> void:
	_group(Rect2(36, 200, 592, 370), "MOTOR Y TRANSMISIÓN")
	_field_rows(
		Rect2(36, 200, 592, 370),
		[
			{"p": "powertrain.max_rpm", "l": "Régimen máximo"},
			{"p": "powertrain.final_drive", "l": "Relación final"},
			{"p": "powertrain.reverse_ratio", "l": "Marcha atrás"},
			{"p": "powertrain.gear_ratios.0", "l": "1ª marcha"},
			{"p": "powertrain.gear_ratios.1", "l": "2ª marcha"},
			{"p": "powertrain.gear_ratios.2", "l": "3ª marcha"},
			{"p": "powertrain.gear_ratios.3", "l": "4ª marcha"},
		]
	)

	if is_instance_valid(vehicle) and vehicle.simulation.is_historic_differential():
		_group(Rect2(652, 200, 592, 240), "DIFERENCIAL — TIPO / CONFIGURACIÓN")
		_draw_differential_preset_row(Rect2(652, 200, 592, 240))

		_group(Rect2(652, 452, 592, 118), "DIRECCIÓN")
		_field_rows(
			Rect2(652, 452, 592, 118),
			[
				{"p": "steering.max_steering_angle", "l": "Ángulo máximo"},
				{"p": "steering.steering_speed", "l": "Velocidad de giro"},
			]
		)
	else:
		# Modo modern: LSD autoblocante moderno con los 4 números libres.
		_group(Rect2(652, 200, 592, 322), "DIFERENCIAL Y DIRECCIÓN")
		_field_rows(
			Rect2(652, 200, 592, 322),
			[
				{"p": "powertrain.differential.preload_nm", "l": "Precarga"},
				{"p": "powertrain.differential.power_ramp_angle_deg", "l": "Rampa de aceleración"},
				{"p": "powertrain.differential.coast_ramp_angle_deg", "l": "Rampa de retención"},
				{"p": "powertrain.differential.clutches", "l": "Paquetes de discos"},
				{"p": "steering.max_steering_angle", "l": "Ángulo máximo"},
				{"p": "steering.steering_speed", "l": "Velocidad de giro"},
			]
		)

	_draw_gear_chart(Rect2(36, 582, 1208, 92))


func _draw_differential_preset_row(group_rect: Rect2) -> void:
	var options := _preset_options()
	var selected := selected_field_path == DIFFERENTIAL_PRESET_PATH
	var current_id := _draft_preset_id()
	var current := RallyDifferentialCatalog.get_preset(_garage_profile_id(), current_id)
	var inner := _group_inner(group_rect)
	var row := Rect2(inner.position.x, inner.position.y, inner.size.x, 44)
	_row_frame(row, selected, false, _mouse_over(row))
	_hit_regions.append({"rect": row, "kind": "select", "path": DIFFERENTIAL_PRESET_PATH})
	_text_with(FONT_UI, _box(row.position.x + 12, row.position.y, 150, row.size.y), "Configuración", 10, C_TEXT if selected else C_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0)
	var minus := Rect2(row.position.x + 168, row.position.y + (row.size.y - 26.0) * 0.5, 26, 26)
	var plus := Rect2(row.end.x - 36, row.position.y + (row.size.y - 26.0) * 0.5, 26, 26)
	_stepper(minus, false)
	_stepper(plus, true)
	_hit_regions.append({"rect": minus, "kind": "preset_adjust", "amount": -1.0})
	_hit_regions.append({"rect": plus, "kind": "preset_adjust", "amount": 1.0})
	var name_rect := Rect2(minus.end.x + 8, row.position.y + (row.size.y - 32.0) * 0.5, plus.position.x - minus.end.x - 16, 32)
	if options.is_empty():
		_field_box(name_rect, "SIN CATÁLOGO", 10, C_DIM, false)
		_hint(_box(inner.position.x + 12, row.end.y + 6, inner.size.x - 24, 18), "Legado temporal: sin presets históricos.")
		return
	var label := str(current.get("label", current_id)) if not current.is_empty() else current_id
	_field_box(name_rect, label, 10, C_GOLD if selected else C_TEXT, false)
	var y := row.end.y + 8.0
	if current.is_empty():
		_hint(_box(inner.position.x + 12, y, inner.size.x - 24, 18), "Preset no resuelto.")
		return
	if not bool(current.get("enabled", false)):
		_hint(_box(inner.position.x + 12, y, inner.size.x - 24, 18), "Pendiente de calibración: no seleccionable.")
		return
	var bench: Dictionary = current.get("bench_preload_nm", {})
	var reported: Dictionary = current.get("reported_nominal_lock_pct", {})
	var discs: Variant = current.get("physical_disc_count", null)
	var discs_txt := str(int(discs)) if discs is int or discs is float else "—"
	_text(_box(inner.position.x + 12, y, inner.size.x - 24, 16), str(current.get("supplier_or_family", "")) + " · " + str(current.get("model_reference", "")), 9, C_DIM, false)
	y += 16.0
	_text(_box(inner.position.x + 12, y, inner.size.x - 24, 16), "Rampas %d°/%d° · Superficies %d · Discos %s" % [int((current.get("ramp_deg", {}) as Dictionary).get("power", 0)), int((current.get("ramp_deg", {}) as Dictionary).get("coast", 0)), int(current.get("active_friction_surfaces", 0)), discs_txt], 9, C_TEXT, false)
	y += 16.0
	_text(_box(inner.position.x + 12, y, inner.size.x - 24, 16), "Banco %.0f–%.0f Nm · Ficha %d%%/%d%% (no bloqueo dinámico)" % [float(bench.get("min", 0.0)), float(bench.get("max", 0.0)), int(reported.get("power", 0)), int(reported.get("coast", 0))], 9, C_DIM, false)
	y += 18.0
	var names: Array[String] = []
	for p in options:
		var n := str(p.get("label", p.get("id", "")))
		if not bool(p.get("enabled", false)):
			n += " (pendiente)"
		if str(p.get("id", "")) == current_id:
			n = "«" + n + "»"
		names.append(n)
	_hint(_box(inner.position.x + 12, y, inner.size.x - 24, 18), " · ".join(names))


func _draw_gear_chart(rect: Rect2) -> void:
	_group(rect, "ESCALONADO DE MARCHAS")
	var inner := Rect2(rect.position.x + 14, rect.position.y + 20, rect.size.x - 28, rect.size.y - 34)
	var gears: Array = []
	if is_instance_valid(vehicle):
		var ratios: Array = vehicle.simulation.powertrain_model.gear_ratios
		for index in ratios.size():
			gears.append({ "label": str(index + 1) + "ª", "value": float(ratios[index]) })
		gears.append(
			{ "label": "R", "value": absf(float(vehicle.simulation.powertrain_model.reverse_ratio)) }
		)
	if gears.is_empty():
		_hint(_box(inner.position.x, inner.position.y, inner.size.x, inner.size.y), "SIN DATOS DE CAJA")
		return
	var gap := 10.0
	var box_w := floorf((inner.size.x - gap * float(gears.size() - 1)) / float(gears.size()))
	var max_value := 0.001
	for gear in gears:
		max_value = maxf(max_value, float(gear.value))
	for i in gears.size():
		var box := Rect2(inner.position.x + float(i) * (box_w + gap), inner.position.y, box_w, inner.size.y)
		draw_rect(box, C_FACE_LO)
		_sunken(box)
		_text_with(FONT_SUBTITLE, _box(box.position.x + 8, box.position.y + 4, 40, 18), str(gears[i].label), 13, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0)
		_num(
			_box(box.position.x, box.position.y + 4, box.size.x - 8, 18),
			"%0.2f" % float(gears[i].value),
			9,
			C_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT,
			box.size.x - 8
		)
		var bar := Rect2(box.position.x + 8, box.end.y - 16, box.size.x - 16, 8)
		draw_rect(bar, C_FIELD)
		_sunken(bar)
		var ratio_fill := Rect2(
			bar.position + Vector2(1, 1),
			Vector2((bar.size.x - 2) * (float(gears[i].value) / max_value), bar.size.y - 2)
		)
		draw_rect(ratio_fill, Color(C_GOLD, 0.42), true)
		draw_rect(ratio_fill, Color(C_GOLD, 0.85), false)


# =============================================================================
# PÁGINA 2 — ESTRATEGIA
# =============================================================================


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


func _draw_pool_slot_card(rect: Rect2, title: String, subtitle: String, status_tag: String, status_color: Color, focused: bool, selected_card: bool, interactive: bool) -> void:
	var fill := C_FACE_HI if (selected_card or _mouse_over(rect)) else C_FACE_LO
	draw_rect(rect, fill)
	if selected_card:
		draw_rect(rect, C_GOLD, false, 2.0)
	elif focused:
		draw_rect(rect, BORDER_FOCUS, false, 2.0)
	else:
		_sunken(rect)
	var text_col := C_TEXT if interactive else C_DIM
	_text(_box(rect.position.x + 8, rect.position.y + 4, rect.size.x - 102, 18), title, 9, text_col, true)
	_text(
		_box(rect.position.x + 8, rect.position.y + 22, rect.size.x - 16, 16),
		subtitle,
		8,
		C_DIM,
		false
	)
	_text(
		_box(rect.position.x, rect.position.y + 4, rect.size.x - 8, 18),
		status_tag,
		8,
		status_color,
		status_tag != "OK",
		HORIZONTAL_ALIGNMENT_RIGHT,
		rect.size.x - 8
	)


func _draw_strategy_page() -> void:
	var _is_pool := _is_pool_mode()
	var can_service := compound_change_allowed and _may_service_tires()

	if _is_pool:
		_group(Rect2(36, PAGE_TOP, 596, 108), "COMBUSTIBLE")
		_field_rows(Rect2(36, PAGE_TOP, 596, 70), [{ "p": "fuel.initial_kg", "l": "Combustible inicial" }])
	else:
		_group(Rect2(36, PAGE_TOP, 596, 164), "COMBUSTIBLE")
		_field_rows(Rect2(36, PAGE_TOP, 596, 92), [{ "p": "fuel.initial_kg", "l": "Combustible inicial" }])

	var capacity := 45.0
	if is_instance_valid(vehicle):
		capacity = maxf(float(vehicle.simulation.mass_model.fuel_capacity_kg), 0.001)
	var current := float(draft_values.get("fuel.initial_kg", 0.0))
	var fraction := clampf(current / capacity, 0.0, 1.0)
	var dep_y := 216.0 if _is_pool else 246.0
	var grv_y := 236.0 if _is_pool else 270.0
	_text(_box(50, dep_y, 200, 18), "DEPÓSITO", 9, C_DIM, true)
	_num(
		_box(50, dep_y, 568, 18),
		"%0.1f / %0.1f L" % [current / _fuel_density(), capacity / _fuel_density()],
		10,
		C_TEXT,
		HORIZONTAL_ALIGNMENT_RIGHT,
		568
	)
	var groove := Rect2(50, grv_y, 568, 16 if _is_pool else 22)
	draw_rect(groove, C_FIELD)
	_sunken(groove)
	var fill := Rect2(
		groove.position + Vector2(1, 1),
		Vector2(maxf((groove.size.x - 2) * fraction, 1.0), groove.size.y - 2)
	)
	draw_rect(fill, Color(C_BLUE_DEEP, 0.95))
	draw_rect(
		Rect2(fill.position, Vector2(fill.size.x, maxf(floorf(fill.size.y * 0.5), 1.0))),
		Color(C_BLUE, 0.45),
		true
	)
	for segment in range(1, 10):
		var sx := groove.position.x + groove.size.x * (float(segment) / 10.0)
		draw_rect(Rect2(sx, groove.position.y + 1, 1, groove.size.y - 2), Color(C_DARK, 0.55))

	if _is_pool:
		_group(Rect2(36, 272, 596, 58), "METEOROLOGÍA")
		var memo_pool := Rect2(50, 295, 568, 28)
		draw_rect(memo_pool, C_FIELD)
		_sunken(memo_pool)
		if event_forecast.is_empty():
			_hint(_box(memo_pool.position.x + 10, memo_pool.position.y + 4, memo_pool.size.x - 20, 20), "SIN PREVISIÓN PARA ESTE EVENTO")
		else:
			var f_lines := _wrap_text(event_forecast, 2, 68)
			for i in f_lines.size():
				var ly := memo_pool.position.y + (5.0 if f_lines.size() == 1 else 2.0 + float(i) * 12.0)
				_text(
					_box(memo_pool.position.x + 10, ly, memo_pool.size.x - 20, 14),
					f_lines[i],
					9,
					C_TEXT if i == 0 else C_DIM
				)

		var inv_ref: RallyTireInventory = vehicle.tire_inventory
		var inv_count: int = inv_ref.total_count()
		_group(Rect2(36, 336, 596, 338), "MALETERO Y PARQUE 3D (%d/10)" % inv_count)
		var drag_tid := _strategy_board._active_drag_tire_id if _strategy_board != null else -1
		var mode_note := "ARRASTRA RUEDAS 3D O PULSA ORIGEN -> DESTINO"
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
			_box(50, 356, 568, 15),
			"MALETERO %d/%d · PARQUE %d  ·  %s" % [draft_spare_ids.size(), _tire_capacity(), draft_stock_ids.size(), mode_note],
			8,
			note_color,
			true
		)

		var telemetry := Rect2(648, PAGE_TOP, 596, 518)
		_group(telemetry, "MONTAJE 3D EN EL COCHE")
		_text(
			_box(662, 177, 568, 15),
			"ARRASTRA RUEDAS 3D ENTRE COCHE, MALETERO Y PARQUE  ·  CLIC O D-PAD SELECCIONA",
			8,
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
			_box(662, 653, 568, 16),
			"PRESIÓN MEDIA %0.0f kPa  ·  DESLIZA SOBRE MONTAJE PARA INTERCAMBIAR POSICIONES" % (p_sum * 0.25),
			8,
			C_DIM,
			true,
			HORIZONTAL_ALIGNMENT_CENTER,
			568
		)
		return

	_group(Rect2(36, 332, 596, 156), "INVENTARIO DE NEUMÁTICOS")
	var service_rect := Rect2(50, 356, 568, 44)
	_row_frame(service_rect, selected_field_path == "service", false, _mouse_over(service_rect))
	_text(_box(service_rect.position.x + 12, service_rect.position.y, 300, 44), "NEUMÁTICOS NUEVOS", 10, C_TEXT)
	_toggle(
		Rect2(service_rect.end.x - 132, service_rect.position.y + 7, 120, 30),
		"SÍ" if new_tires_service else "NO",
		new_tires_service
	)
	if _may_service_tires():
		_hit_regions.append({ "rect": service_rect, "kind": "service" })

	var spare_rect := Rect2(50, 408, 568, 44)
	_row_frame(spare_rect, selected_field_path == "spares", true, _mouse_over(spare_rect))
	_text(_box(spare_rect.position.x + 12, spare_rect.position.y, 300, 44), "RUEDAS DE REPUESTO", 10, C_TEXT)
	for s in 3:
		var button := Rect2(spare_rect.end.x - 140 + float(s) * 46, spare_rect.position.y + 8, 42, 28)
		_toggle(button, str(s), draft_spare_wheels == s)
		if _may_service_tires():
			_hit_regions.append({ "rect": button, "kind": "spares", "delta": s - draft_spare_wheels })

	_group(Rect2(36, 500, 596, 174), "METEOROLOGÍA")
	_text(_box(50, 516, 568, 18), "PREVISIÓN DEL EVENTO", 9, C_DIM, true)
	var memo := Rect2(50, 538, 568, 122)
	draw_rect(memo, C_FIELD)
	_sunken(memo)
	if event_forecast.is_empty():
		_hint(_box(memo.position.x + 10, memo.position.y + 10, memo.size.x - 20, 18), "SIN PREVISIÓN PARA ESTE EVENTO")
	else:
		var lines := _wrap_text(event_forecast, 4, 68)
		for i in lines.size():
			_text(
				_box(memo.position.x + 10, memo.position.y + 10 + float(i) * 20, memo.size.x - 20, 18),
				lines[i],
				9,
				C_TEXT if i == 0 else C_DIM
			)

	var telemetry := Rect2(648, PAGE_TOP, 596, 518)
	_group(telemetry, "TELEMETRÍA DE NEUMÁTICOS")
	var inner := _group_inner(telemetry)
	var gap := 12.0
	var card_w := floorf((inner.size.x - gap) * 0.5)
	var card_h := floorf((inner.size.y - gap) * 0.5)
	var codes := ["FL", "FR", "RL", "RR"]
	var names := ["DEL. IZQUIERDA", "DEL. DERECHA", "TRAS. IZQUIERDA", "TRAS. DERECHA"]
	for i in 4:
		var col := i % 2
		var row := i / 2
		var card := Rect2(
			inner.position.x + float(col) * (card_w + gap),
			inner.position.y + float(row) * (card_h + gap),
			card_w,
			card_h
		)
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
		_text(
			_box(card.position.x, card.position.y + 10, card.size.x - 12, 18),
			"%s · %s" % [names[i], status_tag],
			8,
			status_color if status_tag != "OK" else C_DIM,
			status_tag != "OK",
			HORIZONTAL_ALIGNMENT_RIGHT,
			card.size.x - 12
		)
		_text(_box(card.position.x + 12, card.position.y + 42, 220, 14), "PRESIÓN · DESGASTE %0.0f%%" % wear_pct, 8, C_DIM, true)
		_field_box(
			Rect2(card.position.x + 12, card.position.y + 56, card.size.x - 24, 30),
			"%0.0f kPa" % _wheel_pressure(i),
			10,
			C_TEXT
		)
		_text(_box(card.position.x + 12, card.position.y + 94, 160, 14), "TEMPERATURA", 8, C_DIM, true)
		_field_box(
			Rect2(card.position.x + 12, card.position.y + 108, card.size.x - 24, 30),
			"%0.0f °C" % _wheel_temperature(i),
			10,
			C_BLUE
		)
		var bar := Rect2(card.position.x + 12, card.position.y + 152, card.size.x - 24, 10)
		var temp_c := _wheel_temperature(i)
		var thermal := clampf((temp_c - 20.0) / 90.0, 0.04, 1.0)
		var thermal_color := C_ROSE if temp_c >= 95.0 else (C_GOLD if temp_c >= 75.0 else Color(C_BLUE, 0.92))
		draw_rect(bar, C_FIELD)
		_sunken(bar)
		draw_rect(
			Rect2(bar.position + Vector2(1, 1), Vector2(maxf((bar.size.x - 2) * thermal, 2.0), bar.size.y - 2)),
			thermal_color,
			true
		)
		var toggle := Rect2(card.position.x + 12, card.end.y - 44, card.size.x - 24, 32)
		var btn_label := _compound_label(cid, true)
		_toggle(toggle, btn_label, can_service)
		if can_service:
			_hit_regions.append({ "rect": toggle, "kind": "compound", "corner": codes[i] })


# =============================================================================
# PÁGINA 3 — PERFILES
# =============================================================================


func _draw_setups_page() -> void:
	var list_panel := Rect2(36, PAGE_TOP, 844, 518)
	_group(list_panel, "PERFILES GUARDADOS")
	var inner := _group_inner(list_panel)
	draw_rect(inner, C_FIELD)
	_sunken(inner)
	var row_h := 52.0
	var visible_rows := _setup_visible_rows()
	for slot in visible_rows:
		var index := setup_scroll_offset + slot
		if index >= setup_rows.size():
			break
		var row: Dictionary = setup_rows[index]
		var rect := Rect2(inner.position.x, inner.position.y + float(slot) * row_h, inner.size.x, row_h)
		var selected := index == selected_setup_index
		_row_frame(rect, selected, false, _mouse_over(rect), C_FIELD)
		if int(row.get("id", -1)) == active_setup_id:
			draw_rect(Rect2(rect.position.x + 6, rect.position.y + 10, 6, row_h - 20), C_BLUE)
		_text(
			_box(rect.position.x + 24, rect.position.y, rect.size.x - 220, row_h),
			str(row.get("name", "Reglaje")),
			11,
			C_TEXT,
			selected
		)
		_num(
			_box(rect.position.x, rect.position.y, rect.size.x - 16, row_h),
			_short_timestamp(str(row.get("modified_at", ""))),
			9,
			C_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT,
			rect.size.x - 16
		)
		_hit_regions.append({ "rect": rect, "kind": "setup_row", "index": index })

	if setup_rows.is_empty():
		_text(
			_box(inner.position.x, inner.position.y, inner.size.x, inner.size.y),
			"SIN PERFILES GUARDADOS",
			11,
			C_DIM,
			false,
			HORIZONTAL_ALIGNMENT_CENTER
		)

	var actions := Rect2(892, PAGE_TOP, 352, 518)
	_group(actions, "ACCIONES")
	_classic_button(Rect2(910, 190, 316, 48), "NUEVO PERFIL", "new")
	_classic_button(Rect2(910, 250, 316, 48), "SOBRESCRIBIR", "save")
	_classic_button(Rect2(910, 310, 316, 48), "CARGAR", "load")
	_classic_button(Rect2(910, 370, 316, 48), "ELIMINAR", "delete")

	var detail := Rect2(910, 440, 316, 214)
	draw_rect(detail, C_FIELD)
	_sunken(detail)
	_text_with(FONT_SUBTITLE, _box(detail.position.x + 12, detail.position.y + 10, detail.size.x - 24, 18), "DETALLE", 11, C_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0)
	_text(_box(detail.position.x + 12, detail.position.y + 32, detail.size.x - 24, 18), "CIRCUITO", 8, Color(C_DIM, 0.75))
	_text(_box(detail.position.x + 12, detail.position.y + 48, detail.size.x - 24, 18), circuit_name.to_upper(), 10, C_TEXT)
	_text(_box(detail.position.x + 12, detail.position.y + 74, detail.size.x - 24, 18), "COCHE", 8, Color(C_DIM, 0.75))
	_text(_box(detail.position.x + 12, detail.position.y + 90, detail.size.x - 24, 18), _get_vehicle_display_name(), 10, C_TEXT)
	_text(_box(detail.position.x + 12, detail.position.y + 116, detail.size.x - 24, 18), "REGLAJE ACTIVO", 8, Color(C_DIM, 0.75))
	_text(_box(detail.position.x + 12, detail.position.y + 132, detail.size.x - 24, 18), active_setup_name.to_upper(), 10, C_BLUE, true)
	_text(
		_box(detail.position.x + 12, detail.position.y + 164, detail.size.x - 24, 18),
		"ENTER CARGA · SUPR BORRA",
		8,
		Color(C_DIM, 0.7)
	)


# =============================================================================
# MODAL
# =============================================================================


func _draw_modal() -> void:
	draw_rect(Rect2(Vector2.ZERO, LOGICAL_SIZE), RallyUITheme.BG_OVERLAY)
	var rect := Rect2(390, 262, 500, 250)
	_glass_window(rect, RallyUITheme.CORNER_RADIUS)
	_text_title(
		_box(rect.position.x + 18, rect.position.y + 8, rect.size.x - 36, 32),
		"PERFIL" if modal_mode == "name" else "CONFIRMACIÓN",
		16,
		C_GOLD
	)
	draw_line(
		Vector2(rect.position.x + 1, rect.position.y + 44),
		Vector2(rect.end.x - 1, rect.position.y + 44),
		BORDER_SUBTLE,
		1.0
	)

	var body := Rect2(rect.position.x + 18, rect.position.y + 58, rect.size.x - 36, 118)
	draw_rect(body, C_FACE)
	_bevel(body, false, 2)

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
		_text(
			_box(body.position.x + 12, body.position.y + 30, body.size.x - 24, 24),
			"¿ELIMINAR «" + selected_name.to_upper() + "»?",
			11,
			C_TEXT,
			true
		)
		_hint(_box(body.position.x + 12, body.position.y + 74, body.size.x - 24, 18), "ESTA ACCIÓN NO SE PUEDE DESHACER")
	else:
		_text(
			_box(body.position.x + 12, body.position.y + 30, body.size.x - 24, 24),
			"¿DESCARTAR CAMBIOS SIN APLICAR?",
			11,
			C_TEXT,
			true
		)
		_hint(_box(body.position.x + 12, body.position.y + 74, body.size.x - 24, 18), "SE PERDERÁN LOS AJUSTES DE ESTA SESIÓN")

	_classic_button(Rect2(rect.end.x - 300, rect.end.y - 62, 130, 40), "CANCELAR", "cancel", true)
	_gold_button(Rect2(rect.end.x - 158, rect.end.y - 62, 140, 40), "ACEPTAR", "accept", true)


# =============================================================================
# PRIMITIVAS WINDOWS 98
# =============================================================================


func _group(rect: Rect2, caption: String) -> void:
	draw_style_box(RallyUITheme.make_flat_panel(C_FACE_LO, BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS), rect)
	var cap_w := _title_width(caption, 13) + 14.0
	_text_with(FONT_SUBTITLE, _box(rect.position.x + 14, rect.position.y + 4, cap_w, 14), caption, 13, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0)
	draw_line(
		Vector2(rect.position.x + 14, rect.position.y + 19),
		Vector2(rect.end.x - 14, rect.position.y + 19),
		BORDER_SUBTLE,
		1.0
	)


func _group_inner(rect: Rect2) -> Rect2:
	return Rect2(rect.position.x + 14, rect.position.y + 20, rect.size.x - 28, rect.size.y - 34)


func _row_frame(
	rect: Rect2, selected: bool, last: bool, hovered: bool, base: Color = C_FACE_LO
) -> void:
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


func _bevel(rect: Rect2, _raised: bool, _thick: int = 2) -> void:
	draw_rect(rect, BORDER_SUBTLE, false, 1.0)


func _sunken(rect: Rect2) -> void:
	draw_rect(rect, BORDER_SUBTLE, false, 1.0)


func _field_box(rect: Rect2, text: String, size: int, color: Color, numeric: bool = true) -> void:
	draw_style_box(RallyUITheme.make_flat_panel(C_FIELD, BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS), rect)
	var inner := _box(rect.position.x + 6, rect.position.y, rect.size.x - 12, rect.size.y)
	if numeric:
		_num(inner, text, size, color, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 12)
	else:
		_text(inner, text, size, color, true, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 12)


func _stepper(rect: Rect2, plus: bool) -> void:
	var hovered := _mouse_over(rect)
	draw_style_box(RallyUITheme.make_flat_panel(C_FACE_HI if hovered else WB_SLIDER_STEPPER, RallyUITheme.BORDER_HOVER if hovered else BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS), rect)
	var cx: float = round(rect.get_center().x)
	var cy: float = round(rect.get_center().y)
	var glyph: Color = C_TEXT if hovered else C_DIM
	draw_rect(Rect2(cx - 4, cy - 1, 9, 2), glyph)
	if plus:
		draw_rect(Rect2(cx - 1, cy - 4, 2, 9), glyph)


func _track(rect: Rect2, fraction: float, selected: bool) -> void:
	draw_rect(rect, C_FIELD)
	draw_rect(rect, BORDER_SUBTLE, false, 1.0)
	var inner := rect.grow(-2.0)
	var fill_w: float = maxf(inner.size.x * clampf(fraction, 0.0, 1.0), 2.0)
	draw_rect(Rect2(inner.position, Vector2(fill_w, inner.size.y)), C_BLUE)
	for i in 4:
		var tx := inner.position.x + inner.size.x * (0.2 + 0.2 * float(i))
		draw_rect(Rect2(tx, inner.position.y, 1, inner.size.y), Color(1.0, 1.0, 1.0, 0.12))

	var thumb := Rect2(inner.position.x + fill_w - 6.0, rect.position.y - 5.0, 12.0, rect.size.y + 10.0)
	draw_rect(thumb, WB_SLIDER_THUMB)
	draw_rect(thumb, Color("#000000"), false, 1.0)
	if selected:
		draw_rect(Rect2(thumb.position.x, thumb.position.y, thumb.size.x, 3), C_GOLD)


func _radio(rect: Rect2, label: String, on: bool) -> void:
	var radius := 6.0
	var center := Vector2(rect.position.x + radius + 1.0, rect.position.y + rect.size.y * 0.5)
	draw_circle(center, radius, C_FIELD)
	draw_arc(center, radius, 0.0, TAU, 24, C_GOLD if on else BORDER_SUBTLE, 1.2)
	if on:
		draw_circle(center, radius - 3.0, C_GOLD)
	_text(
		_box(rect.position.x + 18, rect.position.y, rect.size.x - 18, rect.size.y),
		label,
		11,
		C_TEXT if on else C_DIM,
		on
	)


func _toggle(rect: Rect2, label: String, on: bool) -> void:
	var fill := C_BLUE_DEEP if on else C_FIELD
	draw_style_box(RallyUITheme.make_flat_panel(fill, C_GOLD if on else BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS), rect)
	_text_with(
		FONT_BUTTON,
		_box(rect.position.x, rect.position.y, rect.size.x, rect.size.y),
		label,
		13,
		C_GOLD_HI if on else C_DIM,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1.0
	)


func _segment_button(rect: Rect2, label: String, active: bool) -> void:
	var fill := WB_BG_TAB_ACTIVE if active else RallyUITheme.BG_SHELL
	if not active and _mouse_over(rect):
		fill = WB_BG_CARD_HOVER
	draw_style_box(RallyUITheme.make_flat_panel(fill, C_GOLD if active else BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS), rect)
	if active:
		draw_rect(Rect2(rect.position.x + 2, rect.end.y - 2, rect.size.x - 4, 2), C_GOLD)
	_text_with(
		FONT_BUTTON,
		_box(rect.position.x, rect.position.y, rect.size.x, rect.size.y),
		label,
		13,
		C_TEXT if active else C_DIM,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1.0
	)


func _classic_button(rect: Rect2, label: String, action: String, modal: bool = false) -> void:
	var hovered := _mouse_over(rect)
	var fill := C_FACE_HI if hovered else C_FACE_LO
	draw_style_box(RallyUITheme.make_flat_panel(fill, BORDER_FOCUS if hovered else RallyUITheme.BORDER_CARD, 1, RallyUITheme.CORNER_RADIUS), rect)
	_text_with(
		FONT_BUTTON,
		_box(rect.position.x, rect.position.y - 1, rect.size.x, rect.size.y),
		label,
		15,
		C_TEXT,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1.0
	)
	_hit_regions.append({ "rect": rect, "kind": "button", "action": action, "modal": modal })


func _hint(rect: Rect2, text: String) -> void:
	_text(rect, text, 8, Color(C_DIM, 0.9))


# =============================================================================
# FILAS DE PARÁMETRO
# =============================================================================


func _field_rows(group_rect: Rect2, rows: Array) -> void:
	var inner := _group_inner(group_rect)
	var height := floorf(inner.size.y / float(rows.size()))
	var offset := (inner.size.y - height * float(rows.size())) * 0.5
	for i in rows.size():
		_field_row(
			Rect2(inner.position.x, inner.position.y + float(i) * height + offset, inner.size.x, height),
			str(rows[i].p),
			str(rows[i].l),
			i == rows.size() - 1
		)


func _field_row(rect: Rect2, path: String, label: String, last: bool) -> void:
	var field := RallySetupCatalog.field_for_path(path)
	if field.is_empty():
		return
	var selected := selected_field_path == path
	_row_frame(rect, selected, last, _mouse_over(rect))
	# La fila se registra primero: los controles de dentro ganan el clic.
	_hit_regions.append({ "rect": rect, "kind": "select", "path": path })

	_text_with(
		FONT_UI,
		_box(rect.position.x + 12, rect.position.y, 236, rect.size.y),
		label,
		10,
		C_TEXT if selected else C_DIM,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0
	)

	var field_rect := Rect2(rect.end.x - 96, rect.position.y + (rect.size.y - 32.0) * 0.5, 94, 32)
	var minus := Rect2(rect.position.x + 240, rect.position.y + (rect.size.y - 26.0) * 0.5, 26, 26)
	var plus := Rect2(field_rect.position.x - 36, rect.position.y + (rect.size.y - 26.0) * 0.5, 26, 26)
	var track := Rect2(
		minus.end.x + 10,
		rect.position.y + (rect.size.y - 11.0) * 0.5,
		plus.position.x - minus.end.x - 20,
		11
	)

	_field_box(field_rect, _format_field(field, path), 10, C_GOLD if selected else C_TEXT)
	_stepper(minus, false)
	_track(track, _field_fraction(field, path), selected)
	_stepper(plus, true)

	_hit_regions.append({ "rect": minus, "kind": "adjust", "path": path, "amount": -1.0 })
	_hit_regions.append({ "rect": plus, "kind": "adjust", "path": path, "amount": 1.0 })
	_hit_regions.append({ "rect": track.grow(6.0), "kind": "slide", "path": path, "track": track })


func _format_field(field: Dictionary, path: String) -> String:
	if path == "fuel.initial_kg":
		return "%.1f L" % (float(draft_values.get(path, 0.0)) / _fuel_density())
	var scaled := float(draft_values.get(path, 0.0)) * float(field.scale)
	var pattern := "%." + str(int(field.digits)) + "f"
	return (pattern % scaled) + str(field.suffix)


func _field_fraction(field: Dictionary, path: String) -> float:
	var span := maxf(float(field.max) - float(field.min), 0.0001)
	return clampf((float(draft_values.get(path, 0.0)) - float(field.min)) / span, 0.0, 1.0)


# =============================================================================
# PRIMITIVAS PLANAS MOTORSPORT (2 PX CHAMFER)
# =============================================================================


func _glass_window(rect: Rect2, radius: int) -> void:
	_glass_box(rect, mini(radius, RallyUITheme.CORNER_RADIUS), BG_SURFACE, RallyUITheme.BORDER_CARD, 0.0)


func _glass_box(rect: Rect2, radius: int, fill: Color, rim: Color, _gloss_alpha: float) -> void:
	draw_style_box(RallyUITheme.make_flat_panel(fill, rim, 1, mini(radius, RallyUITheme.CORNER_RADIUS)), rect)


func _gloss(_rect: Rect2, _radius: int, _height: float, _alpha: float) -> void:
	pass


func _glow(rect: Rect2, _radius: int, color: Color) -> void:
	draw_rect(rect.grow(1.5), Color(color.r, color.g, color.b, clampf(color.a, 0.35, 1.0)), false, 1.5)


func _chrome_button(rect: Rect2, label: String, action: String) -> void:
	var hovered := _mouse_over(rect)
	var fill := WB_BG_CARD_HOVER if hovered else WB_BG_CARD
	draw_style_box(RallyUITheme.make_flat_panel(fill, BORDER_FOCUS if hovered else RallyUITheme.BORDER_CARD, 1, RallyUITheme.CORNER_RADIUS), rect)
	_text_with(
		FONT_BUTTON,
		_box(rect.position.x, rect.position.y, rect.size.x, rect.size.y),
		label,
		15,
		C_CHROME_TEXT,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1.0
	)
	_hit_regions.append({ "rect": rect, "kind": "button", "action": action })


func _gold_button(rect: Rect2, label: String, action: String, modal: bool = false) -> void:
	var hovered := _mouse_over(rect)
	var fill := Color("#f2bb54") if hovered else ACCENT_RALLY
	draw_style_box(RallyUITheme.make_flat_panel(fill, Color("#f6c96e"), 1, RallyUITheme.CORNER_RADIUS), rect)
	_text_with(
		FONT_BUTTON,
		_box(rect.position.x, rect.position.y - 1, rect.size.x, rect.size.y),
		label,
		15,
		BG_BASE,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1.0
	)
	_hit_regions.append({ "rect": rect, "kind": "button", "action": action, "modal": modal })


func _focus_dots(rect: Rect2, color: Color) -> void:
	var step := 4.0
	var x := rect.position.x
	while x < rect.end.x - 1.0:
		draw_rect(Rect2(x, rect.position.y, 2, 1), color)
		draw_rect(Rect2(x, rect.end.y - 1, 2, 1), color)
		x += step
	var y := rect.position.y
	while y < rect.end.y - 1.0:
		draw_rect(Rect2(rect.position.x, y, 1, 2), color)
		draw_rect(Rect2(rect.end.x - 1, y, 1, 2), color)
		y += step


# =============================================================================
# TEXTO
# =============================================================================


func _box(x: float, y: float, width: float, height: float) -> Rect2:
	return Rect2(x, y, width, height)


func _mouse_over(rect: Rect2) -> bool:
	return rect.has_point(_hover_point)


# El ancho se pasa siempre: con width < 0 Godot ignora la alineación y dibuja el
# texto desde el ancla en lugar de hacia ella (ese era el fallo de raíz).
# Texto general en Montserrat; los números y sus unidades usan D-DIN.
func _text(
	rect: Rect2,
	text: String,
	size: int,
	color: Color,
	bold: bool = false,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	width_override: float = -1.0
) -> void:
	_text_with(
		FONT_SERIF_BOLD if bold else FONT_SERIF, rect, text, size, color, align, width_override
	)


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
	draw_string(
		font,
		Vector2(round(rect.position.x), round(baseline)),
		text,
		align,
		width,
		size,
		color
	)


func _ui_width(text: String, size: int, bold: bool) -> float:
	var font := FONT_UI_BOLD if bold else FONT_UI
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


# Ancho medido con la fuente real del texto general (Montserrat).
func _serif_width(text: String, size: int, bold: bool) -> float:
	var font := FONT_SERIF_BOLD if bold else FONT_SERIF
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _wrap_text(text: String, max_lines: int, width_chars: int) -> Array[String]:
	var lines: Array[String] = []
	var current := ""
	for word in text.split(" ", false):
		var candidate := word if current.is_empty() else current + " " + word
		if candidate.length() > width_chars and not current.is_empty():
			lines.append(current)
			current = word
			if lines.size() >= max_lines:
				break
		else:
			current = candidate
	if lines.size() < max_lines and not current.is_empty():
		lines.append(current)
	return lines


func _short_timestamp(value: String) -> String:
	if value.is_empty():
		return ""
	return value.replace("T", " ").trim_suffix("Z").left(16)


func _fuel_density() -> float:
	return maxf(vehicle.simulation.mass_model.fuel_density_kg_per_litre, 0.000001) if vehicle != null else 0.74
