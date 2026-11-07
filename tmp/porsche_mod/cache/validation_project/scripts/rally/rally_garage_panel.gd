class_name RallyGaragePanel
extends Control

signal garage_closed(applied: bool)

const LOGICAL_SIZE := Vector2(1280.0, 800.0)
const FONT_SERIF: Font = preload("res://fonts/libron/Libron-Regular.ttf")
const FONT_SERIF_BOLD: Font = preload("res://fonts/libron/Libron-Bold.ttf")
const FONT_UI: Font = preload("res://fonts/D-DIN.ttf")
const FONT_UI_BOLD: Font = preload("res://fonts/D-DIN-Bold.ttf")
const FONT_TITLE: Font = preload("res://fonts/montserrat/Montserrat-Bold.ttf")

# --- Aero Glass 2006: cabecera y pie ----------------------------------------
const C_BACK := Color("#080d12")
const C_GLASS := Color("#16232f")
const C_GLASS_DEEP := Color("#0d151d")
const C_RIM := Color("#7fa8c9")
const C_CHROME_TEXT := Color("#eaf2f8")
const C_CHROME_DIM := Color("#93a9bb")
const C_BLUE := Color("#6db2e8")
const C_BLUE_DEEP := Color("#2c6da3")

# --- Windows 98 clásico: panel central ---------------------------------------
const C_FACE := Color("#2b3d4d")
const C_FACE_HI := Color("#374c5e")
const C_FACE_LO := Color("#22323f")
const C_FIELD := Color("#0c151d")
const C_HI := Color("#93afc8")
const C_LIGHT := Color("#5d7890")
const C_SHADOW := Color("#101b25")
const C_DARK := Color("#000000")
const C_TEXT := Color("#e2edf6")
const C_DIM := Color("#9eb3c5")
const C_GOLD := Color("#e3b23c")
const C_GOLD_HI := Color("#f6d68a")
const C_ROSE := Color("#ff6b61")
const C_SEL := Color("#3b3324")

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
	"powertrain.differential.preload_nm",
	"powertrain.differential.power_ramp_angle_deg",
	"powertrain.differential.coast_ramp_angle_deg",
	"powertrain.differential.clutches",
	"steering.max_steering_angle",
	"steering.steering_speed",
]
const STRATEGY_PATHS: Array[String] = ["fuel.initial_kg"]

@export var vehicle_path: NodePath
@export var input_controller_path: NodePath
@export_enum("rally", "gp") var mode: String = "rally"
@export var circuit_id: String = "russia-stage-1"
@export var circuit_name: String = "Rusia Stage 1"
@export var circuit_country: String = "Russia"
@export var circuit_length_m: float = 5500.0
@export var team_id: String = "rally-works"
@export var team_name: String = "Ford Rally Works"

var advanced_section := 0
var mandatory_confirmation := false
var compound_change_allowed := true
var draft_wheel_compounds: Dictionary = { }
var draft_compound_id: String:
	get:
		var wet_count := 0
		for c in draft_wheel_compounds.values():
			if c == "gravel_wet":
				wet_count += 1
		return "gravel_wet" if wet_count >= 2 else "gravel_normal"
	set(value):
		for corner in ["FL", "FR", "RL", "RR"]:
			draft_wheel_compounds[corner] = value
var opening_wheel_compounds: Dictionary = { }
var draft_spare_wheels := 1
var opening_spares := 1
var confirmed_setup: Dictionary = { }
var event_forecast := ""
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
var _hit_regions: Array[Dictionary] = []
var _page_field_paths: Array[String] = []
var _canvas_scale: float = 1.0
var _canvas_offset: Vector2 = Vector2.ZERO
var _restore_tree_paused: bool = false
var _restore_controls_enabled: bool = true
var _hover_point := Vector2(-4000.0, -4000.0)
var _dragging_path: String = ""
var _dragging_rect := Rect2()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_process_input(false)
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
	database.close_database()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_resize_canvas()


func _resize_canvas() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_canvas_scale = minf(size.x / LOGICAL_SIZE.x, size.y / LOGICAL_SIZE.y)
	_canvas_offset = (size - LOGICAL_SIZE * _canvas_scale) * 0.5
	queue_redraw()


func open_garage_for_event(options: Dictionary = { }) -> void:
	mandatory_confirmation = bool(options.get("confirmation_required", false))
	if options.has("window_label") and not str(options.get("window_label", "")).is_empty():
		circuit_name = str(options["window_label"])
	compound_change_allowed = bool(options.get("compound_change_allowed", true))
	event_forecast = (
		str(options.get("forecast_summary", "")) + "  " + str(options.get("forecast_advice", ""))
	).strip_edges()
	open_garage()
	if str(options.get("initial_tab", "")) in ["tires", "strategy"]:
		advanced_section = 1
		_set_page(1)


func get_confirmed_setup() -> Dictionary:
	return confirmed_setup.duplicate(true)


func open_garage() -> void:
	if visible or vehicle == null:
		return
	_restore_tree_paused = get_tree().paused
	_restore_controls_enabled = input_controller.controls_enabled if input_controller != null else true
	opening_values = RallySetupCatalog.defaults(vehicle.simulation.domains)
	opening_values["fuel.initial_kg"] = vehicle.simulation.thermal_model.fuel_remaining_litres * vehicle \
			.simulation \
			.mass_model \
			.fuel_density_kg_per_litre
	draft_values = opening_values.duplicate(true)
	vehicle.ensure_tire_inventory()
	draft_wheel_compounds.clear()
	for i in 4:
		draft_wheel_compounds[["FL", "FR", "RL", "RR"][i]] = vehicle \
				.tire_inventory \
				.mounted[i] \
				.compound_id
	opening_wheel_compounds = draft_wheel_compounds.duplicate()
	draft_spare_wheels = vehicle.tire_inventory.spares.size()
	opening_spares = draft_spare_wheels
	confirmed_setup = { }
	pending_values = { }
	new_tires_service = false
	page = 0
	advanced_section = 0
	selected_field_path = ""
	_set_page(0)
	active_setup_id = -1
	active_setup_name = "BASE"
	modal_mode = ""
	modal_text = ""
	notice = ""
	notice_time = 0.0
	_dragging_path = ""
	_hover_point = Vector2(-4000.0, -4000.0)
	_refresh_setups()
	visible = true
	set_process_input(true)
	if input_controller != null:
		input_controller.set_controls_enabled(false)
	get_tree().paused = true
	queue_redraw()


