extends SceneTree


func _initialize() -> void:
	call_deferred("verify")


func verify() -> void:
	var scene = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 240:
		await physics_frame
	var vehicle = scene.get_node("FordEscortRS2000")
	var vfx = vehicle.get_node("VehicleVFX")
	vfx.set_physics_process(false)
	assert(vfx.wheel_plumes.size() == 4 and vfx.impact_pool.size() == 6)
	var sim = vehicle.simulation
	var index := -1
	for i in [2, 3]:
		if sim.wheel_loads[i] > 60.0 and sim.wheel_contact_casts[i].is_colliding():
			index = i
			break
	assert(index >= 0, "Real Jolt wheel casts must reach the proving ground")
	vehicle.freeze = true
	for front in [0, 1]:
		vfx.update_wheel(front, 0.0)
		assert(not vfx.wheel_cores[front].emitting)
		assert(not vfx.wheel_plumes[front].emitting)
		assert(not vfx.wheel_chips[front].emitting)
	vehicle.linear_velocity = Vector3(0, 0, -15)
	sim.wheel_slips[index] = Vector2(0.3, 0.15)
	for surface in ["Gravel", "Dirt", "Sand", "Grass"]:
		sim.wheel_surfaces[index] = surface
		vfx.update_wheel(index, 0.0)
		assert(vfx.wheel_plumes[index].emitting)
		assert(vfx.wheel_chips[index].emitting)
	sim.wheel_surfaces[index] = "Gravel"
	vfx.update_wheel(index, 0.0)
	var dry: float = vfx.wheel_plumes[index].amount_ratio
	vfx.update_wheel(index, 1.0)
	assert(vfx.wheel_plumes[index].amount_ratio < dry * 0.2)
	sim.wheel_surfaces[index] = "Road"
	sim.wheel_slips[index] = Vector2.ZERO
	vfx.update_wheel(index, 0.0)
	assert(not vfx.wheel_plumes[index].emitting and not vfx.wheel_chips[index].emitting)
	sim.wheel_slips[index] = Vector2(0.5, 0.2)
	vfx.update_wheel(index, 0.0)
	assert(vfx.wheel_plumes[index].emitting)
	sim.wheel_loads[index] = 0.0
	vfx.update_wheel(index, 0.0)
	assert(not vfx.wheel_plumes[index].emitting and not vfx.wheel_chips[index].emitting)
	vehicle.body_contact_vfx.clear()
	vehicle.body_contact_vfx.append({"position": Vector3.ZERO, "normal": Vector3.UP, "impulse_ns": 0.0, "speed_ms": 0.0, "tangent_ms": 0.0, "surface": "Gravel", "collider_name": "collision_road"})
	vfx.update_impacts(0.0)
	assert(vfx.emitted_impacts == 0)
	vehicle.body_contact_vfx[0].impulse_ns = vehicle.mass
	vehicle.body_contact_vfx[0].speed_ms = 4.0
	vfx.update_impacts(0.0)
	assert(vfx.emitted_impacts == 1)
	vfx.update_impacts(0.0)
	assert(vfx.emitted_impacts == 1, "Sustained contacts must respect the cooldown")
	for i in 20:
		vfx.emit_impact(Vector3.ZERO, Vector3.UP, Color.WHITE, 0.5, true)
	assert(vfx.emitted_impacts == 6, "The pool must cap overlapping impact effects")
	vfx.reset_effects()
	assert(not vfx.wheel_plumes[index].emitting)
	print("RALLY_VFX_CONTRACT_OK real_contacts surfaces wetness skid airborne impact_cooldown pool_reset")
	scene.queue_free()
	await process_frame
	quit()
