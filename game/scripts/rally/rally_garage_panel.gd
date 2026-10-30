class_name RallyGaragePanel
extends Control

signal garage_closed(applied: bool)

const LOGICAL_SIZE := Vector2(1280.0, 800.0)
const FONT_REGULAR: Font = preload("res://fonts/libron/Libron-Regular.ttf")
const FONT_BOLD: Font = preload("res://fonts/libron/Libron-Bold.ttf")
const CAR_TEXTURE: Texture2D = preload("res://assets/rally/garage/formula-car-top-ui-silhouette-v2.png")
const C_BG := Color("#171b1f")
const C_PANEL := Color("#1e2429")
const C_PANEL_ALT := Color("#242c32")
const C_LINE := Color("#607e91")
const C_STEEL := Color("#607e91")
const C_STEEL_DARK := Color("#343e46")
const C_GOLD := Color("#e3b23c")
const C_WHITE := Color("#e9ece8")
const C_MUTED := Color("#a8b5ba")
const C_RED := Color("#ff6b61")
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
	vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	input_controller = get_node_or_null(input_controller_path) as RallyVehicleInputController
	if input_controller != null and not input_controller.garage_menu_requested.is_connected(open_garage):
		input_controller.garage_menu_requested.connect(open_garage)
	if vehicle == null:
		database_status = "No se encontro el coche de Rally."
		push_error(database_status)
		return
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
	if visible or vehicle == null:
		return
	_restore_tree_paused = get_tree().paused
	_restore_controls_enabled = input_controller.controls_enabled if input_controller != null else true
	opening_values = RallySetupCatalog.defaults(vehicle.simulation.domains)
	opening_values["fuel.initial_kg"] = vehicle.simulation.thermal_model.fuel_remaining_litres * vehicle.simulation.mass_model.fuel_density_kg_per_litre
	draft_values = opening_values.duplicate(true)
	pending_values = {}
	new_tires_service = false
	page = 0
	selected_field_path = ""
	_set_page(0)
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
	if not apply_changes and _has_unapplied_changes() and not confirmed_discard:
		modal_mode = "discard"
		queue_redraw()
		return
	if apply_changes:
		var applied := vehicle.apply_setup_values(draft_values)
		if not bool(applied.get("ok", false)):
			_show_notice(str(applied.get("error", "No se pudo aplicar el reglaje.")), true)
			return
		if new_tires_service:
			vehicle.service_new_tires()
	else:
		vehicle.apply_setup_values(opening_values)
	visible = false
	set_process_input(false)
	get_tree().paused = _restore_tree_paused
	if input_controller != null:
		input_controller.set_controls_enabled(_restore_controls_enabled)
	garage_closed.emit(apply_changes)
	queue_redraw()


func _has_unapplied_changes() -> bool:
	return draft_values != opening_values or new_tires_service


func _input(event: InputEvent) -> void:
	if not visible:
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
					_set_from_slider(str(region.path), point.x, region.rect as Rect2)
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
		queue_redraw()
		return


func _set_page(next_page: int) -> void:
	page = posmod(next_page, RallySetupCatalog.PAGE_TITLES.size())
	var fields := RallySetupCatalog.fields_for_page(page)
	_page_field_paths.clear()
	for field in fields:
		var path: String = field.path
		if not _page_field_paths.has(path):
			_page_field_paths.append(path)
	for extra_path in (["steering.max_steering_angle", "brakes.max_brake_torque"] if page == 2 else []):
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


func _set_from_slider(path: String, x: float, rect: Rect2) -> void:
	var field := RallySetupCatalog.field_for_path(path)
	if field.is_empty():
		return
	var track_start := rect.position.x + 34.0
	var track_width := maxf(rect.size.x - 68.0, 1.0)
	var normalized := clampf((x - track_start) / track_width, 0.0, 1.0)
	var value := lerpf(float(field.min), float(field.max), normalized)
	_update_value(path, value)


