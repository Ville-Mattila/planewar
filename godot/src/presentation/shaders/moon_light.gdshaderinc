// moon_light.gdshaderinc - the shared PLANEWAR light model (07 s1.5; ART-01 look-dev, S-ART-1).
// Every spatial material includes this file: units and structures (unit_lit), the moon (planet/shaders/
// moon_surface, later TA-24 moon_terrain), props (ART-03). Compatibility renderer, LDR.
//
// Colour space (measured in ART-01 on Godot 4.7.2 Compatibility, GL 3.3 and ANGLE/D3D11; REPORT s3):
// Compatibility treats ALBEDO and EMISSION as sRGB-encoded. It decodes them with Godot's polynomial
// sRGB->linear approximation, lights in linear (DIFFUSE_LIGHT is linear) and encodes the sum with an
// approximate pow. `source_color` textures and uniforms reach the shader unconverted. The polynomial is off
// near black (an unlit byte 8 shows as 1, 20 as 16, 40 as 38; hull_800 decodes 23 % dark), so this file
// computes in linear explicitly: inputs go through ml_to_linear(), and ml_encode() writes the value whose
// polynomial decode is exactly the linear result. Team glow then shows the exact 07 s2.2 hex.
//
// Terms (07 s1.5; values in linear light; a hex x k means srgb_to_linear(hex) * k):
//   wrap diffuse     d = clamp((N.L + w) / (1 + w), 0, 1), w = 0.30, in light() (the sun DirectionalLight3D)
//   radial ambient   mix(#2B3142 x 0.22, #8EA0C8 x 0.38, 0.5 + 0.5 N.up), up = normalize(world_pos)
//   earthshine       albedo * #9DB6E8 * ML_EARTH_GAIN * k, k = (0.45 + 0.55 max(0, -up.z)) * nf,
//                    nf = 1 - smoothstep(-0.10, 0.18, dot(up, sun_dir)); Earth stays at -Z
//   limb rim         day side only: albedo += #BFC9E0 * pow(1 - N.V, 3) * 0.20, faded in with camera height
//   sun_dir          global shader uniform (MoonLight.ensure_globals registers it; default +Z). MoonLight.
//                    set_sun_dir() keeps the sun light, which light() reads as LIGHT, aligned with it.
// Ambient and earthshine go to EMISSION (independent of the light count); the sun alone is in light().
//
// ART-01 tuning (within the +-20 % anchor band of 07 s1.5): ML_EARTH_GAIN 0.55 -> 0.50 so night mare at the
// Midnight Pole lands at albedo x (0.271, 0.368, 0.623) vs the target (0.30, 0.36, 0.55). MoonLight
// (planet/moon_light.gd) mirrors these constants; test_moon_light.gd asserts the two agree.
//
// Usage (spatial shader; render_mode specular_disabled):
//   #include "res://src/presentation/shaders/moon_light.gdshaderinc"
//   varying vec3 v_world;  void vertex() { v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
//   void fragment() {
//       MoonLit ml = ml_shade(albedo_linear, v_world, NORMAL, VIEW, INV_VIEW_MATRIX);
//       ALBEDO = ml_encode(ml.albedo); EMISSION = ml_encode(ml.base + own_emission_linear);
//   }
// light() is defined here; a shader that needs its own light() defines ML_NO_LIGHT before the include.

global uniform vec3 sun_dir;

const float ML_WRAP = 0.30;
const vec3 ML_AMB_LOW = vec3(0.00531, 0.00676, 0.01199);   // #2B3142 x 0.22
const vec3 ML_AMB_HIGH = vec3(0.10279, 0.13358, 0.21948);  // #8EA0C8 x 0.38
const vec3 ML_EARTH = vec3(0.33716, 0.46778, 0.80695);     // #9DB6E8
const float ML_EARTH_GAIN = 0.50;                          // 07 anchor 0.55, tuned in ART-01
const float ML_EARTH_BASE = 0.45;
const float ML_NIGHT_LO = -0.10;
const float ML_NIGHT_HI = 0.18;
const vec3 ML_RIM = vec3(0.10420, 0.11682, 0.14908);       // #BFC9E0 x 0.20
const float ML_RIM_POW = 3.0;
// ART-01: the rim is an orbit read. At Chase / Tactical heights it lifts every grazing terrain pixel (dark
// mare at the horizon rendered +59 % over the model on the day side), so it fades in with the camera's
// distance from the moon centre relative to the surface point: 1.25 x (about 1.5 km up) -> 1.75 x (4.5 km).
const float ML_RIM_NEAR = 1.25;
const float ML_RIM_FAR = 1.75;

