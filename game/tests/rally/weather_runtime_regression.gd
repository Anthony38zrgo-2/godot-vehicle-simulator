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
	check(manager.begin_event({"seed": 42}), "event generates from JSON")
	if manager.weather_schedule.is_empty():
		quit(1)
		return
	var scene = load("res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn").instantiate()
	scene.begin_event_session(manager, "russia_stage1")
	root.add_child(scene)
	current_scene = scene
	for i in 600:
		await process_frame
		if scene.session_ready:
			break
	check(scene.session_ready and scene.awaiting_setup and paused, "initial mandatory garage pauses session")
	check(scene.terrain_wetness != null, "retro mode keeps wet surface visuals enabled")
	scene.garage_panel.draft_compound_id = "gravel_wet"
	scene.garage_panel.close_garage(true)
	check(not paused and not scene.awaiting_setup, "accept starts session")
	check(scene.vehicle.get_tire_compound() == "gravel_wet", "selected compound applied")
	check(not manager.confirm_setup("gravel_normal", {}).ok, "compound cannot change outside window even with empty setup")
	var ctl = scene.event_weather
	for boundary_index in [1, 2]:
		var boundary: float = ctl.surface.zones[boundary_index].start_distance_m
		ctl.surface.zones[boundary_index - 1].ground_c = 10.0
		ctl.surface.zones[boundary_index].ground_c = 30.0
		var left: Dictionary = ctl.surface.blended_state_at_distance(boundary - 0.01)
		var right: Dictionary = ctl.surface.blended_state_at_distance(boundary + 0.01)
		check(absf(left.ground_c - right.ground_c) < 0.1, "surface continuous across boundary")
	ctl.on_rescue(ctl.route_points[250])
	check(absf(ctl.route_progress_m - ctl.route_distances[250]) < 1.0, "rescue projects to distant road")
	ctl.update_vehicle_position(ctl.route_points[245])
	check(absf(ctl.route_progress_m - ctl.route_distances[245]) < 1.0, "reverse updates surface position")
	for zi in 3:
		ctl.surface.zones[zi].ground_c = 10.0 + zi * 10.0
	var cursor: float = ctl.route_progress_m
	var first: Dictionary = ctl.local_conditions_for_contact("Gravel", ctl.route_points[1])
	# Move cursor to the first zone for near-contact sampling, preserving HUD query independence.
	ctl.on_rescue(ctl.route_points[1])
	first = ctl.local_conditions_for_contact("Gravel", ctl.route_points[1])
	check(first.ground_c < 11.0, "contact uses its own position")
	check(ctl.route_progress_m < cursor, "reprojection moved to first zone")
	ctl.current_blend = ctl.surface.state_for_zone(0)
	ctl.current_blend.climate.precipitation_mm_h = 8.0
	ctl.current_blend.precipitation_kind = "rain"
	ctl.visual_state = ctl.current_blend.duplicate(true)
	ctl.apply_to_adapters(scene.weather_sky_dome, scene.weather_controller_node, scene.terrain_wetness, 12.0)
	check(scene.weather_controller_node.particle_system != null and scene.weather_controller_node.particle_system.emitting, "calendar actually starts rain particles")
	check(not scene.weather_controller_node.is_processing(), "TCA autonomous selection disabled")
	for i in 20:
		await physics_frame
	check(scene.vehicle.simulation.surface_temperature_for_hud().ok, "HUD surface reading available")
	manager.cursor = 5
	manager._update_pending_window()
	scene._open_setup_window()
	check(scene.awaiting_setup and paused and scene.garage_panel.visible, "mid-rally garage opens")
	scene.garage_panel.close_garage(true)
	check(not paused and manager.get_pending_window().is_empty(), "mid-rally window confirmed")
	scene.queue_free()
	await process_frame
	print("WEATHER_RUNTIME_REGRESSION ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
