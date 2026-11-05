shader_type particles;
render_mode disable_force, disable_velocity;

uniform vec3 ground_normal = vec3(0.0, 1.0, 0.0);
uniform vec3 travel_direction = vec3(0.0, 0.0, 1.0);
uniform vec4 rock_color : source_color = vec4(0.35, 0.28, 0.21, 1.0);

void start() {
	CUSTOM.x = 0.0;
	CUSTOM.y = float(INDEX % 2u);
}

void process() {
	CUSTOM.x += DELTA;
	float age = CUSTOM.x;
	float phase = age < 0.18 ? age / 0.18 : clamp((age - 0.18) / 0.14, 0.0, 1.0);
	float height = sin(phase * PI) * (age < 0.18 ? 0.13 : 0.046);
	vec3 side = cross(ground_normal, travel_direction);
	vec3 offset = travel_direction * (age * (1.8 + CUSTOM.y * 0.5))
		+ side * (CUSTOM.y - 0.5) * age * 0.65;
	float size = 0.15 + CUSTOM.y * 0.025;
	TRANSFORM = mat4(vec4(size, 0, 0, 0), vec4(0, size, 0, 0), vec4(0, 0, size, 0),
		vec4(EMISSION_TRANSFORM[3].xyz + offset + ground_normal * (0.04 + height), 1));
	COLOR = vec4(rock_color.rgb, rock_color.a * (1.0 - smoothstep(0.29, LIFETIME, age)));
}
