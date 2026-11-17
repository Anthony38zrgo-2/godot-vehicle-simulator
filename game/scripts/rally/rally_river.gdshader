shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled, vertex_lighting;

// Uniforms conectados a RallyRiverChannels._update_channel_material()
uniform vec2 footprint_min = vec2(0.0);
uniform vec2 footprint_size = vec2(1.0);
uniform sampler2D bed_tex : hint_default_white, filter_nearest;
uniform float bed_min_y = 0.0;
uniform float bed_max_y = 1.0;
uniform float edge_feather_m = 0.06;
uniform float rise_m = 0.0;
uniform float rain = 0.0;
uniform vec2 flow_dir = vec2(0.3, 0.95);
uniform float flow_speed = 0.58;
uniform vec3 shallow_color : source_color = vec3(0.09, 0.19, 0.22);
uniform vec3 deep_color : source_color = vec3(0.03, 0.08, 0.12);
uniform vec3 horizon_color : source_color = vec3(0.26, 0.36, 0.46);
uniform vec3 sky_tint : source_color = vec3(0.34, 0.48, 0.62);

// Controles de estética PS2 (GS / VU1)
uniform float ps2_vertex_wave = 0.012;
uniform float ps2_env_warp = 0.08;
uniform float ps2_color_levels = 32.0; // 32 niveles = 5 bits por canal (RGB5A1)
uniform float ps2_depth_steps = 8.0;   // Bandas de turbidez cuantizadas
uniform float ps2_dither_strength = 1.0;

#include "res://scripts/rally/rally_water_detail.gdshaderinc"

varying vec3 world_position;
varying float v_base_y;
varying vec3 v_sky_color;
varying float v_fresnel;
varying vec2 v_env_offset;

// Matriz Bayer 4x4 del hardware GS de PS2 (rango [-0.5, 0.5])
float ps2_bayer4x4(vec2 screen_pos) {
	ivec2 p = ivec2(mod(screen_pos, 4.0));
	int idx = p.y * 4 + p.x;
	const float bayer[16] = float[16](
		 0.0,  8.0,  2.0, 10.0,
		12.0,  4.0, 14.0,  6.0,
		 3.0, 11.0,  1.0,  9.0,
		15.0,  7.0, 13.0,  5.0
	);
	return (bayer[idx] / 16.0) - 0.5;
}

void vertex() {
	vec3 wp_base = (MODEL_MATRIX * vec4(VERTEX + vec3(0.0, rise_m, 0.0), 1.0)).xyz;
	v_base_y = wp_base.y;
	VERTEX.y += rise_m;

	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Iluminación, Fresnel y reflejo calculados POR VÉRTICE (Gouraud interpolation)
	vec3 normal_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 view_dir_world = normalize(CAMERA_POSITION_WORLD - world_position);

	// Fresnel lineal sin curvas suaves por píxel
	v_fresnel = clamp(1.0 - dot(normal_world, view_dir_world), 0.0, 1.0);

	// Tinte de cielo por vértice
	vec3 reflected = reflect(-view_dir_world, normal_world);
	float sky_factor = clamp((reflected.y + 0.05) * 2.5, 0.0, 1.0);
	v_sky_color = mix(horizon_color, sky_tint, sky_factor);

	// Fake sphere-map offset para deformar UVs según la cámara
	v_env_offset = view_dir_world.xz * ps2_env_warp;
}

