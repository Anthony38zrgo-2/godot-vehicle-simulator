extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func capture(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(path) == OK)
func run() -> void:
	var scene = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 20:
		await physics_frame
	var vehicle = scene.get_node("FordEscortRS2000")
	vehicle.freeze = true
	vehicle.set_physics_process(false)
	vehicle.get_node("CockpitAnimation").set_process(false)
	scene.get_node("RallyCameraRig").set_process(false)
	scene.head_up_display.visible = false
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.near = .035
	camera.fov = 75
	camera.global_position = vehicle.to_global(Vector3(0, 1.035, -.04))
	camera.look_at(vehicle.to_global(Vector3(0, .85, 1.3)))
	var cleaned: Node = vehicle.get_node("Chassis")
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file("D:/open-formula/staging_rally/cars/ra-escort-rs2000/rear_cleanup_before/ford_escort_rs2000_1971_chassis.glb", state) == OK)
	var old: Node = document.generate_scene(state)
	old.name = "Chassis"
	vehicle.remove_child(cleaned)
	vehicle.add_child(old)
	vehicle._set_vehicle_layers(old)
	await capture("user://rs2000_rear_before.png")
	vehicle.remove_child(old)
	old.free()
	vehicle.add_child(cleaned)
	await capture("user://rs2000_rear_after.png")
	var tub = cleaned.find_child("interior_rear_roll_cage", true, false)
	tub.visible = false
	await capture("user://rs2000_rear_hi_only.png")
	tub.visible = true
	camera.global_position = vehicle.to_global(Vector3(2.6, 1.9, 3.3))
	camera.look_at(vehicle.to_global(Vector3(0, .65, .25)))
	camera.fov = 50
	await capture("user://rs2000_rear_exterior_after.png")
	print("RS2000_REAR_VISUAL_PROBE PASS ", ProjectSettings.globalize_path("user://"))
	quit()
