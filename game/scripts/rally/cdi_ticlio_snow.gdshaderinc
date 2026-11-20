uniform bool ticlio_snow_enabled = false;
uniform sampler2D ticlio_snow_coverage : filter_linear, repeat_disable;
uniform sampler2DArray ticlio_snow_textures : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

vec3 ticlio_triplanar(vec3 p, vec3 n, float layer) {
	vec3 weights = pow(abs(n), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.001);
	vec2 warp = terrain_warp(p.xz * 0.94) * 1.20 + terrain_warp(p.xz * 2.40) * 0.24;
	vec3 q = p / 4.3 + vec3(warp.x, 0.3 * (warp.x - warp.y), warp.y);
	mat2 turn = mat2(vec2(0.8387, 0.5446), vec2(-0.5446, 0.8387));
	return texture(ticlio_snow_textures, vec3(turn * q.zy, layer)).rgb * weights.x
		+ texture(ticlio_snow_textures, vec3(turn * q.xz, layer)).rgb * weights.y
		+ texture(ticlio_snow_textures, vec3(turn * q.xy, layer)).rgb * weights.z;
}

vec3 ticlio_winter_ground(vec3 base, vec3 p, vec3 n, float distance_m, float shelter) {
	if (!ticlio_snow_enabled) {
		return base;
	}
	// Y is relative to the start datum of Abra Ticlio. Break the snowline
	// into slopes and gullies before adding smaller clumps at the roadside.
	float altitude = smoothstep(76.0, 292.0, p.y);
	float steep = smoothstep(0.055, 0.48, 1.0 - abs(n.y));
	float drift = patch_noise(p.xz * 0.012 + vec2(19.1, 51.7));
	float banks = patch_noise(p.xz * 0.046 + vec2(4.2, 37.6));
	float catchment = drift * 0.68 + banks * 0.32;
	float deposit = altitude * 0.72 + (catchment - 0.5) * 0.83 + shelter * 0.14 - steep * 0.29;
	float gate = smoothstep(64.0, 105.0, p.y);
	float scoured = smoothstep(0.29, 0.54, catchment + shelter * 0.11);
	float cover = smoothstep(0.24, 0.62, deposit) * gate * mix(0.10, 1.0, scoured);
	vec2 uv = (p.xz - grass_gis_bounds.xy) / grass_gis_bounds.zw;
	vec2 margin = min(uv, 1.0 - uv);
	float mapped = smoothstep(0.0, 0.025, min(margin.x, margin.y));
	cover = mix(cover, texture(ticlio_snow_coverage, uv).r, mapped);
	float core = smoothstep(0.55, 0.87, cover);
	if (cover <= 0.001) {
		return base;
	}
	float detail = 1.0 - smoothstep(120.0, 550.0, distance_m);
	vec3 pure_snow = mix(vec3(0.52, 0.55, 0.58), vec3(0.68, 0.70, 0.72), banks);
	vec3 transition = mix(base, pure_snow, 0.78);
	if (detail > 0.001) {
		float cell = floor(patch_noise(p.xz * 0.012 + vec2(73.2, 18.2)) * 4.0);
		float basin_layer = cell < 1.0 ? 1.0 : (cell < 2.0 ? 3.0 : (cell < 3.0 ? 4.0 : 5.0));
		float rock_layer = banks < 0.48 ? 0.0 : (banks < 0.71 ? 2.0 : 6.0);
		vec3 basin = ticlio_triplanar(p, n, basin_layer);
		vec3 rock = ticlio_triplanar(p, n, rock_layer);
		transition = mix(transition, mix(basin, rock, steep), detail * 0.66 * (1.0 - core));
		float fine_detail = 1.0 - smoothstep(45.0, 190.0, distance_m);
		if (fine_detail > 0.001 && core > 0.001) {
			vec3 snow_grain = ticlio_triplanar(p, n, banks < 0.60 ? 7.0 : 8.0);
			pure_snow = mix(pure_snow, snow_grain * 0.71, fine_detail * 0.78);
		}
	}
	// The coherent field controls opacity once, so high-contrast snow
	// textures cannot draw repeating stripes through the ichu layer.
	vec3 patch_edge = mix(base, transition, smoothstep(0.03, 0.68, cover) * 0.83);
	return mix(patch_edge, pure_snow, core * 0.98);
}
