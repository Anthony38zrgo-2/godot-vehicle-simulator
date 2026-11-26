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

var save_path: String = SAVE_PATH

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
var stage_forecasts: Array = []
var climate_seed: int = 0
var initial_weather: String = ""
var selected_livery_id: String = ""
var weather_generator_version: int = 1
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
var championship_standings: Array = []
var championship_points: Dictionary = {}
var initial_start_draw: Array = []
var start_order_by_stage: Dictionary = {}
var legacy_locked_stages: Dictionary = {}
var started_stages: Dictionary = {}
var climate_mode: String = ""
var save_mode_version: int = 2
var start_order_rules_override: Dictionary = {}

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		error = "No existe " + path
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		error = "JSON inválido: " + path
		return {}
	return parsed

var event_path_used: String = EVENT_PATH

func load_event(event_path: String = "") -> bool:
	error = ""
	var path := event_path.strip_edges() if not event_path.is_empty() else EVENT_PATH
	event_doc = _read_json(path)
	if event_doc.is_empty():
		return false
	event_path_used = path
	stage_order.clear()
	var configured_stages: Variant = event_doc.get("stages_explicit_order")
	if not (configured_stages is Array) or configured_stages.is_empty():
		error = "El evento debe listar al menos una especial"
		return false
	stage_order = configured_stages.duplicate()
	return true

