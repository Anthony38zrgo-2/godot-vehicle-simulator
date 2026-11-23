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

// Shared CPU/GPU procedural loose clay-gravel (~40% of gravel stages) and heavy-rain mud factor:
// Returns vec2(loose_gravel_coverage, mud_factor) in [0, 1].
vec2 proc_sample_loose_gravel_and_mud(float station_m, float uv_x, float snow_cov) {
	float signed_lateral = (clamp(uv_x, 0.0, 1.0) - 0.5) * 2.0;
	float span_m = max(surface_station_range_m.y - surface_station_range_m.x, 1.0);
	float norm_u = clamp((station_m - surface_station_range_m.x) / span_m, 0.0, 1.0);
	float nw = max(surface_field_width, 2.0);
	float tex_u = (norm_u * (nw - 1.0) + 0.5) / nw;
	vec4 tex_rgba = texture(surface_field_tex, vec2(tex_u, 0.5));
	float road_water_mm = tex_rgba.r * surface_max_encode_mm;
	float saturation = clamp(tex_rgba.a, 0.0, 1.0);

	vec2 s0 = surface_seed_offsets.zw + vec2(31.4, 59.2);
	float n_macro = proc_value_noise2(vec2(station_m * 0.0075, 0.35), s0);
	float n_meso = proc_value_noise2(vec2(station_m * 0.024, 1.65), s0 + vec2(13.7, 29.1));
	float n_fine = proc_value_noise2(vec2(station_m * 0.085, 2.85 + signed_lateral * 0.75), s0 + vec2(47.3, 11.8));
	float field = 0.54 * n_macro + 0.30 * n_meso + 0.16 * n_fine;
	float sector_gate = smoothstep(0.530, 0.640, field);
	if (sector_gate <= 0.001) {
		return vec2(0.0);
	}
	float abs_lat = clamp(abs(signed_lateral), 0.0, 1.0);
	float rut_dip = 1.0 - 0.16 * (1.0 - clamp(abs(abs_lat - 0.48) / 0.24, 0.0, 1.0));
	float snow_mask = clamp(1.0 - snow_cov, 0.0, 1.0);
	float loose_cov = clamp(sector_gate * rut_dip, 0.0, 1.0) * snow_mask;
	float wet_drive = clamp(road_water_mm / 0.55 + saturation * 0.45, 0.0, 1.0);
	float mud_raw = smoothstep(0.32, 0.82, wet_drive);
	float mud = clamp(loose_cov * mud_raw, 0.0, 1.0);
	return vec2(loose_cov, mud);
}

vec3 proc_rotate_y(vec3 d, float yaw) {
	return vec3(cos(yaw) * d.x + sin(yaw) * d.z, d.y, -sin(yaw) * d.x + cos(yaw) * d.z);
}

vec3 proc_sample_sky_refl(vec3 reflected_world, float lod_bias) {
	vec3 dir = normalize(vec3(reflected_world.x, max(reflected_world.y, 0.015), reflected_world.z));
	vec3 sky = proc_horizon_color;
	if (proc_has_sky) {
		sky = mix(
			textureLod(proc_sky_a, dir, lod_bias).rgb * proc_tint_a,
			textureLod(proc_sky_b, proc_rotate_y(dir, proc_yaw_b), lod_bias).rgb * proc_tint_b,
			proc_weather_mix
		);
		sky = mix(
			textureLod(proc_sky_c, proc_rotate_y(dir, proc_twilight_yaw), lod_bias).rgb * proc_tint_c,
			sky,
			proc_daylight_mix
		);
		sky = mix(proc_horizon_color, sky, smoothstep(-0.02, 0.06, reflected_world.y));
	}
	return sky;
}

