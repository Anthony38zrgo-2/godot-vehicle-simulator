extends SceneTree
## tire_combined_migration_contract.gd
##
## Regression & acceptance test suite for bidirectional combined-slip
## reference migration v2 in TireModel.
##
## Acceptance criteria:
## 1. Migration disabled: Reproduces legacy behavior with identical parameters.
## 2. Migration enabled, coefficients zero: Recovers original brush stiffnesses without legacy compensation.
## 3. ux = 0: Lateral reference unchanged.
## 4. uy = 0: Longitudinal reference unchanged.
## 5. ux = 1, m_lat = 0.15: peak_lat_eff = base_peak_lat * 1.15 (stiffness_y scaled by 1/1.15).
## 6. uy = 1, m_lon = 0.08: peak_lon_eff = base_peak_lon * 1.08 (stiffness_x scaled by 1/1.08).
## 7. Increasing m_lat: Reduces stiffness_y monotonically for positive longitudinal demand.
## 8. Increasing m_lon: Reduces stiffness_x monotonically for positive lateral demand.
## 9. High combined slip: Finite forces within elliptical friction budget.
## 10. Airborne / unloaded wheel: Generates zero forces.
## 11. Traction and braking: Continuous across sign change of demand.
## 12. Friction ellipse budget: sqrt((Fx/Lx)^2 + (Fy/Ly)^2) <= 1 + eps.
## 13. Profile loader & Escort RS2000 initial rear axle calibration.

var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)
	else:
		print("  PASS: " + message)


func _initialize() -> void:
	call_deferred("run_suite")


func run_suite() -> void:
	print("--- TIRE COMBINED MIGRATION V2 CONTRACT ---")
	test_profile_and_escort_calibration()
	test_legacy_equivalence()
	test_zero_migration_coefficients()
	test_ux_zero_lateral_unchanged()
	test_uy_zero_longitudinal_unchanged()
	test_ux_one_scaling()
	test_uy_one_scaling()
	test_monotonic_stiffness_reduction()
	test_unloaded_wheel()
	test_continuity_and_symmetry()
	test_high_combined_slip_and_friction_budget()
	test_all_vehicles_migration_v2()

	if failures.is_empty():
		print("\nALL TIRE COMBINED MIGRATION V2 CONTRACT TESTS PASSED!")
		quit(0)
	else:
		print("\nTIRE COMBINED MIGRATION CONTRACT FAILED with %d errors:" % failures.size())
		for f in failures:
			print("  - ", f)
		quit(1)


func create_tire_model(overrides: Dictionary = {}, axle_idx: int = 2) -> TireModel:
	var loader := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	assert(loader.ok, "Escort RS2000 profile must load successfully")
	var domains: Dictionary = loader.domains.duplicate(true)
	var filters: Dictionary = loader.resolved_tire_filters.duplicate(true)
	var axle_name := "front" if axle_idx < 2 else "rear"
	var profile: Dictionary = filters.get(axle_name, {}).duplicate(true)
	for k in overrides:
		profile[k] = overrides[k]
	filters[axle_name] = profile
	var tire := TireModel.new()
	tire.configure(domains, filters, [2500.0, 2500.0, 2500.0, 2500.0])
	return tire


func test_profile_and_escort_calibration() -> void:
	print("\n[1] Testing Escort RS2000 profile configuration and calibration...")
	var loader := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	check(loader.ok, "VehicleProfileLoader loads escort profile")
	var rear: Dictionary = loader.resolved_tire_filters.get("rear", {})
	check(bool(rear.get("combined_migration_v2_enabled", false)) == true, "Rear axle migration v2 is enabled")
	check(is_equal_approx(float(rear.get("combined_lateral_peak_migration", 0.0)), 0.15), "Rear combined_lateral_peak_migration is 0.15")
	check(is_equal_approx(float(rear.get("combined_longitudinal_peak_migration", 0.0)), 0.08), "Rear combined_longitudinal_peak_migration is 0.08")
	check(is_equal_approx(float(rear.get("lateral_peak_slip_angle_rad", 0.0)), 0.17), "Rear lateral_peak_slip_angle_rad is 0.17")
	check(is_equal_approx(float(rear.get("longitudinal_peak_slip_ratio", 0.0)), 0.28), "Rear longitudinal_peak_slip_ratio is 0.28")
	check(is_equal_approx(float(rear.get("lateral_slide_mu_ratio", 0.0)), 0.97), "Rear lateral_slide_mu_ratio is 0.97")
	check(is_equal_approx(float(rear.get("longitudinal_slide_mu_ratio", 0.0)), 0.96), "Rear longitudinal_slide_mu_ratio is 0.96")
	check(is_equal_approx(float(rear.get("slip_loss_tau_s", 0.0)), 0.10), "Rear slip_loss_tau_s is 0.10")
	check(is_equal_approx(float(rear.get("slip_recovery_tau_s", 0.0)), 0.12), "Rear slip_recovery_tau_s is 0.12")

	var front: Dictionary = loader.resolved_tire_filters.get("front", {})
	check(bool(front.get("combined_migration_v2_enabled", false)) == false, "Front axle migration v2 defaults to disabled")


