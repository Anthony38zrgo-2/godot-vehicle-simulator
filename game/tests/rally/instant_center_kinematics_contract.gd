extends SceneTree
## instant_center_kinematics_contract.gd
##
## Contrato de cinemática de centros instantáneos:
##  1. Descomposición exacta de Roll Center (elástico h_CG - h_RC vs geométrico h_RC)
##     y diferenciación entre suspensión independiente (jacking neto vertical)
##     y eje rígido (par puro izquierda-derecha sin expansión de vía).
##  2. Migración dinámica del Roll Center con compresión (roll_center_height_gain).
##  3. Pitch Center: Anti-Dive delantero (frenada), Anti-Squat trasero (tracción)
##     y Anti-Lift (tracción delantera / frenada trasera).
##  4. No doble conteo con axis_pitch_rad / axis_roll_rad explícitos.
##  5. Comparativa dinámica real en escena (Escort RS2000, Jolt + rig 10-DOF):
##     curva (menor roll + transferencia inicial más rápida), frenada (anti-dive)
##     y aceleración (anti-squat) comparando ON vs OFF.
##
## Ejecución:
##   godot --headless --path game --script res://tests/rally/instant_center_kinematics_contract.gd

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


func test_architecture_defaults_and_rc_migration() -> void:
	print("\n[1] Defaults por arquitectura y migración dinámica de Roll Center...")
	var escort := _configure_vehicle(
		"res://data/vehicles/ford-escort-rs2000/vehicle.json",
		"res://assets/rally/ford_escort_rs2000_1971/manifest.json",
	)
	check(escort != null, "Escort configura")
	if escort == null:
		return
	var pf: Dictionary = escort.suspension_model.axle_parameters[0]
	var pr: Dictionary = escort.suspension_model.axle_parameters[2]
	check(not bool(pf["solid_axle"]), "Escort delantero MacPherson es independiente")
	check(bool(pr["solid_axle"]), "Escort trasero live_axle_leaf es eje rígido")
	check(float(pr["roll_center_height_m"]) > float(pf["roll_center_height_m"]), "Escort RC trasero > RC delantero (eje de alabeo inclinado)")
	check(float(pf["anti_dive_tan"]) > 0.01, "Escort anti-dive delantero > 0")
	check(float(pr["anti_squat_tan"]) > 0.01, "Escort anti-squat trasero > 0")
	check(float(pr["anti_lift_tan"]) > 0.01, "Escort anti-lift trasero > 0")

	var rc_rest := escort.suspension_model.dynamic_roll_center_height_m(0, 0.0, 0.505)
	var rc_bump := escort.suspension_model.dynamic_roll_center_height_m(0, 0.08, 0.505)
	check(rc_bump < rc_rest - 0.02, "MacPherson RC desciende en compresión (rest=%.4f, bump=%.4f)" % [rc_rest, rc_bump])

	var fulvia := _configure_vehicle(
		"res://data/vehicles/lancia-fulvia/vehicle.json",
		"res://assets/rally/lancia_fulvia/manifest.json",
	)
	check(fulvia != null, "Fulvia configura")
	if fulvia != null:
		var ff: Dictionary = fulvia.suspension_model.axle_parameters[0]
		var fr: Dictionary = fulvia.suspension_model.axle_parameters[2]
		check(not bool(ff["solid_axle"]), "Fulvia delantero double_wishbone es independiente")
		check(bool(fr["solid_axle"]), "Fulvia trasero dead_axle es eje rígido")
		check(float(ff["anti_lift_tan"]) > 0.005, "Fulvia FWD anti-lift delantero > 0")