// Computes progressive 3-stage wet road optics as wetness `water_cov` grows in [0, 1]:
// - Stage 1 (0.00..0.30): porous capillary darkening, soft blurred grazing sheen.
// - Stage 2 (0.30..0.68): micro-film fills aggregate cavities & wheel tracks first (textured reflection).
// - Stage 3 (0.68..1.00): continuous glossy film mirroring the sky & clouds via Schlick Fresnel.
// Returns vec4(albedo_darken_mult, roughness, specular, reflection_strength).
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
		return vec4(1.0, dry_roughness, 0.08, 0.0);
	}
	// Map physical water_cov (smoothstep over water_mm in [0.01, full_mm]) onto a
	// perceptually progressive optical wetness curve from damp pores to soaked mirror.
	float w_vis = pow(w, 0.55);
	float darken = 1.0 - max_darken * smoothstep(0.0, 0.75, w_vis);

	// Local micro-pooling: aggregate crevices and wheel ruts hold a smoother film first.
	float local_pool = clamp(w_vis * (0.78 + 0.28 * micro_cavity + 0.24 * wheel_track_mask), 0.0, 1.0);
	float film_lin = clamp((local_pool - 0.06) / 0.88, 0.0, 1.0);
	float film = film_lin * (1.25 - 0.25 * film_lin);
	float mirror_film = smoothstep(0.32, 0.98, local_pool);

	// Soft Schlick Fresnel across the whole wet carriageway: gives a subtle, continuous
	// wet sky sheen even at mid/near driving angles while capping below standing puddles.
	float grazing = 1.0 - clamp(ndotv, 0.0, 1.0);
	float fresnel = 0.12 + 0.64 * pow(grazing, 2.15);

	float damp_rough = mix(dry_roughness, mix(dry_roughness, min_wet_roughness, 0.45), smoothstep(0.0, 0.35, w_vis));
	float wet_rough = mix(damp_rough, min_wet_roughness, film);
	wet_rough = mix(wet_rough, max(min_wet_roughness * 0.65, 0.12), mirror_film * 0.55);

	float spec = mix(0.16, 0.58, film);
	spec = mix(spec, 0.78, mirror_film * (0.40 + 0.60 * fresnel));

	// Gentle reflection blend factor over the entire wet surface (capped at 0.42 so puddles stand out cleanly)
	float refl_strength = clamp(film * (0.62 + 0.38 * mirror_film) * (0.34 + 0.66 * fresnel) * 0.58, 0.0, 0.42);

	return vec4(darken, wet_rough, spec, refl_strength);
}

// Multi-octave rotated 2D micro-roughness gradient in [-1, 1] with zero axis-aligned grid artifacts.
vec2 proc_road_micro_grad(vec2 xz, float freq_hi, float freq_lo) {
	mat2 rot1 = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	mat2 rot2 = mat2(vec2(0.54, -0.84), vec2(0.84, 0.54));
	vec2 p_lo = rot1 * (xz * freq_lo);
	vec2 p_hi = rot2 * (xz * freq_hi);
	vec2 g_lo = vec2(
		proc_value_noise2(p_lo, vec2(4.7, 1.3)) - 0.5,
		proc_value_noise2(p_lo, vec2(11.2, 6.8)) - 0.5
	);
	vec2 g_hi = vec2(
		proc_value_noise2(p_hi, vec2(19.3, 3.7)) - 0.5,
		proc_value_noise2(p_hi, vec2(27.1, 14.9)) - 0.5
	);
	return clamp((g_lo * 0.45 + g_hi * 0.95) * 2.0, vec2(-1.0), vec2(1.0));
}

