// Data-Driven banded body paint & quantized clearcoat/glass reflection bands.
// Extracted from monolithic toon shader to decouple vehicle-specific shell curves from base shaders.

group_uniforms banded_paint;
uniform bool use_banded_body_paint = false;
uniform float body_paint_downward_normal = 0.0;
uniform vec2 body_paint_height_range = vec2(0.26, 0.90);
uniform vec2 body_paint_end_drop = vec2(0.18, 0.10);
uniform vec2 body_paint_nose_z_range = vec2(0.45, 1.82);
uniform vec2 body_paint_tail_z_range = vec2(0.72, 1.68);
uniform sampler2D body_paint_mask : filter_nearest, repeat_disable, hint_default_white;
group_uniforms;

varying float v_body_height;
varying float v_body_surface_up;
varying float v_body_surface_side;

// Returns vec3(body_height, surface_up, surface_side) for varying assignment in vertex().
vec3 paint_bands_vertex_pack(vec3 local_vertex, vec3 local_normal) {
	float nose_drop = body_paint_end_drop.x * smoothstep(body_paint_nose_z_range.x, body_paint_nose_z_range.y, -local_vertex.z);
	float tail_drop = body_paint_end_drop.y * smoothstep(body_paint_tail_z_range.x, body_paint_tail_z_range.y, local_vertex.z);
	float sill = body_paint_height_range.x;
	float shoulder = body_paint_height_range.y - nose_drop - tail_drop;
	return vec3(
		clamp((local_vertex.y - sill) / max(shoulder - sill, 0.01), 0.0, 1.0),
		local_normal.y,
		abs(local_normal.x)
	);
}

float reflection_bands_3(float value, float dither) {
	return floor(clamp(value, 0.0, 1.0) * 3.0 + 0.5 + dither) / 3.0;
}

float reflection_ordered_dither(vec2 frag_xy, vec2 viewport_size, vec2 snap_res) {
	vec2 cell = mod(floor(frag_xy * snap_res / max(viewport_size, vec2(1.0))), 2.0);
	return (mod(cell.x + cell.y, 2.0) * 2.0 + cell.y - 1.5) * 0.12;
}
