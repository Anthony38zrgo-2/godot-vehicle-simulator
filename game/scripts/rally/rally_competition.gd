extends RefCounted
## Pure virtual rally field. All official times are integer milliseconds.
## Random streams depend on entry, leg, sector and purpose, never render order.
const VERSION := 1
const DATA := "res://data/competition/"
var balance: Dictionary = {}
var stage: Dictionary = {}
var entries: Array = []
var rows: Array = []
var reference: Array = []
var sector: int = 0
var level: float = 1.0
var seed_value: int = 1974
var leg: int = 1
var complete: bool = false
var started: bool = false
var error: String = ""
var player_ms: int = 0
var player_penalty_ms: int = 0
var player_status: String = "En carrera"
var player_retired: bool = false
var player_splits: Array = []
var history: Array = []
var previous_totals: Dictionary = {}
var player_previous_ms: int = 0
var confidence: float = 0.0
var save_path: String = "user://rally_competition_v1.json"
var generation: int = -1
var initial_rows: Array = []
var initial_level: float = 1.0
var initial_confidence: float = 0.0
var configuration_hash: String = ""
var observation_cursor: int = 0
var observation_ms: int = 0
var observed_seconds: float = 0.0
var observed_factors: Array = []

func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		error = "No existe " + path
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		error = "JSON inválido: " + path
		return {}
	return parsed

func configure(stage_path: String = DATA + "stages/russia_stage1.json", race_seed: int = 1974) -> bool:
	error = ""
	seed_value = race_seed
	balance = read_json(DATA + "simulation_balance.json")
	stage = read_json(stage_path)
	var catalog := read_json(DATA + "historical_profiles_1974.json")
	var field := read_json(DATA + "entries.json")
	if not error.is_empty():
		return false
	var drivers: Dictionary = {}
	var vehicles: Dictionary = {}
	for driver: Dictionary in catalog.drivers:
		drivers[driver.id] = driver
	for vehicle: Dictionary in catalog.vehicles:
		vehicles[vehicle.id] = vehicle
	entries.clear()
	for entry: Dictionary in field.entries:
		if not drivers.has(entry.driver_id) or not vehicles.has(entry.vehicle_id):
			error = "Inscripción inválida"
			return false
		var driver: Dictionary = drivers[entry.driver_id]
		var ratings: Dictionary = driver.ratings if driver.ratings != null else {}
		if ratings.is_empty():
			if not entry.estimated_ratings is Array or entry.estimated_ratings.size() != field.rating_order.size():
				error = "Perfil incompleto: " + str(driver.id)
				return false
			for i in field.rating_order.size():
				ratings[field.rating_order[i]] = entry.estimated_ratings[i]
		for score: Variant in ratings.values():
			if float(score) < 1.0 or float(score) > 100.0:
				error = "Puntuación fuera de rango"
				return false
		var data := entry.duplicate(true)
		data.merge({"name": driver.name, "ratings": ratings, "car": vehicles[entry.vehicle_id].name})
		entries.append(data)
	var original := read_json(stage.fallback_path)
	reference.clear()
	for i in stage.sector_checkpoint_indices.size():
		var key := "CPUSplit%d" % i
		if not original.get("values_seconds", {}).has(key):
			error = "Este tramo no tiene respaldo CPU original"
			return false
		var seconds := float(original.values_seconds[key][int(stage.difficulty)]) * float(stage.reference_scale)
		if seconds <= 0.0:
			error = "Tiempo de referencia inválido"
			return false
		reference.append(seconds)
	if not error.is_empty():
		return false
	configuration_hash = (JSON.stringify(balance) + JSON.stringify(stage) + JSON.stringify(entries)).sha256_text()
	begin_stage()
	return true

func stream(id: String, purpose: String, index: int = -1) -> RandomNumberGenerator:
	var random := RandomNumberGenerator.new()
	random.seed = ("%d/%d/%s/%s/%d" % [seed_value, leg, id, purpose, index]).hash()
	return random

