class_name RallyCockpitAnimation
extends Node

# The original driver1.bzf arms contain 19 samples spanning a half turn.
# Positive steering is left; frame00 is left lock and frame09 is neutral.
const POSE_COUNT := 19
const NEUTRAL_POSE := 9

@export var steering_wheel_lock_degrees: float = 90.0
@export var steering_wheel_axis: Vector3 = Vector3.BACK

var vehicle: RallyEscortVehicle
var steering_wheel: Node3D
var driver_head: MeshInstance3D
var arms: Array[MeshInstance3D] = []
var _wheel_rest_basis: Basis
var _pose_indices: Array[PackedInt32Array] = []
var _head_was_visible: bool = true
var _last_command: float = -9999.0
var _last_lower: int = -1
var _last_upper: int = -1


func _ready() -> void:
	vehicle = get_parent() as RallyEscortVehicle
	var chassis := vehicle.get_node("Chassis")
	steering_wheel = chassis.find_child("steering_wheel_hi", true, false) as Node3D
	driver_head = chassis.find_child("Driver_driver_head", true, false) as MeshInstance3D
	if steering_wheel == null or driver_head == null:
		push_error("Ford cockpit is missing the steering wheel or driver head")
		set_process(false)
		return
	_wheel_rest_basis = steering_wheel.basis
	_head_was_visible = driver_head.visible
	for side in ["left", "right"]:
		var arm := chassis.find_child("DriverArm_" + side + "_frame09", true, false) as MeshInstance3D
		if arm == null:
			push_error("Ford cockpit is missing the " + side + " arm")
			set_process(false)
			return
		var indices := PackedInt32Array()
		for pose in POSE_COUNT:
			var index := arm.find_blend_shape_by_name("steer_%02d" % pose)
			if index < 0:
				push_error("Ford arm is missing original steering pose " + str(pose))
				set_process(false)
				return
			indices.append(index)
		arms.append(arm)
		arm.extra_cull_margin = 0.35
		_pose_indices.append(indices)
	update_steering_pose(0.0)


func _process(_delta: float) -> void:
	var command := vehicle.steering_amount
	var shaped_command := signf(command) * pow(absf(command), maxf(vehicle.steering_exponent, 0.1))
	update_steering_pose(shaped_command)


func update_steering_pose(command: float) -> void:
	if steering_wheel == null or arms.size() != 2:
		return
	command = clampf(command, -1.0, 1.0)
	if absf(command - _last_command) < 0.0005:
		return
	_last_command = command

	# Rotate around the wheel's own shaft, preserving its original tilt and pivot.
	steering_wheel.basis = _wheel_rest_basis * Basis(steering_wheel_axis.normalized(), deg_to_rad(command * steering_wheel_lock_degrees))
	var sample := float(NEUTRAL_POSE) * (1.0 - command)
	var lower := int(floor(sample))
	var upper := mini(lower + 1, POSE_COUNT - 1)
	var fraction := sample - float(lower)

	if _last_lower < 0:
		for side in arms.size():
			for pose in POSE_COUNT:
				if pose != lower and pose != upper:
					arms[side].set_blend_shape_value(_pose_indices[side][pose], 0.0)
	else:
		for side in arms.size():
			if _last_lower != lower and _last_lower != upper:
				arms[side].set_blend_shape_value(_pose_indices[side][_last_lower], 0.0)
			if _last_upper != lower and _last_upper != upper:
				arms[side].set_blend_shape_value(_pose_indices[side][_last_upper], 0.0)

	for side in arms.size():
		if lower == upper:
			arms[side].set_blend_shape_value(_pose_indices[side][lower], 1.0)
		else:
			arms[side].set_blend_shape_value(_pose_indices[side][lower], 1.0 - fraction)
			arms[side].set_blend_shape_value(_pose_indices[side][upper], fraction)

	_last_lower = lower
	_last_upper = upper


func set_cockpit_view(enabled: bool) -> void:
	if driver_head != null:
		driver_head.visible = _head_was_visible and not enabled
