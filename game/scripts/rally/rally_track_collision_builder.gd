class_name RallyTrackCollisionBuilder
extends Node3D

@export var collision_scene_path: String = "res://assets/rally/russia_stage1/russia_stage1_collision.glb"
@export var terrain_surface_group: String = "Gravel"
@export var collision_layer: int = 1
@export var body_friction: float = 0.9
@export var procedural_ss04_asphalt_mode: bool = false

# Material-aware road classification. The stage's terrain_surface_group
# is used only when the imported mesh has no identifiable road material.
# Physical snow and ice overlays will be implemented separately.
const SURFACE_GROUP_BY_NODE := {
	# NOTE: in this rally blend `road_*` materials are the gravel stage road
	# (road_gravel_*), so the rally's main "road" is Gravel, not paved. Map
	# it to Gravel. The "Road" -> surf_road (asphalt) rule stays available in
	# the audio policy for genuinely paved tracks only.
	"collision_terrain_grass": "Grass",
	"collision_terrain_dirt": "Dirt",
	"collision_terrain_dirt_raura_exterior": "Dirt",
	"collision_terrain_sand": "Sand",
}
const WOOD_IMPACT_MATERIALS := [
	"fence_1_1", "fence_1_2", "fence_gate_1", "fin_fence_1_1", "fin_fence_1_2",
	"fin_puuaita", "village_fence", "woodpile", "sign_wooden1",
]

# River lid removal: the imported Kenya collision closes the river channel
# with a flat cap at water level, so the channel has no bed to flood and the
# dynamic water only appears in the fords. The cap is detected against the
# imported water ribbon (visual) and dropped from the terrain bodies.
const RIVER_DATA_PATH := "res://data/rally/kenya_rivers.json"
const LID_CELL_M := 0.5
const LID_FLAT_SPAN_M := 0.25
# Tolerancia del nivel del agua para el triángulo semilla de la tapa.
const LID_LEVEL_TOL_M := 0.12
# Tolerancia ampliada para los triángulos que se enganchan a la hoja de la
# tapa (la tapa exportada no siempre está al mismo nivel que la lámina
# importada: en Kenia 2 hay tramos 145 mm más arriba).
const LID_LEVEL_TOL_WIDE_M := 0.35

var generated_body_count: int = 0
var generated_triangle_count: int = 0
var generated_shape_count: int = 0
var minimum_collision_height_m: float = INF
# Nivel del agua importada por celda (XZ) y celdas con agua, para detectar la
# tapa plana que cierra el cauce del río en la colisión.
var _water_levels: Dictionary = {}
# Triángulos de tapa que se retiran, por "instance_id:surface".
var _lid_triangles: Dictionary = {}
var _lid_removed_triangles: int = 0


func build_collision(visual_root: Node = null) -> bool:
	if not ResourceLoader.exists(collision_scene_path):
		push_error("Rally collision scene is unavailable: " + collision_scene_path)
		return false
	var packed := load(collision_scene_path) as PackedScene
	if packed == null:
		push_error("Rally collision scene cannot be loaded: " + collision_scene_path)
		return false
	_collect_water_levels(visual_root)
	var collision_source := packed.instantiate()
	_mark_river_lids(collision_source)
	# No añadir collision_source al SceneTree: evita subir 114k triángulos al RenderingServer
	var mesh_instances: Array[MeshInstance3D] = []
	collect_mesh_instances(collision_source, mesh_instances)
	if mesh_instances.is_empty():
		push_error("Rally collision scene contains no meshes: " + collision_scene_path)
		collision_source.free()
		return false
	for mesh_instance in mesh_instances:
		var rel_transform := _get_relative_transform(mesh_instance, collision_source)
		# Split mixed imported terrain primitives so winter and bare faces do
		# not inherit one classification from the parent collision node.
		var node_name := mesh_instance.name.to_lower()
		var split_surfaces := node_name.begins_with("collision_road") or (
			collision_scene_path.contains("/sweden_") and node_name.begins_with("collision_terrain_")
		)
		if split_surfaces and mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 1:
			for si in mesh_instance.mesh.get_surface_count():
				var subset := ArrayMesh.new()
				subset.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_instance.mesh.surface_get_arrays(si))
				subset.surface_set_material(0, mesh_instance.mesh.surface_get_material(si))
				var part := MeshInstance3D.new()
				part.name = mesh_instance.name
				part.mesh = subset
				build_static_body(part, rel_transform)
				part.free()
		elif "terrain" in node_name or "road" in node_name or not _build_mixed_wood_collision(mesh_instance, rel_transform):
			build_static_body(mesh_instance, rel_transform)
	if visual_root != null:
		build_erosion_bank_collision(visual_root)
	collision_source.free()
	print("RALLY_COLLISION_READY bodies=", generated_body_count, " shapes=", generated_shape_count, " triangles=", generated_triangle_count)
	return generated_shape_count > 0


