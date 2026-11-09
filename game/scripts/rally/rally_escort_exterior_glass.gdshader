shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;

uniform sampler2D glass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool cracked = false;
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float car_speed_mps : hint_range(0.0, 80.0) = 0.0;
uniform float rain_scroll = 0.0;

varying vec3 v_local_pos;
varying vec3 v_local_normal;

float hash12(vec2 p) {
	vec2 q = fract(vec2(
		p.x * 0.443897 + p.y * 0.129731,
		p.y * 0.408327 - p.x * 0.173891
	));
	q += dot(q, q.yx + vec2(37.19, 19.73));
	return fract((q.x + q.y) * q.x * 23.17);
}

vec2 hash22(vec2 p) {
	return vec2(
		hash12(p + vec2(13.71, 47.29)),
		hash12(p + vec2(71.13, 29.83))
	);
}

vec2 rotate2d(vec2 p, float cs, float sn) {
	return vec2(p.x * cs - p.y * sn, p.x * sn + p.y * cs);
}

vec3 ext_persistent_droplets(vec2 pos_m, float scale, float density, float cs, float sn, float seed) {
	if (density <= 0.005) {
		return vec3(0.0);
	}
	vec2 rpos = rotate2d(pos_m, cs, sn);
	rpos += 0.014 * sin(rpos.yx * 11.0 + vec2(seed * 2.1, seed * 4.7));

	vec2 p = rpos * scale + vec2(seed * 19.3, seed * 37.1);
	vec2 cell = floor(p);
	vec2 local = fract(p) - 0.5;

	float prob = hash12(cell + vec2(seed * 7.3, seed * 13.9));
	if (prob > density) {
		return vec3(0.0);
	}

	vec2 rnd = hash22(cell + vec2(seed * 31.4, seed * 9.1));
	vec2 center = (rnd - 0.5) * 0.52;
	vec2 delta = rotate2d(local - center, cs, -sn);
	delta.y *= 0.88;

	float base_rad = mix(0.11, 0.20, hash12(cell + vec2(seed * 11.2, seed * 5.7)));
	float threshold_fade = clamp((density - prob) / 0.14, 0.0, 1.0);
	float radius = base_rad * threshold_fade;
	float dist = length(delta);
	if (dist >= radius) {
		return vec3(0.0);
	}

	float r = dist / max(radius, 0.0001);
	float lens_curve = r * (0.35 + 0.65 * r * r);
	vec2 dir = delta / max(dist, 0.0001);
	vec2 normal_2d = dir * lens_curve * threshold_fade;
	float coverage = (1.0 - smoothstep(0.78, 1.0, r)) * threshold_fade;
	return vec3(normal_2d, coverage);
}

vec3 ext_sliding_droplets(vec2 pos_m, float scale, float scroll, float density, float speed_norm, float cs, float sn, float seed) {
	if (density <= 0.005) {
		return vec3(0.0);
	}

	vec2 rpos = rotate2d(pos_m, cs, sn);
	rpos += 0.016 * sin(rpos.yx * 9.5 + vec2(seed * 3.7, seed * 6.1));

	vec2 p = rpos * scale + vec2(seed * 23.7, seed * 41.3);
	vec2 scroll_dir = rotate2d(vec2(0.0, 1.0), cs, sn);
	p -= scroll_dir * scroll;

	vec2 cell = floor(p);
	vec2 local = fract(p) - 0.5;

	float prob = hash12(cell + vec2(seed * 17.1, seed * 8.9));
	if (prob > density) {
		return vec3(0.0);
	}

	vec2 rnd = hash22(cell + vec2(seed * 14.3, seed * 27.6));
	vec2 center = (rnd - 0.5) * 0.40;
	vec2 delta = rotate2d(local - center, cs, -sn);

	float base_rad = mix(0.11, 0.18, hash12(cell + vec2(seed * 2.3, seed * 19.8)));
	float threshold_fade = clamp((density - prob) / 0.14, 0.0, 1.0);
	float radius = base_rad * threshold_fade;

	float trail_stretch = (delta.y < 0.0) ? mix(0.84, 0.72, clamp(speed_norm, 0.0, 1.0)) : 1.0;
	float trail_taper = (delta.y < 0.0) ? (1.0 + clamp(-delta.y / max(radius * 1.35, 0.001), 0.0, 1.0) * 0.45) : 1.0;
	vec2 shaped = vec2(delta.x * trail_taper, delta.y * trail_stretch);

	float dist = length(shaped);
	if (dist >= radius) {
		return vec3(0.0);
	}

	float r = dist / max(radius, 0.0001);
	float lens_curve = r * (0.35 + 0.65 * r * r);
	vec2 dir = shaped / max(dist, 0.0001);
	vec2 normal_2d = dir * lens_curve * threshold_fade;
	float coverage = (1.0 - smoothstep(0.76, 1.0, r)) * threshold_fade;
	return vec3(normal_2d, coverage);
}

