extends SceneTree
const Puddles = preload("res://scripts/rally/rally_puddles.gd")
func _initialize() -> void:
	call_deferred("verify")
func verify() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var road := StaticBody3D.new()
	road.name = "Collision_Road"
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
	var points: Array[Vector3] = [Vector3(0,0.1,-130), Vector3(0,0.1,130)]
	var a := Puddles.new()
	a.configure(points, 731, null, moisture)
	world.add_child(a)
	await physics_frame
	await physics_frame
	a._physics_process(0.3)
	assert(not a.patches.is_empty(), "No puddles generated on flat road")
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
	var dry_tire := Puddles.contact_response(15.0, 30.0, false, 2500.0, 0.2, 1.0)
	var rain_tire := Puddles.contact_response(15.0, 30.0, true, 2500.0, 0.2, 1.0)
	assert(float(rain_tire.support) > float(dry_tire.support))
	assert(float(dry_tire.drag_n) > 0.0 and float(dry_tire.drag_n) <= 1125.0)
	assert(float(Puddles.contact_response(0.0, 30.0, false, 2500, 0.2, 1).support) == 1.0)
	moisture.wetness = 0.5
	a._physics_process(0.3)
	var partial := float(a.sample_contact(position).depth_mm)
	assert(partial > 0.0 and partial < float(wet.depth_mm))
	moisture.wetness = 0.0
	a._physics_process(0.3)
	assert(float(a.sample_contact(position).depth_mm) == 0.0)
	assert(not (first.mesh as MeshInstance3D).visible)
	print("PUDDLES_CONTRACT_OK")
	world.queue_free()
	await process_frame
	quit()
