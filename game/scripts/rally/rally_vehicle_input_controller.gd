class_name RallyVehicleInputController
extends Node

signal camera_mode_toggle_requested
signal driving_assistance_changed(state: Dictionary)
signal vehicle_reset_requested
signal garage_menu_requested

@export var vehicle_path: NodePath
@export var action_throttle: String = InputBindings.THROTTLE
@export var action_brakes: String = InputBindings.BRAKES
@export var action_steer_left: String = InputBindings.STEER_LEFT
@export var action_steer_right: String = InputBindings.STEER_RIGHT
@export var action_handbrake: String = InputBindings.HANDBRAKE
@export var action_clutch: String = InputBindings.CLUTCH
@export var action_shift_up: String = InputBindings.SHIFT_UP
@export var action_shift_down: String = InputBindings.SHIFT_DOWN
@export var action_toggle_transmission: String = InputBindings.TOGGLE_TRANSMISSION
@export var action_toggle_traction_control: String = InputBindings.TOGGLE_TRACTION_CONTROL
@export var action_reset_vehicle: String = InputBindings.RESET_VEHICLE
@export var action_toggle_camera: String = InputBindings.TOGGLE_CAMERA
@export var action_toggle_garage: String = InputBindings.TOGGLE_GARAGE
@export var action_assistance_1: String = InputBindings.AID_1
@export var action_assistance_2: String = InputBindings.AID_2
@export var action_assistance_3: String = InputBindings.AID_3

var vehicle: RallyEscortVehicle
var spawn_position: Vector3 = Vector3.ZERO
var spawn_yaw: float = 0.0
var controls_enabled: bool = true
var throttle_release_value: float = 0.0
var brake_release_value: float = 0.0
var steering_return_speed_pending: bool = false


func _ready() -> void:
	vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	if vehicle == null:
		push_error("Rally input controller cannot resolve its vehicle: " + str(vehicle_path))
		set_physics_process(false)
		return
	set_spawn_pose(vehicle.global_position, vehicle.global_rotation.y)
	steering_return_speed_pending = true


func set_spawn_pose(position: Vector3, yaw: float) -> void:
	spawn_position = position
	spawn_yaw = yaw


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled and vehicle != null:
		vehicle.throttle_input = 0.0
		vehicle.brake_input = 0.0
		vehicle.steering_input = 0.0
		vehicle.handbrake_input = 0.0
		vehicle.clutch_input = 0.0


func _physics_process(delta: float) -> void:
	if vehicle == null:
		return
	if Input.is_action_just_pressed(action_toggle_garage):
		garage_menu_requested.emit()
	if not controls_enabled:
		return
	if steering_return_speed_pending:
		apply_steering_return_speed()
	var input_profile := active_input_profile()
	var throttle_value := shaped_unsigned_input(action_throttle, input_profile.throttle_curve_exponent if input_profile != null else 1.0)
	throttle_value = apply_pedal_release(throttle_value, false, input_profile, delta)
	var brake_value := shaped_unsigned_input(action_brakes, input_profile.brake_curve_exponent if input_profile != null else 1.0)
	brake_value = apply_pedal_release(brake_value, true, input_profile, delta)
	var steering_value := shaped_steering_input(input_profile)
	var handbrake_value := action_strength(action_handbrake)
	var clutch_value := clampf(action_strength(action_clutch) + handbrake_value, 0.0, 1.0)
	process_transmission_controls()
	process_assistance_controls()
	process_reset_control()
	process_camera_control()
	var next_gear := resolve_manual_gear_request()
	if vehicle.current_gear == -1:
		var requested_throttle := brake_value
		brake_value = throttle_value
		throttle_value = requested_throttle
	vehicle.throttle_input = throttle_value
	vehicle.brake_input = brake_value
	vehicle.steering_input = steering_value
	vehicle.handbrake_input = handbrake_value
	vehicle.clutch_input = clutch_value
	if next_gear != vehicle.current_gear:
		vehicle.shift(next_gear - vehicle.current_gear)


