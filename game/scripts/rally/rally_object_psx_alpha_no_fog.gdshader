shader_type spatial;
render_mode cull_disabled, diffuse_lambert, fog_disabled;

#define PSX_OBJECT_BLEND_ALPHA
#include "res://scripts/rally/rally_object_psx_surface.gdshaderinc"
