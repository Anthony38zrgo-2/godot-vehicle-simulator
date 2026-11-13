class_name RallyPacenoteController
extends Node

signal call_triggered(call_index: int, word: int)

const PacenoteGateTracker = preload("res://scripts/rally/pacenote_gate_tracker.gd")
const Cmr2CallQueue = preload("res://scripts/rally/cmr2_call_queue.gd")
const Cmr2SpeechQueue = preload("res://scripts/rally/cmr2_speech_queue.gd")
const Cmr2PacenoteCodec = preload("res://scripts/rally/cmr2_pacenote_codec.gd")
const Cmr2PacenoteHud = preload("res://scripts/rally/cmr2_pacenote_hud.gd")
const SeamlessVehicleLoop = preload("res://scripts/audio/seamless_vehicle_loop.gd")

# Orchestrates CMR2 pacenote detection, queues, speech and HUD integration.
const PROVENANCE_PATH := "res://sounds/banks/pacenotes/cmr2/es/provenance.json"
const ES_SOUNDS_DIR := "res://sounds/banks/pacenotes/cmr2/es/"
const TICK_RATE_HZ := 25.0
const SECONDS_PER_TICK := 1.0 / TICK_RATE_HZ

var tracker := PacenoteGateTracker.new()
var call_queue := Cmr2CallQueue.new()
var speech_queue := Cmr2SpeechQueue.new()

var sound_bank: Dictionary = {} # slot_int -> AudioStream
var call_table: Array[int] = [] # table of .cod 32-bit words
var audio_player: AudioStreamPlayer
var hud_node: Cmr2PacenoteHud

var tick_accumulator: float = 0.0
var mirror: bool = false
var active: bool = false
var last_position: Vector3 = Vector3.ZERO
var position_initialized: bool = false
var route_points: Array[Vector3] = []
var route_distances: Array[float] = []
var off_route: bool = false

func _ready() -> void:
	_setup_audio()
	_load_sound_bank()

func configure(stage_data_path: String) -> bool:
	active = false
	tracker = PacenoteGateTracker.new()
	call_queue.clear()
	speech_queue.clear(audio_player)
	if audio_player == null:
		_setup_audio()
	if sound_bank.is_empty():
		_load_sound_bank()
	if not FileAccess.file_exists(stage_data_path):
		push_error("Pacenote stage data not found: " + stage_data_path)
		return false
	var file := FileAccess.open(stage_data_path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false
	var data: Dictionary = parsed
	route_points.clear()
	route_distances.clear()
	var route_path := stage_data_path.replace("/pacenotes/", "/").trim_suffix(".json") + "_route.json"
	if FileAccess.file_exists(route_path):
		var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(route_path))
		var distance := 0.0
		for p in route.get("points", []):
			var point := Vector3(p[0], p[1], p[2])
			if not route_points.is_empty():
				distance += route_points[-1].distance_to(point)
			route_points.append(point)
			route_distances.append(distance)
	off_route = false
	
	# Load call table words
	call_table.clear()
	for w in data.get("calls", []):
		call_table.append(int(w))

	# Configure gates
	var gate_defs: Array = data.get("gates", [])
	if not tracker.configure(gate_defs):
		push_warning("Copiloto desactivado: faltan puertas runtime válidas en " + stage_data_path)
		return false

	call_queue.clear()
	speech_queue.clear(audio_player)
	active = true
	position_initialized = false
	return true

func set_hud(hud: Cmr2PacenoteHud) -> void:
	hud_node = hud

func _setup_audio() -> void:
	if audio_player == null:
		audio_player = AudioStreamPlayer.new()
		audio_player.name = "Cmr2CopilotVoice"
		audio_player.volume_db = -2.0
		var bus_idx := AudioServer.get_bus_index("Copilot")
		if bus_idx == -1:
			AudioServer.add_bus()
			bus_idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus_idx, "Copilot")
			AudioServer.set_bus_send(bus_idx, "Master")
		audio_player.bus = "Copilot"
	if audio_player.get_parent() == null:
		add_child(audio_player)

