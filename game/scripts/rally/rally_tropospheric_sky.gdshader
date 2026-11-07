shader_type sky;
render_mode use_debanding;

uniform samplerCube sky_a : source_color, filter_linear_mipmap;
uniform samplerCube sky_b : source_color, filter_linear_mipmap;
uniform samplerCube sky_c : source_color, filter_linear_mipmap;
uniform float weather_mix = 0.0;
uniform float daylight_mix = 0.0;
uniform float twilight_yaw = 0.0;
uniform float yaw_b = 0.0;
uniform vec3 tint_a = vec3(1.0);
uniform vec3 tint_c = vec3(1.0);
uniform vec3 tint_b = vec3(1.0);
uniform vec3 horizon_color : source_color;

vec3 rotate_y(vec3 dir, float yaw) {
	float s = sin(yaw);
	float c = cos(yaw);
	return vec3(c * dir.x + s * dir.z, dir.y, -s * dir.x + c * dir.z);
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = horizon_color;
	} else {
		vec3 color = texture(sky_a, EYEDIR).rgb * tint_a;
		if (weather_mix > 0.0) {
			vec3 second = texture(sky_b, rotate_y(EYEDIR, yaw_b)).rgb * tint_b;
			color = mix(color, second, weather_mix);
		}
		if (daylight_mix < 1.0) {
			vec3 twilight = texture(sky_c, rotate_y(EYEDIR, twilight_yaw)).rgb * tint_c;
			color = mix(twilight, color, daylight_mix);
		}
		// Source's lower hemisphere is blank. Use the same horizon as the terrain fog.
		COLOR = mix(horizon_color, color, smoothstep(-0.025, 0.12, EYEDIR.y));
	}
}
