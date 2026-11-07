shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

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
uniform float rain = 0.0;
uniform float edge_softness = 0.18;
uniform vec4 shallow_color : source_color = vec4(0.065, 0.052, 0.038, 0.22);
uniform vec4 deep_color : source_color = vec4(0.015, 0.010, 0.006, 0.88);

vec3 rotate_y(vec3 d, float yaw) {
	return vec3(cos(yaw) * d.x + sin(yaw) * d.z, d.y, -sin(yaw) * d.x + cos(yaw) * d.z);
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
	if (fill <= 0.001) {
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

	// 4. Wave & Ripple Dynamics modulated by depth:
	// Shallow puddles exhibit high-frequency capillary ripples; deep pools allow broad gravity waves.
	vec3 n_mod = NORMAL;
	if (water_body > 0.01 && rain > 0.02) {
		float freq1 = mix(28.0, 14.0, depth_norm);
		float freq2 = mix(42.0, 20.0, depth_norm);
		vec2 uv1 = fract(UV * freq1 + vec2(0.12, 0.18)) - 0.5;
		vec2 uv2 = fract(UV * freq2 + vec2(0.65, 0.42)) - 0.5;
		float r1 = sin(length(uv1) * mix(52.0, 24.0, depth_norm) - TIME * 7.5);
		float r2 = sin(length(uv2) * mix(68.0, 32.0, depth_norm) - TIME * 10.5);
		float wave_amplitude = mix(0.020, 0.055, depth_norm);
		float ripples = (r1 * 0.60 + r2 * 0.40) * rain * wave_amplitude * water_body;
		n_mod = normalize(NORMAL + TANGENT * ripples + BINORMAL * ripples);
	}
	NORMAL = n_mod;

	// Sky reflection lookup
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

	// Fresnel re-calibrated for low chase-camera grazing angles (dot(N,V) ~ 0.07 to 0.22):
	float view_angle = clamp(dot(NORMAL, VIEW) * 2.8, 0.0, 1.0);
	float fresnel = pow(1.0 - view_angle, 3.0) * water_body;

	// Dark damp soil albedo modulated by rim cavity occlusion
	vec3 soil_albedo = vec3(0.012, 0.009, 0.007) * cavity_occlusion;

	// Water body color: clear amber/clay in shallow water, deep espresso mud in deep puddles
	vec3 water_color = mix(shallow_color.rgb, deep_color.rgb, turbidity) * cavity_occlusion;
	vec3 water_albedo = mix(water_color, sky * 0.55, fresnel * 0.32);

	ALBEDO = mix(soil_albedo, water_albedo, water_body);
	EMISSION = (sky * fresnel * 0.32 + vec3(meniscus_glint)) * water_body;

	// Roughness: damp mud = 0.48; shallow water = 0.08 (ground contact); deep water = 0.02 (liquid glass)
	ROUGHNESS = mix(0.48, mix(0.08, 0.02, turbidity), water_body);
	METALLIC = 0.0;
	SPECULAR = mix(0.22, 0.98, water_body);

	// Transparency:
	// - Wet soil ring: alpha ~0.38 darkens the underlying road gravel/dirt texture
	// - Shallow water (turbidity ~ 0.25): alpha ~0.24 (gravel & rocks underneath clearly visible)
	// - Deep water (turbidity ~ 0.95): alpha ~0.88 (impenetrable muddy water that hides the road)
	float soil_alpha = wet_soil * 0.38;
	float base_water_alpha = mix(0.22, 0.88, turbidity);
	float water_alpha = (base_water_alpha + fresnel * (1.0 - base_water_alpha) * 0.50) * water_body;
	ALPHA = max(soil_alpha, water_alpha) * smoothstep(0.0, 0.03, fill);
}