func test_roll_center_and_jacking_math() -> void:
	print("\n[2] Matemática exacta de Roll Center, transferencia geométrica y jacking...")
	var escort := _configure_vehicle(
		"res://data/vehicles/ford-escort-rs2000/vehicle.json",
		"res://assets/rally/ford_escort_rs2000_1971/manifest.json",
	)
	if escort == null:
		check(false, "Escort listo para matemática")
		return
	var susp := escort.suspension_model
	var wpos := escort.wheel_positions_local
	var b_f := absf(wpos[0].x)
	var b_r := absf(wpos[2].x)
	var rc_f := susp.dynamic_roll_center_height_m(0, 0.0, 0.505)
	var rc_r := susp.dynamic_roll_center_height_m(2, 0.0, 0.505)

	# Giro a izquierda: fuerzas laterales hacia -X (negativas), rueda exterior (FR/RR) más cargada.
	var lat: Array[float] = [-1500.0, -3500.0, -1400.0, -3200.0]
	var lon: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var trav: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var cgh: Array[float] = [0.505, 0.505, 0.505, 0.505]
	var res := susp.instant_center_jacking_forces(lat, lon, trav, wpos, cgh)
	var geo: Array = res["geometric_load_transfer_n"]
	var hub: Array = res["hub_forces_n"]

	# Eje delantero independiente: exterior (+Fz), interior (-Fz), jacking neto positivo (eleva chasis).
	check(float(geo[1]) > 0.0 and float(geo[0]) < 0.0, "Giro izq delantero: FR +Fz geométrico (%.1f N), FL -Fz (%.1f N)" % [float(geo[1]), float(geo[0])])
	var front_roll_moment_geo := b_f * (float(geo[1]) - float(geo[0]))
	var expected_front_geo_moment := rc_f * absf(lat[0] + lat[1])
	check(absf(front_roll_moment_geo - expected_front_geo_moment) < 1.0, "Momento geométrico delantero = h_RC * |Fy| (got %.2f exp %.2f)" % [front_roll_moment_geo, expected_front_geo_moment])
	var front_net_heave_jack := float(geo[0]) + float(geo[1])
	check(front_net_heave_jack > 50.0, "Suspensión independiente genera jacking neto vertical positivo al cargar más la exterior (%.1f N)" % front_net_heave_jack)

	# Eje trasero rígido: par puro igual y opuesto, sin jacking neto de expansión de vía.
	check(float(geo[3]) > 0.0 and float(geo[2]) < 0.0, "Giro izq trasero: RR +Fz geométrico (%.1f N), RL -Fz (%.1f N)" % [float(geo[3]), float(geo[2])])
	var rear_net_heave_jack := float(geo[2]) + float(geo[3])
	check(absf(rear_net_heave_jack) < 1.0e-4, "Eje rígido tiene jacking neto vertical cero (%.6f N)" % rear_net_heave_jack)
	var rear_roll_moment_geo := b_r * (float(geo[3]) - float(geo[2]))
	var expected_rear_geo_moment := rc_r * absf(lat[2] + lat[3])
	check(absf(rear_roll_moment_geo - expected_rear_geo_moment) < 1.0, "Momento geométrico trasero = h_RC * |Fy| (got %.2f exp %.2f)" % [rear_roll_moment_geo, expected_rear_geo_moment])
	check(absf(float(hub[1]) + float(geo[1])) < 1.0e-4, "Identidad Q_hub = -geo_transfer exacta")

	# Simetría en giro a derecha (Fy > 0).
	var lat_r: Array[float] = [3500.0, 1500.0, 3200.0, 1400.0]
	var res_r := susp.instant_center_jacking_forces(lat_r, lon, trav, wpos, cgh)
	var geo_r: Array = res_r["geometric_load_transfer_n"]
	check(absf(float(geo_r[0]) - float(geo[1])) < 1.0e-3 and absf(float(geo_r[1]) - float(geo[0])) < 1.0e-3, "Simetría exacta izquierda/derecha en tren delantero")
	check(absf(float(geo_r[2]) - float(geo[3])) < 1.0e-3 and absf(float(geo_r[3]) - float(geo[2])) < 1.0e-3, "Simetría exacta izquierda/derecha en tren trasero")


