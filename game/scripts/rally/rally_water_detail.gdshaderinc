uniform sampler2D water_detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 0.30;
uniform float detail_strength = 0.72;
uniform float detail_normal_strength = 0.0;
uniform float detail_speed = 0.035;
// 0 = el detalle viene del JPEG; 1 = el detalle lo calcula el shader con
// ondas procedurales. La ruta procedural es la que da el color de agua de
// PS2: el mapa de bits solo traía el ruido del oleaje.
uniform float detail_procedural_mix = 0.0;

// Oleaje procedural cuantizado a 4 bits por canal, como la paleta corta de
// PS2. Tres trenes de ondas cruzados (dos cortos y uno largo) en lugar de
// una textura: sin bump mapping y sin mapa de bits.
float water_wave(vec2 p, float t) {
	float w1 = sin(p.x * 2.30 + t * 1.70);
	float w2 = sin(p.y * 1.70 - t * 1.10);
	float w3 = sin((p.x + p.y) * 0.85 + t * 0.55);
	float v = (w1 * 0.45 + w2 * 0.35 + w3 * 0.20) * 0.5 + 0.5;
	// 4 bits: 16 niveles, el tamaño de paleta típico de PS2.
	return floor(clamp(v, 0.0, 1.0) * 15.0 + 0.5) / 15.0;
}

float water_detail_lum(vec2 p) {
	vec3 c = texture(water_detail_tex, p).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(lum, water_wave(p, TIME), clamp(detail_procedural_mix, 0.0, 1.0));
}

// Two overlapping scrolling layers (Dreamcast multi-layer UV scroll style),
// keeping normals smooth (yz = 0) to avoid modern per-pixel specular noise.
vec3 water_detail_sample(vec2 world_xz, vec2 flow) {
	vec2 uv_a = world_xz * detail_scale + flow;
	vec2 uv_b = world_xz * (detail_scale * 1.45) + vec2(0.37, 0.61) - flow * 0.55;
	float a = water_detail_lum(uv_a);
	float b = water_detail_lum(uv_b);
	float lum = mix(a, b, 0.45);
	return vec3(lum, 0.0, 0.0);
}

vec3 water_detail_rgb(vec2 world_xz, vec2 flow) {
	vec2 uv_a = world_xz * detail_scale + flow;
	vec2 uv_b = world_xz * (detail_scale * 1.45) + vec2(0.37, 0.61) - flow * 0.55;
	return mix(texture(water_detail_tex, uv_a).rgb, texture(water_detail_tex, uv_b).rgb, 0.45);
}
