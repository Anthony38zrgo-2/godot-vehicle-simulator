shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Camera-facing unshaded precipitation billboard sprite (rain streaks and snow flakes).

#include "res://shaders/lib/vfx/billboard_sprite.gdshaderinc"
#include "res://shaders/lib/vfx/soft_particles.gdshaderinc"

uniform sampler2D particle_texture : source_color, filter_linear_mipmap;
uniform float opacity = 0.55;
uniform vec3 tint_color = vec3(1.0);
uniform float ambient_brightness = 1.0;
uniform float near_start_m = 0.9;
uniform float near_end_m = 3.6;
uniform float far_start_m = 22.0;
uniform float far_end_m = 38.0;
uniform float sprite_frames = 1.0;
uniform bool snow_sway = false;
uniform vec3 rain_direction = vec3(0.0);

varying float distance_fade;
varying flat float sprite_frame;

void vertex() {
	sprite_frame = mod(float(INSTANCE_ID), sprite_frames);
	mat4 billboard;
	if (length(rain_direction) > 0.1) {
		billboard = vfx_billboard_axis_aligned(INV_VIEW_MATRIX, MODEL_MATRIX, -rain_direction);
	} else {
		billboard = vfx_billboard_camera(INV_VIEW_MATRIX, MODEL_MATRIX);
		if (snow_sway) {
			billboard[3].xyz += INV_VIEW_MATRIX[0].xyz * sin(TIME * 2.7 + float(INSTANCE_ID) * 1.73) * 0.13;
		}
		billboard = vfx_billboard_apply_scale(billboard, MODEL_MATRIX);
	}
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float distance_m = length((VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz);
	distance_fade = smoothstep(near_start_m, near_end_m, distance_m)
		* (1.0 - smoothstep(far_start_m, far_end_m, distance_m));
}

void fragment() {
	vec2 sprite_uv = vfx_sprite_sheet_uv(UV, sprite_frame, sprite_frames, particle_texture);
	vec4 sample_color = texture(particle_texture, sprite_uv) * COLOR;
	float border_fade = vfx_uv_border_fade(UV, vec2(0.01), vec2(0.12));
	ALBEDO = tint_color * ambient_brightness;
	ALPHA = sample_color.a * opacity * distance_fade * border_fade;
}
