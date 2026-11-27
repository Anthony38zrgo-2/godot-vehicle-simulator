class_name GarageSetupPresenter
extends RefCounted
## Pure presentation/domain helper for RallyGaragePanel:
## resolves vehicle names via registry.json, loads stage routes/altitude/terrain briefings,
## formats setup fields, and computes gear speeds & differential summaries.

const _Catalog := preload("res://scripts/ui/services/menu_catalog_service.gd")
const REGISTRY_PATH := "res://data/vehicles/registry.json"

static var _vehicle_registry_cache: Array = []
static var _vehicle_registry_loaded: bool = false


static func get_vehicle_registry_entries() -> Array:
	if _vehicle_registry_loaded:
		return _vehicle_registry_cache
	_vehicle_registry_loaded = true
	if not FileAccess.file_exists(REGISTRY_PATH):
		return _vehicle_registry_cache
	var file := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if file == null:
		return _vehicle_registry_cache
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var pd := parsed as Dictionary
		var lower_v: Variant = pd.get("vehicles")
		if lower_v is Dictionary:
			_vehicle_registry_cache = (lower_v as Dictionary).values()
		elif lower_v is Array:
			_vehicle_registry_cache = lower_v as Array
		elif pd.get("Vehicles") is Array:
			_vehicle_registry_cache = pd.get("Vehicles") as Array
	elif parsed is Array:
		_vehicle_registry_cache = parsed as Array
	return _vehicle_registry_cache


static func resolve_vehicle_display_name(vehicle: Node, team_name: String = "") -> String:
	if vehicle != null:
		var manifest_val: Variant = vehicle.get("rally_asset_manifest")
		if manifest_val is Dictionary:
			var source_val: Variant = (manifest_val as Dictionary).get("source", {})
			if source_val is Dictionary:
				var recipe_val: Variant = (source_val as Dictionary).get("recipe", {})
				if recipe_val is Dictionary:
					var recipe_name := str((recipe_val as Dictionary).get("display_name", "")).strip_edges()
					if not recipe_name.is_empty():
						return recipe_name.to_upper()

		var profile_val: Variant = vehicle.get("rally_profile")
		var profile_dict: Dictionary = profile_val if profile_val is Dictionary else {}
		var profile_id := str(profile_dict.get("profile_id", "")).strip_edges().to_lower()
		var profile_path := str(vehicle.get("rally_profile_path")).strip_edges().to_lower()
		var node_name := str(vehicle.name).strip_edges().to_lower()
		for entry in get_vehicle_registry_entries():
			if not (entry is Dictionary):
				continue
			var d := entry as Dictionary
			var eid := str(d.get("Id", "")).strip_edges().to_lower()
			var eprof := str(d.get("Profile", "")).strip_edges().to_lower()
			var disp := str(d.get("DisplayName", "")).strip_edges()
			if disp.is_empty():
				continue
			if (not profile_id.is_empty() and (profile_id == eid or profile_id == eprof or profile_id == eprof.get_file())) \
					or (not profile_path.is_empty() and not eprof.is_empty() and profile_path.contains("/%s/" % eprof)) \
					or (not node_name.is_empty() and node_name != "vehicle" and (node_name == eid or (not eprof.is_empty() and node_name.contains(eprof.get_file())))):
				return disp.to_upper()

		var direct_name := str(profile_dict.get("display_name", profile_dict.get("profile_name", ""))).strip_edges()
		if not direct_name.is_empty():
			return direct_name.to_upper()
		if node_name.contains("fulvia") or profile_path.contains("fulvia"):
			return "LANCIA FULVIA HF"
		if node_name.contains("escort") or profile_path.contains("escort"):
			return "FORD ESCORT RS2000"
	if not team_name.is_empty() and team_name != "Ford Rally Works":
		return team_name.to_upper()
	return "FORD ESCORT RS2000"


static func normalize_stage_id(circuit_id: String) -> String:
	var cid := circuit_id.strip_edges().to_lower().replace("-", "_")
	var regex := RegEx.new()
	regex.compile("^([a-z_]+)_stage_(\\d+)$")
	var m := regex.search(cid)
	if m != null:
		return "%s_stage%s" % [m.get_string(1), m.get_string(2)]
	return cid


