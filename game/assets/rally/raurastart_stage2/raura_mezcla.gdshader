shader_type spatial;
render_mode specular_disabled;

uniform int surface_kind;
uniform sampler2D road_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cold_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D satellite_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D snow_mask : filter_linear, repeat_disable;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

vec3 tiled(sampler2D tex, float metres) {
	vec3 n = pow(abs(normalize(world_normal)), vec3(5.0));
	n /= max(n.x + n.y + n.z, 0.001);
	return n.x * texture(tex, world_position.zy / metres).rgb +
	       n.y * texture(tex, world_position.xz / metres).rgb +
	       n.z * texture(tex, world_position.xy / metres).rgb;
}

void fragment() {
	float variation = 0.5 + 0.25 * sin(world_position.x * 0.15 + world_position.z * 0.07)
	                      + 0.25 * sin(world_position.z * 0.21 - world_position.x * 0.09);
	vec3 gravel = tiled(gravel_tex, 2.1) * vec3(1.10, 1.14, 1.21);
	vec3 earth = mix(gravel, tiled(earth_tex, 3.2) * vec3(1.12, 1.18, 1.28), 0.28 + variation * 0.22);
	vec3 rock = mix(tiled(rock_tex, 3.6), tiled(cold_tex, 4.5) * 0.74, variation * 0.32);
	vec3 color = earth;
	if (surface_kind == 0) {
		float across = clamp(UV.x / 6.0, 0.0, 1.0);
		vec3 road = texture(road_tex, vec2(across, UV.y * 0.25)).rgb * vec3(0.88, 0.87, 0.84);
		float distance_to_edge = min(across, 1.0-across) * 6.0;
		color = mix(earth, road, smoothstep(0.0, 0.62, distance_to_edge));
	} else if (surface_kind == 1) {
		// Hold longitudinal UV fixed so a steep descent does not count as a bank.
		vec3 lateral = dFdx(world_position) * dFdy(UV.y) - dFdy(world_position) * dFdx(UV.y);
		float cross_slope = abs(lateral.y) / max(length(lateral.xz), 0.00001);
		color = mix(earth, rock, smoothstep(0.28, 0.68, cross_slope) * (0.66 + variation * 0.26));
	} else {
		vec3 satellite = texture(satellite_tex, UV).rgb;
		float slope = 1.0 - abs(normalize(world_normal).y);
		color = mix(earth, rock, smoothstep(0.08, 0.55, slope) * 0.60);
		float luminance = dot(satellite, vec3(0.2126, 0.7152, 0.0722));
		color *= mix(0.80, 1.16, smoothstep(0.06, 0.58, luminance));
		color = mix(color, min(satellite, vec3(0.53)) * vec3(0.94, 0.98, 1.04), 0.16);
		float snow = texture(snow_mask, UV).r * smoothstep(-160.0, 10.0, world_position.y);
		color = mix(color, tiled(snow_tex, 7.0) * vec3(0.86, 0.90, 0.95), snow * 0.85);
	}
	ALBEDO = color;
	ROUGHNESS = 0.95;
}
