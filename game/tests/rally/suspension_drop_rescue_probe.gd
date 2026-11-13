extends SceneTree
## suspension_drop_rescue_probe.gd — Sonda headless de recalibración 60 Hz.
##
## Alcance §SUSPENSION_RECALIBRATION_60HZ_PLAN:
##  - Fija Jolt a 60 Hz durante toda la campaña y comprueba el tick efectivo
##    en cada traza (Engine.physics_ticks_per_second, physics/3d/physics_engine,
##    dt_s por tick, tick_id monotónico, subpasos del neumático).
##  - Usa ShapeCast3D, el catálogo actual, los mismos subpasos del neumático y
##    el mismo setup de referencia por coche (RallySetupCatalog.defaults).
##  - Calibra únicamente front/rear.ride_frequency_hz y damping_ratio de los
##    perfiles activos; los multiplicadores de compresión/rebote se conservan.
##  - Confirma el manifiesto que carga cada variante antes de tocar upgrades.
##
## Maniobras (§1): reposo en plano, caída simétrica 0.5 m, bache de una rueda,
## frenada recta, curva lisa con gas constante, salida con rampa de gas y
## salida sobre cresta. Cada caso repite pose, velocidad (0), combustible y
## temperatura inicial. Guarda CSV por tick y resumen por perfil/maniobra/
## candidato. Registra recorrido físico y velocidad relativa del buje, cargas,
## fuerzas de muelle/amortiguador/tope, pérdidas de contacto, guiñada y deriva.
##
## Barridos (§2): f por eje ±5 %/±10 % con zeta fija; después zeta ±0.05/±0.10
## con f elegida; combinaciones en memoria vía apply_setup_values (sin tocar
## disco hasta aceptación). Control Escort + combustible bajo/nominal.
##
## Uso:
##   godot --headless --path game --script res://tests/rally/suspension_drop_rescue_probe.gd
##   godot --headless --path game --script res://tests/rally/suspension_drop_rescue_probe.gd -- --profiles=escort,fulvia,rt-mini-cooper-s --maneuvers=rest,drop,bump,brake,corner,exit_ramp,crest --fuel-kg=25.0 --sweep=none --repeats=1
##   ... -- --sweep=full  (17 candidatos: base + 8 f + 8 zeta)
##   ... -- --sweep=f --fuel-sweep (repite nominal + bajo 5 kg)
##
## Salidas: marcadores SUSPENSION_TICK_EFFECTIVE / SUSPENSION_CANDIDATE_RATES /
## SUSPENSION_MANEUVER_SUMMARY / SUSPENSION_DIVERGENCE / SUSPENSION_DROP_RESULT /
## SUSPENSION_RESCUE_RESULT + CSV por ejecución en user://suspension_60hz/.

const EXPECTED_PHYSICS_HZ := 60
const EXPECTED_PHYSICS_ENGINE := "Jolt Physics"
const EXPECTED_CONTACT_QUERY := "ShapeCast3D"
const EXPECTED_CONTACT_SHAPES := 1
const DROP_HEIGHT_M := 0.5
const LOW_FUEL_KG := 5.0
const DEFAULT_FUEL_KG := 25.0
const REPEAT_TOL_MIN_REL := 0.01

## Tabla de partida del plan (f Hz / zeta por eje). El Escort es control.
const BASELINE_TUNE := {
	"escort": {"f_front": 1.6737692722839896, "f_rear": 1.701101815559341, "z_front": 0.3380336517607532, "z_rear": 0.6680211208461856},
	"fulvia": {"f_front": 1.75, "f_rear": 1.85, "z_front": 0.55, "z_rear": 0.55},
	"rt": {"f_front": 1.7, "f_rear": 1.8, "z_front": 0.5, "z_rear": 0.5},
}

const PROFILE_SCENES := {
	"escort": "res://scenes/rally/rally_proving_ground.tscn",
	"fulvia": "res://scenes/rally/rally_proving_ground_fulvia.tscn",
}

const MANEUVER_IDS := ["rest", "drop", "bump", "brake", "corner", "exit_ramp", "crest"]

var failures: Array[String] = []
var drop_results: Array[Dictionary] = []
var summaries: Array[Dictionary] = []
var opt_profiles: Array[String] = ["escort", "fulvia", "rt-mini-cooper-s"]
var opt_maneuvers: Array[String] = ["rest", "drop", "bump", "brake", "corner", "exit_ramp", "crest"]
var opt_fuel_kg := DEFAULT_FUEL_KG
var opt_fuel_sweep := false
var opt_sweep := "none"
var opt_repeats := 1
var opt_out_dir := "user://suspension_60hz"
var opt_diag := "base"
var opt_settle120 := false
var baseline_traces := {}


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


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		var s := str(a)
		if s.begins_with("--profiles="):
			var raw := s.trim_prefix("--profiles=").split(",")
			var cleaned: Array[String] = []
			for p in raw:
				var k := str(p).strip_edges().to_lower()
				if not k.is_empty():
					cleaned.append(k)
			if not cleaned.is_empty():
				opt_profiles = cleaned
		elif s.begins_with("--maneuvers="):
			var raw2: PackedStringArray = s.split("=")[1].split(",")
			var cleaned2: Array[String] = []
			for m in raw2:
				var k2 := str(m).strip_edges().to_lower()
				if k2 in MANEUVER_IDS:
					cleaned2.append(k2)
			if not cleaned2.is_empty():
				opt_maneuvers = cleaned2
		elif s.begins_with("--maneuver="):
			var single := s.trim_prefix("--maneuver=").strip_edges().to_lower()
			if single in MANEUVER_IDS:
				opt_maneuvers = [single]
		elif s.begins_with("--fuel-kg="):
			opt_fuel_kg = clampf(float(s.trim_prefix("--fuel-kg=")), 0.0, 45.0)
		elif s == "--fuel-sweep":
			opt_fuel_sweep = true
		elif s.begins_with("--sweep="):
			var mode := s.trim_prefix("--sweep=").strip_edges().to_lower()
			if mode in ["none", "f", "z", "full"]:
				opt_sweep = mode
		elif s.begins_with("--repeats="):
			opt_repeats = maxi(1, int(s.trim_prefix("--repeats=")))
		elif s.begins_with("--diag="):
			var dv := s.trim_prefix("--diag=").strip_edges().to_lower()
			if dv in ["base", "limiter", "novisc", "implicit", "implicit_limiter"]:
				opt_diag = dv
		elif s == "--settle120":
			opt_settle120 = true
		elif s.begins_with("--out-dir="):
			var d := s.trim_prefix("--out-dir=").strip_edges()
			if not d.is_empty():
				opt_out_dir = d


