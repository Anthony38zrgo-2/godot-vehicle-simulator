shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Simple low-poly matte PSX shader (64x64 Nearest + optional per-instance pastel tint)
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
instance uniform vec3 tint_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.94;

#include "res://scripts/rally/rally_object_psx_projection.gdshaderinc"

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float distance_weight = smoothstep(0.25, 1.25, clip.w);
	psx_object_w = max(clip.w, 0.15);
	psx_object_uv_over_plane = UV * psx_object_w;
	psx_object_affine = psx_affine_strength * distance_weight;
	POSITION = psx_object_snap(clip, distance_weight);
}

void fragment() {
	vec4 tex = texture(albedo_texture, psx_object_texture_uv(UV));
	ALBEDO = tex.rgb * tint_color;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
