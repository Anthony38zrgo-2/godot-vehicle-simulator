extends Node3D

@export var pixel_albedo := false

const TOON := preload("res://scripts/rally/rally_toon_surface.gdshader")
const TOON_CUTOUT := preload("res://scripts/rally/rally_toon_cutout.gdshader")
const OUTLINE := preload("res://scripts/rally/soft_toon_outline.gdshader")
static var _paint_ramps: Dictionary[bool, ImageTexture] = {}


static func _paint_ramp(is_rock: bool) -> ImageTexture:
	if not _paint_ramps.has(is_rock):
		var shade := Color("#695762") if is_rock else Color("#55536b")
		var middle := Color("#ad9384") if is_rock else Color("#a6a1b2")
		var highlight := Color("#dcc8b1") if is_rock else Color("#f2e8d6")
		var pixels := Image.create_empty(16, 1, false, Image.FORMAT_RGB8)
		pixels.fill(shade)
		pixels.set_pixel(6, 0, shade.lerp(middle, 0.5))
		pixels.fill_rect(Rect2i(7, 0, 4, 1), middle)
		pixels.set_pixel(11, 0, middle.lerp(highlight, 0.5))
		pixels.fill_rect(Rect2i(12, 0, 4, 1), highlight)
		_paint_ramps[is_rock] = ImageTexture.create_from_image(pixels)
	return _paint_ramps[is_rock]


static func make_toon_material(source: StandardMaterial3D, is_rock: bool = false, cutout: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TOON_CUTOUT if cutout else TOON
	material.set_shader_parameter("base_color", source.albedo_color)
	if source.albedo_texture != null:
		material.set_shader_parameter("base_texture", source.albedo_texture)
	material.set_shader_parameter("use_vertex_color", source.vertex_color_use_as_albedo)
	if source.normal_enabled and source.normal_texture != null:
		material.set_shader_parameter("use_normal", true)
		material.set_shader_parameter("normal_texture", source.normal_texture)
		material.set_shader_parameter("normal_strength", source.normal_scale)
	material.set_shader_parameter("uv_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y))
	material.set_shader_parameter("uv_offset", Vector2(source.uv1_offset.x, source.uv1_offset.y))
	material.set_shader_parameter("rim_strength", 0.025 if is_rock else 0.12)
	material.set_shader_parameter("edge_wobble", 0.10 if is_rock else 0.4)
	material.set_shader_parameter("wobble_scale", 2.4 if is_rock else 1.8)
	material.set_shader_parameter("wobble_in_world", is_rock)
	material.set_shader_parameter("use_ramp", false)
	material.set_shader_parameter("ramp", _paint_ramp(is_rock))
	material.set_shader_parameter("crisp_shadows", false)
	if cutout:
		material.set_shader_parameter("alpha_cutoff", source.alpha_scissor_threshold)
	if is_rock:
		var outline := ShaderMaterial.new()
		outline.shader = OUTLINE
		outline.set_shader_parameter("outline_width", 8.0)
		outline.set_shader_parameter("outline_fade_start", 18.0)
		outline.set_shader_parameter("outline_fade_end", 48.0)
		material.next_pass = outline
	return material


func _ready() -> void:
	var meshes := find_children("*", "MeshInstance3D", true, false)
	var root_mesh := get_node(".") as MeshInstance3D
	if root_mesh != null:
		meshes.push_front(root_mesh)
	var converted := {}
	for visual: MeshInstance3D in meshes:
		if visual.mesh == null:
			continue
		for surface in visual.mesh.get_surface_count():
			var source := visual.get_active_material(surface) as StandardMaterial3D
			if source == null or source.emission_enabled \
					or source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				continue
			var cutout := visual.name == &"Shelby_GT350" \
				and source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			if not cutout and (source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
					or source.cull_mode != BaseMaterial3D.CULL_BACK):
				continue
			if not converted.has(source):
				var toon_material := make_toon_material(source, false, cutout)
				if pixel_albedo and source.albedo_texture != null:
					toon_material.set_shader_parameter("use_pixel_albedo", true)
					toon_material.set_shader_parameter("pixel_albedo", source.albedo_texture)
				converted[source] = toon_material
			visual.set_surface_override_material(surface, converted[source])
