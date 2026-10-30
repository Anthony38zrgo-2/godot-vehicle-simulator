class_name RallyProvingGroundSession
extends Node3D

const SPAWN_POSITION := Vector3(0.0, 0.12, 0.0)
const SPAWN_HEADING := 0.0
const FALL_RESET_HEIGHT := -25.0

@export var vehicle_path: NodePath
@export var input_controller_path: NodePath
@export var camera_rig_path: NodePath
@export var head_up_display_path: NodePath
@export var telemetry_recorder_path: NodePath

var vehicle: RallyEscortVehicle
var input_controller: RallyVehicleInputController
var camera_rig: RallyChaseCameraRig
var head_up_display: RallyF1HeadUpDisplay
var telemetry_recorder: RallyTelemetryRecorder
var elapsed_seconds: float = 0.0
var session_ready: bool = false


func _ready() -> void:
	var shared_telemetry_manager := get_node_or_null("/root/TelemetryManager")
	if shared_telemetry_manager != null:
		shared_telemetry_manager.enabled = false
	vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	input_controller = get_node_or_null(input_controller_path) as RallyVehicleInputController
	camera_rig = get_node_or_null(camera_rig_path) as RallyChaseCameraRig
	head_up_display = get_node_or_null(head_up_display_path) as RallyF1HeadUpDisplay
	telemetry_recorder = get_node_or_null(telemetry_recorder_path) as RallyTelemetryRecorder
	if vehicle == null or input_controller == null or camera_rig == null or head_up_display == null:
		push_error("Rally proving ground is missing a mandatory runtime binding")
		return
	vehicle.freeze = true
	if telemetry_recorder != null:
		telemetry_recorder.set_physics_process(false)
	build_environment()
	build_ground()
	build_obstacles()
	await get_tree().physics_frame
	await get_tree().physics_frame
	place_vehicle()
	input_controller.camera_mode_toggle_requested.connect(on_camera_mode_toggle_requested)
	input_controller.driving_assistance_changed.connect(on_driving_assistance_changed)
	input_controller.vehicle_reset_requested.connect(on_vehicle_reset_requested)
	head_up_display.set_vehicle(vehicle)
	if telemetry_recorder != null:
		telemetry_recorder.set_physics_process(true)
	session_ready = true
	print("RALLY_PROVING_GROUND_READY physics_engine=", ProjectSettings.get_setting("physics/3d/physics_engine"))
	if OS.get_cmdline_user_args().has("--rally-smoke"):
		_run_gdscript_smoke()


