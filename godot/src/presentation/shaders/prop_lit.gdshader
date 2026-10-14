// prop_lit: rocks, pylons and other team-less scenery (07 s3.3, s4.3). Same atlas and light model as unit_lit
// (moon_light.gdshaderinc), no team zones: alpha classes 0 and 1 are plain lit swatches, 2 and 3 emissive.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#include "res://src/presentation/shaders/moon_light.gdshaderinc"

uniform sampler2D atlas : source_color, filter_nearest_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);   // multiplies the albedo (variants of one rock mesh)

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 s = texture(atlas, UV);
	int cls = int(round(s.a * 3.0));
	vec3 rgb = ml_to_linear(s.rgb);
	bool glows = cls >= 2;
	MoonLit ml = ml_shade(glows ? vec3(0.0) : rgb * ml_to_linear(tint), v_world, NORMAL, VIEW, INV_VIEW_MATRIX);
	ALBEDO = glows ? vec3(0.0) : ml_encode(ml.albedo);
	EMISSION = ml_encode(ml.base + (glows ? rgb : vec3(0.0)));
}
