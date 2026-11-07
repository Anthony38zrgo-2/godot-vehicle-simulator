shader_type spatial;
render_mode cull_disabled;
uniform vec2 patch_size = vec2(1.0);
varying vec2 patch_uv;
varying vec3 world_position;
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
vec3 rotate_y(vec3 d, float yaw) {
 return vec3(cos(yaw)*d.x + sin(yaw)*d.z, d.y, -sin(yaw)*d.x + cos(yaw)*d.z);
}
void vertex() {
 patch_uv = VERTEX.xz / patch_size;
 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
uniform float fill = 0.0;
uniform float rain = 0.0;
void fragment() {
 vec2 p = patch_uv * 2.0;
 float edge = 1.0 + 0.07 * sin(p.x * 11.0 + p.y * 7.0) * sin(p.y * 9.0);
 float mask = clamp(1.0 - length(p) * edge, 0.0, 1.0);
 // Same footprint and depth curve as sample_contact().
 float radius = pow(fill, 0.25);
 float footprint = max(1.0 - (1.0 - mask) / max(radius, 0.0001), 0.0);
 float depth = footprint * fill;
 if (footprint < 0.008 || fill <= 0.0) { discard; }
 float ripple = sin(length(fract(UV * 16.0) - 0.5) * 42.0 - TIME * 7.0) * rain;
 NORMAL_MAP = normalize(vec3(ripple * 0.025, ripple * 0.025, 1.0)) * 0.5 + 0.5;
 vec3 normal_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
 vec3 reflected = reflect(normalize(world_position - CAMERA_POSITION_WORLD), normal_world);
 reflected.xz += vec2(ripple * 0.004);
 vec3 sky = horizon_color;
 if (has_sky) {
  sky = mix(texture(sky_a, reflected).rgb * tint_a, texture(sky_b, rotate_y(reflected, yaw_b)).rgb * tint_b, weather_mix);
  sky = mix(texture(sky_c, rotate_y(reflected, twilight_yaw)).rgb * tint_c, sky, daylight_mix);
  sky = mix(horizon_color, sky, smoothstep(-0.025, 0.12, reflected.y));
 }
 ALBEDO = vec3(0.035);
 EMISSION = sky * 0.85;
 METALLIC = 0.0;
 SPECULAR = 0.5;
 ROUGHNESS = mix(0.24, 0.055, smoothstep(0.0, 0.25, depth));
 ALPHA = smoothstep(0.008, 0.08, footprint) * smoothstep(0.0, 0.04, fill) * mix(0.30, 0.88, pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0));
}
