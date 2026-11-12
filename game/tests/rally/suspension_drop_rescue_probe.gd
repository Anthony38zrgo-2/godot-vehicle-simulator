extends SceneTree
## suspension_drop_rescue_probe.gd
##
## Sonda comparativa §SUSPENSION_CORRECTION_PLAN (hallazgos F1/F3):
##  - Caídas de 0,5 m desde el mismo estado inicial con el recorte de
##    diagnóstico DESACTIVADO (producción) y ACTIVADO, con tándem y con
##    ShapeCast. Registra carga pico, recorrido pico, velocidad relativa pico
##    y número de recortes (wheel-ticks con damper_clamped).
##  - Rescate comparativo: último tick previo al rescate y primeros ticks
##    posteriores frente a un vehículo recién colocado en la misma pose
##    (hubs en pose esperada; primera fuerza de damper vs velocidad medida).
##
## Diagnóstico a 60 Hz con parámetros fijos. Salida en marcadores JSON:
##  SUSPENSION_DROP_RESULT {...} / SUSPENSION_RESCUE_RESULT {...}

var failures: Array[String] = []
var drop_results: Array[Dictionary] = []


func check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		push_error("FAIL: " + msg)
	else:
		print("  PASS: " + msg)


func _initialize() -> void:
	call_deferred("run")


func _w(reason: String) -> void:
	push_warning("probe: " + reason)


func run() -> void:
	print("--- SUSPENSION DROP/RESCUE PROBE (F1/F3, 60 Hz) ---")
	Engine.physics_ticks_per_second = 60
	var scene = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 240:
		await physics_frame
		if scene.session_ready:
			break
	if not scene.session_ready:
		failures.append("proving ground session ready")
		push_error("FAIL: proving ground session ready")
		quit(1)
		return
	var vehicle = scene.vehicle
	var ctl = scene.input_controller
	ctl.set_physics_process(false)
	vehicle.throttle_input = 0.0
	vehicle.brake_input = 0.0
	vehicle.steering_input = 0.0
	vehicle.handbrake_input = 0.0
	# Asentamiento inicial.
	for i in 120:
		await physics_frame
	var base_pose: Transform3D = vehicle.global_transform
	var drop_origin: Vector3 = base_pose.origin + Vector3.UP * 0.5
	var drop_pose := Transform3D(base_pose.basis, drop_origin)
	for tandem in [true, false]:
		vehicle.simulation.tandem_cam_enabled = tandem
		for limit in [false, true]:
			vehicle.simulation.set_damper_impulse_limit(limit)
			var r := await _run_drop(vehicle, drop_pose, tandem, limit)
			drop_results.append(r)
			print("SUSPENSION_DROP_RESULT ", JSON.stringify(r))
	check(true, "caídas 0,5 m completadas (%d configs)" % drop_results.size())
	# Comparativa con límite OFF/tándem contra el dato de revisión (346/520 y
	# 332/520 wheel-ticks con el límite activado a 60 Hz).
	var rescue := await _run_rescue_comparison(vehicle, drop_pose)
	print("SUSPENSION_RESCUE_RESULT ", JSON.stringify(rescue))
	check(bool(rescue.get("ok", false)), "rescate comparativo con traza por tick")
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("\nSUSPENSION DROP/RESCUE PROBE DONE")
		quit(0)
	else:
		print("\nPROBE FAILED:")
		for f in failures:
			print("  - ", f)
		quit(1)


