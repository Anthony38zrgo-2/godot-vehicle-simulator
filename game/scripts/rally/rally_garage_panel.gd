class_name RallyGaragePanel
extends Control

signal garage_closed(applied: bool)

const LOGICAL_SIZE := Vector2(1280.0, 800.0)

const FONT_REGULAR: Font = preload("res://fonts/libron/Libron-Regular.ttf")
const FONT_BOLD: Font = preload("res://fonts/libron/Libron-Bold.ttf")
const FONT_DIN_REGULAR: Font = preload("res://fonts/D-DIN.ttf")
const FONT_DIN_BOLD: Font = preload("res://fonts/D-DIN-Bold.ttf")

# --- Recalibrated Motorsport Palette ---
const C_BG := Color("#111518")
const C_PANEL := Color("#171e24")
const C_PANEL_ALT := Color("#1f2730")
const C_PANEL_HOVER := Color("#27333e")
const C_BORDER := Color("#2c3842")
const C_BORDER_FOCUS := Color("#4c6475")
const C_STEEL := Color("#4a7187")
const C_STEEL_DARK := Color("#232c35")
const C_GOLD := Color("#e3b23c")
const C_GOLD_BRIGHT := Color("#f5c449")
const C_WHITE := Color("#edf0ee")
const C_MUTED := Color("#879aa4")
const C_RED := Color("#e0534a")
const C_GREEN := Color("#44b365")
const C_SLIDER_TRACK := Color("#12161a")
const C_SLIDER_FILL := Color("#395768")

const PAD_NAME_CHARACTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_"

@export var vehicle_path: NodePath
@export var input_controller_path: NodePath
@export_enum("rally", "gp") var mode: String = "rally"
@export var circuit_id: String = "russia-stage-1"
@export var circuit_name: String = "Rusia Stage 1"
@export var circuit_country: String = "Russia"
@export var circuit_length_m: float = 5500.0
@export var team_id: String = "ford-rally-works"
@export var team_name: String = "Ford Rally Works"

var vehicle: RallyEscortVehicle
var input_controller: RallyVehicleInputController
var database := RallySetupDatabase.new()
var database_ready: bool = false
var database_status: String = "Conectando SQLite..."
var page: int = 0
var selected_field_path: String = ""
var selected_setup_index: int = 0
var selected_setup_id: int = -1
var setup_scroll_offset: int = 0
var pad_character_index: int = 0
var active_setup_id: int = -1
var active_setup_name: String = "Ajuste actual"
var setup_rows: Array[Dictionary] = []
var draft_values: Dictionary = {}
var opening_values: Dictionary = {}
var pending_values: Dictionary = {}
var new_tires_service: bool = false
var modal_mode: String = ""
var modal_text: String = ""
var notice: String = ""
var notice_time: float = 0.0
var draft_compound_id: String = "gravel_normal"
var opening_compound_id: String = "gravel_normal"
var confirmed_compound_id: String = "gravel_normal"
var compound_change_allowed: bool = true
var mandatory_confirmation: bool = false
var forecast_summary: String = ""
var forecast_advice: String = ""
var setup_window_label: String = ""
var compound_catalog: Dictionary = {}
var draft_spare_wheels: int = 1
var opening_spare_wheels: int = 1
var draft_wheel_compounds: Dictionary = {
	"FL": "gravel_normal",
	"FR": "gravel_normal",
	"RL": "gravel_normal",
	"RR": "gravel_normal"
}
var opening_wheel_compounds: Dictionary = {
	"FL": "gravel_normal",
	"FR": "gravel_normal",
	"RL": "gravel_normal",
	"RR": "gravel_normal"
}
var _hit_regions: Array[Dictionary] = []
var _page_field_paths: Array[String] = []
var _canvas_scale: float = 1.0
var _canvas_offset: Vector2 = Vector2.ZERO
var _restore_tree_paused: bool = false
var _restore_controls_enabled: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_process_input(false)
	if vehicle == null and not vehicle_path.is_empty():
		vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	input_controller = get_node_or_null(input_controller_path) as RallyVehicleInputController
	if input_controller != null and not input_controller.garage_menu_requested.is_connected(open_garage):
		input_controller.garage_menu_requested.connect(open_garage)
	var opened := database.open_database()
	database_ready = bool(opened.get("ok", false))
	database_status = str(opened.get("path", "SQLite no disponible")) if database_ready else str(opened.get("error", "Error SQLite"))
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


func open_garage() -> void:
	open_garage_for_event({})


func open_garage_for_event(options: Dictionary = {}) -> void:
	if vehicle == null and not vehicle_path.is_empty():
		vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	if visible or vehicle == null:
		return
	_restore_tree_paused = get_tree().paused
	_restore_controls_enabled = input_controller.controls_enabled if input_controller != null else true
	opening_values = RallySetupCatalog.defaults(vehicle.simulation.domains)
	opening_values["fuel.initial_kg"] = vehicle.simulation.thermal_model.fuel_remaining_litres * vehicle.simulation.mass_model.fuel_density_kg_per_litre
	draft_values = opening_values.duplicate(true)
	pending_values = {}
	new_tires_service = false
	opening_compound_id = vehicle.get_tire_compound() if vehicle.has_method("get_tire_compound") else "gravel_normal"
	draft_compound_id = str(options.get("compound_id", opening_compound_id))
	if draft_compound_id == "":
		draft_compound_id = opening_compound_id
	confirmed_compound_id = opening_compound_id
	compound_change_allowed = bool(options.get("compound_change_allowed", true))
	mandatory_confirmation = bool(options.get("confirmation_required", false))
	forecast_summary = str(options.get("forecast_summary", ""))
	forecast_advice = str(options.get("forecast_advice", ""))
	setup_window_label = str(options.get("window_label", ""))
	compound_catalog = RallyTireCompound.load_catalog() if FileAccess.file_exists(RallyTireCompound.CATALOG_PATH) else {}
	
	draft_spare_wheels = int(options.get("spare_wheels", 1))
	opening_spare_wheels = draft_spare_wheels
	var initial_wheel_compounds: Dictionary = options.get("wheel_compounds", {})
	draft_wheel_compounds = {
		"FL": str(initial_wheel_compounds.get("FL", draft_compound_id)),
		"FR": str(initial_wheel_compounds.get("FR", draft_compound_id)),
		"RL": str(initial_wheel_compounds.get("RL", draft_compound_id)),
		"RR": str(initial_wheel_compounds.get("RR", draft_compound_id))
	}
	opening_wheel_compounds = draft_wheel_compounds.duplicate()
	
	var initial_tab := str(options.get("initial_tab", ""))
	if initial_tab == "tires":
		page = 1
	elif initial_tab == "strategy":
		page = 3
	else:
		page = int(options.get("initial_page", 0))
	selected_field_path = ""
	_set_page(page)
	active_setup_id = -1
	active_setup_name = "Ajuste actual"
	modal_mode = ""
	modal_text = ""
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
	if mandatory_confirmation and not apply_changes and not confirmed_discard:
		_show_notice("Confirma el reglaje para iniciar (Aceptar).", true)
		return
	if not apply_changes and _has_unapplied_changes() and not confirmed_discard:
		modal_mode = "discard"
		queue_redraw()
		return
	if apply_changes:
		if draft_compound_id != opening_compound_id and not compound_change_allowed:
			_show_notice("Cambio de compuesto bloqueado fuera de ventana de servicio.", true)
			return
		var applied := vehicle.apply_setup_values(draft_values)
		if not bool(applied.get("ok", false)):
			_show_notice(str(applied.get("error", "No se pudo aplicar el reglaje.")), true)
			return
		
		var wet_count := 0
		for w in draft_wheel_compounds.values():
			if w == "gravel_wet":
				wet_count += 1
		draft_compound_id = "gravel_wet" if wet_count >= 2 else "gravel_normal"
		
		if draft_compound_id != opening_compound_id:
			vehicle.set_tire_compound(draft_compound_id)
			vehicle.service_new_tires(draft_compound_id)
			confirmed_compound_id = draft_compound_id
		elif new_tires_service:
			vehicle.service_new_tires(vehicle.get_tire_compound())
	else:
		vehicle.apply_setup_values(opening_values)
		if vehicle.has_method("get_tire_compound") and vehicle.get_tire_compound() != opening_compound_id:
			vehicle.set_tire_compound(opening_compound_id)
	visible = false
	set_process_input(false)
	get_tree().paused = _restore_tree_paused
	if input_controller != null:
		input_controller.set_controls_enabled(_restore_controls_enabled)
	garage_closed.emit(apply_changes)
	queue_redraw()


func get_confirmed_setup() -> Dictionary:
	return {
		"compound_id": confirmed_compound_id if not visible else draft_compound_id,
		"wheel_compounds": draft_wheel_compounds.duplicate(),
		"spare_wheels": draft_spare_wheels,
		"values": draft_values.duplicate(true),
		"confirmed": not visible
	}


func _has_unapplied_changes() -> bool:
	return draft_values != opening_values or new_tires_service or draft_compound_id != opening_compound_id or draft_spare_wheels != opening_spare_wheels or draft_wheel_compounds != opening_wheel_compounds


func _input(event: InputEvent) -> void:
	if not visible:
		if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN] and is_instance_valid(vehicle) and not get_tree().paused:
			vehicle.simulation.adjust_live_tire_pressure(5.0 if event.keycode == KEY_PAGEUP else -5.0)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)
		accept_event()
	elif event is InputEventJoypadButton and event.pressed:
		_handle_pad_button(event as InputEventJoypadButton)
		accept_event()
	elif event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(_to_logical(mouse_event.position))
			accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_page(page - 1)
			accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_page(page + 1)
			accept_event()


