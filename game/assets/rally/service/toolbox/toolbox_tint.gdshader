shader_type spatial;
uniform sampler2D source_color_texture : source_color, filter_linear_mipmap;
uniform vec4 paint : source_color = vec4(0.9, 0.82, 0.65, 1.0);
void fragment() {
 vec3 original = texture(source_color_texture, UV).rgb;
 float brightness = dot(original, vec3(0.2126, 0.7152, 0.0722));
 float painted = smoothstep(0.18, 0.65, brightness);
 ALBEDO = mix(vec3(brightness), paint.rgb * brightness, painted);
 ROUGHNESS = 0.7;
}
