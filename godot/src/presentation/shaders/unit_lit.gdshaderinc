// unit_lit body (07 s4.3; ART-01 look-dev, ART-03 finishes the library). Included by unit_lit.gdshader
// (UNIT_PARAM = uniform: per-material team / state, the path ART-01 recommends) and by
// unit_lit_instanced.gdshader (UNIT_PARAM = instance uniform: per-instance, capped by the GLES3 global
// uniform buffer; see docs/spikes/ART-01/REPORT.md). The including file defines UNIT_PARAM and render_mode.
//
// Atlas: 256 x 256 palette atlas (tools/blender/palette.json -> godot/assets/textures/unit_atlas.png). Every
// face samples one swatch centre; alpha carries the 2-bit class: 0 plain (lit), 1 team paint
// (team_color * rgb.r, lit), 2 emissive accent (EMISSION = rgb), 3 team glow (EMISSION = team_color * rgb.r,
// unlit: the exact 07 s2.2 hex at rgb.r = 1). Emblem cells (v >= 0.875) shift u by team_index * 0.125.

#include "res://src/presentation/shaders/moon_light.gdshaderinc"

uniform sampler2D atlas : source_color, filter_nearest_mipmap, repeat_disable;

UNIT_PARAM int team_index = 0;
UNIT_PARAM vec3 team_color : source_color = vec3(1.0);
UNIT_PARAM float build_progress = 1.0;
UNIT_PARAM float damage01 = 0.0;
UNIT_PARAM float wreck = 0.0;

const float EMBLEM_V = 0.875;
const float EMBLEM_STEP = 0.125;
const float BUILD_DIM = 0.25;     // unbuilt part of a structure: dark frame (ART-03 replaces with hologram)
const float DAMAGE_DIM = 0.45;    // fully damaged hull darkens to 55 %
const float WRECK_DIM = 0.25;     // wrecks keep 25 % albedo and lose team light

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	if (uv.y >= EMBLEM_V) {
		uv.x += float(team_index) * EMBLEM_STEP;
	}
	vec4 s = texture(atlas, uv);
	int cls = int(round(s.a * 3.0));
	vec3 rgb = ml_to_linear(s.rgb);              // Compatibility does not linearise source_color (see include)
	vec3 team = ml_to_linear(team_color);
	vec3 albedo = rgb;
	vec3 glow = vec3(0.0);
	if (cls == 1) {
		albedo = team * rgb.r;
	} else if (cls == 2) {
		glow = rgb;
		albedo = vec3(0.0);
	} else if (cls == 3) {
		glow = team * rgb.r * (1.0 - wreck);
		albedo = vec3(0.0);
	}
	float dim = (1.0 - DAMAGE_DIM * damage01) * mix(1.0, WRECK_DIM, wreck);
	dim *= build_progress >= 1.0 ? 1.0 : BUILD_DIM;
	MoonLit ml = ml_shade(albedo * dim, v_world, NORMAL, VIEW, INV_VIEW_MATRIX);
	ALBEDO = cls >= 2 ? vec3(0.0) : ml_encode(ml.albedo);   // unlit zones get no rim either: exact hex
	EMISSION = ml_encode(ml.base + glow);
}