func _baseline_for(profile_key: String) -> Dictionary:
	if profile_key == "escort":
		return (BASELINE_TUNE["escort"] as Dictionary).duplicate(true)
	if profile_key == "fulvia" or profile_key == "lancia-fulvia":
		return (BASELINE_TUNE["fulvia"] as Dictionary).duplicate(true)
	return (BASELINE_TUNE["rt"] as Dictionary).duplicate(true)


func _proving_scene_for(profile_key: String) -> String:
	if PROFILE_SCENES.has(profile_key):
		return str(PROFILE_SCENES[profile_key])
	if profile_key.begins_with("rt-"):
		return "res://scenes/rally/rt/%s_proving.tscn" % profile_key
	return ""


func _profile_path_for(profile_key: String) -> String:
	if profile_key == "escort":
		return "res://data/vehicles/ford-escort-rs2000/vehicle.json"
	if profile_key == "fulvia" or profile_key == "lancia-fulvia":
		return "res://data/vehicles/lancia-fulvia/vehicle.json"
	return "res://data/vehicles/rt/%s/vehicle.json" % profile_key


func _provenance_for(profile_key: String) -> String:
	if profile_key == "escort":
		return "res://data/vehicles/ford-escort-rs2000/OPEN_FORMULA_PROVENANCE.json"
	if profile_key == "fulvia" or profile_key == "lancia-fulvia":
		return "res://data/vehicles/lancia-fulvia/HISTORICAL_PROVENANCE.json"
	return "res://data/vehicles/rt/%s/HISTORICAL_PROVENANCE.json" % profile_key


func _verify_global_physics() -> Dictionary:
	var hz := int(Engine.physics_ticks_per_second)
	var eng := str(ProjectSettings.get_setting("physics/3d/physics_engine", ""))
	var hz_ok := hz == EXPECTED_PHYSICS_HZ
	var eng_ok := eng == EXPECTED_PHYSICS_ENGINE
	check(hz_ok, "Jolt a 60 Hz fijado (physics_ticks_per_second=%d)" % hz)
	check(eng_ok, "motor físico Jolt (physics_engine=%s)" % eng)
	var info := {
		"physics_hz_setting": hz,
		"physics_engine": eng,
		"expected_hz": EXPECTED_PHYSICS_HZ,
		"expected_engine": EXPECTED_PHYSICS_ENGINE,
	}
	print("SUSPENSION_TICK_EFFECTIVE_GLOBAL ", JSON.stringify(info))
	return info


func _confirm_manifest(profile_key: String) -> Dictionary:
	var profile_path := _profile_path_for(profile_key)
	var prov_path := _provenance_for(profile_key)
	var loaded := VehicleProfileLoader.load_profile(profile_path)
	var ok := bool(loaded.get("ok", false))
	check(ok, "%s: manifiesto %s carga" % [profile_key, profile_path])
	var suspension: Dictionary = {}
	var qtype := ""
	var qcount := -1
	if ok:
		var domains: Dictionary = loaded["domains"]
		suspension = (domains.get("suspension", {}) as Dictionary).get("suspension", {})
		qtype = str(suspension.get("contact_query_type", ""))
		qcount = int(suspension.get("contact_shape_count", -1))
		check(qtype == EXPECTED_CONTACT_QUERY, "%s: ShapeCast3D (got %s)" % [profile_key, qtype])
		check(qcount == EXPECTED_CONTACT_SHAPES, "%s: 1 forma por rueda (got %d)" % [profile_key, qcount])
	var upgrade_probe := "res://data/vehicles/rt/%s-upgrade/vehicle.json" % profile_key
	var upgrade_is_profile := FileAccess.file_exists(upgrade_probe)
	var out := {
		"profile": profile_key,
		"manifest": profile_path,
		"provenance": prov_path,
		"loads": ok,
		"contact_query_type": qtype,
		"contact_shape_count": qcount,
		"upgrade_dir_is_standalone_profile": upgrade_is_profile,
	}
	print("SUSPENSION_MANIFEST_CONFIRMED ", JSON.stringify(out))
	return out


func run() -> void:
	print("--- SUSPENSION 60HZ RECALIBRATION PROBE ---")
	_parse_args()
	_ensure_out_dir(opt_out_dir)
	Engine.physics_ticks_per_second = EXPECTED_PHYSICS_HZ
	var global_info := _verify_global_physics()
	await _run_legacy_matrix()
	for profile_key in opt_profiles:
		var scene_path := _proving_scene_for(profile_key)
		if scene_path.is_empty() or not FileAccess.file_exists(scene_path):
			check(false, "%s: escena proving %s no encontrada" % [profile_key, scene_path])
			continue
		_confirm_manifest(profile_key)
		await _run_profile_campaign(profile_key, scene_path, global_info)
	if failures.is_empty():
		print("\nSUSPENSION 60HZ PROBE DONE (%d resumenes)" % summaries.size())
		quit(0)
	else:
		print("\nPROBE FAILED:")
		for f in failures:
			print("  - ", f)
		quit(1)