func close_garage(apply_changes: bool, confirmed_discard: bool = false) -> void:
	if not visible:
		return
	if mandatory_confirmation and not apply_changes:
		_show_notice("Confirma reglajes para continuar.", true)
		return
	if not apply_changes and _has_unapplied_changes() and not confirmed_discard:
		modal_mode = "discard"
		queue_redraw()
		return
	if apply_changes:
		var setup_to_apply := draft_values.duplicate(true)
		for k in setup_to_apply.keys():
			if str(k).begins_with("strategy."):
				if str(k) == "strategy.spare_wheels":
					draft_spare_wheels = int(setup_to_apply[k])
				elif str(k).begins_with("strategy.wheel_compound."):
					var corner := str(k).trim_prefix("strategy.wheel_compound.")
					draft_wheel_compounds[corner] = str(setup_to_apply[k])
				setup_to_apply.erase(k)
		var applied := vehicle.apply_setup_values(setup_to_apply)
		if not bool(applied.get("ok", false)):
			_show_notice(str(applied.get("error", "Error al aplicar.")), true)
			return
		vehicle.service_tire_inventory(draft_wheel_compounds, draft_spare_wheels, new_tires_service)
		var wet_count := 0
		for compound in draft_wheel_compounds.values():
			if compound == "gravel_wet":
				wet_count += 1
		confirmed_setup = {
			"compound_id": "gravel_wet" if wet_count >= 2 else "gravel_normal",
			"values": draft_values.duplicate(true),
		}
	else:
		vehicle.apply_setup_values(opening_values)
	visible = false
	set_process_input(false)
	_dragging_path = ""
	get_tree().paused = _restore_tree_paused
	if input_controller != null:
		input_controller.set_controls_enabled(_restore_controls_enabled)
	garage_closed.emit(apply_changes)
	queue_redraw()


func _has_unapplied_changes() -> bool:
	return (
		draft_values != opening_values or new_tires_service
		or draft_wheel_compounds != opening_wheel_compounds or draft_spare_wheels != opening_spares
	)


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
		queue_redraw()
		return
	if modal_mode == "delete":
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_delete_selected_setup()
		elif event.keycode == KEY_ESCAPE:
			modal_mode = ""
		queue_redraw()
		return
	if modal_mode == "discard":
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			close_garage(false, true)
		elif event.keycode == KEY_ESCAPE:
			modal_mode = ""
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
		KEY_DELETE:
			if page == 3:
				_begin_delete_setup()
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
			JOY_BUTTON_START:
				_commit_new_setup()
			JOY_BUTTON_B:
				modal_mode = ""
		queue_redraw()
		return
	if modal_mode == "delete":
		if event.button_index in [JOY_BUTTON_START, JOY_BUTTON_A]:
			_delete_selected_setup()
		elif event.button_index == JOY_BUTTON_B:
			modal_mode = ""
		queue_redraw()
		return
	if modal_mode == "discard":
		if event.button_index in [JOY_BUTTON_START, JOY_BUTTON_A]:
			close_garage(false, true)
		elif event.button_index == JOY_BUTTON_B:
			modal_mode = ""
		queue_redraw()
		return
	match event.button_index:
		JOY_BUTTON_START:
			close_garage(true)
		JOY_BUTTON_B:
			close_garage(false)
		JOY_BUTTON_A:
			_confirm_selection()
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
				if compound_change_allowed:
					for corner in ["FL", "FR", "RL", "RR"]:
						draft_wheel_compounds[corner] = str(region.compound)
			"compound":
				if compound_change_allowed:
					var corner: String = str(region.corner)
					draft_wheel_compounds[corner] = "gravel_wet" if draft_wheel_compounds.get(
						corner
					) == "gravel_normal" else "gravel_normal"
			"spares":
				draft_spare_wheels = posmod(draft_spare_wheels + int(region.get("delta", 1)), 3)
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


func _set_page(next_page: int) -> void:
	page = posmod(next_page, 4)
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
					source = POWERTRAIN_PATHS
		2:
			source = STRATEGY_PATHS
	for path in source:
		if not _page_field_paths.has(path):
			_page_field_paths.append(path)
	if not _page_field_paths.has(selected_field_path):
		selected_field_path = _page_field_paths[0] if not _page_field_paths.is_empty() else ""
	if page == 3:
		_refresh_setups()
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


func _confirm_selection() -> void:
	if page == 2:
		new_tires_service = not new_tires_service
	elif page == 3:
		_load_selected_setup()
	elif selected_field_path.is_empty() and not _page_field_paths.is_empty():
		selected_field_path = _page_field_paths[0]
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
			active_setup_name = "FÁBRICA"
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
		modal_text = active_setup_name if not (active_setup_name in ["BASE", "FÁBRICA"]) else ""
		return
	var result := database.update_setup(_database_context(), target_id, target_name, draft_values)
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
	var result := database.create_setup(_database_context(), setup_name, draft_values)
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
	var validation := RallySetupCatalog.validate(result.values)
	if not bool(validation.get("ok", false)):
		_show_notice(str(validation.get("error", "Incompatible.")), true)
		return
	var applied := vehicle.apply_setup_values(validation.values)
	if not bool(applied.get("ok", false)):
		_show_notice(str(applied.get("error", "Error al aplicar.")), true)
		return
	draft_values = applied.values
	active_setup_id = selected_setup_id
	active_setup_name = str(result.get("name", "REGLAJE"))
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
	var keys: Array = vehicle.simulation.domain_hashes.keys()
	keys.sort()
	var canonical := ""
	for key in keys:
		canonical += str(key) + ":" + str(vehicle.simulation.domain_hashes[key]) + "\n"
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(canonical.to_utf8_buffer())
	return {
		"circuit_id": circuit_id,
		"team_id": team_id,
		"car_id": str(vehicle.rally_profile.get("profile_id", "ford_escort_rs2000_1971")),
		"physics_backend": RallySetupDatabase.PHYSICS_BACKEND,
		"base_profile_sha256": hash_context.finish().hex_encode(),
		"mode": mode,
	}


func _show_notice(message: String, is_error: bool = false) -> void:
	notice = message
	notice_time = 4.0
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
	for i in 48:
		var t := float(i) / 48.0
		draw_rect(
			Rect2(0, t * 470.0, LOGICAL_SIZE.x, 470.0 / 48.0 + 1.0),
			Color(0.30, 0.52, 0.72, pow(1.0 - t, 2.0) * 0.20)
		)