func _is_wood_impact_material(material: Material) -> bool:
	if material == null:
		return false
	var label := material.resource_name.to_lower()
	return label in WOOD_IMPACT_MATERIALS or label.begins_with("wood_")


func _build_mixed_wood_collision(source: MeshInstance3D, relative: Transform3D) -> bool:
	var mesh := source.mesh
	if mesh == null or mesh.get_surface_count() < 2:
		return false
	var wood: Array[int] = []
	var other: Array[int] = []
	for i in mesh.get_surface_count():
		if _is_wood_impact_material(mesh.surface_get_material(i)):
			wood.append(i)
		else:
			other.append(i)
	if wood.is_empty() or other.is_empty():
		return false
	# A collision mesh can contain wood fences, metal barriers and rock in the
	# same node. Keep a separate body for just the wood faces.
	for surfaces: Array[int] in [other, wood]:
		var subset := ArrayMesh.new()
		for i in surfaces:
			subset.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(i))
			subset.surface_set_material(subset.get_surface_count() - 1, mesh.surface_get_material(i))
		var part := MeshInstance3D.new()
		part.name = source.name
		part.mesh = subset
		build_static_body(part, relative)
		part.free()
	return true


## Nivel del agua importada por celda (XZ).
## Recorre la escena visual y rasteriza las láminas de agua (river1_1,
## river2_1) en una rejilla: cada celda guarda el nivel medio del agua.
## Sirve para reconocer la tapa plana que cierra el cauce en la colisión.
func _collect_water_levels(visual_root: Node) -> void:
	_water_levels.clear()
	if visual_root == null:
		return
	if not FileAccess.file_exists(RIVER_DATA_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RIVER_DATA_PATH))
	if not (parsed is Dictionary):
		return
	var policy: Dictionary = (parsed as Dictionary).get("surface_policy", {})
	var wanted := {}
	for name in (policy.get("dynamic_surfaces", []) as Array):
		wanted[str(name).to_lower()] = true
	if wanted.is_empty():
		return
	var meshes: Array[MeshInstance3D] = []
	collect_mesh_instances(visual_root, meshes)
	for source in meshes:
		if source.mesh == null:
			continue
		var gt := source.global_transform
		for surface_index in source.mesh.get_surface_count():
			var material := source.mesh.surface_get_material(surface_index)
			if material == null or not (material is BaseMaterial3D):
				continue
			if not wanted.has(str((material as BaseMaterial3D).resource_name).to_lower()):
				continue
			var arrays := source.mesh.surface_get_arrays(surface_index)
			if arrays == null or arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var tri_count := (idx.size() / 3) if not idx.is_empty() else (verts.size() / 3)
			for t in tri_count:
				var a := Vector3.ZERO
				var b := Vector3.ZERO
				var c := Vector3.ZERO
				if idx.is_empty():
					a = gt * verts[t * 3]
					b = gt * verts[t * 3 + 1]
					c = gt * verts[t * 3 + 2]
				else:
					a = gt * verts[idx[t * 3]]
					b = gt * verts[idx[t * 3 + 1]]
					c = gt * verts[idx[t * 3 + 2]]
				var cen := (a + b + c) / 3.0
				var key := Vector2i(floori(cen.x / LID_CELL_M), floori(cen.z / LID_CELL_M))
				var level := (a.y + b.y + c.y) / 3.0
				if _water_levels.has(key):
					var prev: float = float(_water_levels[key])
					_water_levels[key] = (prev + level) * 0.5
				else:
					_water_levels[key] = level


