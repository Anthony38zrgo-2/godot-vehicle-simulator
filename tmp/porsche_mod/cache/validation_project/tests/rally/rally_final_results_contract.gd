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
	for abandon in [false, true]:
		var manager := TestEvent.new()
		check(manager.begin_event(), "begin event")
		for i in 9:
			manager.close_current_stage({"measured_ms": 180000, "penalty_ms": 0, "retired": false})
			check(manager.advance(), "advance through first nine stages")
		var scene = load("res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn").instantiate()
		scene.begin_event_session(manager, "russia_stage10")
		scene.weather_enabled = false
		root.add_child(scene)
		current_scene = scene
		for i in 600:
			await physics_frame
			if scene.session_ready:
				break
		check(scene.session_ready, "last stage session ready")
		if not scene.session_ready:
			quit(1)
			return
		if abandon:
			scene.retire_competition_player()
		else:
			scene.start_sequence.elapsed = 3.5
			scene.course.clock_started = true
			scene.course.finished = true
			scene.course.elapsed_s = 180.0
			for i in 10:
				scene.course.splits.append({"time_ms": (i + 1) * 18000})
			scene._physics_process(0.0)
		var panel = scene.head_up_display.competition_panel
		check(manager.status == "finished", "event closes automatically")
		check(manager.official.player.stages.size() == 10, "ten official results")
		check(panel.results.visible and panel.title.text == "RESULTADO FINAL · RALLY DE RUSIA", "final screen visible")
		check(not panel.next_button.visible and not panel.retry_button.visible, "no next stage or practice action")
		check(panel.table.columns == 7 and panel.table.get_root().get_child_count() == manager.standings().size(), "final classification rendered")
		check(panel.notice.text.contains("Ganador:"), "winner shown")
		var player = panel.table.get_root().get_first_child()
		while player != null and player.get_text(1) != "Jugador":
			player = player.get_next()
		check(player != null, "player in final ranking")
		if player != null:
			check(player.get_text(2) == panel.clock(manager.official.player.grand_total_ms), "official accumulated time shown")
			check(player.get_text(6) == str(manager.points_ledger.total.get("player", 0)), "total points shown")
		var ledger := JSON.stringify(manager.points_ledger)
		scene.apply_competition_controls()
		await scene.continue_competition()
		check(JSON.stringify(manager.points_ledger) == ledger, "repeated finish cannot award again")
		check(scene.session_track_id == "russia_stage10", "no stage eleven")
		var empty_state: Dictionary = scene.get_competition_panel_state()
		empty_state.event_final_rows = []
		empty_state.event_points = {"winner": ""}
		panel.present(empty_state, Vector2(1280, 720))
		check(panel.notice.text.contains("sin participantes clasificados"), "no winner when no classified participants")
		scene.queue_free()
		await process_frame
	print("RALLY_FINAL_RESULTS_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
