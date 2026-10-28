class_name VehicleSimulation
extends RefCounted

var tire_model := TireModel.new()
var tire_relaxation_states: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var tire_temperatures_celsius: Array[float] = [25.0, 25.0, 25.0, 25.0]
var engine_temperature_celsius := 85.0

func configure(tire_data: Dictionary) -> void:
	tire_model.parameters = tire_data.get("tires", {})

func advance_tire_filter(index: int, target_slip: Vector2, speed: float, delta: float, filter_data: Dictionary) -> Vector2:
	var axle_name := "front" if index < 2 else "rear"
	var axle_filter: Dictionary = filter_data.get("tire_filters", {}).get(axle_name, {})
	var relaxation_length := 0.35
	var minimum_tau := float(axle_filter.get("min_relaxation_tau_s", 0.01))
	var recovery_scale := float(axle_filter.get("relaxation_recovery_scale", 1.2))
	var relaxation_tau := maxf(relaxation_length / maxf(speed, 4.0), clampf(minimum_tau, 0.0, 0.5))
	var state := tire_relaxation_states[index]
	for axis in 2:
		var recovery := absf(target_slip[axis]) < absf(state[axis])
		var tau := relaxation_tau * (recovery_scale if recovery else 1.0)
		var interpolation := 1.0 - exp(-delta / maxf(tau, 0.000001))
		state[axis] += (target_slip[axis] - state[axis]) * interpolation
	tire_relaxation_states[index] = state
	return state

func advance_tire_temperature(index: int, friction_power_watts: float, ambient_celsius: float, delta: float) -> float:
	var tire_heat_capacity := 900.0
	var cooling_coefficient := 25.0
	tire_temperatures_celsius[index] = clampf(tire_temperatures_celsius[index] + (friction_power_watts * 0.3 - cooling_coefficient * (tire_temperatures_celsius[index] - ambient_celsius)) / tire_heat_capacity * delta, ambient_celsius, 150.0)
	return tire_temperatures_celsius[index]
