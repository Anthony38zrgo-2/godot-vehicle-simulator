shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, particle_trails;

uniform float opacity = 0.65;
uniform float near_start_m = 0.8;
uniform float near_end_m = 3.2;
uniform float far_start_m = 22.0;
uniform float far_end_m = 38.0;
uniform float ambient_luma = 0.90;
uniform vec3 tint_color = vec3(0.85, 0.90, 0.98);
varying float distance_fade;

void vertex() {
	float distance_m = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	distance_fade = smoothstep(near_start_m, near_end_m, distance_m) * (1.0 - smoothstep(far_start_m, far_end_m, distance_m));
}

void fragment() {
	// Cheap linear ribbon taper; distance fading is interpolated from vertices.
	float trail_profile = clamp(min(UV.y, 1.0 - UV.y) * 8.0, 0.0, 1.0);

	ALBEDO = tint_color * clamp(ambient_luma, 0.40, 1.0);
	ALPHA = opacity * trail_profile * distance_fade;
}
