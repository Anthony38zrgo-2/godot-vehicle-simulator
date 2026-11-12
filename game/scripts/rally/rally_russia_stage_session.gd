class_name RallyRussiaStageSession
extends Node3D

const STAGE_MANIFEST_PATH := "res://assets/rally/russia_stage1/manifest.json"
const FALLBACK_START_POSITION := Vector3(-2.18, -1.7963, -38.388)
const FALLBACK_START_HEADING := -0.0008558533301677789
const SPAWN_CLEARANCE_METRES := 0.02
const FALL_DISTANCE_BELOW_STAGE_METRES := 50.0
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
@export var selected_weather: String = "random"
@export var single_stage_weather: String = ""
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
var pause_inventory: CanvasLayer
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
var river_channels = null
var weather_is_raining: bool = false
var garage_panel: Control = null
var event_weather = preload("res://scripts/rally/rally_weather_controller.gd").new()
var awaiting_setup: bool = false
var setup_open_count: int = 0
var session_mode: String = "rally"
var selected_vehicle_key: String = ""


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
	session_track_id = track_id
	resolved_stage = stage_loader.resolve(session_track_id)
	if resolved_stage.is_empty():
		push_error("Rally stage: " + stage_loader.error + " (sin sustitución por Stage 1)")
		return
	var route_path: String = (resolved_stage["paths"] as Dictionary)["route"]
	if not course.configure(route_path):
		push_error("Russia course timing route is missing: " + route_path)
		return
	var stage_config_path: String = (resolved_stage["paths"] as Dictionary)["stage_config"]
	if practice_mode or session_mode == "single_stage":
		competition.save_path = ""
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
		vehicle.set_stage_headlights(sky_start_hour)
		event_clock.configure(event_clock.event_date, sky_start_hour * 3600.0, 1.0)
		event_clock.set_paused(false)
		if not single_stage_weather.is_empty() and single_stage_weather != "random":
			_apply_single_stage_weather(single_stage_weather)
	# Single Stage/práctica: sin calendario no hay proveedor climático; se fija
	# el entorno térmico desde el perfil regional para que Kenia soleado sea
	# caliente y Suecia fría también fuera del modo evento.
	if (practice_mode or session_mode == "single_stage") and event_manager == null:
		var practice_choice := single_stage_weather if not single_stage_weather.is_empty() else selected_weather
		var practice_thermal := RallyWeatherScheduler.practice_thermal_for_stage(
			session_track_id, practice_choice, sky_start_hour
		)
		if not practice_thermal.is_empty():
			vehicle.simulation.set_practice_thermal_environment(practice_thermal)
	# Política de temperatura de salida (tire_rules): environment_weighted
	# arranca la goma entre el ambiente de la zona y el óptimo del compuesto
	# (fría en Suecia, caliente en Kenia). El resto conserva el óptimo.
	var start_rules: Dictionary = (
		event_manager.event_doc.get("tire_rules", {}) as Dictionary
	) if (not practice_mode and event_manager != null) else RallyTireCompound.event_rules_for_stage(session_track_id)
	vehicle.start_temperature_policy = str(start_rules.get("start_temperature_policy", "selected_compound_optimum"))
	vehicle.simulation.sync_ambient_conditions()
	# Compuesto confirmado antes de precalentar (objetivos térmicos por compuesto).
	if not practice_mode and event_manager != null and vehicle.has_method("set_tire_compound"):
		vehicle.set_tire_compound(event_manager.confirmed_compound_id)
		for i in mini(4, event_manager.mounted_tire_condition.size()):
			var condition: Dictionary = event_manager.mounted_tire_condition[i]
			vehicle.simulation.thermal_model.tire_states[i].wear_fraction = clampf(float(condition.get("wear_fraction", 0.0)), 0.0, 1.0)
			vehicle.simulation.thermal_model.tire_states[i].thermal_damage_fraction = clampf(float(condition.get("thermal_damage_fraction", 0.0)), 0.0, 1.0)
	# Single-stage/práctica sin manager: instalar el compuesto
	# predeterminado del evento del país antes de crear el inventario.
	# No toca inventarios existentes (ensure_tire_inventory no recrea)
	# ni selecciones guardadas.
	if (practice_mode or session_mode == "single_stage") and event_manager == null:
		var initial_rules := RallyTireCompound.event_rules_for_stage(session_track_id)
		var initial_compound := str(initial_rules.get("default_compound_id", "gravel_normal"))
		if not initial_compound.is_empty() and vehicle.has_method("set_tire_compound"):
			vehicle.set_tire_compound(initial_compound)
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
	if not practice_mode and event_manager != null:
		vehicle.restore_damage(event_manager.vehicle_damage_state)
	if track_collision == null:
		push_error("Rally session cannot resolve the stage collision builder")
		return
	var collision_ready: bool = await _swap_stage_geometry(resolved_stage)
	if not collision_ready:
		push_error("Rally session cannot build the stage collision")
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	_build_puddles()
	_build_rivers()
	_build_stage_grass()
	place_vehicle_on_stage()
	_refresh_stage_weather()
	connect_runtime_signals()
	configure_runtime_paths()
	_connect_garage_panel()
	pause_inventory = preload("res://scripts/rally/rally_pause_inventory.gd").new()
	pause_inventory.session = self
	add_child(pause_inventory)
	if telemetry_recorder != null:
		telemetry_recorder.set_physics_process(true)
	session_ready = true
	var panel: Control = head_up_display.competition_panel
	panel.retire_requested.connect(retire_competition_player)
	panel.retry_requested.connect(retry_competition_attempt)
	panel.next_requested.connect(continue_competition)
	panel.workshop_requested.connect(_open_between_stage_workshop)
	pause_inventory.results_workshop_closed.connect(func():
		_update_panel_for_stage()
		if panel.workshop_button.is_visible_in_tree():
			panel.workshop_button.grab_focus())
	panel.new_rally_requested.connect(start_new_competition)
	setup_start_audio()
	setup_pacenotes()
	reset_start_sequence()
	apply_competition_controls()
	_update_panel_for_stage()
	# Ventana inicial de reglaje (Neumáticos primero, Aceptar inicia la salida).
	# Se abre automáticamente en las tres modalidades (Rally, Championship, Single Stage).
	# Sin ventana vamos directo a pilotar: corte inmediato, nada de menú en tramo.
	if not practice_mode and event_manager != null and not event_manager.get_pending_window().is_empty():
		_open_setup_window()
	elif session_mode == "single_stage":
		_open_setup_window()
	else:
		var _rm_init := get_node_or_null("/root/RallyMusic")
		if _rm_init != null and _rm_init.has_method("on_start_rally"):
			_rm_init.call("on_start_rally")
	print("RALLY_SESSION_READY scene=%s vehicle=%s spawn=" % [session_track_id, vehicle.rally_profile.get("profile_id", "unknown")], start_position, " heading_radians=", start_heading, " physics_engine=", ProjectSettings.get_setting("physics/3d/physics_engine"))


