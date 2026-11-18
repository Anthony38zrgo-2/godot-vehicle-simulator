extends SceneTree

const SECTORS := "res://assets/rally/cdi_stage1/sectores/"


func _initialize() -> void:
	call_deferred("_verify")


func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok


func _has_road(track: RallyTrackCollisionBuilder, p: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		p + Vector3.UP * 2.0, p - Vector3.UP * 2.0, track.collision_layer)
	var hit := track.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider.is_in_group("Gravel")


func _wait_for_sector(stream: Node3D, path: String) -> bool:
	for frame in range(650):
		if stream.get_children().any(func(node: Node) -> bool: return node.scene_file_path == path):
			return true
		await process_frame
	return false


func _verify() -> void:
	var session := (load("res://scenes/rally/cdi_stage1.tscn") as PackedScene).instantiate()
	root.add_child(session)
	for frame in range(1800):
		if session.has_node("StageBushes"):
			break
		await process_frame
	if not _require(session.has_node("StageBushes"), "CDI session did not load"):
		return
	var stream := session.get_node("TrackVisual/VisualSectorStream") as Node3D
	var track := session.get_node("TrackCollision") as RallyTrackCollisionBuilder
	var vehicle := session.vehicle as RallyEscortVehicle
	if not _require(str(vehicle.rally_profile.get("profile_id", "")) == "ford_mustang_1967_289_2v",
			"Rajuntay did not start with the Mustang"):
		return
	var course: RallyStageProgress = session.course
	var first := course.points[0]
	var last := course.points[-1]
	var start_sector: String = stream.sector_for_point(first)
	var finish_sector: String = stream.sector_for_point(last)
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SECTORS + "index.json"))
	var regional := session.find_child("Rajuntay Regional DEM", true, false) as MeshInstance3D
	if not _require(regional != null,
			"The continuous regional mesh must be resident"):
		return
	var regional_material := regional.get_active_material(0) as ShaderMaterial
	if not _require(regional_material != null and regional_material.get_shader_parameter("grass_gis") != null,
			"The regional mesh is missing its GIS coverage mask"):
		return
	if not _require(await _wait_for_sector(stream, start_sector), "Missing starting detail"):
		return
	var first_tile: Node = stream.get_children().filter(
		func(node: Node) -> bool: return node.scene_file_path == start_sector).front()
	var first_tile_id := first_tile.get_instance_id()
	var first_objects := first_tile.get_node("SectorObjects")
	var props := session.get_node("StageProps")
	if not _require(first_objects.get_child_count() > 0 and props.get_child_count() == 0
			and props.get_meta("counts").rocks == 200
			and session.get_node("StageGrass").get_child_count() == 0,
			"Procedural scenery was not assigned to the terrain sectors"):
		return
	var has_rock_texture := false
	for slope in stream.find_children("Terrain_Dirt_*", "MeshInstance3D", true, false):
		for i in slope.mesh.get_surface_count():
			var material := slope.get_active_material(i) as ShaderMaterial
			if material != null:
				var texture := material.get_shader_parameter("terrain_palette") as Texture2DArray
				var uv_mask: PackedVector2Array = slope.mesh.surface_get_arrays(i)[Mesh.ARRAY_TEX_UV2]
				has_rock_texture = has_rock_texture or (texture != null
					and texture.get_layers() == 19 and not uv_mask.is_empty()
					and material.get_shader_parameter("grass_gis") == regional_material.get_shader_parameter("grass_gis"))
	if not _require(has_rock_texture, "Streamed taluds did not receive the rock cut texture"):
		return
	var road := stream.find_child("Road", true, false) as MeshInstance3D
	var gravel := road.get_active_material(0) as ShaderMaterial if road != null else null
	if not _require(gravel != null and gravel.get_shader_parameter("terrain_palette") == stream.terrain_palette
			and gravel.get_shader_parameter("terrain_mode") == 2, "Streamed road lost its gravel palette"):
		return
	var road_uv: PackedVector2Array = road.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	var has_station := false
	for uv in road_uv:
		if uv.y > 10.0:
			has_station = true
			break
	if not _require(has_station, "Streamed road lost its material station coordinates"):
		return
	var start_active := stream.get_child_count()
	if not _require(start_active < index.sectors.size() and not ResourceLoader.has_cached(finish_sector),
			"A distant sector should not be preloaded with the entire visual stage"):
		return
	await physics_frame
	if not _require(_has_road(track, last), "Collision must exist before finish detail loads"):
		return
	vehicle.freeze = true
	vehicle.global_position = last + Vector3.UP
	if not _require(await _wait_for_sector(stream, finish_sector), "Finish detail failed to load"):
		return
	for frame in range(10):
		await process_frame
	if not _require(not ResourceLoader.has_cached(start_sector) and stream.get_child_count() < index.sectors.size(),
			"The starting mesh was not released"):
		return
	await physics_frame
	if not _require(_has_road(track, first), "Starting road collision disappeared on unload"):
		return
	vehicle.global_position = first + Vector3.UP
	if not _require(await _wait_for_sector(stream, start_sector), "Returning did not reload starting detail"):
		return
	var reloaded: Node = stream.get_children().filter(
		func(node: Node) -> bool: return node.scene_file_path == start_sector).front()
	if not _require(reloaded.get_instance_id() != first_tile_id and reloaded.get_node("SectorObjects").get_child_count() > 0,
			"Returning did not recreate streamed scenery"):
		return
	print("CDI_STREAM_OK start_active=", start_active, " total=", index.sectors.size())
	session.queue_free()
	await process_frame
	quit()
