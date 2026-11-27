shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled;

// Static alpine lake/pond surface using shared water ripple detail and gentle Fresnel sky reflection.

#include "res://shaders/lib/math/hash_noise.gdshaderinc"
#include "res://shaders/lib/water/water_waves.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.07, 0.15, 0.20);
uniform float base_alpha = 0.65;
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo_tex = false;
uniform vec3 horizon_color : source_color = vec3(0.26, 0.36, 0.46);
uniform vec3 sky_tint : source_color = vec3(0.34, 0.48, 0.62);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 detail_flow = vec2(TIME) * detail_speed * vec2(0.7, 1.0);
	vec3 wd = water_detail_sample(world_position.xz, detail_flow);
	float dist_fade = 1.0 - smoothstep(55.0, 140.0, length(world_position - CAMERA_POSITION_WORLD));
	float detail_k = clamp(detail_strength * dist_fade, 0.0, 1.0);
	float pattern = smoothstep(0.40, 0.68, wd.x);

	vec3 normal_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 reflected = reflect(normalize(world_position - CAMERA_POSITION_WORLD), normal_world);
	vec3 sky = mix(horizon_color, sky_tint, smoothstep(-0.025, 0.35, reflected.y));

	float view_angle = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float soft_fresnel = 1.0 - view_angle;

	vec3 surface_color = base_color;
	float surface_alpha = base_alpha;
	if (has_albedo_tex) {
		vec4 texel = texture(albedo_tex, UV);
		surface_color *= texel.rgb;
		surface_alpha *= texel.a;
	}
	vec3 highlight = mix(surface_color * 1.85 + sky * 0.16, sky * 0.50, 0.40);
	vec3 lake_color = mix(surface_color * 0.72, highlight, pattern * detail_k);

	ALBEDO = mix(lake_color, sky * 0.52, 0.06 + 0.10 * soft_fresnel);
	EMISSION = sky * (0.14 * pattern * detail_k + 0.04 * soft_fresnel);
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ALPHA = clamp(surface_alpha, 0.0, 0.72);
}
