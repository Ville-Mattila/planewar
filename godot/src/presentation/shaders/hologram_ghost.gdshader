// hologram_ghost: build placement ghosts and unbuilt structure parts (07 s6 vfx_build_scaffold). A tinted
// fresnel body with scan lines by height above the moon centre. Blend add, no depth write.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, fog_disabled;

#define ML_NO_LIGHT
#include "res://src/presentation/shaders/moon_light.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.36, 0.78, 1.0);   // valid = ally blue, invalid = danger red
uniform float alpha : hint_range(0.0, 1.0) = 0.55;
uniform float line_pitch = 1.5;       // metres between scan lines
uniform float line_speed = 0.6;       // lines per second
uniform float clip01 : hint_range(0.0, 1.0) = 1.0;   // reveal height fraction (spawn-in / scaffold)
uniform float height_m = 10.0;        // model height used for clip01

varying vec3 v_world;
varying float v_h;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_h = VERTEX.y;
}

void fragment() {
	if (v_h > height_m * clip01) {
		discard;
	}
	float scan = 0.5 + 0.5 * sin(6.2831853 * (length(v_world) / line_pitch - TIME * line_speed));
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = ml_encode(ml_to_linear(tint));
	ALPHA = clamp(alpha * (0.35 + 0.45 * scan + 0.6 * fres), 0.0, 1.0);
}
