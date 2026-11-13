extends SceneTree
## fulvia_landing_probe.gd - Cuarta prueba del Fulvia (runbook): aterrizaje
## equivalente y validacion en movimiento.
##
## Compara aterrizaje con aterrizaje a igual estado pre-impacto y separa la
## sensibilidad a la frecuencia (60 vs 120 Hz) de la sensibilidad al algoritmo
## (radial explicito vs implicito), sin rescate automatico.
##
## Configuraciones (x3 pasadas):
##   impl60       : radial implicito + limitador de impulso @ 60 Hz (candidato)
##   base120      : radial explicito de produccion, limitador OFF @ 120 Hz (control)
##   impl120      : radial implicito + limitador @ 120 Hz
##   impl60_nolim : radial implicito sin limitador @ 60 Hz (caso mixto Q3)
##
## Preparacion del estado pre-impacto:
##   1. Asentar con setup de fabrica + 20 kg hasta pose estable.
##   2. Calibrar la altura de contacto por micro-caida a 240 Hz usando CONTACTO
##      CARGADO (fuerza radial > 0), no el impacto geometrico del ShapeCast
##      (que se dispara hasta 0.21 m antes de tocar por el recorrido del barrido).
##   3. Medir la velocidad de impacto en la caida de 0.5 m (primer tick con
##      contacto cargado) o usar una velocidad comun con --impact-v.
##   4. Recolocar en la altura de contacto con v_chasis = v_bujes = -v y
##      verificar pose, velocidades y deflexion en el primer contacto cargado.
##
## Comparacion: alineada por primer contacto cargado y tiempo simulado; por
## rueda carga estatica/maxima, recorrido maximo, tiempo en topes, perdida de
## apoyo, velocidad de rebote y asentamiento; impulso int F dt por rueda;
## impulso neto vertical (descontado el peso) frente a delta-momento del sistema
## (chasis + bujes); picos nativos y promediados en intervalos de 16.67 ms.
## El impulso del bajos del chasis se mide con el diagnostico gated del vehiculo
## (diagnostic_body_contacts_enabled) y se suma al balance.
##
## Uso:
##   godot --headless --path game --script res://tests/rally/fulvia_landing_probe.gd -- --mode=landing --reps=3
##   godot --headless --path game --script res://tests/rally/fulvia_landing_probe.gd -- --mode=handling
##
## Salidas: SUSPENSION_LANDING_VERIFY / SUSPENSION_LANDING_SUMMARY /
## SUSPENSION_LANDING_COMPARE / SUSPENSION_LANDING_DETERMINISM /
## SUSPENSION_LANDING_TOLERANCE / SUSPENSION_HANDLING_SUMMARY + CSV por pasada
## en user://suspension_60hz_q4/.

const SCENE_PATH := "res://scenes/rally/rally_proving_ground_fulvia.tscn"
const NOMINAL_FUEL_KG := 20.0
const DROP_HEIGHT_M := 0.5
const SETTLE_TICKS := 240
const CALIBRATION_HZ := 240
const GRAVITY := 9.80665
const BIN_S := 1.0 / 60.0
const SUPPORT_EPS_N := 1.0
const SETTLE_COMP_M := 0.005
const SETTLE_VEL_M_S := 0.35
const SETTLE_LOAD_FRAC := 0.10
const SETTLE_HOLD_TICKS := 20
const CONTACT_SEARCH_TICKS := 90

const CONFIGS := {
	"impl60": {"hz": 60, "implicit": true, "limiter": true},
	"base120": {"hz": 120, "implicit": false, "limiter": false},
	"impl120": {"hz": 120, "implicit": true, "limiter": true},
	"impl60_nolim": {"hz": 60, "implicit": true, "limiter": false},
	"sub180": {"hz": 60, "implicit": false, "limiter": false, "substeps": 3},
	"sub360": {"hz": 60, "implicit": false, "limiter": false, "substeps": 6},
	"base60": {"hz": 60, "implicit": false, "limiter": false},
}

var failures: Array[String] = []
var opt_mode := "landing"
var opt_reps := 3
var opt_configs: Array[String] = ["impl60", "base120", "impl120", "impl60_nolim"]
var opt_window_s := 4.0
var opt_impact_v := 0.0
var opt_substeps := 1
var opt_steer_gain := 1.0
var pending_substeps := 1
var opt_out := "user://suspension_60hz_q4"
var results: Array[Dictionary] = []
var init_order := 0


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
		if s.begins_with("--mode="):
			var m := s.trim_prefix("--mode=").strip_edges().to_lower()
			if m in ["landing", "handling"]:
				opt_mode = m
		elif s.begins_with("--reps="):
			opt_reps = clampi(int(s.trim_prefix("--reps=")), 1, 5)
		elif s.begins_with("--window-s="):
			opt_window_s = clampf(float(s.trim_prefix("--window-s=")), 0.5, 8.0)
		elif s.begins_with("--substeps="):
			opt_substeps = clampi(int(s.trim_prefix("--substeps=")), 1, 6)
			if not opt_substeps in [1, 3, 6]:
				opt_substeps = 1
		elif s.begins_with("--steer-gain="):
			opt_steer_gain = clampf(float(s.trim_prefix("--steer-gain=")), 0.2, 1.5)
		elif s.begins_with("--impact-v="):
			opt_impact_v = clampf(float(s.trim_prefix("--impact-v=")), 0.0, 8.0)
		elif s.begins_with("--configs="):
			var cleaned: Array[String] = []
			for c in s.trim_prefix("--configs=").split(","):
				var k := str(c).strip_edges().to_lower()
				if CONFIGS.has(k) and not cleaned.has(k):
					cleaned.append(k)
			if not cleaned.is_empty():
				opt_configs = cleaned


