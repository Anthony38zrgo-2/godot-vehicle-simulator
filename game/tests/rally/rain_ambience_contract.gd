extends SceneTree

## Regression: light rain must stay audible. The rain ambience HPF and gain
## both follow precipitation; before the fix a 2.5 mm/h shower produced a
## ~683 Hz high-pass and -13 dB gain, which removed most of the sample body.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_contract")


func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)


func settle(audio: Node, precip_mm_h: float) -> void:
	audio.vehicle.simulation.last_local_conditions = [{"climate": {"precipitation_mm_h": precip_mm_h}}]
	for i in 4:
		audio.update_rain_ambience(1.0)


func run_contract() -> void:
	var scene: Node = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 90:
		await physics_frame
	var vehicle = scene.get_node("FordEscortRS2000")
	var audio = vehicle.get_node("VehicleAudio")
	check(audio.rain_ambience_player != null, "Rain ambience player was not built")
	check(audio.rain_ambience_hpf != null, "Rain ambience high-pass was not installed")
	if audio.rain_ambience_player == null or audio.rain_ambience_hpf == null:
		_emit_and_quit({})
		return
	audio.set_physics_process(false)

	settle(audio, 2.5)
	var light_hpf: float = audio.rain_ambience_hpf.cutoff_hz
	var light_gain: float = audio.rain_ambience_player.volume_linear
	check(light_hpf > 200.0 and light_hpf < 400.0, "Light rain HPF is too aggressive: " + str(light_hpf) + " Hz")
	check(light_gain > 0.30, "Light rain gain is inaudible: " + str(light_gain))
	check(not audio.rain_ambience_player.stream_paused, "Light rain ambience is paused")

	settle(audio, 12.0)
	var heavy_hpf: float = audio.rain_ambience_hpf.cutoff_hz
	var heavy_gain: float = audio.rain_ambience_player.volume_linear
	check(heavy_hpf <= 160.0, "Heavy rain HPF did not open up: " + str(heavy_hpf) + " Hz")
	check(heavy_gain > light_gain + 0.25, "Heavy rain is not fuller/louder than light rain")
	check(heavy_gain < 1.0, "Heavy rain ambience clips above unity gain")

	settle(audio, 0.0)
	check(audio.rain_ambience_player.stream_paused, "Dry weather must mute the rain ambience")
	check(audio.rain_ambience_player.volume_linear < 0.0001, "Dry weather leak in rain ambience")

	var result := {
		"passed": failures.is_empty(),
		"failures": failures,
		"light_rain_hpf_hz": light_hpf,
		"light_rain_gain": light_gain,
		"heavy_rain_hpf_hz": heavy_hpf,
		"heavy_rain_gain": heavy_gain,
	}
	_emit_and_quit(result)


func _emit_and_quit(result: Dictionary) -> void:
	var file := FileAccess.open("res://logs/rally/rain_ambience_contract.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "  "))
		file.close()
	print("RAIN_AMBIENCE_CONTRACT ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
