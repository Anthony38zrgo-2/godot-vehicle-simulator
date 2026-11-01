extends SceneTree
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
	var sim = Competition.new()
	sim.save_path = ""
	check(sim.configure(), "stage data loads")
	var course = Progress.new()
	check(course.configure(sim.stage.route_path), "official reset route loads")
	check(course.configure_timing_gates(sim.stage.timing_gates), "original trigger planes load")
	check(course.points.size() == 494, "route extended to actual finish plane")
	course.external_start = true
	course.generation = 0
	course.clock_started = true
	course.previous_position = course.points[0] + Vector3.UP * 0.4
	var published := 0
	for i in range(1, course.points.size()):
		var position: Vector3 = course.points[i] + Vector3.UP * 0.4
		# A legitimate line outside the former 8 m reset-node radius, then rejoin.
		if i >= 10 and i <= 20:
			position.x += 12.0
		course.advance(position, 0.25, 0, 60.0)
		sim.update(course.readout())
		if course.splits.size() > published:
			check(sim.sector == course.splits.size(), "crossing publishes AI sector immediately")
			print("ORIGINAL_SPLIT ", course.splits[-1])
			published = course.splits.size()
		if i == 492:
			check(not course.finished and course.splits.size() == 9, "reset endpoint is not premature finish")
	var last: Vector3 = course.points[-1]
	var forward: Array = sim.stage.timing_gates[-1].forward
	course.advance(last + Vector3(float(forward[0]), float(forward[1]), float(forward[2])) * 4.0 + Vector3.UP * 0.4, 0.1, 0, 60.0)
	sim.update(course.readout())
	check(course.splits.size() == 10 and course.finished and sim.complete, "nine real signs plus real finish detected")
	check(course.splits[0].gate_id == "split_00" and course.splits[-1].gate_id == "split_09", "original gate identities retained")
	for i in range(1, course.splits.size()):
		check(course.splits[i].time_ms > course.splits[i-1].time_ms, "official split times strictly increasing")
	var count: int = course.splits.size()
	course.advance(last, 1.0, 0, 60.0)
	check(course.splits.size() == count, "finish cannot count twice")
	var skipped = Progress.new()
	skipped.configure(sim.stage.route_path)
	skipped.configure_timing_gates(sim.stage.timing_gates)
	skipped.external_start = true
	skipped.clock_started = true
	skipped.generation = 0
	skipped.previous_position = skipped.points[0]
	skipped.advance(skipped.points[100], 0.1, 0, 30.0)
	check(skipped.splits.is_empty() and skipped.route_progress_m < 40.0, "teleport cannot award a split")
	print("OFFICIAL_SPLIT_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
