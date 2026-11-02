class_name Cmr2PacenoteCodec
extends RefCounted

# Port of Race_AssignSlotsFromCallRecord, OpenCMR2 GPL-3.0,
# game/Race.cpp, revision a51f47f216af16fec8959edcf83694ea22cbc0fe.
static func speech_slots(word: int, mirror: bool = false) -> Array[int]:
	word &= 0xffffffff
	var kind := word & 15
	var direction := (word >> 4) & 3
	var distance := (word >> 6) & 15
	var length := (word >> 10) & 3
	var turn := (word >> 12) & 7
	var surface := (word >> 15) & 3
	var hazard := (word >> 17) & 15
	var caution := (word >> 21) & 3
	var junction := (word >> 23) & 1
	var no_cut := (word >> 24) & 1
	var ending := (word >> 25) & 7
	var side := (word >> 28) & 3
	var result: Array[int] = []
	if kind == 6 and direction == 0 and distance == 0 and length == 0 and turn == 0 and hazard == 0 and caution == 0 and surface == 0 and side == 0 and no_cut == 0 and ending == 0:
		return result
	if kind == 9:
		result.append(55)
	if distance >= 1 and distance <= 14:
		result.append(mini(13 + distance, 22))
	_append_choice(result, caution, {1: 26, 2: 27})
	_append_choice(result, length, {1: 10, 2: 28})
	if junction == 1:
		result.append(29)
	_append_choice(result, kind, {1: 5, 2: 4, 3: 3, 4: 2, 5: 1, 6: 0, 7: 6, 8: 7})
	if direction == 1 or direction == 2:
		result.append((9 if direction == 1 else 8) if mirror else (8 if direction == 1 else 9))
	_append_choice(result, turn, {1: 12, 2: 11, 3: 30})
	_append_choice(result, surface, {1: 23, 2: 31})
	_append_choice(result, hazard, {1: 25, 2: 24, 3: 34, 4: 35, 5: 36, 6: 33, 7: 37, 8: 38, 9: 39, 10: 40, 11: 41, 12: 42, 13: 43, 14: 54, 15: 32})
	_append_choice(result, side, {1: 44, 2: 45})
	if no_cut == 1:
		result.append(46)
	if ending >= 1 and ending <= 7:
		result.append(46 + ending)
	return result

static func _append_choice(result: Array[int], value: int, choices: Dictionary) -> void:
	if choices.has(value):
		result.append(int(choices[value]))

static func icon(word: int, mirror: bool = false) -> Dictionary:
	word &= 0xffffffff
	var kind := word & 15
	var direction := (word >> 4) & 3
	var hazard := (word >> 17) & 15
	var caution := (word >> 21) & 3
	var visible := direction != 0 or (kind != 0 and kind != 9) or hazard in [1, 2, 14] or caution != 0
	var index := int({2: 5, 3: 4, 4: 3, 5: 2, 6: 2, 7: 1, 8: 0}.get(kind, 6))
	var flip := (direction == 1) != mirror
	var tint := Color.WHITE
	if hazard != 0 and direction == 0:
		flip = false
		index = 7
		if hazard in [2, 14]:
			tint = Color(1, 1, 13.0 / 255.0)
		elif hazard == 1:
			tint = Color.RED
	if caution != 0:
		flip = false
		index = 7
		tint = Color(1, 1, 13.0 / 255.0) if caution == 1 else Color.RED
	return {"visible": visible, "index": index, "flip": flip, "tint": tint}
