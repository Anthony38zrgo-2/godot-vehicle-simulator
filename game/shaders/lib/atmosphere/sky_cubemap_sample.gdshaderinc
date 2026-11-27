// Pure tropospheric multi-cubemap sampling helper (shared between sky dome and water reflections).
// Depends on: lib/math/coordinates.gdshaderinc

vec3 sample_tropospheric_cubemaps(
	samplerCube sky_a,
	samplerCube sky_b,
	samplerCube sky_c,
	vec3 dir,
	float weather_mix,
	float daylight_mix,
	float twilight_yaw,
	float yaw_b,
	vec3 tint_a,
	vec3 tint_b,
	vec3 tint_c,
	vec3 horizon_color,
	float horizon_top
) {
	vec3 color = texture(sky_a, dir).rgb * tint_a;
	if (weather_mix > 0.02) {
		vec3 second = texture(sky_b, rotate_y(dir, yaw_b)).rgb * tint_b;
		color = (weather_mix >= 0.98) ? second : mix(color, second, weather_mix);
	}
	if (daylight_mix < 0.98) {
		vec3 twilight = texture(sky_c, rotate_y(dir, twilight_yaw)).rgb * tint_c;
		color = mix(twilight, color, daylight_mix);
	}
	return mix(horizon_color, color, smoothstep(-0.025, horizon_top, dir.y));
}
