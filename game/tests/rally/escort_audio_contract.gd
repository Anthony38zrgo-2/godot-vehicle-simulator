extends SceneTree

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func energy(voices: Array) -> float:
	var total := 0.0
	for voice in voices:
		total += voice.player.volume_linear * voice.player.volume_linear
	return total

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://sounds/banks/EscortRS1600/manifest.json"))
	check(manifest.samples.size() == 35, "Escort source inventory incomplete")
	for sample in manifest.samples:
		var path: String = "res://sounds/banks/EscortRS1600/" + str(sample.file)
		check(FileAccess.get_sha256(path) == sample.source_sha256, "Source bytes changed: " + path)
		var stream := SeamlessVehicleLoop.load_pcm(path, false)
		check(stream != null and stream.mix_rate == int(sample.mix_rate_hz), "Native PCM failed: " + path)
	var scene: Node = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	var audio = scene.get_node("FordEscortRS2000/VehicleAudio")
	audio.set_physics_process(false)
	check(audio.engine_voices.size() == 6 and audio.exhaust_voices.size() == 6, "Loaded layers missing")
	check(audio.coast_engine_voices.size() == 5 and audio.coast_exhaust_voices.size() == 5, "Coast layers missing")
	check(audio.whine_players.size() == 2 and audio.backfire_players.size() == 4, "Auxiliary samples missing")
	check(audio.upshift_players.is_empty() and audio.downshift_players.is_empty(), "Shift pool missing")
	audio.update_view_balance()
	check(audio.onboard_upshift_players.is_empty() and audio.onboard_downshift_players.is_empty(), "WRC onboard pool missing")
	check(audio.extra_upshift_players.size() == 2 and audio.extra_downshift_players.size() == 2, "Commons shift layers missing")
	check(audio.camera_rig != null, "Camera rig unavailable for onboard gating")
	if audio.camera_rig != null:
		audio.clunk_scale = 1.0
		for mode in [0, 1, 2]:
			audio.camera_rig.camera_mode = mode
			audio.play_neutral_event(true)
			check(audio.neutral_player.playing, "Neutral transition did not play in camera mode " + str(mode))
			var expected_db := 2.0 - AudioServer.get_bus_volume_db(AudioServer.get_bus_index(audio.neutral_player.bus)) if mode == 2 else -11.0 + linear_to_db(0.75 * 0.85 * 2.0)
			check(absf(audio.neutral_player.volume_db - expected_db) < 0.001, "Neutral camera gain incorrect")
			audio.upshift_cooldown = 0.0
			audio.downshift_cooldown = 0.0
			audio.update_cockpit_audio(1.0)
			audio.play_upshift_event(2)
			audio.play_downshift_event(1)
			var active := false
			for player in audio.onboard_upshift_players + audio.onboard_downshift_players:
				active = active or player.playing
			check(not active, "Bank shift sounds should be disabled")
			audio.camera_rig.camera_mode = 0
			audio.update_cockpit_audio(1.0)
			for player in audio.onboard_upshift_players + audio.onboard_downshift_players:
				check(not player.playing, "Onboard tail leaked to outside camera")
	for throttle in [0.0, 0.5, 1.0]:
		audio.acoustic = {"throttle": throttle, "load": throttle}
		for rpm in [1050.0, 1500.0, 1800.0, 2400.0, 3000.0, 4200.0, 5500.0, 6800.0, 7500.0]:
			audio.smoothed_revolutions = rpm
			audio.update_layer(audio.engine_voices, rpm, 1.0)
			audio.update_layer(audio.exhaust_voices, rpm, 1.0)
			audio.update_retention_audio(1.0)
			check(energy(audio.engine_voices) + energy(audio.coast_engine_voices) > 0.000001, "Silent engine transition")
			check(energy(audio.exhaust_voices) + energy(audio.coast_exhaust_voices) > 0.000001, "Silent exhaust transition")
			if throttle == 1.0:
				check(energy(audio.coast_engine_voices) < 0.000001, "Coast still audible at full throttle")
			if throttle == 0.0 and rpm >= 3000.0:
				check(energy(audio.engine_voices) < 0.000001, "Loaded bank still audible on coast")
			for voice in audio.engine_voices + audio.exhaust_voices + audio.coast_engine_voices + audio.coast_exhaust_voices:
				check(is_finite(voice.player.volume_linear) and is_finite(voice.player.pitch_scale), "Invalid mix value")
	print("ESCORT_AUDIO_CONTRACT passed=", not failed, " native_samples=35 continuous_layers=22")
	scene.queue_free()
	await process_frame
	quit(1 if failed else 0)
