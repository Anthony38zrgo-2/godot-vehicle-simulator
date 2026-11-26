#include "res://scripts/rally/rally_object_psx_projection.gdshaderinc"

uniform sampler2D texture_nearest : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform sampler2D texture_nearest_clamped : source_color, hint_default_white, filter_nearest_mipmap, repeat_disable;
uniform sampler2D texture_smooth : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D texture_smooth_clamped : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool nearest_filter = false;
uniform bool repeat_texture = true;
uniform bool use_texture = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool billboard_y = false;
uniform bool use_vertex_color = false;
uniform bool vertex_color_srgb = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float alpha_cutoff = 0.0;
uniform int cull_side = 0;
uniform float roughness_value = 1.0;
uniform float metallic_value = 0.0;
uniform float specular_value = 0.0;
uniform bool unshaded_surface = false;
uniform vec3 emission_tint : source_color = vec3(0.0);
uniform float emission_strength = 0.0;
uniform vec3 backlight_tint : source_color = vec3(0.0);

void vertex() {
	if (billboard_y) {
		MODELVIEW_MATRIX = psx_upright_billboard(MODEL_MATRIX, VIEW_MATRIX, MAIN_CAM_INV_VIEW_MATRIX[0].xyz);
		MODELVIEW_NORMAL_MATRIX = transpose(inverse(mat3(MODELVIEW_MATRIX)));
	}
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float distance_weight = smoothstep(0.25, 1.25, clip.w);
	psx_object_w = max(clip.w, 0.15);
	psx_object_uv_over_plane = UV * psx_object_w;
	psx_object_affine = psx_affine_strength * distance_weight;
	POSITION = psx_object_snap(clip, distance_weight);
}

void fragment() {
	if ((cull_side == 0 && !FRONT_FACING) || (cull_side == 1 && FRONT_FACING)) {
		discard;
	}
	vec4 color = tint;
	if (use_texture) {
		vec2 tex_uv = psx_object_texture_uv(UV) * uv_scale + uv_offset;
		if (nearest_filter) {
			color *= repeat_texture ? texture(texture_nearest, tex_uv) : texture(texture_nearest_clamped, tex_uv);
		} else {
			color *= repeat_texture ? texture(texture_smooth, tex_uv) : texture(texture_smooth_clamped, tex_uv);
		}
	}
	if (use_vertex_color) {
		color *= vec4(vertex_color_srgb ? pow(COLOR.rgb, vec3(2.2)) : COLOR.rgb, COLOR.a);
	}
	if (color.a < alpha_cutoff) {
		discard;
	}
	ALBEDO = unshaded_surface ? vec3(0.0) : color.rgb;
	EMISSION = emission_tint * emission_strength + (unshaded_surface ? color.rgb : vec3(0.0));
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = specular_value;
	BACKLIGHT = backlight_tint;
#ifdef PSX_OBJECT_BLEND_ALPHA
	ALPHA = color.a;
#endif
}
