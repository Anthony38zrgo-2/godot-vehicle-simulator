class_name VehiclePowertrainModel
extends RefCounted

const GEVP_GEAR_INERTIA := 0.02

var idle_rpm: float = 900.0
var maximum_rpm: float = 7200.0
var peak_torque_nm: float = 0.0
var torque_curve: Array[Vector2] = []
var variable_drag_ratio: float = 0.0
var constant_brake_ratio: float = 0.0
var gear_ratios: Array[float] = []
var reverse_ratio: float = 0.0
var final_drive_ratio: float = 1.0
var engine_inertia_kg_m2: float = 0.1
var clutch_max_torque_nm: float = 0.0
var clutch_max_torque_ratio: float = 1.35
var clutch_out_rpm_offset: float = 600.0
var idle_disengagement_hysteresis_rpm: float = 150.0
var torque_attack_rate_nm_s: float = 0.0
var engine_attack_limited_torque_nm: float = 0.0
var front_wheel_mass_kg: float = 20.0
var front_wheel_radius_m: float = 0.28
var rear_wheel_mass_kg: float = 20.0
var rear_wheel_radius_m: float = 0.28
var front_torque_split: float = 0.0
var clutch_engagement: float = 0.0
var clutch_torque_nm: float = 0.0
var drive_inertia_kg_m2: float = 0.0
var differential_preload_nm: float = 0.0
var differential_power_ratio: float = 0.0
var differential_coast_ratio: float = 0.25
var differential_power_ramp_angle_deg: float = 45.0
var differential_coast_ramp_angle_deg: float = 60.0
var differential_clutches: float = 4.0
var differential_slip_transition_threshold_rad_s: float = 4.0
var current_gear: int = 0
var engine_rpm: float = 0.0
var engine_torque_nm: float = 0.0
var maximum_forward_gear: int = 0
var shift_time_seconds: float = 0.0
var gear_inertia_shift_seconds: float = 0.0
var shift_remaining_seconds: float = 0.0
var automatic_transmission: bool = false


func configure(domains: Dictionary) -> Dictionary:
	var powertrain: Dictionary = domains.get("powertrain", {}).get("powertrain", {})
	idle_rpm = float(powertrain.get("idle_rpm", 900.0))
	maximum_rpm = float(powertrain.get("max_rpm", 7200.0))
	peak_torque_nm = float(powertrain.get("max_torque", 0.0))
	torque_curve.clear()
	var torque_curve_document: Variant = powertrain.get("torque_curve", [])
	if torque_curve_document is Array:
		for point in torque_curve_document:
			if point is Array and point.size() >= 2:
				torque_curve.append(Vector2(float(point[0]), float(point[1])))
	variable_drag_ratio = maxf(float(powertrain.get("variable_drag_ratio", 0.0)), 0.0)
	constant_brake_ratio = maxf(float(powertrain.get("constant_brake_ratio", 0.0)), 0.0)
	reverse_ratio = -absf(float(powertrain.get("reverse_ratio", 3.317)))
	final_drive_ratio = float(powertrain.get("final_drive", 1.0))
	engine_inertia_kg_m2 = float(powertrain.get("motor_moment", 0.1))
	clutch_max_torque_ratio = maxf(float(powertrain.get("max_clutch_torque_ratio", 1.35)), 0.0)
	clutch_max_torque_nm = peak_torque_nm * clutch_max_torque_ratio
	clutch_out_rpm_offset = maxf(float(powertrain.get("clutch_out_rpm_offset", 600.0)), 0.0)
	idle_disengagement_hysteresis_rpm = maxf(float(powertrain.get("idle_disengagement_hysteresis_rpm", 150.0)), 0.0)
	torque_attack_rate_nm_s = maxf(float(powertrain.get("torque_attack_rate_nm_s", 0.0)), 0.0)
	front_torque_split = clampf(float(powertrain.get("front_torque_split", 0.0)), 0.0, 1.0)
	gear_inertia_shift_seconds = maxf(float(powertrain.get("gear_inertia", 0.0)), 0.0)
	var tires: Dictionary = domains.get("tires", {}).get("tires", {})
	var front_tire: Dictionary = tires.get("front", {})
	var rear_tire: Dictionary = tires.get("rear", {})
	front_wheel_mass_kg = maxf(float(front_tire.get("wheel_mass", 20.0)), 0.0)
	front_wheel_radius_m = maxf(float(front_tire.get("radius", 0.28)), 0.05)
	rear_wheel_mass_kg = maxf(float(rear_tire.get("wheel_mass", 20.0)), 0.0)
	rear_wheel_radius_m = maxf(float(rear_tire.get("radius", 0.28)), 0.05)
	shift_time_seconds = float(powertrain.get("shift_time", 0.0))
	automatic_transmission = bool(powertrain.get("automatic_transmission", false))
	var differential: Dictionary = powertrain.get("differential", {})
	differential_preload_nm = float(differential.get("preload_nm", 0.0))
	differential_power_ratio = float(differential.get("clutch_friction_coefficient", 0.0))
	differential_coast_ratio = differential_power_ratio
	differential_power_ramp_angle_deg = float(differential.get("power_ramp_angle_deg", 45.0))
	differential_coast_ramp_angle_deg = float(differential.get("coast_ramp_angle_deg", 60.0))
	differential_clutches = float(differential.get("clutches", 4.0))
	differential_slip_transition_threshold_rad_s = maxf(float(differential.get("slip_transition_threshold_rad_s", 4.0)), 0.01)
	gear_ratios.clear()
	var ratios: Variant = powertrain.get("gear_ratios", [])
	if not ratios is Array or ratios.is_empty():
		return {"ok": false, "error": "powertrain.gear_ratios must contain at least one forward ratio."}
	for ratio in ratios:
		gear_ratios.append(float(ratio))
	maximum_forward_gear = gear_ratios.size()
	engine_rpm = idle_rpm
	engine_attack_limited_torque_nm = 0.0
	clutch_engagement = 0.0
	clutch_torque_nm = 0.0
	drive_inertia_kg_m2 = 0.0
	return {"ok": true}


