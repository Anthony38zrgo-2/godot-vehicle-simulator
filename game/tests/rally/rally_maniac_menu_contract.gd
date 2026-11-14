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
	print("--- RALLY MANIAC MENU ACCEPTANCE CONTRACT ---")
	await test_menu_structure_and_order()
	await test_navigation_and_focus()
	await test_error_handling_and_loading_state()
	await test_rally_event_itinerary_slicing()
	await test_single_stage_and_championship_isolation()
	await test_stage_session_setup_and_freeze()
	await test_menu_to_garage_music_flow()

	print("RALLY_MANIAC_MENU_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)


func test_menu_structure_and_order() -> void:
	print("[1] Comprobando estructura y orden de botones de Rally Maniac...")
	var menu_scene = load("res://scenes/rally/rally_maniac_menu.tscn").instantiate()
	root.add_child(menu_scene)
	current_scene = menu_scene
	await process_frame

	check(menu_scene.header_title != null and menu_scene.header_title.text == "Rally Maniac", "El título exacto debe ser 'Rally Maniac'")
	var title_font = menu_scene.header_title.get_theme_font("font")
	check(title_font != null and (title_font.resource_path.ends_with("bungee_regular.tres") or (title_font is FontVariation and title_font.base_font != null and title_font.base_font.resource_path.ends_with("Bungee-Regular.ttf"))), "El título principal debe usar Bungee Regular")
	check(menu_scene.btn_championship != null and menu_scene.btn_championship.text == "Campeonato", "Primer botón debe ser Campeonato")
	check(menu_scene.btn_rally != null and menu_scene.btn_rally.text == "Rally", "Segundo botón debe ser Rally")
	check(menu_scene.btn_single_stage != null and menu_scene.btn_single_stage.text == "Tramo Único", "Tercer botón debe ser Tramo Único")
	check(menu_scene.btn_exit != null and menu_scene.btn_exit.text == "Salir", "Cuarto botón debe ser Salir")

	# Verificar orden en el contenedor horizontal de botones (dock inferior)
	var btn_parent = menu_scene.btn_championship.get_parent()
	check(btn_parent is HBoxContainer, "El dock de botones principal debe ser HBoxContainer horizontal")
	var children = btn_parent.get_children()
	check(children.size() >= 4, "Debe haber al menos 4 botones en el contenedor principal")
	check(children[0] == menu_scene.btn_championship, "Orden 1: Championship")
	check(children[1] == menu_scene.btn_rally, "Orden 2: Rally")
	check(children[2] == menu_scene.btn_single_stage, "Orden 3: Single Stage")
	check(children[3] == menu_scene.btn_exit, "Orden 4: Exit")
	check(menu_scene.btn_championship.focus_neighbor_right == menu_scene.btn_championship.get_path_to(menu_scene.btn_rally), "Foco horizontal derecho: Campeonato -> Rally")
	check(menu_scene.btn_championship.focus_neighbor_left == menu_scene.btn_championship.get_path_to(menu_scene.btn_exit), "Foco horizontal izquierdo cíclico: Campeonato -> Salir")
	check(menu_scene.btn_exit.focus_neighbor_right == menu_scene.btn_exit.get_path_to(menu_scene.btn_championship), "Foco horizontal derecho cíclico: Salir -> Campeonato")
	await process_frame
	check(menu_scene.size.y > 0.0 and btn_parent.global_position.y > menu_scene.size.y * 0.6, "El dock horizontal debe situarse en la zona inferior")
	check(menu_scene.btn_rally.global_position.x > menu_scene.btn_championship.global_position.x and menu_scene.btn_exit.global_position.x > menu_scene.btn_single_stage.global_position.x, "Los botones deben distribuirse horizontalmente de izquierda a derecha")

	menu_scene.queue_free()
	await process_frame


func test_navigation_and_focus() -> void:
	print("[2] Comprobando navegación entre pantallas, botones Back y retención de foco...")
	var menu_scene = load("res://scenes/rally/rally_maniac_menu.tscn").instantiate()
	root.add_child(menu_scene)
	current_scene = menu_scene
	await process_frame
	await process_frame

	# Foco inicial en Championship
	check(menu_scene.btn_championship.has_focus(), "Foco inicial visible en Championship")

	# Seleccionar modo Rally
	menu_scene.btn_rally.emit_signal("pressed")
	await process_frame
	await process_frame

	check(menu_scene.current_screen == "stage_select", "Pantalla cambia a stage_select")
	check(menu_scene.selected_mode == "rally", "Modo seleccionado es rally")
	check(menu_scene.stage_buttons.size() == 10, "Selector contiene 10 tramos rusos")

	for i in range(10):
		var expected_id := "russia_stage%d" % (i + 1)
		var expected_label := "Russia Stage %d" % (i + 1)
		var btn: Button = menu_scene.stage_buttons[i]
		check(btn.text == expected_label, "Texto tramo %d: %s" % [i + 1, expected_label])
		check(str(btn.get_meta("stage_id", "")) == expected_id, "ID interno tramo %d: %s" % [i + 1, expected_id])

	# Foco en el tramo por defecto (Stage 1)
	check(menu_scene.stage_buttons[0].has_focus(), "Foco en Stage 1 al entrar al selector de tramos")

	# Seleccionar Stage 4 y entrar a selector de coches
	menu_scene.stage_buttons[3].emit_signal("pressed")
	await process_frame
	await process_frame

	check(menu_scene.current_screen == "car_select", "Pantalla cambia a car_select")
	check(menu_scene.selected_stage_id == "russia_stage4", "Tramo seleccionado es russia_stage4")
	check(menu_scene.car_scroll != null, "Selector de coches tiene un ScrollContainer para scroll interactivo")
	check(menu_scene.car_scroll.follow_focus, "ScrollContainer de coches sigue el foco del teclado")
	check(menu_scene.car_buttons.size() >= 2, "Selector contiene coches del registro")
	check(menu_scene.car_buttons[0].text in ["Lancia Fulvia HF", "Ford Escort RS2000"], "Coche 1 DisplayName válido")
	check(menu_scene.car_buttons[1].text in ["Lancia Fulvia HF", "Ford Escort RS2000"], "Coche 2 DisplayName válido")
	check(menu_scene.car_buttons[0].has_focus(), "Foco en primer coche al entrar al selector de coches")

	# Probar scroll del selector de coches: foco en el último coche debe desplazar scroll_vertical
	if menu_scene.car_buttons.size() > 5:
		var last_btn: Button = menu_scene.car_buttons[menu_scene.car_buttons.size() - 1]
		last_btn.grab_focus()
		await process_frame
		await process_frame
		check(menu_scene.car_scroll.scroll_vertical > 0, "ScrollContainer desplaza el scroll verticalmente al seleccionar coches inferiores")

	# Probar Back en selector de coches -> debe volver a Stage Select con Stage 4 enfocado
	menu_scene.btn_car_back.emit_signal("pressed")
	await process_frame
	await process_frame

	check(menu_scene.current_screen == "stage_select", "Volver desde coche lleva a stage_select")
	check(menu_scene.stage_buttons[3].has_focus(), "Foco conservado en Stage 4 tras pulsar Back")

	# Probar Back en selector de tramos -> debe volver al Menú Principal con Rally enfocado
	menu_scene.btn_stage_back.emit_signal("pressed")
	await process_frame
	await process_frame

	check(menu_scene.current_screen == "menu", "Volver desde tramo lleva a menu")
	check(menu_scene.btn_rally.has_focus(), "Foco conservado en botón Rally tras pulsar Back")

	menu_scene.queue_free()
	await process_frame


func test_error_handling_and_loading_state() -> void:
	print("[3] Comprobando control de errores, bloqueo de clics y ausencia de sustitución...")
	var menu_scene = load("res://scenes/rally/rally_maniac_menu.tscn").instantiate()
	root.add_child(menu_scene)
	current_scene = menu_scene
	await process_frame

	menu_scene.selected_stage_id = "russia_stage99_inexistente"
	menu_scene.selected_car_key = "fulvia"
	menu_scene._launch_session()
	await process_frame

	check(menu_scene.status_banner.visible, "Banner de error debe ser visible tras ID de tramo inválido")
	check(menu_scene.status_label.text.find("ID de tramo no válido") != -1 or menu_scene.status_label.text.find("Fallo al resolver recursos") != -1, "Mensaje identifica fallo del tramo")
	check(not menu_scene.is_loading, "Estado de carga desbloqueado tras error para permitir corregir")
	check(not menu_scene.btn_car_back.disabled, "Botón Back habilitado tras error")

	menu_scene.queue_free()
	await process_frame


func test_rally_event_itinerary_slicing() -> void:
	print("[4] Comprobando inicio de evento Rally en tramo intermedio (Stage 9 y Stage 10)...")
	var EventManagerScript = load("res://scripts/rally/rally_event_manager.gd")
	var manager9 = EventManagerScript.new()
	var ok9: bool = manager9.begin_event({"start_stage_id": "russia_stage9", "preview": true})
	check(ok9, "Evento Rally puede iniciar desde russia_stage9")
	check(manager9.stage_order.size() == 2, "Itinerario desde Stage 9 contiene exactamente 2 tramos")
	check(manager9.stage_order[0] == "russia_stage9", "Primer tramo del itinerario es russia_stage9")
	check(manager9.stage_order[1] == "russia_stage10", "Segundo tramo del itinerario es russia_stage10")
	check(manager9.current_stage_id() == "russia_stage9", "Tramo activo inicial es russia_stage9")
	check(manager9.cursor == 0, "Cursor inicial es 0")
	var win9: Dictionary = manager9.get_pending_window()
	check(not win9.is_empty() and str(win9.get("window_key", "")) == "initial", "Ventana inicial presente")

	var manager10 = EventManagerScript.new()
	var ok10: bool = manager10.begin_event({"start_stage_id": "russia_stage10", "preview": true})
	check(ok10, "Evento Rally puede iniciar desde russia_stage10")
	check(manager10.stage_order.size() == 1, "Itinerario desde Stage 10 contiene exactamente 1 tramo")
	check(manager10.stage_order[0] == "russia_stage10", "Único tramo del itinerario es russia_stage10")
	check(manager10.current_stage_id() == "russia_stage10", "Tramo activo inicial es russia_stage10")


func test_single_stage_and_championship_isolation() -> void:
	print("[5] Comprobando aislamiento de guardado oficial en Single Stage y progresión en Championship...")
	# 1. Comprobar que en single_stage la sesión es aislada y no permite pasar al siguiente tramo
	var session_scene = load("res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn").instantiate()
	session_scene.track_id = "russia_stage2"
	session_scene.session_track_id = "russia_stage2"
	session_scene.session_mode = "single_stage"
	session_scene.selected_vehicle_key = "escort"
	session_scene.practice_mode = true
	session_scene.weather_enabled = false
	root.add_child(session_scene)
	current_scene = session_scene

	for i in 300:
		await physics_frame
		if session_scene.session_ready:
			break

	check(session_scene.session_ready, "Sesión de Single Stage lista")
	check(session_scene.event_manager == null, "Single Stage no tiene gestor oficial de evento")
	check(session_scene.competition.save_path == "", "save_path de competición debe estar vacío")
	var comp_state: Dictionary = session_scene.get_competition_panel_state()
	check(bool(comp_state.get("allow_next", true)) == false, "Single stage no debe permitir pasar al siguiente tramo")

	session_scene.queue_free()
	await process_frame

	# 2. Comprobar que Championship tiene gestor propio, progresión habilitada y guardado independiente
	var champ_scene = load("res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn").instantiate()
	champ_scene.track_id = "russia_stage1"
	champ_scene.session_track_id = "russia_stage1"
	champ_scene.session_mode = "championship"
	champ_scene.selected_vehicle_key = "escort"
	champ_scene.weather_enabled = false

	var champ_manager = EventManagerScript.new()
	var champ_ok: bool = champ_manager.begin_event({"start_stage_id": "russia_stage1", "save_path": "user://championship_event_v1.json", "preview": true})
	check(champ_ok, "Gestor de evento para Championship se inicia correctamente")
	check(champ_manager.save_path == "user://championship_event_v1.json", "Championship usa guardado independiente")
	champ_scene.begin_event_session(champ_manager, "russia_stage1")

	root.add_child(champ_scene)
	current_scene = champ_scene

	for i in 300:
		await physics_frame
		if champ_scene.session_ready:
			break

	check(champ_scene.session_ready, "Sesión de Championship lista")
	check(champ_scene.event_manager != null, "Championship tiene gestor de evento")
	var champ_comp_state: Dictionary = champ_scene.get_competition_panel_state()
	check(bool(champ_comp_state.get("allow_next", true)) == true, "Championship debe permitir pasar al siguiente tramo")

	champ_scene.queue_free()
	await process_frame


func test_stage_session_setup_and_freeze() -> void:
	print("[6] Comprobando rótulo de reglajes, congelación y apertura previa para Stage 1 y Stage 10 con ambos coches...")
	var test_matrix := [
		{"car_key": "escort", "scene": "russia_stage1_ford_escort_rs2000", "stage": "russia_stage1", "num": 1},
		{"car_key": "escort", "scene": "russia_stage1_ford_escort_rs2000", "stage": "russia_stage10", "num": 10},
		{"car_key": "fulvia", "scene": "russia_stage1_lancia_fulvia", "stage": "russia_stage1", "num": 1},
		{"car_key": "fulvia", "scene": "russia_stage1_lancia_fulvia", "stage": "russia_stage10", "num": 10},
	]
	for item in test_matrix:
		var car_key: String = item["car_key"]
		var scene_name: String = item["scene"]
		var test_stage: String = item["stage"]
		var expected_stage_num: int = item["num"]

		var session_scene = load("res://scenes/rally/%s.tscn" % scene_name).instantiate()
		session_scene.track_id = test_stage
		session_scene.session_track_id = test_stage
		session_scene.session_mode = "single_stage"
		session_scene.selected_vehicle_key = car_key
		session_scene.practice_mode = true
		session_scene.weather_enabled = false
		root.add_child(session_scene)
		current_scene = session_scene

		for i in 300:
			await physics_frame
			if session_scene.session_ready:
				break

		check(session_scene.session_ready, "Sesión para %s con %s lista" % [test_stage, car_key])
		check(session_scene.awaiting_setup, "Sesión debe estar en espera de reglajes antes de iniciar en %s con %s" % [test_stage, car_key])
		check(session_scene.vehicle.freeze, "Vehículo debe estar congelado durante reglajes en %s con %s" % [test_stage, car_key])
		check(session_scene.event_clock.paused, "Reloj de eventos debe estar pausado durante reglajes en %s con %s" % [test_stage, car_key])
		check(not session_scene.input_controller.controls_enabled, "Controles deshabilitados durante reglajes en %s con %s" % [test_stage, car_key])

		var expected_label := "INICIO · STAGE %d" % expected_stage_num
		check(session_scene.garage_panel != null and session_scene.garage_panel.circuit_name == expected_label, "Rótulo del garaje debe ser '%s' (obtenido: '%s')" % [expected_label, session_scene.garage_panel.circuit_name if session_scene.garage_panel != null else "null"])

		# Confirmar reglaje
		session_scene.garage_panel.close_garage(true)
		await physics_frame
		await physics_frame

		check(not session_scene.awaiting_setup, "awaiting_setup debe ser false tras confirmar")
		check(not session_scene.vehicle.freeze, "Vehículo debe descongelarse tras confirmar reglajes")
		check(not session_scene.event_clock.paused, "Reloj debe reanudarse tras confirmar reglajes")
		check(session_scene.input_controller.controls_enabled, "Controles deben activarse tras confirmar reglajes")

		session_scene.queue_free()
		await process_frame


func test_menu_to_garage_music_flow() -> void:
	print("[7] Comprobando que el tema del menú sigue en garaje-reglajes (con corte y reinicio)...")
	var menu_scene = load("res://scenes/rally/rally_maniac_menu.tscn").instantiate()
	root.add_child(menu_scene)
	current_scene = menu_scene
	await process_frame
	await process_frame

	var music = root.get_node_or_null("RallyMusic")
	check(music != null, "Nodo RallyMusic debe existir en /root")
	if music != null:
		check(music.is_playing_menu_music(), "La música del menú debe estar reproduciéndose en el primer menú")
		check(music.menu_stream is AudioStreamMP3 and (music.menu_stream as AudioStreamMP3).loop, "El stream del menú debe ser AudioStreamMP3 con loop activo")

		# Navegar a stage_select, car_select y weather_select: la música debe seguir sonando
		menu_scene.show_stage_select()
		await process_frame
		check(music.is_playing_menu_music(), "La música debe seguir sonando en el selector de tramo")

		menu_scene.show_car_select()
		await process_frame
		check(music.is_playing_menu_music(), "La música debe seguir sonando en el selector de vehículo")

		menu_scene.show_weather_select()
		await process_frame
		check(music.is_playing_menu_music(), "La música debe seguir sonando en el selector de clima")

	menu_scene.queue_free()
	await process_frame

	# Ahora entrar a una sesión que abre garaje-reglajes
	var session_scene = load("res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn").instantiate()
	session_scene.track_id = "russia_stage1"
	session_scene.session_track_id = "russia_stage1"
	session_scene.session_mode = "single_stage"
	session_scene.selected_vehicle_key = "escort"
	session_scene.practice_mode = true
	session_scene.weather_enabled = false
	root.add_child(session_scene)
	current_scene = session_scene

	for i in 300:
		await physics_frame
		if session_scene.session_ready:
			break

	if music != null:
		check(music.is_playing_menu_music(), "La música del menú debe seguir en garaje-reglajes (mismo tema, con corte y reinicio)")
		check(music.menu_player.playing and music.menu_player.stream == music.menu_stream, "Garaje-reglajes debe sonar con menu_theme.mp3")
		check(music.current_context == "garage", "El contexto de música debe ser 'garage' al abrir garaje-reglajes")

	session_scene.queue_free()
	await process_frame
	if music != null and music.has_method("stop_menu_music"):
		music.call("stop_menu_music")
	await process_frame
	await process_frame

