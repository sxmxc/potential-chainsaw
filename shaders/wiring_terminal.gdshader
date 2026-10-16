shader_type spatial;
render_mode unshaded, fog_disabled;

instance uniform vec4 tint : source_color = vec4(0.23, 0.95, 0.76, 1.0);
instance uniform vec4 highlight : source_color = vec4(1.0, 0.79, 0.35, 1.0);
instance uniform float focus = 0.0;
instance uniform float available = 1.0;

void fragment() {
	float facing = max(dot(normalize(NORMAL), normalize(VIEW)), 0.0);
	vec3 color = mix(tint.rgb, highlight.rgb, focus);
	ALBEDO = color * (0.4 + 0.6 * facing) * mix(0.24, 1.0, available) + color * focus * 0.3;
}
