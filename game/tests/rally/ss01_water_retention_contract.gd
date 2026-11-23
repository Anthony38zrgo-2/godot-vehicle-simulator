extends SceneTree

const EventManagerScript := preload("res://scripts/rally/rally_event_manager.gd")
const ControllerScript := preload("res://scripts/rally/rally_weather_controller.gd")
const PuddlesScript := preload("res://scripts/rally/rally_puddles.gd")
const StreamScript := preload("res://scripts/rally/rally_visual_sector_stream.gd")
const TireModelScript := preload("res://scripts/physics/tire_model.gd")

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("SS01_RETENTION_FAIL: " + label)


func _initialize() -> void:
	call_deferred("run")


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _decode_shader_red_mm(packet: Dictionary, station_m: float) -> float:
	var width := int(packet.get("width", 0))
	var rgba: PackedByteArray = packet.get("rgba8", PackedByteArray())
	if width < 2 or rgba.size() != width * 4:
		return -1.0
	var st_min := float(packet.get("station_min_m", 0.0))
	var st_max := float(packet.get("station_max_m", 1.0))
	var max_enc := float(packet.get("max_encode_mm", 3.5))
	var span := maxf(st_max - st_min, 1.0)
	var norm_u := clampf((station_m - st_min) / span, 0.0, 1.0)
	var nw := float(width)
	# Match cdi_procedural_surface.gdshaderinc texel-center linear filtering:
	# tex_u = (norm_u * (nw - 1.0) + 0.5) / nw
	var tex_x := norm_u * (nw - 1.0)
	var i0 := clampi(int(floor(tex_x)), 0, width - 1)
	var i1 := clampi(i0 + 1, 0, width - 1)
	var frac := clampf(tex_x - float(i0), 0.0, 1.0)
	var r0 := float(rgba[i0 * 4]) / 255.0
	var r1 := float(rgba[i1 * 4]) / 255.0
	return lerpf(r0, r1, frac) * max_enc


