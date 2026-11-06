class_name RallyEventManager
extends RefCounted
## Estado del evento, selección de especial, resultados oficiales,
## transición, clasificación y cierre. rally_competition.gd sigue siendo
## el simulador de la especial actual; aquí viven los acumulados oficiales.

const EVENT_PATH := "res://data/competition/events/russia_rally.json"
const SAVE_PATH := "user://rally_event_v2.json"
const LEGACY_SAVE_PATH := "user://rally_competition_v1.json"
const StageLoaderScript := preload("res://scripts/rally/rally_stage_loader.gd")
const PointsScript := preload("res://scripts/rally/rally_points_rules.gd")
const SchedulerScript := preload("res://scripts/rally/rally_weather_scheduler.gd")
const CompoundScript := preload("res://scripts/rally/rally_tire_compound.gd")

var error: String = ""
var event_doc: Dictionary = {}
var stage_order: Array = []
var cursor: int = 0
var official: Dictionary = {}
var points_ledger: Dictionary = {}
var closed_keys: Dictionary = {}
var definitive_withdrawals: Dictionary = {}
var status: String = "idle"
var seed_value: int = 1974
var difficulty: int = 1
var ambient_rate: float = 1.0
var single_day: bool = false
var custom_starts: Dictionary = {}
var itinerary: Array = []
var sim = null
var loader = StageLoaderScript.new()
var weather_schedule: Array = []
var climate_seed: int = 0
var weather_generator_version: int = 1
var weather_rules_hash: String = ""
var route_hashes: Dictionary = {}
var surface_continuity: Dictionary = {}
var confirmed_compound_id: String = "gravel_normal"
var draft_compound_id: String = "gravel_normal"
var setup_values: Dictionary = {}
var mounted_tire_condition: Array = []
var tire_inventory_state: Dictionary = {}
var vehicle_damage_state: Dictionary = {}
var service_penalties_ms: Dictionary = {}
var setup_confirmed: bool = false
var windows_attended: Dictionary = {}
var pending_window: Dictionary = {}
var stage_surface_states: Dictionary = {}
var rival_compounds: Dictionary = {}
var compound_catalog: Dictionary = {}

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		error = "No existe " + path
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		error = "JSON inválido: " + path
		return {}
	return parsed

func load_event() -> bool:
	error = ""
	event_doc = _read_json(EVENT_PATH)
	if event_doc.is_empty():
		return false
	stage_order = (event_doc.get("stages_explicit_order", []) as Array).duplicate()
	if stage_order.size() != 10:
		error = "El evento debe listar exactamente diez especiales"
		return false
	return true

func begin_event(choices: Dictionary = {}) -> bool:
	if not load_event():
		return false
	var start_stage_id := str(choices.get("start_stage_id", choices.get("stage_id", "")))
	if not start_stage_id.is_empty():
		var start_index := stage_order.find(start_stage_id)
		if start_index < 0:
			error = "Especial inicial desconocida en el evento: " + start_stage_id
			return false
		if start_index > 0:
			stage_order = stage_order.slice(start_index)
	seed_value = int(choices.get("seed", 0))
	if seed_value <= 0:
		var random := RandomNumberGenerator.new()
		random.randomize()
		seed_value = random.randi_range(1, 2147483647)
	difficulty = int(choices.get("difficulty", 1))
	ambient_rate = float(choices.get("ambient_rate", 1.0))
	single_day = bool(choices.get("single_day", false))
	cursor = 0
	official.clear()
	points_ledger.clear()
	closed_keys.clear()
	definitive_withdrawals.clear()
	weather_schedule.clear()
	stage_surface_states.clear()
	rival_compounds.clear()
	windows_attended.clear()
	pending_window = {}
	setup_confirmed = false
	setup_values = {}
	mounted_tire_condition.clear()
	tire_inventory_state.clear()
	vehicle_damage_state.clear()
	service_penalties_ms.clear()
	# Compuesto inicial: borrador hasta Aceptar (no se consume ni se cronometra antes).
	var requested_compound := str(choices.get("compound_id", choices.get("compound", "")))
	var tire_rules: Dictionary = event_doc.get("tire_rules", {})
	var default_compound := str(tire_rules.get("default_compound_id", "gravel_normal"))
	draft_compound_id = CompoundScript.validated_id(requested_compound) if requested_compound != "" else default_compound
	confirmed_compound_id = default_compound
	compound_catalog = CompoundScript.load_catalog()
	status = "running"
	_build_itinerary(choices)
	# Generar el itinerario climático de todo el rally una sola vez tras Aceptar.
	if not _generate_weather_schedule():
		return false
	# La selección es borrador hasta confirmación explícita del reglaje.
	if bool(choices.get("setup_accepted", false)):
		confirm_setup(draft_compound_id, choices.get("setup_values", {}))
	else:
		# Ventana inicial pendiente (antes de Stage 1, pestaña Neumáticos).
		_update_pending_window()
	var CompetitionScript := load("res://scripts/rally/rally_competition.gd")
	sim = CompetitionScript.new()
	sim.save_path = ""
	var first_config: String = loader.stage_config_path(str(stage_order[0]))
	if not sim.configure(first_config, seed_value):
		error = "No se pudo configurar la primera especial: " + sim.error
		return false
	sim.leg = 1
	_register_participants()
	_assign_rival_compounds()
	if sim.has_method("set_weather_context"):
		sim.set_weather_context(weather_entry_for(current_stage_id()), rival_compounds.get(current_stage_id(), {}))
	# La vista previa del menú no debe llamar a un inicio que escriba el guardado oficial.
	if not bool(choices.get("preview", false)):
		save()
	return true