func request_shift(delta_gears: int) -> bool:
	if shift_remaining_seconds > 0.0:
		return false
	var target_gear := clampi(current_gear + delta_gears, -1, maximum_forward_gear)
	if target_gear == current_gear:
		return false
	if target_gear < 0 and current_gear >= 0:
		target_gear = -1
	current_gear = target_gear
	shift_remaining_seconds = shift_time_seconds + gear_inertia_shift_seconds
	return true


func set_gear(target_gear: int) -> void:
	current_gear = clampi(target_gear, -1, maximum_forward_gear)
	shift_remaining_seconds = shift_time_seconds + gear_inertia_shift_seconds


func gear_ratio() -> float:
	if current_gear == -1:
		return reverse_ratio
	if current_gear <= 0:
		return 0.0
	return gear_ratios[current_gear - 1] if current_gear <= gear_ratios.size() else 1.0


func engine_torque_at_rpm(rpm: float, throttle: float, thermal_derating: float = 1.0) -> float:
	var throttle_value := clampf(throttle, 0.0, 1.0)
	var rpm_fraction := clampf(rpm / maxf(maximum_rpm, 1.0), 0.0, 1.0)
	var positive_torque := _evaluate_torque_curve(rpm_fraction) * peak_torque_nm * throttle_value * clampf(thermal_derating, 0.0, 1.0)
	var variable_drag := rpm_fraction * peak_torque_nm * variable_drag_ratio
	var constant_brake := peak_torque_nm * constant_brake_ratio * (1.0 - throttle_value)
	return positive_torque - variable_drag - constant_brake