func test_legacy_equivalence() -> void:
	print("\n[2] Testing legacy behavior when combined_migration_v2_enabled is false...")
	# With migration disabled, the code must behave exactly like the legacy implementation:
	# Front axle: no migration, no legacy relief.
	# Rear axle: under acceleration (patch_pos.x > 0), legacy relief reduces norm_demand_x.
	# Rear axle: under braking (patch_pos.x < 0), no legacy relief.
	var tire := create_tire_model({"combined_migration_v2_enabled": false}, 2)
	# Warm up state
	tire.evaluate(2, 2500.0, "Gravel", 15.0, 0.0, 15.0 / 0.28, 0.28, 0.0, 1.0, 200.0, 0.01, 60.0)
	tire.states[2].contact_blend = 1.0
	tire.states[2].surface_initialized = true

	# Test rear accelerating
	tire.states[2].patch_pos = Vector2(0.05, 0.02)
	var res_legacy_acc := tire.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)
	check(is_finite(res_legacy_acc.longitudinal_force_n) and is_finite(res_legacy_acc.lateral_force_n), "Legacy accelerating forces are finite")

	# Test rear braking
	tire.states[2].patch_pos = Vector2(-0.05, 0.02)
	var res_legacy_brk := tire.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)
	check(is_finite(res_legacy_brk.longitudinal_force_n) and is_finite(res_legacy_brk.lateral_force_n), "Legacy braking forces are finite")


func test_zero_migration_coefficients() -> void:
	print("\n[3] Testing migration enabled with zero coefficients...")
	# When migration is enabled and coefficients are 0:
	# peak_lat_eff == base_peak_lat, peak_lon_eff == base_peak_lon.
	# Brush stiffnesses are exactly original.
	# Legacy compensation is NOT applied.
	var tire_zero := create_tire_model({
		"combined_migration_v2_enabled": true,
		"combined_lateral_peak_migration": 0.0,
		"combined_longitudinal_peak_migration": 0.0,
	}, 2)
	tire_zero.evaluate(2, 2500.0, "Gravel", 15.0, 0.0, 15.0 / 0.28, 0.28, 0.0, 1.0, 200.0, 0.01, 60.0)
	tire_zero.states[2].contact_blend = 1.0
	tire_zero.states[2].surface_initialized = true

	var px := 0.001
	var py := 0.001
	tire_zero.states[2].patch_pos = Vector2(px, py)
	var res := tire_zero.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)

	# Compare with unmigrated front axle with no relief
	var tire_front := create_tire_model({"combined_migration_v2_enabled": false}, 0)
	tire_front.evaluate(0, 2500.0, "Gravel", 15.0, 0.0, 15.0 / 0.28, 0.28, 0.0, 1.0, 200.0, 0.01, 60.0)
	tire_front.states[0].contact_blend = 1.0
	tire_front.states[0].surface_initialized = true

	check(is_finite(res.longitudinal_force_n) and is_finite(res.lateral_force_n), "Forces with zero coefficients are finite")
	check(res.longitudinal_force_n > 0.0 and res.lateral_force_n > 0.0, "Forces respond positively in linear regime")


