extends SceneTree

class TestVehicle extends RallyEscortVehicle:
	func _ready() -> void:
		freeze = true
		set_physics_process(false)
		set_process(false)

	func set_glass_cockpit_view(_enabled: bool) -> void:
		pass

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var vehicle := TestVehicle.new()
	vehicle.name = "Vehicle"
	root.add_child(vehicle)
	var rig := RallyChaseCameraRig.new()
	rig.vehicle_path = NodePath("../Vehicle")
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	root.add_child(rig)
	_check(is_equal_approx(rig.global_position.z, 6.2), "CHASE must load the original distance")
	_check(is_equal_approx(rig.global_position.y, 2.45), "CHASE must load the original height")
	_check((-rig.global_basis.z).is_equal_approx(Vector3(0.0, -1.65, -11.2).normalized()), "CHASE must restore the original viewing angle")
	var before := rig.global_position - vehicle.global_position
	vehicle.position += Vector3(2.0, 0.0, -3.0)
	rig._process(0.0)
	_check((rig.global_position - vehicle.global_position).is_equal_approx(before), "CHASE translation must follow the current render anchor without waiting for physics")
	vehicle.rotation.y = PI / 2.0
	rig._process(1.0 / 60.0)
	var early := rig.calculate_desired_position()
	_check(early.z - vehicle.position.z > 5.0 and early.x > vehicle.position.x, "CHASE must start turning with visible lag")
	for frame in 300:
		rig._process(1.0 / 60.0)
	var settled := rig.calculate_desired_position()
	_check(settled.x - vehicle.position.x > 6.1 and absf(settled.z - vehicle.position.z) < 0.15, "CHASE must converge behind the vehicle")
	vehicle.position = Vector3(20.0, 1.0, 10.0)
	vehicle.rotation = Vector3.ZERO
	rig.snap_to_target()
	_check(rig.global_position.is_equal_approx(Vector3(20.0, 3.45, 16.2)), "Snap must discard the previous pose")

	var terrain := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	collision.shape = box
	terrain.add_child(collision)
	terrain.position = Vector3(20.0, 2.0, 16.2)
	root.add_child(terrain)
	for tick in 40:
		await physics_frame
	await process_frame
	_check(absf(rig.global_position.y - 4.0) < 0.001, "CHASE must settle a metre above terrain")
	terrain.queue_free()
	for tick in 4:
		await physics_frame
	await process_frame
	_check(rig.global_position.y > 3.5 and rig.global_position.y < 4.0, "Ground correction must decay gradually")
	rig.toggle_camera_mode()
	_check(rig.camera_mode == RallyChaseCameraRig.Mode.BONNET, "CHASE must still toggle to bonnet")
	_check(rig.global_position.is_equal_approx(vehicle.global_transform * rig.bonnet_offset_metres), "Bonnet must use its original mount")
	if _failures == 0:
		print("RALLY_CHASE_CAMERA_CONTRACT PASS")
	quit(0 if _failures == 0 else 1)