func build_environment() -> void:
	weather_sky_node = TroposphericSky.new()
	weather_sky_node.name = "RallyTroposphericSky"
	var sky_date := str(event_clock.event_date)
	var rally_id := session_track_id.get_slice("_stage", 0)
	if event_manager != null and not practice_mode:
		var schedule: Dictionary = event_manager.schedule_for(session_track_id)
		sky_date = str(schedule.get("date", sky_date))
		rally_id = str(event_manager.event_doc.get("id", rally_id))
	weather_sky_node.configure_event(rally_id, session_track_id, sky_date)
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


func _build_stage_grass() -> void:
	var previous := get_node_or_null("StageGrass")
	if previous != null:
		remove_child(previous)
		previous.queue_free()
	# La nieve de Suecia usa Collision_Terrain_Grass para el manto nevado:
	# no generar matas de hierba de verano sobre la nieve. En Finlandia el
	# suelo es Dirt/Sand (grass=0) y RallyStageGrass retorna limpio sin error.
	if session_track_id.begins_with("sweden_"):
		return
	var grass := preload("res://scripts/rally/rally_stage_grass.gd").new()
	grass.name = "StageGrass"
	grass.aged_only = session_track_id in ["raura_stage2", "raurasr_stage2", "raurastart_stage2", "rauraearth_stage2"]
	if session_track_id == "raurasr_stage2":
		grass.density_scale = 0.5
		for variant in ["hierba-seca-florida", "matorral-bajo-oliva", "pasto-alto-dorado", "planta-hojas-verdes"]:
			var asset := load("res://assets/rally/raurasr_stage2/vegetacion/%s.glb" % variant) as PackedScene
			if asset != null:
				grass.custom_variants.append(asset)
	add_child(grass)
	grass.build(course.points, hash(session_track_id), track_collision.collision_layer)


func _build_puddles() -> void:
	var previous := get_node_or_null("RallyPuddles")
	if previous != null:
		remove_child(previous)
		previous.queue_free()
	var puddles := preload("res://scripts/rally/rally_puddles.gd").new()
	puddles.name = "RallyPuddles"
	puddles.sky_node = weather_sky_node
	puddles.configure(course.points, hash(session_track_id), event_weather, terrain_wetness)
	add_child(puddles)
	vehicle.simulation.puddle_system = puddles


func _practice_weather_choice() -> String:
	return single_stage_weather if not single_stage_weather.is_empty() else selected_weather


func _combined_surface_snapshot() -> Dictionary:
	var snap := event_weather.snapshot()
	if river_channels != null and is_instance_valid(river_channels):
		var rsnap: Dictionary = river_channels.snapshot()
		snap["rivers"] = rsnap.get("channels", {})
		snap["rivers_version"] = rsnap.get("version", 1)
	return snap


