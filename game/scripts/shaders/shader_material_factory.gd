class_name ShaderMaterialFactory
extends RefCounted
## Builds and configures ShaderMaterial instances from Data-Driven registry & JSON presets.

const _ShaderRegistry := preload("res://scripts/shaders/shader_registry.gd")
const _ShaderPresetResolver := preload("res://scripts/shaders/shader_preset_resolver.gd")


static func create_from_shader(shader_id: String, params: Dictionary = {}) -> ShaderMaterial:
	var shader := _ShaderRegistry.get_shader(shader_id)
	if shader == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	if not params.is_empty():
		apply_params(mat, params, shader_id)
	return mat


static func create_from_preset(
	preset_id: String,
	overrides: Dictionary = {},
	apply_quality_profile: bool = false
) -> ShaderMaterial:
	var resolved := _ShaderPresetResolver.resolve_preset(preset_id, apply_quality_profile)
	if resolved.is_empty():
		return null
	var shader_id := str(resolved.get("shader_id", ""))
	if shader_id.is_empty():
		push_error("ShaderMaterialFactory: preset '%s' has no shader_id" % preset_id)
		return null
	var mat := create_from_shader(shader_id)
	if mat == null:
		return null
	var params: Dictionary = resolved.get("params", {})
	apply_params(mat, params, shader_id)
	if not overrides.is_empty():
		apply_params(mat, overrides, shader_id)
	return mat


static func apply_params(mat: ShaderMaterial, params: Dictionary, shader_id: String = "") -> void:
	if mat == null or params.is_empty():
		return
	var schema := _ShaderRegistry.get_shader_uniforms(shader_id) if not shader_id.is_empty() else {}
	for key in params:
		var uname := str(key)
		var val: Variant = params[key]
		if schema.has(uname):
			val = _ShaderPresetResolver.coerce_value_for_uniform(val, schema[uname])
		mat.set_shader_parameter(uname, val)


static func apply_dirt_palette(mat: ShaderMaterial, palette_id: String = "andean_default") -> void:
	if mat == null:
		return
	var palette := _ShaderPresetResolver.get_dirt_palette(palette_id)
	if palette.is_empty():
		return
	if palette.has("dirt_powder_color"):
		var c: Variant = _ShaderPresetResolver.coerce_value_to_type(palette["dirt_powder_color"], TYPE_COLOR)
		mat.set_shader_parameter("dirt_powder_color", c)
	if palette.has("dirt_mud_color"):
		var m: Variant = _ShaderPresetResolver.coerce_value_to_type(palette["dirt_mud_color"], TYPE_COLOR)
		mat.set_shader_parameter("dirt_mud_color", m)


static func apply_vehicle_base_contract(mat: ShaderMaterial, src: BaseMaterial3D) -> void:
	## Populates the unified vehicle albedo/normal/emission contract (`base_albedo_contract.gdshaderinc`).
	if mat == null or src == null:
		return
	mat.set_shader_parameter("albedo_color", src.albedo_color)
	mat.set_shader_parameter("use_texture", src.albedo_texture != null)
	if src.albedo_texture != null:
		mat.set_shader_parameter("albedo_tex", src.albedo_texture)
	if src is StandardMaterial3D:
		var std := src as StandardMaterial3D
		mat.set_shader_parameter("use_vertex_color", std.vertex_color_use_as_albedo)
		mat.set_shader_parameter("use_normal", std.normal_enabled and std.normal_texture != null)
		if std.normal_enabled and std.normal_texture != null:
			mat.set_shader_parameter("normal_texture", std.normal_texture)
			mat.set_shader_parameter("normal_strength", std.normal_scale)
		mat.set_shader_parameter("uv_scale", Vector2(std.uv1_scale.x, std.uv1_scale.y))
		mat.set_shader_parameter("uv_offset", Vector2(std.uv1_offset.x, std.uv1_offset.y))
	if src.emission_enabled:
		mat.set_shader_parameter("emission_color", src.emission)
		mat.set_shader_parameter("emission_energy", src.emission_energy_multiplier)
	if src.next_pass != null:
		mat.next_pass = src.next_pass