func begin_stage(carried: Array = []) -> void:
	rows.clear()
	sector = 0
	player_ms = 0
	player_penalty_ms = 0
	player_splits.clear()
	player_status = "En carrera"
	player_retired = false
	complete = false
	started = false
	generation = -1
	for entry: Dictionary in entries:
		var health: Dictionary = {}
		for component: String in balance.components:
			health[component] = 1.0
		var retired := false
		var old_events: Array = []
		for old: Dictionary in carried:
			if old.id == entry.driver_id:
				health = old.health.duplicate(true)
				retired = old.retired
				old_events = old.get("events", []).duplicate(true)
		var row := {"id": entry.driver_id, "name": entry.name, "car": entry.car, "team": entry.team, "ratings": entry.ratings, "vehicle_id": entry.vehicle_id, "support": entry.support, "health": health, "retired": retired, "start_status": "pending", "status": "Retirado del rally" if retired else "En carrera", "time_ms": 0, "splits": [], "events": [], "past_events": old_events, "fatigue": minf(0.5, (leg - 1) * 0.04)}
		if not retired:
			var random := stream(row.id, "preparation")
			var lowest := 1.0
			var lowest_component := "engine"
			for component: String in balance.components:
				if float(health[component]) < lowest:
					lowest = float(health[component])
					lowest_component = component
			if lowest < 0.12 or random.randf() < float(balance.dns_probability) * (2.0 - float(row.support)):
				row.retired = true
				row.start_status = "dns"
				row.status = "No tomó la salida — " + str(balance.components[lowest_component])
				row.events.append({"type": "dns", "component": lowest_component, "sector": -1, "loss_ms": 0})
			else:
				row.start_status = "started"
		rows.append(row)
	initial_rows = rows.duplicate(true)
	initial_level = level
	initial_confidence = confidence
	observation_cursor = 0
	observation_ms = 0
	observed_seconds = 0.0
	observed_factors.clear()

func reset_attempt() -> void:
	# Restores identical preparation and random streams, preventing a DNS reroll.
	rows = initial_rows.duplicate(true)
	level = initial_level
	confidence = initial_confidence
	observation_cursor = 0
	observation_ms = 0
	observed_seconds = 0.0
	observed_factors.clear()
	sector = 0
	player_ms = 0
	player_penalty_ms = 0
	player_splits.clear()
	complete = false
	started = false
	player_retired = false
	player_status = "En carrera"
	generation = -1

func update(course: Dictionary) -> void:
	if complete:
		return
	if not started and bool(course.get("running", false)):
		started = true
		save()
	if generation == -1:
		generation = int(course.get("generation", 0))
	elif generation != int(course.get("generation", 0)):
		generation = int(course.get("generation", 0))
		player_penalty_ms += int(balance.reset_penalty_ms)
	observe_progress(course)
	var splits: Array = course.get("splits", [])
	while sector < splits.size() and sector < reference.size():
		var split: Dictionary = splits[sector]
		var elapsed_ms := int(split.time_ms)
		var duration_s := float(elapsed_ms - player_ms) / 1000.0
		var observed := duration_s / float(reference[sector])
		if sector == 0 and observed_seconds >= 15.0 and observed_factors.size() >= 10:
			var sorted := observed_factors.duplicate()
			sorted.sort()
			var clean_factor := float(sorted[sorted.size() / 2])
			level = clampf(lerpf(initial_level, clean_factor, float(balance.first_split_calibration_weight)), float(balance.minimum_level), float(balance.maximum_level))
			confidence = 0.75
		# Long stops and accidents remain on the official clock, but never slow rivals.
		if observed >= 0.5 and observed <= 1.8:
			var desired := lerpf(level, observed, float(balance.adaptation_alpha))
			level += clampf(desired - level, -float(balance.adaptation_limit), float(balance.adaptation_limit))
			confidence = minf(1.0, confidence + 0.1)
		player_ms = elapsed_ms
		player_splits.append(elapsed_ms + player_penalty_ms)
		advance_sector()
		save()
	if bool(course.get("finished", false)) and sector == reference.size():
		player_ms = int(round(float(course.current_s) * 1000.0))
		finalize()

