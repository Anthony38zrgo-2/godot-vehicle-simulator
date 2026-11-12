extends SceneTree

## Fase 2 (profundo): vado piloto de Kenia 1 y puente control.
## Cruces ruta<->agua, calzada de colisión, lecho, orillas y cota máxima.

const visual1 := "res://assets/rally/kenya_stage1/kenya_stage1_visual.glb"
const coll1 := "res://assets/rally/kenya_stage1/kenya_stage1_collision.glb"
const visual5 := "res://assets/rally/kenya_stage5/kenya_stage5_visual.glb"


func collect_verts(inst: Node, wanted: Dictionary) -> Dictionary:
	var out := {}
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
				if not wanted.has(key):
					continue
				var varr = mesh.surface_get_arrays(si)
				var verts: PackedVector3Array = varr[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = varr[Mesh.ARRAY_INDEX]
				var pts: Array = out.get(key, [])
				if idx.is_empty():
					var i := 0
					while i < verts.size():
						pts.append(gt * verts[i])
						i += 7
				else:
					var i := 0
					while i < idx.size():
						pts.append(gt * verts[idx[i]])
						i += 21
				out[key] = pts
		for child in node.get_children():
			stack.append(child)
	return out


func route_points(path: String) -> Array:
	var pts: Array = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	for p in (parsed as Dictionary).get("points", []):
		pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return pts


func route_dists(pts: Array) -> PackedFloat64Array:
	var d := PackedFloat64Array([0.0])
	for i in range(1, pts.size()):
		d.append(d[-1] + (pts[i - 1] as Vector3).distance_to(pts[i] as Vector3))
	return d


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var report := {}
	# --- Kenia 1 ---
	var vinst := (load(visual1) as PackedScene).instantiate()
	root.add_child(vinst)
	await process_frame
	var vwanted := {"river2_1": true, "river1_1": true, "kenya_river_2": true,
		"kenya_river_road_2": true, "jungle_river_road": true}
	var vv := collect_verts(vinst, vwanted)
	var cinst := (load(coll1) as PackedScene).instantiate()
	root.add_child(cinst)
	await process_frame
	var cwanted := {"collision_road": true, "collision_terrain_dirt": true,
		"collision_terrain_grass": true}
	# La colisión no lleva materiales con nombre: agrupar por nombre de nodo.
	var croad: Array = []
	var cterr: Array = []
	var stack: Array = [cinst]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mi := node as MeshInstance3D
			var nname := mi.name.to_lower()
			var mesh := mi.mesh
			var gt := mi.global_transform
			for si in mesh.get_surface_count():
				var varr = mesh.surface_get_arrays(si)
				var verts: PackedVector3Array = varr[Mesh.ARRAY_VERTEX]
				var i := 0
				while i < verts.size():
					var w: Vector3 = gt * verts[i]
					if nname.contains("road"):
						croad.append(w)
					else:
						cterr.append(w)
					i += 3
		for child in node.get_children():
			stack.append(child)
	print("FORD verts river2=", (vv.get("river2_1", []) as Array).size(),
		" riverbed=", (vv.get("kenya_river_2", []) as Array).size(),
		" coll_road=", croad.size(), " coll_terr=", cterr.size())

	var route := route_points("res://data/rally/kenya_stage1_route.json")
	var dists := route_dists(route)
	var water: Array = vv.get("river2_1", [])
	# Rejilla grosera del agua para proximidad ruta<->cauce.
	var cell := {}
	for w in water:
		var k := Vector2i(floori((w as Vector3).x / 4.0), floori((w as Vector3).z / 4.0))
		if not cell.has(k):
			cell[k] = []
		(cell[k] as Array).append(w)
	var near: Array = []  # indices de ruta a <=8 m del agua (XZ)
	for i in route.size():
		var p: Vector3 = route[i]
		var ck := Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
		var best := INF
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				var kk := ck + Vector2i(dx, dz)
				if not cell.has(kk):
					continue
				for w in (cell[kk] as Array):
					var d := Vector2(p.x - (w as Vector3).x, p.z - (w as Vector3).z).length()
					best = minf(best, d)
		if best <= 8.0:
			near.append(i)
	# Agrupar contiguos -> candidatos de vado.
	var groups: Array = []
	var cur: Array = []
	for i in near:
		if cur.is_empty() or i == cur[-1] + 1:
			cur.append(i)
		else:
			groups.append(cur)
			cur = [i]
	if not cur.is_empty():
		groups.append(cur)
	var ginfo := []
	for g in groups:
		ginfo.append({"from": g[0], "to": g[-1], "n": g.size(),
			"prog_from": dists[g[0]], "prog_to": dists[g[-1]]})
	report["ford_candidate_groups"] = ginfo
	print("FORD groups=", JSON.stringify(ginfo))
	# Vado = grupo más largo.
	var best_g: Array = []
	for g in groups:
		if g.size() > best_g.size():
			best_g = g
	if best_g.is_empty():
		push_error("sin cruce ruta-agua en Kenia 1")
		quit(1)
		return
	var mid: Vector3 = route[best_g[best_g.size() / 2]]
	var prog: float = dists[best_g[best_g.size() / 2]]
	var tangent: Vector3 = (route[min(best_g[-1] + 1, route.size() - 1)] as Vector3) - (route[max(best_g[0] - 1, 0)] as Vector3)
	tangent.y = 0.0
	tangent = tangent.normalized()
	var side := tangent.cross(Vector3.UP).normalized()
	# Alturas: agua, calzada colisión, lecho y orillas cerca del centro.
	var river_y := []
	for w in water:
		if Vector2((w as Vector3).x - mid.x, (w as Vector3).z - mid.z).length() <= 12.0:
			river_y.append((w as Vector3).y)
	var road_y := []
	for w in croad:
		if Vector2((w as Vector3).x - mid.x, (w as Vector3).z - mid.z).length() <= 12.0:
			road_y.append((w as Vector3).y)
	var bed_y := []
	for w in (vv.get("kenya_river_2", []) as Array):
		if Vector2((w as Vector3).x - mid.x, (w as Vector3).z - mid.z).length() <= 12.0:
			bed_y.append((w as Vector3).y)
	# Sección transversal orilla-orilla: calzada+terreno a lo largo de side.
	var profile := []
	for off in [-15.0, -12.0, -9.0, -6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 9.0, 12.0, 15.0]:
		var c: Vector3 = mid + side * float(off)
		var ys := []
		for w in croad:
			if Vector2((w as Vector3).x - c.x, (w as Vector3).z - c.z).length() <= 2.5:
				ys.append((w as Vector3).y)
		for w in cterr:
			if Vector2((w as Vector3).x - c.x, (w as Vector3).z - c.z).length() <= 2.5:
				ys.append((w as Vector3).y)
		ys.sort()
		var med := -999.0
		if not ys.is_empty():
			med = ys[ys.size() / 2]
		profile.append({"off": off, "n": ys.size(), "median_y": med})
	report["ford"] = {
		"center": [mid.x, mid.y, mid.z],
		"route_index": best_g[best_g.size() / 2],
		"progress_m": prog,
		"direction": [tangent.x, tangent.y, tangent.z],
		"river_y_min": _minmax(river_y)[0], "river_y_max": _minmax(river_y)[1],
		"road_y_min": _minmax(road_y)[0], "road_y_max": _minmax(road_y)[1],
		"bed_y_min": _minmax(bed_y)[0], "bed_y_max": _minmax(bed_y)[1],
		"cross_section": profile,
	}
	print("FORD center=", mid, " prog=", prog, " dir=", tangent)
	print("FORD river_y=", _minmax(river_y), " road_y=", _minmax(road_y), " bed_y=", _minmax(bed_y))
	for row in profile:
		print("FORD sect off=", row["off"], " n=", row["n"], " med_y=", row["median_y"])
	vinst.queue_free()
	cinst.queue_free()

	# --- Puente control (Kenia 5: tablero + lámina debajo) ---
	var v5 := (load(visual5) as PackedScene).instantiate()
	root.add_child(v5)
	await process_frame
	var b := collect_verts(v5, {"kenya_bridge": true, "river2_1": true})
	var deck: Array = b.get("kenya_bridge", [])
	var w5: Array = b.get("river2_1", [])
	var dc := Vector3.ZERO
	for w in deck:
		dc += (w as Vector3)
	dc /= maxf(deck.size(), 1.0)
	# Agua bajo el tablero (radio 20 m XZ).
	var wnear := []
	for w in w5:
		if Vector2((w as Vector3).x - dc.x, (w as Vector3).z - dc.z).length() <= 20.0:
			wnear.append((w as Vector3).y)
	var route5 := route_points("res://data/rally/kenya_stage5_route.json")
	var dists5 := route_dists(route5)
	var bi := 0
	var bd := INF
	for i in route5.size():
		var d: float = Vector2((route5[i] as Vector3).x - dc.x, (route5[i] as Vector3).z - dc.z).length()
		if d < bd:
			bd = d
			bi = i
	report["bridge_control"] = {
		"stage": "kenya_stage5",
		"deck_center": [dc.x, dc.y, dc.z], "deck_y_min": _minmax(deck)[0], "deck_y_max": _minmax(deck)[1],
		"water_below_min": _minmax(wnear)[0], "water_below_max": _minmax(wnear)[1],
		"route_index": bi, "route_distance_m": bd, "progress_m": dists5[bi],
		"clearance_m": _minmax(deck)[0] - _minmax(wnear)[1],
	}
	print("BRIDGE deck=", dc, " deck_y=", _minmax(deck), " water_below=", _minmax(wnear),
		" route_i=", bi, " route_d=", bd, " prog=", dists5[bi])
	v5.queue_free()
	var path := "user://kenya_ford_report.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("FORD_SAVED ", ProjectSettings.globalize_path(path))
	quit(0)


func _minmax(xs: Array) -> Array:
	if xs.is_empty():
		return [-999.0, -999.0]
	var mn := INF
	var mx := -INF
	for x in xs:
		var v := float(x) if not (x is Vector3) else (x as Vector3).y
		mn = minf(mn, v)
		mx = maxf(mx, v)
	return [mn, mx]
