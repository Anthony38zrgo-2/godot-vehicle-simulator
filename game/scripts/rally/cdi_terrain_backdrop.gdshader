shader_type spatial;
render_mode fog_disabled, specular_disabled;

#include "res://scripts/rally/cdi_terrain_layers.gdshaderinc"
#include "res://scripts/rally/cdi_ticlio_snow.gdshaderinc"

varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float patch = patch_noise(world_point.xz * 0.052) * 0.70
		+ patch_noise(world_point.xz * 0.82) * 0.30;
	ALBEDO = ground_cover(world_point, patch) * terrain_macro_tone(world_point.xz);
	vec3 n = normalize(cross(dFdx(world_point), dFdy(world_point)));
	float view_dist = length(VERTEX);
	ALBEDO = ticlio_winter_ground(ALBEDO, world_point, n, view_dist, 0.0);
	float haze = terrain_depth_haze(view_dist);
	ALBEDO = mix(ALBEDO, depth_haze_color, haze);
	EMISSION = depth_haze_color * (0.42 * haze);
	float horizontal_distance = distance(world_point.xz, CAMERA_POSITION_WORLD.xz);
	ALPHA = 1.0 - smoothstep(125.0, 340.0, horizontal_distance);
	ROUGHNESS = 0.95;
}
