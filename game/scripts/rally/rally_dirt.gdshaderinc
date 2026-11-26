instance uniform vec4 dirt_x;
instance uniform vec4 dirt_y;
instance uniform vec4 dirt_z;
instance uniform vec4 dirt_stage;
instance uniform vec4 dirt_mud;
instance uniform vec4 dirt_wheel_stage;
instance uniform vec4 dirt_wheel_mud;
instance uniform vec4 dirt_axles;
instance uniform vec4 dirt_wheel_z;
varying vec3 dirt_position;

vec3 dirt_local_position(vec3 vertex) {
	vec4 p = vec4(vertex, 1.0);
	return vec3(dot(dirt_x, p), dot(dirt_y, p), dot(dirt_z, p));
}

vec4 dirt_sample() {
	float stage = dirt_stage.x;
	float mud = dirt_mud.x;
	vec3 p = dirt_position;
	vec3 grain_uv = p * 136.0;
	vec3 footprint = fwidth(grain_uv);
	float pixel_size = max(footprint.x, max(footprint.y, footprint.z));
	if (dirt_stage.w == 0.0) {
		if (p.y >= 0.5) {
			return vec4(0.0);
		}
		bool front = (p.z - dirt_axles.x) * dirt_axles.y > 0.0;
		float end_distance = min(p.z, 1.0 - p.z);
		if (end_distance < 0.18) {
			stage = front ? dirt_stage.y : dirt_stage.z;
			mud = front ? dirt_mud.y : dirt_mud.z;
		}
		bool left = (p.x - 0.5) * dirt_axles.z > 0.0;
		int wheel = (front ? 0 : 2) + (left ? 0 : 1);
		if (abs(p.x - 0.5) > 0.30 && abs(p.z - dirt_wheel_z[wheel]) < 0.13 && p.y < 0.32) {
			if (dirt_wheel_stage[wheel] > stage) {
				stage = dirt_wheel_stage[wheel];
				mud = dirt_wheel_mud[wheel];
			}
		}
	}
	if (stage == 0.0) {
		return vec4(0.0);
	}
	vec3 cell = floor(grain_uv);
	float grain = fract(dot(cell, vec3(0.317, 0.473, 0.619)) + fract(dot(cell, vec3(0.159, 0.279, 0.137))) * 2.31);
	float height_bias = dirt_stage.w > 0.0 ? 0.0 : clamp(p.y, 0.0, 0.5) * 0.8;
	float coverage = clamp(stage * 0.17 - height_bias, 0.0, 1.0);
	// Resolve the grain up close and average its coverage as it becomes subpixel.
	float mask = mix(step(grain, coverage), coverage, smoothstep(0.5, 1.4, pixel_size));
	vec3 powder = vec3(0.142, 0.086, 0.046);
	vec3 mud_color = vec3(0.073, 0.038, 0.020);
	return vec4(mix(powder, mud_color, mud), mask * mix(0.24, 0.38, mud));
}
