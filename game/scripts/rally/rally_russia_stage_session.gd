class_name RallyRussiaStageSession
extends Node3D

const STAGE_MANIFEST_PATH := "res://assets/rally/russia_stage1/manifest.json"
const FALLBACK_START_POSITION := Vector3(-2.18, -1.7963, -38.388)
const FALLBACK_START_HEADING := -0.0008558533301677789
const SPAWN_CLEARANCE_METRES := 0.08
const MINIMUM_WORLD_HEIGHT_METRES := -50.0
# Sesión genérica del evento de Rusia (Entrega 1): el track activo se
# resuelve por ID con RallyStageLoader. STAGE_MANIFEST_PATH queda como
# respaldo legado para la escena Stage 1 existente.
@export var track_id: String = "russia_stage1"
@export var practice_mode: bool = false
@export var event_seed: int = 0

@export var vehicle_path: NodePath
@export var input_controller_path: NodePath
@export var camera_rig_path: NodePath
@export var head_up_display_path: NodePath
@export var telemetry_recorder_path: NodePath
@export var track_collision_path: NodePath
@export var track_visual_path: NodePath
@export var garage_panel_path: NodePath = NodePath("RallyGaragePanel")
@export var weather_enabled: bool = true
@export var weather_season_path: String = "res://data/weather/russia_winter_overcast.tres"
@export var weather_start_weather: int = 0
@export var weather_speed_multiplier: float = 1.0
@export_group("Tropospheric Sky")
@export_range(0.0, 23.99) var sky_start_hour: float = 11.0
@export var weather_minutes_per_day: float = 24.0
@export var sky_exposure: float = 1.0
@export_group("Dreamcast Aesthetics")
@export var dreamcast_visual_mode: bool = true
@export_group("TCA")

var vehicle: RallyEscortVehicle
var input_controller: RallyVehicleInputController
var camera_rig: RallyChaseCameraRig
var head_up_display: RallyF1HeadUpDisplay
var telemetry_recorder: RallyTelemetryRecorder
var track_collision: RallyTrackCollisionBuilder
var track_visual: Node3D
var start_position: Vector3 = FALLBACK_START_POSITION
var start_heading: float = FALLBACK_START_HEADING
var elapsed_seconds: float = 0.0
var session_ready: bool = false
var stage_transition_running: bool = false
var telemetry_file_path: String = ""
var run_identifier: String = ""
var start_sequence = preload("res://scripts/rally/rally_start_sequence.gd").new()
var start_click: AudioStreamPlayer
var start_horn: AudioStreamPlayer
var course := RallyStageProgress.new()
var competition = preload("res://scripts/rally/rally_competition.gd").new()
var pacenotes = preload("res://scripts/rally/rally_pacenote_controller.gd").new()
const StageLoaderScript := preload("res://scripts/rally/rally_stage_loader.gd")
const EventManagerScript := preload("res://scripts/rally/rally_event_manager.gd")
const EventClockScript := preload("res://scripts/rally/rally_event_clock.gd")
var stage_loader = StageLoaderScript.new()
var event_manager = null
var event_clock = EventClockScript.new()
var resolved_stage: Dictionary = {}
var session_track_id: String = "russia_stage1"
var pacenote_hud: Control = null
const TroposphericSky := preload("res://scripts/rally/rally_tropospheric_sky.gd")
var weather_sky_node: TroposphericSky
var weather_controller_node: Node = null
var terrain_wetness: Node = null
var weather_is_raining: bool = false
var garage_panel: Control = null
var event_weather = preload("res://scripts/rally/rally_weather_controller.gd").new()
var awaiting_setup: bool = false
var setup_open_count: int = 0


