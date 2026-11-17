// Francisco Cidade | fcidade.com | fcidade.itch.io
// Soft Toon: gentle cel shading for painted, storybook worlds. Light falls in soft bands (or along
// a colour ramp) over a tinted shade, with a hand-painted wobble on the band edges, wrapped light,
// glowing backlit leaves and a rim of light. Pair it with soft_toon_outline.gdshader as `next_pass`.
shader_type spatial;
render_mode ambient_light_disabled;

group_uniforms surface;
// Base colour. Multiplies the texture.
uniform vec4 albedo : source_color = vec4(1.0);
// The picture of the surface, multiplied by the colour. Without one the surface is plain white.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
// How many times the picture repeats over the surface, across and down.
uniform vec2 uv_scale = vec2(1.0);
// Slides the picture over the surface, as a share of its size.
uniform vec2 uv_offset = vec2(0.0);
// Multiply the colour by the mesh's vertex colours.
uniform bool use_vertex_color = false;
// Light added to the surface whether or not any reaches it.
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);

group_uniforms shading;
// What the surface colour is multiplied by where no light reaches. A cool tint (blue, violet) reads as painted shade.
uniform vec4 shadow_color : source_color = vec4(0.6, 0.66, 0.9, 1.0);
// Lit steps above the shade: 1 is two-tone, 3 or 4 a soft gradient.
uniform int bands : hint_range(1, 8) = 3;
// 0 hard edges between the bands, 1 a smooth gradient.
uniform float band_softness : hint_range(0.0, 1.0) = 0.3;
// Where the light gives way to shade, as the cosine of the angle to the light. Raise it to shrink the lit side.
uniform float light_threshold : hint_range(-1.0, 0.95) = 0.0;
// Lets the light reach round the edge of the form: 0 is plain, 1 reaches the far side.
uniform float light_wrap : hint_range(0.0, 1.0) = 0.15;
// Read the light along the ramp texture (left is shade, right is full light) instead of the bands.
uniform bool use_ramp = false;
// The ramp picture, one pixel high: its left edge is the shade, its right edge the full light, and the colours between tint the light.
uniform sampler2D ramp : source_color, filter_linear, repeat_disable, hint_default_white;
// Cut the sun's shadows and the lamps' pools to a crisp edge, one pixel wide. Off keeps them soft.
uniform bool crisp_shadows = false;
// Where a lamp's light is cut, as a share of its strength. Only with crisp shadows.
uniform float lamp_cutoff : hint_range(0.0, 0.5) = 0.04;

group_uniforms painted_edge;
// How far the band edges wander, as if painted by hand. 0 keeps them clean.
uniform float edge_wobble : hint_range(0.0, 0.5) = 0.0;
// Size of the wander, in waves a metre.
uniform float wobble_scale : hint_range(0.2, 12.0) = 3.0;

group_uniforms rim;
// Strength of the rim of light round the silhouette. 0 turns it off.
uniform float rim : hint_range(0.0, 1.0) = 0.0;
// Colour of the rim of light.
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
// How far in from the silhouette the rim reaches.
uniform float rim_width : hint_range(0.0, 1.0) = 0.3;
// 0 lights the rim all round, 1 only where a light falls (a backlight).
uniform float rim_follows_light : hint_range(0.0, 1.0) = 0.7;

group_uniforms leaves;
// Light that shines through thin surfaces (leaves, cloth, ears) when it stands behind them. 0 turns it off.
uniform float translucency : hint_range(0.0, 1.0) = 0.0;
// Colour of the light that shines through the surface.
uniform vec4 translucency_color : source_color = vec4(1.0, 0.9, 0.5, 1.0);
// How tightly the glow gathers round the light's direction.
uniform float translucency_focus : hint_range(1.0, 16.0) = 4.0;

varying vec3 world_pos;

void vertex() {
	UV = UV * uv_scale + uv_offset;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float rim_amount(vec3 normal, vec3 view) {
	float facing = 1.0 - clamp(dot(normal, view), 0.0, 1.0);
	return smoothstep(1.0 - rim_width, 1.0 - rim_width + 0.05 + band_softness * 0.2, facing) * rim;
}

void fragment() {
	vec4 c = albedo * texture(albedo_texture, UV);
	if (use_vertex_color) {
		c *= COLOR;
	}
	ALBEDO = c.rgb;
	// The shade is a flat tint of the colour; the lights add the rest on top.
	EMISSION = c.rgb * shadow_color.rgb + emission.rgb + rim_color.rgb * rim_amount(NORMAL, VIEW) * (1.0 - rim_follows_light);
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Smooth value noise, 0 to 1.
float wander(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

// `d` is the light, 0 (shade) to 1 (full), cut into `bands` steps.
float band_steps(float d) {
	float n = float(bands);
	float f = d * n;
	return clamp((floor(f) + smoothstep(0.0, max(band_softness, 0.001), fract(f))) / n, 0.0, 1.0);
}

// Light's reach, cut to on or off at a one-pixel edge.
float crisp(float a, bool directional) {
	float at = directional ? 0.5 : lamp_cutoff;
	float w = max(fwidth(a), 0.0005);
	return smoothstep(at - w, at + w, a);
}

void light() {
	float reach = crisp_shadows ? crisp(ATTENUATION, LIGHT_IS_DIRECTIONAL) : ATTENUATION;
	float facing = (dot(NORMAL, LIGHT) + light_wrap) / (1.0 + light_wrap);
	float d = (facing - light_threshold) / (1.0 - light_threshold);
	if (edge_wobble > 0.0) {
		d += (wander(world_pos * wobble_scale) - 0.5) * edge_wobble;
	}
	d = clamp(d, 0.0, 1.0) * reach;
	vec3 lit = use_ramp ? texture(ramp, vec2(d, 0.5)).rgb : vec3(band_steps(d));
	vec3 energy = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += energy * lit * (vec3(1.0) - shadow_color.rgb);
	if (translucency > 0.0) {
		float behind = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), translucency_focus);
		DIFFUSE_LIGHT += energy * translucency_color.rgb * behind * translucency * reach;
	}
	if (rim_follows_light > 0.0) {
		SPECULAR_LIGHT += energy * rim_color.rgb * rim_amount(NORMAL, VIEW) * rim_follows_light * d;
	}
}