func _update_value(path: String, value: float) -> void:
	var field := RallySetupCatalog.field_for_path(path)
	if field.is_empty():
		return
	var clamped := snappedf(clampf(value, float(field.min), float(field.max)), float(field.step))
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
		_show_notice("Escribe un nombre para el reglaje.", true)
		return
	if not database_ready:
		modal_mode = ""
		_show_notice("SQLite no esta disponible: " + database_status, true)
		return
	var result := database.create_setup(_database_context(), setup_name, draft_values)
	modal_mode = ""
	if bool(result.get("ok", false)):
		active_setup_id = int(result.get("id", -1))
		active_setup_name = setup_name
		_show_notice("Reglaje creado y guardado.")
		_refresh_setups()
		for index in setup_rows.size():
			if int(setup_rows[index].get("id", -1)) == active_setup_id:
				selected_setup_index = index
				selected_setup_id = active_setup_id
				break
	else:
		_show_notice(str(result.get("error", "No se pudo crear el reglaje.")), true)
	queue_redraw()


func _load_selected_setup() -> void:
	if selected_setup_id < 0:
		_show_notice("Selecciona un reglaje guardado.", true)
		return
	var result := database.load_setup(_database_context(), selected_setup_id)
	if not bool(result.get("ok", false)):
		_show_notice(str(result.get("error", "No se pudo cargar.")), true)
		return
	var validation := RallySetupCatalog.validate(result.values)
	if not bool(validation.get("ok", false)):
		_show_notice(str(validation.get("error", "Reglaje incompatible.")), true)
		return
	var applied := vehicle.apply_setup_values(validation.values)
	if not bool(applied.get("ok", false)):
		_show_notice(str(applied.get("error", "No se pudo aplicar el reglaje.")), true)
		return
	draft_values = applied.values
	active_setup_id = selected_setup_id
	active_setup_name = str(result.get("name", "Reglaje"))
	_show_notice("Reglaje aplicado en tiempo real: " + active_setup_name)
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
	notice_time = 3.5
	if is_error:
		push_warning("Rally garage: " + message)
	queue_redraw()


func _process(delta: float) -> void:
	if notice_time > 0.0:
		notice_time = maxf(notice_time - delta, 0.0)
		queue_redraw()


func _to_logical(point: Vector2) -> Vector2:
	return (point - _canvas_offset) / maxf(_canvas_scale, 0.0001)


