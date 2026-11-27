// Shared water surface waves, PS2 procedural wave quantization, wind capillary slope, and raindrop rings.
// Depends on: lib/math/hash_noise.gdshaderinc

group_uniforms water_detail;
uniform sampler2D water_detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 0.30;
uniform float detail_strength = 0.72;
uniform float detail_normal_strength = 0.0;
uniform float detail_speed = 0.035;
uniform float detail_procedural_mix = 0.0;
group_uniforms;

float water_wave(vec2 p, float t) {
	float w1 = sin(p.x * 2.30 + t * 1.70);
	float w2 = sin(p.y * 1.70 - t * 1.10);
	float w3 = sin((p.x + p.y) * 0.85 + t * 0.55);
	float v = (w1 * 0.45 + w2 * 0.35 + w3 * 0.20) * 0.5 + 0.5;
	return floor(clamp(v, 0.0, 1.0) * 15.0 + 0.5) / 15.0;
}

float water_detail_lum(vec2 p) {
	vec3 c = texture(water_detail_tex, p).rgb;
	float lum = luma_bt601(c);
	return mix(lum, water_wave(p, TIME), clamp(detail_procedural_mix, 0.0, 1.0));
}

vec3 water_detail_sample(vec2 world_xz, vec2 flow) {
	vec2 uv_a = world_xz * detail_scale + flow;
	vec2 uv_b = world_xz * (detail_scale * 1.45) + vec2(0.37, 0.61) - flow * 0.55;
	float a = water_detail_lum(uv_a);
	float b = water_detail_lum(uv_b);
	float lum = mix(a, b, 0.45);
	return vec3(lum, 0.0, 0.0);
}

vec3 water_detail_rgb(vec2 world_xz, vec2 flow) {
	vec2 uv_a = world_xz * detail_scale + flow;
	vec2 uv_b = world_xz * (detail_scale * 1.45) + vec2(0.37, 0.61) - flow * 0.55;
	return mix(texture(water_detail_tex, uv_a).rgb, texture(water_detail_tex, uv_b).rgb, 0.45);
}

vec3 puddle_micro_relief(vec2 xz, bool compute_grad) {
	vec2 p1 = vec2(xz.x * 1.40 + xz.y * 1.05, -xz.x * 1.05 + xz.y * 1.40);
	vec2 p2 = vec2(xz.x * 3.13 - xz.y * 4.87, xz.x * 4.87 + xz.y * 3.13);
	float n1 = value_noise2(p1) - 0.5;
	float n2 = value_noise2(p2) - 0.5;
	float h = n1 * 0.62 + n2 * 0.38;
	if (!compute_grad) {
		return vec3(h, 0.0, 0.0);
	}
	float gx = (value_noise2(p2 + vec2(0.18, 0.0)) - 0.5) - n2;
	float gz = (value_noise2(p2 + vec2(0.0, 0.18)) - 0.5) - n2;
	return vec3(h, gx * 4.2, gz * 4.2);
}

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

vec2 rain_ripple_layer(vec2 uv_world, float scale, vec2 offset, float time, float spawn_prob) {
	vec2 p = uv_world * scale + offset;
	vec2 cell_id = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash12(cell_id);
	float rate = 0.85 + 0.65 * h;
	float t_cycle = time * rate + h * 6.2831;
	float cycle_idx = floor(t_cycle);
	float h_spawn = hash12(cell_id + vec2(cycle_idx * 13.7, cycle_idx * 7.3));
	if (h_spawn > spawn_prob) {
		return vec2(0.0);
	}
	vec2 jitter = (vec2(
		hash12(cell_id + vec2(19.1 + cycle_idx, 5.7)),
		hash12(cell_id + vec2(31.3, 11.9 + cycle_idx))
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
