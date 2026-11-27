shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float car_speed_mps : hint_range(0.0, 80.0) = 0.0;
uniform float rain_scroll = 0.0;
uniform bool is_cockpit_view = true;

uniform float bead_scale = 38.0;
uniform float slider_scale = 11.0;
uniform float wind_slant : hint_range(0.0, 0.5) = 0.18;
uniform float slide_dir : hint_range(-1.0, 1.0) = -1.0;
uniform float fall_speed : hint_range(0.0, 0.5) = 0.10;

#include "res://shaders/lib/math/hash_noise.gdshaderinc"
#include "res://shaders/lib/math/coordinates.gdshaderinc"
#include "res://shaders/lib/vehicle/glass_droplets.gdshaderinc"

void fragment() {
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	if (is_cockpit_view && rain_intensity > 0.005) {
		float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
		vec2 uv = vec2(SCREEN_UV.x * aspect, 1.0 - SCREEN_UV.y);

		float speed_norm = clamp(car_speed_mps / 28.0, 0.0, 1.0);
		uv.x += (uv.y - 0.5) * wind_slant * speed_norm;

		float t = rain_scroll * 0.35 + TIME * fall_speed;
		float ri = rain_intensity;

		vec3 b1 = glass_beads_2d(uv, bead_scale, ri * 0.58, 1.0);
		vec3 b2 = glass_beads_2d(uv, bead_scale * 2.4, ri * 0.55, 5.0);
		vec3 s1 = glass_slider_trails_2d(uv, slider_scale, ri * 0.52, 3.0, t, slide_dir);

		vec2 off = b1.xy + b2.xy * 0.65 + s1.xy;
		float mask = clamp(max(max(b1.z, b2.z * 0.78), s1.z), 0.0, 1.0);

		if (mask > 0.003) {
			float len_off = clamp(length(off), 0.0, 1.0);
			float rim = smoothstep(0.45, 0.95, len_off);
			vec2 dd = -off;
			float spec = smoothstep(0.36, 0.0, length(dd - vec2(-0.34, 0.38)));
			float bottom_bounce = smoothstep(0.48, 0.0, length(dd - vec2(0.18, -0.45))) * 0.28;

			vec3 body_col = mix(vec3(0.56, 0.64, 0.72), vec3(0.14, 0.18, 0.24), rim);
			col = body_col + vec3(0.88, 0.94, 1.0) * (spec * 0.72 + bottom_bounce);
			alpha = clamp(smoothstep(0.0, 0.25, mask) * (0.28 + 0.36 * rim + 0.32 * spec), 0.0, 0.82);
		}
	}
	ALBEDO = col;
	ALPHA = alpha;
}
