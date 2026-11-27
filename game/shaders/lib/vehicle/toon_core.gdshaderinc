// Shared stylized toon vehicle surface core (used by vehicle_toon, vehicle_toon_cutout, vehicle_louver).
// Depends on: hash_noise, psx_projection, base_albedo_contract, dirt_overlay, paint_bands

#ifdef TOON_ALPHA_CUTOUT
uniform float alpha_cutoff = 0.5;
#endif

group_uniforms toon_shading;
uniform float rim_strength = 0.10;
uniform float edge_wobble = 0.04;
uniform float wobble_scale = 3.0;
uniform vec3 wobble_anisotropy = vec3(1.0);
uniform bool wobble_in_world = false;
uniform vec3 shade_tint : source_color = vec3(0.67, 0.69, 0.82);
uniform bool use_ramp = false;
uniform sampler2D ramp : source_color, filter_linear, repeat_disable, hint_default_white;
uniform float toon_blend : hint_range(0.0, 1.0) = 1.0;
uniform bool crisp_shadows = false;
group_uniforms;

group_uniforms vehicle_reflections;
uniform bool enable_vehicle_reflections = false;
uniform float paint_spec_strength : hint_range(0.0, 1.0) = 0.0;
uniform float paint_spec_threshold : hint_range(0.5, 0.99) = 0.88;
uniform vec3 paint_spec_color : source_color = vec3(1.0, 0.97, 0.90);
uniform float paint_env_strength : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D paint_env_map : source_color, filter_linear, repeat_disable;
uniform sampler2D paint_env_mask : hint_default_white, filter_nearest, repeat_disable;
uniform float paint_env_mask_threshold = 0.30;
uniform bool use_glass_reflection = false;
uniform sampler2D glass_reflection_mask : filter_nearest, repeat_disable, hint_default_black;
group_uniforms;

varying vec3 v_up_view;
varying float v_reflection_dither;
varying float v_body_paint_coverage;
varying float v_painted_edge;

void vertex() {
	dirt_position = dirt_local_position(VERTEX);
	vec3 pb = paint_bands_vertex_pack(VERTEX, NORMAL);
	v_body_height = pb.x;
	v_body_surface_up = pb.y;
	v_body_surface_side = pb.z;
	v_up_view = normalize(MODELVIEW_NORMAL_MATRIX * vec3(0.0, 1.0, 0.0));
#ifdef VEHICLE_LOUVER_SLATS
	v_louver_xz = VERTEX.xz;
	v_louver_up_view = v_up_view;
#endif
	if (edge_wobble > 0.001) {
		vec3 wp = wobble_in_world ? (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz : VERTEX;
		v_painted_edge = (value_noise3(wp * wobble_scale * wobble_anisotropy) - 0.5) * edge_wobble;
	} else {
		v_painted_edge = 0.0;
	}
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 base_uv = UV * uv_scale + uv_offset;
	vec4 psx_pack = psx_affine_pack(clip, base_uv, 0.25, 1.25);
	v_psx_uv_over_w = psx_pack.xy;
	v_psx_w = psx_pack.z;
	v_psx_affine_weight = psx_pack.w;
	POSITION = psx_snap_clip_range(clip, 0.25, 1.25);
}

void fragment() {
	vec2 tex_uv = psx_resolve_uv(UV * uv_scale + uv_offset);
	vec4 paint = sample_vehicle_albedo(tex_uv, COLOR);
	v_body_paint_coverage = use_banded_body_paint ? step(0.5, texture(body_paint_mask, tex_uv).r) : 0.0;
	if (body_paint_downward_normal > 0.0 && v_body_paint_coverage > 0.0) {
		float side = smoothstep(0.45, 0.75, v_body_surface_side);
		float lower = 1.0 - smoothstep(0.24, 0.28, v_body_height);
		float middle = 1.0 - smoothstep(0.53, 0.58, v_body_height);
		float bias = (0.58 * lower + 0.42 * middle) * side * body_paint_downward_normal;
		NORMAL = normalize(NORMAL - normalize(v_up_view) * bias);
	}
	v_reflection_dither = 0.0;
	if (use_glass_reflection || (enable_vehicle_reflections && use_banded_body_paint)) {
		v_reflection_dither = reflection_ordered_dither(FRAGCOORD.xy, VIEWPORT_SIZE, psx_snap_resolution);
	}
	vec4 dirt = dirt_sample();
	if (use_glass_reflection) {
		vec2 glass_mask = texture(glass_reflection_mask, tex_uv).rg * (1.0 - v_body_paint_coverage);
		dirt.a *= 1.0 - step(0.1, max(glass_mask.x, glass_mask.y));
	}
	ALBEDO = mix(paint.rgb, dirt.rgb, dirt.a);
	vec3 total_emission = emission_color * emission_energy;
	if (enable_vehicle_reflections && paint_env_strength > 0.001) {
		float coverage = use_banded_body_paint
			? v_body_paint_coverage
			: step(paint_env_mask_threshold, texture(paint_env_mask, tex_uv).r);
		if (coverage > 0.0) {
			vec3 n = normalize(NORMAL);
			vec3 reflected = mat3(INV_VIEW_MATRIX) * reflect(-VIEW, n);
			vec2 env_uv = vec2(0.5 + reflected.x * 0.45, 0.5 - reflected.y * 0.48);
			vec3 streak = texture(paint_env_map, env_uv).rgb;
			float grazing = 1.0 - clamp(dot(n, VIEW), 0.0, 1.0);
			float sheen = paint_env_strength * (0.35 + 0.65 * grazing * grazing);
			total_emission += streak * sheen * smoothstep(-0.30, 0.16, v_body_surface_up);
		}
	}
	if (use_glass_reflection) {
		vec2 glass = texture(glass_reflection_mask, tex_uv).rg * (1.0 - v_body_paint_coverage);
		vec3 reflected = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, normalize(NORMAL)), 0.0)).xyz;
		float sky = smoothstep(-0.12, 0.55, reflected.y);
		float grazing = 1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
		float windshield = reflection_bands_3(glass.x * (0.35 + 0.65 * sky) * (0.62 + 0.38 * grazing), v_reflection_dither);
		float side_window = reflection_bands_3(glass.y * (0.32 + 0.68 * sky), v_reflection_dither);
		total_emission += vec3(0.016, 0.065, 0.095) * windshield + vec3(0.014, 0.050, 0.077) * side_window;
	}
