class_name VehicleBrakeModel
extends RefCounted

var maximum_brake_torque_nm: float = 0.0
var front_brake_bias: float = 0.5
var handbrake_torque_fraction: float = 0.0
var handbrake_rear_only: bool = true
var pedal_exponent: float = 1.32
var proportioning_knee: float = 0.68
var proportioning_slope: float = 0.55
var smoothed_service_input: float = 0.0
var smoothed_handbrake_input: float = 0.0


func configure(domains: Dictionary) -> void:
	var brakes: Dictionary = domains.get("brakes", { }).get("brakes", { })
	var powertrain: Dictionary = domains.get("powertrain", { }).get("powertrain", { })
	var aids: Dictionary = domains.get("driving_assistance", { }).get("aids", { })
	maximum_brake_torque_nm = float(brakes.get("max_brake_torque", 0.0))
	front_brake_bias = clampf(float(brakes.get("front_brake_bias", 0.5)), 0.0, 1.0)
	handbrake_torque_fraction = float(
		powertrain.get("handbrake_torque_fraction", brakes.get("handbrake_torque_fraction", 1.0))
	)
	handbrake_rear_only = bool(aids.get("handbrake_rear_only", true))
	pedal_exponent = clampf(float(brakes.get("pedal_exponent", 1.32)), 1.0, 2.2)
	proportioning_knee = clampf(float(brakes.get("proportioning_knee", 0.68)), 0.35, 1.0)
	proportioning_slope = clampf(float(brakes.get("proportioning_slope", 0.55)), 0.2, 1.0)
	smoothed_service_input = 0.0
	smoothed_handbrake_input = 0.0


func evaluate(
	brake_input: float,
	handbrake_input: float,
	fade_factors: Array[float],
) -> Array[float]:
	var target_service := pow(clampf(brake_input, 0.0, 1.0), pedal_exponent)
	var target_handbrake := clampf(handbrake_input, 0.0, 1.0)
	var service_rate := 0.38 if target_service > smoothed_service_input else 0.65
	var handbrake_rate := 0.55 if target_handbrake > smoothed_handbrake_input else 0.75
	smoothed_service_input = lerpf(smoothed_service_input, target_service, service_rate)
	if smoothed_service_input < 0.001 and target_service <= 0.0:
		smoothed_service_input = 0.0
	smoothed_handbrake_input = lerpf(smoothed_handbrake_input, target_handbrake, handbrake_rate)
	if smoothed_handbrake_input < 0.001 and target_handbrake <= 0.0:
		smoothed_handbrake_input = 0.0

	var rear_effective_input := smoothed_service_input
	if rear_effective_input > proportioning_knee:
		rear_effective_input = proportioning_knee + (rear_effective_input - proportioning_knee) * proportioning_slope

	var front_total := smoothed_service_input * maximum_brake_torque_nm * front_brake_bias
	var rear_service_total := rear_effective_input * maximum_brake_torque_nm * (
		1.0 - front_brake_bias
	)
	var handbrake_total := smoothed_handbrake_input * maximum_brake_torque_nm * handbrake_torque_fraction
	var front_torque := front_total * 0.5
	var rear_torque := rear_service_total * 0.5
	var result: Array[float] = [front_torque, front_torque, rear_torque, rear_torque]

	if handbrake_rear_only:
		var hb_wheel := handbrake_total * 0.5
		var max_rear_cap := maxf(
			maximum_brake_torque_nm * (1.0 - front_brake_bias) * 0.65,
			hb_wheel * 1.15,
		)
		result[2] = minf(maxf(result[2], hb_wheel) + minf(result[2], hb_wheel) * 0.25, max_rear_cap)
		result[3] = minf(maxf(result[3], hb_wheel) + minf(result[3], hb_wheel) * 0.25, max_rear_cap)
	else:
		var hb_all := handbrake_total * 0.25
		for i in 4:
			result[i] = maxf(result[i], hb_all) + minf(result[i], hb_all) * 0.25

	for i in 4:
		var fade := fade_factors[i] if i < fade_factors.size() else 1.0
		result[i] *= clampf(fade, 0.15, 1.0)
	return result
