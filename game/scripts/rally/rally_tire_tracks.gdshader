shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D track_texture : filter_linear;

void fragment() {
	vec4 pattern = texture(track_texture, UV);
	ALBEDO = mix(vec3(1.0), pattern.rgb * COLOR.rgb, pattern.a * COLOR.a);
	ALPHA = 1.0;
}
