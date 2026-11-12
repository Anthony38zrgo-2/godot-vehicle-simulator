shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Lámina de cauce dinámico de Kenia. Deriva de rally_puddle.gdshader:
// misma respuesta óptica a profundidad (Beer-Lambert sobre barro en
// suspensión) y ondulaciones por lluvia, escaladas a profundidades de río
// (decímetros en vez de milímetros de charco). La malla se desplaza por CPU
// (cota = base + rise) para conservar la pendiente longitudinal original; el
// shader solo resuelve color/alpha por profundidad óptica y bordes.
// La profundidad por fragmento sale del campo de lecho horneado cuando hay
// pantalla de profundidad inadecuada: bed_tex guarda altura del lecho
// normalizada en R y validez en G sobre la huella (footprint_min/size).

uniform vec2 footprint_min = vec2(0.0);
uniform vec2 footprint_size = vec2(1.0);
uniform sampler2D bed_tex : hint_default_white, filter_linear_mipmap;
uniform float bed_min_y = 0.0;
uniform float bed_max_y = 1.0;
uniform float edge_feather_m = 0.06;
uniform float rain = 0.0;
uniform vec2 flow_dir = vec2(0.3, 0.95);
uniform float flow_speed = 0.35;
uniform vec3 shallow_color : source_color = vec3(0.10, 0.085, 0.06);
uniform vec3 deep_color : source_color = vec3(0.02, 0.014, 0.008);
uniform vec3 horizon_color : source_color = vec3(0.25, 0.28, 0.30);
uniform vec3 sky_tint : source_color = vec3(0.46, 0.52, 0.58);

varying vec3 world_position;

float puddle_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float rain_drop_ripples(vec2 uv_world, float time, float intensity) {
	if (intensity <= 0.01) return 0.0;
	float total = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		float scale = (layer == 0) ? 5.5 : 9.5;
		vec2 p = uv_world * scale + float(layer) * 17.3;
		vec2 g = floor(p);
		vec2 f = fract(p) - 0.5;
		for (int i = -1; i <= 1; i++) {
			for (int j = -1; j <= 1; j++) {
				vec2 n = vec2(float(i), float(j));
				float h = puddle_hash(g + n);
				float age = fract(time * (1.1 + 0.5 * h) + h * 6.2831);
				float rad = age * 0.45;
				vec2 d = f - n;
				float dist = length(d);
				if (dist < rad && dist > rad - 0.16) {
					float wave = sin((dist - rad) * 36.0);
					float fade = (1.0 - age) * smoothstep(rad - 0.16, rad, dist);
					total += wave * fade;
				}
			}
		}
	}
	return total * intensity;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 fuv = (world_position.xz - footprint_min) / max(footprint_size, vec2(0.001));
	if (fuv.x < 0.0 || fuv.x > 1.0 || fuv.y < 0.0 || fuv.y > 1.0) {
		discard;
	}
	vec4 bed = texture(bed_tex, fuv);
	if (bed.g < 0.5) {
		discard;
	}
	float bed_y = mix(bed_min_y, bed_max_y, bed.r);
	float depth_m = world_position.y - bed_y;
	if (depth_m <= 0.0) {
		discard;
	}
	// Suavizar el borde en una franja estrecha: solo moja terreno comunicado
	// con el cauce dentro de la huella; fuera de ella no hay lámina.
	float edge = smoothstep(0.0, max(edge_feather_m, 0.001), depth_m);
	float depth_mm = depth_m * 1000.0;
	float depth_norm = clamp(depth_mm / 450.0, 0.0, 1.0);

	// Turbidez Beer-Lambert escalada a río: somero translúcido (fondo visible),
	// profundo opaco. Profundidades de vado piloto: base ~0.05-0.15 m,
	// crecida hasta ~0.5 m.
	float turbidity = 1.0 - exp(-depth_mm * 0.008);

	vec3 n_mod = NORMAL;
	vec2 advected = world_position.xz * 0.35 - flow_dir * TIME * flow_speed * (0.4 + 0.6 * rain + 0.4);
	if (rain > 0.02) {
		float freq1 = mix(28.0, 14.0, depth_norm);
		float freq2 = mix(42.0, 20.0, depth_norm);
		vec2 uv1 = fract(advected * freq1 * 0.12 + vec2(0.12, 0.18)) - 0.5;
		vec2 uv2 = fract(advected * freq2 * 0.12 + vec2(0.65, 0.42)) - 0.5;
		float r1 = sin(length(uv1) * mix(52.0, 24.0, depth_norm) - TIME * 7.5);
		float r2 = sin(length(uv2) * mix(68.0, 32.0, depth_norm) - TIME * 10.5);
		float wave_amplitude = mix(0.020, 0.055, depth_norm);
		float ripples = (r1 * 0.60 + r2 * 0.40) * rain * wave_amplitude;
		float drops = rain_drop_ripples(world_position.xz, TIME, rain) * 0.035;
		n_mod = normalize(NORMAL + TANGENT * (ripples + drops) + BINORMAL * (ripples - drops));
	} else if (flow_speed > 0.01) {
		float w = sin(dot(advected, vec2(6.0, 8.0)) * 3.0 - TIME * 2.0) * 0.012;
		n_mod = normalize(NORMAL + TANGENT * w);
	}
	NORMAL = n_mod;

	vec3 normal_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 reflected = reflect(normalize(world_position - CAMERA_POSITION_WORLD), normal_world);
	vec3 sky = mix(horizon_color, sky_tint.rgb, smoothstep(-0.025, 0.35, reflected.y));

	float view_angle = clamp(dot(NORMAL, VIEW) * 2.8, 0.0, 1.0);
	float fresnel = pow(1.0 - view_angle, 3.0);

	vec3 water_color = mix(shallow_color, deep_color, turbidity);
	vec3 water_albedo = mix(water_color, sky * 0.55, fresnel * 0.32);
	ALBEDO = water_albedo;
	EMISSION = sky * fresnel * 0.30;
	ROUGHNESS = mix(0.08, 0.02, turbidity);
	METALLIC = 0.0;
	SPECULAR = 0.98;

	float base_alpha = mix(0.30, 0.90, turbidity);
	float water_alpha = (base_alpha + fresnel * (1.0 - base_alpha) * 0.50) * edge;
	ALPHA = water_alpha * smoothstep(0.0, 0.03, edge + 0.03);
}
