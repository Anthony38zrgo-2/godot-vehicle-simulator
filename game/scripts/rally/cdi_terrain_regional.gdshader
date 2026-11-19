shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

#include "res://scripts/rally/cdi_terrain_layers.gdshaderinc"

varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 gis = grass_coverage(world_point);
	vec3 normal = normalize(cross(dFdx(world_point), dFdy(world_point)));
	float steep = 1.0 - smoothstep(0.80, 0.96, abs(normal.y));
	float cover = gis.a * (1.0 - 0.85 * steep) * (1.0 - 0.65 * gis.b);
	float daylight = clamp(dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722)) * 1.3 + 0.5, 0.58, 1.12);
	ALBEDO = mix(COLOR.rgb, grass_macro_color(gis.rgb) * daylight, cover);
}
