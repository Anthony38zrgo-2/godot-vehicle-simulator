uniform bool procedural_surface_enabled = false;
uniform sampler2D surface_field_tex : filter_linear, repeat_disable;
uniform vec2 surface_station_range_m = vec2(0.0, 1.0);
uniform float surface_field_width = 2.0;
uniform float surface_max_encode_mm = 3.5;
uniform vec3 surface_full_mm = vec3(3.0, 3.5, 1.8);
uniform vec4 surface_seed_offsets = vec4(0.0, 0.0, 17.3, 9.7);

float proc_hash2_01(vec2 icell, vec2 seed_offset) {
	vec2 wrapped = vec2(mod(icell.x, 2048.0), mod(icell.y, 512.0)) + seed_offset;
	return fract(sin(dot(wrapped, vec2(127.1, 311.7))) * 43758.5453);
}

float proc_value_noise2(vec2 p, vec2 seed_offset) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = proc_hash2_01(i, seed_offset);
	float b = proc_hash2_01(i + vec2(1.0, 0.0), seed_offset);
	float c = proc_hash2_01(i + vec2(0.0, 1.0), seed_offset);
	float d = proc_hash2_01(i + vec2(1.0, 1.0), seed_offset);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float proc_spatial_patch_field(float station_m, float lateral_t, vec2 seed_offset) {
	float n1 = proc_value_noise2(vec2(station_m * 0.045, lateral_t * 1.8), seed_offset);
	float n2 = proc_value_noise2(vec2(station_m * 0.16, lateral_t * 4.5), seed_offset + vec2(19.7, 7.3));
	return clamp(0.65 * n1 + 0.35 * n2, 0.0, 1.0);
}

float proc_local_pattern_coverage(
	float mean_mm,
	float full_mm,
	float min_visible_mm,
	float station_m,
	float lateral_t,
	vec2 seed_offset,
	float edge_bias
) {
	if (mean_mm <= min_visible_mm) {
		return 0.0;
	}
	float base_cov = smoothstep(min_visible_mm, full_mm, mean_mm);
	float patch = proc_spatial_patch_field(station_m, lateral_t, seed_offset);
	float abs_t = clamp(abs(lateral_t), 0.0, 1.0);
	float rut_d = (abs_t - 0.42) / 0.22;
	float wheel_rut = exp(-(rut_d * rut_d));
	float shoulder = smoothstep(0.55, 1.0, abs_t);
	float bias = (shoulder * 0.22 - wheel_rut * 0.16) * edge_bias;
	float modulated = clamp(
		base_cov + (patch - 0.5) * 0.45 * (1.0 - abs(base_cov - 0.5) * 1.4) + bias,
		0.0,
		1.0
	);
	return mix(modulated, base_cov, clamp(base_cov * base_cov, 0.0, 0.75));
}

// Returns vec3(water_cov, snow_cov, ice_cov) for a carriageway coordinate.
vec3 proc_sample_surface(float station_m, float uv_x) {
	float signed_lateral = (clamp(uv_x, 0.0, 1.0) - 0.5) * 2.0;
	float span_m = max(surface_station_range_m.y - surface_station_range_m.x, 1.0);
	float norm_u = clamp((station_m - surface_station_range_m.x) / span_m, 0.0, 1.0);
	float nw = max(surface_field_width, 2.0);
	float tex_u = (norm_u * (nw - 1.0) + 0.5) / nw;
	vec3 field_mm = texture(surface_field_tex, vec2(tex_u, 0.5)).rgb * surface_max_encode_mm;
	float water_cov = field_mm.r > 0.01 ? smoothstep(0.01, surface_full_mm.x, field_mm.r) : 0.0;
	float snow_cov = proc_local_pattern_coverage(
		field_mm.g, surface_full_mm.y, 0.03, station_m, signed_lateral, surface_seed_offsets.xy, 1.0
	);
	float ice_cov = proc_local_pattern_coverage(
		field_mm.b, surface_full_mm.z, 0.02, station_m, signed_lateral, surface_seed_offsets.zw, 0.85
	);
	return vec3(water_cov, snow_cov, ice_cov);
}
