extends SceneTree

const Controller = preload("res://scripts/rally/rally_weather_controller.gd")
const Puddles = preload("res://scripts/rally/rally_puddles.gd")

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# 1. Configure procedural weather + surface pre-roll for SS04.
	var ctl := Controller.new()
	var ok := ctl.configure_procedural(
		"cdi_stage4",
		"res://data/rally/cdi_stage4_route.json",
		2026,
		"transition",
		9.6667,
		"asphalt",
		"wet_front"
	)
	check(ok, "Controller configure_procedural succeeds: " + ctl.error)
	if not ok:
		quit(1)
		return

	var tel0: Dictionary = ctl.procedural_telemetry(1000.0)
	check(bool(tel0.get("ok", false)), "Telemetry available before race start")
	var samples0: Array = tel0.get("samples", [])
	check(samples0.size() >= 6, "Telemetry spans full stage")
	var mass_bal_err0 := absf(
		float(tel0.get("mean_total_mass_mm", 0.0))
		- (float(tel0.get("rain_in_mm", 0.0)) + float(tel0.get("snow_in_mm", 0.0))
		- float(tel0.get("evap_out_mm", 0.0)) - float(tel0.get("drain_out_mm", 0.0))
		- float(tel0.get("clipped_overflow_mm", 0.0)))
	)
	check(mass_bal_err0 < 0.01, "Pre-roll mass balance conserved within 0.01 mm (err=%.5f)" % mass_bal_err0)

	# 2. Advance runtime surface and test snapshot/restore exactness.
	var snap := ctl.snapshot()
	ctl.advance_ambient(300.0, 1.0)
	var after_300 := ctl.local_surface_state_at_distance(3100.0, 0.0)
	check(float(after_300.get("water_mm", -1.0)) >= 0.0, "Non-negative water_mm")
	check(float(after_300.get("snow_mm", -1.0)) >= 0.0, "Non-negative snow_mm")
	check(float(after_300.get("ice_mm", -1.0)) >= 0.0, "Non-negative ice_mm")
	var w_sum := float(after_300.get("dry_weight", 0.0)) + float(after_300.get("snow_weight", 0.0)) + float(after_300.get("ice_weight", 0.0))
	check(absf(w_sum - 1.0) < 0.001, "Normalized contact weights sum to 1.0")

	ctl.restore_snapshot(snap)
	ctl.advance_ambient(300.0, 1.0)
	var after_restore := ctl.local_surface_state_at_distance(3100.0, 0.0)
	check(is_equal_approx(float(after_restore.get("water_mm", -1.0)), float(after_300.get("water_mm", -2.0))), "Snapshot/restore reproduces exact water_mm")
	check(is_equal_approx(float(after_restore.get("snow_mm", -1.0)), float(after_300.get("snow_mm", -2.0))), "Snapshot/restore reproduces exact snow_mm")
	check(is_equal_approx(float(after_restore.get("ice_mm", -1.0)), float(after_300.get("ice_mm", -2.0))), "Snapshot/restore reproduces exact ice_mm")

	# Print sample telemetry line for inspection.
	var tel1: Dictionary = ctl.procedural_telemetry(1500.0)
	print("SS04_SURFACE_TELEMETRY elapsed_s=", tel1.get("elapsed_s"), " rain_in=", snappedf(float(tel1.get("rain_in_mm", 0.0)), 0.001), " snow_in=", snappedf(float(tel1.get("snow_in_mm", 0.0)), 0.001), " mean_mass=", snappedf(float(tel1.get("mean_total_mass_mm", 0.0)), 0.001))

	# 3. Connect RallyPuddles to procedural weather controller and test dry, liquid, and frozen puddle states.
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

	var dry_ctl := Controller.new()
	check(dry_ctl.configure_procedural("cdi_stage4", "res://data/rally/cdi_stage4_route.json", 777, "dry", 11.0, "asphalt", "dry"), "Dry controller configures")

	var pts: Array[Vector3] = [Vector3(0, 0.1, -130), Vector3(0, 0.1, 130)]
	var puddles := Puddles.new()
	puddles.configure(pts, 731, dry_ctl, null)
	world.add_child(puddles)
	await physics_frame
	await physics_frame
	puddles._physics_process(0.3)
	check(not puddles.patches.is_empty(), "Puddles built on test road")
	var first_pos: Vector3 = puddles.patches[0].transform.origin
	check(float(puddles.sample_contact(first_pos).depth_mm) == 0.0, "Dry procedural day has zero puddle depth")

	# Inject liquid meltwater (3.5 mm water, 0.0 mm ice) via surface snapshot into dry_ctl.
	var rust_eng: RefCounted = dry_ctl.procedural_atmosphere
	var snap_liq: Dictionary = rust_eng.call("snapshot_surface")
	var packed_liq: PackedFloat32Array = snap_liq["cells_packed"]
	for i in range(0, packed_liq.size(), 5):
		packed_liq[i] = 2.5       # ground_c
		packed_liq[i + 1] = 3.5   # water_mm (liquid from rain/melt)
		packed_liq[i + 2] = 0.0   # snow_mm
		packed_liq[i + 3] = 0.0   # ice_mm
	snap_liq["cells_packed"] = packed_liq
	check(bool(rust_eng.call("restore_surface_snapshot", snap_liq)), "Inject liquid meltwater snapshot")
	puddles._physics_process(0.3)
	var wet_depth := float(puddles.sample_contact(first_pos).depth_mm)
	check(wet_depth > 0.5, "Liquid water fills puddles (got %.3f mm)" % wet_depth)

	# Now freeze that water into ice (0.0 mm liquid water, 3.5 mm ice): puddle drag/depth must drop to zero.
	var snap_ice: Dictionary = rust_eng.call("snapshot_surface")
	var packed_ice: PackedFloat32Array = snap_ice["cells_packed"]
	for i in range(0, packed_ice.size(), 5):
		packed_ice[i] = -4.0      # ground_c
		packed_ice[i + 1] = 0.0   # water_mm frozen away
		packed_ice[i + 2] = 0.0   # snow_mm
		packed_ice[i + 3] = 3.5   # ice_mm
	snap_ice["cells_packed"] = packed_ice
	check(bool(rust_eng.call("restore_surface_snapshot", snap_ice)), "Inject frozen ice snapshot")
	puddles._physics_process(0.3)
	var ice_depth := float(puddles.sample_contact(first_pos).depth_mm)
	check(ice_depth == 0.0, "Frozen puddle water does not exert liquid puddle drag/depth (got %.3f mm)" % ice_depth)

	# Check local_conditions_for_contact propagates ice & lateral sampling.
	var contact_c := dry_ctl.local_conditions_for_contact("Road", dry_ctl.route_points[10])
	check(float(contact_c.get("ice_mm", 0.0)) > 1.0, "Contact query returns ice_mm")
	check(float(contact_c.get("ice_coverage", 0.0)) > 0.2, "Contact query returns ice_coverage")

	world.queue_free()
	await process_frame
	print("SS04_SURFACE_PUDDLES_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