func _test_station_correspondence_and_config() -> void:
	var base_abs := float(EventManagerScript.datetime_to_abs_seconds("2026-11-18", "08:00"))
	var t0 := Time.get_ticks_usec()
	var ctl := ControllerScript.new()
	check(
		ctl.configure_five_sector_snapshot(
			"cdi_stage1",
			"res://data/rally/cdi_stage1_route.json",
			2026,
			"transition",
			base_abs,
			base_abs,
			"gravel",
			"wet_front",
		),
		"SS01 configures five_sector_snapshot: " + ctl.error,
	)
	var prep_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var wr_status := ctl.water_retention_status()
	check(bool(wr_status.get("enabled", false)), "SS01 enables water retention from stage config")
	check(bool(wr_status.get("active", false)), "SS01 water retention active")
	check(bool(wr_status.get("valid", false)), "SS01 water retention profile valid")
	check(int(wr_status.get("sample_count", 0)) == 204, "SS01 profile built over 204 climate samples")
	# Also inspect SS01 sector water_mm under wet_front at 13:00 (afternoon liquid rain) across seeds.
	var noon_abs := float(EventManagerScript.datetime_to_abs_seconds("2026-11-18", "13:00"))
	for seed_v in [2026, 4242, 777, 1974]:
		var wc := ControllerScript.new()
		wc.configure_five_sector_snapshot("cdi_stage1", "res://data/rally/cdi_stage1_route.json", seed_v, "transition", noon_abs, noon_abs, "gravel", "wet_front")
		var secs: Array = wc.sector_summary()
		var ws: Array[String] = []
		for sr: Dictionary in secs:
			ws.append("%.2f(r=%.1f,s=%.1f)" % [float(sr.get("water_mm", 0.0)), float(sr.get("rain_mm_h", 0.0)), float(sr.get("snow_mm_h", 0.0))])
		print("SS01_WET_FRONT_13H seed=%d sectors=%s" % [seed_v, ", ".join(ws)])

	# SS04 keeps retention disabled by default.
	var ctl_ss04 := ControllerScript.new()
	check(
		ctl_ss04.configure_five_sector_snapshot(
			"cdi_stage4",
			"res://data/rally/cdi_stage4_route.json",
			2026,
			"transition",
			base_abs,
			base_abs,
			"asphalt",
			"wet_front",
		),
		"SS04 configures five_sector_snapshot",
	)
	check(not bool(ctl_ss04.water_retention_status().get("active", true)), "SS04 keeps water retention disabled by default")

	# Station correspondence: start (~61.47m), finish (~5076.49m), hairpins, monotonicity.
	var eng: RefCounted = ctl.procedural_atmosphere
	var st_start := ctl.progress_to_shader_station(0.0)
	var st_end := ctl.progress_to_shader_station(ctl.route_total_m)
	check(absf(st_start - 61.4747) < 0.05, "SS01 start shader_station ~61.47m (got %.3f)" % st_start)
	check(absf(st_end - 5076.4864) < 0.25, "SS01 end shader_station ~5076.49m (got %.3f)" % st_end)
	var prev_st := -1.0
	for p in [0.0, 864.5, 1692.0, 2360.2, 2539.6, 2645.9, 2796.1, 3462.5, 4448.2, ctl.route_total_m]:
		var st := ctl.progress_to_shader_station(p)
		check(st > prev_st, "Monotonic shader_station at p=%.1f (%.2f > %.2f)" % [p, st, prev_st])
		prev_st = st
		var rt_p := float(eng.call("shader_station_to_progress", st))
		check(absf(rt_p - p) < 0.1, "Inverse mapping round-trip at p=%.1f (got %.3f)" % [p, rt_p])

	# Event calendar integration with effective time != base time.
	var mgr := EventManagerScript.new()
	check(mgr.begin_event({"event_id": "cdi_rally", "seed": 2026, "preview": true}), "CDI event begins")
	var sched := mgr.schedule_for("cdi_stage1")
	var ev_ctl := ControllerScript.new()
	check(
		ev_ctl.configure_five_sector_snapshot(
			"cdi_stage1",
			"res://data/rally/cdi_stage1_route.json",
			int(mgr.seed_value),
			str(sched.get("base_date", "2026-11-18")),
			float(sched.get("base_abs_seconds", base_abs)),
			float(sched.get("effective_abs_seconds", base_abs)),
			"gravel",
			"wet_front",
		),
		"Event calendar effective time configures SS01",
	)
	check(bool(ev_ctl.water_retention_status().get("active", false)), "Event mode activates SS01 retention")

	# Invalid profile diagnostic + neutral fallback.
	var bad_eng: RefCounted = ClassDB.instantiate(&"RustFiveSectorWeather")
	var climate_json := FileAccess.get_file_as_string("res://data/weather/cdi_ss04_climate.json")
	var bad_route_json := JSON.stringify({
		"track_id": "bad_stage",
		"samples": [
			{"progress_m": 0.0, "shader_station_m": 10.0, "altitude_m": 4600.0, "local_x_m": 0.0, "local_z_m": 0.0},
			{"progress_m": 20.0, "shader_station_m": 10.0, "altitude_m": 4600.0, "local_x_m": 20.0, "local_z_m": 0.0},
		],
	})
	var bad_cfg: Dictionary = bad_eng.call("configure_and_precompute_from_json", climate_json, bad_route_json, 77, "transition", base_abs, base_abs, "gravel", "wet_front")
	check(bool(bad_cfg.get("ok", false)), "Bad route configures base engine")
	var bad_wr: Dictionary = bad_eng.call("set_local_water_retention", true)
	check(not bool(bad_wr.get("valid", true)), "Invalid route reports valid=false")
	check(not str(bad_wr.get("diagnostic", "")).is_empty(), "Invalid route emits diagnostic message")
	check(not bool(bad_wr.get("active", true)), "Invalid route disables retention modifier (neutral 1.0)")