func test_pitch_anti_dive_squat_and_no_double_count() -> void:
	print("\n[3] Anti-Dive, Anti-Squat, Anti-Lift y guardia de no doble conteo...")
	var escort := _configure_vehicle(
		"res://data/vehicles/ford-escort-rs2000/vehicle.json",
		"res://assets/rally/ford_escort_rs2000_1971/manifest.json",
	)
	if escort == null:
		return
	var susp := escort.suspension_model
	var wpos := escort.wheel_positions_local
	var lat0: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var trav: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var cgh: Array[float] = [0.505, 0.505, 0.505, 0.505]

	# Frenada: fx < 0 -> delante +Fz (anti-dive), detrás -Fz (anti-lift).
	var brake_lon: Array[float] = [-3200.0, -3200.0, -1700.0, -1700.0]
	var r_brake := susp.instant_center_jacking_forces(lat0, brake_lon, trav, wpos, cgh)
	var g_brake: Array = r_brake["geometric_load_transfer_n"]
	check(float(g_brake[0]) > 100.0 and float(g_brake[1]) > 100.0, "Frenada: anti-dive delantero añade +Fz geométrico (%.1f N/rueda)" % float(g_brake[0]))
	check(float(g_brake[2]) < -50.0 and float(g_brake[3]) < -50.0, "Frenada: anti-lift trasero descarga -Fz geométrico (%.1f N/rueda)" % float(g_brake[2]))

	# Aceleración RWD: fx > 0 detrás -> detrás +Fz (anti-squat).
	var accel_lon: Array[float] = [0.0, 0.0, 2800.0, 2800.0]
	var r_accel := susp.instant_center_jacking_forces(lat0, accel_lon, trav, wpos, cgh)
	var g_accel: Array = r_accel["geometric_load_transfer_n"]
	check(float(g_accel[2]) > 100.0 and float(g_accel[3]) > 100.0, "Tracción RWD: anti-squat trasero añade +Fz geométrico (%.1f N/rueda)" % float(g_accel[2]))
	check(absf(float(g_accel[0])) < 1.0e-4, "Tracción RWD: sin fuerza longitudinal delantera => 0")

	# Guardia de no doble conteo: si axis_roll_rad != 0, lateral queda en 0.
	susp.axle_parameters[0]["axis_roll_rad"] = 0.1
	susp.axle_parameters[1]["axis_roll_rad"] = 0.1
	var lat_guard: Array[float] = [-2000.0, -2000.0, 0.0, 0.0]
	var lon_guard: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var r_guard := susp.instant_center_jacking_forces(lat_guard, lon_guard, trav, wpos, cgh)
	check(absf(float((r_guard["lateral_jacking_n"] as Array)[0])) < 1.0e-6, "Sin doble conteo cuando axis_roll_rad explícito != 0")


