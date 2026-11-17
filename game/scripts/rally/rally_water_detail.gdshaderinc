uniform sampler2D water_detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 0.30;
uniform float detail_strength = 0.72;
uniform float detail_normal_strength = 0.0;
uniform float detail_speed = 0.035;

float water_detail_lum(vec2 p) {
	vec3 c = texture(water_detail_tex, p).rgb;
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Two overlapping scrolling layers (Dreamcast multi-layer UV scroll style),
// keeping normals smooth (yz = 0) to avoid modern per-pixel specular noise.
vec3 water_detail_sample(vec2 world_xz, vec2 flow) {
	vec2 uv_a = world_xz * detail_scale + flow;
	vec2 uv_b = world_xz * (detail_scale * 1.45) + vec2(0.37, 0.61) - flow * 0.55;
	float a = water_detail_lum(uv_a);
	float b = water_detail_lum(uv_b);
	float lum = mix(a, b, 0.45);
	return vec3(lum, 0.0, 0.0);
}

vec3 water_detail_rgb(vec2 world_xz, vec2 flow) {
	vec2 uv_a = world_xz * detail_scale + flow;
	vec2 uv_b = world_xz * (detail_scale * 1.45) + vec2(0.37, 0.61) - flow * 0.55;
	return mix(texture(water_detail_tex, uv_a).rgb, texture(water_detail_tex, uv_b).rgb, 0.45);
}