func _test_pilot_points_shader_and_restore() -> void:
	var base_abs := float(EventManagerScript.datetime_to_abs_seconds("2026-11-18", "09:40"))
	var ctl := ControllerScript.new()
	check(
		ctl.configure_five_sector_snapshot(
			"cdi_stage1",
			"res://data/rally/cdi_stage1_route.json",
			2026,
			"transition",
			base_abs,
			base_abs + 420.0,
			"gravel",
			"controlled_timing_episode",
		),
		"SS01 controlled episode configures",
	)
	var insp := ctl.inspect_water_retention_profile(25.0)
	check(bool(insp.get("ok", false)) and bool(insp.get("active", false)), "Inspection profile active")
	var rows: Array = insp.get("rows", [])
	check(rows.size() >= 180, "Inspection spans full 5km stage")

	# Three Sector-2 pilot points: crest (2539.6m), steep descent (2645.9m), valley/depression (2796.1m & 2360.2m).
	var p_crest := ctl.route_points[mini(323, ctl.route_points.size() - 1)]
	var s_crest := ctl.local_surface_state_at_distance(2539.6, 0.0)
	var s_desc := ctl.local_surface_state_at_distance(2645.9, 0.0)
	var s_gentle := ctl.local_surface_state_at_distance(2867.8, 0.0)
	var s_depr := ctl.local_surface_state_at_distance(2360.2, 0.0)
	var w_crest := float(s_crest.get("water_mm", 0.0))
	var w_desc := float(s_desc.get("water_mm", 0.0))
	var w_gentle := float(s_gentle.get("water_mm", 0.0))
	var w_depr := float(s_depr.get("water_mm", 0.0))
	check(w_crest < w_desc and w_desc < w_gentle and w_gentle < w_depr, "Pilot points order: crest (%.3f) < steep_desc (%.3f) < gentle_desc (%.3f) < depr (%.3f)" % [w_crest, w_desc, w_gentle, w_depr])
	check(p_crest != Vector3.ZERO, "Route points loaded")

	# Packet width (~12.5m target, <= 512) and shader decoding accuracy.
	var pkt := ctl.surface_field_packet(-1)
	check(bool(pkt.get("ok", false)), "Surface field packet generated")
	var pkt_w := int(pkt.get("width", 0))
	check(pkt_w >= 390 and pkt_w <= 512, "SS01 packet width ~12.5m/sample (got %d)" % pkt_w)
	var rev := int(pkt.get("revision", -1))
	check(ctl.surface_field_packet(rev).is_empty(), "Stable revision skips redundant packet/texture upload")

	var max_encode := float(pkt.get("max_encode_mm", 3.5))
	var quant_bound := 0.5 * (max_encode / 255.0) + 0.002
	var max_spatial_err := 0.0
	for p in [2360.2, 2539.6, 2645.9, 2796.1, 2867.8]:
		var cpu_s := ctl.local_surface_state_at_distance(p, 0.0)
		var cpu_w := float(cpu_s.get("water_mm", 0.0))
		var st := float(cpu_s.get("shader_station_m", ctl.progress_to_shader_station(p)))
		var gpu_w := _decode_shader_red_mm(pkt, st)
		var err := absf(cpu_w - gpu_w)
		max_spatial_err = maxf(max_spatial_err, err)
		check(err <= maxf(quant_bound * 4.0, 0.06), "CPU vs decoded shader red channel matches at p=%.1f (cpu=%.3f gpu=%.3f err=%.4f)" % [p, cpu_w, gpu_w, err])

	# Verify exact texel-center quantization bound at texel centers.
	var st_min := float(pkt.get("station_min_m", 0.0))
	var st_max := float(pkt.get("station_max_m", 1.0))
	var tex_step_st := (st_max - st_min) / float(pkt_w - 1)
	var eng: RefCounted = ctl.procedural_atmosphere
	for ti in [0, 50, 150, 250, pkt_w - 1]:
		var st_c := st_min + float(ti) * tex_step_st
		var p_c := float(eng.call("shader_station_to_progress", st_c))
		var cpu_c := float(ctl.local_surface_state_at_distance(p_c, 0.0).get("water_mm", 0.0))
		var dec_c := _decode_shader_red_mm(pkt, st_c)
		check(absf(cpu_c - dec_c) <= quant_bound, "Texel %d quantization err <= half step (%.4f vs %.4f)" % [ti, absf(cpu_c - dec_c), quant_bound])

	# Verify RallyVisualSectorStream applies texture & uniforms to gravel Road material (terrain_mode=2).
	var stream := StreamScript.new()
	stream.use_cdi_gravel_road = true
	check(stream.load_cdi_palette("res://assets/rally/cdi_stage1"), "Load SS01 palette")
	stream.sync_procedural_surface(pkt, true)
	var gravel_mat := stream._terrain_blend_for("Road")
	check(gravel_mat != null, "Gravel Road material created")
	check(bool(gravel_mat.get_shader_parameter("procedural_surface_enabled")), "Gravel Road material enables procedural_surface_enabled")
	check(gravel_mat.get_shader_parameter("surface_field_tex") != null, "Gravel Road material receives surface_field_tex")
	check(int(gravel_mat.get_shader_parameter("surface_field_width")) == pkt_w, "Gravel Road material width matches packet")
	# Subsequent streamed sectors share the same ShaderMaterial without discontinuity.
	check(stream._terrain_blend_for("Road") == gravel_mat, "Streamed sectors share identical gravel Road material")
	stream.free()

	# Compare with profile disabled (override=0) & dry day & post-rain retained moisture.
	var ctl_off := ControllerScript.new()
	check(
		ctl_off.configure_five_sector_snapshot(
			"cdi_stage1",
			"res://data/rally/cdi_stage1_route.json",
			2026,
			"transition",
			base_abs,
			base_abs + 420.0,
			"gravel",
			"controlled_timing_episode",
			0,
		),
		"SS01 configures with retention override=0",
	)
	check(not bool(ctl_off.water_retention_status().get("active", true)), "Override=0 disables retention")
	var pkt_off := ctl_off.surface_field_packet(-1)
	check(int(pkt_off.get("width", 0)) == 204, "Disabled retention keeps legacy 204-texel width")

	var ctl_dry := ControllerScript.new()
	check(ctl_dry.configure_five_sector_snapshot("cdi_stage1", "res://data/rally/cdi_stage1_route.json", 4242, "dry", base_abs, base_abs, "gravel", "dry"), "Dry SS01 configures")
	for p in [2360.2, 2539.6, 2796.1]:
		check(float(ctl_dry.local_surface_state_at_distance(p, 0.0).get("water_mm", -1.0)) == 0.0, "Dry SS01 water_mm == 0 at p=%.1f" % p)

	# Post-rain retained water after precipitation ends (+1500s -> rain_mm_h == 0, water_mm > 0).
	var ctl_post := ControllerScript.new()
	check(ctl_post.configure_five_sector_snapshot("cdi_stage1", "res://data/rally/cdi_stage1_route.json", 2026, "transition", base_abs, base_abs + 1500.0, "gravel", "controlled_timing_episode"), "Post-rain SS01 configures")
	var post_s := ctl_post.local_surface_state_at_distance(2360.2, 0.0)
	check(float(post_s.get("rain_mm_h", 99.0)) <= 0.01 and float(post_s.get("water_mm", 0.0)) > 0.1 and float(post_s.get("water_coverage", 0.0)) > 0.01, "Post-rain retained water persists visually after rain stops")

	# Snapshot save & restore reproduces identical contacts, shader packet, and puddle fills.
	var saved_snap := ctl.snapshot()
	var ctl_restored := ControllerScript.new()
	check(ctl_restored.configure_five_sector_snapshot("cdi_stage1", "res://data/rally/cdi_stage1_route.json", 2026, "transition", base_abs, base_abs, "gravel", "controlled_timing_episode"), "Fresh SS01 configures for restore")
	var rev_before_restore := int(ctl_restored.surface_field_packet(-1).get("revision", 0))
	ctl_restored.restore_snapshot(saved_snap)
	var pkt_restored := ctl_restored.surface_field_packet(rev_before_restore)
	check(bool(pkt_restored.get("ok", false)) and int(pkt_restored.get("revision", 0)) > rev_before_restore, "Restore increments revision and invalidates packet")
	check(pkt_restored.get("rgba8") == pkt.get("rgba8"), "Restored shader texture bytes match original snapshot")
	for p in [2360.2, 2539.6, 2645.9, 2796.1]:
		var a := float(ctl.local_surface_state_at_distance(p, 0.0).get("water_mm", -1.0))
		var b := float(ctl_restored.local_surface_state_at_distance(p, 0.0).get("water_mm", -2.0))
		check(is_equal_approx(a, b), "Restored surface water_mm matches at p=%.1f" % p)

	print("SS01_PILOT_DIAG crest_w=%.3f desc_w=%.3f gentle_w=%.3f depr_w=%.3f pkt_w=%d max_spatial_err=%.4f" % [w_crest, w_desc, w_gentle, w_depr, pkt_w, max_spatial_err])


