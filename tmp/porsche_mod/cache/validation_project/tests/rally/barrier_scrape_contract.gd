extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var scene: Node = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.0).timeout
	var vehicle = scene.get_node("FordEscortRS2000")
	var audio = vehicle.get_node("VehicleAudio")
	var wall := StaticBody3D.new()
	wall.set_meta("collision_role", "barrier")
	wall.collision_layer = 1
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 2.0, 50.0)
	collider.shape = shape
	wall.add_child(collider)
	scene.add_child(wall)
	wall.global_position = vehicle.global_position + Vector3(1.1, 1.0, -15.0)
	vehicle.linear_velocity = Vector3(5.0, 0.0, -10.0)
	var maximum_power := 0.0
	var maximum_gain := 0.0
	for frame in 240:
		await physics_frame
		maximum_power = maxf(maximum_power, float(vehicle.body_contact_audio.get("scrape_power_w", 0.0)))
		maximum_gain = maxf(maximum_gain, audio.scrape_player.volume_linear)
	var passed: bool = maximum_power > 0.0 and maximum_gain > 0.001 and vehicle.simulation.contact_query_count == 4
	print("BARRIER_SCRAPE_CONTRACT ", JSON.stringify({"passed": passed, "maximum_scrape_power_w": maximum_power, "maximum_voice_gain": maximum_gain}))
	quit(0 if passed else 1)
