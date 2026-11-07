extends SceneTree

const Mixer = preload("res://scripts/audio/surface_mix.gd")
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
func wheels(names: Array, slip: float = 0.0, load_n: float = 2500.0) -> Array:
	var result: Array = []
	for name in names:
		result.append({"surface": name, "load_n": load_n, "slip_ratio": slip, "slip_angle_rad": 0.0})
	return result
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var mixed: Dictionary = Mixer.evaluate(wheels(["Gravel", "Gravel", "Grass", "Grass"]), 60.0, 0.0, 0.0, 10000.0)
	check(is_equal_approx(float(mixed.shares.gravel), 0.5) and mixed.surfaces.size() == 2, "mixed contact")
	var airborne: Dictionary = Mixer.evaluate(wheels(["Gravel", "Gravel", "Grass", "Grass"], 1.0, 0.0), 60.0, 1.0, 0.0, 10000.0)
	check(airborne.roll_total == 0.0 and airborne.contacts == 0 and airborne.slip.is_empty(), "airborne silence")
	var stopped: Dictionary = Mixer.evaluate(wheels(["Road", "Road", "Road", "Road"], 1.0), 0.0, 1.0, 0.0, 10000.0)
	check(stopped.roll_total == 0.0 and stopped.slip.tarmac.peel == 0.0, "stopped silence")
	var slipping: Dictionary = Mixer.evaluate(wheels(["Gravel", "Gravel", "Gravel", "Gravel"], 0.5), 60.0, 1.0, 0.0, 10000.0)
	var rolling: Dictionary = Mixer.evaluate(wheels(["Gravel", "Gravel", "Gravel", "Gravel"]), 60.0, 1.0, 0.0, 10000.0)
	check(slipping.roll_total < rolling.roll_total and slipping.slip.gravel.peel > 0.0 and rolling.slip.gravel.peel == 0.0, "slip replaces rolling")
	var many: Dictionary = Mixer.evaluate(wheels(["Gravel", "Grass", "Dirt", "Sand"]), 60.0, 0.0, 0.0, 10000.0)
	check(many.surfaces.size() == 2, "two surface limit")
	var whole: float = Mixer.smooth(0.0, 1.0, 0.1, 0.08)
	var halves: float = Mixer.smooth(Mixer.smooth(0.0, 1.0, 0.05, 0.08), 1.0, 0.05, 0.08)
	check(is_equal_approx(whole, halves), "frame independent transitions")
	var scene: Node = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.2).timeout
	var vehicle = scene.get_node("FordEscortRS2000")
	var audio = vehicle.get_node("VehicleAudio")
	audio.set_physics_process(false)
	check(audio.surface_players.size() == 12, "all 12 surface roles loaded")
	var packet: Dictionary = {"wheels": wheels(["Gravel", "Gravel", "Grass", "Grass"], 0.5), "speed_kph": 60.0, "throttle": 1.0}
	for step in 120:
		audio.update_surface_audio(packet, 1.0 / 120.0)
	check(audio.surface_players["gravel:roll"].volume_linear > 0.0 and audio.surface_players["grass:skid"].volume_linear > 0.0, "runtime mixed roll and slip")
	packet.wheels = wheels(["Gravel", "Gravel", "Grass", "Grass"], 0.5, 0.0)
	for step in 240:
		audio.update_surface_audio(packet, 1.0 / 120.0)
	for key in audio.surface_players:
		check(audio.surface_players[key].stream_paused, "runtime airborne fade " + str(key))
	print("SURFACE_AUDIO_CONTRACT ", JSON.stringify({"passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
