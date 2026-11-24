shader_type spatial;
render_mode fog_disabled;

#include "res://scripts/rally/cdi_terrain_layers.gdshaderinc"
#include "res://scripts/rally/cdi_ticlio_snow.gdshaderinc"
#include "res://scripts/rally/cdi_procedural_surface.gdshaderinc"

uniform int terrain_mode = 0;
varying vec3 world_point;
varying vec3 world_normal;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 p = world_point;
	vec3 n = normalize(world_normal);
	float fine = patch_noise(p.xz * 0.82);
	float patch = patch_noise(p.xz * 0.052) * 0.70 + fine * 0.30;
	vec3 zone = zone_layers(UV2.y);
	if (terrain_mode == 2) {
		// Gravel fades into the same dirt used by the bordering shoulder.
		float edge = min(UV.x, 1.0 - UV.x);
		float gravel = smoothstep(0.0, 0.085 + fine * 0.030, edge);
		ALBEDO = mix(zone_shoulder(p, zone), zone_texture(UV, 0.0, 4.0, zone), gravel);
	} else {
		vec3 cover = ground_cover(p, patch);
		if (terrain_mode == 1) {
			// UV2.x runs from the road edge to the outside of the talud.
			float side = clamp(UV2.x, 0.0, 1.0);
			float grass = smoothstep(0.37 + fine * 0.15, 0.99, side);
			float incline = degrees(acos(clamp(abs(n.y), 0.0, 1.0)));
			float exposure = smoothstep(12.0, 33.0, incline + (fine - 0.5) * 9.0);
			float rock = exposure * smoothstep(0.08, 0.30, side) * (1.0 - smoothstep(0.58, 0.99, side));
			float mineral = patch_noise(p.xz * 0.19 + vec2(7.0, 23.0));
			float scree = smoothstep(0.22, 0.68, mineral) * exposure;
			vec3 soil = mix(zone_shoulder(p, zone), palette_layer(p.xz / 2.5, 13.0),
				exposure * smoothstep(0.0, 0.12, side) * (1.0 - smoothstep(0.60, 0.95, side)));
			vec3 debris = zone_texture(p.xz / 2.0 + terrain_warp(p.xz) * 0.64, 17.0, 2.0, zone);
			ALBEDO = mix(mix(mix(soil, debris, scree * smoothstep(0.0, 0.12, side)), cut_rock(p, n, zone), rock), cover, grass);
		} else {
			ALBEDO = cover;
		}
	}
	ALBEDO *= terrain_macro_tone(p.xz);
	float road_roughness = 0.95;
	float road_specular = 0.0;
	vec3 road_emission = vec3(0.0);
	if (terrain_mode == 2 && procedural_surface_enabled) {
		vec3 proc = proc_sample_surface(UV2.y, UV.x);
		vec2 loose_mud = proc_sample_loose_gravel_and_mud(UV2.y, UV.x, proc.y);
		float loose_cov = loose_mud.x;
		float mud_factor = loose_mud.y;
		float dry_clay_cov = clamp(loose_cov - mud_factor, 0.0, 1.0);

		float local_wetness = proc.x;
		float tracks = 0.0;
		float micro_cavity = clamp(1.0 - fine, 0.0, 1.0);
		proc_transverse_water_distribution(
			UV2.y,
			UV.x,
			p.xz,
			n,
			proc.x,
			0.48,
			local_wetness,
			tracks,
			micro_cavity
		);

		// Clayey loose gravel tint in dry/damp conditions + deep dark muddy paste under heavy rain
		float fine_pebble = patch_noise(p.xz * 3.4);
		vec3 clay_dry_tint = mix(vec3(0.66, 0.48, 0.33), vec3(0.76, 0.57, 0.40), fine_pebble);
		ALBEDO = mix(ALBEDO, mix(ALBEDO * vec3(1.08, 0.88, 0.68), clay_dry_tint, 0.56), dry_clay_cov * 0.78);
		vec3 mud_paste_tint = mix(vec3(0.28, 0.18, 0.11), vec3(0.38, 0.25, 0.16), tracks * 0.5 + fine * 0.5);
		ALBEDO = mix(ALBEDO, mix(ALBEDO * vec3(0.55, 0.44, 0.34), mud_paste_tint, 0.68), mud_factor * 0.88);

		// Protruding gravel stones stay drier while mud paste holds a slightly smoother sheen
		float emergent_stones = smoothstep(0.54, 0.80, fine) * (1.0 - tracks * 0.45) * (1.0 - mud_factor * 0.82);
		float effective_film_wet = clamp(max(local_wetness * (1.0 - emergent_stones * 0.50), mud_factor * 0.65), 0.0, 1.0);
		vec4 wet_opt = proc_wet_surface_optics(
			effective_film_wet,
			mix(0.95, 0.985, dry_clay_cov),
			mix(0.58, 0.48, mud_factor),
			mix(0.24, 0.30, mud_factor),
			micro_cavity,
			tracks,
			dot(NORMAL, VIEW)
		);
		float snow_suppress = 1.0 - proc.y * 0.85;
		float sheen_w = wet_opt.w * 0.65 * snow_suppress * (1.0 - emergent_stones * 0.60);
		vec3 gravel_lit = ALBEDO * mix(wet_opt.x, 1.0, emergent_stones * 0.40);
		vec3 snow_patch = mix(vec3(0.72, 0.75, 0.78), vec3(0.84, 0.86, 0.88), fine);
		gravel_lit = mix(gravel_lit, snow_patch, proc.y * 0.76);
		ALBEDO = gravel_lit;
		road_emission = proc_horizon_color * sheen_w;
		road_roughness = mix(wet_opt.y, 0.95, proc.y * 0.76);
		road_specular = wet_opt.z * 0.65 * snow_suppress * (1.0 - emergent_stones * 0.50) * (1.0 - dry_clay_cov * 0.45);
	} else if (terrain_mode != 2) {
		float ditch = terrain_mode == 1 ? 1.0 - smoothstep(0.24, 0.73, UV2.x) : 0.0;
		ALBEDO = ticlio_winter_ground(ALBEDO, p, n, length(VERTEX), ditch);
	}
	float haze = terrain_depth_haze(length(VERTEX));
	ALBEDO = mix(ALBEDO, depth_haze_color, haze);
	EMISSION = mix(road_emission, depth_haze_color * 0.42, haze);
	ROUGHNESS = mix(road_roughness, 0.96, haze);
	SPECULAR = road_specular * (1.0 - haze);
}
