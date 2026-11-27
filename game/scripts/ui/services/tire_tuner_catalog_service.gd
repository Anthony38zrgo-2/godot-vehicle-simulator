class_name TireTunerCatalogService
extends RefCounted
## Pure domain/IO service for tire catalog loading, atomic saving, backups, history, and parameter schema.

const OFFICIAL_CATALOG_RES := RallyTireCompound.CATALOG_PATH
const BACKUP_DIR_RES := "res://data/tires/backups"
const HISTORY_INDEX_RES := "res://data/tires/backups/tire_tuning_history.json"
const MAX_HISTORY_ENTRIES := 100

const SURFACES := [
	{"key": "Gravel", "label": "GRAVA (Gravel)"},
	{"key": "Dirt", "label": "TIERRA (Dirt)"},
	{"key": "Road", "label": "ASFALTO (Road)"},
	{"key": "Sand", "label": "ARENA (Sand)"},
	{"key": "Grass", "label": "HIERBA (Grass)"},
	{"key": "Curb", "label": "PIANO / BORDE (Curb)"},
]


static func resolve_read_path(res_path: String) -> String:
	var global := ProjectSettings.globalize_path(res_path)
	if not global.is_empty() and FileAccess.file_exists(global):
		return global
	return res_path


static func resolve_write_path(res_path: String) -> String:
	var global := ProjectSettings.globalize_path(res_path)
	return global if not global.is_empty() else res_path


static func read_json_dict(res_path: String) -> Dictionary:
	var path := resolve_read_path(res_path)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (parsed as Dictionary) if parsed is Dictionary else {}


