extends SceneTree

const SPARK := RallyVehicleVFX.SPARK
const MUD := RallyVehicleVFX.MUD_CLOD
const LEAF := RallyVehicleVFX.LEAVES[0]

var folder := ""
var scene: Node3D
var vehicle: RigidBody3D
var vfx: Node3D
var sim
var camera: Camera3D


func _initialize() -> void:
	call_deferred("run")


func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := folder.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("VFX_VISUAL_CAPTURE ", path)


func set_chase_camera() -> void:
	camera.global_position = vehicle.global_transform * Vector3(3.2, 1.35, 4.2)
	camera.look_at(vehicle.global_transform * Vector3(0.0, 0.65, 0.2), Vector3.UP)


func set_close_camera(point: Vector3) -> void:
	camera.global_position = point + Vector3(1.25, 0.85, 1.25)
	camera.look_at(point + Vector3(0.0, 0.22, 0.0), Vector3.UP)


func set_side_camera() -> void:
	camera.global_position = vehicle.global_transform * Vector3(3.2, 1.5, 0.9)
	camera.look_at(vehicle.global_transform * Vector3(0.0, 0.85, 0.9), Vector3.UP)


func reset_visuals() -> void:
	vfx.reset_effects()
	for frame in 90:
		await process_frame


func apply_state(surface: String, snow_mm: float) -> void:
	for i in [2, 3]:
		sim.wheel_surfaces[i] = surface
		sim.wheel_loads[i] = maxf(sim.wheel_loads[i], 3000.0)
		sim.wheel_slips[i] = Vector2(0.3, 0.15)
		sim.last_local_conditions[i] = { "snow_mm": snow_mm }
	vehicle.linear_velocity = Vector3(0, 0, -15)


func run_wheel(seconds: float, wetness: float) -> void:
	for frame in int(seconds / vfx.WHEEL_PARTICLES.STEP):
		vfx.advance_wheel_particles(wetness)
		await process_frame


func run() -> void:
	scene = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 240:
		await physics_frame
	vehicle = scene.get_node("FordEscortRS2000")
	vfx = vehicle.get_node("VehicleVFX")
	vfx.set_physics_process(false)
	sim = vehicle.simulation
	var index := -1
	for i in [2, 3]:
		if sim.wheel_loads[i] > 60.0 and sim.wheel_contact_casts[i].is_colliding():
			index = i
			break
	assert(index >= 0, "The proving ground must provide a loaded rear wheel")
	vehicle.freeze = true
	scene.set_physics_process(false)
	var rig = scene.get_node("RallyCameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	scene.get_node("RallyF1HeadUpDisplay").visible = false
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.05
	camera.current = true
	scene.add_child(camera)
	folder = OS.get_environment("TEMP").path_join("rally_vfx_visual")
	DirAccess.make_dir_recursive_absolute(folder)

	for i in [2, 3]:
		sim.wheel_loads[i] = maxf(sim.wheel_loads[i], 3000.0)
		sim.wheel_surfaces[i] = "Gravel"
		sim.wheel_slips[i] = Vector2(0.3, 0.15)
		sim.last_local_conditions[i] = { "snow_mm": 0.0 }
	vehicle.linear_velocity = Vector3(0, 0, -15)
	set_chase_camera()

	apply_state("Gravel", 0.0)
	await run_wheel(1.2, 0.0)
	await capture("dry_gravel_chase")
	set_close_camera(sim.wheel_contact_points[3])
	await run_wheel(0.6, 0.0)
	await capture("dry_gravel_close")

	await reset_visuals()
	apply_state("Gravel", 0.0)
	set_chase_camera()
	await run_wheel(1.2, 1.0)
	await capture("wet_gravel_chase")
	set_close_camera(sim.wheel_contact_points[3])
	await run_wheel(0.6, 1.0)
	await capture("wet_gravel_close")

	await reset_visuals()
	apply_state("Road", 0.0)
	set_chase_camera()
	await run_wheel(1.2, 1.0)
	await capture("wet_road_chase")
	set_close_camera(sim.wheel_contact_points[3])
	await run_wheel(0.6, 1.0)
	await capture("wet_road_close")

	await reset_visuals()
	apply_state("Gravel", 6.0)
	set_chase_camera()
	await run_wheel(1.2, 1.0)
	await capture("snow_chase")
	set_close_camera(sim.wheel_contact_points[3])
	await run_wheel(0.6, 1.0)
	await capture("snow_close")

	await reset_visuals()
	apply_state("Gravel", 0.0)
	set_chase_camera()
	await run_wheel(0.6, 0.0)

	var impact_point: Vector3 = vehicle.global_transform * Vector3(2.3, 0.15, 1.0)
	set_close_camera(impact_point)
	var effects := [
		["impact_spark", { "texture": SPARK, "additive": true, "color": Color(1.0, 0.74, 0.28), "quad_size": Vector2(0.35, 0.9), "unlit": true }],
		["impact_mud", { "texture": MUD, "additive": false, "color": Color(0.34, 0.25, 0.15), "quad_size": Vector2(0.16, 0.28), "unlit": true }],
		["impact_leaf", { "texture": LEAF, "additive": false, "color": Color(0.34, 0.44, 0.17), "quad_size": Vector2(0.22, 0.32), "unlit": false }],
	]
	for entry in effects:
		vfx.impact_busy.fill(0.0)
		vfx.impact_cooldown = 0.0
		vfx.emit_impact_effect(impact_point, Vector3.UP, entry[1], 1.0)
		for frame in 6:
			await process_frame
		await capture(entry[0] + "_close")
		for frame in 30:
			await process_frame

	for i in [2, 3]:
		sim.wheel_surfaces[i] = "Gravel"
		sim.wheel_slips[i] = Vector2(0.3, 0.15)
	vehicle.linear_velocity = Vector3(0, 0, -15)
	set_side_camera()
	await reset_visuals()
	await run_wheel(1.5, 1.0)
	await capture("side_cabin_wet")

	print("VFX_VISUAL_DONE ", folder)
	scene.queue_free()
	await process_frame
	quit()
