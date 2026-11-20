extends SceneTree

const TRACK := "cdi_stage1"
const NEXT_TRACK := "cdi_stage2"
const SERVICE := preload("res://scripts/rally/rally_service_panel.gd")
const EventManager := preload("res://scripts/rally/rally_event_manager.gd")
const RallyCompetition = preload("res://scripts/rally/rally_competition.gd")
const STEP_S := 0.05
const SPEED_M_S := 20.0


func _initialize() -> void:
	call_deferred("_verify")


func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok


func _advance(course: RallyStageProgress, competition: RallyCompetition, point: Vector3) -> void:
	course.advance(point, STEP_S, course.generation, SPEED_M_S)
	competition.update(course.readout())


func _verify() -> void:
	var session := (load("res://scenes/rally/cdi_stage1.tscn") as PackedScene).instantiate() as RallyRussiaStageSession
	var event := EventManager.new()
	if not _require(event.begin_event({
		"event_path": "res://data/competition/events/cdi_rally.json", "save_path": "", "seed": 19, "setup_accepted": true,
	}), "Could not start CDI event: " + event.error):
		return
	session.begin_event_session(event, TRACK)
	root.add_child(session)
	for i in range(1800):
		await physics_frame
		if session.session_ready:
			break
	if not _require(session.session_ready, "Rajuntay session did not finish loading"):
		return
	session.set_physics_process(false)
	await physics_frame
	await physics_frame
	var track := session.get_node("TrackCollision") as RallyTrackCollisionBuilder
	if not _require(track.get_node_or_null("TrackCollision_Collision_Barrier_Guardrail") == null,
			"SS01 must not have roadside guardrails"):
		return
	var loader := RallyStageLoader.new()
	var resolved := loader.resolve(TRACK)
	var source: Dictionary = resolved.manifest.source
	var end_pk := float(source.source_pk_m[-1])
	var finish_pk := float(source.timed_source_pk_m[-1])
	if not _require(end_pk > 5156.0 and is_equal_approx(end_pk - finish_pk, 50.0),
			"Expected full SS01 geometry and 50 m beyond the timing line"):
		return
	var route_path: String = resolved.paths.route
	var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(route_path))
	var gates: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(resolved.paths.timing_gates))
	var course := RallyStageProgress.new()
	var competition: RallyCompetition = session.competition
	if not _require(course.configure(route_path) and course.configure_timing_gates(gates.gates)
			and event.current_stage_id() == TRACK and not event.is_last_stage(), "Timing data failed to load"):
		return
	var finish: Dictionary = course.timing_gates[-1]
	var origin: Vector3 = finish.origin
	var forward: Vector3 = finish.forward
	var right: Vector3 = finish.right
	if not _require(course.route_distances[-1] > 4900.0 and finish.kind == "finish"
			and int(finish.route_index) == course.points.size() - 1
			and origin.distance_to(course.points[-1]) < 0.01
			and absf(float(finish.route_distance_m) - course.route_distances[-1]) < 0.01,
			"Finish gate is not at the final timed point"):
		return
	for label in ["Meta_L", "Meta_R"]:
		var board := session.find_child(label, true, false) as MeshInstance3D
		if not _require(board != null and absf((board.to_global(board.get_aabb().get_center()) - origin).dot(forward)) < 0.01,
				"Finish boards are not aligned with the timing plane"):
			return

	# Follow the entire route in roughly one-metre steps. Both timing layers
	# must stay open through the last approach inside the checkpoint radius.
	course.external_start = true
	_advance(course, competition, course.points[0])
	course.clock_started = true
	for i in range(1, course.points.size() - 1):
		var a := course.points[i - 1]
		var b := course.points[i]
		var steps := maxi(1, ceili(a.distance_to(b)))
		for j in range(1, steps + 1):
			_advance(course, competition, a.lerp(b, float(j) / steps))
			if not _require(not course.finished and not competition.complete, "SS01 ended before the finish plane"):
				return
	_advance(course, competition, origin - forward * 0.10)
	if not _require(not course.finished and not competition.complete and course.splits.size() == 3,
			"SS01 finished inside the approach radius"):
		return

	var side := right * (float(finish.half_width_m) + 3.0)
	_advance(course, competition, origin - forward + side)
	_advance(course, competition, origin + forward + side)
	_advance(course, competition, origin + forward)
	_advance(course, competition, origin - forward)
	if not _require(not course.finished and not competition.complete,
			"A crossing outside the gate or against its direction ended SS01"):
		return
	session.continue_competition()
	if not _require(event.current_stage_id() == TRACK and not session.stage_transition_running,
			"SS02 became available before crossing the SS01 finish"):
		return
	var before_s := course.elapsed_s
	_advance(course, competition, origin + forward)
	if not _require(course.finished and competition.complete and course.splits.size() == 4
			and course.splits[-1].gate_id == "finish"
			and absf(course.elapsed_s - (before_s + STEP_S * 0.5)) <= 0.001,
			"SS01 did not register the actual swept finish crossing"):
		return

	var space := track.get_world_3d().direct_space_state
	var runout: Array = route.runout_probes
	if not _require(runout.size() >= 6, "Missing post-finish road samples"):
		return
	var last_sample := Vector3.ZERO
	for xyz: Array in runout:
		var point := Vector3(xyz[0], xyz[1], xyz[2])
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP, track.collision_layer)
		var hit := space.intersect_ray(query)
		if not _require(not hit.is_empty() and hit.collider.is_in_group("Gravel"), "Missing gravel after the finish"):
			return
		last_sample = point
	if not _require(last_sample.distance_to(origin) > 44.0, "Gravel ends too soon after the finish"):
		return
	print("CDI_FINISH_OK race_m=", course.route_distances[-1], " runout_probes=", runout.size())
	var ss01_ms := competition.player_ms
	session.apply_competition_controls()
	var panel = session.head_up_display.competition_panel
	if not _require(panel.next_button.visible and not panel.next_button.disabled,
			"Results do not offer SS02 after crossing the finish"):
		return
	panel.next_button.pressed.emit()
	for i in range(1800):
		await physics_frame
		if session.session_ready and not session.stage_transition_running:
			break
	if not _require(session.session_ready and session.session_track_id == NEXT_TRACK
			and event.current_stage_id() == NEXT_TRACK and not event.is_last_stage()
			and session.stage_place == "Quebrada Chinchán" and not session.competition.complete
			and event.official.get("player", {}).get("grand_total_ms", 0) == ss01_ms,
			"Could not continue into SS02 with the SS01 result"):
		return
	var stream := session.get_node("TrackVisual/VisualSectorStream") as RallyVisualSectorStream
	if not _require(stream != null and stream.terrain_palette != null
			and session.has_node("StageProps") and session.has_node("StageBushes"),
			"SS02 did not load its streamed terrain and scenery"):
		return
	if not _require(track.get_node_or_null("TrackCollision_Collision_Barrier_Guardrail") == null,
			"SS02 must not have roadside guardrails"):
		return
	var start := session.course.points[0]
	var start_query := PhysicsRayQueryParameters3D.create(start + Vector3.UP, start - Vector3.UP, track.collision_layer)
	var start_hit := space.intersect_ray(start_query)
	if not _require(not start_hit.is_empty() and start_hit.collider.is_in_group("Gravel"),
			"SS02 has no gravel collision at the start"):
		return
	var next_route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(session.resolved_stage.paths.route))
	var next_runout: Array = next_route.runout_probes
	if not _require(next_runout.size() >= 6, "Missing SS02 post-finish samples"):
		return
	for xyz: Array in next_runout:
		var point := Vector3(xyz[0], xyz[1], xyz[2])
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP, track.collision_layer)
		var hit := space.intersect_ray(query)
		if not _require(not hit.is_empty() and hit.collider.is_in_group("Gravel"), "Missing SS02 gravel after the finish"):
			return
	print("CDI_SEQUENCE_OK stage=", session.session_track_id, " carried_ms=", ss01_ms)
	if not await _verify_service_and_final_stages(session, event, track):
		return
	var music := root.get_node_or_null("RallyMusic")
	if music != null:
		music.call("on_start_rally")
	session.queue_free()
	await create_timer(0.2).timeout
	quit()


