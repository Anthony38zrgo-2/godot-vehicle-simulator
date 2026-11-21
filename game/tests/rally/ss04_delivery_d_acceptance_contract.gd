extends SceneTree

const Controller = preload("res://scripts/rally/rally_weather_controller.gd")
const SectorStream = preload("res://scripts/rally/rally_visual_sector_stream.gd")
const TireModel = preload("res://scripts/physics/tire_model.gd")

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("DELIVERY_D_FAIL: " + label)


func _initialize() -> void:
	call_deferred("run")


func _capture_point_screenshot(session: RallyRussiaStageSession, progress_m: float, out_path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if session.garage_panel != null and session.garage_panel.visible:
		session.garage_panel.close_garage(true)
	session.get_tree().paused = false
	var route := session.course.points
	var dists := session.course.route_distances
	var best_i := 0
	var best_d := INF
	for i in route.size():
		var d := absf(float(dists[i]) - progress_m)
		if d < best_d:
			best_d = d
			best_i = i
	var pt := route[best_i]
	var next_pt := route[mini(best_i + 1, route.size() - 1)]
	var fwd := (next_pt - pt)
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()
	session.vehicle.freeze = true
	session.vehicle.global_position = pt + Vector3.UP * 0.45
	session.vehicle.look_at(pt + fwd * 10.0 + Vector3.UP * 0.45, Vector3.UP)
	session.camera_rig.snap_to_target()
	session._refresh_stage_weather()
	for _f in 45:
		await physics_frame
		await process_frame
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png(out_path)
		print("DELIVERY_D_SCREENSHOT path=", out_path)


func _test_controlled_scenarios_and_determinism() -> void:
	# 1. Reproducible mixed ascent scenario (start melt/cloudy -> mid rain bare -> abra snow).
	var ctl := Controller.new()
	check(ctl.configure_procedural(
		"cdi_stage4", "res://data/rally/cdi_stage4_route.json",
		777, "transition", 9.6667, "asphalt", "controlled_mixed_ascent"
	), "controlled_mixed_ascent configured")
	var total := ctl.route_total_m
	var low := ctl.local_surface_state_at_distance(total * 0.03, 0.0)
	var mid := ctl.local_surface_state_at_distance(total * 0.48, 0.0)
	var abra := ctl.local_surface_state_at_distance(total * 0.90, 0.0)
	print("DELIVERY_D_MIXED_ASCENT low=(cloud=%.2f,ground=%.2f,snow=%.2f,water=%.2f,rain=%.2f) mid=(rain=%.2f,snow=%.2f,snow_cov=%.2f,water=%.2f) abra=(snow_h=%.2f,snow=%.2f,snow_cov=%.2f)" % [
		float(low.get("climate", {}).get("cumulus_coverage", 0.0)),
		float(low.get("ground_c", 0.0)), float(low.get("snow_mm", 0.0)), float(low.get("water_mm", 0.0)), float(low.get("rain_mm_h", 0.0)),
		float(mid.get("rain_mm_h", 0.0)), float(mid.get("snow_mm", 0.0)), float(mid.get("snow_coverage", 0.0)), float(mid.get("water_mm", 0.0)),
		float(abra.get("snow_mm_h", 0.0)), float(abra.get("snow_mm", 0.0)), float(abra.get("snow_coverage", 0.0)),
	])
	check(float(low.get("climate", {}).get("cumulus_coverage", 0.0)) >= 0.65 and float(low.get("snow_mm", 0.0)) > 0.25 and float(low.get("ground_c", 0.0)) > 0.15 and float(low.get("water_mm", 0.0)) > 0.05,
		"Mixed ascent start: cloudy with melting residual snow")
	check(float(mid.get("rain_mm_h", 0.0)) > 0.5 and float(mid.get("snow_mm", 0.0)) <= 0.01 and float(mid.get("snow_coverage", 0.0)) <= 0.001,
		"Mixed ascent mid: active rain on snow-free asphalt")
	check(float(abra.get("snow_mm_h", 0.0)) > 0.5 and float(abra.get("snow_mm", 0.0)) > 0.5 and float(abra.get("snow_coverage", 0.0)) > 0.15,
		"Mixed ascent Abra: active snowfall with covered road")

	# 2. Controlled refreeze scenario (liquid meltwater freezes into ice).
	var ctl_ice := Controller.new()
	check(ctl_ice.configure_procedural(
		"cdi_stage4", "res://data/rally/cdi_stage4_route.json",
		888, "transition", 9.6667, "asphalt", "controlled_refreeze"
	), "controlled_refreeze configured")
	var pre_freeze := ctl_ice.local_surface_state_at_distance(total * 0.85, 0.0)
	ctl_ice.advance_ambient(1800.0, 0.6)
	var post_freeze := ctl_ice.local_surface_state_at_distance(total * 0.85, 0.0)
	print("DELIVERY_D_REFREEZE before=(water=%.2f,ice=%.2f,ground=%.2f) after=(water=%.2f,ice=%.2f,ice_cov=%.2f,ground=%.2f)" % [
		float(pre_freeze.get("water_mm", 0.0)), float(pre_freeze.get("ice_mm", 0.0)), float(pre_freeze.get("ground_c", 0.0)),
		float(post_freeze.get("water_mm", 0.0)), float(post_freeze.get("ice_mm", 0.0)), float(post_freeze.get("ice_coverage", 0.0)), float(post_freeze.get("ground_c", 0.0)),
	])
	check(float(pre_freeze.get("water_mm", 0.0)) > 0.25 and float(post_freeze.get("ice_mm", 0.0)) > 0.1 and float(post_freeze.get("ice_coverage", 0.0)) > 0.05,
		"Controlled refreeze produces ice from liquid water")

	# 3. Geography + Seed determinism + Seed variation.
	var route_prof: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/rally/cdi_stage4/climate_route_profile.json"))
	var samples: Array = route_prof.get("samples", [])
	check(samples.size() >= 200, "Route profile samples loaded")
	var s0_alt := float((samples[0] as Dictionary).get("altitude_m", 0.0))
	var s_last_alt := float((samples[-1] as Dictionary).get("altitude_m", 0.0))
	check(absf(float(low.get("altitude_m", 0.0)) - s0_alt) < 35.0, "Start altitude matches profile")
	check(absf(float(abra.get("altitude_m", 0.0)) - s_last_alt) < 40.0, "Abra altitude matches profile")

	var ctl_a := Controller.new()
	var ctl_b := Controller.new()
	var ctl_c := Controller.new()
	check(ctl_a.configure_procedural("cdi_stage4", "res://data/rally/cdi_stage4_route.json", 4242, "2026-11-15", 9.6667, "asphalt", "auto"), "auto seed A")
	check(ctl_b.configure_procedural("cdi_stage4", "res://data/rally/cdi_stage4_route.json", 4242, "2026-11-15", 9.6667, "asphalt", "auto"), "auto seed B")
	check(ctl_c.configure_procedural("cdi_stage4", "res://data/rally/cdi_stage4_route.json", 5151, "2026-11-15", 9.6667, "asphalt", "wet_front"), "seed C")
	var st_a := ctl_a.local_surface_state_at_distance(3500.0, 0.0)
	var st_b := ctl_b.local_surface_state_at_distance(3500.0, 0.0)
	var st_c := ctl_c.local_surface_state_at_distance(3500.0, 0.0)
	check(absf(float(st_a["air_c"]) - float(st_b["air_c"])) < 1e-4 and absf(float(st_a["water_mm"]) - float(st_b["water_mm"])) < 1e-4,
		"Same seed+date+hour deterministic")
	check(absf(float(st_a["air_c"]) - float(st_c["air_c"])) > 0.01 or absf(float(st_a["water_mm"]) - float(st_c["water_mm"])) > 0.01,
		"Seed variation produces distinct weather")

	# 4. Differential left vs right wheel contact across partial snow patches.
	var tire_loader := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	var tire := TireModel.new()
	tire.configure(tire_loader.domains, tire_loader.resolved_tire_filters, [3500.0, 3500.0, 3500.0, 3500.0])
	tire.set_compound("asphalt_dry")
	# Find a station along mixed ascent start where left vs right lateral_t differ visibly.
	var found_diff := false
	for p_m in [100.0, 220.0, 340.0, 480.0, 620.0]:
		var ql := ctl.local_surface_state_at_distance(p_m, -0.85)
		var qr := ctl.local_surface_state_at_distance(p_m, 0.42)
		if absf(float(ql["snow_coverage"]) - float(qr["snow_coverage"])) > 0.02:
			found_diff = true
			var rl := tire.evaluate(0, 3500.0, "Road", 20.0, 2.5, 64.5, 0.31, 0.0, 1.0, 200.0, 0.01, 60.0,
				float(ql["water_mm"]), float(ql["snow_mm"]), float(ql["ground_c"]), "", float(ql["ice_mm"]), float(ql["snow_coverage"]), float(ql["ice_coverage"]))
			var rr := tire.evaluate(1, 3500.0, "Road", 20.0, 2.5, 64.5, 0.31, 0.0, 1.0, 200.0, 0.01, 60.0,
				float(qr["water_mm"]), float(qr["snow_mm"]), float(qr["ground_c"]), "", float(qr["ice_mm"]), float(qr["snow_coverage"]), float(qr["ice_coverage"]))
			check(absf(float(rl["lateral_force_n"]) - float(rr["lateral_force_n"])) > 1.0,
				"Split left/right wheel snow coverage produces asymmetric cornering force")
			break
	check(found_diff, "Carriageway lateral snow contrast exists for split-mu test")


func _test_ss01_gravel_default_integration() -> void:
	var packed := load("res://scenes/rally/cdi_stage1.tscn") as PackedScene
	check(packed != null, "cdi_stage1 scene loads")
	if packed == null:
		return
	var session := packed.instantiate() as RallyRussiaStageSession
	session.track_id = "cdi_stage1"
	session.session_mode = "single_stage"
	session.practice_mode = false
	session.event_seed = 4242
	root.add_child(session)
	var frames := 0
	while not session.session_ready and frames < 240:
		await physics_frame
		frames += 1
	check(session.session_ready, "SS01 gravel session ready by default")
	check(session.event_weather.procedural_active, "SS01 procedural_active by default")
	var tel := session.event_weather.procedural_telemetry(1000.0)
	check(str(tel.get("surface_type", "")) == "gravel", "SS01 uses gravel surface balance profile (got %s)" % str(tel.get("surface_type", "")))
	var stream := session.track_visual.get_node_or_null("VisualSectorStream") as SectorStream
	check(stream != null and stream.is_procedural_surface_enabled(), "SS01 SectorStream in procedural mode")
	var gravel_mat: ShaderMaterial = stream._terrain_materials.get(2) if stream != null else null
	check(gravel_mat != null and bool(gravel_mat.get_shader_parameter("procedural_surface_enabled")),
		"SS01 gravel road shader enabled with shared procedural surface uniforms")
	check(gravel_mat != null and gravel_mat.get_shader_parameter("surface_field_tex") != null,
		"SS01 gravel road shader has surface_field_tex")
	var gravel_bodies := get_nodes_in_group("Gravel")
	check(not gravel_bodies.is_empty(), "SS01 retains Gravel physical collision")
	session.queue_free()
	await process_frame
	await process_frame


func _test_ss04_default_and_perf(capture_dir: String = "") -> void:
	var timings_ms := {}
	for mode_label in ["procedural", "legacy"]:
		var packed := load("res://scenes/rally/cdi_stage4.tscn") as PackedScene
		var session := packed.instantiate() as RallyRussiaStageSession
		session.track_id = "cdi_stage4"
		session.session_mode = "single_stage"
		session.practice_mode = false
		session.event_seed = 777
		if mode_label == "legacy":
			session.procedural_climate_override = 0
		else:
			# Use default JSON config (enabled = true)! Optionally override regime for captures.
			if not capture_dir.is_empty():
				session.procedural_regime_override = "controlled_mixed_ascent"
		root.add_child(session)
		var frames := 0
		while not session.session_ready and frames < 240:
			await physics_frame
			frames += 1
		check(session.session_ready, "SS04 %s session ready" % mode_label)
		if mode_label == "procedural":
			check(session.event_weather.procedural_active, "SS04 procedural active by DEFAULT in cdi_stage4.json")
			check(session.track_collision.procedural_ss04_asphalt_mode, "SS04 collision uses asphalt Road by DEFAULT")
			var stream := session.track_visual.get_node_or_null("VisualSectorStream") as SectorStream
			check(stream != null and stream.is_procedural_surface_enabled(), "SS04 visual stream procedural by DEFAULT")
			if not capture_dir.is_empty():
				var total := session.course.route_distances[-1]
				await _capture_point_screenshot(session, total * 0.03, capture_dir.path_join("ss04_01_start_melt.png"))
				await _capture_point_screenshot(session, total * 0.48, capture_dir.path_join("ss04_02_mid_rain_bare.png"))
				await _capture_point_screenshot(session, total * 0.90, capture_dir.path_join("ss04_03_abra_snow.png"))
		session.vehicle.freeze = false
		var samples_us: Array[float] = []
		for _i in 120:
			var t0 := Time.get_ticks_usec()
			await physics_frame
			var dt_us := float(Time.get_ticks_usec() - t0)
			samples_us.append(dt_us)
		var sum_us := 0.0
		var max_us := 0.0
		for v in samples_us:
			sum_us += v
			max_us = maxf(max_us, v)
		timings_ms[mode_label] = {
			"mean_ms": (sum_us / maxf(samples_us.size(), 1)) / 1000.0,
			"max_ms": max_us / 1000.0,
		}
		session.queue_free()
		await process_frame
		await process_frame
	print("DELIVERY_D_PERF procedural=%s legacy=%s" % [str(timings_ms["procedural"]), str(timings_ms["legacy"])])


func run() -> void:
	var capture_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
	_test_controlled_scenarios_and_determinism()
	await _test_ss01_gravel_default_integration()
	await _test_ss04_default_and_perf(capture_dir)
	print("SS04_DELIVERY_D_CONTRACT ", "PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
