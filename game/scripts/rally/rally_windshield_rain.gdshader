shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float car_speed_mps : hint_range(0.0, 80.0) = 0.0;
uniform bool is_cockpit_view = true;

varying vec2 v_glass_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// 1. Persistent Static Droplets:
// Stable resting water beads adhering to the glass.
// Never flickers or blinks; presence scales continuously with rain_intensity.
vec3 persistent_droplet_layer(vec2 pos_m, float scale, float density, float seed) {
	vec2 p = pos_m * scale + vec2(seed * 19.3, seed * 37.1);
	vec2 cell = floor(p);
	vec2 local = fract(p) - 0.5;

	float prob = hash12(cell + vec2(7.3, 13.9));
	if (prob > density) {
		return vec3(0.0);
	}

	vec2 rnd = hash22(cell + vec2(31.4, 9.1));
	vec2 center = (rnd - 0.5) * 0.62;
	vec2 delta = local - center;
	delta.y *= 0.88; // Slight teardrop elongation on inclined windshield

	float base_rad = mix(0.12, 0.22, hash12(cell + vec2(11.2, 5.7)));
	// Softly fade in new droplets as rain_intensity increases without popping
	float threshold_fade = clamp((density - prob) / 0.12, 0.0, 1.0);
	float radius = base_rad * threshold_fade;
	float dist = length(delta);
	if (dist >= radius) {
		return vec3(0.0);
	}

	float r = dist / max(radius, 0.0001);
	float lens_curve = r * (0.35 + 0.65 * r * r);
	vec2 dir = delta / max(dist, 0.0001);
	vec2 normal_2d = dir * lens_curve * threshold_fade;
	float coverage = (1.0 - smoothstep(0.80, 1.0, r)) * threshold_fade;
	return vec3(normal_2d, coverage);
}

// 2. Dual-Phase Smooth Dynamic Micro-Droplets:
// Two time-offset phases blended with sin/cos so total coverage is mathematically
// constant over time (w_a^2 + w_b^2 == 1.0), completely eliminating strobing/popping.
vec3 smooth_dynamic_layer(vec2 pos_m, float scale, float time, float density, float seed) {
	vec2 p = pos_m * scale + vec2(seed * 23.7, seed * 41.3);
	vec2 cell = floor(p);
	vec2 local = fract(p) - 0.5;

	float prob = hash12(cell + vec2(17.1, 8.9));
	if (prob > density) {
		return vec3(0.0);
	}

	vec2 rnd = hash22(cell);
	vec2 center = (rnd - 0.5) * 0.58;
	vec2 delta = local - center;
	delta.y *= 0.90;

	float cycle_rate = 0.45 + 0.35 * rnd.x;
	float t_val = time * cycle_rate + rnd.y * 6.2831;

	// Dual-phase sine/cosine weights guarantee seamless continuous presence
	float w_a = sin(t_val);
	float w_b = cos(t_val);
	float weight = max(w_a * w_a, w_b * w_b); // Smooth breathing envelope, never drops to 0

	float base_rad = mix(0.10, 0.18, hash12(cell + vec2(2.3, 19.8)));
	float radius = base_rad * (0.85 + 0.25 * weight);
	float dist = length(delta);
	if (dist >= radius) {
		return vec3(0.0);
	}

	float r = dist / max(radius, 0.0001);
	float lens_curve = r * (0.32 + 0.68 * r * r);
	vec2 dir = delta / max(dist, 0.0001);
	vec2 normal_2d = dir * lens_curve * weight;
	float coverage = (1.0 - smoothstep(0.78, 1.0, r)) * weight;
	return vec3(normal_2d, coverage);
}