func _ensure_out_dir(path: String) -> void:
	if path.begins_with("user://"):
		var sub := path.trim_prefix("user://")
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.make_dir_recursive(sub)
	else:
		DirAccess.make_dir_recursive_absolute(path)


func _run_legacy_matrix() -> void:
	var scene_path := _proving_scene_for("escort")
	if not FileAccess.file_exists(scene_path):
		check(false, "legado: escena escort no encontrada")
		return
	var scene = load(scene_path).instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 240:
		await physics_frame
		if scene.session_ready:
			break
	if not scene.session_ready:
		failures.append("proving ground session ready (legado)")
		push_error("FAIL: proving ground session ready (legado)")
		quit(1)
		return
	var vehicle = scene.vehicle
	var ctl = scene.input_controller
	ctl.set_physics_process(false)
	vehicle.throttle_input = 0.0
	vehicle.brake_input = 0.0
	vehicle.steering_input = 0.0
	vehicle.handbrake_input = 0.0
	for i in 120:
		await physics_frame
	var base_pose: Transform3D = vehicle.global_transform
	var drop_origin: Vector3 = base_pose.origin + Vector3.UP * DROP_HEIGHT_M
	var drop_pose := Transform3D(base_pose.basis, drop_origin)
	for tandem in [true, false]:
		vehicle.simulation.tandem_cam_enabled = tandem
		for limit in [false, true]:
			vehicle.simulation.set_damper_impulse_limit(limit)
			var r := await _run_drop(vehicle, drop_pose, tandem, limit)
			drop_results.append(r)
			print("SUSPENSION_DROP_RESULT ", JSON.stringify(r))
	check(true, "caidas 0,5 m completadas (%d configs)" % drop_results.size())
	var rescue := await _run_rescue_comparison(vehicle, drop_pose)
	print("SUSPENSION_RESCUE_RESULT ", JSON.stringify(rescue))
	check(bool(rescue.get("ok", false)), "rescate comparativo con traza por tick")
	scene.queue_free()
	await process_frame


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
		"drop_m": DROP_HEIGHT_M,
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
	vehicle._reset_to_transform(pose)
	for i in 8:
		await physics_frame
	var post_fresh := await _sample_ticks(vehicle, 5)
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


func _run_profile_campaign(profile_key: String, scene_path: String, _global: Dictionary) -> void:
	var scene = load(scene_path).instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 240:
		await physics_frame
		if scene.session_ready:
			break
	if not scene.session_ready:
		check(false, "%s: session ready" % profile_key)
		scene.queue_free()
		await process_frame
		return
	var vehicle = scene.vehicle
	var ctl = scene.input_controller
	ctl.set_physics_process(false)
	vehicle.throttle_input = 0.0
	vehicle.brake_input = 0.0
	vehicle.steering_input = 0.0
	vehicle.handbrake_input = 0.0
	for i in 120:
		await physics_frame
	var base_pose: Transform3D = vehicle.global_transform
	var fuel_levels: Array[float] = [opt_fuel_kg]
	if opt_fuel_sweep:
		if absf(opt_fuel_kg - LOW_FUEL_KG) > 0.01:
			fuel_levels = [opt_fuel_kg, LOW_FUEL_KG]
		else:
			fuel_levels = [opt_fuel_kg, DEFAULT_FUEL_KG]
	for fuel_kg in fuel_levels:
		for maneuver in opt_maneuvers:
			var candidates := _candidate_list(profile_key, opt_sweep)
			var baseline_key := _trace_key(profile_key, maneuver, fuel_kg, "base")
			for ci in candidates.size():
				var cand: Dictionary = candidates[ci]
				for rep in opt_repeats:
					var label := str(cand.get("label", "base"))
					if opt_repeats > 1:
						label = "%s_r%d" % [label, rep]
					var summary := await _run_single_maneuver(scene, vehicle, base_pose, profile_key, maneuver, cand, fuel_kg, label)
					summaries.append(summary)
					print("SUSPENSION_MANEUVER_SUMMARY ", JSON.stringify(summary))
					if str(cand.get("label", "base")) == "base" and rep == 0:
						baseline_traces[baseline_key] = summary.get("trace_ref", [])
					if str(cand.get("label", "base")) != "base":
						var div := _first_divergence(baseline_key, summary)
						print("SUSPENSION_DIVERGENCE ", JSON.stringify(div))
	scene.queue_free()
	await process_frame


func _trace_key(profile_key: String, maneuver: String, fuel_kg: float, label: String) -> String:
	return "%s|%s|%.1f|%s" % [profile_key, maneuver, fuel_kg, label]


