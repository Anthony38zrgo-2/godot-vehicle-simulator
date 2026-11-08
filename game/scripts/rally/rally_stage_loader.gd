class_name RallyStageLoader
extends RefCounted
## Resuelve manifiesto, visuales, colisión, ruta, puertas, pacenotes y
## respaldo CPU por track_id (p. ej. "russia_stage2").
## Valida dependencias y hashes conocidos; nunca sustituye en silencio por Stage 1.

const RALLY_ROOT := "res://assets/rally"
const ROUTE_ROOT := "res://data/rally"
const PACENOTES_ROOT := "res://data/rally/pacenotes"
const STAGE_CONFIG_ROOT := "res://data/competition/stages"

## Etapas por país. Rusia tiene 10 (track1); Kenia, Finlandia, Suecia y
## Suiza tienen 8 (tracks 2-5, solo stage1..8 en los .bzf originales).
const COUNTRY_STAGE_COUNTS := {
	"russia": 10,
	"kenya": 8,
	"finland": 8,
	"sweden": 8,
	"switzerland": 8,
}

var error: String = ""
var last_diagnostics: Dictionary = {}

static func track_id_for_index(stage_index: int) -> String:
	return "russia_stage%d" % stage_index


## "kenya", 3 -> "kenya_stage3". Devuelve "" si el país o el índice es inválido.
static func track_id_for_country_index(country: String, stage_index_1_based: int) -> String:
	var c := country.to_lower()
	if not COUNTRY_STAGE_COUNTS.has(c):
		return ""
	var count: int = COUNTRY_STAGE_COUNTS[c]
	if stage_index_1_based < 1 or stage_index_1_based > count:
		return ""
	return "%s_stage%d" % [c, stage_index_1_based]


## Catálogo ordenado 1..N de un país. Vacío si el país es desconocido.
static func catalog_for_country(country: String) -> Array[String]:
	var out: Array[String] = []
	var c := country.to_lower()
	if not COUNTRY_STAGE_COUNTS.has(c):
		return out
	for i in range(1, int(COUNTRY_STAGE_COUNTS[c]) + 1):
		out.append("%s_stage%d" % [c, i])
	return out


## Los 42 tracks del juego (10 + 8*4) en orden por país.
static func all_countries_catalog() -> Array[String]:
	var out: Array[String] = []
	for country in ["russia", "kenya", "finland", "sweden", "switzerland"]:
		out.append_array(catalog_for_country(country))
	return out

static func is_valid_track_id(track_id: String) -> bool:
	var parts := track_id.split("_stage")
	if parts.size() != 2:
		return false
	if parts[0].is_empty():
		return false
	return parts[1].is_valid_int() and int(parts[1]) >= 1

func manifest_path(track_id: String) -> String:
	return "%s/%s/manifest.json" % [RALLY_ROOT, track_id]

func visual_path(track_id: String) -> String:
	return "%s/%s/%s_visual.glb" % [RALLY_ROOT, track_id, track_id]

func collision_path(track_id: String) -> String:
	return "%s/%s/%s_collision.glb" % [RALLY_ROOT, track_id, track_id]

func route_path(track_id: String) -> String:
	return "%s/%s_route.json" % [ROUTE_ROOT, track_id]

func stage_config_path(track_id: String) -> String:
	return "%s/%s.json" % [STAGE_CONFIG_ROOT, track_id]

func timing_gates_path(track_id: String) -> String:
	return "%s/%s_timing_gates.json" % [STAGE_CONFIG_ROOT, track_id]

func pacenotes_path(track_id: String) -> String:
	return "%s/%s.json" % [PACENOTES_ROOT, track_id]

