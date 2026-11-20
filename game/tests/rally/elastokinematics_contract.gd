extends SceneTree
## elastokinematics_contract.gd
##
## Contrato de elastocinemática (flexión filtrada de silentblocks/brazos):
##  1. Defaults por arquitectura (MacPherson > double wishbone >> eje rígido en caída).
##  2. Signos exactos de compliance steer lateral (subviraje elástico delante y
##     estabilización coherente detrás) y compliance camber (+caída en rueda exterior).
##  3. Signos de frenada longitudinal: toe-out simétrico delante, cero en frenada
##     simétrica sobre eje rígido y guiñada coherente del puente en split-mu.
##  4. Filtro exponencial de primer orden (τ ≈ 20-24 ms): 1 - 1/e en t = τ,
##     invarianza al tamaño de subpaso y topes ante picos extremos.
##  5. Comparativa dinámica real en escena (Escort RS2000, ON vs OFF) en curva y frenada.
##
## Ejecución:
##   godot --headless --path game --script res://tests/rally/elastokinematics_contract.gd

var failures: Array[String] = []


func check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		push_error("FAIL: " + msg)
	else:
		print("  PASS: " + msg)


func _initialize() -> void:
	call_deferred("run")


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _configure_vehicle(profile_path: String, asset_path: String) -> FordRallyVehicleSimulation:
	var sim := FordRallyVehicleSimulation.new()
	var res := sim.configure(_load_json(asset_path), profile_path)
	if not bool(res.get("ok", false)):
		push_error("configure failed: " + str(res.get("error", "")))
		return null
	return sim


func test_architecture_defaults() -> void:
	print("\n[1] Defaults elastocinemáticos por arquitectura...")
	var escort := _configure_vehicle(
		"res://data/vehicles/ford-escort-rs2000/vehicle.json",
		"res://assets/rally/ford_escort_rs2000_1971/manifest.json",
	)
	var fulvia := _configure_vehicle(
		"res://data/vehicles/lancia-fulvia/vehicle.json",
		"res://assets/rally/lancia_fulvia/manifest.json",
	)
	check(escort != null and fulvia != null, "Escort y Fulvia configuran")
	if escort == null or fulvia == null:
		return
	var ef: Dictionary = escort.suspension_model.axle_parameters[0]
	var er: Dictionary = escort.suspension_model.axle_parameters[2]
	var ff: Dictionary = fulvia.suspension_model.axle_parameters[0]
	check(float(ef["compliance_camber_lat_rad_per_n"]) > float(ff["compliance_camber_lat_rad_per_n"]),
		"MacPherson flexa más en caída que doble horquilla")
	check(float(ff["compliance_camber_lat_rad_per_n"]) > float(er["compliance_camber_lat_rad_per_n"]) * 2.0,
		"Eje rígido trasero tiene rigidez de caída muy superior a independiente")
	check(float(ef["compliance_tau_s"]) >= 0.015 and float(ef["compliance_tau_s"]) <= 0.030,
		"Constante de tiempo silentblocks en 15-30 ms (%.1f ms)" % (float(ef["compliance_tau_s"]) * 1000.0))


