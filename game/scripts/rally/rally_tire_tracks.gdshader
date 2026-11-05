shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D track_texture : filter_linear;

void fragment() {
	vec4 pattern = texture(track_texture, UV);
	// Preserve the hue of the terrain already in the framebuffer.
	float shade = mix(1.0, COLOR.r, pattern.a * COLOR.a);
	ALBEDO = vec3(shade);
	ALPHA = 1.0;
}
