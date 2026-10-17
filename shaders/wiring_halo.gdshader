shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, fog_disabled;

instance uniform vec4 source_tint : source_color = vec4(0.23, 0.95, 0.76, 1.0);
instance uniform vec4 target_tint : source_color = vec4(0.57, 0.60, 1.0, 1.0);
instance uniform vec4 highlight : source_color = vec4(1.0, 0.79, 0.35, 1.0);
instance uniform float focus = 0.0;

void vertex() {
	VERTEX += NORMAL * (0.014 + focus * 0.006);
}

void fragment() {
	vec3 tint = mix(source_tint.rgb, target_tint.rgb, smoothstep(0.0, 1.0, UV2.x));
	float phase = fract((UV.x - TIME * 0.65) / 0.36);
	if (phase > 0.46) { discard; }
	float facing = max(dot(normalize(NORMAL), normalize(VIEW)), 0.0);
	ALBEDO = tint;
	// The expanded surface fades to zero at its silhouette; no scene-wide bloom required.
	ALPHA = pow(facing, 3.0) * (0.12 + focus * 0.12);
}
