class_name RallyStageVisualMaterialAdjuster
extends Node

const CUTOUT_MATERIAL_NAMES := [
	"grass",
	"russian_tree_plane",
	"forest_mixed_1",
	"forest_mixed_2",
	"forest_mixed_3",
	"forest_mixed_1_end_left",
	"forest_mixed_1_end_right",
	"bush_4",
	"audience_3",
	"audience_4",
	"fence_1_1",
	"fence_1_2",
	"fence_gate_1",
	"fence_metal",
	"string_red",
	"power_line_1",
	"power_line_cord",
	"polyn_1_wire",
	"terrain_field_1_",
]

@export var visual_root_path: NodePath
@export var alpha_scissor_threshold: float = 0.38
@export var enforce_dreamcast_pipeline: bool = true

var adjusted_surface_count: int = 0
var prepared_textures: Dictionary = {}


func _ready() -> void:
	var visual_root := get_node_or_null(visual_root_path)
	if visual_root == null:
		return
	adjust_node(visual_root)
	print("RALLY_STAGE_VISUAL_ADJUSTED surfaces=", adjusted_surface_count)


func adjust_node(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mesh_instance := node as MeshInstance3D
		# En Dreamcast los objetos del escenario rara vez proyectaban shadow maps dinamicos
		if enforce_dreamcast_pipeline:
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		for surface_index in mesh_instance.mesh.get_surface_count():
			var mat := mesh_instance.get_active_material(surface_index)
			if mat is BaseMaterial3D:
				adjust_material(mat as BaseMaterial3D)
	for child in node.get_children():
		adjust_node(child)


func adjust_material(material: BaseMaterial3D) -> void:
	var material_name := material.resource_name.to_lower()
	var is_cutout := CUTOUT_MATERIAL_NAMES.has(material_name) or material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR

	# Sponsor banners already contain opposing faces with their own UVs.
	# Drawing both sides of each face makes the coplanar fronts/backs fight.
	if material_name == "sponsors" or material_name == "fin_sponsors":
		material.cull_mode = BaseMaterial3D.CULL_BACK

	if enforce_dreamcast_pipeline:
		# 1. Gouraud Shading (Iluminacion por vertice clasica de fines de los 90)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		material.roughness = 1.0
		material.metallic = 0.0
		# Suavizado con filtrado anisotrópico para superficies vistas en ángulo.
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if material.albedo_texture != null:
			material.albedo_texture = prepare_texture(material.albedo_texture)
		# Asegurar texture_repeat activo para que las texturas que se repiten (bosque, carretera) no se estiren
		if is_cutout or not material_name.begins_with("sign_"):
			material.set_flag(BaseMaterial3D.FLAG_USE_TEXTURE_REPEAT, true)

	if is_cutout:
		# Punch-through alpha de PowerVR2
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = alpha_scissor_threshold
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.disable_receive_shadows = true

		# En lugar de UNSHADED (que rompe el balance con la niebla y el clima),
		# usamos iluminacion por vertice con backlight para igualar ambas caras del plano.
		material.backlight_enabled = true
		material.backlight = Color(0.65, 0.65, 0.65)

	adjusted_surface_count += 1


func prepare_texture(texture: Texture2D) -> Texture2D:
	var key := texture.get_instance_id()
	if prepared_textures.has(key):
		return prepared_textures[key]
	var pixels := texture.get_image()
	if pixels == null or pixels.has_mipmaps():
		return texture
	if pixels.is_compressed() and pixels.decompress() != OK:
		return texture
	if pixels.generate_mipmaps() != OK:
		return texture
	var prepared := ImageTexture.create_from_image(pixels)
	prepared_textures[key] = prepared
	return prepared
