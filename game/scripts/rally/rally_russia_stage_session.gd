class_name RallyRussiaStageSession
extends Node3D

const STAGE_MANIFEST_PATH := "res://assets/rally/russia_stage1/manifest.json"
const FALLBACK_START_POSITION := Vector3(-2.18, -1.7963, -38.388)
const FALLBACK_START_HEADING := -0.0008558533301677789
const SPAWN_CLEARANCE_METRES := 0.08
const MINIMUM_WORLD_HEIGHT_METRES := -50.0

@export var vehicle_path: NodePath
@export var input_controller_path: NodePath
@export var camera_rig_path: NodePath
@export var head_up_display_path: NodePath
@export var telemetry_recorder_path: NodePath
@export var track_collision_path: NodePath
@export var track_visual_path: NodePath
@export var weather_enabled: bool = true
@export var weather_season_path: String = "res://data/weather/russia_winter_overcast.tres"
@export var weather_start_weather: int = 0
@export var weather_speed_multiplier: float = 1.0
@export_group("Sky3D")
@export var sky3d_time_of_day: float = 11.0
@export var sky3d_minutes_per_day: float = 24.0
@export var sky3d_cumulus_coverage: float = 0.68
@export var sky3d_cirrus_coverage: float = 0.55
@export var sky3d_cumulus_intensity: float = 0.85
@export var sky3d_fog_density: float = 0.0004
@export var sky3d_fog_end: float = 3000.0
@export var couple_clouds_to_weather: bool = true
@export var sky3d_precipitation_cloud_coverage: float = 0.92
@export_group("Dreamcast Aesthetics")
@export var dreamcast_visual_mode: bool = true
@export var dc_fog_begin: float = 55.0
@export var dc_fog_end: float = 230.0
@export var dc_fog_color_day: Color = Color(0.62, 0.68, 0.74)
@export_group("Sky3D Brillo")
# Bajamos el aporte del cielo a 0.15 para evitar que Sky3D tina el suelo con PBR moderno
@export var sky3d_ambient_sky_contribution: float = 0.15
@export var sky3d_ambient_energy: float = 0.85
@export var sky3d_sun_energy: float = 0.95
@export var sky3d_skydome_energy: float = 0.85
@export var sky3d_atm_sun_intensity: float = 6.0
@export var sky3d_camera_exposure: float = 1.0
@export var sky3d_sun_shadow_opacity: float = 0.45
@export_group("Sky3D Color")
@export var sky3d_adjustment_saturation: float = 1.30
@export var sky3d_adjustment_contrast: float = 1.14
@export var sky3d_adjustment_brightness: float = 1.02
@export_group("TCA")
@export var tca_wind_speed: float = 4.0
@export var tca_wind_direction_degrees: float = 35.0

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
var telemetry_file_path: String = ""
var run_identifier: String = ""
var start_sequence = preload("res://scripts/rally/rally_start_sequence.gd").new()
var start_click: AudioStreamPlayer
var start_horn: AudioStreamPlayer
var course := RallyStageProgress.new()
var competition = preload("res://scripts/rally/rally_competition.gd").new()
var pacenotes = preload("res://scripts/rally/rally_pacenote_controller.gd").new()
var pacenote_hud: Control = null
var weather_sky_node: Node = null
var weather_sky_dome: Node = null
var weather_controller_node: Node = null
var weather_wind: Node = null
var terrain_wetness: Node = null
var weather_is_raining: bool = false


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
	if not course.configure("res://data/rally/russia_stage1_route.json"):
		push_error("Russia course timing route is missing")
		return
	if not competition.configure():
		push_error("Rally competition: " + competition.error)
		return
	course.sector_indices = competition.stage.sector_checkpoint_indices
	if not course.configure_timing_gates(competition.stage.timing_gates):
		push_error("Original rally split gates could not be configured")
		return
	if competition.restore() and not competition.complete and competition.started:
		competition.retire_player("Abandono — sesión interrumpida")
	build_environment()
	apply_start_pose_from_manifest()
	if track_collision == null:
		push_error("Rally session cannot resolve the stage collision builder")
		return
	var collision_ready: bool = await track_collision.build_collision()
	if not collision_ready:
		push_error("Rally session cannot build the stage collision")
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	place_vehicle_on_stage()
	connect_runtime_signals()
	configure_runtime_paths()
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
	print("RALLY_SESSION_READY scene=russia_stage1 vehicle=ford_escort_rs2000_1971 spawn=", start_position, " heading_radians=", start_heading, " physics_engine=", ProjectSettings.get_setting("physics/3d/physics_engine"))


