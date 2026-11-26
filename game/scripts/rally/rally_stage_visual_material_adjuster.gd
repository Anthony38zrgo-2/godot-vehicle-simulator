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
	# Kenia (shader_id == 5)
	"kenya_audience",
	"kenya_bighut_roofalpha",
	"kenya_roundhut_pale",
	"kenya_roundhut_roofalpha",
	"plane2_bush",
	"plane2_wood",
	"plane3_bush",
	"plane3_wood",
	"plane_bush",
	"plane_bush2",
	"rope",
	"village_fence",
	# Finlandia (shader_id == 5)
	"fin_fence_1_1",
	"fin_fence_1_2",
	"fin_fence_metal",
	"fin_field1_edge",
	"fin_forest_mixed1",
	"fin_pole_wires",
	"fin_powerline_insulation",
	"fin_puuaita",
	"fin_string_red",
	"fin_trees_leaves",
	"forest_ends",
	"forest_ends2",
	# Suecia (shader_id == 5)
	"fence_snow_1",
	"forest_snow_1",
	"forest_snow_1_end",
	"forest_snow_2",
	"forest_snow_2_end",
	"polyn_1_wire",
	"sweden_tree_plane",
	# Suiza (shader_id == 5)
	"fence_metal_2",
	"fence_metal_tunnel_1",
	"mountain_tree_plane",
	"waterfall_1",
	"waterfall_2",
	# Comunes (ya presentes o compartidos)
	# "audience_4", "fence_metal", "string_red" (arriba)
]

## Banners/carteles que el .glb exporta con CLAMP_TO_EDGE: nunca forzar REPEAT.
const BANNER_MATERIAL_PREFIXES := [
	"sign_",
	"checkpoint",
	"fin_checkpoint",
	"gate_finish",
	"fin_gate_finish",
	"sponsors",
	"fin_sponsors",
]

const ObjectMaterial := preload("res://scripts/rally/rally_object_psx_material.gd")
const OBJECT_TOKENS := ["tree", "forest", "bush", "audience", "spectator", "fence", "hut", "house", "building", "barn", "cabin", "village", "power_line", "powerline", "pole", "guardarrail", "guardrail", "checkpoint", "gate_finish", "sponsors", "sign_", "string_red", "rope", "meta_", "tunnel", "bridge"]
const GROUND_MESH_PREFIXES := ["terrain", "road", "ladera", "rajuntay dem", "rajuntay regional dem", "backdrop", "mountain", "ground"]

const STATIC_WATER_SHADER := preload("res://scripts/rally/rally_static_water.gdshader")
const WATER_DETAIL_TEX := preload("res://assets/rally/water/water_detail.jpg")
const WATER_BODY_TOKENS := ["water", "lake", "lago", "agua", "pond", "lagoon", "laguna", "sea"]
const WATER_EXCLUDE_TOKENS := ["waterfall", "bank", "terrain", "road", "dry", "rock", "wall", "sign", "snow", "ice", "wet"]

@export var visual_root_path: NodePath
@export var alpha_scissor_threshold: float = 0.38
@export var enforce_dreamcast_pipeline: bool = true

var adjusted_surface_count: int = 0
var adjusted_materials: Dictionary = {}
var static_water_materials: Dictionary = {}
var prepared_textures: Dictionary = {}
var object_materials: Dictionary = {}
var _hidden_finish_surface: StandardMaterial3D


func _ready() -> void:
	var visual_root := get_node_or_null(visual_root_path)
	if visual_root == null:
		return
	adjust_node(visual_root)
	print("RALLY_STAGE_VISUAL_ADJUSTED surfaces=", adjusted_surface_count)


func adjust_node(node: Node) -> void:
	# Las láminas de cauce dinámico (RallyRiverChannels) llevan ShaderMaterial
	# propio por instancia: solo se tocan BaseMaterial3D, así el shader del
	# río y sus parámetros (cota, lecho, lluvia) quedan protegidos.
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mesh_instance := node as MeshInstance3D
		var mesh_name := str(mesh_instance.name).to_lower()
		if mesh_name in ["meta_l", "meta_r"] or mesh_name.begins_with("meta_l_soporte_") or mesh_name.begins_with("meta_r_soporte_"):
			mesh_instance.hide()
			return
		# En Dreamcast los objetos del escenario rara vez proyectaban shadow maps dinamicos
		if enforce_dreamcast_pipeline:
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		for surface_index in mesh_instance.mesh.get_surface_count():
			var mat := mesh_instance.get_active_material(surface_index)
			if mat != null and mat.resource_name.to_lower().get_slice(".", 0) in ["gate_finish", "fin_gate_finish"]:
				if _hidden_finish_surface == null:
					_hidden_finish_surface = StandardMaterial3D.new()
					_hidden_finish_surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					_hidden_finish_surface.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
					_hidden_finish_surface.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
				mesh_instance.set_surface_override_material(surface_index, _hidden_finish_surface)
				continue
			if mat is BaseMaterial3D and not bool(mat.get_meta("rally_dynamic_water", false)):
				var base_mat := mat as BaseMaterial3D
				if is_static_water_candidate(base_mat.resource_name.to_lower(), mesh_instance.name.to_lower()):
					var water_mat := _get_or_create_static_water_material(base_mat)
					mesh_instance.set_surface_override_material(surface_index, water_mat)
					adjusted_surface_count += 1
				else:
					adjust_material(base_mat)
					if _is_stage_object(str(mesh_instance.name).to_lower(), base_mat.resource_name.to_lower()):
						var object_mat := ObjectMaterial.cached(base_mat, object_materials)
						if object_mat != base_mat:
							mesh_instance.set_surface_override_material(surface_index, object_mat)
	for child in node.get_children():
		adjust_node(child)


