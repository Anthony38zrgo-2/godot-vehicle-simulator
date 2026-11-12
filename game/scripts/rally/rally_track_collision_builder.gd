class_name RallyTrackCollisionBuilder
extends Node3D

@export var collision_scene_path: String = "res://assets/rally/russia_stage1/russia_stage1_collision.glb"
@export var terrain_surface_group: String = "Gravel"
@export var collision_layer: int = 1
@export var body_friction: float = 0.9

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

var generated_body_count: int = 0
var generated_triangle_count: int = 0
var generated_shape_count: int = 0
var minimum_collision_height_m: float = INF


func build_collision(visual_root: Node = null) -> bool:
	if not ResourceLoader.exists(collision_scene_path):
		push_error("Rally collision scene is unavailable: " + collision_scene_path)
		return false
	var packed := load(collision_scene_path) as PackedScene
	if packed == null:
		push_error("Rally collision scene cannot be loaded: " + collision_scene_path)
		return false
	var collision_source := packed.instantiate()
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
		else:
			build_static_body(mesh_instance, rel_transform)
	if visual_root != null:
		build_erosion_bank_collision(visual_root)
	collision_source.free()
	print("RALLY_COLLISION_READY bodies=", generated_body_count, " shapes=", generated_shape_count, " triangles=", generated_triangle_count)
	return generated_shape_count > 0


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
	var shape := mesh_instance.mesh.create_trimesh_shape()
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
	# Switzerland: all main road collision meshes are asphalt.
	# Preserve off-track terrain classifications.
	if (
		collision_scene_path.contains("/switzerland_")
		and source_name.begins_with("collision_road")
	):
		surface_group = "Road"
	var original_group := surface_group
	if snow_deep:
		surface_group = "SnowDeep"
	static_body.set_meta("base_surface_id", original_group)
	static_body.set_meta("winter_layer_id", winter_layer_id)
	if not material_names.is_empty():
		static_body.set_meta("source_material", material_names[0])
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
	collision_shape.transform = override_transform if override_transform != Transform3D() else mesh_instance.transform
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