func _build_rivers() -> void:
	# Al cambiar de etapa, desconectar el proveedor del vehículo antes de
	# liberar mallas y datos. Sin cauces registrados no se instancia
	# controlador (tramos ajenos a Kenia).
	if river_channels != null and is_instance_valid(river_channels):
		if vehicle != null and vehicle.simulation != null and vehicle.simulation.river_system == river_channels:
			vehicle.simulation.river_system = null
		river_channels.unbind()
		remove_child(river_channels)
		river_channels.queue_free()
		river_channels = null
	var rivers := RallyRiverChannels.new()
	rivers.name = "RallyRiverChannels"
	if not rivers.configure(session_track_id, track_visual, event_weather, _practice_weather_choice(), weather_controller_node):
		push_warning("Rally rivers: " + rivers.error)
		rivers.queue_free()
		return
	if rivers.channels.is_empty():
		rivers.queue_free()
		return
	add_child(rivers)
	river_channels = rivers
	vehicle.simulation.river_system = rivers
	_init_rivers_from_snapshot()


func _init_rivers_from_snapshot() -> void:
	## Inicializa la crecida después de que el clima de la etapa esté
	## configurado o restaurado, antes de habilitar la conducción. Al
	## rescatar o recolocar el coche se conserva el estado; en un nuevo
	## intento se restaura la condición inicial guardada; al reanudar, el
	## estado guardado para esa especial.
	if river_channels == null or not is_instance_valid(river_channels):
		return
	river_channels.rebind_provider(event_weather, weather_controller_node)
	var saved: Dictionary = {}
	if not practice_mode and event_manager != null and event_weather.calendar_active:
		saved = event_manager.stage_surface_snapshot(session_track_id)
	if not saved.is_empty() and saved.has("rivers"):
		river_channels.restore_snapshot({
			"version": int(saved.get("rivers_version", 0)),
			"stage_id": session_track_id,
			"channels": saved.get("rivers", {}),
		})
	else:
		river_channels.practice_choice = _practice_weather_choice()
		river_channels.initialize_levels()
	river_channels.store_initial()


func _advance_rivers(dt_sim: float) -> void:
	if river_channels == null or not is_instance_valid(river_channels):
		return
	if dt_sim > 0.0:
		river_channels.advance(dt_sim)


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


func _wheel_lowest_offset() -> float:
	# Menor cota local del plano de contacto (centro de rueda - radio).
	var lowest := INF
	if vehicle != null:
		var positions: Array[Vector3] = vehicle.simulation.wheel_positions_local
		var radii: Array[float] = vehicle.simulation.wheel_radii
		for index in mini(positions.size(), radii.size()):
			lowest = minf(lowest, positions[index].y - radii[index])
	return 0.0 if not is_finite(lowest) else lowest


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
	# El origen del cuerpo no coincide con el plano de contacto de las ruedas.
	# Desplazarlo ese tanto evita que coches con poco recorrido de rueda
	# aterricen sobre los topes de suspension al aparecer en el tramo.
	var lowest := _wheel_lowest_offset()
	start_position = surface_position + surface_normal * (SPAWN_CLEARANCE_METRES - lowest)
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
		"scene": scene_file_path.get_file().get_basename(),
		"track_id": session_track_id,
		"vehicle_id": vehicle.rally_profile.get("vehicle_identifier", "") if vehicle != null and vehicle.rally_profile != null else "",
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
	var pose: Variant = null
	var position := vehicle.global_position
	var space := get_world_3d().direct_space_state
	var excluded: Array[RID] = [vehicle.get_rid()]
	for index in range(course.points.size() - 1):
		var a: Vector3 = course.points[index]
		var segment: Vector3 = course.points[index + 1] - a
		if segment.length_squared() < 0.0001:
			continue
		var t := clampf((position - a).dot(segment) / segment.length_squared(), 0.0, 1.0)
		var candidate := a + segment * t
		var distance := position.distance_squared_to(candidate)
		if distance >= closest:
			continue
		var candidate_pose: Variant = _rescue_pose_on_road(space, excluded, candidate, segment)
		if candidate_pose is Transform3D:
			closest = distance
			pose = candidate_pose
	if pose == null:
		pose = _rescue_pose_on_road(space, excluded, start_position, Basis(Vector3.UP, start_heading) * Vector3.FORWARD)
	if pose == null:
		return false
	var target: Vector3 = pose.origin
	vehicle.rescue_to_pose(pose)
	course.generation = vehicle.simulation.session_generation
	course.previous_position = target
	competition.generation = course.generation
	camera_rig.snap_to_target()
	pacenotes.on_rescue(target)
	if not practice_mode and event_weather.calendar_active:
		event_weather.on_rescue(target)
	return true


