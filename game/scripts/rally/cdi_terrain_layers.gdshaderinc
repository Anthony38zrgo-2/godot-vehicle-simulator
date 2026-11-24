uniform sampler2DArray terrain_palette : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_gis : filter_linear, repeat_disable;
uniform vec4 grass_gis_bounds;
uniform vec3 grass_dense_tone : source_color = vec3(0.6196, 0.5294, 0.3882);   // #9E8763
uniform vec3 grass_sparse_tone : source_color = vec3(0.7490, 0.6549, 0.4980);  // #BFA77F
uniform vec3 grass_olive_tone : source_color = vec3(0.4784, 0.4588, 0.3373);   // #7A7556
uniform vec3 grass_mineral_tone : source_color = vec3(0.5608, 0.4000, 0.3333); // #8F6655
uniform vec3 depth_haze_color : source_color = vec3(0.68, 0.76, 0.86);
uniform float depth_haze_start = 140.0;
uniform float depth_haze_end = 620.0;
uniform float depth_haze_max : hint_range(0.0, 0.85) = 0.0;

float terrain_depth_haze(float view_dist) {
	return smoothstep(depth_haze_start, depth_haze_end, view_dist) * depth_haze_max;
}

float hash_patch(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float patch_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 t = fract(p);
	t = t * t * (3.0 - 2.0 * t);
	return mix(mix(hash_patch(cell), hash_patch(cell + vec2(1, 0)), t.x),
		mix(hash_patch(cell + vec2(0, 1)), hash_patch(cell + vec2(1, 1)), t.x), t.y);
}

vec3 palette_layer(vec2 uv, float layer) {
	return texture(terrain_palette, vec3(uv, layer)).rgb;
}

vec3 palette_mix(vec2 uv, float first, float count, float mask) {
	float slot = clamp((mask - 0.17) / 0.66, 0.0, 1.0) * (count - 1.0);
	float lower = floor(slot);
	return mix(palette_layer(uv, first + lower), palette_layer(uv, first + min(lower + 1.0, count - 1.0)),
		smoothstep(0.15, 0.85, fract(slot)));
}

vec2 terrain_warp(vec2 point) {
	return vec2(patch_noise(point * 0.11 + vec2(43.0, 15.0)),
		patch_noise(point * 0.11 + vec2(11.0, 71.0))) - 0.5;
}

float terrain_macro_tone(vec2 point) {
	return mix(0.84, 1.12, patch_noise(point * 0.027 + vec2(41.0, 26.0)));
}

vec3 shoulder_cover(vec3 p) {
	float mask = patch_noise(p.xz * 0.17 + vec2(31.0, 8.0));
	return palette_mix(p.xz / 2.5 + terrain_warp(p.xz) * 0.46, 11.0, 2.0, mask);
}

vec4 grass_coverage(vec3 p) {
	vec2 uv = (p.xz - grass_gis_bounds.xy) / grass_gis_bounds.zw;
	vec2 edge = min(uv, 1.0 - uv) * grass_gis_bounds.zw;
	float coverage = smoothstep(0.0, 180.0, min(edge.x, edge.y));
	return vec4(texture(grass_gis, uv).rgb, coverage);
}

vec3 grass_macro_color(vec3 weights) {
	vec3 grass = mix(grass_dense_tone, grass_sparse_tone, weights.r);
	grass = mix(grass, grass_olive_tone, weights.g);
	return mix(grass, grass_mineral_tone, weights.b);
}

float grass_detail(vec3 sample_color, float reference) {
	float luma = dot(sample_color, vec3(0.2126, 0.7152, 0.0722));
	return clamp(1.0 + (luma - reference) * 2.05, 0.56, 1.44);
}

vec3 ground_cover(vec3 p, float patch) {
	vec2 tile = p.xz / 3.5 + terrain_warp(p.xz) * 0.72;
	vec2 macro_tile = p.xz / 14.0 + terrain_warp(p.xz * 0.25) * 0.85;
	float variant = patch_noise(p.xz * 0.13 + vec2(17.0, 3.0));
	vec4 gis = grass_coverage(p);
	vec3 fallback = vec3(smoothstep(0.24, 0.72, patch), 0.06, 0.18);
	vec3 weights = mix(fallback, gis.rgb, gis.a);
	weights.r = clamp(weights.r * 0.78 + (patch - 0.5) * 0.30, 0.0, 1.0);
	float dense = grass_detail(palette_mix(tile, 4.0, 3.0, variant), 0.34);
	float dry = grass_detail(palette_mix(tile, 7.0, 3.0, variant), 0.46);
	float olive = grass_detail(palette_layer(tile, 10.0), 0.18);
	float mineral = grass_detail(palette_mix(p.xz / 2.0 + terrain_warp(p.xz) * 0.64, 17.0, 2.0, variant), 0.20);
	float near_detail = mix(mix(mix(dense, dry, weights.r), olive, weights.g), mineral, weights.b);
	// Mid-distance macro grain keeps hillsides textured at 30-300 m instead of averaging to flat sand.
	float macro_grass = grass_detail(palette_layer(macro_tile, mix(5.0, 8.0, step(0.5, weights.r))), 0.38);
	float macro_rock = grass_detail(palette_layer(macro_tile * 1.15, 17.0), 0.20);
	float macro_detail = mix(macro_grass, macro_rock, clamp(weights.b * 0.75 + 0.20, 0.0, 1.0));
	float detail = clamp(near_detail * mix(1.0, macro_detail, 0.52), 0.52, 1.46);
	return grass_macro_color(weights) * detail;
}

vec3 zone_layers(float station) {
	float section = floor(station / 215.0);
	float local = station - section * 215.0;
	if (local < 10.0 && section > 0.0) {
		return vec3(section - 1.0, section, smoothstep(-10.0, 10.0, local));
	}
	return vec3(section, section + 1.0, smoothstep(205.0, 225.0, local));
}

vec3 zone_texture(vec2 uv, float first, float count, vec3 zone) {
	vec3 primary = palette_layer(uv, first + mod(zone.x, count));
	vec3 secondary = palette_layer(uv, first + mod(zone.y, count));
	return mix(primary, secondary, zone.z);
}

vec3 zone_shoulder(vec3 p, vec3 zone) {
	return zone_texture(p.xz / 2.5 + terrain_warp(p.xz) * 0.46, 11.0, 2.0, zone);
}

vec3 cut_rock(vec3 p, vec3 n, vec3 zone) {
	vec3 weights = pow(abs(n), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.001);
	return zone_texture(p.zy / 2.5 + terrain_warp(p.zy) * 0.75, 14.0, 3.0, zone) * weights.x
		+ zone_texture(p.xz / 2.5 + terrain_warp(p.xz) * 0.75, 14.0, 3.0, zone) * weights.y
		+ zone_texture(p.xy / 2.5 + terrain_warp(p.xy) * 0.75, 14.0, 3.0, zone) * weights.z;
}
