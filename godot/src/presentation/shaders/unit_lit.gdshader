// unit_lit: the shared unit and structure material (07 s4.3). Team and state are per-material uniforms;
// ART-01 measured the instance-uniform variant (unit_lit_instanced) at 255 instances per scene on a 64 KB
// uniform buffer and recommends this path plus a material cache keyed by (team, state) (REPORT s5).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#define UNIT_PARAM uniform
#include "res://src/presentation/shaders/unit_lit.gdshaderinc"
