extends SceneTree

var escort_scene: PackedScene = preload("res://scenes/rally/ford_escort_rs2000_1971.tscn")
var garage_script: GDScript = preload("res://scripts/rally/rally_garage_panel.gd")

var root_node: Node3D
var vehicle: RallyEscortVehicle
var garage: Control
var frame_count := 0
var out_dir := "user://garage_workbench/"
var brain_dir := "C:/Users/bill/.gemini/antigravity/brain/f555cd39-d09d-485e-9ac7-83b5ba3bd42a/"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	DisplayServer.window_set_size(Vector2i(1280, 800))
	root.size = Vector2i(1280, 800)
	
	root_node = Node3D.new()
	root.add_child(root_node)
	
	vehicle = escort_scene.instantiate() as RallyEscortVehicle
	root_node.add_child(vehicle)
	
	garage = Control.new()
	garage.set_script(garage_script)
	garage.size = Vector2(1280, 800)
	garage.set("vehicle", vehicle)
	root_node.add_child(garage)

func _process(delta: float) -> bool:
	frame_count += 1
	if frame_count == 4:
		garage.set("vehicle", vehicle)
		garage.call("open_garage_for_event", {
			"forecast_summary": "Cielo nublado · Humedad 60%",
			"forecast_advice": "Compuesto sugerido: Normal",
			"window_label": "Inicio · Stage 1"
		})
		garage.call("_set_page", 0)
		garage.queue_redraw()
		print("Garage opened: visible=", garage.visible, " page=", garage.get("page"))
	elif frame_count == 8:
		_save_capture("workbench_page_0_rapido.png")
		garage.call("_set_page", 1)
		garage.set("advanced_section", 0)
		garage.queue_redraw()
	elif frame_count == 12:
		_save_capture("workbench_page_1_avanzado.png")
		garage.call("_set_page", 2)
		garage.queue_redraw()
	elif frame_count == 16:
		_save_capture("workbench_page_2_estrategia.png")
		garage.call("_set_page", 3)
		garage.queue_redraw()
	elif frame_count == 20:
		_save_capture("workbench_page_3_perfiles.png")
		print("All Workbench captures completed successfully!")
		quit(0)
	return false

func _save_capture(filename: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if img != null:
		var p := out_dir + filename
		img.save_png(p)
		var p_brain := brain_dir + filename
		img.save_png(p_brain)
		print("Captured: ", filename, " to ", p_brain)
