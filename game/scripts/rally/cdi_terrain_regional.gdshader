shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

#include "res://scripts/rally/cdi_terrain_layers.gdshaderinc"

varying vec3 world_point;
varying vec3 world_normal;

// Ruido de crestas afiladas (Ridged FBM) para fracturas, aristas y canaletas rocosas
float ridge_noise(vec2 p) {
	float n1 = 1.0 - abs(patch_noise(p) * 2.0 - 1.0);
	float n2 = 1.0 - abs(patch_noise(p * 2.37 + vec2(19.3, 41.7)) * 2.0 - 1.0);
	float n3 = 1.0 - abs(patch_noise(p * 5.61 + vec2(73.1, 11.9)) * 2.0 - 1.0);
	return n1 * 0.55 + n2 * 0.30 + n3 * 0.15;
}

// Muestreo triplanar de luminancia sobre las capas de roca (14..16) y pedregal (17..18)
float triplanar_rock_luma(vec3 p, vec3 n, float scale, float layer) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(dot(w, vec3(1.0)), 0.001);
	vec2 warp = terrain_warp(p.xz * 0.08) * 0.45;
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
	// Normal suave interpolada por vértice (con respaldo en derivadas si faltara)
	vec3 base_normal = length(world_normal) > 0.001
		? normalize(world_normal)
		: normalize(cross(dFdx(p), dFdy(p)));
	if (base_normal.y < 0.0) {
		base_normal = -base_normal;
	}

	float dist = length(VERTEX);
	float detail_fade = 1.0 - smoothstep(1800.0, 7500.0, dist);

	// 1. Pendiente y exposición rocosa
	float slope = 1.0 - clamp(base_normal.y, 0.0, 1.0);
	float steep = smoothstep(0.04, 0.24, slope);
	float cliff = smoothstep(0.16, 0.42, slope);

	// 2. Estratos geológicos inclinados + canaletas de derrubios (scree gullies)
	float warp = patch_noise(p.xz * 0.0065) * 28.0 + patch_noise(p.xz * 0.025) * 7.0;
	float strata_coord = p.y * 0.085 + p.x * 0.022 - p.z * 0.015 + warp;
	float strata_bands = smoothstep(0.15, 0.85, sin(strata_coord * 3.14159) * 0.5 + 0.5);

	vec2 slope_dir = normalize(base_normal.xz + vec2(0.0001));
	vec2 gully_uv = vec2(dot(p.xz, vec2(-slope_dir.y, slope_dir.x)) * 0.045, p.y * 0.018);
	float gullies = ridge_noise(gully_uv + warp * 0.08);

	// 3. Textura triplanar multiescala de roca y pedregal
	float macro_rock = triplanar_rock_luma(p, base_normal, 38.0, 15.0);
	float mid_rock = triplanar_rock_luma(p, base_normal, 9.5, 14.0);
	float scree_tex = triplanar_rock_luma(p, base_normal, 7.0, 17.0);
	float rock_tex = mix(scree_tex, mix(macro_rock, mid_rock, 0.55), cliff);

	// 4. Micro-relieve y sombreado direccional (acentuación topográfica)
	float relief_field = (rock_tex - 0.36) * 1.4
		+ (gullies - 0.5) * 0.75 * steep
		+ (strata_bands - 0.5) * 0.45 * cliff;
	vec2 d_relief = vec2(dFdx(relief_field), dFdy(relief_field)) * detail_fade;
	vec3 detail_normal = normalize(base_normal + vec3(d_relief.x, 0.0, d_relief.y) * (1.8 * steep));

	// Dirección del sol alineada con el hillshade de Python (-dx*0.34 - dz*0.38)
	vec3 sun_dir = normalize(vec3(-0.48, 0.72, -0.50));
	float base_shade = clamp(dot(base_normal, sun_dir), 0.25, 1.0);
	float micro_shade = clamp(dot(detail_normal, sun_dir), 0.15, 1.0);
	float relief_boost = clamp(1.0 + (micro_shade - base_shade) * (1.35 * steep), 0.58, 1.38);

	// Oclusión en grietas profundas y realce en filos de roca
	float cavity = mix(0.76, 1.16, clamp(gullies * 0.65 + (rock_tex - 0.32) * 1.2, 0.0, 1.0));
	float rock_modulation = mix(1.0, relief_boost * cavity * mix(0.88, 1.12, strata_bands * cliff), steep * detail_fade);

	// 5. Color mineral con detalle geológico + mezcla de pastizal GIS
	vec3 mountain_color = COLOR.rgb * rock_modulation;
	float scree_mask = steep * (1.0 - cliff) * smoothstep(0.45, 0.80, gullies) * detail_fade;
	mountain_color = mix(mountain_color, mountain_color * vec3(0.92, 0.96, 1.04), scree_mask * 0.45);

	float cover = gis.a * (1.0 - 0.88 * steep) * (1.0 - 0.72 * gis.b);
	float daylight = clamp(dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722)) * 1.3 + 0.5, 0.58, 1.12);
	vec3 grass_color = grass_macro_color(gis.rgb) * daylight;

	ALBEDO = mix(mountain_color, grass_color, cover);
}
