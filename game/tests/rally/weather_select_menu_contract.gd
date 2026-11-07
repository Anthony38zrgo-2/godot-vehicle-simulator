extends SceneTree

const EventManagerScript = preload("res://scripts/rally/rally_event_manager.gd")

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAILURE: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("--- WEATHER SELECT MENU ACCEPTANCE CONTRACT ---")
	await test_weather_screen_structure_and_options()
	await test_weather_navigation_and_back()
	await test_weather_selection_reaction()
	await test_event_manager_initial_weather_integration()

	print("WEATHER_SELECT_MENU_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)


func test_weather_screen_structure_and_options() -> void:
	print("[1] Comprobando que antes de empezar un rally aparece la pantalla de clima con solo las intermedias...")
	var menu_scene: RallyManiacMenu = load("res://scenes/rally/rally_maniac_menu.tscn").instantiate()
	root.add_child(menu_scene)
	current_scene = menu_scene
	await process_frame
	await process_frame

	# Simular flujo: Menú -> Tramo 1 -> Coche
	menu_scene.show_stage_select()
	await process_frame
	menu_scene.show_car_select()
	await process_frame

	# En el selector de coche, seleccionar coche debe llevar a la pantalla de clima antes de iniciar
	menu_scene._on_car_selected("fulvia")
	await process_frame
	await process_frame

	check(menu_scene.current_screen == "weather_select", "Pantalla cambia a weather_select antes de iniciar el rally")
	check(menu_scene.screen_weather_select.visible, "screen_weather_select es visible")
	check(menu_scene.badge_top.text == "CONDICIÓN", "Badge superior indica CONDICIÓN")
	check(menu_scene.badge_bottom.text == "SELECT WEATHER", "Badge inferior indica SELECT WEATHER")

	# Verificar que SOLO ofrece las intermedias: Soleado, Nublado, Lluvia, Aleatorio (exactamente 4 opciones)
	check(menu_scene.weather_buttons.size() == 4, "Ofrece exactamente 4 opciones intermedias")

	var expected_options := [
		{"id": "sunny", "title": "Soleado"},
		{"id": "cloudy", "title": "Nublado"},
		{"id": "medium_precipitation", "title": "Lluvia"},
		{"id": "random", "title": "Aleatorio"}
	]

	for i in range(4):
		var btn: Button = menu_scene.weather_buttons[i]
		var exp_id: String = expected_options[i]["id"]
		var exp_title: String = expected_options[i]["title"]
		check(str(btn.get_meta("weather_id", "")) == exp_id, "Opción %d ID es '%s'" % [i + 1, exp_id])
		check(btn.text == exp_title, "Opción %d Título es '%s'" % [i + 1, exp_title])

	menu_scene.queue_free()
	await process_frame


func test_weather_navigation_and_back() -> void:
	print("[2] Comprobando navegación atrás desde la pantalla de clima...")
	var menu_scene: RallyManiacMenu = load("res://scenes/rally/rally_maniac_menu.tscn").instantiate()
	root.add_child(menu_scene)
	current_scene = menu_scene
	await process_frame
	await process_frame

	menu_scene.show_stage_select()
	await process_frame
	menu_scene.show_car_select()
	await process_frame
	menu_scene.show_weather_select()
	await process_frame

	check(menu_scene.current_screen == "weather_select", "En pantalla de clima")
	check(menu_scene.btn_weather_back != null, "Botón Back de clima presente")

	# Pulsar Back debe regresar a la pantalla de selección de coches
	menu_scene.btn_weather_back.emit_signal("pressed")
	await process_frame
	await process_frame

	check(menu_scene.current_screen == "car_select", "Volver desde clima lleva a car_select")
	check(menu_scene.screen_car_select.visible, "screen_car_select es visible")

	menu_scene.queue_free()
	await process_frame


func test_weather_selection_reaction() -> void:
	print("[3] Comprobando interactividad de selección de climas...")
	var menu_scene: RallyManiacMenu = load("res://scenes/rally/rally_maniac_menu.tscn").instantiate()
	root.add_child(menu_scene)
	current_scene = menu_scene
	await process_frame
	await process_frame

	menu_scene.show_weather_select()
	await process_frame

	# Probar selección de Soleado
	menu_scene._select_weather("sunny")
	check(menu_scene.selected_weather == "sunny", "Clima seleccionado es sunny (Soleado)")
	check("SOLEADO" in menu_scene.weather_selected_desc_label.text, "Etiqueta refleja Soleado")

	# Probar selección de Nublado
	menu_scene._select_weather("cloudy")
	check(menu_scene.selected_weather == "cloudy", "Clima seleccionado es cloudy (Nublado)")
	check("NUBLADO" in menu_scene.weather_selected_desc_label.text, "Etiqueta refleja Nublado")

	# Probar selección de Lluvia
	menu_scene._select_weather("medium_precipitation")
	check(menu_scene.selected_weather == "medium_precipitation", "Clima seleccionado es medium_precipitation (Lluvia)")
	check("LLUVIA" in menu_scene.weather_selected_desc_label.text, "Etiqueta refleja Lluvia")

	# Probar selección de Aleatorio
	menu_scene._select_weather("random")
	check(menu_scene.selected_weather == "random", "Clima seleccionado es random (Aleatorio)")
	check("ALEATORIO" in menu_scene.weather_selected_desc_label.text, "Etiqueta refleja Aleatorio")

	check(menu_scene.btn_weather_confirm != null, "Botón de confirmación de inicio de rally presente")
	check(menu_scene.btn_weather_confirm.text.find("Rally") != -1, "Texto descriptivo de inicio del rally")

	menu_scene.queue_free()
	await process_frame


func test_event_manager_initial_weather_integration() -> void:
	print("[4] Comprobando integración con RallyEventManager y generación de tramo inicial con el clima elegido...")
	var manager := EventManagerScript.new()
	check(manager.load_event(), "Carga evento de Rusia")

	# Caso 1: Soleado
	var ok_sunny = manager.begin_event({"seed": 1974, "preview": true, "initial_weather": "sunny"})
	check(ok_sunny, "Evento generado con initial_weather=sunny")
	check(manager.weather_schedule.size() == 10, "10 tramos en cronograma")
	var z0_sunny: Dictionary = manager.weather_schedule[0]["zones"][0]
	check(str(z0_sunny.get("weather_state_id", "")) == "sunny", "Zona 0 de Stage 1 comienza en 'sunny' (Soleado)")

	# Caso 2: Nublado
	var ok_cloudy = manager.begin_event({"seed": 1974, "preview": true, "initial_weather": "cloudy"})
	check(ok_cloudy, "Evento generado con initial_weather=cloudy")
	var z0_cloudy: Dictionary = manager.weather_schedule[0]["zones"][0]
	check(str(z0_cloudy.get("weather_state_id", "")) == "cloudy", "Zona 0 de Stage 1 comienza en 'cloudy' (Nublado)")

	# Caso 3: Lluvia
	var ok_rain = manager.begin_event({"seed": 1974, "preview": true, "initial_weather": "medium_precipitation"})
	check(ok_rain, "Evento generado con initial_weather=medium_precipitation")
	var z0_rain: Dictionary = manager.weather_schedule[0]["zones"][0]
	check(str(z0_rain.get("weather_state_id", "")) == "medium_precipitation", "Zona 0 de Stage 1 comienza en 'medium_precipitation' (Lluvia)")
	check(float((z0_rain.get("climate", {}) as Dictionary).get("precipitation_mm_h", 0.0)) >= 3.0, "Precipitación activa en mm/h")
	check(str(z0_rain.get("precipitation_kind", "")) == "rain", "Tipo de precipitación es lluvia")

	# Caso 4: Aleatorio (conserva comportamiento dinámico)
	var ok_rand = manager.begin_event({"seed": 1974, "preview": true, "initial_weather": "random"})
	check(ok_rand, "Evento generado con initial_weather=random")
	check(manager.weather_schedule[0]["zones"].size() == 3, "Zona 0 válida en aleatorio")
