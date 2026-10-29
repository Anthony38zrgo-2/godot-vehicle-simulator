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
var course := RallyStageProgress.new()


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
	print("RALLY_SESSION_READY scene=russia_stage1 vehicle=ford_escort_rs2000_1971 spawn=", start_position, " heading_radians=", start_heading, " physics_engine=", ProjectSettings.get_setting("physics/3d/physics_engine"))


func build_environment() -> void:
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
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.fog_enabled = true
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
	head_up_display.show_status("CAMERA MODE " + ("CHASE" if camera_rig.camera_mode == 0 else "BONNET"), Color(0.94, 0.55, 0.16), 1.6)


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
	head_up_display.show_status("VEHICLE RESET TO START", Color(0.95, 0.72, 0.24), 2.2)
	print("RALLY_VEHICLE_RESET time_seconds=", elapsed_seconds)


func _physics_process(delta: float) -> void:
	if not session_ready or vehicle == null:
		return
	elapsed_seconds += delta
	course.advance(vehicle.global_position, delta, vehicle.simulation.session_generation, vehicle.linear_velocity.length())
	if vehicle.global_position.y < MINIMUM_WORLD_HEIGHT_METRES:
		vehicle.reset_to_pose(start_position, start_heading)
	if vehicle.sleeping:
		vehicle.sleeping = false
	head_up_display.set_session_state(get_session_state())


func get_session_state() -> Dictionary:
	return {
		"elapsed_seconds": elapsed_seconds,
		"course": course.readout(),
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
