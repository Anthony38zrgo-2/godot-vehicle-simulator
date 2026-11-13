extends SceneTree
## fulvia_spawn_diagnostic.gd — Segunda prueba: impulso radial y rebote del buje.
##
## Plan §segunda-prueba: reproducir la pérdida de apoyo de FL en el tick 2 y
## explicar el salto de velocidad del buje entre los ticks 1 y 2 con impulsos
## medidos (J = F·dt frente a m·Δv por término, residual sin explicar aparte).
##
## Variantes (cada cambio en una pasada distinta; controles solo en sonda):
##   base     : producción (limitador OFF, viscoso radial ×1.0).
##   limiter  : limitador diagnóstico de impulso del amortiguador ON.
##   novisc   : término viscoso radial ×0.0 (elástica, tope y unilateralidad
##              intactos; `radial_viscous_scale` del rig, 1.0 por defecto).
##   settled  : asentamiento previo a 120 Hz (240 ticks), captura de pose y
##              re-arranque a 60 Hz con velocidades reiniciadas.
## Jolt de producción a 60 Hz; 120 Hz solo como control diagnóstico.
## Fulvia de disco, ShapeCast3D, 20 kg, neutra, plano, controles a cero, mismo
## spawn y estado térmico inicial. f = 1.75/1.85 Hz, ζ = 0.55/0.55 (fábrica).
##
## Uso:
##   godot --headless --path game --script res://tests/rally/fulvia_spawn_diagnostic.gd -- --hz=60 --ticks=240
##   godot --headless --path game --script res://tests/rally/fulvia_spawn_diagnostic.gd -- --hz=120 --ticks=240
##   godot --headless --path game --script res://tests/rally/fulvia_spawn_diagnostic.gd -- --hz=both --ticks=240 --variants=base,limiter,implicit,implicit_limiter --reps=3
##   godot --headless --path game --script res://tests/rally/fulvia_spawn_diagnostic.gd -- --hz=both --variants=base,limiter,novisc,settled --reps=3
##
## Salidas: SUSPENSION_SPAWN_HEADER / SUSPENSION_IMPULSE_BALANCE /
## SUSPENSION_SPAWN_FIRST_ANOMALY / SUSPENSION_SPAWN_SUMMARY + CSV por tick
## (fulvia_spawn_hz<HZ>_<variante>_r<R>.csv) e impulsos
## (fulvia_impulse_hz<HZ>_<variante>_r<R>.csv) en user://suspension_60hz/.

const SCENE_PATH := "res://scenes/rally/rally_proving_ground_fulvia.tscn"
const NOMINAL_FUEL_KG := 20.0
const SETTLE_TICKS_120 := 240
const LOAD_SPIKE_N := 12000.0
const DEFLECTION_SPIKE_M := 0.06
const BALANCE_TICKS := 10

var failures: Array[String] = []
var opt_hz := "60"
var opt_ticks := 240
var opt_variants: Array[String] = ["base"]
var opt_reps := 1
var opt_out := "user://suspension_60hz"


func check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		push_error("FAIL: " + msg)
	else:
		print("  PASS: " + msg)


func _initialize() -> void:
	call_deferred("run")


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--hz="):
			var v := s.trim_prefix("--hz=").strip_edges().to_lower()
			if v in ["60", "120", "both"]:
				opt_hz = v
		elif s.begins_with("--ticks="):
			opt_ticks = clampi(int(s.trim_prefix("--ticks=")), 30, 1200)
		elif s.begins_with("--variants="):
			var cleaned: Array[String] = []
			for v2 in s.trim_prefix("--variants=").split(","):
				var k := str(v2).strip_edges().to_lower()
				if k in ["base", "limiter", "novisc", "settled", "implicit", "implicit_limiter"] and not cleaned.has(k):
					cleaned.append(k)
			if not cleaned.is_empty():
				opt_variants = cleaned
		elif s.begins_with("--reps="):
			opt_reps = clampi(int(s.trim_prefix("--reps=")), 1, 5)


func _hz_list() -> Array[int]:
	if opt_hz == "both":
		return [60, 120]
	return [int(opt_hz)]


