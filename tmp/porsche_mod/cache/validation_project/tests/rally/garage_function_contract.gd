extends SceneTree

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 120:
		await physics_frame
		if scene.get_node_or_null("FordEscortRS2000") != null and scene.get_node("FordEscortRS2000").simulation != null:
			break
	var vehicle = scene.get_node("FordEscortRS2000")
	var panel = load("res://scenes/rally/rally_garage_panel.tscn").instantiate()
	panel.vehicle = vehicle
	scene.add_child(panel)
	panel.open_garage_for_event({"confirmation_required": true})
	check(panel.visible, "garage opens")
	var initial: Dictionary = panel.draft_values.duplicate(true)
	check(initial.has("brakes.front_brake_bias"), "real setup loaded")
	panel.draft_values["brakes.front_brake_bias"] = 0.6
	panel.draft_values["strategy.wheel_compound.FL"] = "gravel_wet"
	panel.draft_values["strategy.spare_wheels"] = 2
	panel.close_garage(false)
	check(panel.visible, "mandatory confirmation prevents cancellation")
	panel.close_garage(true)
	check(not panel.visible, "confirmation closes garage")
	check(absf(float(vehicle.get_setup_snapshot()["brakes.front_brake_bias"]) - 0.6) < 0.001, "brake adjustment applied")
	check(vehicle.tire_inventory.mounted[0].compound_id == "gravel_wet", "individual tire applied")
	check(vehicle.tire_inventory.spares.size() == 2, "spares applied")
	check(panel.get_confirmed_setup().values.has("brakes.front_brake_bias"), "confirmed values available to event")
	panel.open_garage_for_event({})
	panel.draft_values["brakes.front_brake_bias"] = 0.7
	panel.close_garage(false)
	check(absf(float(vehicle.get_setup_snapshot()["brakes.front_brake_bias"]) - 0.6) < 0.001, "discard preserves vehicle")
	print("GARAGE_FUNCTION_CONTRACT ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