func _get_vehicle_display_name() -> String:
	if vehicle != null:
		if vehicle.name.to_lower().contains("fulvia") or vehicle.rally_profile_path.to_lower().contains("fulvia"):
			return "LANCIA FULVIA HF"
		if vehicle.name.to_lower().contains("escort") or vehicle.rally_profile_path.to_lower().contains("escort"):
			return "FORD ESCORT RS2000"
		if vehicle.rally_profile.has("profile_name"):
			return str(vehicle.rally_profile.get("profile_name")).to_upper()
	return "FORD ESCORT RS2000"


func _get_team_display_name() -> String:
	if not team_name.is_empty() and team_name != "Ford Rally Works":
		return team_name.to_upper()
	if vehicle != null and (vehicle.name.to_lower().contains("fulvia") or vehicle.rally_profile_path.to_lower().contains("fulvia")):
		return "LANCIA HF"
	return "FORD RALLY WORKS"
func _draw_chrome_header() -> void:
	_glass_window(Rect2(24, 18, 1232, 76), 10)

	_text_title(_box(46, 22, 0, 34), _get_vehicle_display_name(), 20, C_CHROME_TEXT)
	_text_serif(_box(46, 54, 260, 26), _get_team_display_name(), 11, C_CHROME_DIM, true)

	draw_line(Vector2(330, 34), Vector2(330, 78), Color(C_RIM, 0.22), 1.0)

	_text_title(_box(354, 22, 0, 34), circuit_name.to_upper(), 16, C_CHROME_TEXT)
	var subtitle := "%s  ·  %0.1f KM  ·  %s" % [
		circuit_country.to_upper(), circuit_length_m / 1000.0, mode.to_upper()
	]
	_text_serif(_box(354, 54, 360, 26), subtitle, 11, C_CHROME_DIM)

	_glass_box(Rect2(986, 30, 250, 52), 7, C_GLASS_DEEP, Color(C_RIM, 0.34), 0.06)
	_text_title(_box(1002, 36, 218, 20), "REGLAJE ACTIVO", 9, C_CHROME_DIM)
	_text_title(
		_box(1002, 54, 218, 24),
		active_setup_name.to_upper(),
		15,
		C_BLUE,
		HORIZONTAL_ALIGNMENT_RIGHT,
		218
	)


func _draw_chrome_footer() -> void:
	_glass_window(Rect2(24, 692, 1232, 88), 10)

	_chrome_button(Rect2(46, 714, 168, 46), "FÁBRICA", "reset")

	# Franja reservada para el aviso: nunca se dibuja encima del contenido.
	var lane := Rect2(400, 700, 470, 72)
	if notice_time > 0.0 and not notice.is_empty():
		var tone := C_ROSE if _notice_is_error() else C_GOLD
		_glass_box(lane, 7, Color(C_GLASS_DEEP, 0.85), Color(tone, 0.55), 0.05)
		_text_serif(
			_box(lane.position.x + 12, lane.position.y, lane.size.x - 24, lane.size.y),
			notice.to_upper(),
			11,
			tone,
			true,
			HORIZONTAL_ALIGNMENT_CENTER
		)
	else:
		_text_serif(
			_box(lane.position.x, lane.position.y, lane.size.x, lane.size.y),
			"ENTER CONFIRMA · ESC DESCARTA · W/S NAVEGA",
			10,
			Color(C_CHROME_DIM, 0.72),
			false,
			HORIZONTAL_ALIGNMENT_CENTER
		)

	_chrome_button(Rect2(900, 714, 150, 46), "CANCELAR", "cancel")
	_gold_button(Rect2(1066, 714, 168, 46), "APLICAR", "apply")


func _notice_is_error() -> bool:
	var lowered := notice.to_lower()
	return (
		lowered.contains("error") or lowered.contains("no disponible")
		or lowered.contains("incompatible") or lowered.contains("selecciona")
	)


func _draw_classic_panel() -> void:
	draw_rect(PANEL, C_FACE)
	draw_rect(Rect2(PANEL.position.x, PANEL.position.y, PANEL.size.x, 1), C_HI)
	draw_rect(Rect2(PANEL.position.x, PANEL.position.y, 1, PANEL.size.y), C_HI)
	draw_rect(Rect2(PANEL.position.x, PANEL.end.y - 1, PANEL.size.x, 1), C_DARK)
	draw_rect(Rect2(PANEL.end.x - 1, PANEL.position.y, 1, PANEL.size.y), C_DARK)
	draw_rect(Rect2(PANEL.position.x + 1, 144, PANEL.size.x - 2, 1), C_SHADOW)
	draw_rect(Rect2(PANEL.position.x + 1, 145, PANEL.size.x - 2, 1), C_LIGHT)


func _draw_tabs() -> void:
	var titles := ["RÁPIDO", "AVANZADO", "ESTRATEGIA", "PERFILES"]
	var x := 34.0
	for index in titles.size():
		var label: String = titles[index]
		var width: float = maxf(126.0, _title_width(label, 11) + 52.0)
		var rect := Rect2(x, 100, width, 44)
		_tab(rect, label, index == page)
		_hit_regions.append({ "rect": rect, "kind": "tab", "page": index })
		x += width + 4.0

	var changed := _dirty_field_count()
	if changed > 0:
		var banner := "%d CAMBIO%s SIN APLICAR" % [changed, "" if changed == 1 else "S"]
		var banner_w := _serif_width(banner, 10, true)
		var banner_x := 1244.0 - banner_w
		draw_circle(Vector2(banner_x - 14.0, 122.0), 3.5, C_BLUE)
		draw_circle(Vector2(banner_x - 14.0, 122.0), 7.0, Color(C_BLUE, 0.16))
		_text(_box(banner_x, 104, banner_w + 2, 36), banner, 10, C_BLUE, true)


func _dirty_field_count() -> int:
	var count := 0
	for path in draft_values:
		if float(draft_values.get(path, 0.0)) != float(opening_values.get(path, 0.0)):
			count += 1
	if draft_wheel_compounds != opening_wheel_compounds:
		count += 1
	if draft_spare_wheels != opening_spares:
		count += 1
	if new_tires_service:
		count += 1
	return count