func _drive_finish(course: RallyStageProgress, competition: RallyCompetition) -> bool:
	course.external_start = true
	_advance(course, competition, course.points[0])
	course.clock_started = true
	for i in range(1, course.points.size()):
		var a := course.points[i - 1]
		var b := course.points[i]
		var steps := maxi(1, ceili(a.distance_to(b)))
		for j in range(1, steps + 1):
			_advance(course, competition, a.lerp(b, float(j) / steps))
	var gate: Dictionary = course.timing_gates[-1]
	_advance(course, competition, gate.origin + gate.forward)
	return course.finished and competition.complete and course.splits.size() == 4


func _wait_for_stage(session: RallyRussiaStageSession, stage_id: String) -> bool:
	for i in range(1800):
		if session.session_track_id == stage_id and session.session_ready and not session.stage_transition_running:
			return true
		await process_frame
	return false


func _road_at(track: RallyTrackCollisionBuilder, point: Vector3) -> StaticBody3D:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP, track.collision_layer)
	return track.get_world_3d().direct_space_state.intersect_ray(query).get("collider") as StaticBody3D


func _verify_service_and_final_stages(
		session: RallyRussiaStageSession, event: RallyEventManager, track: RallyTrackCollisionBuilder) -> bool:
	if not _require(_drive_finish(session.course, session.competition), "SS02 finish did not register"):
		return false
	session.apply_competition_controls()
	var panel = session.head_up_display.competition_panel
	if not _require(panel.next_button.visible and panel.next_button.text.contains("SERVICIO"),
			"SS02 results did not offer service"):
		return false
	panel.next_button.pressed.emit()
	if not _require(await _wait_for_stage(session, "cdi_stage3"), "SS03 failed to load"):
		return false
	var service: Node
	for child in session.get_children():
		if child.get_script() == SERVICE:
			service = child
			break
	var window := event.get_pending_window()
	if not _require(service != null and session.awaiting_setup and session.vehicle.freeze
			and window.get("window_key") == "service:cdi_stage2>cdi_stage3" and window.get("repair_minutes") == 30,
			"SS03 must wait for the 30-minute service"):
		return false
	service.get("commit").pressed.emit()
	for i in range(180):
		if session.garage_panel.visible:
			break
		await process_frame
	if not _require(session.garage_panel.visible and session.awaiting_setup,
			"Service did not lead to the required setup confirmation"):
		return false
	session.garage_panel.close_garage(true)
	if not _require(not session.awaiting_setup and event.get_pending_window().is_empty()
			and session.stage_place == "Chinchán Asfalto", "SS03 remained locked after service"):
		return false
	await physics_frame
	if not await _verify_asphalt_pack(session, track, false):
		return false
	var route := session.course.points
	for i in [0, route.size() / 2, route.size() - 1]:
		var road := _road_at(track, route[i])
		if not _require(road != null and road.is_in_group("Road")
				and str(road.get_meta("winter_layer_id", "")).is_empty(), "Expected asphalt throughout SS03"):
			return false
	if not _require(_drive_finish(session.course, session.competition), "SS03 finish did not register"):
		return false
	session.apply_competition_controls()
	panel.next_button.pressed.emit()
	if not _require(await _wait_for_stage(session, "cdi_stage4")
			and event.is_last_stage() and not session.awaiting_setup and session.stage_place == "Abra Ticlio",
			"Could not continue directly to SS04"):
		return false
	await physics_frame
	if not await _verify_asphalt_pack(session, track, true):
		return false
	route = session.course.points
	var transition := float(session.resolved_stage.manifest.source.get("snow_start_m_from_start", 0.0))
	var length := session.course.route_distances[-1]
	if not _require(absf(transition - length * 0.5) < 20.0, "SS04 snow does not begin near the midpoint"):
		return false
	for i in range(0, route.size(), 4):
		var distance := session.course.route_distances[i]
		if absf(distance - transition) < 12.0:
			continue
		var road := _road_at(track, route[i])
		var snowy := distance > transition
		if not _require(road != null and (road.get_meta("winter_layer_id", "") == "snow_packed" if snowy
				else road.is_in_group("Road") and str(road.get_meta("winter_layer_id", "")).is_empty()),
				"Unexpected SS04 road surface around %d m" % roundi(distance)):
			return false
	var finish_road := _road_at(track, route[-1])
	if not _require(finish_road != null and finish_road.get_meta("winter_layer_id", "") == "snow_packed",
			"Snow must continue through the SS04 finish"):
		return false
	if not _require(_drive_finish(session.course, session.competition), "SS04 finish did not register"):
		return false
	session.apply_competition_controls()
	if not _require(event.status == "finished" and event.official.get("player", {}).get("stages", {}).size() == 4,
			"Expected an official result for each CDI stage"):
		return false
	print("CDI_SERVICE_AND_SURFACES_OK snow_m=", transition, " race_m=", length)
	return true

