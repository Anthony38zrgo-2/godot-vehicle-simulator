shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D track_texture : filter_linear;

uniform float track_time = 0.0;
varying vec4 track_state;

void vertex() {
	track_state = INSTANCE_CUSTOM;
}

void fragment() {
	vec4 pattern = texture(track_texture, UV);
	// Preserve the hue of the terrain already in the framebuffer.
	float age_fade = 1.0 - clamp((track_time - track_state.b) / max(track_state.a, 0.01), 0.0, 1.0);
	float opacity = mix(track_state.r, track_state.g, UV.y) * age_fade;
	float shade = mix(1.0, COLOR.r, pattern.a * opacity);
	ALBEDO = vec3(shade);
	ALPHA = 1.0;
}