func _handle_key(event: InputEventKey) -> void:
	if modal_mode == "name":
		if event.keycode == KEY_ESCAPE:
			modal_mode = ""
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_commit_new_setup()
		elif event.keycode == KEY_BACKSPACE:
			modal_text = modal_text.left(maxi(0, modal_text.length() - 1))
		elif event.unicode > 0 and modal_text.length() < 100:
			modal_text += String.chr(event.unicode)
		queue_redraw()
		return
	if modal_mode == "delete":
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_delete_selected_setup()
		elif event.keycode == KEY_ESCAPE:
			modal_mode = ""
		queue_redraw()
		return
	if modal_mode == "discard":
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
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
		KEY_C:
			if page == 3 or page == 1:
				_select_compound("gravel_wet" if draft_compound_id == "gravel_normal" else "gravel_normal")
		KEY_PAGEUP:
			_set_page(page - 1)
		KEY_PAGEDOWN:
			_set_page(page + 1)
		KEY_LEFT:
			_adjust_selected(-1.0)
		KEY_RIGHT:
			_adjust_selected(1.0)
		KEY_UP:
			_navigate_selection(-1)
		KEY_DOWN:
			_navigate_selection(1)
		KEY_TAB:
			_navigate_selection(1)
		KEY_DELETE:
			if page == 4:
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
				if modal_text.length() < 100:
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
		if event.button_index == JOY_BUTTON_START or event.button_index == JOY_BUTTON_A:
			_delete_selected_setup()
		elif event.button_index == JOY_BUTTON_B:
			modal_mode = ""
		queue_redraw()
		return
	if modal_mode == "discard":
		if event.button_index == JOY_BUTTON_START or event.button_index == JOY_BUTTON_A:
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


func _handle_click(point: Vector2) -> void:
	for index in range(_hit_regions.size() - 1, -1, -1):
		var region: Dictionary = _hit_regions[index]
		if not (region.rect as Rect2).has_point(point):
			continue
		match str(region.kind):
			"tab":
				_set_page(int(region.page))
			"field":
				selected_field_path = str(region.path)
				if bool(region.slider):
					var track_box: Rect2 = region.get("track", region.rect as Rect2)
					_set_from_slider(str(region.path), point.x, track_box)
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
			"compound":
				_select_compound(str(region.compound_id))
			"spare_wheels":
				draft_spare_wheels = int(region.count)
			"wheel_compound":
				var w_id: String = str(region.wheel)
				var c_id: String = str(region.compound_id)
				if compound_change_allowed:
					draft_wheel_compounds[w_id] = c_id
					# Update global compound reference to majority
					var wet_c := 0
					for comp in draft_wheel_compounds.values():
						if comp == "gravel_wet":
							wet_c += 1
					draft_compound_id = "gravel_wet" if wet_c >= 2 else "gravel_normal"
				else:
					_show_notice("Cambio de compuesto bloqueado fuera de servicio.", true)
			"all_compounds":
				var all_cid: String = str(region.compound_id)
				if compound_change_allowed:
					for w_k in draft_wheel_compounds.keys():
						draft_wheel_compounds[w_k] = all_cid
					draft_compound_id = all_cid
				else:
					_show_notice("Cambio de compuesto bloqueado fuera de servicio.", true)
		queue_redraw()
		return


func _select_compound(compound_id: String) -> void:
	if not compound_change_allowed:
		_show_notice("Cambio de compuesto bloqueado fuera de ventana de servicio.", true)
		return
	if compound_id in ["gravel_normal", "gravel_wet"]:
		draft_compound_id = compound_id
		for k in draft_wheel_compounds.keys():
			draft_wheel_compounds[k] = compound_id
		queue_redraw()


func _set_page(next_page: int) -> void:
	page = posmod(next_page, RallySetupCatalog.PAGE_TITLES.size())
	var fields := RallySetupCatalog.fields_for_page(page)
	_page_field_paths.clear()
	for field in fields:
		var path: String = field.path
		if not _page_field_paths.has(path):
			_page_field_paths.append(path)
	for extra_path in (["steering.max_steering_angle"] if page == 0 else []):
		if not _page_field_paths.has(extra_path):
			_page_field_paths.append(extra_path)
	if not _page_field_paths.has(selected_field_path):
		selected_field_path = _page_field_paths[0] if not _page_field_paths.is_empty() else ""
	if page == 4:
		_refresh_setups()
	queue_redraw()


func _navigate_selection(direction: int) -> void:
	if page == 4:
		if setup_rows.is_empty():
			selected_setup_index = 0
		else:
			selected_setup_index = posmod(selected_setup_index + direction, setup_rows.size())
			selected_setup_id = int(setup_rows[selected_setup_index].get("id", -1))
			if selected_setup_index < setup_scroll_offset:
				setup_scroll_offset = selected_setup_index
			elif selected_setup_index >= setup_scroll_offset + 7:
				setup_scroll_offset = selected_setup_index - 6
		return
	if _page_field_paths.is_empty():
		_set_page(page)
		return
	var index := _page_field_paths.find(selected_field_path)
	selected_field_path = _page_field_paths[posmod(index + direction, _page_field_paths.size())]


func _adjust_selected(direction: float) -> void:
	if page == 4:
		_navigate_selection(int(direction))
		return
	if selected_field_path.is_empty() and not _page_field_paths.is_empty():
		selected_field_path = _page_field_paths[0]
	_adjust_field(selected_field_path, direction)


func _adjust_field(path: String, direction: float) -> void:
	var field := RallySetupCatalog.field_for_path(path)
	if field.is_empty():
		return
	var current := float(draft_values.get(path, 0.0))
	var next_value := current + float(field.step) * direction
	_update_value(path, next_value)


func _set_from_slider(path: String, x: float, track: Rect2) -> void:
	var field := RallySetupCatalog.field_for_path(path)
	if field.is_empty():
		return
	var normalized := clampf((x - track.position.x) / maxf(track.size.x, 1.0), 0.0, 1.0)
	var value := lerpf(float(field.min), float(field.max), normalized)
	_update_value(path, value)


func _update_value(path: String, value: float) -> void:
	var field := RallySetupCatalog.field_for_path(path)
	if field.is_empty():
		return
	var max_val := float(field.max)
	# Engine RPM ceiling constraint: strictly respect engine maximum
	if path == "powertrain.max_rpm":
		max_val = minf(max_val, 7200.0)
	var clamped := snappedf(clampf(value, float(field.min), max_val), float(field.step))
	draft_values[path] = clamped
	var result := vehicle.apply_setup_values(draft_values)
	if not bool(result.get("ok", false)):
		_show_notice(str(result.get("error", "No se pudo actualizar el coche.")), true)
	else:
		draft_values = result.values
	queue_redraw()


func _confirm_selection() -> void:
	if page == 3:
		new_tires_service = not new_tires_service
	elif page == 4:
		_load_selected_setup()
	elif selected_field_path.is_empty() and not _page_field_paths.is_empty():
		selected_field_path = _page_field_paths[0]
	queue_redraw()


func _run_button(action: String) -> void:
	match action:
		"reset":
			draft_values = vehicle.simulation.setup_design_values.duplicate(true)
			active_setup_id = -1
			active_setup_name = "Ajuste de fabrica"
			vehicle.apply_setup_values(draft_values)
			_show_notice("Valores de fabrica restaurados.")
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


func _refresh_setups() -> void:
	if not database_ready or vehicle == null:
		setup_rows.clear()
		return
	var result := database.list_setups(_database_context())
	if not bool(result.get("ok", false)):
		database_status = str(result.get("error", "Error al consultar la base."))
		setup_rows.clear()
		return
	setup_rows.clear()
	for row in result.get("rows", []):
		if row is Dictionary:
			setup_rows.append(row)
	if selected_setup_index >= setup_rows.size():
		selected_setup_index = maxi(setup_rows.size() - 1, 0)
	setup_scroll_offset = clampi(setup_scroll_offset, 0, maxi(setup_rows.size() - 7, 0))
	selected_setup_id = int(setup_rows[selected_setup_index].get("id", -1)) if not setup_rows.is_empty() else -1


func _save_selected_setup() -> void:
	if not database_ready:
		_show_notice("SQLite no esta disponible: " + database_status, true)
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
		modal_text = active_setup_name if active_setup_name != "Ajuste actual" else ""
		return
	var result := database.update_setup(_database_context(), target_id, target_name, draft_values)
	if bool(result.get("ok", false)):
		active_setup_id = target_id
		active_setup_name = target_name
		_show_notice("Reglaje guardado en SQLite.")
		_refresh_setups()
	else:
		_show_notice(str(result.get("error", "No se pudo guardar.")), true)


func _commit_new_setup() -> void:
	var setup_name := modal_text.strip_edges()
	if setup_name.is_empty():
		_show_notice("El nombre del reglaje no puede quedar vacio.", true)
		return
	var result := database.create_setup(_database_context(), setup_name, draft_values)
	modal_mode = ""
	if bool(result.get("ok", false)):
		active_setup_id = int(result.get("id", -1))
		active_setup_name = setup_name
		selected_setup_id = active_setup_id
		_show_notice("Nuevo reglaje guardado.")
		_refresh_setups()
	else:
		_show_notice(str(result.get("error", "No se pudo crear el reglaje.")), true)
	queue_redraw()