func _candidate_list(profile_key: String, mode: String) -> Array:
	var base := _baseline_for(profile_key)
	var out: Array = [{"label": "base", "f_front": float(base["f_front"]), "f_rear": float(base["f_rear"]), "z_front": float(base["z_front"]), "z_rear": float(base["z_rear"])}]
	if mode == "none":
		return out
	var f_f: float = base["f_front"]
	var f_r: float = base["f_rear"]
	var z_f: float = base["z_front"]
	var z_r: float = base["z_rear"]
	if mode == "f" or mode == "full":
		for pct in [-0.10, -0.05, 0.05, 0.10]:
			var tag := "m10" if pct < -0.09 else ("m05" if pct < 0.0 else ("p05" if pct < 0.09 else "p10"))
			out.append({"label": "fF_" + tag, "f_front": f_f * (1.0 + pct), "f_rear": f_r, "z_front": z_f, "z_rear": z_r})
			out.append({"label": "fR_" + tag, "f_front": f_f, "f_rear": f_r * (1.0 + pct), "z_front": z_f, "z_rear": z_r})
	if mode == "z" or mode == "full":
		for dz in [-0.10, -0.05, 0.05, 0.10]:
			var ztag := "m10" if dz < -0.09 else ("m05" if dz < 0.0 else ("p05" if dz < 0.09 else "p10"))
			out.append({"label": "zF_" + ztag, "f_front": f_f, "f_rear": f_r, "z_front": clampf(z_f + dz, 0.05, 1.20), "z_rear": z_r})
			out.append({"label": "zR_" + ztag, "f_front": f_f, "f_rear": f_r, "z_front": z_f, "z_rear": clampf(z_r + dz, 0.05, 1.20)})
	return out


func _maneuver_ticks(maneuver: String) -> int:
	match maneuver:
		"rest":
			return 240
		"drop":
			return 150
		"bump":
			return 180
		"brake":
			return 300
		"corner":
			return 360
		"exit_ramp":
			return 300
		"crest":
			return 360
	return 150


func _input_for_tick(maneuver: String, tick: int, total: int) -> Dictionary:
	match maneuver:
		"brake":
			if tick < 120:
				return {"throttle": 0.7, "brake": 0.0, "steering": 0.0, "handbrake": 0.0}
			elif tick < 240:
				return {"throttle": 0.0, "brake": 1.0, "steering": 0.0, "handbrake": 0.0}
			else:
				return {"throttle": 0.0, "brake": 0.0, "steering": 0.0, "handbrake": 0.0}
		"corner":
			var ramp := clampf(float(tick) / 30.0, 0.0, 1.0)
			return {"throttle": 0.45 * ramp, "brake": 0.0, "steering": 0.30 * ramp, "handbrake": 0.0}
		"exit_ramp":
			var ramp2 := clampf(float(tick) / 120.0, 0.0, 1.0)
			return {"throttle": ramp2, "brake": 0.0, "steering": 0.0, "handbrake": 0.0}
		"crest":
			return {"throttle": 0.6, "brake": 0.0, "steering": 0.0, "handbrake": 0.0}
	return {"throttle": 0.0, "brake": 0.0, "steering": 0.0, "handbrake": 0.0}


func _pose_for_maneuver(base_pose: Transform3D, maneuver: String) -> Transform3D:
	match maneuver:
		"drop":
			return Transform3D(base_pose.basis, base_pose.origin + Vector3.UP * DROP_HEIGHT_M)
		"bump":
			var tilted := base_pose.basis.rotated(Vector3.FORWARD, deg_to_rad(3.0))
			return Transform3D(tilted, base_pose.origin + Vector3.UP * DROP_HEIGHT_M)
		"crest":
			var origin := Vector3(-15.0, base_pose.origin.y, -10.0)
			return Transform3D(Basis(Vector3.UP, 0.0), origin)
	return base_pose


func _ensure_single_wheel_bump(scene: Node, vehicle: Node) -> Node3D:
	var existing := scene.get_node_or_null("SingleWheelBump")
	if existing != null:
		return existing as Node3D
	var body := StaticBody3D.new()
	body.name = "SingleWheelBump"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("Gravel")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.12, 0.6)
	shape.shape = box
	shape.position = Vector3(0, -0.06, 0)
	body.add_child(shape)
	scene.add_child(body)
	var fl_local: Vector3 = vehicle.simulation.wheel_positions_local[0]
	var fl_world: Vector3 = vehicle.global_transform * fl_local
	body.global_position = Vector3(fl_world.x, 0.0, fl_world.z)
	return body


func _calibration_snapshot(vehicle: Node) -> Dictionary:
	var rep: Dictionary = vehicle.simulation.suspension_calibration_report()
	var axles: Array = rep.get("axles", [])
	var front: Dictionary = {"reference_mass_kg": 0.0, "frequency_hz": 0.0, "wheel_rate_n_m": 0.0, "bump_damping_ns_m": 0.0, "rebound_damping_ns_m": 0.0}
	var rear: Dictionary = front.duplicate(true)
	if not axles.is_empty():
		front = axles[0]
	if axles.size() >= 2:
		rear = axles[1]
	return {
		"front": front,
		"rear": rear,
		"front_track_m": float(rep.get("front_track_m", 0.0)),
		"rear_track_m": float(rep.get("rear_track_m", 0.0)),
		"wheelbase_m": float(rep.get("wheelbase_m", 0.0)),
		"front_arb_n_m": float(vehicle.simulation.suspension_model.front_arb_stiffness_n_per_m),
		"rear_arb_n_m": float(vehicle.simulation.suspension_model.rear_arb_stiffness_n_per_m),
	}


