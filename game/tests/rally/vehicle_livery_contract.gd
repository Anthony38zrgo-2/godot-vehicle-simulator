extends SceneTree

const LiveryScript := preload("res://scripts/rally/rally_vehicle_livery.gd")
const EventManagerScript := preload("res://scripts/rally/rally_event_manager.gd")

const EXPECTED_LIVERIES := [
	{"id": "rojo_brillante", "name": "Rojo brillante", "hex": "#D51E22"},
	{"id": "burdeos", "name": "Burdeos", "hex": "#782B3B"},
	{"id": "naranja", "name": "Naranja", "hex": "#E87524"},
	{"id": "amarillo", "name": "Amarillo", "hex": "#E6BE29"},
	{"id": "azul_oscuro", "name": "Azul oscuro", "hex": "#244579"},
	{"id": "azul_frances", "name": "Azul francés", "hex": "#326DC1"},
	{"id": "celeste", "name": "Celeste", "hex": "#78A9CF"},
	{"id": "verde_petroleo", "name": "Verde petróleo", "hex": "#15534F"},
	{"id": "verde_britanico", "name": "Verde británico", "hex": "#25452D"},
	{"id": "verde_oliva", "name": "Verde oliva", "hex": "#858B48"},
	{"id": "cobrizo", "name": "Cobrizo", "hex": "#986443"},
	{"id": "marfil", "name": "Marfil", "hex": "#D8C8A8"},
	{"id": "negro", "name": "Negro", "hex": "#202124"},
	{"id": "grafito", "name": "Grafito", "hex": "#555A60"},
	{"id": "plateado", "name": "Plateado", "hex": "#BFC3C8"},
	{"id": "blanco", "name": "Blanco", "hex": "#EEEEEC"},
]

