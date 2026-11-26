shader_type spatial;

uniform sampler2D front_mask : source_color, filter_linear_mipmap;

void fragment() {
	ALBEDO = vec3(0.37, 0.40, 0.42);
	ROUGHNESS = 0.82;
	ALPHA = texture(front_mask, vec2(1.0 - UV.x, UV.y)).a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
}
