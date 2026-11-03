shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Camera-facing sprite used by the weather adapter for the CMR4 rain and snow
// bitmaps. Distance fades prevent a near-plane quad from covering the screen
// and keep the precipitation layer readable without a second particle system.

uniform sampler2D particle_texture : source_color, filter_linear_mipmap;
uniform float opacity = 0.55;
uniform vec3 tint_color = vec3(1.0);
uniform float near_start_m = 0.9;
uniform float near_end_m = 3.6;
uniform float far_start_m = 22.0;
uniform float far_end_m = 38.0;
uniform float ambient_luma = 0.9;
varying float distance_fade;

void vertex() {
	mat4 billboard = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	billboard[0].xyz *= length(MODEL_MATRIX[0].xyz);
	billboard[1].xyz *= length(MODEL_MATRIX[1].xyz);
	billboard[2].xyz *= length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float distance_m = length((VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz);
	distance_fade = smoothstep(near_start_m, near_end_m, distance_m)
		* (1.0 - smoothstep(far_start_m, far_end_m, distance_m));
}

void fragment() {
	vec4 sample_color = texture(particle_texture, UV) * COLOR;
	ALBEDO = tint_color * clamp(ambient_luma, 0.35, 1.0);
	ALPHA = sample_color.a * opacity * distance_fade;
}