func _rescue_pose_on_road(
	space: PhysicsDirectSpaceState3D, excluded: Array[RID], candidate: Vector3, direction: Vector3,
) -> Variant:
	var ray := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 3.0, candidate - Vector3.UP * 6.0, 1, excluded)
	var center := space.intersect_ray(ray)
	if center.is_empty() or not center.collider.get_meta("is_stage_road", false):
		return null
	var up: Vector3 = center.normal
	if up.y < 0.65:
		return null
	var right := direction.cross(up).normalized()
	if right.is_zero_approx():
		return null
	var basis := Basis(right, up, right.cross(up))
	var surface: Vector3 = center.position
	var highest := -INF
	var lowest := INF
	for i in 4:
		var offset: Vector3 = basis * vehicle.simulation.wheel_positions_local[i]
		var wheel: Vector3 = surface + offset
		ray.from = wheel + up * 0.7
		ray.to = wheel - up * 0.9
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.collider.get_meta("collision_role", "") != "terrain":
			return null
		if (hit.normal as Vector3).dot(up) < 0.8:
			return null
		var height := ((hit.position as Vector3) - wheel).dot(up) + vehicle.simulation.wheel_radii[i]
		highest = maxf(highest, height)
		lowest = minf(lowest, height)
	if highest - lowest > 0.14:
		return null
	var pose := Transform3D(basis, surface + up * (highest + 0.04))
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = vehicle.collision_mask
	query.exclude = excluded
	query.margin = 0.02
	for child in vehicle.get_children():
		if child is CollisionShape3D and not child.disabled:
			query.shape = child.shape
			query.transform = pose * child.transform
			if not space.intersect_shape(query, 1).is_empty():
				return null
	return pose


func on_vehicle_reset_requested() -> void:
	if competition.complete or not _reposition_vehicle_on_course():
		return
	if course.running:
		competition.add_penalty("player", int(competition.balance.reset_penalty_ms), "Rescate")
		head_up_display.show_status("RESCATE +%.0f s" % (float(competition.balance.reset_penalty_ms) / 1000.0), Color(0.95, 0.72, 0.24), 2.2)
	else:
		head_up_display.show_status("COCHE RESTABLECIDO", Color(0.95, 0.72, 0.24), 2.2)


func on_quick_repair_radiator_requested(heavy: bool = false) -> bool:
	if (competition.complete and not can_open_between_stage_workshop()) or vehicle == null or vehicle.simulation == null or vehicle.simulation.thermal_model == null:
		return false
	var tm: VehicleThermalModel = vehicle.simulation.thermal_model
	vehicle.ensure_tire_inventory()
	var kit_index := 1 if heavy else 0
	if not vehicle.tire_inventory.repair_kits[kit_index]:
		return false
	var recovery := 0.50 if heavy else 0.20
	if tm.radiator_damage <= 0.0:
		return false
	if not tm.quick_repair_radiator(maxf(0.0, tm.radiator_damage - recovery)):
		return false
	vehicle.tire_inventory.repair_kits[kit_index] = false
	var penalty := 60000 if heavy else 30000
	if competition.complete:
		var charges: Dictionary = event_manager.service_penalties_ms
		charges[session_track_id] = int(charges.get(session_track_id, 0)) + penalty
		_save_mounted_tire_condition()
		event_manager.save()
	else:
		competition.add_penalty("player", penalty, "Herramientas radiador")
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
			event_weather.apply_to_adapters(weather_sky_node, weather_controller_node, terrain_wetness, event_clock.hour_of_day(), vehicle.linear_velocity)
		# Cauces: mismo tiempo simulado y ventana de avance que el ambiente.
		# La posición del coche no modifica el clima asignado a ningún río.
		if clock_advancing:
			_advance_rivers(delta * maxf(event_clock.rate, 0.0))
	elif river_channels != null and (practice_mode or session_mode == "single_stage"):
		# Práctica: convierte la selección de clima (incluida la ruta TCA
		# que corresponda) a mm/h en un único adaptador.
		if clock_advancing:
			river_channels.practice_choice = _practice_weather_choice()
			_advance_rivers(delta)
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
	# Deep descents can legitimately pass below the world's origin.
	var collision_floor := minf(0.0, track_collision.minimum_collision_height_m) if track_collision != null else 0.0
	if vehicle.global_position.y < collision_floor - FALL_DISTANCE_BELOW_STAGE_METRES and not competition.complete:
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
	var number := _get_stage_number(session_track_id)
	var place := str(session_track_id)
	var cut := place.rfind("_stage")
	if cut > 0:
		place = place.substr(0, cut)
	place = place.replace("_", " ").strip_edges().to_upper()
	if place.is_empty():
		return "STAGE %d" % number
	return "STAGE %d · %s" % [number, place]