func _tab(rect: Rect2, label: String, active: bool) -> void:
	var bottom := rect.end.y + 3.0 if active else rect.end.y
	var top := rect.position.y if active else rect.position.y + 5.0
	var cut := 9.0
	var pts := PackedVector2Array(
		[
			Vector2(rect.position.x, bottom),
			Vector2(rect.position.x, top + cut),
			Vector2(rect.position.x + cut, top),
			Vector2(rect.end.x - cut, top),
			Vector2(rect.end.x, top + cut),
			Vector2(rect.end.x, bottom),
		]
	)
	var faced := C_FACE if active else C_FACE_LO
	if not active and _mouse_over(rect):
		faced = C_FACE_HI
	draw_colored_polygon(pts, faced)

	var top_path := PackedVector2Array(
		[
			Vector2(rect.position.x + 0.5, bottom),
			Vector2(rect.position.x + 0.5, top + cut),
			Vector2(rect.position.x + cut, top + 0.5),
			Vector2(rect.end.x - cut, top + 0.5),
			Vector2(rect.end.x - 0.5, top + cut),
		]
	)
	draw_polyline(top_path, C_HI if active else C_LIGHT, 1.0)
	draw_line(Vector2(rect.end.x - 0.5, top + cut), Vector2(rect.end.x - 0.5, bottom), C_DARK, 1.0)
	if active:
		# La pestaña activa tapa el borde de página para leerse como conectada.
		draw_rect(Rect2(rect.position.x + 1, 144, rect.size.x - 2, 3), C_FACE)
	else:
		draw_line(
			Vector2(rect.position.x + 1, bottom - 0.5),
			Vector2(rect.end.x - 1, bottom - 0.5),
			C_SHADOW,
			1.0
		)

	_text_title(
		_box(rect.position.x, top + 5.0, rect.size.x, bottom - top - 9.0),
		label,
		11,
		C_TEXT if active else C_DIM,
		HORIZONTAL_ALIGNMENT_CENTER
	)


# =============================================================================
# PÁGINA 0 — RÁPIDO
# =============================================================================


func _draw_quick_page() -> void:
	var section := Rect2(36, PAGE_TOP, 816, 356)
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

	_draw_compound_group(Rect2(36, 518, 816, 156))
	_draw_state_group(Rect2(864, PAGE_TOP, 380, 268))
	_draw_tire_group(Rect2(864, 434, 380, 240))


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

	_text(_box(rect.position.x + 14, rect.position.y + 8, 250, 26), str(data.name), 13, C_TEXT, true)
	_hint(_box(rect.position.x + 14, rect.position.y + 34, 250, 18), str(data.hint))

	var track_x := rect.position.x + 242.0
	var track_w := 340.0
	_text(_box(track_x, rect.position.y + 8, 150, 14), str(data.left), 8, C_DIM, true)
	_text(
		_box(track_x + track_w - 150, rect.position.y + 8, 150, 14),
		str(data.right),
		8,
		C_DIM,
		true,
		HORIZONTAL_ALIGNMENT_RIGHT,
		150
	)

	_stepper(Rect2(track_x - 36, rect.position.y + 24, 28, 28), false)
	_track(Rect2(track_x, rect.position.y + 33, track_w, 11), _get_quick_fraction(key), selected)
	_stepper(Rect2(track_x + track_w + 6, rect.position.y + 24, 28, 28), true)

	_field_box(
		Rect2(rect.position.x + 624, rect.position.y + 19, 164, 38),
		str(data.value),
		16,
		C_GOLD if selected else C_TEXT,
		bool(data.get("numeric", true))
	)

	var minus := Rect2(track_x - 38, rect.position.y + 20, 32, 36)
	var plus := Rect2(track_x + track_w + 4, rect.position.y + 20, 32, 36)
	_hit_regions.append({ "rect": minus, "kind": "quick", "path": key, "amount": -1.0 })
	_hit_regions.append({ "rect": plus, "kind": "quick", "path": key, "amount": 1.0 })
	_hit_regions.append(
		{
			"rect": Rect2(track_x, rect.position.y + 20, track_w, 36),
			"kind": "quick_slide",
			"path": key,
			"track": Rect2(track_x, rect.position.y + 33, track_w, 11),
		}
	)
	_hit_regions.append({ "rect": Rect2(track_x - 6, rect.position.y + 27, track_w + 12, 23), "kind": "select", "path": key })


func _draw_compound_group(rect: Rect2) -> void:
	_group(rect, "COMPUESTO")
	var dry_rect := Rect2(52, 548, 340, 24)
	var wet_rect := Rect2(52, 578, 340, 24)
	_radio(dry_rect, "GRAVA SECA  —  agarre alto en seco", _all_dry())
	_radio(wet_rect, "GRAVA MOJADA  —  drenaje, menos grip", _all_wet())
	if compound_change_allowed:
		_hit_regions.append({ "rect": dry_rect, "kind": "all_compound", "compound": "gravel_normal" })
		_hit_regions.append({ "rect": wet_rect, "kind": "all_compound", "compound": "gravel_wet" })

	draw_rect(Rect2(52, 610, 340, 1), C_SHADOW)
	draw_rect(Rect2(52, 611, 340, 1), C_LIGHT)
	_hint(_box(52, 618, 340, 18), "SE APLICA A LOS CUATRO NEUMÁTICOS")
	if not compound_change_allowed:
		_hint(_box(52, 636, 340, 18), "BLOQUEADO POR EL EVENTO")

	var memo := Rect2(420, 548, 412, 106)
	draw_rect(memo, C_FIELD)
	_sunken(memo)
	_text(_box(memo.position.x + 10, memo.position.y + 10, memo.size.x - 20, 18), "EL COMPUESTO CAMBIA:", 9, C_TEXT, true)
	_text(_box(memo.position.x + 10, memo.position.y + 28, memo.size.x - 20, 18), "· REPARTO DE AGARRE", 9, C_DIM)
	_text(_box(memo.position.x + 10, memo.position.y + 44, memo.size.x - 20, 18), "· TEMPERATURA DE TRABAJO", 9, C_DIM)
	_text(_box(memo.position.x + 10, memo.position.y + 60, memo.size.x - 20, 18), "· DESGASTE POR VUELTA", 9, C_DIM)
	_text(
		_box(memo.position.x + 10, memo.position.y + 84, memo.size.x - 20, 18),
		"MOJADO PIERDE GRIP EN SECO. SECO PIERDE DRENAJE.",
		9,
		C_TEXT
	)


func _all_dry() -> bool:
	var wet := 0
	for compound in draft_wheel_compounds.values():
		if compound == "gravel_wet":
			wet += 1
	return wet < 2


func _all_wet() -> bool:
	return not _all_dry()