func _load_selected_setup() -> void:
	if selected_setup_id < 0:
		_show_notice("Selecciona un reglaje para cargar.", true)
		return
	var result := database.load_setup(_database_context(), selected_setup_id)
	if not bool(result.get("ok", false)):
		_show_notice(str(result.get("error", "No se pudo cargar el reglaje.")), true)
		return
	var loaded_values: Dictionary = result.get("values", {})
	var validation := RallySetupCatalog.validate(loaded_values)
	if not bool(validation.get("ok", false)):
		_show_notice(str(validation.get("error", "Reglaje incompatible.")), true)
		return
	draft_values = validation.values
	var applied := vehicle.apply_setup_values(draft_values)
	if bool(applied.get("ok", false)):
		draft_values = applied.values
		active_setup_id = selected_setup_id
		active_setup_name = str(result.get("name", "Reglaje cargado"))
		_show_notice("Reglaje cargado y aplicado.")
	else:
		_show_notice(str(applied.get("error", "Error al aplicar.")), true)
	page = 0
	_set_page(page)


func _begin_delete_setup() -> void:
	if selected_setup_id < 0:
		_show_notice("Selecciona un reglaje para borrar.", true)
		return
	modal_mode = "delete"
	queue_redraw()


func _delete_selected_setup() -> void:
	var result := database.delete_setup(_database_context(), selected_setup_id)
	modal_mode = ""
	if bool(result.get("ok", false)):
		if active_setup_id == selected_setup_id:
			active_setup_id = -1
			active_setup_name = "Ajuste actual"
		_show_notice("Reglaje eliminado.")
		_refresh_setups()
	else:
		_show_notice(str(result.get("error", "No se pudo borrar.")), true)
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
	notice_time = 3.0
	queue_redraw()


func _process(delta: float) -> void:
	if notice_time > 0.0:
		notice_time -= delta
		if notice_time <= 0.0:
			notice = ""
			queue_redraw()


func _to_logical(point: Vector2) -> Vector2:
	if _canvas_scale <= 0.0:
		return point
	return (point - _canvas_offset) / _canvas_scale


# ==============================================================================
# DRAWING ROUTINES
# ==============================================================================

