extends SceneTree

const TRACK := "raura_stage2"
const PILOT := "raurapilot_stage2"

func _initialize() -> void:
	call_deferred("_verify")

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok

func _verify() -> void:
	var args := OS.get_cmdline_user_args()
	var start_pilot := "--pilot-start" in args
	var relief := "--pilot-relief" in args or start_pilot
	var pilot := relief or "--pilot-osqp" in args
	var track := "raurastart_stage2" if start_pilot else ("raurarelief_stage2" if relief else (PILOT if pilot else TRACK))
	var packed := load("res://scenes/rally/%s.tscn" % track) as PackedScene
	if not _require(packed != null, "Stage scene could not load"):
		return
	var session := packed.instantiate()
	root.add_child(session)
	for i in range(45):
		await physics_frame
	var builder := session.get_node("TrackCollision") as RallyTrackCollisionBuilder
	if not _require(builder.generated_body_count == (2 if pilot and not start_pilot else 3), "Unexpected road, slope or exterior collision body count"):
		return
	if not pilot or start_pilot:
		var grass := session.get_node("StageGrass")
		if not _require(grass.get_child_count() > 0, "Aged grass was not scattered"):
			return
		for batch in grass.get_children():
			if not _require(str(batch.name).ends_with("Variant0"), "Only aged grass is allowed in Raura"):
				return
	var course: RallyStageProgress = session.course
	var space := builder.get_world_3d().direct_space_state
	var max_error := 0.0
	var excluded: Array[RID] = []
	for item in session.get_node("FordEscortRS2000").find_children("*", "CollisionObject3D", true, false):
		excluded.append(item.get_rid())
	var vehicle := session.get_node("FordEscortRS2000") as RigidBody3D
	excluded.append(vehicle.get_rid())
	var loader := RallyStageLoader.new()
	var paths: Dictionary = loader.resolve(track).paths
	var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(paths.route))
	var probes: Array = route.surface_probes
	if not _require(course.points.size() >= (80 if pilot else 1000) and probes.size() == course.points.size(), "Full course not loaded"):
		return
	for i in range(probes.size()):
		for j in range(probes[i].size()):
			var xyz: Array = probes[i][j]
			var origin := Vector3(xyz[0], xyz[1], xyz[2])
			var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 2, origin - Vector3.UP * 2, builder.collision_layer, excluded)
			var hit := space.intersect_ray(query)
			var group := "Gravel" if j < 3 else "Dirt"
			if not _require(not hit.is_empty() and hit.collider.is_in_group(group), "Unexpected surface at point %d probe %d" % [i, j]):
				return
			var error := absf(hit.position.y - origin.y)
			if error > max_error:
				max_error = error
				if error > 0.03:
					print("RAURA_HEIGHT ", i, " ", j, " ", error)
	if not _require(max_error < 0.03, "Route height differs from collision"):
		return
	if route.has("pothole_probes"):
		var checked_pits := 0
		for probe: Dictionary in route.pothole_probes:
			if float(probe.offset_m) > -0.015:
				continue
			var xyz: Array = probe.position
			var point := Vector3(xyz[0], xyz[1], xyz[2])
			var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP, builder.collision_layer, excluded)
			var hit := space.intersect_ray(query)
			if not _require(not hit.is_empty() and hit.collider.is_in_group("Gravel") and absf(hit.position.y - point.y) < 0.005,
					"Pothole is not represented by the collision mesh"):
				return
			checked_pits += 1
		if not _require(checked_pits >= 10, "Insufficient pothole coverage"):
			return
		print("RAURA_RELIEF_OK pothole_samples=", checked_pits)
	var simulated := RallyStageProgress.new()
	var gates: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(paths.timing_gates))
	if not _require(simulated.configure(paths.route) and simulated.configure_timing_gates(gates.gates), "Timing data did not load"):
		return
	for p in simulated.points:
		simulated.advance(p, 0.5, 1, 16.0)
	var finish: Dictionary = simulated.timing_gates[-1]
	simulated.advance(simulated.points[-1] + finish.forward * 2.0, 0.15, 1, 16.0)
	if not _require(simulated.finished and simulated.splits.size() == 4, "The splits and finish did not trigger"):
		return
	session.get_node("RallyGaragePanel").close_garage(true)
	var controller := session.get_node("RallyInputController")
	if vehicle.current_gear == 0:
		vehicle.shift(1)
	var start := vehicle.global_position
	Input.action_press(controller.action_throttle, 0.55)
	var max_wheel_contacts := 0
	for i in range(180):
		await physics_frame
		max_wheel_contacts = maxi(max_wheel_contacts, vehicle.get_wheel_contact_count())
	Input.action_release(controller.action_throttle)
	var travel := start.distance_to(vehicle.global_position)
	if not _require(travel > 3.0 and max_wheel_contacts == 4, "Escort did not launch with all four wheels contacting the surface"):
		return
	var downhill := course.points[course.points.size() / 2]
	if not _require(start_pilot or downhill.y < -50.0, "Regression point must be below the old retirement threshold"):
		return
	vehicle.global_position = downhill + Vector3.UP * 0.5
	vehicle.linear_velocity = Vector3.ZERO
	await physics_frame
	await physics_frame
	if not _require(not session.competition.player_retired, "Vehicle retired while on the descent"):
		return
	vehicle.global_position.y = builder.minimum_collision_height_m - 51.0
	await physics_frame
	await physics_frame
	if not _require(session.competition.player_retired, "A fall below the stage should still retire the vehicle"):
		return
	print("RAURA_STAGE2_LAUNCH travel_m=", travel, " max_wheel_contacts=", max_wheel_contacts)
	print("RAURA_STAGE2_OK samples=", course.points.size() * 5, " max_surface_error_m=", max_error, " gates=", simulated.splits.size())
	session.queue_free()
	await process_frame
	quit()




