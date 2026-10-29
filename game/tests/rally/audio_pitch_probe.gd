extends SceneTree

func _initialize() -> void:
	call_deferred("probe")

func probe() -> void:
	var path := "res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn" if "--russia" in OS.get_cmdline_user_args() else "res://scenes/rally/rally_proving_ground.tscn"
	var scene: Node = load(path).instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 120:
		await physics_frame
	var vehicle = scene.get_node("FordEscortRS2000")
	var audio = vehicle.get_node("VehicleAudio")
	vehicle.shift(1)
	var rows: Array = []
	for frame in 480:
		Input.action_press(InputBindings.THROTTLE, 0.35 if frame < 240 else 1.0)
		await physics_frame
		if frame % 6 != 0:
			continue
		var state: Dictionary = vehicle.get_presentation_snapshot()
		var voices: Array = []
		for player in audio.engine_players + audio.exhaust_players:
			voices.append({"sample": player.stream.resource_path, "role": player.get_meta("role"), "reference": player.get_meta("reference_revolutions"), "pitch": player.pitch_scale, "db": player.volume_db})
		rows.append({"aux": {"scrape": audio.scrape_player.volume_linear, "scrape_paused": audio.scrape_player.stream_paused, "scrub": audio.scrub_player.volume_linear, "scrub_paused": audio.scrub_player.stream_paused, "surface": audio.surface_players["surf_sand"].volume_linear, "impacts": audio.impact_index}, "body_contacts": vehicle.body_contact_audio.duplicate(), "t": frame / 120.0, "rpm": state.rpm, "speed_kph": state.speed_kph, "audio_rpm": audio.smoothed_revolutions, "voices": voices})
	Input.action_release(InputBindings.THROTTLE)
	var file := FileAccess.open("res://logs/rally/audio_pitch_probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "  "))
	file.close()
	print("AUDIO_PITCH_PROBE rows=", rows.size())
	quit()
