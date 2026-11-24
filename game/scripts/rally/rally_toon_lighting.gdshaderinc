uniform vec4 base_color : source_color = vec4(1.0);
#ifdef TOON_ALPHA_CUTOUT
uniform float alpha_cutoff = 0.5;
#endif
uniform sampler2D base_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_pixel_albedo = false;
uniform sampler2D pixel_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
uniform bool use_vertex_color = false;
uniform float normal_strength = 1.0;
uniform float rim_strength = 0.10;
uniform float edge_wobble = 0.04;
uniform float wobble_scale = 3.0;
uniform vec3 wobble_anisotropy = vec3(1.0);
uniform bool wobble_in_world = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform vec3 shade_tint : source_color = vec3(0.67, 0.69, 0.82);
uniform bool use_ramp = false;
uniform sampler2D ramp : source_color, filter_linear, repeat_disable, hint_default_white;
uniform float toon_blend : hint_range(0.0, 1.0) = 1.0;
uniform bool crisp_shadows = false;
uniform float paint_spec_strength : hint_range(0.0, 1.0) = 0.0;
uniform float paint_spec_threshold : hint_range(0.5, 0.99) = 0.88;
uniform vec3 paint_spec_color : source_color = vec3(1.0, 0.97, 0.90);

// PSX vehicle-only geometry imprecision (GTE integer vertex snapping) & affine texture wobble.
uniform vec2 psx_snap_resolution = vec2(320.0, 240.0);
uniform float psx_snap_strength : hint_range(0.0, 1.0) = 0.0;
uniform float psx_affine_strength : hint_range(0.0, 1.0) = 0.0;

varying float painted_edge;
varying vec2 v_affine_uv;
varying float v_affine_w;
varying float v_psx_affine;

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

void vertex() {
	if (edge_wobble > 0.001) {
		vec3 wp = wobble_in_world ? (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz : VERTEX;
		painted_edge = (paint_noise(wp * wobble_scale * wobble_anisotropy) - 0.5) * edge_wobble;
	} else {
		painted_edge = 0.0;
	}

	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// Smoothly attenuate very close to the camera (<2.6m) so cockpit view stays comfortable.
	float psx_dist_fade = smoothstep(0.9, 2.6, max(clip.w, 0.0));
	if (psx_snap_strength > 0.001) {
		float eff_snap = psx_snap_strength * psx_dist_fade;
		vec2 ndc = clip.xy / max(abs(clip.w), 0.0001);
		vec2 grid = max(psx_snap_resolution, vec2(32.0)) * 0.5;
		vec2 snapped = floor(ndc * grid + 0.5) / grid;
		clip.xy = mix(ndc, snapped, eff_snap) * clip.w;
	}
	POSITION = clip;

	vec2 base_uv = UV * uv_scale + uv_offset;
	float w_eff = max(clip.w, 0.15);
	v_affine_uv = base_uv * w_eff;
	v_affine_w = w_eff;
	v_psx_affine = psx_affine_strength * psx_dist_fade;
}

void fragment() {
	vec2 persp_uv = UV * uv_scale + uv_offset;
	vec2 tex_uv = persp_uv;
	if (v_psx_affine > 0.001) {
		vec2 affine_uv = v_affine_uv / max(v_affine_w, 0.0001);
		tex_uv = mix(persp_uv, affine_uv, v_psx_affine);
	}
	vec4 paint = base_color * (use_pixel_albedo ? texture(pixel_albedo, tex_uv) : texture(base_texture, tex_uv));
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
	float edge_fade = smoothstep(0.0, 0.20, facing);
	vec3 diffuse_color;
	if (use_ramp) {
		float ramp_position = clamp(facing + painted_edge, 0.0, 1.0);
		diffuse_color = textureLod(ramp, vec2(ramp_position, 0.5), 0.0).rgb * edge_fade;
	} else {
		float diffuse = mix(0.32, 0.90, band) * edge_fade;
		diffuse_color = mix(shade_tint, vec3(1.0), band) * diffuse;
	}
	if (toon_blend < 0.999) {
		float smooth_wrap = clamp(facing * 0.72 + 0.28, 0.0, 1.0);
		vec3 smooth_diffuse = mix(shade_tint, vec3(1.0), smooth_wrap) * mix(0.32, 0.94, facing);
		diffuse_color = mix(smooth_diffuse, diffuse_color, toon_blend);
	}
	float reach = ATTENUATION;
	if (crisp_shadows && LIGHT_IS_DIRECTIONAL) {
		reach = step(0.5, reach);
	}
	float rim_term = 0.0;
	if (rim_strength > 0.001) {
		rim_term = smoothstep(0.57, 0.87, 1.0 - max(dot(NORMAL, VIEW), 0.0)) * band * rim_strength;
	}
	vec3 spec_dab = vec3(0.0);
	if (paint_spec_strength > 0.001 && facing > 0.0) {
		vec3 half_vec = normalize(LIGHT + VIEW);
		float ndh = max(dot(NORMAL, half_vec), 0.0);
		float dab = smoothstep(
			paint_spec_threshold - 0.03,
			paint_spec_threshold + 0.03,
			ndh + painted_edge * 0.22
		);
		spec_dab = paint_spec_color * (dab * paint_spec_strength * band);
	}
	DIFFUSE_LIGHT += (diffuse_color + spec_dab + vec3(rim_term)) * reach * LIGHT_COLOR / PI;
}