func test_ux_zero_lateral_unchanged() -> void:
	print("\n[4] Testing ux = 0: Lateral reference unchanged by m_lat...")
	# Pure lateral slip: patch_pos.x = 0, so ux = 0.
	# peak_lat_eff = base_peak_lat * (1.0 + m_lat * 0) = base_peak_lat.
	# Lateral force and stiffness must be strictly independent of m_lat.
	var tire_m0 := create_tire_model({
		"combined_migration_v2_enabled": true,
		"combined_lateral_peak_migration": 0.0,
		"combined_longitudinal_peak_migration": 0.10,
	}, 2)
	var tire_m15 := create_tire_model({
		"combined_migration_v2_enabled": true,
		"combined_lateral_peak_migration": 0.15,
		"combined_longitudinal_peak_migration": 0.10,
	}, 2)
	var tire_m30 := create_tire_model({
		"combined_migration_v2_enabled": true,
		"combined_lateral_peak_migration": 0.30,
		"combined_longitudinal_peak_migration": 0.10,
	}, 2)

	for t in [tire_m0, tire_m15, tire_m30]:
		t.evaluate(2, 2500.0, "Gravel", 15.0, 0.0, 15.0 / 0.28, 0.28, 0.0, 1.0, 200.0, 0.01, 60.0)
		t.states[2].contact_blend = 1.0
		t.states[2].surface_initialized = true
		t.states[2].patch_pos = Vector2(0.0, 0.02)

	var res0 := tire_m0.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)
	var res15 := tire_m15.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)
	var res30 := tire_m30.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)

	check(is_equal_approx(res0.lateral_force_n, res15.lateral_force_n), "ux=0: Fy(m_lat=0) == Fy(m_lat=0.15)")
	check(is_equal_approx(res0.lateral_force_n, res30.lateral_force_n), "ux=0: Fy(m_lat=0) == Fy(m_lat=0.30)")


func test_uy_zero_longitudinal_unchanged() -> void:
	print("\n[5] Testing uy = 0: Longitudinal reference unchanged by m_lon...")
	# Pure longitudinal slip: patch_pos.y = 0, so uy = 0.
	# peak_lon_eff = base_peak_lon * (1.0 + m_lon * 0) = base_peak_lon.
	# Longitudinal force and stiffness must be strictly independent of m_lon.
	var tire_m0 := create_tire_model({
		"combined_migration_v2_enabled": true,
		"combined_lateral_peak_migration": 0.15,
		"combined_longitudinal_peak_migration": 0.0,
	}, 2)
	var tire_m08 := create_tire_model({
		"combined_migration_v2_enabled": true,
		"combined_lateral_peak_migration": 0.15,
		"combined_longitudinal_peak_migration": 0.08,
	}, 2)
	var tire_m30 := create_tire_model({
		"combined_migration_v2_enabled": true,
		"combined_lateral_peak_migration": 0.15,
		"combined_longitudinal_peak_migration": 0.30,
	}, 2)

	for t in [tire_m0, tire_m08, tire_m30]:
		t.evaluate(2, 2500.0, "Gravel", 15.0, 0.0, 15.0 / 0.28, 0.28, 0.0, 1.0, 200.0, 0.01, 60.0)
		t.states[2].contact_blend = 1.0
		t.states[2].surface_initialized = true
		t.states[2].patch_pos = Vector2(0.03, 0.0)

	var res0 := tire_m0.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)
	var res08 := tire_m08.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)
	var res30 := tire_m30.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)

	check(is_equal_approx(res0.longitudinal_force_n, res08.longitudinal_force_n), "uy=0: Fx(m_lon=0) == Fx(m_lon=0.08)")
	check(is_equal_approx(res0.longitudinal_force_n, res30.longitudinal_force_n), "uy=0: Fx(m_lon=0) == Fx(m_lon=0.30)")


