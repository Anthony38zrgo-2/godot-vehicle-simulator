extends SceneTree

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var session := preload("res://scenes/rally/cdi_stage4.tscn").instantiate() as RallyRussiaStageSession
	session.session_mode = "single_stage"
	root.add_child(session)
	for i in 1800:
		if session.session_ready:
			break
		await physics_frame
	if not session.session_ready:
		quit(1)
		return
	session.set_physics_process(false)
	paused = false
	var signs := session.get_node("TiclioRoadSigns")
	var car := session.vehicle
	car.gravity_scale = 0.0
	var all_ok := true
	car.max_contacts_reported = 1
	for speed in [2.0, 5.0, 14.0, 30.0]:
		for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT]:
			var ground: Vector3 = signs.get_meta("placed_signs")[0].ground + Vector3.UP * 20.0
			var sign := {"face":"velocidad_40", "ground":ground, "facing":Vector3.FORWARD, "released":false}
			signs._add_collision(sign, 1)
			var body: RigidBody3D = signs.get_child(-1)
			car.global_transform = Transform3D(Basis.looking_at(-direction, Vector3.UP), ground + direction * 4.0 + Vector3.UP * 0.5)
			car.freeze = false
			car.linear_velocity = -direction * speed
			car.angular_velocity = Vector3.ZERO
			car.freeze = false
			car.sleeping = false
			for i in 180:
				if sign.released:
					break
				await physics_frame
			await physics_frame
			var forward_speed: float = car.linear_velocity.dot(-direction)
			var passed: bool = not sign.released if speed < signs.RELEASE_SPEED else (sign.released and forward_speed > speed * 0.80 and absf(car.linear_velocity.y) < 1.0)
			print("FIRST_HIT speed=",speed," direction=",direction," released=",sign.released," car_forward=",forward_speed," vertical=",car.linear_velocity.y," passed=",passed)
			all_ok = all_ok and passed
			car.freeze = true
			body.queue_free()
			await physics_frame
	quit(0 if all_ok else 1)


