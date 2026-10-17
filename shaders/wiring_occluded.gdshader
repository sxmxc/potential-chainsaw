shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_inverted, depth_draw_never;

void fragment() {
	// A broken silhouette retains traceability behind machinery without flattening crossings.
	float phase = fract((UV.x - TIME * 0.65) / 0.36);
	if (phase > 0.46) { discard; }
	ALBEDO = vec3(0.27, 0.48, 0.52);
	ALPHA = 0.28;
}