func _draw_state_group(rect: Rect2) -> void:
	_group(rect, "ESTADO DEL COCHE")
	var rows := [
		{"k": "MASA", "v": "%0.0f kg" % _vehicle_mass()},
		{"k": "COMPUESTO", "v": "MOJADO" if _all_wet() else "SECO", "numeric": false},
		{"k": "COMBUSTIBLE", "v": "%0.1f L" % (float(draft_values.get("fuel.initial_kg", 0.0)) / _fuel_density())},
		{"k": "PRESIÓN MEDIA", "v": "%0.0f kPa" % _average_pressure()},
		{"k": "TEMP. MEDIA", "v": "%0.0f °C" % _average_temperature()},
	]
	var inner := _group_inner(rect)
	var height := floorf(inner.size.y / float(rows.size()))
	var offset := (inner.size.y - height * float(rows.size())) * 0.5
	for i in rows.size():
		var y := inner.position.y + float(i) * height + offset
		_text(_box(inner.position.x, y, 150, height), str(rows[i].k), 10, C_DIM, true)
		_field_box(
			Rect2(inner.end.x - 176, y + (height - 34.0) * 0.5, 176, 34),
			str(rows[i].v),
			13,
			C_TEXT,
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
		draw_rect(card, C_FACE_LO)
		_sunken(card)
		var wet: bool = draft_wheel_compounds.get(codes[i]) == "gravel_wet"
		_text(_box(card.position.x + 10, card.position.y + 6, 60, 20), codes[i], 13, C_TEXT, true)
		_text(
			_box(card.position.x, card.position.y + 8, card.size.x - 10, 16),
			"MOJADO" if wet else "SECO",
			9,
			C_DIM,
			true,
			HORIZONTAL_ALIGNMENT_RIGHT,
			card.size.x - 10
		)
		var bar := Rect2(card.position.x + 10, card.position.y + 32, card.size.x - 20, 10)
		draw_rect(bar, C_FIELD)
		_sunken(bar)
		var fraction := 0.55 if wet else 0.72
		draw_rect(
			Rect2(bar.position + Vector2(1, 1), Vector2((bar.size.x - 2) * fraction, bar.size.y - 2)),
			Color(C_BLUE_DEEP, 0.9),
			false
		)
		_num(
			_box(card.position.x, card.position.y + 50, card.size.x - 10, 18),
			"%0.0f kPa · %0.0f °C" % [_wheel_pressure(i), _wheel_temperature(i)],
			9,
			C_DIM,
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
		var width: float = maxf(150.0, _title_width(label, 11) + 50.0)
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
	for i in 4:
		var rect := Rect2(inner.position.x, inner.position.y + float(i) * row_h, inner.size.x, row_h)
		var wet: bool = draft_wheel_compounds.get(codes[i]) == "gravel_wet"
		_row_frame(rect, false, i == 3, _mouse_over(rect))
		_text(_box(rect.position.x + 12, rect.position.y, 90, row_h), codes[i], 13, C_TEXT, true)
		_hint(_box(rect.position.x + 52, rect.position.y, 180, row_h), "GRAVA MOJADA" if wet else "GRAVA SECA")
		_toggle(
			Rect2(rect.end.x - 132, rect.position.y + (row_h - 30.0) * 0.5, 120, 30),
			"MOJADO" if wet else "SECO",
			wet
		)
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
		_text(_box(box.position.x + 8, box.position.y + 4, 40, 18), str(gears[i].label), 11, C_TEXT, true)
		_num(
			_box(box.position.x, box.position.y + 4, box.size.x - 8, 18),
			"%0.2f" % float(gears[i].value),
			11,
			C_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT,
			box.size.x - 8
		)
		var bar := Rect2(box.position.x + 8, box.end.y - 16, box.size.x - 16, 8)
		draw_rect(bar, C_FIELD)
		_sunken(bar)
		draw_rect(
			Rect2(
				bar.position + Vector2(1, 1),
				Vector2((bar.size.x - 2) * (float(gears[i].value) / max_value), bar.size.y - 2)
			),
			Color(C_BLUE_DEEP, 0.9),
			false
		)


# =============================================================================
# PÁGINA 2 — ESTRATEGIA
# =============================================================================


func _draw_strategy_page() -> void:
	_group(Rect2(36, PAGE_TOP, 596, 164), "COMBUSTIBLE")
	_field_rows(Rect2(36, PAGE_TOP, 596, 92), [{ "p": "fuel.initial_kg", "l": "Combustible inicial" }])

	var capacity := 45.0
	if is_instance_valid(vehicle):
		capacity = maxf(float(vehicle.simulation.mass_model.fuel_capacity_kg), 0.001)
	var current := float(draft_values.get("fuel.initial_kg", 0.0))
	var fraction := clampf(current / capacity, 0.0, 1.0)
	_text(_box(50, 246, 200, 20), "DEPÓSITO", 10, C_DIM, true)
	_num(
		_box(50, 246, 568, 20),
		"%0.1f / %0.1f L" % [current / _fuel_density(), capacity / _fuel_density()],
		11,
		C_TEXT,
		HORIZONTAL_ALIGNMENT_RIGHT,
		568
	)
	var groove := Rect2(50, 270, 568, 22)
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
		false
	)
	for segment in range(1, 10):
		var sx := groove.position.x + groove.size.x * (float(segment) / 10.0)
		draw_rect(Rect2(sx, groove.position.y + 1, 1, groove.size.y - 2), Color(C_DARK, 0.55))

	_group(Rect2(36, 332, 596, 156), "SERVICIO")
	var service_rect := Rect2(50, 356, 568, 44)
	_row_frame(service_rect, false, false, _mouse_over(service_rect))
	_text(_box(service_rect.position.x + 12, service_rect.position.y, 300, 44), "NEUMÁTICOS NUEVOS", 11, C_TEXT)
	_toggle(
		Rect2(service_rect.end.x - 132, service_rect.position.y + 7, 120, 30),
		"SÍ" if new_tires_service else "NO",
		new_tires_service
	)
	_hit_regions.append({ "rect": service_rect, "kind": "service" })

	var spare_rect := Rect2(50, 408, 568, 44)
	_row_frame(spare_rect, false, true, _mouse_over(spare_rect))
	_text(_box(spare_rect.position.x + 12, spare_rect.position.y, 300, 44), "RUEDAS DE REPUESTO", 11, C_TEXT)
	for s in 3:
		var button := Rect2(spare_rect.end.x - 140 + float(s) * 46, spare_rect.position.y + 8, 42, 28)
		_toggle(button, str(s), draft_spare_wheels == s)
		_hit_regions.append({ "rect": button, "kind": "spares", "delta": s - draft_spare_wheels })

	_group(Rect2(36, 500, 596, 174), "METEOROLOGÍA")
	_text(_box(50, 516, 568, 18), "PREVISIÓN DEL EVENTO", 9, C_DIM, true)
	var memo := Rect2(50, 538, 568, 122)
	draw_rect(memo, C_FIELD)
	_sunken(memo)
	if event_forecast.is_empty():
		_hint(_box(memo.position.x + 10, memo.position.y + 10, memo.size.x - 20, 18), "SIN PREVISIÓN PARA ESTE EVENTO")
	else:
		var lines := _wrap_text(event_forecast, 4, 84)
		for i in lines.size():
			_text(
				_box(memo.position.x + 10, memo.position.y + 10 + float(i) * 20, memo.size.x - 20, 18),
				lines[i],
				10,
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
		draw_rect(card, C_FACE_LO)
		_sunken(card)
		var wet: bool = draft_wheel_compounds.get(codes[i]) == "gravel_wet"
		_text(_box(card.position.x + 12, card.position.y + 8, 70, 22), codes[i], 15, C_TEXT, true)
		_text(
			_box(card.position.x, card.position.y + 10, card.size.x - 12, 18),
			names[i],
			9,
			C_DIM,
			false,
			HORIZONTAL_ALIGNMENT_RIGHT,
			card.size.x - 12
		)
		_text(_box(card.position.x + 12, card.position.y + 42, 160, 14), "PRESIÓN", 9, C_DIM, true)
		_field_box(
			Rect2(card.position.x + 12, card.position.y + 56, card.size.x - 24, 30),
			"%0.0f kPa" % _wheel_pressure(i),
			12,
			C_TEXT
		)
		_text(_box(card.position.x + 12, card.position.y + 94, 160, 14), "TEMPERATURA", 9, C_DIM, true)
		_field_box(
			Rect2(card.position.x + 12, card.position.y + 108, card.size.x - 24, 30),
			"%0.0f °C" % _wheel_temperature(i),
			12,
			C_BLUE
		)
		var bar := Rect2(card.position.x + 12, card.position.y + 152, card.size.x - 24, 10)
		var thermal := clampf((_wheel_temperature(i) - 20.0) / 90.0, 0.04, 1.0)
		draw_rect(bar, C_FIELD)
		_sunken(bar)
		draw_rect(
			Rect2(bar.position + Vector2(1, 1), Vector2((bar.size.x - 2) * thermal, bar.size.y - 2)),
			Color(C_BLUE_DEEP, 0.9),
			false
		)
		var toggle := Rect2(card.position.x + 12, card.end.y - 44, card.size.x - 24, 32)
		_toggle(toggle, "MOJADO" if wet else "SECO", wet)
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
			12,
			C_TEXT,
			selected
		)
		_num(
			_box(rect.position.x, rect.position.y, rect.size.x - 16, row_h),
			_short_timestamp(str(row.get("modified_at", ""))),
			10,
			C_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT,
			rect.size.x - 16
		)
		_hit_regions.append({ "rect": rect, "kind": "setup_row", "index": index })

	if setup_rows.is_empty():
		_text(
			_box(inner.position.x, inner.position.y, inner.size.x, inner.size.y),
			"SIN PERFILES GUARDADOS",
			12,
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
	_text_title(_box(detail.position.x + 12, detail.position.y + 10, detail.size.x - 24, 18), "DETALLE", 9, C_DIM)
	_text(_box(detail.position.x + 12, detail.position.y + 32, detail.size.x - 24, 18), "CIRCUITO", 9, Color(C_DIM, 0.75))
	_text(_box(detail.position.x + 12, detail.position.y + 48, detail.size.x - 24, 18), circuit_name.to_upper(), 11, C_TEXT)
	_text(_box(detail.position.x + 12, detail.position.y + 74, detail.size.x - 24, 18), "COCHE", 9, Color(C_DIM, 0.75))
	_text(_box(detail.position.x + 12, detail.position.y + 90, detail.size.x - 24, 18), _get_vehicle_display_name(), 11, C_TEXT)
	_text(_box(detail.position.x + 12, detail.position.y + 116, detail.size.x - 24, 18), "REGLAJE ACTIVO", 9, Color(C_DIM, 0.75))
	_text(_box(detail.position.x + 12, detail.position.y + 132, detail.size.x - 24, 18), active_setup_name.to_upper(), 11, C_BLUE, true)
	_text(
		_box(detail.position.x + 12, detail.position.y + 164, detail.size.x - 24, 18),
		"ENTER CARGA · SUPR BORRA",
		9,
		Color(C_DIM, 0.7)
	)


# =============================================================================
# MODAL
# =============================================================================


func _draw_modal() -> void:
	draw_rect(Rect2(Vector2.ZERO, LOGICAL_SIZE), Color(0, 0, 0, 0.72))
	var rect := Rect2(390, 262, 500, 250)
	_glass_window(rect, 10)
	_text_title(
		_box(rect.position.x + 18, rect.position.y + 8, rect.size.x - 36, 32),
		"PERFIL" if modal_mode == "name" else "CONFIRMACIÓN",
		11,
		C_BLUE
	)
	draw_line(
		Vector2(rect.position.x + 1, rect.position.y + 44),
		Vector2(rect.end.x - 1, rect.position.y + 44),
		Color(C_RIM, 0.28),
		1.0
	)

	var body := Rect2(rect.position.x + 18, rect.position.y + 58, rect.size.x - 36, 118)
	draw_rect(body, C_FACE)
	_bevel(body, false, 2)

	if modal_mode == "name":
		_text_title(_box(body.position.x + 12, body.position.y + 10, body.size.x - 24, 20), "NOMBRE DEL REGLAJE", 10, C_DIM)
		var input := Rect2(body.position.x + 12, body.position.y + 36, body.size.x - 24, 40)
		draw_rect(input, C_FIELD)
		_sunken(input)
		_text(_box(input.position.x + 8, input.position.y, input.size.x - 16, input.size.y), modal_text, 14, C_TEXT)
		var caret_x := input.position.x + 8.0 + _serif_width(modal_text, 14, false) + 2.0
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
			13,
			C_TEXT,
			true
		)
		_hint(_box(body.position.x + 12, body.position.y + 74, body.size.x - 24, 18), "ESTA ACCIÓN NO SE PUEDE DESHACER")
	else:
		_text(
			_box(body.position.x + 12, body.position.y + 30, body.size.x - 24, 24),
			"¿DESCARTAR CAMBIOS SIN APLICAR?",
			13,
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
	_bevel(rect, false, 1)
	var cap_w := _title_width(caption, 10) + 14.0
	draw_rect(Rect2(rect.position.x + 16, rect.position.y, cap_w, 2), C_FACE)
	_text_title(_box(rect.position.x + 22, rect.position.y - 6, cap_w, 13), caption, 10, C_TEXT)


func _group_inner(rect: Rect2) -> Rect2:
	return Rect2(rect.position.x + 14, rect.position.y + 20, rect.size.x - 28, rect.size.y - 34)


func _row_frame(
	rect: Rect2, selected: bool, last: bool, hovered: bool, base: Color = C_FACE
) -> void:
	var background := base
	if selected:
		background = C_SEL
	elif hovered:
		background = C_FACE_HI
	draw_rect(rect, background)
	if selected:
		draw_rect(Rect2(rect.position.x, rect.position.y, 3, rect.size.y), C_GOLD)
		draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 1), C_GOLD)
		draw_rect(Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1), C_GOLD)
		draw_rect(Rect2(rect.end.x - 1, rect.position.y, 1, rect.size.y), C_GOLD)
	if not last:
		draw_rect(Rect2(rect.position.x, rect.end.y - 2, rect.size.x, 1), C_SHADOW)
		draw_rect(Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1), C_LIGHT)