func _draw() -> void:
	_hit_regions.clear()
	if not visible:
		return
	if _canvas_scale <= 0.0:
		_resize_canvas()
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	draw_set_transform(_canvas_offset, 0.0, Vector2.ONE * _canvas_scale)
	draw_rect(Rect2(Vector2.ZERO, LOGICAL_SIZE), C_BG)
	_draw_header()
	_draw_tabs()
	match page:
		0:
			_draw_suspension_page()
		1:
			_draw_wheels_page()
		2:
			_draw_powertrain_page()
		3:
			_draw_strategy_page()
		4:
			_draw_setups_page()
	_draw_footer()
	if modal_mode != "":
		_draw_modal()
	if notice_time > 0.0 and not notice.is_empty():
		_draw_notice()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_header() -> void:
	var rect := Rect2(24.0, 18.0, 1232.0, 70.0)
	_draw_panel(rect, C_PANEL, C_BORDER)
	draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 3.0), C_GOLD)
	
	_draw_text(Vector2(46.0, 48.0), "GRUPO 4 - GARAJE", 18, C_GOLD, true)
	_draw_text(Vector2(46.0, 68.0), "PARC FERMÉ  ·  SETUP Y ESTRATEGIA DE COMPETICIÓN", 10, C_WHITE, true)
	
	_draw_line(Vector2(380.0, 30.0), Vector2(380.0, 76.0), C_BORDER, 1.0)
	
	_draw_text(Vector2(404.0, 48.0), "FORD ESCORT RS2000 (1971)", 16, C_WHITE, true)
	_draw_text(Vector2(404.0, 68.0), circuit_name.to_upper() + "  ·  " + circuit_country.to_upper(), 11, C_MUTED)
	
	_draw_text(Vector2(rect.end.x - 20.0, 48.0), "MODO " + mode.to_upper(), 13, C_GOLD, true, HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_text(Vector2(rect.end.x - 20.0, 68.0), "SETUP: " + active_setup_name.to_upper(), 11, C_MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_tabs() -> void:
	var titles: Array = RallySetupCatalog.PAGE_TITLES
	var x := 24.0
	var gap := 6.0
	var width := (1232.0 - gap * 4.0) / 5.0
	var y := 100.0
	var height := 44.0
	for index in titles.size():
		var rect := Rect2(x + float(index) * (width + gap), y, width, height)
		var active := index == page
		_draw_rect(rect, C_PANEL_ALT if active else C_PANEL, true)
		_draw_rect(rect, C_BORDER_FOCUS if active else C_BORDER, false, 1.0)
		if active:
			draw_rect(Rect2(rect.position.x, rect.end.y - 3.0, rect.size.x, 3.0), C_GOLD)
		_draw_text(rect.get_center() + Vector2(0.0, 4.0), str(titles[index]), 12, C_GOLD if active else C_MUTED, active, HORIZONTAL_ALIGNMENT_CENTER)
		_hit_regions.append({"rect": rect, "kind": "tab", "page": index})


func _draw_suspension_page() -> void:
	var y := 158.0
	var h := 524.0
	var col_w := 370.0
	
	# Left Column: Front Damper & Spring (6) + Front ARB (1)
	_draw_group_panel(Rect2(24.0, y, col_w, 360.0), "SUSPENSIÓN DELANTERA", _paths([
		"suspension.front.ride_frequency_hz",
		"suspension.front.resting_ratio",
		"suspension.front.damping_ratio",
		"suspension.front.bump_damp_multiplier",
		"suspension.front.rebound_damp_multiplier",
		"suspension.front.bump_stop_multiplier"
	]), 36.0)
	_draw_group_panel(Rect2(24.0, y + 372.0, col_w, 152.0), "BARRA ESTABILIZADORA DELANTERA", _paths([
		"suspension.geometry_physical.front_arb.ratio"
	]), 44.0)
	
	# Right Column: Rear Damper & Spring (6) + Rear ARB (1)
	var right_x := 1280.0 - 24.0 - col_w
	_draw_group_panel(Rect2(right_x, y, col_w, 360.0), "SUSPENSIÓN TRASERA", _paths([
		"suspension.rear.ride_frequency_hz",
		"suspension.rear.resting_ratio",
		"suspension.rear.damping_ratio",
		"suspension.rear.bump_damp_multiplier",
		"suspension.rear.rebound_damp_multiplier",
		"suspension.rear.bump_stop_multiplier"
	]), 36.0)
	_draw_group_panel(Rect2(right_x, y + 372.0, col_w, 152.0), "BARRA ESTABILIZADORA TRASERA", _paths([
		"suspension.geometry_physical.rear_arb.ratio"
	]), 44.0)
	
	# Center Column: Chassis Balance and Steering Angle (Rally schematic, no F1 silhouette)
	var center_x := 24.0 + col_w + 16.0
	var center_w := right_x - center_x - 16.0
	var center_rect := Rect2(center_x, y, center_w, h)
	_draw_chassis_balance_card(center_rect)


func _draw_chassis_balance_card(rect: Rect2) -> void:
	_draw_panel(rect, C_PANEL, C_BORDER)
	_draw_text(Vector2(rect.get_center().x, rect.position.y + 26.0), "BALANCE DEL CHASIS Y DIRECCIÓN", 13, C_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text(Vector2(rect.get_center().x, rect.position.y + 44.0), "DISTRIBUCIÓN ESTÁTICA Y BALANCE DE EJES", 10, C_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	
	var card_cx := rect.get_center().x
	var card_top := rect.position.y + 60.0
	
	# Technical Rally Chassis Schematic (Escort RS2000 Proportions)
	var sch_w := 140.0
	var sch_h := 240.0
	var sch_rect := Rect2(card_cx - sch_w * 0.5, card_top + 10.0, sch_w, sch_h)
	
	# Chassis Main Body Contour
	_draw_rect(sch_rect, Color(C_PANEL_ALT, 0.7), true)
	_draw_rect(sch_rect, C_STEEL, false, 1.5)
	
	# Front hood & cabin lines
	var front_y := sch_rect.position.y + 65.0
	var cabin_rear_y := sch_rect.position.y + 175.0
	_draw_line(Vector2(sch_rect.position.x + 10.0, front_y), Vector2(sch_rect.end.x - 10.0, front_y), C_BORDER_FOCUS, 1.0)
	_draw_line(Vector2(sch_rect.position.x + 10.0, cabin_rear_y), Vector2(sch_rect.end.x - 10.0, cabin_rear_y), C_BORDER_FOCUS, 1.0)
	_draw_line(Vector2(card_cx, sch_rect.position.y + 15.0), Vector2(card_cx, sch_rect.end.y - 15.0), Color(C_BORDER, 0.8), 1.0)
	
	# Axle lines
	var f_axle_y := sch_rect.position.y + 45.0
	var r_axle_y := sch_rect.position.y + 195.0
	_draw_line(Vector2(sch_rect.position.x - 18.0, f_axle_y), Vector2(sch_rect.end.x + 18.0, f_axle_y), C_GOLD, 2.0)
	_draw_line(Vector2(sch_rect.position.x - 18.0, r_axle_y), Vector2(sch_rect.end.x + 18.0, r_axle_y), C_STEEL, 2.0)
	
	# Wheel footprints
	var wh_w := 14.0
	var wh_h := 36.0
	_draw_rect(Rect2(sch_rect.position.x - 22.0, f_axle_y - wh_h * 0.5, wh_w, wh_h), C_GOLD, true)
	_draw_rect(Rect2(sch_rect.end.x + 8.0, f_axle_y - wh_h * 0.5, wh_w, wh_h), C_GOLD, true)
	_draw_rect(Rect2(sch_rect.position.x - 22.0, r_axle_y - wh_h * 0.5, wh_w, wh_h), C_WHITE, true)
	_draw_rect(Rect2(sch_rect.end.x + 8.0, r_axle_y - wh_h * 0.5, wh_w, wh_h), C_WHITE, true)
	
	# Center of Gravity Badge (53% Front / 47% Rear)
	var cg_y := f_axle_y + (r_axle_y - f_axle_y) * 0.47
	draw_circle(Vector2(card_cx, cg_y), 7.0, C_GOLD)
	draw_circle(Vector2(card_cx, cg_y), 3.0, C_BG)
	_draw_line(Vector2(card_cx - 10.0, cg_y), Vector2(card_cx + 10.0, cg_y), C_GOLD, 1.0)
	_draw_line(Vector2(card_cx, cg_y - 10.0), Vector2(card_cx, cg_y + 10.0), C_GOLD, 1.0)
	_draw_text(Vector2(card_cx + 14.0, cg_y + 4.0), "CG 53 / 47", 10, C_GOLD, true)
	
	# Side telemetry readouts
	var f_freq := float(draft_values.get("suspension.front.ride_frequency_hz", 1.67))
	var r_freq := float(draft_values.get("suspension.rear.ride_frequency_hz", 1.70))
	_draw_text(Vector2(rect.position.x + 20.0, f_axle_y + 4.0), "%0.2f Hz" % f_freq, 12, C_GOLD, true, HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
	_draw_text(Vector2(rect.position.x + 20.0, f_axle_y - 12.0), "EJE DELANTERO", 9, C_MUTED, true)
	
	_draw_text(Vector2(rect.end.x - 20.0, f_axle_y + 4.0), "ARB %0.2f" % float(draft_values.get("suspension.geometry_physical.front_arb.ratio", 0.0)), 12, C_WHITE, true, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, true)
	_draw_text(Vector2(rect.end.x - 20.0, f_axle_y - 12.0), "ESTABILIZADORA", 9, C_MUTED, true, HORIZONTAL_ALIGNMENT_RIGHT)
	
	_draw_text(Vector2(rect.position.x + 20.0, r_axle_y + 4.0), "%0.2f Hz" % r_freq, 12, C_WHITE, true, HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
	_draw_text(Vector2(rect.position.x + 20.0, r_axle_y - 12.0), "EJE TRASERO", 9, C_MUTED, true)
	
	_draw_text(Vector2(rect.end.x - 20.0, r_axle_y + 4.0), "ARB %0.2f" % float(draft_values.get("suspension.geometry_physical.rear_arb.ratio", 0.0)), 12, C_WHITE, true, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, true)
	_draw_text(Vector2(rect.end.x - 20.0, r_axle_y - 12.0), "ESTABILIZADORA", 9, C_MUTED, true, HORIZONTAL_ALIGNMENT_RIGHT)
	
	# ARB Distribution Capsule Bar
	var arb_f := float(draft_values.get("suspension.geometry_physical.front_arb.ratio", 0.0))
	var arb_r := float(draft_values.get("suspension.geometry_physical.rear_arb.ratio", 0.0))
	var arb_tot := arb_f + arb_r
	var arb_ratio := arb_f / maxf(arb_tot, 0.001) if arb_tot > 0.001 else 0.5
	var bar_y := sch_rect.end.y + 24.0
	var bar_w := rect.size.x - 60.0
	var bar_x := rect.position.x + 30.0
	_draw_text(Vector2(bar_x, bar_y - 8.0), "BALANCE RIGIDEZ ANTIBALANCE (ARB)", 10, C_MUTED, true)
	_draw_text(Vector2(bar_x + bar_w, bar_y - 8.0), "%0.0f%% DEL  /  %0.0f%% TRAS" % [arb_ratio * 100.0, (1.0 - arb_ratio) * 100.0], 11, C_GOLD, true, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, true)
	_draw_capsule_bar(Vector2(bar_x, bar_y), bar_w, 8.0, C_SLIDER_TRACK)
	_draw_capsule_bar(Vector2(bar_x, bar_y), bar_w * arb_ratio, 8.0, C_GOLD)
	
	# Bottom field: Steering angle slider
	_draw_field_row(RallySetupCatalog.field_for_path("steering.max_steering_angle"), Rect2(rect.position.x + 18.0, rect.end.y - 62.0, rect.size.x - 36.0, 48.0))


func _draw_wheels_page() -> void:
	var y := 158.0
	var col_w := 350.0
	var wheel_h := 248.0
	var row_y1 := y
	var row_y2 := row_y1 + wheel_h + 16.0
	
	# Left: FL & RL
	_draw_group_panel(Rect2(24.0, row_y1, col_w, wheel_h), "DELANTERA IZQUIERDA (FL)", _paths([
		"tires.pressure.cold_kpa_gauge.FL",
		"suspension.front.camber",
		"suspension.front.toe"
	]), 44.0)
	_draw_group_panel(Rect2(24.0, row_y2, col_w, wheel_h), "TRASERA IZQUIERDA (RL)", _paths([
		"tires.pressure.cold_kpa_gauge.RL",
		"suspension.rear.camber",
		"suspension.rear.toe"
	]), 44.0)
	
	# Right: FR & RR
	var right_x := 1280.0 - 24.0 - col_w
	_draw_group_panel(Rect2(right_x, row_y1, col_w, wheel_h), "DELANTERA DERECHA (FR)", _paths([
		"tires.pressure.cold_kpa_gauge.FR",
		"suspension.front.camber",
		"suspension.front.toe"
	]), 44.0)
	_draw_group_panel(Rect2(right_x, row_y2, col_w, wheel_h), "TRASERA DERECHA (RR)", _paths([
		"tires.pressure.cold_kpa_gauge.RR",
		"suspension.rear.camber",
		"suspension.rear.toe"
	]), 44.0)
	
	# Center: Top Wheel Geometry Alignment + Bottom Brake System
	var center_x := 24.0 + col_w + 16.0
	var center_w := right_x - center_x - 16.0
	_draw_wheel_geometry_card(Rect2(center_x, row_y1, center_w, wheel_h))
	_draw_brakes_panel(Rect2(center_x, row_y2, center_w, wheel_h))


func _draw_wheel_geometry_card(rect: Rect2) -> void:
	_draw_panel(rect, C_PANEL, C_BORDER)
	_draw_text(Vector2(rect.get_center().x, rect.position.y + 24.0), "GEOMETRÍA Y CAÍDAS", 13, C_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text(Vector2(rect.get_center().x, rect.position.y + 40.0), "ALINEACIÓN DE EJES DELANTERO Y TRASERO", 10, C_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	
	var f_camber := float(draft_values.get("suspension.front.camber", 0.0)) * 57.2957795
	var r_camber := float(draft_values.get("suspension.rear.camber", 0.0)) * 57.2957795
	var f_toe := float(draft_values.get("suspension.front.toe", 0.0)) * 57.2957795
	var r_toe := float(draft_values.get("suspension.rear.toe", 0.0)) * 57.2957795
	
	var box_w := (rect.size.x - 48.0) * 0.5
	var box_h := rect.size.y - 64.0
	var box_f := Rect2(rect.position.x + 16.0, rect.position.y + 50.0, box_w, box_h)
	var box_r := Rect2(rect.position.x + 32.0 + box_w, rect.position.y + 50.0, box_w, box_h)
	
	_draw_panel(box_f, C_PANEL_ALT, C_BORDER)
	_draw_text(Vector2(box_f.position.x + 14.0, box_f.position.y + 24.0), "EJE DELANTERO", 12, C_GOLD, true)
	_draw_text(Vector2(box_f.position.x + 14.0, box_f.position.y + 52.0), "Caída estática:", 11, C_MUTED)
	_draw_text(Vector2(box_f.end.x - 14.0, box_f.position.y + 52.0), "%0.2f°" % f_camber, 13, C_WHITE, true, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, true)
	_draw_text(Vector2(box_f.position.x + 14.0, box_f.position.y + 82.0), "Convergencia:", 11, C_MUTED)
	_draw_text(Vector2(box_f.end.x - 14.0, box_f.position.y + 82.0), "%0.2f°" % f_toe, 13, C_GOLD, true, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, true)
	_draw_line(Vector2(box_f.position.x + 14.0, box_f.position.y + 104.0), Vector2(box_f.end.x - 14.0, box_f.position.y + 104.0), C_BORDER, 1.0)
	_draw_text(Vector2(box_f.position.x + 14.0, box_f.position.y + 128.0), "Geometría MacPherson", 10, C_MUTED)
	_draw_text(Vector2(box_f.position.x + 14.0, box_f.position.y + 146.0), "Optimizada para tierra y gravilla", 10, C_WHITE)
	
	_draw_panel(box_r, C_PANEL_ALT, C_BORDER)
	_draw_text(Vector2(box_r.position.x + 14.0, box_r.position.y + 24.0), "EJE TRASERO", 12, C_GOLD, true)
	_draw_text(Vector2(box_r.position.x + 14.0, box_r.position.y + 52.0), "Caída estática:", 11, C_MUTED)
	_draw_text(Vector2(box_r.end.x - 14.0, box_r.position.y + 52.0), "%0.2f°" % r_camber, 13, C_WHITE, true, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, true)
	_draw_text(Vector2(box_r.position.x + 14.0, box_r.position.y + 82.0), "Convergencia:", 11, C_MUTED)
	_draw_text(Vector2(box_r.end.x - 14.0, box_r.position.y + 82.0), "%0.2f°" % r_toe, 13, C_GOLD, true, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, true)
	_draw_line(Vector2(box_r.position.x + 14.0, box_r.position.y + 104.0), Vector2(box_r.end.x - 14.0, box_r.position.y + 104.0), C_BORDER, 1.0)
	_draw_text(Vector2(box_r.position.x + 14.0, box_r.position.y + 128.0), "Eje Rígido Salisbury 4-Link", 10, C_MUTED)
	_draw_text(Vector2(box_r.position.x + 14.0, box_r.position.y + 146.0), "Tracción longitudinal máxima", 10, C_WHITE)


func _draw_brakes_panel(rect: Rect2) -> void:
	_draw_panel(rect, C_PANEL, C_BORDER)
	_draw_text(Vector2(rect.position.x + 16.0, rect.position.y + 24.0), "SISTEMA DE FRENOS", 12, C_GOLD, true)
	_draw_line(Vector2(rect.position.x + 14.0, rect.position.y + 34.0), Vector2(rect.end.x - 14.0, rect.position.y + 34.0), C_BORDER, 1.0)
	
	var bias := float(draft_values.get("brakes.front_brake_bias", 0.60))
	var f1 := RallySetupCatalog.field_for_path("brakes.front_brake_bias")
	var f2 := RallySetupCatalog.field_for_path("brakes.max_brake_torque")
	
	_draw_field_row(f1, Rect2(rect.position.x + 12.0, rect.position.y + 44.0, rect.size.x - 24.0, 52.0))
	_draw_field_row(f2, Rect2(rect.position.x + 12.0, rect.position.y + 102.0, rect.size.x - 24.0, 52.0))
	
	# Brake distribution capsule bar
	var bar_y := rect.end.y - 36.0
	var bar_w := rect.size.x - 40.0
	var bar_x := rect.position.x + 20.0
	_draw_text(Vector2(bar_x, bar_y - 8.0), "REPARTO: DELANTERA %0.1f%%" % (bias * 100.0), 10, C_GOLD, true)
	_draw_text(Vector2(bar_x + bar_w, bar_y - 8.0), "TRASERA %0.1f%%" % ((1.0 - bias) * 100.0), 10, C_MUTED, true, HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_capsule_bar(Vector2(bar_x, bar_y), bar_w, 8.0, C_SLIDER_TRACK)
	_draw_capsule_bar(Vector2(bar_x, bar_y), bar_w * bias, 8.0, C_GOLD)


func _draw_powertrain_page() -> void:
	var y := 158.0
	var h := 524.0
	var col_w := 388.0
	var gap := 18.0
	
	# Col 1: Motor & Final Drive
	var col1_x := 24.0
	_draw_group_panel(Rect2(col1_x, y, col_w, 230.0), "MOTOR RS2000 (GRUPO 4)", _paths([
		"powertrain.max_rpm",
		"powertrain.final_drive"
	]), 52.0)
	_draw_group_panel(Rect2(col1_x, y + 244.0, col_w, 140.0), "DIRECCIÓN Y ASISTENCIA", _paths([
		"steering.steering_speed"
	]), 54.0)
	
	# Col 1 Bottom note
	var note_rect := Rect2(col1_x, y + 398.0, col_w, 126.0)
	_draw_panel(note_rect, C_PANEL, C_BORDER)
	_draw_text(Vector2(note_rect.position.x + 14.0, note_rect.position.y + 24.0), "ESPECIFICACIONES DEL MOTOR", 11, C_GOLD, true)
	_draw_text(Vector2(note_rect.position.x + 14.0, note_rect.position.y + 48.0), "Motor Ford Pinto 2.0L OHC (Grupo 4 Rally)", 11, C_WHITE)
	_draw_text(Vector2(note_rect.position.x + 14.0, note_rect.position.y + 70.0), "Régimen máximo homologado: 7.200 rpm", 11, C_MUTED)
	_draw_text(Vector2(note_rect.position.x + 14.0, note_rect.position.y + 92.0), "Potencia estimada: 245 CV @ 7.000 rpm", 11, C_GOLD, true)
	
	# Col 2: Gear Ratios Interactive Sliders (1a, 2a, 3a, 4a, R)
	var col2_x := col1_x + col_w + gap
	_draw_group_panel(Rect2(col2_x, y, col_w, h), "RELACIONES DE CAMBIO (4 MARCHAS + R)", _paths([
		"powertrain.gear_ratios.0",
		"powertrain.gear_ratios.1",
		"powertrain.gear_ratios.2",
		"powertrain.gear_ratios.3",
		"powertrain.reverse_ratio"
	]), 52.0)
	
	# Col 3: Salisbury Differential
	var col3_x := col2_x + col_w + gap
	_draw_group_panel(Rect2(col3_x, y, col_w, h), "DIFERENCIAL SALISBURY", _paths([
		"powertrain.differential.preload_nm",
		"powertrain.differential.power_ramp_angle_deg",
		"powertrain.differential.coast_ramp_angle_deg",
		"powertrain.differential.clutches"
	]), 52.0)


func _draw_strategy_page() -> void:
	var y := 158.0
	var h := 524.0
	
	# Left: Fuel and Tire Service Panel
	var left_w := 580.0
	var left_rect := Rect2(24.0, y, left_w, h)
	_draw_panel(left_rect, C_PANEL, C_BORDER)
	
	# Unified Fuel & Autonomy Card
	_draw_text(Vector2(left_rect.position.x + 20.0, left_rect.position.y + 28.0), "COMBUSTIBLE Y AUTONOMÍA", 14, C_GOLD, true)
	_draw_text(Vector2(left_rect.position.x + 20.0, left_rect.position.y + 46.0), "Depósito de seguridad: capacidad total 45.0 kg", 11, C_MUTED)
	
	var fuel_field := RallySetupCatalog.field_for_path("fuel.initial_kg")
	var fuel_val := float(draft_values.get("fuel.initial_kg", 25.0))
	var fuel_cap := 45.0
	var fuel_pct := clampf(fuel_val / fuel_cap, 0.0, 1.0) * 100.0
	
	# Unified interactive fuel slider row
	var fuel_row_rect := Rect2(left_rect.position.x + 16.0, left_rect.position.y + 60.0, left_w - 32.0, 58.0)
	_draw_rect(fuel_row_rect, C_PANEL_ALT, true)
	_draw_rect(fuel_row_rect, C_GOLD if selected_field_path == "fuel.initial_kg" else C_BORDER, false, 1.0)
	
	_draw_text(Vector2(fuel_row_rect.position.x + 14.0, fuel_row_rect.position.y + 20.0), "Carga de combustible", 12, C_WHITE, true)
	_draw_text(Vector2(fuel_row_rect.end.x - 14.0, fuel_row_rect.position.y + 20.0), "%0.1f / %0.1f kg  (%0.0f%%)" % [fuel_val, fuel_cap, fuel_pct], 13, C_GOLD, true, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, true)
	
	var fuel_track := Rect2(fuel_row_rect.position.x + 36.0, fuel_row_rect.position.y + 38.0, fuel_row_rect.size.x - 72.0, 8.0)
	_draw_capsule_bar(fuel_track.position, fuel_track.size.x, 8.0, C_SLIDER_TRACK)
	var fill_fw := fuel_track.size.x * (fuel_val / fuel_cap)
	_draw_capsule_bar(fuel_track.position, fill_fw, 8.0, C_GOLD)
	draw_circle(Vector2(fuel_track.position.x + fill_fw, fuel_track.position.y + 4.0), 6.0, C_WHITE)
	draw_circle(Vector2(fuel_track.position.x + fill_fw, fuel_track.position.y + 4.0), 3.0, C_BG)
	
	_draw_text(Vector2(fuel_row_rect.position.x + 14.0, fuel_row_rect.position.y + 45.0), "−", 12, C_MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text(Vector2(fuel_row_row_rect_end(fuel_row_rect) - 14.0, fuel_row_rect.position.y + 45.0), "+", 12, C_MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)
	
	_hit_regions.append({"rect": fuel_row_rect, "kind": "field", "path": "fuel.initial_kg", "slider": false})
	_hit_regions.append({"rect": fuel_track.grow(8.0), "kind": "field", "path": "fuel.initial_kg", "slider": true, "track": fuel_track})
	_hit_regions.append({"rect": Rect2(fuel_row_rect.position.x, fuel_row_rect.position.y + 26.0, 30.0, 26.0), "kind": "adjust", "path": "fuel.initial_kg", "amount": -1.0})
	_hit_regions.append({"rect": Rect2(fuel_row_rect.end.x - 30.0, fuel_row_rect.position.y + 26.0, 30.0, 26.0), "kind": "adjust", "path": "fuel.initial_kg", "amount": 1.0})
	
	# Calculation for First Leg before Service
	var leg_box := Rect2(left_rect.position.x + 16.0, left_rect.position.y + 128.0, left_w - 32.0, 112.0)
	_draw_panel(leg_box, Color(C_PANEL_ALT, 0.6), C_BORDER)
	_draw_text(Vector2(leg_box.position.x + 14.0, leg_box.position.y + 22.0), "PRIMERA SECCIÓN (SS1 – SS5 HASTA ASISTENCIA):", 11, C_GOLD, true)
	_draw_text(Vector2(leg_box.position.x + 14.0, leg_box.position.y + 44.0), "5 tramos cronometrados acumulados · Distancia: ~28.5 km", 11, C_WHITE)
	_draw_text(Vector2(leg_box.position.x + 14.0, leg_box.position.y + 64.0), "Consumo estimado: ~0.62 kg/km  ·  Mínimo necesario: 17.7 kg", 11, C_MUTED)
	
	var margin := fuel_val - 17.7
	var status_text := ""
	var status_col := C_GREEN
	if fuel_val < 17.7:
		status_text = "⚠️ INSUFICIENTE: Faltan %0.1f kg para llegar a la asistencia" % (17.7 - fuel_val)
		status_col = C_RED
	elif fuel_val < 21.5:
		status_text = "⚠️ AJUSTADO: Margen escaso (+%0.1f kg de reserva)" % margin
		status_col = C_GOLD
	else:
		status_text = "✓ AUTONOMÍA ÓPTIMA: +%0.1f kg de reserva de seguridad" % margin
		status_col = C_GREEN
	_draw_text(Vector2(leg_box.position.x + 14.0, leg_box.position.y + 92.0), status_text, 11, status_col, true)
	
	_draw_line(Vector2(left_rect.position.x + 16.0, left_rect.position.y + 252.0), Vector2(left_rect.end.x - 16.0, left_rect.position.y + 252.0), C_BORDER, 1.0)
	
	# Spare Wheels Selector
	_draw_text(Vector2(left_rect.position.x + 20.0, left_rect.position.y + 276.0), "RUEDAS DE REPUESTO EN EL COCHE (A BORDO)", 13, C_GOLD, true)
	_draw_text(Vector2(left_rect.position.x + 20.0, left_rect.position.y + 294.0), "Feature pendiente de sustitución en tramo en desarrollo", 10, C_MUTED)
	
	var opt_w := (left_w - 48.0) / 3.0
	for count_idx in 3:
		var opt_rect := Rect2(left_rect.position.x + 16.0 + float(count_idx) * (opt_w + 8.0), left_rect.position.y + 306.0, opt_w, 42.0)
		var is_sel := draft_spare_wheels == count_idx
		_draw_rect(opt_rect, C_PANEL_ALT if is_sel else C_BG, true)
		_draw_rect(opt_rect, C_GOLD if is_sel else C_BORDER, false, 1.5 if is_sel else 1.0)
		var lbl := "%d RUEDAS" % count_idx
		if count_idx == 1:
			lbl = "1 RUEDA (REC)"
		elif count_idx == 0:
			lbl = "0 (LIGERO)"
		_draw_text(opt_rect.get_center() + Vector2(0.0, 4.0), lbl, 11, C_WHITE if is_sel else C_MUTED, is_sel, HORIZONTAL_ALIGNMENT_CENTER)
		_hit_regions.append({"rect": opt_rect, "kind": "spare_wheels", "count": count_idx})
	
	_draw_text(Vector2(left_rect.position.x + 20.0, left_rect.position.y + 364.0), "Peso añadido en maletero: +%d kg sobre eje trasero" % (draft_spare_wheels * 18), 10, C_MUTED)
	
	_draw_line(Vector2(left_rect.position.x + 16.0, left_rect.position.y + 382.0), Vector2(left_rect.end.x - 16.0, left_rect.position.y + 382.0), C_BORDER, 1.0)
	
	# Tire Service Checkbox Card
	_draw_text(Vector2(left_rect.position.x + 20.0, left_rect.position.y + 406.0), "ASISTENCIA EN EL PARQUE DE TRABAJO", 13, C_WHITE, true)
	var service_rect := Rect2(left_rect.position.x + 16.0, left_rect.position.y + 422.0, left_w - 32.0, 68.0)
	_draw_rect(service_rect, C_PANEL_ALT if new_tires_service else Color(C_PANEL_ALT, 0.5), true)
	_draw_rect(service_rect, C_GOLD if new_tires_service else C_BORDER, false, 1.5 if new_tires_service else 1.0)
	
	var box_rect := Rect2(service_rect.position.x + 16.0, service_rect.position.y + 22.0, 24.0, 24.0)
	_draw_rect(box_rect, C_BG, true)
	_draw_rect(box_rect, C_GOLD if new_tires_service else C_BORDER, false, 1.5)
	if new_tires_service:
		_draw_rect(Rect2(box_rect.position.x + 5.0, box_rect.position.y + 5.0, 14.0, 14.0), C_GOLD, true)
	_draw_text(Vector2(service_rect.position.x + 52.0, service_rect.position.y + 32.0), "MONTAR JUEGO NUEVO DE NEUMÁTICOS", 12, C_WHITE, true)
	_draw_text(Vector2(service_rect.position.x + 52.0, service_rect.position.y + 50.0), "El juego actual se renueva por completo en la asistencia", 10, C_MUTED)
	_hit_regions.append({"rect": service_rect, "kind": "service"})
	
	# Right: Per-Wheel Compound Selection & Weather Forecast
	var right_x := left_rect.end.x + 18.0
	var right_w := 1280.0 - 24.0 - right_x
	var right_rect := Rect2(right_x, y, right_w, h)
	_draw_panel(right_rect, C_PANEL, C_BORDER)
	
	_draw_text(Vector2(right_rect.position.x + 20.0, right_rect.position.y + 28.0), "TIPO DE COMPUESTO POR NEUMÁTICO", 14, C_GOLD, true)
	_draw_text(Vector2(right_rect.position.x + 20.0, right_rect.position.y + 46.0), "Selección independiente por cada rueda del coche", 11, C_MUTED)
	
	# 4 Wheel Compound Cards
	var wheels_info := [
		{"key": "FL", "label": "DELANTERA IZQ (FL)"},
		{"key": "FR", "label": "DELANTERA DER (FR)"},
		{"key": "RL", "label": "TRASERA IZQ (RL)"},
		{"key": "RR", "label": "TRASERA DER (RR)"}
	]
	
	var card_w := (right_w - 44.0) * 0.5
	var card_h := 88.0
	for wi in 4:
		var w_item: Dictionary = wheels_info[wi]
		var wk: String = w_item.key
		var col_idx := wi % 2
		var row_idx := wi / 2
		var wx := right_rect.position.x + 16.0 + float(col_idx) * (card_w + 12.0)
		var wy := right_rect.position.y + 60.0 + float(row_idx) * (card_h + 12.0)
		var w_rect := Rect2(wx, wy, card_w, card_h)
		_draw_panel(w_rect, C_PANEL_ALT, C_BORDER)
		_draw_text(Vector2(wx + 12.0, wy + 22.0), str(w_item.label), 11, C_WHITE, true)
		
		var cur_comp: String = str(draft_wheel_compounds.get(wk, "gravel_normal"))
		var btn_w := (card_w - 28.0) * 0.5
		var btn_h := 34.0
		var btn_sec := Rect2(wx + 10.0, wy + 38.0, btn_w, btn_h)
		var btn_llu := Rect2(wx + 18.0 + btn_w, wy + 38.0, btn_w, btn_h)
		
		var is_sec := cur_comp == "gravel_normal"
		var is_llu := cur_comp == "gravel_wet"
		
		_draw_rect(btn_sec, C_PANEL_HOVER if is_sec else C_BG, true)
		_draw_rect(btn_sec, C_GOLD if is_sec else C_BORDER, false, 1.5 if is_sec else 1.0)
		_draw_text(btn_sec.get_center() + Vector2(0.0, 4.0), "NORMAL / SECO", 10, C_GOLD if is_sec else C_MUTED, is_sec, HORIZONTAL_ALIGNMENT_CENTER)
		_hit_regions.append({"rect": btn_sec, "kind": "wheel_compound", "wheel": wk, "compound_id": "gravel_normal"})
		
		_draw_rect(btn_llu, C_PANEL_HOVER if is_llu else C_BG, true)
		_draw_rect(btn_llu, C_GOLD if is_llu else C_BORDER, false, 1.5 if is_llu else 1.0)
		_draw_text(btn_llu.get_center() + Vector2(0.0, 4.0), "LLUVIA / BARRO", 10, C_GOLD if is_llu else C_MUTED, is_llu, HORIZONTAL_ALIGNMENT_CENTER)
		_hit_regions.append({"rect": btn_llu, "kind": "wheel_compound", "wheel": wk, "compound_id": "gravel_wet"})
	
	# Global Compound Batch Quick Actions
	var quick_y := right_rect.position.y + 266.0
	_draw_text(Vector2(right_rect.position.x + 20.0, quick_y + 16.0), "APLICAR A LAS 4 RUEDAS:", 10, C_MUTED, true)
	var q_btn_w := (right_w - 44.0) * 0.5
	var q_rect1 := Rect2(right_rect.position.x + 16.0, quick_y + 26.0, q_btn_w, 34.0)
	var q_rect2 := Rect2(right_rect.position.x + 28.0 + q_btn_w, quick_y + 26.0, q_btn_w, 34.0)
	
	_draw_rect(q_rect1, C_PANEL_ALT, true)
	_draw_rect(q_rect1, C_BORDER_FOCUS, false, 1.0)
	_draw_text(q_rect1.get_center() + Vector2(0.0, 4.0), "MONTAR 4 SECO", 11, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	_hit_regions.append({"rect": q_rect1, "kind": "all_compounds", "compound_id": "gravel_normal"})
	
	_draw_rect(q_rect2, C_PANEL_ALT, true)
	_draw_rect(q_rect2, C_BORDER_FOCUS, false, 1.0)
	_draw_text(q_rect2.get_center() + Vector2(0.0, 4.0), "MONTAR 4 LLUVIA", 11, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	_hit_regions.append({"rect": q_rect2, "kind": "all_compounds", "compound_id": "gravel_wet"})
	
	_draw_line(Vector2(right_rect.position.x + 16.0, quick_y + 74.0), Vector2(right_rect.end.x - 16.0, quick_y + 74.0), C_BORDER, 1.0)
	
	# Weather Forecast and Stage Environment
	var fore_y := quick_y + 86.0
	_draw_text(Vector2(right_rect.position.x + 20.0, fore_y + 16.0), "PRONÓSTICO METEOROLÓGICO Y CONDICIONES", 12, C_GOLD, true)
	
	var fore_box := Rect2(right_rect.position.x + 16.0, fore_y + 28.0, right_w - 32.0, 116.0)
	_draw_panel(fore_box, C_PANEL_ALT, C_BORDER)
	
	var f_summary := forecast_summary if not forecast_summary.is_empty() else "Seco · Cielos despejados con zonas de gravilla compacta"
	_draw_text(Vector2(fore_box.position.x + 16.0, fore_box.position.y + 28.0), "PRÓXIMA SECCIÓN: " + f_summary.to_upper(), 11, C_WHITE, true)
	_draw_text(Vector2(fore_box.position.x + 16.0, fore_box.position.y + 54.0), "Superficie: Pistas forestales mixtas · Agarre: Medio-Alto", 11, C_MUTED)
	var adv := forecast_advice if not forecast_advice.is_empty() else "Compuesto recomendado: Normal (Seco/Mixto)"
	_draw_text(Vector2(fore_box.position.x + 16.0, fore_box.position.y + 78.0), "Recomendación del ingeniero: " + adv, 11, C_GOLD, true)
	_draw_text(Vector2(fore_box.position.x + 16.0, fore_box.position.y + 102.0), "Permitido cambiar neumáticos en cada parque de trabajo oficial", 10, C_MUTED)


func fuel_row_row_rect_end(r: Rect2) -> float:
	return r.end.x


func _draw_setups_page() -> void:
	var y := 158.0
	var h := 524.0
	
	# Left: Saved Setups Table
	var left_w := 820.0
	var left_rect := Rect2(24.0, y, left_w, h)
	_draw_panel(left_rect, C_PANEL, C_BORDER)
	
	_draw_text(Vector2(left_rect.position.x + 20.0, left_rect.position.y + 32.0), "REGLAJES GUARDADOS EN BASE DE DATOS", 16, C_WHITE, true)
	_draw_text(Vector2(left_rect.position.x + 20.0, left_rect.position.y + 54.0), circuit_name.to_upper() + "  ·  " + mode.to_upper() + "  ·  FORD ESCORT RS2000", 11, C_MUTED)
	
	# Table Header
	var th_y := left_rect.position.y + 72.0
	_draw_rect(Rect2(left_rect.position.x + 16.0, th_y, left_w - 32.0, 28.0), C_PANEL_ALT, true)
	_draw_text(Vector2(left_rect.position.x + 32.0, th_y + 19.0), "NOMBRE DEL REGLAJE", 11, C_GOLD, true)
	_draw_text(Vector2(left_rect.position.x + 460.0, th_y + 19.0), "EQUIPO / AUTOR", 11, C_GOLD, true)
	_draw_text(Vector2(left_rect.end.x - 32.0, th_y + 19.0), "FECHA MODIFICADO", 11, C_GOLD, true, HORIZONTAL_ALIGNMENT_RIGHT)
	
	var list_y := th_y + 36.0
	for visible_index in mini(maxi(setup_rows.size() - setup_scroll_offset, 0), 7):
		var index := setup_scroll_offset + visible_index
		var row := setup_rows[index]
		var rect := Rect2(left_rect.position.x + 16.0, list_y + float(visible_index) * 48.0, left_w - 32.0, 42.0)
		var selected := index == selected_setup_index
		_draw_rect(rect, C_PANEL_HOVER if selected else C_PANEL_ALT, true)
		_draw_rect(rect, C_BORDER_FOCUS if selected else C_BORDER, false, 1.0)
		if selected:
			_draw_rect(Rect2(rect.position.x, rect.position.y, 4.0, rect.size.y), C_GOLD, true)
		_draw_text(Vector2(rect.position.x + 16.0, rect.position.y + 26.0), str(row.get("name", "Reglaje")), 13, C_WHITE, true)
		_draw_text(Vector2(rect.position.x + 444.0, rect.position.y + 26.0), team_name.to_upper(), 11, C_MUTED)
		_draw_text(Vector2(rect.end.x - 16.0, rect.position.y + 26.0), _short_timestamp(str(row.get("modified_at", ""))), 11, C_MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, true)
		_hit_regions.append({"rect": rect, "kind": "setup_row", "index": index})
		
	if setup_rows.is_empty():
		_draw_text(Vector2(left_rect.get_center().x, left_rect.get_center().y), "NO HAY REGLAJES GUARDADOS PARA ESTE CIRCUITO", 13, C_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
		
	_draw_text(Vector2(left_rect.position.x + 20.0, left_rect.end.y - 18.0), "Base de datos de reglajes activa", 11, C_MUTED)
	
	# Right: Action Buttons & Setup Info (No Local Storage text block)
	var right_x := left_rect.end.x + 20.0
	var right_w := 1280.0 - 24.0 - right_x
	var right_rect := Rect2(right_x, y, right_w, h)
	_draw_panel(right_rect, C_PANEL, C_BORDER)
	
	_draw_text(Vector2(right_rect.position.x + 20.0, right_rect.position.y + 32.0), "GESTIÓN DE REGLAJES", 14, C_WHITE, true)
	
	var btn_w := right_w - 40.0
	var btn_h := 46.0
	var by := right_rect.position.y + 60.0
	_draw_button(Rect2(right_rect.position.x + 20.0, by, btn_w, btn_h), "NUEVO REGLAJE", "new", true)
	_draw_button(Rect2(right_rect.position.x + 20.0, by + 56.0, btn_w, btn_h), "GUARDAR SELECCIONADO", "save")
	_draw_button(Rect2(right_rect.position.x + 20.0, by + 112.0, btn_w, btn_h), "CARGAR Y APLICAR", "load")
	_draw_button(Rect2(right_rect.position.x + 20.0, by + 168.0, btn_w, btn_h), "ELIMINAR REGLAJE", "delete", false, true)
	
	_draw_line(Vector2(right_rect.position.x + 20.0, by + 236.0), Vector2(right_rect.end.x - 20.0, by + 236.0), C_BORDER, 1.0)
	
	# Setup Guide card
	var guide_box := Rect2(right_rect.position.x + 20.0, by + 256.0, btn_w, 180.0)
	_draw_panel(guide_box, C_PANEL_ALT, C_BORDER)
	_draw_text(Vector2(guide_box.position.x + 14.0, guide_box.position.y + 24.0), "INFORMACIÓN DEL PERFIL", 11, C_GOLD, true)
	_draw_text(Vector2(guide_box.position.x + 14.0, guide_box.position.y + 48.0), "Vehículo activo: Ford Escort RS2000", 11, C_WHITE)
	_draw_text(Vector2(guide_box.position.x + 14.0, guide_box.position.y + 70.0), "Categoría: Grupo 4 Histórico FIA", 11, C_MUTED)
	_draw_text(Vector2(guide_box.position.x + 14.0, guide_box.position.y + 92.0), "Reglaje activo: " + active_setup_name, 11, C_GOLD, true)
	_draw_text(Vector2(guide_box.position.x + 14.0, guide_box.position.y + 120.0), "Los reglajes se aplican directamente", 10, C_MUTED)
	_draw_text(Vector2(guide_box.position.x + 14.0, guide_box.position.y + 138.0), "a las físicas y dinámicas del coche.", 10, C_MUTED)


func _draw_footer() -> void:
	var line_y := 698.0
	_draw_line(Vector2(24.0, line_y), Vector2(1256.0, line_y), C_BORDER, 1.0)
	
	var btn_y := 718.0
	var btn_h := 48.0
	
	if page == 4:
		_draw_button(Rect2(24.0, btn_y, 200.0, btn_h), "RESTAURAR PERFIL", "reset")
		_draw_button(Rect2(930.0, btn_y, 140.0, btn_h), "CANCELAR", "cancel")
		_draw_button(Rect2(1082.0, btn_y, 174.0, btn_h), "APLICAR Y SALIR", "apply", true)
	else:
		_draw_button(Rect2(24.0, btn_y, 180.0, btn_h), "RESTABLECER", "reset")
		_draw_text(Vector2(640.0, btn_y + 28.0), "W/S O ↑/↓ NAVEGAR   ·   Q/E O ←/→ AJUSTAR   ·   RE PÁG/AV PÁG CAMBIAR PÁGINA", 11, C_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_button(Rect2(930.0, btn_y, 140.0, btn_h), "CANCELAR", "cancel")
		_draw_button(Rect2(1082.0, btn_y, 174.0, btn_h), "APLICAR Y SALIR", "apply", true)
		
	_draw_text(Vector2(1256.0, 788.0), "F5 / START APLICAR   ·   ESC / B CANCELAR", 10, C_MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_group_panel(rect: Rect2, title: String, paths: Array[String], row_height: float) -> void:
	_draw_panel(rect, C_PANEL, C_BORDER)
	_draw_text(Vector2(rect.position.x + 16.0, rect.position.y + 24.0), title, 12, C_GOLD, true)
	_draw_line(Vector2(rect.position.x + 14.0, rect.position.y + 34.0), Vector2(rect.end.x - 14.0, rect.position.y + 34.0), C_BORDER, 1.0)
	var row_y := rect.position.y + 42.0
	for path in paths:
		var field := RallySetupCatalog.field_for_path(path)
		if field.is_empty():
			continue
		_draw_field_row(field, Rect2(rect.position.x + 10.0, row_y, rect.size.x - 20.0, row_height))
		row_y += row_height


func _draw_field_row(field: Dictionary, rect: Rect2) -> void:
	var path: String = str(field.path)
	var selected := selected_field_path == path
	_draw_rect(rect, C_PANEL_HOVER if selected else Color(C_PANEL_ALT, 0.45), true)
	_draw_rect(rect, C_BORDER_FOCUS if selected else Color(C_BORDER, 0.5), false, 1.0)
	if selected:
		_draw_rect(Rect2(rect.position.x, rect.position.y, 3.0, rect.size.y), C_GOLD, true)
		
	var display_value := float(draft_values.get(path, 0.0)) * float(field.scale)
	var formatted := ("%0.*f" % [int(field.digits), display_value]) + str(field.suffix)
	
	_draw_text(Vector2(rect.position.x + 10.0, rect.position.y + 15.0), str(field.label), 11, C_WHITE if selected else C_MUTED)
	_draw_text(Vector2(rect.end.x - 10.0, rect.position.y + 15.0), formatted, 13, C_GOLD if selected else C_WHITE, true, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, true)
	
	var track_h := 6.0
	var track_rect := Rect2(rect.position.x + 36.0, rect.position.y + rect.size.y - 12.0, rect.size.x - 72.0, track_h)
	_draw_capsule_bar(track_rect.position, track_rect.size.x, track_h, C_SLIDER_TRACK)
	
	var range_value := maxf(float(field.max) - float(field.min), 0.0001)
	var fraction := clampf((float(draft_values.get(path, 0.0)) - float(field.min)) / range_value, 0.0, 1.0)
	var fill_w := track_rect.size.x * fraction
	if fill_w > 0.0:
		_draw_capsule_bar(track_rect.position, fill_w, track_h, C_GOLD if selected else C_SLIDER_FILL)
	
	var knob_center := Vector2(track_rect.position.x + fill_w, track_rect.position.y + track_h * 0.5)
	draw_circle(knob_center, 5.0, C_GOLD if selected else C_WHITE)
	draw_circle(knob_center, 2.5, C_BG)
	
	_hit_regions.append({"rect": rect, "kind": "field", "path": path, "slider": false})
	_hit_regions.append({"rect": track_rect.grow(8.0), "kind": "field", "path": path, "slider": true, "track": track_rect})
	_hit_regions.append({"rect": Rect2(rect.position.x + 2.0, rect.end.y - 22.0, 26.0, 20.0), "kind": "adjust", "path": path, "amount": -1.0})
	_hit_regions.append({"rect": Rect2(rect.end.x - 28.0, rect.end.y - 22.0, 26.0, 20.0), "kind": "adjust", "path": path, "amount": 1.0})
	
	_draw_text(Vector2(rect.position.x + 14.0, rect.end.y - 5.0), "−", 11, C_MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text(Vector2(rect.end.x - 14.0, rect.end.y - 5.0), "+", 11, C_MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_capsule_bar(pos: Vector2, width: float, height: float, color: Color) -> void:
	if width <= 0.0 or height <= 0.0:
		return
	var radius := height * 0.5
	if width <= height:
		draw_circle(pos + Vector2(radius, radius), radius, color)
		return
	draw_rect(Rect2(pos.x + radius, pos.y, width - height, height), color, true)
	draw_circle(Vector2(pos.x + radius, pos.y + radius), radius, color)
	draw_circle(Vector2(pos.x + width - radius, pos.y + radius), radius, color)


func _draw_button(rect: Rect2, label: String, action: String, primary: bool = false, danger: bool = false) -> void:
	var fill := C_GOLD if primary else (Color(C_RED, 0.18) if danger else C_PANEL_ALT)
	var border := C_GOLD if primary else (C_RED if danger else C_BORDER_FOCUS)
	var text_color := C_BG if primary else (C_RED if danger else C_WHITE)
	_draw_rect(rect, fill, true)
	_draw_rect(rect, border, false, 1.0)
	_draw_text(rect.get_center() + Vector2(0.0, 4.0), label, 12, text_color, true, HORIZONTAL_ALIGNMENT_CENTER)
	_hit_regions.append({"rect": rect, "kind": "button", "action": action})


func _draw_modal() -> void:
	draw_rect(Rect2(Vector2.ZERO, LOGICAL_SIZE), Color(0.0, 0.0, 0.0, 0.78))
	var rect := Rect2(380.0, 260.0, 520.0, 240.0)
	_draw_panel(rect, C_PANEL_ALT, C_BORDER_FOCUS)
	draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 3.0), C_GOLD)
	
	if modal_mode == "name":
		_draw_text(Vector2(640.0, 310.0), "GUARDAR NUEVO REGLAJE", 18, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_text(Vector2(414.0, 350.0), "Nombre del reglaje (1–100 caracteres)", 12, C_MUTED)
		var input_rect := Rect2(414.0, 366.0, 452.0, 44.0)
		_draw_rect(input_rect, C_BG, true)
		_draw_rect(input_rect, C_GOLD, false, 1.5)
		_draw_text(Vector2(426.0, 394.0), modal_text + "▌", 14, C_WHITE)
		_draw_text(Vector2(640.0, 448.0), "ENTER GUARDAR   ·   ESC CANCELAR", 12, C_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_text(Vector2(640.0, 472.0), "MANDO: ←/→ ELEGIR  ·  A AÑADIR  ·  LB BORRAR  ·  START GUARDAR", 10, C_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	elif modal_mode == "delete":
		_draw_text(Vector2(640.0, 320.0), "ELIMINAR REGLAJE", 18, C_RED, true, HORIZONTAL_ALIGNMENT_CENTER)
		var selected_name := "este reglaje"
		for row in setup_rows:
			if int(row.get("id", -1)) == selected_setup_id:
				selected_name = str(row.get("name", selected_name))
		_draw_text(Vector2(640.0, 370.0), "¿Deseas eliminar definitivamente «" + selected_name + "»?", 13, C_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_text(Vector2(640.0, 440.0), "ENTER ELIMINAR   ·   ESC CANCELAR", 12, C_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_draw_text(Vector2(640.0, 320.0), "DESCARTAR CAMBIOS", 18, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_text(Vector2(640.0, 370.0), "Se restaurarán los valores previos a la apertura del garaje.", 13, C_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_text(Vector2(640.0, 440.0), "ENTER ACEPTAR DESCARTE   ·   ESC SEGUIR EDITANDO", 12, C_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_notice() -> void:
	var is_error := notice.to_lower().contains("no se") or notice.to_lower().contains("error") or notice.to_lower().contains("incompatible")
	var rect := Rect2(320.0, 656.0, 640.0, 34.0)
	_draw_rect(rect, Color(C_RED if is_error else C_PANEL_ALT, 0.95), true)
	_draw_rect(rect, C_RED if is_error else C_BORDER_FOCUS, false, 1.0)
	_draw_text(rect.get_center() + Vector2(0.0, 4.0), notice, 11, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_panel(rect: Rect2, color: Color, border_color: Color = C_BORDER) -> void:
	_draw_rect(rect, color, true)
	_draw_rect(rect, border_color, false, 1.0)


func _draw_rect(rect: Rect2, color: Color, filled: bool, width: float = 1.0) -> void:
	if filled:
		draw_rect(rect, color)
	else:
		draw_rect(rect, color, false, width)


func _draw_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	draw_line(from, to, color, width)


func _draw_text(baseline: Vector2, text: String, font_size: int, color: Color, bold: bool = false, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, is_numeric: bool = false) -> void:
	var font: Font
	if is_numeric:
		font = FONT_DIN_BOLD if bold else FONT_DIN_REGULAR
	else:
		font = FONT_BOLD if bold else FONT_REGULAR
	var pos := baseline
	if width < 0.0:
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		if alignment == HORIZONTAL_ALIGNMENT_CENTER:
			pos.x -= text_size.x * 0.5
		elif alignment == HORIZONTAL_ALIGNMENT_RIGHT:
			pos.x -= text_size.x
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
	else:
		draw_string(font, pos, text, alignment, width, font_size, color)


func _paths(paths: Array) -> Array[String]:
	var result: Array[String] = []
	for path in paths:
		result.append(str(path))
	return result


func _short_timestamp(value: String) -> String:
	if value.is_empty():
		return ""
	return value.replace("T", " ").trim_suffix("Z").left(19)