func _get_stage_number(id_str: String) -> int:
	var regex := RegEx.new()
	regex.compile("stage(\\d+)")
	var m := regex.search(id_str.to_lower())
	if m != null:
		return m.get_string(1).to_int()
	return 1


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
	var _rm_reset := get_node_or_null("/root/RallyMusic")
	if _rm_reset != null and _rm_reset.has_method("on_start_rally"):
		_rm_reset.call("on_start_rally")
	apply_competition_controls()

func retry_competition_attempt() -> void:
	if not practice_mode:
		if head_up_display != null:
			head_up_display.show_status("MODO OFICIAL: reintentar no reemplaza tiempos", Color(1.0, 0.45, 0.2), 2.5)
		return
	competition.reset_attempt()
	competition.save()
	reset_competition_car()
	if river_channels != null and is_instance_valid(river_channels):
		river_channels.restore_initial()

func can_open_between_stage_workshop() -> bool:
	if not session_ready or practice_mode or session_mode == "single_stage" or awaiting_setup or stage_transition_running:
		return false
	if not competition.complete or competition.player_retired or event_manager == null:
		return false
	if event_manager.status != "running" or event_manager.is_last_stage() or event_manager.current_stage_id() != session_track_id:
		return false
	if event_manager.closed_keys.has("closed:" + session_track_id):
		return false
	if session_track_id in event_manager.event_doc.get("service", {}).get("after_stage_ids", []):
		return false
	var next_id := str(event_manager.stage_order[event_manager.cursor + 1])
	for window in event_manager.setup_windows():
		if window.get("after_stage_id") == session_track_id and window.get("before_stage_id") == next_id:
			return false
	return true


func _open_between_stage_workshop() -> void:
	if can_open_between_stage_workshop() and pause_inventory != null:
		pause_inventory.open_from_results()


func continue_competition() -> void:
	if pause_inventory != null and pause_inventory.opened_from_results:
		return
	if stage_transition_running or not competition.complete:
		return
	if session_mode == "single_stage":
		return
	if event_manager != null and event_manager.status == "finished":
		return
	if practice_mode:
		if competition.next_stage():
			reset_competition_car()
		return
	var _rm_trans := get_node_or_null("/root/RallyMusic")
	if _rm_trans != null and _rm_trans.has_method("on_begin_stage_transition"):
		_rm_trans.call("on_begin_stage_transition")
	_close_event_stage(false, "")
	await _advance_event_stage()

func start_new_competition() -> void:
	if not practice_mode:
		if ResourceLoader.exists("res://scenes/rally/rally_maniac_menu.tscn"):
			get_tree().change_scene_to_file("res://scenes/rally/rally_maniac_menu.tscn")
			return
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
	var _rm_wd := get_node_or_null("/root/RallyMusic")
	if _rm_wd != null and _rm_wd.has_method("on_begin_stage_transition"):
		_rm_wd.call("on_begin_stage_transition")
	_close_event_stage(true, reason)
	_advance_event_stage()


func _exit_tree() -> void:
	_save_mounted_tire_condition()
	if session_ready and not practice_mode and event_manager != null and event_weather.calendar_active:
		event_manager.save_stage_surface(session_track_id, _combined_surface_snapshot())
		event_manager.save()
	if session_ready and competition.started:
		competition.save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if pacenotes != null and is_instance_valid(pacenotes) and pacenotes.get_parent() == null:
			pacenotes.free()
			pacenotes = null


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
		event_manager.save_stage_surface(session_track_id, _combined_surface_snapshot())
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
	_build_puddles()
	_build_rivers()
	_build_stage_grass()
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
	# Sin ventana pendiente vamos directo a pilotar: corte inmediato para que
	# el tema del menú (resultados/transición) no siga en el tramo.
	if not practice_mode and event_manager != null and not event_manager.get_pending_window().is_empty():
		_open_setup_window()
	else:
		var _rm_ready := get_node_or_null("/root/RallyMusic")
		if _rm_ready != null and _rm_ready.has_method("on_start_rally"):
			_rm_ready.call("on_start_rally")
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
	if str(resolved.track_id) in ["raurastart_stage2", "rauraearth_stage2"]:
		preload("res://scripts/rally/raura_pilot_materials.gd").new().apply(track_visual)
	if terrain_wetness != null:
		terrain_wetness.bind_visual_root(track_visual)
		if not practice_mode and event_weather.calendar_active and event_manager != null:
			_assign_wetness_zones(event_manager.weather_entry_for(session_track_id))
	# Stage metadata is a fallback for road meshes with no material labels.
	# Individual collision road materials can still override it.
	var stage_data: Dictionary = resolved.get("stage_config", {})
	track_collision.terrain_surface_group = "Road" if str(stage_data.get("surface", "")).to_lower() == "asphalt" else "Gravel"
	track_collision.collision_scene_path = collision_path
	return await track_collision.build_collision(track_visual)