func advance(
		delta: float,
		throttle: float,
		clutch_engagement_input: float,
		rear_wheel_speeds: Vector2,
		thermal_derating: float,
		rear_tire_reaction_torques: Vector2 = Vector2.ZERO,
		front_wheel_speeds: Vector2 = Vector2.ZERO,
		front_tire_reaction_torques: Vector2 = Vector2.ZERO) -> void:
	var dt := maxf(delta, 0.00001)
	shift_remaining_seconds = maxf(0.0, shift_remaining_seconds - dt)
	_advance_engine_torque(dt, throttle, thermal_derating)
	var engine_inertia := maxf(engine_inertia_kg_m2, 0.000001)
	engine_rpm = clampf(engine_rpm + engine_torque_nm / engine_inertia * dt * 60.0 / TAU, idle_rpm, maximum_rpm)
	if current_gear == 0:
		clutch_engagement = 0.0
		clutch_torque_nm = 0.0
		drive_inertia_kg_m2 = 0.0
		return

	# The vehicle adapter reports clutch engagement (1 = coupled); Open Formula's
	# Rust input stores pedal travel (1 = disengaged), so invert it here.
	var manual_clutch_pedal := 1.0 - clampf(clutch_engagement_input, 0.0, 1.0)
	var shift_clutch := 1.0 if shift_remaining_seconds > 0.0 else 0.0
	var clutch_out_rpm := idle_rpm + clutch_out_rpm_offset
	var idle_floor_rpm := idle_rpm + idle_disengagement_hysteresis_rpm
	var idle_disengagement := 0.0
	if engine_rpm <= idle_floor_rpm:
		idle_disengagement = 1.0
	elif engine_rpm < clutch_out_rpm:
		idle_disengagement = (clutch_out_rpm - engine_rpm) / maxf(clutch_out_rpm - idle_floor_rpm, 0.000001)
	var clutch_disengagement := maxf(maxf(manual_clutch_pedal, shift_clutch), idle_disengagement)
	clutch_engagement = 1.0 - clampf(clutch_disengagement, 0.0, 1.0)

	var total_ratio := gear_ratio() * final_drive_ratio
	if absf(total_ratio) <= 0.000001:
		clutch_engagement = 0.0
		clutch_torque_nm = 0.0
		drive_inertia_kg_m2 = 0.0
		return
	var driven_wheel_inertia := 0.0
	var drivetrain_spin := 0.0
	var driven_reaction_torque := 0.0
	var driven_wheel_count := 0
	if front_torque_split > 0.0:
		driven_wheel_inertia += front_wheel_mass_kg * front_wheel_radius_m * front_wheel_radius_m
		drivetrain_spin += front_wheel_speeds.x + front_wheel_speeds.y
		driven_reaction_torque += front_tire_reaction_torques.x + front_tire_reaction_torques.y
		driven_wheel_count += 2
	if front_torque_split < 1.0:
		driven_wheel_inertia += rear_wheel_mass_kg * rear_wheel_radius_m * rear_wheel_radius_m
		drivetrain_spin += rear_wheel_speeds.x + rear_wheel_speeds.y
		driven_reaction_torque += rear_tire_reaction_torques.x + rear_tire_reaction_torques.y
		driven_wheel_count += 2
	var drivetrain_inertia := engine_inertia + total_ratio * total_ratio * GEVP_GEAR_INERTIA + driven_wheel_inertia
	var reflected_inertia := drivetrain_inertia / maxf(total_ratio * total_ratio, 0.00000001)
	var reaction_torque := driven_reaction_torque / total_ratio
	drivetrain_spin /= float(maxi(driven_wheel_count, 1))
	var speed_difference := engine_rpm * TAU / 60.0 - drivetrain_spin * total_ratio
	if speed_difference < 0.0:
		speed_difference = -sqrt(-speed_difference)
	var engine_side_acceleration_term := engine_inertia * reflected_inertia * speed_difference / dt
	var reaction_term := engine_inertia * reaction_torque
	var engine_torque_term := reflected_inertia * engine_torque_nm
	var clutch_factor := clutch_engagement
	var raw_clutch_torque := (engine_side_acceleration_term - reaction_term + engine_torque_term) / maxf(engine_inertia + reflected_inertia, 0.00000001) * clutch_factor
	clutch_max_torque_nm = peak_torque_nm * clutch_max_torque_ratio * clutch_factor
	clutch_torque_nm = clampf(raw_clutch_torque, -clutch_max_torque_nm, clutch_max_torque_nm)
	engine_rpm = clampf(engine_rpm - 60.0 / TAU * dt * clutch_torque_nm / engine_inertia, idle_rpm, maximum_rpm)
	drive_inertia_kg_m2 = engine_inertia + total_ratio * total_ratio * GEVP_GEAR_INERTIA


