extends SceneTree

var identifier := ""
var output_directory := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rt-id="):
			identifier = argument.trim_prefix("--rt-id=")
		elif argument.begins_with("--rt-output="):
			output_directory = argument.trim_prefix("--rt-output=")
	call_deferred("run")

func run() -> void:
	var registry: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/vehicles/registry.json"))
	var entry: Dictionary = registry.vehicles[identifier]
	var packed = load("res://scenes/rally/" + str(entry.Proving) + ".tscn") as PackedScene
	var session = packed.instantiate()
	root.add_child(session)
	current_scene = session
	for i in 600:
		await physics_frame
		if session.session_ready:
			break
	var car = session.vehicle
	var lines: Array[String] = []
	lines.append("ready physics=" + str(car._physics_ready) + " gear=" + str(car.current_gear) + " rpm=" + str(car.motor_rpm))
	# Secuencia exacta del contrato: cambio + gas inmediato, 1.5 s reales
	car.shift(1)
	Input.action_press(InputBindings.THROTTLE)
	var wall0 := Time.get_ticks_msec()
	var phys0: int = car.simulation.publication_sequence
	await create_timer(1.5).timeout
	var dv: float = car.linear_velocity.dot(-car.global_basis.z)
	lines.append("contract_like vfwd=" + str(dv) + " gear=" + str(car.current_gear) + " rpm=" + str(snappedf(car.motor_rpm, 0.0)) + " phys_frames=" + str(car.simulation.publication_sequence - phys0) + " wall_ms=" + str(Time.get_ticks_msec() - wall0) + " phase=" + car.simulation.powertrain_model.shift_phase + " clE=" + str(snappedf(car.simulation.powertrain_model.clutch_engagement, 2)) + " inShaft=" + str(snappedf(car.simulation.powertrain_model.input_shaft_omega_rad_s, 0.0)) + " engT=" + str(snappedf(car.simulation.powertrain_model.engine_torque_nm, 0.0)) + " clT=" + str(snappedf(car.simulation.powertrain_model.clutch_torque_nm, 0.0)) + " spin=" + str(car.simulation.wheel_spins))
	await create_timer(2.0).timeout
	var dv2: float = car.linear_velocity.dot(-car.global_basis.z)
	lines.append("t35s vfwd=" + str(dv2) + " rpm=" + str(snappedf(car.motor_rpm, 0.0)) + " spin=" + str(car.simulation.wheel_spins))
	await create_timer(2.0).timeout
	var dv3: float = car.linear_velocity.dot(-car.global_basis.z)
	lines.append("t55s vfwd=" + str(dv3) + " rpm=" + str(snappedf(car.motor_rpm, 0.0)) + " spin=" + str(car.simulation.wheel_spins))
	Input.action_release(InputBindings.THROTTLE)
	print("RT_PROBE_BEGIN")
	print("RT_PROBE wall_ms_for_180_physics_frames=" + str(Time.get_ticks_msec() - wall0))
	for line in lines:
		print("RT_PROBE " + line)
	print("RT_PROBE_END")
	quit(0)
