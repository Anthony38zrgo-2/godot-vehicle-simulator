shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert;

// Alpha-blended vehicle VFX particles (dust, splash, mud, steam, smoke, gravel, foliage)
// with soft depth intersection, vehicle cabin SDF exclusion, and PS1 RGB555 ordered dithering.

#include "res://shaders/lib/retro/dither_quantize_fn.gdshaderinc"
#include "res://shaders/lib/vfx/billboard_sprite.gdshaderinc"
#include "res://shaders/lib/vfx/soft_particles.gdshaderinc"
#include "res://shaders/lib/vfx/vehicle_sdf_exclusion.gdshaderinc"

uniform sampler2D particle_texture : source_color, filter_nearest;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float soft_intersection_metres = 0.0;
uniform float sprite_frames = 1.0;
uniform bool manual_particle_state = false;
uniform bool opaque_sprite_mask = false;

uniform bool psx_enabled = true;
uniform int psx_color_bits : hint_range(2, 8) = 5;
uniform float psx_color_dither_strength : hint_range(0.0, 2.0) = 0.85;
uniform int psx_alpha_levels : hint_range(2, 16) = 4;
uniform float psx_alpha_dither_strength : hint_range(0.0, 2.0) = 0.90;
uniform float psx_dither_scale : hint_range(1.0, 4.0) = 2.0;

varying vec3 particle_world_position;
varying float near_fade;
varying float particle_age;

void vertex() {
	particle_age = INSTANCE_CUSTOM.y;
	mat4 billboard = manual_particle_state
		? vfx_billboard_rotated(INV_VIEW_MATRIX, MODEL_MATRIX, INSTANCE_CUSTOM.x)
		: vfx_billboard_apply_scale(vfx_billboard_camera(INV_VIEW_MATRIX, MODEL_MATRIX), MODEL_MATRIX);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	particle_world_position = (billboard * vec4(VERTEX, 1.0)).xyz;
	near_fade = vfx_near_camera_fade(MODELVIEW_MATRIX, 0.45, 1.6);
}

void fragment() {
	float frame = manual_particle_state ? particle_age : min(floor(particle_age * sprite_frames), sprite_frames - 1.0);
	vec2 sprite_uv = vfx_sprite_sheet_uv(UV, frame, sprite_frames, particle_texture);
	vec4 sprite = texture(particle_texture, sprite_uv);
	vec4 sample_color = sprite * COLOR;
	if (opaque_sprite_mask) {
		if (sprite.a < 0.25) {
			discard;
		}
		sample_color.a = 1.0;
	}
	if (sample_color.a * near_fade < 0.005) {
		discard;
	}

	float visibility = vfx_vehicle_body_visibility(particle_world_position);
	float edge_fade = vfx_uv_border_fade(UV, vec2(0.015), vec2(0.18));
	visibility *= vfx_soft_depth_fade(scene_depth, SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX.z, soft_intersection_metres);

	float final_alpha = sample_color.a * visibility * edge_fade * near_fade;
	vec3 out_color = sample_color.rgb;
	if (psx_enabled) {
		float pattern = psx_dither_4x4_sample(FRAGCOORD.xy, psx_dither_scale);
		out_color = psx_quantize_rgb_bits_pattern(out_color, pattern, psx_color_bits, psx_color_dither_strength);
		if (!opaque_sprite_mask) {
			final_alpha = psx_quantize_scalar_pattern(final_alpha, pattern, psx_alpha_levels, psx_alpha_dither_strength);
		}
	}
	if (final_alpha < 0.005) {
		discard;
	}

	ALBEDO = out_color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = final_alpha;
}