func _run_gdscript_smoke() -> void:
	var alignment := _check_alignment_symmetry()
	var initial_engine := vehicle.get_engine_thermal_state()
	var initial_block_c := float(initial_engine.get("block", {}).get("temperature_c", 0.0))
	var required_actions := [InputBindings.THROTTLE, InputBindings.BRAKES, InputBindings.STEER_LEFT, InputBindings.STEER_RIGHT]
	var actions_ready := true
	for action in required_actions:
		actions_ready = actions_ready and InputMap.has_action(action)
	vehicle.shift(1)
	Input.action_press(InputBindings.THROTTLE)
	Input.action_press(InputBindings.STEER_LEFT)
	await get_tree().create_timer(1.5).timeout
	var throttle_seen := vehicle.throttle_input > 0.5
	var forward_speed_under_throttle := vehicle.linear_velocity.dot(-vehicle.global_basis.z)
	var steering_seen := vehicle.steering_input > 0.25
	Input.action_release(InputBindings.THROTTLE)
	Input.action_release(InputBindings.STEER_LEFT)
	Input.action_press(InputBindings.BRAKES)
	await get_tree().create_timer(0.35).timeout
	var brake_seen := vehicle.brake_input > 0.5
	Input.action_release(InputBindings.BRAKES)
	await get_tree().create_timer(1.0).timeout
	var contacts := vehicle.get_number_of_contacting_wheels()
	var query_count := vehicle.simulation.contact_query_count
	var final_engine := vehicle.get_engine_thermal_state()
	var final_block_c := float(final_engine.get("block", {}).get("temperature_c", initial_block_c))
	var tire_state := vehicle.get_tire_thermal_state(0)
	var thermal_changed := absf(final_block_c - initial_block_c) > 0.001 or float(tire_state.get("tread_c", 0.0)) != float(simulation_initial_tire_temperature())
	var passed := forward_speed_under_throttle > 0.5 and actions_ready and throttle_seen and brake_seen and steering_seen and vehicle.current_gear == 1 and contacts > 0 and query_count == 4 and thermal_changed and bool(alignment.get("passed", false))
	var evidence := {
		"passed": passed,
		"alignment": alignment,
		"forward_speed_under_throttle_m_s": forward_speed_under_throttle,
		"actions_loaded": actions_ready,
		"throttle_input_seen": throttle_seen,
		"brake_input_seen": brake_seen,
		"steering_input_seen": steering_seen,
		"first_gear_engaged": vehicle.current_gear == 1,
		"contacting_wheels": contacts,
		"contact_queries_last_step": query_count,
		"engine_block_start_c": initial_block_c,
		"engine_block_end_c": final_block_c,
		"front_left_tread_c": tire_state.get("tread_c"),
	}
	print("RALLY_GDSCRIPT_SMOKE ", JSON.stringify(evidence))
	get_tree().quit(0 if passed else 1)


func _check_alignment_symmetry() -> Dictionary:
	var simulation := vehicle.simulation
	var suspension = simulation.suspension_model
	var front_left_camber := suspension.dynamic_camber(0)
	var front_right_camber := suspension.dynamic_camber(1)
	var front_left_wheel_camber := suspension.dynamic_wheel_camber(0)
	var front_right_wheel_camber := suspension.dynamic_wheel_camber(1)
	var front_left_toe := suspension.dynamic_toe(0)
	var front_right_toe := suspension.dynamic_toe(1)
	var rear_left_toe := suspension.dynamic_toe(2)
	var rear_right_toe := suspension.dynamic_toe(3)
	var front_parameters: Dictionary = suspension.axle_parameters[0]
	var front_travel_delta: float = float(suspension.compression[0]) - float(front_parameters.get("rest_compression_offset", 0.0))
	var front_axle_toe: float = float(front_parameters.get("toe", 0.0)) + float(front_parameters.get("toe_gain", 0.0)) * front_travel_delta
	var tire_domain: Dictionary = simulation.domains.get("tires", {})
	var tire_filter_domain: Dictionary = simulation.domains.get("tire_filters", {})
	var resolved_filters := VehicleProfileLoader._resolve_tire_filters(tire_domain, tire_filter_domain)
	var tire_probe := TireModel.new()
	tire_probe.configure(simulation.domains, resolved_filters, suspension.static_corner_loads_n)
	var wheel_speed := 8.0 / simulation.wheel_radii[0]
	var left_pressure := float(simulation.thermal_model.get_tire_thermal_state_snapshot(0).get("pressure_kpa_gauge", 180.0))
	var right_pressure := float(simulation.thermal_model.get_tire_thermal_state_snapshot(1).get("pressure_kpa_gauge", 180.0))
	var left_result: Dictionary = tire_probe.evaluate(
		0, suspension.static_corner_loads_n[0], "Gravel", 8.0, 0.0, wheel_speed,
		simulation.wheel_radii[0], front_left_camber, 1.0, left_pressure, 1.0 / 120.0, 25.0
	)
	var right_result: Dictionary = tire_probe.evaluate(
		1, suspension.static_corner_loads_n[1], "Gravel", 8.0, 0.0, wheel_speed,
		simulation.wheel_radii[1], front_right_camber, 1.0, right_pressure, 1.0 / 120.0, 25.0
	)
	var camber_axis_error := absf(front_left_camber - front_right_camber)
	var wheel_camber_mirror_error := absf(front_left_wheel_camber + front_right_wheel_camber)
	var toe_mirror_error := absf(front_left_toe + front_right_toe)
	var toe_convention_error := maxf(absf(front_left_toe + front_axle_toe), absf(front_right_toe - front_axle_toe))
	var camber_force_sum := float(left_result.get("lateral_force_n", 0.0)) + float(right_result.get("lateral_force_n", 0.0))
	var passed := camber_axis_error < 1e-7 and wheel_camber_mirror_error < 1e-7 and toe_mirror_error < 1e-7 and toe_convention_error < 1e-7 and absf(rear_left_toe) < 1e-7 and absf(rear_right_toe) < 1e-7 and absf(camber_force_sum) < 1e-4
	return {
		"passed": passed,
		"front_camber_axis_error_rad": camber_axis_error,
		"front_wheel_camber_mirror_error_rad": wheel_camber_mirror_error,
		"front_toe_mirror_error_rad": toe_mirror_error,
		"front_toe_convention_error_rad": toe_convention_error,
		"front_toe_rad": [front_left_toe, front_right_toe],
		"rear_toe_rad": [rear_left_toe, rear_right_toe],
		"equal_load_camber_force_sum_n": camber_force_sum,
	}


