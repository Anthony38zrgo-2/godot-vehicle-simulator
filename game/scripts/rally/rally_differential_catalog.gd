class_name RallyDifferentialCatalog
extends RefCounted

## Catálogo estático de presets de diferencial Rally Trophy (v1 producción).
## Origen de verdad: preset_id. Los valores mecánicos se resuelven desde aquí,
## nunca desde números libres del garaje.
## simulation_estimate_v1: differential_clutches = active_friction_surfaces,
## preload_nm = bench initial_simulation_seed, mu heredada del perfil base
## salvo calibration override no nulo. physical_disc_count informativo.

const PRODUCTION_PATH := "res://data/vehicles/differential_presets.json"
const PRESET_PATH := "powertrain.differential.preset_id"

# Modo dual configurable (game/data/vehicles/differential_config.json).
# modern (defecto): LSD autoblocante moderno totalmente configurable.
# historic: presets históricos por vehículo, selección discreta.
const MODE_CONFIG_PATH := "res://data/vehicles/differential_config.json"
const MODE_MODERN := "modern"
const MODE_HISTORIC := "historic"

static var _mode_cache: String = ""

static var _cache: Dictionary = {}
static var _cache_ok: bool = false


static func _load_document() -> Dictionary:
	if _cache_ok:
		return _cache
	if not FileAccess.file_exists(PRODUCTION_PATH):
		return {"ok": false, "error": "Catálogo de diferenciales no encontrado: " + PRODUCTION_PATH}
	var text := FileAccess.get_file_as_string(PRODUCTION_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"ok": false, "error": "Catálogo de diferenciales con JSON inválido."}
	_cache = parsed
	_cache_ok = true
	return _cache


static func reset_cache() -> void:
	_cache = {}
	_cache_ok = false


static func differential_mode() -> String:
	if not _mode_cache.is_empty():
		return _mode_cache
	_mode_cache = MODE_MODERN
	if FileAccess.file_exists(MODE_CONFIG_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MODE_CONFIG_PATH))
		if parsed is Dictionary:
			var m := str((parsed as Dictionary).get("differential_mode", MODE_MODERN)).to_lower()
			if m == MODE_HISTORIC or m == MODE_MODERN:
				_mode_cache = m
	return _mode_cache


static func reset_mode_cache() -> void:
	_mode_cache = ""


static func set_mode_override(mode: String) -> void:
	if mode == MODE_HISTORIC or mode == MODE_MODERN:
		_mode_cache = mode


static func _profiles(doc: Dictionary) -> Dictionary:
	var profiles: Variant = doc.get("profiles", {})
	return profiles if profiles is Dictionary else {}


## Resuelve alias (lancia-fulvia -> rt-lancia-fulvia, etc.).
## Devuelve {"profile_key":..., "entry":...} o error.
static func _resolve_profile_entry(doc: Dictionary, profile_id: String) -> Dictionary:
	var profiles := _profiles(doc)
	var seen: Array[String] = []
	var current := str(profile_id)
	while true:
		if current in seen:
			return {"ok": false, "error": "Alias circular de perfil: " + str(profile_id)}
		seen.append(current)
		if not profiles.has(current):
			return {"ok": false, "error": "Perfil desconocido en catálogo: " + str(profile_id)}
		var entry: Variant = profiles[current]
		if not entry is Dictionary:
			return {"ok": false, "error": "Entrada de perfil inválida: " + current}
		if (entry as Dictionary).has("alias_of"):
			current = str((entry as Dictionary)["alias_of"])
			continue
		return {"ok": true, "profile_key": current, "entry": entry}
	return {"ok": false, "error": "Alias sin resolver: " + str(profile_id)}


static func list_for_profile(profile_id: String) -> Array[Dictionary]:
	var doc := _load_document()
	if doc.has("error"):
		return []
	var resolved := _resolve_profile_entry(doc, profile_id)
	if not bool(resolved.get("ok", false)):
		return []
	var presets: Variant = (resolved["entry"] as Dictionary).get("presets", [])
	if not presets is Array:
		return []
	var out: Array[Dictionary] = []
	for p in presets:
		if p is Dictionary:
			out.append(p)
	return out


