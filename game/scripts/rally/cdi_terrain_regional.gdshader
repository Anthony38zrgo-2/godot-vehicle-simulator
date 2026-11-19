shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

#include "res://scripts/rally/cdi_terrain_layers.gdshaderinc"

varying vec3 world_point;
varying vec3 world_normal;

// Filtro anti-aliasing por octava según el tamaño del píxel en el plano XZ
float octave_weight(float freq, float uv_footprint) {
	return 1.0 - smoothstep(0.20, 0.48, freq * uv_footprint);
}

// FBM suave con atenuación automática de altas frecuencias
float fbm_aa(vec2 p, float base_freq, float fp) {
	float w1 = octave_weight(base_freq, fp);
	float w2 = octave_weight(base_freq * 2.17, fp);
	float w3 = octave_weight(base_freq * 4.63, fp);
	float n1 = mix(0.5, patch_noise(p * base_freq), w1);
	float n2 = mix(0.5, patch_noise(p * (base_freq * 2.17) + vec2(31.7, 14.3)), w2);
	float n3 = mix(0.5, patch_noise(p * (base_freq * 4.63) + vec2(73.1, 52.9)), w3);
	return n1 * 0.54 + n2 * 0.30 + n3 * 0.16;
}

// Crestas afiladas intermedias (r vs r*r al 55%) con 4 octavas filtradas por AA
float ridge_aa(vec2 p, float base_freq, float fp) {
	float w1 = octave_weight(base_freq, fp);
	float w2 = octave_weight(base_freq * 2.25, fp);
	float w3 = octave_weight(base_freq * 4.95, fp);
	float w4 = octave_weight(base_freq * 10.4, fp);

	float r1 = 1.0 - abs(patch_noise(p * base_freq) * 2.0 - 1.0);
	r1 = mix(r1, r1 * r1, 0.55);
	float r2 = 1.0 - abs(patch_noise(p * (base_freq * 2.25) + vec2(19.3, 41.7)) * 2.0 - 1.0);
	r2 = mix(r2, r2 * r2, 0.55);
	float r3 = 1.0 - abs(patch_noise(p * (base_freq * 4.95) + vec2(73.1, 11.9)) * 2.0 - 1.0);
	r3 = mix(r3, r3 * r3, 0.50);
	float r4 = 1.0 - abs(patch_noise(p * (base_freq * 10.4) + vec2(7.1, 83.4)) * 2.0 - 1.0);

	return mix(0.45, r1, w1) * 0.46
		+ mix(0.45, r2, w2) * 0.28
		+ mix(0.45, r3, w3) * 0.17
		+ mix(0.45, r4, w4) * 0.09;
}

// Estratos geológicos plegados e inclinados en 3D (sin anillos concéntricos de cebra)
float geological_strata(vec3 p) {
	float warp_low = (patch_noise(p.xz * 0.0052 + vec2(13.0, 37.0)) - 0.5) * 2.6;
	float warp_mid = (patch_noise(p.xz * 0.015 + vec2(p.y * 0.009, -p.y * 0.007)) - 0.5) * 0.95;
	// Plano fuertemente buzado en X y Z para cortar las laderas en diagonal natural
	float phase = dot(p, vec3(0.018, 0.026, -0.016)) + warp_low + warp_mid;
	float fw = max(fwidth(phase), 0.001);

	float atten1 = 1.0 - smoothstep(0.14, 0.42, fw);
	float atten2 = 1.0 - smoothstep(0.14, 0.42, fw * 1.83);
	float band1 = sin(phase * 6.283185) * atten1;
	float band2 = sin((phase * 1.83 + 0.5) * 6.283185) * atten2;
	return band1 * 0.64 + band2 * 0.36;
}