var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAILURE: " + message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	print("--- VEHICLE LIVERY CONTRACT ---")
	test_catalog_completeness()
	test_cortina_and_mini_special_rules()
	await test_all_cdi_cars_shader_binding()
	await test_menu_livery_picker_and_showroom()
	test_event_manager_livery_persistence()

	print("VEHICLE_LIVERY_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)


func test_catalog_completeness() -> void:
	print("[1] Comprobando catálogo de 16 liveries exactas...")
	var liveries := LiveryScript.get_liveries()
	check(liveries.size() == 16, "El catálogo debe contener exactamente 16 liveries (actual: %d)" % liveries.size())
	for i in mini(EXPECTED_LIVERIES.size(), liveries.size()):
		var exp: Dictionary = EXPECTED_LIVERIES[i]
		var act: Dictionary = liveries[i]
		check(str(act.get("id", "")) == exp["id"], "Livery #%d ID esperado '%s', actual '%s'" % [i + 1, exp["id"], str(act.get("id", ""))])
		check(str(act.get("name", "")) == exp["name"], "Livery #%d nombre esperado '%s', actual '%s'" % [i + 1, exp["name"], str(act.get("name", ""))])
		check(str(act.get("hex", "")).to_upper() == exp["hex"], "Livery #%d hex esperado '%s', actual '%s'" % [i + 1, exp["hex"], str(act.get("hex", ""))])


func test_cortina_and_mini_special_rules() -> void:
	print("[2] Comprobando reglas especiales de Lotus Cortina (franja verde) y Mini Cooper (techo blanco)...")
	var cortina_orig := LiveryScript.build_shader_params("rt-lotus-cortina", "blanco")
	var cortina_red := LiveryScript.build_shader_params("rt-lotus-cortina", "rojo_brillante")
	check(is_equal_approx(float(cortina_orig.get("mask_threshold", 0.0)), 0.80), "Lotus Cortina en blanco (original) debe preservar la franja verde (threshold=0.80)")
	check(is_equal_approx(float(cortina_red.get("mask_threshold", 0.0)), 0.30), "Lotus Cortina en rojo_brillante debe pintar sobre la franja verde (threshold=0.30)")

	var mini_cfg := LiveryScript.get_vehicle_config("rt-mini-cooper-s")
	var mini_path := str(mini_cfg.get("data_map", ""))
	check(FileAccess.file_exists(mini_path), "Mapa de livery del Mini Cooper S existe: " + mini_path)
	var img := Image.load_from_file(ProjectSettings.globalize_path(mini_path))
	check(img != null and not img.is_empty(), "Imagen livery_data del Mini Cooper S legible")
	if img != null and not img.is_empty():
		var roof_px := img.get_pixel(300, 180)
		var hood_px := img.get_pixel(140, 180)
		check(roof_px.r < 0.1, "Techo blanco del Mini Cooper S debe permanecer sin máscara (R=%.2f)" % roof_px.r)
		check(hood_px.r > 0.9, "Capó del Mini Cooper S debe estar enmascarado como carrocería (R=%.2f)" % hood_px.r)


func test_all_cdi_cars_shader_binding() -> void:
	print("[3] Comprobando aplicación PSX livery en los coches de CDI_CARS...")
	var reg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/vehicles/registry.json"))
	var vehicles: Dictionary = reg.get("vehicles", {})
	check(RallyManiacMenu.CDI_CARS.size() == 12, "CDI_CARS debe contener 12 vehículos")
	for car_key in RallyManiacMenu.CDI_CARS:
		var vcfg := LiveryScript.get_vehicle_config(car_key)
		check(not vcfg.is_empty(), "Configuración de livery presente para " + car_key)
		var data_path := str(vcfg.get("data_map", ""))
		check(FileAccess.file_exists(data_path), "Mapa RGBA de livery existe para %s (%s)" % [car_key, data_path])
		var scene_name := str((vehicles.get(car_key, {}) as Dictionary).get("Scene", ""))
		var scene_path := "res://scenes/rally/%s.tscn" % scene_name
		var packed := load(scene_path) as PackedScene
		check(packed != null, "Escena del coche carga: " + scene_path)
		if packed == null:
			continue
		var car_node := packed.instantiate()
		if car_node is RigidBody3D:
			car_node.freeze = true
		car_node.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(car_node)
		await process_frame
		var updated := LiveryScript.apply_to_vehicle(car_node, car_key, "azul_frances")
		check(updated >= 1, "apply_to_vehicle actualizó >= 1 material de pintura en %s (actual: %d)" % [car_key, updated])
		car_node.queue_free()
		await process_frame


func test_menu_livery_picker_and_showroom() -> void:
	print("[4] Comprobando selector de color en RallyManiacMenu y vista previa 3D...")
	var menu := (load("res://scenes/rally/rally_maniac_menu.tscn") as PackedScene).instantiate() as RallyManiacMenu
	root.add_child(menu)
	current_scene = menu
	await process_frame
	await process_frame

	menu.show_stage_select()
	await process_frame
	menu.show_car_select()
	await process_frame
	await process_frame

	check(menu.livery_buttons.size() == 16, "El selector de color muestra exactamente 16 swatches")
	menu._select_livery("verde_petroleo")
	await process_frame
	check(menu.selected_livery_id == "verde_petroleo", "Livery seleccionada es verde_petroleo")
	check(menu.livery_name_label.text == "VERDE PETRÓLEO", "Etiqueta muestra VERDE PETRÓLEO")
	check(menu.livery_hex_label.text == "#15534F", "Hex muestra #15534F")

	menu._cycle_livery(1)
	check(menu.selected_livery_id == "verde_britanico", "Ciclo siguiente pasa a verde_britanico")
	menu._cycle_livery(-1)
	check(menu.selected_livery_id == "verde_petroleo", "Ciclo anterior vuelve a verde_petroleo")

	# Verificar que el coche 3D del showroom recibió la livery horneada (#15534F)
	var chassis := menu.current_car_model_instance.get_node_or_null("Chassis")
	var found_livery_shader := false
	if chassis != null:
		for mnode in chassis.find_children("*", "MeshInstance3D", true, false):
			var mi := mnode as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var sm := mi.get_surface_override_material(s) as ShaderMaterial
				if sm != null and bool(sm.get_meta("livery_enabled", false)):
					var col_v: Vector3 = sm.get_meta("livery_color_srgb", Vector3.ZERO)
					var expected := Color("#15534F")
					if str(sm.get_meta("livery_id", "")) == "verde_petroleo" and col_v.distance_to(Vector3(expected.r, expected.g, expected.b)) < 0.01:
						found_livery_shader = true
	check(found_livery_shader, "El coche 3D del showroom refleja inmediatamente la livery seleccionada (#15534F)")

	menu.queue_free()
	await process_frame


func test_event_manager_livery_persistence() -> void:
	print("[5] Comprobando persistencia de livery en RallyEventManager (save/restore)...")
	var tmp_save := "user://test_livery_event_persist.json"
	var mgr := EventManagerScript.new()
	var ok := mgr.begin_event({
		"event_path": "cdi",
		"start_stage_id": "cdi_stage1",
		"livery_id": "cobrizo",
		"save_path": tmp_save,
		"seed": 1974,
	})
	check(ok, "RallyEventManager inicia evento CDI con livery_id='cobrizo'")
	check(mgr.selected_livery_id == "cobrizo", "RallyEventManager guarda selected_livery_id='cobrizo'")
	check(mgr.save(), "RallyEventManager guarda JSON correctamente")

	var mgr2 := EventManagerScript.new()
	mgr2.save_path = tmp_save
	check(mgr2.load_event("res://data/competition/events/cdi_rally.json"), "Carga evento CDI para restore")
	check(mgr2.restore(), "RallyEventManager restaura JSON guardado")
	check(mgr2.selected_livery_id == "cobrizo", "RallyEventManager preserva selected_livery_id='cobrizo' tras restore")

	if FileAccess.file_exists(tmp_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_save))
