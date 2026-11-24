shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Lluvia de parabrisas estilizada y ligera (look 2004-2006):
// - Sin hint_screen_texture: evita la copia completa del viewport + mipmaps por frame.
// - 3 capas compactas (gotas quietas, rocio fino y gotas deslizantes con estela) con
//   borde oscuro + brillo especular de cielo en alpha blending directo.

uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float car_speed_mps : hint_range(0.0, 80.0) = 0.0;
uniform float rain_scroll = 0.0;          // acumulado desde GDScript
uniform bool is_cockpit_view = true;

uniform float refraction : hint_range(0.0, 0.08) = 0.03;   // mantenido por compatibilidad
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

// Gotas quietas. Devuelve (offset 2D de curvatura, mascara).
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

// Gotas que suben/se deslizan con estela corta.
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
	float phase = clamp(raw + 0.04 * sin(raw * 18.85 + h3 * 6.28), 0.0, 1.0);
	float dir = (slide_dir >= 0.0) ? 1.0 : -1.0;
	float py = (dir > 0.0) ? phase : 1.0 - phase;
	float px = mix(0.25, 0.75, hash12(id + seed + 4.3)) + 0.04 * sin(phase * 20.0 + h2 * 6.28);
	float rr = mix(0.10, 0.16, h3);

	vec2 d = vec2((f.x - px) / rr, (f.y - py) / (rr * 0.45));
	float drop_m = 1.0 - smoothstep(0.80, 1.0, length(d));

	float behind = (py - f.y) * dir;
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
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	if (is_cockpit_view && rain_intensity > 0.005) {
		float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
		vec2 uv = vec2(SCREEN_UV.x * aspect, 1.0 - SCREEN_UV.y);

		float speed_norm = clamp(car_speed_mps / 28.0, 0.0, 1.0);
		uv.x += (uv.y - 0.5) * wind_slant * speed_norm;

		float t = rain_scroll * 0.35 + TIME * fall_speed;
		float ri = rain_intensity;

		vec3 b1 = beads(uv, bead_scale, ri * 0.58, 1.0);
		vec3 b2 = beads(uv, bead_scale * 2.4, ri * 0.55, 5.0);
		vec3 s1 = slider(uv, slider_scale, ri * 0.52, 3.0, t);

		vec2 off = b1.xy + b2.xy * 0.65 + s1.xy;
		float mask = clamp(max(max(b1.z, b2.z * 0.78), s1.z), 0.0, 1.0);

		if (mask > 0.003) {
			// Sombreado estilizado de gota de cristal sin copia de framebuffer:
			// borde oscuro (menisco), cuerpo translucido frio y brillo puntual superior-izquierdo.
			float len_off = clamp(length(off), 0.0, 1.0);
			float rim = smoothstep(0.45, 0.95, len_off);
			vec2 dd = -off;
			float spec = smoothstep(0.36, 0.0, length(dd - vec2(-0.34, 0.38)));
			float bottom_bounce = smoothstep(0.48, 0.0, length(dd - vec2(0.18, -0.45))) * 0.28;

			vec3 body_col = mix(vec3(0.56, 0.64, 0.72), vec3(0.14, 0.18, 0.24), rim);
			col = body_col + vec3(0.88, 0.94, 1.0) * (spec * 0.72 + bottom_bounce);
			alpha = clamp(smoothstep(0.0, 0.25, mask) * (0.28 + 0.36 * rim + 0.32 * spec), 0.0, 0.82);
		}
	}
	ALBEDO = col;
	ALPHA = alpha;
}
