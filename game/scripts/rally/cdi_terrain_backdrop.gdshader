shader_type spatial;
render_mode fog_disabled, specular_disabled;

#include "res://scripts/rally/cdi_terrain_layers.gdshaderinc"

varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float patch = patch_noise(world_point.xz * 0.052) * 0.70
		+ patch_noise(world_point.xz * 0.82) * 0.30;
	ALBEDO = ground_cover(world_point, patch) * terrain_macro_tone(world_point.xz);
	ALPHA = 1.0 - smoothstep(125.0, 340.0, length(VERTEX));
	ROUGHNESS = 0.95;
}
