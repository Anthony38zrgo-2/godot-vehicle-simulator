shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Simple low-poly matte PSX shader (64x64 Nearest + optional per-instance pastel tint)
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
instance uniform vec3 tint_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.94;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb * tint_color;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