func _bevel(rect: Rect2, raised: bool, thick: int = 2) -> void:
	for i in thick:
		var top_color: Color
		var bottom_color: Color
		if i == 0:
			top_color = C_HI if raised else C_SHADOW
			bottom_color = C_DARK if raised else C_HI
		else:
			top_color = C_LIGHT if raised else C_DARK
			bottom_color = C_SHADOW if raised else C_LIGHT
		draw_rect(Rect2(rect.position.x + i, rect.position.y + i, rect.size.x - i * 2, 1), top_color)
		draw_rect(Rect2(rect.position.x + i, rect.position.y + i, 1, rect.size.y - i * 2), top_color)
		draw_rect(Rect2(rect.position.x + i, rect.end.y - 1 - i, rect.size.x - i * 2, 1), bottom_color)
		draw_rect(Rect2(rect.end.x - 1 - i, rect.position.y + i, 1, rect.size.y - i * 2), bottom_color)


func _sunken(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 1), C_SHADOW)
	draw_rect(Rect2(rect.position.x, rect.position.y, 1, rect.size.y), C_SHADOW)
	draw_rect(Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1), C_HI)
	draw_rect(Rect2(rect.end.x - 1, rect.position.y, 1, rect.size.y), C_HI)


func _field_box(rect: Rect2, text: String, size: int, color: Color, numeric: bool = true) -> void:
	draw_rect(rect, C_FIELD)
	_sunken(rect)
	var inner := _box(rect.position.x + 6, rect.position.y, rect.size.x - 12, rect.size.y)
	if numeric:
		_num(inner, text, size, color, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 12)
	else:
		_text(inner, text, size, color, true, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 12)