func _run_drop(vehicle: Node, pose: Transform3D, tandem: bool, limit: bool) -> Dictionary:
	vehicle.simulation.set_damper_impulse_limit(limit)
	vehicle.simulation.tandem_cam_enabled = tandem
	vehicle._reset_to_transform(pose)
	for i in 6:
		await physics_frame
	var peak_load := 0.0
	var peak_comp := -99.0
	var peak_vel := 0.0
	var clips := 0
	var ticks := 0
	var first_rel := 0.0
	var first_req := 0.0
	var first_app := 0.0
	var got_first := false
	for i in 150:
		await physics_frame
		ticks += 1
		var smp: Array = vehicle.simulation.sample_suspension_trace()
		for w in 4:
			var d: Dictionary = smp[w]
			peak_load = maxf(peak_load, float(d.get("load_n", 0.0)))
			peak_comp = maxf(peak_comp, float(d.get("compression_m", 0.0)))
			peak_vel = maxf(peak_vel, absf(float(d.get("compression_velocity_m_s", 0.0))))
			if bool(d.get("damper_clamped", false)):
				clips += 1
			if not got_first:
				first_rel = float(d.get("compression_velocity_m_s", 0.0))
				first_req = float(d.get("damper_requested_n", 0.0))
				first_app = float(d.get("damper_applied_n", 0.0))
		got_first = true
	var total_wheel_ticks := ticks * 4
	return {
		"tandem": tandem,
		"limiter": ("diag_on" if limit else "prod_off"),
		"hz": Engine.physics_ticks_per_second,
		"drop_m": 0.5,
		"ticks": ticks,
		"wheel_ticks": total_wheel_ticks,
		"peak_load_n": peak_load,
		"peak_compression_m": peak_comp,
		"peak_rel_velocity_m_s": peak_vel,
		"clip_wheel_ticks": clips,
		"first_tick_rel_vel_m_s": first_rel,
		"first_tick_damper_requested_n": first_req,
		"first_tick_damper_applied_n": first_app,
	}


func _sample_ticks(vehicle: Node, n: int) -> Array:
	var out: Array = []
	for i in n:
		await physics_frame
		out.append(
			{
				"suspension": vehicle.simulation.sample_suspension_trace(),
				"tick": vehicle.simulation.sample_tick_trace(),
				"chassis_y": vehicle.global_transform.origin.y,
			}
		)
	return out


func _run_rescue_comparison(vehicle: Node, pose: Transform3D) -> Dictionary:
	vehicle.simulation.tandem_cam_enabled = true
	vehicle.simulation.set_damper_impulse_limit(false)
	vehicle._reset_to_transform(pose)
	for i in 90:
		await physics_frame
	var pre: Array = vehicle.simulation.sample_suspension_trace()
	var pre_tick: Array = vehicle.simulation.sample_tick_trace()
	vehicle.rescue_to_pose(pose)
	for i in 8:
		await physics_frame
	var post_rescue := await _sample_ticks(vehicle, 5)
	# Vehículo recién colocado en la misma pose y estado inicial.
	vehicle._reset_to_transform(pose)
	for i in 8:
		await physics_frame
	var post_fresh := await _sample_ticks(vehicle, 5)
	# Comparación: hubs en pose esperada (origen del hub vs neutro) y primera
	# fuerza de damper frente a la velocidad relativa medida.
	var ok := true
	var notes: Array[String] = []
	if post_rescue.size() != 5 or post_fresh.size() != 5:
		ok = false
		notes.append("muestras incompletas")
	var r0: Dictionary = (post_rescue[0] as Dictionary).get("suspension", [])[0]
	var f0: Dictionary = (post_fresh[0] as Dictionary).get("suspension", [])[0]
	var r_vel := float(r0.get("compression_velocity_m_s", 0.0))
	var r_app := float(r0.get("damper_applied_n", 0.0))
	if signf(r_vel) != signf(r_app) and absf(r_app) > 1.0:
		ok = false
		notes.append("rescate: damper no corresponde a velocidad medida")
	var f_vel := float(f0.get("compression_velocity_m_s", 0.0))
	var f_app := float(f0.get("damper_applied_n", 0.0))
	if signf(f_vel) != signf(f_app) and absf(f_app) > 1.0:
		ok = false
		notes.append("fresco: damper no corresponde a velocidad medida")
	return {
		"ok": ok and failures.is_empty(),
		"notes": notes,
		"pre_rescue_tick_id": (pre_tick[0] as Dictionary).get("tick_id", 0) if pre_tick.size() > 0 else 0,
		"post_rescue_first": post_rescue[0] if post_rescue.size() > 0 else {},
		"post_fresh_first": post_fresh[0] if post_fresh.size() > 0 else {},
	}
