extends SceneTree

const MINI := preload("res://scenes/rally/rt/rt-mini-cooper-s.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	await _check_surface("Gravel")
	await _check_surface("Road")
	print("MINI_COOPER_TRACTION_CONTRACT ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)


func _check_surface(surface: String) -> void:
	var ground := StaticBody3D.new()
	ground.add_to_group(surface)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 2.0, 100.0)
	collider.shape = box
	collider.position.y = -1.0
	ground.add_child(collider)
	root.add_child(ground)

	var vehicle := MINI.instantiate() as RallyEscortVehicle
	vehicle.position.y = RallyProvingGroundSession.SPAWN_CLEARANCE_METRES
	root.add_child(vehicle)
	var powertrain := vehicle.simulation.powertrain_model
	var ticks := Engine.physics_ticks_per_second
	for i in ticks:
		await physics_frame
	await _check_idle(vehicle, surface + " neutral", ticks * 2)
	powertrain.set_gear(1)
	await _check_idle(vehicle, surface + " first gear", ticks * 3)

	var launch_origin := vehicle.position
	vehicle.throttle_input = 1.0
	for i in ticks * 4:
		await physics_frame
	var forward_speed := vehicle.linear_velocity.dot(Vector3.FORWARD)
	var lateral_drift := absf(vehicle.position.x - launch_origin.x)
	_check(forward_speed > 9.0 and lateral_drift < 0.25,
		"%s launch: %.2f m/s forward, %.3f m lateral drift" % [surface, forward_speed, lateral_drift])
	vehicle.queue_free()
	ground.queue_free()
	await process_frame


func _check_idle(vehicle: RallyEscortVehicle, label: String, frames: int) -> void:
	var origin := vehicle.position
	var peak_speed := 0.0
	var peak_angular_speed := 0.0
	for i in frames:
		await physics_frame
		peak_speed = maxf(peak_speed, vehicle.linear_velocity.length())
		peak_angular_speed = maxf(peak_angular_speed, vehicle.angular_velocity.length())
	var drift := Vector2(vehicle.position.x - origin.x, vehicle.position.z - origin.z).length()
	_check(drift < 0.03 and peak_speed < 0.06 and peak_angular_speed < 0.05,
		"%s idle: %.3f m drift, peak %.3f m/s and %.3f rad/s" % [label, drift, peak_speed, peak_angular_speed])


func _check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