func start_clock_for_stage(schedule: Dictionary) -> void:
	# Salta a la hora de salida (empieza la cuenta atrás unos segundos antes).
	var date := str(schedule.get("date", event_clock.event_date))
	var start_str := str(schedule.get("start", "08:00"))
	var parts := start_str.split(":")
	var seconds := float(int(parts[0]) * 3600 + int(parts[1]) * 60)
	vehicle.set_stage_headlights(seconds / 3600.0)
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
	if river_channels != null and is_instance_valid(river_channels):
		_init_rivers_from_snapshot()


func _refresh_stage_weather() -> void:
	if not event_weather.calendar_active:
		return
	event_weather.update_vehicle_position(vehicle.global_position)
	event_weather.tick_visual(2.0)
	event_weather.apply_to_adapters(weather_sky_node, weather_controller_node, terrain_wetness, event_clock.hour_of_day(), vehicle.linear_velocity)
	if river_channels != null and is_instance_valid(river_channels):
		river_channels.refresh_render()
	weather_sky_node.update_visuals(0.0)


func _apply_single_stage_weather(w: String) -> void:
	match w.strip_edges().to_lower():
		"sunny", "soleado":
			if weather_sky_node != null:
				weather_sky_node.set_practice_weather(0.1, 0.0)
			weather_start_weather = 0
		"cloudy", "nublado":
			if weather_sky_node != null:
				weather_sky_node.set_practice_weather(0.6, 0.0)
			weather_start_weather = 1
		"rain", "lluvia", "medium_precipitation", "light_precipitation":
			if weather_sky_node != null:
				weather_sky_node.set_practice_weather(0.9, 0.003)
			weather_start_weather = 2
			if weather_controller_node != null and weather_controller_node.has_method("set_weather"):
				weather_controller_node.call("set_weather", 2)


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
	if garage_panel.get("vehicle") == null and vehicle != null:
		garage_panel.set("vehicle", vehicle)
	if not garage_panel.get("garage_closed").is_connected(_on_garage_closed):
		garage_panel.connect("garage_closed", _on_garage_closed)


func _open_setup_window() -> void:
	if garage_panel == null:
		return
	# La música la dispara cada panel (garaje -> on_enter_garage,
	# servicio -> on_enter_service) para evitar doble reinicio en el mismo frame.
	if not practice_mode and event_manager != null:
		var window: Dictionary = event_manager.get_pending_window()
		if window.is_empty():
			return
		if str(window.get("window_key", "initial")) == "initial" and not event_manager.windows_attended.has("strategy:initial"):
			# Estrategia inicial: NO pausa el SceneTree (el garaje lo hará después con
			# _restore_tree_paused=false). Solo congela vehículo + reloj + input.
			awaiting_setup = true
			vehicle.freeze = true
			input_controller.set_controls_enabled(false)
			event_clock.set_paused(true)
			var strat_layer := CanvasLayer.new()
			strat_layer.layer = 115
			strat_layer.process_mode = Node.PROCESS_MODE_ALWAYS
			var strat_screen := preload("res://scripts/rally/rally_tire_strategy_screen.gd").new()
			strat_screen.manager = event_manager
			if vehicle != null and vehicle.rally_profile.has("display_name"):
				strat_screen.vehicle_name = str(vehicle.rally_profile.get("display_name", vehicle.name))
			strat_layer.add_child(strat_screen)
			add_child(strat_layer)
			strat_screen.strategy_confirmed.connect(func(initial_data: Dictionary) -> void:
				_apply_initial_tire_strategy(initial_data)
				event_manager.windows_attended["strategy:initial"] = true
				event_manager.tire_inventory_state = vehicle.tire_inventory.snapshot()
				event_manager.save()
				strat_layer.queue_free()
				call_deferred("_open_setup_window")
			)
			return
		if str(window.get("window_key", "initial")) != "initial" and not event_manager.windows_attended.has("repairs:" + str(window.get("window_key", ""))):
			awaiting_setup = true
			vehicle.freeze = true
			input_controller.set_controls_enabled(false)
			event_clock.set_paused(true)
			var service := preload("res://scripts/rally/rally_service_panel.gd").new()
			add_child(service)
			service.confirmed.connect(_open_setup_window, CONNECT_DEFERRED)
			service.open(vehicle, event_manager, window)
			return
		awaiting_setup = true
		setup_open_count += 1
		vehicle.freeze = true
		input_controller.set_controls_enabled(false)
		event_clock.set_paused(true)
		reset_start_sequence()
		var forecast: Dictionary = event_manager.forecast_for_half(event_manager.cursor, 5)
		var label := "SERVICIO"
		if str(window.get("window_key", "initial")) == "initial":
			var num := _get_stage_number(session_track_id)
			label = "INICIO · STAGE %d" % num
		elif window.has("before_stage_id"):
			label = "SERVICIO · " + str(window.get("before_stage_id", "")).to_upper()
		garage_panel.circuit_name = label
		garage_panel.call("open_garage_for_event", {
			"spare_wheels": vehicle.tire_inventory.spares.size(),
			"wheel_compounds": mounted_wheel_compounds(),
			"initial_tab": str(window.get("initial_tab", "tires")),
			"compound_id": event_manager.draft_compound_id,
			"compound_change_allowed": true,
			"confirmation_required": bool(window.get("confirmation_required", true)),
			"forecast_summary": str(forecast.get("summary", "")),
			"forecast_advice": "Nieve con clavos" if str(session_track_id).begins_with("sweden_") else str(forecast.get("suggested_compound", "")),
			"window_label": label,
			"allowed_compound_ids": event_manager.get_allowed_compound_ids(),
			"default_compound_id": str(
				event_manager.event_doc.get(
					"tire_rules", {}
				).get("default_compound_id", "gravel_normal")
			),
		})
		if head_up_display != null:
			head_up_display.show_status("REGLAJE OBLIGATORIO — NEUMÁTICOS + ACEPTAR", Color(0.95, 0.72, 0.24), 4.0)
	else:
		# Modo Single Stage / Championship / práctica
		awaiting_setup = true
		setup_open_count += 1
		vehicle.freeze = true
		input_controller.set_controls_enabled(false)
		event_clock.set_paused(true)
		reset_start_sequence()
		var num := _get_stage_number(session_track_id)
		var label := "INICIO · STAGE %d" % num
		garage_panel.circuit_name = label
		var current_compound: String = "gravel_normal"
		if vehicle != null and vehicle.tire_inventory != null and not vehicle.tire_inventory.mounted.is_empty():
			current_compound = vehicle.tire_inventory.mounted[0].compound_id
		var tire_rules := RallyTireCompound.event_rules_for_stage(
			session_track_id
		)
		garage_panel.call("open_garage_for_event", {
			"spare_wheels": vehicle.tire_inventory.spares.size(),
			"wheel_compounds": mounted_wheel_compounds(),
			"initial_tab": "tires",
			"compound_id": current_compound,
			"compound_change_allowed": true,
			"confirmation_required": true,
			"forecast_summary": "",
			"forecast_advice": "",
			"window_label": label,
			"allowed_compound_ids": tire_rules.get(
				"allowed_compound_ids", []
			),
			"default_compound_id": tire_rules.get(
				"default_compound_id", "gravel_normal"
			),
		})
		if head_up_display != null:
			head_up_display.show_status("REGLAJE OBLIGATORIO — NEUMÁTICOS + ACEPTAR", Color(0.95, 0.72, 0.24), 4.0)


