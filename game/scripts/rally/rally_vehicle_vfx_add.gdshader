shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, diffuse_lambert;

// Additive variant used by spark sprites whose black background must not be
// drawn. Vertex billboarding and the vehicle body exclusion match the alpha
// particle shader so impacts remain outside the cabin from every camera.

uniform sampler2D particle_texture : source_color, filter_nearest;
uniform float spark_emission = 0.0;
uniform bool wheel_spark = false;
uniform mat4 world_to_vehicle;
uniform float body_exclusion_strength : hint_range(0.0, 1.0) = 1.0;
varying vec3 particle_world_position;
varying float near_fade;

// PSX VFX finish: RGB555 + aggressive 4x4 ordered dithering on color and alpha (Option A)
uniform bool psx_enabled = true;
uniform int psx_color_bits : hint_range(2, 8) = 5;
uniform float psx_color_dither_strength : hint_range(0.0, 2.0) = 0.85;
uniform int psx_alpha_levels : hint_range(2, 16) = 4;
uniform float psx_alpha_dither_strength : hint_range(0.0, 2.0) = 0.90;
uniform float psx_dither_scale : hint_range(1.0, 4.0) = 2.0;

const float PS1_DITHER_4X4[16] = float[16](
	-4.0,  0.0, -3.0,  1.0,
	 2.0, -2.0,  3.0, -1.0,
	-3.0,  1.0, -4.0,  0.0,
	 3.0, -1.0,  2.0, -2.0
);

float psx_dither_value(vec2 frag_xy) {
	ivec2 cell = ivec2(floor(frag_xy / max(psx_dither_scale, 1.0)));
	return PS1_DITHER_4X4[(cell.y & 3) * 4 + (cell.x & 3)];
}

vec3 psx_quantize_rgb555(vec3 linear_rgb, float pattern) {
	int bits = clamp(psx_color_bits, 2, 8);
	int shift = 8 - bits;
	vec3 srgb = pow(clamp(linear_rgb, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2)) * 255.0;
	if (shift > 0 && psx_color_dither_strength > 0.0) {
		float scale = psx_color_dither_strength * float(1 << shift) / 8.0;
		srgb += vec3(pattern * scale);
	}
	ivec3 q = ivec3(clamp(srgb, vec3(0.0), vec3(255.0))) >> shift;
	vec3 out_srgb;
	if (bits >= 4) {
		ivec3 rep = (q << shift) | (q >> (bits - shift));
		out_srgb = vec3(rep) / 255.0;
	} else {
		float max_lvl = float((1 << bits) - 1);
		out_srgb = vec3(q) / max_lvl;
	}
	return pow(clamp(out_srgb, vec3(0.0), vec3(1.0)), vec3(2.2));
}

float psx_quantize_alpha(float alpha, float pattern) {
	float steps = float(max(psx_alpha_levels - 1, 1));
	float d = (pattern / 8.0) * psx_alpha_dither_strength / steps;
	float q = floor(clamp(alpha + d, 0.0, 1.0) * steps + 0.5) / steps;
	return clamp(q, 0.0, 1.0);
}

void vertex() {
	mat4 billboard = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	vec3 along = normalize(MODEL_MATRIX[1].xyz);
	vec3 across = cross(along, normalize(INV_VIEW_MATRIX[2].xyz));
	if (length(across) > 0.01) {
		billboard[0].xyz = normalize(across);
		billboard[1].xyz = along;
	}
	billboard[0].xyz *= length(MODEL_MATRIX[0].xyz);
	billboard[1].xyz *= length(MODEL_MATRIX[1].xyz);
	billboard[2].xyz *= length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	particle_world_position = (billboard * vec4(VERTEX, 1.0)).xyz;

	// Soft distance fade near camera: prevents huge fullscreen overdraw
	float cam_dist = length(MODELVIEW_MATRIX[3].xyz);
	near_fade = clamp((cam_dist - 0.45) * 1.6, 0.0, 1.0);
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

	float visibility = 1.0;
	if (body_exclusion_strength > 0.01) {
		vec3 local = (world_to_vehicle * vec4(particle_world_position, 1.0)).xyz;
		vec3 offset = abs(local - vec3(0.0, 0.865, 0.0));
		if (offset.x < 0.95 && offset.y < 0.80 && offset.z < 2.10) {
			vec3 box_distance = offset - vec3(0.74, 0.585, 1.85);
			float distance_to_body = length(max(box_distance, vec3(0.0)))
				+ min(max(box_distance.x, max(box_distance.y, box_distance.z)), 0.0) - 0.05;
			float exterior_visibility = smoothstep(0.0, 0.15, distance_to_body);
			visibility = mix(1.0, exterior_visibility, body_exclusion_strength);
		}
	}

	vec2 border = smoothstep(vec2(0.01), vec2(0.10), min(UV, 1.0 - UV));
	float taper = 1.0 - smoothstep(UV.y * 0.5, UV.y * 0.5 + 0.06, abs(UV.x - 0.5));
	float final_alpha = sample_color.a * visibility * near_fade * border.x * border.y * (wheel_spark ? 1.0 : taper);
	vec3 out_color = sample_color.rgb;
	if (psx_enabled) {
		float pattern = psx_dither_value(FRAGCOORD.xy);
		out_color = psx_quantize_rgb555(out_color, pattern);
		final_alpha = psx_quantize_alpha(final_alpha, pattern);
	}
	if (final_alpha < 0.005) {
		discard;
	}

	ALBEDO = out_color;
	EMISSION = out_color * spark_emission;
	ALPHA = final_alpha;
}
