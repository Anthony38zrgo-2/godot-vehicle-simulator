extends SceneTree

var failures: Array[String] = []


func check(ok: bool, message: String = "") -> bool:
	if not ok:
		var msg := message if not message.is_empty() else "mechanical_overrev_missgear_contract assertion failed"
		failures.append(msg)
		push_error(msg)
	return ok


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	print("STARTING MECHANICAL OVERREV & MISSGEAR CONTRACT...")
	test_all_vehicle_damage_mechanical_schemas()
	test_high_rpm_wear_and_limiter_protection()
	test_coupled_overrev_and_gearbox_degradation()
	await test_missgear_audio_across_vehicles()
	if failures.is_empty():
		print("ALL MECHANICAL OVERREV & MISSGEAR CONTRACT TESTS PASSED!")
	else:
		print("MECHANICAL OVERREV & MISSGEAR CONTRACT FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)


func test_all_vehicle_damage_mechanical_schemas() -> void:
	var reg_file := FileAccess.open("res://data/vehicles/registry.json", FileAccess.READ)
	var registry: Dictionary = JSON.parse_string(reg_file.get_as_text()).get("vehicles", {})
	var checked := 0
	for vid in registry:
		var entry: Dictionary = registry[vid]
		var profile_slug := str(entry.get("Profile", ""))
		var manifest_path := "res://data/vehicles/" + profile_slug + "/vehicle.json"
		var loaded := VehicleProfileLoader.load_profile(manifest_path)
		check(bool(loaded.get("ok", false)), vid + ": profile loads: " + str(loaded.get("error", "")))
		if bool(loaded.get("ok", false)):
			var damage_doc: Dictionary = loaded["domains"].get("damage", {})
			check(damage_doc.has("mechanical"), vid + ": damage.json has mechanical section")
			var val := VehicleProfileLoader._validate_damage_domain(damage_doc)
			check(bool(val.get("ok", false)), vid + ": damage validation ok: " + str(val.get("error", "")))
			checked += 1
	check(checked >= 15, "Checked all registered vehicle profiles, got %d" % checked)
	print("PASS: test_all_vehicle_damage_mechanical_schemas (%d vehicles)" % checked)


func test_high_rpm_wear_and_limiter_protection() -> void:
	var profile := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	var domains: Dictionary = profile["domains"]
	var design_max_rpm := float(domains["powertrain"]["powertrain"]["max_rpm"])

	# 1. Lowered rev limiter (~10% below design_max_rpm -> ~6550 rpm) keeps engine below 0.92 * design_max_rpm
	var conservative := VehicleThermalModel.new()
	conservative.configure(domains)
	conservative.water_temperature_c = 88.0
	conservative.oil_temperature_c = 95.0
	for i in 200:
		conservative.advance_engine(0.05, design_max_rpm * 0.89, 150.0, 25.0, 1.2, 0.0, design_max_rpm, design_max_rpm * 0.89)
		conservative.water_temperature_c = 88.0
		conservative.oil_temperature_c = 95.0
	check(conservative.high_rpm_exposure_s == 0.0, "Lowered RPM limiter accumulates zero high_rpm_exposure_s")
	check(conservative.engine_damage == 0.0, "Lowered RPM limiter accumulates zero high-RPM engine damage")

	# 2. Stock redline running accumulates wear past grace_seconds (3.0s)
	var redline := VehicleThermalModel.new()
	redline.configure(domains)
	redline.water_temperature_c = 88.0
	redline.oil_temperature_c = 95.0
	for i in 200:
		redline.advance_engine(0.05, design_max_rpm * 0.99, 150.0, 25.0, 1.2, 0.0, design_max_rpm, design_max_rpm * 0.99)
		redline.water_temperature_c = 88.0
		redline.oil_temperature_c = 95.0
	check(redline.high_rpm_exposure_s > 3.0, "Sustained redline accumulates high_rpm_exposure_s")
	check(redline.engine_damage > 0.005, "Sustained redline causes engine_damage > 0.005, got %f" % redline.engine_damage)

	# 3. Cold oil accelerates high-RPM wear compared to warm oil
	var cold_oil := VehicleThermalModel.new()
	cold_oil.configure(domains)
	cold_oil.water_temperature_c = 88.0
	cold_oil.oil_temperature_c = 40.0
	for i in 200:
		cold_oil.advance_engine(0.05, design_max_rpm * 0.99, 150.0, 25.0, 1.2, 0.0, design_max_rpm, design_max_rpm * 0.99)
		cold_oil.water_temperature_c = 88.0
		cold_oil.oil_temperature_c = 40.0
	check(cold_oil.engine_damage > redline.engine_damage * 1.4, "Cold oil multiplies high-RPM engine wear")

	# 4. Stage reset clears exposure but preserves permanent damage
	var saved_dmg := redline.engine_damage
	redline.reset_for_stage(domains)
	check(redline.high_rpm_exposure_s == 0.0, "reset_for_stage clears high_rpm_exposure_s")
	check(is_equal_approx(redline.engine_damage, saved_dmg), "reset_for_stage preserves permanent engine_damage")

	# 5. Multiplier verification: MECHANICAL_ENGINE_DAMAGE_MULTIPLIER == 2.0 and engine_damage_multiplier scales 2x
	check(is_equal_approx(VehicleThermalModel.MECHANICAL_ENGINE_DAMAGE_MULTIPLIER, 2.0), "MECHANICAL_ENGINE_DAMAGE_MULTIPLIER is 2.0")
	var base_1x := VehicleThermalModel.new()
	base_1x.configure(domains)
	base_1x.mechanical_damage_config["engine_damage_multiplier"] = 0.5
	base_1x.water_temperature_c = 88.0
	base_1x.oil_temperature_c = 95.0
	for i in 200:
		base_1x.advance_engine(0.05, design_max_rpm * 0.99, 150.0, 25.0, 1.2, 0.0, design_max_rpm, design_max_rpm * 0.99)
		base_1x.water_temperature_c = 88.0
		base_1x.oil_temperature_c = 95.0
	check(is_equal_approx(saved_dmg, base_1x.engine_damage * 2.0), "2.0x multiplier doubles high-RPM engine damage")
	print("PASS: test_high_rpm_wear_and_limiter_protection")


func test_coupled_overrev_and_gearbox_degradation() -> void:
	var profile := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	var domains: Dictionary = profile["domains"]
	var pm := VehiclePowertrainModel.new()
	pm.configure(domains)
	var ref_rpm := pm.torque_curve_reference_rpm
	# Even if the ECU rev limiter is lowered by 10%, mechanical overrev uses torque_curve_reference_rpm
	pm.maximum_rpm = ref_rpm * 0.90

	# 1. Neutral / clutch open over-rev does NOT damage gearbox
	pm.current_gear = 0
	pm.engine_rpm = ref_rpm * 1.15
	pm.clutch_engagement = 0.0
	var zeros: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var inertias: Array[float] = [1.5, 1.5, 1.5, 1.5]
	var res_neutral := pm.solve_rotation(0.005, zeros.duplicate(), inertias, zeros, zeros)
	check(pm.transmission_damage == 0.0, "Neutral over-rev does not damage gearbox")
	check(float(res_neutral.get("engine_overrev_damage", 0.0)) == 0.0, "Neutral does not fire coupled overrev")

	# 2. Downshift synchronization into over-rev ("money shift" sync crunch) damages gearbox & triggers missgear
	pm.configure(domains)
	pm.current_gear = 2
	var high_ratio: float = pm.gear_ratios[0] * pm.final_drive_ratio
	var overrev_carrier := (ref_rpm * 1.18 * TAU / 60.0) / high_ratio
	var spins: Array[float] = [overrev_carrier, overrev_carrier, overrev_carrier, overrev_carrier]
	pm.input_shaft_omega_rad_s = (ref_rpm * 0.75) * TAU / 60.0
	pm.output_shaft_omega_rad_s = overrev_carrier
	pm.set_gear(1)
	# Advance until synchronizing phase
	for _i in 30:
		pm.advance(0.005, 0.0, 1.0, 1.0, overrev_carrier)
		if pm.shift_phase == "synchronizing":
			break
	check(pm.shift_phase == "synchronizing", "Entered synchronizing phase for downshift")
	var res_sync := pm.solve_rotation(0.005, spins.duplicate(), inertias, zeros, zeros)
	check(pm.transmission_damage > 0.0, "Synchronizing into over-rev damages transmission_damage, got %f" % pm.transmission_damage)
	check(bool(res_sync.get("missgear_active", false)), "Synchronizing into over-rev activates missgear")
	check(pm.consume_missgear_event(), "Missgear edge event queued")

	# 3. Coupled over-rev damages both engine and gearbox simultaneously
	pm.configure(domains)
	pm.current_gear = 1
	pm.clutch_engagement = 1.0
	pm.engine_rpm = ref_rpm * 1.18
	pm.input_shaft_omega_rad_s = ref_rpm * 1.18 * TAU / 60.0
	pm.output_shaft_omega_rad_s = overrev_carrier
	var total_eng_ov := 0.0
	for _i in 40:
		var r := pm.solve_rotation(0.005, spins.duplicate(), inertias, zeros, zeros)
		total_eng_ov += float(r.get("engine_overrev_damage", 0.0))
	check(total_eng_ov > 0.01, "Coupled over-rev outputs engine_overrev_damage, got %f" % total_eng_ov)
	check(pm.transmission_damage > 0.01, "Coupled over-rev damages gearbox transmission_damage, got %f" % pm.transmission_damage)

	var pm_half := VehiclePowertrainModel.new()
	pm_half.configure(domains)
	pm_half.mechanical_damage_config["engine_damage_multiplier"] = 0.5
	pm_half.current_gear = 1
	pm_half.clutch_engagement = 1.0
	pm_half.engine_rpm = ref_rpm * 1.18
	pm_half.input_shaft_omega_rad_s = ref_rpm * 1.18 * TAU / 60.0
	pm_half.output_shaft_omega_rad_s = overrev_carrier
	var half_eng_ov := 0.0
	for _i in 40:
		var r2 := pm_half.solve_rotation(0.005, spins.duplicate(), inertias, zeros, zeros)
		half_eng_ov += float(r2.get("engine_overrev_damage", 0.0))
	check(absf(total_eng_ov - half_eng_ov * 2.0) < 0.0005, "2.0x multiplier doubles missgear/over-rev engine damage")

	# 4. Degraded gearbox slows synchros under real speed & pops out of gear on hard shock
	var healthy := VehiclePowertrainModel.new()
	healthy.configure(domains)
	var damaged := VehiclePowertrainModel.new()
	damaged.configure(domains)
	damaged.transmission_damage = 0.90
	var drive_carrier := (4500.0 * TAU / 60.0) / high_ratio
	for m in [healthy, damaged]:
		m.current_gear = 2
		m.clutch_engagement = 1.0
		m.engine_rpm = 3500.0
		m.input_shaft_omega_rad_s = (2800.0 * TAU / 60.0)
		m.output_shaft_omega_rad_s = drive_carrier
		m.set_gear(1)
	var sync_ticks_healthy := 0
	var sync_ticks_damaged := 0
	for _i in 400:
		if healthy.shift_phase != "idle":
			healthy.advance(0.005, 0.0, 1.0, 1.0, drive_carrier)
			healthy.solve_rotation(0.005, [drive_carrier, drive_carrier, drive_carrier, drive_carrier], inertias, zeros, zeros)
			sync_ticks_healthy += 1
		if damaged.shift_phase != "idle":
			damaged.advance(0.005, 0.0, 1.0, 1.0, drive_carrier)
			damaged.solve_rotation(0.005, [drive_carrier, drive_carrier, drive_carrier, drive_carrier], inertias, zeros, zeros)
			sync_ticks_damaged += 1
	check(sync_ticks_damaged > sync_ticks_healthy, "Damaged gearbox takes longer to shift/sync (%d > %d)" % [sync_ticks_damaged, sync_ticks_healthy])

	# Pop-out check at severe damage + overrev
	damaged.configure(domains)
	damaged.transmission_damage = 0.85
	damaged.current_gear = 1
	damaged.clutch_engagement = 1.0
	damaged.engine_rpm = ref_rpm * 1.15
	damaged.input_shaft_omega_rad_s = ref_rpm * 1.15 * TAU / 60.0
	damaged.output_shaft_omega_rad_s = overrev_carrier
	damaged.solve_rotation(0.005, spins.duplicate(), inertias, zeros, zeros)
	check(damaged.current_gear == 0, "Severely damaged gearbox pops out to neutral under over-rev")
	check(damaged.consume_missgear_event(), "Gear pop-out emits missgear event")
	print("PASS: test_coupled_overrev_and_gearbox_degradation")


func test_missgear_audio_across_vehicles() -> void:
	var stream := SeamlessVehicleLoop.load_pcm("res://sounds/banks/commons/missgear.wav", true)
	check(stream != null and stream.mix_rate == 44100 and not stream.stereo, "commons/missgear.wav loads as 44.1 kHz mono PCM16")

	var policy := VehicleAudioMixPolicy.new()
	var pkt := {
		"generation": 1,
		"sequence": 1,
		"dt_s": 0.016,
		"rpm": 7600.0,
		"rpm_max": 7300.0,
		"throttle": 0.0,
		"gear": 1,
		"missgear": true,
		"missgear_intensity": 0.9,
		"missgear_event": true,
		"wheels": [],
	}
	var mix := policy.accept(pkt)
	check(bool(mix.get("missgear", false)), "Mix policy propagates missgear state")
	check((mix.get("events", []) as Array).has("missgear"), "Mix policy emits missgear event")

	var reg_file := FileAccess.open("res://data/vehicles/registry.json", FileAccess.READ)
	var registry: Dictionary = JSON.parse_string(reg_file.get_as_text()).get("vehicles", {})
	for vid in ["escort", "fulvia", "rt-alfa-giulia-gta"]:
		var entry: Dictionary = registry[vid]
		var scene_path := "res://scenes/rally/" + str(entry.get("Proving", "")) + ".tscn"
		var packed: PackedScene = load(scene_path)
		var session := packed.instantiate()
		root.add_child(session)
		current_scene = session
		for _f in 30:
			await physics_frame
			if session.get("session_ready") == true:
				break
		var vehicle = session.get("vehicle")
		var audio = vehicle.get_node_or_null("VehicleAudio") if vehicle != null else null
		check(audio != null, vid + ": VehicleAudio node present")
		if audio != null:
			check(audio.missgear_player != null and audio.missgear_player.stream != null, vid + ": missgear_player loaded from commons")
			audio.set_physics_process(false)
			audio.acoustic = {"missgear": true, "missgear_intensity": 0.9, "rpm": 7600.0, "rpm_max": 7300.0}
			audio.missgear_hold_s = 0.5
			audio.update_missgear_audio(1.0)
			check(not audio.missgear_player.stream_paused and audio.missgear_player.volume_linear > 0.01, vid + ": missgear_player plays audibly when active")
		session.queue_free()
		await process_frame
	print("PASS: test_missgear_audio_across_vehicles")
