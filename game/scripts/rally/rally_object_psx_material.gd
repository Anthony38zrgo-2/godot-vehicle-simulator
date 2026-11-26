extends RefCounted

const SURFACE := preload("res://scripts/rally/rally_object_psx.gdshader")
const SURFACE_NO_FOG := preload("res://scripts/rally/rally_object_psx_no_fog.gdshader")
const SURFACE_ALPHA := preload("res://scripts/rally/rally_object_psx_alpha.gdshader")
const SURFACE_ALPHA_NO_FOG := preload("res://scripts/rally/rally_object_psx_alpha_no_fog.gdshader")


static func from_standard(source: Material) -> Material:
	if not source is StandardMaterial3D:
		return source
	var base := source as StandardMaterial3D
	var material := ShaderMaterial.new()
	match base.transparency:
		BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			material.shader = SURFACE_NO_FOG if base.disable_fog else SURFACE
		BaseMaterial3D.TRANSPARENCY_ALPHA:
			if base.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
				return source
			material.shader = SURFACE_ALPHA_NO_FOG if base.disable_fog else SURFACE_ALPHA
		_:
			return source
	material.resource_name = source.resource_name
	material.next_pass = source.next_pass
	material.set_shader_parameter("tint", base.albedo_color)
	material.set_shader_parameter("billboard_y", base.billboard_mode == BaseMaterial3D.BILLBOARD_FIXED_Y)
	material.set_shader_parameter("cull_side", base.cull_mode)
	material.set_shader_parameter("use_vertex_color", base.vertex_color_use_as_albedo)
	material.set_shader_parameter("vertex_color_srgb", base.vertex_color_is_srgb)
	material.set_shader_parameter("roughness_value", base.roughness)
	material.set_shader_parameter("metallic_value", base.metallic)
	material.set_shader_parameter("specular_value", 0.0 if base.specular_mode == BaseMaterial3D.SPECULAR_DISABLED else base.metallic_specular)
	material.set_shader_parameter("unshaded_surface", base.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	material.set_shader_parameter("emission_tint", base.emission)
	material.set_shader_parameter("emission_strength", base.emission_energy_multiplier if base.emission_enabled else 0.0)
	if base.backlight_enabled:
		material.set_shader_parameter("backlight_tint", base.backlight)
	if base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		material.set_shader_parameter("alpha_cutoff", base.alpha_scissor_threshold)
	if base.albedo_texture != null:
		var nearest := base.texture_filter in [BaseMaterial3D.TEXTURE_FILTER_NEAREST, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC]
		var repeat := base.get_flag(BaseMaterial3D.FLAG_USE_TEXTURE_REPEAT)
		var sampler := ("texture_nearest" if nearest else "texture_smooth") + ("" if repeat else "_clamped")
		material.set_shader_parameter(sampler, base.albedo_texture)
		material.set_shader_parameter("use_texture", true)
		material.set_shader_parameter("nearest_filter", nearest)
		material.set_shader_parameter("repeat_texture", repeat)
		material.set_shader_parameter("uv_scale", Vector2(base.uv1_scale.x, base.uv1_scale.y))
		material.set_shader_parameter("uv_offset", Vector2(base.uv1_offset.x, base.uv1_offset.y))
	return material


static func apply_tree(node: Node, materials: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		if node.material_override != null:
			node.material_override = cached(node.material_override, materials)
		else:
			for i in node.mesh.get_surface_count():
				var source: Material = node.get_active_material(i)
				if source != null:
					var material := cached(source, materials)
					if material != source:
						node.set_surface_override_material(i, material)
	for child in node.get_children():
		apply_tree(child, materials)


static func cached(source: Material, materials: Dictionary) -> Material:
	if not materials.has(source):
		materials[source] = from_standard(source)
	return materials[source]
