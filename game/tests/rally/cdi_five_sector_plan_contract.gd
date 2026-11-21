extends SceneTree

const EventManagerScript := preload("res://scripts/rally/rally_event_manager.gd")
const ControllerScript := preload("res://scripts/rally/rally_weather_controller.gd")
const SchedulerScript := preload("res://scripts/rally/rally_weather_scheduler.gd")
const PuddlesScript := preload("res://scripts/rally/rally_puddles.gd")
const TireModelScript := preload("res://scripts/physics/tire_model.gd")

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("CDI_PLAN_FAIL: " + label)


func _initialize() -> void:
	call_deferred("run")


func _test_phase_a_start_order_and_clock() -> void:
	var save_path := "user://test_cdi_phase_a_save.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	# 1. SS01 with full/partial championship standings + midnight date rollover test.
	var mgr := EventManagerScript.new()
	var champ := [
		{"id": "walter_rohrl", "points": 35, "position": 1},
		{"id": "timo_makinen", "points": 28, "position": 2},
		{"id": "player", "points": 22, "position": 3},
	]
	var ok_begin := mgr.begin_event({
		"event_id": "cdi_rally",
		"seed": 1974,
		"save_path": save_path,
		"championship_standings": champ,
	})
	check(ok_begin, "Phase A begin_event(cdi_rally) ok: " + mgr.error)
	if not ok_begin:
		return

	var so1: Dictionary = mgr.start_order_for_stage("cdi_stage1")
	var e1: Array = so1.get("entries", [])
	check(e1.size() >= 10, "SS01 start order includes all eligible entrants")
	check(str((e1[0] as Dictionary).get("id", "")) == "walter_rohrl", "SS01 championship leader starts 1st")
	check(str((e1[1] as Dictionary).get("id", "")) == "timo_makinen", "SS01 championship 2nd starts 2nd")
	check(str((e1[2] as Dictionary).get("id", "")) == "player", "SS01 partial championship player starts 3rd")

	var sched1: Dictionary = mgr.schedule_for("cdi_stage1")
	check(int(sched1.get("start_position_order", 0)) == 3, "SS01 player start slot is #3")
	check(int(sched1.get("interval_seconds", 0)) == 60, "CDI interval_seconds = 60s")
	check(str(sched1.get("effective_hm", "")) == "08:02", "SS01 base 08:00 + 2*60s = 08:02 (got %s)" % str(sched1.get("effective_hm", "")))

	# 2. Zero-car exclusion & SS01 deterministic draw without championship.
	var mgr_draw1 := EventManagerScript.new()
	var mgr_draw2 := EventManagerScript.new()
	check(mgr_draw1.begin_event({"event_id": "cdi_rally", "seed": 4242, "preview": true}), "Draw event 1 ok")
	check(mgr_draw2.begin_event({"event_id": "cdi_rally", "seed": 4242, "preview": true}), "Draw event 2 ok")
	var draw1_ids: Array = (mgr_draw1.start_order_for_stage("cdi_stage1").get("entries", []) as Array).map(func(x): return str((x as Dictionary).get("id", "")))
	var draw2_ids: Array = (mgr_draw2.start_order_for_stage("cdi_stage1").get("entries", []) as Array).map(func(x): return str((x as Dictionary).get("id", "")))
	check(draw1_ids == draw2_ids, "SS01 draw without championship is deterministic for same seed")
	check(mgr_draw1.climate_seed != EventManagerScript.start_order_draw_seed(4242), "Draw seed is separate from climate_seed")
	check(EventManagerScript._is_zero_car_entry("car_zero", {}), "Zero car detected by id")
	check(EventManagerScript._is_zero_car_entry("course_marshal", {"zero_car": true}), "Zero car detected by metadata")

	# Remaining unranked entrants after partial championship in mgr follow the deterministic initial draw!
	check(mgr.initial_start_draw.size() == e1.size(), "Initial start draw covers full eligible field")

	# 3. SS02 order from cumulative official rally standings INCLUDING penalty that shifts position!
	mgr.close_current_stage({"measured_ms": 150000, "penalty_ms": 0, "retired": false})
	# Verify snapshot/frozen publish after close_current_stage:
	var so2: Dictionary = mgr.start_order_for_stage("cdi_stage2")
	check(bool(so2.get("frozen", false)), "SS02 start list is frozen upon publish after SS01 close")
	var e2: Array = so2.get("entries", [])
	check(str((e2[0] as Dictionary).get("id", "")) == "player", "After fastest SS01 (150s), player leads SS02 start list")

	# Check persistence across save/restore and verify penalty can shift SS03 order!
	var mgr_restored := EventManagerScript.new()
	mgr_restored.save_path = save_path
	check(mgr_restored.load_event("res://data/competition/events/cdi_rally.json"), "Load cdi_rally doc")
	check(mgr_restored.restore(), "Restore CDI save ok: " + mgr_restored.error)
	var e2_ids: Array = e2.map(func(x): return str((x as Dictionary).get("id", "")))
	var e2_restored_ids: Array = (mgr_restored.start_order_for_stage("cdi_stage2").get("entries", []) as Array).map(func(x): return str((x as Dictionary).get("id", "")))
	check(
		e2_restored_ids == e2_ids,
		"Restore preserves exact frozen SS02 start order without re-drawing",
	)
	check(mgr_restored.advance(), "Advance to SS02 ok: " + mgr_restored.error)
	# Give player a huge 600s penalty in SS02 so cumulative standings drop player well behind!
	mgr_restored.close_current_stage({"measured_ms": 210000, "penalty_ms": 600000, "retired": false})
	var so3: Dictionary = mgr_restored.start_order_for_stage("cdi_stage3")
	var p_pos_ss3 := int(so3.get("player_position", 0))
	check(p_pos_ss3 > 1, "600s SS02 penalty drops player below 1st in SS03 start order (pos=%d)" % p_pos_ss3)

	# 4. Date rollover across midnight (23:55 + 8*60s or 23:55 + 600s = 00:05 next day) & unclassified behind classified.
	var abs_late := EventManagerScript.datetime_to_abs_seconds("2026-11-18", "23:55")
	var dt_after := EventManagerScript.abs_seconds_to_datetime(abs_late + 600)
	check(str(dt_after.get("date", "")) == "2026-11-19" and str(dt_after.get("hm", "")) == "00:05", "Midnight rollover updates date+hm cleanly")

	# Unclassified eligible entrant behind classified, definitive withdrawal excluded.
	mgr_restored.definitive_withdrawals["sandro_munari"] = true
	mgr_restored.official["late_rejoiner"] = {"name": "Reincorporado", "stages": {}, "grand_total_ms": 0, "eligible": true}
	var prev_before_ss4: Dictionary = mgr_restored.start_order_for_stage("cdi_stage3")
	(prev_before_ss4["entries"] as Array).append({"id": "late_rejoiner", "name": "Reincorporado"})
	mgr_restored.start_order_by_stage["cdi_stage3"] = prev_before_ss4
	mgr_restored.advance()
	mgr_restored.close_current_stage({"measured_ms": 215000, "penalty_ms": 0, "retired": false})
	var so4: Dictionary = mgr_restored.start_order_for_stage("cdi_stage4")
	var e4_ids: Array = (so4.get("entries", []) as Array).map(func(x): return str((x as Dictionary).get("id", "")))
	check(not e4_ids.has("sandro_munari"), "Definitively withdrawn competitor excluded from SS04 start list")
	check(str(e4_ids[-1]) == "late_rejoiner", "Eligible entrant without cumulative result placed after classified entrants preserving order")

	# 5. Legacy save compatibility (v3 without start_order_by_stage preserves active started stage & old mode).
	var legacy_save_path := "user://test_cdi_legacy_compat.json"
	var legacy_doc := {
		"version": 3,
		"event_id": "cdi_rally",
		"cursor": 1,
		"status": "running",
		"seed": 1974,
		"difficulty": 1,
		"single_day": false,
		"itinerary": mgr.itinerary,
		"official": mgr_restored.official,
		"closed_keys": ["closed:cdi_stage1"],
		"definitive_withdrawals": [],
		"clock": {"rate": 1.0},
		"weather_schedule": mgr.weather_schedule,
		"stage_forecasts": mgr.stage_forecasts,
		"climate_seed": mgr.climate_seed,
		"setup_confirmed": true,
	}
	var lf := FileAccess.open(legacy_save_path, FileAccess.WRITE)
	lf.store_string(JSON.stringify(legacy_doc))
	lf.close()
	var mgr_leg := EventManagerScript.new()
	mgr_leg.save_path = legacy_save_path
	check(mgr_leg.load_event("res://data/competition/events/cdi_rally.json"), "Load cdi for legacy test")
	check(mgr_leg.restore(), "Restore old v3 save cleanly")
	check(mgr_leg.save_mode_version == 1 and mgr_leg.climate_mode == "procedural_v1", "Legacy v3 save preserves old mode (v1 / procedural_v1)")
	check(mgr_leg.legacy_locked_stages.has("cdi_stage2"), "Active started stage keeps legacy base reference until closed")
	check(str(mgr_leg.schedule_for("cdi_stage2").get("start", "")) == "08:20", "Locked legacy stage keeps original 08:20 reference")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_save_path))


