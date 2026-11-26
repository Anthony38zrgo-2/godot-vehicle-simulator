shader_type spatial;
render_mode fog_disabled;

#include "res://scripts/rally/cdi_terrain_layers.gdshaderinc"
#include "res://scripts/rally/cdi_ticlio_snow.gdshaderinc"
#include "res://scripts/rally/cdi_procedural_surface.gdshaderinc"

uniform int terrain_mode = 0;
uniform float loose_gravel_scale : hint_range(0.0, 1.0) = 1.0;
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
		float loose_cov = loose_mud.x * loose_gravel_scale;
		float mud_factor = loose_mud.y * loose_gravel_scale;
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

		// Lateral fine-gravel berm & mud paste: keep visual boundary aligned with CPU lateral berm
		// while adding subtle granular stone/sand micro-breakup along the inner transition.
		float edge_breakup = patch_noise(p.xz * 0.38 + vec2(13.1, 7.7));
		float fine_pebble = patch_noise(p.xz * 3.6 + vec2(5.2, 19.4));
		float micro_sand = patch_noise(p.xz * 9.2 + vec2(21.7, 3.1));
		float inner_edge_weight = smoothstep(0.0, 0.35, loose_cov) * (1.0 - smoothstep(0.65, 1.0, loose_cov));
		float broken_mask = clamp(
			loose_cov + ((edge_breakup - 0.5) * 0.14 + (fine_pebble - 0.5) * 0.08) * inner_edge_weight,
			0.0,
			1.0
		);
		float damage_vis = smoothstep(0.03, 0.68, broken_mask) * smoothstep(0.0, 0.04, loose_cov);
		float dry_damage_vis = clamp(damage_vis * (1.0 - mud_factor), 0.0, 1.0);
		float fracture_rim = smoothstep(0.04, 0.28, damage_vis) * (1.0 - smoothstep(0.42, 0.78, damage_vis));
		// Sandy-ochre & Andean clay fine gravel berm fill.
		vec3 disturbed_soil = zone_shoulder(p, zone) * terrain_macro_tone(p.xz);
		float sand_vs_clay = smoothstep(0.28, 0.74, patch_noise(p.xz * 0.14 + vec2(29.3, 11.4)) * 0.65 + edge_breakup * 0.35);
		vec3 sandy_fill = mix(vec3(0.68, 0.56, 0.41), vec3(0.77, 0.65, 0.48), micro_sand);
		vec3 clayey_fill = mix(vec3(0.55, 0.39, 0.27), vec3(0.67, 0.49, 0.34), fine_pebble);
		vec3 loose_aggregate = mix(clayey_fill, sandy_fill, sand_vs_clay);
		float pebble_fleck = smoothstep(0.62, 0.86, fine_pebble * 0.6 + micro_sand * 0.4);
		vec3 damaged_surface = mix(disturbed_soil * vec3(1.12, 0.96, 0.80), loose_aggregate, 0.65);
		damaged_surface *= mix(1.0, 0.88, tracks * 0.55);
		damaged_surface = mix(damaged_surface, damaged_surface * 1.14, pebble_fleck * 0.45);
		ALBEDO *= mix(1.0, 0.86, fracture_rim * (1.0 - mud_factor * 0.5) * 0.55);
		ALBEDO = mix(ALBEDO, damaged_surface, dry_damage_vis * 0.88);

		float mud_vis = clamp(mud_factor * mix(0.82, 1.12, damage_vis), 0.0, 1.0);
		vec3 mud_paste_tint = mix(vec3(0.24, 0.15, 0.10), vec3(0.35, 0.22, 0.14), tracks * 0.5 + fine * 0.5);
		ALBEDO = mix(ALBEDO, mix(ALBEDO * vec3(0.50, 0.40, 0.30), mud_paste_tint, 0.72), mud_vis * 0.92);

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
		float snow_vis = smoothstep(0.0, 0.68, proc.y) * 0.94;
		float snow_suppress = 1.0 - snow_vis * 0.95;
		float sheen_w = wet_opt.w * 0.65 * snow_suppress * (1.0 - emergent_stones * 0.60);
		vec3 gravel_lit = ALBEDO * mix(wet_opt.x, 1.0, emergent_stones * 0.40);
		vec3 snow_patch = mix(vec3(0.76, 0.79, 0.82), vec3(0.88, 0.90, 0.92), fine);
		gravel_lit = mix(gravel_lit, snow_patch, snow_vis);
		ALBEDO = gravel_lit;
		road_emission = proc_horizon_color * sheen_w;
		road_roughness = mix(wet_opt.y, 0.96, snow_vis);
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
