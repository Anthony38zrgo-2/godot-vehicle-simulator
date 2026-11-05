shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert;

uniform sampler2D particle_texture : source_color, filter_linear_mipmap;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float soft_intersection_metres = 0.0;
uniform mat4 world_to_vehicle;
uniform bool unlit = false;
uniform float body_exclusion_strength : hint_range(0.0, 1.0) = 1.0;
varying vec3 particle_world_position;
varying float near_fade;

void vertex() {
	// Face the camera while preserving each particle's size.
	mat4 billboard = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
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
	vec4 sample_color = texture(particle_texture, UV) * COLOR;
	if (sample_color.a * near_fade < 0.005) {
		discard;
	}

	float visibility = 1.0;
	if (body_exclusion_strength > 0.01) {
		vec3 local = (world_to_vehicle * vec4(particle_world_position, 1.0)).xyz;
		vec3 offset = abs(local - vec3(0.0, 0.865, 0.0));
		// Fast AABB early exit: skip expensive 3D SDF for quads outside the vehicle boundary
		if (offset.x < 0.95 && offset.y < 0.80 && offset.z < 2.10) {
			vec3 box_distance = offset - vec3(0.74, 0.585, 1.85);
			float distance_to_body = length(max(box_distance, vec3(0.0)))
				+ min(max(box_distance.x, max(box_distance.y, box_distance.z)), 0.0) - 0.05;
			float exterior_visibility = smoothstep(0.0, 0.15, distance_to_body);
			visibility = mix(1.0, exterior_visibility, body_exclusion_strength);
		}
	}

	// Some source sprites have visible alpha right up to the texture edge.
	vec2 border = smoothstep(vec2(0.015), vec2(0.18), min(UV, 1.0 - UV));
	float edge_fade = border.x * border.y;

	// Fade clouds into opaque geometry instead of cutting the billboard at contact.
	if (soft_intersection_metres > 0.0) {
		float depth = texture(scene_depth, SCREEN_UV).r;
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ndc.z = depth * 2.0 - 1.0;
#endif
		vec4 scene_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		float separation = VERTEX.z - scene_view.z / scene_view.w;
		visibility *= smoothstep(0.0, soft_intersection_metres, separation);
	}

	float final_alpha = sample_color.a * visibility * edge_fade * near_fade;
	if (final_alpha < 0.005) {
		discard;
	}

	ALBEDO = unlit ? vec3(0.0) : sample_color.rgb;
	EMISSION = unlit ? sample_color.rgb : vec3(0.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = final_alpha;
}