func current_stage_id() -> String:
	if stage_order.is_empty() or cursor < 0 or cursor >= stage_order.size():
		return ""
	return str(stage_order[cursor])

func is_last_stage() -> bool:
	return cursor == stage_order.size() - 1

func schedule_for(stage_id: String) -> Dictionary:
	for entry in itinerary:
		if str(entry.get("stage_id", "")) == stage_id:
			return entry
	return {}


func weather_entry_for(stage_id: String) -> Dictionary:
	for entry in weather_schedule:
		if str((entry as Dictionary).get("stage_id", "")) == stage_id:
			return (entry as Dictionary).duplicate(true)
	return {}


func forecast_for_half(from_stage_index: int, count: int = 5) -> Dictionary:
	return SchedulerScript.forecast_for_half(weather_schedule, from_stage_index, count)


func setup_windows() -> Array:
	return (event_doc.get("setup_windows", []) as Array).duplicate(true)


func _update_pending_window() -> void:
	pending_window = {}
	var current := current_stage_id()
	var prev_id := "" if cursor <= 0 else str(stage_order[cursor - 1])
	if cursor == 0 and not windows_attended.has("initial"):
		pending_window = {
			"before_stage_id": current,
			"initial_tab": "tires",
			"confirmation_required": true,
			"window_key": "initial"
		}
		return
	for w in setup_windows():
		var wd: Dictionary = w
		if wd.has("after_stage_id") and wd.has("before_stage_id"):
			if str(wd.get("after_stage_id", "")) == prev_id and str(wd.get("before_stage_id", "")) == current:
				var key := "service:%s>%s" % [prev_id, current]
				if not windows_attended.has(key):
					pending_window = wd.duplicate(true)
					pending_window["window_key"] = key
					return


func get_pending_window() -> Dictionary:
	return pending_window.duplicate(true)


func is_compound_change_allowed() -> bool:
	return not pending_window.is_empty()