func _stepper(rect: Rect2, plus: bool) -> void:
	var hovered := _mouse_over(rect)
	draw_rect(rect, C_FACE_HI if hovered else C_FACE)
	_bevel(rect, true, 2)
	var cx: float = round(rect.get_center().x)
	var cy: float = round(rect.get_center().y)
	var glyph: Color = C_TEXT
	draw_rect(Rect2(cx - 4, cy - 1, 9, 2), glyph)
	if plus:
		draw_rect(Rect2(cx - 1, cy - 4, 2, 9), glyph)


func _track(rect: Rect2, fraction: float, selected: bool) -> void:
	draw_rect(rect, C_FIELD)
	_sunken(rect)
	var inner := rect.grow(-2.0)
	var fill_w: float = maxf(inner.size.x * clampf(fraction, 0.0, 1.0), 2.0)
	draw_rect(Rect2(inner.position, Vector2(fill_w, inner.size.y)), Color(C_BLUE_DEEP, 0.95))
	draw_rect(
		Rect2(inner.position, Vector2(fill_w, maxf(floorf(inner.size.y * 0.5), 1.0))),
		Color(C_BLUE, 0.5),
		false
	)
	for i in 4:
		var tx := inner.position.x + inner.size.x * (0.2 + 0.2 * float(i))
		if tx > inner.position.x + fill_w + 1.0:
			draw_rect(Rect2(tx, inner.position.y, 1, inner.size.y), Color(C_SHADOW, 0.55))

	var thumb := Rect2(inner.position.x + fill_w - 7.0, rect.position.y - 6.0, 14.0, rect.size.y + 12.0)
	draw_rect(Rect2(thumb.position + Vector2(1, 1), thumb.size), Color(0, 0, 0, 0.35))
	draw_rect(thumb, C_FACE)
	_bevel(thumb, true, 2)
	if selected:
		draw_rect(Rect2(thumb.position.x, thumb.position.y, thumb.size.x, 2), C_GOLD)


func _radio(rect: Rect2, label: String, on: bool) -> void:
	var radius := 6.0
	var center := Vector2(rect.position.x + radius + 1.0, rect.position.y + rect.size.y * 0.5)
	draw_circle(center, radius, C_FIELD)
	draw_arc(center, radius, 0.0, TAU, 20, C_SHADOW, 1.0)
	draw_arc(center + Vector2(1, 1), radius - 1.0, PI * 1.05, PI * 1.55, 8, C_LIGHT, 1.0)
	if on:
		draw_circle(center, radius - 3.5, C_TEXT)
	_text(
		_box(rect.position.x + 18, rect.position.y, rect.size.x - 18, rect.size.y),
		label,
		11,
		C_TEXT if on else C_DIM,
		on
	)


