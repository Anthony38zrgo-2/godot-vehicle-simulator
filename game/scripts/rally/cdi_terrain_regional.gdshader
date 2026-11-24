shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

#include "res://scripts/rally/cdi_terrain_layers.gdshaderinc"
#include "res://scripts/rally/cdi_ticlio_snow.gdshaderinc"

// Luz dinámica de la escena (RallyVisualSectorStream._update_regional_lighting)
uniform vec3 sun_dir = vec3(-0.52, 0.66, -0.54);
uniform vec3 sun_color = vec3(1.24, 1.17, 1.02);
uniform vec3 ambient_color = vec3(0.48, 0.54, 0.63);
uniform vec3 haze_color = vec3(0.68, 0.76, 0.86);
uniform float sun_gain = 0.88;
uniform float ambient_gain = 0.56;
// Bruma atmosférica continua con la ladera cercana hacia la cordillera
uniform float haze_start = 450.0;
uniform float haze_end = 14000.0;
uniform float haze_max = 0.36;
uniform float color_saturation = 1.16;

// Acabado PS1 RGB555 + matriz de dithering 4x4 (ps1kit/color.py)
uniform bool psx_quantize_enabled = true;
uniform int psx_color_bits : hint_range(2, 8) = 5;
uniform float psx_dither_strength : hint_range(0.0, 2.0) = 0.35;
uniform float psx_dither_scale : hint_range(1.0, 4.0) = 1.0;

// Geometría imprecisa PS1 (vertex snapping), wobble afín de textura y sombreado Gouraud
// exclusivos para cordilleras y montañas medias/lejanas (Rajuntay Regional DEM).
uniform vec2 psx_snap_resolution = vec2(320.0, 240.0);
uniform float psx_snap_strength : hint_range(0.0, 1.0) = 0.56;
uniform float psx_affine_strength : hint_range(0.0, 1.0) = 0.48;
uniform float psx_gouraud_mix : hint_range(0.0, 1.0) = 0.35;

const float PS1_DITHER_4X4[16] = float[16](
	-4.0,  0.0, -3.0,  1.0,
	 2.0, -2.0,  3.0, -1.0,
	-3.0,  1.0, -4.0,  0.0,
	 3.0, -1.0,  2.0, -2.0
);

vec3 psx_quantize_color(vec3 linear_rgb, vec2 frag_xy) {
	int bits = clamp(psx_color_bits, 2, 8);
	int shift = 8 - bits;
	vec3 srgb = pow(clamp(linear_rgb, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2)) * 255.0;
	if (shift > 0 && psx_dither_strength > 0.0) {
		ivec2 cell = ivec2(floor(frag_xy / max(psx_dither_scale, 1.0)));
		float pattern = PS1_DITHER_4X4[(cell.y & 3) * 4 + (cell.x & 3)];
		float scale = psx_dither_strength * float(1 << shift) / 8.0;
		srgb += vec3(pattern * scale);
	}
	ivec3 q = ivec3(clamp(srgb, vec3(0.0), vec3(255.0))) >> shift;
	vec3 out_srgb;
	if (bits >= 4) {
		ivec3 rep = (q << shift) | (q >> (bits - shift));
		out_srgb = vec3(rep) / 255.0;
	} else {
		float max_lvl = float((1 << bits) - 1);
		out_srgb = vec3(q) / max_lvl;
	}
	return pow(clamp(out_srgb, vec3(0.0), vec3(1.0)), vec3(2.2));
}