static func default_for_profile(profile_id: String) -> String:
	var doc := _load_document()
	if doc.has("error"):
		return ""
	var resolved := _resolve_profile_entry(doc, profile_id)
	if not bool(resolved.get("ok", false)):
		return ""
	return str((resolved["entry"] as Dictionary).get("default_preset_id", ""))


static func is_allowed(profile_id: String, preset_id: String) -> bool:
	var doc := _load_document()
	if doc.has("error"):
		return false
	var resolved := _resolve_profile_entry(doc, profile_id)
	if not bool(resolved.get("ok", false)):
		return false
	var presets: Variant = (resolved["entry"] as Dictionary).get("presets", [])
	if not presets is Array:
		return false
	for p in presets:
		if p is Dictionary and str((p as Dictionary).get("id", "")) == str(preset_id):
			return true
	return false


static func is_enabled(profile_id: String, preset_id: String) -> bool:
	var preset := get_preset(profile_id, preset_id)
	if preset.is_empty():
		return false
	return bool(preset.get("enabled", false))


static func get_preset(profile_id: String, preset_id: String) -> Dictionary:
	for p in list_for_profile(profile_id):
		if str(p.get("id", "")) == str(preset_id):
			return p
	return {}


## Resuelve un preset a parámetros mecánicos + metadatos de UI.
## base_mu: {"power": float, "coast": float} heredada del perfil base.
static func resolve(profile_id: String, preset_id: String, base_mu: Dictionary = {}) -> Dictionary:
	var preset := get_preset(profile_id, preset_id)
	if preset.is_empty():
		return {"ok": false, "error": "Preset no permitido para este vehículo: " + str(preset_id)}
	if not bool(preset.get("enabled", false)):
		return {"ok": false, "error": "Preset deshabilitado pendiente de calibración: " + str(preset_id)}
	var ptype := str(preset.get("type", "clutch_lsd"))
	if ptype != "clutch_lsd" and ptype != "adjustable_friction_lsd":
		return {"ok": false, "error": "Tipo de diferencial no soportado: " + ptype}
	var surfaces := int(preset.get("active_friction_surfaces", 0))
	if surfaces <= 0:
		return {"ok": false, "error": "Preset sin superficies activas: " + str(preset_id)}
	var ramp: Variant = preset.get("ramp_deg", null)
	if not ramp is Dictionary:
		return {"ok": false, "error": "Preset sin rampas: " + str(preset_id)}
	var power_ramp := float((ramp as Dictionary).get("power", -1.0))
	var coast_ramp := float((ramp as Dictionary).get("coast", -1.0))
	if not is_finite(power_ramp) or not is_finite(coast_ramp):
		return {"ok": false, "error": "Rampas no numéricas en preset: " + str(preset_id)}
	if power_ramp < 15.0 or power_ramp > 85.0 or coast_ramp < 15.0 or coast_ramp > 85.0:
		return {"ok": false, "error": "Rampas fuera de 15-85° en preset: " + str(preset_id)}
	var bench: Variant = preset.get("bench_preload_nm", null)
	if not bench is Dictionary:
		return {"ok": false, "error": "Preset sin precarga de banco: " + str(preset_id)}
	var seed := float((bench as Dictionary).get("initial_simulation_seed", -1.0))
	if not is_finite(seed) or seed < 0.0:
		return {"ok": false, "error": "Semilla de precarga inválida: " + str(preset_id)}
	var calib: Dictionary = preset.get("simulation_calibration", {}) if preset.get("simulation_calibration", {}) is Dictionary else {}
	var mu_power: Variant = calib.get("friction_mu_power", null)
	var mu_coast: Variant = calib.get("friction_mu_coast", null)
	var final_power := float(base_mu.get("power", 0.0))
	var final_coast := float(base_mu.get("coast", final_power))
	if mu_power is int or mu_power is float:
		final_power = float(mu_power)
	if mu_coast is int or mu_coast is float:
		final_coast = float(mu_coast)
	if not is_finite(final_power) or not is_finite(final_coast) or final_power < 0.0 or final_coast < 0.0:
		return {"ok": false, "error": "Fricción resultante inválida: " + str(preset_id)}
	var reported: Dictionary = preset.get("reported_nominal_lock_pct", {}) if preset.get("reported_nominal_lock_pct", {}) is Dictionary else {}
	return {
		"ok": true,
		"preset_id": str(preset_id),
		"type": ptype,
		"preload_nm": seed,
		"power_ramp_deg": power_ramp,
		"coast_ramp_deg": coast_ramp,
		"active_friction_surfaces": surfaces,
		"friction_mu_power": final_power,
		"friction_mu_coast": final_coast,
		# Metadatos solo lectura (ficha, no física):
		"bench_min_nm": float((bench as Dictionary).get("min", seed)),
		"bench_max_nm": float((bench as Dictionary).get("max", seed)),
		"reported_lock_pct_power": float(reported.get("power", 0.0)),
		"reported_lock_pct_coast": float(reported.get("coast", 0.0)),
		"supplier": str(preset.get("supplier_or_family", "")),
		"model_reference": str(preset.get("model_reference", "")),
		"label": str(preset.get("label", preset_id)),
		"physical_disc_count": preset.get("physical_disc_count", null),
	}


