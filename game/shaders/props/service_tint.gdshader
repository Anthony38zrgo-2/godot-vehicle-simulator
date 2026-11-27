shader_type spatial;

uniform sampler2D source_color_texture : source_color, filter_linear_mipmap;
uniform vec4 paint : source_color = vec4(0.9, 0.82, 0.65, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.7;

#include "res://shaders/lib/math/hash_noise.gdshaderinc"

void fragment() {
	vec3 original = texture(source_color_texture, UV).rgb;
	float brightness = luma_rec709(original);
	float painted = smoothstep(0.18, 0.65, brightness);
	ALBEDO = mix(vec3(brightness), paint.rgb * brightness, painted);
	ROUGHNESS = roughness_value;
}
