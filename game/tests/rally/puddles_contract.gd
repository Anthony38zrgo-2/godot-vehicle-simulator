extends SceneTree

const Puddles = preload("res://scripts/rally/rally_puddles.gd")


func _initialize() -> void:
	call_deferred("verify")


func verify() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var road := StaticBody3D.new()
	road.name = "Collision_Road"
	road.set_meta("is_stage_road", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 0.2, 300)
	shape.shape = box
	road.add_child(shape)
	world.add_child(road)

	var moisture := Node.new()
	moisture.set_script(load("res://scripts/rally/rally_terrain_wetness.gd"))
	world.add_child(moisture)
	moisture.set_process(false)
	moisture.wetness = 1.0

	var points: Array[Vector3] = [Vector3(0, 0.1, -130), Vector3(0, 0.1, 130)]
	var a := Puddles.new()
	a.configure(points, 731, null, moisture)
	world.add_child(a)
	await physics_frame
	await physics_frame
	a._physics_process(0.3)
	assert(not a.patches.is_empty(), "No puddles generated on flat road")

	# Verify morphological asymmetry
	var test_shape := Vector4(0.35, -0.25, 0.18, 1.2)
	var m_pos := Puddles.mask_at(Vector2(0.25, 0.30), test_shape)
	var m_neg := Puddles.mask_at(Vector2(-0.25, -0.30), test_shape)
	assert(m_pos != m_neg, "Mask must be organically asymmetric")

	# Verify profile diversity
	var profile_ids: Dictionary = {}
	var max_depth_found := 0.0
	var min_depth_found := 999.0
	var max_area_found := 0.0
	var min_area_found := 999.0
	var mean_abs_lat := 0.0
	var min_yaw := 999.0
	var max_yaw := -999.0
	var cluster_set: Dictionary = {}

	for p in a.patches:
		var pid: String = str(p.profile.id)
		profile_ids[pid] = true
		var pd: float = float(p.get("depth_mm", p.profile.depth_mm))
		max_depth_found = maxf(max_depth_found, pd)
		min_depth_found = minf(min_depth_found, pd)
		var sz: Vector2 = p.size
		var area: float = sz.x * sz.y
		max_area_found = maxf(max_area_found, area)
		min_area_found = minf(min_area_found, area)
		mean_abs_lat += absf(float(p.get("lateral_offset", 0.0)))
		var y := float(p.get("yaw", 0.0))
		min_yaw = minf(min_yaw, y)
		max_yaw = maxf(max_yaw, y)
		cluster_set[int(p.get("cluster_id", 0))] = true

	mean_abs_lat /= float(a.patches.size())
	assert(profile_ids.size() >= 3, "Puddles must generate diverse profiles")
	assert(max_depth_found >= 38.0 and min_depth_found <= 10.0, "Puddles must span diverse depths with high dynamic range")
	assert(max_area_found > 14.0, "Puddles must include large basins with +25% size increase")
	assert(max_area_found / min_area_found > 3.0, "Puddles must have high size variability")
	assert(mean_abs_lat > 0.65, "Puddles must form off-center wheel-rut and shoulder patterns (not a centerline file)")
	assert(max_yaw - min_yaw > 1.0, "Puddles must have diverse 360-degree yaw rotations")
	assert(cluster_set.size() >= 4, "Puddles must group into Poisson clusters")

	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tires/rally_compounds.json"))
	var tires = load("res://scripts/physics/tire_model.gd").new()
	tires.set_compound("gravel_normal", catalog)
	tires.set_wheel_compound(0, "gravel_wet")
	assert(tires.wheel_compounds[0].id == "gravel_wet")
	assert(tires.wheel_compounds[1].id == "gravel_normal")

	var first: Dictionary = a.patches[0]
	var position: Vector3 = first.transform.origin
	var wet := a.sample_contact(position)
	assert(float(wet.depth_mm) > 0.0)
	assert(float(a.sample_contact(position + Vector3.UP).depth_mm) == 0.0)
	assert(float(a.sample_contact(position + Vector3.RIGHT * 20.0).depth_mm) == 0.0)

	var b := Puddles.new()
	b.configure(points, 731, null, moisture)
	world.add_child(b)
	b.build()
	assert(a.patches.size() == b.patches.size())
	for i in a.patches.size():
		assert(a.patches[i].transform == b.patches[i].transform)

	# Hydrodynamic physical response contract
	var dry_tire := Puddles.contact_response(15.0, 30.0, false, 2500.0, 0.2, 1.0, 80.0, 0.28)
	var rain_tire := Puddles.contact_response(15.0, 30.0, true, 2500.0, 0.2, 1.0, 80.0, 0.28)
	assert(float(rain_tire.support) > float(dry_tire.support), "Wet tire must have higher aquaplaning support")
	assert(float(dry_tire.support_longitudinal) > float(dry_tire.support_lateral), "Lateral grip must drop faster than longitudinal")
	assert(float(dry_tire.drag_n) >= 1000.0 and float(dry_tire.drag_n) <= 2032.0, "Drag must deliver strong palpable retarding force with +25% reaction force")
	assert(float(dry_tire.wheel_torque_nm) > 100.0, "Puddle must exert braking torque on wheel rotation")
	assert(float(dry_tire.steering_pull_nm) > 20.0, "Asymmetrical puddle must produce steering pull moment")
	assert(float(Puddles.contact_response(0.0, 30.0, false, 2500, 0.2, 1).support) == 1.0)
	assert(float(Puddles.contact_response(0.0, 30.0, false, 2500, 0.2, 1).drag_n) == 0.0)

	# Llenado parcial vs secado
	moisture.wetness = 0.5
	a._physics_process(0.3)
	var partial := float(a.sample_contact(position).depth_mm)
	assert(partial < float(wet.depth_mm), "Partial wetness must have lower depth")

	# En condiciones secas: cero profundidad y visibilidad apagada
	moisture.wetness = 0.0
	a._physics_process(0.3)
	assert(float(a.sample_contact(position).depth_mm) == 0.0, "Dry weather must have zero depth")
	for p in a.patches:
		assert(not (p.mesh as MeshInstance3D).visible, "All puddles must be invisible in dry weather")

	print("PUDDLES_CONTRACT_OK")
	world.queue_free()
	await process_frame
	quit()
