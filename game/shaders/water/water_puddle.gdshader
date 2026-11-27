shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert;

// Dynamic bathymetric puddle and winter slush shader using shared hydrology, rain ripples,
// wind capillary slopes, CPU-matched shoreline masks, and tropospheric sky reflections.

#include "res://shaders/lib/math/hash_noise.gdshaderinc"
#include "res://shaders/lib/math/coordinates.gdshaderinc"
#include "res://shaders/lib/math/cpu_gpu_parity.gdshaderinc"
#include "res://shaders/lib/atmosphere/global_env_uniforms.gdshaderinc"
#include "res://shaders/lib/atmosphere/sky_cubemap_sample.gdshaderinc"
#include "res://shaders/lib/water/water_waves.gdshaderinc"
#include "res://shaders/lib/water/water_optics.gdshaderinc"

uniform vec2 patch_size = vec2(1.0);
varying vec2 patch_uv;
varying vec3 world_position;
varying float v_road_weight;

uniform bool use_global_env = false;
uniform bool enable_water_reflections = false;
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
uniform vec4 sky_tint : source_color = vec4(0.56, 0.82, 0.96, 1.0);
uniform vec3 sun_dir = vec3(0.0, 0.7, 0.7);
uniform vec3 sun_color = vec3(1.0, 0.95, 0.85);

uniform sampler2D puddle_mask : hint_default_white, filter_linear_mipmap;
uniform bool use_mask_texture = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec4 shape_params = vec4(0.0);
uniform float max_depth_mm = 48.0;
uniform float fill = 0.0;
uniform int winter_kind = 0;
uniform float winter_depth_mm = 0.0;
uniform float rain = 0.0;
uniform vec2 wind_vec = vec2(1.2, 0.4);
uniform float edge_softness = 0.18;
uniform float turbidity_rate = 0.065;
uniform vec4 shallow_color : source_color = vec4(0.46, 0.78, 0.94, 0.38);
uniform vec4 deep_color : source_color = vec4(0.14, 0.36, 0.56, 0.90);