func _ready() -> void:
	var shared_telemetry_manager := get_node_or_null("/root/TelemetryManager")
	if shared_telemetry_manager != null:
		shared_telemetry_manager.enabled = false
	vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	input_controller = get_node_or_null(input_controller_path) as RallyVehicleInputController
	camera_rig = get_node_or_null(camera_rig_path) as RallyChaseCameraRig
	head_up_display = get_node_or_null(head_up_display_path) as RallyF1HeadUpDisplay
	telemetry_recorder = get_node_or_null(telemetry_recorder_path) as RallyTelemetryRecorder
	track_collision = get_node_or_null(track_collision_path) as RallyTrackCollisionBuilder
	track_visual = get_node_or_null(track_visual_path) as Node3D
	if vehicle == null or input_controller == null or camera_rig == null or head_up_display == null:
		push_error("Rally session is missing a mandatory runtime binding")
		return
	vehicle.freeze = true
	if telemetry_recorder != null:
		telemetry_recorder.set_physics_process(false)
	session_track_id = track_id if StageLoaderScript.is_valid_track_id(track_id) else "russia_stage1"
	resolved_stage = stage_loader.resolve(session_track_id)
	if resolved_stage.is_empty():
		push_error("Rally stage: " + stage_loader.error + " (sin sustitución por Stage 1)")
		return
	var route_path: String = (resolved_stage["paths"] as Dictionary)["route"]
	if not course.configure(route_path):
		push_error("Russia course timing route is missing: " + route_path)
		return
	var stage_config_path: String = (resolved_stage["paths"] as Dictionary)["stage_config"]
	if practice_mode:
		if not competition.configure(stage_config_path, event_seed):
			push_error("Rally competition: " + competition.error)
			return
	else:
		if event_manager == null:
			event_manager = EventManagerScript.new()
			if not event_manager.begin_event({"seed": event_seed}):
				push_error("Rally event: " + event_manager.error)
				return
		# La simulación de la especial la lleva competition; los acumulados
		# oficiales los lleva el manager. Aquí se configura la especial actual.
		if not competition.configure(stage_config_path, event_manager.seed_value):
			push_error("Rally competition: " + competition.error)
			return
		competition.save_path = ""
		event_manager.sim = competition
		competition.set_weather_context(event_manager.weather_entry_for(session_track_id), event_manager.rival_compounds.get(session_track_id, {}))
	course.sector_indices = competition.stage.sector_checkpoint_indices
	if not course.configure_timing_gates(competition.stage.timing_gates):
		push_error("Original rally split gates could not be configured")
		return
	if practice_mode:
		if competition.restore() and not competition.complete and competition.started:
			competition.retire_player("Abandono — sesión interrumpida")
	build_environment()
	event_clock.attach_adapters(weather_sky_node, weather_controller_node)
	if not practice_mode and event_manager != null:
		start_clock_for_stage(event_manager.schedule_for(session_track_id))
		_setup_event_weather()
	else:
		event_clock.configure(event_clock.event_date, sky_start_hour * 3600.0, 1.0)
		event_clock.set_paused(false)
	# Compuesto confirmado antes de precalentar (objetivos térmicos por compuesto).
	if not practice_mode and event_manager != null and vehicle.has_method("set_tire_compound"):
		vehicle.set_tire_compound(event_manager.confirmed_compound_id)
		for i in mini(4, event_manager.mounted_tire_condition.size()):
			var condition: Dictionary = event_manager.mounted_tire_condition[i]
			vehicle.simulation.thermal_model.tire_states[i].wear_fraction = clampf(float(condition.get("wear_fraction", 0.0)), 0.0, 1.0)
			vehicle.simulation.thermal_model.tire_states[i].thermal_damage_fraction = clampf(float(condition.get("thermal_damage_fraction", 0.0)), 0.0, 1.0)
	apply_start_pose_from_manifest()
	vehicle.ensure_tire_inventory()
	if not practice_mode and event_manager != null and not event_manager.tire_inventory_state.is_empty():
		if not vehicle.tire_inventory.restore(event_manager.tire_inventory_state):
			push_error("Inventario de neumáticos guardado inválido")
			return
		var saved_brakes: Variant = event_manager.tire_inventory_state.get("brake_collision_loss", [])
		if saved_brakes is Array:
			for i in mini(saved_brakes.size(), 4):
				vehicle.simulation.brake_collision_loss[i] = clampf(float(saved_brakes[i]), 0.0, 1.0)
		var saved_alignment: Variant = event_manager.tire_inventory_state.get("alignment_collision_damage", [])
		if saved_alignment is Array:
			for i in mini(saved_alignment.size(), 4):
				vehicle.simulation.alignment_collision_damage[i] = clampf(float(saved_alignment[i]), 0.0, 1.0)
	vehicle.apply_tire_inventory()
	if track_collision == null:
		push_error("Rally session cannot resolve the stage collision builder")
		return
	var collision_ready: bool = await _swap_stage_geometry(resolved_stage)
	if not collision_ready:
		push_error("Rally session cannot build the stage collision")
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	place_vehicle_on_stage()
	_refresh_stage_weather()
	connect_runtime_signals()
	configure_runtime_paths()
	_connect_garage_panel()
	var pause_inventory = preload("res://scripts/rally/rally_pause_inventory.gd").new()
	pause_inventory.session = self
	add_child(pause_inventory)
	if telemetry_recorder != null:
		telemetry_recorder.set_physics_process(true)
	session_ready = true
	var panel: Control = head_up_display.competition_panel
	panel.retire_requested.connect(retire_competition_player)
	panel.retry_requested.connect(retry_competition_attempt)
	panel.next_requested.connect(continue_competition)
	panel.new_rally_requested.connect(start_new_competition)
	setup_start_audio()
	setup_pacenotes()
	reset_start_sequence()
	apply_competition_controls()
	_update_panel_for_stage()
	# Ventana inicial de reglaje (Neumáticos primero, Aceptar inicia la salida).
	if not practice_mode and event_manager != null and not event_manager.get_pending_window().is_empty():
		_open_setup_window()
	print("RALLY_SESSION_READY scene=%s vehicle=ford_escort_rs2000_1971 spawn=" % session_track_id, start_position, " heading_radians=", start_heading, " physics_engine=", ProjectSettings.get_setting("physics/3d/physics_engine"))


func build_environment() -> void:
	weather_sky_node = TroposphericSky.new()
	weather_sky_node.name = "RallyTroposphericSky"
	weather_sky_node.current_time = sky_start_hour
	weather_sky_node.dreamcast_visual_mode = dreamcast_visual_mode
	weather_sky_node.exposure = sky_exposure
	add_child(weather_sky_node)
	if not weather_enabled:
		return
	const TCA_WEATHER_SCRIPT := "res://addons/TCA_Weather_System/scripts/WeatherController.gd"
	if not ResourceLoader.exists(TCA_WEATHER_SCRIPT) or not ResourceLoader.exists(weather_season_path):
		push_warning("TCA weather resources missing; tropospheric sky remains active")
		return
	var season_res: Resource = load(weather_season_path)
	if season_res == null:
		return
	_build_terrain_wetness()
	if _build_tca_precipitation(TCA_WEATHER_SCRIPT, season_res):
		print("RALLY_WEATHER_READY sky=tropospheric precipitation=TCA season=", weather_season_path)


func _build_tca_precipitation(script_path: String, season_res: Resource) -> bool:
	var weather_script := load(script_path) as Script
	if weather_script == null:
		push_warning("TCA WeatherController failed to load")
		return false
	var controller: Node = weather_script.new()
	if controller == null:
		push_warning("TCA WeatherController failed to instantiate")
		return false
	controller.name = "TCAWeatherController"
	# TCA solo lleva clima y precipitación.
	controller.set("drive_environment", false)
	var seasons: Array = controller.get("seasons")
	if seasons == null:
		seasons = []
		controller.set("seasons", seasons)
	seasons.clear()
	seasons.append(season_res)
	var minutes_per_day: float = maxf(weather_minutes_per_day, 0.1)
	var tca_speed: float = (86400.0 / (minutes_per_day * 60.0)) * maxf(weather_speed_multiplier, 0.01)
	controller.set("time_speed_multiplier", tca_speed)
	controller.set("start_time", clampf(sky_start_hour, 0.0, 23.99) / 24.0 * 86400.0)
	controller.set("start_season", 0)
	controller.set("start_weather", weather_start_weather)
	# Las senales se conectan antes de entrar al arbol: el clima inicial se emite en _ready().
	controller.connect(&"weather_changed", _on_tca_weather_changed)
	controller.connect(&"weather_ended", _on_tca_weather_ended)
	controller.connect(&"season_changed", _on_tca_season_changed)
	add_child(controller)
	weather_controller_node = controller
	return true