func _apply_candidate(vehicle: Node, cand: Dictionary, fuel_kg: float) -> Dictionary:
	var sim = vehicle.simulation
	var payload: Dictionary = sim.filter_garage_values(RallySetupCatalog.defaults(sim.domains))
	payload["suspension.front.ride_frequency_hz"] = float(cand.get("f_front", 1.7))
	payload["suspension.rear.ride_frequency_hz"] = float(cand.get("f_rear", 1.8))
	payload["suspension.front.damping_ratio"] = float(cand.get("z_front", 0.5))
	payload["suspension.rear.damping_ratio"] = float(cand.get("z_rear", 0.5))
	payload["fuel.initial_kg"] = fuel_kg
	var res: Dictionary = sim.apply_setup_values(payload)
	if not bool(res.get("ok", false)):
		return {"ok": false, "error": str(res.get("error", "apply_setup_values"))}
	var snap := _calibration_snapshot(vehicle)
	print("SUSPENSION_CANDIDATE_RATES ", JSON.stringify({"candidate": cand.get("label", "?"), "fuel_kg": fuel_kg, "calibration": snap}))
	return {"ok": true, "calibration": snap}


func _run_single_maneuver(scene: Node, vehicle: Node, base_pose: Transform3D, profile_key: String, maneuver: String, cand: Dictionary, fuel_kg: float, run_label: String) -> Dictionary:
	var sim = vehicle.simulation
	# Variante de diagnóstico de la tercera prueba (solo sonda): base =
	# producción; limiter = recorte de impulso del amortiguador ON;
	# novisc = término viscoso radial ×0.0; implicit/implicit_limiter =
	# paso radial implícito (con/sin limitador).
	sim.tandem_cam_enabled = false
	sim.set_damper_impulse_limit(opt_diag == "limiter" or opt_diag == "implicit_limiter")
	sim.unsprung_rig.radial_viscous_scale = 0.0 if opt_diag == "novisc" else 1.0
	sim.unsprung_rig.radial_implicit_enabled = opt_diag == "implicit" or opt_diag == "implicit_limiter"
	var applied := _apply_candidate(vehicle, cand, fuel_kg)
	if not bool(applied.get("ok", false)):
		check(false, "%s %s %s: candidato no aplicado (%s)" % [profile_key, maneuver, run_label, str(applied.get("error", ""))])
		return {"profile": profile_key, "maneuver": maneuver, "candidate": run_label, "ok": false}
	vehicle.prepare_for_stage()
	# Cabecera por pasada (§instrucciones-1): registrar y comprobar profile_id,
	# Jolt, 60 Hz y tandem desactivado antes de cada secuencia por tick.
	# Se parte de sesión limpia (reset_dynamics vía _reset_to_transform abajo,
	# que incrementa session_generation) y de setup de fábrica + combustible
	# y temperaturas iniciales iguales entre pasadas (prepare_for_stage).
	var pass_profile_id := str(sim.active_profile_id)
	if pass_profile_id.is_empty():
		pass_profile_id = str(sim.profile.get("vehicle_identifier", ""))
	var pass_fuel_kg := float(sim.mass_model.fuel_initial_kg)
	var pass_thermal: Dictionary = sim.thermal_model.get_tire_thermal_state_snapshot(0) if sim.thermal_model.tire_states.size() > 0 else {}
	var pass_header := {
		"profile": profile_key,
		"profile_id": pass_profile_id,
		"maneuver": maneuver,
		"candidate": run_label,
		"fuel_kg": fuel_kg,
		"fuel_initial_kg": pass_fuel_kg,
		"physics_hz_setting": int(Engine.physics_ticks_per_second),
		"physics_engine": str(ProjectSettings.get_setting("physics/3d/physics_engine", "")),
		"tandem_cam_enabled": bool(sim.tandem_cam_enabled),
		"session_generation": int(sim.session_generation),
		"ambient_c": float(sim.thermal_model.ambient_temperature_c),
		"tire0_carcass_c": float(pass_thermal.get("carcass_c", 0.0)),
		"tire0_gas_c": float(pass_thermal.get("gas_c", 0.0)),
	}
	print("SUSPENSION_PASS_HEADER ", JSON.stringify(pass_header))
	check(pass_profile_id.to_lower().contains(profile_key.replace("lancia-", "")) or (profile_key == "fulvia" and pass_profile_id.to_lower().contains("fulvia")), "%s %s %s: profile_id %s" % [profile_key, maneuver, run_label, pass_profile_id])
	check(int(Engine.physics_ticks_per_second) == EXPECTED_PHYSICS_HZ, "%s %s %s: 60 Hz al iniciar pasada" % [profile_key, maneuver, run_label])
	check(str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) == EXPECTED_PHYSICS_ENGINE, "%s %s %s: Jolt al iniciar pasada" % [profile_key, maneuver, run_label])
	check(not bool(sim.tandem_cam_enabled), "%s %s %s: tandem desactivado" % [profile_key, maneuver, run_label])
	# Con variante de diagnóstico, re-asentar con la variante activa antes de
	# capturar la pose de referencia: la pose base de producción puede venir
	# contaminada por el banco inestable (lanzamiento), y la caída debe medirse
	# desde el apoyo real con el control ya aplicado.
	var effective_base := base_pose
	if opt_diag != "base":
		vehicle._reset_to_transform(base_pose)
		for i in 120:
			await physics_frame
		effective_base = vehicle.global_transform
	if opt_settle120:
		# Arranque desde pose asentada a 120 Hz con velocidades reiniciadas:
		# asienta en el spawn de la sesión a 120 Hz, captura la pose, vuelve
		# a 60 Hz e iguala temperaturas antes de la maniobra.
		Engine.physics_ticks_per_second = 120
		var spawn_y := 0.0
		if scene.has_method("spawn_position"):
			spawn_y = (scene.spawn_position() as Vector3).y
		else:
			spawn_y = vehicle.global_transform.origin.y
		vehicle._reset_to_transform(Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.0, spawn_y, 0.0)))
		if maneuver in ["brake", "corner", "exit_ramp", "crest"]:
			sim.powertrain_model.set_gear(1)
		else:
			sim.powertrain_model.set_gear(0)
		for i in 240:
			await physics_frame
		var settled_pose: Transform3D = vehicle.global_transform
		Engine.physics_ticks_per_second = EXPECTED_PHYSICS_HZ
		vehicle.prepare_for_stage()
		print("SUSPENSION_SETTLE120 ", JSON.stringify({
			"profile": profile_key, "maneuver": maneuver, "candidate": run_label,
			"settled_y": settled_pose.origin.y,
		}))
		effective_base = settled_pose
	var pose := _pose_for_maneuver(effective_base, maneuver)
	var bump_body: Node3D = null
	if maneuver == "bump":
		vehicle._reset_to_transform(pose)
		for i in 3:
			await physics_frame
		bump_body = _ensure_single_wheel_bump(scene, vehicle)
		pose = _pose_for_maneuver(vehicle.global_transform, "drop")
	vehicle._reset_to_transform(pose)
	if maneuver in ["brake", "corner", "exit_ramp", "crest"]:
		sim.powertrain_model.set_gear(1)
	else:
		sim.powertrain_model.set_gear(0)
	for i in 6:
		await physics_frame
	var total := _maneuver_ticks(maneuver)
	var tick_rows: Array = []
	var dt_sum := 0.0
	var dt_min := INF
	var dt_max := 0.0
	var monotonic := true
	var last_tick_id := -1
	for t in total:
		var inp := _input_for_tick(maneuver, t, total)
		vehicle.throttle_input = float(inp.get("throttle", 0.0))
		vehicle.brake_input = float(inp.get("brake", 0.0))
		vehicle.steering_input = float(inp.get("steering", 0.0))
		vehicle.handbrake_input = float(inp.get("handbrake", 0.0))
		await physics_frame
		var susp: Array = sim.sample_suspension_trace()
		var ticks: Array = sim.sample_tick_trace()
		var contacts: Array = sim.sample_contact_trace()
		var origin: Vector3 = vehicle.global_transform.origin
		var lin: Vector3 = vehicle.linear_velocity
		var ang: Vector3 = vehicle.angular_velocity
		var yaw := atan2(-vehicle.global_transform.basis.z.x, -vehicle.global_transform.basis.z.z)
		for w in 4:
			var s: Dictionary = susp[w]
			var tk: Dictionary = ticks[w]
			var ct: Dictionary = contacts[w] if w < contacts.size() else {}
			var dt := float(tk.get("dt_s", 0.0))
			if w == 0:
				dt_sum += dt
				dt_min = minf(dt_min, dt)
				dt_max = maxf(dt_max, dt)
				var tid := int(tk.get("tick_id", 0))
				if last_tick_id >= 0 and tid != last_tick_id + 1:
					monotonic = false
				last_tick_id = tid
			tick_rows.append({
				"tick": t, "wheel": w,
				"compression_m": float(s.get("compression_m", 0.0)),
				"hub_travel_m": float(s.get("hub_travel_m", 0.0)),
				"compression_velocity_m_s": float(s.get("compression_velocity_m_s", 0.0)),
				"geometric_contact": bool(s.get("geometric_contact", false)),
				"loaded_contact": bool(s.get("loaded_contact", false)),
				"load_n": float(s.get("load_n", 0.0)),
				"elastic_n": float(s.get("elastic_n", 0.0)),
				"damper_requested_n": float(s.get("damper_requested_n", 0.0)),
				"damper_applied_n": float(s.get("damper_applied_n", 0.0)),
				"damper_impulse_ns": float(s.get("damper_impulse_ns", 0.0)),
				"damper_clamped": bool(s.get("damper_clamped", false)),
				"bump_n": float(sim.suspension_model.last_bump_forces_n[w]),
				"bar_travel_m": float(s.get("bar_travel_m", 0.0)),
				"radial_deflection_m": float(ct.get("radial_deflection_m", 0.0)),
				"contact_distance_m": float(ct.get("distance_m", 0.0)),
				"tick_id": int(tk.get("tick_id", 0)),
				"dt_s": dt,
				"throttle": float(inp.get("throttle", 0.0)),
				"brake": float(inp.get("brake", 0.0)),
				"steering": float(inp.get("steering", 0.0)),
				"chassis_y": origin.y,
				"speed_m_s": lin.length(),
				"vy_m_s": lin.y,
				"yaw_rad": yaw,
				"yaw_rate_rad_s": ang.y,
			})
	if bump_body != null:
		bump_body.queue_free()
		await process_frame
	var avg_dt := dt_sum / maxf(float(total), 1.0)
	var measured_hz := 1.0 / maxf(avg_dt, 1.0e-6)
	var hz_ok := absf(avg_dt - 1.0 / 60.0) < 0.001
	var tick_info := {
		"profile": profile_key,
		"maneuver": maneuver,
		"candidate": run_label,
		"diag_variant": opt_diag,
		"fuel_kg": fuel_kg,
		"physics_hz_setting": int(Engine.physics_ticks_per_second),
		"physics_engine": str(ProjectSettings.get_setting("physics/3d/physics_engine", "")),
		"dt_avg_s": avg_dt,
		"dt_min_s": dt_min,
		"dt_max_s": dt_max,
		"hz_measured": measured_hz,
		"hz_ok_60": hz_ok,
		"tick_monotonic": monotonic,
		"contact_query_type": str((sim.domains.get("suspension", {}) as Dictionary).get("suspension", {}).get("contact_query_type", "")),
		"contact_shape_count": int((sim.domains.get("suspension", {}) as Dictionary).get("suspension", {}).get("contact_shape_count", -1)),
		"maximum_substep_s": float(sim.maximum_substep_seconds),
		"tire_substeps_per_tick": maxi(1, ceili(avg_dt / maxf(float(sim.maximum_substep_seconds), 0.0005))),
		"compound": str(sim.active_compound_id),
		"setup_is_factory_reference": true,
	}
	print("SUSPENSION_TICK_EFFECTIVE ", JSON.stringify(tick_info))
	check(hz_ok, "%s %s %s: tick efectivo 60 Hz (dt=%.6f)" % [profile_key, maneuver, run_label, avg_dt])
	check(monotonic, "%s %s %s: tick_id monotonico" % [profile_key, maneuver, run_label])
	var summary := _compute_summary(profile_key, maneuver, run_label, cand, fuel_kg, tick_rows, tick_info, applied.get("calibration", {}))
	_write_csv(profile_key, maneuver, run_label, fuel_kg, cand, tick_rows, tick_info)
	var light: Array = []
	for r in tick_rows:
		light.append([int(r["tick"]), int(r["wheel"]), float(r["compression_m"]), float(r["load_n"]), float(r["damper_applied_n"])])
	summary["trace_ref"] = light
	_acceptance_checks(summary)
	return summary


