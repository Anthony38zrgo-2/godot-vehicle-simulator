shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, particle_trails;

uniform float opacity = 0.4;
uniform float near_start_m = 1.0;
uniform float near_end_m = 4.0;
varying float camera_distance;

void vertex() {
	camera_distance = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	ALBEDO = vec3(0.8, 0.84, 0.88);
	ALPHA = opacity * smoothstep(near_start_m, near_end_m, camera_distance);
}
