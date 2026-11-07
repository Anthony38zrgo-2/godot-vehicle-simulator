extends SceneTree
const Competition = preload("res://scripts/rally/rally_competition.gd")
const Progress = preload("res://scripts/rally/rally_stage_progress.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func make(seed_number: int = 1974):
	var sim = Competition.new()
	sim.save_path = ""
	check(sim.configure("res://data/competition/stages/russia_stage1.json", seed_number), "catalog configures")
	return sim
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var sim = make()
	check(sim.rows.size() == 23 and sim.reference.size() == 10, "complete field and fallback")
	var first = make()
	first.retire_player()
	check(first.complete and first.sector == 10 and first.player_retired, "retirement before first split simulates remainder")
	check(first.confidence == 0.0 and first.readout().fallback, "early retirement uses original fallback")
	var second = make()
	second.retire_player()
	check(JSON.stringify(first.rows) == JSON.stringify(second.rows), "deterministic simulation")
	second.reset_attempt()
	second.retire_player()
	check(JSON.stringify(first.rows) == JSON.stringify(second.rows), "practice cannot reroll preparation or incidents")
	var splits: Array = []
	var time_ms := 0
	for i in 10:
		time_ms += int(float(sim.reference[i]) * 1050.0)
		splits.append({"time_ms": time_ms})
		sim.update({"splits": splits, "current_s": time_ms / 1000.0, "finished": i == 9})
		if i == 0:
			check(sim.level > 1.0 and sim.level <= 1.02, "adaptation bounded")
	check(sim.complete and sim.player_ms == time_ms, "finish preserves player clock")
	var frozen := JSON.stringify(sim.rows)
	sim.update({"splits": splits, "current_s": 9999.0, "finished": true})
	check(JSON.stringify(sim.rows) == frozen, "finish idempotent")
	var observed = make()
	observed.update({"splits": [{"time_ms": 600000}], "current_s": 600.0, "finished": false})
	check(is_equal_approx(observed.level, 1.0), "long stop does not slow field")
	var committed = make()
	committed.update({"splits": [{"time_ms": 19000}], "current_s": 19.0, "finished": false})
	var old_times: Array = []
	for row: Dictionary in committed.rows:
		old_times.append(row.splits.duplicate())
	committed.retire_player()
	for i in committed.rows.size():
		if not old_times[i].is_empty():
			check(committed.rows[i].splits[0] == old_times[i][0], "published partial unchanged")
	check(not committed.next_stage(), "retired player cannot continue rally")
	var saved_total: int = sim.player_ms
	check(sim.next_stage(), "next special available after finish")
	check(sim.leg == 2 and sim.player_previous_ms == saved_total and sim.sector == 0, "accumulated time carried once")
	sim.save_path = "user://competition_contract_test.json"
	check(sim.save(), "atomic save")
	var loaded = make()
	loaded.save_path = sim.save_path
	check(loaded.restore(), "load saved rally")
	check(JSON.parse_string(JSON.stringify(loaded.rows, "", true, true)) == JSON.parse_string(JSON.stringify(sim.rows, "", true, true)) and loaded.player_previous_ms == saved_total, "save roundtrip")
	var comparable = make()
	comparable.save_path = ""
	comparable.leg = sim.leg
	comparable.level = sim.level
	comparable.rows = sim.rows.duplicate(true)
	comparable.retire_player()
	loaded.retire_player()
	for n in comparable.rows.size():
		var expected: Dictionary = comparable.rows[n]
		var actual: Dictionary = loaded.rows[n]
		check(expected.time_ms == actual.time_ms and expected.status == actual.status and expected.splits == actual.splits, "load preserves subsequent official times and status")
		check(expected.events.size() == actual.events.size(), "load preserves incident count")
		for e in expected.events.size():
			check(expected.events[e].type == actual.events[e].type and expected.events[e].component == actual.events[e].component and expected.events[e].loss_ms == actual.events[e].loss_ms, "load preserves incident outcome")
		for component: String in expected.health:
			check(is_equal_approx(float(expected.health[component]), float(actual.health[component])), "load preserves health")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sim.save_path))
	var micro = make()
	var samples: Array = []
	var sample_ms := 0
	for i in 40:
		sample_ms += int(float(micro.stage.checkpoint_reference_s[i]) * 1200.0)
		samples.append({"index": i + 1, "time_ms": sample_ms})
	micro.update({"checkpoint_times": samples, "splits": [], "running": true})
	check(micro.confidence > 0.0 and micro.level > 1.0, "clean microsections inform early retirement before visible split")
	var shuffled = make()
	shuffled.rows.reverse()
	shuffled.retire_player()
	check(shuffled.readout().rows == first.readout().rows, "entry order does not change random outcomes")
	# Sweep crosses several mandatory controls in one physics frame.
	var course = Progress.new()
	course.points.assign([Vector3.ZERO, Vector3(10,0,0), Vector3(20,0,0), Vector3(30,0,0)])
	course.radius_m = 1.0
	course.sector_indices = [1,2,3]
	course.advance(Vector3.ZERO, 0.0, 0, 30.0)
	course.advance(Vector3(35,0,0), 1.0, 0, 35.0)
	check(course.finished and course.splits.size() == 3, "swept checkpoints at speed")
	check(course.splits[0].time_ms < course.splits[1].time_ms and course.splits[1].time_ms < course.splits[2].time_ms, "distinct interpolated crossing timestamps")
	var cut = Progress.new()
	cut.points.assign([Vector3.ZERO, Vector3(10,0,0), Vector3(20,0,0)])
	cut.radius_m = 1.0
	cut.advance(Vector3.ZERO, 0.0, 0, 20.0)
	cut.advance(Vector3(20,0,10), 1.0, 0, 20.0)
	check(not cut.finished and cut.next_checkpoint == 1, "shortcut cannot skip mandatory control")
	# Many seeds exercise real DNS, recoverable and terminal incident paths.
	var dns := false
	var dnf := false
	var damaged := false
	for seed_number in range(1000):
		var batch = make(seed_number)
		batch.retire_player()
		for row: Dictionary in batch.rows:
			dns = dns or row.start_status == "dns"
			for event: Dictionary in row.events:
				dnf = dnf or event.type in ["mechanical_dnf", "crash"]
				damaged = damaged or event.type == "damage"
			if row.retired:
				for result: Dictionary in batch.readout().rows:
					if result.id == row.id:
						check(result.stage_ms == null and result.total_ms == null and result.position == 0, "retired entries have no fabricated final time")
	check(dns and dnf and damaged, "batch covers DNS, terminal and recoverable incidents")
	print("COMPETITION_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
