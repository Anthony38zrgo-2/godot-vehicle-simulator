extends SceneTree

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
	assert(scene.session_ready)
	scene.set_physics_process(false)
	scene.vehicle.freeze = true
	var panel: Node
	for child in scene.get_children():
		if child.get_script() == load("res://scripts/rally/rally_pause_inventory.gd"):
			panel = child
	assert(panel != null)
	var menu_press := InputEventJoypadButton.new()
	menu_press.button_index = JOY_BUTTON_START
	menu_press.pressed = true
	assert(menu_press.is_action_pressed(InputBindings.UI_BACK_TO_MENU))
	assert(not menu_press.is_action_pressed(InputBindings.TOGGLE_GARAGE))
	Input.parse_input_event(menu_press)
	Input.flush_buffered_events()
	await process_frame
	assert(paused and panel.modal.visible)
	assert(not scene.garage_panel.visible)
	var handbrake_press := InputEventJoypadButton.new()
	handbrake_press.button_index = JOY_BUTTON_LEFT_SHOULDER
	handbrake_press.pressed = true
	assert(handbrake_press.is_action_pressed(InputBindings.HANDBRAKE))
	assert(not handbrake_press.is_action_pressed(InputBindings.CLUTCH))
	var menu_release := InputEventJoypadButton.new()
	menu_release.button_index = JOY_BUTTON_START
	Input.parse_input_event(menu_release)
	Input.parse_input_event(menu_press)
	Input.flush_buffered_events()
	await process_frame
	assert(not paused and not panel.modal.visible)
	Input.parse_input_event(handbrake_press)
	Input.flush_buffered_events()
	scene.input_controller._physics_process(0.1)
	assert(scene.vehicle.handbrake_input == 1.0)
	var handbrake_release := InputEventJoypadButton.new()
	handbrake_release.button_index = JOY_BUTTON_LEFT_SHOULDER
	Input.parse_input_event(handbrake_release)
	Input.flush_buffered_events()
	scene.input_controller._physics_process(0.1)
	assert(scene.vehicle.handbrake_input == 0.0)
	Input.parse_input_event(menu_release)
	panel.pause_button.pressed.emit()
	assert(paused and panel.modal.visible)
	var buttons: Dictionary = {}
	for child in panel.content.get_children():
		if child is Button:
			buttons[child.text] = child
	assert(buttons.has("Pedir rescate") and buttons.has("Abandonar etapa"))
	scene.course.running = true
	scene.course.elapsed_s = 12.0
	scene.vehicle.simulation.thermal_model.fuel_remaining_litres = 8.5
	scene.vehicle.simulation.thermal_model.tire_states[0].wear_fraction = 0.4
	var before_penalty: int = scene.competition.player_penalty_ms
	buttons["Pedir rescate"].pressed.emit()
	assert(not paused and not panel.modal.visible)
	assert(scene.competition.player_penalty_ms == before_penalty + int(scene.competition.balance.reset_penalty_ms))
	assert(scene.vehicle.simulation.thermal_model.fuel_remaining_litres == 8.5)
	assert(scene.vehicle.simulation.thermal_model.tire_states[0].wear_fraction == 0.4)
	assert(scene.course.elapsed_s == 12.0)
	var hud = scene.head_up_display
	hud.update_thermal_readout()
	assert(hud.formula_panels.snapshot.air_temp_c == scene.vehicle.simulation.thermal_model.ambient_temperature_c)
	var points: Array = [Vector3.ZERO, Vector3(100, 0, 1), Vector3(200, 0, 2)]
	var rotation: float = hud.formula_panels.map_rotation(points)
	var direction := Vector2(200, 2).rotated(rotation)
	assert(direction.y < 0.0 and absf(direction.x) < 0.01)
	if "--pause-map-capture" in OS.get_cmdline_user_args():
		await capture("rally_vertical_map.png")
	panel.pause_button.pressed.emit()
	assert(paused)
	if "--pause-map-capture" in OS.get_cmdline_user_args():
		await capture("rally_pause_actions.png")
	for child in panel.content.get_children():
		if child is Button and child.text == "Abandonar etapa":
			child.pressed.emit()
			break
	assert(not paused and not panel.modal.visible)
	assert(scene.competition.complete and scene.competition.player_retired)
	scene.queue_free()
	await process_frame
	print("PAUSE_MAP_CONTRACT PASS")
	quit()

func capture(filename: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join(filename))