func confirm_setup(compound_id: String, values: Dictionary = {}) -> Dictionary:
	# Idempotente: doble clic no duplica cambios ni servicio.
	if setup_confirmed and str(compound_id) == confirmed_compound_id and (values.is_empty() or values == setup_values):
		return {"ok": true, "already": true, "compound": confirmed_compound_id}
	var tire_rules: Dictionary = event_doc.get("tire_rules", {})
	var allowed: Array = tire_rules.get("allowed_compound_ids", ["gravel_normal", "gravel_wet"])
	if str(compound_id) not in allowed:
		error = "Compuesto no permitido: " + str(compound_id)
		return {"ok": false, "error": error}
	# El cambio de compuesto solo está habilitado en ventanas JSON; fuera de
	# ventana se bloquea (el reglaje general sigue sus propias restricciones).
	if not pending_window.is_empty():
		pass
	elif str(compound_id) != confirmed_compound_id and not is_compound_change_allowed():
		error = "Cambio de compuesto bloqueado fuera de ventana de servicio"
		return {"ok": false, "error": error}
	draft_compound_id = str(compound_id)
	confirmed_compound_id = str(compound_id)
	if not values.is_empty():
		setup_values = (values as Dictionary).duplicate(true)
	setup_confirmed = true
	if pending_window.has("window_key"):
		windows_attended[str(pending_window.get("window_key", ""))] = true
		pending_window = {}
	save()
	return {"ok": true, "compound": confirmed_compound_id}


func _generate_weather_schedule() -> bool:
	var sched := SchedulerScript.new()
	var route_paths := {}
	for sid in stage_order:
		route_paths[str(sid)] = "res://data/rally/%s_route.json" % str(sid)
	var result := sched.generate_event_schedule(event_doc, stage_order, itinerary, seed_value, route_paths)
	if not bool(result.get("ok", false)):
		error = "Clima incompatible: " + str(result.get("error", "sin detalle"))
		return false
	var validation := SchedulerScript.validate_schedule(result.get("schedule", []), stage_order, event_doc.get("weather_rules", {}))
	if not bool(validation.get("ok", false)):
		error = "Cronograma climático inválido: " + str(validation.get("error", ""))
		return false
	weather_schedule = result.get("schedule", [])
	climate_seed = int(result.get("climate_seed", 0))
	weather_generator_version = int(result.get("generator_version", 1))
	route_hashes = result.get("route_hashes", {})
	surface_continuity = result.get("surface_continuity", {})
	weather_rules_hash = str(result.get("rules_hash", ""))
	return true


func _assign_rival_compounds() -> void:
	# Decisiones de compuesto coherentes por sector con otra corriente de
	# semilla (independiente de la del jugador y de la IA deportiva).
	rival_compounds.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = SchedulerScript.rival_seed(seed_value)
	for entry in weather_schedule:
		var sid := str((entry as Dictionary).get("stage_id", ""))
		rival_compounds[sid] = {}
		var wet_zones := 0
		for z in ((entry as Dictionary).get("zones", []) as Array):
			if float(((z as Dictionary).get("climate", {}) as Dictionary).get("precipitation_mm_h", 0.0)) >= 2.0:
				wet_zones += 1
		for row in sim.rows if sim != null else []:
			var pid := str((row as Dictionary).get("id", ""))
			# Sin multiplicar pérdidas ya incorporadas en tiempos CPU mojados:
			# el compuesto rival solo matiza dentro del factor ya calibrado.
			var pick_wet := wet_zones >= 2 or (wet_zones >= 1 and rng.randf() < 0.4)
			if rival_compounds.get(sid, {}) is Dictionary:
				(rival_compounds[sid] as Dictionary)[pid] = "gravel_wet" if pick_wet else "gravel_normal"
			else:
				rival_compounds[sid] = {pid: ("gravel_wet" if pick_wet else "gravel_normal")}
		# El jugador usa el confirmado (no se sortea).
		if rival_compounds.get(sid, {}) is Dictionary:
			(rival_compounds[sid] as Dictionary)["player"] = confirmed_compound_id


func rival_compound_for(pid: String, stage_id: String) -> String:
	var m: Dictionary = rival_compounds.get(stage_id, {})
	return str(m.get(pid, confirmed_compound_id))


func save_stage_surface(stage_id: String, snapshot: Dictionary) -> void:
	stage_surface_states[stage_id] = snapshot
	save()


func stage_surface_snapshot(stage_id: String) -> Dictionary:
	return (stage_surface_states.get(stage_id, {}) as Dictionary).duplicate(true) if stage_surface_states.has(stage_id) else {}

