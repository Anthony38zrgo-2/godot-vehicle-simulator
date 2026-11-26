shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

// Gran Turismo 2 (PS1) inspired vehicle shader:
// - Crisp nearest-mipmap RGB555 albedo (preserving baked AO/livery atlases)
// - Per-vertex sphere-mapped environment reflection streaks scrolling across hood, roof, doors, and glass
// - Smooth Gouraud-like wrap-Lambert + crisp solar clearcoat highlight
// - Subtle PS1 RGB555 + 4x4 ordered dithering on reflection streaks

uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_pixel_albedo = false;
uniform sampler2D pixel_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
uniform bool use_vertex_color = false;
uniform float normal_strength = 1.0;
uniform bool use_alpha_cutout = false;
uniform float alpha_cutoff = 0.5;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);

// GT2 sliding environment reflection streaks
uniform sampler2D env_map : source_color, hint_default_black, filter_linear, repeat_enable;
uniform float env_strength : hint_range(0.0, 1.5) = 0.34;
uniform float env_fresnel_base : hint_range(0.0, 1.0) = 0.42;
uniform float env_contrast : hint_range(0.5, 2.5) = 1.35;
uniform float spec_strength : hint_range(0.0, 1.5) = 0.35;
uniform float spec_shininess : hint_range(4.0, 64.0) = 26.0;
uniform vec3 shade_tint : source_color = vec3(0.66, 0.70, 0.80);

// Subtle PS1 RGB555 + 4x4 dither on the additive reflection pass
uniform bool psx_dither_env = true;
uniform float psx_dither_strength : hint_range(0.0, 1.0) = 0.30;

// PSX vehicle-only geometry imprecision (vertex snapping) & affine texture wobble
uniform vec2 psx_snap_resolution = vec2(320.0, 240.0);
uniform float psx_snap_strength : hint_range(0.0, 1.0) = 0.0;
uniform float psx_affine_strength : hint_range(0.0, 1.0) = 0.0;

varying vec2 v_env_uv;
varying float v_fresnel;
varying float v_sky_facing;
varying vec2 v_affine_uv;
varying float v_affine_w;
varying float v_psx_affine;

const float PS1_DITHER_4X4[16] = float[16](
	-4.0,  0.0, -3.0,  1.0,
	 2.0, -2.0,  3.0, -1.0,
	-3.0,  1.0, -4.0,  0.0,
	 3.0, -1.0,  2.0, -2.0
);

vec3 psx_quantize_rgb555(vec3 linear_rgb, vec2 frag_xy) {
	vec3 srgb = pow(clamp(linear_rgb, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2)) * 255.0;
	if (psx_dither_strength > 0.0) {
		ivec2 cell = ivec2(frag_xy);
		float pattern = PS1_DITHER_4X4[(cell.y & 3) * 4 + (cell.x & 3)];
		srgb += vec3(pattern * psx_dither_strength);
	}
	ivec3 q = ivec3(clamp(srgb, vec3(0.0), vec3(255.0))) >> 3;
	ivec3 rep = (q << 3) | (q >> 2);
	return pow(clamp(vec3(rep) / 255.0, vec3(0.0), vec3(1.0)), vec3(2.2));
}

#include "res://scripts/rally/rally_dirt.gdshaderinc"

