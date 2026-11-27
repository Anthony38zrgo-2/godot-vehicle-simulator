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

	# Verificar página TRAMO con nodos Control reales (sin selector de compuestos), botón RESTAURAR y caché de trazado.
	panel.open_garage_for_event({"confirmation_required": false, "stage_weather_label": "Nublado"})
	panel._set_page(0)
	panel._run_button("reset")
	check(panel.active_setup_name == "BASE", "reset button restores BASE setup instead of FABRICA")
	await process_frame
	check(panel._stage_tab != null and panel._stage_tab.visible, "Stage tab Control view is visible on page 0")
	check(panel._strategy_tab != null and not panel._strategy_tab.visible, "Strategy/compound tab is hidden on page 0")
	check(panel.reset_button != null and panel.reset_button.visible, "Footer exposes real Control reset button")
	check(panel._get_stage_weather_text() == "NUBLADO", "Stage weather text uses provided label")
	panel.close_garage(false)
	scene.queue_free()
	await process_frame

	# Verificar resolución de nombres para todos los coches (registry.json) sin fallback a Escort.
	var v_script = load("res://scripts/rally/rally_escort_vehicle.gd")
	var g_script = load("res://scripts/rally/rally_garage_panel.gd")
	for pair in [
		{"profile": "res://data/vehicles/rt/rt-alfa-giulia-gta/vehicle.json", "expected": "ALFA ROMEO GIULIA SPRINT GTA"},
		{"profile": "res://data/vehicles/rt/rt-alpine-a110/vehicle.json", "expected": "ALPINE RENAULT A110 1600"},
		{"profile": "res://data/vehicles/lancia-fulvia/vehicle.json", "expected": "LANCIA FULVIA HF"},
		{"profile": "res://data/vehicles/ford-escort-rs2000/vehicle.json", "expected": "FORD ESCORT RS2000"},
	]:
		var mock_v = v_script.new()
		mock_v.name = "Vehicle"
		mock_v.rally_profile_path = str(pair["profile"])
		mock_v.rally_profile = {"profile_id": "test", "domain_hashes": {}}
		var test_p = g_script.new()
		test_p.vehicle = mock_v
		check(test_p._get_vehicle_display_name() == str(pair["expected"]), "Registry resolves " + str(pair["expected"]))
		test_p.queue_free()
		mock_v.queue_free()

	# Verificar escena real rt-alfa-giulia-gta + sesión sincronizando trazado, clima y km reales.
	var alfa_scene = load("res://scenes/rally/rt/rt-alfa-giulia-gta_stage.tscn").instantiate()
	alfa_scene.practice_mode = true
	alfa_scene.single_stage_weather = "rain"
	root.add_child(alfa_scene)
	current_scene = alfa_scene
	for i in 300:
		await process_frame
		if alfa_scene.session_ready:
			break
	check(alfa_scene.session_ready, "Alfa stage session ready")
	if alfa_scene.garage_panel != null:
		check(
			alfa_scene.garage_panel._get_vehicle_display_name() == "ALFA ROMEO GIULIA SPRINT GTA",
			"Alfa stage header resolves ALFA ROMEO GIULIA SPRINT GTA (single name, no Escort hardcode)"
		)
		alfa_scene.garage_panel._ensure_stage_route_cache()
		check(alfa_scene.garage_panel._cached_route_points.size() >= 2, "Russia stage1 route points cached")
		check(alfa_scene.garage_panel._get_stage_distance_text() == "5.0 KM", "Russia stage1 displays real 5.0 KM")
		check(alfa_scene.garage_panel._get_stage_weather_text() == "LLUVIA", "Single stage rain displays LLUVIA")
		alfa_scene.garage_panel.set_stage_metadata({
			"stage_id": "kenya_stage2",
			"stage_country": "Kenya",
			"stage_length_m": 6800.0,
			"stage_route_path": "res://data/rally/kenya_stage2_route.json",
			"stage_weather_label": "Soleado",
		})
		alfa_scene.garage_panel._ensure_stage_route_cache()
		check(alfa_scene.garage_panel._cached_route_points.size() >= 2, "Kenya stage2 route points cached")
		check(alfa_scene.garage_panel._get_stage_distance_text() == "6.8 KM", "Kenya stage2 displays 6.8 KM")
		check(alfa_scene.garage_panel._get_stage_weather_text() == "SOLEADO", "Kenya stage2 weather displays SOLEADO")
	alfa_scene.queue_free()
	await process_frame

	print("GARAGE_FUNCTION_CONTRACT ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
