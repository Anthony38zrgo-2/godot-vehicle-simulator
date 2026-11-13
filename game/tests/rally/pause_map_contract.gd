extends SceneTree

var failures: Array[String] = []

func check(ok: bool, label: String = "") -> void:
	if not ok:
		var msg := label if not label.is_empty() else "pause_map_contract assertion failed"
		failures.append(msg)
		push_error(msg)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn").instantiate()
	scene.practice_mode = true
	scene.competition.save_path = ""
	scene.weather_enabled = false
	root.add_child(scene)
	current_scene = scene
	for i in 600:
		await process_frame
		if scene.session_ready:
			break
	check(scene.session_ready, "scene.session_ready")
	scene.set_physics_process(false)
	scene.vehicle.freeze = true
	var panel: Node
	for child in scene.get_children():
		if child.get_script() == load("res://scripts/rally/rally_pause_inventory.gd"):
			panel = child
	check(panel != null, "pause panel present")
	var menu_press := InputEventJoypadButton.new()
	menu_press.button_index = JOY_BUTTON_START
	menu_press.pressed = true
	check(menu_press.is_action_pressed(InputBindings.UI_BACK_TO_MENU), "JOY_BUTTON_START maps to UI_BACK_TO_MENU")
	check(not menu_press.is_action_pressed(InputBindings.TOGGLE_GARAGE), "JOY_BUTTON_START does not map to TOGGLE_GARAGE")
	Input.parse_input_event(menu_press)
	Input.flush_buffered_events()
	await process_frame
	check(paused and panel.modal.visible, "start pauses and opens modal")
	check(not scene.garage_panel.visible, "garage panel stays closed on pause")
	var handbrake_press := InputEventJoypadButton.new()
	handbrake_press.button_index = JOY_BUTTON_LEFT_SHOULDER
	handbrake_press.pressed = true
	check(handbrake_press.is_action_pressed(InputBindings.HANDBRAKE), "LB maps to HANDBRAKE")
	check(not handbrake_press.is_action_pressed(InputBindings.CLUTCH), "LB does not map to CLUTCH")
	var menu_release := InputEventJoypadButton.new()
	menu_release.button_index = JOY_BUTTON_START
	Input.parse_input_event(menu_release)
	Input.parse_input_event(menu_press)
	Input.flush_buffered_events()
	await process_frame
	check(not paused and not panel.modal.visible, "second start resumes and hides modal")
	Input.parse_input_event(handbrake_press)
	Input.flush_buffered_events()
	scene.input_controller._physics_process(0.1)
	check(scene.vehicle.handbrake_input == 1.0, "handbrake pressed sets input to 1.0")
	var handbrake_release := InputEventJoypadButton.new()
	handbrake_release.button_index = JOY_BUTTON_LEFT_SHOULDER
	Input.parse_input_event(handbrake_release)
	Input.flush_buffered_events()
	scene.input_controller._physics_process(0.1)
	check(scene.vehicle.handbrake_input == 0.0, "handbrake release resets input to 0.0")
	Input.parse_input_event(menu_release)
	panel.pause_button.pressed.emit()
	check(paused and panel.modal.visible, "pause button opens modal")
	var buttons: Dictionary = {}
	for child in panel.content.get_children():
		if child is Button:
			buttons[child.text] = child
	check(buttons.has("Pedir rescate") and buttons.has("Abandonar etapa"), "pause menu shows rescue and abandon")
	scene.course.running = true
	scene.course.elapsed_s = 12.0
	scene.vehicle.simulation.thermal_model.fuel_remaining_litres = 8.5
	scene.vehicle.simulation.thermal_model.tire_states[0].wear_fraction = 0.4
	var before_penalty: int = scene.competition.player_penalty_ms
	buttons["Pedir rescate"].pressed.emit()
	check(not paused and not panel.modal.visible, "rescue resumes stage")
	check(scene.competition.player_penalty_ms == before_penalty + int(scene.competition.balance.reset_penalty_ms), "rescue applies configured penalty")
	check(scene.vehicle.simulation.thermal_model.fuel_remaining_litres == 8.5, "rescue preserves fuel")
	check(scene.vehicle.simulation.thermal_model.tire_states[0].wear_fraction == 0.4, "rescue preserves tire wear")
	check(scene.course.elapsed_s == 12.0, "rescue preserves elapsed stage time")
	var hud = scene.head_up_display
	hud.update_thermal_readout()
	check(not hud.formula_panels.has_method("map_rotation"), "route map removed from CMR2 HUD")
	check(hud.formula_panels.snapshot.has("hud_indicators"), "hud publishes simplified engine indicators")
	if "--pause-map-capture" in OS.get_cmdline_user_args():
		await capture("rally_vertical_map.png")
	panel.pause_button.pressed.emit()
	check(paused, "pause button pauses again")
	if "--pause-map-capture" in OS.get_cmdline_user_args():
		await capture("rally_pause_actions.png")
	for child in panel.content.get_children():
		if child is Button and child.text == "Abandonar etapa":
			child.pressed.emit()
			break
	check(not paused and not panel.modal.visible, "abandon unpauses and closes modal")
	check(scene.competition.complete and scene.competition.player_retired, "abandon retires player")
	scene.queue_free()
	await process_frame
	print("PAUSE_MAP_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)

func capture(filename: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join(filename))
