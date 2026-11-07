extends SceneTree
const Sequence = preload("res://scripts/rally/rally_start_sequence.gd")
const Progress = preload("res://scripts/rally/rally_stage_progress.gd")
const Competition = preload("res://scripts/rally/rally_competition.gd")
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var sequence = Sequence.new()
	sequence.reset(Vector3.ZERO)
	check(sequence.readout().phase == "off", "both lights initially off")
	check(sequence.advance(0.49, Vector3.ZERO, 0.0).events.is_empty(), "dark interval")
	check(sequence.advance(0.01, Vector3.ZERO, 0.0).events == ["click"] and sequence.readout().phase == "ready", "red and first click at half second")
	check(sequence.advance(1.0, Vector3.ZERO, 0.0).events == ["click"], "second click")
	check(sequence.advance(1.0, Vector3.ZERO, 0.0).events == ["click"], "third click")
	var go: Dictionary = sequence.advance(1.0, Vector3.ZERO, 0.0)
	check(go.events == ["go"] and is_zero_approx(go.racing_dt) and sequence.readout().phase == "go", "horn and green exactly at go")
	check(is_equal_approx(sequence.advance(0.25, Vector3.ZERO, 0.0).racing_dt, 0.25), "stationary player clock advances after go")
	sequence.reset(Vector3.ZERO)
	check(sequence.advance(0.4, Vector3(0,0,-1), 3.0).events == ["false_start"], "false start even during dark interval")
	check(not "false_start" in sequence.advance(1.0, Vector3(0,0,-4), 3.0).events, "false start only once")
	sequence.reset(Vector3.ZERO)
	sequence.advance(3.4, Vector3.ZERO, 0.0)
	var crossing: Dictionary = sequence.advance(0.2, Vector3(0,0,-1), 5.0)
	check(not "false_start" in crossing.events and is_equal_approx(crossing.racing_dt, 0.1), "motion after green does not count as early; fractional frame clock")
	var course = Progress.new()
	course.points.assign([Vector3.ZERO, Vector3(0,0,-10), Vector3(0,0,-20)])
	course.radius_m = 1.0
	course.external_start = true
	course.generation = 0
	course.advance(Vector3(0,0,-11), 0.0, 0, 5.0)
	check(is_zero_approx(course.elapsed_s) and not course.running, "no timer before go even after moving")
	course.clock_started = true
	course.advance(Vector3(0,0,-11), 0.5, 0, 0.0)
	check(is_equal_approx(course.elapsed_s, 0.5) and course.running, "clock starts on go without movement or start radius")
	var sim = Competition.new()
	sim.save_path = ""
	check(sim.configure(), "competition configures")
	sim.add_penalty("player", 10000, "Salida anticipada")
	var opponent: String = sim.rows[0].id
	var initial_penalty: int = sim.rows[0].penalty_ms
	sim.add_penalty(opponent, 10000, "Control horario")
	sim.update({"splits": [{"time_ms": 19000}], "current_s": 19.0, "running": true})
	for row: Dictionary in sim.readout().rows:
		if row.player:
			check(row.penalty_ms == 10000 and row.partial_ms == 29000 and row.partial_index == 1, "HUD player partial includes penalty once")
		if row.id == opponent:
			check(row.penalty_ms == initial_penalty + 10000 and row.partial_ms == sim.rows[0].time_ms + row.penalty_ms, "opponent partial and sanction exposed")
	var total: int = sim.player_penalty_ms
	sim.update({"splits": [{"time_ms": 19000}], "current_s": 19.0, "running": true})
	check(sim.player_penalty_ms == total, "no repeated penalty on HUD update")
	sim.save_path = "user://rally_start_contract_test.json"
	check(sim.save(), "false-start penalty saved")
	var loaded = Competition.new()
	loaded.save_path = sim.save_path
	check(loaded.configure() and loaded.restore(), "penalty save restores")
	check(loaded.player_penalty_ms == 10000 and loaded.player_penalties[0].reason == "Salida anticipada", "penalty amount and cause persist")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sim.save_path))
	print("START_SEQUENCE_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)

