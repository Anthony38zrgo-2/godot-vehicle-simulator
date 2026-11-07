extends SceneTree

var menu_scene: RallyManiacMenu
var frame_count := 0
var brain_dir := "C:/Users/bill/.gemini/antigravity/brain/6b7a48bc-07f8-4e1a-9c21-cf3cd1328f0a/"

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)

	menu_scene = load("res://scenes/rally/rally_maniac_menu.tscn").instantiate()
	root.add_child(menu_scene)
	current_scene = menu_scene

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 10:
		menu_scene.show_stage_select()
	elif frame_count == 20:
		menu_scene.show_car_select()
	elif frame_count == 30:
		# Mostrar selector de clima antes de empezar el rally
		menu_scene.show_weather_select()
	elif frame_count == 40:
		_save_capture("weather_select_screen.png")
		print("Capturado Weather Select Screen")
	elif frame_count == 50:
		# Seleccionar Lluvia para comprobar feedback visual
		menu_scene._select_weather("medium_precipitation")
	elif frame_count == 60:
		_save_capture("weather_select_rain.png")
		print("Capturado Weather Select Rain")
		quit(0)
	return false

func _save_capture(filename: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if img != null:
		var p_brain := brain_dir + filename
		img.save_png(p_brain)
		print("Guardada captura: ", p_brain)