func _apply_initial_tire_strategy(data: Dictionary) -> void:
	# Construye el pool fijo de 10 con ids 1..10: 4 montados + N maletera + resto parque.
	if vehicle == null or vehicle.tire_inventory == null:
		return
	var inv = vehicle.tire_inventory
	inv.mounted.clear()
	inv.spares.clear()
	inv.service_stock.clear()
	inv.discarded.clear()
	inv.next_id = 1
	var mounted_cids: Array = data.get("mounted_compounds", ["gravel_normal", "gravel_normal", "gravel_normal", "gravel_normal"])
	for i in 4:
		var cid := str(mounted_cids[i]) if i < mounted_cids.size() else "gravel_normal"
		if not RallyTireCompound.is_valid(cid):
			cid = "gravel_normal"
		inv.mounted.append(inv.item(cid, vehicle.fresh_tire_state(cid, i)))
	var spares_cids: Array = data.get("spares_compounds", [])
	for raw in spares_cids:
		var cid := str(raw)
		if not RallyTireCompound.is_valid(cid):
			continue
		inv.spares.append(inv.item(cid, vehicle.fresh_tire_state(cid)))
		if inv.spares.size() >= inv.capacity:
			break
	var stock_cids: Array = data.get("service_compounds", [])
	for raw in stock_cids:
		var cid := str(raw)
		if not RallyTireCompound.is_valid(cid):
			continue
		inv.service_stock.append(inv.item(cid, vehicle.fresh_tire_state(cid)))
		if inv.total_count() >= RallyTireInventory.TOTAL_POOL_SIZE:
			break
	vehicle.apply_tire_inventory()
	if event_manager != null and not mounted_cids.is_empty():
		event_manager.draft_compound_id = str(mounted_cids[0])


