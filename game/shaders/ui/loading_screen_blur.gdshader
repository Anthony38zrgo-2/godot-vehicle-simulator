shader_type canvas_item;

// Screen-space frosted blur overlay for loading transitions.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 5.0) = 3.2;
uniform vec4 tint_color : source_color = vec4(0.03, 0.05, 0.08, 0.58);

void fragment() {
	vec4 bg = textureLod(screen_tex, SCREEN_UV, blur_lod);
	COLOR = mix(bg, vec4(tint_color.rgb, 1.0), tint_color.a);
}