func _build_terrain_wetness() -> void:
	# Wet albedo must remain visible in the retro pipeline too; the material
	# adjuster already disables specular, so wetness does not add PBR reflections.
	if track_visual == null:
		return
	var wetness_node := preload("res://scripts/rally/rally_terrain_wetness.gd").new()
	wetness_node.name = "RallyTerrainWetness"
	wetness_node.set("visual_root", track_visual)
	add_child(wetness_node)
	terrain_wetness = wetness_node


func _on_tca_weather_changed(weather) -> void:
	# Con calendario activo la selección aleatoria autónoma de TCA está
	# desactivada: la fuente única es el cronograma (no una segunda secuencia).
	if not practice_mode and event_weather.calendar_active:
		return
	var description := describe_tca_weather(weather)
	var precipitation: Variant = weather.get("precipitation")
	var is_precipitating := precipitation != null
	weather_is_raining = is_precipitating and description.contains("RAIN")
	if terrain_wetness != null:
		terrain_wetness.set_rain_intensity(1.0 if weather_is_raining else 0.0)
	if weather_sky_node != null and weather != null:
		var cover := float(weather.get("large_cloud_cover"))
		weather_sky_node.set_practice_weather(maxf(cover, 0.92) if is_precipitating else cover,
			float(weather.get("fog_density")))
	print("RALLY_WEATHER_CHANGED ", description, " precipitation=", is_precipitating, " raining=", weather_is_raining)
	if head_up_display != null and session_ready:
		head_up_display.show_status("WEATHER " + description.to_upper(), Color(0.62, 0.78, 0.95), 2.4)


func _on_tca_weather_ended(_weather) -> void:
	print("RALLY_WEATHER_ENDED")


func _on_tca_season_changed(season) -> void:
	print("RALLY_SEASON_CHANGED season=", season.get("season_id"))


func describe_tca_weather(weather) -> String:
	if weather == null:
		return "UNKNOWN"
	var precipitation: Variant = weather.get("precipitation")
	if precipitation != null:
		var particles: Variant = precipitation.get("particles")
		var particles_path := ""
		if particles is PackedScene:
			particles_path = (particles as PackedScene).resource_path.to_lower()
		var is_snow := particles_path.contains("snow")
		if float(weather.get("large_cloud_cover")) >= 0.9:
			return "HEAVY SNOW" if is_snow else "HEAVY RAIN"
		return "SNOW" if is_snow else "RAIN"
	if float(weather.get("fog_density")) > 0.01:
		return "FOG"
	if float(weather.get("fog_density")) > 0.003:
		return "LIGHT FOG"
	if float(weather.get("large_cloud_cover")) >= 0.6:
		return "OVERCAST"
	if float(weather.get("large_cloud_cover")) >= 0.35:
		return "CLOUDY"
	return "CLEAR"