func run() -> void:
	_parse_args()
	print("--- FULVIA Q4 PROBE mode=%s reps=%d configs=%s window=%.2fs impact_v=%.2f ---" % [
		opt_mode, opt_reps, str(opt_configs), opt_window_s, opt_impact_v])
	check(str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) == "Jolt Physics", "motor Jolt")
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.make_dir_recursive(opt_out.trim_prefix("user://"))
	if opt_mode == "landing":
		for cfg_name in opt_configs:
			for rep in opt_reps:
				await _run_landing(cfg_name, rep)
		_report_compare()
	else:
		for cfg_name in opt_configs:
			for maneuver in ["brake", "corner", "crest"]:
				for rep in opt_reps:
					await _run_handling(cfg_name, maneuver, rep)
	if failures.is_empty():
		print("\nQ4 PROBE DONE (%d pasadas)" % results.size())
		quit(0)
	else:
		print("\nQ4 PROBE FAILED:")
		for f in failures:
			print("  - ", f)
		quit(1)


# -------------------------------------------------------------- escena comun
func _prepare_scene(hz: int, implicit: bool, limiter: bool, substeps: int = 1) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var scene = load(SCENE_PATH).instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 240:
		await physics_frame
		if scene.session_ready:
			break
	if not scene.session_ready:
		return {}
	var vehicle = scene.vehicle
	scene.input_controller.set_physics_process(false)
	var sim = vehicle.simulation
	vehicle.diagnostic_body_contacts_enabled = true
	sim.tandem_cam_enabled = false
	sim.set_damper_impulse_limit(limiter)
	sim.unsprung_rig.radial_implicit_enabled = implicit
	sim.unsprung_rig.radial_viscous_scale = 1.0
	# Los subpasos solo actúan en la ventana de registro; asentado,
	# calibración y medida corren a frecuencia nativa (idéntico pre-impacto).
	sim.unsprung_rig.coupled_substeps = 1
	pending_substeps = maxi(1, substeps)
	var payload: Dictionary = sim.filter_garage_values(RallySetupCatalog.defaults(sim.domains))
	payload["fuel.initial_kg"] = NOMINAL_FUEL_KG
	var applied: Dictionary = sim.apply_setup_values(payload)
	if not bool(applied.get("ok", false)):
		scene.queue_free()
		await process_frame
		return {}
	vehicle.prepare_for_stage()
	vehicle.throttle_input = 0.0
	vehicle.brake_input = 0.0
	vehicle.steering_input = 0.0
	vehicle.handbrake_input = 0.0
	sim.powertrain_model.set_gear(0)
	return {"scene": scene, "vehicle": vehicle, "sim": sim}


func _spawn_y(scene: Node, vehicle: Node) -> float:
	if scene.has_method("spawn_position"):
		return (scene.spawn_position() as Vector3).y
	return vehicle.global_transform.origin.y


## Contacto real: alguna rueda con carga radial positiva.
func _any_loaded(sim) -> bool:
	for s in sim.sample_suspension_trace():
		if bool((s as Dictionary).get("loaded_contact", false)):
			return true
	return false


func _settle_pose(scene: Node, vehicle: Node, sim) -> Dictionary:
	Engine.physics_ticks_per_second = 120
	vehicle._reset_to_transform(Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.0, _spawn_y(scene, vehicle), 0.0)))
	vehicle.freeze = false
	vehicle._reset_pending = false
	for i in SETTLE_TICKS:
		await physics_frame
	var loads: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in 12:
		await physics_frame
		for w in 4:
			loads[w] += float(sim.wheel_loads[w])
	for w in 4:
		loads[w] /= 12.0
	return {"pose": vehicle.global_transform, "static_loads": loads}


## Micro-caida a 240 Hz para localizar la altura de contacto cargado.
func _calibrate_contact_y(vehicle: Node, sim, settled_pose: Transform3D) -> Dictionary:
	Engine.physics_ticks_per_second = CALIBRATION_HZ
	var start := Transform3D(Basis(Vector3.UP, 0.0), settled_pose.origin + Vector3.UP * 0.012)
	vehicle._reset_to_transform(start)
	vehicle.freeze = false
	vehicle._reset_pending = false
	var dt := 1.0 / float(CALIBRATION_HZ)
	for t in 240:
		await physics_frame
		if _any_loaded(sim):
			var y: float = vehicle.global_transform.origin.y
			var vy: float = vehicle.linear_velocity.y
			return {"contact_y": y - vy * dt, "observed_y": y, "vy": vy, "ticks": t}
	return {"contact_y": NAN, "observed_y": NAN, "vy": 0.0, "ticks": -1}


## Velocidad de impacto medida en la caida de 0.5 m a la frecuencia de pasada.
func _measure_impact_speed(vehicle: Node, sim, settled_pose: Transform3D, hz: int) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var start := Transform3D(Basis(Vector3.UP, 0.0), settled_pose.origin + Vector3.UP * DROP_HEIGHT_M)
	vehicle._reset_to_transform(start)
	vehicle.freeze = false
	vehicle._reset_pending = false
	for t in 900:
		await physics_frame
		if _any_loaded(sim):
			var vy: float = vehicle.linear_velocity.y
			var y: float = vehicle.global_transform.origin.y
			return {"impact_vy": vy, "impact_y": y, "ticks": t, "fall_m": start.origin.y - y}
	return {"impact_vy": 0.0, "impact_y": NAN, "ticks": -1, "fall_m": NAN}


