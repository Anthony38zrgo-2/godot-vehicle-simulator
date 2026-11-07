extends SceneTree

func _initialize() -> void:
	call_deferred("run_sweep")

func rms(samples: PackedVector2Array) -> float:
	var energy := 0.0
	for sample in samples:
		energy += sample.length_squared() * 0.5
	return sqrt(energy / maxf(float(samples.size()), 1.0))

func run_sweep() -> void:
	var scene: Node = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.0).timeout
	var vehicle = scene.get_node("FordEscortRS2000")
	var audio = vehicle.get_node("VehicleAudio")
	vehicle.freeze = true
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Vehicle"), capture)
	for player in audio.engine_players + audio.exhaust_players:
		player.stream_paused = true
	await create_timer(0.3).timeout
	capture.clear_buffer()
	await create_timer(0.25).timeout
	var background_rms := rms(capture.get_buffer(capture.get_frames_available()))
	audio.set_physics_process(false)
	audio.acoustic = {"throttle": 0.4, "load": 0.5, "limiter": false}
	var rows: Array = []
	var passed := background_rms < 0.00001 and audio.whine_player == null
	for role in ["engine", "exhaust"]:
		var players: Array[AudioStreamPlayer3D] = audio.engine_players if role == "engine" else audio.exhaust_players
		for player in players:
			player.stream_paused = false
		var minimum := INF
		var maximum := -INF
		for rpm in [1800.0, 2200.0, 2800.0, 3400.0, 4000.0, 4800.0, 5400.0, 6000.0, 8000.0, 9700.0]:
			audio.update_layer(players, rpm, 1.0)
			await create_timer(0.15).timeout
			capture.clear_buffer()
			await create_timer(0.3).timeout
			var level := rms(capture.get_buffer(capture.get_frames_available()))
			var db := linear_to_db(maxf(level, 0.0000001))
			minimum = minf(minimum, db)
			maximum = maxf(maximum, db)
			rows.append({"role": role, "rpm": rpm, "rms_db": db})
		passed = passed and maximum - minimum < 6.0
		print("AUDIO_LEVEL_RANGE role=", role, " spread_db=", maximum - minimum)
		for player in players:
			player.stream_paused = true
	var result := {"passed": passed, "background_rms_without_engine": background_rms, "synthetic_whine_present": audio.whine_player != null, "rows": rows}
	var file := FileAccess.open("res://logs/rally/audio_level_sweep.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("AUDIO_LEVEL_SWEEP passed=", passed, " background_rms=", background_rms)
	quit(0 if passed else 1)
