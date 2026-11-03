extends SceneTree

class TestManager:
	extends "res://scripts/rally/rally_event_manager.gd"
	func save() -> bool:
		return true

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var manager := TestManager.new()
	assert(manager.begin_event({"seed": 42, "setup_accepted": true}))
	var scene = load("res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn").instantiate()
	scene.begin_event_session(manager, "russia_stage1")
	root.add_child(scene)
	current_scene = scene
	for i in 600:
		await process_frame
		if scene.session_ready:
			break
	assert(scene.session_ready)
	scene.set_physics_process(false)
	scene.input_controller.set_controls_enabled(false)
	scene.vehicle.freeze = true
	scene.camera_rig.set_process(false)
	scene.camera_rig.set_physics_process(false)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.global_position = scene.start_position + Vector3(0, 3.0, 5)
	camera.look_at(scene.start_position + Vector3(0, 5, -35), Vector3.UP)
	camera.fov = 75
	camera.current = true
	scene.head_up_display.visible = false
	scene.event_clock.jump_to("2026-06-13", 12.0 * 3600.0, "visual_probe")
	var ctl = scene.event_weather
	var folder := OS.get_environment("TEMP").path_join("rally_weather_visual")
	DirAccess.make_dir_recursive_absolute(folder)
	for state in ["clear", "sunny", "cloudy", "cloudy_wet", "light_precipitation", "medium_precipitation", "heavy_precipitation", "snow"]:
		var preset: Dictionary = ctl.catalog.presets["cloudy" if state == "cloudy_wet" else ("heavy_precipitation" if state == "snow" else state)]
		var climate := {}
		for key in ["cumulus_coverage", "cirrus_coverage", "irradiance_w_m2", "air_temperature_c", "precipitation_mm_h", "fog_density", "wind_m_s"]:
			var values: Array = preset[key]
			climate[key] = (float(values[0]) + float(values[1])) * 0.5
		for zone in ctl.surface.zones:
			zone.climate = climate.duplicate(true)
			zone.precipitation_kind = "snow" if state == "snow" else ("rain" if "precipitation" in state else "none")
			zone.water_mm = 4.0 if state in ["heavy_precipitation", "cloudy_wet"] else 0.0
		ctl.update_vehicle_position(scene.vehicle.global_position)
		ctl.tick_visual(3.0)
		ctl.apply_to_adapters(scene.weather_sky_node, scene.weather_controller_node, scene.terrain_wetness, 12.0)
		for frame in 100:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(state + ".png"))
		print("WEATHER_VISUAL_CAPTURE ", folder.path_join(state + ".png"))
		print("WETNESS ", scene.terrain_wetness.zone_wetness, " materials=", scene.terrain_wetness._materials.size())
		assert(scene.terrain_wetness != null, "wet visuals must be present in retro mode")
		assert(not scene.weather_sky_node.environment.volumetric_fog_enabled, "no second fog pass")
		if state == "cloudy_wet":
			assert(scene.terrain_wetness._materials[0].albedo_color.r < 0.8, "wet surface darkens")
	scene.queue_free()
	await process_frame
	quit()