void fragment() {
	vec2 fuv = (world_position.xz - footprint_min) / max(footprint_size, vec2(0.001));
	if (fuv.x < 0.0 || fuv.x > 1.0 || fuv.y < 0.0 || fuv.y > 1.0) {
		discard;
	}
	vec4 bed = texture(bed_tex, fuv);
	if (bed.g < 0.5) {
		discard;
	}
	float bed_y = mix(bed_min_y, bed_max_y, bed.r);
	float depth_m = v_base_y - bed_y;
	if (depth_m <= 0.0) {
		discard;
	}

	float dither = ps2_bayer4x4(FRAGCOORD.xy) * ps2_dither_strength;

	// Orilla suave sin cortes bruscos
	float edge_raw = clamp(depth_m / max(edge_feather_m, 0.001), 0.0, 1.0);
	float edge = smoothstep(0.0, 1.0, edge_raw);
	if (edge <= 0.01) {
		discard;
	}

	// Profundidad cuantizada en bandas de turbidez (sin exp() por fragmento)
	float depth_mm = depth_m * 1000.0;
	float depth_norm = clamp(depth_mm / 450.0, 0.0, 1.0);
	float depth_steps = max(ps2_depth_steps, 1.0);
	float turbidity = floor(clamp(depth_mm / 320.0, 0.0, 1.0) * depth_steps + (dither * 0.5 + 0.5)) / depth_steps;
	turbidity = clamp(turbidity, 0.0, 1.0);

	// Doble scroll continuo con distorsión de vista
	float t = TIME;
	vec2 base_flow = (flow_speed > 0.01) ? (-flow_dir * t * flow_speed * 0.28) : (vec2(t) * detail_speed * vec2(0.7, 1.0));
	vec2 uv_a = world_position.xz + v_env_offset;
	vec2 uv_b = world_position.xz * 1.35 - v_env_offset * 0.7;
	vec3 wd_a = water_detail_sample(uv_a, base_flow);
	vec3 wd_b = water_detail_sample(uv_b, vec2(-base_flow.y, base_flow.x) * 0.85);

	// Mezcla continua sin saltos discretos
	float combined_tex = (wd_a.x * wd_b.x) * 2.2;
	float rain_sparkle = smoothstep(0.68 - rain * 0.18, 0.92, fract((wd_a.x - wd_b.x) * 4.0 + t * 6.0)) * rain;

	float dist_fade = 1.0 - clamp((length(world_position - CAMERA_POSITION_WORLD) - 45.0) / 85.0, 0.0, 1.0);
	float detail_k = clamp(detail_strength * edge * dist_fade, 0.0, 1.0);

	float spec_band = smoothstep(0.32, 0.72, combined_tex);
	float foam_shore = smoothstep(0.10, 0.25, edge_raw) * (1.0 - smoothstep(0.35, 0.60, edge_raw)) * smoothstep(0.35, 0.65, wd_a.x);

	vec3 river_base = mix(shallow_color, deep_color, turbidity);
	// Modulate 2x sobre los reflejos del cielo interpolados por vértice
	vec3 env_highlight = (river_base * 1.6 + v_sky_color * 0.65) * 1.35;

	vec3 water_color = mix(river_base * 0.82, env_highlight, spec_band * detail_k);
	water_color = mix(water_color, v_sky_color * 0.75, 0.08 + 0.22 * v_fresnel);
	water_color += v_sky_color * (rain_sparkle * 0.35 + foam_shore * 0.25);

	// Cuantización final a 16-bit (RGB5A1) con Bayer Dithering centrado (sin sesgo oscuro)
	float color_steps = max(ps2_color_levels - 1.0, 1.0);
	vec3 quantized_albedo = floor(water_color * color_steps + (dither + 0.5)) / color_steps;

	ALBEDO = clamp(quantized_albedo, vec3(0.0), vec3(1.0));
	// En PS2 el brillo del agua venía de un pase aditivo de textura + envmap
	EMISSION = v_sky_color * ((0.18 * spec_band + 0.25 * rain_sparkle) * detail_k + 0.06 * v_fresnel) * edge;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;

	float base_alpha = mix(0.20, 0.58, depth_norm);
	float alpha_quant = floor((base_alpha * edge) * 15.0 + (dither * 0.5 + 0.5)) / 15.0;
	ALPHA = clamp(alpha_quant, 0.0, 0.68);
}
