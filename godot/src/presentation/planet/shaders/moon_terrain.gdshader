// moon_terrain: the planet material (07 s3.1, 03 s7.8; TA-24). Chunk CUSTOM0 layout (03 s7.3): r = height01,
// g = slope01 (angle / 90 deg), b = cube face 0..5 / 255 (the biome id is read per pixel from the baked u8 face),
// a = 255 on skirt vertices. UV = the vertex's (u, v) on its face. Chunks sit at the origin with identity transforms.
// Lit by moon_light.gdshaderinc; every colour goes through ml_to_linear / ml_encode (ART-01 REPORT s3).
//   biome id   biome_faces: Texture2DArray R8, nearest texelFetch; the colour is blended over the 4 texels around the pixel (ART-14)
//   ramp       moon_ramp.png, 64 x 16 RGBA8: row = biome id, column = ramp value (07 s2.1)
//   ramp value v = 0.55 fbm(pos 0.015) + 0.30 (1 - slope01) + 0.15 cell(pos 0.12)
//   craters    one jittered crater per cell at 40 / 15 / 6 m, mean-zero bowl + rim profile, vertex displacement
//              (<= 1.2 m total) plus albedo darkening in the bowls; fades to 0 on skirts and beyond
//              detail_range_m (tier detail_displacement_m), and to FOOTPRINT_KEEP of that inside footprints
//   footprints sites[] (xyz world, w radius m) from PlanetRenderer.set_flatten_sites: displacement x
//              mix(FOOTPRINT_KEEP, 1, smoothstep(r, 1.5 r, dist)) so it is <= 0.6 m under a structure
//   shading    flat (faceted) normals from screen derivatives; no triplanar, no normal maps (ADR-04)
// Detail never changes Terrain.height_at (07 s3). MoonDetail (moon_detail.gd) mirrors the constants below;
// test_moon_terrain.gd asserts the two agree.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#include "res://src/presentation/shaders/moon_light.gdshaderinc"

const float DETAIL_AMP_40 = 0.6;      // bowl depth (m) of the 40 m layer
const float DETAIL_AMP_15 = 0.4;
const float DETAIL_AMP_6 = 0.2;       // sum 1.2 (07 s3.1)
const float FOOTPRINT_KEEP = 0.5;     // 1.2 m x 0.5 = 0.6 m inside footprints (R0 C2-31)
const float FOOTPRINT_OUTER = 1.5;
const float DARKEN_BOWL = 0.22;       // albedo darkening at a full bowl
const float EDGE_WARP = 0.9;          // biome edge noise warp in texels (ART-14)
const int MAX_SITES = 32;

uniform sampler2D ramp : filter_linear, repeat_disable;
uniform sampler2DArray biome_faces : filter_nearest, repeat_disable;
uniform float detail_range_m = 300.0;      // tier detail_displacement_m; 0 = no detail at all
uniform float ramp_v_override = -1.0;      // >= 0 forces the ramp value (measurement plates)
uniform int site_count = 0;
uniform vec4 sites[MAX_SITES];
uniform vec3 debug_color = vec3(1.0);      // LOD debug tint (PlanetRenderer.debug_depth_tint)
uniform float debug_mix = 0.0;

varying vec3 v_world;
varying vec2 v_uv;
varying float v_slope;
varying float v_face;
varying float v_fade;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

float fbm3(vec3 p) {
	return (0.5 * vnoise(p) + 0.25 * vnoise(p * 2.03 + 11.7) + 0.125 * vnoise(p * 4.01 + 23.1)) / 0.875;
}

// One jittered crater per cell, wholly inside its cell. Height in units of the layer amplitude: bowl -1 at the
// centre, rim +1/3 at t^2 = 2/3, mean zero over the disc (integral of (1 - u)(1/3 - u) t dt = 0, u = t^2).
float crater_layer(vec3 p, float cell_m) {
	vec3 q = p / cell_m;
	vec3 c = floor(q);
	vec3 h = hash33(c);
	float rr = 0.18 + 0.30 * hash13(c + 7.3);
	vec3 centre = vec3(rr) + (1.0 - 2.0 * rr) * h;
	float t = length(fract(q) - centre) / rr;
	float u = t * t;
	return step(u, 1.0) * (-3.0) * (1.0 - u) * (1.0 / 3.0 - u);
}

float crater_height(vec3 p) {
	return DETAIL_AMP_40 * crater_layer(p, 40.0) + DETAIL_AMP_15 * crater_layer(p + 5.1, 15.0) + DETAIL_AMP_6 * crater_layer(p + 9.7, 6.0);
}

float footprint_scale(vec3 p) {
	float s = 1.0;
	for (int i = 0; i < MAX_SITES; i++) {
		if (i >= site_count) {
			break;
		}
		float r = sites[i].w;
		s = min(s, mix(FOOTPRINT_KEEP, 1.0, smoothstep(r, r * FOOTPRINT_OUTER, distance(p, sites[i].xyz))));
	}
	return s;
}