func _compute_summary(profile_key: String, maneuver: String, run_label: String, cand: Dictionary, fuel_kg: float, rows: Array, tick_info: Dictionary, calib: Dictionary) -> Dictionary:
	var peak_load := 0.0
	var peak_comp := -99.0
	var peak_vel := 0.0
	var clips := 0
	var bump_hits := 0
	var losses := 0
	var rear_discharge_ticks := 0
	var max_rear_discharge := 0
	var cur_rear_discharge := 0
	var yaw_peak := 0.0
	var braking_distance := 0.0
	var exit_speed := 0.0
	var finite_ok := true
	var last_speed := 0.0
	for r in rows:
		var load := float(r["load_n"])
		var comp := float(r["compression_m"])
		var vel := absf(float(r["compression_velocity_m_s"]))
		peak_load = maxf(peak_load, load)
		peak_comp = maxf(peak_comp, comp)
		peak_vel = maxf(peak_vel, vel)
		if bool(r["damper_clamped"]):
			clips += 1
		if float(r["bump_n"]) > 1.0:
			bump_hits += 1
		if not is_finite(load) or not is_finite(comp) or not is_finite(float(r["damper_applied_n"])):
			finite_ok = false
		yaw_peak = maxf(yaw_peak, absf(float(r["yaw_rate_rad_s"])))
		last_speed = float(r["speed_m_s"])
		if maneuver == "brake" and int(r["wheel"]) == 0:
			braking_distance += float(r["speed_m_s"]) * maxf(float(r["dt_s"]), 1.0e-6)
	for t in _maneuver_ticks(maneuver):
		var rear_loaded := 0
		for r in rows:
			if int(r["tick"]) != t:
				continue
			if int(r["wheel"]) in [2, 3] and bool(r["loaded_contact"]):
				rear_loaded += 1
			if not bool(r["loaded_contact"]):
				losses += 1
		if rear_loaded == 0:
			cur_rear_discharge += 1
			max_rear_discharge = maxi(max_rear_discharge, cur_rear_discharge)
		else:
			cur_rear_discharge = 0
		if rear_loaded < 2:
			rear_discharge_ticks += 1
	exit_speed = last_speed
	var settle_tick := -1
	var calm := 0
	for t in _maneuver_ticks(maneuver):
		var cmax := 0.0
		var vmax := 0.0
		for r in rows:
			if int(r["tick"]) == t:
				cmax = maxf(cmax, absf(float(r["compression_m"])))
				vmax = maxf(vmax, absf(float(r["compression_velocity_m_s"])))
		# Reposo: posición a ±5 mm y velocidad < 0.20 m/s durante 20 ticks.
		# La velocidad sola no basta a 60 Hz (ruido Jolt + radial); la posición
		# confirma el asentamiento que la envolvente ya mide.
		if cmax < 0.005 and vmax < 0.20:
			calm += 1
			if calm >= 20:
				settle_tick = t - 19
				break
		else:
			calm = 0
	var half := _maneuver_ticks(maneuver) / 2
	var peak_first := 0.0
	var peak_second := 0.0
	for r in rows:
		var a := absf(float(r["compression_m"]))
		if int(r["tick"]) < half:
			peak_first = maxf(peak_first, a)
		else:
			peak_second = maxf(peak_second, a)
	var envelope_decays := peak_second <= peak_first + 0.002
	return {
		"profile": profile_key,
		"maneuver": maneuver,
		"candidate": run_label,
		"f_front": float(cand.get("f_front", 0.0)),
		"f_rear": float(cand.get("f_rear", 0.0)),
		"z_front": float(cand.get("z_front", 0.0)),
		"z_rear": float(cand.get("z_rear", 0.0)),
		"fuel_kg": fuel_kg,
		"calibration": calib,
		"tick_effective": tick_info,
		"peak_load_n": peak_load,
		"peak_compression_m": peak_comp,
		"peak_rel_velocity_m_s": peak_vel,
		"clip_wheel_ticks": clips,
		"bump_stop_wheel_ticks": bump_hits,
		"contact_loss_wheel_ticks": losses,
		"rear_discharge_ticks": rear_discharge_ticks,
		"max_rear_discharge_ticks": max_rear_discharge,
		"yaw_peak_rad_s": yaw_peak,
		"braking_distance_m": braking_distance,
		"exit_speed_m_s": exit_speed,
		"settle_tick": settle_tick,
		"envelope_decays": envelope_decays,
		"peak_first_half_m": peak_first,
		"peak_second_half_m": peak_second,
		"finite_ok": finite_ok,
		"ok": finite_ok,
	}


