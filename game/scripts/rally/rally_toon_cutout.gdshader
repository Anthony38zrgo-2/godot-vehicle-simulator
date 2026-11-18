shader_type spatial;
render_mode specular_disabled, cull_disabled;

#define TOON_ALPHA_CUTOUT
#include "res://scripts/rally/rally_toon_lighting.gdshaderinc"