func close_current_stage(player: Dictionary) -> Dictionary:
	# player: {measured_ms, penalty_ms, retired, definitive, elapsed_ms, provenance}
	# Idempotente por clave evento/participante/especial evitada con closed_keys por especial.
	error = ""
	var stage_id := current_stage_id()
	if stage_id.is_empty() or sim == null:
		error = "Sin especial activa"
		return {}
	if closed_keys.has("closed:" + stage_id):
		return {"already_closed": true, "stage_id": stage_id}
	var reference_total = sim.stage_reference_total_ms()
	player = player.duplicate(true)
	player["penalty_ms"] = int(player.get("penalty_ms", 0)) + int(service_penalties_ms.get(stage_id, 0))
	var rejoin_penalty: int = int(((event_doc.get("retirement_policy", {}) as Dictionary).get("rejoin_penalty_ms", 300000)))
	var readout: Dictionary = sim.readout()
	# Oficiales CPU bajo la misma política que el jugador.
	for row in readout.get("rows", []):
		if bool(row.get("player", false)):
			continue
		var pid := str(row.get("id", ""))
		if definitive_withdrawals.has(pid):
			_set_official(pid, stage_id, 0, 0, "definitive", false, false, "Retiro definitivo previo")
			continue
		if row.get("retired", false):
			var adj = reference_total + rejoin_penalty
			_set_official(pid, stage_id, adj, 0, "adjudicated", false, false, "CPU reenganche: referencia + 300s")
		else:
			var total_ms := int(row.get("stage_ms", 0))
			_set_official(pid, stage_id, total_ms, int(row.get("penalty_ms", 0)), "finished", true, true, "CPU finished")
	# Jugador.
	var pid_player := "player"
	if bool(player.get("definitive", false)):
		definitive_withdrawals[pid_player] = true
		_set_official(pid_player, stage_id, 0, int(player.get("penalty_ms", 0)), "definitive", false, false, str(player.get("reason", "Retiro definitivo")))
	elif bool(player.get("retired", false)):
		var elapsed_ms := int(player.get("elapsed_ms", player.get("measured_ms", 0)))
		var adj_p = maxi(elapsed_ms, reference_total) + rejoin_penalty
		_set_official(pid_player, stage_id, adj_p, int(player.get("penalty_ms", 0)), "adjudicated", false, false, str(player.get("reason", "Abandono")) + " | ref=" + str(reference_total))
	else:
		var total_p := int(player.get("measured_ms", 0)) + int(player.get("penalty_ms", 0))
		_set_official(pid_player, stage_id, total_p, int(player.get("penalty_ms", 0)), "finished", true, true, "finished")
	closed_keys["closed:" + stage_id] = true
	_award_points_if_closed()
	save()
	return {"stage_id": stage_id, "cursor": cursor, "is_last": is_last_stage()}

func advance() -> bool:
	# Cargar la siguiente configuración sin perder inscritos, semilla,
	# acumulados ni estado mecánico que deba conservarse.
	error = ""
	if status != "running":
		error = "Evento no en curso"
		return false
	if not closed_keys.has("closed:" + current_stage_id()):
		error = "Hay que cerrar la especial actual antes de avanzar"
		return false
	if is_last_stage():
		status = "finished"
		_award_points_if_closed()
		save()
		return true
	# CPU repairs follow the same two-stage service cadence as the player.
	if current_stage_id() in event_doc.get("service", {}).get("after_stage_ids", []):
		sim.apply_event_service()
	var carried = sim.rows.duplicate(true)
	cursor += 1
	var next_id := current_stage_id()
	var next_config: String = loader.stage_config_path(next_id)
	if not sim.reconfigure_for_event_stage(next_config, carried):
		error = "No se pudo cargar " + next_id + ": " + sim.error
		cursor -= 1
		return false
	sim.leg = cursor + 1
	sim.save_path = ""
	# El mismo calendario y reglas de compuesto para la CPU (otra semilla).
	if sim.has_method("set_weather_context"):
		sim.set_weather_context(weather_entry_for(next_id), rival_compounds.get(next_id, {}))
	# El servicio corresponde a las ventanas del itinerario, también tras un abandono.
	_update_pending_window()
	save()
	return true

