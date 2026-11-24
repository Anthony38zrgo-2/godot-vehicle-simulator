shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled;

uniform float track_time = 0.0;
uniform float track_opacity_scale : hint_range(0.0, 1.0) = 0.55;
uniform bool psx_enabled = true;
uniform int psx_shade_levels : hint_range(2, 16) = 4;
uniform float psx_dither_strength : hint_range(0.0, 2.0) = 1.05;
uniform float psx_dither_scale : hint_range(1.0, 4.0) = 2.0;

const float PS1_DITHER_4X4[16] = float[16](
	-4.0,  0.0, -3.0,  1.0,
	 2.0, -2.0,  3.0, -1.0,
	-3.0,  1.0, -4.0,  0.0,
	 3.0, -1.0,  2.0, -2.0
);

float psx_quantize_shade(float value, vec2 frag_xy) {
	ivec2 cell = ivec2(floor(frag_xy / max(psx_dither_scale, 1.0)));
	float pattern = PS1_DITHER_4X4[(cell.y & 3) * 4 + (cell.x & 3)];
	float steps = float(max(psx_shade_levels - 1, 1));
	float d = (pattern / 8.0) * psx_dither_strength / steps;
	return clamp(floor(clamp(value + d, 0.0, 1.0) * steps + 0.5) / steps, 0.0, 1.0);
}

float tread_blocks(vec2 uv) {
	float column = floor(uv.x * 5.0);
	float across = abs(fract(uv.x * 5.0) - 0.5);
	float row = uv.y + mod(column, 2.0) * 0.5 + abs(uv.x - 0.5) * 0.9;
	float along = abs(fract(row) - 0.5);
	float aa_x = min(fwidth(uv.x) * 5.0, 0.20);
	float aa_y = min(fwidth(uv.y), 0.20);
	float across_block = 1.0 - smoothstep(0.36 - aa_x, 0.37 + aa_x, across);
	float along_block = 1.0 - smoothstep(0.30 - aa_y, 0.31 + aa_y, along + across * 0.18);
	return across_block * along_block;
}

void fragment() {
	float life = abs(UV2.y);
	float age = track_time - UV2.x;
	float fade = 1.0 - smoothstep(life * 0.25, life, age);
	float edge = smoothstep(0.0, 0.10, UV.x) * (1.0 - smoothstep(0.90, 1.0, UV.x));
	float asphalt = step(UV2.y, 0.0);
	float grooves = smoothstep(0.04, 0.18, abs(fract(UV.x * 4.0) - 0.5));
	float blocks = mix(tread_blocks(UV), grooves, asphalt);
	float smear = COLOR.b;
	float print_mask = mix(blocks, 0.72, smear);
	float ridge = (1.0 - smoothstep(0.02, 0.095, min(UV.x, 1.0 - UV.x))) * edge;
	float opacity = COLOR.g * fade * track_opacity_scale;
	float shade = 1.0 - (1.0 - COLOR.r) * opacity * edge * print_mask;
	shade += ridge * COLOR.a * opacity * 0.20 * (1.0 - smear * 0.5);
	if (psx_enabled) {
		shade = psx_quantize_shade(shade, FRAGCOORD.xy);
	}
	ALBEDO = vec3(shade);
	ALPHA = 1.0;
}