func _set_landing_state(vehicle: Node, sim, pose: Transform3D, v_down: float) -> void:
	vehicle._reset_to_transform(pose)
	vehicle.freeze = false
	vehicle._reset_pending = false
	var v := Vector3(0.0, -v_down, 0.0)
	vehicle.linear_velocity = v
	vehicle.angular_velocity = Vector3.ZERO
	for hub in sim.unsprung_rig.hubs:
		hub.freeze = false
		hub.linear_velocity = v
		hub.angular_velocity = Vector3.ZERO
		var hs := PhysicsServer3D.body_get_direct_state((hub as RigidBody3D).get_rid())
		if hs != null:
			hs.linear_velocity = v
			hs.angular_velocity = Vector3.ZERO
	var cs := PhysicsServer3D.body_get_direct_state((vehicle as RigidBody3D).get_rid())
	if cs != null:
		cs.linear_velocity = v
		cs.angular_velocity = Vector3.ZERO


# ---------------------------------------------------------------- aterrizaje
func _run_landing(cfg_name: String, rep: int) -> void:
	var cfg: Dictionary = CONFIGS[cfg_name]
	var hz := int(cfg["hz"])
	var env := await _prepare_scene(hz, bool(cfg["implicit"]), bool(cfg["limiter"]), int(cfg.get("substeps", opt_substeps)))
	if env.is_empty():
		check(false, "%s r%d: escena preparada" % [cfg_name, rep])
		return
	var scene = env["scene"]
	var vehicle = env["vehicle"]
	var sim = env["sim"]
	init_order += 1
	var order := init_order
	var settled := await _settle_pose(scene, vehicle, sim)
	var settled_pose: Transform3D = settled["pose"]
	var static_loads: Array = settled["static_loads"]
	var contact := await _calibrate_contact_y(vehicle, sim, settled_pose)
	var contact_y := float(contact["contact_y"])
	var impact := await _measure_impact_speed(vehicle, sim, settled_pose, hz)
	var v_impact := -float(impact["impact_vy"])
	if opt_impact_v > 0.0:
		v_impact = opt_impact_v
	check(is_finite(contact_y), "%s r%d: altura de contacto cargado calibrada" % [cfg_name, rep])
	check(v_impact > 1.5 and v_impact < 4.5, "%s r%d: impacto preparado %.2f m/s (caida medida %.3f m)" % [cfg_name, rep, v_impact, float(impact["fall_m"])])
	Engine.physics_ticks_per_second = hz
	var dt := 1.0 / float(hz)
	var pre_pose := Transform3D(Basis(Vector3.UP, 0.0), Vector3(settled_pose.origin.x, contact_y, settled_pose.origin.z))
	_set_landing_state(vehicle, sim, pre_pose, v_impact)
	# Aquí empieza la ventana de registro: activar subpasos acoplados.
	sim.unsprung_rig.coupled_substeps = pending_substeps
	var seq_at_reset := int(sim.unsprung_rig.tick_sequence)
	print("SUSPENSION_SEQ0 ", JSON.stringify({"config": cfg_name, "rep": rep, "tick_seq_at_reset": seq_at_reset, "pre_pose_y": pre_pose.origin.y, "deterministic_check": pending_substeps}))
	var max_ticks := int(round(opt_window_s * float(hz))) + CONTACT_SEARCH_TICKS
	var frames: Array = []
	var hub_masses: Array[float] = []
	for hub in sim.unsprung_rig.hubs:
		hub_masses.append(float((hub as RigidBody3D).mass))
	var contact_idx := -1
	var verify := {}
	var substep_rows: Array = []
	var sub_n := int(sim.unsprung_rig.coupled_substeps)
	var skipped_total := 0
	var skipped_max := 0
	var frames0 := Engine.get_physics_frames()
	for t in max_ticks:
		var pre_frames := Engine.get_physics_frames()
		await physics_frame
		var skipped: int = Engine.get_physics_frames() - pre_frames - 1
		var susp: Array = sim.sample_suspension_trace()
		var ticks: Array = sim.sample_tick_trace()
		var contacts: Array = sim.sample_contact_trace()
		var imp_trace: Array = sim.unsprung_rig.impulse_trace
		if sub_n > 1:
			var sst: Array = sim.unsprung_rig.substep_trace
			if not sst.is_empty():
				var sentry: Dictionary = sst[0]
				var srows: Array = sentry.get("rows", [])
				for k in sub_n:
					for w in 4:
						var wr: Dictionary = (srows[w] as Dictionary) if w < srows.size() else {}
						substep_rows.append({
							"tick": t, "sub": k, "wheel": w,
							"travel": float((wr.get("travel", []) as Array)[k]) if (wr.get("travel", []) as Array).size() > k else 0.0,
							"vel_rel": float((wr.get("vel_rel", []) as Array)[k]) if (wr.get("vel_rel", []) as Array).size() > k else 0.0,
							"comp": float((wr.get("comp", []) as Array)[k]) if (wr.get("comp", []) as Array).size() > k else 0.0,
							"damper": float((wr.get("damper_app", []) as Array)[k]) if (wr.get("damper_app", []) as Array).size() > k else 0.0,
							"elastic": float((wr.get("elastic", []) as Array)[k]) if (wr.get("elastic", []) as Array).size() > k else 0.0,
							"bump": float((wr.get("bump", []) as Array)[k]) if (wr.get("bump", []) as Array).size() > k else 0.0,
							"arb": float((wr.get("arb", []) as Array)[k]) if (wr.get("arb", []) as Array).size() > k else 0.0,
							"droop": float((wr.get("droop", []) as Array)[k]) if (wr.get("droop", []) as Array).size() > k else 0.0,
							"defl": float((wr.get("defl", []) as Array)[k]) if (wr.get("defl", []) as Array).size() > k else 0.0,
							"Fz": float((wr.get("Fz", []) as Array)[k]) if (wr.get("Fz", []) as Array).size() > k else 0.0,
							"loaded": bool((wr.get("loaded", []) as Array)[k]) if (wr.get("loaded", []) as Array).size() > k else false,
						})
		var loads: Array[float] = [0.0, 0.0, 0.0, 0.0]
		var bumps: Array[float] = [0.0, 0.0, 0.0, 0.0]
		var hub_vy: Array[float] = [0.0, 0.0, 0.0, 0.0]
		var chassis_vy: float = vehicle.linear_velocity.y
		var chassis_y: float = vehicle.global_transform.origin.y
		var chassis_vy_tick: float = float(((ticks[0] as Dictionary).get("chassis_vel", [0.0, 0.0, 0.0]) as Array)[1])
		var body_contacts: int = int(vehicle.get_contact_count())
		var body_impulse: float = float(vehicle.last_body_contact_vertical_impulse_ns)
		for w in 4:
			loads[w] = float((susp[w] as Dictionary).get("load_n", 0.0))
			bumps[w] = float(sim.suspension_model.last_bump_forces_n[w])
			var hv: Array = ((ticks[w] as Dictionary).get("hub_vel", [0.0, 0.0, 0.0]) as Array)
			hub_vy[w] = float(hv[1])
		frames.append({
			"chassis_vy": chassis_vy, "chassis_vy_tick": chassis_vy_tick,
			"chassis_y": chassis_y, "body_contacts": body_contacts,
			"body_impulse": body_impulse, "skipped": skipped,
			"loads": loads, "hub_vy": hub_vy, "bumps": bumps,
			"susp": susp, "ticks": ticks, "contacts": contacts, "imp": imp_trace,
		})
		if contact_idx < 0 and _any_loaded_from(loads):
			contact_idx = t
			var defls: Array = []
			for c in contacts:
				defls.append(float((c as Dictionary).get("radial_deflection_m", 0.0)))
			verify = {
				"pass_id": "%s_r%d" % [cfg_name, rep],
				"config": cfg_name, "hz": hz, "rep": rep, "init_order": order,
				"first_loaded_tick": t,
				"pre_pose_y": pre_pose.origin.y,
				"contact_y_calibrated": contact_y,
				"target_impact_vy": -v_impact,
				"separation_mm": (contact_y - pre_pose.origin.y) * 1000.0,
				"verify_chassis_y": chassis_y,
				"verify_vy": chassis_vy,
				"verify_vy_tick": chassis_vy_tick,
				"verify_hub_vy": hub_vy.duplicate(),
				"verify_deflection_m": defls,
				"verify_loads_n": loads.duplicate(),
				"impact_error_m_s": chassis_vy + v_impact,
				"measured_impact_vy": -float(impact["impact_vy"]),
				"measured_impact_fall_m": float(impact["fall_m"]),
				"static_loads_n": static_loads,
			}
		if contact_idx >= 0 and t >= contact_idx + int(round(opt_window_s * float(hz))):
			break
	if contact_idx < 0:
		check(false, "%s r%d: primer contacto cargado detectado" % [cfg_name, rep])
		scene.queue_free()
		await process_frame
		return
	print("SUSPENSION_LANDING_VERIFY ", JSON.stringify(verify))
	check(absf(float(verify["impact_error_m_s"])) < 0.40, "%s r%d: velocidad en primer contacto cargado %.2f m/s (objetivo %.2f)" % [
		cfg_name, rep, float(verify["verify_vy"]), -v_impact])
	var win_start := contact_idx
	var win_end := mini(frames.size() - 2, win_start + int(round(opt_window_s * float(hz))) - 1)
	var summary := _summarize_landing(cfg_name, hz, rep, order, verify, static_loads, frames, win_start, win_end, hub_masses, sim, substep_rows)
	summary["pass_id"] = "%s_r%d" % [cfg_name, rep]
	results.append(summary)
	_write_landing_csv(cfg_name, hz, rep, frames, win_start, win_end)
	_write_substep_csv(cfg_name, hz, rep, substep_rows)
	_write_substep_csv(cfg_name, hz, rep, substep_rows)
	print("SUSPENSION_LANDING_SUMMARY ", JSON.stringify(summary))
	scene.queue_free()
	await process_frame