static func write_json_dict(res_path: String, doc: Dictionary) -> bool:
	var write_path := resolve_write_path(res_path)
	var parent_dir := write_path.get_base_dir()
	if not parent_dir.is_empty():
		var dir_err := DirAccess.make_dir_recursive_absolute(parent_dir)
		if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
			return false
	var serialized := JSON.stringify(doc, "  ", false, true) + "\n"
	var check: Variant = JSON.parse_string(serialized)
	if not check is Dictionary:
		return false
	var temp_path := write_path + ".%d-%d.tmp" % [OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	var written := file.store_string(serialized)
	file.close()
	if written and DirAccess.rename_absolute(temp_path, write_path) == OK:
		return true
	DirAccess.remove_absolute(temp_path)
	return false


static func load_history_index() -> Array:
	var doc := read_json_dict(HISTORY_INDEX_RES)
	var entries: Variant = doc.get("entries", [])
	return (entries as Array).duplicate(true) if entries is Array else []


static func save_history_index(entries: Array) -> bool:
	return write_json_dict(HISTORY_INDEX_RES, {"format_version": 1, "entries": entries})


static func ensure_initial_baseline_backup(current_catalog: Dictionary, compound_id: String) -> void:
	if not load_history_index().is_empty():
		return
	create_backup_snapshot(current_catalog, "Baseline inicial", "Copia automática inicial previa a ediciones", compound_id)


static func create_backup_snapshot(catalog: Dictionary, label_text: String, changes_summary: String, compound_id: String) -> Dictionary:
	var dt := Time.get_datetime_dict_from_system()
	var ms := Time.get_ticks_msec() % 1000
	var stamp_human := "%04d-%02d-%02d %02d:%02d:%02d" % [
		int(dt.get("year", 2026)), int(dt.get("month", 1)), int(dt.get("day", 1)),
		int(dt.get("hour", 0)), int(dt.get("minute", 0)), int(dt.get("second", 0)),
	]
	var stamp_file := "%04d-%02d-%02d_%02d-%02d-%02d_%03d" % [
		int(dt.get("year", 2026)), int(dt.get("month", 1)), int(dt.get("day", 1)),
		int(dt.get("hour", 0)), int(dt.get("minute", 0)), int(dt.get("second", 0)), ms,
	]
	var filename := "rally_compounds_%s.json" % stamp_file
	var backup_res := BACKUP_DIR_RES.path_join(filename)
	if not write_json_dict(backup_res, catalog):
		return {"ok": false, "error": "No se pudo escribir el archivo de backup en %s" % backup_res}

	var entries := load_history_index()
	var entry := {
		"id": stamp_file,
		"timestamp": stamp_human,
		"label": label_text,
		"compound_id": compound_id,
		"backup_file": filename,
		"changes_summary": changes_summary,
	}
	entries.push_front(entry)
	if entries.size() > MAX_HISTORY_ENTRIES:
		entries.resize(MAX_HISTORY_ENTRIES)
	save_history_index(entries)
	return {"ok": true, "entry": entry}


static func format_float(v: float) -> String:
	if not is_finite(v):
		return "0"
	if v == 0.0:
		return "0"
	var text := "%.10f" % v
	if text.contains("."):
		while text.ends_with("0"):
			text = text.substr(0, text.length() - 1)
		if text.ends_with("."):
			text = text.substr(0, text.length() - 1)
	return text if text != "-0" else "0"


static func build_diff_summary(specs: Array[Dictionary], old_values: Dictionary, new_values: Dictionary) -> String:
	var diffs: Array[String] = []
	for axle in ["front", "rear"]:
		var prefix := "Del" if axle == "front" else "Tras"
		var old_map: Dictionary = old_values.get(axle, {})
		var new_map: Dictionary = new_values.get(axle, {})
		for spec in specs:
			if str(spec.get("kind", "")) != "param":
				continue
			var id := str(spec["id"])
			var a := float(old_map.get(id, 0.0))
			var b := float(new_map.get(id, a))
			if absf(a - b) > 1e-9:
				diffs.append("%s %s: %s→%s" % [prefix, str(spec["key"]), format_float(a), format_float(b)])
	if diffs.is_empty():
		return "Sin cambios en parámetros de tabla"
	if diffs.size() <= 4:
		return "; ".join(diffs)
	return "%s (+%d más)" % ["; ".join(diffs.slice(0, 4)), diffs.size() - 4]


static func apply_values_to_catalog(catalog: Dictionary, changes: Dictionary, routes: Dictionary) -> Dictionary:
	var updated := catalog.duplicate(true)
	for axle: String in changes:
		for id: String in changes[axle]:
			var route: Dictionary = routes[axle][id]
			var path: Array = route["path"]
			var target := updated
			for key in path.slice(0, -1):
				if not target.has(key):
					target[key] = {}
				target = target[key]
			target[path[-1]] = float(changes[axle][id]) / float(route["factor"])
	return updated


static func _param(
	id: String, key: String, desc: String, source: String, field: String,
	min_v: float, max_v: float, default_v: float, strict_positive: bool = false, surface_name: String = "",
) -> Dictionary:
	return {
		"kind": "param",
		"id": id,
		"key": key,
		"description": desc,
		"source": source,
		"field": field,
		"min": min_v,
		"max": max_v,
		"default": default_v,
		"strict_positive": strict_positive,
		"surface": surface_name,
	}


static func build_parameter_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = [
		{"kind": "section", "title": "CURVA DE AGARRE Y DESLIZAMIENTO (force_model)"},
		_param("fm.lateral_peak_slip_angle_rad", "Referencia lateral (rad)", "Pendiente inicial en curva.", "force_model", "lateral_peak_slip_angle_rad", 0.02, 1.2, 0.18),
		_param("fm.lateral_slide_mu_ratio", "Agarre residual lateral", "Fracción de agarre en derrape.", "force_model", "lateral_slide_mu_ratio", 0.0, 1.0, 0.92),
		_param("fm.longitudinal_peak_slip_ratio", "Referencia longitudinal", "Pendiente en frenada y tracción.", "force_model", "longitudinal_peak_slip_ratio", 0.02, 1.0, 0.2),
		_param("fm.longitudinal_slide_mu_ratio", "Agarre residual longitudinal", "Agarre al patinar o bloquear.", "force_model", "longitudinal_slide_mu_ratio", 0.0, 1.0, 0.91),
		_param("fm.falloff_sharpness", "falloff_sharpness", "Brusquedad de pérdida de agarre tras el pico; menor = transición más suave y controlable.", "force_model", "falloff_sharpness", 0.2, 8.0, 1.2),
		_param("fm.combined_lateral_peak_migration", "combined_lateral_peak_migration", "Migración del pico lateral al frenar o acelerar en curva; ayuda en trail-braking.", "force_model", "combined_lateral_peak_migration", 0.0, 0.65, 0.0),
		_param("fm.combined_longitudinal_peak_migration", "combined_longitudinal_peak_migration", "Migración del pico longitudinal al girar; evita corte brusco al dar gas doblando.", "force_model", "combined_longitudinal_peak_migration", 0.0, 0.65, 0.0),
		_param("fm.peak_load_sensitivity", "peak_load_sensitivity", "Desplazamiento del pico según carga vertical; modula cambios por transferencia de peso.", "force_model", "peak_load_sensitivity", -0.5, 0.5, 0.0),

		{"kind": "section", "title": "TRANSITORIOS, RELAJACIÓN Y HUELLA"},
		_param("fm.slip_loss_tau_s", "slip_loss_tau_s", "Tiempo (s) en soltar relajación al entrar en derrape; menor = giro más vivo al romper agarre.", "force_model", "slip_loss_tau_s", 0.001, 2.0, 0.08),
		_param("fm.slip_recovery_tau_s", "slip_recovery_tau_s", "Tiempo (s) en recuperar agarre al salir del derrape; menor = cambia de apoyo en S más rápido.", "force_model", "slip_recovery_tau_s", 0.001, 2.0, 0.09),
		_param("fm.contact_ramp_tau_s", "contact_ramp_tau_s", "Constante de mezcla en segundos. Al aterrizar, la subida usa un máximo de 20 ms.", "force_model", "contact_ramp_tau_s", 0.0, 1.0, 0.0),
		_param("fm.min_relaxation_tau_s", "min_relaxation_tau_s", "Retardo mínimo (s) de deformación del flanco; menor = respuesta más directa al volante.", "force_model", "min_relaxation_tau_s", 0.0, 0.5, 0.0),
		_param("fm.relaxation_recovery_scale", "relaxation_recovery_scale", "Escala de retorno de relajación al estabilizar; <1 agiliza recuperación entre curvas.", "force_model", "relaxation_recovery_scale", 0.1, 3.0, 0.9),
		_param("ax.relaxation_length_scale", "Longitud de relajación (m)", "Distancia de respuesta al slip.", "axle_scalar", "relaxation_length_scale", 0.2, 5.0, 1.25),
		_param("ax.surface_transition_tau_s", "surface_transition_tau_s", "Suavizado (s) al cambiar entre superficies; menor = adaptación más instantánea.", "axle_scalar", "surface_transition_tau_s", 0.0, 2.0, 0.09),
		_param("ax.contact_patch_load_gain", "contact_patch_load_gain", "Crecimiento de la huella dinámica con el peso vertical; aporta apoyo bajo carga.", "axle_scalar", "contact_patch_load_gain", 0.0, 1.0, 0.12),
		_param("ax.contact_patch_deflection_gain", "contact_patch_deflection_gain", "Crecimiento de huella según la compresión de carcasa en apoyos y aterrizajes.", "axle_scalar", "contact_patch_deflection_gain", 0.0, 1.0, 0.2),

		{"kind": "section", "title": "SENSIBILIDAD A CARGA Y PRESIÓN"},
		_param("ax.load_sensitivity_per_newton", "Sensibilidad a carga (1/MN)", "Caída de μ con carga.", "axle_scalar", "load_sensitivity_per_newton", 0.0, 0.001, 1.5e-5),
		_param("pm.response_sensitivity", "pressure_mechanics.response_sensitivity", "Influencia de la presión de aire sobre la rapidez de respuesta y relajación.", "pressure_mechanics", "response_sensitivity", -3.0, 3.0, -0.15),
		_param("pm.rolling_resistance_sensitivity", "pressure_mechanics.rolling_resistance_sensitivity", "Variación de la resistencia a la rodadura según la presión en caliente.", "pressure_mechanics", "rolling_resistance_sensitivity", -3.0, 3.0, -0.3),

		{"kind": "section", "title": "CARCASA RADIAL (radial_model)"},
		_param("rad.carcass_stiffness_n_m", "radial_model.carcass_stiffness_n_m", "Rigidez base de carcasa (N/m); mayor = flanco firme y directo, menor = más absorción.", "radial_model", "carcass_stiffness_n_m", 1000.0, 500000.0, 30000.0, true),
		_param("rad.pressure_stiffness_n_m_per_kpa", "radial_model.pressure_stiffness_n_m_per_kpa", "Rigidez extra por kPa de presión (N/m/kPa); controla cuánto endurece al inflar.", "radial_model", "pressure_stiffness_n_m_per_kpa", 1.0, 10000.0, 666.6667, true),
		_param("rad.damping_ratio", "radial_model.damping_ratio", "Amortiguamiento vertical de carcasa; mayor = menos rebote en rizado y baches.", "radial_model", "damping_ratio", TireRadialModel.MIN_DAMPING_RATIO, 2.0, TireRadialModel.MIN_DAMPING_RATIO),
		_param("rad.damping_contact_ramp_m", "radial_model.damping_contact_ramp_m", "Rampa inicial (m) de contacto para suavizar impactos verticales tras un salto.", "radial_model", "damping_contact_ramp_m", TireRadialModel.MIN_DAMPING_RAMP_M, 0.1, 0.015, true),
		_param("rad.rim_stop_start_sidewall_fraction", "radial_model.rim_stop_start_sidewall_fraction", "Fracción comprimida del flanco donde entra el tope de llanta (entre 0 y 1).", "radial_model", "rim_stop_start_sidewall_fraction", 0.4, 0.95, 0.75),
		_param("rad.rim_stop_stiffness_n_m", "radial_model.rim_stop_stiffness_n_m", "Rigidez del tope metálico de llanta (N/m) en compresiones extremas.", "radial_model", "rim_stop_stiffness_n_m", 1000.0, 2000000.0, 300000.0, true),
	]

	for s_info in SURFACES:
		var s_key := str(s_info["key"])
		var s_label := str(s_info["label"])
		specs.append({"kind": "section", "title": "SUPERFICIE · " + s_label})
		specs.append(_param("surf.%s.friction" % s_key, "surfaces.%s.friction" % s_key, "Agarre global del eje sobre %s. Sube para más grip total o baja para soltar antes." % s_key, "surface", "friction", 0.05, 3.0, 1.0, false, s_key))
		specs.append(_param("surf.%s.stiffness" % s_key, "surfaces.%s.stiffness" % s_key, "Mordida inicial a poco volante sobre %s. Mayor = respuesta inicial más incisiva." % s_key, "surface", "stiffness", 0.05, 10.0, 1.0, false, s_key))
		specs.append(_param("surf.%s.longitudinal_grip_ratio" % s_key, "surfaces.%s.longitudinal_grip_ratio" % s_key, "Balance tracción/freno frente a giro en %s (>1 prioriza acelerar/frenar; <1 prioriza lateral)." % s_key, "surface", "longitudinal_grip_ratio", 0.1, 1.5, 1.0, false, s_key))
		specs.append(_param("surf.%s.lateral_grip_assist" % s_key, "surfaces.%s.lateral_grip_assist" % s_key, "Asistencia extra de apoyo lateral en %s para estabilizar derrapes en suelto." % s_key, "surface", "lateral_grip_assist", -0.5, 1.0, 0.0, false, s_key))
		specs.append(_param("surf.%s.rolling_resistance" % s_key, "surfaces.%s.rolling_resistance" % s_key, "Resistencia al avance y hundimiento en %s; mayor frena más el coche al rodar." % s_key, "surface", "rolling_resistance", 0.0, 20.0, 1.0, false, s_key))

	return specs


static func build_filter_specs(all_specs: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var groups := {
		"CURVA PURA": [
			"fm.lateral_peak_slip_angle_rad", "fm.longitudinal_peak_slip_ratio",
			"fm.lateral_slide_mu_ratio", "fm.longitudinal_slide_mu_ratio",
		],
		"CARGA Y RESPUESTA": ["ax.load_sensitivity_per_newton", "ax.relaxation_length_scale"],
	}
	var by_id := {}
	for spec in all_specs:
		if spec["kind"] == "param":
			by_id[spec["id"]] = spec
	for title: String in groups:
		out.append({"kind": "section", "title": title})
		for id: String in groups[title]:
			out.append(by_id[id])
	return out
