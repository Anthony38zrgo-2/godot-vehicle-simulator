// Shared particle/precipitation billboard matrix builders and sprite sheet UV slicer.

mat4 vfx_billboard_camera(mat4 inv_view, mat4 model) {
	return mat4(inv_view[0], inv_view[1], inv_view[2], model[3]);
}

mat4 vfx_billboard_apply_scale(mat4 billboard, mat4 model) {
	billboard[0].xyz *= length(model[0].xyz);
	billboard[1].xyz *= length(model[1].xyz);
	billboard[2].xyz *= length(model[2].xyz);
	return billboard;
}

mat4 vfx_billboard_rotated(mat4 inv_view, mat4 model, float angle) {
	mat4 bb = vfx_billboard_camera(inv_view, model);
	vec3 right = bb[0].xyz;
	vec3 up = bb[1].xyz;
	bb[0].xyz = right * cos(angle) + up * sin(angle);
	bb[1].xyz = up * cos(angle) - right * sin(angle);
	return vfx_billboard_apply_scale(bb, model);
}

mat4 vfx_billboard_axis_aligned(mat4 inv_view, mat4 model, vec3 up_axis) {
	mat4 bb = vfx_billboard_camera(inv_view, model);
	vec3 facing = normalize(inv_view[2].xyz);
	vec3 across = cross(up_axis, facing);
	if (length(across) > 0.01) {
		bb[0].xyz = normalize(across);
		bb[1].xyz = up_axis;
	}
	return vfx_billboard_apply_scale(bb, model);
}

vec2 vfx_sprite_sheet_uv(vec2 uv, float frame, float total_frames, sampler2D tex) {
	if (total_frames <= 1.0) {
		return uv;
	}
	float half_texel = 0.5 * total_frames / float(textureSize(tex, 0).x);
	return vec2((frame + mix(half_texel, 1.0 - half_texel, uv.x)) / total_frames, uv.y);
}
