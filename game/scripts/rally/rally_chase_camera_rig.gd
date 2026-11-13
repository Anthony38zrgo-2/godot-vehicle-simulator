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

const LOOK_LIMIT := deg_to_rad(110.0)
const LOOK_SPEED := deg_to_rad(540.0)
const CHASE_PROFILE := "res://data/rally/camera/chase_default.json"

var vehicle: RallyEscortVehicle
var camera: Camera3D
var camera_mode: int = 0
var _look_yaw := 0.0
var _chase: Dictionary
var _follow_angles := Vector3.ZERO
var _ground_lift := 0.0
var _required_ground_lift := 0.0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	_resolve_vehicle_eye()
	_load_chase_profile()
	snap_to_target()


func set_vehicle(target_vehicle: RallyEscortVehicle) -> void:
	vehicle = target_vehicle
	vehicle_path = vehicle.get_path()
	_resolve_vehicle_eye()
	_load_chase_profile()
	snap_to_target()


func _resolve_vehicle_eye() -> void:
	var eye := vehicle.get_node_or_null("Chassis/CockpitEye") as Node3D
	if eye != null:
		cockpit_eye_offset_metres = vehicle.to_local(eye.global_position)


func toggle_camera_mode() -> void:
	camera_mode = (camera_mode + 1) % Mode.size()
	if vehicle != null and not vehicle.cockpit_camera_enabled and camera_mode == Mode.COCKPIT:
		camera_mode = Mode.CHASE
	snap_to_target()


func get_camera_mode_label() -> String:
	return ["CHASE", "BONNET", "COCKPIT"][camera_mode]


func snap_to_target() -> void:
	if vehicle == null or camera == null:
		return
	if camera_mode == Mode.CHASE:
		_follow_angles = _vehicle_chase_angles(vehicle.global_basis)
		_ground_lift = 0.0
		_required_ground_lift = 0.0
	_update_camera_transform(vehicle.global_position)
	vehicle.set_glass_cockpit_view(camera_mode == Mode.COCKPIT)
	var cockpit_animation := vehicle.get_node_or_null("CockpitAnimation") as RallyCockpitAnimation
	if cockpit_animation != null:
		cockpit_animation.set_cockpit_view(camera_mode == Mode.COCKPIT)


func _process(delta: float) -> void:
	if vehicle == null or camera == null:
		return
	var look := Input.get_axis(InputBindings.LOOK_RIGHT, InputBindings.LOOK_LEFT)
	var look_limit := LOOK_LIMIT
	var look_speed := LOOK_SPEED
	if camera_mode == Mode.CHASE:
		look_limit = deg_to_rad(_chase.manual_look.limit_deg)
		look_speed = deg_to_rad(_chase.manual_look.speed_deg_per_s)
	_look_yaw = move_toward(_look_yaw, look * look_limit, delta * look_speed)
	var anchor := vehicle.global_transform
	if camera_mode == Mode.CHASE:
		if get_tree().physics_interpolation:
			anchor = vehicle.get_global_transform_interpolated()
		_update_chase_follow(anchor.basis, delta)
		var ground: Dictionary = _chase.ground
		var response: float = ground.rise_response_s if _required_ground_lift > _ground_lift else ground.fall_response_s
		_ground_lift = lerpf(_ground_lift, _required_ground_lift, _response_weight(response, delta))
	_update_camera_transform(anchor.origin)


func _physics_process(delta: float) -> void:
	if vehicle != null and camera != null and camera_mode == Mode.CHASE:
		_probe_ground(calculate_desired_position())


func _update_chase_follow(basis: Basis, delta: float) -> void:
	var target := _vehicle_chase_angles(basis)
	var follow: Dictionary = _chase.follow
	var deadzone := deg_to_rad(follow.angular_deadzone_deg)
	_follow_angles.x = _follow_angle(_follow_angles.x, target.x, follow.pitch_response_s, deadzone, delta)
	_follow_angles.y = _follow_angle(_follow_angles.y, target.y, follow.yaw_response_s, deadzone, delta)
	_follow_angles.z = _follow_angle(_follow_angles.z, target.z, follow.roll_response_s, deadzone, delta)
	var max_lag := deg_to_rad(follow.max_yaw_lag_deg)
	_follow_angles.y = target.y - clampf(angle_difference(_follow_angles.y, target.y), -max_lag, max_lag)