func begin_event(choices: Dictionary = {}) -> bool:
	if choices.has("save_path"):
		save_path = str(choices["save_path"])
	var requested_event := str(choices.get("event_path", choices.get("event_id", "")))
	# Acepta ruta res:// completa o event_id ("kenya_rally" -> evento de Kenia).
	if requested_event == "cdi_rally" or requested_event == "cdi":
		requested_event = "res://data/competition/events/cdi_rally.json"
	elif requested_event == "kenya_rally" or requested_event == "kenya":
		requested_event = "res://data/competition/events/kenya_rally.json"
	elif requested_event == "finland_rally" or requested_event == "finland":
		requested_event = "res://data/competition/events/finland_rally.json"
	elif requested_event == "sweden_rally" or requested_event == "sweden":
		requested_event = "res://data/competition/events/sweden_rally.json"
	elif requested_event == "switzerland_rally" or requested_event == "switzerland":
		requested_event = "res://data/competition/events/switzerland_rally.json"
	elif requested_event == "russia_rally" or requested_event == "russia":
		requested_event = EVENT_PATH
	if not load_event(requested_event):
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
	initial_weather = str(choices.get("initial_weather", choices.get("weather", choices.get("start_weather", ""))))
	selected_livery_id = str(choices.get("livery_id", choices.get("selected_livery_id", ""))).strip_edges().to_lower()
	cursor = 0
	official.clear()
	points_ledger.clear()
	closed_keys.clear()
	definitive_withdrawals.clear()
	weather_schedule.clear()
	stage_forecasts.clear()
	stage_surface_states.clear()
	rival_compounds.clear()
	championship_points = {}
	if bool(choices.get("carry_championship_points", false)) and FileAccess.file_exists(save_path):
		var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if previous is Dictionary:
			championship_points = (previous.get("championship_points", {}) as Dictionary).duplicate()
			if str(previous.get("status", "")) == "finished":
				var round_points: Dictionary = (previous.get("points_ledger", {}) as Dictionary).get("total", {})
				for pid in round_points:
					var points := int(round_points[pid])
					if points > 0:
						championship_points[pid] = int(championship_points.get(pid, 0)) + points
	championship_standings = _normalize_championship_standings(choices.get("championship_standings", championship_points))
	initial_start_draw.clear()
	start_order_by_stage.clear()
	legacy_locked_stages.clear()
	started_stages.clear()
	climate_mode = str(choices.get("climate_mode", "")).strip_edges().to_lower()
	save_mode_version = int(choices.get("save_mode_version", 2))
	var rules_ovr: Variant = choices.get("start_order_rules", {})
	start_order_rules_override = (rules_ovr as Dictionary).duplicate(true) if rules_ovr is Dictionary else {}
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
	var allowed_compound_ids: Array = get_allowed_compound_ids()
	if not CompoundScript.is_valid(default_compound):
		error = "Compuesto predeterminado inexistente: " + default_compound
		return false
	if not allowed_compound_ids.is_empty() and not allowed_compound_ids.has(default_compound):
		error = "Compuesto predeterminado no permitido en este evento: " + default_compound
		return false
	if not requested_compound.is_empty():
		if not CompoundScript.is_valid(requested_compound):
			error = "Compuesto solicitado inexistente: " + requested_compound
			return false
		if not allowed_compound_ids.is_empty() and not allowed_compound_ids.has(requested_compound):
			error = "Compuesto no permitido en este evento: " + requested_compound
			return false
	draft_compound_id = requested_compound if not requested_compound.is_empty() else default_compound
	confirmed_compound_id = default_compound
	compound_catalog = CompoundScript.load_catalog()
	status = "running"
	_build_itinerary(choices)
	# Generar el itinerario climático de todo el rally una sola vez tras Aceptar.
	if not _generate_weather_schedule():
		return false
	stage_forecasts = SchedulerScript.generate_stage_forecasts(weather_schedule, climate_seed, _forecast_accuracy(), _ordered_weather_states())
	# La selección es borrador hasta confirmación explícita del reglaje.
	if bool(choices.get("setup_accepted", false)):
		var setup_result: Dictionary = confirm_setup(draft_compound_id, choices.get("setup_values", {}))
		if not bool(setup_result.get("ok", false)):
			error = str(setup_result.get("error", "Reglaje inicial inválido"))
			return false
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
	if _start_order_enabled() and not stage_order.is_empty():
		_ensure_initial_start_draw()
		_resolve_and_freeze_start_order(str(stage_order[0]), "")
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
			var out: Dictionary = (entry as Dictionary).duplicate(true)
			var base_date := str(out.get("base_date", out.get("date", "2026-06-13")))
			var base_start := str(out.get("base_start", out.get("start", "08:00")))
			var base_abs: int = int(out.get("base_abs_seconds", datetime_to_abs_seconds(base_date, base_start)))
			out["base_date"] = base_date
			out["base_start"] = base_start
			out["base_abs_seconds"] = base_abs
			if not legacy_locked_stages.has(stage_id) and start_order_by_stage.has(stage_id):
				var so: Dictionary = start_order_by_stage[stage_id] as Dictionary
				var eff_abs: int = int(so.get("player_abs_seconds", base_abs))
				var eff_dt: Dictionary = abs_seconds_to_datetime(eff_abs)
				out["date"] = str(eff_dt.get("date", base_date))
				out["start"] = str(eff_dt.get("hm", base_start))
				out["effective_date"] = str(eff_dt.get("date", base_date))
				out["effective_hm"] = str(eff_dt.get("hm", base_start))
				out["effective_hms"] = str(eff_dt.get("hms", base_start + ":00"))
				out["effective_seconds_of_day"] = int(eff_dt.get("seconds_of_day", eff_abs % 86400))
				out["effective_abs_seconds"] = eff_abs
				out["effective_hour"] = float(eff_dt.get("hour_float", 8.0))
				out["start_position_order"] = int(so.get("player_position", 1))
				out["interval_seconds"] = int(so.get("interval_seconds", 60))
				out["start_order_frozen"] = bool(so.get("frozen", true))
				out["start_order_source"] = str(so.get("source", ""))
				out["start_order_total"] = (so.get("entries", []) as Array).size()
			else:
				var base_dt: Dictionary = abs_seconds_to_datetime(base_abs)
				out["effective_date"] = str(base_dt.get("date", base_date))
				out["effective_hm"] = str(base_dt.get("hm", base_start))
				out["effective_hms"] = str(base_dt.get("hms", base_start + ":00"))
				out["effective_seconds_of_day"] = int(base_dt.get("seconds_of_day", base_abs % 86400))
				out["effective_abs_seconds"] = base_abs
				out["effective_hour"] = float(base_dt.get("hour_float", 8.0))
				out["start_position_order"] = 1
				out["interval_seconds"] = _start_interval_for_stage(stage_id) if _start_order_enabled() else 0
				out["start_order_frozen"] = false
				out["start_order_source"] = "legacy_base" if legacy_locked_stages.has(stage_id) else "base"
			return out
	return {}


func start_order_for_stage(stage_id: String) -> Dictionary:
	if start_order_by_stage.has(stage_id):
		return (start_order_by_stage[stage_id] as Dictionary).duplicate(true)
	return {}


func mark_stage_started(stage_id: String = "") -> void:
	var sid := stage_id if not stage_id.is_empty() else current_stage_id()
	if not sid.is_empty():
		started_stages[sid] = true


func weather_entry_for(stage_id: String) -> Dictionary:
	for entry in weather_schedule:
		if str((entry as Dictionary).get("stage_id", "")) == stage_id:
			return (entry as Dictionary).duplicate(true)
	return {}


func forecast_for_half(from_stage_index: int, count: int = 5) -> Dictionary:
	return SchedulerScript.forecast_for_half(weather_schedule, from_stage_index, count)


func setup_windows() -> Array:
	return (event_doc.get("setup_windows", []) as Array).duplicate(true)


func get_allowed_compound_ids() -> Array:
	var rules: Dictionary = event_doc.get("tire_rules", {})
	return (
		rules.get("allowed_compound_ids", []) as Array
	).duplicate()


func get_compound_label_overrides() -> Dictionary:
	var rules: Dictionary = event_doc.get("tire_rules", {})
	var overrides: Variant = rules.get("compound_label_overrides", {})
	return (overrides as Dictionary).duplicate(true) if overrides is Dictionary else {}


