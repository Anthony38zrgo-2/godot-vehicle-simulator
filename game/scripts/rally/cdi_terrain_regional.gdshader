shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

#include "res://scripts/rally/cdi_terrain_layers.gdshaderinc"

varying vec3 world_point;
varying vec3 world_normal;

// FBM suave de 3 octavas para roturas orgánicas de cobertura y erosión
float fbm3(vec2 p) {
	float v = patch_noise(p) * 0.55;
	v += patch_noise(p * 2.13 + vec2(31.7, 14.3)) * 0.30;
	v += patch_noise(p * 4.71 + vec2(73.1, 52.9)) * 0.15;
	return v;
}

// Ruido de crestas afiladas (Ridged Multifractal) para aristas y fracturas rocosas
float ridge_fbm(vec2 p) {
	float n1 = 1.0 - abs(patch_noise(p) * 2.0 - 1.0);
	n1 = n1 * n1;
	float n2 = 1.0 - abs(patch_noise(p * 2.31 + vec2(19.3, 41.7)) * 2.0 - 1.0);
	n2 = n2 * n2;
	float n3 = 1.0 - abs(patch_noise(p * 5.27 + vec2(73.1, 11.9)) * 2.0 - 1.0);
	n3 = n3 * n3;
	float n4 = 1.0 - abs(patch_noise(p * 11.4 + vec2(5.7, 89.2)) * 2.0 - 1.0);
	return n1 * 0.48 + n2 * 0.28 + n3 * 0.16 + n4 * 0.08;
}

// Campo de altura geológico en espacio mundo (independiente de la cámara)
float rock_height(vec3 p, float steep, float cliff, vec2 slope_dir) {
	vec2 w = vec2(patch_noise(p.xz * 0.0085), patch_noise(p.xz * 0.0085 + vec2(47.2, 19.6))) - 0.5;
	vec2 pw = p.xz + w * 28.0;

	// Crestas y bloques fracturados a escala de montaña (60m -> 6m)
	float crags = ridge_fbm(pw * 0.017) * 1.15 + ridge_fbm(pw * 0.068 + vec2(13.0, 29.0)) * 0.55;

	// Estratos geológicos inclinados tipo cordillera andina (escalonamiento de roca)
	float strata_coord = p.y * 0.105 + p.x * 0.024 - p.z * 0.016 + w.x * 16.0;
	float strata_wave = sin(strata_coord * 3.14159) + 0.45 * sin(strata_coord * 7.3 + w.y * 4.0);

	// Canaletas de erosión / derrubios (scree gullies) alineadas a la caída de la ladera
	float across = dot(pw, vec2(-slope_dir.y, slope_dir.x));
	float along = dot(pw, slope_dir);
	float gullies = ridge_fbm(vec2(across * 0.036, along * 0.009 + p.y * 0.014));

	return crags * (0.55 + 0.85 * cliff)
		+ gullies * (0.70 * steep)
		+ strata_wave * (0.28 * cliff);
}

