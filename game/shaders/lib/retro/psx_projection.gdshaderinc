// Shared PSX GTE integer vertex snapping and affine texture coordinate warping.

group_uniforms psx_projection;
uniform vec2 psx_snap_resolution = vec2(320.0, 240.0);
uniform float psx_snap_strength : hint_range(0.0, 1.0) = 0.0;
uniform float psx_affine_strength : hint_range(0.0, 1.0) = 0.0;
group_uniforms;

varying vec2 v_psx_uv_over_w;
varying float v_psx_w;
varying float v_psx_affine_weight;

vec4 psx_snap_clip(vec4 clip, float distance_weight, float strength) {
	if (strength > 0.001 && clip.w > 0.25) {
		vec2 ndc = clip.xy / max(abs(clip.w), 0.0001);
		vec2 grid = max(psx_snap_resolution, vec2(32.0)) * 0.5;
		vec2 snapped = floor(ndc * grid + 0.5) / grid;
		clip.xy = mix(ndc, snapped, strength * distance_weight) * clip.w;
	}
	return clip;
}

vec4 psx_snap_clip_range(vec4 clip, float fade_start, float fade_end) {
	float dist_weight = smoothstep(fade_start, fade_end, max(clip.w, 0.0));
	return psx_snap_clip(clip, dist_weight, psx_snap_strength);
}

// Returns vec4(uv.x * w_eff, uv.y * w_eff, w_eff, affine_weight) for assignment to varyings in vertex().
vec4 psx_affine_pack(vec4 clip, vec2 uv, float fade_start, float fade_end) {
	float dist_weight = smoothstep(fade_start, fade_end, max(clip.w, 0.0));
	float w_eff = max(clip.w, 0.15);
	return vec4(uv * w_eff, w_eff, psx_affine_strength * dist_weight);
}

vec2 psx_resolve_uv(vec2 perspective_uv) {
	if (v_psx_affine_weight <= 0.001) {
		return perspective_uv;
	}
	vec2 affine_uv = v_psx_uv_over_w / max(v_psx_w, 0.0001);
	return mix(perspective_uv, affine_uv, v_psx_affine_weight);
}