func _any_loaded_from(loads: Array) -> bool:
	for l in loads:
		if float(l) > SUPPORT_EPS_N:
			return true
	return false


func _summarize_landing(cfg_name: String, hz: int, rep: int, order: int, verify: Dictionary, static_loads: Array, frames: Array, win_start: int, win_end: int, hub_masses: Array, sim, substep_rows: Array) -> Dictionary:
	var dt := 1.0 / float(hz)
	var n_ticks := win_end - win_start + 1
	var window_s := n_ticks * dt
	var total_mass := float((sim.mass_state as Dictionary).get("vehicle_total_mass_kg", 1200.0))
	var rig_chassis: RigidBody3D = sim.unsprung_rig.chassis
	var chassis_mass := float(rig_chassis.mass) if rig_chassis != null else total_mass
	var max_load: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var max_comp: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var bump_ticks: Array[int] = [0, 0, 0, 0]
	var loss_ticks: Array[int] = [0, 0, 0, 0]
	var rebound_v: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var impulse: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var radial_imp: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var finite_ok := true
	var tick_total: Array[float] = []
	var body_contact_ticks := 0
	var body_contact_first := -1
	var body_impulse_total := 0.0
	var weight := total_mass * GRAVITY
	for t in range(win_start, win_end + 1):
		var fr: Dictionary = frames[t]
		body_impulse_total += float(fr.get("body_impulse", 0.0))
		if int(fr.get("body_contacts", 0)) > 0:
			body_contact_ticks += 1
			if body_contact_first < 0:
				body_contact_first = t - win_start
		var loads: Array = fr["loads"]
		var hub_vy: Array = fr["hub_vy"]
		var susp: Array = fr["susp"]
		var imp: Array = fr["imp"]
		var tot := 0.0
		for w in 4:
			var s: Dictionary = susp[w]
			var load := float(loads[w])
			var comp := float(s.get("compression_m", 0.0))
			tot += load
			max_load[w] = maxf(max_load[w], load)
			max_comp[w] = maxf(max_comp[w], comp)
			if float((fr["bumps"] as Array)[w]) > 1.0:
				bump_ticks[w] += 1
			if not bool(s.get("loaded_contact", false)):
				loss_ticks[w] += 1
			rebound_v[w] = maxf(rebound_v[w], float(hub_vy[w]))
			impulse[w] += load * dt
			if w < imp.size():
				radial_imp[w] += float((imp[w] as Dictionary).get("J_radial_ns", 0.0))
			if not is_finite(load) or not is_finite(comp) or not is_finite(float(hub_vy[w])):
				finite_ok = false
		tick_total.append(tot)
	var total_impulse := 0.0
	for w in 4:
		total_impulse += impulse[w]
	var weight_impulse := weight * window_s
	var net_impulse := total_impulse - weight_impulse
	# Delta-momento con la MISMA fase (velocidad al inicio de tick) en ambos
	# extremos: el impulso de los ticks de la ventana cambia la velocidad de
	# inicio del tick siguiente al ultimo incluido.
	var fr0: Dictionary = frames[win_start]
	var fr1: Dictionary = frames[win_end + 1]
	var chassis_dv := float(fr1["chassis_vy_tick"]) - float(fr0["chassis_vy_tick"])
	var dp := chassis_mass * chassis_dv
	for w in 4:
		dp += float(hub_masses[w]) * (float((fr1["hub_vy"] as Array)[w]) - float((fr0["hub_vy"] as Array)[w]))
	var residual := net_impulse + body_impulse_total - dp
	# Picos: nativo y promediado en intervalos comunes de 16.67 ms.
	var bin_len := maxi(1, int(round(BIN_S / dt)))
	var bin_peak := 0.0
	var bins := int(ceil(float(n_ticks) / float(bin_len)))
	for b in bins:
		var ssum := 0.0
		var c := 0
		for k in bin_len:
			var idx := b * bin_len + k
			if idx < n_ticks:
				ssum += tick_total[idx]
				c += 1
		if c > 0:
			bin_peak = maxf(bin_peak, ssum / float(c))
	var native_peak := 0.0
	for v in tick_total:
		native_peak = maxf(native_peak, v)
	# Asentamiento (criterio independiente de la frecuencia): 20 ticks con
	# |compresion| < 5 mm, |vel. buje| < 0.35 m/s, las cuatro ruedas cargadas y
	# carga total dentro del 10 % del peso.
	var settle_tick := -1
	var calm := 0
	for i in n_ticks:
		var fr: Dictionary = frames[win_start + i]
		var cmax := 0.0
		var vmax := 0.0
		var tot_i := 0.0
		var all_loaded := true
		for w in 4:
			cmax = maxf(cmax, absf(float((fr["susp"] as Array)[w].get("compression_m", 0.0))))
			vmax = maxf(vmax, absf(float((fr["hub_vy"] as Array)[w])))
			tot_i += float((fr["loads"] as Array)[w])
			if float((fr["loads"] as Array)[w]) <= SUPPORT_EPS_N:
				all_loaded = false
		if cmax < SETTLE_COMP_M and vmax < SETTLE_VEL_M_S and all_loaded and absf(tot_i - weight) < SETTLE_LOAD_FRAC * weight:
			calm += 1
			if calm >= SETTLE_HOLD_TICKS:
				settle_tick = i - SETTLE_HOLD_TICKS + 1
				break
		else:
			calm = 0
	var support_loss_total := 0
	for w in 4:
		support_loss_total += loss_ticks[w]
	var skipped_total := 0
	for fr in frames:
		skipped_total += int(fr.get("skipped", 0))
	var support_recovered := true
	for i in range(maxi(0, n_ticks - SETTLE_HOLD_TICKS), n_ticks):
		var fr: Dictionary = frames[win_start + i]
		for w in 4:
			if float((fr["loads"] as Array)[w]) <= SUPPORT_EPS_N:
				support_recovered = false
	var settled := settle_tick >= 0 and support_recovered
	# Predicho vs observado (solo modo subpasos): error de la predicción del
	# tick anterior frente al estado medido, con gravedad descontada aparte.
	var pred_err_hub_max := 0.0
	var pred_err_hub_mean := 0.0
	var pred_err_chassis_max := 0.0
	var pred_err_chassis_mean := 0.0
	var pred_n := 0
	for i in n_ticks:
		var fr: Dictionary = frames[win_start + i]
		var imp: Array = fr.get("imp", [])
		for w in 4:
			if w < imp.size():
				var im: Dictionary = imp[w]
				if im.has("pred_err_hub_v"):
					var e := absf(float(im.get("pred_err_hub_v", 0.0)))
					pred_err_hub_max = maxf(pred_err_hub_max, e)
					pred_err_hub_mean += e
					pred_n += 1
		var im0: Dictionary = imp[0] if imp.size() > 0 else {}
		if im0.has("pred_err_chassis_v"):
			var ec := absf(float(im0.get("pred_err_chassis_v", 0.0)))
			pred_err_chassis_max = maxf(pred_err_chassis_max, ec)
			pred_err_chassis_mean += ec
	if pred_n > 0:
		pred_err_hub_mean /= float(pred_n)
		pred_err_chassis_mean /= float(n_ticks)
	var sub_n := int(sim.unsprung_rig.coupled_substeps)
	return {
		"config": cfg_name, "hz": hz, "rep": rep, "init_order": order,
		"window_s": window_s, "window_ticks": n_ticks,
		"contact_tick_abs": win_start,
		"static_loads_n": static_loads,
		"max_load_n": max_load,
		"max_compression_m": max_comp,
		"bump_stop_ticks": bump_ticks,
		"support_loss_ticks": loss_ticks,
		"support_loss_total": support_loss_total,
		"skipped_ticks_total": skipped_total,
		"rebound_hub_vy_m_s": rebound_v,
		"impulse_per_wheel_ns": impulse,
		"radial_impulse_per_wheel_ns": radial_imp,
		"total_impulse_ns": total_impulse,
		"weight_impulse_ns": weight_impulse,
		"net_vertical_impulse_ns": net_impulse,
		"body_contact_ticks": body_contact_ticks,
		"body_contact_first_tick": body_contact_first,
		"body_impulse_ns": body_impulse_total,
		"momentum_change_ns": dp,
		"impulse_residual_ns": residual,
		"impulse_residual_frac": residual / maxf(absf(dp), 1.0),
		"peak_total_load_native_n": native_peak,
		"peak_total_load_bin67_n": bin_peak,
		"total_mass_kg": total_mass,
		"chassis_mass_kg": chassis_mass,
		"settle_tick": settle_tick,
		"support_recovered": support_recovered,
		"settled": settled,
		"finite_ok": finite_ok,
		"coupled_substeps": sub_n,
		"pred_err_hub_v_max": pred_err_hub_max,
		"pred_err_hub_v_mean": pred_err_hub_mean,
		"pred_err_chassis_v_max": pred_err_chassis_max,
		"pred_err_chassis_v_mean": pred_err_chassis_mean,
		"verify": verify,
		"tick_total_loads": tick_total,
	}