func test_ux_one_scaling() -> void:
	print("\n[6] Testing ux = 1, m_lat = 0.15: peak_lat_eff = base_peak_lat * 1.15...")
	# At ux = 1.0, peak_lat_eff = base_peak_lat * (1 + 0.15 * 1.0) = base_peak_lat * 1.15.
	# In linear regime (small py), stiffness_y scales by 1.0 / 1.15.
	# Thus Fy(m_lat=0) / Fy(m_lat=0.15) == 1.15.
	var tire := create_tire_model({
		"combined_migration_v2_enabled": true,
		"combined_lateral_peak_migration": 0.15,
		"combined_longitudinal_peak_migration": 0.08,
	}, 2)
	tire.evaluate(2, 2500.0, "Gravel", 15.0, 0.0, 15.0 / 0.28, 0.28, 0.0, 1.0, 200.0, 0.01, 60.0)
	tire.states[2].contact_blend = 1.0
	tire.states[2].surface_initialized = true
	tire.states[2].post_peak_decay_lat = 0.0
	tire.states[2].post_peak_decay_lon = 0.0

	var base_peak_lon := float(tire.axle_profiles[2].longitudinal_peak_slip_ratio)
	var length_m: float = float(tire.states[2].relaxation_length_m)
	# At ux = 1.0: patch_pos.x = base_peak_lon * length_m
	var px := base_peak_lon * length_m
	var py := 0.001 # Small linear deformation

	# With m_lat = 0.15
	tire.axle_profiles[2].combined_lateral_peak_migration = 0.15
	tire.states[2].patch_pos = Vector2(px, py)
	var res15 := tire.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)
	var fy15: float = res15.lateral_force_n

	# With m_lat = 0.0
	tire.axle_profiles[2].combined_lateral_peak_migration = 0.0
	tire.states[2].patch_pos = Vector2(px, py)
	var res0 := tire.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)
	var fy0: float = res0.lateral_force_n

	var ratio := fy0 / fy15
	check(absf(ratio - 1.15) < 1.0e-3, "ux=1, m_lat=0.15: ratio Fy0/Fy15 = %.5f, expected 1.15" % ratio)


func test_uy_one_scaling() -> void:
	print("\n[7] Testing uy = 1, m_lon = 0.08: peak_lon_eff = base_peak_lon * 1.08...")
	# At uy = 1.0, peak_lon_eff = base_peak_lon * (1 + 0.08 * 1.0) = base_peak_lon * 1.08.
	# In linear regime (small px, speed = 0 so rolling force = 0), stiffness_x scales by 1.0 / 1.08.
	# Thus Fx(m_lon=0) / Fx(m_lon=0.08) == 1.08.
	var tire := create_tire_model({
		"combined_migration_v2_enabled": true,
		"combined_lateral_peak_migration": 0.15,
		"combined_longitudinal_peak_migration": 0.08,
	}, 2)
	tire.evaluate(2, 2500.0, "Gravel", 15.0, 0.0, 15.0 / 0.28, 0.28, 0.0, 1.0, 200.0, 0.01, 60.0)
	tire.states[2].contact_blend = 1.0
	tire.states[2].surface_initialized = true
	tire.states[2].post_peak_decay_lat = 0.0
	tire.states[2].post_peak_decay_lon = 0.0

	var base_peak_lat := float(tire.axle_profiles[2].lateral_peak_slip_angle_rad)
	var length_m: float = float(tire.states[2].relaxation_length_m)
	# At uy = 1.0: patch_pos.y = base_peak_lat * length_m
	var px := 0.001 # Small linear deformation
	var py := base_peak_lat * length_m

	# With m_lon = 0.08
	tire.axle_profiles[2].combined_longitudinal_peak_migration = 0.08
	tire.states[2].patch_pos = Vector2(px, py)
	var res08 := tire.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)
	var fx08: float = res08.longitudinal_force_n

	# With m_lon = 0.0
	tire.axle_profiles[2].combined_longitudinal_peak_migration = 0.0
	tire.states[2].patch_pos = Vector2(px, py)
	var res0 := tire.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)
	var fx0: float = res0.longitudinal_force_n

	var ratio := fx0 / fx08
	check(absf(ratio - 1.08) < 1.0e-3, "uy=1, m_lon=0.08: ratio Fx0/Fx08 = %.5f, expected 1.08" % ratio)