func _verify_asphalt_pack(session: RallyRussiaStageSession, track: RallyTrackCollisionBuilder, has_snow: bool) -> bool:
	var stream := session.get_node("TrackVisual/VisualSectorStream") as RallyVisualSectorStream
	var road := stream.find_child("Road", true, false) as MeshInstance3D
	var surface := road.get_active_material(0) as ShaderMaterial if road != null else null
	if not _require(surface != null and surface.shader.resource_path.ends_with("cdi_asfalto_estepa.gdshader")
			and (float(surface.get_shader_parameter("snow_station_m")) > 0.0) == has_snow,
			"Missing asphalt pack or incorrect snow transition"):
		return false
	var textures := surface.get_shader_parameter("surface_textures") as Texture2DArray
	if not _require(textures != null and textures.get_layers() == 10, "Incomplete asphalt/snow palette"):
		return false
	var rail := track.get_node_or_null("TrackCollision_Collision_Barrier_Guardrail") as StaticBody3D
	if not _require(rail != null and rail.get_meta("collision_role", "") == "barrier",
			"Missing resident guardrail collision"):
		return false
	var signs := session.get_node_or_null("TiclioRoadSigns")
	if not _require((signs != null and int(signs.get_meta("sign_count", 0)) == 17) if has_snow else signs == null,
			"Expected the complete roadside sign set only in SS04"):
		return false
	var parking := session.get_node_or_null("TiclioParking")
	var groups: Dictionary = parking.get_meta("viewing_groups", {}) if parking != null else {}
	for pk in ([4227, 5647] if has_snow else [1187]):
		var group: Dictionary = groups.get(pk, {})
		if not _require(group.get("vehicles", 0) == 2 and int(group.get("people", 0)) >= 4,
				"Missing parked vehicles or spectators at PK %d" % pk):
			return false
	if has_snow:
		if not _require(parking != null and int(parking.get_meta("arrival_count", 0)) == 8
				and int(parking.get_meta("building_count", 0)) == 4
				and int(parking.get_meta("uphill_count", 0)) >= 5, "Incomplete SS04 parking"):
			return false
		if not _require(float(parking.get_meta("monument_station_m", 0)) > float(parking.get_meta("parking_end_m", INF)),
				"Ticlio monuments must be beyond the parked vehicles"):
			return false
		var grass := session.get_node("StageGrass")
		var mask := stream._ticlio_snow_coverage
		if not _require(mask != null and int(grass.get_meta("snow_skipped", 0)) > 100
				and int(grass.get_meta("snow_placed", 0)) > 20 and grass.custom_variants.size() == 15
				and grass.snowy_variants.size() == 15,
				"SS04 snow mask did not thin the ichu"):
			return false
	var shape := rail.get_node("TrackCollisionShape") as CollisionShape3D
	var faces := (shape.shape as ConcavePolygonShape3D).get_faces()
	var height := maxf(faces[0].y, maxf(faces[1].y, faces[2].y)) 		- minf(faces[0].y, minf(faces[1].y, faces[2].y))
	var vertical_edge := 0.0
	for i in range(3):
		var delta := faces[(i + 1) % 3] - faces[i]
		if Vector2(delta.x, delta.z).length() < 0.001:
			vertical_edge = absf(delta.y)
	if not _require(absf(vertical_edge - 0.49) < 0.002 and height >= vertical_edge - 0.002,
			"Guardrail collision must use the reduced height"):
		return false
	var regional := session.find_child("Rajuntay Regional DEM", true, false) as MeshInstance3D
	var terrain := regional.get_active_material(0) as ShaderMaterial if regional != null else null
	if not _require(terrain != null and bool(terrain.get_shader_parameter("ticlio_snow_enabled")) == has_snow,
			"Regional snow shading must be specific to SS04"):
		return false
	var p := shape.to_global((faces[0] + faces[1] + faces[2]) / 3.0)
	var near := Vector2(p.x, p.z)
	var visual_rail: MeshInstance3D
	for i in range(120):
		stream._tick(near, near)
		visual_rail = stream.find_child("Guardarrail", true, false) as MeshInstance3D
		if visual_rail != null:
			break
		await process_frame
	if not _require(visual_rail != null, "No guardrail visual near its resident collision mesh"):
		return false
	for i in visual_rail.mesh.get_surface_count():
		var mat := visual_rail.get_active_material(i) as StandardMaterial3D
		if not _require(mat != null and mat.albedo_texture != null
				and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
				"Guardrail must use a cutout texture from asfalto_estepa"):
			return false
	await physics_frame
	var normal := (faces[1] - faces[0]).cross(faces[2] - faces[0]).normalized()
	var query := PhysicsRayQueryParameters3D.create(p + normal * 0.15, p - normal * 0.15, track.collision_layer)
	query.hit_back_faces = true
	var hit := track.get_world_3d().direct_space_state.intersect_ray(query)
	return _require(hit.get("collider") == rail, "Guardrail did not stop a physics ray at the rail")
