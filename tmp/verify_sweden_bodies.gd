extends SceneTree
## Probe: build Sweden collision via the runtime builder and dump per-body
## surface metadata. No physics driving, no force changes.

const Builder = preload("res://scripts/rally/rally_track_collision_builder.gd")

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var track_id := "sweden_stage1"
	var loader = load("res://scripts/rally/rally_stage_loader.gd").new()
	var resolved: Dictionary = loader.resolve(track_id)
	check(not resolved.is_empty(), "stage resolve ok")
	var paths: Dictionary = resolved.get("paths", {})
	var visual: Node3D = load(str(paths["visual"])).instantiate()
	root.add_child(visual)
	var builder = Builder.new()
	builder.collision_scene_path = str(paths["collision"])
	root.add_child(builder)
	check(builder.build_collision(visual), "build_collision ok")
	var road_packed := 0
	var road_total := 0
	var loose_bodies := 0
	var erosion_in_export := 0
	var groups := {}
	for child in builder.get_children():
		if not (child is StaticBody3D):
			continue
		var base := str(child.get_meta("base_surface_id", "?"))
		var layer := str(child.get_meta("winter_layer_id", ""))
		var src := str(child.get_meta("source_material", "?"))
		var is_road := bool(child.get_meta("is_stage_road", false))
		var tris := 0
		for sub in child.get_children():
			if sub is CollisionShape3D and (sub as CollisionShape3D).shape is ConcavePolygonShape3D:
				tris += int(((sub as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces().size() / 3)
		groups[base] = int(groups.get(base, 0)) + tris
		if is_road:
			road_total += tris
			if layer == "snow_packed":
				road_packed += tris
		if layer == "snow_loose":
			loose_bodies += 1
		if src.begins_with("erosion_snow_"):
			erosion_in_export += tris
		print("BODY name=%s base=%s layer=%s src=%s tris=%d" % [child.name, base, layer, src, tris])
	print("ROAD total=%d packed=%d" % [road_total, road_packed])
	print("GROUPS %s" % str(groups))
	print("snow_loose bodies=%d erosion_src_bodies=%d" % [loose_bodies, erosion_in_export])
	check(road_total > 30000, "road corridor present")
	check(road_packed == road_total and road_total > 0, "all road contact is snow_packed")
	# Erosion banks must come ONLY from the runtime bank pass (the last
	# children appended by build_erosion_bank_collision), never from the
	# exported GLB. Stage1 visual erosion total = 3155 (all exact matches).
	var kids := builder.get_children()
	var tail_erosion := 0
	for i in range(kids.size() - 3, kids.size()):
		if kids[i] is StaticBody3D and str((kids[i] as StaticBody3D).get_meta("source_material", "")).begins_with("erosion_snow_"):
			var bsh = (kids[i] as StaticBody3D).get_child(0)
			if bsh is CollisionShape3D and (bsh as CollisionShape3D).shape is ConcavePolygonShape3D:
				tail_erosion += int((((bsh as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces().size() / 3))
	check(erosion_in_export == tail_erosion and tail_erosion == 3155, "erosion only from runtime banks (3155), none exported")
	check(groups.has("Gravel") and groups.has("Grass"), "base groups present")
	print("SWEDEN_BODIES_PROBE ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