static func resolve_stage_route_path(explicit_path: String, circuit_id: String) -> String:
	if not explicit_path.strip_edges().is_empty():
		return explicit_path.strip_edges()
	var cid := normalize_stage_id(circuit_id)
	if cid.is_empty():
		return ""
	var candidate := "res://data/rally/%s_route.json" % cid
	if FileAccess.file_exists(candidate):
		return candidate
	return ""


static func compute_vertical_stage_points(raw_points: Array) -> PackedVector2Array:
	if raw_points.size() < 2:
		return PackedVector2Array()
	var pts_2d: Array[Vector2] = []
	var center := Vector2.ZERO
	for p in raw_points:
		if p is Array and (p as Array).size() >= 3:
			var arr := p as Array
			var v := Vector2(float(arr[0]), float(arr[2]))
			pts_2d.append(v)
			center += v
	if pts_2d.size() < 2:
		return PackedVector2Array()
	center /= float(pts_2d.size())

	var xx := 0.0
	var yy := 0.0
	var xy := 0.0
	for v in pts_2d:
		var off := v - center
		xx += off.x * off.x
		yy += off.y * off.y
		xy += off.x * off.y

	var angle := -PI * 0.5 - atan2(2.0 * xy, xx - yy) * 0.5
	if (pts_2d[-1] - pts_2d[0]).rotated(angle).y > 0.0:
		angle += PI

	var rotated_pts: Array[Vector2] = []
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for v in pts_2d:
		var rot_v := v.rotated(angle)
		rotated_pts.append(rot_v)
		min_v = min_v.min(rot_v)
		max_v = max_v.max(rot_v)

	var extent := max_v - min_v
	var max_dim := maxf(maxf(extent.x, extent.y), 0.001)
	var out := PackedVector2Array()
	for rv in rotated_pts:
		out.append((rv - min_v) / max_dim)
	return out


static func load_stage_route(explicit_path: String, circuit_id: String) -> Dictionary:
	var rpath := resolve_stage_route_path(explicit_path, circuit_id)
	var sid := normalize_stage_id(circuit_id)
	var result := {
		"key": sid + "|" + rpath,
		"points": PackedVector2Array(),
		"heights": PackedFloat32Array(),
		"profile_altitudes": PackedFloat32Array(),
		"length_m": 0.0,
	}
	if rpath.is_empty() or not FileAccess.file_exists(rpath):
		return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(rpath))
	if not (parsed is Dictionary):
		return result
	var doc := parsed as Dictionary
	result["length_m"] = float(doc.get("total_route_length_m", 0.0))

	var config_path := "res://data/competition/stages/%s.json" % sid
	var config: Dictionary = {}
	if FileAccess.file_exists(config_path):
		var cfg_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
		if cfg_doc is Dictionary:
			config = cfg_doc
	var reverse_route := bool(config.get("reverse_route", false))
	var raw_pts: Variant = doc.get("points", [])
	if raw_pts is Array:
		var pts_copy := (raw_pts as Array).duplicate()
		if reverse_route:
			pts_copy.reverse()
		result["points"] = compute_vertical_stage_points(pts_copy)
		var heights := PackedFloat32Array()
		for p in pts_copy:
			if p is Array and (p as Array).size() >= 3:
				heights.append(float((p as Array)[1]))
		result["heights"] = heights

	var map_id := str(config.get("map_id", sid))
	var prof_path := "res://assets/rally/%s/climate_route_profile.json" % map_id
	var prof_alts := PackedFloat32Array()
	if not sid.is_empty() and FileAccess.file_exists(prof_path):
		var prof_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(prof_path))
		if prof_parsed is Dictionary:
			var samples: Variant = (prof_parsed as Dictionary).get("samples", [])
			if samples is Array:
				for s in (samples as Array):
					if s is Dictionary and (s as Dictionary).has("altitude_m"):
						prof_alts.append(float((s as Dictionary)["altitude_m"]))
	if reverse_route:
		prof_alts.reverse()
	result["profile_altitudes"] = prof_alts
	return result