func standings() -> Array:
	# Clasificación general entre elegibles (no definitivos).
	var rows: Array = []
	for pid in official:
		if definitive_withdrawals.has(pid):
			continue
		var entry: Dictionary = (official[pid] as Dictionary).duplicate(true)
		entry["id"] = pid
		rows.append(entry)
	return PointsScript.rank(rows, stage_order)

func sunday_standings() -> Array:
	var sunday_ids: Array = event_doc.get("sunday_stage_ids", ["russia_stage6", "russia_stage7", "russia_stage8", "russia_stage9", "russia_stage10"])
	if single_day and not bool(((event_doc.get("points_profiles", {}) as Dictionary).get("wrc_2026_v1", {}) as Dictionary).get("single_day_disables_sunday_bonus_unless_custom_grouping_marked_custom", true)):
		pass
	var rows: Array = []
	for pid in official:
		if definitive_withdrawals.has(pid):
			continue
		var entry: Dictionary = official[pid]
		var eligible := true
		var sunday_total := 0
		for sid in sunday_ids:
			var rec: Dictionary = ((entry.get("stages", {}) as Dictionary).get(sid, {}) as Dictionary)
			if rec.is_empty() or not bool(rec.get("counts_for_bonus", false)):
				eligible = false
				break
			sunday_total += int(rec.get("official_ms", 0))
		if eligible:
			rows.append({"id": pid, "name": entry.get("name", pid), "grand_total_ms": sunday_total, "stage_totals": _sunday_map(entry, sunday_ids)})
	var ordered = PointsScript.rank(rows, sunday_ids)
	return ordered

func power_results(power_stage_times: Dictionary) -> Array:
	# power_stage_times: pid -> ms válido (solo finished cuenta).
	var power_id := str(event_doc.get("power_stage_id", "russia_stage10"))
	var rows: Array = []
	for pid in power_stage_times:
		if definitive_withdrawals.has(pid):
			continue
		var entry: Dictionary = official.get(pid, {})
		var rec: Dictionary = ((entry.get("stages", {}) as Dictionary).get(power_id, {}) as Dictionary)
		if rec.is_empty() or not bool(rec.get("counts_for_bonus", false)):
			continue
		rows.append({"id": pid, "grand_total_ms": int(power_stage_times[pid]), "stage_totals": {power_id: int(power_stage_times[pid])}})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["grand_total_ms"]) < int(b["grand_total_ms"]))
	var position := 0
	for row in rows:
		position += 1
		row["position"] = position
	return rows

func final_points(power_stage_times: Dictionary) -> Dictionary:
	var result := {"general": {}, "sunday": {}, "power": {}, "total": {}, "winner": ""}
	var gen = standings()
	for row in gen:
		(result["general"] as Dictionary)[row["id"]] = PointsScript.general_points_for_position(int(row.get("position", 0)))
	var sun_disabled := single_day
	if not sun_disabled:
		for row in sunday_standings():
			(result["sunday"] as Dictionary)[row["id"]] = PointsScript.sunday_points_for_position(int(row.get("position", 0)))
	for row in power_results(power_stage_times):
		(result["power"] as Dictionary)[row["id"]] = PointsScript.power_points_for_position(int(row.get("position", 0)))
	var participants := {}
	for table in [(result["general"] as Dictionary), (result["sunday"] as Dictionary), (result["power"] as Dictionary)]:
		for pid in table:
			participants[pid] = true
	for pid in participants:
		(result["total"] as Dictionary)[pid] = int((result["general"] as Dictionary).get(pid, 0)) + int((result["sunday"] as Dictionary).get(pid, 0)) + int((result["power"] as Dictionary).get(pid, 0))
	if not gen.is_empty():
		result["winner"] = str(gen[0].get("id", ""))
	return result

