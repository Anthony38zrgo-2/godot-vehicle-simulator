extends SceneTree

const EngineLowMidSynth = preload("res://scripts/audio/engine_lowmid_synth.gd")

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		push_error("LOWMID_SYNTH_CONTRACT FAILURE: " + msg)


func _init() -> void:
	call_deferred("_run")


func _measure_band_energy(buf: PackedVector2Array, sample_rate: float, freq_lo: float, freq_hi: float) -> float:
	var n := mini(buf.size(), 1024)
	if n < 64:
		return 0.0
	var energy := 0.0
	var steps := 12
	for k in steps:
		var freq := lerpf(freq_lo, freq_hi, float(k) / float(maxi(steps - 1, 1)))
		var w := TAU * freq / sample_rate
		var re := 0.0
		var im := 0.0
		for i in n:
			var s := 0.5 * (buf[i].x + buf[i].y)
			var ang := w * float(i)
			re += s * cos(ang)
			im -= s * sin(ang)
		energy += (re * re + im * im) / float(n * n)
	return sqrt(energy / float(steps))


func _capture_stats(cap: AudioEffectCapture) -> Dictionary:
	var n := cap.get_frames_available()
	if n <= 0:
		return {"frames": 0, "rms": 0.0, "peak": 0.0, "finite": true, "buf": PackedVector2Array()}
	var buf := cap.get_buffer(n)
	var sum_sq := 0.0
	var peak := 0.0
	var finite := true
	for s in buf:
		if not is_finite(s.x) or not is_finite(s.y):
			finite = false
			continue
		var mag := maxf(absf(s.x), absf(s.y))
		peak = maxf(peak, mag)
		sum_sq += 0.5 * (s.x * s.x + s.y * s.y)
	return {
		"frames": n,
		"rms": sqrt(sum_sq / float(maxi(n, 1))),
		"peak": peak,
		"finite": finite,
		"buf": buf,
	}


func _drain(cap: AudioEffectCapture) -> void:
	var n := cap.get_frames_available()
	if n > 0:
		cap.get_buffer(n)


