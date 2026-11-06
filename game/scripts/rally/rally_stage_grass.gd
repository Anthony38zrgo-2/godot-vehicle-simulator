extends Node3D
## Builds sparse, deterministic decoration once per stage.
const VARIANTS: Array[PackedScene] = [
	preload("res://assets/rally/grass/short_fresh.glb"),
	preload("res://assets/rally/grass/short_aged.glb"),
	preload("res://assets/rally/grass/tall.glb"),
]
const SECTOR_LENGTH := 96.0
const TERRAIN_CLEARANCE := 0.02

func build(route: Array[Vector3], stage_seed: int, collision_mask: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = stage_seed
	var space := get_world_3d().direct_space_state
	var buckets: Dictionary = {}
	for side in [-1.0, 1.0]:
		var distance := 0.0
		var next_patch := rng.randf_range(8.0, 16.0)
		for i in range(1, route.size()):
			var start := route[i - 1]
			var delta := route[i] - start
			var length := delta.length()
			var lateral := Vector3.UP.cross(delta).normalized() * float(side)
			if length < 0.01 or lateral.is_zero_approx():
				continue
			while next_patch < distance + length:
				var center := start + delta * ((next_patch - distance) / length)
				center += lateral * rng.randf_range(5.5, 16.0)
				_add_patch(space, collision_mask, center, int(next_patch / SECTOR_LENGTH), rng, buckets)
				next_patch += rng.randf_range(12.0, 27.0)
			distance += length

	var meshes: Array[Mesh] = []
	var materials: Array[StandardMaterial3D] = []
	for variant in VARIANTS:
		var instance := variant.instantiate()
		var visual := instance as MeshInstance3D
		if visual == null:
			visual = instance.find_children("*", "MeshInstance3D", true, false).front() as MeshInstance3D
		meshes.append(visual.mesh)
		var material := visual.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.45
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		materials.append(material)
		instance.free()

	var count := 0
	for key: Vector2i in buckets:
		var transforms: Array[Transform3D] = buckets[key]
		var batch := MultiMeshInstance3D.new()
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = meshes[key.y]
		multimesh.instance_count = transforms.size()
		for i in transforms.size():
			multimesh.set_instance_transform(i, transforms[i])
		batch.material_override = materials[key.y]
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batch.multimesh = multimesh
		add_child(batch)
		count += transforms.size()
	print("RALLY_GRASS_READY instances=", count, " batches=", buckets.size())

func _add_patch(space: PhysicsDirectSpaceState3D, collision_mask: int, center: Vector3, sector: int, rng: RandomNumberGenerator, buckets: Dictionary) -> void:
	for i in rng.randi_range(3, 7):
		var point := center + Vector3(rng.randf_range(-1.25, 1.25), 0, rng.randf_range(-1.25, 1.25))
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 8.0, point - Vector3.UP * 6.0, collision_mask)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var collider := hit.collider as Node
		if collider == null or not collider.is_in_group("Grass") or collider.get_meta("is_stage_road", false):
			continue
		var normal: Vector3 = hit.normal
		if normal.y < 0.72:
			continue
		var variant := 2 if rng.randf() < 0.10 else rng.randi_range(0, 1)
		var scale := rng.randf_range(0.75, 1.25)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale)
		var position: Vector3 = hit.position
		var key := Vector2i(sector, variant)
		if not buckets.has(key):
			var transforms: Array[Transform3D] = []
			buckets[key] = transforms
		buckets[key].append(Transform3D(basis, to_local(position - Vector3.UP * TERRAIN_CLEARANCE)))
