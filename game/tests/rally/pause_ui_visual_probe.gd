extends SceneTree

var escort_scene: PackedScene = preload("res://scenes/rally/ford_escort_rs2000_1971.tscn")
var pause_script: GDScript = preload("res://scripts/rally/rally_pause_inventory.gd")

var root_node: Node3D
var vehicle: RallyEscortVehicle
var pause_menu: CanvasLayer
var frame_count := 0
var out_dir := "user://pause_redesign/"
var brain_dir := "C:/Users/bill/.gemini/antigravity/brain/903e96ef-d92d-42eb-96b3-8a01280574f5/"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)

	root_node = Node3D.new()
	root.add_child(root_node)

	vehicle = escort_scene.instantiate() as RallyEscortVehicle
	root_node.add_child(vehicle)

	# Mock session with all necessary objects
	var dummy_script = GDScript.new()
	dummy_script.source_code = """extends Node
var vehicle: Node
var session_ready: bool = true
var awaiting_setup: bool = false
var stage_transition_running: bool = false
var competition = null
var course = null
var garage_panel = null
var pacenotes = null
var event_manager = null
var session_track_id: String = "russia_stage1"
func may_service_tires() -> bool: return true
func on_vehicle_reset_requested() -> void: pass
func retire_competition_player() -> void: pass
func on_quick_repair_radiator_requested() -> void: pass
"""
	dummy_script.reload()
	var dummy_session = dummy_script.new()
	dummy_session.vehicle = vehicle

	var comp_script = preload("res://scripts/rally/rally_competition.gd")
	var comp = comp_script.new()
	comp.save_path = ""
	comp.configure("res://data/competition/stages/russia_stage1.json", 1974)
	comp.player_penalty_ms = 0
	dummy_session.competition = comp

	var course_script = preload("res://scripts/rally/rally_stage_progress.gd")
	var course = course_script.new()
	course.elapsed_s = 102.85
	dummy_session.course = course

	pause_menu = pause_script.new()
	pause_menu.session = dummy_session
	root.add_child(pause_menu)

func _process(delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		# 1. Abrir menú de pausa principal
		vehicle.ensure_tire_inventory()
		vehicle.sync_tire_inventory()
		pause_menu.modal.show()
		pause_menu.backdrop.show()
		pause_menu.show_menu()
		print("Pause menu opened")
	elif frame_count == 6:
		_save_capture("pause_menu_720.png")
		# 2. Abrir menú de neumáticos e inventario con daños de prueba
		if vehicle.simulation != null and vehicle.simulation.thermal_model != null:
			# Rueda 1 (FR): Pinchada y rin deformado
			var st_fr: Dictionary = vehicle.simulation.thermal_model.tire_states[1]
			st_fr.wear_fraction = 0.65
			st_fr.leak_per_second = 0.04
			st_fr.pressure_loss_fraction = 0.88
			st_fr.rim_deformation = 0.32
			st_fr.tread_c = 82.0
			# Rueda 2 (RL): Desgaste moderado
			var st_rl: Dictionary = vehicle.simulation.thermal_model.tire_states[2]
			st_rl.wear_fraction = 0.42
			st_rl.tread_c = 71.0
		vehicle.sync_tire_inventory()
		pause_menu.selected_wheel = 1
		pause_menu.show_inventory()
		print("Tires inventory opened")
	elif frame_count == 9:
		_save_capture("pause_tires_720.png")
		# 3. Simular daño en radiador y abrir reparaciones rápidas
		if vehicle.simulation != null and vehicle.simulation.thermal_model != null:
			vehicle.simulation.thermal_model.radiator_damage = 0.28
		pause_menu.show_quick_repairs()
		print("Quick repairs opened")
	elif frame_count == 12:
		_save_capture("pause_repairs_720.png")
		print("PAUSE_UI_VISUAL_PROBE PASS")
		quit(0)
	return false

func _save_capture(filename: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if img != null:
		var p := out_dir + filename
		img.save_png(p)
		var p_brain := brain_dir + filename
		img.save_png(p_brain)
		print("Saved capture: ", filename)
