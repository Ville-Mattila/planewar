// unit_decal: soft dark scorch quads lying on the ground (bomb impacts, 07 s6 / 03 s7.10). Colour (rgb = soot,
// a = remaining opacity) comes from the per-instance colour; radial falloff from UV. Alpha blended, no depth
// write, unshaded: a flat mark, not a lit surface. 4.8's Compatibility decals replace this later (R2 s1.3).
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, fog_disabled;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float edge = 1.0 - smoothstep(0.35, 1.0, r);
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * edge;
}
