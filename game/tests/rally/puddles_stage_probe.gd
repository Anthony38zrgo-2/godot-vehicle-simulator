extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 180:
		await process_frame
	var session = scene
	var puddles = session.get_node("RallyPuddles")
	puddles.build()
	assert(puddles.patches.size() > 0, "No valid puddles on actual stage")
	puddles.provider = null
	puddles.wetness_node.wetness = 1.0
	puddles.wetness_node.set_process(false)
	puddles._physics_process(0.3)
	var patch: Dictionary = puddles.patches[0]
	assert(float(puddles.sample_contact(patch.transform.origin).depth_mm) > 0.0)
	for item in scene.find_children("*", "CanvasItem", true, false):
		(item as CanvasItem).hide()
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.global_position = patch.transform.origin + Vector3(3.0, 1.2, 4.0)
	camera.look_at(patch.transform.origin)
	camera.current = true
	for i in 8:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://puddles_stage_probe.png")
	print("PUDDLES_STAGE_PROBE_OK count=", puddles.patches.size(), " screenshot=", ProjectSettings.globalize_path("user://puddles_stage_probe.png"))
	quit()