func _vehicle_chase_angles(source_basis: Basis) -> Vector3:
	var basis := source_basis.orthonormalized()
	var forward := -basis.z
	var horizontal := Vector2(forward.x, forward.z)
	var yaw := _follow_angles.y
	if horizontal.length_squared() > 0.000001:
		yaw = atan2(-forward.x, -forward.z)
	var pitch := asin(clampf(forward.y, -1.0, 1.0))
	var heading_basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var roll := heading_basis.x.signed_angle_to(basis.x, heading_basis.z)
	return Vector3(pitch * float(_chase.follow.pitch_influence), yaw, roll * float(_chase.follow.roll_influence))


func _response_weight(seconds: float, delta: float) -> float:
	return 1.0 if seconds <= 0.0 else 1.0 - exp(-delta / seconds)


func _follow_angle(current: float, target: float, seconds: float, deadzone: float, delta: float) -> float:
	var difference := angle_difference(current, target)
	if seconds > 0.0 and absf(difference) < deadzone:
		return current
	return current + difference * _response_weight(seconds, delta)


func _chase_basis() -> Basis:
	return Basis.from_euler(_follow_angles) * Basis(Vector3.UP, _look_yaw)


func _probe_ground(position: Vector3) -> void:
	var ground: Dictionary = _chase.ground
	if not ground.enabled:
		_required_ground_lift = 0.0
		return
	var clearance: float = ground.clearance_m
	var probe: float = ground.probe_height_m
	var query := PhysicsRayQueryParameters3D.create(
		position + Vector3.UP * probe,
		position - Vector3.UP * probe,
		int(ground.collision_mask),
		[vehicle.get_rid()]
	)
	query.hit_back_faces = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_required_ground_lift = 0.0
	if not hit.is_empty():
		_required_ground_lift = maxf(0.0, hit.position.y + clearance - position.y)


func _build_chase_pose(anchor: Vector3) -> Transform3D:
	var position := anchor + _chase_position_offset() + Vector3.UP * _ground_lift
	var target := anchor + _chase_target_offset() + Vector3.UP * _ground_lift * (1.0 - float(_chase.ground.pitch_compensation))
	var direction := (target - position).normalized()
	var up := _chase_basis().y
	if absf(direction.dot(up)) > 0.999:
		up = _chase_basis().x
	return Transform3D(Basis.looking_at(direction, up), position)


func _update_camera_transform(anchor: Vector3) -> void:
	if not vehicle.cockpit_camera_enabled and camera_mode == Mode.COCKPIT:
		camera_mode = Mode.CHASE
	if camera_mode == Mode.COCKPIT:
		var view_basis := Basis(Vector3.UP, _look_yaw) * Basis(Vector3.RIGHT, deg_to_rad(cockpit_pitch_degrees))
		global_transform = vehicle.global_transform * Transform3D(view_basis, cockpit_eye_offset_metres)
		camera.fov = cockpit_field_of_view_degrees
		camera.near = 0.035
		return
	if camera_mode == Mode.CHASE:
		global_transform = _build_chase_pose(anchor)
		camera.fov = _chase.framing.fov_deg
		camera.near = _chase.framing.near_clip_m
		return
	global_position = calculate_desired_position()
	look_at(calculate_look_target(), Vector3.UP)
	camera.fov = base_field_of_view_degrees
	camera.near = 0.25


func calculate_desired_position() -> Vector3:
	if camera_mode == Mode.COCKPIT:
		return vehicle.global_transform * cockpit_eye_offset_metres
	if camera_mode == Mode.BONNET:
		return vehicle.global_transform * bonnet_offset_metres
	return vehicle.global_position + _chase_position_offset()


func _chase_position_offset() -> Vector3:
	return _chase_basis() * Vector3(0.0, _chase.framing.height_m, _chase.framing.distance_m)


