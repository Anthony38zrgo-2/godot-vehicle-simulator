extends SceneTree

var escort_scene: PackedScene = preload("res://scenes/rally/ford_escort_rs2000_1971.tscn")
var garage_script: GDScript = preload("res://scripts/rally/rally_garage_panel.gd")

var root_node: Node3D
var vehicle: RallyEscortVehicle
var garage: Control
var frame_count := 0
var out_dir := "user://garage_recalibrated_v2/"

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
	if frame_count == 3:
		garage.set("vehicle", vehicle)
		garage.call("open_garage_for_event", {
			"forecast_summary": "Cielo nublado · Humedad 60%",
			"forecast_advice": "Compuesto sugerido: Normal",
			"window_label": "Asistencia Previa al Rally"
		})
		print("Garage opened: visible=", garage.visible, " page=", garage.get("page"))
	elif frame_count == 6:
		_save_capture("page_0.png")
		garage.call("_set_page", 1)
	elif frame_count == 9:
		_save_capture("page_1.png")
		garage.call("_set_page", 2)
	elif frame_count == 12:
		_save_capture("page_2.png")
		garage.call("_set_page", 3)
	elif frame_count == 15:
		_save_capture("page_3.png")
		garage.call("_set_page", 4)
	elif frame_count == 18:
		_save_capture("page_4.png")
		garage.set("modal_mode", "name")
		garage.set("modal_text", "Rally Asfalto Mixto")
		garage.queue_redraw()
	elif frame_count == 21:
		_save_capture("modal_name.png")
		print("All captures completed successfully!")
		quit(0)
	return false

func _save_capture(filename: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if img != null:
		var p := out_dir + filename
		img.save_png(p)
		print("Captured: ", filename)