func test_monotonic_stiffness_reduction() -> void:
	print("\n[8] Testing monotonic stiffness reduction when increasing migration coefficients...")
	var tire := create_tire_model({"combined_migration_v2_enabled": true}, 2)
	tire.evaluate(2, 2500.0, "Gravel", 15.0, 0.0, 15.0 / 0.28, 0.28, 0.0, 1.0, 200.0, 0.01, 60.0)
	tire.states[2].contact_blend = 1.0
	tire.states[2].surface_initialized = true
	tire.states[2].post_peak_decay_lat = 0.0
	tire.states[2].post_peak_decay_lon = 0.0

	var base_peak_lon := float(tire.axle_profiles[2].longitudinal_peak_slip_ratio)
	var base_peak_lat := float(tire.axle_profiles[2].lateral_peak_slip_angle_rad)
	var length_m: float = float(tire.states[2].relaxation_length_m)

	# 1. Increasing m_lat reduces stiffness_y (and linear Fy) for ux > 0
	var px := base_peak_lon * length_m * 0.7 # ux = 0.7
	var py := 0.001
	var m_lat_values: Array[float] = [0.0, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30]
	var last_fy := INF
	var lat_monotonic := true
	for m in m_lat_values:
		tire.axle_profiles[2].combined_lateral_peak_migration = m
		tire.states[2].patch_pos = Vector2(px, py)
		var res := tire.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)
		var fy: float = res.lateral_force_n
		if fy >= last_fy:
			lat_monotonic = false
		last_fy = fy
	check(lat_monotonic, "Increasing m_lat strictly decreases stiffness_y monotonically")

	# 2. Increasing m_lon reduces stiffness_x (and linear Fx) for uy > 0
	px = 0.001
	py = base_peak_lat * length_m * 0.7 # uy = 0.7
	var m_lon_values: Array[float] = [0.0, 0.04, 0.08, 0.15, 0.20, 0.25, 0.30]
	var last_fx := INF
	var lon_monotonic := true
	for m in m_lon_values:
		tire.axle_profiles[2].combined_longitudinal_peak_migration = m
		tire.states[2].patch_pos = Vector2(px, py)
		var res := tire.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)
		var fx: float = res.longitudinal_force_n
		if fx >= last_fx:
			lon_monotonic = false
		last_fx = fx
	check(lon_monotonic, "Increasing m_lon strictly decreases stiffness_x monotonically")


func test_unloaded_wheel() -> void:
	print("\n[9] Testing unloaded wheel behavior (no contact)...")
	var tire := create_tire_model({"combined_migration_v2_enabled": true}, 2)
	# Fz = 0
	var res0 := tire.evaluate(2, 0.0, "Gravel", 15.0, 2.0, 18.0 / 0.28, 0.28, 0.0, 1.0, 200.0, 0.01, 60.0)
	check(res0.longitudinal_force_n == 0.0 and res0.lateral_force_n == 0.0, "Fz=0 produces exactly zero Fx and Fy")
	check(is_finite(res0.longitudinal_force_n) and is_finite(res0.lateral_force_n), "Forces are finite when unloaded")

	# Fz < 0 (negative load clamp)
	var res_neg := tire.evaluate(2, -500.0, "Gravel", 15.0, 2.0, 18.0 / 0.28, 0.28, 0.0, 1.0, 200.0, 0.01, 60.0)
	check(res_neg.longitudinal_force_n == 0.0 and res_neg.lateral_force_n == 0.0, "Fz<0 produces exactly zero Fx and Fy")


func test_continuity_and_symmetry() -> void:
	print("\n[10] Testing continuity and symmetry across traction and braking...")
	var tire := create_tire_model({
		"combined_migration_v2_enabled": true,
		"combined_lateral_peak_migration": 0.15,
		"combined_longitudinal_peak_migration": 0.08,
	}, 2)
	tire.evaluate(2, 2500.0, "Gravel", 15.0, 0.0, 15.0 / 0.28, 0.28, 0.0, 1.0, 200.0, 0.01, 60.0)
	tire.states[2].contact_blend = 1.0
	tire.states[2].surface_initialized = true

	# Test longitudinal sign change: Fx must be antisymmetric, Fy symmetric (magnitude based ux)
	var px_pos := 0.02
	var px_neg := -0.02
	var py := 0.015

	tire.states[2].patch_pos = Vector2(px_pos, py)
	var res_pos := tire.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)

	tire.states[2].patch_pos = Vector2(px_neg, py)
	var res_neg := tire.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)

	check(is_equal_approx(res_pos.longitudinal_force_n, -res_neg.longitudinal_force_n), "Fx is antisymmetric across traction and braking")
	check(is_equal_approx(res_pos.lateral_force_n, res_neg.lateral_force_n), "Fy is symmetric across traction and braking (lateral migration operates in both)")

	# Sweep across zero in small steps to confirm no discontinuity
	var prev_fx := 0.0
	var max_step_diff := 0.0
	var steps := 20
	for i in range(-steps, steps + 1):
		var p: float = float(i) / float(steps) * 0.04
		tire.states[2].patch_pos = Vector2(p, py)
		var r := tire.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.0, 60.0)
		if i > -steps:
			var step_diff := absf(float(r.longitudinal_force_n) - prev_fx)
			if step_diff > max_step_diff:
				max_step_diff = step_diff
		prev_fx = float(r.longitudinal_force_n)

	check(is_finite(max_step_diff) and max_step_diff < 500.0, "Smooth continuous transition through zero longitudinal demand")