func get_compound_label(compound_id: String, short: bool = false) -> String:
	return CompoundScript.compound_label(
		compound_id,
		short,
		get_compound_label_overrides(),
		compound_catalog
	)


func _forecast_accuracy() -> float:
	var rules: Dictionary = event_doc.get("tire_rules", {})
	var acc := float(rules.get("forecast_accuracy", SchedulerScript.FORECAST_DEFAULT_ACCURACY))
	if acc <= 0.0 or acc >= 1.0:
		return SchedulerScript.FORECAST_DEFAULT_ACCURACY
	return acc


func _ordered_weather_states() -> Array:
	var rules: Dictionary = event_doc.get("weather_rules", {})
	var states: Array = rules.get("ordered_states", [])
	if states.is_empty():
		return ["sunny", "clear", "partly_cloudy", "cloudy", "overcast", "mist_fog", "drizzle", "light_precipitation", "medium_precipitation", "heavy_precipitation"]
	return states.duplicate()


func _update_pending_window() -> void:
	pending_window = {}
	var current := current_stage_id()
	var prev_id := "" if cursor <= 0 else str(stage_order[cursor - 1])
	if cursor == 0 and not windows_attended.has("initial"):
		pending_window = {
			"before_stage_id": current,
			"initial_tab": "quick",
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


func confirm_setup(
	compound_id: String,
	values: Dictionary = {},
	wheel_compounds: Dictionary = {}
) -> Dictionary:
	var allowed_ids: Array = get_allowed_compound_ids()
	if not CompoundScript.is_valid(compound_id):
		error = "Compuesto desconocido: " + compound_id
		return {"ok": false, "error": error}
	if not allowed_ids.is_empty() and not allowed_ids.has(compound_id):
		error = "Compuesto no permitido en este evento: " + compound_id
		return {"ok": false, "error": error}
	if not wheel_compounds.is_empty():
		for corner in ["FL", "FR", "RL", "RR"]:
			var wheel_cid := str(wheel_compounds.get(corner, ""))
			if wheel_cid.is_empty():
				error = "Compuesto desconocido en rueda " + corner
				return {"ok": false, "error": error}
			if not CompoundScript.is_valid(wheel_cid):
				error = "Compuesto desconocido: " + wheel_cid
				return {"ok": false, "error": error}
			if not allowed_ids.is_empty() and not allowed_ids.has(wheel_cid):
				error = "Compuesto no permitido en este evento: " + wheel_cid
				return {"ok": false, "error": error}
	# Idempotente: doble clic no duplica cambios ni servicio.
	if setup_confirmed and str(compound_id) == confirmed_compound_id and (values.is_empty() or values == setup_values):
		return {"ok": true, "already": true, "compound": confirmed_compound_id}
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
		var stage_cfg := _read_json(loader.stage_config_path(str(sid)))
		route_paths[str(sid)] = str(stage_cfg.get("route_path", loader.route_path(str(sid))))
	var result := sched.generate_event_schedule(event_doc, stage_order, itinerary, seed_value, route_paths, initial_weather)
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
	surface_continuity = result.get("surface_continuity", {})
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
			# Keep the original forecast decisions; tire selection is data-driven.
			var pick_wet := wet_zones >= 2 or (wet_zones >= 1 and rng.randf() < 0.4)
			var chosen := _rival_compound_for_weather(pick_wet)
			if rival_compounds.get(sid, {}) is Dictionary:
				(rival_compounds[sid] as Dictionary)[pid] = chosen
			else:
				rival_compounds[sid] = {pid: chosen}
		# El jugador usa el confirmado (no se sortea).
		if rival_compounds.get(sid, {}) is Dictionary:
			(rival_compounds[sid] as Dictionary)["player"] = confirmed_compound_id


func _rival_compound_for_weather(wet: bool) -> String:
	var allowed: Array = get_allowed_compound_ids()
	if str(event_doc.get("event_id", "")) == "sweden_rally":
		if allowed.is_empty() or allowed.has("snow_studded"):
			return "snow_studded"
	var rules: Dictionary = event_doc.get("tire_rules", {})
	var preferred := str(rules.get("wet_compound_id" if wet else "dry_compound_id", ""))
	if not preferred.is_empty() and CompoundScript.is_valid(preferred):
		if allowed.is_empty() or allowed.has(preferred):
			return preferred
	var definitions: Dictionary = compound_catalog.get("compounds", {})
	var candidates: Array = []
	for cid in definitions:
		if allowed.is_empty() or allowed.has(cid):
			candidates.append(str(cid))
	if candidates.is_empty():
		for cid in definitions:
			candidates.append(str(cid))
	var chosen := confirmed_compound_id
	if not candidates.has(chosen) and not candidates.is_empty():
		chosen = str(candidates[0])
	var best := INF
	for cid in candidates:
		var model: Dictionary = definitions.get(cid, {})
		var score := float(model.get("water_grip_loss_per_mm", 0.12)) if wet else float(model.get("dry_wear_multiplier", 1.0))
		if score < best:
			best = score
			chosen = str(cid)
	return chosen


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
			if total_ms <= 0 and (row.get("splits", []) as Array).is_empty():
				total_ms = reference_total
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
	legacy_locked_stages.erase(stage_id)
	if _start_order_enabled() and not is_last_stage():
		var next_id := str(stage_order[cursor + 1])
		_resolve_and_freeze_start_order(next_id, stage_id)
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
	var prev_id := current_stage_id()
	if sim == null:
		_ensure_sim_restored({})
	if sim != null and prev_id in event_doc.get("service", {}).get("after_stage_ids", []):
		sim.apply_event_service()
	var carried = sim.rows.duplicate(true) if sim != null else []
	cursor += 1
	var next_id := current_stage_id()
	if _start_order_enabled() and not start_order_by_stage.has(next_id):
		_resolve_and_freeze_start_order(next_id, prev_id)
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
		"save_mode_version": save_mode_version,
		"climate_mode": climate_mode,
		"event_id": event_doc.get("event_id", "russia_rally"),
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
		"championship_standings": championship_standings,
		"championship_points": championship_points,
		"initial_start_draw": initial_start_draw,
		"start_order_by_stage": start_order_by_stage,
		"legacy_locked_stages": legacy_locked_stages.keys(),
		"started_stages": started_stages.keys(),
		"start_order_rules_override": start_order_rules_override,
		"clock": {"rate": ambient_rate},
		"weather_schedule": weather_schedule,
		"stage_forecasts": stage_forecasts,
		"climate_seed": climate_seed,
		"initial_weather": initial_weather,
		"selected_livery_id": selected_livery_id,
		"generator_version": weather_generator_version,
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
		"sim_rows": sim.rows.duplicate(true) if sim != null else [],
		"sim_previous_totals": sim.previous_totals.duplicate(true) if sim != null else {},
		"sim_player_previous_ms": int(sim.player_previous_ms) if sim != null else 0,
	}
	var path: String = save_path
	if path.is_empty():
		return true
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
	if save_path.is_empty() or not FileAccess.file_exists(save_path):
		return false
	var doc := _read_json(save_path)
	var ver := int(doc.get("version", -1))
	if ver == 2:
		error = "Guardado v2 sin clima/compuesto: requiere migración explícita o iniciar un evento nuevo (no se altera en silencio)"
		return false
	if ver != 3:
		return false
	if str(doc.get("event_id", "")) != str(event_doc.get("event_id", "russia_rally")):
		return false
	save_mode_version = int(doc.get("save_mode_version", 1))
	climate_mode = str(doc.get("climate_mode", "procedural_v1" if save_mode_version < 2 else ""))
	cursor = int(doc.get("cursor", 0))
	status = str(doc.get("status", "running"))
	seed_value = int(doc.get("seed", seed_value))
	difficulty = int(doc.get("difficulty", difficulty))
	single_day = bool(doc.get("single_day", false))
	itinerary = doc.get("itinerary", [])
	# The saved itinerary owns the stage order of an event already in progress.
	if not itinerary.is_empty():
		var saved_order: Array = []
		for entry: Dictionary in itinerary:
			saved_order.append(str(entry.get("stage_id", "")))
		stage_order = saved_order
	for it_entry in itinerary:
		if it_entry is Dictionary:
			var ed := it_entry as Dictionary
			var bdate := str(ed.get("base_date", ed.get("date", "2026-06-13")))
			var bstart := str(ed.get("base_start", ed.get("start", "08:00")))
			ed["base_date"] = bdate
			ed["base_start"] = bstart
			if not ed.has("base_abs_seconds"):
				ed["base_abs_seconds"] = datetime_to_abs_seconds(bdate, bstart)
	official = doc.get("official", {})
	points_ledger = doc.get("points_ledger", {})
	closed_keys.clear()
	for key in doc.get("closed_keys", []):
		closed_keys[str(key)] = true
	definitive_withdrawals.clear()
	for pid in doc.get("definitive_withdrawals", []):
		definitive_withdrawals[str(pid)] = true
	championship_points = (doc.get("championship_points", {}) as Dictionary).duplicate()
	championship_standings = _normalize_championship_standings(doc.get("championship_standings", championship_points))
	initial_start_draw = (doc.get("initial_start_draw", []) as Array).duplicate()
	start_order_by_stage = (doc.get("start_order_by_stage", {}) as Dictionary).duplicate(true)
	legacy_locked_stages.clear()
	for sid in doc.get("legacy_locked_stages", []):
		legacy_locked_stages[str(sid)] = true
	started_stages.clear()
	for sid in doc.get("started_stages", []):
		started_stages[str(sid)] = true
	var r_ovr: Variant = doc.get("start_order_rules_override", {})
	start_order_rules_override = (r_ovr as Dictionary).duplicate(true) if r_ovr is Dictionary else {}
	ambient_rate = float((doc.get("clock", {}) as Dictionary).get("rate", 1.0))
	# Clima/compuesto/ventanas: reanudar conserva todo; no se re-sortea.
	weather_schedule = doc.get("weather_schedule", [])
	stage_forecasts = doc.get("stage_forecasts", [])
	if stage_forecasts.is_empty() and not weather_schedule.is_empty():
		stage_forecasts = SchedulerScript.generate_stage_forecasts(weather_schedule, climate_seed, _forecast_accuracy(), _ordered_weather_states())
	climate_seed = int(doc.get("climate_seed", 0))
	initial_weather = str(doc.get("initial_weather", ""))
	selected_livery_id = str(doc.get("selected_livery_id", "")).strip_edges().to_lower()
	weather_generator_version = int(doc.get("generator_version", 1))
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
	_ensure_sim_restored(doc)
	# Resolver listas pendientes en guardados previos sin listas de salida,
	# conservando la referencia temporal de la especial activa si ya había iniciado.
	if _start_order_enabled():
		_ensure_initial_start_draw()
		var cur_sid := current_stage_id()
		var had_active_legacy := (
			save_mode_version < 2
			and status == "running"
			and not cur_sid.is_empty()
			and not closed_keys.has("closed:" + cur_sid)
			and (started_stages.has(cur_sid) or stage_surface_states.has(cur_sid) or setup_confirmed)
		)
		if had_active_legacy and not start_order_by_stage.has(cur_sid):
			legacy_locked_stages[cur_sid] = true
		_resolve_pending_start_orders_on_restore()
	# Si se cerró durante una ventana, restaurar la ventana pendiente.
	if pending_window.is_empty():
		_update_pending_window()
	return true