func action_strength(action: String) -> float:
	if action.is_empty() or not InputMap.has_action(action):
		return 0.0
	return Input.get_action_strength(action)


func shaped_unsigned_input(action: String, curve_exponent: float) -> float:
	return InputProfile.apply_unsigned_curve(action_strength(action), curve_exponent)


func shaped_steering_input(input_profile: InputProfile) -> float:
	var raw_value := action_strength(action_steer_left) - action_strength(action_steer_right)
	if input_profile == null:
		return clampf(raw_value, -1.0, 1.0)
	var deadzoned := InputProfile.remap_axis_deadzone(raw_value, input_profile.steering_axis_deadzone)
	return InputProfile.apply_signed_curve(deadzoned, input_profile.steering_curve_exponent)


func apply_pedal_release(raw_value: float, is_brake_pedal: bool, input_profile: InputProfile, delta_seconds: float) -> float:
	var release_speed := 0.0
	if input_profile != null:
		release_speed = input_profile.brake_release_speed_per_second if is_brake_pedal else input_profile.throttle_release_speed_per_second
	if is_brake_pedal:
		brake_release_value = InputProfile.apply_release_limit(brake_release_value, raw_value, release_speed, delta_seconds)
		return brake_release_value
	throttle_release_value = InputProfile.apply_release_limit(throttle_release_value, raw_value, release_speed, delta_seconds)
	return throttle_release_value


func active_input_profile() -> InputProfile:
	var bindings := get_node_or_null("/root/InputBindings")
	if bindings == null:
		return null
	var profile: InputProfile = bindings.input_profile
	if profile == null or not profile.is_valid():
		return null
	return profile


func apply_steering_return_speed() -> void:
	steering_return_speed_pending = false
	var input_profile := active_input_profile()
	if input_profile == null:
		return
	vehicle.countersteer_speed = input_profile.steering_return_speed_per_second


func process_transmission_controls() -> void:
	if Input.is_action_just_pressed(action_toggle_transmission):
		emit_assistance_state(vehicle.toggle_driving_assistance("automatic_transmission"))
	if Input.is_action_just_pressed(action_toggle_traction_control):
		emit_assistance_state(vehicle.toggle_driving_assistance("traction_control"))


func process_assistance_controls() -> void:
	if Input.is_action_just_pressed(action_assistance_1):
		emit_assistance_state(vehicle.toggle_driving_assistance("stability"))
	if Input.is_action_just_pressed(action_assistance_2):
		emit_assistance_state(vehicle.toggle_driving_assistance("anti_lock_brakes"))
	if Input.is_action_just_pressed(action_assistance_3):
		emit_assistance_state(vehicle.toggle_driving_assistance("countersteer"))


func process_reset_control() -> void:
	if Input.is_action_just_pressed(action_reset_vehicle):
		vehicle.reset_to_pose(spawn_position, spawn_yaw)
		vehicle_reset_requested.emit()


func process_camera_control() -> void:
	if Input.is_action_just_pressed(action_toggle_camera):
		camera_mode_toggle_requested.emit()


func resolve_manual_gear_request() -> int:
	if vehicle.automatic_transmission:
		return vehicle.current_gear
	if Input.is_action_just_pressed(action_shift_up):
		if vehicle.current_gear == -1:
			return 0
		if vehicle.current_gear < vehicle.maximum_forward_gear:
			return vehicle.current_gear + 1
	if Input.is_action_just_pressed(action_shift_down):
		if vehicle.current_gear > 0:
			return vehicle.current_gear - 1
		if vehicle.current_gear == 0 and absf(vehicle.speed * 3.6) < 3.0:
			return -1
	return vehicle.current_gear


func emit_assistance_state(state: Dictionary) -> void:
	driving_assistance_changed.emit(state)
