extends SceneTree
## Contrato headless de carga, colisión, spawn y splits para las 32 etapas
## (kenya/finland/sweden/switzerland × stage1..8).
## Verifica por etapa:
##  1. stage_loader.resolve(track_id) ok + recursos en ResourceLoader.
##  2. RallyTrackCollisionBuilder construye StaticBody3D desde el
##     collision GLB + taludes de erosión con get_child_count() >= 3.
##  3. RallyStageProgress.configure(route) + configure_timing_gates() ok, y al
##     simular el paso por route_position los 10 portales disparan en orden
##     hasta finished == true.
##  4. Raycast vertical desde start_pose.ground_godot + (0,3,0) impacta
##     Collision_Road a menos de 0.6 m.

const Loader = preload("res://scripts/rally/rally_stage_loader.gd")
const Builder = preload("res://scripts/rally/rally_track_collision_builder.gd")
const Progress = preload("res://scripts/rally/rally_stage_progress.gd")

var failures: Array[String] = []
var checked := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func _initialize() -> void:
	call_deferred("run")


func _track_ids() -> Array:
	var out: Array = []
	for country in ["kenya", "finland", "sweden", "switzerland"]:
		for i in range(1, 9):
			out.append("%s_stage%d" % [country, i])
	return out


func run() -> void:
	var loader = Loader.new()
	for track_id in _track_ids():
		await _check_stage(loader, str(track_id))
		checked += 1
		if checked % 8 == 0:
			print("ALL_COUNTRIES_CONTRACT progreso %d/32 fallos=%d" % [checked, failures.size()])
	print("ALL_COUNTRIES_STAGE_IMPORT_CONTRACT ",
		"PASS 32/32" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)


func _check_stage(loader, track_id: String) -> void:
	# 1. Catálogo + recursos.
	var resolved: Dictionary = loader.resolve(track_id)
	check(not resolved.is_empty(), "%s resolve ok: %s" % [track_id, loader.error])
	if resolved.is_empty():
		return
	var paths: Dictionary = resolved.get("paths", {})
	for key in ["visual", "collision", "route", "timing_gates"]:
		check(ResourceLoader.exists(str(paths.get(key, ""))),
			"%s recurso %s existe" % [track_id, key])

	# 2. Visual + colisión + taludes de erosión.
	var visual: Node3D = load(str(paths["visual"])).instantiate()
	root.add_child(visual)
	var builder = Builder.new()
	root.add_child(builder)
	builder.collision_scene_path = str(paths["collision"])
	var built: bool = builder.build_collision(visual)
	check(built, "%s build_collision ok" % track_id)
	check(builder.get_child_count() >= 3,
		"%s bodies>=3 (actual %d)" % [track_id, builder.get_child_count()])

	# 3. Progreso + 10 portales en orden.
	var progress = Progress.new()
	check(progress.configure(str(paths["route"])), "%s route configure" % track_id)
	var gates_doc: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(str(paths["timing_gates"])))
	var gates: Array = (gates_doc as Dictionary).get("gates", [])
	check(gates.size() == 10, "%s 10 gates" % track_id)
	check(progress.configure_timing_gates(gates), "%s gates configure" % track_id)
	# Simular conducción por la poligonal desde antes del inicio, en subpasos
	# de 5 m: el hit de split_09 puede quedar hasta 120 m más allá del último
	# nodo (tangente extendida en la exportación) y un salto mayor de 50 m se
	# rechaza como teletransporte en advance_timing_gates().
	var pts: Array[Vector3] = progress.points
	var dir := (pts[1] - pts[0]).normalized()
	progress.external_start = true
	progress.clock_started = true
	var walk: Array[Vector3] = [pts[0] - dir * 15.0]
	walk.append_array(pts)
	# Seguir 30 m más allá de la meta: el último punto añadido por
	# configure_timing_gates() está EXACTAMENTE sobre el plano del portal
	# (after == 0) y advance_timing_gates() exige cruzarlo (after > 0),
	# igual que el coche real atraviesa el arco en carrera.
	var _tail: Vector3 = walk[walk.size() - 1]
	var _tan: Vector3 = _tail - walk[walk.size() - 2]
	if _tan.length() < 0.001:
		_tan = Vector3(0, 0, -1)
	_tan = _tan.normalized()
	for e in range(1, 7):
		walk.append(_tail + _tan * (5.0 * float(e)))
	progress.advance(walk[0], 0.1, 1, 20.0)
	for k in range(1, walk.size()):
		var a: Vector3 = walk[k - 1]
		var b: Vector3 = walk[k]
		var n := maxi(1, int(ceil(a.distance_to(b) / 5.0)))
		for s in range(1, n + 1):
			progress.advance(a.lerp(b, float(s) / float(n)), 0.1, 1, 20.0)
			if progress.finished:
				break
		if progress.finished:
			break
	check(progress.finished, "%s finished" % track_id)
	check(progress.splits.size() == 10, "%s 10 splits (actual %d)" % [track_id, progress.splits.size()])
	var ids: Array = []
	for s in progress.splits:
		ids.append(str((s as Dictionary).get("gate_id", "")))
	var expected: Array = []
	for g in gates:
		expected.append(str((g as Dictionary).get("id", "")))
	check(ids == expected, "%s orden %s" % [track_id, str(ids)])

	# 4. Spawn sobre Collision_Road (< 0.6 m).
	await physics_frame
	await physics_frame
	var ground: Array = (resolved.get("start_pose", {}) as Dictionary).get("ground_godot", [0, 0, 0])
	var origin := Vector3(float(ground[0]), float(ground[1]), float(ground[2]))
	var world: World3D = root.get_world_3d()
	if world == null:
		check(false, "%s sin world_3d" % track_id)
	else:
		var query := PhysicsRayQueryParameters3D.create(
			origin + Vector3(0, 3, 0), origin - Vector3(0, 10, 0), 1)
		var hit: Dictionary = world.direct_space_state.intersect_ray(query)
		check(not hit.is_empty(), "%s spawn ray impacta" % track_id)
		if not hit.is_empty():
			var col := hit.collider as Node
			check(col != null and col.get_meta("is_stage_road", false),
				"%s spawn sobre Collision_Road" % track_id)
			check(absf((hit.position as Vector3).y - origin.y) < 0.6,
				"%s spawn a <0.6m (actual %.3f)" % [track_id, absf((hit.position as Vector3).y - origin.y)])

	visual.queue_free()
	builder.clear_collision()
	builder.queue_free()
	await process_frame
