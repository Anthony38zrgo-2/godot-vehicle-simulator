// Francisco Cidade | fcidade.com | fcidade.itch.io
// Ink line: the mesh's back faces pushed outwards a fixed number of screen pixels.
// Use it as the `next_pass` of a toon material.
shader_type spatial;
render_mode unshaded, cull_front;

// Colour of the ink line.
uniform vec4 outline_color : source_color = vec4(0.1, 0.07, 0.12, 1.0);
// Width in pixels of a 1080-line screen (the same share of any other size), near or far.
uniform float outline_width : hint_range(0.0, 16.0) = 3.0;
// 0 pushes along the normals (smooth meshes). 1 pushes out from the mesh's origin, which closes the
// gaps that hard-edged meshes (a box's split normals) leave at their corners.
uniform float outline_smooth : hint_range(0.0, 1.0) = 0.0;
// Distance from the camera where the line starts to fade out. The fade is off while the end is not beyond the start.
uniform float outline_fade_start = 0.0;
// Distance from the camera where the line is gone.
uniform float outline_fade_end = 0.0;

varying float fade;

void vertex() {
	vec3 away = normalize(mix(NORMAL, VERTEX / max(length(VERTEX), 1e-5), outline_smooth) + vec3(1e-6));
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec2 dir = (PROJECTION_MATRIX * vec4(mat3(MODELVIEW_MATRIX) * away, 0.0)).xy;
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	dir.x *= aspect;  // work in square pixels
	if (length(dir) > 1e-6) {
		dir = normalize(dir);
		dir.x /= aspect;
		clip.xy += dir * outline_width * (2.0 / 1080.0) * clip.w;
	}
	fade = outline_fade_end > outline_fade_start ? 1.0 - smoothstep(outline_fade_start, outline_fade_end, clip.w) : 1.0;
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = fade;
}