func test_lateral_and_longitudinal_signs() -> void:
	print("\n[2] Signos de compliance steer y compliance camber (lateral y frenada)...")
	var escort := _configure_vehicle(
		"res://data/vehicles/ford-escort-rs2000/vehicle.json",
		"res://assets/rally/ford_escort_rs2000_1971/manifest.json",
	)
	if escort == null:
		return
	var susp := escort.suspension_model
	var zero: Array[float] = [0.0, 0.0, 0.0, 0.0]

	# Giro a izquierda (Fy < 0), régimen estacionario (dt = 0 -> asignación directa).
	var lat_l: Array[float] = [-1500.0, -3500.0, -1400.0, -3200.0]
	susp.step_elastokinematics(0.0, lat_l, zero)
	check(susp.compliance_toe_rad[0] < 0.0 and susp.compliance_toe_rad[1] < 0.0,
		"Giro izq delantero: subviraje elástico abre hacia derecha (<0: FL=%.4f FR=%.4f deg)" % [
			rad_to_deg(susp.compliance_toe_rad[0]), rad_to_deg(susp.compliance_toe_rad[1])])
	check(absf(susp.compliance_toe_rad[1]) > absf(susp.compliance_toe_rad[0]),
		"Rueda exterior más cargada flexa más en convergencia")
	check(susp.compliance_toe_rad[2] > 0.0 and absf(susp.compliance_toe_rad[2] - susp.compliance_toe_rad[3]) < 1.0e-7,
		"Giro izq trasero eje rígido: puente acompaña coherentemente hacia izquierda (+%.4f deg)" % rad_to_deg(susp.compliance_toe_rad[2]))
	check(susp.compliance_camber_rad[1] > 0.0 and susp.compliance_camber_rad[0] < 0.0,
		"Giro izq caída AXLE-FRAME: exterior FR gana +camber (+%.3f deg), interior FL -camber (%.3f deg)" % [
			rad_to_deg(susp.compliance_camber_rad[1]), rad_to_deg(susp.compliance_camber_rad[0])])

	# Verificar espejo izquierda/derecha (giro a derecha Fy > 0).
	var toe_l := susp.compliance_toe_rad.duplicate()
	var cam_l := susp.compliance_camber_rad.duplicate()
	var lat_r: Array[float] = [3500.0, 1500.0, 3200.0, 1400.0]
	susp.clear_compliance_state()
	susp.step_elastokinematics(0.0, lat_r, zero)
	check(absf(susp.compliance_toe_rad[0] + float(toe_l[1])) < 1.0e-6 and absf(susp.compliance_toe_rad[1] + float(toe_l[0])) < 1.0e-6,
		"Simetría espejo exacta en compliance toe delantero")
	check(absf(susp.compliance_camber_rad[0] - float(cam_l[1])) < 1.0e-6 and absf(susp.compliance_camber_rad[1] - float(cam_l[0])) < 1.0e-6,
		"Simetría espejo exacta en compliance camber delantero")

	# Frenada simétrica (Fx < 0): delante toe-out simétrico (FL > 0 izq, FR < 0 der), detrás eje rígido = 0.
	susp.clear_compliance_state()
	var brake_sym: Array[float] = [-3200.0, -3200.0, -1800.0, -1800.0]
	susp.step_elastokinematics(0.0, zero, brake_sym)
	check(susp.compliance_toe_rad[0] > 0.0 and susp.compliance_toe_rad[1] < 0.0 and absf(susp.compliance_toe_rad[0] + susp.compliance_toe_rad[1]) < 1.0e-6,
		"Frenada simétrica delantera: toe-out simétrico (FL=+%.3f deg, FR=%.3f deg)" % [
			rad_to_deg(susp.compliance_toe_rad[0]), rad_to_deg(susp.compliance_toe_rad[1])])
	check(absf(susp.compliance_toe_rad[2]) < 1.0e-7 and absf(susp.compliance_toe_rad[3]) < 1.0e-7,
		"Frenada simétrica en eje rígido trasero: convergencia nula (tubo rígido)")

	# Frenada asimétrica (split-mu) en eje rígido: puente gira coherentemente.
	susp.clear_compliance_state()
	var brake_asym: Array[float] = [0.0, 0.0, -3000.0, -500.0]
	susp.step_elastokinematics(0.0, zero, brake_asym)
	check(susp.compliance_toe_rad[2] > 0.0 and absf(susp.compliance_toe_rad[2] - susp.compliance_toe_rad[3]) < 1.0e-7,
		"Frenada split-mu en eje rígido: guiñada elástica coherente del puente (+%.4f deg)" % rad_to_deg(susp.compliance_toe_rad[2]))

	# Integración con dynamic_camber / dynamic_toe y compatibilidad en cero.
	var c_with := susp.dynamic_camber(0)
	susp.clear_compliance_state()
	var c_zero := susp.dynamic_camber(0)
	check(absf(c_zero - float(susp.axle_parameters[0].camber)) < 1.0e-7, "Con estado a cero dynamic_camber conserva valor base exacto")
	check(absf(c_with - c_zero) < 1.0e-7, "Sin fuerza en FL, camber base intacto")


