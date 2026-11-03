shader_type sky;

uniform sampler2D clear_panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D overcast_panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_density : filter_linear_mipmap, repeat_enable;
uniform float coverage = 0.4;
uniform float daylight = 1.0;
uniform float twilight = 0.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 horizon_color : source_color = vec3(0.64, 0.73, 0.82);

void sky() {
	vec3 direction = normalize(EYEDIR);
	vec2 uv = SKY_COORDS;
	// Mirrored longitude closes both panorama edges without another lookup.
	vec2 wrapped_uv = vec2(abs(uv.x * 2.0 - 1.0), clamp(uv.y, 0.01, 0.99));
	vec3 clear_color = texture(clear_panorama, wrapped_uv).rgb;
	vec3 covered_color = texture(overcast_panorama, wrapped_uv).rgb;
	float overcast = smoothstep(0.35, 0.95, coverage);
	vec3 base = mix(clear_color, covered_color, overcast);
	// Fade the panorama at the poles to avoid pinching of painted details.
	base = mix(base, mix(vec3(0.18, 0.34, 0.56), vec3(0.36, 0.42, 0.49), overcast), smoothstep(0.85, 1.0, direction.y));
	// One planar cloud layer, one density lookup. Fade before the horizon.
	vec2 cloud_uv = direction.xz / max(direction.y + 0.25, 0.25) * 0.18 + cloud_offset;
	// Mirror tiles so generated image edges cannot leave a moving seam.
	cloud_uv = abs(fract(cloud_uv * 0.5) * 2.0 - 1.0);
	float density = texture(cloud_density, cloud_uv).r;
	float threshold = mix(1.02, 0.08, coverage);
	float cloud = smoothstep(threshold - 0.12, threshold + 0.12, density);
	cloud *= smoothstep(0.02, 0.22, direction.y);
	vec3 cloud_color = mix(vec3(0.88, 0.90, 0.92), vec3(0.39, 0.44, 0.50), overcast);
	vec3 color = mix(base, cloud_color * mix(0.82, 1.0, density), cloud * mix(0.75, 0.95, overcast));
	float horizon = 1.0 - smoothstep(0.0, 0.22, abs(direction.y));
	color = mix(color, horizon_color, horizon * 0.72);
	vec3 night = color * vec3(0.055, 0.075, 0.13);
	color = mix(night, color, daylight);
	float sunset_side = max(dot(direction, normalize(vec3(sun_direction.x, 0.05, sun_direction.z))), 0.0);
	color += vec3(0.30, 0.095, 0.025) * twilight * horizon * sunset_side * (1.0 - overcast * 0.7);
	float sun = smoothstep(0.99980, 0.99994, dot(direction, sun_direction));
	float moon = smoothstep(0.99984, 0.99996, dot(direction, -sun_direction));
	color += sun * vec3(1.0, 0.88, 0.61) * daylight * (1.0 - cloud) * (1.0 - overcast);
	color += moon * vec3(0.45, 0.51, 0.61) * (1.0 - daylight) * (1.0 - cloud) * (1.0 - overcast);
	COLOR = max(color, vec3(0.0));
}