void vertex() {
	patch_uv = VERTEX.xz / max(patch_size, vec2(0.1));
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_road_weight = COLOR.r;
}

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
		vec2 muv = warp_mask_uv(patch_uv, uv_scale, shape_params);
		if (muv.x < 0.0 || muv.x > 1.0 || muv.y < 0.0 || muv.y > 1.0) {
			discard;
		}
		mask = texture(puddle_mask, muv).r;
	} else {
		mask = procedural_mask(patch_uv, shape_params);
	}

	mask *= smoothstep(0.04, 0.65, v_road_weight);
	if (mask <= 0.006) {
		discard;
	}

	float cam_dist = length(world_position - CAMERA_POSITION_WORLD);
	vec3 micro_rel = puddle_micro_relief(world_position.xz, winter_kind == 0 && cam_dist < 40.0);
	float shore_thresh = (winter_kind == 1) ? 0.18 : shore_threshold_for_fill(fill);
	float rim_zone = 1.0 - smoothstep(shore_thresh, min(shore_thresh + 0.30, 0.96), mask);
	float vis_mask = mask + micro_rel.x * (0.11 + 0.08 * edge_softness) * rim_zone * smoothstep(0.04, 0.22, mask);

	float wet_soil = smoothstep(0.05, max(shore_thresh, 0.24), vis_mask);
	float water_body = smoothstep(shore_thresh, min(shore_thresh + 0.08 + edge_softness * 0.10, 0.96), vis_mask);
	float water_mask = clamp((vis_mask - shore_thresh) / max(1.0 - shore_thresh, 0.18), 0.0, 1.0);

	if (winter_kind == 1) {
		float depth_mm = water_mask * winter_depth_mm;
		float edge_fade = smoothstep(0.0, 4.5, depth_mm);
		float core_dense = smoothstep(2.0, 18.0, depth_mm);
		float grain_break = clamp(micro_rel.x * 0.24 * (1.0 - core_dense * 0.55), -0.14, 0.14);
		float snow_alpha = clamp(edge_fade * mix(0.26, 0.76, core_dense) + grain_break * edge_fade, 0.0, 0.80);
		ALBEDO = mix(vec3(0.54, 0.58, 0.63), vec3(0.86, 0.89, 0.93), core_dense);
		ROUGHNESS = mix(0.68, 0.92, core_dense);
		SPECULAR = mix(0.24, 0.12, core_dense);
		ALPHA = snow_alpha;
	} else {
		float active_rain = use_global_env ? rally_rain_intensity : rain;
		vec2 active_wind = use_global_env ? rally_wind_vec : wind_vec;
		vec3 active_horizon = use_global_env ? rally_sky_horizon : horizon_color;

		float real_depth_mm = water_mask * fill * max_depth_mm;
		float depth_norm = clamp(real_depth_mm / 48.0, 0.0, 1.0);
		float shore_depth = smoothstep(0.0, 7.0, real_depth_mm);

		float turbidity = water_beer_lambert_turbidity(real_depth_mm, turbidity_rate);
		float turbidity_alpha = water_beer_lambert_turbidity(real_depth_mm, turbidity_rate * 0.38);

		float rim_band = smoothstep(shore_thresh, shore_thresh + 0.10, vis_mask) * (1.0 - smoothstep(shore_thresh + 0.10, shore_thresh + 0.32, vis_mask));
		float cavity_occlusion = 1.0 - rim_band * depth_norm * 0.35;
		float meniscus_glint = water_meniscus_glint(vis_mask, shore_thresh, water_body);

		float dist_fade = 1.0 - smoothstep(45.0, 95.0, cam_dist);
		float detail_k = clamp(detail_strength * 0.22 * water_body * dist_fade, 0.0, 1.0);
		float pattern = 0.5;
		if (detail_k > 0.005) {
			vec2 detail_flow = active_wind * (TIME * 0.035) + vec2(TIME) * detail_speed * vec2(0.4, 0.6);
			vec3 wd = water_detail_sample(world_position.xz, detail_flow);
			pattern = smoothstep(0.38, 0.68, wd.x);
		}

		float ripple_damping = smoothstep(shore_thresh, min(shore_thresh + 0.18, 0.95), vis_mask) * dist_fade;
		vec2 rain_grad = rain_drop_ripples_grad(world_position.xz, TIME, active_rain, cam_dist) * ripple_damping;
		vec2 wind_grad = (cam_dist < 70.0) ? (puddle_wind_slope(world_position.xz, TIME, depth_norm, active_wind) * ripple_damping) : vec2(0.0);
		vec2 shore_grain_grad = micro_rel.yz * (1.0 - shore_depth) * 0.15;
		vec2 wave_slope = wind_grad + rain_grad + shore_grain_grad;

		vec3 base_world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 normal_world = normalize(base_world_n + vec3(wave_slope.x, 0.0, wave_slope.y));
		NORMAL = normalize((VIEW_MATRIX * vec4(mix(base_world_n, normal_world, water_body), 0.0)).xyz);

		vec3 view_dir_world = normalize(world_position - CAMERA_POSITION_WORLD);
		vec3 reflected = reflect(view_dir_world, normal_world);
		vec3 refl_dir = normalize(vec3(reflected.x, max(reflected.y, 0.015), reflected.z));

		vec3 sky = active_horizon;
		if (enable_water_reflections && has_sky) {
			float eff_wmix = use_global_env ? rally_sky_mix.x : weather_mix;
			float eff_dmix = use_global_env ? rally_sky_mix.y : daylight_mix;
			float eff_tyaw = use_global_env ? rally_sky_mix.z : twilight_yaw;
			float eff_yb = use_global_env ? rally_sky_mix.w : yaw_b;
			vec3 eff_ta = use_global_env ? rally_sky_tint_a : tint_a;
			vec3 eff_tb = use_global_env ? rally_sky_tint_b : tint_b;
			vec3 eff_tc = use_global_env ? rally_sky_tint_c : tint_c;
			sky = sample_tropospheric_cubemaps(
				sky_a, sky_b, sky_c,
				refl_dir,
				eff_wmix, eff_dmix, eff_tyaw, eff_yb,
				eff_ta, eff_tb, eff_tc,
				active_horizon, 0.05
			);
			sky = mix(active_horizon, sky, smoothstep(-0.02, 0.05, reflected.y));
		} else {
			sky = sky_tint.rgb;
		}

		float view_angle = clamp(dot(normal_world, -view_dir_world), 0.0, 1.0);
		float shore_mirror = pow(shore_depth, 0.68);
		float schlick_fresnel = water_schlick_fresnel(view_angle, shore_mirror);

		vec3 soil_albedo = vec3(0.018, 0.018, 0.019) * cavity_occlusion;
		vec3 base_puddle = mix(shallow_color.rgb, deep_color.rgb, turbidity) * cavity_occlusion;
		float edge_color_mix = smoothstep(0.0, 2.5, real_depth_mm);
		base_puddle = mix(soil_albedo, base_puddle, edge_color_mix);
		vec3 sky_refl = mix(sky, mix(shallow_color.rgb, deep_color.rgb, turbidity * 0.5), 0.35);
		vec3 highlight = base_puddle * 1.25;
		if (enable_water_reflections) {
			highlight = mix(highlight + sky_refl * 0.24, sky_refl * 0.78, 0.45);
		}
		vec3 water_color = mix(base_puddle * 0.92, highlight, pattern * detail_k * shore_depth);
		vec3 water_albedo = enable_water_reflections ? mix(water_color, sky_refl * 0.95, schlick_fresnel * 0.68) : water_color;

		ALBEDO = mix(soil_albedo, water_albedo, water_body);
		if (enable_water_reflections) {
			EMISSION = (sky_refl * (0.12 * pattern * detail_k * shore_depth + 0.48 * schlick_fresnel) + sky_refl * (meniscus_glint * 0.24)) * water_body;
		}

		ROUGHNESS = mix(0.42, enable_water_reflections ? 0.02 + 0.08 * (1.0 - shore_depth) : 0.62, water_body);
		METALLIC = 0.0;
		SPECULAR = enable_water_reflections ? mix(0.20, 0.98, water_body * (0.45 + 0.55 * shore_mirror)) : 0.0;

		float soil_alpha = wet_soil * (1.0 - water_body * 0.85) * 0.18 * smoothstep(0.0, 0.12, fill);
		float vertical_water_alpha = mix(0.32, 0.72, turbidity_alpha);
		float base_water_alpha = enable_water_reflections ? clamp(mix(vertical_water_alpha, 0.86, schlick_fresnel * 0.85), 0.24, 0.86) : vertical_water_alpha;
		float water_alpha = base_water_alpha * water_body * pow(clamp(water_mask * 1.45, 0.0, 1.0), 0.78);
		ALPHA = max(soil_alpha, water_alpha);
	}
}