func _advance_engine_torque(delta: float, throttle: float, thermal_derating: float) -> void:
	var rpm_fraction := clampf(engine_rpm / maxf(maximum_rpm, 1.0), 0.0, 1.0)
	var positive_target := _evaluate_torque_curve(rpm_fraction) * peak_torque_nm * clampf(throttle, 0.0, 1.0) * clampf(thermal_derating, 0.0, 1.0)
	if torque_attack_rate_nm_s > 0.0 and positive_target > engine_attack_limited_torque_nm:
		engine_attack_limited_torque_nm = minf(positive_target, engine_attack_limited_torque_nm + torque_attack_rate_nm_s * delta)
	else:
		engine_attack_limited_torque_nm = positive_target
	var variable_drag := rpm_fraction * peak_torque_nm * variable_drag_ratio
	var constant_brake := peak_torque_nm * constant_brake_ratio * (1.0 - clampf(throttle, 0.0, 1.0))
	engine_torque_nm = engine_attack_limited_torque_nm - variable_drag - constant_brake


func _evaluate_torque_curve(normalized_rpm: float) -> float:
	var rpm_fraction := clampf(normalized_rpm, 0.0, 1.0)
	if torque_curve.is_empty():
		return 1.0
	if rpm_fraction <= torque_curve[0].x:
		return torque_curve[0].y
	var last_index := torque_curve.size() - 1
	if rpm_fraction >= torque_curve[last_index].x:
		return torque_curve[last_index].y
	for index in range(last_index):
		var first_point := torque_curve[index]
		var second_point := torque_curve[index + 1]
		if rpm_fraction >= first_point.x and rpm_fraction <= second_point.x:
			var fraction := (rpm_fraction - first_point.x) / maxf(second_point.x - first_point.x, 0.000001)
			return lerpf(first_point.y, second_point.y, fraction)
	return torque_curve[last_index].y


func drive_torques(_throttle: float, _clutch_engagement: float, rear_wheel_speeds: Vector2, _thermal_derating: float) -> Array[float]:
	var torques: Array[float] = [0.0, 0.0, 0.0, 0.0]
	if current_gear == 0 or shift_remaining_seconds > 0.0:
		return torques
	var total_ratio := gear_ratio() * final_drive_ratio
	var drive_torque := clutch_torque_nm * total_ratio
	var front_total := drive_torque * front_torque_split
	torques[0] = front_total * 0.5
	torques[1] = front_total * 0.5
	var differential_input := drive_torque * (1.0 - front_torque_split)
	var delta_spin := rear_wheel_speeds.x - rear_wheel_speeds.y
	var ramp_angle_deg := differential_power_ramp_angle_deg if differential_input >= 0.0 else differential_coast_ramp_angle_deg
	var ramp_angle_rad := clampf(deg_to_rad(ramp_angle_deg), deg_to_rad(10.0), deg_to_rad(85.0))
	var ramp_lock_torque := absf(differential_input) / maxf(tan(ramp_angle_rad), 0.01) * maxf(differential_clutches, 1.0) * maxf(differential_power_ratio, 0.0) * 0.90
	var locking_capacity := maxf(differential_preload_nm, 0.0) + ramp_lock_torque
	var delta_torque := locking_capacity * clampf(delta_spin / differential_slip_transition_threshold_rad_s, -1.0, 1.0)
	var torque_cap := absf(differential_input) * 0.5 + maxf(differential_preload_nm, 0.0)
	delta_torque = clampf(delta_torque, -torque_cap, torque_cap)
	torques[2] = differential_input * 0.5 - delta_torque
	torques[3] = differential_input * 0.5 + delta_torque
	return torques


func wheel_is_driven(index: int) -> bool:
	if index < 2:
		return front_torque_split > 0.0
	return front_torque_split < 1.0


func chassis_reaction_torque(torques: Array[float]) -> float:
	return (torques[0] + torques[1] + torques[2] + torques[3]) if torques.size() >= 4 else 0.0