varying vec3 world_point;
varying vec3 world_normal;
varying vec3 v_world_affine;
varying float v_affine_w;
varying float v_gouraud_ndl;
varying float v_gouraud_sky;

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
	r1 = mix(r1, r1 * r1, 0.38);
	r2 = mix(r2, r2 * r2, 0.38);
	r3 = mix(r3, r3 * r3, 0.32);
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
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = MODEL_NORMAL_MATRIX * NORMAL;
	world_point = wp;
	world_normal = wn;

	// 1. PS1 GTE integer vertex snapping (solo cordillera/montañas medias-lejanas)
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (psx_snap_strength > 0.001 && clip.w > 0.25) {
		vec2 ndc = clip.xy / clip.w;
		vec2 grid = max(psx_snap_resolution, vec2(32.0)) * 0.5;
		vec2 snapped = floor(ndc * grid + 0.5) / grid;
		clip.xy = mix(ndc, snapped, psx_snap_strength) * clip.w;
	}
	POSITION = clip;

	// 2. Coordenadas en mundo multiplicadas por w para mapeo afín PS1 (texture wobble)
	float w_eff = max(clip.w, 8.0);
	v_world_affine = wp * w_eff;
	v_affine_w = w_eff;

	// 3. Iluminación Gouraud por vértice estilo PS1
	vec3 n_v = length(wn) > 0.001 ? normalize(wn) : vec3(0.0, 1.0, 0.0);
	if (n_v.y < 0.0) {
		n_v = -n_v;
	}
	vec3 L = normalize(sun_dir);
	v_gouraud_ndl = clamp(dot(n_v, L) * 0.72 + 0.28, 0.0, 1.0);
	v_gouraud_sky = 0.72 + 0.28 * n_v.y;
}