static func sector_weather_badge(sector: Dictionary, gold_color: Color) -> Dictionary:
	var has_cov := sector.has("ice_coverage")
	var ice_cov := float(sector.get("ice_coverage", 0.0))
	var snow_cov := float(sector.get("snow_coverage", 0.0))
	var water_cov := float(sector.get("water_coverage", 0.0))
	var ice := float(sector.get("ice_mm", 0.0))
	var snow := float(sector.get("snow_mm", 0.0))
	var snow_rate := float(sector.get("snow_mm_h", 0.0))
	var rain_rate := float(sector.get("rain_mm_h", 0.0))
	var water := float(sector.get("water_mm", 0.0))
	var cloud := float(sector.get("cloud_cover", 0.0))
	var ground_c := float(sector.get("ground_c", 5.0))

	if (has_cov and ice_cov >= 0.08) or (not has_cov and ice >= 0.25 and ground_c <= 0.0):
		return {"label": "HIELO", "color": Color("#22d3ee"), "detail": "%.1f mm hielo" % maxf(ice, snow)}
	if snow_cov >= 0.08 or snow_rate >= 0.35 or (snow >= 0.45 and ground_c <= 2.0):
		return {"label": "NIEVE", "color": Color("#e0f2fe"), "detail": "%.1f mm nieve" % snow}
	if rain_rate >= 0.35:
		return {"label": "LLUVIA", "color": Color("#38bdf8"), "detail": "%.1f mm/h · %.1f mm" % [rain_rate, water]}
	var basin_water := float(sector.get("basin_water_mm", 0.0))
	if water >= 0.15 or basin_water >= 0.25 or water_cov >= 0.15:
		return {"label": "HÚMEDO", "color": Color("#60a5fa"), "detail": "%.1f mm agua" % maxf(water, basin_water)}
	if cloud >= 0.50:
		return {"label": "NUBLADO", "color": Color("#94a3b8"), "detail": "Piso seco"}
	return {"label": "SECO", "color": gold_color, "detail": "Piso seco"}


static func build_terrain_bars(terrain: Dictionary, sectors: Array, gold_color: Color) -> Array[Dictionary]:
	var is_asphalt := bool(terrain.get("is_asphalt", false))
	var loose := clampf(float(terrain.get("loose_gravel_avg", 0.0)), 0.0, 1.0)
	var mud := clampf(float(terrain.get("mud_avg", 0.0)), 0.0, 1.0)
	var water := clampf(float(terrain.get("water_avg", 0.0)), 0.0, 1.0)
	var snow := clampf(float(terrain.get("snow_avg", 0.0)), 0.0, 1.0)
	var ice := clampf(float(terrain.get("ice_avg", 0.0)), 0.0, 1.0)

	if not sectors.is_empty():
		var sec_wet := 0.0
		var sec_snow := 0.0
		for sd in sectors:
			var lbl := str(sector_weather_badge(sd as Dictionary, gold_color).get("label", "SECO"))
			if lbl in ["LLUVIA", "HÚMEDO"]:
				sec_wet += 1.0
			elif lbl in ["NIEVE", "HIELO"]:
				sec_snow += 1.0
		var n_s := float(sectors.size())
		water = maxf(water, (sec_wet / n_s) * (0.65 if is_asphalt else 0.35))
		snow = maxf(snow, (sec_snow / n_s) * 0.25)

	var winter_frac := clampf(snow + ice, 0.0, 1.0)
	var rem := maxf(1.0 - winter_frac, 0.0)
	var bars: Array[Dictionary] = []
	if is_asphalt:
		var wet_frac := clampf(water, 0.0, rem)
		var dry_frac := maxf(rem - wet_frac, 0.0)
		bars.append({"label": "ASFALTO SECO", "pct": roundi(dry_frac * 100.0), "color": Color("#94a3b8")})
		bars.append({"label": "ASFALTO MOJADO", "pct": roundi(wet_frac * 100.0), "color": Color("#38bdf8")})
		bars.append({"label": "NIEVE / HIELO", "pct": roundi(winter_frac * 100.0), "color": Color("#bae6fd")})
	else:
		var loose_frac := clampf(loose * (1.0 - mud) * rem, 0.0, rem)
		var mud_frac := clampf(maxf(mud, water * 0.65) * rem, 0.0, maxf(rem - loose_frac, 0.0))
		var compact_frac := maxf(rem - loose_frac - mud_frac, 0.0)
		bars.append({"label": "GRAVA COMPACTA", "pct": roundi(compact_frac * 100.0), "color": Color("#c89b54")})
		bars.append({"label": "GRAVILLA SUELTA", "pct": roundi(loose_frac * 100.0), "color": gold_color})
		bars.append({"label": "BARRO / MOJADO", "pct": roundi(mud_frac * 100.0), "color": Color("#38bdf8")})
		bars.append({"label": "NIEVE / HIELO", "pct": roundi(winter_frac * 100.0), "color": Color("#bae6fd")})

	var total := 0
	var max_idx := 0
	for i in bars.size():
		total += int(bars[i]["pct"])
		if int(bars[i]["pct"]) > int(bars[max_idx]["pct"]):
			max_idx = i
	if total != 100 and not bars.is_empty():
		bars[max_idx]["pct"] = maxi(0, int(bars[max_idx]["pct"]) + (100 - total))
	return bars


