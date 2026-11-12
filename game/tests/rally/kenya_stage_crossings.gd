extends SceneTree

## Cruces ruta<->agua en stages 2/3/5/6: grupos contiguos, cota de agua por
## material, calzada de colisión e inmersión por punto. Solo malla con
## registro river (river1_1/river2_1); 4/7/8 no tienen.

const V := "res://assets/rally/kenya_stage%d/kenya_stage%d_visual.glb"
const C := "res://assets/rally/kenya_stage%d/kenya_stage%d_collision.glb"


func load_inst(path: String) -> Node:
	var inst := (load(path) as PackedScene).instantiate()
	root.add_child(inst)
	return inst


func collect(inst: Node, visual: bool, wanted: Dictionary) -> Dictionary:
	var out := {}
	for k in wanted:
		out[k] = []
	var stack: Array = [inst]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mi := node as MeshInstance3D
			var mesh := mi.mesh
			var gt := mi.global_transform
			if visual:
				for si in mesh.get_surface_count():
					var mat := mi.get_active_material(si)
					if mat == null:
						mat = mesh.surface_get_material(si)
					var key := ""
					if mat is BaseMaterial3D:
						key = str((mat as BaseMaterial3D).resource_name).to_lower()
					if not wanted.has(key):
						continue
					var varr = mesh.surface_get_arrays(si)
					var verts: PackedVector3Array = varr[Mesh.ARRAY_VERTEX]
					var i := 0
					while i < verts.size():
						(out[key] as Array).append(gt * verts[i])
						i += 4
			else:
				if not mi.name.to_lower().contains("road"):
					continue
				for si in mesh.get_surface_count():
					var varr = mesh.surface_get_arrays(si)
					var verts: PackedVector3Array = varr[Mesh.ARRAY_VERTEX]
					var i := 0
					while i < verts.size():
						(out["road"] as Array).append(gt * verts[i])
						i += 4
		for child in node.get_children():
			stack.append(child)
	return out


func gridify(pts: Array, cell: float) -> Dictionary:
	var g := {}
	for w in pts:
		var k := Vector2i(floori((w as Vector3).x / cell), floori((w as Vector3).z / cell))
		if not g.has(k):
			g[k] = []
		(g[k] as Array).append(w)
	return g


func nearest(g: Dictionary, cell: float, p: Vector3, radius: float) -> Array:
	var best_d := INF
	var best_y := 999.0
	var ck := Vector2i(floori(p.x / cell), floori(p.z / cell))
	var r := int(ceil(radius / cell))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var kk := ck + Vector2i(dx, dz)
			if not g.has(kk):
				continue
			for w in (g[kk] as Array):
				var d := Vector2((w as Vector3).x - p.x, (w as Vector3).z - p.z).length()
				if d < best_d:
					best_d = d
					best_y = (w as Vector3).y
	if best_d > radius:
		return [false, 0.0, 999.0]
	return [true, best_y, best_d]


func route_of(stage: int) -> Array:
	var pts: Array = []
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/rally/kenya_stage%d_route.json" % stage))
	for p in (parsed as Dictionary).get("points", []):
		pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return pts


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	for stage in [2, 3, 5, 6]:
		var vv := load_inst(V % [stage, stage])
		await process_frame
		var cc := load_inst(C % [stage, stage])
		await process_frame
		var dd: Dictionary = collect(vv, true, {"river1_1": true, "river2_1": true})
		var rd: Dictionary = collect(cc, false, {"road": true})
		var g1 := gridify(dd["river1_1"], 8.0)
		var g2 := gridify(dd["river2_1"], 8.0)
		var gr := gridify(rd["road"], 4.0)
		var rt := route_of(stage)
		var dist := 0.0
		var groups: Array = []
		var cur: Array = []
		for i in rt.size():
			if i > 0:
				dist += (rt[i - 1] as Vector3).distance_to(rt[i] as Vector3)
			var p: Vector3 = rt[i]
			var a: Array = nearest(g1, 8.0, p, 8.0)
			var b: Array = nearest(g2, 8.0, p, 8.0)
			if bool(a[0]) or bool(b[0]):
				cur.append(i)
			else:
				if not cur.is_empty():
					groups.append(cur)
					cur = []
		if not cur.is_empty():
			groups.append(cur)
		var total := dist
		print("STAGE ", stage, " groups=", groups.size(), " total_m=", snappedf(total, 0.1))
		for g in groups:
			var d0 := 0.0
			var d1 := 0.0
			var dd0 := 0.0
			for i in rt.size():
				if i > 0:
					dd0 += (rt[i - 1] as Vector3).distance_to(rt[i] as Vector3)
				if i == (g as Array)[0]:
					d0 = dd0
				if i == (g as Array)[-1]:
					d1 = dd0
			print(" GROUP idx=", (g as Array)[0], "-", (g as Array)[-1],
				" prog=", snappedf(d0, 0.1), "-", snappedf(d1, 0.1))
			for i in (g as Array):
				var p: Vector3 = rt[int(i)]
				var a: Array = nearest(g1, 8.0, p, 12.0)
				var b: Array = nearest(g2, 8.0, p, 12.0)
				var cr: Array = nearest(gr, 4.0, p, 8.0)
				var line := "  i=" + str(i) + " water1=" + ("%.3f@%.1f" % [float(a[1]), float(a[2])] if bool(a[0]) else "na")
				line += " water2=" + ("%.3f@%.1f" % [float(b[1]), float(b[2])] if bool(b[0]) else "na")
				if bool(cr[0]):
					line += " coll=%.3f@%.1f" % [float(cr[1]), float(cr[2])]
					if bool(a[0]):
						line += " sub1=%.3f" % (float(a[1]) - float(cr[1]))
					if bool(b[0]):
						line += " sub2=%.3f" % (float(b[1]) - float(cr[1]))
				else:
					line += " coll=na"
				print(line)
		vv.queue_free()
		cc.queue_free()
	quit(0)