func _run() -> void:
	EngineLowMidSynth.reload_config()
	var reg_file := FileAccess.open("res://data/vehicles/registry.json", FileAccess.READ)
	var registry: Dictionary = JSON.parse_string(reg_file.get_as_text()) if reg_file != null else {}
	var vehicles: Dictionary = registry.get("vehicles", {})
	check(vehicles.size() >= 18, "Registry lists all vehicles (got " + str(vehicles.size()) + ")")

	# 1. Verify EVERY registered vehicle resolves its own unique bespoke low-mid synth configuration
	var seen_signatures: Dictionary = {}
	for reg_key in vehicles:
		var entry: Dictionary = vehicles[reg_key]
		var profile_slug := str(entry.get("Profile", "")).get_file()
		var veh_id := str(entry.get("Id", ""))
		var resolved := EngineLowMidSynth.resolve_vehicle_config([profile_slug, veh_id])
		check(not resolved.is_empty(), reg_key + ": resolves active lowmid synth config (slug=" + profile_slug + ")")
		check(str(resolved.get("_resolved_key", "")) == profile_slug, reg_key + ": matched dedicated vehicle entry '" + profile_slug + "' (got '" + str(resolved.get("_resolved_key", "")) + "')")
		var aux_mult := float(resolved.get("aux_order_mult", 0.0))
		check(is_equal_approx(aux_mult, 0.5) or is_equal_approx(aux_mult, 1.5), reg_key + ": aux_order_mult is 0.5 or 1.5 (got " + str(aux_mult) + ")")
		var sig := "%.1f|%.1f|%.2f|%.2f|%.1f|%.2f|%.1f|%.1f|%.1f" % [
			float(resolved.get("orders_per_rev", 0.0)),
			aux_mult,
			float(resolved.get("aux_order_gain", 0.0)),
			float(resolved.get("pulse_skew", 0.0)),
			float(resolved.get("body_freq_hz", 0.0)),
			float(resolved.get("body_q", 0.0)),
			float(resolved.get("hpf_hz", 0.0)),
			float(resolved.get("wot_lpf_hz", 0.0)),
			float(resolved.get("max_rpm", 0.0)),
		]
		check(not seen_signatures.has(sig), reg_key + ": has unique acoustic signature (duplicate with " + str(seen_signatures.get(sig, "")) + ")")
		seen_signatures[sig] = reg_key
	print("LOWMID_REGISTRY_UNIQUE count=", seen_signatures.size(), "/", vehicles.size())

	# 2. Verify live instantiation & AudioEffectCapture across all 18 scenes (full sweep on representative families)
	var cam := Camera3D.new()
	var listener := AudioListener3D.new()
	cam.add_child(listener)
	root.add_child(cam)
	cam.make_current()
	listener.make_current()

	var deep_check_keys := ["fulvia", "escort", "rt-lancia-stratos", "porsche911", "rt-porsche-356b-2000gs", "rt-saab-96-v4", "rt-fiat-abarth-1000", "mustang67", "f10070", "gaz24"]
	var mix_rate := AudioServer.get_mix_rate()
	var max_pump_us := 0

	for reg_key in vehicles:
		var entry: Dictionary = vehicles[reg_key]
		var scene_path := "res://scenes/rally/" + str(entry.get("Scene", "")) + ".tscn"
		var packed: PackedScene = load(scene_path)
		check(packed != null, reg_key + ": scene loads (" + scene_path + ")")
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		if inst is RigidBody3D:
			inst.freeze = true
		root.add_child(inst)
		cam.global_position = inst.global_position + Vector3(0.0, 1.3, 3.8)
		await process_frame

		var audio := inst.get_node_or_null("VehicleAudio")
		check(audio != null and audio.lowmid_synth != null and audio.lowmid_synth.enabled, reg_key + ": VehicleAudio.lowmid_synth active")
		if audio == null or audio.lowmid_synth == null:
			inst.free()
			continue

		var synth: EngineLowMidSynth = audio.lowmid_synth
		check(synth.player != null and synth.player.stream is AudioStreamGenerator, reg_key + ": mono AudioStreamGenerator ready")
		check(is_equal_approx((synth.player.stream as AudioStreamGenerator).mix_rate, EngineLowMidSynth.STREAM_RATE_HZ), reg_key + ": runs at 16 kHz")

		if reg_key in deep_check_keys:
			var synth_bus_idx := AudioServer.get_bus_index(synth.synth_bus)
			check(synth_bus_idx >= 0, reg_key + ": dedicated bus exists")
			var cap := AudioEffectCapture.new()
			AudioServer.add_bus_effect(synth_bus_idx, cap)
			audio.set_physics_process(false)
			audio.view_engine_gain = 1.0
			audio.view_exhaust_gain = 0.8

			var idle_r := synth._idle_rpm
			var max_r := synth._max_rpm
			var mid_r := lerpf(idle_r, max_r, 0.42)
			var high_r := lerpf(idle_r, max_r, 0.82)
			var shift_r := lerpf(idle_r, max_r, 0.72)
			var overrun_r := lerpf(idle_r, max_r, 0.64)

			var phases := [
				{"name": "idle", "rpm": idle_r, "throttle": 0.0, "load": 0.08, "tq": 0.04, "lim": 0.0},
				{"name": "mid_wot", "rpm": mid_r, "throttle": 1.0, "load": 0.95, "tq": 0.92, "lim": 0.0},
				{"name": "shift_cut", "rpm": shift_r, "throttle": 0.0, "load": 0.05, "tq": -0.15, "lim": 0.0},
				{"name": "high_wot", "rpm": high_r, "throttle": 1.0, "load": 0.95, "tq": 0.88, "lim": 0.0},
				{"name": "overrun", "rpm": overrun_r, "throttle": 0.0, "load": 0.30, "tq": -0.35, "lim": 0.0},
				{"name": "limiter", "rpm": max_r + 50.0, "throttle": 1.0, "load": 0.90, "tq": 0.30, "lim": 0.95},
			]

			var rms_by_phase: Dictionary = {}
			for ph in phases:
				audio.acoustic = {
					"rpm": ph["rpm"],
					"throttle": ph["throttle"],
					"load": ph["load"],
					"normalized_torque": ph["tq"],
					"limiter_cut": ph["lim"],
				}
				for _w in 10:
					var t0 := Time.get_ticks_usec()
					synth.update(audio.acoustic, ph["rpm"], 1.0 / 60.0, 1.0, 0.8, 0.0, 0.0, audio)
					max_pump_us = maxi(max_pump_us, Time.get_ticks_usec() - t0)
					OS.delay_msec(10)
					await process_frame
				_drain(cap)
				for _m in 30:
					synth.update(audio.acoustic, ph["rpm"], 1.0 / 60.0, 1.0, 0.8, 0.0, 0.0, audio)
					OS.delay_msec(10)
					await process_frame
					if cap.get_frames_available() >= 2048:
						break
				var stats := _capture_stats(cap)
				rms_by_phase[ph["name"]] = stats["rms"]
				check(stats["finite"], reg_key + "/" + ph["name"] + ": finite samples")
				check(stats["frames"] > 128, reg_key + "/" + ph["name"] + ": captured frames")
				check(stats["rms"] > 0.002 and stats["rms"] < 0.45, reg_key + "/" + ph["name"] + ": healthy RMS (" + str(stats["rms"]) + ")")
				check(stats["peak"] <= 0.96, reg_key + "/" + ph["name"] + ": no clipping (" + str(stats["peak"]) + ")")

				if ph["name"] == "mid_wot":
					var lowmid_e := _measure_band_energy(stats["buf"], mix_rate, 40.0, 380.0)
					var high_e := _measure_band_energy(stats["buf"], mix_rate, 900.0, 2600.0)
					var ratio := lowmid_e / maxf(high_e, 1e-6)
					print("LOWMID_CAR ", reg_key, " ord=", synth._orders_per_rev, " body=", synth._body_freq_hz, " mid_rms=", snappedf(stats["rms"], 0.0001), " crossover=", snappedf(ratio, 0.1))
					check(ratio >= 4.0, reg_key + ": strong low-mid focus vs >900 Hz (ratio=" + str(ratio) + ")")

			check(float(rms_by_phase.get("mid_wot", 0.0)) > float(rms_by_phase.get("idle", 0.0)) * 1.25, reg_key + ": WOT > idle")
			check(float(rms_by_phase.get("shift_cut", 0.0)) >= float(rms_by_phase.get("mid_wot", 0.0)) * 0.25, reg_key + ": shift_cut continuity")
			check(float(rms_by_phase.get("limiter", 0.0)) >= float(rms_by_phase.get("high_wot", 0.0)) * 0.35, reg_key + ": limiter continuity")
			AudioServer.remove_bus_effect(synth_bus_idx, AudioServer.get_bus_effect_count(synth_bus_idx) - 1)

		inst.free()

	print("LOWMID_PERF max_update_us=", max_pump_us)
	check(max_pump_us < 2500, "Low CPU cost per update (< 2.5 ms, got " + str(max_pump_us) + " us)")
	cam.free()
	_finish()


func _finish() -> void:
	var result := {"passed": failures.is_empty(), "failures": failures}
	print("LOWMID_SYNTH_CONTRACT ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