func _ensure_sim_restored(doc: Dictionary) -> void:
	if stage_order.is_empty():
		return
	var cur_sid := current_stage_id()
	if cur_sid.is_empty():
		return
	var cfg_path: String = loader.stage_config_path(cur_sid)
	if cfg_path.is_empty() or not FileAccess.file_exists(cfg_path):
		return
	var CompetitionScript := load("res://scripts/rally/rally_competition.gd")
	var restored_sim = CompetitionScript.new()
	restored_sim.save_path = ""
	var saved_rows: Variant = doc.get("sim_rows", [])
	var carried: Array = saved_rows.duplicate(true) if saved_rows is Array else []
	if restored_sim.configure(cfg_path, seed_value, carried):
		restored_sim.leg = cursor + 1
		if doc.get("sim_previous_totals", {}) is Dictionary:
			restored_sim.previous_totals = (doc.get("sim_previous_totals", {}) as Dictionary).duplicate(true)
		restored_sim.player_previous_ms = int(doc.get("sim_player_previous_ms", 0))
		if restored_sim.has_method("set_weather_context"):
			restored_sim.set_weather_context(weather_entry_for(cur_sid), rival_compounds.get(cur_sid, {}))
		sim = restored_sim


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
		var ed := entry as Dictionary
		var pid := str(ed.get("driver_id", ""))
		var eligible := not _is_zero_car_entry(pid, ed)
		official[pid] = {
			"name": ed.get("name", pid),
			"stages": {},
			"grand_total_ms": 0,
			"eligible": eligible,
			"zero_car": not eligible,
		}
	official["player"] = {"name": "Jugador", "stages": {}, "grand_total_ms": 0, "eligible": true, "zero_car": false}


