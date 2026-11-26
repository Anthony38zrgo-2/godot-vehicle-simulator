shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D bush_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 bush_color : source_color = vec4(1.0);
uniform vec3 card_center;
uniform bool face_camera = false;
uniform float alpha_cutoff = 0.38;
uniform float outline_width = 0.2;
uniform vec3 outline_color : source_color = vec3(0.2745, 0.2510, 0.1647);
varying float outline_fade;

#include "res://scripts/rally/rally_object_psx_projection.gdshaderinc"

float tile_mask(vec2 uv) {
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	return inside.x * inside.y;
}

void vertex() {
	if (face_camera) {
		MODELVIEW_MATRIX = psx_upright_billboard(MODEL_MATRIX, VIEW_MATRIX, MAIN_CAM_INV_VIEW_MATRIX[0].xyz);
	}
	float distance_m = length((MODELVIEW_MATRIX * vec4(card_center, 1.0)).xyz);
	outline_fade = 1.0 - smoothstep(18.0, 48.0, distance_m);
	VERTEX = card_center + (VERTEX - card_center) * 1.6;
	UV = (UV - vec2(0.5)) * 1.6 + vec2(0.5);
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float distance_weight = smoothstep(0.25, 1.25, clip.w);
	psx_object_w = max(clip.w, 0.15);
	psx_object_uv_over_plane = UV * psx_object_w;
	psx_object_affine = psx_affine_strength * distance_weight;
	POSITION = psx_object_snap(clip, distance_weight);
}

void fragment() {
	vec2 uv = psx_object_texture_uv(UV);
	vec2 gradient_x = dFdx(uv);
	vec2 gradient_y = dFdy(uv);
	vec4 bush = texture(bush_texture, uv) * bush_color;
	bush.a *= tile_mask(uv);
	float coverage = bush.a;
	if (outline_fade > 0.0 && coverage < alpha_cutoff) {
		float pixels = outline_width * outline_fade * VIEWPORT_SIZE.y / 1080.0;
		for (int direction = 0; direction < 8; direction++) {
			float angle = float(direction) * PI / 4.0;
			vec2 delta = (gradient_x * cos(angle) + gradient_y * sin(angle)) * pixels;
			for (int ring = 1; ring <= 3; ring++) {
				vec2 sample_uv = uv + delta * (float(ring) / 3.0);
				float sample_alpha = textureGrad(bush_texture, sample_uv, gradient_x, gradient_y).a;
				coverage = max(coverage, sample_alpha * tile_mask(sample_uv) * bush_color.a);
			}
		}
	} else {
		discard;
	}
	if (coverage < alpha_cutoff) {
		discard;
	}
	ALBEDO = outline_color;
	ALPHA = outline_fade;
}
