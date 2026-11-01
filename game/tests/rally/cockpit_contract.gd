extends SceneTree

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _initialize() -> void:
	call_deferred("run_contract")


func run_contract() -> void:
	var scene_path := "res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn" if "--russia-preview" in OS.get_cmdline_user_args() else "res://scenes/rally/rally_proving_ground.tscn"
	var scene: Node = load(scene_path).instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	await physics_frame
	var vehicle := scene.get_node("FordEscortRS2000") as RallyEscortVehicle
	var rig := scene.get_node("RallyCameraRig") as RallyChaseCameraRig
	var cockpit := vehicle.get_node("CockpitAnimation") as RallyCockpitAnimation
	check(cockpit.arms.size() == 2, "Both animated arms must load")
	if cockpit.arms.size() != 2:
		quit(1)
		return
	vehicle.freeze = true
	vehicle.set_physics_process(false)
	cockpit.set_process(false)
	rig.toggle_camera_mode()
	check(rig.camera_mode == RallyChaseCameraRig.Mode.BONNET, "First camera toggle must select bonnet")
	rig.toggle_camera_mode()
	check(rig.camera_mode == RallyChaseCameraRig.Mode.COCKPIT, "Second toggle must select cockpit")
	check(is_equal_approx(rig.camera.fov, 75.0), "Cockpit FOV must be 75 degrees")
	check(not cockpit.driver_head.visible, "Driver helmet must not occlude cockpit camera")
	var rest_transform := vehicle.transform
	vehicle.transform = Transform3D(Basis.from_euler(Vector3(0.15, 0.6, -0.2)), Vector3(12, 4, 7))
	rig.snap_to_target()
	check((vehicle.global_transform.affine_inverse() * rig.global_position).distance_to(rig.cockpit_eye_offset_metres) < 0.0001, "Cockpit eye must follow chassis translation, pitch and roll")
	check(rig.global_basis.is_equal_approx(vehicle.global_basis * Basis(Vector3.RIGHT, deg_to_rad(rig.cockpit_pitch_degrees))), "Cockpit view must inherit chassis orientation")
	vehicle.transform = rest_transform
	rig.snap_to_target()
	var rest_basis := cockpit.steering_wheel.basis
	for command: float in [0.0, 1.0, -1.0, 0.5, 0.0]:
		cockpit.update_steering_pose(command)
		for arm in cockpit.arms:
			var total := 0.0
			for index in arm.get_blend_shape_count():
				total += arm.get_blend_shape_value(index)
			check(is_equal_approx(total, 1.0), "Arm interpolation must preserve total pose weight")
			var sample := 9.0 * (1.0 - command)
			var lower := int(floor(sample))
			check(arm.get_blend_shape_value(arm.find_blend_shape_by_name("steer_%02d" % lower)) > 0.0, "Both arms must select the matching native steering pose")
		if command != 0.0:
			check(not cockpit.steering_wheel.basis.is_equal_approx(rest_basis), "Steering wheel must rotate with arms")
		if "--capture-cockpit" in OS.get_cmdline_user_args() and command in [0.0, 1.0, -1.0]:
			await process_frame
			await RenderingServer.frame_post_draw
			var label := "neutral" if command == 0.0 else ("left" if command > 0.0 else "right")
			root.get_texture().get_image().save_png("res://logs/rally/cockpit_" + label + ".png")
	check(cockpit.steering_wheel.basis.is_equal_approx(rest_basis), "Returning to neutral must restore the wheel without drift")
	rig.toggle_camera_mode()
	check(rig.camera_mode == RallyChaseCameraRig.Mode.CHASE, "Third camera toggle must return to chase")
	check(cockpit.driver_head.visible, "Chase camera must restore the driver helmet")
	check(is_equal_approx(rig.camera.fov, 68.0), "Chase FOV must retain its setting")
	# Exercise the actual input -> filtered physics steering -> render animation path.
	vehicle.set_physics_process(true)
	cockpit.set_process(true)
	for direction in [InputBindings.STEER_LEFT, InputBindings.STEER_RIGHT]:
		Input.action_press(direction)
		for tick in 100:
			await physics_frame
		await process_frame
		await process_frame
		check(vehicle.steering_amount > 0.1 if direction == InputBindings.STEER_LEFT else vehicle.steering_amount < -0.1, "Driving input must steer in the requested direction")
		check(not cockpit.steering_wheel.basis.is_equal_approx(rest_basis), "Driving input must animate the steering wheel")
		for arm in cockpit.arms:
			check(arm.get_blend_shape_value(arm.find_blend_shape_by_name("steer_09")) < 0.1, "Driving input must animate both arms away from neutral")
		Input.action_release(direction)
	for tick in 100:
		await physics_frame
	await process_frame
	await process_frame
	check(absf(vehicle.steering_amount) < 0.001 and cockpit.steering_wheel.basis.is_equal_approx(rest_basis), "Releasing direction must return steering and cockpit animation to neutral")
	print("RALLY_COCKPIT_CONTRACT ", JSON.stringify({"passed": failures.is_empty(), "failures": failures}))
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
