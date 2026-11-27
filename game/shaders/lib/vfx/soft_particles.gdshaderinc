// Shared particle fading: near-camera fade, UV border anti-clipping, and depth soft intersection.

float vfx_near_camera_fade(mat4 modelview, float start_m, float inv_range) {
	float cam_dist = length(modelview[3].xyz);
	return clamp((cam_dist - start_m) * inv_range, 0.0, 1.0);
}

float vfx_uv_border_fade(vec2 uv, vec2 edge_lo, vec2 edge_hi) {
	vec2 border = smoothstep(edge_lo, edge_hi, min(uv, 1.0 - uv));
	return border.x * border.y;
}

float vfx_soft_depth_fade(sampler2D depth_tex, vec2 screen_uv, mat4 inv_proj, float view_z, float soft_metres) {
	if (soft_metres <= 0.0) {
		return 1.0;
	}
	float depth = texture(depth_tex, screen_uv).r;
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z = depth * 2.0 - 1.0;
#endif
	vec4 scene_view = inv_proj * vec4(ndc, 1.0);
	float separation = view_z - scene_view.z / scene_view.w;
	return smoothstep(0.0, soft_metres, separation);
}