func simulation_initial_tire_temperature() -> float:
	return float(vehicle.simulation.thermal_model.tire_config.get("initial_temperature_c", vehicle.simulation.thermal_model.ambient_temperature_c))


func build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.28, 0.42, 0.58)
	sky_material.sky_horizon_color = Color(0.7, 0.73, 0.74)
	sky_material.ground_bottom_color = Color(0.18, 0.18, 0.16)
	sky_material.ground_horizon_color = Color(0.45, 0.44, 0.38)
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = Color(0.55, 0.58, 0.6)
	environment.fog_density = 0.002
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -30.0, 0.0)
	sun.light_color = Color(1.0, 0.9, 0.72)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)


func build_ground() -> void:
	var ground_body := StaticBody3D.new()
	ground_body.name = "ProvingGround"
	ground_body.collision_layer = 1
	ground_body.collision_mask = 0
	ground_body.add_to_group("Gravel")
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(400.0, 2.0, 400.0)
	ground_shape.shape = ground_box
	ground_shape.position = Vector3(0.0, -1.0, 0.0)
	ground_body.add_child(ground_shape)
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 0.9
	ground_body.physics_material_override = physics_material
	add_child(ground_body)
	var ground_visual := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(400.0, 2.0, 400.0)
	ground_visual.mesh = ground_mesh
	ground_visual.position = Vector3(0.0, -1.0, 0.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.34, 0.31, 0.24)
	ground_material.roughness = 1.0
	ground_visual.material_override = ground_material
	add_child(ground_visual)
	for lane_index in 21:
		var lane := MeshInstance3D.new()
		var lane_mesh := BoxMesh.new()
		lane_mesh.size = Vector3(0.06, 0.01, 300.0)
		lane.mesh = lane_mesh
		lane.position = Vector3(-20.0 + lane_index * 2.0, 0.005, 0.0)
		var lane_material := StandardMaterial3D.new()
		lane_material.albedo_color = Color(0.55, 0.52, 0.4)
		lane.material_override = lane_material
		add_child(lane)
	for stripe_index in 31:
		var stripe := MeshInstance3D.new()
		var stripe_mesh := BoxMesh.new()
		stripe_mesh.size = Vector3(300.0, 0.01, 0.06)
		stripe.mesh = stripe_mesh
		stripe.position = Vector3(0.0, 0.005, -150.0 + stripe_index * 10.0)
		var stripe_material := StandardMaterial3D.new()
		stripe_material.albedo_color = Color(0.55, 0.52, 0.4)
		stripe.material_override = stripe_material
		add_child(stripe)


