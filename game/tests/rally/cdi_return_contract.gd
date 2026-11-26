extends SceneTree

const SERVICE := preload("res://scripts/rally/rally_service_panel.gd")
const EventManager := preload("res://scripts/rally/rally_event_manager.gd")
const RallyCompetition := preload("res://scripts/rally/rally_competition.gd")
const STEP_S := 0.05
const SPEED_M_S := 20.0


func _verify() -> void:
	var event := EventManager.new()
	if not _require(event.begin_event({
		"event_path": "cdi", "start_stage_id": "cdi_stage4", "save_path": "", "seed": 19, "setup_accepted": true,
	}), "Could not start CDI at SS04: " + event.error):
		return
	var session := (load("res://scenes/rally/cdi_stage4.tscn") as PackedScene).instantiate() as RallyRussiaStageSession
	session.begin_event_session(event, "cdi_stage4")
	root.add_child(session)
	if not _require(await _wait_for_stage(session, "cdi_stage4"), "Failed to load SS04"):
		return
	session.set_physics_process(false)
	if not _require(_drive_finish(session.course, session.competition), "SS04 finish did not register"):
		return
	session.apply_competition_controls()
	var track := session.get_node("TrackCollision") as RallyTrackCollisionBuilder
	if await _verify_return(session, event, track):
		quit()


func _initialize() -> void:
	call_deferred("_verify")


func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok


func _advance(course: RallyStageProgress, competition: RallyCompetition, point: Vector3) -> void:
	course.advance(point, STEP_S, course.generation, SPEED_M_S)
	competition.update(course.readout())


func _drive_finish(course: RallyStageProgress, competition: RallyCompetition) -> bool:
	course.external_start = true
	_advance(course, competition, course.points[0])
	course.clock_started = true
	for i in range(1, course.points.size()):
		var a := course.points[i - 1]
		var b := course.points[i]
		var steps := maxi(1, ceili(a.distance_to(b)))
		for j in range(1, steps + 1):
			_advance(course, competition, a.lerp(b, float(j) / steps))
	var gate: Dictionary = course.timing_gates[-1]
	_advance(course, competition, gate.origin + gate.forward)
	return course.finished and competition.complete and course.splits.size() == 4


func _wait_for_stage(session: RallyRussiaStageSession, stage_id: String) -> bool:
	for i in range(1800):
		if session.session_track_id == stage_id and session.session_ready and not session.stage_transition_running:
			return true
		await process_frame
	return false


func _road_at(track: RallyTrackCollisionBuilder, point: Vector3) -> StaticBody3D:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP, track.collision_layer)
	return track.get_world_3d().direct_space_state.intersect_ray(query).get("collider") as StaticBody3D


func _verify_return(session: RallyRussiaStageSession, event: RallyEventManager,
		track: RallyTrackCollisionBuilder) -> bool:
	var starts := ["16:30", "17:00", "17:55", "18:25"]
	var panel = session.head_up_display.competition_panel
	for stage_number in range(5, 9):
		var stage_id := "cdi_stage%d" % stage_number
		var expected_map := "cdi_stage%d" % (9 - stage_number)
		var has_service := stage_number in [5, 7]
		if not _require(panel.next_button.visible and panel.next_button.text.contains("SERVICIO") == has_service,
				"Incorrect continue action before " + stage_id):
			return false
		panel.next_button.pressed.emit()
		if not _require(await _wait_for_stage(session, stage_id), "Failed to load " + stage_id):
			return false
		if not _require(session.map_id == expected_map and session.awaiting_setup == has_service
				and event.schedule_for(stage_id).get("base_start") == starts[stage_number - 5],
				"Wrong map, service state or schedule for " + stage_id):
			return false
		if has_service:
			var service: Node
			for child in session.get_children():
				if child.get_script() == SERVICE:
					service = child
					break
			var window := event.get_pending_window()
			if not _require(service != null and session.vehicle.freeze and window.get("repair_minutes") == 30,
					"Expected a 30-minute service before " + stage_id):
				return false
			service.get("commit").pressed.emit()
			for i in range(180):
				if session.garage_panel.visible:
					break
				await process_frame
			if not _require(session.garage_panel.visible, "Service did not open the garage"):
				return false
			session.garage_panel.close_garage(true)
			if not _require(not session.awaiting_setup and event.get_pending_window().is_empty(),
					"Service did not release " + stage_id):
				return false
		await physics_frame
		var course := session.course
		var source := session.map_course
		var start := session.stage_markers.get_node_or_null("StartMarker") as Node3D
		if not _require(start != null and start.position.is_equal_approx(source.timing_gates[-1].origin)
				and course.points[0].is_equal_approx(source.points[-1]) and _road_at(track, session.start_position) != null,
				"Reverse start is not on the original finish road: " + stage_id):
			return false
		for i in range(course.timing_gates.size() - 1):
			var gate: Dictionary = course.timing_gates[i]
			var original: Dictionary = source.timing_gates[source.timing_gates.size() - 2 - i]
			if not _require(gate.origin.is_equal_approx(original.origin)
					and gate.forward.is_equal_approx(-original.forward),
					"Reverse timing gate out of order: " + stage_id):
				return false
		if not await _verify_signs(session, stage_number == 5):
			return false
		if not _require(_drive_finish(course, session.competition), "Reverse finish did not register: " + stage_id):
			return false
		session.apply_competition_controls()
	if not _require(event.status == "finished" and event.official.get("player", {}).get("stages", {}).size() == 5,
			"Expected an official result for SS04 through SS08"):
		return false
	print("CDI_RETURN_OK")
	return true


func _verify_signs(session: RallyRussiaStageSession, has_ticlio_panel: bool) -> bool:
	var signs := session.get_node("TiclioRoadSigns")
	var bodies: Array[RigidBody3D] = []
	for child in signs.get_children():
		if child is RigidBody3D and child.has_meta("sign_impact"):
			bodies.append(child)
	var placed: Array = signs.get_meta("placed_signs")
	if not _require(bodies.size() == placed.size() + int(has_ticlio_panel), "Missing sign collision body"):
		return false
	var preview := Node3D.new()
	signs.add_child(preview)
	for i in bodies.size():
		var body := bodies[i]
		var impact: Callable = body.get_meta("sign_impact", Callable())
		if not _require(impact.is_valid(), "Sign has no release handler"):
			return false
		if has_ticlio_panel and i == 0:
			if not _require(body.get_child_count() == 5, "Ticlio panel needs panel, posts and pedestals"):
				return false
		else:
			var sign: Dictionary = placed[i - int(has_ticlio_panel)]
			var model: Node3D = signs._spawn_model(preview, body.global_transform, sign)
			var back := model.get_child(1) as MeshInstance3D
			if not _require(back != null and is_equal_approx(back.rotation.y, PI)
					and back.mesh.material.get_shader_parameter("front_mask") != null,
					"Missing textured rear for " + str(sign.face)):
				return false
		var direction := body.global_basis.z
		var point := body.global_position + Vector3.UP
		if not _require(impact.call(3.0, 150.0, direction, point, true) == 0.0
				and impact.call(9.0, 150.0, direction, point, true) > 0.0
				and impact.call(9.0, 150.0, direction, point, true) == 0.0,
				"Sign threshold or duplicate-hit guard failed"):
			return false
	preview.queue_free()
	await physics_frame
	await physics_frame
	var fallen := 0
	for child in signs.get_children():
		if child is RigidBody3D and child.get_meta("collision_role", "") == "fallen_sign":
			fallen += 1
	return _require(fallen == bodies.size(), "Some signs did not become rigid bodies")
