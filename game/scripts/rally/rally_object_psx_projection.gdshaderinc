uniform vec2 psx_snap_resolution = vec2(320.0, 240.0);
uniform float psx_snap_strength : hint_range(0.0, 1.0) = 0.54;
uniform float psx_affine_strength : hint_range(0.0, 1.0) = 0.51;

varying vec2 psx_object_uv_over_plane;
varying float psx_object_w;
varying float psx_object_affine;

vec4 psx_object_snap(vec4 clip, float distance_weight) {
	if (clip.w > 0.25) {
		vec2 ndc = clip.xy / clip.w;
		vec2 grid = max(psx_snap_resolution, vec2(32.0)) * 0.5;
		vec2 snapped = floor(ndc * grid + 0.5) / grid;
		clip.xy = mix(ndc, snapped, psx_snap_strength * distance_weight) * clip.w;
	}
	return clip;
}

vec2 psx_object_texture_uv(vec2 perspective_uv) {
	vec2 affine_uv = psx_object_uv_over_plane / max(psx_object_w, 0.001);
	return mix(perspective_uv, affine_uv, psx_object_affine);
}

mat4 psx_upright_billboard(mat4 model, mat4 view, vec3 camera_right) {
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(vec3(camera_right.x, 0.0, camera_right.z));
	vec3 forward = cross(right, up);
	return view * mat4(vec4(right * length(model[0].xyz), 0.0),
		vec4(up * length(model[1].xyz), 0.0),
		vec4(forward * length(model[2].xyz), 0.0), model[3]);
}
