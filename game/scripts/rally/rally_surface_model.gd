class_name RallySurfaceModel
extends RefCounted
## Modelo local de superficie por zona: temperatura de superficie (suelo),
## agua superficial (mm), saturación del suelo, nieve acumulada (mm eq. agua)
## y nieve efectiva sobre el contacto. La humedad relativa del aire es otro
## dato; no equivale a carretera mojada.
##
## Evoluciona por balance de energía (aporte solar menos intercambio con
## aire, lluvia/nieve y evaporación) y balance hídrico (precipitación/deshielo
## menos drenaje/evaporación). Todas las zonas evolucionan según el reloj
## ambiental común, incluyendo las no visitadas, con pasos acotados
## independientes del FPS. En pausa/reglaje/carga no avanza.

var zones: Array = []
var surface_profiles: Dictionary = {}
var regional_id: String = "russia_summer"
var valid: bool = false


func configure_from_schedule(entry: Dictionary, catalog: Dictionary) -> bool:
	zones.clear()
	surface_profiles.clear()
	valid = false
	if entry.is_empty():
		return false
	regional_id = str(entry.get("regional_profile", "russia_summer"))
	var regional: Dictionary = ((catalog.get("regional_profiles", {}) as Dictionary).get(regional_id, {}) as Dictionary)
	if regional.is_empty():
		return false
	surface_profiles = ((regional.get("surface_profiles", {}) as Dictionary).duplicate(true))
	for z in (entry.get("zones", []) as Array):
		var zd: Dictionary = (z as Dictionary).duplicate(true)
		zones.append({
			"zone_index": int(zd.get("zone_index", 0)),
			"air_c": float(zd.get("initial_air_c", 15.0)),
			"ground_c": float(zd.get("initial_ground_c", 15.0)),
			"water_mm": float(zd.get("initial_water_mm", 0.0)),
			"saturation": clampf(float(zd.get("initial_saturation", 0.1)), 0.0, 1.0),
			"snow_mm": float(zd.get("initial_snow_mm", 0.0)),
			"climate": (zd.get("climate", {}) as Dictionary).duplicate(true),
			"precipitation_kind": str(zd.get("precipitation_kind", "none")),
			"start_distance_m": float(zd.get("start_distance_m", 0.0)),
			"end_distance_m": float(zd.get("end_distance_m", 0.0)),
			"length_m": float(zd.get("length_m", 1.0)),
			"blend_length_m": float(zd.get("blend_length_m", 50.0)),
		})
	valid = zones.size() == 3
	return valid


func zone_count() -> int:
	return zones.size()


func state_for_zone(zi: int) -> Dictionary:
	if zi < 0 or zi >= zones.size():
		return {}
	return (zones[zi] as Dictionary).duplicate(true)


## Interpolación espacial en límites de zona (smoothstep sobre la franja de
## mezcla). Las franjas son interpolación, no otra zona.
func blended_state_at_distance(dist_m: float) -> Dictionary:
	if zones.is_empty():
		return {}
	var zi := zone_index_at_distance(dist_m)
	var z: Dictionary = zones[zi]
	# Buscar si estamos dentro de la franja anterior al límite.
	for boundary_index in range(1, zones.size()):
		z = zones[boundary_index - 1]
		var next: Dictionary = zones[boundary_index]
		var boundary: float = float(next.get("start_distance_m", 0.0))
		var blend: float = minf(float(z.get("blend_length_m", 50.0)), float(next.get("blend_length_m", 50.0)))
		var half := blend * 0.5
		if absf(dist_m - boundary) <= half and half > 0.01:
			var t := smoothstep(0.0, 1.0, clampf((dist_m - (boundary - half)) / (half * 2.0), 0.0, 1.0))
			return _lerp_states(z, next, t)
	return (zones[zi] as Dictionary).duplicate(true)


func zone_index_at_distance(dist_m: float) -> int:
	for i in zones.size():
		var z: Dictionary = zones[i]
		if dist_m < float(z.get("end_distance_m", INF)) or i == zones.size() - 1:
			if dist_m >= float(z.get("start_distance_m", 0.0)) or i == 0:
				return i
	# Fuera de rango: sujetar al extremo más próximo (salida de carretera).
	if dist_m < float((zones[0] as Dictionary).get("start_distance_m", 0.0)):
		return 0
	return zones.size() - 1


