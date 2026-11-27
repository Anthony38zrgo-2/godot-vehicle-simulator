// Atomic 1D/2D/3D hash and value/FBM/ridge noise utilities.
// Pure functions only (no uniforms), safe for spatial, sky, and canvas_item shaders.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	return vec2(
		hash12(p + vec2(13.71, 47.29)),
		hash12(p + vec2(71.13, 29.83))
	);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float hash21_sin(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float value_noise2_sin(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21_sin(i), hash21_sin(i + vec2(1.0, 0.0)), u.x),
		mix(hash21_sin(i + vec2(0.0, 1.0)), hash21_sin(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float value_noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 weight = smoothstep(vec3(0.0), vec3(1.0), fract(p));
	vec4 lower = vec4(
		hash13(cell),
		hash13(cell + vec3(1.0, 0.0, 0.0)),
		hash13(cell + vec3(0.0, 1.0, 0.0)),
		hash13(cell + vec3(1.0, 1.0, 0.0))
	);
	cell.z += 1.0;
	vec4 upper = vec4(
		hash13(cell),
		hash13(cell + vec3(1.0, 0.0, 0.0)),
		hash13(cell + vec3(0.0, 1.0, 0.0)),
		hash13(cell + vec3(1.0, 1.0, 0.0))
	);
	vec4 corners = mix(lower, upper, weight.z);
	return mix(mix(corners.x, corners.y, weight.x), mix(corners.z, corners.w, weight.x), weight.y);
}

float noise_octave_weight(float freq, float fp) {
	return 1.0 - smoothstep(0.20, 0.48, freq * fp);
}

float fbm_aa(vec2 p, float f, float fp) {
	float n1 = mix(0.5, value_noise2_sin(p * f), noise_octave_weight(f, fp));
	float n2 = mix(0.5, value_noise2_sin(p * f * 2.17 + vec2(31.7, 14.3)), noise_octave_weight(f * 2.17, fp));
	float n3 = mix(0.5, value_noise2_sin(p * f * 4.63 + vec2(73.1, 52.9)), noise_octave_weight(f * 4.63, fp));
	return n1 * 0.54 + n2 * 0.30 + n3 * 0.16;
}

float ridge_aa(vec2 p, float f, float fp) {
	float r1 = 1.0 - abs(value_noise2_sin(p * f) * 2.0 - 1.0);
	float r2 = 1.0 - abs(value_noise2_sin(p * f * 2.25 + vec2(19.3, 41.7)) * 2.0 - 1.0);
	float r3 = 1.0 - abs(value_noise2_sin(p * f * 4.95 + vec2(73.1, 11.9)) * 2.0 - 1.0);
	float r4 = 1.0 - abs(value_noise2_sin(p * f * 10.4 + vec2(7.1, 83.4)) * 2.0 - 1.0);
	r1 = mix(r1, r1 * r1, 0.38);
	r2 = mix(r2, r2 * r2, 0.38);
	r3 = mix(r3, r3 * r3, 0.32);
	return mix(0.45, r1, noise_octave_weight(f, fp)) * 0.46
		+ mix(0.45, r2, noise_octave_weight(f * 2.25, fp)) * 0.28
		+ mix(0.45, r3, noise_octave_weight(f * 4.95, fp)) * 0.17
		+ mix(0.45, r4, noise_octave_weight(f * 10.4, fp)) * 0.09;
}

float luma_rec709(vec3 rgb) {
	return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

float luma_bt601(vec3 rgb) {
	return dot(rgb, vec3(0.299, 0.587, 0.114));
}