func observe_progress(course: Dictionary) -> void:
	if sector != 0:
		return
	var checkpoints: Array = course.get("checkpoint_times", [])
	while observation_cursor < checkpoints.size():
		var point: Dictionary = checkpoints[observation_cursor]
		var duration := float(int(point.time_ms) - observation_ms) / 1000.0
		var expected := float(stage.checkpoint_reference_s[int(point.index) - 1])
		var ratio := duration / maxf(0.001, expected)
		if ratio >= 0.25 and ratio <= 5.0 and duration > 0.0 and duration <= 8.0:
			observed_factors.append(ratio)
			observed_seconds += duration
		observation_ms = int(point.time_ms)
		observation_cursor += 1
	if observed_seconds >= 15.0 and observed_factors.size() >= 10:
		var sorted := observed_factors.duplicate()
		sorted.sort()
		var median := float(sorted[sorted.size() / 2])
		confidence = 0.25
		level = initial_level + clampf((median - initial_level) * confidence, -0.15, 0.15)

func add_event(row: Dictionary, kind: String, component: String, loss: int, severity: float, distance_km: float) -> void:
	var offset_km := 0.0
	for i in sector:
		offset_km += float(stage.sector_lengths_km[i])
	row.events.append({"type": kind, "component": component, "sector": sector, "distance_km": offset_km + distance_km, "loss_ms": loss, "severity": severity})

func advance_sector() -> void:
	var km := float(stage.sector_lengths_km[sector])
	for row: Dictionary in rows:
		if row.retired:
			continue
		var random := stream(row.id, "sector", sector)
		var ratings: Dictionary = row.ratings
		var vehicle: Dictionary = balance.vehicles[row.vehicle_id]
		var aggression := float(ratings.aggression) / 100.0
		var management := float(ratings.mechanical_management) / 100.0
		var affinity := float(ratings.get(stage.surface, ratings.gravel_mud))
		var damage := 0.0
		for component: String in balance.components:
			damage += (1.0 - float(row.health[component])) * 0.025
		var comeback := 0.0
		if row.time_ms > player_ms and sector > 0:
			comeback = float(ratings.comeback) / 100.0 * 0.008
		var form := stream(row.id, "form").randf_range(-0.012, 0.012)
		var factor := float(vehicle.pace_factor) * exp((96.0 - float(ratings.pace)) * 0.003 + (94.0 - affinity) * 0.0015 + damage + float(row.fatigue) * 0.025 + form - comeback)
		var weather_factor := 1.0 + float(stage.wetness) * (100.0 - affinity) * 0.0008 + (1.0 - float(stage.visibility)) * (100.0 - float(ratings.pace)) * 0.001
		var seconds := float(reference[sector]) * level * factor * weather_factor * random.randf_range(0.992, 1.008)
		for component: String in balance.components:
			var vulnerability := 1.6 if component in vehicle.vulnerable else 1.0
			var exposure := 1.0 + float(stage.roughness) + float(stage.wetness) * 0.4 + float(stage.jumps) * 0.5
			row.health[component] = maxf(0.0, float(row.health[component]) - km * float(balance.wear_per_km) * vulnerability * exposure * (0.7 + aggression - management * 0.4))
			var hazard := float(balance.mechanical_rate_per_km) * vulnerability * exposure * (0.5 + aggression) * (1.5 - management) * (1.0 + (1.0 - float(row.health[component])) * 5.0)
			if random.randf() < 1.0 - exp(-hazard * km) or float(row.health[component]) <= 0.05:
				var severity := 1.0 if float(row.health[component]) <= 0.05 else random.randf()
				var at := random.randf()
				row.health[component] = maxf(0.0, float(row.health[component]) - severity * 0.5)
				if severity > float(balance.terminal_severity) and component != "tyres":
					row.retired = true
					row.status = "Abandono — " + str(balance.components[component])
					add_event(row, "mechanical_dnf", component, 0, severity, km * at)
					seconds *= at
					break
				var loss := int(random.randf_range(8.0, 50.0) * severity * 1000.0)
				seconds += float(loss) / 1000.0
				row.status = "Daños — " + str(balance.components[component])
				add_event(row, "damage", component, loss, severity, km * at)
		if not row.retired:
			var blind := 1.5 if bool(stage.blind_route) else 1.0
			var error_rate := float(balance.error_rate_per_km) * (0.3 + aggression * 2.0) * (2.0 - affinity / 100.0) * blind / maxf(0.3, float(stage.visibility))
			if random.randf() < 1.0 - exp(-error_rate * km):
				var severity := random.randf()
				var terminal := severity > 0.8
				row.retired = terminal
				row.status = "Abandono — accidente" if terminal else "Salida de pista — recuperado"
				var loss := 0 if terminal else int(random.randf_range(5.0, 45.0) * 1000.0)
				seconds = seconds * random.randf() if terminal else seconds + float(loss) / 1000.0
				add_event(row, "crash" if terminal else "off_road", "driver", loss, severity, km * random.randf())
		row.time_ms = int(row.time_ms) + maxi(1, int(round(seconds * 1000.0)))
		if not row.retired:
			row.splits.append(row.time_ms)
	sector += 1

