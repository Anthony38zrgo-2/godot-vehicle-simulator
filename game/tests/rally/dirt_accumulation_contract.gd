extends SceneTree

const Dirt = preload("res://scripts/physics/dirt_model.gd")
const ServicePanel = preload("res://scripts/rally/rally_service_panel.gd")


class ServiceEvent extends RallyEventManager:
	var fail_save := true
	var saves := 0

	func current_stage_id() -> String:
		return "test"

	func save() -> bool:
		saves += 1
		error = "Test save failure" if fail_save else ""
		return not fail_save

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(4.0, 2.0, 5.0)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.rotation_degrees = Vector3(-45, -35, 0)
	var dirt := Dirt.new()
	var surfaces: Array[String] = ["Dirt", "Gravel", "Road", "SnowDeep"]
	var conditions := [{"mud_factor": 1.0}, {"mud_factor": 0.0}, {"background_water_mm": 0.0}, {"mud_factor": 1.0}]
	var loads: Array[float] = [3500.0, 3500.0, 3500.0, 3500.0]
	var slips: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	for i in 48000:
		dirt.step(1.0 / 120.0, 25.0, surfaces, conditions, loads, loads, slips)
	var expected := Vector4(0.8647, 0.4512, 0.0296, 0.0)
	var measured := Vector4(dirt.level(1), dirt.level(2), dirt.level(3), dirt.level(4))
	var ok := (expected - measured).length() < 0.002 and dirt.visual_state(1).x == 4.0
	var saved := dirt.snapshot()
	dirt.step(1.0, 0.0, surfaces, conditions, loads, loads, slips)
	ok = ok and dirt.snapshot() == saved
	dirt.service_clean()
	ok = ok and not dirt.is_dirty()
	dirt.restore(JSON.parse_string(JSON.stringify(saved, "", true, true)))
	ok = ok and dirt.snapshot() == saved
	var scenes := [
		"res://scenes/rally/ford_escort_rs2000_1971.tscn",
		"res://scenes/rally/porsche_911_24s.tscn",
		"res://scenes/rally/rt/rt-porsche-356b-2000gs.tscn",
	]
	for i in scenes.size():
		var vehicle := (load(scenes[i]) as PackedScene).instantiate() as RallyEscortVehicle
		if i == 1:
			vehicle.get_node("Chassis").set("gt2_vehicle_shading", true)
		root.add_child(vehicle)
		vehicle.freeze = true
		vehicle.restore_damage({"dirt": saved})
		await process_frame
		var thermal := vehicle.simulation.thermal_model
		ok = ok and ((thermal.dirt_cooler > 0.0) == (i == 0))
		var clean_disc := float(thermal._brake_heat_losses(0, 300.0, 25.0, 20.0).convection_w_k)
		var factor := thermal.dirt_brakes[0]
		ok = ok and factor > thermal.dirt_brakes[1]
		vehicle.service_clean_dirt()
		var washed_disc := float(thermal._brake_heat_losses(0, 300.0, 25.0, 20.0).convection_w_k)
		ok = ok and is_equal_approx(clean_disc, washed_disc * (1.0 - 0.5625 * factor))
		ok = ok and not vehicle.simulation.dirt.is_dirty()
		if i == 0:
			thermal.dirt_brakes[0] = 1.0
			var max_dirt_disc := float(thermal._brake_heat_losses(0, 300.0, 25.0, 20.0).convection_w_k)
			ok = ok and is_equal_approx(max_dirt_disc, washed_disc * 0.4375)
			var duct: Dictionary = thermal.engine_config.get("water_cooling_duct", {})
			var base := float(duct.get("base_cooling_conductance_watts_per_kelvin", 0.0))
			thermal.advance_engine(0.01, 3000.0, 80.0, 25.0, 1.2)
			var clean_air := thermal.water_cooling_conductance_w_k - base
			thermal.dirt_cooler = 1.0
			thermal.advance_engine(0.01, 3000.0, 80.0, 25.0, 1.2)
			ok = ok and clean_air > 0.0 and is_equal_approx(thermal.water_cooling_conductance_w_k - base, clean_air * 0.70)
			ok = _test_service(vehicle, saved) and ok
		vehicle.queue_free()
		await process_frame
	for player: AudioStreamPlayer in root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.2).timeout
	print("DIRT_ACCUMULATION_CONTRACT ", "PASS" if ok else "FAIL", " levels=", measured)
	quit(0 if ok else 1)


func _test_service(vehicle: RallyEscortVehicle, dirt: Dictionary) -> bool:
	vehicle.restore_damage({"dirt": dirt})
	var event := ServiceEvent.new()
	var panel := ServicePanel.new()
	root.add_child(panel)
	var music := root.get_node_or_null("RallyMusic")
	if music != null:
		root.remove_child(music)
	panel.open(vehicle, event, {"window_key": "test", "repair_minutes": 4})
	if music != null:
		music.queue_free()
	var ok := panel.wash_box != null and panel.wash_box.disabled
	if panel.wash_box == null:
		panel.queue_free()
		return false
	panel.limit_minutes = 5
	panel._refresh()
	ok = ok and not panel.wash_box.disabled
	panel.wash_box.button_pressed = true
	ok = ok and panel._minutes() == 5
	panel._commit()
	ok = ok and event.saves == 1 and vehicle.simulation.dirt.snapshot() == dirt and event.windows_attended.is_empty()
	event.fail_save = false
	panel._commit()
	panel._commit()
	ok = ok and event.saves == 2 and event.windows_attended.has("repairs:test")
	ok = ok and not vehicle.simulation.dirt.is_dirty() and event.service_penalties_ms.get("test", -1) == 0
	vehicle.restore_damage(event.vehicle_damage_state)
	return ok and not vehicle.simulation.dirt.is_dirty()
