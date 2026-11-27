shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

// Far regional DEM terrain with procedural strata, gullies, triplanar rocky crags,
// PS1 vertex snapping, affine texture wobble, vertex Gouraud mix, and RGB555 dithering.

#include "res://shaders/lib/math/hash_noise.gdshaderinc"
#include "res://shaders/lib/math/coordinates.gdshaderinc"
#include "res://shaders/lib/surface/terrain_palette_gis.gdshaderinc"
#include "res://shaders/lib/surface/snow_accumulation.gdshaderinc"
#include "res://shaders/lib/retro/dither_quantize_fn.gdshaderinc"
#include "res://shaders/lib/retro/psx_quantize_uniforms.gdshaderinc"
#include "res://shaders/lib/retro/psx_projection.gdshaderinc"
#include "res://shaders/lib/atmosphere/global_env_uniforms.gdshaderinc"

group_uniforms regional_lighting;
uniform bool use_global_env = false;
uniform vec3 sun_dir = vec3(-0.52, 0.66, -0.54);
uniform vec3 sun_color = vec3(1.24, 1.17, 1.02);
uniform vec3 ambient_color = vec3(0.48, 0.54, 0.63);
uniform vec3 haze_color = vec3(0.68, 0.76, 0.86);
uniform float sun_gain = 0.88;
uniform float ambient_gain = 0.56;
uniform float haze_start = 450.0;
uniform float haze_end = 14000.0;
uniform float haze_max = 0.36;
uniform float color_saturation = 1.16;
uniform float psx_gouraud_mix : hint_range(0.0, 1.0) = 0.35;
group_uniforms;

varying vec3 world_point;
varying vec3 world_normal;
varying vec3 v_world_affine;
varying float v_affine_w;
varying float v_gouraud_ndl;
varying float v_gouraud_sky;

vec3 eff_sun_dir() {
	return use_global_env ? rally_sun_dir : sun_dir;
}

float strata_phase(vec3 p) {
	float warp_low = (value_noise2_sin(p.xz * 0.0052 + vec2(13.0, 37.0)) - 0.5) * 2.6;
	float warp_mid = (value_noise2_sin(p.xz * 0.015 + vec2(p.y * 0.009, -p.y * 0.007)) - 0.5) * 0.95;
	return dot(p, vec3(0.018, 0.026, -0.016)) + warp_low + warp_mid;
}

float geological_strata(vec3 p) {
	float phase = strata_phase(p);
	float fw = max(fwidth(phase), 0.001);
	float b1 = sin(phase * 6.283185) * (1.0 - smoothstep(0.14, 0.42, fw));
	float b2 = sin((phase * 1.83 + 0.5) * 6.283185) * (1.0 - smoothstep(0.14, 0.42, fw * 1.83));
	return b1 * 0.64 + b2 * 0.36;
}

float gully_field(vec2 pw, float py, vec2 slope_dir, float fp) {
	float across = dot(pw, vec2(-slope_dir.y, slope_dir.x));
	float along = dot(pw, slope_dir);
	return ridge_aa(vec2(across * 1.15, along * 0.32 + py * 0.48), 0.025, fp);
}

vec2 warped_xz(vec3 p) {
	return p.xz + vec2(
		value_noise2_sin(p.xz * 0.0068) - 0.5,
		value_noise2_sin(p.xz * 0.0068 + vec2(47.2, 19.6)) - 0.5
	) * 32.0;
}

float macro_height(vec3 p, float steep, float cliff, vec2 slope_dir, float fp) {
	vec2 pw = warped_xz(p);
	float crags = ridge_aa(pw, 0.013, fp) * 0.85 + ridge_aa(pw + vec2(17.0, 29.0), 0.038, fp) * 0.45;
	float gullies = gully_field(pw, p.y, slope_dir, fp);
	float step_ = sin(strata_phase(p) * 6.283185) * noise_octave_weight(0.028, fp);
	return crags * (0.52 + 0.72 * cliff) + gullies * (0.58 * steep) + step_ * (0.16 * cliff);
}

