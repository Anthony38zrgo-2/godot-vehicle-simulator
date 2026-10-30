class_name SeamlessVehicleLoop
extends RefCounted

# PCM16 RIFF loader: smooth the wrap by the Rust core's 512/44100 s window.
# The bank bytes remain untouched. Godot owns audio-thread mixing/resampling.
static func load_pcm(path: String, looping: bool = true, envelope: Dictionary = {}) -> AudioStreamWAV:
	# Exports normally replace WAV sources with imported resources. The build
	# packs an untouched .pcm copy for this RIFF reader and its seamless loops.
	var source_path := path + ".pcm" if FileAccess.file_exists(path + ".pcm") else path
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var rate := 0
	var channels := 0
	var pcm := PackedByteArray()
	var offset := 12
	while offset + 8 <= bytes.size():
		var key := bytes.slice(offset, offset + 4).get_string_from_ascii()
		var length := int(bytes.decode_u32(offset + 4))
		var start := offset + 8
		if start + length > bytes.size():
			return null
		if key == "fmt ":
			if length < 16 or bytes.decode_u16(start) != 1 or bytes.decode_u16(start + 14) != 16:
				return null
			channels = bytes.decode_u16(start + 2)
			rate = bytes.decode_u32(start + 4)
		elif key == "data":
			pcm = bytes.slice(start, start + length)
		offset = start + length + (length % 2)
	if channels < 1 or channels > 2 or rate <= 0 or pcm.is_empty():
		return null
	var frames := int(pcm.size() / (channels * 2))
	var fade := mini(int(512.0 * rate / 44100.0), int(frames / 4)) if looping else 0
	if not looping and bool(envelope.get("enabled", false)):
		var attack := float(envelope.get("attack_ms", 0.0)) * rate / 1000.0
		var decay := float(envelope.get("decay_ms", 0.0)) * rate / 1000.0
		var release := minf(float(envelope.get("release_ms", 0.0)) * rate / 1000.0, frames)
		var sustain := clampf(float(envelope.get("sustain", 1.0)), 0.0, 1.0)
		for frame in frames:
			var gain := sustain
			if attack > 0.0 and frame < attack:
				gain = float(frame) / attack
			elif decay > 0.0 and frame < attack + decay:
				gain = lerpf(1.0, sustain, (float(frame) - attack) / decay)
			if release > 0.0 and frame > frames - release:
				gain *= maxf(float(frames - 1 - frame) / release, 0.0)
			for channel in channels:
				var address := (frame * channels + channel) * 2
				pcm.encode_s16(address, roundi(float(pcm.decode_s16(address)) * gain))
	for frame in fade:
		var alpha := float(frame) / maxf(float(fade - 1), 1.0)
		for channel in channels:
			var tail := ((frames - fade + frame) * channels + channel) * 2
			var head := (frame * channels + channel) * 2
			pcm.encode_s16(tail, roundi(lerpf(float(pcm.decode_s16(tail)), float(pcm.decode_s16(head)), alpha)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = channels == 2
	stream.data = pcm
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
	stream.loop_begin = fade
	stream.loop_end = frames
	return stream
