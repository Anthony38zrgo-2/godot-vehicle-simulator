extends SceneTree

const Builder = preload("res://scripts/rally/rally_track_collision_builder.gd")

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/rally/russia_stage1/manifest.json"))
	var visual = load("res://assets/rally/russia_stage1/" + str(manifest.visual.path)).instantiate()
	root.add_child(visual)
	assert(visual.get_child_count() == 5)
	var builder = Builder.new()
	root.add_child(builder)
	assert(await builder.build_collision(visual))
	var expected := 0
	# The manifest still counts duplicate barrier backfaces removed from the GLB.
	var collision = load("res://assets/rally/russia_stage1/" + str(manifest.collision.path)).instantiate()
	var meshes: Array[MeshInstance3D] = []
	builder.collect_mesh_instances(collision, meshes)
	for mesh in meshes:
		expected += mesh.mesh.get_faces().size() / 3
	collision.free()
	assert(builder.generated_triangle_count == expected + 582)
	assert(builder.generated_body_count == manifest.collision.collision_objects.size() + 3)
	var dirt_triangles := 0
	for body in get_nodes_in_group("Dirt"):
		var shape = body.get_child(0).shape
		assert(shape.backface_collision)
		dirt_triangles += shape.get_faces().size() / 3
	assert(dirt_triangles == 11695 + 582)
	for group in ["Gravel", "Grass", "Dirt", "Sand"]:
		assert(not get_nodes_in_group(group).is_empty())
	visual.queue_free()
	builder.queue_free()
	await process_frame
	print("Stage export import: visual, collision and surface groups OK")
	quit()