func calculate_look_target() -> Vector3:
	if camera_mode == Mode.COCKPIT:
		return calculate_desired_position() - global_basis.z * 12.0
	if camera_mode == Mode.BONNET:
		var direction := Vector3(0.0, 0.95, -bonnet_look_ahead_metres) - bonnet_offset_metres
		return vehicle.global_transform * (bonnet_offset_metres + direction.rotated(Vector3.UP, _look_yaw))
	return vehicle.global_position + _chase_target_offset()


func _chase_target_offset() -> Vector3:
	return _chase_basis() * Vector3(0.0, _chase.framing.look_height_m, -float(_chase.framing.look_ahead_m))


func _load_chase_profile() -> void:
	_chase = {
		"framing": {
			"distance_m": chase_distance_metres, "height_m": chase_height_metres,
			"look_ahead_m": chase_look_ahead_metres, "look_height_m": chase_look_height_metres,
			"fov_deg": base_field_of_view_degrees, "near_clip_m": 0.25,
		},
		"follow": {
			"yaw_response_s": 0.0, "pitch_response_s": 0.0, "roll_response_s": 0.0,
			"pitch_influence": 0.0, "roll_influence": 0.0,
			"angular_deadzone_deg": 0.0, "max_yaw_lag_deg": 180.0,
		},
		"ground": {
			"enabled": false, "clearance_m": 1.0, "probe_height_m": 8.0,
			"collision_mask": 1, "rise_response_s": 0.0, "fall_response_s": 0.78,
			"pitch_compensation": 1.0,
		},
		"manual_look": {"limit_deg": rad_to_deg(LOOK_LIMIT), "speed_deg_per_s": rad_to_deg(LOOK_SPEED)},
	}
	_merge_chase_profile(CHASE_PROFILE)
	if not vehicle.rally_profile_path.is_empty():
		var override_path := vehicle.rally_profile_path.get_base_dir().path_join("chase_camera.json")
		if FileAccess.file_exists(override_path):
			_merge_chase_profile(override_path)


func _merge_chase_profile(path: String) -> void:
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not document is Dictionary or document.get("version") != 1:
		push_warning("Invalid chase camera profile: " + path)
		return
	var ranges := {
		"distance_m": Vector2(0.1, 100.0), "height_m": Vector2(-20.0, 50.0),
		"look_ahead_m": Vector2(0.0, 100.0), "look_height_m": Vector2(-20.0, 50.0),
		"fov_deg": Vector2(1.0, 179.0), "near_clip_m": Vector2(0.01, 5.0),
		"yaw_response_s": Vector2(0.0, 10.0), "pitch_response_s": Vector2(0.0, 10.0),
		"roll_response_s": Vector2(0.0, 10.0), "pitch_influence": Vector2(0.0, 1.0),
		"roll_influence": Vector2(0.0, 1.0), "angular_deadzone_deg": Vector2(0.0, 15.0),
		"max_yaw_lag_deg": Vector2(0.0, 180.0), "clearance_m": Vector2(0.0, 10.0),
		"probe_height_m": Vector2(0.1, 50.0), "collision_mask": Vector2(1.0, 4294967295.0),
		"rise_response_s": Vector2(0.0, 10.0), "fall_response_s": Vector2(0.0, 10.0),
		"pitch_compensation": Vector2(0.0, 1.0), "limit_deg": Vector2(0.0, 180.0),
		"speed_deg_per_s": Vector2(0.0, 3600.0),
	}
	for section: String in _chase:
		var overrides: Variant = document.get(section, {})
		if not overrides is Dictionary:
			push_warning("Invalid chase camera section %s in %s" % [section, path])
			continue
		for key: String in _chase[section]:
			if not overrides.has(key):
				continue
			var value: Variant = overrides[key]
			if key == "enabled" and value is bool:
				_chase[section][key] = value
				continue
			if ranges.has(key) and (value is float or value is int):
				var bounds: Vector2 = ranges[key]
				if is_finite(value) and value >= bounds.x and value <= bounds.y and (key != "collision_mask" or floor(value) == value):
					_chase[section][key] = value
					continue
			push_warning("Invalid chase camera setting %s.%s in %s" % [section, key, path])