func player_start_summary_text(stage_id: String = "") -> String:
	var sid := stage_id if not stage_id.is_empty() else current_stage_id()
	var sched := schedule_for(sid)
	if sched.is_empty():
		return ""
	var eff_hms := str(sched.get("effective_hms", sched.get("start", "")))
	var eff_hm := str(sched.get("effective_hm", sched.get("start", "")))
	var disp_time := eff_hm if eff_hms.ends_with(":00") else eff_hms
	if bool(sched.get("start_order_frozen", false)):
		var pos := int(sched.get("start_position_order", 1))
		var total := int(sched.get("start_order_total", pos))
		var base_hm := str(sched.get("base_start", ""))
		var interval_s := int(sched.get("interval_seconds", 60))
		return "Turno #%d/%d · Salida %s (Base %s · +%ds)" % [pos, total, disp_time, base_hm, interval_s]
	return "Salida %s" % disp_time

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
	var override_starts: Dictionary = choices.get("custom_starts", custom_starts) if choices.get("custom_starts", {}) is Dictionary else custom_starts
	if single_day:
		var alt: Dictionary = doc_itin.get("single_day_alternative", {})
		var starts: Array = alt.get("starts", [])
		var date: String = str(alt.get("date", event_doc.get("base_date", "2026-06-13")))
		var day_offset := 0
		var previous_start := -1
		for i in stage_order.size():
			var sid := str(stage_order[i])
			var start_str := str(override_starts.get(sid, starts[i] if i < starts.size() else "08:00"))
			var parts := start_str.split(":")
			var start_minutes := int(parts[0]) * 60 + int(parts[1])
			if previous_start >= 0 and start_minutes <= previous_start:
				day_offset += 1
			previous_start = start_minutes
			var day := _shift_date(date, day_offset)
			var base_abs := datetime_to_abs_seconds(day, start_str)
			itinerary.append({"stage_id": sid, "date": day, "start": start_str, "base_date": day, "base_start": start_str, "base_abs_seconds": base_abs, "day_label": "Único"})
	else:
		for day in (doc_itin.get("days", []) as Array):
			var ids: Array = day.get("stage_ids", [])
			var starts_day: Array = day.get("starts", [])
			for i in ids.size():
				var sid: String = str(ids[i])
				if stage_order.has(sid):
					var d_str := str(day.get("date", event_doc.get("base_date", "2026-06-13")))
					var s_str := str(override_starts.get(sid, starts_day[i] if i < starts_day.size() else "08:00"))
					var base_abs := datetime_to_abs_seconds(d_str, s_str)
					itinerary.append({"stage_id": sid, "date": d_str, "start": s_str, "base_date": d_str, "base_start": s_str, "base_abs_seconds": base_abs, "day_label": str(day.get("label", ""))})
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
	return float(datetime_to_abs_seconds(date, hm)) / 60.0


