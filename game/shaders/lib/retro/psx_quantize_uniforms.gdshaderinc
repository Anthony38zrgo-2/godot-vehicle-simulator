// Uniform wrapper for retro color/alpha quantization & dithering.
// Depends on: lib/retro/dither_quantize_fn.gdshaderinc

group_uniforms psx_quantize;
uniform bool psx_quantize_enabled = true;
uniform int psx_color_bits : hint_range(2, 8) = 5;
uniform float psx_dither_strength : hint_range(0.0, 2.0) = 0.35;
uniform float psx_dither_scale : hint_range(1.0, 4.0) = 1.0;
uniform int psx_alpha_levels : hint_range(2, 16) = 4;
uniform float psx_alpha_dither_strength : hint_range(0.0, 2.0) = 0.90;
group_uniforms;

vec3 psx_apply_color_quantize(vec3 linear_rgb, vec2 frag_xy) {
	if (!psx_quantize_enabled) {
		return linear_rgb;
	}
	return psx_quantize_rgb_bits(linear_rgb, frag_xy, psx_color_bits, psx_dither_strength, psx_dither_scale);
}

float psx_apply_alpha_quantize(float alpha, vec2 frag_xy) {
	if (!psx_quantize_enabled) {
		return alpha;
	}
	return psx_quantize_scalar(alpha, frag_xy, psx_alpha_levels, psx_alpha_dither_strength, psx_dither_scale);
}
