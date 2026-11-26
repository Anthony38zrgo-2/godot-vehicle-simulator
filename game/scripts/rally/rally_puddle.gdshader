shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert;

uniform vec2 patch_size = vec2(1.0);
varying vec2 patch_uv;
varying vec3 world_position;
varying float v_road_weight;

uniform bool enable_water_reflections = false;
uniform bool has_sky = false;
uniform samplerCube sky_a : source_color, filter_linear_mipmap;
uniform samplerCube sky_b : source_color, filter_linear_mipmap;
uniform samplerCube sky_c : source_color, filter_linear_mipmap;
uniform float weather_mix = 0.0;
uniform float daylight_mix = 1.0;
uniform float twilight_yaw = 0.0;
uniform float yaw_b = 0.0;
uniform vec3 tint_a = vec3(1.0);
uniform vec3 tint_b = vec3(1.0);
uniform vec3 tint_c = vec3(1.0);
uniform vec3 horizon_color : source_color = vec3(0.25);
uniform vec4 sky_tint : source_color = vec4(0.46, 0.52, 0.58, 1.0);
uniform vec3 sun_dir = vec3(0.0, 0.7, 0.7);
uniform vec3 sun_color = vec3(1.0, 0.95, 0.85);

uniform sampler2D puddle_mask : hint_default_white, filter_linear_mipmap;
uniform bool use_mask_texture = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec4 shape_params = vec4(0.0);
uniform float max_depth_mm = 48.0;
uniform float fill = 0.0;
uniform int winter_kind = 0;
uniform float winter_depth_mm = 0.0;
uniform float rain = 0.0;
uniform vec2 wind_vec = vec2(1.2, 0.4);
uniform float edge_softness = 0.18;
uniform float turbidity_rate = 0.065;
uniform vec4 shallow_color : source_color = vec4(0.030, 0.065, 0.105, 0.22);
uniform vec4 deep_color : source_color = vec4(0.008, 0.022, 0.048, 0.88);

#include "res://scripts/rally/rally_water_detail.gdshaderinc"

vec3 rotate_y(vec3 d, float yaw) {
	return vec3(cos(yaw) * d.x + sin(yaw) * d.z, d.y, -sin(yaw) * d.x + cos(yaw) * d.z);
}

float puddle_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float puddle_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = puddle_hash(i);
	float b = puddle_hash(i + vec2(1.0, 0.0));
	float c = puddle_hash(i + vec2(0.0, 1.0));
	float d = puddle_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Lightweight 2-octave world-space micro-relief in [-0.5, 0.5] + cheap shore slope.
vec3 puddle_micro_relief(vec2 xz, bool compute_grad) {
	vec2 p1 = vec2(xz.x * 1.40 + xz.y * 1.05, -xz.x * 1.05 + xz.y * 1.40);
	vec2 p2 = vec2(xz.x * 3.13 - xz.y * 4.87, xz.x * 4.87 + xz.y * 3.13);
	float n1 = puddle_value_noise(p1) - 0.5;
	float n2 = puddle_value_noise(p2) - 0.5;
	float h = n1 * 0.62 + n2 * 0.38;
	if (!compute_grad) {
		return vec3(h, 0.0, 0.0);
	}
	float gx = (puddle_value_noise(p2 + vec2(0.18, 0.0)) - 0.5) - n2;
	float gz = (puddle_value_noise(p2 + vec2(0.0, 0.18)) - 0.5) - n2;
	return vec3(h, gx * 4.2, gz * 4.2);
}

// Shared CPU/Rust/GPU bathymetric shoreline threshold in [0.18, 0.62].
float shore_threshold_for_fill(float f_in) {
	float t = clamp(f_in, 0.0, 1.0);
	float f = t * (1.35 - 0.35 * t);
	return mix(0.62, 0.18, f);
}