func build_environment() -> void:
	if weather_enabled and _build_weather_system():
		return
	_build_legacy_environment()


## Reparto de responsabilidades:
##   Sky3D -> cielo, atmosfera, nubes, niebla y ciclo dia/noche (sol, luna, hora).
##   TCA   -> calendario de climas, precipitacion (lluvia/nieve), transiciones y viento.
##   Propio-> humedad del terreno acumulada por la lluvia de TCA.
func _build_weather_system() -> bool:
	const SKY3D_SCRIPT := "res://addons/sky_3d/src/Sky3D.gd"
	const TCA_WEATHER_SCRIPT := "res://addons/TCA_Weather_System/scripts/WeatherController.gd"
	const TCA_WIND_SCRIPT := "res://addons/TCA_Weather_System/scripts/wind_controller.gd"
	if not FileAccess.file_exists(SKY3D_SCRIPT):
		push_warning("Sky3D addon missing, using legacy environment")
		return false
	if not FileAccess.file_exists(TCA_WEATHER_SCRIPT) or not FileAccess.file_exists(TCA_WIND_SCRIPT):
		push_warning("TCA addon missing, using legacy environment")
		return false
	if not FileAccess.file_exists(weather_season_path):
		push_warning("TCA season missing, using legacy environment")
		return false
	var season_res: Resource = load(weather_season_path)
	if season_res == null:
		push_warning("TCA season failed to load, using legacy environment")
		return false
	if not _build_sky3d(SKY3D_SCRIPT):
		return false
	if not _build_tca_precipitation(TCA_WEATHER_SCRIPT, season_res):
		return false
	_build_tca_wind(TCA_WIND_SCRIPT)
	_build_terrain_wetness()
	var weather_count: int = 0
	var season_weathers: Variant = season_res.get("weathers")
	if season_weathers is Array:
		weather_count = (season_weathers as Array).size()
	print("RALLY_WEATHER_READY scene=russia_stage1 sky=Sky3D precipitation=TCA wind=TCA season=", weather_season_path, " weathers=", weather_count)
	return true


