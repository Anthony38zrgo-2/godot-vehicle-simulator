extends SceneTree

class TestManager:
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
	var manager := TestManager.new()
	check(manager.begin_event({"seed": 42, "setup_accepted": true}), "event starts")
	var scene = load("res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn").instantiate()
	scene.begin_event_session(manager, "russia_stage1")
	scene.weather_enabled = false
	root.add_child(scene)
	current_scene = scene
	for frame in 600:
		await process_frame
		if scene.session_ready:
			break
	check(scene.session_ready, "session ready")
	var vehicle = scene.vehicle
	var inventory = vehicle.tire_inventory
	check(inventory.mounted.size() == 4 and inventory.spares.size() == 2, "four mounted plus two real spares")
	scene.garage_panel.open_garage()
	check(scene.garage_panel.draft_spare_wheels == 2, "garage reads real spare count")
	scene.garage_panel.close_garage(true)
	check(inventory.spares.size() == 2, "applying unchanged setup preserves inventory")
	scene.garage_panel.close_garage(false)
	var panel: Node
	for child in scene.get_children():
		if child.get_script() == load("res://scripts/rally/rally_pause_inventory.gd"):
			panel = child
	check(panel != null, "pause inventory installed")
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	panel._unhandled_input(event)
	check(paused and panel.modal.visible, "pause button opens menu")
	panel.show_inventory()
	if DisplayServer.get_name() != "headless":
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("rally_tire_inventory.png"))
	var mass_before: float = vehicle.mass
	var inertia_before: Vector3 = vehicle.inertia
	vehicle.simulation.thermal_model.tire_states[0].wear_fraction = 0.4
	vehicle.simulation.thermal_model.tire_states[0].thermal_damage_fraction = 0.2
	vehicle.simulation.thermal_model.tire_states[0].tread_c = 72.0
	vehicle.simulation.thermal_model.tire_states[0].leak_per_second = 0.045
	vehicle.simulation.thermal_model.tire_states[0].pressure_loss_fraction = 0.55
	vehicle.simulation.brake_collision_loss[0] = 0.3
	vehicle.simulation.thermal_model.tire_states[0].rim_deformation = 0.4
	vehicle.simulation.alignment_collision_damage[0] = 0.5
	check(vehicle.simulation._effective_toe(0) < vehicle.simulation.suspension_model.dynamic_toe(0), "impact adds inward toe on the left")
	var removed_id := int(inventory.mounted[0].id)
	inventory.spares[0].compound_id = "gravel_wet"
	inventory.spares[0].state = vehicle.fresh_tire_state("gravel_wet")
	var replacement_id := int(inventory.spares[0].id)
	panel.selected_wheel = 0
	panel.show_inventory()
	panel.exchange()
	check(inventory.spares.size() == 2 and int(inventory.mounted[0].id) == replacement_id, "swap uses existing spare without duplication")
	var removed: Dictionary = inventory.spares[1]
	check(is_zero_approx(vehicle.simulation.thermal_model.tire_states[0].leak_per_second), "fresh spare stops the leak")
	check(is_equal_approx(vehicle.simulation.brake_collision_loss[0], 0.3), "fresh spare leaves brake damage on the corner")
	check(is_zero_approx(vehicle.simulation.thermal_model.tire_states[0].rim_deformation), "fresh spare removes rim deformation")
	check(is_equal_approx(removed.state.rim_deformation, 0.4), "removed rim keeps deformation")
	check(is_equal_approx(vehicle.simulation.alignment_collision_damage[0], 0.5), "spare leaves alignment damage on the corner")
	check(is_equal_approx(removed.state.pressure_loss_fraction, 0.55), "removed wheel keeps its pressure loss")
	check(int(removed.id) == removed_id and removed.state.wear_fraction == 0.4 and removed.state.thermal_damage_fraction == 0.2 and removed.state.tread_c == 72.0, "removed tire retains wear damage and temperature")
	check(vehicle.simulation.thermal_model.compound_for_wheel(0).label == "Grava-Lluvia", "thermal model uses per-wheel compound")
	var wet_grip: Dictionary = vehicle.simulation.tire_model.compound_water_snow_ground_factor(3.0, 0.0, 18.0, 0)
	var dry_grip: Dictionary = vehicle.simulation.tire_model.compound_water_snow_ground_factor(3.0, 0.0, 18.0, 1)
	check(wet_grip.combined > dry_grip.combined, "grip uses per-wheel compound")
	check(vehicle.exchange_tire(1, removed_id, true), "old tire can be reused")
	check(vehicle.simulation.thermal_model.tire_states[1].wear_fraction == 0.4, "reused tire keeps wear")
	check(vehicle.discard_spare(int(inventory.spares[0].id)), "discard carried spare")
	check(is_equal_approx(mass_before - vehicle.mass, 18.0), "discard removes eighteen kg without double-counting baseline")
	check(not vehicle.inertia.is_equal_approx(inertia_before), "discard updates inertia")
	check(vehicle.exchange_tire(2, int(inventory.spares[0].id), false), "discard removed wheel during exchange")
	check(inventory.spares.is_empty() and is_equal_approx(mass_before - vehicle.mass, 36.0), "no spares means thirty-six kg less")
	var before := JSON.stringify(inventory.snapshot())
	check(not vehicle.exchange_tire(3, 99999, true), "cannot create a tire from missing ID")
	check(JSON.stringify(inventory.snapshot()) == before, "failed exchange leaves inventory intact")
	panel.persist()
	var restored = preload("res://scripts/rally/rally_tire_inventory.gd").new()
	check(restored.restore(JSON.parse_string(JSON.stringify(manager.tire_inventory_state))), "inventory roundtrip persists IDs and condition")
	check(is_equal_approx(restored.mounted[1].state.leak_per_second, 0.045), "save keeps puncture on the remounted wheel")
	check(is_equal_approx(manager.tire_inventory_state.brake_collision_loss[0], 0.3), "save keeps brake damage on the original corner")
	check(is_equal_approx(restored.mounted[1].state.rim_deformation, 0.4), "save keeps deformation on the remounted wheel")
	check(is_equal_approx(manager.tire_inventory_state.alignment_collision_damage[0], 0.5), "save keeps alignment on the original corner")
	check(restored.mounted[1].state.wear_fraction == 0.4 and restored.spares.is_empty(), "save keeps reused condition and discards")
	panel.toggle()
	check(not paused, "resume unpauses")
	scene.retire_competition_player()
	await scene.continue_competition()
	check(inventory.spares.is_empty() and vehicle.simulation.thermal_model.tire_states[1].wear_fraction == 0.4, "next stage preserves inventory and wear")
	check(vehicle.simulation.thermal_model.compound_for_wheel(0).label == "Grava-Lluvia", "mixed compound survives next stage")
	check(is_equal_approx(vehicle.simulation.thermal_model.tire_states[1].leak_per_second, 0.045), "stage reset preserves puncture")
	check(is_equal_approx(vehicle.simulation.brake_collision_loss[0], 0.3), "stage reset preserves brake damage")
	check(is_equal_approx(vehicle.simulation.thermal_model.tire_states[1].rim_deformation, 0.4), "stage reset preserves rim deformation")
	check(is_equal_approx(vehicle.simulation.alignment_collision_damage[0], 0.5), "stage reset preserves alignment damage")
	var thermal := VehicleThermalModel.new()
	thermal.configure(vehicle.simulation.domains)
	thermal.set_compound("gravel_normal")
	var state: Dictionary = thermal.tire_states[0]
	thermal.accumulate_tire_damage(state, 1000.0, 10.0)
	var expected_wear := 10000.0 * float(thermal.active_compound.wear_per_j)
	expected_wear *= float(thermal.active_compound.get("dry_wear_multiplier", 1.0))
	expected_wear *= VehicleThermalModel.NATURAL_WEAR_MULTIPLIER / float(thermal.compound_catalog.durability_life_scale)
	check(is_equal_approx(state.wear_fraction, expected_wear), "wear uses dry abrasion and configured inverse lifetime scaling")
	scene.queue_free()
	await process_frame
	print("TIRE_INVENTORY_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
