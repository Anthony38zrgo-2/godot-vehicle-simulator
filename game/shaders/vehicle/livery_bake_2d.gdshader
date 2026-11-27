shader_type canvas_item;

// One-shot offscreen GPU baker for stylized PSX liveries.

uniform sampler2D orig_tex : filter_nearest, repeat_enable;
uniform sampler2D livery_data_map : filter_nearest, repeat_enable;
uniform bool use_livery_data_map = true;
uniform vec3 livery_color_srgb = vec3(1.0);
uniform vec3 livery_shadow_tint_srgb = vec3(0.17, 0.055, 0.21);
uniform float livery_shadow_tint_strength = 0.40;
uniform float livery_ao_strength = 0.52;
uniform vec2 livery_dir_from = vec2(-0.50, 0.88);
uniform vec2 livery_dir_to = vec2(0.64, 1.0);
uniform float livery_shadow_gamma = 1.08;
uniform float livery_saturation = 1.04;
uniform float livery_dither_base = 0.0;
uniform float livery_dither_shadow_boost = 0.86;
uniform vec2 livery_shadow_band = vec2(0.56, 0.96);
uniform float livery_dither_dark_floor = 0.45;
uniform vec2 livery_effective_res = vec2(512.0, 512.0);
uniform float livery_mask_threshold = 0.30;
uniform bool livery_paint_rgb555 = true;
uniform float livery_dither_cell_scale = 1.0;

#include "res://shaders/lib/math/hash_noise.gdshaderinc"
#include "res://shaders/lib/retro/dither_quantize_fn.gdshaderinc"

void fragment() {
	vec4 lm = use_livery_data_map
		? texture(livery_data_map, UV)
		: vec4(1.0, 0.85, 0.85, 1.0);
	if (lm.r < livery_mask_threshold) {
		COLOR = texture(orig_tex, UV);
	} else {
		float ao = clamp(lm.g, 0.0, 1.0);
		float ao_factor = (1.0 - livery_ao_strength) + livery_ao_strength * ao;
		float dot_nl = clamp(lm.b, 0.0, 1.0) * 2.0 - 1.0;
		float t_dir = clamp((dot_nl - livery_dir_from.x) / max(livery_dir_from.y - livery_dir_from.x, 0.0001), 0.0, 1.0);
		float dir_factor = mix(livery_dir_to.x, livery_dir_to.y, t_dir);
		float light_val = pow(clamp(ao_factor * dir_factor, 0.0, 1.0), livery_shadow_gamma);

		vec3 base_srgb = livery_color_srgb * (255.0 * lm.a);
		vec3 lit_srgb = base_srgb * light_val;
		float darkness = clamp(1.0 - light_val, 0.0, 1.0);
		float tint_w = clamp(darkness * livery_shadow_tint_strength, 0.0, 0.85);
		lit_srgb = mix(lit_srgb, livery_shadow_tint_srgb * 255.0, tint_w);

		float luma_srgb = luma_bt601(lit_srgb);
		lit_srgb = vec3(luma_srgb) + (lit_srgb - vec3(luma_srgb)) * livery_saturation;

		float pen_t = clamp((livery_shadow_band.y - light_val) / max(livery_shadow_band.y - livery_shadow_band.x, 0.0001), 0.0, 1.0);
		float ramp_in = smoothstep(0.0, 0.30, pen_t);
		float settle = 1.0 - (1.0 - livery_dither_dark_floor) * smoothstep(0.75, 1.0, pen_t);
		float dither_str = livery_dither_base + livery_dither_shadow_boost * (ramp_in * settle);

		ivec2 cell = ivec2(floor(UV * livery_effective_res / livery_dither_cell_scale));
		vec3 srgb_out = psx_quantize_srgb255_rgb555(lit_srgb, cell, dither_str, livery_paint_rgb555);
		COLOR = vec4(srgb_out, 1.0);
	}
}