func _test_puddle_fills_and_wheel_contact_continuity() -> void:
	# 1. Verify compute_puddle_fills with active retention vs disabled on SS01 Sector 2 under moderate rain (13:00 wet_front).
	var noon_abs := float(EventManagerScript.datetime_to_abs_seconds("2026-11-18", "13:00"))
	var ctl := ControllerScript.new()
	check(ctl.configure_five_sector_snapshot("cdi_stage1", "res://data/rally/cdi_stage1_route.json", 2026, "transition", noon_abs, noon_abs, "gravel", "wet_front"), "SS01 wet_front for puddle fill check")
	var fills := ctl.compute_puddle_fills(
		PackedFloat32Array([2539.6, 2360.2]),
		PackedFloat32Array([1.5, 1.5]),
		PackedFloat32Array([0.75, 0.75]),
		PackedFloat32Array([1.2, 1.2]),
	)
	var ctl_legacy := ControllerScript.new()
	check(ctl_legacy.configure_five_sector_snapshot("cdi_stage1", "res://data/rally/cdi_stage1_route.json", 2026, "transition", noon_abs, noon_abs, "gravel", "wet_front", 0), "SS01 legacy (override=0) configures")
	var fills_legacy := ctl_legacy.compute_puddle_fills(
		PackedFloat32Array([2539.6, 2360.2]),
		PackedFloat32Array([1.5, 1.5]),
		PackedFloat32Array([0.75, 0.75]),
		PackedFloat32Array([1.2, 1.2]),
	)
	check(fills == fills_legacy, "Procedural basin filling is independent of the surrounding road film")
	check(fills_legacy[0] > 0.5, "Legacy path without local retention would flood crest via TWI multiplier (fill=%.3f)" % fills_legacy[0])

	# 2. VehicleSimulation scalar + 4-wheel contact continuity across puddle edge & left/right asymmetry.
	var asset := _load_json("res://assets/rally/ford_escort_rs2000_1971/manifest.json")
	var sim := FordRallyVehicleSimulation.new()
	var res := sim.configure(asset, "res://data/vehicles/ford-escort-rs2000/vehicle.json")
	check(bool(res.get("ok", false)), "Vehicle simulation configures: " + str(res.get("error", "")))

	var world := Node3D.new()
	root.add_child(world)
	var road := StaticBody3D.new()
	road.name = "Collision_Road"
	road.set_meta("is_stage_road", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 0.2, 300)
	shape.shape = box
	road.add_child(shape)
	world.add_child(road)

	var pts: Array[Vector3] = [Vector3(0, 0.1, -130), Vector3(0, 0.1, 130)]
	var puddles := PuddlesScript.new()
	puddles.configure(pts, 731, null, null)
	world.add_child(puddles)
	await physics_frame
	await physics_frame
	puddles.build()
	check(not puddles.patches.is_empty(), "Test road puddles built")

	# Pick first puddle patch and force known fill = 0.8 for deterministic edge/center probe.
	var target_patch: Dictionary = puddles.patches[0]
	var center_pos: Vector3 = (target_patch["transform"] as Transform3D).origin
	var patch_size: Vector2 = target_patch["size"]
	for i in puddles.patches.size():
		puddles.patches[i]["fill"] = 0.8 if i == 0 else 0.0
	if puddles._rust_field != null:
		var f_arr := PackedFloat32Array()
		f_arr.resize(puddles.patches.size())
		f_arr[0] = 0.8
		puddles._rust_field.call("update_fills", f_arr)

	# Configure practice background film = 2.0 mm and attach puddles to simulation.
	sim.set_practice_thermal_environment({"air_c": 8.0, "ground_c": 8.0, "water_mm": 2.0, "snow_mm": 0.0, "irradiance_w_m2": 100.0})
	sim.puddle_system = puddles

	# Find a point just outside the puddle, just inside the edge (0 < depth < 1.5mm), and at center.
	var basis: Basis = (target_patch["transform"] as Transform3D).basis
	var out_pos := center_pos + basis.x * (patch_size.length() * 0.9)
	var edge_pos := center_pos
	var found_edge := false
	for dir_v: Vector3 in [basis.x, -basis.x, basis.z, -basis.z]:
		for step_k in range(1, 120):
			var cand: Vector3 = center_pos + dir_v * (patch_size.length() * 0.75 * float(step_k) / 120.0)
			var sc: Dictionary = puddles.sample_contact(cand)
			var d_mm := float(sc.get("depth_mm", 0.0))
			if d_mm > 0.15 and d_mm < 1.4:
				edge_pos = cand
				found_edge = true
				break
		if found_edge:
			break
	check(found_edge, "Found shallow edge probe inside puddle mask")

	var c_out := sim._local_conditions_at_contact("Gravel", out_pos, true)
	var c_edge := sim._local_conditions_at_contact("Gravel", edge_pos, true)
	var c_ctr := sim._local_conditions_at_contact("Gravel", center_pos, true)
	check(float(c_out.get("puddle_depth_mm", -1.0)) == 0.0 and is_equal_approx(float(c_out.get("background_water_mm", 0.0)), 2.0), "Outside puddle: depth=0, background_water=2.0mm")
	check(float(c_edge.get("puddle_depth_mm", 0.0)) > 0.1 and float(c_edge.get("puddle_depth_mm", 99.0)) < 1.5 and is_equal_approx(float(c_edge.get("background_water_mm", 0.0)), 2.0), "Edge puddle: shallow depth (%.2fmm) keeps background_water=2.0mm" % float(c_edge.get("puddle_depth_mm", 0.0)))
	check(float(c_ctr.get("puddle_depth_mm", 0.0)) > 8.0 and is_equal_approx(float(c_ctr.get("background_water_mm", 0.0)), 2.0), "Center puddle: deep (%.2fmm) keeps background_water=2.0mm" % float(c_ctr.get("puddle_depth_mm", 0.0)))

	# Verify no grip jump when crossing from outside -> edge -> center at moderate/high speed.
	var profile := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	var eval_lat := func(cond: Dictionary, speed_m_s: float) -> float:
		var tire := TireModelScript.new()
		tire.configure(profile.domains, profile.resolved_tire_filters, [3500.0, 3500.0, 3500.0, 3500.0])
		tire.set_compound("gravel_normal")
		var bg_w := float(cond.get("background_water_mm", 0.0))
		var tr := {}
		for _step_i in 30:
			tr = tire.evaluate(0, 3500.0, "Gravel", speed_m_s, 2.0, speed_m_s / 0.31, 0.31, 0.0, 1.0, 180.0, 0.01, 25.0, bg_w, 0.0, 8.0)
		var wf_bg := maxf(float(tr.get("compound_water_factor", 1.0)), 0.05)
		var pd := float(cond.get("puddle_depth_mm", 0.0))
		var eff_sup_y := 1.0
		if pd > 0.001:
			var pres := PuddlesScript.contact_response_packed(pd, speed_m_s, 16.0, 3500.0, 0.2, float(cond.get("puddle_drag", 1.0)), 0.0, 0.31)
			eff_sup_y = minf(wf_bg, pres[2]) / wf_bg
		return absf(float(tr.get("lateral_force_n", 0.0)) * eff_sup_y)

	var lat_out := float(eval_lat.call(c_out, 24.0))
	var lat_edge := float(eval_lat.call(c_edge, 24.0))
	var lat_ctr := float(eval_lat.call(c_ctr, 24.0))
	check(is_equal_approx(lat_edge, lat_out), "No grip discontinuity at shallow puddle edge (out=%.1fN edge=%.1fN ctr=%.1fN)" % [lat_out, lat_edge, lat_ctr])
	check(lat_ctr < lat_edge * 0.5, "Center puddle sharply reduces lateral support (ctr=%.1fN vs edge=%.1fN)" % [lat_ctr, lat_edge])

	# Verify batch 4-wheel path gives drag only on wheel inside puddle and zero on wheel outside.
	var w_pos := PackedVector3Array([center_pos, out_pos, center_pos, out_pos])
	var batch := puddles.sample_4wheels(w_pos, 15)
	check(batch.size() == 8 and batch[0] > 8.0 and batch[2] == 0.0, "4-wheel batch isolates puddle depth to wheel inside mask (FL=%.2f FR=%.2f)" % [batch[0], batch[2]])

	world.queue_free()
	await process_frame


