class_name RallyWeatherScheduler
extends RefCounted
## Generador del itinerario climático del evento (Entrega 1 del plan).
## Datos en JSON, algoritmo genérico en código. Una sola generación por rally,
## determinista por semilla climática derivada de la semilla del rally con
## propósito independiente de la IA. No se re-sortea al reabrir ni al aceptar
## dos veces: el cronograma resuelto se persiste.

const GENERATOR_VERSION := 2
const CLIMATE_PURPOSE := "rally_weather_v1"
const RIVAL_PURPOSE := "rally_weather_rival_v1"
const PRESET_CATALOG_PATH := "res://data/weather/rally_weather_presets.json"
const COMPOUND_CATALOG_PATH := "res://data/tires/rally_compounds.json"

var error: String = ""


static func climate_seed(rally_seed: int) -> int:
	return abs(int(("%d/%s" % [rally_seed, CLIMATE_PURPOSE]).hash()))


static func rival_seed(rally_seed: int) -> int:
	return abs(int(("%d/%s" % [rally_seed, RIVAL_PURPOSE]).hash()))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		error = "No existe " + path
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		error = "JSON inválido: " + path
		return {}
	return parsed


func _route_points(route_path: String) -> Array:
	if not FileAccess.file_exists(route_path):
		error = "Ruta ausente: " + route_path
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(route_path))
	if not parsed is Dictionary:
		error = "Ruta inválida: " + route_path
		return []
	var out: Array = []
	for p in (parsed as Dictionary).get("points", []):
		if p is Array and (p as Array).size() >= 3:
			out.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return out


func _cumulative_distances(points: Array) -> PackedFloat64Array:
	var cum := PackedFloat64Array([0.0])
	for i in range(1, points.size()):
		cum.append(cum[-1] + (points[i] as Vector3).distance_to(points[i - 1] as Vector3))
	return cum


func _nearest_node(cum: PackedFloat64Array, target: float) -> int:
	var best := 0
	var best_d := INF
	for i in cum.size():
		var d := absf(cum[i] - target)
		if d < best_d:
			best_d = d
			best = i
	return best


## Divide la ruta en tres tercios iguales por distancia y ajusta los dos
## límites interiores a los nodos existentes más próximos por distancia
## acumulada, sin desplazamiento aleatorio.
func compute_zones_for_route(route_path: String, rules: Dictionary) -> Dictionary:
	error = ""
	var points := _route_points(route_path)
	if points.size() < 4:
		return {"ok": false, "error": "Ruta incompatible: nodos insuficientes en " + route_path}
	var cum := _cumulative_distances(points)
	var total: float = cum[-1]
	var zones_cfg: Dictionary = rules.get("zones", {})
	var count := int(zones_cfg.get("count", 3))
	if count != 3:
		return {"ok": false, "error": "Solo se admiten exactamente tres zonas por especial"}
	var min_len := float(zones_cfg.get("minimum_length_m", 250.0))
	if total < min_len * 3.0:
		return {"ok": false, "error": "Ruta incompatible: longitud %.1f m menor que 3x%.1f m (%s)" % [total, min_len, route_path]}
	var fractions: Array = zones_cfg.get("boundary_distance_fractions", [0.0, 0.3333333333333333, 0.6666666666666666, 1.0])
	if fractions.size() != 4:
		return {"ok": false, "error": "Se requieren 4 fracciones de límite (0, 1/3, 2/3, 1)"}
	var b0 := 0
	var b1 := _nearest_node(cum, total * float(fractions[1]))
	var b2 := _nearest_node(cum, total * float(fractions[2]))
	var b3 := int(points.size())
	# La última zona incluye el final; no hay huecos ni solapamientos.
	if b1 <= b0 or b2 <= b1 or b3 <= b2:
		return {"ok": false, "error": "Ruta incompatible: los límites caen en el mismo nodo (%s: %d/%d/%d/%d)" % [route_path, b0, b1, b2, b3]}
	var boundaries := [b0, b1, b2, b3]
	for zi in 3:
		var zlen: float = cum[boundaries[zi + 1] - 1 if boundaries[zi + 1] < cum.size() else cum.size() - 1] - cum[boundaries[zi]]
		# Última zona: distancia hasta el final real.
		if zi == 2:
			zlen = total - cum[boundaries[zi]]
		if zlen < min_len:
			return {"ok": false, "error": "Ruta incompatible: zona %d de %.1f m menor que %.1f m (%s)" % [zi, zlen, min_len, route_path]}
		if zi > 0 and boundaries[zi] - boundaries[zi - 1] < 1:
			return {"ok": false, "error": "Ruta incompatible: zona vacía en " + route_path}
	var blend_frac := float(zones_cfg.get("blend_fraction_of_zone", 0.25))
	var max_blend := float(zones_cfg.get("maximum_blend_distance_m", 150.0))
	var zones: Array = []
	for zi in 3:
		var s: int = boundaries[zi]
		var e: int = boundaries[zi + 1]
		var start_d: float = cum[s]
		var end_d: float = (total if e >= cum.size() else cum[e])
		if zi == 2:
			end_d = total
		var zlen2: float = maxf(end_d - start_d, 1.0)
		var blend: float = minf(zlen2 * blend_frac, max_blend)
		zones.append({
			"zone_index": zi,
			"start_node": s,
			"end_node_exclusive": e,
			"start_distance_m": start_d,
			"end_distance_m": end_d,
			"length_m": zlen2,
			"blend_length_m": blend,
		})
	return {"ok": true, "zones": zones, "total_length_m": total, "node_count": points.size(), "route_hash": FileAccess.get_file_as_string(route_path).sha256_text()}


