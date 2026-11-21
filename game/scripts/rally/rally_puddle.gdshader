shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled;

uniform vec2 patch_size = vec2(1.0);
varying vec2 patch_uv;
varying vec3 world_position;
varying float v_road_weight;

uniform bool has_sky = false;
uniform samplerCube sky_a : source_color, filter_linear_mipmap;
uniform samplerCube sky_b : source_color, filter_linear_mipmap;
uniform samplerCube sky_c : source_color, filter_linear_mipmap;
uniform float weather_mix = 0.0;
uniform float daylight_mix = 1.0;
uniform float twilight_yaw = 0.0;
uniform float yaw_b = 0.0;
uniform vec3 tint_a = vec3(1.0);
uniform vec3 tint_b = vec3(1.0);
uniform vec3 tint_c = vec3(1.0);
uniform vec3 horizon_color : source_color = vec3(0.25);
uniform vec4 sky_tint : source_color = vec4(0.46, 0.52, 0.58, 1.0);

uniform sampler2D puddle_mask : hint_default_white, filter_linear_mipmap;
uniform bool use_mask_texture = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec4 shape_params = vec4(0.0);
uniform float max_depth_mm = 48.0;
uniform float fill = 0.0;
uniform int winter_kind = 0;
uniform float winter_depth_mm = 0.0;
uniform float rain = 0.0;
uniform float edge_softness = 0.18;
uniform vec4 shallow_color : source_color = vec4(0.030, 0.065, 0.105, 0.22);
uniform vec4 deep_color : source_color = vec4(0.008, 0.022, 0.048, 0.88);

#include "res://scripts/rally/rally_water_detail.gdshaderinc"

vec3 rotate_y(vec3 d, float yaw) {
	return vec3(cos(yaw) * d.x + sin(yaw) * d.z, d.y, -sin(yaw) * d.x + cos(yaw) * d.z);
}

float puddle_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float rain_drop_ripples(vec2 uv_world, float time, float intensity) {
	if (intensity <= 0.01) return 0.0;
	float total = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		float scale = (layer == 0) ? 5.5 : 9.5;
		vec2 p = uv_world * scale + float(layer) * 17.3;
		vec2 g = floor(p);
		vec2 f = fract(p) - 0.5;
		for (int i = -1; i <= 1; i++) {
			for (int j = -1; j <= 1; j++) {
				vec2 n = vec2(float(i), float(j));
				float h = puddle_hash(g + n);
				float age = fract(time * (1.1 + 0.5 * h) + h * 6.2831);
				float rad = age * 0.45;
				vec2 d = f - n;
				float dist = length(d);
				if (dist < rad && dist > rad - 0.16) {
					float wave = sin((dist - rad) * 36.0);
					float fade = (1.0 - age) * smoothstep(rad - 0.16, rad, dist);
					total += wave * fade;
				}
			}
		}
	}
	return total * intensity;
}

void vertex() {
	patch_uv = VERTEX.xz / max(patch_size, vec2(0.1));
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_road_weight = COLOR.r;
}

// Procedural fallback: gentle rounded organic pond without sharp spikes or pinched poles
float procedural_mask(vec2 uv, vec4 sp) {
	vec2 p = uv * 2.0;
	p.x += (p.y * 0.20) * sp.y;
	p.x *= (1.0 + p.y * 0.15 * sp.x);
	float phase = sp.w;
	float w1 = sin(p.y * 2.2 + phase) * 0.08 * sp.z;
	float w2 = cos(p.x * 2.0 + phase * 1.2) * 0.08 * sp.z;
	vec2 warped = p + vec2(w1, w2);
	float r = length(warped);
	float theta = atan(warped.y, warped.x);
	float r_bound = 0.86 + 0.05 * sin(2.0 * theta + phase);
	return clamp(1.0 - (r / r_bound), 0.0, 1.0);
}

