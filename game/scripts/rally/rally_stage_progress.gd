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

func advance(world_position: Vector3, dt: float, session_generation: int, speed_m_s: float) -> void:
	position = world_position
	if session_generation != generation:
		generation = session_generation
		next_checkpoint = 1
		running = false
		finished = false
		elapsed_s = 0.0
	if points.size() < 2 or finished:
		return
	if not running and world_position.distance_to(points[0]) < radius_m and speed_m_s > 1.0:
		running = true
	if not running:
		return
	elapsed_s += maxf(dt, 0.0)
	# Ordered source reset nodes are mandatory: cutting across the stage cannot
	# award a time merely by reaching its finish. No physics queries are added.
	while next_checkpoint < points.size() and world_position.distance_to(points[next_checkpoint]) < radius_m:
		next_checkpoint += 1
	if next_checkpoint >= points.size():
		finished = true
		running = false
		last_s = elapsed_s
		best_s = elapsed_s if best_s == null else minf(float(best_s), elapsed_s)

func readout() -> Dictionary:
	return {"points": points, "position": position, "current_s": elapsed_s, "last_s": last_s, "best_s": best_s, "running": running, "finished": finished, "checkpoint": next_checkpoint, "checkpoint_count": points.size()}
