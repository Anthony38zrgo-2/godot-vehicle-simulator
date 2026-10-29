class_name VehicleSoundRouting
extends RefCounted

var config: Dictionary = {}

func _init() -> void:
	var file := FileAccess.open("res://data/rally/audio_mixer.json", FileAccess.READ)
	if file != null:
		var loaded: Variant = JSON.parse_string(file.get_as_text())
		if loaded is Dictionary:
			config = loaded

func settings(key: String) -> Dictionary:
	var value: Dictionary = config.get("defaults", {}).duplicate(true)
	value.merge(config.get("sounds", {}).get(key, {}), true)
	return value

func route(player: AudioStreamPlayer3D, key: String) -> void:
	var sound := settings(key)
	var bus := "Rally:" + key
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, "Vehicle")
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(float(sound.get("volume", 1.0)), 0.0001)))
		var eq: Dictionary = sound.get("eq", {})
		if bool(eq.get("enabled", false)):
			var effect := AudioEffectEQ10.new()
			var bands: Dictionary = eq.get("bands_db", {})
			for band in effect.get_band_count():
				var frequency: float = [31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0][band]
				var closest := ""
				var difference := INF
				for configured in bands:
					var distance := absf(log(maxf(frequency, 1.0) / maxf(float(configured), 1.0)))
					if distance < difference:
						difference = distance
						closest = str(configured)
				if difference < 0.4:
					effect.set_band_gain_db(band, float(bands[closest]))
			AudioServer.add_bus_effect(index, effect)
			AudioServer.set_bus_volume_db(index, AudioServer.get_bus_volume_db(index) + float(eq.get("output_db", 0.0)))
		var send: Dictionary = sound.get("reverb", {})
		var reverb: Dictionary = config.get("reverb_buses", {}).get(str(send.get("bus", "")), {})
		if bool(send.get("enabled", false)) and bool(reverb.get("enabled", false)):
			var effect := AudioEffectReverb.new()
			effect.predelay_msec = float(reverb.get("pre_delay_ms", 0.0))
			effect.damping = float(reverb.get("damping", 0.5))
			effect.room_size = clampf(float(reverb.get("decay_s", 0.5)) / 2.0, 0.0, 1.0)
			effect.spread = float(reverb.get("stereo_width", 0.5))
			effect.dry = 1.0
			effect.wet = db_to_linear(float(send.get("send_db", -120.0)) + float(reverb.get("wet_db", 0.0)))
			AudioServer.add_bus_effect(index, effect)
	player.bus = bus
