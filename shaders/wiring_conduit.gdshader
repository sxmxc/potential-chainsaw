shader_type spatial;
render_mode unshaded, fog_disabled;

instance uniform vec4 source_tint : source_color = vec4(0.23, 0.95, 0.76, 1.0);
instance uniform vec4 target_tint : source_color = vec4(0.57, 0.60, 1.0, 1.0);
instance uniform vec4 highlight : source_color = vec4(1.0, 0.79, 0.35, 1.0);
instance uniform float focus = 0.0;

void vertex() {
	VERTEX += NORMAL * focus * 0.003;
}

void fragment() {
	vec3 tint = mix(source_tint.rgb, target_tint.rgb, smoothstep(0.0, 1.0, UV2.x));
	// Actual gaps, with a constant world-space dash length and output-to-input motion.
	float phase = fract((UV.x - TIME * 0.65) / 0.36);
	if (phase > 0.46) { discard; }
	ALBEDO = tint * (0.75 + focus * 0.15);
	EMISSION = tint * (0.2 + focus * 0.25);
}
