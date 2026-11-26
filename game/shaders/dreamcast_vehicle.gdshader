shader_type spatial;
render_mode vertex_lighting, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_texture = true;

// PowerVR2 tenía coma flotante limpia (0.0 = Dreamcast nativo, >0.1 = toque retro arcade)
uniform vec2 snap_resolution = vec2(640.0, 480.0);
uniform float snap_strength : hint_range(0.0, 1.0) = 0.0;

// Reflejo de entorno por vértice (Gouraud Sphere Mapping) sutil solo en bordes
uniform float reflectivity : hint_range(0.0, 1.0) = 0.10;
uniform sampler2D env_map : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_env_texture = false;
uniform vec3 sky_color : source_color = vec3(0.55, 0.75, 1.0);
uniform vec3 horizon_color : source_color = vec3(0.95, 0.92, 0.80);
uniform vec3 ground_color : source_color = vec3(0.30, 0.25, 0.18);
uniform vec3 sun_direction = vec3(0.4, 0.8, 0.3);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.8);

// Respuesta PBR base heredada del material original
uniform float roughness_value : hint_range(0.0, 1.0) = 0.40;
uniform float specular_value : hint_range(0.0, 1.0) = 0.50;

// Especular por vértice típico de carrocerías Sega AM2 / AM3
uniform float vertex_specular_strength : hint_range(0.0, 2.0) = 0.18;
uniform float vertex_shininess : hint_range(4.0, 64.0) = 40.0;

// Soporte para faros (VisualDamage)
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy : hint_range(0.0, 5.0) = 0.0;

// Framebuffer 16-bit RGB565 + Dithering en salida final
uniform bool rgb565 = true;
uniform float dither_amount : hint_range(0.0, 1.0) = 0.30;

varying vec3 v_env_reflection;
varying float v_fresnel;
varying float v_spec;
varying vec2 v_sphere_uv;

const float bayer[16] = float[16](
	0.0,  8.0,  2.0, 10.0,
	12.0, 4.0, 14.0,  6.0,
	3.0, 11.0,  1.0,  9.0,
	15.0, 7.0, 13.0,  5.0
);

#include "res://scripts/rally/rally_dirt.gdshaderinc"

void vertex() {
	dirt_position = dirt_local_position(VERTEX);
	// 1. Subpixel snap opcional
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (snap_strength > 0.001) {
		vec2 ndc = clip.xy / clip.w;
		vec2 half_res = snap_resolution * 0.5;
		vec2 snapped = floor(ndc * half_res + 0.5) / half_res;
		clip.xy = mix(ndc, snapped, snap_strength) * clip.w;
	}
	POSITION = clip;

	// 2. Vectores en View Space y World Space calculados por vértice (look 1999)
	vec3 pos_view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n_view = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v_view = normalize(-pos_view);

	// Coordenadas Sphere Map clásicas (D3DTSS_TCI_CAMERASPACEREFLECTIONVECTOR)
	vec3 r_view = reflect(-v_view, n_view);
	v_sphere_uv = r_view.xy * 0.5 + 0.5;

	// Reflejo en espacio mundo para el cielo procedural
	vec3 r_world = normalize((INV_VIEW_MATRIX * vec4(r_view, 0.0)).xyz);
	float h = r_world.y;
	vec3 env = h > 0.0
		? mix(horizon_color, sky_color, pow(h, 0.6))
		: mix(horizon_color, ground_color, pow(-h, 0.6));

	vec3 sun_dir_norm = normalize(sun_direction);
	env += sun_color * pow(max(dot(r_world, sun_dir_norm), 0.0), 32.0);
	v_env_reflection = env;

	// Fresnel cerrado en bordes y Specular puntual por vértice
	v_fresnel = pow(1.0 - max(dot(n_view, v_view), 0.0), 4.0);
	vec3 l_view = normalize((VIEW_MATRIX * vec4(sun_dir_norm, 0.0)).xyz);
	vec3 h_view = normalize(l_view + v_view);
	v_spec = pow(max(dot(n_view, h_view), 0.0), vertex_shininess) * vertex_specular_strength;
}

void fragment() {
	vec4 c = albedo_color;
	if (use_texture) {
		c *= texture(albedo_tex, UV);
	}

	vec3 env = use_env_texture ? texture(env_map, v_sphere_uv).rgb : v_env_reflection;
	float refl = reflectivity * mix(0.02, 1.0, v_fresnel);

	// Conservar el color original íntegro y limitar el reflejo aditivo a los bordes
	vec4 dirt = dirt_sample();
	ALBEDO = mix(c.rgb, dirt.rgb, dirt.a);

	vec3 total_emission = env * refl + (sun_color * v_spec * reflectivity) + (emission_color * emission_energy);

	total_emission *= 1.0 - dirt.a;

	// Cuantización RGB565 con matriz Bayer 4x4 sobre el color y la emisión
	if (rgb565) {
		vec3 steps = vec3(31.0, 63.0, 31.0);
		ivec2 p = ivec2(FRAGCOORD.xy) % 4;
		float d = (bayer[p.y * 4 + p.x] / 16.0 - 0.5) * dither_amount;
		ALBEDO = clamp(floor(ALBEDO * steps + 0.5 + d) / steps, 0.0, 1.0);
		total_emission = max(floor(total_emission * steps + 0.5 + d) / steps, vec3(0.0));
	}

	EMISSION = total_emission;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value * (1.0 - dirt.a);
}
