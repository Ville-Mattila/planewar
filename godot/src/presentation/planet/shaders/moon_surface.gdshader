// moon_surface: first-pass moon material on the shared light model (ART-01). Replaces the interim
// planet_chunk look in the demo and goldens: same chunk CUSTOM0 layout (03 s7.3: r = height01, g = slope01,
// b = biome / 255, a = skirt flag), mare -> highland by height and slope, lit by moon_light.gdshaderinc
// (wrap sun, radial ambient, earthshine, limb rim, sun_dir). TA-24's moon_terrain.gdshader supersedes it with
// the biome face, the 16 x 64 ramp LUT, the ramp value v and detail displacement (07 s3.1).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#include "res://src/presentation/shaders/moon_light.gdshaderinc"

const vec3 MARE = vec3(0.05127, 0.05951, 0.08438);       // #404552 (07 s2.1 mare mid)
const vec3 HIGHLAND = vec3(0.30054, 0.28315, 0.25016);   // #959189 (07 s2.1 highland mid)

uniform vec3 debug_color = vec3(1.0);                    // LOD debug tint (PlanetRenderer.debug_depth_tint)
uniform float debug_mix = 0.0;

varying float v_h;
varying float v_slope;
varying vec3 v_world;

void vertex() {
	v_h = CUSTOM0.r;
	v_slope = CUSTOM0.g;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = clamp(v_h * 1.6 - 0.45 + v_slope * 0.8, 0.0, 1.0);
	vec3 albedo = mix(mix(MARE, HIGHLAND, t), ml_to_linear(debug_color), debug_mix);
	MoonLit ml = ml_shade(albedo, v_world, NORMAL, VIEW, INV_VIEW_MATRIX);
	ALBEDO = ml_encode(ml.albedo);
	EMISSION = ml_encode(ml.base);
}
