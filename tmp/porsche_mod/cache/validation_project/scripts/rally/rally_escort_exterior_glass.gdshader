shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

uniform sampler2D glass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool cracked = false;

void fragment() {
	vec4 glass = texture(glass_texture, UV);
	float grazing = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 3.0);
	vec3 tint = vec3(0.035, 0.046, 0.052);
	ALBEDO = tint + glass.rgb * (cracked ? 0.20 : 0.07) * glass.a;
	ROUGHNESS = 0.28;
	ALPHA = mix(0.92, 0.98, grazing);
}