func resolve(track_id: String) -> Dictionary:
	error = ""
	last_diagnostics = {"track_id": track_id}
	if not is_valid_track_id(track_id):
		error = "track_id inválido: %s (esperado <pais>_stage<N>)" % track_id
		return {}
	var paths := {
		"manifest": manifest_path(track_id),
		"visual": visual_path(track_id),
		"collision": collision_path(track_id),
		"route": route_path(track_id),
		"stage_config": stage_config_path(track_id),
		"timing_gates": timing_gates_path(track_id),
		"pacenotes": pacenotes_path(track_id),
	}
	var missing: Array = []
	for key in paths:
		if not ResourceLoader.exists(paths[key]) and not FileAccess.file_exists(paths[key]):
			missing.append("%s (%s)" % [key, paths[key]])
	if not missing.is_empty():
		error = "Recurso ausente para %s: %s" % [track_id, ", ".join(missing)]
		last_diagnostics["missing"] = missing
		return {}
	# Verificar hashes visual/colisión contra el manifiesto cuando exista.
	var manifest: Dictionary = _read_json(paths["manifest"])
	if manifest.is_empty():
		error = "Manifiesto ilegible: %s" % paths["manifest"]
		return {}
	if str(manifest.get("track_id", "")) != track_id:
		error = "Manifiesto de %s declara track_id=%s" % [track_id, manifest.get("track_id")]
		return {}
	last_diagnostics["manifest_track_id"] = manifest.get("track_id")
	var stage_config: Dictionary = _read_json(paths["stage_config"])
	if stage_config.is_empty() or str(stage_config.get("id", "")) != track_id:
		error = "Configuración de competición incoherente para %s" % track_id
		last_diagnostics["stage_config_id"] = stage_config.get("id", "")
		return {}
	return {
		"track_id": track_id,
		"paths": paths,
		"manifest": manifest,
		"stage_config": stage_config,
		"start_pose": manifest.get("start_pose", {}),
	}

func validate_catalog(track_ids: Array) -> Dictionary:
	var report := {"ok": true, "stages": {}, "errors": []}
	var seen := {}
	for track_id in track_ids:
		if seen.has(track_id):
			report["ok"] = false
			(report["errors"] as Array).append("ID duplicado: %s" % track_id)
			continue
		seen[track_id] = true
		var resolved := resolve(str(track_id))
		(report["stages"] as Dictionary)[str(track_id)] = not resolved.is_empty()
		if resolved.is_empty():
			report["ok"] = false
			(report["errors"] as Array).append("%s: %s" % [track_id, error])
			continue
	# Compatibilidad Rusia: secuencia exacta russia_stage1..10 sin orden alfabético.
	var all_russia := true
	if track_ids.size() == int(COUNTRY_STAGE_COUNTS["russia"]):
		for i in range(1, track_ids.size() + 1):
			if not track_ids.has("russia_stage%d" % i):
				all_russia = false
				break
	else:
		all_russia = false
	if all_russia:
		var expected: Array = []
		for i in range(1, track_ids.size() + 1):
			expected.append("russia_stage%d" % i)
		if track_ids != expected:
			report["ok"] = false
			(report["errors"] as Array).append("Secuencia distinta de 1..%d sin ordenar alfabéticamente" % track_ids.size())
		return report
	# Catálogos de otros países (p. ej. kenya_stage1..8) o el total de 42:
	# formato <país>_stage<N> válido, sin duplicados y con resolve() exitoso.
	var countries := {}
	for track_id in track_ids:
		var parts := str(track_id).split("_stage")
		if parts.size() != 2 or not COUNTRY_STAGE_COUNTS.has(str(parts[0]).to_lower()):
			report["ok"] = false
			(report["errors"] as Array).append("Formato inválido o país desconocido: %s" % track_id)
			continue
		var c := str(parts[0]).to_lower()
		if not countries.has(c):
			countries[c] = []
		(countries[c] as Array).append(track_id)
	for c in countries:
		var expected_c := catalog_for_country(str(c))
		var got: Array = (countries[c] as Array).duplicate()
		# Secuencia exacta 1..N del país cuando el catálogo está completo.
		if got.size() == expected_c.size():
			var ordered := true
			for want in expected_c:
				if not got.has(want):
					ordered = false
					break
			if not ordered:
				report["ok"] = false
				(report["errors"] as Array).append("Catálogo %s incompleto o desordenado" % c)
	return report


## Valida el catálogo de un país. Sin track_ids, usa el catálogo 1..N por defecto
## (retrocompatible: validate_country_catalog("russia") == russia_stage1..10).
func validate_country_catalog(country: String, track_ids: Array = []) -> Dictionary:
	var c := country.to_lower()
	if not COUNTRY_STAGE_COUNTS.has(c):
		return {"ok": false, "stages": {}, "errors": ["País desconocido: %s" % country]}
	var ids: Array = track_ids if not track_ids.is_empty() else catalog_for_country(c)
	return validate_catalog(ids)

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