// Analytical 2-wave slope (dh/dx, dh/dz) aligned with meteorological wind_vec (m/s).
vec2 puddle_wind_slope(vec2 xz, float time, float depth_norm, vec2 wind) {
	float wspd = length(wind);
	float w_amp = smoothstep(0.15, 7.5, wspd);
	if (w_amp <= 0.001) {
		return vec2(0.0);
	}
	vec2 wdir = (wspd > 0.01) ? (wind / wspd) : vec2(0.85, 0.52);
	vec2 wperp = vec2(-wdir.y, wdir.x);
	vec2 dir1 = normalize(wdir + wperp * 0.28);
	vec2 dir2 = normalize(wdir - wperp * 0.34);

	float f1 = mix(3.0, 1.6, depth_norm);
	float f2 = mix(4.6, 2.5, depth_norm);
	float speed = 0.75 + 0.32 * min(wspd, 12.0);

	float a1 = dot(xz, dir1) * f1 - time * speed * 1.35;
	float a2 = dot(xz, dir2) * f2 - time * speed * 1.10;

	vec2 g = dir1 * (cos(a1) * f1 * 0.022) + dir2 * (cos(a2) * f2 * 0.015);
	return g * (0.12 + 0.88 * w_amp);
}

// Single-cell concentric raindrop ring gradient (no 3x3 neighbor loop: jitter + max radius
// stay bounded within the cell so rings never clip at cell borders).
vec2 rain_ripple_layer(vec2 uv_world, float scale, vec2 offset, float time, float spawn_prob) {
	vec2 p = uv_world * scale + offset;
	vec2 cell_id = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = puddle_hash(cell_id);
	float rate = 0.85 + 0.65 * h;
	float t_cycle = time * rate + h * 6.2831;
	float cycle_idx = floor(t_cycle);
	float h_spawn = puddle_hash(cell_id + vec2(cycle_idx * 13.7, cycle_idx * 7.3));
	if (h_spawn > spawn_prob) {
		return vec2(0.0);
	}
	vec2 jitter = (vec2(
		puddle_hash(cell_id + vec2(19.1 + cycle_idx, 5.7)),
		puddle_hash(cell_id + vec2(31.3, 11.9 + cycle_idx))
	) - 0.5) * 0.34;
	float age = fract(t_cycle);
	float rad = age * 0.32;
	vec2 d = f - jitter;
	float dist = length(d);
	if (dist <= 0.005 || dist >= rad || dist <= rad - 0.14) {
		return vec2(0.0);
	}
	float ring_t = clamp((dist - (rad - 0.14)) / 0.14, 0.0, 1.0);
	float window = sin(ring_t * 3.14159265);
	float slope = sin(ring_t * 12.5663706) * window * window;
	float fade = (1.0 - age) * smoothstep(0.0, 0.12, age);
	return (d / dist) * (slope * fade);
}

// Lightweight 1-to-2 layer concentric raindrop ripples (15x fewer evaluations than 2x3x3 Voronoi).
vec2 rain_drop_ripples_grad(vec2 uv_world, float time, float intensity, float cam_dist) {
	if (intensity <= 0.01 || cam_dist > 34.0) {
		return vec2(0.0);
	}
	float dist_fade = 1.0 - smoothstep(14.0, 34.0, cam_dist);
	float spawn_prob = clamp(0.18 + 0.82 * pow(clamp(intensity, 0.0, 1.0), 0.75), 0.0, 1.0);
	float amp_scale = (0.09 + 0.08 * clamp(intensity, 0.0, 1.0)) * dist_fade;
	vec2 grad = rain_ripple_layer(uv_world, 3.6, vec2(0.0), time, spawn_prob);
	if (intensity >= 0.32 && cam_dist < 18.0) {
		grad += rain_ripple_layer(uv_world, 5.8, vec2(17.3, 29.1), time * 1.12, spawn_prob) * (1.0 - smoothstep(10.0, 18.0, cam_dist));
	}
	return grad * amp_scale;
}

void vertex() {
	patch_uv = VERTEX.xz / max(patch_size, vec2(0.1));
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_road_weight = COLOR.r;
}

