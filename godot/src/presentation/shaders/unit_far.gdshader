// unit_far: flat team colour for the `_Far` meshes drawn through per-class MultiMesh pools (07 ART-A1, 03 s7.9).
// The team colour (or the wreck-darkened colour) rides in the per-instance colour, so one material serves every
// team and every class; lit by the shared light model so far units do not pop against near ones.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#include "res://src/presentation/shaders/moon_light.gdshaderinc"

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 team = ml_to_linear(COLOR.rgb);
	MoonLit ml = ml_shade(team, v_world, NORMAL, VIEW, INV_VIEW_MATRIX);
	ALBEDO = ml_encode(ml.albedo);
	EMISSION = ml_encode(ml.base);
}