## Nivel del agua importada en (x, z) buscando en el vecindario (celdas de
## 0.5 m). INF si no hay agua importada cerca.
func _water_level_at(x: float, z: float) -> float:
	if _water_levels.is_empty():
		return INF
	var cx := floori(x / LID_CELL_M)
	var cz := floori(z / LID_CELL_M)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var key := Vector2i(cx + dx, cz + dz)
			if _water_levels.has(key):
				return float(_water_levels[key])
	return INF


## ¿Hay agua importada cerca de (x, z)?
func _has_water_near(x: float, z: float) -> bool:
	return is_finite(_water_level_at(x, z))


## ¿Es este triángulo la tapa plana que cierra el cauce del río?
##
## Condiciones: está sobre el agua importada, es plano y está al nivel del
## agua. El valle real (paredes y fondo) no es plano y se conserva.
func _is_river_lid(a: Vector3, b: Vector3, c: Vector3) -> bool:
	if _water_levels.is_empty():
		return false
	var cen := (a + b + c) / 3.0
	if not _has_water_near(cen.x, cen.z):
		return false
	var level := _water_level_at(cen.x, cen.z)
	if not is_finite(level):
		return false
	var span := maxf(maxf(a.y, b.y), c.y) - minf(minf(a.y, b.y), c.y)
	if span > LID_FLAT_SPAN_M:
		return false
	return absf(cen.y - level) <= LID_LEVEL_TOL_M


## Marca las tapas del cauce como una HOJA CONECTADA.
##
## La tapa exportada es una lámina continua al nivel del agua que cubre el
## valle. Si solo se retiran los triángulos que coinciden con el nivel, se
## quedan fragmentos sueltos (en Kenia 2, un bloque de 145 mm más arriba
## que el agua) que forman un muro en mitad del cauce e impiden cruzarlo.
## Por eso, desde los triángulos semilla se extiende la retirada a los
## vecinos que también son planos y están cerca del nivel del agua: se
## retira la hoja entera y el valle queda limpio.
func _mark_river_lids(node: Node) -> void:
	_lid_triangles.clear()
	if _water_levels.is_empty():
		return
	var meshes: Array[MeshInstance3D] = []
	collect_mesh_instances(node, meshes)
	for source in meshes:
		if source.mesh == null:
			continue
		var source_name := str(source.name).to_lower()
		if "terrain" not in source_name or "road" in source_name:
			continue
		# La malla de colisión no está en el árbol: se usa la transform
		# relativa al nodo raíz de la escena de colisión.
		var gt := _get_relative_transform(source, node)
		for surface_index in source.mesh.get_surface_count():
			var arrays := source.mesh.surface_get_arrays(surface_index)
			if arrays == null or arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var tri_count := (idx.size() / 3) if not idx.is_empty() else (verts.size() / 3)
			var centroids: Array = []
			var spans: Array = []
			var levels: Array = []
			var tri_vertices: Array = []
			var adjacency: Dictionary = {}
			for t in tri_count:
				var a := Vector3.ZERO
				var b := Vector3.ZERO
				var c := Vector3.ZERO
				var vi := [0, 0, 0]
				if idx.is_empty():
					a = gt * verts[t * 3]
					b = gt * verts[t * 3 + 1]
					c = gt * verts[t * 3 + 2]
					vi = [t * 3, t * 3 + 1, t * 3 + 2]
				else:
					vi = [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]]
					a = gt * verts[vi[0]]
					b = gt * verts[vi[1]]
					c = gt * verts[vi[2]]
				var cen := (a + b + c) / 3.0
				var span := maxf(maxf(a.y, b.y), c.y) - minf(minf(a.y, b.y), c.y)
				centroids.append(cen)
				spans.append(span)
				levels.append(_water_level_at(cen.x, cen.z))
				tri_vertices.append(vi)
				for v in vi:
					if not adjacency.has(v):
						adjacency[v] = []
					(adjacency[v] as Array).append(t)
			# Semillas: planos y al nivel del agua.
			var removed := {}
			var queue: Array = []
			for t in tri_count:
				var level: float = levels[t]
				if not is_finite(level):
					continue
				if float(spans[t]) > LID_FLAT_SPAN_M:
					continue
				if absf((centroids[t] as Vector3).y - level) > LID_LEVEL_TOL_M:
					continue
				removed[t] = true
				queue.append(t)
			# Extensión a los vecinos de la hoja (tolerancia ampliada).
			var head := 0
			while head < queue.size():
				var t2: int = queue[head]
				head += 1
				var cen2: Vector3 = centroids[t2]
				var level2: float = levels[t2]
				if not is_finite(level2):
					continue
				for v in (tri_vertices[t2] as Array):
					for nb in (adjacency.get(v, []) as Array):
						var t3: int = nb
						if removed.has(t3):
							continue
						if float(spans[t3]) > LID_FLAT_SPAN_M:
							continue
						var level3: float = levels[t3]
						if not is_finite(level3):
							continue
						if absf((centroids[t3] as Vector3).y - level3) > LID_LEVEL_TOL_WIDE_M:
							continue
						removed[t3] = true
						queue.append(t3)
			if removed.is_empty():
				continue
			var list: Array = removed.keys()
			list.sort()
			_lid_triangles["%d:%d" % [source.get_instance_id(), surface_index]] = list
			_lid_removed_triangles += list.size()


