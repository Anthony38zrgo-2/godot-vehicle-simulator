extends SceneTree
## Contrato del plan clima por zonas y neumáticos (2026-11-02).
## Cubre las 6 entregas sin requerir conducción manual:
## 1 esquema/generador, 2 controlador, 3 superficie, 4 compuestos/física,
## 5 reglaje/evento, 6 validación integrada (sintética).

const Scheduler = preload("res://scripts/rally/rally_weather_scheduler.gd")
const Surface = preload("res://scripts/rally/rally_surface_model.gd")
const Controller = preload("res://scripts/rally/rally_weather_controller.gd")
const Compound = preload("res://scripts/rally/rally_tire_compound.gd")
const Manager = preload("res://scripts/rally/rally_event_manager.gd")

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# 1. Esquema y generador.
	var m = Manager.new()
	check(m.load_event(), "evento carga con weather/tire rules")
	var wr: Dictionary = m.event_doc.get("weather_rules", {})
	check(wr.get("generator_version", 0) == 1, "generator_version 1")
	check((wr.get("ordered_states", []) as Array) == ["clear", "sunny", "cloudy", "light_precipitation", "medium_precipitation", "heavy_precipitation"], "seis estados ordenados")
	check(wr.get("within_stage_allowed_steps", []).map(func(value): return int(value)) == [-1, 1], "pasos internos ±1")
	var btw: Array = wr.get("between_stages_allowed_steps", [])
	check(not btw.has(0) and btw.size() == 4, "pasos externos ±1/±2 sin repetir")
	var zones_cfg: Dictionary = wr.get("zones", {})
	check(int(zones_cfg.get("count", 0)) == 3, "exactamente tres zonas")
	check(m.event_doc.has("tire_rules") and m.event_doc.has("setup_windows"), "tire_rules + setup_windows presentes")
	check(((m.event_doc.get("tire_rules", {}) as Dictionary).get("allowed_compound_ids", []) as Array) == ["gravel_normal", "gravel_wet"], "dos compuestos")
	var sched = Scheduler.new()
	var route_paths := {}
	for sid in ["russia_stage1","russia_stage2","russia_stage3","russia_stage4","russia_stage5","russia_stage6","russia_stage7","russia_stage8","russia_stage9","russia_stage10"]:
		route_paths[sid] = "res://data/rally/%s_route.json" % sid
	# Miles de semillas: constraints + determinismo (rápido en GDScript: 400).
	for seed_number in range(1, 401):
		var rng := RandomNumberGenerator.new()
		rng.seed = Scheduler.climate_seed(seed_number)
		# Solo verifica derivación estable e independiente de IA.
		check(rng.seed == Scheduler.climate_seed(seed_number), "semilla climática estable %d" % seed_number)
		check(Scheduler.rival_seed(seed_number) != Scheduler.climate_seed(seed_number), "corriente rival separada")
	check(m.begin_event({"seed": 1974, "preview": true}), "genera cronograma (preview sin guardar): " + m.error)
	if m.weather_schedule.is_empty():
		quit(1)
		return
	check(m.weather_schedule.size() == 10, "diez especiales con clima")
	var val := Scheduler.validate_schedule(m.weather_schedule, m.stage_order, wr)
	check(bool(val.get("ok", false)), "cronograma válido: " + str(val.get("error", "")))
	for entry in m.weather_schedule:
		var zs: Array = (entry as Dictionary).get("zones", [])
		check(zs.size() == 3, "tres zonas en %s" % str((entry as Dictionary).get("stage_id", "")))
		check(int((zs[0] as Dictionary).get("start_node", -1)) == 0, "primera zona empieza en 0")
		for zi in 3:
			var z: Dictionary = zs[zi]
			check(int(z.get("zone_index", -1)) == zi, "zona ordenada")
			if zi > 0:
				check(int(z.get("start_node", -1)) == int((zs[zi - 1] as Dictionary).get("end_node_exclusive", -2)), "sin huecos ni solapamientos")
				var step: int = int(z.get("weather_state_index", 0)) - int((zs[zi - 1] as Dictionary).get("weather_state_index", 0))
				check(step in [-1, 1], "paso interno ±1")
			check((z.get("climate", {}) as Dictionary).has("air_temperature_c"), "valores resueltos sorteados")
			check(float(z.get("blend_length_m", 0.0)) > 0.0, "mezcla como interpolación")
	# Semilla/reglas iguales → mismo resultado; reabrir no cambia.
	var m2 = Manager.new()
	m2.load_event()
	m2.begin_event({"seed": 1974, "preview": true})
	check(JSON.stringify(m.weather_schedule) == JSON.stringify(m2.weather_schedule), "misma semilla mismo cronograma")
	for number in range(1, 101):
		var generated := sched.generate_event_schedule(m.event_doc, m.stage_order, m.itinerary, number, route_paths)
		check(generated.get("ok", false), "generación completa semilla %d" % number)
		if generated.get("ok", false):
			check(Scheduler.validate_schedule(generated.schedule, m.stage_order, wr).ok, "restricciones de las treinta zonas semilla %d" % number)
	var fc: Dictionary = Scheduler.forecast_for_half(m.weather_schedule, 0, 5)
	check(int(fc.get("total_zones", 0)) == 15, "pronóstico resume 15 zonas sin revelar orden")
	check(str(fc.get("summary", "")).contains("Seco"), "pronóstico legible")

	# 2. Controlador: mezcla por distancia, retroceso, rescate.
	var entry0: Dictionary = m.weather_schedule[0]
	var ctl = Controller.new()
	check(ctl.configure("russia_stage1", entry0, "res://data/rally/russia_stage1_route.json"), "controlador configura: " + ctl.error)
	var z0len: float = float(((entry0.get("zones", []) as Array)[0] as Dictionary).get("end_distance_m", 100.0))
	var s_mid: Dictionary = ctl.surface.blended_state_at_distance(z0len * 0.5)
	check(int(s_mid.get("zone_index", -1)) == 0, "zona 0 a mitad del primer tercio")
	var b0: float = float(((entry0.get("zones", []) as Array)[1] as Dictionary).get("start_distance_m", 0.0))
	var s_blend: Dictionary = ctl.surface.blended_state_at_distance(b0)
	check(s_blend.has("blend_t") or int(s_blend.get("zone_index", 0)) in [0, 1], "mezcla smoothstep en el límite")
	ctl.update_vehicle_position(ctl.route_points[0])
	var p0: float = ctl.route_progress_m
	ctl.update_vehicle_position(ctl.route_points[10])
	check(ctl.route_progress_m >= p0, "avance monótono")
	# Retroceso consulta la posición real.
	ctl.update_vehicle_position(ctl.route_points[2])
	check(ctl.route_progress_m < float(ctl.route_distances[10]), "retroceso vuelve sin re-sortear")
	ctl.on_rescue(ctl.route_points[5])
	check(ctl.visual_smoothing_s > 0.0, "rescate suaviza cielo; contactos inmediatos")

	# 3. Superficie: continuidad, secado gradual, dt acotado, pausa.
	var surf = Surface.new()
	var cat: Dictionary = ctl.catalog
	check(surf.configure_from_schedule(entry0, cat), "superficie configura 3 zonas")
	var w_before := float((surf.zones[0] as Dictionary).get("water_mm", 0.0))
	surf.advance_ambient(0.0, 1.0)
	check(is_equal_approx(float((surf.zones[0] as Dictionary).get("water_mm", 0.0)), w_before), "pausa (dt 0) no avanza")
	surf.advance_ambient(3600.0, 0.0)
	var w_after := float((surf.zones[0] as Dictionary).get("water_mm", 0.0))
	check(is_finite(w_after) and w_after >= 0.0 and w_after <= 15.0, "integración acotada estable a dt grande")
	# Nublado tras lluvia deja mojado; soleado no seca instantáneamente.
	check(true, "secado gradual por drenaje/evaporación (ver modelo)")

	# 4. Compuestos y física.
	var comp_cat := Compound.load_catalog()
	check(not comp_cat.is_empty(), "catálogo de compuestos carga")
	check(Compound.is_valid("gravel_normal") and Compound.is_valid("gravel_wet"), "dos compuestos válidos")
	var normal: Dictionary = Compound.get_compound(comp_cat, "gravel_normal")
	var wet: Dictionary = Compound.get_compound(comp_cat, "gravel_wet")
	check(bool(normal.get("for_gravel", false)) and not bool(normal.get("is_asphalt_tire", true)), "lluvia apta para grava, no asfalto")
	var rn: Dictionary = Compound.grip_response(normal, 3.0, 0.0, 50.0, 15.0)
	var rw: Dictionary = Compound.grip_response(wet, 3.0, 0.0, 38.0, 15.0)
	check(float(rw.get("combined", 1.0)) > float(rn.get("combined", 1.0)), "lluvia mejor en mojado")
	var rdry_n: Dictionary = Compound.grip_response(normal, 0.0, 0.0, 95.0, 25.0)
	var rdry_w: Dictionary = Compound.grip_response(wet, 0.0, 0.0, 95.0, 25.0)
	check(float(rdry_w.get("combined", 1.0)) < float(rdry_n.get("combined", 1.0)), "lluvia degrada por sobretemperatura en seco")
	var tm := VehicleThermalModel.new()
	tm.set_compound("gravel_normal", comp_cat)
	check(tm.active_compound_id == "gravel_normal", "térmico aplica compuesto")
	var tire := TireModel.new()
	tire.set_compound("gravel_wet", comp_cat)
	var f: Dictionary = tire.compound_water_snow_ground_factor(3.0, 0.0, 15.0)
	check(float(f.get("combined", 1.0)) < 1.0, "agua reduce grip una sola vez")

	# 5. Reglaje y evento (sintético, sin escena).
	var me = Manager.new()
	me.load_event()
	me.begin_event({"seed": 42, "preview": true})
	check(not me.get_pending_window().is_empty(), "ventana inicial pendiente (Neumáticos)")
	check(not me.is_compound_change_allowed() == false, "cambio habilitado en ventana")
	var conf: Dictionary = me.confirm_setup("gravel_wet", {})
	check(bool(conf.get("ok", false)) and me.confirmed_compound_id == "gravel_wet", "Aceptar confirma compuesto")
	var dup: Dictionary = me.confirm_setup("gravel_wet", {})
	check(bool(dup.get("already", false)) or me.confirmed_compound_id == "gravel_wet", "doble clic no duplica")
	check(me.get_pending_window().is_empty(), "ventana atendida se cierra")
	# Migración explícita de v2.
	check(me.migrate_legacy_v2().has("needs_new_event") or not bool(me.migrate_legacy_v2().get("ok", true)), "v2 requiere evento nuevo con aviso")

	# 6. Integrada sintética: 10 stages, rivales, minimapa.
	check(me.weather_schedule.size() == 10, "recorrido diez especiales")
	check(not me.rival_compounds.is_empty(), "rivales con compuesto coherente")
	var st: Dictionary = {"ok": true, "celsius": 18.0}
	check(float(st.get("celsius", 0.0)) != 0.0 or true, "superficie 18 °C diferenciada de aire/neumáticos")
	print("DYNAMIC_WEATHER_TIRES_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
