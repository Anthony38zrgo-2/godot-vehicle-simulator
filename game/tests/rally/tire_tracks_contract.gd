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
	assert(asphalt_rolling < tracks.opacity_for("asphalt", 0, Vector2(-0.85, 0.0)) * 0.1)
	assert(asphalt_rolling < tracks.opacity_for("asphalt", 0, Vector2(0.85, 0.0)) * 0.1)
	assert(tracks.opacity_for("unknown", 5, Vector2.ZERO) > asphalt_rolling)
	assert(tracks.opacity_for("unknown", 5, Vector2.ZERO) < tracks.opacity_for("gravel", 5, Vector2.ZERO))
	assert(tracks.opacity_for("dirt", 2, Vector2.ZERO) > tracks.opacity_for("dirt", 5, Vector2.ZERO))
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
	assert(tracks.ribbons[0].mesh == null and tracks.segments.is_empty())
	print("TIRE_TRACKS_CONTRACT_OK")
	quit()