float texid(ivec2 t, ivec2 hi, int layer) {
	return floor(texelFetch(biome_faces, ivec3(clamp(t, ivec2(0), hi), layer), 0).r * 255.0 + 0.5);
}

vec3 ramp_rgb(float id, float v) {
	return texture(ramp, vec2((v * 63.0 + 0.5) / 64.0, (id + 0.5) / 16.0)).rgb;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float not_skirt = 1.0 - step(0.5, CUSTOM0.a);
	float fade = 0.0;
	if (detail_range_m > 0.0) {
		float dist = distance(wp, CAMERA_POSITION_WORLD);
		fade = (1.0 - smoothstep(0.5 * detail_range_m, detail_range_m, dist)) * not_skirt;
	}
	if (fade > 0.0) {
		fade *= footprint_scale(wp);
		wp += normalize(wp) * (crater_height(wp) * fade);
		VERTEX = wp;
	}
	v_world = wp;
	v_uv = UV;
	v_slope = CUSTOM0.g;
	v_face = CUSTOM0.b * 255.0;
	v_fade = fade;
}

void fragment() {
	vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(fn, VIEW) < 0.0 ? -fn : fn;

	vec3 pos = v_world;
	float v = 0.55 * fbm3(pos * 0.015) + 0.30 * (1.0 - v_slope) + 0.15 * hash13(floor(pos * 0.12));
	if (ramp_v_override >= 0.0) {
		v = ramp_v_override;
	}
	v = clamp(v, 0.0, 1.0);
	// ART-14: the baked ids stay nearest (rows are not ordered), but the COLOUR is blended across the four
	// neighbouring texels with a noise-warped smoothstep weight, so patch edges are soft and ragged instead of
	// 9 m stair-steps. Away from edges (all four ids equal) it is one ramp fetch and equals Terrain.biome_at.
	ivec3 sz = textureSize(biome_faces, 0);
	int layer = int(v_face + 0.5);
	vec2 fp = v_uv * float(sz.x - 1) + (vec2(vnoise(pos * 0.35), vnoise(pos * 0.35 + 17.0)) - 0.5) * EDGE_WARP;
	ivec2 i0 = ivec2(floor(fp));
	vec2 f = fp - vec2(i0);
	f = f * f * (3.0 - 2.0 * f);
	ivec2 hi = ivec2(sz.x - 1);
	float id00 = texid(i0, hi, layer);
	float id10 = texid(i0 + ivec2(1, 0), hi, layer);
	float id01 = texid(i0 + ivec2(0, 1), hi, layer);
	float id11 = texid(i0 + ivec2(1, 1), hi, layer);
	float id = id00;
	vec3 albedo;
	if (id10 == id00 && id01 == id00 && id11 == id00) {
		albedo = ml_to_linear(ramp_rgb(id00, v));
	} else {
		vec3 c00 = ml_to_linear(ramp_rgb(id00, v));
		vec3 c10 = ml_to_linear(ramp_rgb(id10, v));
		vec3 c01 = ml_to_linear(ramp_rgb(id01, v));
		vec3 c11 = ml_to_linear(ramp_rgb(id11, v));
		albedo = mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
		id = f.y < 0.5 ? (f.x < 0.5 ? id00 : id10) : (f.x < 0.5 ? id01 : id11);
	}

	// cold_trap (4): sparse static frost speckle; solar_plateau (6): faint tile grid (07 s2.1, s3.1)
	float cold = step(3.5, id) * step(id, 4.5);
	float frost = step(0.985, hash13(floor(pos * 2.5))) * cold;
	albedo = mix(albedo, vec3(0.72, 0.80, 0.88), frost * 0.85);
	float plateau = step(5.5, id) * step(id, 6.5);
	vec2 grid = abs(fract(pos.xy * 0.125 + pos.z * 0.0625) - 0.5);
	albedo *= 1.0 - 0.05 * plateau * step(0.485, max(grid.x, grid.y));

	if (v_fade > 0.0) {
		float bowl = max(0.0, -crater_layer(pos, 40.0)) * DETAIL_AMP_40 + max(0.0, -crater_layer(pos + 5.1, 15.0)) * DETAIL_AMP_15
				+ max(0.0, -crater_layer(pos + 9.7, 6.0)) * DETAIL_AMP_6;
		albedo *= 1.0 - DARKEN_BOWL * min(bowl / 0.8, 1.0) * v_fade;
	}
	albedo = mix(albedo, ml_to_linear(debug_color), debug_mix);

	MoonLit ml = ml_shade(albedo, pos, NORMAL, VIEW, INV_VIEW_MATRIX);
	ALBEDO = ml_encode(ml.albedo);
	EMISSION = ml_encode(ml.base);
}
