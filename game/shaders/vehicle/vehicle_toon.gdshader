shader_type spatial;
render_mode specular_disabled, cull_back;

#include "res://shaders/lib/math/hash_noise.gdshaderinc"
#include "res://shaders/lib/retro/psx_projection.gdshaderinc"
#include "res://shaders/lib/surface/base_albedo_contract.gdshaderinc"
#include "res://shaders/lib/vehicle/dirt_overlay.gdshaderinc"
#include "res://shaders/lib/vehicle/paint_bands.gdshaderinc"
#include "res://shaders/lib/vehicle/toon_core.gdshaderinc"
