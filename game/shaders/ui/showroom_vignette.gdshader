shader_type canvas_item;

// Parameterized radial + directional HUD vignette overlay for vehicle showroom menus.

uniform vec3 tint_color : source_color = vec3(0.04, 0.06, 0.08);
uniform float radial_strength : hint_range(0.0, 1.0) = 0.70;
uniform float left_shade_strength : hint_range(0.0, 1.0) = 0.52;
uniform float vertical_shade_strength : hint_range(0.0, 1.0) = 0.38;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.12;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.94;

void fragment() {
	vec2 uv = UV;
	float dist = length(uv - vec2(0.5));
	float vignette = smoothstep(0.25, 0.95, dist) * radial_strength;
	float left_shade = smoothstep(0.52, 0.0, uv.x) * left_shade_strength;
	float vertical_shade = (smoothstep(0.12, 0.0, uv.y) + smoothstep(0.88, 1.0, uv.y)) * vertical_shade_strength;
	float alpha = clamp(vignette + left_shade + vertical_shade + base_alpha, 0.0, max_alpha);
	COLOR = vec4(tint_color, alpha);
}
