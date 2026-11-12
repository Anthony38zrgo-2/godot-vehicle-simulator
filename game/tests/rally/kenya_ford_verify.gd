extends SceneTree

## Verificación fina: calzada en radio 2 m por punto (outlier i=125 stage2),
## y puente cercano al cruce alto de stage6 (idx 180-182).

const V := "res://assets/rally/kenya_stage%d/kenya_stage%d_visual.glb"
const C := "res://assets/rally/kenya_stage%d/kenya_stage%d_collision.glb"


func load_inst(path: String) -> Node:
	var inst := (load(path) as PackedScene).instantiate()
	root.add_child(inst)
	return inst


func collect_road(inst: Node) -> Array:
	var pts: Array = []
	var stack: Array = [inst]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mi := node as MeshInstance3D
			if not mi.name.to_lower().contains("road"):
				continue
			var mesh := mi.mesh
			var gt := mi.global_transform
			for si in mesh.get_surface_count():
				var varr = mesh.surface_get_arrays(si)
				var verts: PackedVector3Array = varr[Mesh.ARRAY_VERTEX]
				var i := 0
				while i < verts.size():
					pts.append(gt * verts[i])
					i += 2
		for child in node.get_children():
			stack.append(child)
	return pts


func bridge_near(inst: Node, p: Vector3, radius: float) -> Array:
	var best_d := INF
	var best_y := 999.0
	var found := false
	var stack: Array = [inst]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mi := node as MeshInstance3D
			var mesh := mi.mesh
			var gt := mi.global_transform
			for si in mesh.get_surface_count():
				var mat := mi.get_active_material(si)
				if mat == null:
					mat = mesh.surface_get_material(si)
				var key := ""
				if mat is BaseMaterial3D:
					key = str((mat as BaseMaterial3D).resource_name).to_lower()
				if not key.contains("bridge"):
					continue
				var varr = mesh.surface_get_arrays(si)
				var verts: PackedVector3Array = varr[Mesh.ARRAY_VERTEX]
				var i := 0
				while i < verts.size():
					var w: Vector3 = gt * verts[i]
					var d := Vector2(w.x - p.x, w.z - p.z).length()
					if d < best_d:
						best_d = d
						best_y = w.y
						found = true
					i += 6
		for child in node.get_children():
			stack.append(child)
	return [found, best_y, best_d]


func route_of(stage: int) -> Array:
	var pts: Array = []
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/rally/kenya_stage%d_route.json" % stage))
	for p in (parsed as Dictionary).get("points", []):
		pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return pts


func stats(pts: Array, p: Vector3, radius: float) -> String:
	var ys := []
	for w in pts:
		if Vector2((w as Vector3).x - p.x, (w as Vector3).z - p.z).length() <= radius:
			ys.append((w as Vector3).y)
	if ys.is_empty():
		return "n=0"
	ys.sort()
	return "n=%d min=%.3f med=%.3f max=%.3f" % [ys.size(), ys[0], ys[ys.size() / 2], ys[-1]]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# Stage2: radio 2 m en grupos A y B.
	var c2 := load_inst(C % [2, 2])
	await process_frame
	var road2 := collect_road(c2)
	var rt2 := route_of(2)
	for i in [124, 125, 126, 127, 128, 408, 409, 410]:
		print("S2 i=", i, " route=", rt2[i], " road2m: ", stats(road2, rt2[i], 2.0),
			" road6m: ", stats(road2, rt2[i], 6.0))
	c2.queue_free()
	# Stage6: puente cerca de idx 180-182.
	var v6 := load_inst(V % [6, 6])
	await process_frame
	var rt6 := route_of(6)
	for i in [114, 115, 116, 117, 180, 181, 182]:
		var b: Array = bridge_near(v6, rt6[i], 60.0)
		print("S6 i=", i, " route=", rt6[i],
			" bridge=", ("%.3f@%.1f" % [float(b[1]), float(b[2])] if bool(b[0]) else "none"))
	v6.queue_free()
	quit(0)