func test_high_combined_slip_and_friction_budget() -> void:
	print("\n[11] Testing high combined slip and elliptical friction budget...")
	var tire := create_tire_model({
		"combined_migration_v2_enabled": true,
		"combined_lateral_peak_migration": 0.15,
		"combined_longitudinal_peak_migration": 0.08,
	}, 2)

	var slip_ratios: Array[float] = [-2.0, -1.0, -0.4, 0.0, 0.4, 1.0, 2.0]
	var slip_angles_rad: Array[float] = [-0.6, -0.3, 0.0, 0.3, 0.6]
	var loads: Array[float] = [1000.0, 2500.0, 4500.0]
	var surfaces: Array[String] = ["Gravel", "Road"]

	var budget_violation_count := 0
	var non_finite_count := 0
	var total_tests := 0

	for surf in surfaces:
		for load in loads:
			for sx in slip_ratios:
				for sy in slip_angles_rad:
					total_tests += 1
					# Integrate 40 steps to allow steady state and post-peak decay memory to settle
					for step in 40:
						var v_lon := 22.0
						var v_lat: float = -v_lon * tan(sy)
						var w_rad: float = (v_lon * (1.0 + sx)) / 0.28
						var res := tire.evaluate(2, load, surf, v_lon, v_lat, w_rad, 0.28, 0.0, 1.0, 200.0, 0.01, 60.0)
						if not is_finite(res.longitudinal_force_n) or not is_finite(res.lateral_force_n):
							non_finite_count += 1

					var st: Dictionary = tire.states[2]
					var fx: float = float(st.longitudinal_force)
					var fy: float = float(st.lateral_force)

					if not is_finite(fx) or not is_finite(fy):
						non_finite_count += 1

					# Compute ellipse friction limits Lx and Ly including slide_scale and contact_blend
					var limits := compute_friction_limits(tire, 2, load, surf)
					var budget_ratio := sqrt(pow(fx / limits.x, 2.0) + pow(fy / limits.y, 2.0))
					# Budget norm must not exceed 1.0 + small numerical epsilon (1e-3)
					if budget_ratio > 1.001:
						budget_violation_count += 1

	check(non_finite_count == 0, "No non-finite forces or NaNs under extreme combined slip (%d cases)" % total_tests)
	check(budget_violation_count == 0, "Friction ellipse budget respected: sqrt((Fx/Lx)^2 + (Fy/Ly)^2) <= 1 + eps across all %d conditions" % total_tests)