// 3. Continuous Aerodynamic Rivulets & Streaks:
// Uses continuous vertical flow channels so water runs smoothly upward/outward
// with vehicle speed without jumping across cell boundaries.
vec3 continuous_streak_layer(vec2 pos_m, float time, float intensity, float speed_mps) {
	if (intensity <= 0.01) {
		return vec3(0.0);
	}

	float speed_norm = clamp(speed_mps / 28.0, 0.0, 1.6);
	float flow_speed = 0.06 + speed_norm * 0.38;

	// Outward aerodynamic splay across the windshield curved glass
	vec2 flow_pos = pos_m;
	flow_pos.x -= pos_m.x * (pos_m.y * 0.16 * clamp(speed_norm, 0.0, 1.0));

	float num_channels = 36.0;
	float ch = floor(flow_pos.x * num_channels);
	float ch_prob = hash12(vec2(ch, 53.0));
	if (ch_prob > intensity * 0.78) {
		return vec3(0.0);
	}

	float ch_x_center = (ch + 0.5) / num_channels;
	float dist_x = (flow_pos.x - ch_x_center) * num_channels; // [-0.5 .. 0.5]

	float ch_speed = flow_speed * (0.82 + 0.36 * ch_prob);
	// Continuous scrolling vertical parameter
	float y_stream = flow_pos.y * 2.8 - time * ch_speed * 2.8 + ch_prob * 11.0;

	// Two staggered drops per channel for a continuous uninterrupted stream
	vec2 normal_total = vec2(0.0);
	float cov_total = 0.0;

	for (int i = 0; i < 2; i++) {
		float offset = float(i) * 0.5;
		float y_phase = fract(y_stream + offset); // 0.0 -> 1.0

		// Meandering path
		float meander = sin(y_stream * 4.0 + ch_prob * 6.28) * 0.12;
		float dx = dist_x - meander;

		// Droplet head at y_phase in [0.70 .. 0.88]
		float head_dist_y = (y_phase - 0.80) * 5.0;
		vec2 head_vec = vec2(dx * 1.8, head_dist_y);
		float head_len = length(head_vec);
		float head_rad = 0.28;

		if (head_len < head_rad) {
			float r = head_len / head_rad;
			float curve = r * (0.35 + 0.65 * r * r);
			vec2 n = (head_vec / max(head_len, 0.0001)) * curve;
			float cov = 1.0 - smoothstep(0.75, 1.0, r);
			normal_total += n * cov;
			cov_total = max(cov_total, cov);
		}

		// Trailing continuous wake (y_phase in [0.15 .. 0.78])
		if (y_phase < 0.78 && y_phase > 0.18) {
			float wake_norm = (y_phase - 0.18) / 0.60; // 0 (tail) -> 1 (near head)
			float wake_width = mix(0.04, 0.14, wake_norm);
			float adx = abs(dx);
			if (adx < wake_width) {
				float wr = adx / wake_width;
				float wake_fade = wake_norm * (1.0 - smoothstep(0.60, 1.0, wr));
				vec2 wake_n = vec2(sign(dx) * wr * 0.45, -0.12) * wake_fade;
				normal_total += wake_n;
				cov_total = max(cov_total, wake_fade * 0.65);
			}
		}
	}

	return vec3(normal_total, clamp(cov_total, 0.0, 1.0));
}

void vertex() {
	// Isometric coordinates in meters on the windshield plane
	v_glass_pos = vec2(VERTEX.x, VERTEX.y * 0.608 + VERTEX.z * 0.794);
}

void fragment() {
	if (!is_cockpit_view || rain_intensity <= 0.005) {
		ALPHA = 0.0;
		discard;
	}

	// 1. Persistent resting beads (stable, steady, continuous)
	vec3 p1 = persistent_droplet_layer(v_glass_pos, 52.0, rain_intensity * 0.88, 1.0);
	vec3 p2 = persistent_droplet_layer(v_glass_pos, 88.0, rain_intensity * 0.76, 2.0);

	// 2. Dual-phase smooth dynamic droplets (no flickering/choppiness)
	vec3 d1 = smooth_dynamic_layer(v_glass_pos, 64.0, TIME, rain_intensity * 0.80, 3.0);
	vec3 d2 = smooth_dynamic_layer(v_glass_pos, 120.0, TIME * 1.1, rain_intensity * 0.70, 4.0);

	// 3. Continuous aerodynamic sliding streaks
	vec3 s1 = continuous_streak_layer(v_glass_pos, TIME, rain_intensity, car_speed_mps);

	vec2 lens_normal = p1.xy + p2.xy * 0.80 + d1.xy * 0.75 + d2.xy * 0.55 + s1.xy * 1.10;
	float coverage = clamp(max(max(max(p1.z, p2.z), max(d1.z, d2.z)), s1.z), 0.0, 1.0);

	if (coverage <= 0.003) {
		ALPHA = 0.0;
		discard;
	}

	// Pure optical refraction of the 3D scene behind the windshield
	float refr_strength = 0.020;
	vec2 refr_uv = clamp(SCREEN_UV + lens_normal * refr_strength, vec2(0.002), vec2(0.998));
	vec3 refracted = textureLod(screen_tex, refr_uv, 0.0).rgb;

	// Optical rim physics: steep outer rim bends sky light, center remains clear
	float rim_steepness = clamp(length(lens_normal), 0.0, 1.0);
	float rim_ring = smoothstep(0.32, 0.85, rim_steepness);
	vec2 n_dir = lens_normal / max(rim_steepness, 0.0001);

	// Subtle pinpoint crescent glint on sky-facing rim
	float sky_catch = clamp(dot(n_dir, normalize(vec2(0.2, 0.98))), 0.0, 1.0);
	float lower_meniscus = clamp(dot(n_dir, normalize(vec2(-0.1, -0.99))), 0.0, 1.0);

	float scene_luma = dot(refracted, vec3(0.299, 0.587, 0.114));
	vec3 glint = vec3(0.88, 0.94, 1.0) * pow(sky_catch, 4.0) * rim_ring * (0.12 + 0.16 * scene_luma);
	float meniscus_darken = 1.0 - (pow(lower_meniscus, 3.0) * rim_ring * 0.10);

	ALBEDO = refracted * meniscus_darken + glint;
	ALPHA = clamp(smoothstep(0.0, 0.18, coverage) * 0.95, 0.0, 0.96);
}
