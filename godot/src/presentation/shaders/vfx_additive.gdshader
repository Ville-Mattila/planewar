// vfx_additive: additive billboards, cones, beams and halos (07 s6). Unshaded, no depth write, no screen or
// depth texture. Colour = tint x optional mask x vertex COLOR (particles fade alpha), colour-space safe.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

#define ML_NO_LIGHT
#include "res://src/presentation/shaders/moon_light.gdshaderinc"

uniform sampler2D mask : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_mask = false;
uniform vec3 tint : source_color = vec3(1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform vec2 scroll = vec2(0.0);                       // uv units per second (dock beams, exhaust cones)
uniform float end_fade : hint_range(0.0, 1.0) = 0.0;   // fades towards UV.y = 1 (cone tips, tracers)

void fragment() {
	vec4 m = use_mask ? texture(mask, UV + scroll * TIME) : vec4(1.0);
	float a = m.a * COLOR.a * mix(1.0, 1.0 - UV.y, end_fade);
	vec3 c = ml_to_linear(tint) * ml_to_linear(m.rgb) * ml_to_linear(COLOR.rgb) * intensity;
	ALBEDO = ml_encode(clamp(c, vec3(0.0), vec3(1.0)));
	ALPHA = clamp(a, 0.0, 1.0);
}
