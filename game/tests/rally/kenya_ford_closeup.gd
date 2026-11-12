extends SceneTree

## Fase 2 (cierre): cobertura y orillas del vado B, poses de cámara,
## cruces en 2/3/5/6 y texturas de agua en 4/7/8.

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
						i += 2
			else:
				if not mi.name.to_lower().contains("road"):
					continue
				for si in mesh.get_surface_count():
					var varr = mesh.surface_get_arrays(si)
					var verts: PackedVector3Array = varr[Mesh.ARRAY_VERTEX]
					var i := 0
					while i < verts.size():
						(out["road"] as Array).append(gt * verts[i])
						i += 2
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
	# --- Vado B: cobertura de calzada 166-170 y orillas ---
	var v1 := load_inst(V % [1, 1])
	await process_frame
	var c1 := load_inst(C % [1, 1])
	await process_frame
	var vv: Dictionary = collect(v1, true, {"river2_1": true})
	var cc: Dictionary = collect(c1, false, {"road": true})
	var gr: Dictionary = gridify(cc["road"], 4.0)
	var route := route_of(1)
	var dist := 0.0
	for i in route.size():
		if i > 0:
			dist += (route[i - 1] as Vector3).distance_to(route[i] as Vector3)
		if i >= 164 and i <= 172:
			var p: Vector3 = route[i]
			var n: Array = nearest(gr, 4.0, p, 6.0)
			print("COVER i=", i, " prog=", snappedf(dist, 0.01),
				" coll_ok=", bool(n[0]), " coll_y=", (snappedf(float(n[1]), 0.001) if bool(n[0]) else "na"),
				" coll_d=", (snappedf(float(n[2]), 0.01) if bool(n[0]) else "na"))
	# Orillas: calzada min/max en anillo 8-25 m del centro del vado.
	var mid := Vector3(761.519, -5.755, -1321.138)
	var bank_l := []
	var bank_r := []
	var tangent := Vector3(-0.860, 0.0, -0.510)
	var side := tangent.cross(Vector3.UP).normalized()
	for w in (cc["road"] as Array):
		var d := Vector2((w as Vector3).x - mid.x, (w as Vector3).z - mid.z)
		var lateral: float = d.dot(Vector2(side.x, side.z))
		if absf(d.length()) >= 8.0 and absf(d.length()) <= 25.0 and absf(d.dot(Vector2(tangent.x, tangent.z))) <= 12.0:
			if lateral > 0.0:
				bank_r.append((w as Vector3).y)
			else:
				bank_l.append((w as Vector3).y)
	bank_l.sort()
	bank_r.sort()
	print("BANK left n=", bank_l.size(), " min=", snappedf(bank_l[0], 0.001) if not bank_l.is_empty() else "na",
		" p10=", snappedf(bank_l[bank_l.size() / 10], 0.001) if not bank_l.is_empty() else "na")
	print("BANK right n=", bank_r.size(), " min=", snappedf(bank_r[0], 0.001) if not bank_r.is_empty() else "na",
		" p10=", snappedf(bank_r[bank_r.size() / 10], 0.001) if not bank_r.is_empty() else "na")
	# Poses de cámara: fija lateral + cabina en el vado (pendiente captura en juego).
	var cam_fixed := mid + side * 9.0 + Vector3(0, 2.2, 0)
	var cam_cockpit := Vector3(761.519, -5.755 + 1.15, -1321.138) + tangent * -6.0
	print("CAM fixed pos=", cam_fixed, " look=", mid)
	print("CAM cockpit pos=", cam_cockpit, " look=", cam_cockpit + tangent * 10.0 + Vector3(0, -0.4, 0))
	v1.queue_free()
	c1.queue_free()

	# --- Cruces en 2/3/5/6 (grueso, radio 8 m) ---
	for stage in [2, 3, 5, 6]:
		var vv2 := load_inst(V % [stage, stage])
		await process_frame
		var dd: Dictionary = collect(vv2, true, {"river1_1": true, "river2_1": true})
		var all: Array = []
		all.append_array(dd["river1_1"])
		all.append_array(dd["river2_1"])
		var g := gridify(all, 8.0)
		var rt := route_of(stage)
		var d := 0.0
		var hits := 0
		var first := -1.0
		var last := -1.0
		for i in rt.size():
			if i > 0:
				d += (rt[i - 1] as Vector3).distance_to(rt[i] as Vector3)
			var p: Vector3 = rt[i]
			var n: Array = nearest(g, 8.0, p, 8.0)
			if bool(n[0]):
				hits += 1
				if first < 0.0:
					first = d
				last = d
		print("X stage=", stage, " route_pts_near_water=", hits, " prog_first=", snappedf(first, 0.1), " prog_last=", snappedf(last, 0.1), " total_m=", snappedf(d, 0.1))
		vv2.queue_free()
	quit(0)