func test_first_order_filter_and_clamps() -> void:
	print("\n[3] Filtro exponencial de primer orden (τ), invarianza de subpaso y topes...")
	var escort := _configure_vehicle(
		"res://data/vehicles/ford-escort-rs2000/vehicle.json",
		"res://assets/rally/ford_escort_rs2000_1971/manifest.json",
	)
	if escort == null:
		return
	var susp := escort.suspension_model
	var tau := float(susp.axle_parameters[0]["compliance_tau_s"])
	var lat: Array[float] = [0.0, -3000.0, 0.0, 0.0]
	var zero: Array[float] = [0.0, 0.0, 0.0, 0.0]

	# 10 pasos de tau/10 -> debe alcanzar 1 - 1/e ≈ 0.63212 del objetivo.
	susp.clear_compliance_state()
	for _k in 10:
		susp.step_elastokinematics(tau / 10.0, lat, zero)
	var ratio_10 := susp.compliance_camber_rad[1] / maxf(absf(susp.compliance_camber_target_rad[1]), 1.0e-9)
	var exp_1_e := 1.0 - exp(-1.0)
	check(absf(ratio_10 - exp_1_e) < 0.002, "En t=τ alcanza 1-1/e (got %.5f exp %.5f)" % [ratio_10, exp_1_e])

	# 100 pasos de tau/100 -> invarianza exacta al subpaso.
	var val_10 := susp.compliance_camber_rad[1]
	susp.clear_compliance_state()
	for _k in 100:
		susp.step_elastokinematics(tau / 100.0, lat, zero)
	var val_100 := susp.compliance_camber_rad[1]
	check(absf(val_100 - val_10) < 1.0e-6, "Invarianza al tamaño de subpaso (10 pasos=%.6f vs 100 pasos=%.6f)" % [val_10, val_100])

	# Topes ante impacto extremo de 50 kN.
	susp.clear_compliance_state()
	var extreme_lat: Array[float] = [-50000.0, -50000.0, -50000.0, -50000.0]
	susp.step_elastokinematics(0.0, extreme_lat, extreme_lat)
	for i in 4:
		check(absf(susp.compliance_toe_rad[i]) <= VehicleSuspensionModel.MAX_COMPLIANCE_TOE_RAD + 1.0e-6,
			"Rueda %d compliance toe acotado a ±%.3f rad" % [i, VehicleSuspensionModel.MAX_COMPLIANCE_TOE_RAD])
		check(absf(susp.compliance_camber_rad[i]) <= VehicleSuspensionModel.MAX_COMPLIANCE_CAMBER_RAD + 1.0e-6,
			"Rueda %d compliance camber acotado a ±%.3f rad" % [i, VehicleSuspensionModel.MAX_COMPLIANCE_CAMBER_RAD])


func _run_proving_maneuver(maneuver: String, elasto_enabled: bool) -> Dictionary:
	var scene = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for _i in 240:
		await physics_frame
		if scene.session_ready:
			break
	if not scene.session_ready:
		scene.queue_free()
		await process_frame
		return {"ok": false}
	var vehicle = scene.vehicle
	scene.input_controller.set_physics_process(false)
	var sim: FordRallyVehicleSimulation = vehicle.simulation
	sim.elastokinematics_enabled = elasto_enabled
	vehicle.throttle_input = 0.0
	vehicle.brake_input = 0.0
	vehicle.steering_input = 0.0
	vehicle.handbrake_input = 0.0
	for _i in 90:
		await physics_frame
	var base_pose: Transform3D = vehicle.global_transform
	vehicle._reset_to_transform(base_pose)
	vehicle.freeze = false
	vehicle._reset_pending = false
	sim.elastokinematics_enabled = elasto_enabled
	sim.powertrain_model.set_gear(2)

	var fwd_vel := -base_pose.basis.z * (18.0 if maneuver == "corner" else 22.0)
	vehicle.linear_velocity = fwd_vel
	var cs := PhysicsServer3D.body_get_direct_state(vehicle.get_rid())
	if cs != null:
		cs.linear_velocity = fwd_vel
	for w in 4:
		sim.wheel_spins[w] = fwd_vel.length() / maxf(sim.wheel_radii[w], 0.1)
		sim.tire_belt_spins[w] = sim.wheel_spins[w]
	sim.powertrain_model.engine_rpm = 3500.0
	sim.powertrain_model.clutch_engagement = 1.0

	var max_fr_toe_deg := 0.0
	var max_fr_cam_deg := 0.0
	var max_brake_toe_out_deg := 0.0
	var max_rear_brake_toe_deg := 0.0
	var peak_yaw_rate := 0.0
	var peak_yaw_accel := 0.0
	var prev_yaw := 0.0
	var finite_ok := true
	var total_ticks := 80 if maneuver == "corner" else 60
	for t in total_ticks:
		if maneuver == "corner":
			vehicle.throttle_input = 0.25
			vehicle.brake_input = 0.0
			vehicle.steering_input = clampf(float(t) / 10.0, 0.0, 1.0) * 0.45
		else:
			vehicle.throttle_input = 0.0
			vehicle.brake_input = clampf(float(t) / 6.0, 0.0, 1.0) * 0.85
			vehicle.steering_input = 0.0
		await physics_frame
		var yr := absf(vehicle.angular_velocity.y)
		if not is_finite(yr):
			finite_ok = false
		peak_yaw_rate = maxf(peak_yaw_rate, yr)
		if t > 0:
			peak_yaw_accel = maxf(peak_yaw_accel, absf(yr - prev_yaw) * float(Engine.physics_ticks_per_second))
		prev_yaw = yr
		max_fr_toe_deg = maxf(max_fr_toe_deg, absf(rad_to_deg(sim.suspension_model.compliance_toe_rad[1])))
		max_fr_cam_deg = maxf(max_fr_cam_deg, rad_to_deg(sim.suspension_model.compliance_camber_rad[1]))
		var brake_toe_out := rad_to_deg(0.5 * (sim.suspension_model.compliance_toe_rad[0] - sim.suspension_model.compliance_toe_rad[1]))
		max_brake_toe_out_deg = maxf(max_brake_toe_out_deg, brake_toe_out)
		max_rear_brake_toe_deg = maxf(max_rear_brake_toe_deg, absf(rad_to_deg(sim.suspension_model.compliance_toe_rad[2])))

	scene.queue_free()
	await process_frame
	return {
		"ok": true,
		"finite_ok": finite_ok,
		"max_fr_toe_deg": max_fr_toe_deg,
		"max_fr_cam_deg": max_fr_cam_deg,
		"max_brake_toe_out_deg": max_brake_toe_out_deg,
		"max_rear_brake_toe_deg": max_rear_brake_toe_deg,
		"peak_yaw_rate": peak_yaw_rate,
		"peak_yaw_accel": peak_yaw_accel,
	}


