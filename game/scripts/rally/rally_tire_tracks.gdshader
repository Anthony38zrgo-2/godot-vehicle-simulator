shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled;

uniform float track_time = 0.0;

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
	float opacity = COLOR.g * fade;
	float shade = 1.0 - (1.0 - COLOR.r) * opacity * edge * print_mask;
	shade += ridge * COLOR.a * opacity * 0.20 * (1.0 - smear * 0.5);
	ALBEDO = vec3(shade);
	ALPHA = 1.0;
}
