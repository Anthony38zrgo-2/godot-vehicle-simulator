shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

#include "res://scripts/rally/cdi_terrain_layers.gdshaderinc"

// Luz dinámica de la escena (RallyVisualSectorStream._update_regional_lighting)
uniform vec3 sun_dir = vec3(-0.52, 0.66, -0.54);
uniform vec3 sun_color = vec3(1.24, 1.17, 1.02);
uniform vec3 ambient_color = vec3(0.48, 0.54, 0.63);
uniform vec3 haze_color = vec3(0.68, 0.76, 0.86);
uniform float sun_gain = 0.82;
uniform float ambient_gain = 0.60;
// Aire fino de 4800 m: bruma ligera y tardía
uniform float haze_start = 2500.0;
uniform float haze_end = 18000.0;
uniform float haze_max = 0.30;

varying vec3 world_point;
varying vec3 world_normal;

float octave_weight(float freq, float fp) {
	return 1.0 - smoothstep(0.20, 0.48, freq * fp);
}

float fbm_aa(vec2 p, float f, float fp) {
	float n1 = mix(0.5, patch_noise(p * f), octave_weight(f, fp));
	float n2 = mix(0.5, patch_noise(p * f * 2.17 + vec2(31.7, 14.3)), octave_weight(f * 2.17, fp));
	float n3 = mix(0.5, patch_noise(p * f * 4.63 + vec2(73.1, 52.9)), octave_weight(f * 4.63, fp));
	return n1 * 0.54 + n2 * 0.30 + n3 * 0.16;
}

float ridge_aa(vec2 p, float f, float fp) {
	float r1 = 1.0 - abs(patch_noise(p * f) * 2.0 - 1.0);
	float r2 = 1.0 - abs(patch_noise(p * f * 2.25 + vec2(19.3, 41.7)) * 2.0 - 1.0);
	float r3 = 1.0 - abs(patch_noise(p * f * 4.95 + vec2(73.1, 11.9)) * 2.0 - 1.0);
	float r4 = 1.0 - abs(patch_noise(p * f * 10.4 + vec2(7.1, 83.4)) * 2.0 - 1.0);
	r1 = mix(r1, r1 * r1, 0.55);
	r2 = mix(r2, r2 * r2, 0.55);
	r3 = mix(r3, r3 * r3, 0.50);
	return mix(0.45, r1, octave_weight(f, fp)) * 0.46
		+ mix(0.45, r2, octave_weight(f * 2.25, fp)) * 0.28
		+ mix(0.45, r3, octave_weight(f * 4.95, fp)) * 0.17
		+ mix(0.45, r4, octave_weight(f * 10.4, fp)) * 0.09;
}

float strata_phase(vec3 p) {
	float warp_low = (patch_noise(p.xz * 0.0052 + vec2(13.0, 37.0)) - 0.5) * 2.6;
	float warp_mid = (patch_noise(p.xz * 0.015 + vec2(p.y * 0.009, -p.y * 0.007)) - 0.5) * 0.95;
	return dot(p, vec3(0.018, 0.026, -0.016)) + warp_low + warp_mid;
}

float geological_strata(vec3 p) {
	float phase = strata_phase(p);
	float fw = max(fwidth(phase), 0.001);
	float b1 = sin(phase * 6.283185) * (1.0 - smoothstep(0.14, 0.42, fw));
	float b2 = sin((phase * 1.83 + 0.5) * 6.283185) * (1.0 - smoothstep(0.14, 0.42, fw * 1.83));
	return b1 * 0.64 + b2 * 0.36;
}

float gully_field(vec2 pw, float py, vec2 slope_dir, float fp) {
	float across = dot(pw, vec2(-slope_dir.y, slope_dir.x));
	float along = dot(pw, slope_dir);
	return ridge_aa(vec2(across * 1.15, along * 0.32 + py * 0.48), 0.025, fp);
}

vec2 warped_xz(vec3 p) {
	return p.xz + vec2(patch_noise(p.xz * 0.0068) - 0.5,
		patch_noise(p.xz * 0.0068 + vec2(47.2, 19.6)) - 0.5) * 32.0;
}

float macro_height(vec3 p, float steep, float cliff, vec2 slope_dir, float fp) {
	vec2 pw = warped_xz(p);
	float crags = ridge_aa(pw, 0.013, fp) * 0.85 + ridge_aa(pw + vec2(17.0, 29.0), 0.038, fp) * 0.45;
	float gullies = gully_field(pw, p.y, slope_dir, fp);
	float step_ = sin(strata_phase(p) * 6.283185) * octave_weight(0.028, fp);
	return crags * (0.52 + 0.72 * cliff) + gullies * (0.58 * steep) + step_ * (0.16 * cliff);
}

