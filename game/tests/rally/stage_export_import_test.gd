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
	assert(await builder.build_collision())
	var expected := 0
	for count in manifest.collision.collision_objects.values():
		expected += int(count)
	assert(builder.generated_triangle_count == expected)
	assert(builder.generated_body_count == manifest.collision.collision_objects.size())
	for group in ["Gravel", "Grass", "Dirt", "Sand"]:
		assert(not get_nodes_in_group(group).is_empty())
	visual.queue_free()
	builder.queue_free()
	await process_frame
	print("Stage export import: visual, collision and surface groups OK")
	quit()
