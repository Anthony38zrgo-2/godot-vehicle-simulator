class_name VehicleBrakeModel
extends RefCounted

var maximum_brake_torque_nm: float = 0.0
var front_brake_bias: float = 0.5
var handbrake_torque_fraction: float = 0.0
var handbrake_rear_only: bool = true


func configure(domains: Dictionary) -> void:
	var brakes: Dictionary = domains.get("brakes", {}).get("brakes", {})
	var powertrain: Dictionary = domains.get("powertrain", {}).get("powertrain", {})
	var aids: Dictionary = domains.get("driving_assistance", {}).get("aids", {})
	maximum_brake_torque_nm = float(brakes.get("max_brake_torque", 0.0))
	front_brake_bias = clampf(float(brakes.get("front_brake_bias", 0.5)), 0.0, 1.0)
	handbrake_torque_fraction = float(powertrain.get("handbrake_torque_fraction", brakes.get("handbrake_torque_fraction", 1.0)))
	handbrake_rear_only = bool(aids.get("handbrake_rear_only", true))


func evaluate(brake_input: float, handbrake_input: float, fade_factors: Array[float]) -> Array[float]:
	var service_total := clampf(brake_input, 0.0, 1.0) * maximum_brake_torque_nm
	var handbrake_total := clampf(handbrake_input, 0.0, 1.0) * maximum_brake_torque_nm * handbrake_torque_fraction
	var front_torque := service_total * front_brake_bias * 0.5
	var rear_torque := service_total * (1.0 - front_brake_bias) * 0.5
	var result: Array[float] = [front_torque, front_torque, rear_torque, rear_torque]
	if handbrake_rear_only:
		result[2] += handbrake_total * 0.5
		result[3] += handbrake_total * 0.5
	else:
		for i in 4:
			result[i] += handbrake_total * 0.25
	for i in 4:
		var fade := fade_factors[i] if i < fade_factors.size() else 1.0
		result[i] *= clampf(fade, 0.0, 1.0)
	return result