static func _days_from_civil(y: int, m: int, d: int) -> int:
	# Howard Hinnant's civil-from-days / days-from-civil (UTC/Julian-free exact integer math).
	var yy := y - (1 if m <= 2 else 0)
	var era := (yy if yy >= 0 else yy - 399) / 400
	var yoe := yy - era * 400
	var doy := (153 * (m + (-3 if m > 2 else 9)) + 2) / 5 + d - 1
	var doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468


static func _civil_from_days(z_in: int) -> Dictionary:
	var z := z_in + 719468
	var era := (z if z >= 0 else z - 146096) / 146097
	var doe := z - era * 146097
	var yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	var y := yoe + era * 400
	var doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	var mp := (5 * doy + 2) / 153
	var d := doy - (153 * mp + 2) / 5 + 1
	var m := mp + (3 if mp < 10 else -9)
	y += (1 if m <= 2 else 0)
	return {"year": y, "month": m, "day": d, "iso": "%04d-%02d-%02d" % [y, m, d]}


static func datetime_to_abs_seconds(date: String, hm_or_hms: String) -> int:
	var dparts := date.strip_edges().split("-")
	var days := 0
	if dparts.size() == 3:
		days = _days_from_civil(int(dparts[0]), int(dparts[1]), int(dparts[2]))
	var tparts := hm_or_hms.strip_edges().split(":")
	var h := int(tparts[0]) if tparts.size() >= 1 else 0
	var m := int(tparts[1]) if tparts.size() >= 2 else 0
	var s := int(tparts[2]) if tparts.size() >= 3 else 0
	return days * 86400 + h * 3600 + m * 60 + s


static func abs_seconds_to_datetime(abs_seconds: int) -> Dictionary:
	var days := floori(float(abs_seconds) / 86400.0)
	var rem := abs_seconds - days * 86400
	while rem < 0:
		rem += 86400
		days -= 1
	while rem >= 86400:
		rem -= 86400
		days += 1
	var civ := _civil_from_days(days)
	var hour := rem / 3600
	var minute := (rem % 3600) / 60
	var second := rem % 60
	return {
		"date": str(civ["iso"]),
		"year": int(civ["year"]),
		"month": int(civ["month"]),
		"day": int(civ["day"]),
		"seconds_of_day": rem,
		"hour": hour,
		"minute": minute,
		"second": second,
		"hm": "%02d:%02d" % [hour, minute],
		"hms": "%02d:%02d:%02d" % [hour, minute, second],
		"hour_float": float(rem) / 3600.0,
	}


func _shift_date(iso: String, delta_days: int) -> String:
	var parts := iso.split("-")
	if parts.size() != 3:
		return iso
	var days := _days_from_civil(int(parts[0]), int(parts[1]), int(parts[2])) + delta_days
	return str(_civil_from_days(days)["iso"])


static func start_order_draw_seed(rally_seed: int) -> int:
	return abs(int(("%d/rally_start_order_draw_v1" % rally_seed).hash()))


