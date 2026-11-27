// Pure hydrological optics helpers: Beer-Lambert turbidity, Schlick Fresnel, meniscus glint, PS2 6-step ramp.

float water_beer_lambert_turbidity(float depth_mm, float turbidity_rate) {
	return 1.0 - exp(-max(depth_mm, 0.0) * turbidity_rate);
}

float water_schlick_fresnel(float view_angle, float shore_mirror) {
	float soft_fresnel = 1.0 - clamp(view_angle, 0.0, 1.0);
	return clamp(0.08 + 0.90 * pow(soft_fresnel, 2.50), 0.0, 0.94) * shore_mirror;
}

float water_meniscus_glint(float vis_mask, float shore_thresh, float water_body) {
	float meniscus = smoothstep(shore_thresh - 0.01, shore_thresh + 0.035, vis_mask)
		* (1.0 - smoothstep(shore_thresh + 0.035, shore_thresh + 0.09, vis_mask));
	return pow(meniscus, 2.0) * 0.22 * water_body;
}

vec3 water_ps2_palette_ramp(
	float ramp_t,
	vec3 step0,
	vec3 step1,
	vec3 step2,
	vec3 step3,
	vec3 step4,
	vec3 step5
) {
	if (ramp_t < 0.1667) {
		return step0;
	} else if (ramp_t < 0.3333) {
		return step1;
	} else if (ramp_t < 0.5) {
		return step2;
	} else if (ramp_t < 0.6667) {
		return step3;
	} else if (ramp_t < 0.8333) {
		return step4;
	}
	return step5;
}