func run() -> void:
	_parse_args()
	print("--- FULVIA SPAWN DIAGNOSTIC-2 hz=%s ticks=%d variants=%s reps=%d ---" % [opt_hz, opt_ticks, str(opt_variants), opt_reps])
	check(str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) == "Jolt Physics", "motor Jolt")
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.make_dir_recursive("suspension_60hz")
	for hz in _hz_list():
		for variant in opt_variants:
			# La variante settled solo tiene sentido con asentado a 120 Hz y
			# ejecución a 60 Hz; a 120 Hz equivale a base y se omite.
			if variant == "settled" and hz != 60:
				continue
			for rep in opt_reps:
				await _run_pass(hz, variant, rep)
	scene_cleanup()
	if failures.is_empty():
		print("\nSPAWN DIAGNOSTIC-2 DONE")
		quit(0)
	else:
		print("\nSPAWN DIAGNOSTIC-2 FAILED")
		quit(1)


func scene_cleanup() -> void:
	pass


func _run_pass(hz: int, variant: String, rep: int) -> void:
	Engine.physics_ticks_per_second = hz
	var settle_hz := 120 if variant == "settled" else hz
	Engine.physics_ticks_per_second = settle_hz
	var scene = load(SCENE_PATH).instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 240:
		await physics_frame
		if scene.session_ready:
			break
	if not scene.session_ready:
		check(false, "session ready hz=%d %s r%d" % [hz, variant, rep])
		scene.queue_free()
		await process_frame
		return
	var vehicle = scene.vehicle
	var ctl = scene.input_controller
	ctl.set_physics_process(false)
	var sim = vehicle.simulation
	sim.tandem_cam_enabled = false
	sim.set_damper_impulse_limit(variant == "limiter" or variant == "implicit_limiter")
	sim.unsprung_rig.radial_viscous_scale = 0.0 if variant == "novisc" else 1.0
	sim.unsprung_rig.radial_implicit_enabled = variant == "implicit" or variant == "implicit_limiter"
	var payload: Dictionary = sim.filter_garage_values(RallySetupCatalog.defaults(sim.domains))
	payload["fuel.initial_kg"] = NOMINAL_FUEL_KG
	var res: Dictionary = sim.apply_setup_values(payload)
	if not bool(res.get("ok", false)):
		check(false, "setup de fábrica hz=%d %s r%d" % [hz, variant, rep])
		scene.queue_free()
		await process_frame
		return
	vehicle.prepare_for_stage()
	var hub_masses: Array = []
	for hub in sim.unsprung_rig.hubs:
		hub_masses.append(float((hub as RigidBody3D).mass))
	var spawn_y := 0.0
	if scene.has_method("spawn_position"):
		spawn_y = (scene.spawn_position() as Vector3).y
	else:
		spawn_y = vehicle.global_transform.origin.y
	var settled_from := ""
	if variant == "settled":
		# Fase 1: asentar a 120 Hz con controles a cero y neutra.
		vehicle.throttle_input = 0.0
		vehicle.brake_input = 0.0
		vehicle.steering_input = 0.0
		vehicle.handbrake_input = 0.0
		vehicle._reset_to_transform(Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.0, spawn_y, 0.0)))
		sim.powertrain_model.set_gear(0)
		for i in SETTLE_TICKS_120:
			await physics_frame
		var settled_pose: Transform3D = vehicle.global_transform
		settled_from = "pose_120hz_y=%.4f" % settled_pose.origin.y
		# Fase 2: re-arranque a 60 Hz con velocidades reiniciadas.
		Engine.physics_ticks_per_second = 60
		vehicle.prepare_for_stage()
		vehicle._reset_to_transform(Transform3D(Basis(Vector3.UP, 0.0), Vector3(settled_pose.origin.x, settled_pose.origin.y, settled_pose.origin.z)))
	print("SUSPENSION_SPAWN_HEADER ", JSON.stringify({
		"profile_id": str(sim.active_profile_id),
		"hz": hz,
		"variant": variant,
		"rep": rep,
		"settle_hz": settle_hz,
		"settled_from": settled_from,
		"physics_hz_setting": int(Engine.physics_ticks_per_second),
		"physics_engine": str(ProjectSettings.get_setting("physics/3d/physics_engine", "")),
		"tandem_cam_enabled": bool(sim.tandem_cam_enabled),
		"damper_limiter": bool(sim.unsprung_rig.damper_impulse_limit_enabled),
		"radial_viscous_scale": float(sim.unsprung_rig.radial_viscous_scale),
		"radial_implicit": bool(sim.unsprung_rig.radial_implicit_enabled),
		"fuel_initial_kg": float(sim.mass_model.fuel_initial_kg),
		"hub_masses_kg": hub_masses,
		"maximum_substep_s": float(sim.maximum_substep_seconds),
		"session_generation": int(sim.session_generation),
		"ambient_c": float(sim.thermal_model.ambient_temperature_c),
	}))
	check(int(Engine.physics_ticks_per_second) == hz, "tick %d Hz (%s r%d)" % [hz, variant, rep])
	check(not bool(sim.tandem_cam_enabled), "tandem desactivado (%s r%d)" % [variant, rep])
	if variant != "settled":
		vehicle._reset_to_transform(Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.0, spawn_y, 0.0)))
	sim.powertrain_model.set_gear(0)
	vehicle.throttle_input = 0.0
	vehicle.brake_input = 0.0
	vehicle.steering_input = 0.0
	vehicle.handbrake_input = 0.0
	var tag := "hz%d_%s_r%d" % [hz, variant, rep]
	var csv_path := "%s/fulvia_spawn_%s.csv" % [opt_out.rstrip("/"), tag]
	var imp_path := "%s/fulvia_impulse_%s.csv" % [opt_out.rstrip("/"), tag]
	var f := FileAccess.open(csv_path, FileAccess.WRITE)
	var fi := FileAccess.open(imp_path, FileAccess.WRITE)
	if f != null:
		f.store_line("tick,chassis_y,vy,wheel,comp,hub_travel,vel,geom,loaded,load,elastic,damper_app,bump,radial_defl,contact_dist,safe_frac,tick_id,dt")
	if fi != null:
		fi.store_line("tick_seq,wheel,hub_mass,up_y,pre_hub_v,pre_anchor_v,pre_chassis_v,hit,loaded,dist,road_comp,hub_travel,comp_raw,comp_clamped,defl,cspeed_raw,cspeed_used,press,carcass,rad_elas,rad_visc_full,rad_visc_scale,rad_visc_app,rad_rim,rad_force,rad_clamped,susp_elas,susp_damper_req,susp_damper_app,susp_clamped,susp_bump,susp_arb,susp_droop,susp_internal,hub_susp_ax,hub_rad_ax,hub_grav_ax,J_susp,J_rad,J_grav,J_sum,rad_implicit,rad_F_inst,rad_F_mean,rad_J_imp,rad_iters,rad_fallback,rad_opening")
	var first_anomaly := {"tick": -1, "wheel": -1, "channel": "", "detail": ""}
	var ever_contact := [false, false, false, false]
	var impulse_by_seq := {}
	var load_peak := 0.0
	var axial_vel_peak := 0.0
	var bump_dwell_fl := 0
	for t in opt_ticks:
		vehicle.throttle_input = 0.0
		vehicle.brake_input = 0.0
		vehicle.steering_input = 0.0
		vehicle.handbrake_input = 0.0
		await physics_frame
		var susp: Array = sim.sample_suspension_trace()
		var ticks: Array = sim.sample_tick_trace()
		var contacts: Array = sim.sample_contact_trace()
		var origin: Vector3 = vehicle.global_transform.origin
		var lin: Vector3 = vehicle.linear_velocity
		var rig = sim.unsprung_rig
		for w in 4:
			var s: Dictionary = susp[w]
			var tk: Dictionary = ticks[w]
			var ct: Dictionary = contacts[w] if w < contacts.size() else {}
			var load := float(s.get("load_n", 0.0))
			var comp := float(s.get("compression_m", 0.0))
			var defl := float(ct.get("radial_deflection_m", 0.0))
			var geom := bool(s.get("geometric_contact", false))
			var loaded := bool(s.get("loaded_contact", false))
			var vax := absf(float(s.get("compression_velocity_m_s", 0.0)))
			load_peak = maxf(load_peak, load)
			axial_vel_peak = maxf(axial_vel_peak, vax)
			if w == 0 and float(sim.suspension_model.last_bump_forces_n[w]) > 1.0:
				bump_dwell_fl += 1
			if loaded:
				ever_contact[w] = true
			if f != null:
				f.store_line("%d,%.4f,%.3f,%d,%.5f,%.5f,%.4f,%d,%d,%.1f,%.1f,%.1f,%.1f,%.4f,%.4f,%.4f,%d,%.6f" % [
					t, origin.y, lin.y, w, comp, float(s.get("hub_travel_m", 0.0)),
					float(s.get("compression_velocity_m_s", 0.0)), int(geom), int(loaded),
					load, float(s.get("elastic_n", 0.0)), float(s.get("damper_applied_n", 0.0)),
					float(sim.suspension_model.last_bump_forces_n[w]), defl,
					float(ct.get("distance_m", 0.0)), float(ct.get("safe_fraction", 0.0)),
					int(tk.get("tick_id", 0)), float(tk.get("dt_s", 0.0)),
				])
			var im: Dictionary = (rig.impulse_trace[w] as Dictionary).duplicate(true)
			var seq := int(im.get("tick_seq", -1))
			if seq >= 0:
				if not impulse_by_seq.has(seq):
					impulse_by_seq[seq] = [{}, {}, {}, {}]
				(impulse_by_seq[seq] as Array)[w] = im
				if fi != null:
					fi.store_line("%d,%d,%.2f,%.4f,%.4f,%.4f,%.4f,%d,%d,%.4f,%.4f,%.5f,%.5f,%.5f,%.4f,%.4f,%.4f,%.1f,%.1f,%.1f,%.1f,%.2f,%.1f,%.1f,%.1f,%d,%.1f,%.1f,%.1f,%d,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.4f,%.4f,%.4f,%.4f,%d,%.1f,%.1f,%.4f,%d,%d,%d" % [
						seq, w, float(im.get("hub_mass_kg", 0.0)), float((im.get("up", [0, 1, 0]) as Array)[1]),
						float(im.get("pre_hub_vel_axial", 0.0)), float(im.get("pre_anchor_vel_axial", 0.0)), float(im.get("pre_chassis_vel_axial", 0.0)),
						int(bool(im.get("hit", false))), int(bool(im.get("contact_loaded_final", false))),
						float(im.get("distance_m", 0.0)), float(im.get("road_compression_m", 0.0)), float(im.get("hub_travel_physical_m", 0.0)),
						float(im.get("comp_raw_m", 0.0)), float(im.get("comp_clamped_m", 0.0)), float(im.get("deflection_m", 0.0)),
						float(im.get("compression_speed_raw", 0.0)), float(im.get("compression_speed_used", 0.0)),
						float(im.get("pressure_kpa", 0.0)), float(im.get("carcass_c", 0.0)),
						float(im.get("radial_elastic_n", 0.0)), float(im.get("radial_viscous_full_n", 0.0)), float(im.get("radial_viscous_scale", 1.0)),
						float(im.get("radial_viscous_applied_n", 0.0)), float(im.get("radial_rim_stop_n", 0.0)), float(im.get("radial_force_n", 0.0)),
						int(bool(im.get("radial_clamped_zero", false))),
						float(im.get("susp_elastic_n", 0.0)), float(im.get("susp_damper_req_n", 0.0)), float(im.get("susp_damper_app_n", 0.0)),
						int(bool(im.get("susp_damper_clamped", false))),
						float(im.get("susp_bump_n", 0.0)), float(im.get("susp_arb_n", 0.0)), float(im.get("susp_droop_n", 0.0)), float(im.get("susp_internal_n", 0.0)),
						float(im.get("hub_susp_axial_n", 0.0)), float(im.get("hub_radial_axial_n", 0.0)), float(im.get("hub_gravity_axial_n", 0.0)),
						float(im.get("J_susp_ns", 0.0)), float(im.get("J_radial_ns", 0.0)), float(im.get("J_gravity_ns", 0.0)), float(im.get("J_sum_known_ns", 0.0)),
						int(bool(im.get("radial_implicit", false))), float(im.get("radial_F_inst_n", 0.0)), float(im.get("radial_F_mean_n", 0.0)),
						float(im.get("radial_J_imp_ns", 0.0)), int(im.get("radial_iters", 0)), int(bool(im.get("radial_fallback", false))), int(bool(im.get("radial_opening", false))),
					])
			if int(first_anomaly.get("tick", -1)) < 0:
				if load > LOAD_SPIKE_N:
					first_anomaly = {"tick": t, "wheel": w, "channel": "load_spike", "detail": "load=%.0f N" % load}
				elif defl > DEFLECTION_SPIKE_M:
					first_anomaly = {"tick": t, "wheel": w, "channel": "deflection_spike", "detail": "defl=%.3f m" % defl}
				elif (comp >= 0.219 or comp <= -0.179) and t > 2:
					first_anomaly = {"tick": t, "wheel": w, "channel": "travel_clamp", "detail": "comp=%.3f m" % comp}
				elif not loaded and bool(ever_contact[w]):
					first_anomaly = {"tick": t, "wheel": w, "channel": "support_loss", "detail": "pierde apoyo tras contactar"}
	if f != null:
		f.close()
	if fi != null:
		fi.close()
	_print_impulse_balance(impulse_by_seq, hz, variant, rep)
	print("SUSPENSION_SPAWN_FIRST_ANOMALY ", JSON.stringify(first_anomaly))
	var last_y := 0.0
	var max_y := -999.0
	if FileAccess.file_exists(csv_path):
		var rf := FileAccess.open(csv_path, FileAccess.READ)
		rf.get_line()
		while not rf.eof_reached():
			var line := rf.get_line()
			if line.is_empty():
				continue
			var cols := line.split(",")
			if cols.size() > 1 and int(cols[3]) == 0:
				last_y = float(cols[1])
				max_y = maxf(max_y, last_y)
		rf.close()
	print("SUSPENSION_SPAWN_SUMMARY ", JSON.stringify({
		"hz": hz, "variant": variant, "rep": rep, "ticks": opt_ticks,
		"first_support_loss_tick": int(first_anomaly.get("tick", -1)),
		"first_anomaly": first_anomaly,
		"load_peak_n": load_peak,
		"axial_vel_peak_m_s": axial_vel_peak,
		"bump_dwell_fl_ticks": bump_dwell_fl,
		"chassis_y_end_m": last_y,
		"chassis_y_max_m": max_y,
		"csv": csv_path,
		"impulse_csv": imp_path,
	}))
	scene.queue_free()
	await process_frame


