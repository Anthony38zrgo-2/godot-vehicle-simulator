shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert;

// Camera-facing sprite used by the weather adapter for the CMR2 rain and snow
// bitmaps. Distance fades prevent a near-plane quad from covering the screen
// and keep the precipitation layer readable without a second particle system.

uniform sampler2D particle_texture : source_color, filter_linear_mipmap;
uniform float opacity = 0.55;
uniform vec3 tint_color = vec3(1.0);
uniform float near_start_m = 0.9;
uniform float near_end_m = 3.6;
uniform float far_start_m = 22.0;
uniform float far_end_m = 38.0;
varying float distance_fade;
varying flat float sprite_frame;
uniform float sprite_frames = 1.0;
uniform bool snow_sway = false;
uniform vec3 rain_direction = vec3(0.0);

void vertex() {
	sprite_frame = mod(float(INSTANCE_ID), sprite_frames);
	mat4 billboard = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	if (length(rain_direction) > 0.1) {
		vec3 facing = normalize(INV_VIEW_MATRIX[2].xyz);
		vec3 across = cross(-rain_direction, facing);
		if (length(across) > 0.01) {
			billboard[0].xyz = normalize(across);
			billboard[1].xyz = -rain_direction;
		}
	} else if (snow_sway) {
		billboard[3].xyz += INV_VIEW_MATRIX[0].xyz * sin(TIME * 2.7 + float(INSTANCE_ID) * 1.73) * 0.13;
	}
	billboard[0].xyz *= length(MODEL_MATRIX[0].xyz);
	billboard[1].xyz *= length(MODEL_MATRIX[1].xyz);
	billboard[2].xyz *= length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float distance_m = length((VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz);
	distance_fade = smoothstep(near_start_m, near_end_m, distance_m)
		* (1.0 - smoothstep(far_start_m, far_end_m, distance_m));
}

void fragment() {
	vec2 sprite_uv = UV;
	if (sprite_frames > 1.0) {
		float half_texel = 0.5 * sprite_frames / float(textureSize(particle_texture, 0).x);
		sprite_uv.x = (sprite_frame + mix(half_texel, 1.0 - half_texel, UV.x)) / sprite_frames;
	}
	vec4 sample_color = texture(particle_texture, sprite_uv) * COLOR;
	vec2 border = smoothstep(vec2(0.01), vec2(0.12), min(UV, 1.0 - UV));
	float alpha = sample_color.a * opacity * distance_fade * border.x * border.y;
	if (alpha < 0.005) {
		discard;
	}
	ALBEDO = tint_color;
	ALPHA = alpha;
}
