extends SceneTree

var escort_scene: PackedScene = preload("res://scenes/rally/ford_escort_rs2000_1971.tscn")
var pause_script: GDScript = preload("res://scripts/rally/rally_pause_inventory.gd")

var root_node: Node3D
var vehicle: RallyEscortVehicle
var pause_menu: CanvasLayer
var frame_count := 0
var out_dir := "user://pause_redesign/"

func _init() -> void:
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
func on_quick_repair_radiator_requested(_heavy: bool = false) -> bool: return false
"""
	dummy_script.reload()
	var dummy_session = dummy_script.new()
	dummy_session.vehicle = vehicle
	root_node.add_child(dummy_session)

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

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		vehicle.ensure_tire_inventory()
		vehicle.sync_tire_inventory()
		pause_menu.modal.show()
		pause_menu.show_inventory()
	elif frame_count == 5:
		var workshop = pause_menu.content.get_child(0)
		var ids: Array = vehicle.tire_inventory.mounted.map(func(t): return t.id)
		workshop.select_slot(0)
		workshop.activate()
		assert(workshop.cancel_transfer())
		assert(vehicle.tire_inventory.mounted[0].id == ids[0])
		assert(not workshop.compatible(0, 4))
		workshop.select_slot(0)
		workshop.activate()
		workshop.select_slot(2)
		workshop.activate()
		assert(vehicle.tire_inventory.mounted[2].id == ids[0])
		assert(vehicle.tire_inventory.mounted[0].id == ids[2])
		workshop = pause_menu.content.get_child(0)
		var spare_id: int = vehicle.tire_inventory.spares[0].id
		workshop.select_slot(5)
		workshop.activate()
		workshop.select_slot(1)
		workshop.activate()
		assert(vehicle.tire_inventory.mounted[1].id == spare_id)
		assert(vehicle.tire_inventory.spares.any(func(t): return t.id == ids[1]))
		workshop = pause_menu.content.get_child(0)
		var event := InputEventJoypadButton.new()
		event.button_index = JOY_BUTTON_DPAD_RIGHT
		event.pressed = true
		workshop._input(event)
		assert(workshop.selected == 1)
		event.button_index = JOY_BUTTON_DPAD_DOWN
		workshop._input(event)
		assert(workshop.selected == 3)
		event.button_index = JOY_BUTTON_DPAD_UP
		workshop._input(event)
		assert(workshop.selected == 1)
		event.button_index = JOY_BUTTON_A
		workshop._input(event)
		assert(workshop.held == 1)
		assert(workshop.cancel_transfer())
		assert(workshop.copies.size() > 4)
		var repair_session = preload("res://scripts/rally/rally_russia_stage_session.gd").new()
		repair_session.vehicle = vehicle
		repair_session.competition = pause_menu.session.competition
		var thermal = vehicle.simulation.thermal_model
		thermal.radiator_damage = 0.8
		var before: int = repair_session.competition.player_penalty_ms
		assert(repair_session.on_quick_repair_radiator_requested(false))
		assert(is_equal_approx(thermal.radiator_damage,0.6))
		assert(repair_session.competition.player_penalty_ms == before + 30000)
		thermal.radiator_damage = 0.6
		assert(repair_session.on_quick_repair_radiator_requested(true))
		assert(is_equal_approx(thermal.radiator_damage,0.1))
		assert(not repair_session.on_quick_repair_radiator_requested(true))
		assert(is_equal_approx(thermal.radiator_damage,0.1))
		assert(not repair_session.on_quick_repair_radiator_requested(false))
		var saved: Dictionary = vehicle.tire_inventory.snapshot()
		var restored = preload("res://scripts/rally/rally_tire_inventory.gd").new()
		assert(restored.restore(saved))
		assert(restored.repair_kits == [false,false])
		# A new kit still charges the full cost when only ten health points are missing.
		vehicle.tire_inventory.repair_kits[1] = true
		assert(repair_session.on_quick_repair_radiator_requested(true))
		assert(is_zero_approx(thermal.radiator_damage))
		assert(repair_session.competition.player_penalty_ms == before + 150000)
		var manager = preload("res://scripts/rally/rally_event_manager.gd").new()
		manager.save_path = ""
		manager.status = "running"
		manager.stage_order = ["russia_stage1", "russia_stage2"]
		manager.event_doc = {}
		repair_session.event_manager = manager
		repair_session.practice_mode = false
		repair_session.session_mode = "rally"
		repair_session.session_ready = true
		repair_session.session_track_id = "russia_stage1"
		repair_session.competition.finalize()
		assert(repair_session.can_open_between_stage_workshop())
		manager.event_doc["setup_windows"] = [{"after_stage_id": "russia_stage1", "before_stage_id": "russia_stage2"}]
		assert(not repair_session.can_open_between_stage_workshop())
		manager.event_doc.clear()
		manager.stage_order.pop_back()
		assert(not repair_session.can_open_between_stage_workshop())
		manager.stage_order.append("russia_stage2")
		repair_session.competition.player_retired = true
		assert(not repair_session.can_open_between_stage_workshop())
		repair_session.competition.player_retired = false
		vehicle.tire_inventory.repair_kits[0] = true
		thermal.radiator_damage = 0.35
		assert(repair_session.on_quick_repair_radiator_requested(false))
		assert(not repair_session.on_quick_repair_radiator_requested(false))
		assert(manager.service_penalties_ms["russia_stage1"] == 30000)
		assert(is_equal_approx(manager.vehicle_damage_state.radiator, 0.15))
		assert(manager.tire_inventory_state.repair_kits == [false, false])
		var results: Dictionary = repair_session.get_competition_panel_state()
		var player: Dictionary = results.rows.filter(func(row): return row.player)[0]
		assert(player.penalty_ms == before + 180000)
		assert(repair_session.competition.player_penalty_ms == before + 150000)
		pause_menu.modal.hide()
		var original_session: Node = pause_menu.session
		pause_menu.session = repair_session
		repair_session.pause_inventory = pause_menu
		repair_session._open_between_stage_workshop()
		assert(paused and pause_menu.opened_from_results)
		repair_session.continue_competition()
		assert(manager.cursor == 0)
		pause_menu.toggle()
		assert(not paused and not pause_menu.opened_from_results and not pause_menu.modal.visible)
		pause_menu.session = original_session
		repair_session.free()
		pause_menu.show_inventory()
		workshop = pause_menu.content.get_child(0)
		workshop._category("radiator")
		assert(workshop.buttons.size() == 1)
		assert(not workshop.compatible(7,4) and not workshop.compatible(8,4))
		pause_menu.show_menu()
		pause_menu.free()
		root_node.free()
		print("SERVICE_WORKSHOP_CONTRACT PASS")
	elif frame_count == 7:
		quit(0)
	return false
