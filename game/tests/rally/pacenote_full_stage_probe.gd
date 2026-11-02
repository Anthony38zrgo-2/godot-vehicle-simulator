extends SceneTree

const Controller = preload("res://scripts/rally/rally_pacenote_controller.gd")
const Hud = preload("res://scripts/rally/cmr2_pacenote_hud.gd")

func _initialize() -> void:
	var ctrl = Controller.new()
	root.add_child(ctrl)
	assert(ctrl.configure("res://data/rally/pacenotes/russia_stage1.json"))
	var hud = Hud.new()
	root.add_child(hud)
	ctrl.set_hud(hud)

	var file := FileAccess.open("res://data/rally/russia_stage1_route.json", FileAccess.READ)
	assert(file != null)
	var doc: Dictionary = JSON.parse_string(file.get_as_text())
	var points: Array = doc.get("points", [])
	assert(points.size() == 493)

	var triggered_indices: Array[int] = []
	ctrl.call_triggered.connect(func(call_idx: int, _word: int):
		if not call_idx in triggered_indices:
			triggered_indices.append(call_idx)
	)

	var total_steps := 0
	var hud_rendered_count := 0

	# Simulate driving along all 493 points
	# Interpolate 4 sub-steps per ~10m segment to simulate 40 m/s (~144 km/h) driving
	var prev_pos = Vector3(float(points[0][0]), float(points[0][1]), float(points[0][2]))
	for i in range(1, points.size()):
		var target_pos = Vector3(float(points[i][0]), float(points[i][1]), float(points[i][2]))
		for step in range(1, 5):
			var frac := float(step) / 4.0
			var current_pos := prev_pos.lerp(target_pos, frac)
			ctrl.advance(current_pos, 0.05)
			total_steps += 1
			if hud.primary_rect != null and hud.primary_rect.visible:
				hud_rendered_count += 1
		prev_pos = target_pos

	print("Full stage traverse complete: total_steps=", total_steps, " gates_reached=", ctrl.tracker.next_gate, "/", ctrl.tracker.gates.size())
	print("Curve pacenote calls triggered: ", triggered_indices.size(), " / ", ctrl.call_table.size())
	print("HUD render frames with active icon: ", hud_rendered_count)
	print("Total audio samples played: ", ctrl.speech_queue.total_samples_played)

	assert(ctrl.tracker.next_gate >= 490) # Reached finish!
	assert(triggered_indices.size() == 32) # All 32 curve calls triggered across stage!
	assert(ctrl.speech_queue.total_samples_played >= 80) # Audio played throughout stage
	assert(hud_rendered_count > 100) # HUD presented visual icons during run

	ctrl.queue_free()
	hud.queue_free()
	print("PACENOTE_FULL_STAGE_PROBE PASS")
	quit()