func _triangle_vertices(vi: Array, idx: PackedInt32Array, t: int) -> Array:
	if idx.is_empty():
		return [t * 3, t * 3 + 1, t * 3 + 2]
	return [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]]



## Construcción del cuerpo estático del terreno descartando la tapa del río.
func _build_terrain_shape_without_lid(mesh_instance: MeshInstance3D, transform: Transform3D) -> ConcavePolygonShape3D:
	var faces := PackedVector3Array()
	for surface_index in mesh_instance.mesh.get_surface_count():
		var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
		if arrays == null or arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var tri_count := (idx.size() / 3) if not idx.is_empty() else (verts.size() / 3)
		var surface_key := "%d:%d" % [mesh_instance.get_instance_id(), surface_index]
		var surface_drop: Dictionary = {}
		for t in (_lid_triangles.get(surface_key, []) as Array):
			surface_drop[int(t)] = true
		for t in tri_count:
			if surface_drop.has(t):
				continue
			var a := Vector3.ZERO
			var b := Vector3.ZERO
			var c := Vector3.ZERO
			if idx.is_empty():
				a = verts[t * 3]
				b = verts[t * 3 + 1]
				c = verts[t * 3 + 2]
			else:
				a = verts[idx[t * 3]]
				b = verts[idx[t * 3 + 1]]
				c = verts[idx[t * 3 + 2]]
			faces.append(transform * a)
			faces.append(transform * b)
			faces.append(transform * c)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape


func get_removed_lid_triangle_count() -> int:
	return _lid_removed_triangles


func build_erosion_bank_collision(visual_root: Node) -> void:
	# The exported collision GLB excludes sand_erosion_* (and equivalents in
	# the new countries) even though these surfaces form raised roadside banks
	# rather than flat decorative decals. Without this pass the car would fall
	# through the visual ground when leaving the road by half a metre in
	# Kenya/Finland/Sweden/Switzerland.
	var meshes: Array[MeshInstance3D] = []
	collect_mesh_instances(visual_root, meshes)
	for source in meshes:
		if source.mesh == null:
			continue
		for surface_index in source.mesh.get_surface_count():
			var material := source.mesh.surface_get_material(surface_index)
			if material == null:
				continue
			var mat_name := str(material.resource_name).to_lower()
			var bank_node := _erosion_bank_collision_node(mat_name)
			if bank_node.is_empty():
				continue
			var bank_mesh := ArrayMesh.new()
			bank_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.mesh.surface_get_arrays(surface_index))
			# Preserve original erosion_snow_* material on generated banks.
			bank_mesh.surface_set_material(0, material)
			var bank := MeshInstance3D.new()
			bank.name = bank_node
			bank.mesh = bank_mesh
			build_static_body(bank, source.global_transform)
			bank.free()


