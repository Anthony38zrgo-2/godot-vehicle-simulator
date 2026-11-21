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
	if (terrain_mode == 2 && procedural_surface_enabled) {
		vec3 proc = proc_sample_surface(UV2.y, UV.x);
		float gravel_wet = 1.0 - 0.36 * proc.x;
		vec3 gravel_lit = ALBEDO * gravel_wet;
		vec3 snow_patch = mix(vec3(0.72, 0.75, 0.78), vec3(0.84, 0.86, 0.88), fine);
		gravel_lit = mix(gravel_lit, snow_patch, proc.y * 0.76);
		float ice_glaze = proc.z * (1.0 - proc.y * 0.82);
		gravel_lit = mix(gravel_lit, mix(gravel_lit * 1.08, vec3(0.70, 0.80, 0.90), 0.34), ice_glaze);
		ALBEDO = gravel_lit;
		road_roughness = mix(mix(0.95, 0.32, proc.x), 0.18, ice_glaze);
		road_specular = mix(mix(0.0, 0.56, smoothstep(0.02, 0.75, proc.x)) * (1.0 - proc.y * 0.85), 0.65, ice_glaze);
	} else if (terrain_mode != 2) {
		float ditch = terrain_mode == 1 ? 1.0 - smoothstep(0.24, 0.73, UV2.x) : 0.0;
		ALBEDO = ticlio_winter_ground(ALBEDO, p, n, length(VERTEX), ditch);
	}
	ROUGHNESS = road_roughness;
	SPECULAR = road_specular;
}
