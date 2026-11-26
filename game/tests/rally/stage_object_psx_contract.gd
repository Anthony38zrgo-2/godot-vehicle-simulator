extends SceneTree

const ObjectMaterial := preload("res://scripts/rally/rally_object_psx_material.gd")
const Grass := preload("res://scripts/rally/rally_stage_grass.gd")
const Markers := preload("res://scripts/rally/rally_stage_markers.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(4.0, 2.5, 6.0)
	camera.look_at(Vector3(0.0, 0.8, 0.0))
	camera.current = true
	var sun := DirectionalLight3D.new()
	stage.add_child(sun)
	sun.rotation_degrees = Vector3(-48, 25, 0)

	var texture := preload("res://assets/rally/stage_markers/marshal.png")
	var grass_source := StandardMaterial3D.new()
	grass_source.albedo_texture = texture
	var card := QuadMesh.new()
	card.material = grass_source
	var card_node := MeshInstance3D.new()
	card_node.mesh = card
	var grass := Grass.new()
	grass.face_camera = true
	grass.outline_bush_cards = true
	grass.fog_enabled = false
	var grass_mat := grass._make_material(card_node) as ShaderMaterial
	grass.free()
	card_node.free()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = card
	multimesh.instance_count = 2
	multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(-2, 0.7, 0)))
	multimesh.set_instance_transform(1, Transform3D(Basis.IDENTITY, Vector3(-1, 0.7, 0)))
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = multimesh
	batch.material_override = grass_mat
	stage.add_child(batch)

	var terrain := _add_box(stage, "Terrain_Dirt", "dirt", Vector3(0, -0.26, 0), Vector3(12, 0.5, 12))
	var mountain := _add_box(stage, "Rajuntay Regional DEM", "DEM regional", Vector3(0, 0, -8), Vector3(12, 1, 2))
	var house := _add_box(stage, "TestHouse", "house", Vector3(0.5, 1.0, 0), Vector3(1.3, 2.0, 1.1))
	var finish_board := _add_box(stage, "Meta_L", "Meta blanco", Vector3.ZERO, Vector3.ONE)
	var finish_post := _add_box(stage, "Meta_R_soporte_1", "Meta negro", Vector3.ZERO, Vector3.ONE)
	var classic_finish := _add_box(stage, "ClassicSign", "fin_gate_finish.001", Vector3.ZERO, Vector3.ONE)
	var checkpoint := _add_box(stage, "Checkpoint", "checkpoint", Vector3(0.0, 5.0, 0.0), Vector3.ONE)
	var adjuster := RallyStageVisualMaterialAdjuster.new()
	adjuster.adjust_node(stage)
	adjuster.free()
	var house_mat := house.get_active_material(0) as ShaderMaterial
	var alpha_source := StandardMaterial3D.new()
	alpha_source.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	alpha_source.albedo_color = Color(0.4, 0.6, 0.8, 0.4)
	var glass := _add_box(stage, "Window", "window", Vector3(2.0, 0.7, 0), Vector3(0.3, 1.4, 0.7))
	glass.material_override = ObjectMaterial.from_standard(alpha_source)

	var markers := Markers.new()
	stage.add_child(markers)
	markers.build(Vector3(0.0, 0.0, -1.0), Vector3.FORWARD, {}, 1)
	markers.set_phase("go")
	var people := markers.find_children("*", "Sprite3D", true, false)
	var person := people.front() as Sprite3D if not people.is_empty() else null
	var person_mat := person.material_override as ShaderMaterial if person != null else null
	var ok := house_mat != null and person_mat != null and terrain.get_active_material(0) is StandardMaterial3D and mountain.get_active_material(0) is StandardMaterial3D
	var hidden := classic_finish.get_active_material(0) as StandardMaterial3D
	ok = ok and not finish_board.visible and not finish_post.visible
	ok = ok and hidden != null and hidden.albedo_color.a == 0.0
	ok = ok and checkpoint.visible and checkpoint.get_active_material(0) is ShaderMaterial
	ok = ok and grass_mat.shader == ObjectMaterial.SURFACE_NO_FOG and grass_mat.next_pass != null
	ok = ok and bool(grass_mat.get_shader_parameter("billboard_y")) and is_equal_approx(float(grass_mat.get_shader_parameter("alpha_cutoff")), 0.38)
	ok = ok and not is_zero_approx(float(markers._green.get_shader_parameter("emission_strength")))
	for material in [grass_mat, house_mat, person_mat, glass.material_override]:
		if material == null:
			continue
		var constants: Array = material.shader.get_shader_uniform_list()
		ok = ok and constants.any(func(u: Dictionary) -> bool: return u.name == "psx_affine_strength")

	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var enabled := root.get_texture().get_image().get_data()
		for material in [grass_mat, grass_mat.next_pass, house_mat, person_mat, glass.material_override]:
			if material != null:
				material.set_shader_parameter("psx_snap_strength", 0.0)
				material.set_shader_parameter("psx_affine_strength", 0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		ok = ok and enabled != root.get_texture().get_image().get_data()
	stage.queue_free()
	await process_frame
	await process_frame
	print("STAGE_OBJECT_PSX_CONTRACT ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _add_box(stage: Node3D, label: String, material_name: String, point: Vector3, dimensions: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	var box := BoxMesh.new()
	box.size = dimensions
	var surface := StandardMaterial3D.new()
	surface.resource_name = material_name
	box.material = surface
	instance.mesh = box
	stage.add_child(instance)
	instance.position = point
	return instance