// Muestreo triplanar de luminancia sobre las capas de roca (14..16) y pedregal (17..18)
float triplanar_rock_luma(vec3 p, vec3 n, float scale, float layer) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(dot(w, vec3(1.0)), 0.001);
	vec2 warp = terrain_warp(p.xz * 0.06) * 0.4;
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
	float detail_fade = 1.0 - smoothstep(2800.0, 11500.0, dist);
	float near_fade = 1.0 - smoothstep(450.0, 2600.0, dist);

	// 1. Pendiente real calibrada al DEM de 55 m (tan_slope: p50=0.35, p75=0.54, p90=0.70)
	float grade = length(base_normal.xz) / max(base_normal.y, 0.05);
	float breakup = fbm3(p.xz * 0.011) - 0.5;
	float micro_breakup = fbm3(p.xz * 0.048) - 0.5;

	float steep = smoothstep(0.20, 0.50, grade + breakup * 0.16);
	float cliff = smoothstep(0.40, 0.74, grade + breakup * 0.18 + micro_breakup * 0.08);
	vec2 slope_dir = normalize(base_normal.xz + vec2(0.0001));

	// 2. Micro-relieve real en espacio mundo (diferencias finitas en X, Y, Z)
	float eps = mix(2.2, 7.5, clamp(dist / 3500.0, 0.0, 1.0));
	float h0 = rock_height(p, steep, cliff, slope_dir);
	float hx = rock_height(p + vec3(eps, 0.0, 0.0), steep, cliff, slope_dir);
	float hy = rock_height(p + vec3(0.0, eps, 0.0), steep, cliff, slope_dir);
	float hz = rock_height(p + vec3(0.0, 0.0, eps), steep, cliff, slope_dir);
	vec3 grad = vec3(hx - h0, hy - h0, hz - h0) / eps;

	// Perturbación fuerte en acantilados y moderada en laderas para romper el aspecto suave
	float bump_strength = mix(1.4, 9.5, steep) * (1.0 + 0.75 * cliff) * detail_fade;
	vec3 detail_normal = normalize(base_normal - grad * bump_strength);

	// 3. Textura triplanar multiescala de roca + pedregal + grano procedural
	float macro_rock = triplanar_rock_luma(p, base_normal, 42.0, 15.0);
	float mid_rock = triplanar_rock_luma(p, base_normal, 11.0, 14.0);
	float scree_tex = triplanar_rock_luma(p, base_normal, 8.5, 17.0);
	float rock_tex = mix(scree_tex, mix(macro_rock, mid_rock, 0.55), cliff);
	float fine_grain = patch_noise(p.xz * 0.24 + vec2(p.y * 0.19, -p.y * 0.13));

	// 4. Iluminación direccional de alto contraste + sombra fría azulada de cordillera
	vec3 sun_dir = normalize(vec3(-0.52, 0.66, -0.54));
	float base_ndotl = clamp(dot(base_normal, sun_dir), 0.0, 1.0);
	float detail_ndotl = clamp(dot(detail_normal, sun_dir), 0.0, 1.0);
	float rel_shade = (detail_ndotl - base_ndotl) * (1.15 + 0.85 * cliff);

	// Oclusión de cavidades/grietas y realce en aristas expuestas
	float cavity = clamp(0.55 + (h0 - 0.85) * 0.42 + (rock_tex - 0.34) * 0.95, 0.48, 1.26);
	float grain_mod = mix(0.88, 1.12, fine_grain);

	// Las caras en sombra viran hacia gris-azulado frío; las aristas al sol se aclaran
	vec3 lit_tint = mix(vec3(0.76, 0.82, 0.92), vec3(1.16, 1.12, 1.06), clamp(0.5 + rel_shade, 0.0, 1.0));
	float rock_factor = clamp((1.0 + rel_shade * 0.85) * cavity * mix(1.0, grain_mod, near_fade * 0.7), 0.42, 1.48);

	// Color mineral de la montaña (con más pizarra oscura en afloramientos rotos y acantilados)
	vec3 slate_dark = vec3(0.11, 0.125, 0.145);
	vec3 scree_gray = vec3(0.24, 0.255, 0.275);
	vec3 terracotta = vec3(0.40, 0.175, 0.125);

	vec3 mountain_color = COLOR.rgb;
	// Afloramientos de pizarra oscura en crestas y filos abruptos
	float crag_outcrop = cliff * smoothstep(0.95, 1.65, h0) * detail_fade;
	mountain_color = mix(mountain_color, slate_dark, crag_outcrop * 0.52);

	// Conos de derrubios gris ceniza frío en faldas medias bajo los picos
	float scree_zone = steep * (1.0 - cliff * 0.55) * smoothstep(0.32, 0.72, fbm3(p.xz * 0.022 + vec2(9.0, 3.0)));
	mountain_color = mix(mountain_color, scree_gray, scree_zone * 0.32 * detail_fade);

	// Cortes erosionados de tierra roja terracota en cárcavas y rupturas de ladera
	float red_scar = smoothstep(0.18, 0.46, grade + breakup * 0.14) * (1.0 - cliff * 0.75)
		* smoothstep(0.54, 0.78, fbm3(p.xz * 0.014 + vec2(61.0, 17.0)));
	mountain_color = mix(mountain_color, terracotta, red_scar * 0.48 * detail_fade);

	// Aplicar sombreado de micro-relieve y tinte frío en sombra
	mountain_color *= lit_tint * mix(1.0, rock_factor, (0.35 + 0.65 * steep) * detail_fade);

	// 5. Pastizal regional con textura real (matas, surcos y suelo mineral asomando)
	float grass_patch = fbm3(p.xz * 0.032) * 0.65 + fine_grain * 0.35;
	vec3 grass_base = grass_macro_color(gis.rgb);
	vec3 grass_textured = mix(grass_base, ground_cover(p, grass_patch), near_fade * 0.80);

	// Micro-relieve suave sobre el pastizal para eliminar el efecto sábana lisa
	float grass_shade = clamp(1.0 + rel_shade * 0.42, 0.72, 1.24);
	float grass_var = mix(0.84, 1.14, grass_patch);
	float daylight = clamp(dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722)) * 1.35 + 0.48, 0.56, 1.12);
	vec3 grass_color = grass_textured * grass_shade * grass_var * daylight;

	// Ruptura orgánica de la cobertura de pastizal por pendiente, cárcavas y mineralidad GIS
	float cover_break = smoothstep(0.16, 0.46, grade + breakup * 0.22 + micro_breakup * 0.12);
	float cover = gis.a * (1.0 - 0.92 * cover_break) * (1.0 - 0.76 * gis.b);
	// Acentuar el borde roto entre pasto y barranco
	cover = smoothstep(0.12, 0.78, cover);

	ALBEDO = mix(mountain_color, grass_color, cover);
}
