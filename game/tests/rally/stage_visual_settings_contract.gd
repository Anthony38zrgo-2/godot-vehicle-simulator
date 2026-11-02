extends SceneTree

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func inspect_meshes(node: Node, stage: int) -> void:
	if node is MeshInstance3D and node.mesh != null:
		check(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "stage %d shadows" % stage)
		for surface in node.mesh.get_surface_count():
			check((node.mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) == 0, "stage %d uncompressed mesh" % stage)
			var material: Material = node.get_active_material(surface)
			if material is BaseMaterial3D:
				check(material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_VERTEX, "vertex lighting")
				check(material.specular_mode == BaseMaterial3D.SPECULAR_DISABLED, "specular disabled")
				check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "same filtering")
				if material.albedo_texture != null:
					check(material.albedo_texture.get_image().has_mipmaps(), "stage %d texture has mipmaps: %s" % [stage, material.resource_name])
	for child in node.get_children():
		inspect_meshes(child, stage)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var wetness := RallyTerrainWetness.new()
	root.add_child(wetness)
	wetness.wetness = 0.5
	for stage in range(1, 11):
		var visual: Node3D = load("res://assets/rally/russia_stage%d/russia_stage%d_visual.glb" % [stage, stage]).instantiate()
		root.add_child(visual)
		var adjuster := RallyStageVisualMaterialAdjuster.new()
		adjuster.adjust_node(visual)
		adjuster.free()
		wetness.bind_visual_root(visual)
		check(not wetness._materials.is_empty(), "stage %d wet materials bound" % stage)
		for index in wetness._materials.size():
			check(is_equal_approx(wetness._original_roughness[index], 1.0), "wetness uses prepared roughness")
			check(wetness._materials[index].albedo_color.is_equal_approx(wetness._original_albedo[index] * Color(0.85, 0.85, 0.85, 1.0)), "wetness applied on load")
		inspect_meshes(visual, stage)
		print("VISUAL_SETTINGS stage=", stage, " wet_materials=", wetness._materials.size())
		visual.free()
	wetness.free()
	print("STAGE_VISUAL_SETTINGS_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