static func _lerp_states(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := (a as Dictionary).duplicate(true)
	for k in ["air_c", "ground_c", "water_mm", "saturation", "snow_mm"]:
		out[k] = lerpf(float(a.get(k, 0.0)), float(b.get(k, 0.0)), t)
	# El clima también se mezcla para irradiancia/precipitación visual.
	var ca: Dictionary = a.get("climate", {})
	var cb: Dictionary = b.get("climate", {})
	var mixed := {}
	for ck in ca:
		if cb.has(ck):
			mixed[ck] = lerpf(float(ca[ck]), float(cb[ck]), t)
		else:
			mixed[ck] = ca[ck]
	out["climate"] = mixed
	out["blend_t"] = t
	out["blend_from"] = a.get("zone_index", 0)
	out["blend_to"] = b.get("zone_index", 0)
	return out


## Avanza todas las zonas según el reloj ambiental común. Llamar solo cuando
## el reloj avanza (no en pausa/reglaje/carga). Usa pasos acotados.
func advance_ambient(delta_s: float, solar_factor: float = 1.0) -> void:
	if not valid or delta_s <= 0.0:
		return
	var max_step := 5.0
	var remaining := delta_s
	while remaining > 0.001:
		var h := minf(remaining, max_step)
		_step_all(h, solar_factor)
		remaining -= h


func _step_all(h: float, solar_factor: float) -> void:
	for i in zones.size():
		var z: Dictionary = zones[i]
		var climate: Dictionary = z.get("climate", {})
		var profile: Dictionary = _profile_for_surface("Gravel")
		var irr := float(climate.get("irradiance_w_m2", 100.0)) * clampf(solar_factor, 0.0, 1.0)
		var air := float(z.get("air_c", 15.0))
		var ground := float(z.get("ground_c", 15.0))
		var water := float(z.get("water_mm", 0.0))
		var sat := float(z.get("saturation", 0.1))
		var snow := float(z.get("snow_mm", 0.0))
		var precip := float(climate.get("precipitation_mm_h", 0.0))
		var kind := str(z.get("precipitation_kind", "none"))
		# Balance de energía: aporte solar menos intercambio con aire,
		# lluvia/nieve y evaporación. Capacidad térmica por superficie.
		var cap := float(profile.get("thermal_capacity_kj_m2_k", 900.0)) * 1000.0
		var solar_gain := irr * float(profile.get("solar_absorption", 0.62))
		var air_loss := float(profile.get("air_exchange_w_m2_k", 9.0)) * (ground - air)
		var evap_loss := _evaporation_mm_h(irr, water, profile) * 680.0
		var precip_cool := 0.0
		if kind == "rain":
			precip_cool = precip * 4.0 * maxf(ground - air, 0.0) * 0.12
		elif kind in ["snow", "mixed"]:
			precip_cool = (2.0 + precip * 0.8) * maxf(ground - 1.0, 0.0) * 0.2
		var d_ground := (solar_gain - air_loss - evap_loss - precip_cool) / maxf(cap, 1.0) * h
		ground = clampf(ground + d_ground, -12.0, 55.0)
		# Balance hídrico: precipitación/deshielo menos drenaje/evaporación.
		var melt := 0.0
		if snow > 0.0 and ground > 0.5:
			melt = minf(snow, (ground * 0.02 + irr * 0.0004) * h / 3600.0 * 10.0)
			snow -= melt
		var precip_in := 0.0
		if kind == "rain":
			precip_in = precip * h / 3600.0
		elif kind == "mixed":
			precip_in = precip * 0.6 * h / 3600.0
			snow += precip * 0.4 * h / 3600.0
		elif kind == "snow":
			snow += precip * h / 3600.0
		var drain := float(profile.get("drainage_mm_h", 6.0)) * clampf(water / 3.0, 0.0, 1.0) * h / 3600.0
		var evap := _evaporation_mm_h(irr, water, profile) * h / 3600.0
		water = clampf(water + precip_in + melt - drain - evap, 0.0, 15.0)
		sat = clampf(sat + (precip_in + melt) * 0.08 - drain * 0.05 - evap * 0.03, 0.0, 1.0)
		z["ground_c"] = ground
		z["water_mm"] = water
		z["saturation"] = sat
		z["snow_mm"] = snow
		# El aire de la zona sigue al clima resuelto con inercia suave.
		var target_air := float(climate.get("air_temperature_c", air))
		z["air_c"] = lerpf(air, target_air, clampf(h / 240.0, 0.0, 1.0))
		zones[i] = z


func _evaporation_mm_h(irradiance: float, water_mm: float, profile: Dictionary) -> float:
	if water_mm <= 0.001:
		return 0.0
	return float(profile.get("evaporation_mm_h_per_100w", 0.35)) * (irradiance / 100.0) * clampf(water_mm / 2.0, 0.15, 1.0)


func _profile_for_surface(surface: String) -> Dictionary:
	if surface_profiles.has(surface):
		return surface_profiles[surface]
	if surface_profiles.has("Gravel"):
		return surface_profiles["Gravel"]
	return {"solar_absorption": 0.62, "thermal_capacity_kj_m2_k": 900.0, "air_exchange_w_m2_k": 9.0, "evaporation_mm_h_per_100w": 0.35, "drainage_mm_h": 6.0}


## Nieve efectiva sobre el contacto (mm): limita por dibujo disponible.
func effective_snow_mm(state: Dictionary) -> float:
	return clampf(float(state.get("snow_mm", 0.0)), 0.0, 8.0)


func snapshot() -> Array:
	return zones.duplicate(true)


func restore_snapshot(data: Array) -> void:
	zones = (data as Array).duplicate(true)
	valid = zones.size() == 3
