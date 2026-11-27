shader_type spatial;
render_mode vertex_lighting, cull_back, diffuse_lambert, specular_disabled;

// Dreamcast (PowerVR2) vehicle shader sharing the unified vehicle LSP contract.

uniform float roughness_value : hint_range(0.0, 1.0) = 0.40;
uniform float specular_value : hint_range(0.0, 1.0) = 0.0;
uniform bool rgb565 = true;
uniform float dither_amount : hint_range(0.0, 1.0) = 0.30;

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
	vec4 c = sample_vehicle_albedo(tex_uv, COLOR);
	vec4 dirt = dirt_sample();
	vec3 albedo = mix(c.rgb, dirt.rgb, dirt.a);
	vec3 total_emission = emission_color * emission_energy * (1.0 - dirt.a);

	if (rgb565) {
		albedo = dc_quantize_rgb565(albedo, FRAGCOORD.xy, dither_amount);
		total_emission = dc_quantize_rgb565(total_emission, FRAGCOORD.xy, dither_amount);
	}

	ALBEDO = albedo;
	EMISSION = total_emission;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
}
