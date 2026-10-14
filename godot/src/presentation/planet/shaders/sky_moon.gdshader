// sky_moon: the moon's sky (07 s1.5 Sky, R0 C2-31; ART-15). Vacuum: black space, static hash stars (3 magnitudes,
// no twinkle), the sun (a 2 degree disc at sun_dir, one flat additive halo, no gradient glow: 07 s1.1 rule 5) and the
// Earth, a full 6 degree disc exactly at -Z above the Midnight Pole (art-scaled; true size is about 1.9 degrees) with
// procedural ocean #3F6FB5, land blobs and a cloud swirl. Cool grey moon, warm white sun, blue earthshine: the sun is
// the only warm hue in the sky, so stars, land and cloud are cool.
// Colour (ART-01 REPORT s3): constants are linear; every output goes through ml_encode of moon_light.gdshaderinc, and
// the empty-space path writes SPACE_ENC (= ml_encode(SPACE), asserted by the golden, byte (5, 7, 12)) so most pixels
// cost one hash. 1 LSB of triangular dither is added only where a gradient exists (Earth shading, halo), so there is
// no banding on flat space and none on the discs. Cost: one hash13 per pixel; the Earth branch (vnoise x 7) runs
// only inside its 6 degree disc. Disc size, direction and constants are asserted by test_sky_moon.gd.
shader_type sky;

#define ML_NO_LIGHT
#include "res://src/presentation/shaders/moon_light.gdshaderinc"

uniform float earth_plain = 0.0;     // 1 = ocean only, no land or cloud (golden measurement of #3F6FB5)

const vec3 SPACE = vec3(0.00152, 0.00212, 0.00368);     // #05070C, linear
const vec3 SPACE_ENC = vec3(0.0420, 0.0500, 0.0641);   // ml_encode(SPACE), +1 LSB on r and g (measured: renders byte 5, 7, 12)
const vec3 SUN_COL = vec3(1.0, 0.8796, 0.7157);         // #FFF1DC, linear
const vec3 STAR_COL = vec3(0.80, 0.86, 1.0);            // cool white
const vec3 OCEAN = vec3(0.0497, 0.1589, 0.4620);        // #3F6FB5, linear
const vec3 LAND = vec3(0.0980, 0.2070, 0.1900);         // cool sage, #587B76-ish: no warm hue in the sky
const vec3 CLOUD = vec3(0.7300, 0.7900, 0.8800);
const vec3 ATMOSPHERE = vec3(0.2400, 0.4000, 0.7600);   // thin cool limb
const vec3 EARTH_DIR = vec3(0.0, 0.0, -1.0);          // exactly -Z, above the Midnight Pole (R0 C2-31)
const float EARTH_HALF_DEG = 3.0;                       // 6 degree disc
const float SUN_HALF_DEG = 1.0;                         // 2 degree disc
const float SUN_HALO_MULT = 3.0;                        // flat halo radius, in disc radii
const float SUN_HALO_AMOUNT = 0.10;
const float STAR_CELLS = 110.0;                          // lattice cells across the unit sphere

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

// One candidate per lattice cell; three magnitudes (faint, mid, bright). Returns linear brightness 0..1.
float star_field(vec3 d) {
	vec3 sp = d * STAR_CELLS;
	vec3 cell = floor(sp);
	float hs = hash13(cell);
	float star = step(0.9930, hs);
	if (star == 0.0) {
		return 0.0;
	}
	float mag = 0.40 + 0.35 * step(0.9965, hs) + 0.25 * step(0.9985, hs);
	vec3 centre = cell + 0.34 + 0.32 * vec3(hash13(cell + 1.7), hash13(cell + 3.1), hash13(cell + 5.3));
	return mag * smoothstep(0.34, 0.0, distance(sp, centre));   // radius = margin 0.34: never clipped by the cell
}

// Earth disc at -Z. Returns rgb in .xyz and coverage in .w; (0,0,0,0) outside.
vec4 earth(vec3 d) {
	float rad_e = radians(EARTH_HALF_DEG);
	if (dot(d, EARTH_DIR) < cos(rad_e) - 0.002) {
		return vec4(0.0);
	}
	vec2 q = d.xy / sin(rad_e);                          // -1..1 across the disc (small angles)
	float r2 = dot(q, q);
	float z = sqrt(max(1.0 - r2, 0.0));
	vec3 n = vec3(q, -z);                                // point on the visible hemisphere
	vec3 surf = OCEAN;
	if (earth_plain < 0.5) {
		float land = smoothstep(0.52, 0.58, vnoise(n * 3.1 + 4.0) * 0.7 + vnoise(n * 7.3) * 0.3);
		surf = mix(OCEAN, LAND, land);
		float swirl = vnoise(vec3(n.xy * 5.0 + vec2(sin(n.y * 4.0), cos(n.x * 3.0)), n.z * 2.0 + 9.0));
		surf = mix(surf, CLOUD, smoothstep(0.60, 0.82, swirl) * 0.75);
	}
	surf *= 0.80 + 0.20 * z;                             // limb darkening; the disc centre is the exact ocean colour
	surf = mix(surf, ATMOSPHERE, smoothstep(0.80, 0.98, sqrt(r2)) * 0.35);
	return vec4(surf, smoothstep(1.0, 0.97, sqrt(r2)));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sdir = normalize(sun_dir);
	float cos_s = dot(d, sdir);
	float rad_s = radians(SUN_HALF_DEG);
	float halo = smoothstep(cos(rad_s * SUN_HALO_MULT * 1.04), cos(rad_s * SUN_HALO_MULT * 0.96), cos_s);
	float disc = smoothstep(cos(rad_s * 1.04), cos(rad_s * 0.96), cos_s);
	vec4 e = earth(d);
	float s = star_field(d);
	if (e.w == 0.0 && disc == 0.0 && halo == 0.0 && s == 0.0) {
		COLOR = SPACE_ENC;
	} else {
		vec3 col = SPACE + STAR_COL * (s * 0.6);
		col = mix(col, e.xyz, e.w);
		col += SUN_COL * (halo * SUN_HALO_AMOUNT);
		col = mix(col, SUN_COL, disc);
		// 1 LSB triangular dither where there is a gradient (Earth shading, halo edge); flat space stays clean
		float n = hash13(d * 2048.0) + hash13(d * 2048.0 + 7.7) - 1.0;
		float grad = max(e.w, halo) * (1.0 - disc);
		COLOR = clamp(ml_encode(col) + vec3(n * grad / 255.0), 0.0, 1.0);
	}
}