func retire_player(reason: String = "Abandono voluntario") -> void:
	if complete:
		return
	player_retired = true
	player_status = "No tomó la salida — decisión del jugador" if not started and player_ms == 0 and reason == "Abandono voluntario" else reason
	# No player observations after retirement: frozen reference and normal hazards.
	while sector < reference.size():
		advance_sector()
	finalize()

func finalize() -> void:
	if complete:
		return
	complete = true
	if not player_retired:
		player_status = "Completado"
	for row: Dictionary in rows:
		if not row.retired:
			row.status = "Completado" if row.events.is_empty() else "Completado — " + str(row.status)
	save()

func next_stage() -> bool:
	if not complete or player_retired:
		return false
	history.append(readout().duplicate(true))
	for row: Dictionary in rows:
		if not row.retired:
			previous_totals[row.id] = int(previous_totals.get(row.id, 0)) + int(row.time_ms)
		# Limited team service; retired cars remain retired.
		var service_budget := float(balance.service_seconds) * float(row.support)
		for component: String in balance.components:
			var repair := minf(1.0 - float(row.health[component]), minf(float(balance.service_repair) * float(row.support), service_budget / 1800.0))
			row.health[component] += repair
			service_budget -= repair * 1800.0
	player_previous_ms += player_ms + player_penalty_ms
	leg += 1
	var carried := rows.duplicate(true)
	begin_stage(carried)
	save()
	return true

func readout() -> Dictionary:
	var ordered: Array = []
	for row: Dictionary in rows:
		var result := row.duplicate(true)
		result.stage_ms = null if row.retired else int(row.time_ms)
		result.total_ms = null if row.retired else int(previous_totals.get(row.id, 0)) + int(row.time_ms)
		result.player = false
		ordered.append(result)
	ordered.append({"id": "player", "name": "Jugador", "car": "Ford Escort RS2000", "team": "Privado", "stage_ms": null if player_retired else player_ms + player_penalty_ms, "total_ms": null if player_retired else player_previous_ms + player_ms + player_penalty_ms, "retired": player_retired, "status": player_status, "player": true, "splits": player_splits.duplicate()})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.retired != b.retired:
			return not a.retired
		if a.total_ms != b.total_ms:
			return int(a.total_ms) < int(b.total_ms)
		return str(a.id) < str(b.id))
	var position := 0
	var previous_time: int = -1
	var previous_position: int = 0
	var player_position := 0
	var leader_ms: int = 0
	for row: Dictionary in ordered:
		if not row.retired:
			position += 1
			row.position = previous_position if int(row.total_ms) == previous_time else position
			previous_time = int(row.total_ms)
			previous_position = int(row.position)
			if position == 1:
				leader_ms = int(row.total_ms)
		else:
			row.position = 0
		if row.player:
			player_position = int(row.position)
	return {"rows": ordered, "sector": sector, "sector_count": reference.size(), "complete": complete, "leg": leg, "player_retired": player_retired, "player_position": player_position, "delta_ms": player_previous_ms + player_ms + player_penalty_ms - leader_ms, "confidence": confidence, "fallback": confidence == 0.0, "error": error}

