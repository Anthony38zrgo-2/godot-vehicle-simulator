extends SceneTree

class TestEvent:
	extends "res://scripts/rally/rally_event_manager.gd"
	func save() -> bool:
		return true

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var manager := TestEvent.new()
	check(manager.begin_event(), "event begins")
	var scene = load("res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn").instantiate()
	scene.begin_event_session(manager, "russia_stage1")
	scene.weather_enabled = false
	root.add_child(scene)
	current_scene = scene
	for i in 600:
		await physics_frame
		if scene.session_ready:
			break
	check(scene.session_ready, "initial session ready")
	if not scene.session_ready:
		quit(1)
		return
	for index in range(2, 11):
		var old_visual: WeakRef = weakref(scene.track_visual.get_child(0))
		var old_body: WeakRef = weakref(scene.track_collision.get_child(0))
		# A completed previous stage must not finish the next at the green light.
		scene.course.finished = true
		scene.course.elapsed_s = 180.0
		scene.course.splits.clear()
		for split in 10:
			scene.course.splits.append({"time_ms": (split + 1) * 18000})
		scene.retire_competition_player()
		await scene.continue_competition()
		var expected := "russia_stage%d" % index
		check(scene.session_ready, "session ready after transition")
		check(scene.session_track_id == expected, "correct active stage")
		check(scene.competition.stage.id == expected, "correct timing config")
		check(not scene.course.finished and scene.course.splits.is_empty(), "previous finish and splits cleared")
		check(is_zero_approx(scene.course.elapsed_s) and scene.course.next_timing_gate == 0, "fresh clock and timing controls")
		check(scene.track_visual.get_child_count() == 1, "only one visual loaded")
		check(scene.track_visual.get_child(0).scene_file_path.ends_with(expected + "_visual.glb"), "own visual GLB")
		check(old_visual.get_ref() == null and old_body.get_ref() == null, "old visual and collision freed")
		check(scene.track_collision.collision_scene_path.ends_with(expected + "_collision.glb"), "own collision GLB")
		check(scene.track_collision.generated_body_count == scene.track_collision.get_child_count(), "no stale collision bodies")
		check(scene.input_controller.controls_enabled and not scene.vehicle.freeze, "controls resumed")
		check(scene.start_position.distance_to(scene.vehicle.global_position) < 5.0, "vehicle at new spawn")
		check(manager.official.player.stages.size() == index - 1, "results carried once")
		var schedule: Dictionary = manager.schedule_for(expected)
		var parts: PackedStringArray = str(schedule.start).split(":")
		var scheduled_seconds := int(parts[0]) * 3600 + int(parts[1]) * 60
		check(absf(scene.event_clock.event_seconds - scheduled_seconds + 5) < 1.0, "next scheduled time")
		for frame in 720:
			await physics_frame
			if scene.competition.complete:
				break
		print("STAGE_START_PROBE stage=", index, " position=", scene.vehicle.global_position, " status=", scene.competition.player_status)
		check(not scene.competition.complete, "no automatic retirement after countdown stage %d" % index)
	scene.retire_competition_player()
	await scene.continue_competition()
	await scene.continue_competition()
	check(manager.status == "finished" and scene.session_track_id == "russia_stage10", "final stage closes without reload")
	check(manager.official.player.stages.size() == 10, "ten unique official results")
	scene.queue_free()
	await process_frame
	print("RUSSIA_STAGE_TRANSITION_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