func _write_substep_csv(cfg_name: String, hz: int, rep: int, substep_rows: Array) -> void:
	var path := "%s/substep_%s_hz%d_r%d.csv" % [opt_out.rstrip("/"), cfg_name, hz, rep]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("no se pudo abrir " + path)
		return
	f.store_line("config,hz,rep,tick,sub,wheel,travel_m,vel_rel_m_s,comp_m,damper_app_n,elastic_n,bump_n,arb_n,droop_n,defl_m,Fz_n,loaded")
	for r in substep_rows:
		var d: Dictionary = r
		f.store_line("%s,%d,%d,%d,%d,%d,%.5f,%.4f,%.5f,%.1f,%.1f,%.1f,%.1f,%.1f,%.5f,%.1f,%d" % [
			cfg_name, hz, rep, int(d.get("tick", 0)), int(d.get("sub", 0)), int(d.get("wheel", 0)),
			float(d.get("travel", 0.0)), float(d.get("vel_rel", 0.0)), float(d.get("comp", 0.0)),
			float(d.get("damper", 0.0)), float(d.get("elastic", 0.0)), float(d.get("bump", 0.0)),
			float(d.get("arb", 0.0)), float(d.get("droop", 0.0)), float(d.get("defl", 0.0)), float(d.get("Fz", 0.0)),
			int(bool(d.get("loaded", false))),
		])
	f.close()