func save() -> bool:
	var doc := {
		"version": 3,
		"event_id": event_doc.get("event_id", "russia_rally"),
		"rules_hash": _rules_hash(),
		"cursor": cursor,
		"status": status,
		"seed": seed_value,
		"difficulty": difficulty,
		"single_day": single_day,
		"itinerary": itinerary,
		"official": official,
		"points_ledger": points_ledger,
		"closed_keys": closed_keys.keys(),
		"definitive_withdrawals": definitive_withdrawals.keys(),
		"clock": {"rate": ambient_rate},
		"weather_schedule": weather_schedule,
		"climate_seed": climate_seed,
		"generator_version": weather_generator_version,
		"route_hashes": route_hashes,
		"surface_continuity": surface_continuity,
		"confirmed_compound": confirmed_compound_id,
		"draft_compound": draft_compound_id,
		"setup_values": setup_values,
		"mounted_tire_condition": mounted_tire_condition,
		"tire_inventory_state": tire_inventory_state,
		"vehicle_damage_state": vehicle_damage_state,
		"service_penalties_ms": service_penalties_ms,
		"setup_confirmed": setup_confirmed,
		"windows_attended": windows_attended,
		"pending_window": pending_window,
		"stage_surface_states": stage_surface_states,
		"rival_compounds": rival_compounds,
	}
	var path: String = SAVE_PATH
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		error = "No se pudo guardar el evento"
		return false
	file.store_string(JSON.stringify(doc, "", true, true))
	file.close()
	var result := DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))
	if result != OK:
		error = "No se pudo reemplazar el guardado del evento"
		return false
	# Libro de puntos por evento: repetir una carga o reabrir resultados
	# no puede volver a otorgarlos (se conserva points_ledger).
	return true

func restore() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var doc := _read_json(SAVE_PATH)
	var ver := int(doc.get("version", -1))
	if ver == 2:
		error = "Guardado v2 sin clima/compuesto: requiere migración explícita o iniciar un evento nuevo (no se altera en silencio)"
		return false
	if ver != 3:
		return false
	if str(doc.get("event_id", "")) != str(event_doc.get("event_id", "russia_rally")):
		return false
	if str(doc.get("rules_hash", "")) != _rules_hash_for_restore(doc):
		error = "Guardado incompatible: reglas, rutas o generador distintos"
		return false
	cursor = int(doc.get("cursor", 0))
	status = str(doc.get("status", "running"))
	seed_value = int(doc.get("seed", seed_value))
	difficulty = int(doc.get("difficulty", difficulty))
	single_day = bool(doc.get("single_day", false))
	itinerary = doc.get("itinerary", [])
	official = doc.get("official", {})
	points_ledger = doc.get("points_ledger", {})
	closed_keys.clear()
	for key in doc.get("closed_keys", []):
		closed_keys[str(key)] = true
	definitive_withdrawals.clear()
	for pid in doc.get("definitive_withdrawals", []):
		definitive_withdrawals[str(pid)] = true
	ambient_rate = float((doc.get("clock", {}) as Dictionary).get("rate", 1.0))
	# Clima/compuesto/ventanas: reanudar conserva todo; no se re-sortea.
	weather_schedule = doc.get("weather_schedule", [])
	climate_seed = int(doc.get("climate_seed", 0))
	weather_generator_version = int(doc.get("generator_version", 1))
	route_hashes = doc.get("route_hashes", {})
	surface_continuity = doc.get("surface_continuity", {})
	confirmed_compound_id = str(doc.get("confirmed_compound", "gravel_normal"))
	draft_compound_id = str(doc.get("draft_compound", confirmed_compound_id))
	setup_values = doc.get("setup_values", {})
	mounted_tire_condition = doc.get("mounted_tire_condition", [])
	tire_inventory_state = doc.get("tire_inventory_state", {})
	vehicle_damage_state = doc.get("vehicle_damage_state", {})
	service_penalties_ms = doc.get("service_penalties_ms", {})
	setup_confirmed = bool(doc.get("setup_confirmed", false))
	windows_attended = doc.get("windows_attended", {})
	pending_window = doc.get("pending_window", {})
	stage_surface_states = doc.get("stage_surface_states", {})
	rival_compounds = doc.get("rival_compounds", {})
	compound_catalog = CompoundScript.load_catalog()
	# Si se cerró durante una ventana, restaurar la ventana pendiente.
	if pending_window.is_empty():
		_update_pending_window()
	return true