// Godot's Compatibility sRGB->linear polynomial (the ALBEDO / EMISSION decode that ml_encode inverts).
const vec3 ML_P3 = vec3(0.305306011);
const vec3 ML_P2 = vec3(0.682171111);
const vec3 ML_P1 = vec3(0.012522878);

struct MoonLit {
	vec3 albedo;    // linear, rim included; goes to ALBEDO through ml_encode
	vec3 base;      // linear, light-independent: albedo * (ambient + earthshine); goes to EMISSION
};

// Exact sRGB EOTF: Compatibility hands source_color samples and uniforms to the shader unconverted.
vec3 ml_to_linear(vec3 c) {
	vec3 lo = c / 12.92;
	vec3 hi = pow((c + vec3(0.055)) / 1.055, vec3(2.4));
	return mix(hi, lo, lessThanEqual(c, vec3(0.04045)));
}

// ALBEDO / EMISSION value whose Compatibility decode is `lin` (two Newton steps on the decode polynomial,
// started from the exact sRGB encoding). Valid for 0 <= lin <= 1.
vec3 ml_encode(vec3 lin) {
	vec3 l = clamp(lin, vec3(0.0), vec3(1.0));
	vec3 x = mix(1.055 * pow(l, vec3(1.0 / 2.4)) - vec3(0.055), l * 12.92, lessThan(l, vec3(0.0031308)));
	for (int i = 0; i < 2; i++) {
		vec3 f = x * (x * (x * ML_P3 + ML_P2) + ML_P1) - l;
		vec3 df = x * (x * 3.0 * ML_P3 + 2.0 * ML_P2) + ML_P1;
		x -= f / df;
	}
	return clamp(x, vec3(0.0), vec3(1.0));
}

// 1 on the day side, 0 on the night side; the band matches the earthshine fade.
float ml_day(vec3 up) {
	return smoothstep(ML_NIGHT_LO, ML_NIGHT_HI, dot(up, normalize(sun_dir)));
}

vec3 ml_ambient(vec3 n_world, vec3 up) {
	return mix(ML_AMB_LOW, ML_AMB_HIGH, 0.5 + 0.5 * dot(n_world, up));
}

// Earthshine strength k (07 s1.5): 1 at the Midnight Pole, 0.45 at the terminator, 0 on the day side.
float ml_earth_k(vec3 up) {
	return (ML_EARTH_BASE + (1.0 - ML_EARTH_BASE) * max(0.0, -up.z)) * (1.0 - ml_day(up));
}

// albedo: linear base colour. world_pos: fragment position in world space (moon centre = origin).
// normal / view: NORMAL and VIEW (view space). inv_view: INV_VIEW_MATRIX.
MoonLit ml_shade(vec3 albedo, vec3 world_pos, vec3 normal, vec3 view, mat4 inv_view) {
	vec3 up = normalize(world_pos);
	vec3 n_world = normalize((inv_view * vec4(normal, 0.0)).xyz);
	float n_dot_v = clamp(dot(normal, view), 0.0, 1.0);
	float rim_fade = smoothstep(ML_RIM_NEAR, ML_RIM_FAR, length(inv_view[3].xyz) / length(world_pos));
	MoonLit r;
	r.albedo = albedo + ML_RIM * (pow(1.0 - n_dot_v, ML_RIM_POW) * ml_day(up) * rim_fade);
	r.base = albedo * (ml_ambient(n_world, up) + ML_EARTH * ML_EARTH_GAIN * ml_earth_k(up));
	return r;
}

#ifndef ML_NO_LIGHT
void light() {
	float d = clamp((dot(NORMAL, LIGHT) + ML_WRAP) / (1.0 + ML_WRAP), 0.0, 1.0);
	DIFFUSE_LIGHT += d * ATTENUATION * LIGHT_COLOR / PI;
}
#endif