func _place_car_at_world(session: RallyRussiaStageSession, ground_pos: Vector3, fwd: Vector3, speed_m_s: float, settle_frames: int = 36) -> void:
	session.set_physics_process(false)
	session.get_tree().paused = false
	var hit: Dictionary = session.vehicle.simulation.puddle_system.road_hit(ground_pos) if session.vehicle.simulation.puddle_system != null else {}
	var base_pos: Vector3 = hit.get("position", ground_pos) as Vector3
	var road_n: Vector3 = (hit.get("normal", Vector3.UP) as Vector3).normalized()
	var slope_fwd := (fwd - road_n * fwd.dot(road_n)).normalized()
	if slope_fwd.length_squared() < 0.1:
		slope_fwd = fwd.normalized()
	var target := base_pos + road_n * 0.30
	var heading := atan2(-slope_fwd.x, -slope_fwd.z)
	session.vehicle.reset_to_pose(target, heading)
	session.vehicle.freeze = false
	session.vehicle.sleeping = false
	await physics_frame
	session.vehicle.freeze = false
	session.vehicle.sleeping = false
	session.vehicle.linear_velocity = slope_fwd * speed_m_s
	session.vehicle.angular_velocity = Vector3.ZERO
	var cs := PhysicsServer3D.body_get_direct_state(session.vehicle.get_rid())
	if cs != null:
		cs.linear_velocity = slope_fwd * speed_m_s
		cs.angular_velocity = Vector3.ZERO
	for _f in settle_frames:
		await physics_frame
		session.event_weather.update_vehicle_position(session.vehicle.global_position)


