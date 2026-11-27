// SEALED CPU / RUST <-> GPU PARITY FUNCTIONS
// Do not change formulas or constants without updating Rust (`puddles.rs`, `procedural_weather.rs`)
// and GDScript (`rally_puddles.gd`) counterparts and passing retention/water contracts.

float shore_threshold_for_fill(float f_in) {
	float t = clamp(f_in, 0.0, 1.0);
	float f = t * (1.35 - 0.35 * t);
	return mix(0.62, 0.18, f);
}

vec2 warp_mask_uv(vec2 uv, vec2 scale, vec4 sp) {
	vec2 p = uv * scale;
	float px = p.x * (1.0 + p.y * 0.34 * sp.x) + (p.y * p.y - 0.06) * 0.28 * sp.y;
	float py = p.y * (1.0 - p.x * 0.18 * sp.y) + (p.x * p.x - 0.05) * 0.16 * sp.x;
	float r2 = clamp(dot(p, p) * 4.0, 0.0, 1.0);
	float w1 = (sin(py * 5.8 + sp.w) + 0.55 * cos(px * 11.2 - sp.w * 1.7)) * 0.038 * sp.z * r2;
	float w2 = (cos(px * 5.4 + sp.w * 1.3) + 0.55 * sin(py * 10.6 + sp.w * 0.8)) * 0.038 * sp.z * r2;
	return vec2(px + w1, py + w2) + vec2(0.5);
}

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