func _start_order_rules() -> Dictionary:
	var doc_rules := (event_doc.get("start_order_rules", {}) as Dictionary).duplicate(true)
	for k in start_order_rules_override:
		doc_rules[k] = start_order_rules_override[k]
	return doc_rules


func _start_order_enabled() -> bool:
	return bool(_start_order_rules().get("enabled", false))


func _start_interval_for_stage(stage_id: String) -> int:
	var rules := _start_order_rules()
	var overrides := rules.get("stage_interval_overrides", {}) as Dictionary
	if overrides.has(stage_id):
		return maxi(int(overrides[stage_id]), 0)
	return maxi(int(rules.get("interval_seconds", 60)), 0)


static func _is_zero_car_entry(pid: String, meta: Dictionary = {}) -> bool:
	var low := pid.strip_edges().to_lower()
	if low in ["0", "car_0", "car_zero", "zero_car", "auto_0", "auto_cero"]:
		return true
	if bool(meta.get("zero_car", false)) or bool(meta.get("is_zero_car", false)):
		return true
	var role := str(meta.get("role", "")).strip_edges().to_lower()
	return role in ["zero_car", "auto_cero", "course_car"]


func _is_eligible_for_start_order(pid: String) -> bool:
	if pid.is_empty():
		return false
	if definitive_withdrawals.has(pid):
		return false
	var meta: Dictionary = official.get(pid, {}) as Dictionary
	if _is_zero_car_entry(pid, meta):
		return false
	if meta.has("eligible") and not bool(meta.get("eligible", true)):
		return false
	return true