// Campo de altura geológico 3D con rugosidad marcada pero filtrada por footprint
float macro_structure_height(vec3 p, float steep, float cliff, vec2 slope_dir, float fp) {
	vec2 warp = vec2(
		patch_noise(p.xz * 0.0068) - 0.5,
		patch_noise(p.xz * 0.0068 + vec2(47.2, 19.6)) - 0.5
	) * 32.0;
	vec2 pw = p.xz + warp;

	// Espolones, aristas y bloques fracturados (de 80 m a 8 m)
	float crags = ridge_aa(pw, 0.013, fp) * 0.85
		+ ridge_aa(pw + vec2(17.0, 29.0), 0.038, fp) * 0.45;

	// Canaletas de erosión y derrubios alineadas con la caída de la ladera
	float across = dot(pw, vec2(-slope_dir.y, slope_dir.x));
	float along = dot(pw, slope_dir);
	float gullies = ridge_aa(vec2(across * 1.15, along * 0.32 + p.y * 0.48), 0.025, fp);

	// Escalonamiento físico moderado de los estratos inclinados
	float strata_step = sin(dot(p, vec3(0.018, 0.026, -0.016)) * 6.283185 + warp.x * 0.12)
		* octave_weight(0.028, fp);

	return crags * (0.52 + 0.72 * cliff)
		+ gullies * (0.58 * steep)
		+ strata_step * (0.16 * cliff);
}

