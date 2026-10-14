// shield_dome: vfx_shield_dome and the Core's integrated shield (07 s6). Sphere mesh, fresnel plus procedural
// hex pattern scrolled by TIME, up to 4 impact ripples. cull_disabled with FRONT_FACING selecting the side:
// front faces from outside, back faces only when the camera is inside (`camera_inside` = 1). Alpha is
// capped (`max_alpha`, 0.25 on mobile); additive, no depth write, no screen texture.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

#define ML_NO_LIGHT
#include "res://src/presentation/shaders/moon_light.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.36, 0.78, 1.0);
uniform float camera_inside : hint_range(0.0, 1.0) = 0.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.25;
uniform float hex_scale = 18.0;
uniform float hex_speed = 0.05;
uniform float fresnel_pow = 2.5;
uniform float strength : hint_range(0.0, 1.0) = 1.0;   // fade-in / fade-out of the dome
// xyz = unit direction of the hit in the dome's local space, w = age 0..1 (outside 0..1: inactive)
uniform vec4 ripples[4];

varying vec3 v_local;

void vertex() {
	v_local = normalize(VERTEX);
}

// Distance (in cell units) to the nearest hex cell edge; 0 on an edge.
float hex_edge(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	vec2 q = abs(dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw);
	return 0.5 - max(dot(q, s * 0.5), q.x);
}

void fragment() {
	bool inside = camera_inside > 0.5;
	if (FRONT_FACING == inside) {
		discard;
	}
	float ndv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float fres = pow(1.0 - ndv, fresnel_pow);
	vec2 uv = vec2(atan(v_local.x, v_local.z) * 0.15915494, v_local.y * 0.5) * hex_scale;
	uv += vec2(TIME * hex_speed, 0.0);
	float edge = 1.0 - smoothstep(0.0, 0.08, hex_edge(uv));
	float rip = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 r = ripples[i];
		if (r.w >= 0.0 && r.w < 1.0) {
			float d = acos(clamp(dot(v_local, normalize(r.xyz)), -1.0, 1.0));
			rip += (1.0 - r.w) * (1.0 - smoothstep(0.0, 0.12, abs(d - r.w * 1.2)));
		}
	}
	float a = (0.35 * fres + 0.5 * edge * (0.25 + fres) + rip) * strength;
	ALBEDO = ml_encode(ml_to_linear(tint));
	ALPHA = min(clamp(a, 0.0, 1.0), max_alpha);
}