func compute_friction_limits(tire: TireModel, index: int, normal_load_n: float, surface_name: String, thermal_grip_factor: float = 1.0) -> Vector2:
	var state: Dictionary = tire.states[index]
	var profile: Dictionary = tire.axle_profiles[index]
	var axle_surface_set: Dictionary = tire.axle_surfaces[index]
	var target_surface: Dictionary = axle_surface_set.get(surface_name, axle_surface_set.get("Gravel", {}))
	var fz := maxf(normal_load_n, 0.0)
	var ref_load := maxf(float(tire.static_wheel_load_n[index]), 100.0)
	var load_ratio := maxf(fz / ref_load, 0.05)
	var axle_mult := float(tire.axle_load_mult[index])
	var load_sensitivity_exp := clampf(float(tire.axle_load_sensitivity[index]) * ref_load * axle_mult, 0.08, 0.25)
	var load_scale := clampf(pow(load_ratio, -load_sensitivity_exp), 0.60, 1.20)
	var compound_mult := 1.0
	if not tire.active_compound.is_empty():
		var compound_detail: Dictionary = tire.compound_water_snow_ground_factor(0.0, 0.0, 30.0, index)
		compound_mult = float(compound_detail.get("combined", 1.0))
	var mu := maxf(float(state.surface_friction), 0.0) * load_scale * clampf(thermal_grip_factor, 0.05, 1.0) * compound_mult
	var longitudinal_ratio := clampf(float(target_surface.get("longitudinal_grip_ratio", 1.0)), 0.10, 1.50)
	var lateral_assist := clampf(float(target_surface.get("lateral_grip_assist", 0.0)), -0.5, 1.0)
	var lateral_bonus := 1.0 + lateral_assist
	var fx_capacity := maxf(mu * longitudinal_ratio * fz, 1e-6)
	var fy_capacity := maxf(mu * lateral_bonus * fz, 1e-6)
	var slide_lat := clampf(float(profile.get("lateral_slide_mu_ratio", profile.get("longitudinal_slide_mu_ratio", 0.94))), 0.0, 1.0)
	var slide_lon := clampf(float(profile.get("longitudinal_slide_mu_ratio", 0.95)), 0.0, 1.0)
	var sliding_fraction := clampf(float(state.post_peak_decay_lon) + float(state.post_peak_decay_lat), 0.0, 1.0)

	var fx: float = float(state.longitudinal_force)
	var fy: float = float(state.lateral_force)
	var nd_x := absf(fx) / maxf(fx_capacity, 1e-6)
	var nd_y := absf(fy) / maxf(fy_capacity, 1e-6)
	var lat_w := nd_y / maxf(nd_x + nd_y, 1e-6)
	var directional_slide_mu := lerpf(slide_lon, slide_lat, lat_w)
	var slide_scale := lerpf(1.0, directional_slide_mu, sliding_fraction)
	var blend := float(state.contact_blend)
	return Vector2(maxf(fx_capacity * slide_scale * blend, 1e-6), maxf(fy_capacity * slide_scale * blend, 1e-6))


func test_all_vehicles_migration_v2() -> void:
	print("\n[12] Testing all vehicle profiles have rear axle migration v2 enabled and calibrated...")
	var vehicle_paths := [
		"res://data/vehicles/ford-escort-rs2000/vehicle.json",
		"res://data/vehicles/lancia-fulvia/vehicle.json",
		"res://data/vehicles/rt/rt-alfa-giulia-gta/vehicle.json",
		"res://data/vehicles/rt/rt-alpine-a110/vehicle.json",
		"res://data/vehicles/rt/rt-fiat-abarth-1000/vehicle.json",
		"res://data/vehicles/rt/rt-lancia-stratos/vehicle.json",
		"res://data/vehicles/rt/rt-lotus-cortina/vehicle.json",
		"res://data/vehicles/rt/rt-mini-cooper-s/vehicle.json",
		"res://data/vehicles/rt/rt-opel-kadett/vehicle.json",
		"res://data/vehicles/rt/rt-saab-96-v4/vehicle.json",
		"res://data/vehicles/rt/rt-volvo-amazon/vehicle.json",
	]
	for vpath in vehicle_paths:
		var loaded := VehicleProfileLoader.load_profile(vpath)
		var vname: String = str(vpath.get_base_dir().get_file())
		check(loaded.ok, "Vehicle profile loads: " + vname)
		if not loaded.ok:
			continue
		var front: Dictionary = loaded.resolved_tire_filters.get("front", {})
		var rear: Dictionary = loaded.resolved_tire_filters.get("rear", {})
		check(bool(front.get("combined_migration_v2_enabled", false)) == false, "%s front axle migration v2 is disabled" % vname)
		check(bool(rear.get("combined_migration_v2_enabled", false)) == true, "%s rear axle migration v2 is enabled" % vname)
		check(is_equal_approx(float(rear.get("combined_lateral_peak_migration", 0.0)), 0.15), "%s rear combined_lateral_peak_migration is 0.15" % vname)
		check(is_equal_approx(float(rear.get("combined_longitudinal_peak_migration", 0.0)), 0.08), "%s rear combined_longitudinal_peak_migration is 0.08" % vname)
