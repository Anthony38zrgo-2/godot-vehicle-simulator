// Francisco Cidade | fcidade.com | fcidade.itch.io
// GENERATED from soft_toon_screen.gdshader by ferramentas/variantes_tela.py. Do not edit.
// Forward+ ONLY: creases use the normal the engine already rendered instead of rebuilding it from depth.
// It does not compile in Compatibility or Mobile; use soft_toon_screen_vulkan.gdshader on Mobile.
// Toon screen pass: an ink line drawn on the finished image wherever the depth jumps (silhouettes)
// or the surface bends (creases), plus a colour grade. It reads only the depth texture and rebuilds
// the surface normals from it. This file is for the Compatibility renderer; Forward+ and Mobile use
// soft_toon_screen_vulkan.gdshader (depth runs 0 to 1 there). SoftToon.add_screen_pass picks the right one.
// Put it on a QuadMesh child of the camera (SoftToon.add_screen_pass does it).
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;

// How the shader reads the screen and writes the result. Forward+ and Mobile keep the screen in linear light,
// so their variants convert to and from sRGB around the effect; here they are plain.
// Forward+ and Mobile keep the screen in linear light: read it as sRGB and write it back, so the effect works on
// the same values as in Compatibility.
vec3 to_srgb(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(pow(c, vec3(1.0 / 2.4)) * 1.055 - 0.055, c * 12.92, step(c, vec3(0.0031308)));
}
vec3 to_linear(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}
#define SCREEN_RGB(uv) to_srgb(texture(screen_tex, (uv)).rgb)
#define OUT_RGB(c) to_linear(c)

group_uniforms ink;
// Colour of the ink line drawn on the finished image.
uniform vec4 line_color : source_color = vec4(0.1, 0.07, 0.12, 1.0);
// Line width in pixels of the rendered image.
uniform float line_width : hint_range(0.5, 6.0) = 1.0;
// How far apart two neighbouring depths must be (as a share of the depth) to draw a silhouette line.
uniform float depth_threshold : hint_range(0.001, 0.5) = 0.05;
// How sharply the surface must bend to draw a crease line. Lower draws more lines.
uniform float crease_threshold : hint_range(0.02, 1.0) = 0.25;
// 0 draws only silhouettes, 1 silhouettes and creases.
uniform float creases : hint_range(0.0, 1.0) = 1.0;
// Distance from the camera where the line starts to fade out. The fade is off while the end is not beyond the start.
uniform float fade_start = 0.0;
// Distance from the camera where the line is gone.
uniform float fade_end = 0.0;

group_uniforms grade;
// 0 turns the image grey, 1 leaves its colours, above 1 makes them stronger.
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
// Below 1 flattens the image towards grey, above 1 pushes light and dark apart.
uniform float contrast : hint_range(0.5, 1.5) = 1.0;
// Colour mixed over the whole image.
uniform vec4 tint : source_color = vec4(1.0);
// How much of the tint colour is mixed over the whole image.
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;

group_uniforms miniature;
// Blur above and below a band of focus, as a tilt-shift lens does: the world turns into a toy diorama. 0 turns it off.
uniform float tilt_blur : hint_range(0.0, 1.0) = 0.0;
// Where the sharp band sits on the screen, 0 at the top and 1 at the bottom.
uniform float tilt_focus : hint_range(0.0, 1.0) = 0.55;
// Half the height of the sharp band, as a share of the screen.
uniform float tilt_width : hint_range(0.02, 0.6) = 0.15;
// Widest blur, in pixels of the rendered image.
uniform float tilt_radius : hint_range(1.0, 24.0) = 9.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

vec3 view_pos(vec2 uv, mat4 inv_proj) {
	// Forward+ and Mobile depth is already in clip space (0 to 1)
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, texture(depth_tex, uv).r, 1.0);
	return v.xyz / v.w;
}

// Surface normal as the engine rendered it (view space).
vec3 view_normal(vec2 uv, vec2 px, mat4 inv_proj) {
	return normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
}

void fragment() {
	vec2 px = line_width / VIEWPORT_SIZE;
	mat4 ip = INV_PROJECTION_MATRIX;
	vec3 p0 = view_pos(SCREEN_UV, ip);
	float d0 = -p0.z;
	float dx = -view_pos(SCREEN_UV + vec2(px.x, 0.0), ip).z;
	float dy = -view_pos(SCREEN_UV + vec2(0.0, px.y), ip).z;
	float silhouette = step(depth_threshold * d0, abs(dx - d0) + abs(dy - d0));
	float crease = 0.0;
	if (creases > 0.0) {
		vec3 n0 = view_normal(SCREEN_UV, px, ip);
		vec3 n1 = view_normal(SCREEN_UV + vec2(px.x, 0.0), px, ip);
		vec3 n2 = view_normal(SCREEN_UV + vec2(0.0, px.y), px, ip);
		crease = step(crease_threshold, (1.0 - dot(n0, n1)) + (1.0 - dot(n0, n2))) * creases;
	}
	float fade = fade_end > fade_start ? 1.0 - smoothstep(fade_start, fade_end, d0) : 1.0;
	float line = max(silhouette, crease) * fade * line_color.a;

	vec3 c = SCREEN_RGB(SCREEN_UV);
	float blur = 0.0;
	if (tilt_blur > 0.0) {
		blur = smoothstep(0.0, 1.0, clamp((abs(SCREEN_UV.y - tilt_focus) - tilt_width) / 0.4, 0.0, 1.0)) * tilt_blur;
		float radius = blur * tilt_radius;
		if (radius > 0.5) {
			// a spiral of taps spread over a disc, so the blur has no visible grid
			vec3 sum = vec3(0.0);
			for (int i = 0; i < 20; i++) {
				float r = sqrt((float(i) + 0.5) / 20.0) * radius;
				float a = float(i) * 2.39996;
				sum += SCREEN_RGB(SCREEN_UV + vec2(cos(a), sin(a)) * r / VIEWPORT_SIZE);
			}
			c = sum / 20.0;
		}
	}
	line *= 1.0 - blur;
	c = mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c = mix(c, c * tint.rgb, tint_amount);
	ALBEDO = OUT_RGB(mix(c, line_color.rgb, line));
}