func _draw() -> void:
	_hit_regions.clear()
	if not visible:
		return
	if _canvas_scale <= 0.0:
		_resize_canvas()
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	draw_set_transform(_canvas_offset, 0.0, Vector2.ONE * _canvas_scale)
	draw_rect(Rect2(Vector2.ZERO, LOGICAL_SIZE), C_BG)
	draw_rect(Rect2(0.0, 0.0, 1280.0, 5.0), C_GOLD)
	_draw_header()
	_draw_tabs()
	match page:
		0:
			_draw_suspension_page()
		1:
			_draw_aero_wheels_page()
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
	_draw_panel(Rect2(24.0, 24.0, 1232.0, 72.0), C_PANEL)
	_draw_text(Vector2(48.0, 55.0), "FORMULA 90s", 18, C_GOLD, true)
	_draw_text(Vector2(48.0, 79.0), "GARAGE  /  REGLAJES", 17, C_WHITE, true)
	_draw_line(Vector2(286.0, 38.0), Vector2(286.0, 82.0), C_LINE, 1.0)
	_draw_text(Vector2(312.0, 54.0), "FORD ESCORT RS2000", 18, C_WHITE, true)
	_draw_text(Vector2(312.0, 77.0), circuit_name.to_upper() + "  ·  " + circuit_country.to_upper(), 13, C_MUTED)
	_draw_text(Vector2(1230.0, 53.0), "MODO " + mode.to_upper(), 14, C_GOLD, true, HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_text(Vector2(1230.0, 77.0), "SETUP: " + active_setup_name.to_upper(), 12, C_MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_tabs() -> void:
	var titles: Array = RallySetupCatalog.PAGE_TITLES
	var x := 24.0
	var gap := 7.0
	var width := (1232.0 - gap * 4.0) / 5.0
	for index in titles.size():
		var rect := Rect2(x + float(index) * (width + gap), 112.0, width, 48.0)
		var active := index == page
		_draw_rect(rect, C_STEEL if active else C_PANEL, true)
		_draw_rect(rect, C_GOLD if active else C_LINE, false, 1.0)
		_draw_text(rect.get_center() + Vector2(0.0, 5.0), str(titles[index]), 15, C_WHITE if active else C_MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)
		_hit_regions.append({"rect": rect, "kind": "tab", "page": index})
	_draw_line(Vector2(24.0, 170.0), Vector2(1256.0, 170.0), C_LINE, 1.0)


func _draw_suspension_page() -> void:
	_draw_group_panel(Rect2(24.0, 180.0, 330.0, 234.0), "SUSPENSIÓN DELANTERA", _paths(["suspension.front.ride_frequency_hz", "suspension.front.resting_ratio", "suspension.front.damping_ratio", "suspension.front.bump_damp_multiplier", "suspension.front.rebound_damp_multiplier", "suspension.front.bump_stop_multiplier"]), 31.0)
	_draw_group_panel(Rect2(24.0, 426.0, 330.0, 236.0), "SUSPENSIÓN TRASERA", _paths(["suspension.rear.ride_frequency_hz", "suspension.rear.resting_ratio", "suspension.rear.damping_ratio", "suspension.rear.bump_damp_multiplier", "suspension.rear.rebound_damp_multiplier", "suspension.rear.bump_stop_multiplier"]), 31.0)
	_draw_group_panel(Rect2(926.0, 180.0, 330.0, 234.0), "BARRA DELANTERA", _paths(["suspension.geometry_physical.front_arb.ratio"]))
	_draw_group_panel(Rect2(926.0, 426.0, 330.0, 236.0), "BARRA TRASERA", _paths(["suspension.geometry_physical.rear_arb.ratio"]))
	_draw_car_card(Rect2(374.0, 180.0, 528.0, 482.0), "BALANCE DEL CHASIS")
	_draw_field_row(RallySetupCatalog.field_for_path("steering.max_steering_angle"), Rect2(404.0, 592.0, 468.0, 56.0))


func _draw_aero_wheels_page() -> void:
	_draw_group_panel(Rect2(24.0, 180.0, 330.0, 234.0), "DELANTERA IZQUIERDA", _paths(["tires.pressure.cold_kpa_gauge.FL", "suspension.front.camber", "suspension.front.toe"]))
	_draw_group_panel(Rect2(24.0, 426.0, 330.0, 236.0), "TRASERA IZQUIERDA", _paths(["tires.pressure.cold_kpa_gauge.RL", "suspension.rear.camber", "suspension.rear.toe"]))
	_draw_group_panel(Rect2(926.0, 180.0, 330.0, 234.0), "DELANTERA DERECHA", _paths(["tires.pressure.cold_kpa_gauge.FR", "suspension.front.camber", "suspension.front.toe"]))
	_draw_group_panel(Rect2(926.0, 426.0, 330.0, 236.0), "TRASERA DERECHA", _paths(["tires.pressure.cold_kpa_gauge.RR", "suspension.rear.camber", "suspension.rear.toe"]))
	_draw_car_card(Rect2(374.0, 180.0, 528.0, 284.0), "PRESIONES Y GEOMETRÍA")
	_draw_group_panel(Rect2(374.0, 476.0, 528.0, 186.0), "AERODINÁMICA Y FRENOS", _paths(["aero.model.front_wing.incidence_deg", "aero.model.rear_wing.incidence_deg", "brakes.front_brake_bias", "brakes.max_brake_torque"]), 34.0)


func _draw_powertrain_page() -> void:
	_draw_group_panel(Rect2(24.0, 180.0, 388.0, 482.0), "MOTOR", _paths(["powertrain.max_rpm", "powertrain.final_drive"]))
	_draw_group_panel(Rect2(446.0, 180.0, 388.0, 482.0), "DIFERENCIAL SALISBURY", _paths(["powertrain.differential.preload_nm", "powertrain.differential.power_ramp_angle_deg", "powertrain.differential.coast_ramp_angle_deg", "powertrain.differential.clutches"]))
	_draw_group_panel(Rect2(868.0, 180.0, 388.0, 482.0), "DIRECCIÓN / FRENADA", _paths(["steering.max_steering_angle", "steering.steering_speed", "brakes.max_brake_torque"]))
	_draw_text(Vector2(640.0, 640.0), "RELACIONES DE MARCHA", 12, C_MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)
	var ratios: Array = vehicle.simulation.powertrain_model.gear_ratios
	var gear_text := "R " + str(snappedf(vehicle.simulation.powertrain_model.reverse_ratio, 0.01))
	for index in ratios.size():
		gear_text += "     " + str(index + 1) + "ª " + str(snappedf(float(ratios[index]), 0.01))
	_draw_text(Vector2(640.0, 656.0), gear_text, 12, C_WHITE, false, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_strategy_page() -> void:
	_draw_panel(Rect2(24.0, 180.0, 1232.0, 482.0), C_PANEL)
	_draw_text(Vector2(54.0, 218.0), "ESTRATEGIA DE CARRERA", 20, C_WHITE, true)
	_draw_text(Vector2(54.0, 247.0), "Combustible y servicio de neumáticos", 14, C_MUTED)
	var fuel_field := RallySetupCatalog.field_for_path("fuel.initial_kg")
	_draw_field_row(fuel_field, Rect2(52.0, 278.0, 458.0, 56.0))
	var fuel_capacity := float(vehicle.simulation.mass_model.fuel_capacity_kg)
	_draw_text(Vector2(66.0, 365.0), "CAPACIDAD DEL DEPÓSITO", 12, C_MUTED, true)
	_draw_text(Vector2(498.0, 365.0), "%0.1f kg" % fuel_capacity, 14, C_WHITE, true, HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_rect(Rect2(64.0, 384.0, 430.0, 9.0), C_STEEL_DARK, true)
	var fuel_fraction := clampf(float(draft_values.get("fuel.initial_kg", 0.0)) / maxf(fuel_capacity, 0.001), 0.0, 1.0)
	_draw_rect(Rect2(64.0, 384.0, 430.0 * fuel_fraction, 9.0), C_GOLD, true)
	var service_rect := Rect2(54.0, 424.0, 454.0, 54.0)
	_draw_rect(service_rect, C_PANEL_ALT, true)
	_draw_rect(Rect2(70.0, 439.0, 22.0, 22.0), C_LINE, false, 2.0)
	if new_tires_service:
		_draw_rect(Rect2(74.0, 443.0, 14.0, 14.0), C_GOLD, true)
	_draw_text(Vector2(108.0, 458.0), "MONTAR NEUMÁTICOS NUEVOS", 15, C_WHITE, true)
	_draw_text(Vector2(56.0, 514.0), "El servicio se ejecuta al aplicar y volver al coche.", 12, C_MUTED)
	_hit_regions.append({"rect": service_rect, "kind": "service"})
	_draw_car_card(Rect2(554.0, 198.0, 636.0, 432.0), "ESTADO DE LOS NEUMÁTICOS")
	var wheel_labels := ["FL", "FR", "RL", "RR"]
	for index in 4:
		var wheel: Dictionary = vehicle.get_tire_thermal_state(index)
		var x := 580.0 + float(index % 2) * 410.0
		var y := 548.0 + float(index >> 1) * 38.0
		_draw_text(Vector2(x, y), "%s   %0.0f kPa   ·   %0.0f °C" % [wheel_labels[index], float(wheel.get("pressure_kpa_gauge", 0.0)), float(wheel.get("tread_c", 0.0))], 12, C_WHITE, true)
	_draw_text(Vector2(105.0, 630.0), "CIRCUITO   " + circuit_name.to_upper(), 14, C_STEEL, true)
	_draw_text(Vector2(510.0, 630.0), "DISTANCIA   %0.1f km" % (circuit_length_m / 1000.0), 14, C_STEEL, true, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_setups_page() -> void:
	_draw_panel(Rect2(24.0, 180.0, 842.0, 482.0), C_PANEL)
	_draw_text(Vector2(52.0, 216.0), "REGLAJES GUARDADOS", 20, C_WHITE, true)
	_draw_text(Vector2(52.0, 241.0), circuit_name.to_upper() + "  ·  " + mode.to_upper() + "  ·  FORD ESCORT RS2000", 12, C_MUTED)
	var list_rect := Rect2(44.0, 260.0, 802.0, 346.0)
	_draw_rect(list_rect, C_BG, true)
	for visible_index in mini(maxi(setup_rows.size() - setup_scroll_offset, 0), 7):
		var index := setup_scroll_offset + visible_index
		var row := setup_rows[index]
		var rect := Rect2(54.0, 270.0 + float(visible_index) * 46.0, 782.0, 40.0)
		var selected := index == selected_setup_index
		_draw_rect(rect, C_STEEL_DARK if selected else C_PANEL, true)
		if selected:
			_draw_rect(Rect2(rect.position.x, rect.position.y, 4.0, rect.size.y), C_GOLD, true)
		_draw_text(Vector2(rect.position.x + 16.0, rect.position.y + 26.0), str(row.get("name", "Reglaje")), 14, C_WHITE, true)
		_draw_text(Vector2(rect.position.x + 414.0, rect.position.y + 26.0), team_name.to_upper(), 10, C_MUTED)
		_draw_text(Vector2(rect.end.x - 12.0, rect.position.y + 26.0), _short_timestamp(str(row.get("modified_at", ""))), 10, C_MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)
		_hit_regions.append({"rect": rect, "kind": "setup_row", "index": index})
	if setup_rows.is_empty():
		_draw_text(list_rect.get_center() + Vector2(0.0, 4.0), "NO HAY REGLAJES GUARDADOS PARA ESTE CIRCUITO", 13, C_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text(Vector2(52.0, 638.0), database_status, 10, C_MUTED)
	_draw_panel(Rect2(888.0, 180.0, 368.0, 482.0), C_PANEL)
	_draw_text(Vector2(920.0, 216.0), "GESTIÓN", 18, C_WHITE, true)
	_draw_button(Rect2(918.0, 250.0, 308.0, 48.0), "NUEVO REGLAJE", "new", true)
	_draw_button(Rect2(918.0, 312.0, 308.0, 48.0), "GUARDAR SELECCIONADO", "save")
	_draw_button(Rect2(918.0, 374.0, 308.0, 48.0), "CARGAR Y APLICAR", "load")
	_draw_button(Rect2(918.0, 436.0, 308.0, 48.0), "ELIMINAR", "delete")
	_draw_line(Vector2(918.0, 512.0), Vector2(1226.0, 512.0), C_LINE, 1.0)
	_draw_text(Vector2(920.0, 540.0), "ALMACENAMIENTO", 11, C_GOLD, true)
	_draw_text(Vector2(920.0, 565.0), "SQLite local  ·  user://open_formula.db", 11, C_MUTED)
	_draw_text(Vector2(920.0, 591.0), "Perfil: " + str(vehicle.rally_profile.get("profile_id", "Ford Escort")), 10, C_MUTED)
	_draw_text(Vector2(920.0, 617.0), "Modo: " + mode.to_upper(), 11, C_STEEL, true)


func _draw_footer() -> void:
	_draw_line(Vector2(24.0, 696.0), Vector2(1256.0, 696.0), C_LINE, 1.0)
	if page == 4:
		_draw_button(Rect2(24.0, 718.0, 210.0, 52.0), "RESTAURAR PERFIL", "reset")
		_draw_button(Rect2(944.0, 718.0, 130.0, 52.0), "CANCELAR", "cancel")
		_draw_button(Rect2(1084.0, 718.0, 172.0, 52.0), "APLICAR Y VOLVER", "apply", true)
	else:
		_draw_button(Rect2(24.0, 718.0, 210.0, 52.0), "RESTABLECER", "reset")
		_draw_text(Vector2(640.0, 750.0), "W/S O ↑/↓ NAVEGAR     Q/E O ←/→ AJUSTAR     RE PÁG/AV PÁG CAMBIAR PÁGINA", 11, C_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_button(Rect2(944.0, 718.0, 130.0, 52.0), "CANCELAR", "cancel")
		_draw_button(Rect2(1084.0, 718.0, 172.0, 52.0), "APLICAR Y VOLVER", "apply", true)
	_draw_text(Vector2(1256.0, 792.0), "F5 / START  APLICAR     ESC / B  CANCELAR", 9, C_MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_group_panel(rect: Rect2, title: String, paths: Array[String], row_height: float = 36.0) -> void:
	_draw_panel(rect, C_PANEL)
	_draw_text(Vector2(rect.position.x + 16.0, rect.position.y + 24.0), title, 12, C_GOLD, true)
	_draw_line(Vector2(rect.position.x + 14.0, rect.position.y + 34.0), Vector2(rect.end.x - 14.0, rect.position.y + 34.0), C_LINE, 1.0)
	var row_y := rect.position.y + 41.0
	for path in paths:
		var field := RallySetupCatalog.field_for_path(path)
		if field.is_empty():
			continue
		_draw_field_row(field, Rect2(rect.position.x + 10.0, row_y, rect.size.x - 20.0, row_height))
		row_y += row_height


func _draw_field_row(field: Dictionary, rect: Rect2) -> void:
	var path: String = str(field.path)
	var selected := selected_field_path == path
	_draw_rect(rect, C_PANEL_ALT if selected else Color(C_PANEL_ALT, 0.45), true)
	if selected:
		_draw_rect(Rect2(rect.position.x, rect.position.y, 3.0, rect.size.y), C_GOLD, true)
	var display_value := float(draft_values.get(path, 0.0)) * float(field.scale)
	var formatted := String.num(display_value, int(field.digits)) + str(field.suffix)
	_draw_text(Vector2(rect.position.x + 8.0, rect.position.y + 14.0), str(field.label), 10 if rect.size.x < 360.0 else 12, C_WHITE if selected else C_MUTED)
	_draw_text(Vector2(rect.end.x - 8.0, rect.position.y + 14.0), formatted, 11 if rect.size.x < 360.0 else 12, C_GOLD, true, HORIZONTAL_ALIGNMENT_RIGHT)
	var track_rect := Rect2(rect.position.x + 34.0, rect.position.y + rect.size.y - 9.0, rect.size.x - 68.0, 2.0)
	_draw_rect(track_rect, C_LINE, true)
	var range_value := maxf(float(field.max) - float(field.min), 0.0001)
	var fraction := clampf((float(draft_values.get(path, 0.0)) - float(field.min)) / range_value, 0.0, 1.0)
	_draw_rect(Rect2(track_rect.position, Vector2(track_rect.size.x * fraction, track_rect.size.y)), C_STEEL, true)
	draw_circle(Vector2(track_rect.position.x + track_rect.size.x * fraction, track_rect.position.y + 1.0), 4.0, C_GOLD if selected else C_WHITE)
	_hit_regions.append({"rect": rect, "kind": "field", "path": path, "slider": false})
	_hit_regions.append({"rect": track_rect.grow(6.0), "kind": "field", "path": path, "slider": true})
	_hit_regions.append({"rect": Rect2(rect.position.x + 2.0, rect.end.y - 17.0, 24.0, 16.0), "kind": "adjust", "path": path, "amount": -1.0})
	_hit_regions.append({"rect": Rect2(rect.end.x - 26.0, rect.end.y - 17.0, 24.0, 16.0), "kind": "adjust", "path": path, "amount": 1.0})
	_draw_text(Vector2(rect.position.x + 12.0, rect.end.y - 2.0), "−", 11, C_MUTED, true)
	_draw_text(Vector2(rect.end.x - 12.0, rect.end.y - 2.0), "+", 11, C_MUTED, true, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_car_card(rect: Rect2, title: String) -> void:
	_draw_panel(rect, C_PANEL)
	_draw_text(Vector2(rect.get_center().x, rect.position.y + 26.0), title, 13, C_MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)
	var image_height := minf(rect.size.y - 72.0, 365.0)
	var image_width := image_height * 0.55
	var image_rect := Rect2(rect.get_center().x - image_width * 0.5, rect.position.y + 40.0, image_width, image_height)
	draw_texture_rect(CAR_TEXTURE, image_rect, false, Color(1.0, 1.0, 1.0, 0.88))
	_draw_line(Vector2(rect.position.x + 26.0, rect.end.y - 22.0), Vector2(rect.end.x - 26.0, rect.end.y - 22.0), C_LINE, 1.0)


func _draw_button(rect: Rect2, label: String, action: String, primary: bool = false) -> void:
	var fill := C_STEEL if primary else C_PANEL
	_draw_rect(rect, fill, true)
	_draw_rect(rect, C_GOLD if primary else C_LINE, false, 1.0)
	_draw_text(rect.get_center() + Vector2(0.0, 5.0), label, 12, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	_hit_regions.append({"rect": rect, "kind": "button", "action": action})


func _draw_modal() -> void:
	draw_rect(Rect2(Vector2.ZERO, LOGICAL_SIZE), Color(0.0, 0.0, 0.0, 0.70))
	var rect := Rect2(384.0, 280.0, 512.0, 230.0)
	_draw_panel(rect, C_PANEL_ALT)
	_draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 4.0), C_GOLD, true)
	if modal_mode == "name":
		_draw_text(Vector2(640.0, 332.0), "GUARDAR REGLAJE", 20, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_text(Vector2(424.0, 376.0), "Nombre (1–100 caracteres)", 13, C_MUTED)
		_draw_rect(Rect2(424.0, 392.0, 432.0, 42.0), C_BG, true)
		_draw_rect(Rect2(424.0, 392.0, 432.0, 42.0), C_STEEL, false, 1.0)
		_draw_text(Vector2(440.0, 419.0), modal_text + "▌", 15, C_WHITE)
		_draw_text(Vector2(640.0, 474.0), "ENTER GUARDAR    ·    ESC CANCELAR", 11, C_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_text(Vector2(640.0, 495.0), "MANDO: ←/→ ELEGIR   ·   A AÑADIR   ·   LB BORRAR   ·   START GUARDAR", 9, C_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	elif modal_mode == "delete":
		_draw_text(Vector2(640.0, 350.0), "ELIMINAR REGLAJE", 20, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
		var selected_name := "este reglaje"
		for row in setup_rows:
			if int(row.get("id", -1)) == selected_setup_id:
				selected_name = str(row.get("name", selected_name))
		_draw_text(Vector2(640.0, 394.0), "¿Eliminar «" + selected_name + "»?", 14, C_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_text(Vector2(640.0, 458.0), "ENTER ELIMINAR    ·    ESC CANCELAR", 12, C_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_draw_text(Vector2(640.0, 350.0), "DESCARTAR CAMBIOS", 20, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_text(Vector2(640.0, 394.0), "Se restaurará el reglaje que tenías al abrir el garage.", 13, C_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_text(Vector2(640.0, 458.0), "ENTER / ACEPTAR DESCARTE    ·    ESC / B SEGUIR EDITANDO", 11, C_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_notice() -> void:
	var is_error := notice.to_lower().contains("no se") or notice.to_lower().contains("error") or notice.to_lower().contains("incompatible")
	var rect := Rect2(310.0, 664.0, 660.0, 34.0)
	_draw_rect(rect, C_RED if is_error else C_STEEL_DARK, true)
	_draw_text(rect.get_center() + Vector2(0.0, 5.0), notice, 11, C_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_panel(rect: Rect2, color: Color) -> void:
	_draw_rect(rect, color, true)
	_draw_rect(rect, C_LINE, false, 1.0)


func _draw_rect(rect: Rect2, color: Color, filled: bool, width: float = 1.0) -> void:
	draw_rect(rect, color, filled, width)


func _draw_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	draw_line(from, to, color, width)


func _draw_text(baseline: Vector2, text: String, font_size: int, color: Color, bold: bool = false, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var font := FONT_BOLD if bold else FONT_REGULAR
	draw_string(font, baseline, text, alignment, -1.0, font_size, color)


func _paths(paths: Array) -> Array[String]:
	var result: Array[String] = []
	for path in paths:
		result.append(str(path))
	return result


func _short_timestamp(value: String) -> String:
	if value.is_empty():
		return ""
	return value.replace("T", " ").trim_suffix("Z").left(19)
