shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

#define PSX_OBJECT_BLEND_ALPHA
#include "res://shaders/lib/math/coordinates.gdshaderinc"
#include "res://shaders/lib/retro/psx_projection.gdshaderinc"
#include "res://shaders/lib/props/psx_object_base.gdshaderinc"
