extends SceneTree
## Fast mirror of stage_export_import_test.gd assertions (no grass/puddles/waits).

const Builder = preload("res://scripts/rally/rally_track_collision_builder.gd")

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/rally/russia_stage1/manifest.json"))
	var visual = load("res://assets/rally/russia_stage1/" + str(manifest.visual.path)).instantiate()
	root.add_child(visual)
	check(visual.get_child_count() == 5, "visual child count == 5")
	var builder = Builder.new()
	root.add_child(builder)
	check(await builder.build_collision(visual), "build_collision ok")
	var expected := 0
	var collision = load("res://assets/rally/russia_stage1/" + str(manifest.collision.path)).instantiate()
	var meshes: Array[MeshInstance3D] = []
	builder.collect_mesh_instances(collision, meshes)
	for mesh in meshes:
		expected += mesh.mesh.get_faces().size() / 3
	collision.free()
	print("RUSSIA_COUNTS generated=%d expected_glb=%d bodies=%d manifest_nodes=%d" % [builder.generated_triangle_count, expected, builder.generated_body_count, (manifest.collision.collision_objects as Dictionary).size()])
	check(builder.generated_triangle_count == expected + 582, "triangles == glb + 582 banks (got %d, want %d)" % [builder.generated_triangle_count, expected + 582])
	check(builder.generated_body_count == (manifest.collision.collision_objects as Dictionary).size() + 3, "bodies == nodes + 3 banks")
	var dirt_triangles := 0
	for body in get_nodes_in_group("Dirt"):
		var shape = body.get_child(0).shape
		dirt_triangles += shape.get_faces().size() / 3
	check(dirt_triangles == 11695 + 582, "dirt == 11695 + 582 (got %d)" % dirt_triangles)
	for group in ["Gravel", "Grass", "Dirt", "Sand"]:
		check(not get_nodes_in_group(group).is_empty(), "group present: " + group)
	print("RUSSIA_COUNTS_PROBE ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
