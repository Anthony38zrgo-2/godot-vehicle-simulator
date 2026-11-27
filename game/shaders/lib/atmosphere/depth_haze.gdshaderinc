// Shared atmospheric depth haze helpers.

group_uniforms depth_haze;
uniform vec3 depth_haze_color : source_color = vec3(0.68, 0.76, 0.86);
uniform float depth_haze_start = 140.0;
uniform float depth_haze_end = 620.0;
uniform float depth_haze_max : hint_range(0.0, 0.85) = 0.0;
group_uniforms;

float depth_haze_factor(float view_dist) {
	return smoothstep(depth_haze_start, depth_haze_end, view_dist) * depth_haze_max;
}
