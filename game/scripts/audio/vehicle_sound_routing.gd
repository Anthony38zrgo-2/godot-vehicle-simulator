class_name VehicleSoundRouting
extends RefCounted

const FORD_MANIFEST_PATH := "res://sounds/banks/ford_escort_rs2000_rally/manifest.json"

var config: Dictionary = {}
# Per-voice space (EQ, filters, reverb, lateral offset) and loop points, read
# from the bank manifest, which is the sample source of truth for the bank.
var space: Dictionary = {}
var loops: Dictionary = {}

func _init() -> void:
	var file := FileAccess.open("res://data/rally/audio_mixer.json", FileAccess.READ)
	if file != null:
		var loaded: Variant = JSON.parse_string(file.get_as_text())
		if loaded is Dictionary:
			config = loaded
	_load_bank_manifest(FORD_MANIFEST_PATH)

func _load_bank_manifest(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return
	for sample in parsed.get("samples", []):
		if not (sample is Dictionary) or not sample.has("file"):
			continue
		var key := str(sample["file"]).get_basename()
		if sample.has("space"):
			space[key] = sample["space"]
		if sample.has("loop"):
			loops[key] = sample["loop"]

func _deep_merge(target: Dictionary, patch: Dictionary) -> void:
	for key in patch:
		if target.has(key) and target[key] is Dictionary and patch[key] is Dictionary:
			_deep_merge(target[key], patch[key])
		else:
			target[key] = patch[key].duplicate(true) if patch[key] is Dictionary or patch[key] is Array else patch[key]

func settings(key: String) -> Dictionary:
	var value: Dictionary = config.get("defaults", {}).duplicate(true)
	_deep_merge(value, space.get(key, {}))
	_deep_merge(value, config.get("sounds", {}).get(key, {}))
	return value

func loop_for(key: String) -> Dictionary:
	return loops.get(key, {})

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
		# Band allocation: high-pass / low-pass per voice (the EQ10 has no filters).
		var filter: Dictionary = sound.get("filter", {})
		if filter.has("hpf_hz"):
			var hpf := AudioEffectHighPassFilter.new()
			hpf.cutoff_hz = float(filter["hpf_hz"])
			AudioServer.add_bus_effect(index, hpf)
		if filter.has("lpf_hz"):
			var lpf := AudioEffectLowPassFilter.new()
			lpf.cutoff_hz = float(filter["lpf_hz"])
			AudioServer.add_bus_effect(index, lpf)
		var send: Dictionary = sound.get("reverb", {})
		var reverb: Dictionary = config.get("reverb_buses", {}).get(str(send.get("bus", "")), {})
		if bool(send.get("enabled", false)) and bool(reverb.get("enabled", false)):
			var effect := AudioEffectReverb.new()
			effect.predelay_msec = float(reverb.get("pre_delay_ms", 0.0))
			effect.damping = float(reverb.get("damping", 0.5))
			effect.room_size = clampf(float(reverb.get("decay_s", 0.5)) / 2.0, 0.0, 1.0)
			effect.spread = float(reverb.get("stereo_width", 0.5))
			effect.hipass = clampf(float(reverb.get("low_cut_hz", 0.0)) / 1000.0, 0.0, 1.0)
			effect.dry = 1.0
			effect.wet = db_to_linear(float(send.get("send_db", -120.0)) + float(reverb.get("wet_db", 0.0)))
			AudioServer.add_bus_effect(index, effect)
	player.bus = bus
	# Track the applied offset per player so rerouting is idempotent.
	var lateral := float(sound.get("lateral_x", 0.0))
	var previous_offset := float(player.get_meta("rally_audio_lateral_offset", 0.0))
	player.position.x += lateral - previous_offset
	player.set_meta("rally_audio_lateral_offset", lateral)
