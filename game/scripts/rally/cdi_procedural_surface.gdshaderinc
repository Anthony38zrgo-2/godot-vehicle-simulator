uniform bool procedural_surface_enabled = false;
uniform sampler2D surface_field_tex : filter_linear, repeat_disable;
uniform vec2 surface_station_range_m = vec2(0.0, 1.0);
uniform float surface_field_width = 2.0;
uniform float surface_max_encode_mm = 3.5;
uniform vec3 surface_full_mm = vec3(3.0, 3.5, 1.8);
uniform vec4 surface_seed_offsets = vec4(0.0, 0.0, 17.3, 9.7);

// Live tropospheric sky cubemap uniforms for real progressive wet-road reflections
// (works even when Environment.reflected_light_source == REFLECTION_SOURCE_DISABLED).
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
	vec2 side_off = lateral_t >= 0.0 ? vec2(0.0, 0.0) : vec2(41.7, 29.3);
	vec2 s_off = seed_offset + side_off;
	float n1 = proc_value_noise2(vec2(station_m * 0.019, 0.5), s_off);
	float n2 = proc_value_noise2(vec2(station_m * 0.078, 1.5), s_off + vec2(19.7, 7.3));
	float n3 = proc_value_noise2(vec2(station_m * 0.23, 2.7), s_off + vec2(53.1, 31.9));
	return clamp(0.48 * n1 + 0.34 * n2 + 0.18 * n3, 0.0, 1.0);
}

// Shared CPU/GPU Ticlio snow coverage in [0, 1].
// - Residual regime (mean_mm <= 1.8 mm): discontinuous thin lateral snow ribbons
//   strictly confined to the outer ~10-14% berms (|lateral_t| >= 0.85), leaving the
//   driving lane bare.
// - Sustained snowfall regime (mean_mm > 1.8 mm): berm drifts advance inward toward
//   the outer wheel tracks and snow accumulates along the central crown ridge between
//   the wheel tracks (|lateral_t| < 0.24), receding first from the tracks during thaw.
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
	float abs_t = clamp(abs(lateral_t), 0.0, 1.0);
	float sustained = smoothstep(1.80, max(full_mm, 3.5) * 1.25, mean_mm);
	float min_berm_abs_t = mix(0.85, 0.64, sustained);
	if (abs_t < min_berm_abs_t && sustained <= 0.001) {
		return 0.0;
	}
	vec2 side_off = lateral_t >= 0.0 ? vec2(0.0, 0.0) : vec2(41.7, 29.3);
	vec2 s_off = seed_offset + side_off;
	float patch_raw = proc_spatial_patch_field(station_m, lateral_t, seed_offset);
	float amount = smoothstep(min_visible_mm, full_mm, mean_mm);

	// 1. Outer berm / shoulder snow ribbon (advances inward during sustained snowfall)
	float berm_cov = 0.0;
	if (abs_t >= min_berm_abs_t) {
		float gate_lo = mix(0.58, 0.36, amount);
		float gate = smoothstep(gate_lo, gate_lo + 0.22, patch_raw);
		if (gate > 0.001) {
			float edge_jit1 = proc_value_noise2(vec2(station_m * 0.32, abs_t * 6.0), s_off + vec2(7.1, 13.9));
			float edge_jit2 = proc_value_noise2(vec2(station_m * 1.15, abs_t * 14.0), s_off + vec2(23.4, 41.8));
			float scallop = (edge_jit1 - 0.5) * 0.055 + (edge_jit2 - 0.5) * 0.032;
			float dist_from_edge = 1.0 - abs_t;
			float max_w = mix(0.142, 0.34, sustained);
			float base_w = mix(0.10, 0.26, sustained);
			float ribbon_width = clamp(
				base_w * (0.40 + 0.60 * amount) * (0.35 + 0.65 * gate) + scallop * gate,
				0.0,
				max_w
			);
			if (ribbon_width > 0.004) {
				float profile = 1.0 - smoothstep(ribbon_width * 0.24, ribbon_width, dist_from_edge);
				berm_cov = clamp(profile * smoothstep(0.0, 0.20, gate) * (0.45 + 0.55 * amount), 0.0, 1.0);
			}
		}
	}

	// 2. Central inter-track snow deposit during sustained snowfall (recedes with thaw)
	float crown_cov = 0.0;
	if (sustained > 0.001 && abs_t < 0.28) {
		float c_patch = proc_spatial_patch_field(station_m + 37.0, 0.0, seed_offset + vec2(19.3, 23.7));
		float c_gate = smoothstep(0.34, 0.58, c_patch);
		if (c_gate > 0.001) {
			float c_jit = proc_value_noise2(vec2(station_m * 0.45, lateral_t * 7.0), seed_offset + vec2(59.1, 17.4));
			float crown_w = clamp(0.22 * sustained * (0.55 + 0.45 * c_gate) + (c_jit - 0.5) * 0.05 * sustained, 0.0, 0.26);
			if (crown_w > 0.005) {
				float c_prof = 1.0 - smoothstep(crown_w * 0.25, crown_w, abs_t);
				crown_cov = clamp(c_prof * c_gate * sustained * 0.82, 0.0, 1.0);
			}
		}
	}

	return max(berm_cov, crown_cov);
}

// Returns vec3(water_cov, snow_cov, 0.0) for a carriageway coordinate (no ice patches).
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

// Shared CPU/GPU procedural lateral-berm fine gravel coverage and mud conversion factor.
// Mirrors the lateral-berm ribbon architecture of proc_local_pattern_coverage (independent L/R
// edges with slightly irregular width), continuous along 100% of gravel stages, with NO central
// crown line (|lateral_t| < 0.68 stays clean), and decisively replaced by snow wherever snow accumulates.
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

// Lightweight, subtle wet-road optics as wetness `water_cov` grows in [0, 1].
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

// Lightweight transverse wetness distribution: zero cost when dry, 1 single 2D noise when wet.
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
