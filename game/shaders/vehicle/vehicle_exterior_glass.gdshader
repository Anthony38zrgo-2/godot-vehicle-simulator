shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;

uniform sampler2D glass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool cracked = false;
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float car_speed_mps : hint_range(0.0, 80.0) = 0.0;
uniform float rain_scroll = 0.0;

#include "res://shaders/lib/math/hash_noise.gdshaderinc"
#include "res://shaders/lib/math/coordinates.gdshaderinc"
#include "res://shaders/lib/retro/psx_projection.gdshaderinc"
#include "res://shaders/lib/vehicle/glass_droplets.gdshaderinc"

varying vec3 v_local_pos;
varying vec3 v_local_normal;

void vertex() {
	v_local_pos = VERTEX;
	v_local_normal = NORMAL;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 psx_pack = psx_affine_pack(clip, UV, 0.9, 2.6);
	v_psx_uv_over_w = psx_pack.xy;
	v_psx_w = psx_pack.z;
	v_psx_affine_weight = psx_pack.w;
	POSITION = psx_snap_clip_range(clip, 0.9, 2.6);
}

void fragment() {
	vec2 glass_uv = psx_resolve_uv(UV);
	vec4 glass = texture(glass_texture, glass_uv);
	float is_frame = smoothstep(0.60, 0.80, glass.a);

	float grazing = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 3.0);
	vec3 tint = vec3(0.035, 0.046, 0.052);
	vec3 glass_albedo = tint + glass.rgb * (cracked ? 0.35 : 0.07) * glass.a;
	vec3 base_albedo = mix(glass_albedo, glass.rgb, is_frame);

	float coverage = 0.0;
	vec2 lens_normal = vec2(0.0);
	vec3 rim_glint = vec3(0.0);

	if (rain_intensity > 0.005 && is_frame < 0.98) {
		vec2 win_pos = (abs(v_local_normal.x) > 0.45)
			? vec2(v_local_pos.z, v_local_pos.y)
			: vec2(v_local_pos.x, v_local_pos.y * 0.61 + abs(v_local_pos.z) * 0.79);

		float speed_norm = clamp(car_speed_mps / 28.0, 0.0, 1.5);
		float total_scroll = rain_scroll * 14.0 + TIME * 0.45;

		vec3 p1 = ext_persistent_droplets(win_pos, 58.0, rain_intensity * 0.86, 0.9455, 0.3256, 1.0);
		vec3 s1 = ext_sliding_droplets(win_pos, 46.0, total_scroll, rain_intensity * 0.78, speed_norm, 0.9816, 0.1908, 3.0);

		lens_normal = (p1.xy + s1.xy * 0.90) * (1.0 - is_frame);
		coverage = clamp(max(p1.z, s1.z), 0.0, 1.0) * (1.0 - is_frame);

		float steepness = clamp(length(lens_normal), 0.0, 1.0);
		float rim_ring = smoothstep(0.40, 0.88, steepness);
		vec2 n_dir = lens_normal / max(steepness, 0.0001);
		float sky_catch = clamp(dot(n_dir, normalize(vec2(0.2, 0.98))), 0.0, 1.0);
		rim_glint = vec3(0.80, 0.90, 1.0) * pow(sky_catch, 5.0) * rim_ring * 0.12 * rain_intensity * (1.0 - is_frame);
	}

	ALBEDO = base_albedo * (1.0 - coverage * 0.05) + rim_glint;
	float glass_roughness = mix(0.28, 0.04, coverage * rain_intensity);
	ROUGHNESS = mix(glass_roughness, 0.35, is_frame);
	SPECULAR = mix(mix(0.5, 0.90, coverage * rain_intensity), 0.5, is_frame);
	NORMAL = normalize(NORMAL + vec3(lens_normal * 0.20 * rain_intensity, 0.0));
	float glass_alpha = mix(0.92, 0.98, grazing);
	ALPHA = mix(glass_alpha, 1.0, is_frame);
}