func _first_divergence(baseline_key: String, summary: Dictionary) -> Dictionary:
	var out := {"profile": summary.get("profile", ""), "maneuver": summary.get("maneuver", ""), "candidate": summary.get("candidate", ""), "first_tick": -1, "channel": "", "baseline": baseline_key}
	if not baseline_traces.has(baseline_key):
		out["note"] = "sin linea base"
		return out
	var base: Array = baseline_traces[baseline_key]
	var cand: Array = summary.get("trace_ref", [])
	var index := {}
	for b in base:
		index["%d|%d" % [int(b[0]), int(b[1])]] = b
	for c in cand:
		var k := "%d|%d" % [int(c[0]), int(c[1])]
		if not index.has(k):
			continue
		var b: Array = index[k]
		var d_comp := absf(float(c[2]) - float(b[2]))
		var d_load := absf(float(c[3]) - float(b[3]))
		var base_load := maxf(absf(float(b[3])), 500.0)
		if d_comp > 0.002 or d_load / base_load > 0.05:
			out["first_tick"] = int(c[0])
			out["channel"] = "compression" if d_comp > 0.002 else "load"
			out["d_comp_m"] = d_comp
			out["d_load_n"] = d_load
			return out
	out["note"] = "sin divergencia sobre umbral (2 mm / 5 %)"
	return out


