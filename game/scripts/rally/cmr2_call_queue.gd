class_name Cmr2CallQueue
extends RefCounted

# Port of OpenCMR2 call record queue (Race.cpp:876, 4606-4623, GPL-3.0)
const QUEUE_CAPACITY := 5
const INITIAL_FLAGS := 0x132 # bit 8 (0x100 queued) | count 50 (0x32)

var records: Array[Dictionary] = []

func _init() -> void:
	clear()

func clear() -> void:
	records.clear()
	for i in range(QUEUE_CAPACITY):
		records.append({
			"primary_call_id": 0,
			"secondary_call_id": 0,
			"flags": 0
		})

func is_full() -> bool:
	for rec in records:
		if (rec.flags & 0x100) == 0:
			return false
	return true

func is_empty() -> bool:
	return (records[0].flags & 0x100) == 0

func queue_call(word: int, prev_word: int = 0) -> bool:
	word &= 0xffffffff
	prev_word &= 0xffffffff
	var kind := word & 15
	var direction := (word >> 4) & 3
	var hazard := (word >> 17) & 15
	var caution := (word >> 21) & 3

	var is_hazard_call := (hazard == 0xe or hazard == 2 or hazard == 1) and direction != 0
	var is_caution_call := caution != 0 and direction != 0

	var primary_id := word
	var secondary_id := prev_word

	if secondary_id == 0:
		if is_hazard_call:
			primary_id -= hazard * 0x20000
			secondary_id = hazard * 0x20000
		elif is_caution_call:
			primary_id -= caution * 0x200000
			secondary_id = caution * 0x200000

	# Filter empty sentinel: kind 6, direction 0, hazard 0
	if (primary_id & 15) == 6 and ((primary_id >> 4) & 3) == 0 and ((primary_id >> 17) & 15) == 0:
		return false

	for i in range(QUEUE_CAPACITY):
		if (records[i].flags & 0x100) == 0:
			records[i].primary_call_id = primary_id
			records[i].secondary_call_id = secondary_id
			records[i].flags = (records[i].flags & 0xfffffd32) | INITIAL_FLAGS
			return true
	return false

func step_tick(has_upcoming_notes: bool) -> void:
	if (records[0].flags & 0x100) == 0:
		return
	var count: int = records[0].flags & 0xff
	if count != 25:
		count -= 1
		records[0].flags = (records[0].flags & ~0xff) | (count & 0xff)
	else:
		var slot1_queued: bool = (records[1].flags & 0x100) != 0
		if has_upcoming_notes or slot1_queued:
			count -= 1
			records[0].flags = (records[0].flags & ~0xff) | (count & 0xff)

	if (records[0].flags & 0xff) == 0:
		for i in range(QUEUE_CAPACITY - 1):
			records[i] = records[i + 1]
		records[QUEUE_CAPACITY - 1] = {
			"primary_call_id": 0,
			"secondary_call_id": 0,
			"flags": 0
		}

func get_unassigned_calls() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rec in records:
		if (rec.flags & 0x100) != 0 and (rec.flags & 0x200) == 0:
			rec.flags |= 0x200
			result.append({
				"primary": rec.primary_call_id,
				"secondary": rec.secondary_call_id
			})
	return result

func get_active_record() -> Dictionary:
	if (records[0].flags & 0x100) != 0:
		return records[0]
	return {}
