// Pure spatial coordinate transforms, rotations, triplanar weights, and billboarding helpers.

vec3 rotate_y(vec3 dir, float yaw) {
	float s = sin(yaw);
	float c = cos(yaw);
	return vec3(c * dir.x + s * dir.z, dir.y, -s * dir.x + c * dir.z);
}

vec2 rotate2d(vec2 p, float cs, float sn) {
	return vec2(p.x * cs - p.y * sn, p.x * sn + p.y * cs);
}

vec3 triplanar_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / max(dot(w, vec3(1.0)), 0.001);
}

mat4 upright_billboard_y(mat4 model, mat4 view, vec3 camera_right) {
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(vec3(camera_right.x, 0.0, camera_right.z));
	vec3 forward = cross(right, up);
	return view * mat4(
		vec4(right * length(model[0].xyz), 0.0),
		vec4(up * length(model[1].xyz), 0.0),
		vec4(forward * length(model[2].xyz), 0.0),
		model[3]
	);
}
