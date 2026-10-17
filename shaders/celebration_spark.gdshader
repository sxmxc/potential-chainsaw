shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float brilliance : hint_range(0.0, 4.0) = 1.25;
uniform float twinkle : hint_range(0.0, 1.0) = 0.3;
varying float phase;

void vertex() {
	// Camera-facing particles retain their authored scale and world positions.
	vec3 particle_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX[0].xyz *= particle_scale.x;
	MODELVIEW_MATRIX[1].xyz *= particle_scale.y;
	MODELVIEW_MATRIX[2].xyz *= particle_scale.z;
	phase = dot(MODEL_MATRIX[3].xyz, vec3(3.1, 5.7, 2.3));
}

void fragment() {
	vec2 p = abs(UV * 2.0 - 1.0);
	float diamond = 1.0 - smoothstep(0.1, 1.0, p.x + p.y);
	float shimmer = 1.0 - twinkle * (0.5 + 0.5 * sin(TIME * 22.0 + phase));
	ALBEDO = COLOR.rgb * (1.0 + 0.2 * shimmer);
	EMISSION = COLOR.rgb * brilliance * shimmer;
	ALPHA = COLOR.a * diamond;
}
