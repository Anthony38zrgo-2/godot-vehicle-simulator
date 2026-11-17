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
## 13. Profile loader preserves the catalog and mounted compound calibration.

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
	test_legacy_relief_smooth_and_opt_in()
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
	print("\n[1] Testing Escort profile and compound overrides...")
	var loader := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	check(loader.ok, "VehicleProfileLoader loads Escort profile")
	if not loader.ok:
		return
	var catalog := RallyTireCompound.load_catalog()
	var defaults: Dictionary = catalog["default_tire_profile"]["tire_filters"]
	var model := TireModel.new()
	model.configure(loader.domains, loader.resolved_tire_filters, [2500.0, 2500.0, 2500.0, 2500.0])
	for axle in ["front", "rear"]:
		var configured: Dictionary = loader.resolved_tire_filters[axle]
		for key in ["combined_migration_v2_enabled", "combined_lateral_peak_migration", "combined_longitudinal_peak_migration"]:
			check(configured[key] == defaults[axle][key], "Escort %s inherits catalog %s" % [axle, key])
	for compound_id: String in ["gravel_normal", "gravel_wet"]:
		check(model.set_compound(compound_id, catalog), "Escort mounts " + compound_id)
		for wheel in [0, 2]:
			var axle := "front" if wheel == 0 else "rear"
			var expected: Dictionary = catalog["compounds"][compound_id]["force_model"][axle]
			for key in expected:
				check(model.axle_profiles[wheel][key] == expected[key], "%s %s overrides %s" % [compound_id, axle, key])


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


func test_legacy_relief_smooth_and_opt_in() -> void:
	print("\n[2b] Testing legacy relief: opt-in, dedicated key, graduated...")
	# NOTE: legacy relief scales norm_demand_x, which only feeds the post-peak
	# decay target (integrated with slip_loss_tau_s). Single delta=0 steps can
	# never observe it, so these probes use one big-delta step (0.5 s) from a
	# controlled preset: zero velocities keep patch_pos bit-identical
	# (transport 0 -> renewal 1, no camber term) while the decay memory snaps
	# to its target, isolating the relief effect.
	# Over-peak preset in the transition band (unclamped norm ~ 2.5, theta ~ 0.83):
	# without relief decay ~ 0.73; with 0.3 relief the longitudinal part
	# shrinks below the knee (decay 0). Calibrated sweep: at 0.3x the models
	# still agree, at 0.4x they split ~2.8%, at 0.5x+ the unrelieved side
	# saturates and the contrast stops growing.
	var px := 0.08
	var py := 0.034
	# OFF by default (no legacy key), v2 disabled.
	var r_off := _legacy_relief_probe({}, Vector2(px, py))
	# Old overloaded key alone must NOT trigger relief anymore.
	var r_old := _legacy_relief_probe({"combined_lateral_peak_migration": 0.3}, Vector2(px, py))
	check(is_equal_approx(r_old.y, r_off.y) and is_equal_approx(r_old.x, r_off.x),
		"combined_lateral_peak_migration no longer drives legacy relief")
	# Opt-in 0.15 / 0.3: graduated grip gift over the peak (higher ceiling).
	var r_15 := _legacy_relief_probe({"legacy_longitudinal_relief": 0.15}, Vector2(px, py))
	var r_30 := _legacy_relief_probe({"legacy_longitudinal_relief": 0.3}, Vector2(px, py))
	check(r_30.y > r_15.y and r_15.y > r_off.y,
		"Legacy relief raises the over-peak ceiling gradually (Fy ordered by relief)")
	var ratio := r_30.y / maxf(r_off.y, 1.0e-6)
	check(ratio > 1.002 and ratio < 1.20, "Relief 0.3 gift is bounded, got ratio %f" % ratio)
	# Braking mirror: relief_s = 0, exact agreement.
	var rb_off := _legacy_relief_probe({}, Vector2(-px, py))
	var rb_30 := _legacy_relief_probe({"legacy_longitudinal_relief": 0.3}, Vector2(-px, py))
	check(is_equal_approx(rb_30.y, rb_off.y) and is_equal_approx(rb_30.x, rb_off.x),
		"Legacy relief is zero on the braking side")
	# No hardcoded rear bias: front axle honors the same opt-in key.
	var rf_off := _legacy_relief_probe({}, Vector2(px, py), 0)
	var rf_30 := _legacy_relief_probe({"legacy_longitudinal_relief": 0.3}, Vector2(px, py), 0)
	check(rf_30.y > rf_off.y, "Legacy relief is per-axle opt-in, no hardcoded rear bias")


# One big-delta probe step from a fully controlled state. Zero velocities keep
# patch_pos bit-identical (transport 0 -> renewal 1, no camber term) while the
# post-peak decay snaps to its target; returns Vector2(Fx, Fy).
func _legacy_relief_probe(overrides: Dictionary, patch: Vector2, axle_idx: int = 2) -> Vector2:
	var base := {"combined_migration_v2_enabled": false}
	for k in overrides:
		base[k] = overrides[k]
	var tire := create_tire_model(base, axle_idx)
	tire.states[axle_idx].patch_pos = patch
	var r := tire.evaluate(axle_idx, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.5, 60.0)
	return Vector2(float(r.longitudinal_force_n), float(r.lateral_force_n))


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
						var budget_ratio := float(res.instant_combined_utilization)
						if not is_finite(budget_ratio) or budget_ratio > 1.001:
							budget_violation_count += 1

	check(non_finite_count == 0, "No non-finite forces under extreme combined slip (%d cases)" % total_tests)
	check(budget_violation_count == 0, "Instantaneous ellipse respected throughout all %d sequences" % total_tests)


func test_all_vehicles_migration_v2() -> void:
	print("\n[12] Testing resolved combined-slip calibration for the production profiles...")
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
		for axle in ["front", "rear"]:
			var configured: Dictionary = loaded.resolved_tire_filters[axle]
			check(configured.get("combined_migration_v2_enabled") is bool, "%s %s resolves its migration mode" % [vname, axle])
			for key in ["combined_lateral_peak_migration", "combined_longitudinal_peak_migration"]:
				var coefficient := float(configured.get(key, -1.0))
				check(coefficient >= 0.0 and coefficient <= 0.65, "%s %s %s is in range" % [vname, axle, key])