static func _is_stage_object(mesh_name: String, material_name: String) -> bool:
	for prefix in GROUND_MESH_PREFIXES:
		if mesh_name.begins_with(prefix):
			return false
	if material_name.begins_with("waterfall") or material_name in ["river1_1", "river2_1", "terrain_field_1_", "fin_field1_edge"]:
		return false
	if CUTOUT_MATERIAL_NAMES.has(material_name):
		return true
	for token in OBJECT_TOKENS:
		if mesh_name.contains(token) or material_name.contains(token):
			return true
	return false


static func is_static_water_candidate(material_name: String, mesh_name: String = "") -> bool:
	if material_name == "river1_1" or material_name == "river2_1":
		return false
	for excluded in WATER_EXCLUDE_TOKENS:
		if material_name.contains(excluded):
			return false
	for token in WATER_BODY_TOKENS:
		if material_name.contains(token):
			return true
	if material_name.is_empty() or material_name.begins_with("material"):
		for excluded in WATER_EXCLUDE_TOKENS:
			if mesh_name.contains(excluded):
				return false
		for token in WATER_BODY_TOKENS:
			if mesh_name.contains(token):
				return true
	return false


func _get_or_create_static_water_material(base_mat: BaseMaterial3D) -> ShaderMaterial:
	var key := base_mat.get_instance_id()
	if static_water_materials.has(key):
		return static_water_materials[key] as ShaderMaterial
	var sm := ShaderMaterial.new()
	sm.shader = STATIC_WATER_SHADER
	sm.set_shader_parameter("water_detail_tex", WATER_DETAIL_TEX)
	var col := base_mat.albedo_color
	var use_tex := false
	var tex := base_mat.albedo_texture
	if tex != null:
		use_tex = _texture_has_visible_alpha(tex)
	if use_tex:
		var prepared := prepare_texture(tex) if enforce_dreamcast_pipeline else tex
		sm.set_shader_parameter("has_albedo_tex", true)
		sm.set_shader_parameter("albedo_tex", prepared)
		sm.set_shader_parameter("base_color", col)
		sm.set_shader_parameter("base_alpha", col.a)
	else:
		sm.set_shader_parameter("has_albedo_tex", false)
		# Placeholders de lago exportados con alfa 0 (p. ej. Finlandia) usan albedo blanco
		# o negro vacío; conservar un tono natural oscuro cuando no hay textura visible.
		if tex != null and (col.is_equal_approx(Color.WHITE) or col.r + col.g + col.b < 0.01):
			sm.set_shader_parameter("base_color", Color(0.07, 0.15, 0.20))
			sm.set_shader_parameter("base_alpha", 0.65)
		else:
			sm.set_shader_parameter("base_color", col)
			sm.set_shader_parameter("base_alpha", col.a)
	static_water_materials[key] = sm
	return sm


func _texture_has_visible_alpha(tex: Texture2D) -> bool:
	var img := tex.get_image()
	if img == null:
		return false
	if img.is_compressed() and img.decompress() != OK:
		return false
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return false
	var step_x := maxi(w / 8, 1)
	var step_y := maxi(h / 8, 1)
	for y in range(0, h, step_y):
		for x in range(0, w, step_x):
			if img.get_pixel(x, y).a > 0.15:
				return true
	return false


func adjust_material(material: BaseMaterial3D) -> void:
	var key := material.get_instance_id()
	if adjusted_materials.has(key):
		adjusted_surface_count += 1
		return
	adjusted_materials[key] = true

	var material_name := material.resource_name.to_lower()
	# These original Kenya river textures use continuous alpha, even though the
	# imported GLB marks them as cutouts. Keep their original mesh boundaries.
	var is_river_water := material_name == "river1_1" or material_name == "river2_1"
	var is_cutout := not is_river_water and (CUTOUT_MATERIAL_NAMES.has(material_name) or material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)

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
		# Asegurar texture_repeat activo para que las texturas que se repiten (bosque, carretera) no se estiren.
		# Respetar CLAMP_TO_EDGE del .glb (gltf_postprocessor): si el material ya
		# viene con REPEAT desactivado (checkpoint, gate_finish, banners, árboles
		# individuales, público), no sobrescribirlo para no crear wrapping.
		var is_banner := false
		for prefix in BANNER_MATERIAL_PREFIXES:
			if material_name == prefix or material_name.begins_with(prefix):
				is_banner = true
				break
		if material.get_flag(BaseMaterial3D.FLAG_USE_TEXTURE_REPEAT):
			if is_cutout or not is_banner:
				material.set_flag(BaseMaterial3D.FLAG_USE_TEXTURE_REPEAT, true)
		# Si ya viene en false (CLAMP_TO_EDGE), se deja en false.

	if is_river_water:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.disable_receive_shadows = true
	elif is_cutout:
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
		prepared_textures[key] = texture
		return texture
	if pixels.is_compressed() and pixels.decompress() != OK:
		prepared_textures[key] = texture
		return texture
	if pixels.generate_mipmaps() != OK:
		prepared_textures[key] = texture
		return texture
	var prepared := ImageTexture.create_from_image(pixels)
	prepared_textures[key] = prepared
	return prepared
