class_name RallyChaseCameraRig
extends Node3D

@export var vehicle_path: NodePath
@export var camera_path: NodePath = NodePath("Camera3D")
@export var chase_distance_metres: float = 6.2
@export var chase_height_metres: float = 2.45
@export var chase_look_ahead_metres: float = 5.0
@export var chase_look_height_metres: float = 0.8
@export var bonnet_offset_metres: Vector3 = Vector3(0.0, 1.02, -0.55)
@export var bonnet_look_ahead_metres: float = 12.0
@export var base_field_of_view_degrees: float = 68.0
@export var cockpit_field_of_view_degrees: float = 75.0
@export var cockpit_eye_offset_metres := Vector3(-0.325, 1.015, 0.015)
@export var cockpit_pitch_degrees: float = -8.0

enum Mode { CHASE, BONNET, COCKPIT }

var vehicle: RallyEscortVehicle
var camera: Camera3D
var camera_mode: int = 0


func _ready() -> void:
	top_level = true
	camera = get_node_or_null(camera_path) as Camera3D
	vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	if camera == null:
		push_error("Rally camera rig cannot resolve its Camera3D")
		set_process(false)
		return
	if vehicle == null:
		push_error("Rally camera rig cannot resolve its vehicle")
		set_process(false)
		return
	var eye := vehicle.get_node_or_null("Chassis/CockpitEye") as Node3D
	if eye != null:
		cockpit_eye_offset_metres = vehicle.to_local(eye.global_position)
	snap_to_target()


func set_vehicle(target_vehicle: RallyEscortVehicle) -> void:
	vehicle = target_vehicle
	vehicle_path = vehicle.get_path()
	snap_to_target()


func toggle_camera_mode() -> void:
	camera_mode = (camera_mode + 1) % Mode.size()
	snap_to_target()


func get_camera_mode_label() -> String:
	return ["CHASE", "BONNET", "COCKPIT"][camera_mode]


func snap_to_target() -> void:
	if vehicle == null or camera == null:
		return
	_update_camera_transform()
	var cockpit_animation := vehicle.get_node_or_null("CockpitAnimation") as RallyCockpitAnimation
	if cockpit_animation != null:
		cockpit_animation.set_cockpit_view(camera_mode == Mode.COCKPIT)


func _process(_delta: float) -> void:
	if vehicle == null or camera == null:
		return
	_update_camera_transform()


func _update_camera_transform() -> void:
	if camera_mode == Mode.COCKPIT:
		global_transform = vehicle.global_transform * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(cockpit_pitch_degrees)), cockpit_eye_offset_metres)
		camera.fov = cockpit_field_of_view_degrees
		camera.near = 0.035
		return
	global_position = calculate_desired_position()
	look_at(calculate_look_target(), Vector3.UP)
	camera.fov = base_field_of_view_degrees
	camera.near = 0.05


func calculate_desired_position() -> Vector3:
	if camera_mode == Mode.COCKPIT:
		return vehicle.global_transform * cockpit_eye_offset_metres
	if camera_mode == Mode.BONNET:
		return vehicle.global_transform * bonnet_offset_metres
	var yaw_basis := Basis(Vector3.UP, vehicle.global_rotation.y)
	return vehicle.global_position + yaw_basis * Vector3(0.0, chase_height_metres, chase_distance_metres)


func calculate_look_target() -> Vector3:
	if camera_mode == Mode.COCKPIT:
		return calculate_desired_position() - global_basis.z * 12.0
	if camera_mode == Mode.BONNET:
		return vehicle.global_transform * Vector3(0.0, 0.95, -bonnet_look_ahead_metres)
	var yaw_basis := Basis(Vector3.UP, vehicle.global_rotation.y)
	return vehicle.global_position + yaw_basis * Vector3(0.0, chase_look_height_metres, -chase_look_ahead_metres)
