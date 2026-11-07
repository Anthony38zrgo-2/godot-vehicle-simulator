class_name VehicleAudioMixPolicy
extends RefCounted

# Reinterpretation of vehicle-audio-engine/state.rs and mixer.rs. Ford ranges
# replace the V10 bank's RPM axis; the shared gain/bed laws are preserved.
const LIFT_ARMED_THROTTLE := 0.8
const LIFT_FIRED_THROTTLE := 0.15
# Backfire RPM window, relative to the car's own rev range: from an
# intermediate regime up to maximum (the V10 lift_edge at 13500/17500 is the
# same idea: top-of-range overrun only, never low-RPM puttering).
const BACKFIRE_MIN_NORMALIZED_RPM := 0.55
var sequence: int = -1
var generation: int = -1
var previous: Dictionary = {}
var backfire_cooldown: float = 0.0
var limiter_cooldown: float = 0.0
var lift_armed: bool = false
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
		lift_armed = false
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
	for wheel in packet.get("wheels", []):
		slip = maxf(slip, maxf(absf(float(wheel.slip_ratio)), absf(float(wheel.slip_angle_rad))))
	var events: Array[String] = []
	var limiter := rpm > maximum
	# Physical cut depth, same band the powertrain model uses to ramp torque
	# to zero (max*0.025 below maximum): 0 under the band, 1 at/above max.
	# The limiter loop gain follows this instead of a binary gate.
	var rev_limit_band := maxf(maximum * 0.025, 100.0)
	var limiter_cut := 1.0 - clampf((maximum - rpm) / rev_limit_band, 0.0, 1.0)
	# Engine disconnected from the gearbox: clutch open, mid-shift, or neutral.
	# The whole gearbox group (gear clunks + transmission whine) only sounds here.
	var clutch_open := float(packet.get("clutch_engagement", 1.0)) < 0.5 or int(packet.gear) == 0 or str(packet.get("shift_phase", "idle")) != "idle"
	# Lift latch: the packet throttle is smoothed, so a full-to-zero lift
	# never lands inside a single frame pair. Arm at high throttle, fire on
	# the release while RPM is still inside the backfire window.
	if throttle >= LIFT_ARMED_THROTTLE:
		lift_armed = true
	if not previous.is_empty():
		if (int(previous.gear) == 0 and int(packet.gear) == 1) or (int(previous.gear) == 1 and int(packet.gear) == 0):
			events.append("neutral_first")
		# Gearbox event edges mirror the Grand Prix sampler trigger events
		# (upshift_cut_entry / downshift_cut_entry): any confirmed gear step
		# fires the matching single-variant group. N<->1 additionally keeps
		# its neutral_first contact layer on top.
		if int(packet.gear) > int(previous.gear):
			events.append("upshift")
		elif int(packet.gear) < int(previous.gear):
			events.append("downshift")
		if lift_armed and throttle <= LIFT_FIRED_THROTTLE and rpm / maximum >= BACKFIRE_MIN_NORMALIZED_RPM and backfire_cooldown <= 0.0:
			events.append("backfire")
			backfire_cooldown = 1.0
			lift_armed = false
		if limiter and float(previous.rpm) <= float(previous.rpm_max) and limiter_cooldown <= 0.0:
			events.append("limiter")
			limiter_cooldown = 0.25
	mix = {"rpm": rpm, "throttle": throttle, "engine_gain": (0.45 + 0.55 * throttle) * 0.62, "slip": slip, "load": float(packet.load), "limiter": limiter, "limiter_cut": limiter_cut, "rpm_max": maximum, "clutch_open": clutch_open, "events": events, "dt": dt}
	previous = packet
	return mix