func _write_landing_csv(cfg_name: String, hz: int, rep: int, frames: Array, win_start: int, win_end: int) -> void:
	var path := "%s/landing_%s_hz%d_r%d.csv" % [opt_out.rstrip("/"), cfg_name, hz, rep]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("no se pudo abrir " + path)
		return
	f.store_line("config,hz,rep,tick,wheel,load_n,compression_m,hub_travel_m,hub_vy_m_s,geom,loaded,damper_app_n,bump_n,radial_defl_m,chassis_y,chassis_vy_tick,rel_vel_m_s,radial_imp_ns,radial_F_mean_n,body_contacts,body_impulse_ns,tick_seq")
	for t in range(win_start, win_end + 1):
		var fr: Dictionary = frames[t]
		var susp: Array = fr["susp"]
		var ticks: Array = fr["ticks"]
		var contacts: Array = fr["contacts"]
		var imp: Array = fr["imp"]
		for w in 4:
			var s: Dictionary = susp[w]
			var tk: Dictionary = ticks[w]
			var ct: Dictionary = contacts[w] if w < contacts.size() else {}
			var im: Dictionary = imp[w] if w < imp.size() else {}
			var hv: Array = (tk.get("hub_vel", [0.0, 0.0, 0.0]) as Array)
			f.store_line("%s,%d,%d,%d,%d,%.2f,%.5f,%.5f,%.4f,%d,%d,%.1f,%.1f,%.5f,%.5f,%.4f,%.4f,%.4f,%.1f,%d,%.1f,%d" % [
				cfg_name, hz, rep, t - win_start, w,
				float(s.get("load_n", 0.0)), float(s.get("compression_m", 0.0)),
				float(s.get("hub_travel_m", 0.0)), float(hv[1]),
				int(bool(s.get("geometric_contact", false))), int(bool(s.get("loaded_contact", false))),
				float(s.get("damper_applied_n", 0.0)), float((fr["bumps"] as Array)[w]),
				float(ct.get("radial_deflection_m", 0.0)),
				float(fr["chassis_y"]), float(fr["chassis_vy_tick"]),
				float(s.get("compression_velocity_m_s", 0.0)),
				float(im.get("J_radial_ns", 0.0)), float(im.get("radial_F_mean_n", 0.0)),
				int(fr.get("body_contacts", 0)), float(fr.get("body_impulse", 0.0)),
				int(im.get("tick_seq", -1)),
			])
	f.close()


