shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

// Gran Turismo 2 (PS1) inspired vehicle shader:
// - Crisp nearest-mipmap RGB555 albedo (preserving baked AO/livery atlases)
// - Smooth Gouraud-like wrap-Lambert diffuse
// - Subtle PS1 RGB555 + 4x4 ordered dithering on dirt overlay

uniform bool use_alpha_cutout = false;
uniform float alpha_cutoff = 0.5;
uniform vec3 shade_tint : source_color = vec3(0.66, 0.70, 0.80);
uniform float psx_dither_strength : hint_range(0.0, 1.0) = 0.30;

#include "res://shaders/lib/retro/dither_quantize_fn.gdshaderinc"
#include "res://shaders/lib/retro/psx_projection.gdshaderinc"
#include "res://shaders/lib/surface/base_albedo_contract.gdshaderinc"
#include "res://shaders/lib/vehicle/dirt_overlay.gdshaderinc"

void vertex() {
	dirt_position = dirt_local_position(VERTEX);
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 base_uv = UV * uv_scale + uv_offset;
	vec4 psx_pack = psx_affine_pack(clip, base_uv, 0.25, 1.25);
	v_psx_uv_over_w = psx_pack.xy;
	v_psx_w = psx_pack.z;
	v_psx_affine_weight = psx_pack.w;
	POSITION = psx_snap_clip_range(clip, 0.25, 1.25);
}

void fragment() {
	vec2 tex_uv = psx_resolve_uv(UV * uv_scale + uv_offset);
	vec4 paint = sample_vehicle_albedo(tex_uv, COLOR);
	if (use_alpha_cutout && paint.a < alpha_cutoff) {
		discard;
	}
	if (use_normal) {
		NORMAL_MAP = texture(normal_texture, tex_uv).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	vec4 dirt = dirt_sample();
	vec3 q_dirt = psx_quantize_rgb_bits(dirt.rgb, FRAGCOORD.xy, 5, psx_dither_strength, 1.0);
	ALBEDO = mix(paint.rgb, q_dirt, dirt.a);
	EMISSION = emission_color * emission_energy * (1.0 - dirt.a);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp(ndl * 0.62 + 0.38, 0.0, 1.0);
	vec3 diffuse_tint = mix(shade_tint, vec3(1.0), wrap);
	float diffuse = mix(0.28, 0.96, wrap);
	DIFFUSE_LIGHT += diffuse_tint * diffuse * ATTENUATION * LIGHT_COLOR / PI;
}
