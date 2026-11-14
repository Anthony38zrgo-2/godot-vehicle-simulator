extends SceneTree

const SweepGranularEngineBank = preload("res://scripts/audio/sweep_granular_engine_bank.gd")

const ALL_VEHICLE_SCENES := {
	"ford-escort-rs2000": "res://scenes/rally/ford_escort_rs2000_1971.tscn",
	"lancia-fulvia": "res://scenes/rally/lancia_fulvia.tscn",
	"rt-alfa-giulia-gta": "res://scenes/rally/rt/rt-alfa-giulia-gta.tscn",
	"rt-alpine-a110": "res://scenes/rally/rt/rt-alpine-a110.tscn",
	"rt-fiat-abarth-1000": "res://scenes/rally/rt/rt-fiat-abarth-1000.tscn",
	"rt-lancia-stratos": "res://scenes/rally/rt/rt-lancia-stratos.tscn",
	"rt-lotus-cortina": "res://scenes/rally/rt/rt-lotus-cortina.tscn",
	"rt-mini-cooper-s": "res://scenes/rally/rt/rt-mini-cooper-s.tscn",
	"rt-opel-kadett": "res://scenes/rally/rt/rt-opel-kadett.tscn",
	"rt-saab-96-v4": "res://scenes/rally/rt/rt-saab-96-v4.tscn",
	"rt-volvo-amazon": "res://scenes/rally/rt/rt-volvo-amazon.tscn",
}

var failed := false


func check(cond: bool, msg: String) -> void:
	if not cond:
		failed = true
		push_error("RR3_SWEEP_CONTRACT FAILURE: " + msg)


func _init() -> void:
	call_deferred("_run")


func _measure_capture(cap: AudioEffectCapture) -> Dictionary:
	var n := cap.get_frames_available()
	if n <= 0:
		return {"frames": 0, "rms": 0.0, "peak": 0.0, "finite": true}
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
	}


func _drain(cap: AudioEffectCapture) -> void:
	var n := cap.get_frames_available()
	if n > 0:
		cap.get_buffer(n)


