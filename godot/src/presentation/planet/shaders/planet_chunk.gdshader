// Interim chunk material for the planet renderer core (TA-23). TA-24 replaces it with moon_terrain.gdshader
// (07 s3.1: biome ramp, ramp value, detail displacement) on moon_light.gdshaderinc (07 s1.5). It already
// reads the chunk CUSTOM0 layout of 03 s7.3: r = height01, g = slope01, b = biome / 255, a = skirt flag.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

const vec3 MARE = vec3(0.0513, 0.0578, 0.0844);       // #404552 linear (07 s2.1 mare mid)
const vec3 HIGHLAND = vec3(0.2918, 0.2789, 0.2462);   // #959189 linear (07 s2.1 highland mid)
const vec3 AMB_LOW = vec3(0.0242, 0.0273, 0.0395);    // #2B3142 x 0.22 hemisphere ambient, low
const vec3 AMB_HIGH = vec3(0.2671, 0.3515, 0.5776);   // #8EA0C8 x 0.38 hemisphere ambient, high
const float WRAP = 0.30;                              // 07 s1.5 wrap diffuse

uniform vec3 debug_color = vec3(1.0);                // LOD debug tint (PlanetRenderer.debug_depth_tint)
uniform float debug_mix = 0.0;

varying float v_h;
varying float v_slope;
varying vec3 v_up;

void vertex() {
	v_h = CUSTOM0.r;
	v_slope = CUSTOM0.g;
	v_up = normalize((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float t = clamp(v_h * 1.6 - 0.45 + v_slope * 0.8, 0.0, 1.0);
	vec3 albedo = mix(mix(MARE, HIGHLAND, t), debug_color, debug_mix);
	ALBEDO = albedo;
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 amb = mix(AMB_LOW, AMB_HIGH, 0.5 + 0.5 * dot(n_world, v_up));
	EMISSION = albedo * amb;
}

void light() {
	float d = clamp((dot(NORMAL, LIGHT) + WRAP) / (1.0 + WRAP), 0.0, 1.0);
	DIFFUSE_LIGHT += d * ATTENUATION * LIGHT_COLOR / PI;
}
