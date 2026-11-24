shader_type spatial;
render_mode fog_disabled;

#include "res://scripts/rally/cdi_procedural_surface.gdshaderinc"

uniform sampler2DArray surface_textures : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float snow_station_m = -1.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform vec3 depth_haze_color : source_color = vec3(0.68, 0.76, 0.86);
uniform float depth_haze_start = 140.0;
uniform float depth_haze_end = 620.0;
uniform float depth_haze_max : hint_range(0.0, 0.85) = 0.0;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

float hash21(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
		mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float station = UV2.y;
	float lateral = clamp(UV.x, 0.0, 1.0);
	float edge = 2.0 * abs(lateral - 0.5);
	float grain = noise2(world_position.xz * 1.15);
	vec2 tile = vec2(lateral, station / 4.0);
	vec3 pavement = texture(surface_textures, vec3(tile, 0.0)).rgb;
	vec2 shoulder = vec2((1.0 - edge) * 1.4, tile.y);
	vec3 worn_edge = texture(surface_textures, vec3(shoulder, 1.0)).rgb;
	pavement = mix(pavement, worn_edge, smoothstep(0.83 + grain * 0.08, 1.0, edge));

	vec3 unmarked_pavement = pavement;

	// The source stripes sit on the left edge of each tile. Sample only
	// a narrow strip around the stripe and map it onto the road center.
	float marking_zone = floor(station / 115.0);
	float marking = 2.0 + floor(hash21(vec2(marking_zone, 7.0)) * 6.0);
	float stripe_x = 0.063 + (lateral - 0.5) * 2.4;
	vec3 marked = texture(surface_textures, vec3(stripe_x, station / 5.0, marking)).rgb;
	float stripe = 1.0 - smoothstep(0.022, 0.050, abs(lateral - 0.5));
	pavement = mix(pavement, marked, stripe);

	float coverage = 0.0;
	float eff_wetness = wetness;
	float ice_cov = 0.0;
	if (procedural_surface_enabled) {
		vec3 proc = proc_sample_surface(station, lateral);
		eff_wetness = proc.x;
		coverage = proc.y;
		ice_cov = proc.z;
	} else if (snow_station_m >= 0.0) {
		float d = station - snow_station_m;
		float patch = noise2(vec2(station * 0.20, lateral * 9.0)) - 0.5;
		float phase = d + edge * 16.0 + patch * 20.0;
		float altitude = smoothstep(110.0, 292.0, world_position.y);
		float rim = smoothstep(0.68, 1.0, edge);
		float rise = (0.24 + 0.63 * altitude) * mix(0.58, 1.0, rim);
		coverage = smoothstep(-42.0, 45.0, phase) * smoothstep(-65.0, -42.0, d) * rise;
	}
	float variation = noise2(vec2(station * 0.075, lateral * 3.0));
	// Vary the phase of the deposits while keeping the original asphalt UVs.
	vec2 winter_uv = tile + vec2(0.0, variation * 0.65);
	vec3 patches = texture(surface_textures, vec3(winter_uv, 8.0)).rgb;
	vec3 ruts = texture(surface_textures, vec3(winter_uv, 9.0)).rgb;
	vec3 winter_base = texture(surface_textures, vec3(winter_uv, 0.0)).rgb;
	float tracks = 1.0 - smoothstep(0.045, 0.15, abs(abs(lateral - 0.5) - 0.24));
	vec3 deposits = mix(patches, ruts, clamp(tracks * 0.86 + variation * 0.24, 0.0, 1.0)) - winter_base;
	vec3 winter_asphalt = clamp(unmarked_pavement + deposits, vec3(0.0), vec3(1.0));
	float snow_mask = smoothstep(0.065, 0.30, dot(winter_asphalt, vec3(0.2126, 0.7152, 0.0722)));
	winter_asphalt = mix(winter_asphalt, marked, stripe * (1.0 - snow_mask));
	vec3 base_world_n = normalize(world_normal);
	float local_wetness = eff_wetness;
	float wet_tracks = tracks;
	float micro_cavity = clamp(1.0 - grain, 0.0, 1.0);
	if (procedural_surface_enabled) {
		proc_transverse_water_distribution(
			station,
			lateral,
			world_position.xz,
			base_world_n,
			eff_wetness,
			0.32,
			local_wetness,
			wet_tracks,
			micro_cavity
		);
	}
	vec4 wet_opt = proc_wet_surface_optics(
		local_wetness,
		0.92,
		0.45,
		0.22,
		micro_cavity,
		wet_tracks,
		dot(NORMAL, VIEW)
	);
	float snow_blend = procedural_surface_enabled ? coverage : (coverage * snow_mask);
	float sheen_w = wet_opt.w * (1.0 - snow_blend);
	vec3 wet_pavement = pavement * wet_opt.x;
	vec3 ribbon_snow = mix(vec3(0.76, 0.80, 0.84), vec3(0.92, 0.94, 0.97), grain);
	vec3 lit_road = procedural_surface_enabled
		? mix(wet_pavement, ribbon_snow, coverage * 0.90)
		: mix(wet_pavement, winter_asphalt * mix(wet_opt.x, 1.0, snow_mask), coverage);
	float haze = smoothstep(depth_haze_start, depth_haze_end, length(VERTEX)) * depth_haze_max;
	ALBEDO = mix(lit_road, depth_haze_color, haze);
	EMISSION = mix(proc_horizon_color * sheen_w, depth_haze_color * 0.42, haze);
	ROUGHNESS = mix(mix(wet_opt.y, 0.97, snow_blend), 0.97, haze);
	SPECULAR = mix(wet_opt.z, 0.08, snow_blend) * (1.0 - haze);
}