func save() -> bool:
	if save_path.is_empty():
		return true
	var document := {"version": VERSION, "configuration_hash": configuration_hash, "stage_id": stage.id, "seed": seed_value, "leg": leg, "sector": sector, "initial_confidence": initial_confidence, "initial_level": initial_level, "level": level, "confidence": confidence, "complete": complete, "started": started, "rows": rows, "initial_rows": initial_rows, "player_ms": player_ms, "player_penalty_ms": player_penalty_ms, "player_retired": player_retired, "player_status": player_status, "player_splits": player_splits, "previous_totals": previous_totals, "player_previous_ms": player_previous_ms, "history": history}
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		error = "No se pudo guardar competición"
		return false
	file.store_string(JSON.stringify(document, "", true, true))
	file.close()
	var result := DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path + ".tmp"), ProjectSettings.globalize_path(save_path))
	if result != OK:
		error = "No se pudo reemplazar guardado"
	return result == OK

func restore() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var data := read_json(save_path)
	if int(data.get("version", -1)) != VERSION or data.get("stage_id", "") != stage.id:
		return false
	for key: String in ["leg", "sector", "level", "confidence", "complete", "rows", "initial_rows", "player_ms", "player_penalty_ms", "player_retired", "player_status", "player_splits", "previous_totals", "player_previous_ms", "history"]:
		if not data.has(key):
			return false
	if data.get("configuration_hash", "") != configuration_hash:
		error = "Guardado de otra versión de datos; se inicia una nueva competición"
		return false
	if not data.rows is Array or not data.initial_rows is Array or data.rows.size() != entries.size() or data.initial_rows.size() != entries.size():
		return false
	if int(data.sector) < 0 or int(data.sector) > reference.size() or not is_finite(float(data.level)) or float(data.level) <= 0.0:
		return false
	for collection: Array in [data.rows, data.initial_rows]:
		for i in collection.size():
			var row: Variant = collection[i]
			if not row is Dictionary or row.get("id", "") != entries[i].driver_id:
				return false
			for required: String in ["health", "splits", "events", "status", "retired", "time_ms", "ratings", "support", "vehicle_id", "start_status", "fatigue", "name", "car", "team"]:
				if not row.has(required):
					return false
			if not row.health is Dictionary or not row.splits is Array or not row.events is Array:
				return false
			for component: String in balance.components:
				if not row.health.has(component):
					return false
	seed_value = int(data.seed)
	leg = int(data.leg)
	sector = int(data.sector)
	level = float(data.level)
	initial_level = float(data.get("initial_level", level))
	initial_confidence = float(data.get("initial_confidence", 0.0))
	confidence = float(data.confidence)
	complete = bool(data.complete)
	started = bool(data.get("started", sector > 0))
	rows = data.rows
	initial_rows = data.initial_rows
	player_ms = int(data.player_ms)
	player_penalty_ms = int(data.player_penalty_ms)
	player_retired = bool(data.player_retired)
	player_status = data.player_status
	player_splits = data.player_splits
	previous_totals = data.previous_totals
	player_previous_ms = int(data.player_previous_ms)
	history = data.history
	return true