func _test_phase_b_c_five_sectors_turns_and_puddles() -> void:
	# 1. Same journey, different turns (1st vs 8th) + identical repeat + dry Abra check.
	var base_abs := float(EventManagerScript.datetime_to_abs_seconds("2026-11-18", "09:40"))
	var ctl_1st := ControllerScript.new()
	var ctl_8th := ControllerScript.new()
	var ctl_8th_repeat := ControllerScript.new()
	check(ctl_1st.configure_five_sector_snapshot("cdi_stage4", "res://data/rally/cdi_stage4_route.json", 2026, "transition", base_abs, base_abs, "asphalt", "controlled_timing_episode"), "1st configured")
	check(ctl_8th.configure_five_sector_snapshot("cdi_stage4", "res://data/rally/cdi_stage4_route.json", 2026, "transition", base_abs, base_abs + 420.0, "asphalt", "controlled_timing_episode"), "8th configured")
	check(ctl_8th_repeat.configure_five_sector_snapshot("cdi_stage4", "res://data/rally/cdi_stage4_route.json", 2026, "transition", base_abs, base_abs + 420.0, "asphalt", "controlled_timing_episode"), "8th repeat configured")

	var sectors_1st := ctl_1st.sector_summary()
	check(sectors_1st.size() == 5, "Exactly 5 atmospheric/surface sectors generated")
	var s1 := ctl_1st.local_surface_state_at_distance(3000.0, 0.0)
	var s8 := ctl_8th.local_surface_state_at_distance(3000.0, 0.0)
	var s8_rep := ctl_8th_repeat.local_surface_state_at_distance(3000.0, 0.0)
	check(float(s8.get("water_mm", 0.0)) > float(s1.get("water_mm", 0.0)), "8th starter at 09:47 sees higher accumulated water than 1st at 09:40")
	check(is_equal_approx(float(s8.get("water_mm", -1.0)), float(s8_rep.get("water_mm", -2.0))), "Identical turn+seed+params reproduces identical snapshot")

	# Verify advance_ambient does NOT mutate deposits during a fixed-snapshot pass!
	ctl_8th.advance_ambient(600.0, 1.0)
	var s8_after_run := ctl_8th.local_surface_state_at_distance(3000.0, 0.0)
	check(is_equal_approx(float(s8.get("water_mm", -1.0)), float(s8_after_run.get("water_mm", -2.0))), "Fixed snapshot omits soil deposit evolution during stage")

	# 2. Puddles pre-filled before countdown, frozen in _physics_process, zero when dry.
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
	puddles.configure(pts, 731, ctl_8th, null)
	world.add_child(puddles)
	await physics_frame
	await physics_frame
	puddles.build()
	check(puddles.fixed_snapshot_mode, "Puddles automatically enters fixed_snapshot_mode for five_sector_snapshot")
	check(not puddles.patches.is_empty(), "Puddle candidates built")
	var first_patch: Dictionary = puddles.patches[0]
	var fill_init := float(first_patch.get("fill", 0.0))
	check(fill_init > 0.05, "Wet turn pre-fills puddles before countdown (fill=%.3f)" % fill_init)
	var contact_wet := puddles.sample_contact((first_patch["transform"] as Transform3D).origin)
	check(float(contact_wet.get("depth_mm", 0.0)) > 0.5, "Wheel contact detects pre-filled puddle depth_mm (got %.2f)" % float(contact_wet.get("depth_mm", 0.0)))

	# Stepping _physics_process multiple times must keep fill invariant in fixed_snapshot_mode:
	for _i in 4:
		puddles._physics_process(0.25)
	check(is_equal_approx(float(puddles.patches[0].get("fill", -1.0)), fill_init), "Puddle fill stays fixed during pass")

	# Reuse exact same puddle candidates with a dry snapshot -> fills go to 0 without moving candidates!
	var ctl_dry := ControllerScript.new()
	check(ctl_dry.configure_five_sector_snapshot("cdi_stage4", "res://data/rally/cdi_stage4_route.json", 4242, "dry", base_abs, base_abs, "asphalt", "dry"), "Dry snapshot configured")
	puddles.provider = ctl_dry
	puddles.apply_fixed_snapshot_fills()
	check(float(puddles.patches[0].get("fill", -1.0)) == 0.0, "Dry snapshot zeroes fills on same candidates")
	check(float(puddles.sample_contact((first_patch["transform"] as Transform3D).origin).get("depth_mm", -1.0)) == 0.0, "Dry snapshot puddle depth_mm == 0")

	world.queue_free()
	await process_frame


