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
	running = false
	finished = false
	elapsed_s = 0.0
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
	if not running and world_position.distance_to(points[0]) < radius_m and speed_m_s > 1.0:
		running = true
	if not running:
		previous_position = world_position
		return
	var step := maxf(dt, 0.0)
	var displacement := world_position - previous_position
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
	return {"points": points, "position": position, "current_s": elapsed_s, "last_s": last_s, "best_s": best_s, "running": running, "finished": finished, "checkpoint": next_checkpoint, "checkpoint_count": points.size(), "generation": generation, "splits": splits, "checkpoint_times": checkpoint_times}
