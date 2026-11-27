shader_type sky;
render_mode use_debanding;

// Multi-cubemap tropospheric sky dome blending clear, weather, and twilight layers.

#include "res://shaders/lib/math/coordinates.gdshaderinc"
#include "res://shaders/lib/atmosphere/sky_cubemap_sample.gdshaderinc"

uniform samplerCube sky_a : source_color, filter_nearest_mipmap;
uniform samplerCube sky_b : source_color, filter_nearest_mipmap;
uniform samplerCube sky_c : source_color, filter_nearest_mipmap;
uniform float weather_mix = 0.0;
uniform float daylight_mix = 0.0;
uniform float twilight_yaw = 0.0;
uniform float yaw_b = 0.0;
uniform vec3 tint_a = vec3(1.0);
uniform vec3 tint_c = vec3(1.0);
uniform vec3 tint_b = vec3(1.0);
uniform vec3 horizon_color : source_color;

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = horizon_color;
	} else {
		COLOR = sample_tropospheric_cubemaps(
			sky_a, sky_b, sky_c,
			EYEDIR,
			weather_mix, daylight_mix, twilight_yaw, yaw_b,
			tint_a, tint_b, tint_c,
			horizon_color, 0.12
		);
	}
}
