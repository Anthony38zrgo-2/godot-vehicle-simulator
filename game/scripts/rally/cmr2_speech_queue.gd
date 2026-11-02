class_name Cmr2SpeechQueue
extends RefCounted

# Port of OpenCMR2 speech slot playback queue (Race.cpp:49, 72, GPL-3.0)
const QUEUE_CAPACITY := 20

var slots: Array[Dictionary] = []
var sample_duration_remaining: float = 0.0
var total_samples_played: int = 0

func _init() -> void:
	clear()

func clear(player: AudioStreamPlayer = null) -> void:
	if player != null:
		player.stop()
	sample_duration_remaining = 0.0
	slots.clear()
	for i in range(QUEUE_CAPACITY):
		slots.append({
			"owner": -1,
			"flags": 0
		})

func is_full() -> bool:
	for s in slots:
		if (s.flags & 2) == 0:
			return false
	return true

func is_empty() -> bool:
	return (slots[0].flags & 2) == 0

func assign_slot(sample_slot_id: int) -> bool:
	for i in range(QUEUE_CAPACITY):
		if (slots[i].flags & 2) == 0:
			slots[i].flags |= 2
			slots[i].owner = sample_slot_id
			slots[i].flags &= ~1
			return true
	return false

func update(player: AudioStreamPlayer, sound_bank: Dictionary, dt: float = 0.0) -> void:
	if (slots[0].flags & 2) != 0:
		if (slots[0].flags & 1) != 0:
			sample_duration_remaining -= dt
			var is_playing: bool = player.playing or sample_duration_remaining > 0.0
			if not is_playing:
				# Current sample finished, shift queue up
				for i in range(1, QUEUE_CAPACITY):
					slots[i - 1] = slots[i]
				slots[QUEUE_CAPACITY - 1] = {
					"owner": -1,
					"flags": 0
				}
				sample_duration_remaining = 0.0
		else:
			var sample_id: int = slots[0].owner
			if sound_bank.has(sample_id):
				var stream: AudioStream = sound_bank[sample_id]
				player.stream = stream
				player.pitch_scale = 1.0
				if player.is_inside_tree():
					player.play()
				sample_duration_remaining = stream.get_length() if stream != null else 0.5
				slots[0].flags |= 1
				total_samples_played += 1
			else:
				# Skip unresolvable slot
				for i in range(1, QUEUE_CAPACITY):
					slots[i - 1] = slots[i]
				slots[QUEUE_CAPACITY - 1] = {
					"owner": -1,
					"flags": 0
				}
				sample_duration_remaining = 0.0