func _validate_transition(from_idx: int, to_idx: int, allowed: Array) -> bool:
	return (to_idx - from_idx) in allowed


func _pick_weighted(rng: RandomNumberGenerator, options: Array, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return int(options[0])
	var r := rng.randf() * total
	var acc := 0.0
	for i in options.size():
		acc += float(weights[i])
		if r <= acc:
			return int(options[i])
	return int(options[options.size() - 1])


func _sample_range(rng: RandomNumberGenerator, lo: float, hi: float) -> float:
	if hi <= lo:
		return lo
	return rng.randf_range(lo, hi)


func _resolve_climate_values(rng: RandomNumberGenerator, preset: Dictionary, prev_climate: Dictionary = {}) -> Dictionary:
	var cumulus_range: Array = preset.get("cumulus_coverage", [0.5, 0.5])
	var cirrus_range: Array = preset.get("cirrus_coverage", [0.5, 0.5])
	var irr_range: Array = preset.get("irradiance_w_m2", [100.0, 100.0])
	var air_range: Array = preset.get("air_temperature_c", [15.0, 15.0])
	var precip_range: Array = preset.get("precipitation_mm_h", [0.0, 0.0])
	var fog_range: Array = preset.get("fog_density", [0.0, 0.0])
	var wind_range: Array = preset.get("wind_m_s", [3.0, 3.0])

	var wind_dir: float
	if prev_climate.has("wind_direction_deg"):
		var prev_dir: float = float(prev_climate.get("wind_direction_deg", 180.0))
		wind_dir = fposmod(prev_dir + rng.randf_range(-35.0, 35.0), 360.0)
	else:
		wind_dir = rng.randf_range(0.0, 360.0)

	var u: float = rng.randf()
	if prev_climate.has("climate_u"):
		u = clampf(float(prev_climate["climate_u"]) + rng.randf_range(-0.25, 0.25), 0.0, 1.0)

	var cumulus := lerpf(float(cumulus_range[0]), float(cumulus_range[1]), u)
	var cirrus := lerpf(float(cirrus_range[0]), float(cirrus_range[1]), clampf(u + rng.randf_range(-0.15, 0.15), 0.0, 1.0))
	var irr := lerpf(float(irr_range[0]), float(irr_range[1]), clampf(1.0 - u * 0.75 + rng.randf_range(-0.1, 0.1), 0.0, 1.0))
	var air := lerpf(float(air_range[0]), float(air_range[1]), clampf(1.0 - u * 0.5 + rng.randf_range(-0.15, 0.15), 0.0, 1.0))
	var precip := lerpf(float(precip_range[0]), float(precip_range[1]), u)
	var fog := lerpf(float(fog_range[0]), float(fog_range[1]), clampf(u + rng.randf_range(-0.1, 0.1), 0.0, 1.0))
	var wind_spd := lerpf(float(wind_range[0]), float(wind_range[1]), clampf(u * 0.6 + rng.randf_range(0.0, 0.4), 0.0, 1.0))

	return {
		"cumulus_coverage": cumulus,
		"cirrus_coverage": cirrus,
		"irradiance_w_m2": irr,
		"air_temperature_c": air,
		"precipitation_mm_h": precip,
		"fog_density": fog,
		"wind_m_s": wind_spd,
		"wind_direction_deg": wind_dir,
		"climate_u": u,
	}


## Simulación física del enlace (liaison) entre especiales para continuidad térmica e hidrológica.
static func simulate_liaison_physical_balance(gap_hours: float, start_abs_minutes: float, init_ground_c: float, init_water_mm: float, regional: Dictionary) -> Dictionary:
	var ground_c := init_ground_c
	var water_mm := init_water_mm
	var step_h := 0.25
	var steps := maxi(int(ceil(gap_hours / step_h)), 1)
	var dt_s := (gap_hours * 3600.0) / float(steps)
	var dt_h := gap_hours / float(steps)

	for i in steps:
		var cur_min := start_abs_minutes + float(i) * dt_h * 60.0
		var hour := fmod(cur_min / 60.0, 24.0)
		var solar := 0.0
		if hour >= 5.0 and hour <= 21.0:
			var t := (hour - 6.0) / 14.0
			solar = clampf(sin(t * PI), 0.0, 1.0)

		var ambient_air_c := lerpf(8.0, 22.0, solar)
		var solar_irradiance := 650.0 * solar
		var solar_gain := solar_irradiance * 0.65

		var air_exchange := 9.0 * (ground_c - ambient_air_c)
		var cap := 900.0 * 1000.0
		var d_ground := ((solar_gain - air_exchange) / cap) * dt_s
		ground_c = clampf(ground_c + d_ground, -5.0, 45.0)

		var evap := 0.35 * (solar_gain / 100.0) * dt_h
		var drainage := 6.0 * clampf(water_mm / 3.0, 0.08, 1.0) * dt_h
		water_mm = maxf(water_mm - (evap + drainage), 0.0)

	return {
		"ground_c": ground_c,
		"water_mm": water_mm,
	}


func _precipitation_kind(precip_mm_h: float, ground_c: float, profile: Dictionary) -> String:
	if precip_mm_h < 0.05:
		return "none"
	var ptype: Dictionary = profile.get("precipitation_type", {})
	var rain_above := float(ptype.get("rain_above_c", 2.0))
	var snow_below := float(ptype.get("snow_below_c", 0.0))
	if ground_c >= rain_above:
		return "rain"
	if ground_c <= snow_below:
		return "snow"
	return "rain" if precip_mm_h < 4.0 else "mixed"


## Genera el cronograma climático completo del rally. Llamar una sola vez
## tras Aceptar el reglaje; el resultado resuelto se persiste.
func generate_event_schedule(event_doc: Dictionary, stage_order: Array, itinerary: Array, rally_seed: int, route_paths: Dictionary = {}) -> Dictionary:
	error = ""
	var rules: Dictionary = event_doc.get("weather_rules", {})
	if rules.is_empty():
		return {"ok": false, "error": "El evento no define weather_rules"}
	var ordered: Array = rules.get("ordered_states", [])
	if ordered.is_empty():
		return {"ok": false, "error": "ordered_states no puede estar vacío"}
	var within_allowed: Array = rules.get("within_stage_allowed_steps", [-1, 0, 1]).map(func(value): return int(value))
	var between_allowed: Array = rules.get("between_stages_allowed_steps", [-2, -1, 0, 1, 2]).map(func(value): return int(value))
	for s in within_allowed:
		if abs(int(s)) > 1:
			return {"ok": false, "error": "within_stage_allowed_steps admite -1, 0 o 1"}
	for s in between_allowed:
		if abs(int(s)) > 2:
			return {"ok": false, "error": "between_stages_allowed_steps admite pasos entre -2 y 2"}
	var catalog := _read_json(str(rules.get("preset_catalog_path", PRESET_CATALOG_PATH)))
	if catalog.is_empty():
		return {"ok": false, "error": "Catálogo de presets ilegible: " + error}
	var regional_id := str(rules.get("regional_profile_id", "russia_summer"))
	var regional: Dictionary = ((catalog.get("regional_profiles", {}) as Dictionary).get(regional_id, {}) as Dictionary)
	if regional.is_empty():
		return {"ok": false, "error": "Perfil regional ausente: " + regional_id}
	var presets: Dictionary = catalog.get("presets", {})
	for sid in ordered:
		if not (presets as Dictionary).has(str(sid)):
			return {"ok": false, "error": "Preset ausente en catálogo: " + str(sid)}
	var seed := climate_seed(rally_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# Estado inicial ponderado por lugar/estación.
	var init_weights_d: Dictionary = regional.get("initial_state_weights", {})
	var init_options: Array = []
	var init_weights: Array = []
	for i in ordered.size():
		init_options.append(i)
		init_weights.append(float(init_weights_d.get(str(ordered[i]), 1.0)))
	var current := _pick_weighted(rng, init_options, init_weights)
	var adv_w := float(regional.get("within_stage_advance_weight", 0.55))
	var ret_w := float(regional.get("within_stage_retreat_weight", 0.45))
	var schedule: Array = []
	var route_hashes := {}
	var prev_avg_water := 0.3
	var prev_avg_ground := 17.0
	for si in stage_order.size():
		var stage_id := str(stage_order[si])
		var route_path: String = str(route_paths.get(stage_id, "res://data/rally/%s_route.json" % stage_id))
		var zone_info := compute_zones_for_route(route_path, rules)
		if not bool(zone_info.get("ok", false)):
			return {"ok": false, "error": str(zone_info.get("error", "ruta incompatible"))}
		route_hashes[stage_id] = str(zone_info.get("route_hash", ""))
		var sched_entry: Dictionary = (itinerary[si] as Dictionary).duplicate(true) if si < itinerary.size() else {"stage_id": stage_id}
		var zones_out: Array = []
		var gap_h := 2.0
		if si > 0 and si < itinerary.size():
			var prev_abs := float((itinerary[si - 1] as Dictionary).get("absolute_minutes", (si - 1) * 120.0))
			var cur_abs := float((itinerary[si] as Dictionary).get("absolute_minutes", si * 120.0))
			gap_h = maxf((cur_abs - prev_abs) / 60.0, 0.25)
		# Transición sinóptica entre stages (no en el primero):
		if si > 0:
			var candidates: Array = []
			var cand_weights: Array = []
			var cur_abs_min := float(sched_entry.get("absolute_minutes", si * 120.0))
			var t_h := cur_abs_min / 60.0
			var front_trend := sin(t_h * 0.3 + float(seed % 100) * 0.05) * 0.5 + cos(t_h * 0.15 + float(seed % 50) * 0.08) * 0.5
			var b_stay_w := float(regional.get("between_stages_stay_weight", 0.30))
			for step in between_allowed:
				var nxt: int = current + int(step)
				if nxt >= 0 and nxt < ordered.size():
					candidates.append(nxt)
					var w := 1.0
					if int(step) == 0:
						w = b_stay_w * maxf(1.0 - (gap_h - 1.0) * 0.04, 0.15)
					elif int(step) > 0:
						w = maxf(1.0 + front_trend * 0.8, 0.2)
					else:
						w = maxf(1.0 - front_trend * 0.8, 0.2)
					cand_weights.append(w)
			if candidates.is_empty():
				return {"ok": false, "error": "Sin transición válida entre stages hacia %s; se rechaza sin sustituir" % stage_id}
			current = _pick_weighted(rng, candidates, cand_weights)
		var antecedent: Dictionary = (regional.get("antecedent_policy", {}) as Dictionary).duplicate(true)
		var prev_zone_climate: Dictionary = {}
		for zi in 3:
			# Transición dentro del stage (permite conservar estado o avanzar/retroceder suave):
			if zi > 0:
				var opts: Array = []
				var opts_w: Array = []
				var stay_w := float(regional.get("within_stage_stay_weight", 0.35))
				for s in within_allowed:
					var cand: int = current + int(s)
					if cand >= 0 and cand < ordered.size():
						opts.append(cand)
						if int(s) == 0:
							opts_w.append(stay_w)
						elif int(s) > 0:
							opts_w.append(adv_w)
						else:
							opts_w.append(ret_w)
				if opts.is_empty():
					return {"ok": false, "error": "Sin transición válida dentro de %s; se rechaza sin sustituir" % stage_id}
				current = _pick_weighted(rng, opts, opts_w)
			var state_id := str(ordered[current])
			var preset: Dictionary = presets[state_id]
			var climate := _resolve_climate_values(rng, preset, prev_zone_climate)
			prev_zone_climate = climate
			# Antecedentes físicos regionales y continuidad térmica/hidrológica:
			var init_water_lo := float(((antecedent.get("initial_water_mm", [0.0, 1.2]) as Array)[0]))
			var init_water_hi := float(((antecedent.get("initial_water_mm", [0.0, 1.2]) as Array)[1]))
			var base_water := _sample_range(rng, init_water_lo, init_water_hi)
			var ground_lo := 13.0
			var ground_hi := 21.0
			if antecedent.has("initial_ground_c"):
				ground_lo = float((antecedent["initial_ground_c"] as Array)[0])
				ground_hi = float((antecedent["initial_ground_c"] as Array)[1])
			var ground_c := _sample_range(rng, ground_lo, ground_hi)
			if si > 0 and zi == 0:
				var prev_abs_m := float((itinerary[si - 1] as Dictionary).get("absolute_minutes", (si - 1) * 120.0)) if si > 0 and si - 1 < itinerary.size() else float((si - 1) * 120.0)
				var sim_res := simulate_liaison_physical_balance(gap_h, prev_abs_m, prev_avg_ground, prev_avg_water, regional)
				var precip_add := float(climate.get("precipitation_mm_h", 0.0)) * (0.30 + rng.randf() * 0.20)
				base_water = clampf(float(sim_res.water_mm) + precip_add, 0.0, 12.0)
				ground_c = lerpf(float(sim_res.ground_c), float(climate.get("air_temperature_c", ground_c)), 0.35) + rng.randf_range(-0.5, 0.5)
			elif zi > 0:
				var carry_water: float = float((zones_out[zi - 1] as Dictionary).get("initial_water_mm", base_water))
				var carry_ground: float = float((zones_out[zi - 1] as Dictionary).get("initial_ground_c", ground_c))
				var precip_add := float(climate.get("precipitation_mm_h", 0.0)) * (0.22 + rng.randf() * 0.18)
				base_water = clampf(carry_water * 0.85 + precip_add * 0.38 + base_water * 0.15, 0.0, 12.0)
				ground_c = lerpf(carry_ground, float(climate.get("air_temperature_c", ground_c)), 0.28) + rng.randf_range(-0.4, 0.4)
			else:
				if float(climate.get("precipitation_mm_h", 0.0)) > 0.5:
					base_water = maxf(base_water, 0.8 + rng.randf() * 1.2)
				ground_c = lerpf(ground_c, float(climate.get("air_temperature_c", ground_c)), 0.3)
			var init_sat_lo := 0.05
			var init_sat_hi := 0.35
			if antecedent.has("initial_saturation"):
				init_sat_lo = float((antecedent["initial_saturation"] as Array)[0])
				init_sat_hi = float((antecedent["initial_saturation"] as Array)[1])
			var saturation := clampf(_sample_range(rng, init_sat_lo, init_sat_hi) + base_water * 0.06, 0.0, 1.0)
			var snow_mm := 0.0
			if _precipitation_kind(float(climate.get("precipitation_mm_h", 0.0)), ground_c, regional) in ["snow", "mixed"]:
				snow_mm = _sample_range(rng, 0.2, 2.5)
			var zone_tpl: Dictionary = (zone_info["zones"] as Array)[zi]
			zones_out.append({
				"zone_index": zi,
				"start_node": int(zone_tpl["start_node"]),
				"end_node_exclusive": int(zone_tpl["end_node_exclusive"]),
				"start_distance_m": float(zone_tpl["start_distance_m"]),
				"end_distance_m": float(zone_tpl["end_distance_m"]),
				"length_m": float(zone_tpl["length_m"]),
				"blend_length_m": float(zone_tpl["blend_length_m"]),
				"weather_state_id": state_id,
				"weather_state_index": current,
				"climate": climate,
				"precipitation_kind": _precipitation_kind(float(climate.get("precipitation_mm_h", 0.0)), ground_c, regional),
				"initial_air_c": float(climate.get("air_temperature_c", 15.0)),
				"initial_ground_c": ground_c,
				"initial_water_mm": base_water,
				"initial_saturation": saturation,
				"initial_snow_mm": snow_mm,
				"antecedent": {"gap_hours": gap_h, "regional_profile": regional_id, "prev_avg_water_mm": prev_avg_water, "prev_avg_ground_c": prev_avg_ground},
				"reference_time": str(sched_entry.get("date", "")) + " " + str(sched_entry.get("start", "")),
			})
		var avg_w := 0.0
		var avg_g := 0.0
		for z in zones_out:
			avg_w += float((z as Dictionary).get("initial_water_mm", 0.0))
			avg_g += float((z as Dictionary).get("initial_ground_c", 15.0))
		prev_avg_water = avg_w / 3.0
		prev_avg_ground = avg_g / 3.0
		schedule.append({
			"stage_id": stage_id,
			"date": str(sched_entry.get("date", "")),
			"start": str(sched_entry.get("start", "")),
			"absolute_minutes": float(sched_entry.get("absolute_minutes", 0.0)),
			"route_hash": str(route_hashes[stage_id]),
			"regional_profile": regional_id,
			"zones": zones_out,
		})
	var rules_hash := rules_hash_for(event_doc, route_hashes)
	return {
		"ok": true,
		"schedule": schedule,
		"climate_seed": seed,
		"generator_version": GENERATOR_VERSION,
		"rules_hash": rules_hash,
		"route_hashes": route_hashes,
		"surface_continuity": {
			"policy": "regional_shared_context",
			"regional_profile": regional_id,
			"shared_sections": (regional.get("antecedent_policy", {}) as Dictionary).get("shared_sections", []),
			"evolution": (regional.get("evolution", {}) as Dictionary),
			"note": "Las etiquetas conservar/mejorar/empeorar son resultados derivados por variable (una carretera puede secarse mientras se enfría); no se asignan al azar.",
		},
	}


static func rules_hash_for(event_doc: Dictionary, route_hashes: Dictionary) -> String:
	var weather_path := str((event_doc.get("weather_rules", {}) as Dictionary).get("preset_catalog_path", PRESET_CATALOG_PATH))
	var tire_path := str((event_doc.get("tire_rules", {}) as Dictionary).get("compound_catalog_path", COMPOUND_CATALOG_PATH))
	var payload := {
		"weather_catalog": FileAccess.get_file_as_string(weather_path).sha256_text(),
		"tire_catalog": FileAccess.get_file_as_string(tire_path).sha256_text(),
		"itinerary": event_doc.get("itinerary_default", {}),
		"event": event_doc.get("event_id", ""),
		"stages": event_doc.get("stages_explicit_order", []),
		"points": event_doc.get("points_profile_id", ""),
		"policy": event_doc.get("retirement_policy", {}),
		"weather_rules": event_doc.get("weather_rules", {}),
		"tire_rules": event_doc.get("tire_rules", {}),
		"setup_windows": event_doc.get("setup_windows", []),
		"routes": route_hashes,
		"generator_version": GENERATOR_VERSION,
	}
	return JSON.stringify(payload).sha256_text()


## Pronóstico resumido de la próxima mitad: orienta sin revelar la secuencia exacta.
static func forecast_for_half(schedule: Array, from_stage: int, count: int = 5) -> Dictionary:
	var wet := 0
	var dry := 0
	var snow := 0
	var total := 0
	for i in range(from_stage, mini(from_stage + count, schedule.size())):
		for z in ((schedule[i] as Dictionary).get("zones", []) as Array):
			total += 1
			var mm := float(((z as Dictionary).get("climate", {}) as Dictionary).get("precipitation_mm_h", 0.0))
			var kind := str((z as Dictionary).get("precipitation_kind", "none"))
			if kind == "snow" or kind == "mixed":
				snow += 1
			if mm >= 2.5:
				wet += 1
			elif mm < 0.3:
				dry += 1
	var summary := "Seco %d/%d · Húmedo %d/%d" % [dry, total, wet, total]
	if snow > 0:
		summary += " · Nieve %d/%d" % [snow, total]
	var advice := "Grava normal"
	if wet >= 4 or (wet >= 2 and total <= 9):
		advice = "Grava lluvia"
	return {"total_zones": total, "dry_zones": dry, "wet_zones": wet, "snow_zones": snow, "summary": summary, "suggested_compound": advice}


static func validate_schedule(schedule: Array, stage_order: Array, rules: Dictionary) -> Dictionary:
	if schedule.size() != stage_order.size():
		return {"ok": false, "error": "El cronograma debe cubrir las diez especiales"}
	var within_allowed: Array = rules.get("within_stage_allowed_steps", [-1, 1]).map(func(value): return int(value))
	var between_allowed: Array = rules.get("between_stages_allowed_steps", [-2, -1, 1, 2]).map(func(value): return int(value))
	var prev_last_idx := -1
	for si in schedule.size():
		var entry: Dictionary = schedule[si]
		if str(entry.get("stage_id", "")) != str(stage_order[si]):
			return {"ok": false, "error": "Orden del cronograma distinto del itinerario en %d" % si}
		var zones: Array = entry.get("zones", [])
		if zones.size() != 3:
			return {"ok": false, "error": "Se requieren exactamente tres zonas en " + str(entry.get("stage_id", ""))}
		var prev_end := 0
		for zi in 3:
			var z: Dictionary = zones[zi]
			if int(z.get("zone_index", -1)) != zi:
				return {"ok": false, "error": "Zona desordenada en " + str(entry.get("stage_id", ""))}
			if int(z.get("start_node", -1)) != prev_end:
				return {"ok": false, "error": "Hueco o solapamiento en %s zona %d" % [str(entry.get("stage_id", "")), zi]}
			prev_end = int(z.get("end_node_exclusive", -1))
			if zi > 0:
				var step: int = int(z.get("weather_state_index", 0)) - int((zones[zi - 1] as Dictionary).get("weather_state_index", 0))
				if not (step in within_allowed):
					return {"ok": false, "error": "Paso interno inválido en %s zona %d: %d" % [str(entry.get("stage_id", "")), zi, step]}
			if zi == 0 and si > 0:
				var bstep: int = int(z.get("weather_state_index", 0)) - prev_last_idx
				if not (bstep in between_allowed):
					return {"ok": false, "error": "Paso externo inválido hacia %s: %d" % [str(entry.get("stage_id", "")), bstep]}
		prev_last_idx = int((zones[2] as Dictionary).get("weather_state_index", 0))
	return {"ok": true}
