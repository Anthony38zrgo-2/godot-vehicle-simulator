shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

uniform sampler2D glass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool cracked = false;
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float car_speed_mps : hint_range(0.0, 80.0) = 0.0;

varying vec3 v_local_pos;
varying vec3 v_local_normal;

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

vec3 ext_persistent_droplets(vec2 pos_m, float scale, float density, float seed) {
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
	delta.y *= 0.88;

	float base_rad = mix(0.11, 0.20, hash12(cell + vec2(11.2, 5.7)));
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

vec3 ext_continuous_streaks(vec2 pos_m, float time, float intensity, float speed_mps) {
	if (intensity <= 0.01) {
		return vec3(0.0);
	}

	float speed_norm = clamp(speed_mps / 28.0, 0.0, 1.6);
	float flow_speed = 0.06 + speed_norm * 0.36;

	float num_channels = 32.0;
	float ch = floor(pos_m.x * num_channels);
	float ch_prob = hash12(vec2(ch, 47.0));
	if (ch_prob > intensity * 0.75) {
		return vec3(0.0);
	}

	float ch_x_center = (ch + 0.5) / num_channels;
	float dist_x = (pos_m.x - ch_x_center) * num_channels;

	float ch_speed = flow_speed * (0.80 + 0.40 * ch_prob);
	float y_stream = pos_m.y * 2.6 - time * ch_speed * 2.6 + ch_prob * 13.0;

	vec2 normal_total = vec2(0.0);
	float cov_total = 0.0;

	for (int i = 0; i < 2; i++) {
		float offset = float(i) * 0.5;
		float y_phase = fract(y_stream + offset);

		float meander = sin(y_stream * 4.0 + ch_prob * 6.28) * 0.10;
		float dx = dist_x - meander;

		float head_dist_y = (y_phase - 0.80) * 5.0;
		vec2 head_vec = vec2(dx * 1.8, head_dist_y);
		float head_len = length(head_vec);
		float head_rad = 0.26;

		if (head_len < head_rad) {
			float r = head_len / head_rad;
			float curve = r * (0.35 + 0.65 * r * r);
			vec2 n = (head_vec / max(head_len, 0.0001)) * curve;
			float cov = 1.0 - smoothstep(0.75, 1.0, r);
			normal_total += n * cov;
			cov_total = max(cov_total, cov);
		}

		if (y_phase < 0.78 && y_phase > 0.20) {
			float wake_norm = (y_phase - 0.20) / 0.58;
			float wake_width = mix(0.03, 0.12, wake_norm);
			float adx = abs(dx);
			if (adx < wake_width) {
				float wr = adx / wake_width;
				float wake_fade = wake_norm * (1.0 - smoothstep(0.60, 1.0, wr));
				vec2 wake_n = vec2(sign(dx) * wr * 0.40, -0.10) * wake_fade;
				normal_total += wake_n;
				cov_total = max(cov_total, wake_fade * 0.60);
			}
		}
	}

	return vec3(normal_total, clamp(cov_total, 0.0, 1.0));
}

void vertex() {
	v_local_pos = VERTEX;
	v_local_normal = NORMAL;
}

void fragment() {
	vec4 glass = texture(glass_texture, UV);
	float grazing = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 3.0);
	vec3 tint = vec3(0.035, 0.046, 0.052);
	vec3 base_albedo = tint + glass.rgb * (cracked ? 0.20 : 0.07) * glass.a;

	float coverage = 0.0;
	vec2 lens_normal = vec2(0.0);
	vec3 rim_glint = vec3(0.0);

	if (rain_intensity > 0.005) {
		vec2 win_pos = (abs(v_local_normal.x) > 0.45)
			? vec2(v_local_pos.z, v_local_pos.y)
			: vec2(v_local_pos.x, v_local_pos.y * 0.61 + abs(v_local_pos.z) * 0.79);

		vec3 p1 = ext_persistent_droplets(win_pos, 54.0, rain_intensity * 0.86, 1.0);
		vec3 p2 = ext_persistent_droplets(win_pos, 96.0, rain_intensity * 0.72, 2.0);
		vec3 s1 = ext_continuous_streaks(win_pos, TIME, rain_intensity, car_speed_mps);

		lens_normal = p1.xy + p2.xy * 0.75 + s1.xy * 1.05;
		coverage = clamp(max(max(p1.z, p2.z), s1.z), 0.0, 1.0);

		float steepness = clamp(length(lens_normal), 0.0, 1.0);
		float rim_ring = smoothstep(0.40, 0.88, steepness);
		vec2 n_dir = lens_normal / max(steepness, 0.0001);
		float sky_catch = clamp(dot(n_dir, normalize(vec2(0.2, 0.98))), 0.0, 1.0);
		rim_glint = vec3(0.80, 0.90, 1.0) * pow(sky_catch, 5.0) * rim_ring * 0.12 * rain_intensity;
	}

	ALBEDO = base_albedo * (1.0 - coverage * 0.05) + rim_glint;
	ROUGHNESS = mix(0.28, 0.04, coverage * rain_intensity);
	SPECULAR = mix(0.5, 0.90, coverage * rain_intensity);
	NORMAL = normalize(NORMAL + vec3(lens_normal * 0.20 * rain_intensity, 0.0));
	ALPHA = mix(0.92, 0.98, grazing);
}