func _acceptance_checks(summary: Dictionary) -> void:
	var tag := "%s %s %s" % [str(summary.get("profile", "?")), str(summary.get("maneuver", "?")), str(summary.get("candidate", "?"))]
	check(bool(summary.get("finite_ok", false)), "%s: fuerzas finitas" % tag)
	check(bool(summary.get("envelope_decays", false)), "%s: envolvente decae (%.3f -> %.3f)" % [tag, float(summary.get("peak_first_half_m", 0.0)), float(summary.get("peak_second_half_m", 0.0))])
	if str(summary.get("maneuver", "")) == "rest":
		check(int(summary.get("contact_loss_wheel_ticks", 1)) == 0, "%s: reposo sin perdidas de apoyo" % tag)
		check(int(summary.get("settle_tick", -1)) >= 0, "%s: reposo asienta (tick %d)" % [tag, int(summary.get("settle_tick", -1))])
	if str(summary.get("maneuver", "")) in ["drop", "bump"]:
		check(int(summary.get("max_rear_discharge_ticks", 999)) < 60, "%s: descarga trasera acotada (%d ticks)" % [tag, int(summary.get("max_rear_discharge_ticks", 0))])


func _write_csv(profile_key: String, maneuver: String, run_label: String, fuel_kg: float, cand: Dictionary, rows: Array, tick_info: Dictionary) -> void:
	var safe_label := run_label.replace("+", "p").replace("-", "m").replace(".", "_")
	var fname := "%s__%s__%s__fuel%.0f.csv" % [profile_key, maneuver, safe_label, fuel_kg]
	var path := opt_out_dir.rstrip("/") + "/" + fname
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_w("no se pudo abrir CSV " + path)
		return
	f.store_line("profile,maneuver,candidate,f_front_hz,f_rear_hz,z_front,z_rear,fuel_kg,tick,wheel,tick_id,dt_s,effective_hz,physics_engine,contact_query_type,substeps,throttle,brake,steering,chassis_y_m,speed_m_s,yaw_rate_rad_s,compression_m,hub_travel_m,compression_vel_m_s,geometric_contact,loaded_contact,load_n,elastic_n,damper_req_n,damper_app_n,damper_impulse_ns,damper_clamped,bump_n,bar_travel_m,radial_deflection_m,contact_distance_m")
	for r in rows:
		f.store_line("%s,%s,%s,%.6f,%.6f,%.6f,%.6f,%.1f,%d,%d,%d,%.6f,%.2f,%s,%s,%d,%.3f,%.3f,%.3f,%.4f,%.3f,%.4f,%.5f,%.5f,%.4f,%d,%d,%.1f,%.1f,%.1f,%.1f,%.4f,%d,%.1f,%.5f,%.4f,%.4f" % [
			profile_key, maneuver, run_label,
			float(cand.get("f_front", 0.0)), float(cand.get("f_rear", 0.0)), float(cand.get("z_front", 0.0)), float(cand.get("z_rear", 0.0)),
			fuel_kg, int(r["tick"]), int(r["wheel"]), int(r["tick_id"]), float(r["dt_s"]),
			1.0 / maxf(float(r["dt_s"]), 1.0e-6), str(tick_info.get("physics_engine", "")).replace(",", ";"),
			str(tick_info.get("contact_query_type", "")), int(tick_info.get("tire_substeps_per_tick", 1)),
			float(r["throttle"]), float(r["brake"]), float(r["steering"]),
			float(r["chassis_y"]), float(r["speed_m_s"]), float(r["yaw_rate_rad_s"]),
			float(r["compression_m"]), float(r["hub_travel_m"]), float(r["compression_velocity_m_s"]),
			int(bool(r["geometric_contact"])), int(bool(r["loaded_contact"])),
			float(r["load_n"]), float(r["elastic_n"]), float(r["damper_requested_n"]), float(r["damper_applied_n"]),
			float(r["damper_impulse_ns"]), int(bool(r["damper_clamped"])),
			float(r["bump_n"]), float(r["bar_travel_m"]), float(r["radial_deflection_m"]), float(r["contact_distance_m"]),
		])
	f.close()
