extends SceneTree

var menu_scene: RallyManiacMenu
var frame_count := 0
var brain_dir := "C:/Users/bill/.gemini/antigravity/brain/f555cd39-d09d-485e-9ac7-83b5ba3bd42a/"

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)

	menu_scene = load("res://scenes/rally/rally_maniac_menu.tscn").instantiate()
	root.add_child(menu_scene)
	current_scene = menu_scene

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 10:
		# Mostrar selector de tramos
		menu_scene.show_stage_select()
	elif frame_count == 25:
		# Capturar la pantalla de selección de tramos con el carrusel de 4 tramos y botones de flecha
		_save_capture("minimal_stage_select_v2.png")
		print("Capturado Stage Select Strip v2")
		# Mover carrusel a la derecha con el botón next para comprobar navegación
		if menu_scene.btn_carousel_next and not menu_scene.btn_carousel_next.disabled:
			menu_scene._on_carousel_next_pressed()
	elif frame_count == 50:
		_save_capture("minimal_stage_select_scrolled.png")
		print("Capturado Stage Select Scrolled")
		quit(0)
	return false

func _save_capture(filename: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if img != null:
		var p_brain := brain_dir + filename
		img.save_png(p_brain)
		print("Guardada captura: ", p_brain)