void vertex() {
	v_local_pos = VERTEX;
	v_local_normal = NORMAL;
}

void fragment() {
	vec4 glass = texture(glass_texture, UV);

	// Distinguish window glass from painted body frames, pillars, and chrome trim.
	// Glass alpha in original textures is ~0.26 (<= 0.62 at antialiased seam).
	// Body pillars, painted frames, and chrome trim have alpha >= 0.80 (0.875 - 1.0).
	float is_frame = smoothstep(0.60, 0.80, glass.a);

	float grazing = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 3.0);
	vec3 tint = vec3(0.035, 0.046, 0.052);
	vec3 glass_albedo = tint + glass.rgb * (cracked ? 0.35 : 0.07) * glass.a;
	vec3 frame_albedo = glass.rgb;
	vec3 base_albedo = mix(glass_albedo, frame_albedo, is_frame);

	float coverage = 0.0;
	vec2 lens_normal = vec2(0.0);
	vec3 rim_glint = vec3(0.0);

	if (rain_intensity > 0.005) {
		vec2 win_pos = (abs(v_local_normal.x) > 0.45)
			? vec2(v_local_pos.z, v_local_pos.y)
			: vec2(v_local_pos.x, v_local_pos.y * 0.61 + abs(v_local_pos.z) * 0.79);

		float speed_norm = clamp(car_speed_mps / 28.0, 0.0, 1.5);
		float total_scroll = rain_scroll * 14.0 + TIME * 0.45;

		vec3 p1 = ext_persistent_droplets(win_pos, 50.0, rain_intensity * 0.84, 0.9455, 0.3256, 1.0);
		vec3 p2 = ext_persistent_droplets(win_pos, 88.0, rain_intensity * 0.72, 0.8572, -0.5150, 2.0);
		vec3 s1 = ext_sliding_droplets(win_pos, 42.0, total_scroll, rain_intensity * 0.76, speed_norm, 0.9816, 0.1908, 3.0);
		vec3 s2 = ext_sliding_droplets(win_pos, 66.0, total_scroll * 1.28, rain_intensity * 0.68, speed_norm, 0.9563, -0.2924, 4.0);

		lens_normal = (p1.xy + p2.xy * 0.75 + s1.xy * 0.90 + s2.xy * 0.70) * (1.0 - is_frame);
		coverage = clamp(max(max(p1.z, p2.z), max(s1.z, s2.z)), 0.0, 1.0) * (1.0 - is_frame);

		float steepness = clamp(length(lens_normal), 0.0, 1.0);
		float rim_ring = smoothstep(0.40, 0.88, steepness);
		vec2 n_dir = lens_normal / max(steepness, 0.0001);
		float sky_catch = clamp(dot(n_dir, normalize(vec2(0.2, 0.98))), 0.0, 1.0);
		rim_glint = vec3(0.80, 0.90, 1.0) * pow(sky_catch, 5.0) * rim_ring * 0.12 * rain_intensity * (1.0 - is_frame);
	}

	ALBEDO = base_albedo * (1.0 - coverage * 0.05) + rim_glint;
	float glass_roughness = mix(0.28, 0.04, coverage * rain_intensity);
	ROUGHNESS = mix(glass_roughness, 0.35, is_frame);
	SPECULAR = mix(mix(0.5, 0.90, coverage * rain_intensity), 0.5, is_frame);
	NORMAL = normalize(NORMAL + vec3(lens_normal * 0.20 * rain_intensity, 0.0));
	float glass_alpha = mix(0.92, 0.98, grazing);
	ALPHA = mix(glass_alpha, 1.0, is_frame);
}