func _build_sky3d(script_path: String) -> bool:
	var sky_script := load(script_path) as Script
	if sky_script == null:
		push_warning("Sky3D script failed to load, using legacy environment")
		return false
	var sky_node: Node = sky_script.new()
	if sky_node == null:
		push_warning("Sky3D failed to instantiate, using legacy environment")
		return false
	sky_node.name = "Sky3D"
	add_child(sky_node)
	weather_sky_node = sky_node
	weather_sky_dome = sky_node.get("sky")
	sky_node.set("current_time", sky3d_time_of_day)
	sky_node.set("minutes_per_day", sky3d_minutes_per_day)
	sky_node.set("game_time_enabled", true)
	var environment: Environment = sky_node.get("environment")
	if environment != null:
		environment.volumetric_fog_enabled = false
		if dreamcast_visual_mode:
			# Gama cromatica lineal de finales de los 90 (sin compresion filmica)
			environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			# Table Fog lineal de Godot por encima de la niebla atmosferica de Sky3D
			environment.fog_enabled = true
			environment.fog_mode = Environment.FOG_MODE_DEPTH
			environment.fog_light_color = dc_fog_color_day
			environment.fog_depth_begin = dc_fog_begin
			environment.fog_depth_end = dc_fog_end
			environment.fog_depth_curve = 1.0
			environment.fog_sky_affect = 0.35
		else:
			environment.fog_enabled = false
			environment.fog_sky_affect = 0.0
		# Gradado de color: sube la saturacion para que suelo y vegetacion no se vean opacos.
		environment.adjustment_enabled = true
		environment.adjustment_saturation = sky3d_adjustment_saturation
		environment.adjustment_contrast = sky3d_adjustment_contrast
		environment.adjustment_brightness = sky3d_adjustment_brightness
	var sun := sky_node.get("sun") as DirectionalLight3D
	if sun != null:
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 140.0 if dreamcast_visual_mode else 280.0
		sun.shadow_opacity = sky3d_sun_shadow_opacity
	var moon := sky_node.get("moon") as DirectionalLight3D
	if moon != null:
		moon.shadow_enabled = false
	if weather_sky_dome != null:
		weather_sky_dome.set("cumulus_visible", true)
		weather_sky_dome.set("cirrus_visible", true)
		weather_sky_dome.set("cumulus_coverage", sky3d_cumulus_coverage)
		weather_sky_dome.set("cumulus_intensity", sky3d_cumulus_intensity)
		weather_sky_dome.set("cirrus_coverage", sky3d_cirrus_coverage)
		# Con Table Fog Dreamcast se apaga la niebla interna del SkyDome
		weather_sky_dome.set("fog_visible", not dreamcast_visual_mode)
		weather_sky_dome.set("fog_density", sky3d_fog_density)
		weather_sky_dome.set("fog_start", 0.0)
		weather_sky_dome.set("fog_end", sky3d_fog_end)
		weather_sky_dome.set("atm_sun_intensity", sky3d_atm_sun_intensity)
	# Rebalanceo de brillo: Sky3D trae sky_contribution=1.0 (ambiente 100% del cielo),
	# que lava el suelo. Se baja el aporte del cielo y se compensa con ambiente fijo moderado.
	sky_node.set("sky_contribution", sky3d_ambient_sky_contribution)
	sky_node.set("ambient_energy", sky3d_ambient_energy)
	sky_node.set("sun_energy", sky3d_sun_energy)
	sky_node.set("skydome_energy", sky3d_skydome_energy)
	sky_node.set("camera_exposure", sky3d_camera_exposure)
	return true


func _build_tca_precipitation(script_path: String, season_res: Resource) -> bool:
	var weather_script := load(script_path) as Script
	if weather_script == null:
		push_warning("TCA WeatherController failed to load, using legacy environment")
		return false
	var controller: Node = weather_script.new()
	if controller == null:
		push_warning("TCA WeatherController failed to instantiate, using legacy environment")
		return false
	controller.name = "TCAWeatherController"
	# Sky3D manda sobre cielo, niebla y luces: TCA solo lleva clima y precipitacion.
	controller.set("drive_environment", false)
	var seasons: Array = controller.get("seasons")
	if seasons == null:
		seasons = []
		controller.set("seasons", seasons)
	seasons.clear()
	seasons.append(season_res)
	# Un dia de TCA dura los mismos minutos reales que un dia de Sky3D.
	var minutes_per_day: float = maxf(sky3d_minutes_per_day, 0.1)
	var tca_speed: float = (86400.0 / (minutes_per_day * 60.0)) * maxf(weather_speed_multiplier, 0.01)
	controller.set("time_speed_multiplier", tca_speed)
	controller.set("start_time", clampf(sky3d_time_of_day, 0.0, 23.99) / 24.0 * 86400.0)
	controller.set("start_season", 0)
	controller.set("start_weather", weather_start_weather)
	# Las senales se conectan antes de entrar al arbol: el clima inicial se emite en _ready().
	controller.connect(&"weather_changed", _on_tca_weather_changed)
	controller.connect(&"weather_ended", _on_tca_weather_ended)
	controller.connect(&"season_changed", _on_tca_season_changed)
	add_child(controller)
	weather_controller_node = controller
	return true


