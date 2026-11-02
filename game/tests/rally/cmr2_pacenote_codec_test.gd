extends SceneTree

const Codec = preload("res://scripts/rally/cmr2_pacenote_codec.gd")
const CallQueue = preload("res://scripts/rally/cmr2_call_queue.gd")
const SpeechQueue = preload("res://scripts/rally/cmr2_speech_queue.gd")

func _initialize() -> void:
	test_codec_slots()
	test_codec_icons()
	test_call_queue_splitting_and_holding()
	test_speech_queue_shift()
	print("CMR2 pacenote codec & queues: OK")
	quit()

func test_codec_slots() -> void:
	# fin01.cod entries
	# cod[0]: 0x161 -> distance=5 (70), kind=1 (six), dir=2 (right) -> [18, 5, 9]
	assert(Codec.speech_slots(0x161) == [18, 5, 9])
	# cod[0] mirrored -> right becomes left (8)
	assert(Codec.speech_slots(0x161, true) == [18, 5, 8])

	# Empty sentinel
	assert(Codec.speech_slots(6).is_empty())

	# cod[1]: 0x40040 -> distance=1 (30), hazard=2 (jump) -> [14, 24]
	assert(Codec.speech_slots(0x40040) == [14, 24])

	# cod[2]: 0x1492 -> distance=2 (50), length=1 (long), kind=2 (five), dir=1 (left), turn=1 (opens) -> [15, 10, 4, 8, 12]
	assert(Codec.speech_slots(0x1492) == [15, 10, 4, 8, 12])

	# Hairpin (kind=8, dir=1) -> [7, 8]
	assert(Codec.speech_slots(0x18) == [7, 8])
	# Straight (kind=9) -> [55]
	assert(Codec.speech_slots(0x9) == [55])

	# Dontcut (bit 24), Crest (hazard=1), Caution (caution=1)
	# 0x1000000 | 0x20000 | 0x200000 = 0x1220000
	var slots := Codec.speech_slots(0x1220000)
	assert(26 in slots) # caution
	assert(25 in slots) # crest
	assert(46 in slots) # dontcut

func test_codec_icons() -> void:
	# Flat turn
	assert(Codec.icon(0x161).index == 6)
	assert(Codec.icon(0x161).visible == true)

	# Hazard without direction -> icon index 7 (warning), yellow tint
	var ic_haz := Codec.icon(0x40000)
	assert(ic_haz.index == 7)
	assert(ic_haz.tint.r > 0.9 and ic_haz.tint.g > 0.9) # yellow

	# Caution without direction -> icon index 7, red tint for caution 2
	var ic_caut := Codec.icon(0x400000) # caution 2
	assert(ic_caut.index == 7)
	assert(ic_caut.tint == Color.RED)

func test_call_queue_splitting_and_holding() -> void:
	var queue = CallQueue.new()
	assert(queue.is_empty())

	# Queue a call with both hazard and direction: should split into primary and secondary
	# direction=1 (left, 0x10), hazard=2 (jump, 0x40000) -> 0x40010
	assert(queue.queue_call(0x40010))
	assert(not queue.is_empty())
	var active := queue.get_active_record()
	assert(active.primary_call_id == 0x10) # direction
	assert(active.secondary_call_id == 0x40000) # hazard split!
	assert((active.flags & 0xff) == 50) # initial count 50

	# Step 25 ticks: countdown should decrease from 50 to 25
	for _i in range(25):
		queue.step_tick(false)
	active = queue.get_active_record()
	assert((active.flags & 0xff) == 25)

	# Next tick without upcoming notes: should HOLD at 25!
	queue.step_tick(false)
	active = queue.get_active_record()
	assert((active.flags & 0xff) == 25)

	# Tick WITH upcoming notes: should resume countdown below 25!
	queue.step_tick(true)
	active = queue.get_active_record()
	assert((active.flags & 0xff) == 24)

	# Run until expiration (24 ticks)
	for _i in range(24):
		queue.step_tick(true)
	assert(queue.is_empty())

	# Test queue capacity limit: queue 5 calls
	for i in range(5):
		assert(queue.queue_call(0x10 + i))
	assert(queue.is_full())
	# 6th call should be rejected
	assert(not queue.queue_call(0x99))

func test_speech_queue_shift() -> void:
	var sq = SpeechQueue.new()
	assert(sq.is_empty())

	for i in range(20):
		assert(sq.assign_slot(i))
	assert(sq.is_full())
	assert(not sq.assign_slot(99))

	sq.clear()
	assert(sq.is_empty())
