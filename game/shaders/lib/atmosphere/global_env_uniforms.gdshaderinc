// Global scene atmosphere & weather uniforms updated once per frame via ShaderEnvironmentBus.

global uniform vec3 rally_sun_dir;
global uniform vec3 rally_sun_color;
global uniform vec3 rally_ambient_color;
global uniform vec3 rally_haze_color;
global uniform vec2 rally_wind_vec;
global uniform float rally_rain_intensity;
global uniform vec3 rally_sky_horizon;
global uniform vec4 rally_sky_mix; // x=weather_mix, y=daylight_mix, z=twilight_yaw, w=yaw_b
global uniform vec3 rally_sky_tint_a;
global uniform vec3 rally_sky_tint_b;
global uniform vec3 rally_sky_tint_c;
global uniform float rally_sky_enabled;
