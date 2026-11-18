extends SceneTree

const TRACK := "cdi_stage1"
const RallyCompetition = preload("res://scripts/rally/rally_competition.gd")
const STEP_S := 0.05
const SPEED_M_S := 20.0


func _initialize() -> void:
	call_deferred("_verify")


func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok


func _advance(course: RallyStageProgress, competition: RallyCompetition, point: Vector3) -> void:
	course.advance(point, STEP_S, 1, SPEED_M_S)
	competition.update(course.readout())


func _verify() -> void:
	var session := (load("res://scenes/rally/cdi_stage1.tscn") as PackedScene).instantiate()
	root.add_child(session)
	for i in range(1800):
		await physics_frame
		if session.has_node("StageGrass"):
			break
	if not _require(session.has_node("StageGrass"), "Rajuntay session did not finish loading"):
		return
	await physics_frame
	await physics_frame
	var track := session.get_node("TrackCollision") as RallyTrackCollisionBuilder
	var loader := RallyStageLoader.new()
	var resolved := loader.resolve(TRACK)
	var source: Dictionary = resolved.manifest.source
	var end_pk := float(source.source_pk_m[-1])
	var finish_pk := float(source.timed_source_pk_m[-1])
	if not _require(end_pk > 5156.0 and is_equal_approx(end_pk - finish_pk, 50.0),
			"Expected full SS01 geometry and 50 m beyond the timing line"):
		return
	var route_path: String = resolved.paths.route
	var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(route_path))
	var gates: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(resolved.paths.timing_gates))
	var course := RallyStageProgress.new()
	var competition := RallyCompetition.new()
	competition.save_path = ""
	if not _require(course.configure(route_path) and course.configure_timing_gates(gates.gates)
			and competition.configure(resolved.paths.stage_config, 1), "Timing data failed to load"):
		return
	var finish: Dictionary = course.timing_gates[-1]
	var origin: Vector3 = finish.origin
	var forward: Vector3 = finish.forward
	var right: Vector3 = finish.right
	if not _require(course.route_distances[-1] > 4900.0 and finish.kind == "finish"
			and int(finish.route_index) == course.points.size() - 1
			and origin.distance_to(course.points[-1]) < 0.01
			and absf(float(finish.route_distance_m) - course.route_distances[-1]) < 0.01,
			"Finish gate is not at the final timed point"):
		return
	for label in ["Meta_L", "Meta_R"]:
		var board := session.find_child(label, true, false) as MeshInstance3D
		if not _require(board != null and absf((board.to_global(board.get_aabb().get_center()) - origin).dot(forward)) < 0.01,
				"Finish boards are not aligned with the timing plane"):
			return

	# Follow the entire route in roughly one-metre steps. Both timing layers
	# must stay open through the last approach inside the checkpoint radius.
	course.external_start = true
	_advance(course, competition, course.points[0])
	course.clock_started = true
	for i in range(1, course.points.size() - 1):
		var a := course.points[i - 1]
		var b := course.points[i]
		var steps := maxi(1, ceili(a.distance_to(b)))
		for j in range(1, steps + 1):
			_advance(course, competition, a.lerp(b, float(j) / steps))
			if not _require(not course.finished and not competition.complete, "SS01 ended before the finish plane"):
				return
	_advance(course, competition, origin - forward * 0.10)
	if not _require(not course.finished and not competition.complete and course.splits.size() == 3,
			"SS01 finished inside the approach radius"):
		return

	var side := right * (float(finish.half_width_m) + 3.0)
	_advance(course, competition, origin - forward + side)
	_advance(course, competition, origin + forward + side)
	_advance(course, competition, origin + forward)
	_advance(course, competition, origin - forward)
	if not _require(not course.finished and not competition.complete,
			"A crossing outside the gate or against its direction ended SS01"):
		return
	var before_s := course.elapsed_s
	_advance(course, competition, origin + forward)
	if not _require(course.finished and competition.complete and course.splits.size() == 4
			and course.splits[-1].gate_id == "finish"
			and absf(course.elapsed_s - (before_s + STEP_S * 0.5)) <= 0.001,
			"SS01 did not register the actual swept finish crossing"):
		return

	var space := track.get_world_3d().direct_space_state
	var runout: Array = route.runout_probes
	if not _require(runout.size() >= 6, "Missing post-finish road samples"):
		return
	var last_sample := Vector3.ZERO
	for xyz: Array in runout:
		var point := Vector3(xyz[0], xyz[1], xyz[2])
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP, track.collision_layer)
		var hit := space.intersect_ray(query)
		if not _require(not hit.is_empty() and hit.collider.is_in_group("Gravel"), "Missing gravel after the finish"):
			return
		last_sample = point
	if not _require(last_sample.distance_to(origin) > 44.0, "Gravel ends too soon after the finish"):
		return
	print("CDI_FINISH_OK race_m=", course.route_distances[-1], " runout_probes=", runout.size())
	session.queue_free()
	await process_frame
	quit()