func _on_garage_closed(applied: bool) -> void:
	if not awaiting_setup:
		# Garaje abierto a mitad de tramo: al cerrar volvemos a pilotar,
		# corte inmediato para que el tema del menú no siga en el tramo.
		var _rm_mid := get_node_or_null("/root/RallyMusic")
		if _rm_mid != null and _rm_mid.has_method("on_start_rally"):
			_rm_mid.call("on_start_rally")
		return
	if not applied:
		call_deferred("_open_setup_window")
		return
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
		# The four mounted wheel IDs are authoritative; this scalar is legacy.
		var primary_compound := str(vehicle.tire_inventory.mounted[0].compound_id)
		setup = {"compound_id": primary_compound, "values": garage_panel.draft_values}
	else:
		# close_garage(true) ya aplico reglajes fisicos e inventario (apply_pool_plan o service_tire_inventory);
		# aplicar solo las claves fisicas sin re-ejecutar service_tire_inventory() ni pisar montajes mixtos.
		if setup.has("values") and not (setup.values as Dictionary).is_empty():
			var physical_only := (setup.values as Dictionary).duplicate(true)
			for k in physical_only.keys():
				if str(k).begins_with("strategy."):
					physical_only.erase(k)
			if not physical_only.is_empty():
				var committed: Dictionary = vehicle.apply_setup_values(physical_only)
				if not bool(committed.get("ok", false)):
					call_deferred("_open_setup_window")
					return

	var cid := str(setup.get("compound_id", "gravel_normal"))
	if not practice_mode and event_manager != null:
		cid = str(setup.get("compound_id", event_manager.draft_compound_id))
		var result: Dictionary = event_manager.confirm_setup(
			cid,
			setup.get("values", {}),
			setup.get("wheel_compounds", {})
		)
		if not bool(result.get("ok", false)):
			push_warning("Reglaje: " + str(result.get("error", "")))
			call_deferred("_open_setup_window")
			return
		vehicle.apply_tire_inventory()
		_save_mounted_tire_condition()
		event_manager.save()
		start_clock_for_stage(event_manager.schedule_for(session_track_id))
		_setup_event_weather()
		_refresh_stage_weather()
	else:
		vehicle.apply_tire_inventory()
		event_clock.set_paused(false)

	awaiting_setup = false
	var _garage_music := get_node_or_null("/root/RallyMusic")
	if _garage_music != null and _garage_music.has_method("on_start_rally"):
		_garage_music.call("on_start_rally")
	input_controller.arm_start_handbrake()
	reset_start_sequence()
	apply_competition_controls()
	_update_panel_for_stage()
	var comp_summary := ""
	if vehicle.tire_inventory != null and vehicle.tire_inventory.mounted.size() >= 4:
		var cat := RallyTireCompound.load_catalog()
		var unique_cids: Array[String] = []
		var short_parts: Array[String] = []
		for t in vehicle.tire_inventory.mounted:
			var tcid := str((t as Dictionary).get("compound_id", cid))
			if not unique_cids.has(tcid):
				unique_cids.append(tcid)
			var s_lbl := str(RallyTireCompound.get_compound(cat, tcid).get("short_label", tcid))
			short_parts.append(s_lbl.to_upper())
		if unique_cids.size() == 1:
			comp_summary = "COMPUESTO " + unique_cids[0].to_upper()
		else:
			comp_summary = "MIXTO (" + "/".join(short_parts) + ")"
	else:
		var comp_label: String = event_manager.confirmed_compound_id if (not practice_mode and event_manager != null) else cid
		comp_summary = "COMPUESTO " + comp_label.to_upper()
	if head_up_display != null:
		head_up_display.show_status(comp_summary + " — SALIDA HABILITADA", Color(0.34, 0.82, 0.45), 3.0)

func _save_mounted_tire_condition() -> void:
	if practice_mode or event_manager == null or vehicle == null:
		return
	vehicle.sync_tire_inventory()
	event_manager.vehicle_damage_state = vehicle.damage_snapshot()
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


func get_session_allowed_compound_ids() -> Array:
	if event_manager != null:
		if event_manager.has_method("get_allowed_compound_ids"):
			return event_manager.get_allowed_compound_ids()
		return (event_manager.event_doc.get("tire_rules", {}) as Dictionary).get("allowed_compound_ids", [])
	var rules := RallyTireCompound.event_rules_for_stage(session_track_id)
	return rules.get("allowed_compound_ids", [])


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
	if event_manager == null or practice_mode or session_mode == "single_stage":
		var state: Dictionary = competition.readout()
		state["event_stage_id"] = session_track_id
		state["event_cursor"] = _get_stage_number(session_track_id) - 1
		state["event_total"] = 10
		state["session_mode"] = session_mode
		if session_mode == "single_stage":
			state["allow_next"] = false
			state["single_stage_mode"] = true
		return state
	var state: Dictionary = competition.readout(int(event_manager.service_penalties_ms.get(session_track_id, 0)))
	state["allow_workshop"] = can_open_between_stage_workshop()
	state["event_stage_id"] = session_track_id
	state["event_cursor"] = event_manager.cursor
	state["event_total"] = event_manager.stage_order.size()
	state["event_schedule"] = event_manager.schedule_for(session_track_id)
	state["event_player_retired"] = competition.player_retired
	state["event_is_last"] = event_manager.is_last_stage()
	state["event_status"] = event_manager.status
	state["session_mode"] = session_mode
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
