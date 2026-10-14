// unit_icon: camera-facing team-coloured glyph quads, one MultiMesh for the whole icon band (03 s7.9, 07 P4).
// Per instance: transform scale = world size, COLOR = team colour, INSTANCE_CUSTOM.x = glyph index. The glyph set
// below is a placeholder (0 triangle = ship, 1 disc = ground unit, 2 square = structure, 3 diamond); 06/07 own the
// final glyphs. Unshaded: the icon is the readability guarantee, so it is not lit.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

#define ML_NO_LIGHT
#include "res://src/presentation/shaders/moon_light.gdshaderinc"

varying float v_glyph;

void vertex() {
	v_glyph = INSTANCE_CUSTOM.x;
	// Billboard that keeps the instance scale (Godot docs: MultiMesh-safe billboard).
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	bb = bb * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
}

float sd_glyph(vec2 p, int g) {
	if (g == 0) {          // upward triangle
		vec2 q = vec2(abs(p.x), p.y + 0.5);
		return max(q.x * 1.7 + (q.y - 1.0) * 0.5, -q.y) * 0.9 - 0.02;
	}
	if (g == 1) {          // disc
		return length(p) - 0.45;
	}
	if (g == 2) {          // square
		return max(abs(p.x), abs(p.y)) - 0.38;
	}
	return abs(p.x) + abs(p.y) - 0.5;   // diamond
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = sd_glyph(p, int(round(v_glyph)));
	float edge = fwidth(d);
	float a = 1.0 - smoothstep(-edge, edge, d);
	vec3 c = ml_to_linear(COLOR.rgb);
	ALBEDO = ml_encode(c);
	ALPHA = a * COLOR.a;
}
