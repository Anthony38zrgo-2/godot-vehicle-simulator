// Shared raindrop optical fields (persistent beads & sliding streaks with trails).
// Depends on: lib/math/hash_noise.gdshaderinc, lib/math/coordinates.gdshaderinc

vec3 glass_beads_2d(vec2 uv, float scale, float density, float seed) {
	vec2 p = uv * scale + vec2(seed * 17.3, seed * 31.7);
	vec2 id = floor(p);
	vec2 f = fract(p) - 0.5;
	if (hash12(id + seed) > density) {
		return vec3(0.0);
	}
	vec2 c = (vec2(hash12(id + seed + 3.1), hash12(id + seed + 7.7)) - 0.5) * 0.5;
	float r = mix(0.14, 0.30, hash12(id + seed + 11.3));
	vec2 d = (f - c) / r;
	float m = 1.0 - smoothstep(0.80, 1.0, length(d));
	return vec3(-d * m, m);
}

vec3 glass_slider_trails_2d(vec2 uv, float scale, float density, float seed, float t, float p_slide_dir) {
	vec2 p = vec2(uv.x * scale + seed * 13.1, uv.y * scale * 0.45 + seed * 5.7);
	vec2 id = floor(p);
	vec2 f = fract(p);
	if (hash12(id + seed) > density) {
		return vec3(0.0);
	}
	float h2 = hash12(id + seed + 9.1);
	float h3 = hash12(id + seed + 21.7);

	float raw = fract(h2 + t * mix(0.6, 1.4, h3));
	float life = sin(raw * PI);
	float phase = clamp(raw + 0.04 * sin(raw * 18.85 + h3 * 6.28), 0.0, 1.0);
	float dir = (p_slide_dir >= 0.0) ? 1.0 : -1.0;
	float py = (dir > 0.0) ? phase : 1.0 - phase;
	float px = mix(0.25, 0.75, hash12(id + seed + 4.3)) + 0.04 * sin(phase * 20.0 + h2 * 6.28);
	float rr = mix(0.10, 0.16, h3);

	vec2 d = vec2((f.x - px) / rr, (f.y - py) / (rr * 0.45));
	float drop_m = 1.0 - smoothstep(0.80, 1.0, length(d));

	float behind = (py - f.y) * dir;
	float avail = (dir > 0.0) ? py : 1.0 - py;
	float trail_len = max(min(avail, 0.55), 0.01);
	float tx = (f.x - px - 0.025 * sin(f.y * 16.0 + h2 * 6.28)) / (rr * 0.28);
	float trail_m = (1.0 - smoothstep(0.6, 1.0, abs(tx)))
		* step(0.0, behind)
		* (1.0 - clamp(behind / trail_len, 0.0, 1.0))
		* 0.55;

	vec2 off = -d * drop_m + vec2(tx * 0.25, 0.0) * trail_m;
	float mask = max(drop_m, trail_m) * life;
	return vec3(off * life, mask);
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
