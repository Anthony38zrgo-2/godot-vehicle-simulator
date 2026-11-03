extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn").instantiate()
	scene.practice_mode = true
	root.add_child(scene)
	current_scene = scene
	for i in 600:
		await process_frame
		if scene.session_ready:
			break
	assert(scene.session_ready)
	var sky = scene.weather_sky_node
	assert(sky.name == "RallyHybridSky")
	assert(scene.get_node_or_null("Sky3D") == null)
	assert(sky.material.shader.resource_path == "res://scripts/rally/rally_hybrid_sky.gdshader")
	assert(not sky.environment.volumetric_fog_enabled)
	assert(sky.environment.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED)
	assert(sky.material.get_shader_parameter("clear_panorama") != null)
	assert(sky.material.get_shader_parameter("cloud_density") != null)
	var offset: Vector2 = sky.cloud_offset
	sky.apply_climate({"cumulus_coverage": 0.95, "wind_m_s": 8.0, "wind_direction_deg": 90.0, "fog_density": 0.004}, {})
	sky.current_time = 12.0
	sky.update_visuals(10.0)
	assert(sky.cloud_offset.distance_to(offset) > 0.0)
	assert(not sky.sun.shadow_enabled)
	assert(sky.material.get_shader_parameter("coverage") > 0.9)
	sky.current_time = 0.0
	sky.update_visuals(0.0)
	assert(is_zero_approx(sky.sun.light_energy))
	assert(sky.moon.light_energy > 0.0)
	sky.current_time = 12.0
	sky.apply_climate({"cumulus_coverage": 0.15}, {})
	sky.update_visuals(0.0)
	assert(sky.sun.shadow_enabled)
	var captures := "--hybrid-sky-capture" in OS.get_cmdline_user_args()
	if captures:
		scene.vehicle.freeze = true
		scene.set_physics_process(false)
		sky.set_process(false)
		var camera := Camera3D.new()
		scene.add_child(camera)
		camera.global_position = scene.vehicle.global_position + Vector3(0, 3.0, 7.0)
		camera.look_at(scene.vehicle.global_position + Vector3(0, 3.2, -12.0))
		camera.current = true
		for item in [{"name": "clear", "cover": 0.15, "hour": 12.0}, {"name": "storm", "cover": 0.95, "hour": 12.0}, {"name": "sunset", "cover": 0.35, "hour": 17.8}, {"name": "night", "cover": 0.2, "hour": 0.0}]:
			sky.current_time = item.hour
			sky.apply_climate({"cumulus_coverage": item.cover, "fog_density": 0.004 if item.cover > 0.9 else 0.0004}, {})
			sky.update_visuals(0.0)
			for i in 10:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("hybrid_sky_" + item.name + ".png"))
	var paused_offset: Vector2 = sky.cloud_offset
	paused = true
	for i in 10:
		await process_frame
	assert(sky.cloud_offset == paused_offset)
	paused = false
	scene.queue_free()
	await process_frame
	print("HYBRID_SKY_CONTRACT PASS")
	quit()
