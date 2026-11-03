shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert;

uniform sampler2D particle_texture : source_color, filter_linear_mipmap;
uniform mat4 world_to_vehicle;
uniform bool unlit = false;
uniform float body_exclusion_strength : hint_range(0.0, 1.0) = 1.0;
varying vec3 particle_world_position;

void vertex() {
	// Face the camera while preserving each particle's size.
	mat4 billboard = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	billboard[0].xyz *= length(MODEL_MATRIX[0].xyz);
	billboard[1].xyz *= length(MODEL_MATRIX[1].xyz);
	billboard[2].xyz *= length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	particle_world_position = (billboard * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 local = (world_to_vehicle * vec4(particle_world_position, 1.0)).xyz;
	// A rounded exclusion with a soft outside edge avoids a rectangular hole
	// in the trail when the car is viewed from the chase camera.
	vec3 box_distance = abs(local - vec3(0.0, 0.865, 0.0)) - vec3(0.74, 0.585, 1.85);
	float distance_to_body = length(max(box_distance, vec3(0.0)))
		+ min(max(box_distance.x, max(box_distance.y, box_distance.z)), 0.0) - 0.20;
	float exterior_visibility = smoothstep(0.0, 0.55, distance_to_body);
	float visibility = mix(1.0, exterior_visibility, body_exclusion_strength);
	vec4 sample_color = texture(particle_texture, UV) * COLOR;
	ALBEDO = unlit ? vec3(0.0) : sample_color.rgb;
	EMISSION = unlit ? sample_color.rgb : vec3(0.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = sample_color.a * visibility;
}