func _test_phase_d_calibration_gravel_and_cost() -> void:
	var base_abs := float(EventManagerScript.datetime_to_abs_seconds("2026-11-18", "08:00"))
	# 1. Gravel stage (SS01 Rajuntay Alto) uses same 5-sector generator with gravel profile.
	var ctl_gravel := ControllerScript.new()
	check(ctl_gravel.configure_five_sector_snapshot("cdi_stage1", "res://data/rally/cdi_stage1_route.json", 4242, "transition", base_abs, base_abs, "gravel", "wet_front"), "SS01 gravel five-sector configures")
	var tel_g := ctl_gravel.procedural_telemetry(1000.0)
	check(bool(tel_g.get("ok", false)) and str(tel_g.get("surface_type", "")) == "gravel" and int(tel_g.get("sector_count", 0)) == 5, "SS01 uses gravel profile with 5 sectors")

	# 2. Controlled thin snow grip ~80% of dry asphalt reference in TireModel.
	var profile := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	var tire := TireModelScript.new()
	tire.configure(profile.domains, profile.resolved_tire_filters, [3500.0, 3500.0, 3500.0, 3500.0])
	tire.set_compound("asphalt_mixed")
	var dry_lat := absf(float(tire.evaluate(0, 3500.0, "Road", 20.0, 2.5, 64.5, 0.31, 0.0, 1.0, 200.0, 0.01, 70.0, 0.0, 0.0, 20.0, "", 0.0, 0.0, 0.0).get("lateral_force_n", 1.0)))
	var thin_snow_lat := absf(float(tire.evaluate(0, 3500.0, "Road", 20.0, 2.5, 64.5, 0.31, 0.0, 1.0, 200.0, 0.01, 70.0, 0.0, 0.45, 0.0, "", 0.0, 0.38, 0.0).get("lateral_force_n", 0.0)))
	var ratio := thin_snow_lat / maxf(dry_lat, 1.0)
	check(ratio >= 0.72 and ratio <= 0.88, "Thin snow grip ratio ~0.80 of dry reference (got %.3f)" % ratio)

	# 3. Prep cost comparison: 5-sector snapshot vs procedural_v1 (26 nodes + 125 cells 6h pre-roll).
	var t0_v1 := Time.get_ticks_usec()
	var ctl_v1 := ControllerScript.new()
	check(ctl_v1.configure_procedural("cdi_stage4", "res://data/rally/cdi_stage4_route.json", 777, "transition", 9.6667, "asphalt", "wet_front"), "procedural_v1 configures for comparison")
	var prep_v1_us := Time.get_ticks_usec() - t0_v1

	var t0_v2 := Time.get_ticks_usec()
	var ctl_v2 := ControllerScript.new()
	check(ctl_v2.configure_five_sector_snapshot("cdi_stage4", "res://data/rally/cdi_stage4_route.json", 777, "transition", base_abs, base_abs, "asphalt", "wet_front"), "five_sector_snapshot configures for comparison")
	var prep_v2_us := Time.get_ticks_usec() - t0_v2

	print("CDI_PREP_PERF five_sector_ms=%.3f procedural_v1_ms=%.3f thin_snow_ratio=%.3f" % [prep_v2_us / 1000.0, prep_v1_us / 1000.0, ratio])
	check(prep_v2_us < prep_v1_us, "5-sector snapshot prep is strictly faster than 26x125 6h pre-roll")


func run() -> void:
	_test_phase_a_start_order_and_clock()
	await _test_phase_b_c_five_sectors_turns_and_puddles()
	_test_phase_d_calibration_gravel_and_cost()
	print("CDI_FIVE_SECTOR_PLAN_CONTRACT ", "PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
