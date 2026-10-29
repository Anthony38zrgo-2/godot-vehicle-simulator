extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_contract")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)

func run_contract() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var russia := "--russia-preview" in OS.get_cmdline_user_args()
	var scene_path := "res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn" if russia else "res://scenes/rally/rally_proving_ground.tscn"
	var scene: Node = load(scene_path).instantiate()
	var capture_effect := AudioEffectCapture.new()
	capture_effect.buffer_length = 2.0
	var audio_bus := AudioServer.get_bus_index("Vehicle")
	if audio_bus >= 0:
		AudioServer.add_bus_effect(audio_bus, capture_effect)
	root.add_child(scene)
	current_scene = scene
	for i in 120:
		await physics_frame
	var vehicle = scene.get_node("FordEscortRS2000")
	var camera = scene.get_node("RallyCameraRig")
	var audio = vehicle.get_node("VehicleAudio")
	var snapshot: Dictionary = vehicle.get_presentation_snapshot()
	check(not snapshot.is_empty(), "Accepted physics publication is missing")
	check(int(snapshot.get("contact_queries", 0)) == 4, "Exactly four contact queries must be published")
	check(snapshot.get("wheels", []).size() == 4, "Four thermal wheel states must be published")
	camera.snap_to_target()
	var offset_before: Vector3 = camera.global_position - vehicle.global_position
	vehicle.global_position += Vector3(20, 0, 0)
	camera.snap_to_target()
	var offset_after: Vector3 = camera.global_position - vehicle.global_position
	check(offset_before.distance_to(offset_after) < 0.001, "Chase camera distance changes with translation")
	check(is_equal_approx(camera.camera.fov, 68.0), "Chase FOV changes with speed")
	vehicle.global_position -= Vector3(20, 0, 0)
	camera.snap_to_target()
	for definitions in [audio.ENGINE_SAMPLE_DEFINITIONS, audio.EXHAUST_SAMPLE_DEFINITIONS]:
		for rpm in range(900, 8001, 50):
			var total := 0.0
			for definition in definitions:
				total += audio.sample_weight(float(rpm), float(definition.reference), float(definition.lower), float(definition.upper))
			check(total > 0.0, "Engine/exhaust has a silent RPM interval: " + str(rpm))
	for player in audio.engine_players + audio.exhaust_players:
		check(player.playing, "A continuous engine voice stopped")
		check(player.stream.loop_begin > 0, "The Rust-style wrap crossfade was not installed")
	for voices in [audio.engine_players, audio.exhaust_players]:
		for rpm in [0.0, 1800.0, 9500.0, 10000.0, 10200.0]:
			var weights: Array = audio.layer_weights(voices, rpm)
			var sum := 0.0
			for weight in weights:
				sum += float(weight)
			check(absf(sum - 1.0) < 0.0001, "Sampler edge weights do not sum to one")
			if rpm >= 9500.0:
				check(weights[-1] == 1.0 and weights[0] == 0.0, "High RPM falls back to idle sample")
		var low_weights: Array = audio.layer_weights(voices, 2000.0)
		check(low_weights[1] == 1.0, "2000 RPM does not select the low recording reference")
	var policy := VehicleAudioMixPolicy.new()
	var packet := snapshot.duplicate(true)
	packet.throttle = 0.0
	var mix := policy.accept(packet)
	check(absf(float(mix.engine_gain) - 0.279) < 0.0001, "Rust engine coast/headroom law changed")
	packet = packet.duplicate(true)
	packet.sequence += 1
	packet.gear = 0
	policy.accept(packet)
	packet = packet.duplicate(true)
	packet.sequence += 1
	packet.gear = 1
	check(policy.accept(packet).events.has("neutral_first"), "Neutral-first edge is missing")
	var powertrain := VehiclePowertrainModel.new()
	powertrain.configure(vehicle.simulation.domains)
	powertrain.automatic_transmission = true
	check(powertrain.request_shift(1), "Automatic transmission blocks its own shift requests")
	var course := RallyStageProgress.new()
	course.points.assign([Vector3.ZERO, Vector3(20, 0, 0), Vector3(40, 0, 0)])
	course.advance(Vector3.ZERO, 0.1, 0, 2.0)
	course.advance(Vector3(40, 0, 0), 0.1, 0, 2.0)
	check(not course.finished, "Shortcut to finish awarded a stage time")
	course.advance(Vector3(20, 0, 0), 0.1, 0, 2.0)
	course.advance(Vector3(40, 0, 0), 0.1, 0, 2.0)
	check(course.finished and course.best_s != null, "Ordered course completion did not record time")
	course.advance(Vector3.ZERO, 0.1, 1, 0.0)
	check(not course.finished and course.best_s != null and course.elapsed_s == 0.0, "Reset lost best stage time or retained the running clock")
	await process_frame
	await process_frame
	var capture := root.get_texture().get_image()
	capture.save_png("res://logs/rally/formula_hud_russia.png" if russia else "res://logs/rally/formula_hud_contract.png")
	var samples := capture_effect.get_buffer(capture_effect.get_frames_available())
	var energy := 0.0
	for sample in samples:
		energy += sample.length_squared() * 0.5
	var rms := sqrt(energy / maxf(float(samples.size()), 1.0))
	check(samples.size() > 1024 and rms > 0.00001, "Vehicle audio bus did not produce an audible PCM signal")
	var result := {"passed": failures.is_empty(), "failures": failures, "sequence": snapshot.get("sequence"), "queries": snapshot.get("contact_queries"), "camera_offset_m": offset_after.length(), "audio_driver": AudioServer.get_driver_name(), "audio_frames": samples.size(), "audio_rms": rms, "effective_output_latency_s": AudioServer.get_output_latency()}
	var file := FileAccess.open("res://logs/rally/presentation_audio_contract.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("RALLY_PRESENTATION_AUDIO_CONTRACT ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