void fragment() {
	vec3 p = world_point;
	vec3 p_tex = p;
	if (psx_affine_strength > 0.001) {
		vec3 wp_affine = v_world_affine / max(v_affine_w, 0.001);
		vec3 affine_delta = clamp(wp_affine - p, vec3(-45.0), vec3(45.0));
		p_tex = p + affine_delta * psx_affine_strength;
	}
	vec4 gis = grass_coverage(p);
	vec3 base_normal = length(world_normal) > 0.001 ? normalize(world_normal) : normalize(cross(dFdx(p), dFdy(p)));
	if (base_normal.y < 0.0) {
		base_normal = -base_normal;
	}

	float dist = length(VERTEX);
	float xz_fp = max(max(length(dFdx(p.xz)), length(dFdy(p.xz))), 0.25);
	float detail_fade = 1.0 - smoothstep(1350.0, 6000.0, dist);
	float near_fade = 1.0 - smoothstep(400.0, 2300.0, dist);

	float grade = length(base_normal.xz) / max(base_normal.y, 0.05);
	float macro_break = fbm_aa(p_tex.xz, 0.009, xz_fp) - 0.5;
	float mid_break = fbm_aa(p_tex.xz, 0.032, xz_fp) - 0.5;
	float steep = smoothstep(0.19, 0.50, grade + macro_break * 0.15);
	float cliff = smoothstep(0.40, 0.74, grade + macro_break * 0.17 + mid_break * 0.07);
	vec2 slope_dir = normalize(base_normal.xz + vec2(0.0001));

	// --- Micro-relieve 3D (normal perturbada en espacio mundo) ---
	float eps = clamp(xz_fp * 1.7, 1.8, 9.5);
	float h0 = macro_height(p_tex, steep, cliff, slope_dir, xz_fp);
	float hx = macro_height(p_tex + vec3(eps, 0.0, 0.0), steep, cliff, slope_dir, xz_fp);
	float hy = macro_height(p_tex + vec3(0.0, eps, 0.0), steep, cliff, slope_dir, xz_fp);
	float hz = macro_height(p_tex + vec3(0.0, 0.0, eps), steep, cliff, slope_dir, xz_fp);
	vec3 grad = vec3(hx - h0, hy - h0, hz - h0) / eps;
	float bump = mix(0.75, 3.9, steep) * (1.0 + 0.42 * cliff) * detail_fade * (1.0 - psx_gouraud_mix * 0.55);
	vec3 n = normalize(base_normal - grad * bump);

	// --- C. Máscara de afloramientos con borde definido ---
	vec2 pw = warped_xz(p_tex);
	float crest = ridge_aa(pw, 0.016, xz_fp);
	float gully = gully_field(pw, p_tex.y, slope_dir, xz_fp);
	// Lenguas de pasto que suben por las canaletas entre crestones
	float t = COLOR.a + (crest - 0.5) * 0.38 + macro_break * 0.22 + mid_break * 0.10
		- smoothstep(0.55, 0.85, gully) * 0.16 * steep + gis.b * 0.12;
	float edge_w = 0.075 + clamp(xz_fp * 0.006, 0.0, 0.18); // borde suave pero definido
	float rock_mask = smoothstep(0.50 - edge_w, 0.50 + edge_w, t);
	float scree_mask = smoothstep(0.30, 0.46, t) * (1.0 - rock_mask);

	// --- B. Albedo: roca gris neutra / salmón de COLOR_0 + detalle (muestreo afín PS1) ---
	float rock_luma = mix(triplanar_luma(p_tex, base_normal, 10.0, 17.0),
		mix(triplanar_luma(p_tex, base_normal, 45.0, 15.0), triplanar_luma(p_tex, base_normal, 13.0, 14.0), 0.55), cliff);
	float rock_detail = clamp(1.0 + (rock_luma - 0.35) * 0.82, 0.78, 1.22);
	float strata = geological_strata(p_tex);
	float cavity = clamp(0.84 + (h0 - 0.58) * 0.24, 0.74, 1.12);
	vec3 strata_tint = mix(vec3(0.95, 0.97, 1.02), vec3(1.07, 0.97, 0.92), strata * 0.5 + 0.5);
	vec3 rock_albedo = COLOR.rgb * mix(vec3(1.0), strata_tint * rock_detail * cavity * (1.0 + strata * 0.08 * cliff), detail_fade);

	vec3 grass_weights = mix(vec3(0.45, 0.12, 0.10), gis.rgb, gis.a);
	float patch_macro = fbm_aa(p_tex.xz, 0.026, xz_fp) * 0.70 + (mid_break + 0.5) * 0.30;
	vec3 grass_albedo = mix(grass_macro_color(grass_weights), ground_cover(p_tex, patch_macro), near_fade * 0.70 * gis.a);
	grass_albedo *= mix(0.90, 1.08, patch_macro);

	// Falda de pedregal: mezcla de suelo mineral y matas sueltas
	vec3 scree_albedo = mix(rock_albedo * vec3(1.08, 1.04, 1.00), grass_albedo * vec3(0.92, 0.86, 0.80), 0.45);
	vec3 albedo = mix(grass_albedo, scree_albedo, scree_mask * 0.85);
	albedo = mix(albedo, rock_albedo, rock_mask);
	float albedo_luma = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	albedo = clamp(mix(vec3(albedo_luma), albedo, color_saturation), 0.0, 1.0);

	albedo = ticlio_winter_ground(albedo, p_tex, base_normal, dist, 0.0);

	// --- A. Iluminación con el sol dinámico (wrap + Gouraud PS1) + cielo ---
	vec3 L = normalize(sun_dir);
	vec3 shade_n = normalize(mix(base_normal, n, mix(0.35, 0.88, rock_mask)));
	float ndl = mix(clamp(dot(shade_n, L) * 0.72 + 0.28, 0.0, 1.0), v_gouraud_ndl, psx_gouraud_mix);
	float sky = mix(0.72 + 0.28 * shade_n.y, v_gouraud_sky, psx_gouraud_mix);
	float occl = mix(1.0, cavity, rock_mask * detail_fade);
	vec3 light = sun_color * (ndl * sun_gain) + ambient_color * (sky * ambient_gain * occl);
	vec3 lit = albedo * light;

	// --- A. Bruma por distancia a cámara, igual para roca y pasto ---
	float haze = smoothstep(haze_start, haze_end, dist) * haze_max;
	vec3 final_color = mix(lit, haze_color, haze);
	if (psx_quantize_enabled) {
		final_color = psx_quantize_color(final_color, FRAGCOORD.xy);
	}
	ALBEDO = final_color;
}
