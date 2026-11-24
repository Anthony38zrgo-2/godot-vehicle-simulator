extends Node3D

@export var pixel_albedo := false
@export var gt2_vehicle_shading := false

const TOON := preload("res://scripts/rally/rally_toon_surface.gdshader")
const TOON_CUTOUT := preload("res://scripts/rally/rally_toon_cutout.gdshader")
const GT2_VEHICLE := preload("res://scripts/rally/rally_gt2_vehicle.gdshader")
const OUTLINE := preload("res://scripts/rally/soft_toon_outline.gdshader")
static var _paint_ramps: Dictionary[bool, ImageTexture] = {}
static var _gt2_env_texture: ImageTexture = null


static func _gt2_env_map() -> ImageTexture:
	if _gt2_env_texture != null:
		return _gt2_env_texture
	# 64x64 high-contrast GT2 reflection streak map (sky + cloud ribbons + dark horizon + ground).
	var w := 64
	var h := 64
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var v := float(y) / float(h - 1)
		for x in w:
			var u := float(x) / float(w)
			var wave1 := 0.5 + 0.5 * sin(u * TAU * 2.0 + 0.6)
			var wave2 := 0.5 + 0.5 * sin(u * TAU * 3.0 - 1.1)
			var wave3 := 0.5 + 0.5 * sin(u * TAU * 5.0 + 2.3)
			var col: Color
			if v < 0.46:
				# Upper hemisphere: bright blue-white sky with broken white GT2 specular streaks
				var sky_t := clampf(v / 0.46, 0.0, 1.0)
				col = Color(0.55, 0.72, 0.94).lerp(Color(0.88, 0.93, 0.99), sky_t)
				var band_a := exp(-pow((v - (0.14 + 0.04 * wave1)) / 0.055, 2.0)) * (0.45 + 0.55 * wave2)
				var band_b := exp(-pow((v - (0.31 + 0.035 * wave2)) / 0.045, 2.0)) * (0.35 + 0.65 * wave3)
				var horizon_glow := exp(-pow((v - 0.44) / 0.04, 2.0)) * 0.75
				var streak := clampf(band_a * 0.95 + band_b * 0.80 + horizon_glow, 0.0, 1.0)
				col = col.lerp(Color(1.0, 1.0, 1.0), streak)
			elif v < 0.57:
				# Sharp dark treeline / horizon contrast band
				var tree_h := 0.50 + 0.035 * wave2 + 0.02 * wave3
				var t := clampf((v - 0.46) / maxf(tree_h - 0.46, 0.01), 0.0, 1.0)
				col = Color(0.75, 0.80, 0.86).lerp(Color(0.07, 0.09, 0.12), t)
			else:
				# Lower hemisphere: dark asphalt bounce so lower panels stay rich
				var g_t := clampf((v - 0.57) / 0.43, 0.0, 1.0)
				col = Color(0.11, 0.11, 0.12).lerp(Color(0.04, 0.04, 0.05), g_t)
			# Quantize to RGB555 levels
			var r5 := int(clampf(col.r, 0.0, 1.0) * 31.0 + 0.5)
			var g5 := int(clampf(col.g, 0.0, 1.0) * 31.0 + 0.5)
			var b5 := int(clampf(col.b, 0.0, 1.0) * 31.0 + 0.5)
			img.set_pixel(x, y, Color8((r5 << 3) | (r5 >> 2), (g5 << 3) | (g5 >> 2), (b5 << 3) | (b5 >> 2)))
	_gt2_env_texture = ImageTexture.create_from_image(img)
	return _gt2_env_texture


static func make_gt2_vehicle_material(source: StandardMaterial3D, cutout: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GT2_VEHICLE
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
	material.set_shader_parameter("use_alpha_cutout", cutout)
	if cutout:
		material.set_shader_parameter("alpha_cutoff", source.alpha_scissor_threshold)
	material.set_shader_parameter("env_map", _gt2_env_map())

	var mat_name := source.resource_name.to_lower()
	var env_str := 0.42
	var spec_str := 0.42
	var fresnel_base := 0.45
	if mat_name.contains("glass") or mat_name.contains("window") or mat_name.contains("windshield") or mat_name.contains("cristal") or mat_name.contains("vidrio"):
		env_str = 0.72
		spec_str = 0.60
		fresnel_base = 0.58
	elif source.metallic > 0.45 or mat_name.contains("chrome") or mat_name.contains("metal") or mat_name.contains("rim"):
		env_str = 0.60
		spec_str = 0.55
		fresnel_base = 0.52
	elif mat_name.contains("matte") or mat_name.contains("plastic") or mat_name.contains("tire") or mat_name.contains("rubber") or mat_name.contains("goma") or mat_name.contains("interior") or source.roughness > 0.80:
		env_str = 0.08
		spec_str = 0.08
		fresnel_base = 0.22
	elif mat_name.contains("details"):
		env_str = 0.48
		spec_str = 0.45
		fresnel_base = 0.48
	material.set_shader_parameter("env_strength", env_str)
	material.set_shader_parameter("spec_strength", spec_str)
	material.set_shader_parameter("env_fresnel_base", fresnel_base)
	return material


static func _paint_ramp(is_rock: bool) -> ImageTexture:
	if not _paint_ramps.has(is_rock):
		var shade := Color("#695762") if is_rock else Color("#3f425a")
		var middle := Color("#ad9384") if is_rock else Color("#9d99ac")
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
	material.set_shader_parameter("edge_wobble", 0.10 if is_rock else 0.28)
	material.set_shader_parameter("wobble_scale", 2.4 if is_rock else 1.8)
	material.set_shader_parameter("wobble_anisotropy", Vector3.ONE if is_rock else Vector3(1.4, 3.0, 0.55))
	material.set_shader_parameter("wobble_in_world", is_rock)
	material.set_shader_parameter("use_ramp", not is_rock)
	material.set_shader_parameter("ramp", _paint_ramp(is_rock))
	material.set_shader_parameter("toon_blend", 1.0)
	material.set_shader_parameter("crisp_shadows", false)
	if not is_rock:
		var mat_name := source.resource_name.to_lower()
		var spec_str := 0.26
		var spec_thresh := 0.88
		if mat_name.contains("glass") or mat_name.contains("window") or mat_name.contains("windshield") or mat_name.contains("chrome") or mat_name.contains("metal") or source.metallic > 0.45:
			spec_str = 0.44
			spec_thresh = 0.85
		elif mat_name.contains("matte") or mat_name.contains("plastic") or mat_name.contains("tire") or mat_name.contains("rubber") or source.roughness > 0.80:
			spec_str = 0.05
			spec_thresh = 0.92
		material.set_shader_parameter("paint_spec_strength", spec_str)
		material.set_shader_parameter("paint_spec_threshold", spec_thresh)
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
			var cutout := source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			if not cutout and source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			if not converted.has(source):
				var surface_material := make_gt2_vehicle_material(source, cutout) if gt2_vehicle_shading else make_toon_material(source, false, cutout)
				if pixel_albedo and source.albedo_texture != null:
					surface_material.set_shader_parameter("use_pixel_albedo", true)
					surface_material.set_shader_parameter("pixel_albedo", source.albedo_texture)
				converted[source] = surface_material
			visual.set_surface_override_material(surface, converted[source])
