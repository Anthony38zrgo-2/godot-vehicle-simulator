extends SceneTree

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAILURE: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("--- CAR SELECT GUI REDESIGN ACCEPTANCE CONTRACT ---")
	var menu_scene: RallyManiacMenu = load("res://scenes/rally/rally_maniac_menu.tscn").instantiate()
	root.add_child(menu_scene)
	current_scene = menu_scene
	await process_frame
	await process_frame

	print("[1] Navegando a pantalla de selección de coches...")
	menu_scene.show_stage_select()
	await process_frame
	menu_scene.show_car_select()
	await process_frame
	await process_frame

	check(menu_scene.current_screen == "car_select", "Pantalla actual es car_select")
	check(menu_scene.preview_viewport != null, "SubViewport 3D de previsualización instanciado")
	check(menu_scene.car_turntable != null, "Mesa giratoria 3D presente")
	check(menu_scene.current_car_model_instance != null, "Modelo 3D del coche instanciado en showroom")

	print("[2] Comprobando resumen de características del coche por defecto (Lancia Fulvia HF - FF)...")
	check(menu_scene.preview_car_title != null and "Fulvia" in menu_scene.preview_car_title.text, "Título muestra Fulvia")
	check(menu_scene.preview_layout_badge != null and menu_scene.preview_layout_badge.text == "FF", "Badge muestra disposición FF")
	check(menu_scene.spec_power_val != null and "CV" in menu_scene.spec_power_val.text and "kW" in menu_scene.spec_power_val.text, "Especificación de potencia presente")
	check(menu_scene.spec_gears_val != null and "5 marchas" in menu_scene.spec_gears_val.text, "Especificación de número de marchas (5 marchas)")
	check(menu_scene.spec_wb_val != null and "m" in menu_scene.spec_wb_val.text, "Especificación de wheelbase presente en metros")
	check(menu_scene.spec_track_val != null and "m" in menu_scene.spec_track_val.text and "/" in menu_scene.spec_track_val.text, "Especificación de trochas (del/tras)")
	check(menu_scene.spec_mass_val != null and "kg" in menu_scene.spec_mass_val.text, "Especificación de peso mínimo en kg")
	check(menu_scene.spec_layout_val != null and "FF" in menu_scene.spec_layout_val.text and "Tracción delantera" in menu_scene.spec_layout_val.text, "Especificación de tracción FF presente")

	print("[3] Comprobando rotación continua del modelo 3D...")
	var initial_rot: float = menu_scene.car_turntable.rotation.y
	menu_scene._process(1.0)
	var new_rot: float = menu_scene.car_turntable.rotation.y
	check(new_rot != initial_rot, "La mesa giratoria rota con el paso del tiempo (_process)")

	print("[4] Cambiando a Ford Escort RS2000 (FR) y verificando reactividad de ficha técnica y modelo...")
	menu_scene._preview_car("escort")
	await process_frame
	await process_frame

	check("Escort" in menu_scene.preview_car_title.text, "Título cambia a Escort")
	check(menu_scene.preview_layout_badge.text == "FR", "Badge cambia a FR")
	check("FR" in menu_scene.spec_layout_val.text and "trasera" in menu_scene.spec_layout_val.text, "Tracción indica FR / Propulsión trasera")
	check("4 marchas" in menu_scene.spec_gears_val.text, "Marchas del Escort actualizadas (4 marchas)")
	check("2.41 m" in menu_scene.spec_wb_val.text, "Wheelbase del Escort es 2.41 m")
	check("m" in menu_scene.spec_track_val.text, "Trochas del Escort actualizadas")
	check(menu_scene.current_car_model_instance != null and "Escort" in menu_scene.current_car_model_instance.name, "Modelo 3D actualizado al Escort")

	print("[5] Comprobando interacción mediante botón Confirmar Selección...")
	check(menu_scene.btn_car_confirm != null, "Botón de confirmación presente")
	check(menu_scene.btn_car_confirm.text.find("Conducir") != -1 or menu_scene.btn_car_confirm.text.find("Seleccionar") != -1, "Texto descriptivo de confirmación")

	menu_scene.queue_free()
	await process_frame

	print("CAR_SELECT_GUI_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
