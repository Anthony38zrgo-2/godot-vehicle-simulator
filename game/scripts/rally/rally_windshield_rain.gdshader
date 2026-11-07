shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Lluvia de parabrisas estilizada (look 2004-2006).
// - Sin normales de malla, sin VERTEX/UV: todo se calcula en espacio de pantalla.
// - La "lente" de cada gota es un simple offset de muestreo (imagen invertida), sin normal maps.
// - La malla del parabrisas solo actua como mascara de donde se dibuja.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float car_speed_mps : hint_range(0.0, 80.0) = 0.0;
uniform float rain_scroll = 0.0;          // acumulado desde GDScript (se mantiene igual)
uniform bool is_cockpit_view = true;

uniform float refraction : hint_range(0.0, 0.08) = 0.03;   // fuerza de la lente
uniform float bead_scale = 38.0;          // gotas quietas: celdas por alto de pantalla
uniform float slider_scale = 11.0;        // gotas que se deslizan
uniform float wind_slant : hint_range(0.0, 0.5) = 0.18;    // inclinacion lateral a velocidad
uniform float slide_dir : hint_range(-1.0, 1.0) = -1.0;    // -1 = caen hacia abajo, +1 = suben
uniform float fall_speed : hint_range(0.0, 0.5) = 0.10;    // velocidad base de caida (parado)

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Gotas quietas. Devuelve (offset de refraccion, mascara).
vec3 beads(vec2 uv, float scale, float density, float seed) {
	vec2 p = uv * scale + vec2(seed * 17.3, seed * 31.7);
	vec2 id = floor(p);
	vec2 f = fract(p) - 0.5;
	if (hash12(id + seed) > density) {
		return vec3(0.0);
	}
	vec2 c = (vec2(hash12(id + seed + 3.1), hash12(id + seed + 7.7)) - 0.5) * 0.5;
	float r = mix(0.14, 0.30, hash12(id + seed + 11.3));
	vec2 d = (f - c) / r;
	float m = 1.0 - smoothstep(0.80, 1.0, length(d));
	return vec3(-d * m, m);
}

// Gotas que suben/se deslizan con estela corta. Cada celda tiene su propia velocidad y fase,
// asi que cada gota se mueve distinto. La gota nace y muere con fundido (no hay saltos).
vec3 slider(vec2 uv, float scale, float density, float seed, float t) {
	vec2 p = vec2(uv.x * scale + seed * 13.1, uv.y * scale * 0.45 + seed * 5.7);
	vec2 id = floor(p);
	vec2 f = fract(p);
	if (hash12(id + seed) > density) {
		return vec3(0.0);
	}
	float h2 = hash12(id + seed + 9.1);
	float h3 = hash12(id + seed + 21.7);

	float raw = fract(h2 + t * mix(0.6, 1.4, h3));
	float life = sin(raw * PI);
	// Avance a tirones (se frena y acelera, como una gota real sobre el cristal); siempre avanza
	float phase = clamp(raw + 0.04 * sin(raw * 18.85 + h3 * 6.28), 0.0, 1.0);
	float dir = (slide_dir >= 0.0) ? 1.0 : -1.0;
	float py = (dir > 0.0) ? phase : 1.0 - phase;
	// Pequeno vaiven lateral mientras se desplaza
	float px = mix(0.25, 0.75, hash12(id + seed + 4.3)) + 0.04 * sin(phase * 20.0 + h2 * 6.28);
	float rr = mix(0.10, 0.16, h3);

	// Cuerpo de la gota (circular en pantalla gracias al 0.45 del eje Y)
	vec2 d = vec2((f.x - px) / rr, (f.y - py) / (rr * 0.45));
	float drop_m = 1.0 - smoothstep(0.80, 1.0, length(d));

	// Estela detras de la gota (por debajo de ella en el sentido del movimiento)
	float behind = (py - f.y) * dir;   // >0 = lado por donde ya paso la gota
	float avail = (dir > 0.0) ? py : 1.0 - py;
	float trail_len = max(min(avail, 0.55), 0.01);
	float tx = (f.x - px - 0.025 * sin(f.y * 16.0 + h2 * 6.28)) / (rr * 0.28);
	float trail_m = (1.0 - smoothstep(0.6, 1.0, abs(tx)))
		* step(0.0, behind)
		* (1.0 - clamp(behind / trail_len, 0.0, 1.0))
		* 0.55;

	vec2 off = -d * drop_m + vec2(tx * 0.25, 0.0) * trail_m;
	float mask = max(drop_m, trail_m) * life;
	return vec3(off * life, mask);
}

void fragment() {
	if (!is_cockpit_view || rain_intensity <= 0.005) {
		ALPHA = 0.0;
		discard;
	}

	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	// Espacio de pantalla con aspecto corregido; Y hacia arriba
	vec2 uv = vec2(SCREEN_UV.x * aspect, 1.0 - SCREEN_UV.y);

	// Inclinacion por viento: leve cizalla uniforme, acotada (nunca colapsa)
	float speed_norm = clamp(car_speed_mps / 28.0, 0.0, 1.0);
	uv.x += (uv.y - 0.5) * wind_slant * speed_norm;

	float t = rain_scroll * 0.35 + TIME * fall_speed;
	float ri = rain_intensity;

	vec3 b1 = beads(uv, bead_scale, ri * 0.55, 1.0);
	vec3 b2 = beads(uv, bead_scale * 1.8, ri * 0.45, 2.0);
	vec3 b3 = beads(uv, bead_scale * 4.0, ri * 0.60, 5.0);   // rocio fino
	vec3 s1 = slider(uv, slider_scale, ri * 0.45, 3.0, t);
	vec3 s2 = slider(uv, slider_scale * 1.6, ri * 0.35, 4.0, t * 1.3);

	vec2 off = b1.xy + b2.xy * 0.8 + b3.xy * 0.5 + s1.xy + s2.xy;
	float mask = clamp(max(max(max(b1.z, b2.z), max(b3.z * 0.7, s1.z)), s2.z), 0.0, 1.0);

	if (mask <= 0.003) {
		ALPHA = 0.0;
		discard;
	}

	// Lente falsa: la gota muestrea la escena "invertida" y un poco borrosa
	vec2 refr_off = off * refraction * vec2(1.0 / aspect, -1.0);
	vec2 refr_uv = clamp(SCREEN_UV + refr_off, vec2(0.002), vec2(0.998));
	vec3 scene = textureLod(screen_tex, refr_uv, 1.0).rgb;

	// Borde oscuro + brillo puntual arriba-izquierda (se deriva del propio offset, sin normales)
	float len_off = clamp(length(off), 0.0, 1.0);
	float rim = smoothstep(0.55, 1.0, len_off);
	vec2 dd = -off;
	float spec = smoothstep(0.30, 0.0, length(dd - vec2(-0.35, 0.40)));

	vec3 col = scene * (1.0 - 0.22 * rim) + vec3(0.85, 0.92, 1.0) * spec * 0.30;

	ALBEDO = col;
	ALPHA = clamp(smoothstep(0.0, 0.25, mask) * 0.92, 0.0, 0.95);
}