## Maps an erosion/edge bank material to its static collision node.
## Returns "" when the material is not a bank (no runtime collision needed).
## sand_erosion_ stays on Collision_Terrain_Dirt (legacy behavior pinned by
## stage_export_import_test: russia Dirt == 11695 + 582 bank triangles).
## kenya_erosio_/fin_field1_edge -> Dirt, erosion_snow_ -> Grass (snow),
## rock_edge_/kenya_rock_edge_ -> Collision_Road (Gravel surface group).
func _erosion_bank_collision_node(mat_name: String) -> String:
	var m := mat_name.to_lower()
	if m.begins_with("sand_erosion_"):
		return "Collision_Terrain_Dirt"
	if m.begins_with("kenya_erosio_") or m == "fin_field1_edge":
		return "Collision_Terrain_Dirt"
	if m.begins_with("erosion_snow_"):
		return "Collision_Terrain_Grass"
	if m.begins_with("rock_edge_") or m.begins_with("kenya_rock_edge_"):
		return "Collision_Road"
	return ""


func collect_mesh_instances(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		collect_mesh_instances(child, output)


func _get_relative_transform(node: Node3D, root_node: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var current: Node = node
	var chain: Array[Node3D] = []
	while current != null and current != root_node:
		if current is Node3D:
			chain.append(current as Node3D)
		current = current.get_parent()
	for i in range(chain.size() - 1, -1, -1):
		t = t * chain[i].transform
	return t


func build_static_body(mesh_instance: MeshInstance3D, override_transform: Transform3D = Transform3D()) -> void:
	if mesh_instance.mesh == null:
		return
	var shape_transform := override_transform if override_transform != Transform3D() else mesh_instance.transform
	var source_name_lid := str(mesh_instance.name).to_lower()
	# La tapa del río solo se retira del terreno: la calzada mantiene su
	# superficie (el vado) y las barreras no se tocan.
	var drop_lid := (
		not _lid_triangles.is_empty()
		and "terrain" in source_name_lid
		and "road" not in source_name_lid
	)
	var shape: Shape3D = null
	if drop_lid:
		shape = _build_terrain_shape_without_lid(mesh_instance, shape_transform)
	else:
		shape = mesh_instance.mesh.create_trimesh_shape()
	if shape == null:
		return
	var static_body := StaticBody3D.new()
	static_body.name = "TrackCollision_" + mesh_instance.name
	static_body.collision_layer = collision_layer
	static_body.collision_mask = 0
	var source_name := str(mesh_instance.name).to_lower()
	var role := "terrain" if ("terrain" in source_name or "road" in source_name) else ("barrier" if "barrier" in source_name else "obstacle")
	# Terrain banks are thin meshes: keep chassis contacts from their reverse side too.
	# Kenya trunks include thin/open surfaces: contacts must work from either
	# side, just like the stage barriers, rather than depend on face winding.
	if (role in ["terrain", "barrier"] or source_name.begins_with("collision_tree_trunks")) and shape is ConcavePolygonShape3D:
		(shape as ConcavePolygonShape3D).backface_collision = true
	static_body.set_meta("collision_role", role)
	static_body.set_meta("is_stage_road", source_name.begins_with("collision_road"))
	if role != "terrain" and _is_wood_impact_material(mesh_instance.mesh.surface_get_material(0)):
		static_body.set_meta("wood_impact", true)
	var surface_group := str(SURFACE_GROUP_BY_NODE.get(source_name, ""))
	var winter_layer_id := ""
	var material_names: Array[String] = []
	for si in mesh_instance.mesh.get_surface_count():
		var mat := mesh_instance.mesh.surface_get_material(si)
		if mat != null:
			var mat_name := str(mat.resource_name).to_lower()
			if not mat_name.is_empty():
				material_names.append(mat_name)
	# Snow is an overlay, never a wholesale remapping of the body.
	# Driven road snow (including rail crossings and snow bridges) is packed;
	# off-track snow (mantles, banks, ditches and the snow-textured roadside
	# strip, the only non-snow-named terrain in Sweden) is deep; snow-covered
	# rocks keep their loose tag.
	var snow_deep := false
	for mat_name in material_names:
		if procedural_ss04_asphalt_mode and mat_name.begins_with("road_snow_cdi"):
			continue
		if mat_name.begins_with("road_snow_") or mat_name == "road_snow" \
		or mat_name.begins_with("railroad_snow") or mat_name.begins_with("bridge_snow"):
			winter_layer_id = "snow_packed"
		elif mat_name.begins_with("erosion_snow_") or mat_name.begins_with("terrain_snow_") \
		or mat_name.begins_with("ditch_snow_") or mat_name == "terrain_road_side":
			winter_layer_id = "snow_deep"
			snow_deep = true
		elif mat_name.begins_with("rock_snow") or mat_name.begins_with("stone_snow"):
			winter_layer_id = "snow_loose"
		elif mat_name.begins_with("road_ice_") or mat_name == "road_ice":
			winter_layer_id = "ice"
	# Legacy safety net, kept loud: the regenerated Sweden GLBs carry real
	# materials, so this branch must stay silent. If a material-less Sweden
	# road body ever arrives again, tag it as before but warn instead of
	# silently assuming packed snow.
	if (
		winter_layer_id.is_empty()
		and material_names.is_empty()
		and collision_scene_path.contains("/sweden_")
		and source_name.begins_with("collision_road")
	):
		winter_layer_id = "snow_packed"
		push_warning("RallyTrackCollisionBuilder: material-less Sweden road body, tagging snow_packed as fallback")
	if source_name.begins_with("collision_road"):
		for mat_name in material_names:
			if procedural_ss04_asphalt_mode and mat_name.begins_with("road_snow_cdi"):
				surface_group = "Road"
				break
			if mat_name.begins_with("road_snow_") or mat_name == "road_snow" \
			or mat_name.begins_with("railroad_snow") or mat_name.begins_with("bridge_snow"):
				surface_group = "Gravel"
				break
			if "tarmac" in mat_name or "asphalt" in mat_name or "tunnel" in mat_name or "bridgeroad" in mat_name:
				surface_group = "Road"
				break
			if "sand" in mat_name:
				surface_group = "Sand"
				break
			if "dirt" in mat_name or "field" in mat_name or "leaves" in mat_name:
				surface_group = "Dirt"
				break
		if surface_group.is_empty():
			surface_group = terrain_surface_group
	if role == "terrain" and surface_group.is_empty():
		surface_group = terrain_surface_group
	# Deep off-track snow keeps its own contact identity (SnowDeep group);
	# the original physical group is preserved only as metadata.
	# The global Grass mapping and the GLB geometry are untouched.
	# Sin hardcode por país: la superficie la deciden los materiales
	# (tarmac/asphalt/tunnel/bridgeroad → Road, dirt/field/leaves → Dirt,
	# sand → Sand) con fallback a terrain_surface_group (Suiza: Road por
	# stage surface=asphalt, Finlandia/Rusia: Gravel).
	var original_group := surface_group
	if snow_deep:
		surface_group = "SnowDeep"
	static_body.set_meta("base_surface_id", original_group)
	static_body.set_meta("winter_layer_id", winter_layer_id)
	if not material_names.is_empty():
		static_body.set_meta("source_material", material_names[0])
	if source_name.begins_with("collision_road") and material_names.has("kenya_bridge"):
		static_body.set_meta("audio_surface", "wood_bridge")
	if not surface_group.is_empty():
		static_body.add_to_group(surface_group)
	if source_name == "collision_terrain_dirt_raura_exterior":
		static_body.add_to_group("RauraGrassGround")
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = body_friction
	physics_material.bounce = 0.0
	static_body.physics_material_override = physics_material
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "TrackCollisionShape"
	collision_shape.shape = shape
	collision_shape.transform = shape_transform
	static_body.add_child(collision_shape)
	add_child(static_body)
	var world_bounds := collision_shape.global_transform * mesh_instance.mesh.get_aabb()
	minimum_collision_height_m = minf(minimum_collision_height_m, world_bounds.position.y)
	generated_body_count += 1
	generated_shape_count += 1
	if shape is ConcavePolygonShape3D:
		generated_triangle_count += int((shape as ConcavePolygonShape3D).get_faces().size() / 3)
	else:
		generated_triangle_count += int(mesh_instance.mesh.get_faces().size() / 3)


func get_generated_triangle_count() -> int:
	return generated_triangle_count


func clear_collision() -> void:
	for child in get_children():
		# This builder owns all its children. Godot may rename duplicate body
		# names to @StaticBody3D@..., so a name prefix misses old collisions.
		child.queue_free()
	generated_body_count = 0
	generated_shape_count = 0
	generated_triangle_count = 0
	minimum_collision_height_m = INF
