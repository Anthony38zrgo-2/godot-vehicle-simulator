extends SceneTree
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn").instantiate()
	scene.competition.save_path = ""
	root.add_child(scene)
	current_scene = scene
	for i in 600:
		await physics_frame
		if scene.session_ready:
			break
	check(scene.session_ready, "session ready")
	if not scene.session_ready:
		quit(1)
		return
	var panel = scene.head_up_display.competition_panel
	check(scene.input_controller.controls_enabled, "prestage driving enabled")
	var preparation := JSON.stringify(scene.competition.initial_rows)
	panel.retire_requested.emit()
	await process_frame
	await process_frame
	check(scene.competition.complete and scene.competition.player_retired, "retire UI simulates field")
	check(scene.vehicle.freeze and not scene.input_controller.controls_enabled, "results stop driving")
	check(panel.results.visible and panel.table.get_root().get_child_count() == 24, "six-column results include player and field")
	panel.retry_requested.emit()
	await physics_frame
	await process_frame
	check(not scene.competition.complete and scene.input_controller.controls_enabled, "practice retry restores controls")
	check(JSON.stringify(scene.competition.initial_rows) == preparation, "retry preserves DNS preparation")
	var elapsed := 0
	for i in 10:
		elapsed += int(scene.competition.reference[i] * 1000.0)
		scene.course.splits.append({"time_ms": elapsed})
	scene.course.elapsed_s = elapsed / 1000.0
	scene.course.finished = true
	await physics_frame
	await physics_frame
	await process_frame
	check(scene.competition.complete and not scene.competition.player_retired, "course finish completes field")
	check(scene.competition.player_ms == elapsed, "official player finish retained")
	panel.next_requested.emit()
	await physics_frame
	await process_frame
	check(scene.competition.leg == 2 and scene.competition.player_previous_ms == elapsed, "next UI carries total")
	check(not scene.competition.complete and not scene.course.finished, "next UI resets course")
	panel.new_rally_requested.emit()
	await physics_frame
	await process_frame
	check(scene.competition.leg == 1 and scene.competition.player_previous_ms == 0, "new rally clears accumulated total")
	scene.course.running = true
	scene.course.next_checkpoint = 5
	scene.course.elapsed_s = 12.0
	scene.on_vehicle_reset_requested()
	check(scene.course.next_checkpoint == 5 and is_equal_approx(scene.course.elapsed_s, 12.0), "rescue preserves checkpoint and official clock")
	check(scene.competition.player_penalty_ms == 30000 and not scene.competition.player_retired, "rescue applies one penalty without retirement")
	print("COMPETITION_SESSION_CONTRACT ", "PASS" if failures.is_empty() else failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
