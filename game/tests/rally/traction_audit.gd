extends SceneTree

func _initialize() -> void:
	call_deferred("audit")

func audit() -> void:
	var results: Array = []
	var russia := "--russia" in OS.get_cmdline_user_args()
	for pedal in [0.35, 0.65, 1.0]:
		var scene: Node = load("res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn" if russia else "res://scenes/rally/rally_proving_ground.tscn").instantiate()
		root.add_child(scene)
		current_scene = scene
		await create_timer(1.0).timeout
		var vehicle = scene.get_node("FordEscortRS2000")
		vehicle.shift(1)
		var samples: Array = []
		for frame in 360:
			Input.action_press(InputBindings.THROTTLE, pedal)
			await physics_frame
			if frame % 12 != 0:
				continue
			var wheels: Array = []
			var sim = vehicle.simulation
			var drive: Array = sim.powertrain_model.drive_torques(vehicle.throttle_amount, vehicle.clutch_amount, Vector2(sim.wheel_spins[2], sim.wheel_spins[3]), sim.thermal_model.engine_torque_factor())
			for index in 4:
				var tire: Dictionary = sim.tire_model.state_for(index)
				wheels.append({"fz": sim.wheel_loads[index], "fx": tire.get("longitudinal_force"), "slip": sim.wheel_slips[index].x, "rim_m_s": sim.wheel_spins[index] * sim.wheel_radii[index], "drive_nm": drive[index], "reaction_nm": float(tire.get("longitudinal_force", 0.0)) * sim.wheel_radii[index], "thermal_grip": sim.thermal_model.tire_grip_factor(index)})
			samples.append({"time": frame / 120.0, "speed_m_s": vehicle.linear_velocity.dot(-vehicle.global_basis.z), "rpm": vehicle.motor_rpm, "wheels": wheels, "body_contacts": vehicle.body_contact_audio.duplicate(), "queries": sim.contact_query_count})
		Input.action_release(InputBindings.THROTTLE)
		results.append({"throttle": pedal, "samples": samples})
		scene.queue_free()
		await process_frame
	var path := "res://logs/rally/traction_russia.json" if russia else "res://logs/rally/traction_flat.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "  "))
	file.close()
	print("TRACTION_AUDIT ", path)
	quit()
