extends SceneTree


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	print("STARTING DAMAGE SYSTEM CONTRACT...")
	test_profile_loading()
	test_damage_validation()
	test_thermal_damage_mechanics()
	test_oil_model()
	test_impact_zones()
	test_vfx_and_hud()
	print("ALL DAMAGE SYSTEM CONTRACT TESTS PASSED!")
	quit(0)


func test_profile_loading() -> void:
	var result := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	assert(bool(result.get("ok", false)), "Vehicle profile with damage domain must load successfully")
	var domains: Dictionary = result.get("domains", {})
	assert(domains.has("damage"), "Loaded profile must contain damage domain")
	var damage_doc: Dictionary = domains["damage"]
	assert(damage_doc.has("collision") and damage_doc.has("landing") and damage_doc.has("thermal") and damage_doc.has("steam"), "damage.json must have all sections")
	var hashes: Dictionary = result.get("domain_hashes", {})
	assert(hashes.has("damage") or hashes.has("damage.json"), "domain_hashes must include damage")
	print("PASS: test_profile_loading")


func test_damage_validation() -> void:
	# Test schema validation failure on invalid domain
	var bad_collision := {"schema_version": 1, "collision": {"minimum_speed_m_s": 10.0, "full_severity_speed_m_s": 5.0}}
	var res1 := VehicleProfileLoader._validate_damage_domain(bad_collision)
	assert(not bool(res1.get("ok", false)), "Should reject minimum_speed >= full_severity_speed")

	var bad_thermal := {
		"schema_version": 1,
		"collision": {"minimum_speed_m_s": 2.0, "full_severity_speed_m_s": 10.0, "maximum_radiator_damage": 0.5, "maximum_engine_damage": 0.3, "severity_exponent": 1.0, "zone_weights": {}},
		"landing": {"minimum_speed_m_s": 2.0, "full_severity_speed_m_s": 10.0, "maximum_radiator_damage": 0.5, "maximum_engine_damage": 0.3, "severity_exponent": 1.0, "zone_weights": {}},
		"thermal": {"minimum_cooling_factor": 0.0, "minimum_torque_factor": 0.6, "damage_start_c": 110.0, "full_rate_temperature_c": 120.0, "grace_seconds": 6.0, "maximum_damage_per_second": 0.015},
		"steam": {"start_damage": 0.25, "continuous_damage": 0.50, "heavy_damage": 0.75}
	}
	var res2 := VehicleProfileLoader._validate_damage_domain(bad_thermal)
	assert(not bool(res2.get("ok", false)), "Should reject minimum_cooling_factor <= 0")
	print("PASS: test_damage_validation")


func test_thermal_damage_mechanics() -> void:
	var profile := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	var domains: Dictionary = profile["domains"]
	var model := VehicleThermalModel.new()
	model.configure(domains)

	assert(model.radiator_damage == 0.0, "Initial radiator damage must be 0")
	assert(model.engine_damage == 0.0, "Initial engine damage must be 0")
	assert(model.overheat_exposure_s == 0.0, "Initial overheat exposure must be 0")

	# Apply damage
	model.apply_damage(0.40, 0.15)
	assert(absf(model.radiator_damage - 0.40) < 0.001, "Radiator damage must equal applied value")
	assert(absf(model.engine_damage - 0.15) < 0.001, "Engine damage must equal applied value")

	# Snapshot verification
	var snap := model.get_engine_thermal_state_snapshot()
	assert(absf(float(snap["radiator_damage_percent"]) - 40.0) < 0.1, "Snapshot percent must match")
	assert(absf(float(snap["engine_damage_percent"]) - 15.0) < 0.1, "Snapshot percent must match")

	# Advance engine below overheat threshold (water temp 85 C): no exposure or permanent damage
	var prev_engine_dmg := model.engine_damage
	model.advance_engine(0.016, 5000.0, 100.0, 20.0, 1.2)
	assert(model.overheat_exposure_s == 0.0, "No overheat exposure when water temp is normal")
	assert(model.engine_damage == prev_engine_dmg, "No permanent damage accumulation below threshold")

	# Overheat testing: force water temperature to 115 C
	model.water_temperature_c = 115.0
	# Advance 4 seconds (less than grace_seconds = 6.0)
	for i in 250:
		model.advance_engine(0.016, 5000.0, 100.0, 20.0, 1.2)
		model.water_temperature_c = 115.0 # hold hot
	assert(model.overheat_exposure_s > 3.8 and model.overheat_exposure_s <= 4.1, "Overheat exposure should accumulate to ~4s")
	assert(model.engine_damage == prev_engine_dmg, "Within 6s grace period, no extra permanent damage")

	# Advance 3 more seconds (> 6s grace): damage must now accumulate
	for i in 187:
		model.advance_engine(0.016, 5000.0, 100.0, 20.0, 1.2)
		model.water_temperature_c = 115.0
	assert(model.engine_damage > prev_engine_dmg, "Permanent engine damage must accumulate past grace period")

	# Cooling recovery test: cool down at idle
	model.water_temperature_c = 85.0
	model.engine_block_temperature_c = 85.0
	var frozen_damage := model.engine_damage
	for i in 250:
		model.advance_engine(0.016, 900.0, 0.0, 30.0, 1.2)
	assert(model.overheat_exposure_s == 0.0, "Overheat exposure counter must recover to 0")
	assert(model.engine_damage == frozen_damage, "Permanent damage is preserved upon cooling")

	# Torque floor test under maximum damage
	model.radiator_damage = 1.0
	model.engine_damage = 1.0
	model.water_temperature_c = 125.0
	model.oil_temperature_c = 150.0
	model._update_torque_derating()
	assert(model.available_engine_torque_fraction >= 0.599, "Torque must not drop below minimum floor (0.60)")
	assert(model.available_engine_torque_fraction <= 0.601, "Torque at max damage and critical temp must be at floor (0.60)")

	# Reset for stage test
	model.reset_for_stage(domains)
	assert(model.radiator_damage == 0.0 and model.engine_damage == 0.0, "reset_for_stage must reset damage to 0")
	print("PASS: test_thermal_damage_mechanics")


