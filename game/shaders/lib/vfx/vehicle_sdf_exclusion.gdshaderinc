// Parameterized vehicle cabin AABB/SDF exclusion for exterior VFX particles.

group_uniforms vehicle_exclusion;
uniform mat4 world_to_vehicle;
uniform float body_exclusion_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec3 body_exclusion_center = vec3(0.0, 0.865, 0.0);
uniform vec3 body_exclusion_half_extents = vec3(0.74, 0.585, 1.85);
uniform vec3 body_exclusion_cull_bounds = vec3(0.95, 0.80, 2.10);
group_uniforms;

float vfx_vehicle_body_visibility(vec3 particle_world_pos) {
	if (body_exclusion_strength <= 0.01) {
		return 1.0;
	}
	vec3 local = (world_to_vehicle * vec4(particle_world_pos, 1.0)).xyz;
	vec3 offset = abs(local - body_exclusion_center);
	if (offset.x < body_exclusion_cull_bounds.x && offset.y < body_exclusion_cull_bounds.y && offset.z < body_exclusion_cull_bounds.z) {
		vec3 box_distance = offset - body_exclusion_half_extents;
		float distance_to_body = length(max(box_distance, vec3(0.0)))
			+ min(max(box_distance.x, max(box_distance.y, box_distance.z)), 0.0) - 0.05;
		float exterior_visibility = smoothstep(0.0, 0.15, distance_to_body);
		return mix(1.0, exterior_visibility, body_exclusion_strength);
	}
	return 1.0;
}
