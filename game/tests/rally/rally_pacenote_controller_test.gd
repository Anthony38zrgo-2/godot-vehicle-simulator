extends SceneTree

const Controller = preload("res://scripts/rally/rally_pacenote_controller.gd")
const Hud = preload("res://scripts/rally/cmr2_pacenote_hud.gd")

func _initialize() -> void:
	test_controller_lifecycle()
	test_russia_stage1_route_trigger()
	print("Pacenote controller & stage integration: OK")
	quit()

func test_controller_lifecycle() -> void:
	var ctrl = Controller.new()
	root.add_child(ctrl)
	assert(ctrl.configure("res://data/rally/pacenotes/russia_stage1.json"))
	assert(ctrl.tracker.gates.size() == 493)
	assert(ctrl.call_table.size() > 20)

	# Start sequence audio triggers
	ctrl.on_start_countdown(3)
	assert(ctrl.speech_queue.slots[0].owner == 56) # countdown_3
	ctrl.speech_queue.clear()

	ctrl.on_start_countdown(0) # GO
	assert(ctrl.speech_queue.slots[0].owner == 13) # go.wav
	ctrl.speech_queue.clear()

	# Rescue handling
	ctrl.on_rescue(Vector3(-2.17, -1.8, -38.4))
	assert(ctrl.speech_queue.is_empty())
	assert(ctrl.call_queue.is_empty())

	ctrl.queue_free()

func test_russia_stage1_route_trigger() -> void:
	var ctrl = Controller.new()
	root.add_child(ctrl)
	assert(ctrl.configure("res://data/rally/pacenotes/russia_stage1.json"))

	# Load route points
	var file := FileAccess.open("res://data/rally/russia_stage1_route.json", FileAccess.READ)
	assert(file != null)
	var doc: Dictionary = JSON.parse_string(file.get_as_text())
	var points: Array = doc.get("points", [])
	assert(points.size() >= 20)

	# Feed vehicle traversing the start of the stage through the first 15 points
	for i in range(15):
		var p_arr: Array = points[i]
		var pos = Vector3(float(p_arr[0]), float(p_arr[1]), float(p_arr[2]))
		ctrl.advance(pos, 0.05)
		# print("Step ", i, " next_gate=", ctrl.tracker.next_gate, " call_queue_empty=", ctrl.call_queue.is_empty(), " speech_empty=", ctrl.speech_queue.is_empty())

	print("After 15 steps: next_gate=", ctrl.tracker.next_gate, " call_queue_empty=", ctrl.call_queue.is_empty(), " speech_empty=", ctrl.speech_queue.is_empty(), " sound_bank_size=", ctrl.sound_bank.size(), " total_played=", ctrl.speech_queue.total_samples_played)
	assert(ctrl.speech_queue.total_samples_played > 0 or not ctrl.speech_queue.is_empty())
	# Active record in call queue should have countdown active
	assert(not ctrl.call_queue.is_empty())
	var active = ctrl.call_queue.get_active_record()
	assert((active.flags & 0x100) != 0)

	ctrl.queue_free()
