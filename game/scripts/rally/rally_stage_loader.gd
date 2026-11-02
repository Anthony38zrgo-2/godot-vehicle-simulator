class_name RallyStageLoader
extends RefCounted
## Resuelve manifiesto, visuales, colisión, ruta, puertas, pacenotes y
## respaldo CPU por track_id (p. ej. "russia_stage2").
## Valida dependencias y hashes conocidos; nunca sustituye en silencio por Stage 1.

const RALLY_ROOT := "res://assets/rally"
const ROUTE_ROOT := "res://data/rally"
const PACENOTES_ROOT := "res://data/rally/pacenotes"
const STAGE_CONFIG_ROOT := "res://data/competition/stages"

var error: String = ""
var last_diagnostics: Dictionary = {}

static func track_id_for_index(stage_index: int) -> String:
	return "russia_stage%d" % stage_index

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
	# Orden exacto 1..N sin clasificación alfabética ("stage10" nunca antes que "stage2").
	var expected: Array = []
	for i in range(1, track_ids.size() + 1):
		expected.append("russia_stage%d" % i)
	if track_ids != expected:
		report["ok"] = false
		(report["errors"] as Array).append("Secuencia distinta de 1..%d sin ordenar alfabéticamente" % track_ids.size())
	return report

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