// Procedural fallback: gentle rounded organic pond without sharp spikes or pinched poles
float procedural_mask(vec2 uv, vec4 sp) {
	vec2 p = uv * 2.0;
	p.x += (p.y * 0.20) * sp.y;
	p.x *= (1.0 + p.y * 0.15 * sp.x);
	float phase = sp.w;
	float w1 = sin(p.y * 2.2 + phase) * 0.08 * sp.z;
	float w2 = cos(p.x * 2.0 + phase * 1.2) * 0.08 * sp.z;
	vec2 warped = p + vec2(w1, w2);
	float r = length(warped);
	float theta = atan(warped.y, warped.x);
	float r_bound = 0.86 + 0.05 * sin(2.0 * theta + phase);
	return clamp(1.0 - (r / r_bound), 0.0, 1.0);
}

// Shared CPU/GPU organic domain warp for PNG bathymetric masks.
// Reduces to identity `uv * scale + vec2(0.5)` when `sp == vec4(0.0)`.
vec2 warp_mask_uv(vec2 uv, vec2 scale, vec4 sp) {
	vec2 p = uv * scale;
	float px = p.x * (1.0 + p.y * 0.34 * sp.x) + (p.y * p.y - 0.06) * 0.28 * sp.y;
	float py = p.y * (1.0 - p.x * 0.18 * sp.y) + (p.x * p.x - 0.05) * 0.16 * sp.x;
	float r2 = clamp(dot(p, p) * 4.0, 0.0, 1.0);
	float w1 = (sin(py * 5.8 + sp.w) + 0.55 * cos(px * 11.2 - sp.w * 1.7)) * 0.038 * sp.z * r2;
	float w2 = (cos(px * 5.4 + sp.w * 1.3) + 0.55 * sin(py * 10.6 + sp.w * 0.8)) * 0.038 * sp.z * r2;
	return vec2(px + w1, py + w2) + vec2(0.5);
}

