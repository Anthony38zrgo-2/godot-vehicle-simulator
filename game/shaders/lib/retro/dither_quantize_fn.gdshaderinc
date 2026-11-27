// Pure retro ordered dithering and bit-depth quantization functions (PS1 / PS2 / Dreamcast).
// Zero uniforms declared here so this file works identically in spatial and canvas_item shaders.

const float PS1_DITHER_4X4[16] = float[16](
	-4.0,  0.0, -3.0,  1.0,
	 2.0, -2.0,  3.0, -1.0,
	-3.0,  1.0, -4.0,  0.0,
	 3.0, -1.0,  2.0, -2.0
);

const float BAYER_4X4_NORM[16] = float[16](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0
);

float psx_dither_4x4_sample(vec2 frag_xy, float dither_scale) {
	ivec2 cell = ivec2(floor(frag_xy / max(dither_scale, 1.0)));
	return PS1_DITHER_4X4[(cell.y & 3) * 4 + (cell.x & 3)];
}

float ps2_bayer4x4_signed(vec2 screen_pos) {
	ivec2 p = ivec2(mod(screen_pos, 4.0));
	return (BAYER_4X4_NORM[p.y * 4 + p.x] / 16.0) - 0.5;
}

vec3 psx_quantize_rgb_bits_pattern(vec3 linear_rgb, float pattern, int color_bits, float dither_strength) {
	int bits = clamp(color_bits, 2, 8);
	int shift = 8 - bits;
	vec3 srgb = pow(clamp(linear_rgb, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2)) * 255.0;
	if (shift > 0 && dither_strength > 0.0) {
		float scale = dither_strength * float(1 << shift) / 8.0;
		srgb += vec3(pattern * scale);
	}
	ivec3 q = ivec3(clamp(srgb, vec3(0.0), vec3(255.0))) >> shift;
	vec3 out_srgb;
	if (bits >= 4) {
		ivec3 rep = (q << shift) | (q >> (bits - shift));
		out_srgb = vec3(rep) / 255.0;
	} else {
		float max_lvl = float((1 << bits) - 1);
		out_srgb = vec3(q) / max_lvl;
	}
	return pow(clamp(out_srgb, vec3(0.0), vec3(1.0)), vec3(2.2));
}

vec3 psx_quantize_rgb_bits(vec3 linear_rgb, vec2 frag_xy, int color_bits, float dither_strength, float dither_scale) {
	float pattern = psx_dither_4x4_sample(frag_xy, dither_scale);
	return psx_quantize_rgb_bits_pattern(linear_rgb, pattern, color_bits, dither_strength);
}

vec3 psx_quantize_srgb255_rgb555(vec3 srgb_255, ivec2 cell, float dither_strength, bool quantize_rgb555) {
	float d_pat = PS1_DITHER_4X4[(cell.y & 3) * 4 + (cell.x & 3)];
	vec3 dithered = clamp(srgb_255 + vec3(d_pat * max(dither_strength, 0.0)), vec3(0.0), vec3(255.0));
	ivec3 paint_color = ivec3(dithered);
	if (quantize_rgb555) {
		ivec3 q5 = paint_color >> 3;
		paint_color = (q5 << 3) | (q5 >> 2);
	}
	return clamp(vec3(paint_color) / 255.0, vec3(0.0), vec3(1.0));
}

float psx_quantize_scalar_pattern(float value, float pattern, int levels, float dither_strength) {
	float steps = float(max(levels - 1, 1));
	float d = (pattern / 8.0) * dither_strength / steps;
	return clamp(floor(clamp(value + d, 0.0, 1.0) * steps + 0.5) / steps, 0.0, 1.0);
}

float psx_quantize_scalar(float value, vec2 frag_xy, int levels, float dither_strength, float dither_scale) {
	float pattern = psx_dither_4x4_sample(frag_xy, dither_scale);
	return psx_quantize_scalar_pattern(value, pattern, levels, dither_strength);
}

vec3 dc_quantize_rgb565(vec3 linear_rgb, vec2 frag_xy, float p_dither_amount) {
	vec3 steps = vec3(31.0, 63.0, 31.0);
	float d = ps2_bayer4x4_signed(frag_xy) * p_dither_amount;
	return clamp(floor(linear_rgb * steps + 0.5 + d) / steps, vec3(0.0), vec3(1.0));
}