func test_dynamic_scene_comparisons() -> void:
	print("\n[4] Comparativa dinámica real en escena (Escort RS2000, ON vs OFF)...")
	var c_off := await _run_proving_maneuver("corner", false)
	var c_on := await _run_proving_maneuver("corner", true)
	check(bool(c_off.get("ok", false)) and bool(c_on.get("ok", false)), "Escena curva ejecutada ON y OFF")
	check(bool(c_on.get("finite_ok", false)), "Curva ON numéricamente finita")
	check(float(c_on["max_fr_toe_deg"]) > 0.15 and float(c_on["max_fr_toe_deg"]) < 1.5,
		"Curva: compliance toe FR realista (%.3f deg)" % float(c_on["max_fr_toe_deg"]))
	check(float(c_on["max_fr_cam_deg"]) > 0.30 and float(c_on["max_fr_cam_deg"]) < 2.6,
		"Curva: compliance camber FR exterior positivo realista (+%.3f deg)" % float(c_on["max_fr_cam_deg"]))
	check(float(c_off["max_fr_toe_deg"]) < 1.0e-5 and absf(float(c_off["max_fr_cam_deg"])) < 1.0e-5,
		"Curva OFF mantiene compliance exactamente en 0")
	check(float(c_on["peak_yaw_accel"]) <= float(c_off["peak_yaw_accel"]) * 1.02,
		"Curva: transición de guiñada redondeada (peak yaw accel ON=%.2f <= OFF=%.2f rad/s²)" % [
			float(c_on["peak_yaw_accel"]), float(c_off["peak_yaw_accel"])])

	var b_on := await _run_proving_maneuver("brake", true)
	check(bool(b_on.get("ok", false)) and bool(b_on.get("finite_ok", false)), "Frenada ON ejecutada y finita")
	check(float(b_on["max_brake_toe_out_deg"]) > 0.05 and float(b_on["max_brake_toe_out_deg"]) < 0.8,
		"Frenada: toe-out elástico delantero medido (%.3f deg)" % float(b_on["max_brake_toe_out_deg"]))
	check(float(b_on["max_rear_brake_toe_deg"]) < 0.05,
		"Frenada recta en eje rígido trasero: deriva elástica mínima (%.4f deg)" % float(b_on["max_rear_brake_toe_deg"]))


func run() -> void:
	print("=== ELASTOKINEMATICS CONTRACT ===")
	test_architecture_defaults()
	test_lateral_and_longitudinal_signs()
	test_first_order_filter_and_clamps()
	await test_dynamic_scene_comparisons()
	print("\nELASTOKINEMATICS_CONTRACT ", "PASS" if failures.is_empty() else "FAIL")
	if not failures.is_empty():
		for f in failures:
			print("  - ", f)
	quit(0 if failures.is_empty() else 1)
