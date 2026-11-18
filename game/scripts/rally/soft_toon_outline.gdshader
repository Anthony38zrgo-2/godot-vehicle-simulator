shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.19, 0.15, 0.18, 1.0);
uniform float outline_width = 1.3;
uniform float outline_smooth = 0.45;
uniform float outline_fade_start = 35.0;
uniform float outline_fade_end = 85.0;
uniform bool use_alpha_cutout = false;
uniform sampler2D cutout_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float cutout_alpha = 1.0;
uniform float cutout_threshold = 0.5;
uniform bool cutout_vertex_color = false;
uniform vec2 cutout_uv_scale = vec2(1.0);
uniform vec2 cutout_uv_offset = vec2(0.0);

varying float fade;

void vertex() {
	vec3 radial = VERTEX / max(length(VERTEX), 0.00001);
	vec3 outward = mix(NORMAL, radial, outline_smooth);
	vec4 projected = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 direction = (PROJECTION_MATRIX * vec4(mat3(MODELVIEW_MATRIX) * outward, 0.0)).xy;
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	direction.x *= aspect;
	direction /= max(length(direction), 0.00001);
	direction.x /= aspect;
	fade = 1.0 - smoothstep(outline_fade_start, outline_fade_end, projected.w);
	projected.xy += direction * outline_width * fade * (2.0 / 1080.0) * projected.w;
	POSITION = projected;
}

void fragment() {
	if (use_alpha_cutout) {
		float mask = texture(cutout_texture, UV * cutout_uv_scale + cutout_uv_offset).a * cutout_alpha;
		mask *= cutout_vertex_color ? COLOR.a : 1.0;
		if (mask < cutout_threshold) {
			discard;
		}
	}
	ALBEDO = outline_color.rgb;
	ALPHA = fade * outline_color.a;
}
