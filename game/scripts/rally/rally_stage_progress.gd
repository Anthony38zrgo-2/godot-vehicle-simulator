class_name RallyStageProgress
extends RefCounted

var points: Array[Vector3] = []
var radius_m: float = 8.0
var next_checkpoint: int = 1
var running: bool = false
var finished: bool = false
var elapsed_s: float = 0.0
var last_s: Variant = null
var best_s: Variant = null
var generation: int = -1
var position: Vector3 = Vector3.ZERO
var previous_position: Vector3 = Vector3.ZERO
var splits: Array = []
var checkpoint_times: Array = []
var sector_indices: Array = []
var penalty_s: float = 0.0
var external_start: bool = false
var clock_started: bool = false
var timing_gates: Array = []
var next_timing_gate: int = 0
var route_distances := PackedFloat64Array()
var route_progress_m: float = 0.0
var route_segment: int = 0

func configure(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var document: Variant = JSON.parse_string(file.get_as_text())
	if not document is Dictionary:
		return false
	radius_m = float(document.get("checkpoint_radius_m", 8.0))
	points.clear()
	for point in document.get("points", []):
		points.append(Vector3(float(point[0]), float(point[1]), float(point[2])))
	return points.size() > 1

func reset_attempt() -> void:
	next_checkpoint = 1
	next_timing_gate = 0
	route_progress_m = 0.0
	route_segment = 0
	running = false
	finished = false
	elapsed_s = 0.0
	clock_started = false
	splits.clear()
	checkpoint_times.clear()

func advance(world_position: Vector3, dt: float, session_generation: int, speed_m_s: float) -> void:
	position = world_position
	if session_generation != generation:
		generation = session_generation
		reset_attempt()
		previous_position = world_position
	if points.size() < 2 or finished:
		previous_position = world_position
		return
	if external_start:
		running = clock_started
	elif not running and world_position.distance_to(points[0]) < radius_m and speed_m_s > 1.0:
		running = true
	if not running and not external_start:
		previous_position = world_position
		return
	var step := maxf(dt, 0.0) if running else 0.0
	var displacement := world_position - previous_position
	if not timing_gates.is_empty():
		advance_timing_gates(displacement, step, speed_m_s)
		previous_position = world_position
		return
	var length_squared := displacement.length_squared()
	var last_fraction := 0.0
	# Mandatory ordered controls with swept crossing: high speed cannot skip a gate.
	# Reject large teleports; a rescue never awards checkpoints.
	if displacement.length() <= maxf(50.0, speed_m_s * step * 2.0):
		while next_checkpoint < points.size():
			var fraction := clampf((points[next_checkpoint] - previous_position).dot(displacement) / maxf(length_squared, 0.000001), 0.0, 1.0)
			if fraction < last_fraction or (previous_position + displacement * fraction).distance_to(points[next_checkpoint]) > radius_m:
				break
			var crossing_ms := int(round((elapsed_s + step * fraction) * 1000.0))
			checkpoint_times.append({"index": next_checkpoint, "time_ms": crossing_ms})
			if next_checkpoint in sector_indices:
				splits.append({"checkpoint": next_checkpoint, "time_ms": crossing_ms})
			last_fraction = fraction
			next_checkpoint += 1
	elapsed_s += step
	previous_position = world_position
	if next_checkpoint >= points.size():
		finished = true
		running = false
		elapsed_s = float(checkpoint_times[-1].time_ms) / 1000.0
		last_s = elapsed_s
		best_s = elapsed_s if best_s == null else minf(float(best_s), elapsed_s)

func readout() -> Dictionary:
	var split_positions: Array = []
	for gate: Dictionary in timing_gates:
		split_positions.append(gate.route_position)
	return {"split_positions": split_positions, "points": points, "position": position, "current_s": elapsed_s, "last_s": last_s, "best_s": best_s, "running": running, "finished": finished, "checkpoint": next_checkpoint, "checkpoint_count": points.size(), "generation": generation, "splits": splits, "checkpoint_times": checkpoint_times, "next_partial": next_timing_gate + 1, "route_progress_m": route_progress_m}


func configure_timing_gates(definitions: Array) -> bool:
	if definitions.is_empty() or points.size() < 2:
		return false
	timing_gates.clear()
	for definition: Dictionary in definitions:
		var gate := definition.duplicate(true)
		for key in ["origin", "forward", "right", "up", "route_position"]:
			var xyz: Array = gate.get(key, [])
			if xyz.size() != 3:
				return false
			gate[key] = Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
		timing_gates.append(gate)
	# The original reset nodes stop before the actual finish trigger/banner.
	var last: Vector3 = timing_gates[-1].route_position
	if points[-1].distance_to(last) > 0.1:
		points.append(last)
	route_distances = PackedFloat64Array([0.0])
	for i in range(1, points.size()):
		route_distances.append(route_distances[-1] + points[i - 1].distance_to(points[i]))
	return true

func advance_timing_gates(displacement: Vector3, step: float, speed_m_s: float) -> void:
	var old_progress := route_progress_m
	var valid_move := displacement.length() <= maxf(50.0, speed_m_s * step * 2.0)
	if valid_move:
		# Project onto nearby road segments. Missing a dense reset point must not
		# permanently block later official split planes. The search stays local.
		var best_distance := INF
		var best_progress := route_progress_m
		var best_segment := route_segment
		for i in range(maxi(0, route_segment - 8), mini(points.size() - 1, route_segment + 24)):
			var a := Vector2(points[i].x, points[i].z)
			var b := Vector2(points[i + 1].x, points[i + 1].z)
			var p := Vector2(position.x, position.z)
			var fraction := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 0.000001), 0.0, 1.0)
			var projected := points[i].lerp(points[i + 1], fraction)
			var candidate := lerpf(route_distances[i], route_distances[i + 1], fraction)
			if candidate > route_progress_m + maxf(40.0, displacement.length() * 2.5) or absf(position.y - projected.y) > 12.0:
				continue
			var lateral := p.distance_squared_to(a.lerp(b, fraction))
			if lateral < best_distance:
				best_distance = lateral
				best_progress = candidate
				best_segment = i
		if best_distance <= 35.0 * 35.0:
			route_progress_m = maxf(route_progress_m, best_progress)
			route_segment = best_segment
		while next_checkpoint < points.size() and route_distances[next_checkpoint] <= route_progress_m + 0.001:
			var fraction := clampf((route_distances[next_checkpoint] - old_progress) / maxf(0.001, route_progress_m - old_progress), 0.0, 1.0)
			checkpoint_times.append({"index": next_checkpoint, "time_ms": int(round((elapsed_s + step * fraction) * 1000.0))})
			next_checkpoint += 1
		var last_fraction := -1.0
		while next_timing_gate < timing_gates.size():
			var gate: Dictionary = timing_gates[next_timing_gate]
			var origin: Vector3 = gate.origin
			var forward: Vector3 = gate.forward
			var before := (previous_position - origin).dot(forward)
			var after := (position - origin).dot(forward)
			if before > 0.001 or after < 0.0 or after - before < 0.000001:
				break
			var fraction := clampf(-before / (after - before), 0.0, 1.0)
			var crossing := previous_position.lerp(position, fraction) - origin
			if fraction < last_fraction or absf(crossing.dot(gate.right)) > float(gate.half_width_m) + 1.0 or absf(crossing.dot(gate.up)) > float(gate.half_height_m) + 1.0:
				break
			if absf(route_progress_m - float(gate.route_distance_m)) > 100.0:
				break
			var crossing_ms := int(round((elapsed_s + step * fraction) * 1000.0))
			splits.append({"gate_id": gate.id, "checkpoint": next_checkpoint - 1, "time_ms": crossing_ms})
			next_timing_gate += 1
			last_fraction = fraction
	elapsed_s += step
	if next_timing_gate == timing_gates.size():
		finished = true
		running = false
		elapsed_s = float(splits[-1].time_ms) / 1000.0
		last_s = elapsed_s
		best_s = elapsed_s if best_s == null else minf(float(best_s), elapsed_s)
