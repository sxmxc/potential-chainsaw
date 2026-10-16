shader_type spatial;
render_mode fog_disabled, specular_disabled, shadows_disabled, ambient_light_disabled;

instance uniform vec4 source_tint : source_color = vec4(0.23, 0.95, 0.76, 1.0);
instance uniform vec4 target_tint : source_color = vec4(0.57, 0.60, 1.0, 1.0);
instance uniform vec4 highlight : source_color = vec4(1.0, 0.79, 0.35, 1.0);
instance uniform float focus = 0.0;

void vertex() {
	VERTEX += NORMAL * focus * 0.004;
}

void fragment() {
	vec3 tint = mix(source_tint.rgb, target_tint.rgb, smoothstep(0.0, 1.0, UV2.x));
	tint = mix(tint, highlight.rgb, focus * 0.8);
	// Distance UVs keep the traveling bands the same length and speed on every cable.
	float phase = fract((UV.x - TIME * 0.85) / 1.8);
	float band = smoothstep(0.68, 0.86, phase) * (1.0 - smoothstep(0.93, 1.0, phase));
	// Three continuous luminous channels in a dark housing, without plastic highlights.
	float channel_distance = abs(fract(UV.y * 3.0) - 0.5);
	float edge = max(fwidth(channel_distance), 0.01);
	float channel = 1.0 - smoothstep(0.25 - edge, 0.25 + edge, channel_distance);
	ALBEDO = mix(vec3(0.012, 0.028, 0.035), tint * 0.12, channel);
	EMISSION = tint * channel * (1.15 + band * 1.5 + focus * 0.3);
}
