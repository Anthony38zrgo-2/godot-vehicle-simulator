class_name VehicleAudioMixPolicy
extends RefCounted

# Reinterpretation of vehicle-audio-engine/state.rs and mixer.rs. Ford ranges
# replace the V10 bank's RPM axis; the shared gain/bed laws are preserved.
var sequence: int = -1
var generation: int = -1
var previous: Dictionary = {}
var backfire_cooldown: float = 0.0
var limiter_cooldown: float = 0.0
var mix: Dictionary = {}

func accept(packet: Dictionary) -> Dictionary:
	if packet.is_empty():
		return mix
	if generation != int(packet.generation):
		generation = int(packet.generation)
		sequence = -1
		previous = {}
		backfire_cooldown = 0.0
		limiter_cooldown = 0.0
	if int(packet.sequence) <= sequence:
		return mix
	sequence = int(packet.sequence)
	var dt := float(packet.dt_s)
	backfire_cooldown = maxf(0.0, backfire_cooldown - dt)
	limiter_cooldown = maxf(0.0, limiter_cooldown - dt)
	var rpm := float(packet.rpm)
	var throttle := clampf(float(packet.throttle), 0.0, 1.0)
	var maximum := maxf(float(packet.rpm_max), 1.0)
	var slip := 0.0
	var surface := "Unknown"
	var highest_load := 0.0
	for wheel in packet.get("wheels", []):
		slip = maxf(slip, maxf(absf(float(wheel.slip_ratio)), absf(float(wheel.slip_angle_rad))))
		if float(wheel.load_n) > highest_load:
			highest_load = float(wheel.load_n)
			surface = str(wheel.surface)
	var events: Array[String] = []
	var limiter := rpm > maximum
	if not previous.is_empty():
		if (int(previous.gear) == 0 and int(packet.gear) == 1) or (int(previous.gear) == 1 and int(packet.gear) == 0):
			events.append("neutral_first")
		if float(previous.throttle) >= 0.8 and throttle <= 0.15 and rpm / maximum >= 13500.0 / 17500.0 and backfire_cooldown <= 0.0:
			events.append("backfire")
			backfire_cooldown = 1.0
		if limiter and float(previous.rpm) <= float(previous.rpm_max) and limiter_cooldown <= 0.0:
			events.append("limiter")
			limiter_cooldown = 0.25
	var surface_key := ""
	match surface.to_lower():
		"grass": surface_key = "surf_grass"
		"sand", "gravel": surface_key = "surf_sand"
		"rumble", "curb": surface_key = "surf_rumble"
	var bed_gain := 0.25 + 0.55 * clampf(slip, 0.0, 1.0) + 0.12 * minf(float(packet.speed_kph), 120.0) / 120.0
	mix = {"rpm": rpm, "throttle": throttle, "engine_gain": (0.45 + 0.55 * throttle) * 0.62, "surface": surface_key, "surface_gain": bed_gain if highest_load > 0.0 and float(packet.speed_kph) > 0.5 else 0.0, "slip": slip, "load": float(packet.load), "limiter": limiter, "events": events, "dt": dt}
	previous = packet
	return mix