static func _normalize_championship_standings(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for i in (raw as Array).size():
			var item: Variant = (raw as Array)[i]
			if item is String:
				out.append({"id": str(item), "position": i + 1, "points": 0.0})
			elif item is Dictionary:
				var d := (item as Dictionary).duplicate(true)
				var pid := str(d.get("id", d.get("driver_id", "")))
				if pid.is_empty():
					continue
				out.append({
					"id": pid,
					"position": int(d.get("position", d.get("rank", 0))),
					"points": float(d.get("points", 0.0)),
				})
	elif raw is Dictionary:
		for pid in (raw as Dictionary):
			var val: Variant = (raw as Dictionary)[pid]
			if val is Dictionary:
				var d := val as Dictionary
				out.append({
					"id": str(pid),
					"position": int(d.get("position", d.get("rank", 0))),
					"points": float(d.get("points", 0.0)),
				})
			else:
				out.append({"id": str(pid), "position": 0, "points": float(val)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(a.get("position", 0))
		var pb := int(b.get("position", 0))
		if pa > 0 and pb > 0 and pa != pb:
			return pa < pb
		var pta := float(a.get("points", 0.0))
		var ptb := float(b.get("points", 0.0))
		if not is_equal_approx(pta, ptb):
			return pta > ptb
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return out


func _ensure_initial_start_draw() -> void:
	if not initial_start_draw.is_empty():
		return
	var eligible_ids: Array[String] = []
	for pid in official.keys():
		var s_pid := str(pid)
		if _is_eligible_for_start_order(s_pid):
			eligible_ids.append(s_pid)
	eligible_ids.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = start_order_draw_seed(seed_value)
	# Deterministic Fisher-Yates shuffle independent from climate stream.
	for i in range(eligible_ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := eligible_ids[i]
		eligible_ids[i] = eligible_ids[j]
		eligible_ids[j] = tmp
	initial_start_draw = eligible_ids.duplicate()


func _raw_itinerary_base(stage_id: String) -> Dictionary:
	for entry in itinerary:
		if str((entry as Dictionary).get("stage_id", "")) == stage_id:
			return entry as Dictionary
	var bdate := str(event_doc.get("base_date", "2026-06-13"))
	return {"stage_id": stage_id, "base_date": bdate, "base_start": "08:00", "base_abs_seconds": datetime_to_abs_seconds(bdate, "08:00")}


func _previous_relative_order_ids(stage_index: int) -> Array:
	for j in range(stage_index - 1, -1, -1):
		var prev_sid := str(stage_order[j])
		if start_order_by_stage.has(prev_sid):
			var ids: Array = []
			for row in ((start_order_by_stage[prev_sid] as Dictionary).get("entries", []) as Array):
				ids.append(str((row as Dictionary).get("id", "")))
			if not ids.is_empty():
				return ids
	_ensure_initial_start_draw()
	return initial_start_draw.duplicate()


func _resolve_and_freeze_start_order(stage_id: String, prev_stage_id: String = "") -> Dictionary:
	if start_order_by_stage.has(stage_id) and bool((start_order_by_stage[stage_id] as Dictionary).get("frozen", false)):
		return (start_order_by_stage[stage_id] as Dictionary).duplicate(true)
	_ensure_initial_start_draw()
	var eligible_map := {}
	for pid in official.keys():
		var s_pid := str(pid)
		if _is_eligible_for_start_order(s_pid):
			eligible_map[s_pid] = true

	var stage_idx := stage_order.find(stage_id)
	var ordered_ids: Array[String] = []
	var source_label := "initial_draw"
	if stage_idx <= 0:
		# SS01: championship standings (leader first) + deterministic draw for unranked entrants.
		var champ_ids: Array[String] = []
		var seen := {}
		for rec in championship_standings:
			var cid := str((rec as Dictionary).get("id", ""))
			if eligible_map.has(cid) and not seen.has(cid):
				seen[cid] = true
				champ_ids.append(cid)
		if not champ_ids.is_empty():
			ordered_ids.append_array(champ_ids)
			source_label = "championship_standings" if champ_ids.size() == eligible_map.size() else "championship_partial_plus_draw"
		for draw_id_var in initial_start_draw:
			var did := str(draw_id_var)
			if eligible_map.has(did) and not seen.has(did):
				seen[did] = true
				ordered_ids.append(did)
		for rem_id in eligible_map.keys():
			var s_rem := str(rem_id)
			if not seen.has(s_rem):
				seen[s_rem] = true
				ordered_ids.append(s_rem)
	else:
		# SS02+: cumulative official rally standings (leader first);
		# eligible entrants without cumulative classification follow preserving previous order.
		var ranked := standings()
		var seen2 := {}
		var classified_ids: Array[String] = []
		for r in ranked:
			var rd := r as Dictionary
			var pid := str(rd.get("id", ""))
			if not eligible_map.has(pid) or seen2.has(pid):
				continue
			var stg_map: Dictionary = rd.get("stages", {}) as Dictionary
			if not stg_map.is_empty():
				seen2[pid] = true
				classified_ids.append(pid)
		ordered_ids.append_array(classified_ids)
		source_label = "cumulative_standings" if prev_stage_id.is_empty() else ("cumulative_after_" + prev_stage_id)
		var prev_order := _previous_relative_order_ids(stage_idx)
		for prev_id_var in prev_order:
			var pid_prev := str(prev_id_var)
			if eligible_map.has(pid_prev) and not seen2.has(pid_prev):
				seen2[pid_prev] = true
				ordered_ids.append(pid_prev)
		for rem_id in eligible_map.keys():
			var s_rem2 := str(rem_id)
			if not seen2.has(s_rem2):
				seen2[s_rem2] = true
				ordered_ids.append(s_rem2)

	var base_it := _raw_itinerary_base(stage_id)
	var base_date := str(base_it.get("base_date", base_it.get("date", "2026-06-13")))
	var base_start := str(base_it.get("base_start", base_it.get("start", "08:00")))
	var base_abs := int(base_it.get("base_abs_seconds", datetime_to_abs_seconds(base_date, base_start)))
	var interval_s := _start_interval_for_stage(stage_id)
	var list_entries: Array = []
	var player_pos := 1
	var player_abs := base_abs
	var player_dt := abs_seconds_to_datetime(base_abs)
	for i in ordered_ids.size():
		var pid := ordered_ids[i]
		var pos := i + 1
		var abs_s := base_abs + i * interval_s
		var dt := abs_seconds_to_datetime(abs_s)
		var off_entry: Dictionary = official.get(pid, {}) as Dictionary
		list_entries.append({
			"position": pos,
			"id": pid,
			"name": str(off_entry.get("name", pid)),
			"start_abs_seconds": abs_s,
			"date": str(dt["date"]),
			"hm": str(dt["hm"]),
			"hms": str(dt["hms"]),
			"seconds_of_day": int(dt["seconds_of_day"]),
		})
		if pid == "player":
			player_pos = pos
			player_abs = abs_s
			player_dt = dt

	var record := {
		"stage_id": stage_id,
		"frozen": true,
		"source": source_label,
		"base_date": base_date,
		"base_start": base_start,
		"base_abs_seconds": base_abs,
		"interval_seconds": interval_s,
		"entries": list_entries,
		"player_position": player_pos,
		"player_abs_seconds": player_abs,
		"player_date": str(player_dt["date"]),
		"player_hm": str(player_dt["hm"]),
		"player_hms": str(player_dt["hms"]),
		"player_hour": float(player_dt["hour_float"]),
	}
	start_order_by_stage[stage_id] = record
	return record.duplicate(true)


func _resolve_pending_start_orders_on_restore() -> void:
	for i in range(0, mini(cursor + 1, stage_order.size())):
		var sid := str(stage_order[i])
		if legacy_locked_stages.has(sid):
			continue
		var prev_sid := "" if i <= 0 else str(stage_order[i - 1])
		# Only resolve i > 0 when prior stage is closed (or we have official results up to cursor).
		if i == 0 or closed_keys.has("closed:" + prev_sid) or i <= cursor:
			if not start_order_by_stage.has(sid):
				_resolve_and_freeze_start_order(sid, prev_sid)