void fragment() {
	if (winter_kind == 0 && fill <= 0.001) {
		discard;
	}

	float mask = 0.0;
	if (use_mask_texture) {
		vec2 muv = patch_uv * uv_scale + vec2(0.5);
		if (muv.x < 0.0 || muv.x > 1.0 || muv.y < 0.0 || muv.y > 1.0) {
			discard;
		}
		mask = texture(puddle_mask, muv).r;
	} else {
		mask = procedural_mask(patch_uv, shape_params);
	}

	// Smoothly trim geometry that overhangs the edge of the road collision
	mask *= smoothstep(0.04, 0.65, v_road_weight);

	if (mask <= 0.006) {
		discard;
	}

	// Double-zone decomposition:
	// Zone 1: Outer wet soil saturation ring (mask in [0.006, 0.26])
	// Zone 2: Inner liquid water basin (mask > 0.18)
	float wet_soil = smoothstep(0.006, 0.26, mask);
	float water_body = smoothstep(0.18, 0.34 + edge_softness * 0.15, mask);
	float water_mask = clamp((mask - 0.18) / 0.82, 0.0, 1.0);

	// Physical basin depth in mm
	if (winter_kind != 0) {
		float depth_mm = water_mask * winter_depth_mm;
		float solid = smoothstep(0.0, winter_kind == 1 ? 3.5 : 1.8, depth_mm);
		if (winter_kind == 1) {
			ALBEDO = mix(vec3(0.45, 0.47, 0.50), vec3(0.83, 0.86, 0.90), solid);
			ROUGHNESS = 0.92;
			ALPHA = solid;
		} else {
			float grazing = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
			ALBEDO = mix(vec3(0.26, 0.34, 0.40), vec3(0.61, 0.72, 0.79), grazing);
			ROUGHNESS = 0.2;
			ALPHA = solid * 0.75;
		}
	} else {
		float real_depth_mm = water_mask * fill * max_depth_mm;
		float depth_norm = clamp(real_depth_mm / 48.0, 0.0, 1.0);

		// 1. Beer-Lambert Law: Exponential light extinction through muddy sediment suspension.
		// Shallow water (3-10 mm) is clear & translucent; deep potholes (40-60 mm) are opaque dark chocolate mud.
		float turbidity = 1.0 - exp(-real_depth_mm * 0.065);

		// 2. Cavity Rim Occlusion: Deep potholes excavate into the ground, creating a distinct
		// embankment shadow along their inner rim that reads immediately as 3D hollow depth.
		float rim_band = smoothstep(0.16, 0.26, mask) * (1.0 - smoothstep(0.26, 0.44, mask));
		float cavity_occlusion = 1.0 - rim_band * depth_norm * 0.55;

		// 3. Meniscus Surface Tension Glint: Subtle specular highlight line where water meets wet soil.
		float meniscus = smoothstep(0.17, 0.22, mask) * (1.0 - smoothstep(0.22, 0.28, mask));
		float meniscus_glint = pow(meniscus, 2.0) * 0.30 * water_body;

		// 4. Dreamcast-style smooth surface normal + scrolling water texture in ALBEDO (no micro-specular noise).
		vec2 detail_flow = vec2(TIME) * detail_speed * vec2(0.7, 1.0);
		vec3 wd = water_detail_sample(world_position.xz, detail_flow);
		float dist_fade = 1.0 - smoothstep(55.0, 140.0, length(world_position - CAMERA_POSITION_WORLD));
		float detail_k = clamp(detail_strength * 0.25 * water_body * dist_fade, 0.0, 1.0);
		float pattern = smoothstep(0.40, 0.68, wd.x);

		// Sky reflection lookup (smooth planar/env-map feel)
		vec3 normal_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 reflected = reflect(normalize(world_position - CAMERA_POSITION_WORLD), normal_world);
		vec3 sky = horizon_color;
		if (has_sky) {
			sky = mix(texture(sky_a, reflected).rgb * tint_a, texture(sky_b, rotate_y(reflected, yaw_b)).rgb * tint_b, weather_mix);
			sky = mix(texture(sky_c, rotate_y(reflected, twilight_yaw)).rgb * tint_c, sky, daylight_mix);
			sky = mix(horizon_color, sky, smoothstep(-0.025, 0.12, reflected.y));
		} else {
			sky = sky_tint.rgb;
		}

		float view_angle = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float soft_fresnel = 1.0 - view_angle;

		// Dark damp soil albedo modulated by rim cavity occlusion
		vec3 soil_albedo = vec3(0.012, 0.009, 0.007) * cavity_occlusion;

		// Water body color: Dreamcast-style contrast between dark trough and sky-tinted pattern
		vec3 base_puddle = mix(shallow_color.rgb, deep_color.rgb, turbidity) * cavity_occlusion;
		vec3 highlight = mix(base_puddle * 1.8 + sky * 0.16, sky * 0.44, 0.38);
		vec3 water_color = mix(base_puddle * 0.72, highlight, pattern * detail_k);
		vec3 water_albedo = mix(water_color, sky * 0.45, 0.04 + 0.10 * soft_fresnel);

		ALBEDO = mix(soil_albedo, water_albedo, water_body);
		EMISSION = (sky * (0.14 * pattern * detail_k + 0.04 * soft_fresnel) + vec3(meniscus_glint * 0.30)) * water_body;

		ROUGHNESS = 0.85;
		METALLIC = 0.0;
		SPECULAR = 0.0;

		// Uniform Dreamcast-like water translucency over wet road rim
		float soil_alpha = wet_soil * 0.38;
		float base_water_alpha = mix(0.36, 0.66, turbidity);
		float water_alpha = base_water_alpha * water_body;
		ALPHA = max(soil_alpha, water_alpha) * smoothstep(0.0, 0.03, fill);
	}
}