func _build_tca_wind(script_path: String) -> void:
	var wind_script := load(script_path) as Script
	if wind_script == null:
		push_warning("TCA WindController failed to load; clouds will not drift with wind")
		return
	var wind: Node = wind_script.new()
	if wind == null:
		return
	wind.name = "TCAWindController"
	wind.set("wind_speed", tca_wind_speed)
	var radians := deg_to_rad(tca_wind_direction_degrees)
	wind.set("wind_direction", Vector2(cos(radians), sin(radians)))
	add_child(wind)
	weather_wind = wind


func _build_terrain_wetness() -> void:
	# En modo Dreamcast evitamos que el script de humedad active reflejos PBR en el barro/asfalto
	if dreamcast_visual_mode or track_visual == null:
		return
	const WETNESS_SCRIPT := "res://scripts/rally/rally_terrain_wetness.gd"
	if not FileAccess.file_exists(WETNESS_SCRIPT):
		return
	var wetness_script := load(WETNESS_SCRIPT) as Script
	if wetness_script == null:
		return
	var wetness_node: Node = wetness_script.new()
	if wetness_node == null:
		return
	wetness_node.name = "RallyTerrainWetness"
	wetness_node.set("visual_root", track_visual)
	add_child(wetness_node)
	terrain_wetness = wetness_node


func sync_weather_wind() -> void:
	if weather_wind == null or weather_sky_dome == null:
		return
	var speed: float = float(weather_wind.call("get_wind_speed"))
	var direction: Vector2 = weather_wind.call("get_wind_direction")
	weather_sky_dome.set("wind_speed", speed)
	if direction.length_squared() > 0.000001:
		weather_sky_dome.set("wind_direction", atan2(direction.y, direction.x))


func _process(_delta: float) -> void:
	sync_weather_wind()


func _on_tca_weather_changed(weather) -> void:
	var description := describe_tca_weather(weather)
	var precipitation: Variant = weather.get("precipitation")
	var is_precipitating := precipitation != null
	weather_is_raining = is_precipitating and description.contains("RAIN")
	if terrain_wetness != null:
		terrain_wetness.set_rain_intensity(1.0 if weather_is_raining else 0.0)
	# Las nubes siguen siendo de Sky3D; esto solo ajusta su cobertura cuando TCA
	# anuncia precipitacion, para no tener nieve cayendo de un cielo despejado.
	if couple_clouds_to_weather and weather_sky_dome != null:
		var coverage: float = sky3d_precipitation_cloud_coverage if is_precipitating else sky3d_cumulus_coverage
		weather_sky_dome.set("cumulus_coverage", coverage)
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


func _build_legacy_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.46, 0.62)
	sky_material.sky_horizon_color = Color(0.68, 0.71, 0.72)
	sky_material.ground_bottom_color = Color(0.14, 0.16, 0.15)
	sky_material.ground_horizon_color = Color(0.48, 0.49, 0.46)
	sky_material.sun_angle_max = 22.0
	sky_material.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.72
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.fog_enabled = true
	if dreamcast_visual_mode:
		# Gama lineal y Table Fog de profundidad, igual que en el entorno de Sky3D
		environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		environment.tonemap_exposure = 1.0
		environment.fog_mode = Environment.FOG_MODE_DEPTH
		environment.fog_light_color = dc_fog_color_day
		environment.fog_depth_begin = dc_fog_begin
		environment.fog_depth_end = dc_fog_end
		environment.fog_depth_curve = 1.0
	else:
		environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		environment.tonemap_exposure = 1.0
		environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		environment.fog_light_color = Color(0.21, 0.25, 0.28)
		environment.fog_density = 0.0026
		environment.fog_sun_scatter = 0.18
		environment.fog_aerial_perspective = 0.25
	var world_environment := WorldEnvironment.new()
	world_environment.name = "RallyWorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.name = "RallySun"
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	sun.light_color = Color(1.0, 0.88, 0.62)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 280.0
	add_child(sun)


func apply_start_pose_from_manifest() -> void:
	if not FileAccess.file_exists(STAGE_MANIFEST_PATH):
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
	vehicle.global_transform = Transform3D(start_basis, start_position)
	vehicle.simulation.unsprung_rig.reset()
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.sleeping = false
	vehicle.freeze = false
	input_controller.set_spawn_pose(start_position, start_heading)
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
	if track_visual != null:
		var adjuster := RallyStageVisualMaterialAdjuster.new()
		adjuster.visual_root_path = track_visual.get_path()
		add_child(adjuster)


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


