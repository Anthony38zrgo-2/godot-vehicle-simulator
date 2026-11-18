uniform vec4 base_color : source_color = vec4(1.0);
#ifdef TOON_ALPHA_CUTOUT
uniform float alpha_cutoff = 0.5;
#endif
uniform sampler2D base_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
uniform bool use_vertex_color = false;
uniform float normal_strength = 1.0;
uniform float rim_strength = 0.10;
uniform float edge_wobble = 0.04;
uniform float wobble_scale = 3.0;
uniform bool wobble_in_world = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform vec3 shade_tint : source_color = vec3(0.67, 0.69, 0.82);
uniform bool use_ramp = false;
uniform sampler2D ramp : source_color, filter_nearest, repeat_disable, hint_default_white;
uniform bool crisp_shadows = false;

varying vec3 wobble_point;
varying float painted_edge;

void vertex() {
	wobble_point = wobble_in_world ? (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz : VERTEX;
}

float paint_hash(vec3 point) {
	point = fract(point * 0.1031);
	point += dot(point, point.zyx + 31.32);
	return fract((point.x + point.y) * point.z);
}

float paint_noise(vec3 point) {
	vec3 cell = floor(point);
	vec3 weight = smoothstep(vec3(0.0), vec3(1.0), fract(point));
	vec4 lower = vec4(paint_hash(cell), paint_hash(cell + vec3(1, 0, 0)),
		paint_hash(cell + vec3(0, 1, 0)), paint_hash(cell + vec3(1, 1, 0)));
	cell.z += 1.0;
	vec4 upper = vec4(paint_hash(cell), paint_hash(cell + vec3(1, 0, 0)),
		paint_hash(cell + vec3(0, 1, 0)), paint_hash(cell + vec3(1, 1, 0)));
	vec4 corners = mix(lower, upper, weight.z);
	return mix(mix(corners.x, corners.y, weight.x), mix(corners.z, corners.w, weight.x), weight.y);
}

void fragment() {
	painted_edge = (paint_noise(wobble_point * wobble_scale) - 0.5) * edge_wobble;
	vec2 tex_uv = UV * uv_scale + uv_offset;
	vec4 paint = base_color * texture(base_texture, tex_uv);
	if (use_vertex_color) {
		paint *= COLOR;
	}
	ALBEDO = paint.rgb;
#ifdef TOON_ALPHA_CUTOUT
	ALPHA = paint.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
#endif
	if (use_normal) {
		NORMAL_MAP = texture(normal_texture, tex_uv).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
}

void light() {
	float facing = max(dot(NORMAL, LIGHT), 0.0);
	float band = smoothstep(0.35, 0.49, facing + painted_edge);
	float diffuse = mix(0.32, 0.90, band) * smoothstep(0.0, 0.20, facing);
	vec3 diffuse_color = mix(shade_tint, vec3(1.0), band) * diffuse;
	if (use_ramp) {
		float ramp_position = clamp(facing + painted_edge, 0.0, 1.0);
		diffuse_color = textureLod(ramp, vec2(ramp_position, 0.5), 0.0).rgb
			* smoothstep(0.0, 0.20, facing);
	}
	float reach = ATTENUATION;
	if (crisp_shadows && LIGHT_IS_DIRECTIONAL) {
		reach = step(0.5, reach);
	}
	float rim = smoothstep(0.57, 0.87, 1.0 - max(dot(NORMAL, VIEW), 0.0));
	DIFFUSE_LIGHT += (diffuse_color + rim * band * rim_strength) * reach * LIGHT_COLOR / PI;
}
