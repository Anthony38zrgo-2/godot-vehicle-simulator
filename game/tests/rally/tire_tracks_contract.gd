extends SceneTree

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var tracks = load("res://scripts/rally/rally_tire_tracks.gd").new()
	root.add_child(tracks)
	assert(tracks.variant_for("asphalt", 0.0, 0) == 0)
	assert(tracks.variant_for("asphalt", 0.0, 1) == 1)
	assert(tracks.variant_for("dirt", 1.0, 0) == 2)
	assert(tracks.variant_for("ice", 0.0, 0) == 4)
	assert(tracks.variant_for("gravel", 0.0, 0) == 5)
	assert(tracks.variant_for("unknown", 0.0, 0) == 5)
	assert(tracks.variant_for("wood_bridge", 0.0, 0) == 5)
	var asphalt_rolling: float = tracks.opacity_for("asphalt", 0, Vector2.ZERO)
	assert(asphalt_rolling == 0.0)
	assert(tracks.opacity_for("asphalt", 0, Vector2(0.15, 0.12)) == 0.0, "Normal braking/cornering on asphalt must not skidmark")
	assert(tracks.opacity_for("asphalt", 0, Vector2(-0.38, 0.0), 5.0) > 0.45, "Hard braking/lockup on asphalt must leave a strong dark mark")
	assert(tracks.opacity_for("asphalt", 0, Vector2(0.85, 0.0), 0.3) == 0.0, "Near-stopped slip speed must stay gated")
	assert(asphalt_rolling < tracks.opacity_for("asphalt", 0, Vector2(-0.85, 0.0)) * 0.1)
	assert(asphalt_rolling < tracks.opacity_for("asphalt", 0, Vector2(0.85, 0.0)) * 0.1)
	assert(tracks.opacity_for("unknown", 5, Vector2.ZERO) > asphalt_rolling)
	assert(tracks.opacity_for("unknown", 5, Vector2.ZERO) < tracks.opacity_for("gravel", 5, Vector2.ZERO))
	assert(tracks.opacity_for("dirt", 2, Vector2.ZERO) > tracks.opacity_for("dirt", 5, Vector2.ZERO))
	assert(is_equal_approx(tracks.opacity_for("gravel", 5, Vector2(0.18, 0.15)), tracks.opacity_for("gravel", 5, Vector2.ZERO)), "Normal gravel slip must stay at subtle rolling opacity")
	var slope := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.64, 0.20, 2.0)
	collision.shape = shape
	slope.rotation.z = 0.22
	slope.add_child(collision)
	root.add_child(slope)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0.0, 1.0, 1.5)
	camera.look_at(Vector3.ZERO)
	camera.make_current()

	# Allow the collision shape to be registered before querying it.
	await physics_frame
	await physics_frame
	var contact := {
		"collider": slope,
		"position": Vector3(0.0, 0.10, 0.0),
		"normal": Vector3.UP.rotated(Vector3.BACK, 0.22),
		"tread_axis": slope.global_basis.x,
	}
	var excluded: Array[RID] = []
	tracks.add_contact(0, contact, 0.22, 5, 0.8, "gravel", Vector2.ZERO, 1, excluded)
	assert(tracks.segments.is_empty())
	contact.position.z = -0.30
	tracks.add_contact(0, contact, 0.22, 5, 0.8, "gravel", Vector2.ZERO, 1, excluded)
	assert(tracks.segments.size() == 2)
	tracks.flush_ribbons()
	var mesh: ArrayMesh = tracks.ribbons[0].mesh
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert(vertices[2].y - vertices[0].y > 0.04, "Across-tread vertices must follow the slope")
	assert(vertices[3].is_equal_approx(vertices[6]), "Adjacent segments must share their projected row")
	assert(is_equal_approx(uv[3].y, uv[6].y), "Tread phase must continue across segments")
	assert(is_equal_approx(uv[9].y, 0.30 / tracks.TREAD_REPEAT))

	contact.position.z = -0.50
	tracks.add_contact(0, contact, 0.22, 5, 0.8, "mud", Vector2.ZERO, 1, excluded)
	assert(tracks.segments.size() == 2, "A surface change must cut the trail")
	contact.position = Vector3(0.28, 0.16, -0.52)
	tracks.add_contact(0, contact, 0.22, 5, 0.8, "mud", Vector2.ZERO, 1, excluded)
	assert(tracks.previous[0].is_empty(), "A tread edge outside the receiver must cut the trail")
	contact.position = Vector3(0.0, 0.10, -0.6)
	tracks.add_contact(0, contact, 0.22, 5, 0.8, "mud", Vector2.ZERO, 1, excluded)
	contact.position.z = -4.0
	var before_jump: int = tracks.segments.size()
	tracks.add_contact(0, contact, 0.22, 5, 0.8, "mud", Vector2.ZERO, 1, excluded)
	assert(tracks.segments.size() == before_jump and tracks.previous[0].is_empty())

	await process_frame
	await process_frame
	tracks.clear_tracks()
	contact.position = Vector3(0.0, 0.10, 0.0)
	tracks.add_contact(0, contact, 0.22, 0, 0.0, "asphalt", Vector2.ZERO, 1, excluded)
	contact.position.z = -0.30
	tracks.add_contact(0, contact, 0.22, 0, 0.0, "asphalt", Vector2.ZERO, 1, excluded)
	assert(tracks.segments.is_empty() and not tracks.previous[0].is_empty(),
		"Rolling on asphalt must keep continuity without emitting dark segments")
	contact.position.z = -0.60
	var lock_strength: float = tracks.opacity_for("asphalt", 0, Vector2(-0.85, 0.0), 8.0)
	tracks.add_contact(0, contact, 0.22, 0, lock_strength, "asphalt", Vector2(-0.85, 0.0), 1, excluded)
	assert(tracks.segments.size() == 2, "Real lockup on asphalt must emit segments")

	# Verify Phases 1, 2 & 3 on continuous stage terrain: 0 raycasts + collinear merge
	tracks.clear_tracks()
	slope.set_meta("collision_role", "terrain")
	var rays_before: int = tracks.raycast_count
	var analytic_before: int = tracks.analytic_count
	contact.position = Vector3(0.0, 0.10, 0.0)
	tracks.add_contact(0, contact, 0.22, 0, lock_strength, "asphalt", Vector2(-0.85, 0.0), 1, excluded)
	for step_i in range(1, 4):
		contact.position = Vector3(0.0, 0.10, -0.18 * step_i)
		tracks.add_contact(0, contact, 0.22, 0, lock_strength, "asphalt", Vector2(-0.85, 0.0), 1, excluded)
	assert(tracks.raycast_count == rays_before and tracks.analytic_count > analytic_before,
		"Phase 1: Continuous terrain must use analytic projection with 0 raycasts")
	assert(tracks.merged_count >= 2 and tracks.segments.size() == 1,
		"Phase 3: Collinear 18cm steps on terrain must merge in-place into 1 segment")
	tracks.flush_ribbons()
	assert(tracks.ribbons[0].mesh == tracks._ribbon_meshes[0] and tracks.ribbons[0].mesh.get_surface_count() == 1,
		"Phase 2: Block ArrayMesh must be updated in-place from pre-allocated block arrays")

	tracks.clear_tracks()
	assert(tracks.ribbons[0].mesh == null and tracks.segments.is_empty())
	print("TIRE_TRACKS_CONTRACT_OK")
	quit()