func on_vehicle_reset_requested() -> void:
	if course.running and not competition.complete:
		# Rescue at the last validated control, preserving official progress/time.
		var index := maxi(0, course.next_checkpoint - 1)
		var target: Vector3 = course.points[index] + Vector3.UP * 0.2
		var direction: Vector3 = course.points[mini(index + 1, course.points.size() - 1)] - course.points[index]
		var heading := atan2(-direction.x, -direction.z)
		vehicle.reset_to_pose(target, heading)
		course.generation = vehicle.simulation.session_generation
		course.previous_position = target
		competition.generation = course.generation
		competition.add_penalty("player", int(competition.balance.reset_penalty_ms), "Rescate")
		camera_rig.snap_to_target()
		pacenotes.on_rescue(target)
		head_up_display.show_status("RESCATE +30 s", Color(0.95, 0.72, 0.24), 2.2)
	else:
		course.generation = vehicle.simulation.session_generation
		course.previous_position = vehicle.global_position
		head_up_display.show_status("VEHICLE RESET TO START", Color(0.95, 0.72, 0.24), 2.2)


func _physics_process(delta: float) -> void:
	if not session_ready or vehicle == null:
		return
	elapsed_seconds += delta
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
				var summary: Dictionary = competition.readout()
				head_up_display.show_status("PARCIAL %d/9   %.3f s   DELTA %+.3f s" % [competition.sector, float(competition.player_ms + competition.player_penalty_ms) / 1000.0, float(summary.delta_ms) / 1000.0], Color(0.45, 0.9, 0.6), 3.0)
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
	return {
		"elapsed_seconds": elapsed_seconds,
		"course": course.readout(),
		"competition": competition.readout(),
		"pacenotes": {"next_gate": pacenotes.tracker.next_gate, "active_call": pacenotes.call_queue.get_active_record()},
		"start_sequence": start_sequence.readout() if not competition.complete else {},
		"run_identifier": run_identifier,
		"physics_engine": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"start_position": start_position,
		"start_heading": start_heading,
		"telemetry_file_path": telemetry_file_path,
	}


func reset_vehicle_to_start() -> void:
	vehicle.reset_to_pose(start_position, start_heading)
	camera_rig.snap_to_target()
	head_up_display.show_status("VEHICLE RESET TO START", Color(0.95, 0.72, 0.24), 2.2)


func apply_competition_controls() -> void:
	input_controller.set_controls_enabled(not competition.complete)
	vehicle.freeze = competition.complete
	if competition.complete:
		vehicle.linear_velocity = Vector3.ZERO
		vehicle.angular_velocity = Vector3.ZERO
	head_up_display.set_session_state(get_session_state())

func retire_competition_player() -> void:
	competition.retire_player()
	pacenotes.on_retire()
	apply_competition_controls()

func reset_competition_car() -> void:
	course.reset_attempt()
	pacenotes.on_retry()
	vehicle.reset_to_pose(start_position, start_heading)
	course.generation = vehicle.simulation.session_generation
	reset_start_sequence()
	camera_rig.snap_to_target()
	apply_competition_controls()

func retry_competition_attempt() -> void:
	competition.reset_attempt()
	competition.save()
	reset_competition_car()

func continue_competition() -> void:
	if competition.next_stage():
		reset_competition_car()

func start_new_competition() -> void:
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


func _exit_tree() -> void:
	if session_ready and competition.started:
		competition.save()


func setup_pacenotes() -> void:
	pacenotes.name = "RallyPacenotes"
	add_child(pacenotes)
	if head_up_display != null:
		pacenote_hud = preload("res://scenes/rally/cmr2_pacenote_hud.tscn").instantiate()
		head_up_display.add_child(pacenote_hud)
		pacenotes.set_hud(pacenote_hud)
	pacenotes.configure("res://data/rally/pacenotes/russia_stage1.json")


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
