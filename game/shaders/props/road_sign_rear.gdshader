shader_type spatial;

uniform sampler2D front_mask : source_color, filter_linear_mipmap;
uniform vec3 rear_albedo : source_color = vec3(0.37, 0.40, 0.42);
uniform float rear_roughness : hint_range(0.0, 1.0) = 0.82;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	ALBEDO = rear_albedo;
	ROUGHNESS = rear_roughness;
	ALPHA = texture(front_mask, vec2(1.0 - UV.x, UV.y)).a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
