extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func capture(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	var scene = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	var previous := scene.get_node("FordEscortRS2000")
	var original_index := previous.get_index()
	scene.remove_child(previous)
	previous.free()
	var replacement: Node = load("res://scenes/rally/ford_escort_castrol.tscn").instantiate()
	scene.add_child(replacement)
	replacement.owner = scene
	scene.move_child(replacement, original_index)
	root.add_child(scene)
	current_scene = scene
	for i in 30:
		await physics_frame
	var vehicle = scene.get_node("FordEscortRS2000")
	vehicle.freeze = true
	vehicle.set_physics_process(false)
	var cockpit = vehicle.get_node("CockpitAnimation")
	cockpit.set_process(false)
	cockpit.update_steering_pose(0.0)
	scene.head_up_display.visible = false
	var rig = scene.get_node("RallyCameraRig")
	rig.set_process(false)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.global_position = vehicle.to_global(Vector3(3.5, 2.2, -4.8))
	camera.look_at(vehicle.to_global(Vector3(0, .65, 0)))
	camera.fov = 55
	camera.current = true
	await capture("user://escort_replacement_exterior.png")
	camera.global_position = vehicle.to_global(Vector3(2.2, 1.6, -0.6))
	camera.look_at(vehicle.to_global(Vector3(0, .85, .05)))
	camera.fov = 55
	await capture("user://escort_replacement_occupants.png")
	var body = vehicle.get_node("Chassis/Body").find_child("chassis", true, false)
	if body != null:
		body.visible = false
	camera.global_position = vehicle.to_global(Vector3(0, 2.5, -1.2))
	camera.look_at(vehicle.to_global(Vector3(0, .65, .0)))
	await capture("user://escort_replacement_seats.png")
	print("REPLACEMENT_VISUAL_PROBE PASS ", ProjectSettings.globalize_path("user://"))
	var recorder := scene.get_node_or_null("RallyTelemetryRecorder")
	if recorder != null:
		recorder.queue_free()
		await process_frame
	quit()