// Distributes mean road water_cov across the transverse road profile (crown camber drainage,
// curve superelevation/banking runoff, meandering wheel tracks, and 2D multi-scale depressions)
// and computes a geometric aggregate micro-cavity factor independent of texture albedo color.
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
	float signed_lat = (clamp(lateral_01, 0.0, 1.0) - 0.5) * 2.0;
	mat2 rot1 = mat2(vec2(0.82, 0.57), vec2(-0.57, 0.82));
	mat2 rot2 = mat2(vec2(0.54, -0.84), vec2(0.84, 0.54));

	// 1. Geometric micro-cavity from world-space aggregate relief (never biased by dark stone pigment)
	float ag_lo = proc_value_noise2(rot1 * (world_xz * 3.4), vec2(11.7, 29.1));
	float ag_hi = proc_value_noise2(rot2 * (world_xz * 14.5), vec2(47.3, 8.6));
	out_micro_cavity = clamp(1.0 - (0.55 * ag_lo + 0.45 * ag_hi), 0.0, 1.0);

	// 2. Meandering, pulsing wheel ruts (wobble laterally ±4% and vary along station)
	float wobble = (proc_value_noise2(vec2(station_m * 0.052, 1.7), vec2(13.1, 7.9)) - 0.5) * 0.08
		+ (proc_value_noise2(vec2(station_m * 0.17, 3.4), vec2(29.3, 19.1)) - 0.5) * 0.045;
	float track_center = 0.24 + wobble;
	float track_width = 0.11 + 0.055 * proc_value_noise2(vec2(station_m * 0.085, abs(signed_lat) * 2.0), vec2(5.3, 41.2));
	float track_pulse = 0.58 + 0.42 * proc_value_noise2(vec2(station_m * 0.045, sign(signed_lat) * 2.0), vec2(61.7, 11.4));
	float raw_track = 1.0 - smoothstep(track_width * 0.28, track_width, abs(abs(lateral_01 - 0.5) - track_center));
	out_track_mask = clamp(raw_track * track_pulse, 0.0, 1.0);

	if (base_water_cov <= 0.003) {
		out_water_cov = 0.0;
		return;
	}

	// 3. Transverse crown camber (bombeo): central crown drains faster than wheel ruts & shoulders
	float crown_ridge = 1.0 - smoothstep(0.0, 0.26, abs(signed_lat));
	float shoulder_hold = smoothstep(0.60, 0.92, abs(signed_lat)) * 0.18;
	float camber_factor = 1.0 - 0.34 * crown_ridge * (1.0 - base_water_cov * 0.50) + shoulder_hold;

	// 4. Curve superelevation (peralte): water film persists longer on the low side of banked turns
	float bank_tilt = clamp((world_normal.x + world_normal.z) * 2.8, -0.35, 0.35);
	float bank_factor = 1.0 + signed_lat * bank_tilt * 0.55;

	// 5. Domain-warped 2D pavement drainage patchiness & diagonal cross-slope runoff streaks
	vec2 p_meso = rot1 * (world_xz * 0.16);
	vec2 warp = vec2(
		proc_value_noise2(p_meso * 0.65, vec2(17.3, 23.1)) - 0.5,
		proc_value_noise2(p_meso * 0.65, vec2(43.7, 9.2)) - 0.5
	) * 1.40;
	float n_macro = proc_value_noise2(vec2(station_m * 0.021, signed_lat * 0.45), vec2(3.7, 15.9));
	float n_meso = proc_value_noise2(p_meso + warp, vec2(31.4, 27.8));
	vec2 p_streak = vec2(station_m * 0.32 - abs(signed_lat) * 2.5, signed_lat * 3.6) + warp * 0.75;
	float n_streak = proc_value_noise2(p_streak, vec2(73.1, 51.6));
	float patch_field = clamp(0.36 * n_macro + 0.40 * n_meso + 0.24 * n_streak, 0.0, 1.0);
	float contrast = mix(1.18, 0.42, smoothstep(0.12, 0.92, base_water_cov));
	float patch_mult = 0.38 + 1.32 * pow(patch_field, contrast);

	float total_mult = clamp(camber_factor * bank_factor * patch_mult + out_track_mask * track_weight, 0.22, 1.55);
	out_water_cov = clamp(base_water_cov * total_mult, 0.0, 1.0);
}

// Samples the live sky cubemap perturbed by pavement grain and outputs the perturbed world normal
// so direct solar glint can be evaluated in `light()` with real shadow map `ATTENUATION`.
void proc_wet_sky_reflection(
	vec3 world_pos,
	vec3 world_normal,
	vec3 cam_pos,
	float water_cov,
	float refl_strength,
	vec2 micro_grad,
	float max_perturb,
	out vec3 out_sky,
	out vec3 out_pert_world_normal
) {
	// Perturbation decreases as deeper water levels out pavement pores
	float smooth_k = smoothstep(0.08, 0.82, pow(clamp(water_cov, 0.0, 1.0), 0.62));
	float perturb = mix(max_perturb, max_perturb * 0.16, smooth_k);
	out_pert_world_normal = normalize(world_normal + vec3(micro_grad.x * perturb, 0.0, micro_grad.y * perturb));
	if (refl_strength <= 0.002) {
		out_sky = vec3(0.0);
		return;
	}
	vec3 view_world = normalize(world_pos - cam_pos);
	vec3 reflected = reflect(view_world, out_pert_world_normal);

	// Keep wet road reflection softer/more diffuse than crisp standing water puddles
	float lod_bias = mix(3.6, 1.35, smooth_k);
	out_sky = proc_sample_sky_refl(reflected, lod_bias);
}
