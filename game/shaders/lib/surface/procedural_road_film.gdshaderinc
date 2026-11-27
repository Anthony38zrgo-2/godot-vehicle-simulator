// Procedural carriageway water/snow/loose-gravel/mud film optics.
// Depends on: lib/math/cpu_gpu_parity.gdshaderinc

group_uniforms procedural_surface;
uniform bool procedural_surface_enabled = false;
uniform sampler2D surface_field_tex : filter_linear, repeat_disable;
uniform vec2 surface_station_range_m = vec2(0.0, 1.0);
uniform float surface_field_width = 2.0;
uniform float surface_max_encode_mm = 3.5;
uniform vec3 surface_full_mm = vec3(3.0, 3.5, 1.8);
uniform vec4 surface_seed_offsets = vec4(0.0, 0.0, 17.3, 9.7);

uniform bool proc_has_sky = false;
uniform samplerCube proc_sky_a : source_color, filter_linear_mipmap;
uniform samplerCube proc_sky_b : source_color, filter_linear_mipmap;
uniform samplerCube proc_sky_c : source_color, filter_linear_mipmap;
uniform float proc_weather_mix = 0.0;
uniform float proc_daylight_mix = 1.0;
uniform float proc_twilight_yaw = 0.0;
uniform float proc_yaw_b = 0.0;
uniform vec3 proc_tint_a = vec3(1.0);
uniform vec3 proc_tint_b = vec3(1.0);
uniform vec3 proc_tint_c = vec3(1.0);
uniform vec3 proc_horizon_color : source_color = vec3(0.45, 0.50, 0.56);
uniform vec3 proc_sun_dir = vec3(0.0, 0.7, 0.7);
uniform vec3 proc_sun_color = vec3(1.0, 0.95, 0.85);
group_uniforms;

// Returns vec3(water_cov, snow_cov, 0.0) for a carriageway coordinate.
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
	return vec3(water_cov, snow_cov, 0.0);
}

// Returns vec2(loose_gravel_coverage, mud_factor) in [0, 1].
vec2 proc_sample_loose_gravel_and_mud(float station_m, float uv_x, float snow_cov) {
	float signed_lateral = (clamp(uv_x, 0.0, 1.0) - 0.5) * 2.0;
	float abs_t = clamp(abs(signed_lateral), 0.0, 1.0);
	if (abs_t < 0.68) {
		return vec2(0.0);
	}
	float snow_replace = smoothstep(0.02, 0.22, snow_cov);
	if (snow_replace >= 0.999) {
		return vec2(0.0);
	}

	float span_m = max(surface_station_range_m.y - surface_station_range_m.x, 1.0);
	float norm_u = clamp((station_m - surface_station_range_m.x) / span_m, 0.0, 1.0);
	float nw = max(surface_field_width, 2.0);
	float tex_u = (norm_u * (nw - 1.0) + 0.5) / nw;
	vec4 tex_rgba = texture(surface_field_tex, vec2(tex_u, 0.5));
	float road_water_mm = tex_rgba.r * surface_max_encode_mm;
	float saturation = clamp(tex_rgba.a, 0.0, 1.0);

	vec2 seed_offset = surface_seed_offsets.zw;
	vec2 side_off = signed_lateral >= 0.0 ? vec2(0.0, 0.0) : vec2(41.7, 29.3);
	vec2 s_off = seed_offset + side_off;

	float width_field = proc_spatial_patch_field(station_m, signed_lateral, seed_offset);
	float edge_jit1 = proc_value_noise2(vec2(station_m * 0.32, abs_t * 6.0), s_off + vec2(7.1, 13.9));
	float edge_jit2 = proc_value_noise2(vec2(station_m * 1.15, abs_t * 14.0), s_off + vec2(23.4, 41.8));
	float scallop = (edge_jit1 - 0.5) * 0.065 + (edge_jit2 - 0.5) * 0.032;
	float ribbon_width = clamp(0.21 + (width_field - 0.5) * 0.16 + scallop, 0.13, 0.30);

	float dist_from_edge = 1.0 - abs_t;
	float profile = 1.0 - smoothstep(ribbon_width * 0.28, ribbon_width, dist_from_edge);
	if (profile <= 0.001) {
		return vec2(0.0);
	}

	float snow_keep = clamp(1.0 - snow_replace, 0.0, 1.0);
	float loose_cov = clamp(profile * snow_keep, 0.0, 1.0);
	float wet_drive = clamp(road_water_mm / 0.55 + saturation * 0.45, 0.0, 1.0);
	float mud_raw = smoothstep(0.28, 0.78, wet_drive);
	float mud = clamp(loose_cov * mud_raw, 0.0, 1.0);
	return vec2(loose_cov, mud);
}

// Returns vec4(albedo_darken_mult, roughness, specular, subtle_horizon_sheen).
vec4 proc_wet_surface_optics(
	float water_cov,
	float dry_roughness,
	float min_wet_roughness,
	float max_darken,
	float micro_cavity,
	float wheel_track_mask,
	float ndotv
) {
	float w = clamp(water_cov, 0.0, 1.0);
	if (w <= 0.005) {
		return vec4(1.0, dry_roughness, 0.05, 0.0);
	}
	float local_w = clamp(w * (0.85 + 0.15 * wheel_track_mask), 0.0, 1.0);
	float darken = 1.0 - max_darken * local_w;
	float wet_rough = mix(dry_roughness, min_wet_roughness, local_w);
	float spec = mix(0.05, 0.28, local_w);
	float grazing = 1.0 - clamp(ndotv, 0.0, 1.0);
	float fresnel = grazing * grazing;
	float sheen = clamp(local_w * fresnel * 0.10, 0.0, 0.08);
	return vec4(darken, wet_rough, spec, sheen);
}

void proc_transverse_water_distribution(
	float station_m,
	float lateral_01,
	vec2 world_xz,
	vec3 world_normal,
	float base_water_cov,
	float track_weight,
	out float out_water_cov,
	out float out_track_mask,
	out float out_micro_cavity
) {
	out_micro_cavity = 0.5;
	out_track_mask = 1.0 - smoothstep(0.05, 0.16, abs(abs(lateral_01 - 0.5) - 0.24));
	if (base_water_cov <= 0.005) {
		out_water_cov = 0.0;
		return;
	}
	float patch_n = proc_value_noise2(world_xz * 0.14, vec2(17.3, 23.1));
	float patch_mult = mix(0.72, 1.18, patch_n) + out_track_mask * (track_weight * 0.35);
	out_water_cov = clamp(base_water_cov * patch_mult, 0.0, 1.0);
}