float triplanar_luma(vec3 p, vec3 n, float scale, float layer) {
	vec3 w = triplanar_weights(n);
	vec2 warp = terrain_warp(p.xz * 0.045) * 0.38;
	vec3 c = palette_layer(p.zy / scale + warp, layer) * w.x
		+ palette_layer(p.xz / scale + warp, layer) * w.y
		+ palette_layer(p.xy / scale + warp, layer) * w.z;
	return luma_rec709(c);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = MODEL_NORMAL_MATRIX * NORMAL;
	world_point = wp;
	world_normal = wn;

	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = psx_snap_clip(clip, 1.0, psx_snap_strength);

	float w_eff = max(clip.w, 8.0);
	v_world_affine = wp * w_eff;
	v_affine_w = w_eff;

	vec3 n_v = length(wn) > 0.001 ? normalize(wn) : vec3(0.0, 1.0, 0.0);
	if (n_v.y < 0.0) {
		n_v = -n_v;
	}
	vec3 L = normalize(eff_sun_dir());
	v_gouraud_ndl = clamp(dot(n_v, L) * 0.72 + 0.28, 0.0, 1.0);
	v_gouraud_sky = 0.72 + 0.28 * n_v.y;
}

void fragment() {
	vec3 p = world_point;
	vec3 p_tex = p;
	if (psx_affine_strength > 0.001) {
		vec3 wp_affine = v_world_affine / max(v_affine_w, 0.001);
		vec3 affine_delta = clamp(wp_affine - p, vec3(-45.0), vec3(45.0));
		p_tex = p + affine_delta * psx_affine_strength;
	}
	vec4 gis = grass_coverage(p);
	vec3 base_normal = length(world_normal) > 0.001 ? normalize(world_normal) : normalize(cross(dFdx(p), dFdy(p)));
	if (base_normal.y < 0.0) {
		base_normal = -base_normal;
	}

	float dist = length(VERTEX);
	float xz_fp = max(max(length(dFdx(p.xz)), length(dFdy(p.xz))), 0.25);
	float detail_fade = 1.0 - smoothstep(1350.0, 6000.0, dist);
	float near_fade = 1.0 - smoothstep(400.0, 2300.0, dist);

	float grade = length(base_normal.xz) / max(base_normal.y, 0.05);
	float macro_break = fbm_aa(p_tex.xz, 0.009, xz_fp) - 0.5;
	float mid_break = fbm_aa(p_tex.xz, 0.032, xz_fp) - 0.5;
	float steep = smoothstep(0.19, 0.50, grade + macro_break * 0.15);
	float cliff = smoothstep(0.40, 0.74, grade + macro_break * 0.17 + mid_break * 0.07);
	vec2 slope_dir = normalize(base_normal.xz + vec2(0.0001));

	float eps = clamp(xz_fp * 1.7, 1.8, 9.5);
	float h0 = macro_height(p_tex, steep, cliff, slope_dir, xz_fp);
	float hx = macro_height(p_tex + vec3(eps, 0.0, 0.0), steep, cliff, slope_dir, xz_fp);
	float hy = macro_height(p_tex + vec3(0.0, eps, 0.0), steep, cliff, slope_dir, xz_fp);
	float hz = macro_height(p_tex + vec3(0.0, 0.0, eps), steep, cliff, slope_dir, xz_fp);
	vec3 grad = vec3(hx - h0, hy - h0, hz - h0) / eps;
	float bump = mix(0.75, 3.9, steep) * (1.0 + 0.42 * cliff) * detail_fade * (1.0 - psx_gouraud_mix * 0.55);
	vec3 n = normalize(base_normal - grad * bump);

	vec2 pw = warped_xz(p_tex);
	float crest = ridge_aa(pw, 0.016, xz_fp);
	float gully = gully_field(pw, p_tex.y, slope_dir, xz_fp);
	float t = COLOR.a + (crest - 0.5) * 0.38 + macro_break * 0.22 + mid_break * 0.10
		- smoothstep(0.55, 0.85, gully) * 0.16 * steep + gis.b * 0.12;
	float edge_w = 0.075 + clamp(xz_fp * 0.006, 0.0, 0.18);
	float rock_mask = smoothstep(0.50 - edge_w, 0.50 + edge_w, t);
	float scree_mask = smoothstep(0.30, 0.46, t) * (1.0 - rock_mask);

	float rock_luma = mix(
		triplanar_luma(p_tex, base_normal, 10.0, 17.0),
		mix(triplanar_luma(p_tex, base_normal, 45.0, 15.0), triplanar_luma(p_tex, base_normal, 13.0, 14.0), 0.55),
		cliff
	);
	float rock_detail = clamp(1.0 + (rock_luma - 0.35) * 0.82, 0.78, 1.22);
	float strata = geological_strata(p_tex);
	float cavity = clamp(0.84 + (h0 - 0.58) * 0.24, 0.74, 1.12);
	vec3 strata_tint = mix(vec3(0.95, 0.97, 1.02), vec3(1.07, 0.97, 0.92), strata * 0.5 + 0.5);
	vec3 rock_albedo = COLOR.rgb * mix(vec3(1.0), strata_tint * rock_detail * cavity * (1.0 + strata * 0.08 * cliff), detail_fade);

	vec3 grass_weights = mix(vec3(0.45, 0.12, 0.10), gis.rgb, gis.a);
	float patch_macro = fbm_aa(p_tex.xz, 0.026, xz_fp) * 0.70 + (mid_break + 0.5) * 0.30;
	vec3 grass_albedo = mix(grass_macro_color(grass_weights), ground_cover(p_tex, patch_macro), near_fade * 0.70 * gis.a);
	grass_albedo *= mix(0.90, 1.08, patch_macro);

	vec3 scree_albedo = mix(rock_albedo * vec3(1.08, 1.04, 1.00), grass_albedo * vec3(0.92, 0.86, 0.80), 0.45);
	vec3 albedo = mix(grass_albedo, scree_albedo, scree_mask * 0.85);
	albedo = mix(albedo, rock_albedo, rock_mask);
	float albedo_luma = luma_rec709(albedo);
	albedo = clamp(mix(vec3(albedo_luma), albedo, color_saturation), 0.0, 1.0);

	albedo = ticlio_winter_ground(albedo, p_tex, base_normal, dist, 0.0);

	vec3 active_sun_dir = eff_sun_dir();
	vec3 active_sun_col = use_global_env ? rally_sun_color : sun_color;
	vec3 active_amb_col = use_global_env ? rally_ambient_color : ambient_color;
	vec3 active_haze_col = use_global_env ? rally_haze_color : haze_color;

	vec3 L = normalize(active_sun_dir);
	vec3 shade_n = normalize(mix(base_normal, n, mix(0.35, 0.88, rock_mask)));
	float ndl = mix(clamp(dot(shade_n, L) * 0.72 + 0.28, 0.0, 1.0), v_gouraud_ndl, psx_gouraud_mix);
	float sky = mix(0.72 + 0.28 * shade_n.y, v_gouraud_sky, psx_gouraud_mix);
	float occl = mix(1.0, cavity, rock_mask * detail_fade);
	vec3 light = active_sun_col * (ndl * sun_gain) + active_amb_col * (sky * ambient_gain * occl);
	vec3 lit = albedo * light;

	float haze = smoothstep(haze_start, haze_end, dist) * haze_max;
	vec3 final_color = mix(lit, active_haze_col, haze);
	ALBEDO = psx_apply_color_quantize(final_color, FRAGCOORD.xy);
}