void fragment() {
	if (winter_kind == 0 && fill <= 0.001) {
		discard;
	}

	float mask = 0.0;
	if (use_mask_texture) {
		vec2 muv = warp_mask_uv(patch_uv, uv_scale, shape_params);
		if (muv.x < 0.0 || muv.x > 1.0 || muv.y < 0.0 || muv.y > 1.0) {
			discard;
		}
		mask = texture(puddle_mask, muv).r;
	} else {
		mask = procedural_mask(patch_uv, shape_params);
	}

	// Smoothly trim geometry that overhangs the edge of the road collision
	mask *= smoothstep(0.04, 0.65, v_road_weight);

	if (mask <= 0.006) {
		discard;
	}

	float cam_dist = length(world_position - CAMERA_POSITION_WORLD);

	// Bathymetric basin growth + world-space micro-relief shoreline breakup:
	// `shore_thresh` matches CPU/Rust `shore_threshold_for_fill(fill)` so at 10% fill only
	// the deepest pit holds a small water mirror, advancing outward as fill -> 100%,
	// surrounded by a translucent damp pavement rim that preserves the underlying road texture.
	vec3 micro_rel = puddle_micro_relief(world_position.xz, winter_kind == 0 && cam_dist < 40.0);
	float shore_thresh = (winter_kind == 1) ? 0.18 : shore_threshold_for_fill(fill);
	float rim_zone = 1.0 - smoothstep(shore_thresh, min(shore_thresh + 0.30, 0.96), mask);
	float vis_mask = mask + micro_rel.x * (0.11 + 0.08 * edge_softness) * rim_zone * smoothstep(0.04, 0.22, mask);

	// Double-zone decomposition:
	// Zone 1: Translucent outer damp pavement ring (mask in [0.06, shore_thresh])
	// Zone 2: Inner liquid water basin (vis_mask > shore_thresh)
	float wet_soil = smoothstep(0.05, max(shore_thresh, 0.24), vis_mask);
	float water_body = smoothstep(shore_thresh, min(shore_thresh + 0.08 + edge_softness * 0.10, 0.96), vis_mask);
	float water_mask = clamp((vis_mask - shore_thresh) / max(1.0 - shore_thresh, 0.18), 0.0, 1.0);

	// Physical basin depth in mm (winter_kind == 1: translucent snow/slush patch; winter_kind == 0: liquid water)
	if (winter_kind == 1) {
		float depth_mm = water_mask * winter_depth_mm;
		float edge_fade = smoothstep(0.0, 4.5, depth_mm);
		float core_dense = smoothstep(2.0, 18.0, depth_mm);
		float grain_break = clamp(micro_rel.x * 0.24 * (1.0 - core_dense * 0.55), -0.14, 0.14);
		float snow_alpha = clamp(edge_fade * mix(0.26, 0.76, core_dense) + grain_break * edge_fade, 0.0, 0.80);
		ALBEDO = mix(vec3(0.54, 0.58, 0.63), vec3(0.86, 0.89, 0.93), core_dense);
		ROUGHNESS = mix(0.68, 0.92, core_dense);
		SPECULAR = mix(0.24, 0.12, core_dense);
		ALPHA = snow_alpha;
	} else {
		float real_depth_mm = water_mask * fill * max_depth_mm;
		float depth_norm = clamp(real_depth_mm / 48.0, 0.0, 1.0);
		float shore_depth = smoothstep(0.0, 7.0, real_depth_mm);

		// 1. Beer-Lambert Law: Exponential light extinction through muddy sediment suspension.
		// Keep optical turbidity_alpha lighter than tint turbidity so pavement/gravel remains visible from above.
		float turbidity = 1.0 - exp(-real_depth_mm * turbidity_rate);
		float turbidity_alpha = 1.0 - exp(-real_depth_mm * turbidity_rate * 0.38);

		// 2. Subtle cavity rim shading inside deep potholes
		float rim_band = smoothstep(shore_thresh, shore_thresh + 0.10, vis_mask) * (1.0 - smoothstep(shore_thresh + 0.10, shore_thresh + 0.32, vis_mask));
		float cavity_occlusion = 1.0 - rim_band * depth_norm * 0.35;

		// 3. Meniscus surface tension glint along the granular shoreline
		float meniscus = smoothstep(shore_thresh - 0.01, shore_thresh + 0.035, vis_mask) * (1.0 - smoothstep(shore_thresh + 0.035, shore_thresh + 0.09, vis_mask));
		float meniscus_glint = pow(meniscus, 2.0) * 0.22 * water_body;

		// 4. Wind-aligned capillary waves + close-range raindrop rings + shallow stone grain
		float dist_fade = 1.0 - smoothstep(45.0, 95.0, cam_dist);
		float detail_k = clamp(detail_strength * 0.22 * water_body * dist_fade, 0.0, 1.0);
		float pattern = 0.5;
		if (detail_k > 0.005) {
			vec2 detail_flow = wind_vec * (TIME * 0.035) + vec2(TIME) * detail_speed * vec2(0.4, 0.6);
			vec3 wd = water_detail_sample(world_position.xz, detail_flow);
			pattern = smoothstep(0.38, 0.68, wd.x);
		}

		float ripple_damping = smoothstep(shore_thresh, min(shore_thresh + 0.18, 0.95), vis_mask) * dist_fade;
		vec2 rain_grad = rain_drop_ripples_grad(world_position.xz, TIME, rain, cam_dist) * ripple_damping;
		vec2 wind_grad = (cam_dist < 70.0) ? (puddle_wind_slope(world_position.xz, TIME, depth_norm, wind_vec) * ripple_damping) : vec2(0.0);
		vec2 shore_grain_grad = micro_rel.yz * (1.0 - shore_depth) * 0.15;
		vec2 wave_slope = wind_grad + rain_grad + shore_grain_grad;

		// Unified perturbed normal: used both for sky cubemap reflection and view-space NORMAL in light()
		vec3 base_world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 normal_world = normalize(base_world_n + vec3(wave_slope.x, 0.0, wave_slope.y));
		NORMAL = normalize((VIEW_MATRIX * vec4(mix(base_world_n, normal_world, water_body), 0.0)).xyz);

		vec3 view_dir_world = normalize(world_position - CAMERA_POSITION_WORLD);
		vec3 reflected = reflect(view_dir_world, normal_world);
		vec3 refl_dir = normalize(vec3(reflected.x, max(reflected.y, 0.015), reflected.z));
		vec3 sky = horizon_color;
		if (enable_water_reflections && has_sky) {
			// Skip redundant cubemap fetches when a sky layer has negligible weight.
			if (weather_mix <= 0.02) {
				sky = texture(sky_a, refl_dir).rgb * tint_a;
			} else if (weather_mix >= 0.98) {
				sky = texture(sky_b, rotate_y(refl_dir, yaw_b)).rgb * tint_b;
			} else {
				sky = mix(
					texture(sky_a, refl_dir).rgb * tint_a,
					texture(sky_b, rotate_y(refl_dir, yaw_b)).rgb * tint_b,
					weather_mix
				);
			}
			if (daylight_mix < 0.98) {
				vec3 twilight_col = texture(sky_c, rotate_y(refl_dir, twilight_yaw)).rgb * tint_c;
				sky = mix(twilight_col, sky, daylight_mix);
			}
			sky = mix(horizon_color, sky, smoothstep(-0.02, 0.05, reflected.y));
		} else {
			sky = sky_tint.rgb;
		}

		// Physical Schlick Fresnel curve: strong crisp mirror reflection in puddles vs subtle damp road sheen
		float view_angle = clamp(dot(normal_world, -view_dir_world), 0.0, 1.0);
		float soft_fresnel = 1.0 - view_angle;
		float shore_mirror = pow(shore_depth, 0.68);
		float schlick_fresnel = clamp(0.08 + 0.90 * pow(soft_fresnel, 2.50), 0.0, 0.94) * shore_mirror;

		// Neutral translucent damp-pavement darkening in outer rim (preserves underlying road texture/color)
		vec3 soil_albedo = vec3(0.018, 0.018, 0.019) * cavity_occlusion;

		// Water body color: shore absorption into turbid basin + crisp rippled sky reflection in deeper core
		vec3 base_puddle = mix(shallow_color.rgb, deep_color.rgb, turbidity) * cavity_occlusion;
		base_puddle = mix(soil_albedo, base_puddle, shore_depth);
		vec3 highlight = base_puddle * 1.45;
		if (enable_water_reflections) {
			highlight = mix(highlight + sky * 0.28, sky * 0.74, 0.52);
		}
		vec3 water_color = mix(base_puddle * 0.82, highlight, pattern * detail_k * shore_depth);
		vec3 water_albedo = enable_water_reflections ? mix(water_color, sky * 0.96, schlick_fresnel) : water_color;

		ALBEDO = mix(soil_albedo, water_albedo, water_body);
		// EMISSION carries ONLY the crisp sky vault reflection (visible in shadow), deliberately
		// stronger and sharper than the diffuse wet road film surrounding the puddle.
		if (enable_water_reflections) {
			EMISSION = (sky * (0.14 * pattern * detail_k * shore_depth + 0.66 * schlick_fresnel) + sky * (meniscus_glint * 0.24)) * water_body;
		}

		// Differentiated PBR surface response: satin damp rim vs glossy liquid water mirror
		ROUGHNESS = mix(0.42, enable_water_reflections ? 0.02 + 0.08 * (1.0 - shore_depth) : 0.62, water_body);
		METALLIC = 0.0;
		SPECULAR = enable_water_reflections ? mix(0.20, 0.98, water_body * (0.45 + 0.55 * shore_mirror)) : 0.0;

		// Translucent water opacity: clear enough from steep angles to show pavement/gravel underneath,
		// rising smoothly to a reflective mirror at grazing Fresnel angles.
		float soil_alpha = wet_soil * (1.0 - water_body * 0.85) * 0.18 * smoothstep(0.0, 0.12, fill);
		float vertical_water_alpha = mix(0.14, 0.48, turbidity_alpha);
		float base_water_alpha = enable_water_reflections ? clamp(mix(vertical_water_alpha, 0.82, schlick_fresnel * 0.88), 0.12, 0.82) : vertical_water_alpha;
		float water_alpha = base_water_alpha * water_body * pow(clamp(water_mask * 1.45, 0.0, 1.0), 0.78);
		ALPHA = max(soil_alpha, water_alpha);
	}
}