func build_obstacles() -> void:
	build_tree(Vector3(0.0, 0.0, -18.0))
	build_tree(Vector3(6.0, 0.0, -34.0))
	build_wall(Vector3(0.0, 0.55, -45.0), Vector3(24.0, 1.1, 0.6))
	build_ramp(Vector3(-15.0, 0.45, -22.0))
	build_box(Vector3(13.0, 0.4, -12.0), Vector3(2.4, 0.8, 1.2), Color(0.55, 0.35, 0.2))


func build_tree(position: Vector3) -> void:
	var tree_body := StaticBody3D.new()
	tree_body.name = "Tree"
	tree_body.position = position
	tree_body.collision_layer = 1
	tree_body.collision_mask = 0
	tree_body.add_to_group("Gravel")
	var trunk_shape := CollisionShape3D.new()
	var trunk_cylinder := CylinderShape3D.new()
	trunk_cylinder.radius = 0.3
	trunk_cylinder.height = 4.2
	trunk_shape.shape = trunk_cylinder
	trunk_shape.position = Vector3(0.0, 2.1, 0.0)
	tree_body.add_child(trunk_shape)
	var trunk_visual := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.2
	trunk_mesh.bottom_radius = 0.32
	trunk_mesh.height = 4.2
	trunk_visual.mesh = trunk_mesh
	trunk_visual.position = Vector3(0.0, 2.1, 0.0)
	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.3, 0.19, 0.11)
	trunk_visual.material_override = trunk_material
	tree_body.add_child(trunk_visual)
	var foliage_visual := MeshInstance3D.new()
	var foliage_mesh := SphereMesh.new()
	foliage_mesh.radius = 2.2
	foliage_mesh.height = 4.4
	foliage_visual.mesh = foliage_mesh
	foliage_visual.position = Vector3(0.0, 5.0, 0.0)
	var foliage_material := StandardMaterial3D.new()
	foliage_material.albedo_color = Color(0.18, 0.38, 0.18)
	foliage_visual.material_override = foliage_material
	tree_body.add_child(foliage_visual)
	add_child(tree_body)


func build_wall(position: Vector3, size: Vector3) -> void:
	build_box(position, size, Color(0.55, 0.55, 0.53))


func build_box(position: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = "Obstacle"
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("Gravel")
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	body.add_child(visual)
	add_child(body)


func build_ramp(position: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Ramp"
	body.position = position
	body.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("Gravel")
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(8.0, 0.3, 12.0)
	shape.shape = box_shape
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8.0, 0.3, 12.0)
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.38, 0.3)
	visual.material_override = material
	body.add_child(visual)
	add_child(body)


func place_vehicle() -> void:
	vehicle.global_transform = Transform3D(Basis(Vector3.UP, SPAWN_HEADING), SPAWN_POSITION)
	vehicle.simulation.unsprung_rig.reset()
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.sleeping = false
	vehicle.freeze = false
	input_controller.set_spawn_pose(SPAWN_POSITION, SPAWN_HEADING)
	camera_rig.snap_to_target()
	head_up_display.show_status("PROVING GROUND  ARROWS DRIVE  A/Z SHIFT  DELETE AUTO  T TCS  R RESET  C CAMERA", Color(0.34, 0.82, 0.45), 4.0)


func on_camera_mode_toggle_requested() -> void:
	camera_rig.toggle_camera_mode()


func on_driving_assistance_changed(state: Dictionary) -> void:
	print("RALLY_ASSISTANCE ", JSON.stringify(state))


func on_vehicle_reset_requested() -> void:
	head_up_display.show_status("VEHICLE RESET", Color(0.95, 0.72, 0.24), 2.0)


func _physics_process(delta: float) -> void:
	if not session_ready or vehicle == null:
		return
	elapsed_seconds += delta
	if vehicle.global_position.y < FALL_RESET_HEIGHT:
		vehicle.reset_to_pose(SPAWN_POSITION, SPAWN_HEADING)
	if vehicle.sleeping:
		vehicle.sleeping = false