func _report_compare() -> void:
	for cfg_name in opt_configs:
		var group: Array = []
		for r in results:
			if str(r.get("config", "")) == cfg_name:
				group.append(r)
		if group.size() < 2:
			continue
		var base: Dictionary = group[0]
		var divergent: Array[int] = []
		for other in group.slice(1):
			var a: Array = base["tick_total_loads"]
			var b: Array = other["tick_total_loads"]
			var first := -1
			for i in mini(a.size(), b.size()):
				if absf(float(a[i]) - float(b[i])) > 1.0:
					first = i
					break
			divergent.append(first)
		print("SUSPENSION_LANDING_DETERMINISM ", JSON.stringify({
			"config": cfg_name, "reps": group.size(), "first_divergent_ticks": divergent,
			"settled": group.map(func(g): return bool(g.get("settled", false))),
			"settle_ticks": group.map(func(g): return int(g.get("settle_tick", -1))),
			"peaks_bin67": group.map(func(g): return float(g.get("peak_total_load_bin67_n", 0.0))),
			"impulse": group.map(func(g): return float(g.get("total_impulse_ns", 0.0))),
		}))
	var control: Array = []
	for r in results:
		if str(r.get("config", "")) == "base120":
			control.append(r)
	var tolerance := {}
	if control.size() >= 2:
		for m in ["peak_total_load_bin67_n", "total_impulse_ns", "net_vertical_impulse_ns", "momentum_change_ns", "settle_tick"]:
			var vals: Array[float] = []
			for c in control:
				vals.append(float(c.get(m, 0.0)))
			var mean := 0.0
			for v in vals:
				mean += v
			mean /= maxf(float(vals.size()), 1.0)
			var spread := 0.0
			for v in vals:
				spread = maxf(spread, absf(v - mean))
			tolerance[m] = {"mean": mean, "max_abs_dev": spread, "tol": maxf(spread, absf(mean) * 0.02)}
	print("SUSPENSION_LANDING_TOLERANCE ", JSON.stringify(tolerance))
	for cfg_name in opt_configs:
		var group: Array = []
		for r in results:
			if str(r.get("config", "")) == cfg_name:
				group.append(r)
		if group.is_empty():
			continue
		if cfg_name == "base120" and not bool(group[0].get("settled", false)):
			# Control: se compara su dispersiÃ³n y sus picos; el criterio de
			# asentamiento se exige al candidato. Si el control tampoco asienta
			# dentro de la ventana, se informa (no se penaliza al candidato).
			print("SUSPENSION_LANDING_COMPARE_NOTE ", JSON.stringify({
				"config": cfg_name,
				"note": "control sin asentamiento dentro de la ventana de comparacion",
			}))
		var agg := {
			"config": cfg_name,
			"hz": int(group[0]["hz"]),
			"reps": group.size(),
			"settled_all": group.all(func(g): return bool(g.get("settled", false))),
			"finite_all": group.all(func(g): return bool(g.get("finite_ok", false))),
			"support_loss_total_mean": _mean_of(group, "support_loss_total"),
			"peak_bin67_mean": _mean_of(group, "peak_total_load_bin67_n"),
			"native_peak_mean": _mean_of(group, "peak_total_load_native_n"),
			"total_impulse_mean": _mean_of(group, "total_impulse_ns"),
			"momentum_change_mean": _mean_of(group, "momentum_change_ns"),
			"body_impulse_mean": _mean_of(group, "body_impulse_ns"),
			"body_contact_ticks_mean": _mean_of(group, "body_contact_ticks"),
			"impulse_residual_frac_mean": _mean_of(group, "impulse_residual_frac"),
			"settle_tick_mean": _mean_of(group, "settle_tick"),
			"bump_ticks_total_mean": _mean_of_arr(group, "bump_stop_ticks"),
			"max_compression_max": _max_of_arr(group, "max_compression_m"),
			"max_load_max_n": _max_of_arr(group, "max_load_n"),
		}
		print("SUSPENSION_LANDING_COMPARE ", JSON.stringify(agg))
		if cfg_name != "base120":
			check(bool(agg["settled_all"]), "%s: todas las pasadas recuperan apoyo y asientan" % cfg_name)
		check(bool(agg["finite_all"]), "%s: cargas finitas" % cfg_name)
		var loss := float(agg["support_loss_total_mean"])
		var window_ticks := int(round(opt_window_s * float(group[0]["hz"])))
		check(loss <= float(window_ticks) * 4.0 * 0.30, "%s: perdida de apoyo acotada (%d wheel-ticks)" % [cfg_name, int(loss)])


func _mean_of(group: Array, key: String) -> float:
	var s := 0.0
	for g in group:
		s += float(g.get(key, 0.0))
	return s / maxf(float(group.size()), 1.0)


func _mean_of_arr(group: Array, key: String) -> float:
	var s := 0.0
	var n := 0
	for g in group:
		for v in (g.get(key, []) as Array):
			s += float(v)
			n += 1
	return s / maxf(float(n), 1.0)


func _max_of_arr(group: Array, key: String) -> float:
	var m := 0.0
	for g in group:
		for v in (g.get(key, []) as Array):
			m = maxf(m, float(v))
	return m