#ifdef VEHICLE_LOUVER_SLATS
	total_emission = louver_emission(VERTEX);
#endif
	EMISSION = total_emission * (1.0 - dirt.a);
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
	float band = smoothstep(0.35, 0.49, facing + v_painted_edge);
	float edge_fade = smoothstep(0.0, 0.20, facing);
	vec3 diffuse_color;
	if (use_ramp) {
		float ramp_position = clamp(facing + v_painted_edge, 0.0, 1.0);
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
	if (enable_vehicle_reflections && paint_spec_strength > 0.001 && facing > 0.0) {
		vec3 half_vec = normalize(LIGHT + VIEW);
		float ndh = max(dot(NORMAL, half_vec), 0.0);
		float dab = smoothstep(
			paint_spec_threshold - 0.03,
			paint_spec_threshold + 0.03,
			ndh + v_painted_edge * 0.22
		);
		spec_dab = paint_spec_color * (dab * paint_spec_strength * band);
	}
	vec3 lighting = diffuse_color + spec_dab + vec3(rim_term);
	if (v_body_paint_coverage > 0.5) {
		float side_height = v_body_height + 0.035 * (facing - 0.52);
		float side_tone = 0.16
			+ 0.19 * smoothstep(0.23, 0.245, side_height)
			+ 0.25 * smoothstep(0.47, 0.485, side_height)
			+ 0.31 * smoothstep(0.70, 0.72, side_height);
		float upward = smoothstep(0.73, 0.94, v_body_surface_up);
		float tone = mix(side_tone, mix(0.73, 0.94, facing), upward);
		lighting = vec3(tone) * mix(vec3(1.0), diffuse_color, 0.40 * toon_blend);
		if (enable_vehicle_reflections) {
			float alignment = dot(NORMAL, normalize(LIGHT + VIEW));
			float shoulder_light = smoothstep(0.61, 0.82, v_body_height);
			float clearcoat = smoothstep(0.942, 0.967, alignment)
				* smoothstep(0.18, 0.38, facing) * shoulder_light;
			lighting += vec3(0.42 * reflection_bands_3(clearcoat, v_reflection_dither));
		}
	}
	DIFFUSE_LIGHT += lighting * reach * LIGHT_COLOR / PI;
}
