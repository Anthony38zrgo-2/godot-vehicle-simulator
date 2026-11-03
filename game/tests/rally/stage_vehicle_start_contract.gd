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

func check_start(scene: Node, expected_wear: float = 0.0, expected_damage: float = 0.0) -> void:
	var vehicle = scene.vehicle
	var thermal = vehicle.simulation.thermal_model
	check(scene.input_controller.start_handbrake_held and vehicle.handbrake_input == 1.0, "automatic handbrake armed")
	check(vehicle.linear_velocity.length() < 0.1 and vehicle.angular_velocity.length() < 0.1, "chassis motion cleared")
	check(vehicle.current_gear == 0, "gear reset to neutral")
	for i in 4:
		var tire: Dictionary = thermal.tire_states[i]
		check(absf(tire.tread_c - 50.0) < 1.0 and absf(tire.carcass_c - 60.0) < 1.0, "optimal tire temperatures")
		check(tire.brake_disc_c >= 150.0 and tire.brake_disc_c <= 450.0, "optimal brake temperature")
		check(is_equal_approx(tire.wear_fraction, expected_wear), "preheat preserves tire wear")
		check(is_equal_approx(float(tire.get("thermal_damage_fraction", 0.0)), expected_damage), "preheat preserves thermal damage")
		check(absf(vehicle.simulation.wheel_spins[i]) < 0.1, "wheel rotation cleared")
	check(thermal.water_temperature_c < 100.0, "engine temperature reset")

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
	check(scene.session_ready, "session ready")
	if scene.awaiting_setup:
		scene.garage_panel.close_garage(true)
	check_start(scene)
	var controller = scene.input_controller
	for action in [controller.action_throttle, controller.action_brakes, controller.action_handbrake]:
		controller.arm_start_handbrake()
		controller._physics_process(0.01)
		check(controller.start_handbrake_held, "no input keeps hold")
		Input.action_press(controller.action_steer_left)
		controller._physics_process(0.01)
		Input.action_release(controller.action_steer_left)
		check(controller.start_handbrake_held, "steering does not release hold")
		Input.action_press(action)
		controller._physics_process(0.01)
		Input.action_release(action)
		check(not controller.start_handbrake_held, "pedal or handbrake releases hold")
		controller._physics_process(0.01)
		check(scene.vehicle.handbrake_input == 0.0, "hold does not rearm on release")
	var sim = scene.vehicle.simulation
	for i in 4:
		sim.thermal_model.tire_states[i].tread_c = 130.0
		sim.thermal_model.tire_states[i].carcass_c = 120.0
		sim.thermal_model.tire_states[i].brake_disc_c = 800.0
		sim.thermal_model.tire_states[i].wear_fraction = 0.8
		sim.thermal_model.tire_states[i].thermal_damage_fraction = 0.3
		sim.wheel_spins[i] = 100.0
	sim.thermal_model.water_temperature_c = 140.0
	sim.thermal_model.fuel_remaining_litres = 2.123
	scene.retire_competition_player()
	await scene.continue_competition()
	check_start(scene, 0.8, 0.3)
	check(absf(sim.thermal_model.fuel_remaining_litres - 2.123) < 0.01, "stage transition retains exact fuel below garage minimum")
	var fuel_setup: Dictionary = scene.vehicle.get_setup_snapshot()
	fuel_setup["fuel.initial_kg"] = 45.0
	check(scene.vehicle.apply_setup_snapshot(fuel_setup).ok, "other setup remains available")
	check(absf(sim.thermal_model.fuel_remaining_litres - 2.123) < 0.01, "setup outside service cannot refuel")
	check(manager.mounted_tire_condition.size() == 4 and is_equal_approx(manager.mounted_tire_condition[0].thermal_damage_fraction, 0.3), "event retains mounted tire damage")
	scene.vehicle.service_new_tires()
	for tire: Dictionary in sim.thermal_model.tire_states:
		check(tire.wear_fraction == 0.0 and tire.thermal_damage_fraction == 0.0, "new tire service clears wear and heat damage")
	check(scene.session_track_id == "russia_stage2", "stage two loaded")
	var origin: Vector3 = scene.vehicle.global_position
	for i in 480:
		await physics_frame
	check(controller.start_handbrake_held, "countdown does not release hold")
	check(Vector2(scene.vehicle.global_position.x - origin.x, scene.vehicle.global_position.z - origin.z).length() < 0.75, "no rolling or false start on slope")
	check(not scene.start_sequence.false_start, "no false start while held")
	scene.queue_free()
	await process_frame
	print("STAGE_VEHICLE_START_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)

