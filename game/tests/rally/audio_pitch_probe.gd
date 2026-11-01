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
		for voice in audio.engine_voices + audio.exhaust_voices:
			voices.append({"reference": voice.reference_rpm, "pitch": voice.player.pitch_scale, "db": voice.player.volume_db})
		var surfaces: Dictionary = {}
		for key in audio.surface_players:
			surfaces[key] = audio.surface_players[key].volume_linear
		rows.append({"surfaces": surfaces, "rpm": state.rpm, "speed_kph": state.speed_kph, "voices": voices})
	Input.action_release(InputBindings.THROTTLE)
	var file := FileAccess.open("res://logs/rally/audio_pitch_probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "  "))
	file.close()
	print("AUDIO_PITCH_PROBE rows=", rows.size())
	quit()
