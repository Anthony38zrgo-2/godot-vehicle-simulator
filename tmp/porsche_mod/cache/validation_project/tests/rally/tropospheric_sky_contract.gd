extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn").instantiate()
	scene.practice_mode = true
	scene.dreamcast_visual_mode = "--normal" not in OS.get_cmdline_user_args()
	scene.weather_enabled = "--no-tca" not in OS.get_cmdline_user_args()
	root.add_child(scene)
	current_scene = scene
	for i in 600:
		await process_frame
		if scene.session_ready:
			break
	assert(scene.session_ready)
	var sky = scene.weather_sky_node
	assert(sky.name == "RallyTroposphericSky")
	assert(scene.get_node_or_null("Sky3D") == null)
	assert(scene.get_node_or_null("RallyHybridSky") == null)
	assert(sky.material.shader.resource_path.ends_with("rally_tropospheric_sky.gdshader"))
	assert(not sky.environment.volumetric_fog_enabled)
	assert(sky.environment.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED)
	assert(sky.material.get_shader_parameter("sky_a") is CompressedCubemap)
	assert(sky.material.get_shader_parameter("sky_a").get_width() == 512)

	scene.vehicle.freeze = true
	scene.set_physics_process(false)
	scene.event_clock.jump_to("2026-06-13", 12.0 * 3600.0, "test")
	assert(sky.current_time == 12.0)
	sky.apply_climate({"cumulus_coverage": 0.15}, {})
	sky.update_visuals(0.0)
	assert(sky.sun.shadow_enabled)
	var clear_fog_end: float = sky.environment.fog_depth_end
	sky.apply_climate({"cumulus_coverage": 0.15, "precipitation_mm_h": 12.0, "fog_density": 0.004}, {})
	sky.update_visuals(0.0)
	assert(not sky.sun.shadow_enabled)
	assert(sky.environment.fog_depth_end < clear_fog_end)
	assert(sky.material.get_shader_parameter("sky_b").resource_path.ends_with("/verycloudy_4.png"))

	scene.event_clock.jump_to("2026-06-13", 86401.0, "test midnight")
	sky.update_visuals(0.0)
	assert(scene.event_clock.event_date == "2026-06-14")
	assert(is_zero_approx(sky.sun.light_energy))
	assert(sky.moon.light_energy > 0.0)
	assert(sky.material.get_shader_parameter("sky_a").resource_path.ends_with("/night_2.png"))
	var elapsed: float = sky._elapsed
	paused = true
	for i in 10:
		await process_frame
	assert(sky._elapsed == elapsed)
	paused = false

	if "--tropospheric-capture" in OS.get_cmdline_user_args():
		sky.set_process(false)
		var camera := Camera3D.new()
		scene.add_child(camera)
		camera.global_position = scene.vehicle.global_position + Vector3(0, 3.0, 7.0)
		camera.look_at(scene.vehicle.global_position + Vector3(0, 5.2, -12.0))
		camera.current = true
		var cases := [
			{"name": "clear", "cover": 0.15, "hour": 12.0},
			{"name": "cloudy_transition", "cover": 0.42, "hour": 12.0},
			{"name": "storm", "cover": 0.95, "hour": 12.0},
			{"name": "dawn", "cover": 0.2, "hour": 6.1},
			{"name": "sunset", "cover": 0.35, "hour": 17.8},
			{"name": "twilight_transition", "cover": 0.35, "hour": 18.55},
			{"name": "night", "cover": 0.2, "hour": 0.0},
		]
		var mode := "retro" if scene.dreamcast_visual_mode else "normal"
		await capture_cases(sky, cases, mode)
		scene.camera_rig.toggle_camera_mode()
		scene.camera_rig.toggle_camera_mode()
		assert(scene.camera_rig.get_camera_mode_label() == "COCKPIT")
		scene.camera_rig.camera.make_current()
		await capture_cases(sky, cases, mode + "_cockpit")
	scene.queue_free()
	await process_frame
	print("TROPOSPHERIC_SKY_CONTRACT PASS")
	quit()

func capture_cases(sky: Node, cases: Array, mode: String) -> void:
	for item in cases:
		sky.current_time = item.hour
		sky.apply_climate({"cumulus_coverage": item.cover, "fog_density": 0.004 if item.cover > 0.9 else 0.0004}, {})
		sky.update_visuals(0.0)
		for i in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		var filename := "tropospheric_%s_%s.png" % [mode, item.name]
		var result := root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join(filename))
		assert(result == OK)