func migrate_legacy_v2() -> Dictionary:
	# Migración explícita de v2: informa sin alterar la prueba oficial ya empezada.
	if not FileAccess.file_exists(SAVE_PATH):
		return {"ok": false, "error": "Sin guardado previo"}
	var doc := _read_json(SAVE_PATH)
	if int(doc.get("version", -1)) != 2:
		return {"ok": false, "error": "Solo migra guardados v2"}
	return {"ok": false, "error": "Guardado v2 sin cronograma climático: inicie un evento nuevo para usar clima por zonas y dos compuestos", "needs_new_event": true}

func _register_participants() -> void:
	official.clear()
	for entry in sim.entries:
		var pid := str(entry.get("driver_id", ""))
		official[pid] = {"name": entry.get("name", pid), "stages": {}, "grand_total_ms": 0, "eligible": true}
	official["player"] = {"name": "Jugador", "stages": {}, "grand_total_ms": 0, "eligible": true}

func _set_official(pid: String, stage_id: String, official_ms: int, penalty_ms: int, status_value: String, finished_valid: bool, counts_for_bonus: bool, provenance: String) -> void:
	if not official.has(pid):
		official[pid] = {"name": pid, "stages": {}, "grand_total_ms": 0, "eligible": true}
	var entry: Dictionary = official[pid]
	# Clave evento/participante/especial: no duplicar.
	var key := "%s/%s/%s" % [event_doc.get("event_id", "russia_rally"), pid, stage_id]
	if closed_keys.has("entry:" + key):
		return
	closed_keys["entry:" + key] = true
	var stages: Dictionary = entry.get("stages", {})
	stages[stage_id] = {
		"official_ms": official_ms,
		"penalty_ms": penalty_ms,
		"status": status_value,
		"finished_valid": finished_valid,
		"counts_for_bonus": counts_for_bonus,
		"provenance": provenance,
	}
	var total := 0
	for sid in stages:
		total += int((stages[sid] as Dictionary).get("official_ms", 0))
	entry["grand_total_ms"] = total
	entry["stage_totals"] = _stage_totals(entry)

func _stage_totals(entry: Dictionary) -> Dictionary:
	var out := {}
	for sid in (entry.get("stages", {}) as Dictionary):
		out[sid] = int((((entry.get("stages", {}) as Dictionary)[sid]) as Dictionary).get("official_ms", 0))
	return out

func _sunday_map(entry: Dictionary, sunday_ids: Array) -> Dictionary:
	var out := {}
	for sid in sunday_ids:
		out[sid] = int((((entry.get("stages", {}) as Dictionary).get(sid, {})) as Dictionary).get("official_ms", 0))
	return out

func _award_points_if_closed() -> void:
	# Solo otorga al cierre del evento; repetir no duplica.
	if status != "finished":
		return
	if not points_ledger.is_empty():
		return
	var power_times := {}
	var power_id := str(event_doc.get("power_stage_id", "russia_stage10"))
	for pid in official:
		var rec: Dictionary = ((official[pid].get("stages", {})) as Dictionary).get(power_id, {})
		if not rec.is_empty() and bool(rec.get("counts_for_bonus", false)):
			power_times[pid] = int(rec.get("official_ms", 0))
	var awarded := final_points(power_times)
	points_ledger = awarded

func _build_itinerary(choices: Dictionary) -> void:
	itinerary.clear()
	var doc_itin: Dictionary = event_doc.get("itinerary_default", {})
	if not custom_starts.is_empty():
		pass
	if single_day:
		var alt: Dictionary = doc_itin.get("single_day_alternative", {})
		var starts: Array = alt.get("starts", [])
		var date: String = str(alt.get("date", event_doc.get("base_date", "2026-06-13")))
		var day_offset := 0
		var previous_start := -1
		for i in stage_order.size():
			var start_str := str(starts[i]) if i < starts.size() else "08:00"
			var parts := start_str.split(":")
			var start_minutes := int(parts[0]) * 60 + int(parts[1])
			if previous_start >= 0 and start_minutes <= previous_start:
				day_offset += 1
			previous_start = start_minutes
			var day := _shift_date(date, day_offset)
			itinerary.append({"stage_id": stage_order[i], "date": day, "start": start_str, "day_label": "Único"})
	else:
		for day in (doc_itin.get("days", []) as Array):
			var ids: Array = day.get("stage_ids", [])
			var starts_day: Array = day.get("starts", [])
			for i in ids.size():
				var sid: String = str(ids[i])
				if stage_order.has(sid):
					itinerary.append({"stage_id": sid, "date": str(day.get("date", "")), "start": str(starts_day[i]) if i < starts_day.size() else "08:00", "day_label": str(day.get("label", ""))})
	# Validación: horarios absolutos crecientes y margen entre salidas.
	var previous := -1
	for entry in itinerary:
		var absolute := _absolute_minutes(str(entry.get("date", "")), str(entry.get("start", "")))
		entry["absolute_minutes"] = absolute
		if absolute <= previous:
			error = "Itinerario no creciente en %s" % entry.get("stage_id", "")
		previous = absolute