func test_oil_model() -> void:
	var profile := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	var domains: Dictionary = profile["domains"]
	assert(not domains["powertrain"]["powertrain"]["thermal"].has("oil_cooling_duct"), "oil_cooling_duct must be removed")

	# Presion: ralentí caliente sano, aceite muy caliente, motor dañado.
	var model := VehicleThermalModel.new()
	model.configure(domains)
	model.oil_temperature_c = 90.0
	for i in 200:
		model._update_oil_pressure(1000.0, 0.02)
	assert(model.oil_pressure_bar > 1.1 and model.oil_pressure_bar < 1.3, "Hot idle pressure ~1.2 bar, got %f" % model.oil_pressure_bar)
	assert(model.oil_pressure_state() == "ok", "Healthy hot idle must be ok")
	model.oil_temperature_c = 130.0
	for i in 200:
		model._update_oil_pressure(1000.0, 0.02)
	assert(model.oil_pressure_bar < 0.8 and model.oil_pressure_state() == "critical", "Very hot oil at idle must be critical")
	model.oil_temperature_c = 90.0
	model.engine_damage = 1.0
	for i in 200:
		model._update_oil_pressure(3000.0, 0.02)
	assert(absf(model.oil_pressure_bar - 3.6 * 0.65) < 0.05, "Full engine damage must cost 35%% pressure, got %f" % model.oil_pressure_bar)
	model.engine_damage = 0.0
	for i in 200:
		model._update_oil_pressure(7000.0, 0.02)
	assert(absf(model.oil_pressure_bar - 4.0) < 0.05, "Relief valve must cap at 4 bar")

	# Acoplamiento: el aceite sigue al agua y un radiador dañado lo calienta.
	var results := {}
	for damage in [0.0, 1.0]:
		var m := VehicleThermalModel.new()
		m.configure(domains)
		m.radiator_damage = damage
		for i in 6000:
			m.advance_engine(0.02, 5500.0, 120.0, 15.0, 1.2)
		results[damage] = [m.water_temperature_c, m.oil_temperature_c]
	print("OIL/WATER healthy=", results[0.0], " damaged=", results[1.0])
	assert(results[1.0][1] > results[0.0][1] + 5.0, "Damaged radiator must raise oil temperature")
	assert(results[0.0][1] >= results[0.0][0] - 2.0, "Under load oil must not run much colder than water")
	print("PASS: test_oil_model")


func test_impact_zones() -> void:
	var vehicle := RallyEscortVehicle.new()
	# Test impact zone resolver
	assert(vehicle._resolve_impact_zone(Vector3(0.0, 0.35, -1.5), Vector3(0, 0, 1)) == "nose", "Must resolve nose")
	assert(vehicle._resolve_impact_zone(Vector3(0.0, 0.18, -0.8), Vector3(0, 1, 0)) == "front_underbody", "Must resolve front_underbody")
	assert(vehicle._resolve_impact_zone(Vector3(0.75, 0.4, 0.0), Vector3(-1, 0, 0)) == "side", "Must resolve side")
	assert(vehicle._resolve_impact_zone(Vector3(0.0, 0.4, 1.6), Vector3(0, 0, -1)) == "rear", "Must resolve rear")
	vehicle.free()
	print("PASS: test_impact_zones")


func test_vfx_and_hud() -> void:
	# HUD verification
	var hud_class = load("res://scripts/rally/formula_hud_panels.gd")
	var hud = hud_class.new()
	assert(hud.DAMAGE_RECT == Rect2(1620, 482, 276, 116), "DAMAGE_RECT coordinates must match specification")
	assert(hud._damage_color(0.10) == hud.C_GREEN, "0-25% should be nominal green")
	assert(hud._damage_color(0.35) == hud.C_GOLD, "25-50% should be gold/amber")
	assert(hud._damage_color(0.60) == Color("#f08c35"), "50-75% should be warm orange")
	assert(hud._damage_color(0.85) == hud.C_ROSE, ">=75% should be critical rose/red")
	hud.free()

	# VFX Shader verification
	var shader = load("res://scripts/rally/rally_vehicle_vfx.gdshader")
	assert(shader != null, "VFX shader must load cleanly")
	print("PASS: test_vfx_and_hud")