float triplanar_luma(vec3 p, vec3 n, float scale, float layer) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(dot(w, vec3(1.0)), 0.001);
	vec2 warp = terrain_warp(p.xz * 0.045) * 0.38;
	vec3 c = palette_layer(p.zy / scale + warp, layer) * w.x
		+ palette_layer(p.xz / scale + warp, layer) * w.y
		+ palette_layer(p.xy / scale + warp, layer) * w.z;
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 p = world_point;
	vec4 gis = grass_coverage(p);
	vec3 base_normal = length(world_normal) > 0.001 ? normalize(world_normal) : normalize(cross(dFdx(p), dFdy(p)));
	if (base_normal.y < 0.0) {
		base_normal = -base_normal;
	}

	float dist = length(VERTEX);
	float xz_fp = max(max(length(dFdx(p.xz)), length(dFdy(p.xz))), 0.25);
	float detail_fade = 1.0 - smoothstep(1600.0, 7200.0, dist);
	float near_fade = 1.0 - smoothstep(400.0, 2300.0, dist);

	float grade = length(base_normal.xz) / max(base_normal.y, 0.05);
	float macro_break = fbm_aa(p.xz, 0.009, xz_fp) - 0.5;
	float mid_break = fbm_aa(p.xz, 0.032, xz_fp) - 0.5;
	float steep = smoothstep(0.19, 0.50, grade + macro_break * 0.15);
	float cliff = smoothstep(0.40, 0.74, grade + macro_break * 0.17 + mid_break * 0.07);
	vec2 slope_dir = normalize(base_normal.xz + vec2(0.0001));

	// --- Micro-relieve 3D (normal perturbada en espacio mundo) ---
	float eps = clamp(xz_fp * 1.7, 1.8, 9.5);
	float h0 = macro_height(p, steep, cliff, slope_dir, xz_fp);
	float hx = macro_height(p + vec3(eps, 0.0, 0.0), steep, cliff, slope_dir, xz_fp);
	float hy = macro_height(p + vec3(0.0, eps, 0.0), steep, cliff, slope_dir, xz_fp);
	float hz = macro_height(p + vec3(0.0, 0.0, eps), steep, cliff, slope_dir, xz_fp);
	vec3 grad = vec3(hx - h0, hy - h0, hz - h0) / eps;
	float bump = mix(0.95, 5.4, steep) * (1.0 + 0.55 * cliff) * detail_fade;
	vec3 n = normalize(base_normal - grad * bump);

	// --- C. Máscara de afloramientos con borde definido ---
	vec2 pw = warped_xz(p);
	float crest = ridge_aa(pw, 0.016, xz_fp);
	float gully = gully_field(pw, p.y, slope_dir, xz_fp);
	// Lenguas de pasto que suben por las canaletas entre crestones
	float t = COLOR.a + (crest - 0.5) * 0.38 + macro_break * 0.22 + mid_break * 0.10
		- smoothstep(0.55, 0.85, gully) * 0.16 * steep + gis.b * 0.12;
	float edge_w = 0.045 + clamp(xz_fp * 0.006, 0.0, 0.18); // borde nítido cerca, suave lejos (sin aliasing)
	float rock_mask = smoothstep(0.50 - edge_w, 0.50 + edge_w, t);
	float scree_mask = smoothstep(0.30, 0.46, t) * (1.0 - rock_mask);

	// --- B. Albedo: roca gris neutra / salmón de COLOR_0 + detalle ---
	float rock_luma = mix(triplanar_luma(p, base_normal, 10.0, 17.0),
		mix(triplanar_luma(p, base_normal, 45.0, 15.0), triplanar_luma(p, base_normal, 13.0, 14.0), 0.55), cliff);
	float rock_detail = clamp(1.0 + (rock_luma - 0.35) * 1.05, 0.72, 1.30);
	float strata = geological_strata(p);
	float cavity = clamp(0.80 + (h0 - 0.58) * 0.30, 0.68, 1.14);
	vec3 rock_albedo = COLOR.rgb * mix(1.0, rock_detail * cavity * (1.0 + strata * 0.10 * cliff), detail_fade);

	vec3 grass_weights = mix(vec3(0.45, 0.12, 0.10), gis.rgb, gis.a);
	float patch_macro = fbm_aa(p.xz, 0.026, xz_fp) * 0.70 + (mid_break + 0.5) * 0.30;
	vec3 grass_albedo = mix(grass_macro_color(grass_weights), ground_cover(p, patch_macro), near_fade * 0.70 * gis.a);
	grass_albedo *= mix(0.90, 1.08, patch_macro);

	// Falda de pedregal: mezcla de suelo mineral y matas sueltas
	vec3 scree_albedo = mix(rock_albedo * vec3(1.08, 1.04, 1.00), grass_albedo * vec3(0.92, 0.86, 0.80), 0.45);
	vec3 albedo = mix(grass_albedo, scree_albedo, scree_mask * 0.85);
	albedo = mix(albedo, rock_albedo, rock_mask);

	// --- A. Iluminación con el sol dinámico (wrap) + cielo ---
	vec3 L = normalize(sun_dir);
	vec3 shade_n = normalize(mix(base_normal, n, mix(0.45, 1.0, rock_mask)));
	float ndl = clamp(dot(shade_n, L) * 0.78 + 0.22, 0.0, 1.0);
	float sky = 0.72 + 0.28 * shade_n.y;
	float occl = mix(1.0, cavity, rock_mask * detail_fade);
	vec3 light = sun_color * (ndl * sun_gain) + ambient_color * (sky * ambient_gain * occl);
	vec3 lit = albedo * light;

	// --- A. Bruma por distancia a cámara, igual para roca y pasto ---
	float haze = smoothstep(haze_start, haze_end, dist) * haze_max;
	ALBEDO = mix(lit, haze_color, haze);
}