void vertex() {
	dirt_position = dirt_local_position(VERTEX);
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float psx_dist_fade = smoothstep(0.25, 1.25, clip.w);
	if (psx_snap_strength > 0.001) {
		float eff_snap = psx_snap_strength * psx_dist_fade;
		vec2 ndc = clip.xy / max(abs(clip.w), 0.0001);
		vec2 grid = max(psx_snap_resolution, vec2(32.0)) * 0.5;
		vec2 snapped = floor(ndc * grid + 0.5) / grid;
		clip.xy = mix(ndc, snapped, eff_snap) * clip.w;
	}
	POSITION = clip;

	vec2 base_uv = UV * uv_scale + uv_offset;
	float w_eff = max(clip.w, 0.15);
	v_affine_uv = base_uv * w_eff;
	v_affine_w = w_eff;
	v_psx_affine = psx_affine_strength * psx_dist_fade;

	vec3 pos_view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n_view = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec3 v_view = normalize(-pos_view);
	vec3 n_world = normalize(MODEL_NORMAL_MATRIX * NORMAL);

	// Per-vertex sphere-map reflection UVs (creates GT2's signature low-poly sliding highlight bands)
	vec3 r_view = reflect(-v_view, n_view);
	float m = 2.0 * sqrt(r_view.x * r_view.x + r_view.y * r_view.y + (r_view.z + 1.0) * (r_view.z + 1.0));
	vec2 sphere_uv = r_view.xy / max(m, 0.001) + 0.5;
	// Pan reflection bands smoothly as the camera/vehicle turns around world Y
	float cam_yaw = atan(INV_VIEW_MATRIX[2].x, INV_VIEW_MATRIX[2].z);
	v_env_uv = vec2(sphere_uv.x + cam_yaw * 0.16, clamp(1.0 - sphere_uv.y, 0.02, 0.98));

	float ndotv = max(dot(n_view, v_view), 0.0);
	v_fresnel = mix(env_fresnel_base, 1.0, pow(1.0 - ndotv, 1.85));
	// Suppress reflection under chassis/skirts while keeping hood, roof, glass, and side doors glossy
	v_sky_facing = smoothstep(-0.35, 0.30, n_world.y);
}

varying float dirt_specular;

void fragment() {
	vec2 persp_uv = UV * uv_scale + uv_offset;
	vec2 tex_uv = persp_uv;
	if (v_psx_affine > 0.001) {
		vec2 affine_uv = v_affine_uv / max(v_affine_w, 0.0001);
		tex_uv = mix(persp_uv, affine_uv, v_psx_affine);
	}
	vec4 paint = base_color * (use_pixel_albedo ? texture(pixel_albedo, tex_uv) : texture(base_texture, tex_uv));
	if (use_vertex_color) {
		paint *= COLOR;
	}
	if (use_alpha_cutout && paint.a < alpha_cutoff) {
		discard;
	}

	if (use_normal) {
		NORMAL_MAP = texture(normal_texture, tex_uv).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}

	// Sample GT2 reflection streak map (high-contrast sky/cloud bands over dark horizon)
	vec3 env_sample = texture(env_map, v_env_uv).rgb;
	vec3 env_streak = pow(max(env_sample, vec3(0.0)), vec3(env_contrast));
	// Gently protect deep black rubber/gaps on single-atlas cars while letting dark glass shine
	float luma = dot(paint.rgb, vec3(0.2126, 0.7152, 0.0722));
	float mask = smoothstep(0.015, 0.09, luma);
	vec3 refl_add = env_streak * (env_strength * v_fresnel * v_sky_facing * mask);
	if (psx_dither_env && env_strength > 0.001) {
		refl_add = psx_quantize_rgb555(refl_add, FRAGCOORD.xy);
	}

	vec4 dirt = dirt_sample();
	ALBEDO = mix(paint.rgb, psx_quantize_rgb555(dirt.rgb, FRAGCOORD.xy), dirt.a);
	EMISSION = refl_add * (1.0 - dirt.a);
	dirt_specular = 1.0 - dirt.a;
}

void light() {
	// Smooth Gouraud-style wrap-Lambert diffuse (no hard 2-band cel cut)
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp(ndl * 0.62 + 0.38, 0.0, 1.0);
	vec3 diffuse_tint = mix(shade_tint, vec3(1.0), wrap);
	float diffuse = mix(0.28, 0.96, wrap);
	float reach = ATTENUATION;
	DIFFUSE_LIGHT += diffuse_tint * diffuse * reach * LIGHT_COLOR / PI;

	// Crisp GT2 solar clearcoat highlight
	if (spec_strength > 0.001 && ndl > 0.0) {
		vec3 half_vec = normalize(LIGHT + VIEW);
		float spec = pow(max(dot(NORMAL, half_vec), 0.0), spec_shininess) * spec_strength * dirt_specular;
		SPECULAR_LIGHT += spec * reach * LIGHT_COLOR;
	}
}