func apply_start_pose_from_manifest() -> void:
	if not resolved_stage.is_empty():
		var start_pose: Variant = (resolved_stage.get("manifest", {}) as Dictionary).get("start_pose", {})
		if start_pose is Dictionary:
			var ground: Variant = start_pose.get("ground_godot", [])
			if ground is Array and ground.size() == 3:
				start_position = Vector3(float(ground[0]), float(ground[1]), float(ground[2]))
			start_heading = float(start_pose.get("heading_radians", FALLBACK_START_HEADING))
			return
	if not FileAccess.file_exists(STAGE_MANIFEST_PATH):
		return
		return
	var file := FileAccess.open(STAGE_MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var document: Dictionary = parsed
	var start_pose: Variant = document.get("start_pose", {})
	if not start_pose is Dictionary:
		return
	var ground: Variant = start_pose.get("ground_godot", [])
	if ground is Array and ground.size() == 3:
		start_position = Vector3(float(ground[0]), float(ground[1]), float(ground[2]))
	start_heading = float(start_pose.get("heading_radians", FALLBACK_START_HEADING))


func place_vehicle_on_stage() -> void:
	var ground_query := PhysicsRayQueryParameters3D.create(
		Vector3(start_position.x, start_position.y + 30.0, start_position.z),
		Vector3(start_position.x, start_position.y - 30.0, start_position.z),
		1
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(ground_query)
	var surface_position := start_position
	var surface_normal := Vector3.UP
	if not hit.is_empty():
		surface_normal = hit["normal"]
		surface_position = hit["position"]
		print("RALLY_START_SURFACE hit=", surface_position, " normal=", surface_normal, " collider=", hit["collider"].name)
	var heading_forward := Basis(Vector3.UP, start_heading) * Vector3.FORWARD
	var right_axis := heading_forward.cross(surface_normal).normalized()
	if right_axis.length_squared() < 0.001:
		right_axis = Vector3.RIGHT
	var forward_axis := surface_normal.cross(right_axis).normalized()
	var start_basis := Basis(right_axis, surface_normal, -forward_axis)
	start_position = surface_position + surface_normal * SPAWN_CLEARANCE_METRES
	vehicle.reset_to_pose(start_position, start_heading)
	vehicle.global_transform = Transform3D(start_basis, start_position)
	vehicle.prepare_for_stage()
	vehicle.simulation.unsprung_rig.reset()
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.sleeping = false
	vehicle.freeze = false
	input_controller.set_spawn_pose(start_position, start_heading)
	input_controller.arm_start_handbrake()
	camera_rig.snap_to_target()
	head_up_display.show_status("READY  ARROWS DRIVE  A/Z SHIFT  DELETE AUTO  T TCS  R RESET  C CAMERA", Color(0.34, 0.82, 0.45), 4.0)


func connect_runtime_signals() -> void:
	input_controller.camera_mode_toggle_requested.connect(on_camera_mode_toggle_requested)
	input_controller.driving_assistance_changed.connect(on_driving_assistance_changed)
	input_controller.vehicle_reset_requested.connect(on_vehicle_reset_requested)


func configure_runtime_paths() -> void:
	head_up_display.set_vehicle(vehicle)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rally-telemetry="):
			telemetry_file_path = argument.trim_prefix("--rally-telemetry=")
		elif argument.begins_with("--rally-run-id="):
			run_identifier = argument.trim_prefix("--rally-run-id=")
	head_up_display.set_telemetry_path(telemetry_file_path)
	var metadata := {
		"run_identifier": run_identifier,
		"scene": "russia_stage1_ford_escort_rs2000",
		"physics_engine": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"start_position": [start_position.x, start_position.y, start_position.z],
		"start_heading_radians": start_heading,
	}
	print("RALLY_SESSION_METADATA ", JSON.stringify(metadata))


func on_camera_mode_toggle_requested() -> void:
	camera_rig.toggle_camera_mode()
	head_up_display.show_status("CAMERA MODE " + camera_rig.get_camera_mode_label(), Color(0.94, 0.55, 0.16), 1.6)


func on_driving_assistance_changed(state: Dictionary) -> void:
	var active_assistance: Array[String] = []
	if bool(state.get("traction_control", false)):
		active_assistance.append("TCS")
	if bool(state.get("stability", false)):
		active_assistance.append("STABILITY")
	if bool(state.get("anti_lock_brakes", false)):
		active_assistance.append("ABS")
	if bool(state.get("countersteer", false)):
		active_assistance.append("COUNTERSTEER")
	var summary := "ASSISTS: " + (", ".join(active_assistance) if not active_assistance.is_empty() else "NONE")
	summary += "  AUTO: " + ("ON" if bool(state.get("automatic_transmission", false)) else "OFF")
	head_up_display.show_status(summary, Color(0.94, 0.55, 0.16), 2.4)
	print("RALLY_ASSISTANCE ", JSON.stringify(state))


func _reposition_vehicle_on_course() -> bool:
	if vehicle == null or course.points.size() < 2:
		return false
	var closest := INF
	var target := course.points[0]
	var direction := course.points[1] - target
	var position := vehicle.global_position
	for index in range(course.points.size() - 1):
		var a: Vector3 = course.points[index]
		var segment: Vector3 = course.points[index + 1] - a
		if segment.length_squared() < 0.0001:
			continue
		var t := clampf((position - a).dot(segment) / segment.length_squared(), 0.0, 1.0)
		var candidate := a + segment * t
		var distance := position.distance_squared_to(candidate)
		if distance < closest:
			closest = distance
			target = candidate
			direction = segment
	var heading := atan2(-direction.x, -direction.z)
	var basis := Basis(Vector3.UP, heading)
	var support_height := -INF
	for i in vehicle.simulation.wheel_positions_local.size():
		var offset: Vector3 = basis * vehicle.simulation.wheel_positions_local[i]
		var wheel_center := target + offset
		var query := PhysicsRayQueryParameters3D.create(
			wheel_center + Vector3.UP * 3.0,
			wheel_center - Vector3.UP * 6.0,
			1,
			[vehicle.get_rid()]
		)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and (hit.normal as Vector3).y > 0.35:
			support_height = maxf(support_height, (hit.position as Vector3).y + vehicle.simulation.wheel_radii[i] - offset.y)
	if is_finite(support_height):
		target.y = support_height + 0.08
	else:
		target = start_position
		heading = start_heading
	vehicle.rescue_to_pose(target, heading)
	course.generation = vehicle.simulation.session_generation
	course.previous_position = target
	competition.generation = course.generation
	camera_rig.snap_to_target()
	pacenotes.on_rescue(target)
	if not practice_mode and event_weather.calendar_active:
		event_weather.on_rescue(target)
	return true


func on_vehicle_reset_requested() -> void:
	if competition.complete or not _reposition_vehicle_on_course():
		return
	if course.running:
		competition.add_penalty("player", int(competition.balance.reset_penalty_ms), "Rescate")
		head_up_display.show_status("RESCATE +%.0f s" % (float(competition.balance.reset_penalty_ms) / 1000.0), Color(0.95, 0.72, 0.24), 2.2)
	else:
		head_up_display.show_status("COCHE RESTABLECIDO", Color(0.95, 0.72, 0.24), 2.2)


func on_quick_repair_radiator_requested() -> bool:
	if competition.complete or vehicle == null or vehicle.simulation == null or vehicle.simulation.thermal_model == null:
		return false
	var tm: VehicleThermalModel = vehicle.simulation.thermal_model
	if tm.radiator_damage < 0.05:
		return false
	if not tm.quick_repair_radiator():
		return false
	_reposition_vehicle_on_course()
	competition.add_penalty("player", 60000, "Reparación de radiador")
	if head_up_display != null:
		var target_pct := roundi(tm.radiator_damage * 100.0)
		head_up_display.show_status("REPARACIÓN DE RADIADOR (%d%%) +60 s" % target_pct, Color(0.95, 0.72, 0.24), 3.0)
	return true


var _weather_visual_elapsed := 0.1


func _physics_process(delta: float) -> void:
	if not session_ready or vehicle == null:
		return
	elapsed_seconds += delta
	# Mientras se elige reglaje: cuenta atrás, reloj y coche detenidos.
	if awaiting_setup:
		event_weather.tick_visual(delta)
		head_up_display.set_session_state(get_session_state())
		return
	# Reloj ambiental único: avanza en cuenta atrás y conducción, se detiene
	# en pausa, carga y pantallas de resultados. Nunca toca Engine.time_scale.
	var driving_window = not competition.complete or start_sequence.readout().get("phase", "") in ["ready", "go"]
	var clock_advancing: bool = driving_window and not get_tree().paused
	event_clock.tick(delta, clock_advancing)
	# Controlador climático: proyección + evolución + adaptadores (fuente única).
	if not practice_mode and event_weather.calendar_active:
		event_weather.update_vehicle_position(vehicle.global_position)
		if clock_advancing:
			event_weather.advance_ambient(delta * maxf(event_clock.rate, 0.0), event_weather.solar_factor_for_hour(event_clock.hour_of_day()))
		event_weather.tick_visual(delta)
		_weather_visual_elapsed += delta
		if _weather_visual_elapsed >= 0.1:
			_weather_visual_elapsed = fmod(_weather_visual_elapsed, 0.1)
			event_weather.apply_to_adapters(weather_sky_node, weather_controller_node, terrain_wetness, event_clock.hour_of_day())
	if not competition.complete:
		var signal_state: Dictionary = start_sequence.advance(delta, vehicle.global_position, vehicle.linear_velocity.length())
		for event: String in signal_state.events:
			if event == "click":
				start_click.play()
				var remaining: int = 3 - int(floor(start_sequence.elapsed - 0.5))
				pacenotes.on_start_countdown(clampi(remaining, 1, 3))
			elif event == "go":
				course.clock_started = true
				start_horn.play()
				pacenotes.on_start_countdown(0)
			elif event == "false_start":
				competition.add_penalty("player", 10000, "Salida anticipada")
				head_up_display.show_status("FALSE START +10 s", Color(1.0, 0.25, 0.1), 3.0)
		var previous_sector: int = competition.sector
		course.advance(vehicle.global_position, float(signal_state.racing_dt), vehicle.simulation.session_generation, vehicle.linear_velocity.length())
		pacenotes.advance(vehicle.global_position, float(signal_state.racing_dt) if course.clock_started else delta)
		if course.clock_started:
			competition.update(course.readout())
			if competition.sector > previous_sector and not competition.complete:
				head_up_display.show_partial(competition.sector, competition.partial_delta_ms())
		if competition.complete:
			pacenotes.on_retire()
			apply_competition_controls()
	if vehicle.global_position.y < MINIMUM_WORLD_HEIGHT_METRES and not competition.complete:
		competition.retire_player("Abandono — salida de pista")
		apply_competition_controls()
	if vehicle.sleeping:
		vehicle.sleeping = false
	head_up_display.set_session_state(get_session_state())


func get_session_state() -> Dictionary:
	var course_state: Dictionary = course.readout()
	course_state["label"] = stage_label()
	return {
		"elapsed_seconds": elapsed_seconds,
		"course": course_state,
		"competition": get_competition_panel_state(),
		"pacenotes": {"next_gate": pacenotes.tracker.next_gate, "active_call": pacenotes.call_queue.get_active_record()},
		"start_sequence": start_sequence.readout() if not competition.complete else {},
		"run_identifier": run_identifier,
		"physics_engine": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"start_position": start_position,
		"start_heading": start_heading,
		"telemetry_file_path": telemetry_file_path,
	}


func stage_label() -> String:
	var number := 1
	if event_manager != null and not practice_mode:
		number = int(event_manager.cursor) + 1
	else:
		number = int(competition.readout().get("leg", 1))
	var place := str(session_track_id)
	var cut := place.rfind("_stage")
	if cut > 0:
		place = place.substr(0, cut)
	place = place.replace("_", " ").strip_edges().to_upper()
	if place.is_empty():
		return "STAGE %d" % number
	return "STAGE %d · %s" % [number, place]


func reset_vehicle_to_start() -> void:
	vehicle.reset_to_pose(start_position, start_heading)
	camera_rig.snap_to_target()
	head_up_display.show_status("VEHICLE RESET TO START", Color(0.95, 0.72, 0.24), 2.2)


func apply_competition_controls() -> void:
	# Bloqueo durante la ventana de reglaje: no hay cuenta atrás ni controles.
	if awaiting_setup:
		input_controller.set_controls_enabled(false)
		vehicle.freeze = true
		event_clock.set_paused(true)
		head_up_display.set_session_state(get_session_state())
		return
	input_controller.set_controls_enabled(not competition.complete)
	vehicle.freeze = competition.complete
	if competition.complete:
		vehicle.linear_velocity = Vector3.ZERO
		vehicle.angular_velocity = Vector3.ZERO
		event_clock.set_paused(true)
		if not practice_mode and event_manager != null and event_manager.is_last_stage() and event_manager.status == "running":
			_close_event_stage(false, "")
			event_manager.advance()
	else:
		event_clock.set_paused(false)
	head_up_display.set_session_state(get_session_state())
	_update_panel_for_stage()

func retire_competition_player() -> void:
	competition.retire_player()
	pacenotes.on_retire()
	apply_competition_controls()

func reset_competition_car() -> void:
	course.reset_attempt()
	pacenotes.on_retry()
	vehicle.reset_to_pose(start_position, start_heading)
	vehicle.prepare_for_stage()
	input_controller.arm_start_handbrake()
	course.generation = vehicle.simulation.session_generation
	reset_start_sequence()
	camera_rig.snap_to_target()
	apply_competition_controls()

func retry_competition_attempt() -> void:
	if not practice_mode:
		if head_up_display != null:
			head_up_display.show_status("MODO OFICIAL: reintentar no reemplaza tiempos", Color(1.0, 0.45, 0.2), 2.5)
		return
	competition.reset_attempt()
	competition.save()
	reset_competition_car()

func continue_competition() -> void:
	if stage_transition_running or not competition.complete:
		return
	if event_manager != null and event_manager.status == "finished":
		return
	if practice_mode:
		if competition.next_stage():
			reset_competition_car()
		return
	_close_event_stage(false, "")
	await _advance_event_stage()

func start_new_competition() -> void:
	if not practice_mode:
		if head_up_display != null:
			head_up_display.show_status("MODO EVENTO: usa el menú del rally", Color(1.0, 0.45, 0.2), 2.5)
		return
	competition.leg = 1
	competition.history.clear()
	competition.previous_totals.clear()
	competition.player_previous_ms = 0
	competition.confidence = 0.0
	competition.level = 1.0
	competition.seed_value += 1
	competition.begin_stage()
	competition.save()
	reset_competition_car()

func withdraw_event_definitive(reason: String = "Retiro definitivo") -> void:
	if practice_mode or event_manager == null:
		retire_competition_player()
		return
	_close_event_stage(true, reason)
	_advance_event_stage()


func _exit_tree() -> void:
	_save_mounted_tire_condition()
	if session_ready and not practice_mode and event_manager != null and event_weather.calendar_active:
		event_manager.save_stage_surface(session_track_id, event_weather.snapshot())
		event_manager.save()
	if session_ready and competition.started:
		competition.save()


func setup_pacenotes() -> void:
	pacenotes.name = "RallyPacenotes"
	add_child(pacenotes)
	if head_up_display != null:
		pacenote_hud = preload("res://scenes/rally/cmr2_pacenote_hud.tscn").instantiate()
		head_up_display.add_child(pacenote_hud)
		pacenotes.set_hud(pacenote_hud)
	pacenotes.configure("res://data/rally/pacenotes/%s.json" % session_track_id)


func setup_start_audio() -> void:
	start_click = AudioStreamPlayer.new()
	start_click.stream = preload("res://scripts/audio/seamless_vehicle_loop.gd").load_pcm("res://sounds/rally_start/ready_click.wav", false)
	start_click.volume_db = -5.0
	add_child(start_click)
	start_horn = AudioStreamPlayer.new()
	start_horn.stream = preload("res://scripts/audio/seamless_vehicle_loop.gd").load_pcm("res://sounds/rally_start/go_horn.wav", false)
	start_horn.volume_db = -5.0
	add_child(start_horn)

func reset_start_sequence() -> void:
	course.external_start = true
	course.clock_started = false
	course.generation = vehicle.simulation.session_generation
	course.previous_position = vehicle.global_position
	start_sequence.reset(vehicle.global_position)
	if start_click != null:
		start_click.stop()
		start_horn.stop()

# --- Evento de Rusia: carga genérica, reloj y continuación ---

func begin_event_session(manager: RefCounted, stage_id: String) -> void:
	event_manager = manager
	practice_mode = false
	track_id = stage_id

func _close_event_stage(definitive: bool, reason: String) -> void:
	if event_manager == null or event_manager.sim == null:
		return
	_save_mounted_tire_condition()
	var measured_ms := int(competition.player_ms + competition.player_penalty_ms)
	var player := {
		"measured_ms": competition.player_ms,
		"penalty_ms": competition.player_penalty_ms,
		"elapsed_ms": measured_ms,
		"retired": competition.player_retired or not competition.complete,
		"definitive": definitive,
		"reason": reason if not reason.is_empty() else competition.player_status,
	}
	# Sincronizar la simulación del manager con la de la sesión.
	event_manager.sim = competition
	# Persistir estados físicos de zonas para continuidad (no se re-sortean).
	if event_weather.calendar_active:
		event_manager.save_stage_surface(session_track_id, event_weather.snapshot())
	event_manager.close_current_stage(player)

func _advance_event_stage() -> void:
	if event_manager == null:
		return
	stage_transition_running = true
	if not event_manager.advance():
		stage_transition_running = false
		push_warning("Rally event advance: " + event_manager.error)
		_update_panel_for_stage()
		return
	if event_manager.status == "finished":
		stage_transition_running = false
		_update_panel_for_stage()
		return
	var next_id = event_manager.current_stage_id()
	await load_event_stage(next_id)
	stage_transition_running = false

func load_event_stage(next_id: String) -> void:
	session_ready = false
	vehicle.freeze = true
	input_controller.set_controls_enabled(false)
	event_clock.set_paused(true)
	awaiting_setup = false
	if telemetry_recorder != null:
		telemetry_recorder.set_physics_process(false)
	var resolved = stage_loader.resolve(next_id)
	if resolved.is_empty():
		push_error("Rally stage: " + stage_loader.error)
		return
	session_track_id = next_id
	track_id = next_id
	resolved_stage = resolved
	var route_path: String = (resolved["paths"] as Dictionary)["route"]
	course.configure(route_path)
	var stage_config_path: String = (resolved["paths"] as Dictionary)["stage_config"]
	if event_manager != null:
		competition = event_manager.sim
	elif not competition.configure(stage_config_path, event_seed):
		push_error(competition.error)
		return
	course.sector_indices = competition.stage.sector_checkpoint_indices
	course.configure_timing_gates(competition.stage.timing_gates)
	# Reinicio entre especiales con objetivos térmicos del compuesto elegido.
	if not practice_mode and event_manager != null and vehicle.has_method("set_tire_compound"):
		vehicle.set_tire_compound(event_manager.confirmed_compound_id)
		vehicle.apply_tire_inventory()
	apply_start_pose_from_manifest()
	pacenotes.configure("res://data/rally/pacenotes/%s.json" % session_track_id)
	if not await _swap_stage_geometry(resolved):
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	place_vehicle_on_stage()
	course.generation = vehicle.simulation.session_generation
	camera_rig.snap_to_target()
	reset_start_sequence()
	if event_manager != null:
		start_clock_for_stage(event_manager.schedule_for(next_id))
		_setup_event_weather()
		# Los saltos de horario entre stages usan antecedentes ya resueltos
		# (integración acotada en generación); no se simulan dos horas con un dt.
		_refresh_stage_weather()
	session_ready = true
	if telemetry_recorder != null:
		telemetry_recorder.set_physics_process(true)
	apply_competition_controls()
	_update_panel_for_stage()
	# Servicio Stage 5→6: Resultados → Continuar al servicio → Neumáticos → Aceptar → Stage 6.
	if not practice_mode and event_manager != null and not event_manager.get_pending_window().is_empty():
		_open_setup_window()
	print("RALLY_STAGE_TRANSITION_READY stage=", next_id)

func _swap_stage_geometry(resolved: Dictionary) -> bool:
	var paths: Dictionary = resolved.get("paths", {})
	var visual_path: String = str(paths.get("visual", ""))
	var collision_path: String = str(paths.get("collision", ""))
	if track_visual == null or track_collision == null or not ResourceLoader.exists(visual_path):
		push_error("No se puede cargar la geometría de " + str(resolved.track_id))
		return false
	track_collision.clear_collision()
	for child in track_visual.get_children():
		child.queue_free()
	await get_tree().process_frame
	var packed := load(visual_path) as PackedScene
	if packed == null:
		return false
	track_visual.add_child(packed.instantiate())
	var adjuster := RallyStageVisualMaterialAdjuster.new()
	adjuster.adjust_node(track_visual)
	adjuster.free()
	if terrain_wetness != null:
		terrain_wetness.bind_visual_root(track_visual)
		if not practice_mode and event_weather.calendar_active and event_manager != null:
			_assign_wetness_zones(event_manager.weather_entry_for(session_track_id))
	track_collision.collision_scene_path = collision_path
	return await track_collision.build_collision(track_visual)

func start_clock_for_stage(schedule: Dictionary) -> void:
	# Salta a la hora de salida (empieza la cuenta atrás unos segundos antes).
	var date := str(schedule.get("date", event_clock.event_date))
	var start_str := str(schedule.get("start", "08:00"))
	var parts := start_str.split(":")
	var seconds := float(int(parts[0]) * 3600 + int(parts[1]) * 60)
	var countdown_lead := 5.0
	if event_manager != null and not event_manager.event_doc.is_empty():
		countdown_lead = float(((event_manager.event_doc.get("ambient", {}) as Dictionary).get("countdown_starts_seconds_before_scheduled", 5.0)))
	event_clock.set_rate(ambient_rate_for_stage())
	event_clock.set_paused(false)
	event_clock.jump_to(date, maxf(0.0, seconds - countdown_lead), "stage_start")

func ambient_rate_for_stage() -> float:
	if event_manager != null:
		return float(event_manager.ambient_rate) if float(event_manager.ambient_rate) in EventClockScript.ALLOWED_RATES else 1.0
	return 1.0

func _update_panel_for_stage() -> void:
	if head_up_display == null or head_up_display.competition_panel == null:
		return
	var panel: Control = head_up_display.competition_panel
	panel.present(get_competition_panel_state(), get_viewport().get_visible_rect().size)


func _setup_event_weather() -> void:
	if practice_mode or event_manager == null:
		return
	var entry: Dictionary = event_manager.weather_entry_for(session_track_id)
	if entry.is_empty():
		push_warning("Sin cronograma climático para " + session_track_id)
		return
	var route_path: String = (resolved_stage.get("paths", {}) as Dictionary).get("route", "res://data/rally/%s_route.json" % session_track_id)
	if not event_weather.configure(session_track_id, entry, route_path):
		push_warning("Clima del evento: " + event_weather.error)
		return
	# Fuente única: el proveedor alimenta física, materiales y HUD.
	vehicle.simulation.set_weather_controller(event_weather)
	if terrain_wetness != null and terrain_wetness.has_method("bind_shared_provider"):
		terrain_wetness.bind_shared_provider(event_weather)
	# Restaurar estado físico persistido (reanudar no re-sortea).
	var snap: Dictionary = event_manager.stage_surface_snapshot(session_track_id)
	if not snap.is_empty() and snap.has("surface"):
		event_weather.restore_snapshot(snap)
	else:
		event_weather.reset_projection()
	# Máscara espacial por chunk para no oscurecer todo el mapa de golpe.
	_assign_wetness_zones(entry)


func _refresh_stage_weather() -> void:
	if not event_weather.calendar_active:
		return
	event_weather.update_vehicle_position(vehicle.global_position)
	event_weather.tick_visual(2.0)
	event_weather.apply_to_adapters(weather_sky_node, weather_controller_node, terrain_wetness, event_clock.hour_of_day())
	weather_sky_node.update_visuals(0.0)


func _assign_wetness_zones(entry: Dictionary) -> void:
	if terrain_wetness == null or not terrain_wetness.has_method("assign_material_zones"):
		return
	if event_weather.route_points.is_empty():
		return
	var zones: Array = entry.get("zones", [])
	if zones.size() != 3:
		return
	var bounds := [int((zones[0] as Dictionary).get("start_node", 0)), int((zones[1] as Dictionary).get("start_node", 0)), int((zones[2] as Dictionary).get("start_node", 0)), int((zones[2] as Dictionary).get("end_node_exclusive", 0))]
	terrain_wetness.assign_material_zones(event_weather.route_points, bounds)


func _connect_garage_panel() -> void:
	garage_panel = get_node_or_null(garage_panel_path) as Control
	if garage_panel == null:
		return
	if not garage_panel.get("garage_closed").is_connected(_on_garage_closed):
		garage_panel.connect("garage_closed", _on_garage_closed)


func _open_setup_window() -> void:
	if garage_panel == null or event_manager == null:
		return
	var window: Dictionary = event_manager.get_pending_window()
	if window.is_empty():
		return
	# La cuenta atrás, el reloj ambiental y el coche permanecen detenidos mientras se elige.
	awaiting_setup = true
	setup_open_count += 1
	vehicle.freeze = true
	input_controller.set_controls_enabled(false)
	event_clock.set_paused(true)
	reset_start_sequence()
	var forecast: Dictionary = event_manager.forecast_for_half(event_manager.cursor, 5)
	var label := "SERVICIO"
	if str(window.get("window_key", "initial")) == "initial":
		label = "INICIO · STAGE 1"
	elif window.has("before_stage_id"):
		label = "SERVICIO · " + str(window.get("before_stage_id", "")).to_upper()
	garage_panel.call("open_garage_for_event", {
		"spare_wheels": vehicle.tire_inventory.spares.size(),
		"wheel_compounds": mounted_wheel_compounds(),
		"initial_tab": str(window.get("initial_tab", "tires")),
		"compound_id": event_manager.draft_compound_id,
		"compound_change_allowed": true,
		"confirmation_required": bool(window.get("confirmation_required", true)),
		"forecast_summary": str(forecast.get("summary", "")),
		"forecast_advice": str(forecast.get("suggested_compound", "")),
		"window_label": label,
	})
	if head_up_display != null:
		head_up_display.show_status("REGLAJE OBLIGATORIO — NEUMÁTICOS + ACEPTAR", Color(0.95, 0.72, 0.24), 4.0)


func _on_garage_closed(applied: bool) -> void:
	if not awaiting_setup:
		return
	if not applied:
		call_deferred("_open_setup_window")
		return
	# Guardar compuesto confirmado, valores y estado para no duplicar con doble clic.
	var setup: Dictionary = garage_panel.call("get_confirmed_setup") if garage_panel != null and garage_panel.has_method("get_confirmed_setup") else {}
	if setup.is_empty() and garage_panel != null:
		var values: Dictionary = garage_panel.draft_values.duplicate(true)
		for wheel in garage_panel.draft_wheel_compounds:
			values["strategy.wheel_compound." + str(wheel)] = garage_panel.draft_wheel_compounds[wheel]
		values["strategy.spare_wheels"] = garage_panel.draft_spare_wheels
		var committed: Dictionary = vehicle.apply_setup_snapshot(values)
		if not bool(committed.get("ok", false)):
			call_deferred("_open_setup_window")
			return
		var wet_count := 0
		for tire in vehicle.tire_inventory.mounted:
			if tire.compound_id == "gravel_wet":
				wet_count += 1
		setup = {"compound_id": "gravel_wet" if wet_count >= 2 else "gravel_normal", "values": garage_panel.draft_values}
	var cid := str(setup.get("compound_id", event_manager.draft_compound_id))
	var result: Dictionary = event_manager.confirm_setup(cid, setup.get("values", {}))
	if not bool(result.get("ok", false)):
		push_warning("Reglaje: " + str(result.get("error", "")))
		return
	if vehicle.has_method("set_tire_compound"):
		vehicle.set_tire_compound(event_manager.confirmed_compound_id)
		vehicle.apply_tire_inventory()
	_save_mounted_tire_condition()
	event_manager.save()
	awaiting_setup = false
	input_controller.arm_start_handbrake()
	# Aceptar inicia la salida: aplicar condiciones iniciales y habilitar cuenta atrás.
	if not practice_mode and event_manager != null:
		start_clock_for_stage(event_manager.schedule_for(session_track_id))
		_setup_event_weather()
		_refresh_stage_weather()
	reset_start_sequence()
	apply_competition_controls()
	_update_panel_for_stage()
	if head_up_display != null:
		head_up_display.show_status("COMPUESTO " + event_manager.confirmed_compound_id.to_upper() + " — SALIDA HABILITADA", Color(0.34, 0.82, 0.45), 3.0)

func _save_mounted_tire_condition() -> void:
	if practice_mode or event_manager == null or vehicle == null:
		return
	vehicle.sync_tire_inventory()
	event_manager.tire_inventory_state = vehicle.tire_inventory.snapshot()
	event_manager.tire_inventory_state["brake_collision_loss"] = vehicle.simulation.brake_collision_loss.duplicate()
	event_manager.tire_inventory_state["alignment_collision_damage"] = vehicle.simulation.alignment_collision_damage.duplicate()
	event_manager.mounted_tire_condition.clear()
	for tire: Dictionary in vehicle.simulation.thermal_model.tire_states:
		event_manager.mounted_tire_condition.append({"wear_fraction": tire.get("wear_fraction", 0.0), "thermal_damage_fraction": tire.get("thermal_damage_fraction", 0.0)})

func mounted_wheel_compounds() -> Dictionary:
	var result := {}
	for i in vehicle.tire_inventory.mounted.size():
		result[["FL", "FR", "RL", "RR"][i]] = vehicle.tire_inventory.mounted[i].compound_id
	return result

func may_service_tires() -> bool:
	if not session_ready or competition.complete or course.clock_started:
		return false
	if practice_mode or event_manager == null:
		return not course.running
	for window in event_manager.setup_windows():
		if str(window.get("before_stage_id", "")) == session_track_id:
			return true
	return false

func get_competition_panel_state() -> Dictionary:
	if event_manager == null or practice_mode:
		return competition.readout()
	var state: Dictionary = competition.readout()
	state["event_stage_id"] = session_track_id
	state["event_cursor"] = event_manager.cursor
	state["event_total"] = event_manager.stage_order.size()
	state["event_schedule"] = event_manager.schedule_for(session_track_id)
	state["event_player_retired"] = competition.player_retired
	state["event_is_last"] = event_manager.is_last_stage()
	state["event_status"] = event_manager.status
	if event_manager.status == "finished":
		state["event_points"] = event_manager.points_ledger
		state["event_final_rows"] = event_manager.standings()
	return state


func may_refuel() -> bool:
	if not session_ready or course.clock_started or competition.complete:
		return false
	if practice_mode or event_manager == null:
		return not course.running
	return awaiting_setup and not event_manager.get_pending_window().is_empty()