static func gear_top_kmh(max_rpm: float, gear_ratio: float, final_drive: float, wheel_radius_m: float) -> float:
	var total_ratio := maxf(gear_ratio * final_drive, 0.05)
	var wheel_rpm := max_rpm / total_ratio
	return (wheel_rpm / 60.0) * (TAU * wheel_radius_m) * 3.6


static func differential_behavior_lines(draft_values: Dictionary, lsd_enabled: bool) -> Array[String]:
	if not lsd_enabled:
		return [
			"Diferencial ABIERTO activo: sin resistencia interna al girar.",
			"Máxima agilidad en curvas lentas, menor tracción si patina una rueda.",
			"Activa AUTOBLOCANTE arriba para habilitar discos y rampas.",
		]
	var clutches := int(draft_values.get("powertrain.differential.clutches", 4.0))
	var power_deg := float(draft_values.get("powertrain.differential.power_ramp_angle_deg", 60.0))
	var coast_deg := float(draft_values.get("powertrain.differential.coast_ramp_angle_deg", 60.0))
	var accel_desc := "ALTO (tracción agresiva)" if power_deg <= 55.0 else ("MEDIO (equilibrado)" if power_deg <= 75.0 else "SUAVE (giro libre)")
	var coast_desc := "ESTABLE al frenar" if coast_deg <= 55.0 else ("EQUILIBRADO en retención" if coast_deg <= 75.0 else "ÁGIL al soltar gas")
	return [
		"Autoblocante %d superficies · Bloqueo en gas: %s." % [clutches, accel_desc],
		"Comportamiento en retención: %s (%0.0f°)." % [coast_desc, coast_deg],
		"Menor ángulo (45°) = mayor bloqueo · Mayor ángulo (90°) = menos bloqueo.",
	]


static func field_description(path: String) -> String:
	match path:
		"garage.suspension":
			return "Suspensión: BLANDA absorbe baches en tierra; RÍGIDA da precisión en asfalto liso."
		"garage.front_arb":
			return "Estabilizadora del.: más RÍGIDA reduce balanceo pero aumenta el subviraje al entrar."
		"garage.rear_arb":
			return "Estabilizadora tras.: más RÍGIDA ayuda a rotar el coche en curva (más sobreviraje)."
		"brakes.front_brake_bias":
			return "Frenada: más DELANTERA da estabilidad; más TRASERA mete el morro en horquillas."
		"suspension.front.camber":
			return "Caída del.: valores negativos mejoran apoyo en curva; cercanos a 0° mejoran frenada recta."
		"suspension.rear.camber":
			return "Caída tras.: negativa sujeta la trasera en apoyo lateral; 0° maximiza tracción recta."
		"suspension.front.toe":
			return "Convergencia del.: abierta (-) agiliza entrada en giro; cerrada (+) estabiliza en recta."
		"suspension.rear.toe":
			return "Convergencia tras.: cerrada (+) estabiliza la zaga; abierta (-) hace la trasera más viva."
		"powertrain.final_drive":
			return "Relación final: valores BAJOS alargan marchas (vel. punta); ALTOS acortan (aceleración)."
		"powertrain.max_rpm":
			return "Limitador RPM: bajar el corte reduce consumo, calor y desgaste mecánico del motor en tramos largos."
		"garage.cooling":
			return "Mínima (3 %) reduce el flujo de aire en frío. Abrir el conducto enfría el motor y aumenta la resistencia."
		"garage.lsd":
			return "Diferencial: ABIERTO gira libre; AUTOBLOCANTE reparte par para traccionar en salida."
		"powertrain.differential.clutches":
			return "Discos de fricción: más superficies aumentan la fuerza máxima de bloqueo del autoblocante."
		"powertrain.differential.power_ramp_angle_deg":
			return "Rampa aceleración: 45° bloquea FUERTE al dar gas (+tracción); 90° deja girar más libre."
		"powertrain.differential.coast_ramp_angle_deg":
			return "Rampa retención: 45° estabiliza al soltar gas/frenar; 90° permite girar con más agilidad."
		"fuel.initial_kg":
			return "Combustible: cada litro extra añade peso (~0.74 kg/L). Ajusta lo necesario para el tramo."
		"garage.front_pressure":
			return "Presión del.: baja (130-160 kPa) da agarre en tierra; alta (180+ kPa) da precisión en asfalto."
		"garage.rear_pressure":
			return "Presión tras.: ajusta el agarre y temperatura de trabajo del eje trasero."
	if path.begins_with("mounted:") or path.begins_with("spare:") or path.begins_with("stock:"):
		return "Ruedas 3D: arrastra para mover entre coche, maletero (+18 kg c/u) y parque. Clic origen -> destino."
	return ""


