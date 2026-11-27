shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, diffuse_lambert;

// Additive spark/scrape/backfire VFX particles aligned to velocity vector,
// sharing vehicle SDF cabin exclusion and PS1 RGB555 ordered dithering.

#include "res://shaders/lib/retro/dither_quantize_fn.gdshaderinc"
#include "res://shaders/lib/vfx/billboard_sprite.gdshaderinc"
#include "res://shaders/lib/vfx/soft_particles.gdshaderinc"
#include "res://shaders/lib/vfx/vehicle_sdf_exclusion.gdshaderinc"

uniform sampler2D particle_texture : source_color, filter_nearest;
uniform float spark_emission = 0.0;
uniform bool wheel_spark = false;

uniform bool psx_enabled = true;
uniform int psx_color_bits : hint_range(2, 8) = 5;
uniform float psx_color_dither_strength : hint_range(0.0, 2.0) = 0.85;
uniform int psx_alpha_levels : hint_range(2, 16) = 4;
uniform float psx_alpha_dither_strength : hint_range(0.0, 2.0) = 0.90;
uniform float psx_dither_scale : hint_range(1.0, 4.0) = 2.0;

varying vec3 particle_world_position;
varying float near_fade;

void vertex() {
	mat4 billboard = vfx_billboard_axis_aligned(INV_VIEW_MATRIX, MODEL_MATRIX, normalize(MODEL_MATRIX[1].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	particle_world_position = (billboard * vec4(VERTEX, 1.0)).xyz;
	near_fade = vfx_near_camera_fade(MODELVIEW_MATRIX, 0.45, 1.6);
}

void fragment() {
	vec4 sprite = texture(particle_texture, UV);
	if (wheel_spark) {
		float brightness = max(sprite.r, max(sprite.g, sprite.b));
		sprite.rgb = vec3(brightness);
	}
	vec4 sample_color = sprite * COLOR;
	if (sample_color.a * near_fade < 0.005) {
		discard;
	}

	float visibility = vfx_vehicle_body_visibility(particle_world_position);
	float border_fade = vfx_uv_border_fade(UV, vec2(0.01), vec2(0.10));
	float taper = 1.0 - smoothstep(UV.y * 0.5, UV.y * 0.5 + 0.06, abs(UV.x - 0.5));
	float final_alpha = sample_color.a * visibility * near_fade * border_fade * (wheel_spark ? 1.0 : taper);
	vec3 out_color = sample_color.rgb;
	if (psx_enabled) {
		float pattern = psx_dither_4x4_sample(FRAGCOORD.xy, psx_dither_scale);
		out_color = psx_quantize_rgb_bits_pattern(out_color, pattern, psx_color_bits, psx_color_dither_strength);
		final_alpha = psx_quantize_scalar_pattern(final_alpha, pattern, psx_alpha_levels, psx_alpha_dither_strength);
	}
	if (final_alpha < 0.005) {
		discard;
	}

	ALBEDO = out_color;
	EMISSION = out_color * spark_emission;
	ALPHA = final_alpha;
}
