class_name RallyTrackCollisionBuilder
extends Node3D

@export var collision_scene_path: String = "res://assets/rally/russia_stage1/russia_stage1_collision.glb"
@export var terrain_surface_group: String = "Gravel"
@export var collision_layer: int = 1
@export var body_friction: float = 0.9

# Collision node name (lowercase) -> physics surface group. Nodes not in
# this table keep the legacy behavior: "terrain" nodes join
# terrain_surface_group, everything else gets no surface group (the tire
# model then falls back to its default surface).
const SURFACE_GROUP_BY_NODE := {
	# NOTE: in this rally blend `road_*` materials are the gravel stage road
	# (road_gravel_*), so the rally's main "road" is Gravel, not paved. Map
	# it to Gravel. The "Road" -> surf_road (asphalt) rule stays available in
	# the audio policy for genuinely paved tracks only.
	"collision_road": "Gravel",
	"collision_terrain_grass": "Grass",
	"collision_terrain_dirt": "Dirt",
	"collision_terrain_sand": "Sand",
}

var generated_body_count: int = 0
var generated_triangle_count: int = 0
var generated_shape_count: int = 0


func build_collision() -> bool:
	if not ResourceLoader.exists(collision_scene_path):
		push_error("Rally collision scene is unavailable: " + collision_scene_path)
		return false
	var packed := load(collision_scene_path) as PackedScene
	if packed == null:
		push_error("Rally collision scene cannot be loaded: " + collision_scene_path)
		return false
	var collision_source := packed.instantiate()
	add_child(collision_source)
	await get_tree().process_frame
	var mesh_instances: Array[MeshInstance3D] = []
	collect_mesh_instances(collision_source, mesh_instances)
	if mesh_instances.is_empty():
		push_error("Rally collision scene contains no meshes: " + collision_scene_path)
		return false
	for mesh_instance in mesh_instances:
		build_static_body(mesh_instance)
	collision_source.queue_free()
	await get_tree().process_frame
	print("RALLY_COLLISION_READY bodies=", generated_body_count, " shapes=", generated_shape_count, " triangles=", generated_triangle_count)
	return generated_shape_count > 0


func collect_mesh_instances(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		collect_mesh_instances(child, output)


func build_static_body(mesh_instance: MeshInstance3D) -> void:
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
	static_body.set_meta("collision_role", role)
	var surface_group := str(SURFACE_GROUP_BY_NODE.get(source_name, ""))
	if role == "terrain" and surface_group.is_empty():
		surface_group = terrain_surface_group
	if not surface_group.is_empty():
		static_body.add_to_group(surface_group)
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = body_friction
	physics_material.bounce = 0.0
	static_body.physics_material_override = physics_material
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "TrackCollisionShape"
	collision_shape.shape = shape
	collision_shape.transform = mesh_instance.global_transform
	static_body.add_child(collision_shape)
	add_child(static_body)
	generated_body_count += 1
	generated_shape_count += 1
	generated_triangle_count += int(mesh_instance.mesh.get_faces().size() / 3)


func get_generated_triangle_count() -> int:
	return generated_triangle_count
