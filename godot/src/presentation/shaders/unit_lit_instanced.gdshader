// unit_lit_instanced: unit_lit with team and state as instance uniforms (07 s4.3 first choice). Works on
// Compatibility desktop GL and ANGLE (ART-01), but every instance reserves 16 vec4 slots of the global
// uniform buffer, which GLES3 caps at the hardware UBO size: 255 instances at 64 KB, 63 at the WebGL2
// minimum of 16 KB. Use only for small bounded sets (possessed unit, placement ghosts); see REPORT s5.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#define UNIT_PARAM instance uniform
#include "res://src/presentation/shaders/unit_lit.gdshaderinc"
