class_name PacenoteGateTracker
extends RefCounted

const TELEPORT_THRESHOLD_M := 45.0
const PLANE_EPSILON := 0.01
const WIDTH_MARGIN_M := 0.5

var gates: Array[Dictionary] = []
var next_gate := 0
var last_crossed_gate := -1

func configure(definitions: Array) -> bool:
	if definitions.is_empty():
		return false
	var prepared: Array[Dictionary] = []
	for definition in definitions:
		if not definition is Dictionary:
			return false
		var left: Variant = _vector(definition.get("left", []))
		var right: Variant = _vector(definition.get("right", []))
		var hint: Variant = _vector(definition.get("forward_hint", []))
		if left == null or right == null or hint == null:
			return false
		var lateral: Vector3 = right - left
		if lateral.length_squared() < 0.01:
			return false
		var hint_dir: Vector3 = hint.normalized()
		if hint_dir.length_squared() < 0.01:
			return false
		var lateral_dir := lateral.normalized()
		# Compute full 3D orthonormal frame (lateral_dir, up_dir, normal)
		# Road normal is perpendicular to lateral and forward hint
		var road_normal: Vector3 = lateral_dir.cross(hint_dir).normalized()
		if road_normal.length_squared() < 0.01:
			road_normal = Vector3.UP
		elif road_normal.y < 0.0:
			road_normal = -road_normal
		var normal: Vector3 = road_normal.cross(lateral_dir).normalized()
		if normal.dot(hint_dir) < 0.0:
			normal = -normal
		var up_dir: Vector3 = normal.cross(lateral_dir).normalized()
		if up_dir.y < 0.0:
			up_dir = -up_dir

		var gate: Dictionary = definition.duplicate(true)
		gate["center"] = (left + right) * 0.5
		gate["lateral"] = lateral_dir
		gate["up"] = up_dir
		gate["normal"] = normal
		gate["half_width"] = lateral.length() * 0.5
		gate["height_tolerance_m"] = float(definition.get("height_tolerance_m", 3.0))
		prepared.append(gate)
	gates = prepared
	next_gate = 0
	last_crossed_gate = -1
	return true

func reset(index: int = 0) -> void:
	next_gate = clampi(index, 0, gates.size())
	last_crossed_gate = next_gate - 1

func teleport_to(position: Vector3) -> void:
	if gates.is_empty():
		return
	# Find nearest gate to target position
	var best_index := next_gate
	var best_dist_sq := INF
	for i in range(gates.size()):
		var center: Vector3 = gates[i]["center"]
		var d := position.distance_squared_to(center)
		if d < best_dist_sq:
			best_dist_sq = d
			best_index = i
	next_gate = best_index
	last_crossed_gate = next_gate - 1

func advance(previous: Vector3, current: Vector3) -> Array[Dictionary]:
	if gates.is_empty() or next_gate >= gates.size():
		return []

	var displacement := current - previous
	var dist := displacement.length()
	# Teleport detection: sudden large jump (e.g. car rescue or physics glitch)
	if dist > TELEPORT_THRESHOLD_M:
		teleport_to(current)
		return []

	var crossings: Array[Dictionary] = []
	var last_fraction := -1.0

	while next_gate < gates.size():
		var crossing: Dictionary = _check_gate_crossing(next_gate, previous, current)
		if not crossing.is_empty():
			var fraction: float = crossing["fraction"]
			if fraction >= last_fraction:
				crossing["omitted"] = false
				crossings.append(crossing)
				last_fraction = fraction
				last_crossed_gate = next_gate
				next_gate += 1
				continue

		# If the next expected gate was NOT crossed, check if a future gate was crossed
		# (recovery for missed/cut corners, looking ahead up to 8 gates)
		var recovered := false
		var lookahead_limit := mini(next_gate + 8, gates.size())
		for lookahead_idx in range(next_gate + 1, lookahead_limit):
			var look_crossing: Dictionary = _check_gate_crossing(lookahead_idx, previous, current)
			if not look_crossing.is_empty():
				# We crossed a later gate: gates [next_gate .. lookahead_idx - 1] were missed/omitted
				var skipped: Array[int] = []
				for s in range(next_gate, lookahead_idx):
					skipped.append(s)
				look_crossing["omitted"] = false
				look_crossing["skipped_indices"] = skipped
				crossings.append(look_crossing)
				last_crossed_gate = lookahead_idx
				next_gate = lookahead_idx + 1
				recovered = true
				break

		if not recovered:
			break

	return crossings

func _check_gate_crossing(gate_idx: int, previous: Vector3, current: Vector3) -> Dictionary:
	var gate := gates[gate_idx]
	var center: Vector3 = gate["center"]
	var normal: Vector3 = gate["normal"]
	var before: float = (previous - center).dot(normal)
	var after: float = (current - center).dot(normal)

	# Must cross plane from negative (behind) to positive (in front)
	if before > PLANE_EPSILON or after <= 0.0:
		return {}
	var delta := after - before
	if delta < 0.000001:
		return {}

	var fraction := -before / delta
	if fraction < 0.0 or fraction > 1.0:
		return {}

	var point := previous.lerp(current, fraction) - center
	var lateral: Vector3 = gate["lateral"]
	var up: Vector3 = gate["up"]
	var lateral_dist := absf(point.dot(lateral))
	var height_dist := absf(point.dot(up))
	var max_width: float = float(gate["half_width"]) + WIDTH_MARGIN_M
	var max_height: float = float(gate["height_tolerance_m"])

	if lateral_dist > max_width or height_dist > max_height:
		return {}

	return {
		"index": gate_idx,
		"fraction": fraction,
		"point": point + center,
		"gate": gate
	}

static func _vector(value: Variant) -> Variant:
	if not value is Array or value.size() != 3:
		return null
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