func _run_proving_maneuver(maneuver: String, ic_enabled: bool) -> Dictionary:
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
	sim.instant_center_kinematics_enabled = ic_enabled
	vehicle.throttle_input = 0.0
	vehicle.brake_input = 0.0
	vehicle.steering_input = 0.0
	vehicle.handbrake_input = 0.0
	# Asentamiento inicial limpio
	for _i in 90:
		await physics_frame
	var base_pose: Transform3D = vehicle.global_transform
	vehicle._reset_to_transform(base_pose)
	vehicle.freeze = false
	vehicle._reset_pending = false
	sim.instant_center_kinematics_enabled = ic_enabled
	sim.powertrain_model.set_gear(2 if maneuver != "launch" else 1)

	# Lanzamiento a velocidad inicial controlada para corner y brake
	if maneuver in ["corner", "brake"]:
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

	var max_abs_roll_deg := 0.0
	var max_abs_pitch_deg := 0.0
	var max_front_comp_delta := 0.0
	var max_rear_comp_delta := 0.0
	var early_lat_transfer_n := 0.0
	var steady_lat_transfer_n := 0.0
	var steady_samples := 0
	var max_geo_transfer := 0.0
	var finite_ok := true
	var rest_front_comp := 0.5 * (sim.suspension_model.compression[0] + sim.suspension_model.compression[1])
	var rest_rear_comp := 0.5 * (sim.suspension_model.compression[2] + sim.suspension_model.compression[3])
	var initial_d_fz := 0.0
	var has_initial_d_fz := false

	var total_ticks := 90 if maneuver == "corner" else 70
	for t in total_ticks:
		if maneuver == "corner":
			vehicle.throttle_input = 0.25
			vehicle.brake_input = 0.0
			vehicle.steering_input = clampf(float(t) / 10.0, 0.0, 1.0) * 0.45
		elif maneuver == "brake":
			vehicle.throttle_input = 0.0
			vehicle.brake_input = clampf(float(t) / 6.0, 0.0, 1.0) * 0.85
			vehicle.steering_input = 0.0
		elif maneuver == "launch":
			vehicle.throttle_input = 1.0
			vehicle.brake_input = 0.0
			vehicle.steering_input = 0.0
		await physics_frame
		var basis_v: Basis = vehicle.global_transform.basis
		var roll_deg := rad_to_deg(atan2(basis_v.x.y, basis_v.y.y))
		var pitch_deg := rad_to_deg(atan2(-basis_v.z.y, basis_v.y.y))
		if not is_finite(roll_deg) or not is_finite(pitch_deg):
			finite_ok = false
		max_abs_roll_deg = maxf(max_abs_roll_deg, absf(roll_deg))
		max_abs_pitch_deg = maxf(max_abs_pitch_deg, absf(pitch_deg))
		var f_comp := 0.5 * (sim.suspension_model.compression[0] + sim.suspension_model.compression[1]) - rest_front_comp
		var r_comp := 0.5 * (sim.suspension_model.compression[2] + sim.suspension_model.compression[3]) - rest_rear_comp
		max_front_comp_delta = maxf(max_front_comp_delta, f_comp)
		max_rear_comp_delta = maxf(max_rear_comp_delta, r_comp)
		# Transferencia lateral firmada hacia el lado derecho (+X, exterior en giro a izquierda).
		var d_fz := ((sim.wheel_loads[1] - sim.wheel_loads[0]) + (sim.wheel_loads[3] - sim.wheel_loads[2])) * 0.5
		if not has_initial_d_fz:
			initial_d_fz = d_fz
			has_initial_d_fz = true
		var d_fz_delta := d_fz - initial_d_fz
		if maneuver == "corner" and t in [0, 4, 8, 12, 16, 24, 48]:
			print("  [corner ic=%s t=%d] roll=%.3f d_fz=%.1f d_fz_delta=%.1f geo_FR=%.1f geo_RR=%.1f" % [
				str(ic_enabled), t, roll_deg, d_fz, d_fz_delta,
				sim.last_geometric_load_transfer_n[1], sim.last_geometric_load_transfer_n[3],
			])
		if t == 12:
			early_lat_transfer_n = d_fz_delta
		if t >= 35 and t <= 65:
			steady_lat_transfer_n += d_fz_delta
			steady_samples += 1
		for w in 4:
			max_geo_transfer = maxf(max_geo_transfer, absf(sim.last_geometric_load_transfer_n[w]))

	scene.queue_free()
	await process_frame
	return {
		"ok": true,
		"finite_ok": finite_ok,
		"max_abs_roll_deg": max_abs_roll_deg,
		"max_abs_pitch_deg": max_abs_pitch_deg,
		"max_front_comp_delta": max_front_comp_delta,
		"max_rear_comp_delta": max_rear_comp_delta,
		"early_lat_transfer_n": early_lat_transfer_n,
		"steady_lat_transfer_n": steady_lat_transfer_n / maxf(float(steady_samples), 1.0),
		"max_geo_transfer_n": max_geo_transfer,
	}