static func format_field(field: Dictionary, path: String, draft_values: Dictionary, fuel_density: float) -> String:
	if path == "fuel.initial_kg":
		return "%.1f L" % (float(draft_values.get(path, 0.0)) / maxf(fuel_density, 0.1))
	if path == "brakes.front_brake_bias":
		var f := roundi(float(draft_values.get(path, 0.55)) * 100.0)
		return "%d/%d%%" % [f, 100 - f]
	var value := float(draft_values.get(path, 0.0))
	if path in ["garage.suspension", "garage.front_arb", "garage.rear_arb"]:
		return RallySetupCatalog.POSITION_LABELS[clampi(int(value) - 1, 0, 4)]
	if path == "garage.cooling":
		if value < 0.0:
			return "Mínima (%d %%)" % roundi(RallySetupCatalog.MINIMUM_COOLING_OPENING * 100.0)
		return "De serie" if value == 0.0 else "%d %%" % int(value * 25.0)
	if path == "garage.lsd":
		return "Autoblocante" if bool(value) else "Abierto"
	var scaled := value * float(field.get("scale", 1.0))
	var pattern := "%." + str(int(field.get("digits", 2))) + "f"
	var formatted := (pattern % scaled) + str(field.get("suffix", ""))
	if path.begins_with(RallySetupCatalog.DIFFERENTIAL_PREFIX) and value < float(field.get("min", 0.0)):
		formatted += " serie"
	return formatted


static func get_surface_presets() -> Array[Dictionary]:
	var layout := _Catalog.get_garage_layout()
	var out: Array[Dictionary] = []
	for p in layout.get("surface_presets", []):
		if p is Dictionary:
			out.append(p as Dictionary)
	if not out.is_empty():
		return out
	return [
		{
			"id": "gravel", "title": "BASE GRAVA / MIXTO", "subtitle": "Equilibrada · +altura · 55% frenada",
			"values": {"garage.suspension": 3.0, "garage.front_arb": 3.0, "garage.rear_arb": 3.0, "brakes.front_brake_bias": 0.55, "garage.cooling": 1.0}
		},
		{
			"id": "tarmac", "title": "BASE ASFALTO LISO", "subtitle": "Rígida · barras firmes · 60% frenada",
			"values": {"garage.suspension": 1.0, "garage.front_arb": 1.0, "garage.rear_arb": 2.0, "brakes.front_brake_bias": 0.60, "garage.cooling": 2.0}
		},
		{
			"id": "wet_rough", "title": "BASE LLUVIA / BACHES", "subtitle": "Blanda · tracción suave · 52% frenada",
			"values": {"garage.suspension": 5.0, "garage.front_arb": 5.0, "garage.rear_arb": 5.0, "brakes.front_brake_bias": 0.52, "garage.cooling": 0.0}
		},
	]