func resume_after_crash() -> Dictionary:
	# Tras cierre durante conducción: no restaurar coche en coordenadas de
	# otra especial; proponer reanudar como abandono con reenganche.
	if status != "running":
		return {"resumed": false}
	var stage_id := current_stage_id()
	if stage_id.is_empty() or closed_keys.has("closed:" + stage_id):
		return {"resumed": false}
	var reference_total = sim.stage_reference_total_ms() if sim != null else 0
	var rejoin_penalty: int = int(((event_doc.get("retirement_policy", {}) as Dictionary).get("rejoin_penalty_ms", 300000)))
	var adj = reference_total + rejoin_penalty
	_set_official("player", stage_id, adj, 0, "adjudicated", false, false, "Crash durante conducción: abandono con reenganche")
	closed_keys["closed:" + stage_id] = true
	return {"resumed": true, "stage_id": stage_id, "adjudicated_ms": adj}

func validate_schedule(min_gap_minutes: float = 30.0) -> Dictionary:
	var conflicts: Array = []
	for i in range(1, itinerary.size()):
		var gap: float = float(itinerary[i].get("absolute_minutes", 0)) - float(itinerary[i - 1].get("absolute_minutes", 0))
		if gap < min_gap_minutes:
			conflicts.append({"between": [itinerary[i - 1].get("stage_id"), itinerary[i].get("stage_id")], "gap_minutes": gap})
	return {"conflicts": conflicts, "ok": conflicts.is_empty()}

func _absolute_minutes(date: String, hm: String) -> float:
	var dparts := date.split("-")
	var day_index := 0
	if dparts.size() == 3:
		day_index = int(dparts[2])
	var hparts := hm.split(":")
	return float(day_index * 1440 + int(hparts[0]) * 60 + int(hparts[1]))

func _rules_hash() -> String:
	if not route_hashes.is_empty():
		return SchedulerScript.rules_hash_for(event_doc, route_hashes)
	return JSON.stringify({"event": event_doc.get("event_id", ""), "stages": stage_order, "points": event_doc.get("points_profile_id", ""), "policy": event_doc.get("retirement_policy", {}), "weather_rules": event_doc.get("weather_rules", {}), "tire_rules": event_doc.get("tire_rules", {}), "setup_windows": event_doc.get("setup_windows", []), "generator_version": SchedulerScript.GENERATOR_VERSION}).sha256_text()


func _rules_hash_for_restore(doc: Dictionary) -> String:
	# El hash guardado ya incluía rutas y versión del generador.
	var rh: Dictionary = doc.get("route_hashes", {})
	if rh.is_empty():
		return _rules_hash()
	var current_hashes := {}
	for sid in stage_order:
		var path := "res://data/rally/%s_route.json" % sid
		current_hashes[sid] = FileAccess.get_file_as_string(path).sha256_text()
	return SchedulerScript.rules_hash_for(event_doc, current_hashes)

func _shift_date(iso: String, delta_days: int) -> String:
	var parts := iso.split("-")
	if parts.size() != 3:
		return iso
	var y := int(parts[0])
	var m := int(parts[1])
	var d := int(parts[2]) + delta_days
	var leap := (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0))
	var month_days := [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	while d > month_days[m - 1]:
		d -= month_days[m - 1]
		m += 1
		if m > 12:
			m = 1
			y += 1
	return "%04d-%02d-%02d" % [y, m, d]