func test_dynamic_scene_comparisons() -> void:
	print("\n[4] Comparativa dinámica real en escena (Escort RS2000, ON vs OFF)...")
	var c_off := await _run_proving_maneuver("corner", false)
	var c_on := await _run_proving_maneuver("corner", true)
	check(bool(c_off.get("ok", false)) and bool(c_on.get("ok", false)), "Escena curva ejecutada ON y OFF")
	check(bool(c_on.get("finite_ok", false)), "Curva ON numéricamente finita")
	check(float(c_on["max_abs_roll_deg"]) < float(c_off["max_abs_roll_deg"]) * 0.90,
		"Curva: Roll Centers reducen alabeo elástico (ON=%.3f deg < OFF=%.3f deg)" % [float(c_on["max_abs_roll_deg"]), float(c_off["max_abs_roll_deg"])])
	check(float(c_on["early_lat_transfer_n"]) > float(c_off["early_lat_transfer_n"]) * 1.02,
		"Curva: transferencia lateral inicial más inmediata en turn-in (ON=%.1f N > OFF=%.1f N)" % [float(c_on["early_lat_transfer_n"]), float(c_off["early_lat_transfer_n"])])
	check(float(c_on["max_geo_transfer_n"]) > 150.0, "Curva: telemetría de transferencia geométrica activa (%.1f N)" % float(c_on["max_geo_transfer_n"]))

	var b_off := await _run_proving_maneuver("brake", false)
	var b_on := await _run_proving_maneuver("brake", true)
	check(bool(b_off.get("ok", false)) and bool(b_on.get("ok", false)), "Escena frenada ejecutada ON y OFF")
	check(bool(b_on.get("finite_ok", false)), "Frenada ON numéricamente finita")
	check(float(b_on["max_front_comp_delta"]) < float(b_off["max_front_comp_delta"]) * 0.92,
		"Frenada: Anti-Dive reduce hundimiento delantero (ON=%.4f m < OFF=%.4f m)" % [float(b_on["max_front_comp_delta"]), float(b_off["max_front_comp_delta"])])
	check(float(b_on["max_abs_pitch_deg"]) < float(b_off["max_abs_pitch_deg"]) * 0.92,
		"Frenada: Anti-Dive + Anti-Lift reducen cabeceo (ON=%.3f deg < OFF=%.3f deg)" % [float(b_on["max_abs_pitch_deg"]), float(b_off["max_abs_pitch_deg"])])

	var l_off := await _run_proving_maneuver("launch", false)
	var l_on := await _run_proving_maneuver("launch", true)
	check(bool(l_off.get("ok", false)) and bool(l_on.get("ok", false)), "Escena aceleración ejecutada ON y OFF")
	check(bool(l_on.get("finite_ok", false)), "Aceleración ON numéricamente finita")
	check(float(l_on["max_rear_comp_delta"]) < float(l_off["max_rear_comp_delta"]) * 0.90,
		"Aceleración RWD: Anti-Squat reduce hundimiento trasero (ON=%.4f m < OFF=%.4f m)" % [float(l_on["max_rear_comp_delta"]), float(l_off["max_rear_comp_delta"])])


func run() -> void:
	print("=== INSTANT CENTER KINEMATICS CONTRACT ===")
	test_architecture_defaults_and_rc_migration()
	test_roll_center_and_jacking_math()
	test_pitch_anti_dive_squat_and_no_double_count()
	await test_dynamic_scene_comparisons()
	print("\nINSTANT_CENTER_KINEMATICS_CONTRACT ", "PASS" if failures.is_empty() else "FAIL")
	if not failures.is_empty():
		for f in failures:
			print("  - ", f)
	quit(0 if failures.is_empty() else 1)
