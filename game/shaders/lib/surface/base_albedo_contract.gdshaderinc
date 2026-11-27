// Unified LSP contract for all vehicle surface shaders (Toon, GT2, Dreamcast).

group_uniforms surface;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_texture = true;
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_pixel_albedo = false;
uniform sampler2D pixel_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
uniform float normal_strength = 1.0;
uniform bool use_vertex_color = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy : hint_range(0.0, 5.0) = 0.0;
group_uniforms;

vec4 sample_vehicle_albedo(vec2 tex_uv, vec4 vertex_color) {
	vec4 texel = vec4(1.0);
	if (use_texture) {
		texel = use_pixel_albedo ? texture(pixel_albedo, tex_uv) : texture(albedo_tex, tex_uv);
	}
	vec4 paint = albedo_color * texel;
	if (use_vertex_color) {
		paint *= vertex_color;
	}
	return paint;
}