func _load_sound_bank() -> void:
	if not FileAccess.file_exists(PROVENANCE_PATH):
		push_error("CMR2 speech provenance missing: " + PROVENANCE_PATH)
		return
	var file := FileAccess.open(PROVENANCE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var doc: Dictionary = parsed
	for item in doc.get("samples", []):
		if not item is Dictionary:
			continue
		var slot := int(item.get("slot", -1))
		var filename := str(item.get("file", ""))
		var wav_path := ES_SOUNDS_DIR + filename
		var stream := SeamlessVehicleLoop.load_pcm(wav_path, false)
		if stream != null:
			sound_bank[slot] = stream

func advance(position: Vector3, dt: float) -> void:
	if not active:
		return
	var progress := _route_progress(position)
	if not progress.is_empty():
		if not bool(progress.on_route):
			if not off_route:
				_clear_presentation()
			off_route = true
			last_position = position
			position_initialized = true
			return
		if off_route or (position_initialized and last_position.distance_to(position) > PacenoteGateTracker.TELEPORT_THRESHOLD_M):
			_clear_presentation()
			# Resume ahead of the car, without replaying missed or earlier calls.
			while tracker.next_gate < tracker.gates.size() and float(tracker.gates[tracker.next_gate].get("route_distance_m", INF)) <= float(progress.distance):
				tracker.next_gate += 1
			tracker.last_crossed_gate = tracker.next_gate - 1
			off_route = false
			last_position = position
			position_initialized = true
			return

	if not position_initialized:
		last_position = position
		position_initialized = true
		return

	# 1. Gate tracker swept advance
	var crossings := tracker.advance(last_position, position)
	last_position = position

	for c in crossings:
		var gate: Dictionary = c.get("gate", {})
		var call_idx: Variant = gate.get("call_index", null)
		if call_idx != null and int(call_idx) >= 0 and int(call_idx) < call_table.size():
			var word := call_table[int(call_idx)]
			call_queue.queue_call(word)
			call_triggered.emit(int(call_idx), word)

	# 2. Assign voice slots for newly queued calls (Latch 0x200)
	var new_calls := call_queue.get_unassigned_calls()
	for call in new_calls:
		var primary_slots := Cmr2PacenoteCodec.speech_slots(int(call.primary), mirror)
		for s in primary_slots:
			speech_queue.assign_slot(s)
		if int(call.secondary) != 0:
			var sec_slots := Cmr2PacenoteCodec.speech_slots(int(call.secondary), mirror)
			for s in sec_slots:
				speech_queue.assign_slot(s)

	# 3. Compatibility clock for callout countdown (25 Hz)
	tick_accumulator += maxf(dt, 0.0)
	var has_upcoming := _check_upcoming_notes()
	while tick_accumulator >= SECONDS_PER_TICK:
		call_queue.step_tick(has_upcoming)
		tick_accumulator -= SECONDS_PER_TICK

	# 4. Audio sequential playback queue update
	speech_queue.update(audio_player, sound_bank, dt)

	# 5. Presentation / HUD update
	if hud_node != null:
		hud_node.update_hud(call_queue.get_active_record(), mirror)

func _check_upcoming_notes() -> bool:
	# Checks if any of the next 6 gates has a call attached
	var start_idx := tracker.next_gate
	var end_idx := mini(start_idx + 6, tracker.gates.size())
	for i in range(start_idx, end_idx):
		if tracker.gates[i].get("call_index", null) != null:
			return true
	return false

# Start sequence events: countdown 3, 2, 1, GO
func on_start_countdown(count: int) -> void:
	match count:
		3: speech_queue.assign_slot(56) # countdown_3.wav
		2: speech_queue.assign_slot(57) # countdown_2.wav
		1: speech_queue.assign_slot(58) # countdown_1.wav
		0: speech_queue.assign_slot(13) # go.wav

func on_rescue(pose: Vector3) -> void:
	if audio_player != null:
		audio_player.stop()
	speech_queue.clear()
	call_queue.clear()
	tracker.teleport_to(pose)
	last_position = pose
	if hud_node != null:
		hud_node.update_hud({})

func on_retry() -> void:
	off_route = false
	if audio_player != null:
		audio_player.stop()
	speech_queue.clear()
	call_queue.clear()
	tracker.reset(0)
	position_initialized = false
	if hud_node != null:
		hud_node.update_hud({})

func on_retire() -> void:
	if audio_player != null:
		audio_player.stop()
	speech_queue.clear()
	call_queue.clear()
	active = false
	if hud_node != null:
		hud_node.update_hud({})

func on_pause(paused: bool) -> void:
	if audio_player != null:
		audio_player.stream_paused = paused

func _clear_presentation() -> void:
	call_queue.clear()
	speech_queue.clear(audio_player)
	tick_accumulator = 0.0
	if hud_node != null:
		hud_node.update_hud({})

func _route_progress(position: Vector3) -> Dictionary:
	if route_points.size() < 2:
		return {}
	var best := INF
	var distance := 0.0
	for i in range(route_points.size() - 1):
		var a := route_points[i]
		var segment := route_points[i + 1] - a
		var t := clampf((position - a).dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
		var error := position.distance_squared_to(a + segment * t)
		if error < best:
			best = error
			distance = route_distances[i] + t * segment.length()
	return {"on_route": best <= 100.0, "distance": distance}
