extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var total := 0
	for stage in range(2, 11):
		var id := "russia_stage%d" % stage
		var notes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rally/pacenotes/%s.json" % id))
		var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rally/%s_route.json" % id))
		var tracker := PacenoteGateTracker.new()
		assert(tracker.configure(notes.gates), id + " gates configure")
		var points: Array[Vector3] = []
		for p in route.points:
			points.append(Vector3(p[0], p[1], p[2]))
		var previous := points[0] - (points[1] - points[0]).normalized()
		var seen: Array[int] = []
		for target in points:
			var origin := previous
			var steps := maxi(1, ceili(origin.distance_to(target) / 2.0))
			for step in range(1, steps + 1):
				var position := origin.lerp(target, float(step) / steps)
				for crossing in tracker.advance(previous, position):
					assert(not crossing.has("skipped_indices"), id + " skipped gates")
					seen.append(int(crossing.gate.call_index))
				previous = position
		assert(seen.size() == notes.calls.size(), id + " missing calls")
		for index in seen.size():
			assert(seen[index] == index, id + " unordered or duplicate calls")
		total += seen.size()
		print(id, " PASS calls=", seen.size())
	print("PACENOTE_IMPORT_TRAVERSAL PASS calls=", total)
	quit()
