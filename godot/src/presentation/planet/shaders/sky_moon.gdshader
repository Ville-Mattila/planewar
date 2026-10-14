// sky_moon: black space, static hash stars (3 magnitudes, no twinkle), the sun disc (2 degrees at sun_dir) and
// the Earth (a full 6 degree disc exactly at -Z, above the Midnight Pole; R0 C2-31). Vacuum: no scattering.
// 07 s1.5, 03 s7.8. TA-24 hookup version (SkyMoon.apply); ART-15 may restyle the Earth within the same
// contract (disc size and direction are asserted by test_sky_moon.gd).
shader_type sky;

global uniform vec3 sun_dir;

const vec3 SPACE = vec3(0.00152, 0.00212, 0.00368);     // #05070C, linear
const vec3 SUN_COL = vec3(1.0, 0.8796, 0.7157);         // #FFF1DC, linear
const vec3 OCEAN = vec3(0.0497, 0.1589, 0.4620);        // #3F6FB5, linear
const vec3 LAND = vec3(0.1100, 0.1950, 0.0700);
const vec3 CLOUD = vec3(0.86, 0.90, 0.95);
const float EARTH_HALF_DEG = 3.0;                       // 6 degree disc
const float SUN_HALF_DEG = 1.0;                         // 2 degree disc

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

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = SPACE;

	// stars: one candidate per cell of a 3D lattice on the unit sphere, three magnitudes
	vec3 sp = d * 90.0;
	vec3 cell = floor(sp);
	float hs = hash13(cell);
	float star = step(0.9965, hs);
	float mag = 0.35 + 0.65 * step(0.9985, hs) + 0.25 * step(0.9995, hs);
	vec3 centre = cell + 0.2 + 0.6 * vec3(hash13(cell + 1.7), hash13(cell + 3.1), hash13(cell + 5.3));
	float dot_r = smoothstep(0.55, 0.0, distance(sp, centre));
	col += vec3(0.9, 0.93, 1.0) * star * mag * dot_r * 0.6;

	// Earth: exactly at -Z
	vec3 earth_dir = vec3(0.0, 0.0, -1.0);
	float cos_e = dot(d, earth_dir);
	float rad_e = radians(EARTH_HALF_DEG);
	if (cos_e > cos(rad_e) - 0.002) {
		vec2 q = d.xy / sin(rad_e);                  // -1..1 across the disc (small angles)
		float r2 = dot(q, q);
		float z = sqrt(max(1.0 - r2, 0.0));
		vec3 n = vec3(q, -z);                        // point on the visible hemisphere
		float land = smoothstep(0.52, 0.58, vnoise(n * 3.1 + 4.0) * 0.7 + vnoise(n * 7.3) * 0.3);
		vec3 surf = mix(OCEAN, LAND, land);
		float swirl = vnoise(vec3(n.xy * 5.0 + vec2(sin(n.y * 4.0), cos(n.x * 3.0)), n.z * 2.0 + 9.0));
		surf = mix(surf, CLOUD, smoothstep(0.55, 0.78, swirl) * 0.8);
		float edge = smoothstep(1.0, 0.96, sqrt(r2));
		col = mix(col, surf * (0.65 + 0.35 * z), edge);
	}

	// sun disc with a soft halo
	float cos_s = dot(d, normalize(sun_dir));
	float rad_s = radians(SUN_HALF_DEG);
	float disc = smoothstep(cos(rad_s * 1.08), cos(rad_s * 0.96), cos_s);
	float halo = pow(max(cos_s, 0.0), 800.0) * 0.25;
	col = mix(col + SUN_COL * halo, SUN_COL * 4.0, disc);

	COLOR = col;
}