func _toggle(rect: Rect2, label: String, on: bool) -> void:
	draw_rect(rect, C_FACE_LO if on else C_FACE_HI)
	_bevel(rect, not on, 2)
	_text(
		_box(rect.position.x, rect.position.y, rect.size.x, rect.size.y),
		label,
		10,
		C_TEXT if on else C_DIM,
		on,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _segment_button(rect: Rect2, label: String, active: bool) -> void:
	draw_rect(rect, C_FACE_LO if active else C_FACE_HI)
	_bevel(rect, not active, 2)
	if active:
		draw_rect(Rect2(rect.position.x + 3, rect.end.y - 3, rect.size.x - 6, 2), C_BLUE)
	_text_title(
		_box(rect.position.x, rect.position.y, rect.size.x, rect.size.y),
		label,
		11,
		C_TEXT if active else C_DIM,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _classic_button(rect: Rect2, label: String, action: String, modal: bool = false) -> void:
	var fill := C_FACE_HI.lightened(0.12) if _mouse_over(rect) else C_FACE_HI
	draw_rect(rect, fill)
	_bevel(rect, true, 2)
	_text(
		_box(rect.position.x, rect.position.y - 1, rect.size.x, rect.size.y),
		label,
		11,
		C_TEXT,
		true,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_hit_regions.append({ "rect": rect, "kind": "button", "action": action, "modal": modal })


func _hint(rect: Rect2, text: String) -> void:
	_text(rect, text, 9, Color(C_DIM, 0.9))


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

	_text(
		_box(rect.position.x + 12, rect.position.y, 236, rect.size.y),
		label,
		11,
		C_TEXT if selected else C_DIM,
		selected
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

	_field_box(field_rect, _format_field(field, path), 12, C_GOLD if selected else C_TEXT)
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
# PRIMITIVAS AERO
# =============================================================================


func _glass_window(rect: Rect2, radius: int) -> void:
	for i in 3:
		var shadow := StyleBoxFlat.new()
		shadow.bg_color = Color(0, 0, 0, 0)
		shadow.border_color = Color(0, 0, 0, 0.16 - float(i) * 0.045)
		shadow.set_border_width_all(1)
		shadow.set_corner_radius_all(radius + i * 2)
		draw_style_box(
			shadow,
			Rect2(rect.position - Vector2(i, i - 3), rect.size + Vector2(i * 2, i * 2 + 4))
		)
	_glass_box(rect, radius, Color(C_GLASS, 0.94), Color(C_RIM, 0.30), 0.13)


func _glass_box(rect: Rect2, radius: int, fill: Color, rim: Color, gloss_alpha: float) -> void:
	var base := StyleBoxFlat.new()
	base.bg_color = fill
	base.border_color = rim
	base.set_border_width_all(1)
	base.set_corner_radius_all(radius)
	draw_style_box(base, rect)

	if gloss_alpha > 0.0 and rect.size.y > 10.0:
		_gloss(rect, radius, minf(rect.size.y * 0.5, rect.size.y - 2.0), gloss_alpha)

	var inner := StyleBoxFlat.new()
	inner.bg_color = Color(0, 0, 0, 0)
	inner.border_color = Color(1.0, 1.0, 1.0, minf(0.28, gloss_alpha * 1.8))
	inner.border_width_top = 1
	inner.set_corner_radius_all(maxi(radius - 1, 1))
	draw_style_box(inner, rect.grow(-1.0))


# Degradado vertical recortado a las esquinas: separa el cristal de una banda
# blanca plana, que era lo que aplanaba la jerarquía en la versión anterior.
func _gloss(rect: Rect2, radius: int, height: float, alpha: float) -> void:
	var top_y := rect.position.y
	var bottom := top_y + height
	var r: float = minf(float(radius), minf(rect.size.x * 0.5, height))
	var points := PackedVector2Array()
	var colors := PackedColorArray()

	points.append(Vector2(rect.position.x + 1.0, bottom))
	colors.append(Color(1, 1, 1, 0.0))
	points.append(Vector2(rect.position.x + 1.0, top_y + r))
	colors.append(Color(1, 1, 1, alpha))
	for i in 8:
		var angle: float = PI + PI * 0.5 * (float(i) / 7.0)
		var point := Vector2(rect.position.x + r + cos(angle) * r, top_y + r + sin(angle) * r)
		points.append(point)
		colors.append(
			Color(1, 1, 1, alpha * (1.0 - clampf((point.y - top_y) / maxf(height, 1.0), 0.0, 1.0)))
		)
	for i in 8:
		var angle: float = -PI * 0.5 + PI * 0.5 * (float(i) / 7.0)
		var point := Vector2(rect.end.x - r + cos(angle) * r, top_y + r + sin(angle) * r)
		points.append(point)
		colors.append(
			Color(1, 1, 1, alpha * (1.0 - clampf((point.y - top_y) / maxf(height, 1.0), 0.0, 1.0)))
		)
	points.append(Vector2(rect.end.x - 1.0, top_y + r))
	colors.append(Color(1, 1, 1, alpha))
	points.append(Vector2(rect.end.x - 1.0, bottom))
	colors.append(Color(1, 1, 1, 0.0))
	draw_polygon(points, colors)


func _glow(rect: Rect2, radius: int, color: Color) -> void:
	for i in 3:
		var ring := StyleBoxFlat.new()
		ring.bg_color = Color(0, 0, 0, 0)
		ring.border_color = Color(color.r, color.g, color.b, color.a * (0.55 - float(i) * 0.16))
		ring.set_border_width_all(2)
		ring.set_corner_radius_all(radius + i * 2 + 1)
		draw_style_box(ring, rect.grow(float(i) * 2.0 + 1.0))


func _chrome_button(rect: Rect2, label: String, action: String) -> void:
	var hovered := _mouse_over(rect)
	_glass_box(rect, 7, Color(C_GLASS, 0.92), Color(C_RIM, 0.32), 0.12)
	if hovered:
		_glow(rect, 7, Color(C_BLUE, 0.28))
	_text_serif(
		_box(rect.position.x, rect.position.y, rect.size.x, rect.size.y),
		label,
		12,
		C_CHROME_TEXT,
		false,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_hit_regions.append({ "rect": rect, "kind": "button", "action": action })


func _gold_button(rect: Rect2, label: String, action: String, modal: bool = false) -> void:
	var hovered := _mouse_over(rect)
	_glow(rect, 7, Color(C_GOLD, 0.7 if hovered else 0.5))
	_glass_box(rect, 7, Color("#b8862a"), C_GOLD_HI, 0.32 if not hovered else 0.4)
	_text_serif(
		_box(rect.position.x, rect.position.y - 1, rect.size.x, rect.size.y),
		label,
		12,
		Color("#1a1206"),
		true,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_focus_dots(rect.grow(-5.0), Color("#1a1206"))
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
# Texto general en Libron; los números y sus unidades usan D-DIN.
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
	return FONT_TITLE.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


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


# Ancho medido con la fuente real del texto general (Libron).
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