## Validación de contrato del catálogo (prueba 1).
static func validate_catalog() -> Dictionary:
	var doc := _load_document()
	if doc.has("error"):
		return doc
	var profiles := _profiles(doc)
	if profiles.is_empty():
		return {"ok": false, "error": "Catálogo sin perfiles."}
	var errors: Array[String] = []
	for key in profiles:
		var entry: Variant = profiles[key]
		if not entry is Dictionary:
			errors.append("Perfil no diccionario: " + str(key))
			continue
		if (entry as Dictionary).has("alias_of"):
			var target := str((entry as Dictionary)["alias_of"])
			if not profiles.has(target):
				errors.append("Alias sin destino: " + str(key) + " -> " + target)
			elif not (profiles[target] is Dictionary) or (profiles[target] as Dictionary).has("alias_of"):
				errors.append("Alias anidado no permitido: " + str(key))
			continue
		var presets: Variant = (entry as Dictionary).get("presets", [])
		if not presets is Array or (presets as Array).is_empty():
			errors.append("Perfil sin presets: " + str(key))
			continue
		var seen_ids := {}
		for p in presets:
			if not p is Dictionary:
				errors.append("Preset no diccionario en " + str(key))
				continue
			var pid := str((p as Dictionary).get("id", ""))
			if pid.is_empty():
				errors.append("Preset sin ID en " + str(key))
				continue
			if seen_ids.has(pid):
				errors.append("ID duplicado en " + str(key) + ": " + pid)
			seen_ids[pid] = true
			if not bool((p as Dictionary).get("enabled", false)):
				continue
			var surfaces := int((p as Dictionary).get("active_friction_surfaces", 0))
			if surfaces <= 0:
				errors.append("Superficies inválidas " + str(key) + "/" + pid)
			var ramp: Variant = (p as Dictionary).get("ramp_deg", null)
			if not ramp is Dictionary:
				errors.append("Sin rampas " + str(key) + "/" + pid)
			else:
				for side in ["power", "coast"]:
					var v := float((ramp as Dictionary).get(side, -1.0))
					if not is_finite(v) or v < 15.0 or v > 85.0:
						errors.append("Rampa fuera de rango " + str(key) + "/" + pid + "/" + side)
			var bench: Variant = (p as Dictionary).get("bench_preload_nm", null)
			if not bench is Dictionary:
				errors.append("Sin precarga " + str(key) + "/" + pid)
			else:
				var s := float((bench as Dictionary).get("initial_simulation_seed", -1.0))
				if not is_finite(s) or s < 0.0:
					errors.append("Semilla inválida " + str(key) + "/" + pid)
		var default_id := str((entry as Dictionary).get("default_preset_id", ""))
		if default_id.is_empty() or not seen_ids.has(default_id):
			errors.append("default_preset_id inválido en " + str(key))
	if not errors.is_empty():
		return {"ok": false, "error": "; ".join(errors)}
	return {"ok": true, "profiles": profiles.size()}