func _place_car_at_progress(session: RallyRussiaStageSession, progress_m: float, lateral_offset_m: float, speed_m_s: float, settle_frames: int = 36) -> void:
	var pts := session.course.points
	var dists := session.course.route_distances
	var best_i := 0
	var best_d := INF
	for i in pts.size():
		var d := absf(float(dists[i]) - progress_m)
		if d < best_d:
			best_d = d
			best_i = i
	var pt := pts[best_i]
	var next_pt := pts[mini(best_i + 1, pts.size() - 1)]
	var fwd := next_pt - pt
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	await _place_car_at_world(session, pt + right * lateral_offset_m, fwd, speed_m_s, settle_frames)


func _test_ss01_full_stage_puddles_and_wheel_telemetry() -> void:
	var packed := load("res://scenes/rally/cdi_stage1.tscn") as PackedScene
	var session := packed.instantiate() as RallyRussiaStageSession
	session.track_id = "cdi_stage1"
	session.session_mode = "single_stage"
	session.practice_mode = false
	session.event_seed = 2026
	session.sky_start_hour = 13.0
	session.procedural_regime_override = "wet_front"
	session.event_clock.event_date = "2026-11-18"
	root.add_child(session)
	var frames := 0
	while not session.session_ready and frames < 360:
		await physics_frame
		frames += 1
	check(session.session_ready, "SS01 full stage session ready")
	if not session.session_ready:
		session.queue_free()
		await process_frame
		return

	check(session.event_weather.five_sector_snapshot_active, "SS01 uses five_sector_snapshot")
	check(bool(session.event_weather.water_retention_status().get("active", false)), "SS01 session activates water retention")

	var stream := session.track_visual.get_node_or_null("VisualSectorStream") as RallyVisualSectorStream
	check(stream != null and stream.is_procedural_surface_enabled(), "SS01 stream procedural surface active")
	var rev0 := stream.surface_field_revision()
	for _f in 10:
		await physics_frame
	check(stream.surface_field_revision() == rev0, "Stable revision causes zero texture re-uploads during race")

	var puddles := session.vehicle.simulation.puddle_system as RallyPuddles
	check(puddles != null and puddles.fixed_snapshot_mode, "SS01 puddles in fixed_snapshot_mode")

	var crest_active := 0
	var depr_active := 0
	var sec2_active := 0
	var total_active := 0
	var depr_patch: Dictionary = {}
	for p: Dictionary in puddles.patches:
		var d := float(p.get("distance", 0.0))
		var fill := float(p.get("fill", 0.0))
		var prof_id := str((p.get("profile", {}) as Dictionary).get("id", ""))
		var min_w := float((p.get("profile", {}) as Dictionary).get("min_water", 0.0))
		if fill > 0.005:
			total_active += 1
		if d >= 2000.0 and d <= 3000.0:
			var w_here := float(session.event_weather.local_surface_state_at_distance(d, 0.0).get("water_mm", 0.0))
			print("SS01_SEC2_PUDDLE d=%.1f lat=%.2f prof=%s min_w=%.2f water=%.3f fill=%.3f" % [d, float(p.get("lateral_offset", 0.0)), prof_id, min_w, w_here, fill])
			if fill > 0.005:
				sec2_active += 1
		if d >= 2490.0 and d <= 2600.0 and fill > 0.005:
			crest_active += 1
		if ((d >= 2330.0 and d <= 2430.0) or (d >= 2760.0 and d <= 2860.0)) and fill > 0.005:
			depr_active += 1
			if depr_patch.is_empty():
				depr_patch = p
	print("SS01_PUDDLE_TOTAL active=%d / %d sec2_active=%d" % [total_active, puddles.patches.size(), sec2_active])
	check(depr_active > 0 or sec2_active > 0, "SS01 Sector 2 depression has active puddles (depr=%d sec2=%d)" % [depr_active, sec2_active])

	# Measure published wheel telemetry at Sector 2 crest, gentle descent, and depression.
	await _place_car_at_progress(session, 2539.6, 0.0, 4.0, 36)
	var crest_wheels: Array = session.vehicle.simulation.published_state.get("wheels", [])
	var bw_crest := float((crest_wheels[0] as Dictionary).get("background_water_mm", -1.0))

	await _place_car_at_progress(session, 2867.8, 0.0, 4.0, 36)
	var desc_wheels: Array = session.vehicle.simulation.published_state.get("wheels", [])
	var bw_desc := float((desc_wheels[0] as Dictionary).get("background_water_mm", -1.0))

	await _place_car_at_progress(session, 2360.2, 0.0, 4.0, 36)
	var depr_wheels: Array = session.vehicle.simulation.published_state.get("wheels", [])
	var bw_depr := float((depr_wheels[0] as Dictionary).get("background_water_mm", -1.0))

	check(bw_crest > 0.05 and bw_crest < bw_desc and bw_desc < bw_depr, "SS01 wheel telemetry: crest (%.3f) < descent (%.3f) < depression (%.3f)" % [bw_crest, bw_desc, bw_depr])

	# Straddle an active puddle in Sector 2 depression at ~18 m/s so one side hits the puddle and the other misses.
	if not depr_patch.is_empty():
		var p_dist := float(depr_patch.get("distance", 2360.2))
		var p_xf: Transform3D = depr_patch.get("transform") as Transform3D
		var p_lat := float(depr_patch.get("lateral_offset", 1.0))
		var pts := session.course.points
		var dists := session.course.route_distances
		var bi := 0
		var bd := INF
		for i in pts.size():
			var dd := absf(float(dists[i]) - p_dist)
			if dd < bd:
				bd = dd
				bi = i
		var fwd_v := pts[mini(bi + 1, pts.size() - 1)] - pts[bi]
		fwd_v.y = 0.0
		fwd_v = fwd_v.normalized() if fwd_v.length_squared() > 0.01 else Vector3.FORWARD
		var right_v := fwd_v.cross(Vector3.UP).normalized()
		# Place car center ~0.78m toward road centerline from puddle center so one track rides through puddle center and opposite track stays outside.
		var side_sign := signf(p_lat) if absf(p_lat) > 0.1 else 1.0
		await _place_car_at_world(session, p_xf.origin - right_v * side_sign * 0.78 - fwd_v * 1.2, fwd_v, 18.0, 14)
		var max_pd := 0.0
		var min_pd := 999.0
		var max_drag := 0.0
		var min_drag := 999.0
		var min_sup := 999.0
		var max_sup := 0.0
		for _step in 10:
			await physics_frame
			session.event_weather.update_vehicle_position(session.vehicle.global_position)
			var st_wheels: Array = session.vehicle.simulation.published_state.get("wheels", [])
			var f_max_pd := 0.0
			var f_min_pd := 999.0
			var f_max_drag := 0.0
			var f_min_drag := 999.0
			var f_min_sup := 999.0
			var f_max_sup := 0.0
			for w: Dictionary in st_wheels:
				var pd := float(w.get("puddle_depth_mm", 0.0))
				var dg := float(w.get("puddle_drag_n", 0.0))
				var sp := float(w.get("puddle_support", 1.0))
				f_max_pd = maxf(f_max_pd, pd)
				f_min_pd = minf(f_min_pd, pd)
				f_max_drag = maxf(f_max_drag, dg)
				f_min_drag = minf(f_min_drag, dg)
				f_min_sup = minf(f_min_sup, sp)
				f_max_sup = maxf(f_max_sup, sp)
			if f_max_drag > max_drag or (max_drag == 0.0 and f_max_pd > max_pd):
				max_pd = f_max_pd
				min_pd = f_min_pd
				max_drag = f_max_drag
				min_drag = f_min_drag
				min_sup = f_min_sup
				max_sup = f_max_sup
		print("SS01_STRADDLE_TELEMETRY p=%.1f pd=[%.2f..%.2f] drag=[%.1f..%.1f] sup=[%.3f..%.3f]" % [p_dist, min_pd, max_pd, min_drag, max_drag, min_sup, max_sup])
		check(max_pd > 1.5 and max_drag > 1.0 and min_sup < 1.0, "Wheel inside SS01 puddle receives depth, drag, and grip loss")
		check(min_pd == 0.0 and min_drag == 0.0 and is_equal_approx(max_sup, 1.0), "Wheel outside SS01 puddle mask receives zero puddle drag and full support")

	print("SS01_FULL_STAGE_TELEMETRY crest_bw=%.3f desc_bw=%.3f depr_bw=%.3f crest_puddles=%d depr_puddles=%d" % [bw_crest, bw_desc, bw_depr, crest_active, depr_active])
	session.queue_free()
	await process_frame
	await process_frame


func run() -> void:
	_test_station_correspondence_and_config()
	_test_pilot_points_shader_and_restore()
	await _test_puddle_fills_and_wheel_contact_continuity()
	await _test_ss01_full_stage_puddles_and_wheel_telemetry()
	print("SS01_WATER_RETENTION_CONTRACT ", "PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
