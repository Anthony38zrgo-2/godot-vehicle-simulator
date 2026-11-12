extends SceneTree

## Fase 2: localiza superficies de agua en las 8 escenas importadas de Kenia
## y verifica sus transformaciones en el espacio del tramo. No modifica nada.

const STAGES := ["kenya_stage1", "kenya_stage2", "kenya_stage3", "kenya_stage4",
	"kenya_stage5", "kenya_stage6", "kenya_stage7", "kenya_stage8"]
const INTEREST := ["river1_1", "river2_1", "river1_2", "river2_2",
	"kenya_bridge", "kenya_bridge_log", "kenya_bridge_log2",
	"waterfall_1", "waterfall_2", "jungle_vaterfall",
	"jungle_vaterfall_left", "jungle_vaterfall_right",
	"kenya_river_dry_1", "kenya_river_dry_2",
	"kenya_river_dry_crossroad1", "kenya_river_dry_crossroad2",
	"kenya_river_1", "kenya_river_2", "kenya_river_4",
	"kenya_river_road_1", "kenya_river_road_2", "kenya_river_road_3",
	"jungle_river", "jungle_river_road"]


func mat_key(mat: Material) -> String:
	if mat is BaseMaterial3D:
		return str((mat as BaseMaterial3D).resource_name).to_lower()
	return ""


func surf_tris(mesh: Mesh, si: int) -> int:
	var arrays := mesh.surface_get_arrays(si)
	if arrays == null or arrays.is_empty():
		return 0
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if not idx.is_empty():
		return idx.size() / 3
	return verts.size() / 3


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var report := {}
	for stage in STAGES:
		var vpath := "res://assets/rally/%s/%s_visual.glb" % [stage, stage]
		var cpath := "res://assets/rally/%s/%s_collision.glb" % [stage, stage]
		var entry := {"visual_found": ResourceLoader.exists(vpath), "collision_found": ResourceLoader.exists(cpath), "materials": {}, "collision_nodes": []}
		if not ResourceLoader.exists(vpath):
			report[stage] = entry
			continue
		var packed := load(vpath) as PackedScene
		var inst := packed.instantiate()
		root.add_child(inst)
		await process_frame
		var agg := {}
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
					var key := mat_key(mat)
					if key.is_empty():
						continue
					if not agg.has(key):
						agg[key] = {"tris": 0, "min": [INF, INF, INF], "max": [-INF, -INF, -INF], "ymin": INF, "ymax": -INF}
					var tris := surf_tris(mesh, si)
					agg[key]["tris"] = int(agg[key]["tris"]) + tris
					var varr = mesh.surface_get_arrays(si)
					var verts: PackedVector3Array = varr[Mesh.ARRAY_VERTEX]
					for v in verts:
						var w: Vector3 = gt * v
						agg[key]["min"][0] = minf(agg[key]["min"][0], w.x)
						agg[key]["min"][1] = minf(agg[key]["min"][1], w.y)
						agg[key]["min"][2] = minf(agg[key]["min"][2], w.z)
						agg[key]["max"][0] = maxf(agg[key]["max"][0], w.x)
						agg[key]["max"][1] = maxf(agg[key]["max"][1], w.y)
						agg[key]["max"][2] = maxf(agg[key]["max"][2], w.z)
						agg[key]["ymin"] = minf(agg[key]["ymin"], w.y)
						agg[key]["ymax"] = maxf(agg[key]["ymax"], w.y)
			for child in node.get_children():
				stack.append(child)
		var mats := {}
		for key in agg:
			if key in INTEREST or key.begins_with("river") or key.contains("bridge") or key.contains("waterfall") or key.contains("vaterfall") or key.contains("river_dry"):
				mats[key] = agg[key]
		entry["materials"] = mats
		entry["river1_1_tris"] = int(agg.get("river1_1", {}).get("tris", 0))
		entry["river2_1_tris"] = int(agg.get("river2_1", {}).get("tris", 0))
		if ResourceLoader.exists(cpath):
			var cpacked := load(cpath) as PackedScene
			var cinst := packed.instantiate() if false else cpacked.instantiate()
			root.add_child(cinst)
			await process_frame
			var cnames := {}
			var cstack: Array = [cinst]
			while not cstack.is_empty():
				var cnode: Node = cstack.pop_back()
				if cnode is MeshInstance3D:
					var nm := (cnode as Node3D).name
					cnames[str(nm)] = int(cnames.get(str(nm), 0)) + 1
				for child in cnode.get_children():
					cstack.append(child)
			entry["collision_nodes"] = cnames
			cinst.queue_free()
		inst.queue_free()
		report[stage] = entry
		print("SURVEY ", stage, " river1_1=", entry["river1_1_tris"], " river2_1=", entry["river2_1_tris"], " mats=", (mats as Dictionary).keys())
	var path := "user://kenya_water_survey.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("SURVEY_SAVED ", ProjectSettings.globalize_path(path))
	quit(0)