## Balance axial de FL entre ticks consecutivos (paso 3): m·Δv frente a ΣJ
## por término leídos a la misma fase del callback; el residual incluye la
## reacción de las restricciones y del solver. n = fuerza aplicada en el tick
## n; Δv = pre(n+1) − pre(n).
func _print_impulse_balance(impulse_by_seq: Dictionary, hz: int, variant: String, rep: int) -> void:
	var seqs := impulse_by_seq.keys()
	seqs.sort()
	var rows: Array = []
	var count := 0
	for s in seqs:
		if count >= BALANCE_TICKS:
			break
		var a: Array = impulse_by_seq[s]
		var next_seq := -1
		for c in seqs:
			if int(c) == int(s) + 1:
				next_seq = int(c)
				break
		if next_seq < 0 or not impulse_by_seq.has(next_seq):
			continue
		var b: Array = impulse_by_seq[next_seq]
		var fa: Dictionary = a[0]
		var fb: Dictionary = b[0]
		if fa.is_empty() or fb.is_empty():
			continue
		var m := maxf(float(fa.get("hub_mass_kg", 19.0)), 1.0)
		var dv := float(fb.get("pre_hub_vel_axial", 0.0)) - float(fa.get("pre_hub_vel_axial", 0.0))
		var mdv := m * dv
		var j_susp := float(fa.get("J_susp_ns", 0.0))
		var j_rad := float(fa.get("J_radial_ns", 0.0))
		var j_grav := float(fa.get("J_gravity_ns", 0.0))
		var j_sum := float(fa.get("J_sum_known_ns", 0.0))
		var resid := mdv - j_sum
		var denom := maxf(absf(mdv), 1.0)
		rows.append({
			"n": int(s), "m": m,
			"pre_v": float(fa.get("pre_hub_vel_axial", 0.0)),
			"post_v": float(fb.get("pre_hub_vel_axial", 0.0)),
			"dv": dv, "m_dv": mdv,
			"J_susp": j_susp, "J_rad": j_rad, "J_grav": j_grav, "J_sum": j_sum,
			"residual": resid, "res_pct": 100.0 * resid / denom,
		})
		count += 1
	print("SUSPENSION_IMPULSE_BALANCE ", JSON.stringify({
		"hz": hz, "variant": variant, "rep": rep, "wheel": 0, "rows": rows,
	}))
