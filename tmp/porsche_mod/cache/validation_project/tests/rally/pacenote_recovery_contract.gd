extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for stage in range(1, 11):
		var controller := RallyPacenoteController.new()
		root.add_child(controller)
		assert(controller.configure("res://data/rally/pacenotes/russia_stage%d.json" % stage))
		var seen: Array[int] = []
		controller.call_triggered.connect(func(index: int, _word: int): seen.append(index))
		var points := controller.route_points
		controller.advance(points[0], 0.01)
		controller.advance(points[0] + Vector3(0, 100, 0), 0.01)
		assert(controller.off_route)
		assert(controller.call_queue.is_empty())
		var middle := points.size() / 2
		controller.advance(points[middle] + Vector3(0, 100, 0), 0.01)
		controller.advance(points[middle], 0.01)
		assert(not controller.off_route)
		assert(seen.is_empty(), "re-entry must not replay missed calls")
		var previous := points[middle]
		for i in range(middle + 1, points.size()):
			var origin := previous
			var steps := maxi(1, ceili(origin.distance_to(points[i]) / 2.0))
			for step in range(1, steps + 1):
				var position := origin.lerp(points[i], float(step) / steps)
				controller.advance(position, 0.1)
				previous = position
		assert(not seen.is_empty(), "calls resume after re-entry")
		for i in range(1, seen.size()):
			assert(seen[i] > seen[i - 1], "no duplicate or backwards calls")
		var count := seen.size()
		controller.advance(points[0], 0.01)
		controller.advance(points[1], 0.01)
		assert(seen.size() == count, "backwards teleport must not replay calls")
		controller.free()
		print("RECOVERY stage=", stage, " PASS resumed=", count)
	print("PACENOTE_RECOVERY_CONTRACT PASS")
	quit()
