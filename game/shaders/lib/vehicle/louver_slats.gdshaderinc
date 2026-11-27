// Parameterized rear louver slat edge shading (decoupled from base vehicle shader).

group_uniforms louver_slats;
uniform vec4 louver_slat_edges_z = vec4(0.793, 0.912, 1.020, 1.131);
uniform float louver_start_z = 0.675;
uniform float louver_half_width = 0.516;
uniform vec3 louver_fill_color : source_color = vec3(0.015, 0.017, 0.019);
group_uniforms;

varying vec2 v_louver_xz;
varying vec3 v_louver_up_view;

vec3 louver_up_view_dir(mat3 mv_normal_mat) {
	return normalize(mv_normal_mat * vec3(0.0, 1.0, 0.0));
}

vec3 louver_emission(vec3 view_vertex) {
	vec3 face_normal = normalize(cross(dFdx(view_vertex), dFdy(view_vertex)));
	float top_face = smoothstep(0.943, 0.966, abs(dot(face_normal, v_louver_up_view)));
	float z = v_louver_xz.y;
	vec4 edge_distance = abs(vec4(z) - louver_slat_edges_z);
	float nearest_edge = min(min(edge_distance.x, edge_distance.y), min(edge_distance.z, edge_distance.w));
	float pixel_width = clamp(fwidth(z), 0.001, 0.010);
	float lip = 1.0 - smoothstep(0.004, 0.012 + pixel_width, nearest_edge);
	float across = 1.0 - smoothstep(louver_half_width - 0.076, louver_half_width, abs(v_louver_xz.x));
	float slats = smoothstep(louver_start_z, louver_start_z + 0.04, z) * across * top_face;
	return louver_fill_color * slats * (0.35 + 1.55 * lip);
}