func _run() -> void:
	var used_subbanks: Dictionary = {}
	var used_idles: Dictionary = {}
	var used_profiles: Dictionary = {}

	# 1. Verify manifest inventory, uniqueness, and WAV integrity across all 11 cars
	for key in ALL_VEHICLE_SCENES:
		var packed: PackedScene = load(ALL_VEHICLE_SCENES[key])
		check(packed != null, "Scene missing: " + str(key))
		var inst := packed.instantiate()
		var audio := inst.get_node_or_null("VehicleAudio")
		check(audio != null, "VehicleAudio missing in " + str(key))
		var mpath := str(audio.engine_bank_manifest_path)
		check(mpath == "res://sounds/banks/rr3-bank/vehicles/" + key + ".json", "Unexpected manifest path for " + key + ": " + mpath)
		var bank: Variant = JSON.parse_string(FileAccess.get_file_as_string(mpath))
		check(bank is Dictionary and SweepGranularEngineBank.is_sweep_bank(bank), "Invalid schema 4 sweep manifest: " + mpath)
		if bank is Dictionary:
			used_subbanks[str(bank.get("subbank", ""))] = true
			var idle_path := str(bank.get("idle", {}).get("path", ""))
			check(not used_idles.has(idle_path), "Duplicate idle WAV assigned: " + idle_path)
			used_idles[idle_path] = key
			var rp: Dictionary = bank.get("rpm_profile", {})
			var sig := "%s|%s|%.3f|%.3f" % [str(bank.get("subbank", "")), idle_path, float(rp.get("sweep_rpm_scale", 1.0)), float(rp.get("pitch_character", 1.0))]
			check(not used_profiles.has(sig), "Duplicate acoustic tuning signature: " + sig)
			used_profiles[sig] = key
			for slot in ["idle", "accel", "decel"]:
				var spec: Dictionary = bank.get(slot, {})
				var spath := str(spec.get("path", ""))
				check(FileAccess.get_sha256(spath) == str(spec.get("sha256", "")), "WAV checksum mismatch: " + spath)
		inst.free()

	check(used_idles.size() == 11, "Expected 11 distinct idle WAVs, got " + str(used_idles.size()))
	for sub in ["4cyl_01", "i4_01", "i4_02", "i4_03", "i4_04", "i4_05", "i4_06", "v6_01", "v6_01_v2"]:
		check(used_subbanks.has(sub), "Expected rr3 subbank used: " + sub)
	for rc_idle in [
		"res://sounds/banks/rr3-bank/4cyl_01/4cyl_01_racecar_idle.wav",
		"res://sounds/banks/rr3-bank/i4_01/i4_01_racecar_idle.wav",
		"res://sounds/banks/rr3-bank/i4_02/i4_02_racecar_idle.wav",
		"res://sounds/banks/rr3-bank/v6_01/v6_01_racecar_idle.wav",
		"res://sounds/banks/rr3-bank/i4_05/i4_05_idle2.wav",
	]:
		check(used_idles.has(rc_idle), "Expected racecar/idle2 variant wired: " + rc_idle)

	# 2. Verify live granular PCM generation via AudioEffectCapture on representative cars
	var bus_idx := AudioServer.get_bus_index("Vehicle")
	if bus_idx == -1:
		bus_idx = 0
	var cap := AudioEffectCapture.new()
	AudioServer.add_bus_effect(bus_idx, cap)
	var eff_idx := AudioServer.get_bus_effect_count(bus_idx) - 1

	var cam_rig := Node3D.new()
	var cam := Camera3D.new()
	var listener := AudioListener3D.new()
	cam.add_child(listener)
	cam_rig.add_child(cam)
	root.add_child(cam_rig)
	cam.make_current()
	listener.make_current()

	for key in ["ford-escort-rs2000", "rt-lancia-stratos", "lancia-fulvia", "rt-saab-96-v4", "rt-fiat-abarth-1000", "rt-volvo-amazon"]:
		var scene: Node = load(ALL_VEHICLE_SCENES[key]).instantiate()
		root.add_child(scene)
		if scene is RigidBody3D:
			scene.freeze = true
		var audio := scene.get_node("VehicleAudio")
		audio.set_physics_process(false)
		audio.view_engine_gain = 1.0
		audio.view_exhaust_gain = 1.0
		check(audio.sweep_bank != null, key + ": sweep_bank must instantiate")
		if audio.sweep_bank == null:
			scene.free()
			continue

		var sb = audio.sweep_bank
		# Center listener near vehicle
		cam.global_position = scene.global_position + Vector3(0.0, 1.2, 2.5)
		await process_frame

		# Test Idle, Mid WOT, Redline, and High Overrun
		var rp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(audio.engine_bank_manifest_path)).get("rpm_profile", {})
		var idle_r := float(rp.get("idle_rpm", 900.0))
		var max_r := float(rp.get("max_rpm", 7200.0))

		var phases := [
			{"name": "idle", "rpm": idle_r, "throttle": 0.0, "load": 0.1, "tq": 0.05, "overrun": false},
			{"name": "wot", "rpm": lerpf(idle_r, max_r, 0.58), "throttle": 1.0, "load": 0.95, "tq": 0.95, "overrun": false},
			{"name": "redline", "rpm": max_r * 0.96, "throttle": 1.0, "load": 1.0, "tq": 0.9, "overrun": false},
			{"name": "overrun", "rpm": lerpf(idle_r, max_r, 0.72), "throttle": 0.0, "load": 0.35, "tq": -0.35, "overrun": true},
		]
		for ph in phases:
			# Warm up phase across >1 Dummy mix interval so prior silence/transition tail is flushed before draining
			for warm in 4:
				audio.acoustic = {
					"rpm": ph["rpm"],
					"throttle": ph["throttle"],
					"load": ph["load"],
					"normalized_torque": ph["tq"],
					"engine_gain": 1.0,
					"clutch_engagement": 1.0,
				}
				audio.smoothed_revolutions = float(ph["rpm"])
				sb.update(audio.acoustic, float(ph["rpm"]), 1.0 if warm == 0 else 0.025, 1.0, 1.0, 0.0, {}, audio)
				await create_timer(0.025).timeout
			_drain(cap)
			var step := 0
			while step < 20 and cap.get_frames_available() < 2048:
				sb.update(audio.acoustic, float(ph["rpm"]), 0.025, 1.0, 1.0, 0.0, {}, audio)
				await create_timer(0.025).timeout
				step += 1
			var stats := _measure_capture(cap)
			check(int(stats["frames"]) >= 512, key + " " + ph["name"] + ": insufficient mixed audio frames=" + str(stats["frames"]))
			check(bool(stats["finite"]), key + " " + ph["name"] + ": non-finite PCM frames")
			check(float(stats["rms"]) > 0.002, key + " " + ph["name"] + ": silent PCM capture rms=" + str(stats["rms"]))
			check(float(stats["peak"]) < 0.95, key + " " + ph["name"] + ": clipped PCM peak=" + str(stats["peak"]))
			check(sb.is_overrun == bool(ph["overrun"]), key + " " + ph["name"] + ": overrun flag mismatch")

		scene.queue_free()
		await process_frame
		await process_frame

	AudioServer.remove_bus_effect(bus_idx, eff_idx)
	cam_rig.queue_free()
	await process_frame
	print("RR3_SWEEP_BANK_CONTRACT passed=", not failed, " vehicles=11 idles=", used_idles.size(), " subbanks=", used_subbanks.size())
	quit(1 if failed else 0)