// Muestreo triplanar filtrado por los mipmaps anisotrópicos del GPU
float triplanar_rock_luma(vec3 p, vec3 n, float scale, float layer) {
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

	vec3 base_normal = length(world_normal) > 0.001
		? normalize(world_normal)
		: normalize(cross(dFdx(p), dFdy(p)));
	if (base_normal.y < 0.0) {
		base_normal = -base_normal;
	}

	float dist = length(VERTEX);
	float xz_fp = max(max(length(dFdx(p.xz)), length(dFdy(p.xz))), 0.25);
	float detail_fade = 1.0 - smoothstep(1600.0, 7200.0, dist);
	float near_fade = 1.0 - smoothstep(400.0, 2300.0, dist);

	// 1. Pendiente real calibrada al DEM de 55 m (tan_slope: p50=0.35, p75=0.54, p90=0.70)
	float grade = length(base_normal.xz) / max(base_normal.y, 0.05);
	float macro_break = fbm_aa(p.xz, 0.009, xz_fp) - 0.5;
	float mid_break = fbm_aa(p.xz, 0.032, xz_fp) - 0.5;

	float steep = smoothstep(0.19, 0.50, grade + macro_break * 0.15);
	float cliff = smoothstep(0.40, 0.74, grade + macro_break * 0.17 + mid_break * 0.07);
	vec2 slope_dir = normalize(base_normal.xz + vec2(0.0001));

	// 2. Micro-relieve 3D en espacio mundo (hx, hy, hz) con paso adaptativo y rugosidad intermedia
	float eps = clamp(xz_fp * 1.7, 1.8, 9.5);
	float h0 = macro_structure_height(p, steep, cliff, slope_dir, xz_fp);
	float hx = macro_structure_height(p + vec3(eps, 0.0, 0.0), steep, cliff, slope_dir, xz_fp);
	float hy = macro_structure_height(p + vec3(0.0, eps, 0.0), steep, cliff, slope_dir, xz_fp);
	float hz = macro_structure_height(p + vec3(0.0, 0.0, eps), steep, cliff, slope_dir, xz_fp);
	vec3 grad = vec3(hx - h0, hy - h0, hz - h0) / eps;

	// Fuerza intermedia (entre 2.4 y 9.5 -> 5.4 con refuerzo en acantilados)
	float bump_strength = mix(0.95, 5.4, steep) * (1.0 + 0.55 * cliff) * detail_fade;
	vec3 detail_normal = normalize(base_normal - grad * bump_strength);

	// 3. Textura triplanar multiescala de roca + pedregal + estratos plegados
	float macro_rock = triplanar_rock_luma(p, base_normal, 45.0, 15.0);
	float mid_rock = triplanar_rock_luma(p, base_normal, 13.0, 14.0);
	float scree_tex = triplanar_rock_luma(p, base_normal, 10.0, 17.0);
	float rock_luma = mix(scree_tex, mix(macro_rock, mid_rock, 0.55), cliff);
	float rock_detail = clamp(1.0 + (rock_luma - 0.35) * 1.05, 0.72, 1.30);

	float strata = geological_strata(p);
	float strata_mod = 1.0 + strata * (0.11 * cliff * detail_fade);

	// 4. Iluminación direccional con definición geográfica marcada pero sin quemar a negro
	vec3 sun_dir = normalize(vec3(-0.52, 0.66, -0.54));
	float base_light = clamp(dot(base_normal, sun_dir) * 0.72 + 0.28, 0.0, 1.0);
	float detail_light = clamp(dot(detail_normal, sun_dir) * 0.72 + 0.28, 0.0, 1.0);
	float rel_light = clamp((detail_light - base_light) * (1.55 + 0.65 * cliff), -0.38, 0.42);

	// Oclusión de grietas/quebradas y realce de aristas rocosas
	float cavity = clamp(0.68 + (h0 - 0.58) * 0.38 + (rock_luma - 0.35) * 0.45, 0.64, 1.20);
	vec3 sky_tint = mix(vec3(0.83, 0.89, 0.98), vec3(1.11, 1.08, 1.03), clamp(0.5 + rel_light * 1.6, 0.0, 1.0));

	// 5. Variación mineral definida (pizarra oscura, derrubios ceniza y terracota) preservando la bruma
	vec3 mountain_color = COLOR.rgb;
	float base_luma = max(dot(mountain_color, vec3(0.2126, 0.7152, 0.0722)), 0.08);

	// Afloramientos de pizarra gris-azulada oscura en crestas y filos
	vec3 slate_target = base_luma * vec3(0.62, 0.67, 0.76);
	float crag_outcrop = cliff * smoothstep(0.62, 1.15, h0) * detail_fade;
	mountain_color = mix(mountain_color, slate_target, crag_outcrop * 0.42);

	// Conos de derrubios gris ceniza en faldas medias
	vec3 scree_target = base_luma * vec3(0.86, 0.90, 0.96);
	float scree_zone = steep * (1.0 - cliff * 0.55) * smoothstep(0.36, 0.70, fbm_aa(p.xz + vec2(9.0, 3.0), 0.018, xz_fp));
	mountain_color = mix(mountain_color, scree_target, scree_zone * 0.28 * detail_fade);

	// Cortes erosionados de tierra roja terracota / óxido en laderas medias y estratos
	vec3 terracotta_target = base_luma * vec3(1.34, 0.74, 0.58);
	float red_scar = smoothstep(0.18, 0.46, grade + macro_break * 0.14) * (1.0 - cliff * 0.65)
		* smoothstep(0.48, 0.76, fbm_aa(p.xz + vec2(61.0, 17.0), 0.013, xz_fp) + strata * 0.15);
	mountain_color = mix(mountain_color, terracotta_target, red_scar * 0.38 * detail_fade);

	float total_rock_mod = clamp((1.0 + rel_light) * cavity * rock_detail * strata_mod, 0.56, 1.38);
	mountain_color *= mix(vec3(1.0), sky_tint * total_rock_mod, (0.35 + 0.65 * steep) * detail_fade);

	// 6. Pastizal con textura, relieve de lomas y ruptura definida sobre barrancos
	float patch_macro = fbm_aa(p.xz, 0.026, xz_fp) * 0.70 + (mid_break + 0.5) * 0.30;
	vec3 grass_base = grass_macro_color(gis.rgb);
	vec3 grass_near = ground_cover(p, patch_macro);
	vec3 grass_textured = mix(grass_base, grass_near, near_fade * 0.75);

	float daylight = clamp(dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722)) * 1.34 + 0.49, 0.56, 1.12);
	float grass_relief = clamp(1.0 + rel_light * 0.45 + (patch_macro - 0.5) * 0.22 * detail_fade, 0.78, 1.20);
	vec3 grass_color = grass_textured * daylight * grass_relief;

	// Falda de transición de pedregal y ruptura orgánica entre pasto y roca
	vec3 talus_color = mix(mountain_color, grass_color * vec3(0.95, 0.88, 0.83), 0.35);
	float talus_zone = smoothstep(0.14, 0.32, grade + macro_break * 0.14) * (1.0 - smoothstep(0.36, 0.56, grade + macro_break * 0.14));
	mountain_color = mix(mountain_color, talus_color, talus_zone * 0.32 * detail_fade);

	float slope_fade = smoothstep(0.17, 0.46, grade + macro_break * 0.18 + mid_break * 0.08);
	float cover = gis.a * (1.0 - 0.91 * slope_fade) * (1.0 - 0.75 * gis.b);
	cover = smoothstep(0.09, 0.82, cover);

	ALBEDO = mix(mountain_color, grass_color, cover);
}