# ------------------------------------------------------------------ manejo
func _run_handling(cfg_name: String, maneuver: String, rep: int = 0) -> void:
	var cfg: Dictionary = CONFIGS[cfg_name]
	var hz := int(cfg["hz"])
	var env := await _prepare_scene(hz, bool(cfg["implicit"]), bool(cfg["limiter"]), int(cfg.get("substeps", opt_substeps)))
	if env.is_empty():
		check(false, "%s %s: escena preparada" % [cfg_name, maneuver])
		return
	var scene = env["scene"]
	var vehicle = env["vehicle"]
	var sim = env["sim"]
	init_order += 1
	var settled := await _settle_pose(scene, vehicle, sim)
	var settled_pose: Transform3D = settled["pose"]
	Engine.physics_ticks_per_second = hz
	var entry_speed := 15.0
	var start_pos: Vector3 = settled_pose.origin
	if maneuver == "crest":
		start_pos = Vector3(-15.0, settled_pose.origin.y, -10.0)
	elif maneuver == "corner":
		entry_speed = 12.0
	vehicle._reset_to_transform(Transform3D(Basis(Vector3.UP, 0.0), start_pos))
	vehicle.freeze = false
	vehicle._reset_pending = false
	# Ventana de registro de manejo: activar subpasos acoplados.
	sim.unsprung_rig.coupled_substeps = pending_substeps
	var fwd: Vector3 = -vehicle.global_transform.basis.z
	vehicle.linear_velocity = fwd * entry_speed
	vehicle.angular_velocity = Vector3.ZERO
	for hub in sim.unsprung_rig.hubs:
		hub.freeze = false
		hub.linear_velocity = fwd * entry_speed
		hub.angular_velocity = Vector3.ZERO
	sim.powertrain_model.set_gear(1)
	var duration_s := 6.0 if maneuver == "corner" else 4.0
	var ticks := int(round(duration_s * float(hz)))
	var rows: Array = []
	for t in ticks:
		var ts := float(t) / float(hz)
		match maneuver:
			"brake":
				vehicle.throttle_input = 0.0
				vehicle.brake_input = 1.0
				vehicle.steering_input = 0.0
			"corner":
				vehicle.throttle_input = 0.45
				vehicle.steering_input = clampf(ts / 0.5, 0.0, 1.0) * 0.35 * opt_steer_gain
				vehicle.brake_input = 0.0
			"crest":
				vehicle.throttle_input = 0.6
				vehicle.steering_input = 0.0
				vehicle.brake_input = 0.0
		vehicle.handbrake_input = 0.0
		await physics_frame
		var susp: Array = sim.sample_suspension_trace()
		var origin: Vector3 = vehicle.global_transform.origin
		var ang: Vector3 = vehicle.angular_velocity
		var speed: float = vehicle.linear_velocity.length()
		var forward_speed: float = vehicle.linear_velocity.dot(-vehicle.global_transform.basis.z)
		for w in 4:
			var s: Dictionary = susp[w]
			rows.append({
				"t": ts, "wheel": w,
				"load": float(s.get("load_n", 0.0)),
				"comp": float(s.get("compression_m", 0.0)),
				"loaded": bool(s.get("loaded_contact", false)),
				"z": origin.z, "y": origin.y, "speed": speed,
				"forward_speed": forward_speed, "yaw_rate": ang.y,
			})
	var summary := _summarize_handling(cfg_name, maneuver, hz, entry_speed, rows, duration_s)
	summary["init_order"] = init_order
	summary["rep"] = rep
	summary["pass_id"] = "%s_%s_r%d" % [cfg_name, maneuver, rep]
	results.append(summary)
	_write_handling_csv(cfg_name, maneuver, hz, rows, rep)
	print("SUSPENSION_HANDLING_SUMMARY ", JSON.stringify(summary))
	scene.queue_free()
	await process_frame


func _summarize_handling(cfg_name: String, maneuver: String, hz: int, entry_speed: float, rows: Array, duration_s: float) -> Dictionary:
	var n_ticks := 0
	for r in rows:
		if int(r["wheel"]) == 0:
			n_ticks += 1
	var dt := duration_s / maxf(float(n_ticks), 1.0)
	var dist := 0.0
	for r in rows:
		if int(r["wheel"]) == 0:
			dist += float(r["forward_speed"]) * dt
	var exit_speed := 0.0
	var yaw_peak := 0.0
	var rear_loss := 0
	var rear_total := 0
	var min_rear_load := INF
	for r in rows:
		if int(r["t"]) == n_ticks - 1 and int(r["wheel"]) == 0:
			exit_speed = float(r["forward_speed"])
		yaw_peak = maxf(yaw_peak, absf(float(r["yaw_rate"])))
		if int(r["wheel"]) in [2, 3]:
			rear_total += 1
			if not bool(r["loaded"]):
				rear_loss += 1
			min_rear_load = minf(min_rear_load, float(r["load"]))
	return {
		"config": cfg_name, "maneuver": maneuver, "hz": hz,
		"steer_gain": opt_steer_gain,
		"entry_speed_m_s": entry_speed, "duration_s": duration_s,
		"braking_distance_m": dist if maneuver == "brake" else 0.0,
		"distance_m": dist,
		"exit_forward_speed_m_s": exit_speed,
		"yaw_peak_rad_s": yaw_peak,
		"rear_support_loss_ticks": rear_loss,
		"rear_support_loss_frac": float(rear_loss) / maxf(float(rear_total), 1.0),
		"min_rear_load_n": min_rear_load if is_finite(min_rear_load) else 0.0,
	}


func _write_handling_csv(cfg_name: String, maneuver: String, hz: int, rows: Array, rep: int = 0) -> void:
	var path := "%s/handling_%s_%s_hz%d_r%d.csv" % [opt_out.rstrip("/"), cfg_name, maneuver, hz, rep]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("config,maneuver,hz,t,wheel,load_n,compression_m,loaded,z,y,speed_m_s,forward_speed_m_s,yaw_rate_rad_s")
	for r in rows:
		f.store_line("%s,%s,%d,%.4f,%d,%.2f,%.5f,%d,%.4f,%.4f,%.4f,%.4f,%.5f" % [
			cfg_name, maneuver, hz, float(r["t"]), int(r["wheel"]),
			float(r["load"]), float(r["comp"]), int(bool(r["loaded"])),
			float(r["z"]), float(r["y"]), float(r["speed"]), float(r["forward_speed"]), float(r["yaw_rate"]),
		])
	f.close()
