shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_inverted, depth_draw_never;

void fragment() {
	// A broken silhouette retains traceability behind machinery without flattening crossings.
	float dash = step(0.48, fract(UV.x / 0.32));
	ALBEDO = vec3(0.27, 0.48, 0.52);
	ALPHA = dash * 0.28;
}
