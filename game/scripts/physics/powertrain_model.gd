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
var clutch_out_rpm_offset: float = 300.0
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
var input_shaft_omega_rad_s: float = 0.0
var gearbox_input_inertia_kg_m2: float = GEVP_GEAR_INERTIA
var clutch_slip_power_w: float = 0.0
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
var pending_gear: int = 0
var shift_phase: String = "idle"
var shift_phase_seconds: float = 0.0
var clutch_release_seconds: float = 0.04
var clutch_reengage_seconds: float = 0.12
var synchronizer_capacity_nm: float = 25.0
var synchronizer_tolerance_rad_s: float = 0.1
var downshift_rev_matching_enabled: bool = false
var downshift_blip_torque_fraction: float = 0.8
var downshift_target_rpm_fraction: float = 0.92
var downshift_blip_response_seconds: float = 0.04
var downshift_blip_tolerance_rpm: float = 25.0
var revmatch_downshift: bool = false
var autoblip_active: bool = false
var autoblip_target_rpm: float = 0.0
var autoblip_throttle: float = 0.0
var driveline_compliance_enabled: bool = false
var output_shaft_inertia_kg_m2: float = 0.2
var output_shaft_omega_rad_s: float = 0.0
var torsional_stiffness_nm_per_rad: float = 8000.0
var torsional_damping_nms_per_rad: float = 120.0
var driveline_twist_rad: float = 0.0
var driveline_torque_nm: float = 0.0
var driveline_energy_j: float = 0.0
var driveline_dissipation_w: float = 0.0


func configure(domains: Dictionary) -> Dictionary:
	var powertrain: Dictionary = domains.get("powertrain", { }).get("powertrain", { })
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
	engine_inertia_kg_m2 = float(powertrain.get("motor_moment", 0.15))
	gearbox_input_inertia_kg_m2 = maxf(
		float(powertrain.get("gearbox_input_inertia_kg_m2", GEVP_GEAR_INERTIA)),
		0.000001,
	)
	clutch_max_torque_ratio = maxf(float(powertrain.get("max_clutch_torque_ratio", 1.35)), 0.0)
	clutch_max_torque_nm = peak_torque_nm * clutch_max_torque_ratio
	clutch_out_rpm_offset = maxf(float(powertrain.get("clutch_out_rpm_offset", 300.0)), 0.0)
	idle_disengagement_hysteresis_rpm = maxf(
		float(powertrain.get("idle_disengagement_hysteresis_rpm", 150.0)),
		0.0,
	)
	torque_attack_rate_nm_s = maxf(float(powertrain.get("torque_attack_rate_nm_s", 0.0)), 0.0)
	front_torque_split = clampf(float(powertrain.get("front_torque_split", 0.0)), 0.0, 1.0)
	gear_inertia_shift_seconds = maxf(float(powertrain.get("gear_inertia", 0.0)), 0.0)
	var tires: Dictionary = domains.get("tires", { }).get("tires", { })
	var front_tire: Dictionary = tires.get("front", { })
	var rear_tire: Dictionary = tires.get("rear", { })
	front_wheel_mass_kg = maxf(float(front_tire.get("wheel_mass", 20.0)), 0.0)
	front_wheel_radius_m = maxf(float(front_tire.get("radius", 0.28)), 0.05)
	rear_wheel_mass_kg = maxf(float(rear_tire.get("wheel_mass", 20.0)), 0.0)
	rear_wheel_radius_m = maxf(float(rear_tire.get("radius", 0.28)), 0.05)
	shift_time_seconds = maxf(float(powertrain.get("shift_time", 0.0)), 0.0)
	clutch_release_seconds = maxf(float(powertrain.get("clutch_release_seconds", 0.04)), 0.001)
	clutch_reengage_seconds = maxf(
		float(
			powertrain.get(
				"clutch_reengage_seconds",
				powertrain.get("downshift_clutch_reengagement_seconds", 0.12),
			)
		),
		0.001,
	)
	synchronizer_capacity_nm = maxf(float(powertrain.get("synchronizer_capacity_nm", 25.0)), 0.001)
	synchronizer_tolerance_rad_s = maxf(
		float(powertrain.get("synchronizer_tolerance_rad_s", 0.1)),
		0.0001,
	)
	automatic_transmission = bool(powertrain.get("automatic_transmission", false))
	downshift_rev_matching_enabled = bool(powertrain.get("downshift_rev_matching_enabled", false))
	downshift_blip_torque_fraction = clampf(
		float(powertrain.get("downshift_blip_torque_fraction", 0.8)),
		0.0,
		1.0,
	)
	downshift_target_rpm_fraction = clampf(
		float(powertrain.get("downshift_maximum_target_revolutions_per_minute_fraction", 0.92)),
		0.0,
		1.0,
	)
	downshift_blip_response_seconds = maxf(
		float(powertrain.get("downshift_blip_response_seconds", 0.04)),
		0.001,
	)
	downshift_blip_tolerance_rpm = maxf(
		float(powertrain.get("downshift_blip_tolerance_rpm", 25.0)),
		0.0,
	)
	var compliance: Dictionary = powertrain.get("driveline_compliance", { })
	driveline_compliance_enabled = bool(compliance.get("enabled", false))
	output_shaft_inertia_kg_m2 = float(compliance.get("output_inertia_kg_m2", 0.2))
	torsional_stiffness_nm_per_rad = float(compliance.get("stiffness_nm_per_rad", 8000.0))
	torsional_damping_nms_per_rad = float(compliance.get("damping_nms_per_rad", 120.0))
	if (
		not is_finite(output_shaft_inertia_kg_m2) or output_shaft_inertia_kg_m2 <= 0.0
		or not is_finite(torsional_stiffness_nm_per_rad) or torsional_stiffness_nm_per_rad <= 0.0
		or not is_finite(torsional_damping_nms_per_rad) or torsional_damping_nms_per_rad < 0.0
	):
		return {
			"ok": false,
			"error": "Driveline compliance requires finite positive inertia/stiffness and nonnegative damping.",
		}
	reset_compliance()
	var differential: Dictionary = powertrain.get("differential", { })
	differential_preload_nm = float(differential.get("preload_nm", 0.0))
	differential_power_ratio = float(differential.get("clutch_friction_coefficient", 0.0))
	differential_coast_ratio = float(
		differential.get("coast_friction_coefficient", differential_power_ratio)
	)
	differential_power_ramp_angle_deg = float(differential.get("power_ramp_angle_deg", 45.0))
	differential_coast_ramp_angle_deg = float(differential.get("coast_ramp_angle_deg", 60.0))
	differential_clutches = float(differential.get("clutches", 4.0))
	differential_slip_transition_threshold_rad_s = maxf(
		float(differential.get("slip_transition_threshold_rad_s", 4.0)),
		0.01,
	)
	gear_ratios.clear()
	var ratios: Variant = powertrain.get("gear_ratios", [])
	if not ratios is Array or ratios.is_empty():
		return {
			"ok": false,
			"error": "powertrain.gear_ratios must contain at least one forward ratio.",
		}
	for ratio in ratios:
		gear_ratios.append(float(ratio))
	maximum_forward_gear = gear_ratios.size()
	engine_rpm = idle_rpm
	engine_attack_limited_torque_nm = 0.0
	clutch_engagement = 0.0
	clutch_torque_nm = 0.0
	input_shaft_omega_rad_s = 0.0
	reset_shift()
	print(
		"RALLY_DRIVELINE_COMPLIANCE ",
		JSON.stringify(
			{
				"enabled": driveline_compliance_enabled,
				"output_inertia_kg_m2": output_shaft_inertia_kg_m2,
				"stiffness_nm_per_rad": torsional_stiffness_nm_per_rad,
				"damping_nms_per_rad": torsional_damping_nms_per_rad,
				"autoblip_enabled": downshift_rev_matching_enabled,
			}
		),
	)
	return { "ok": true }


func reset_compliance() -> void:
	output_shaft_omega_rad_s = 0.0
	driveline_twist_rad = 0.0
	driveline_torque_nm = 0.0
	driveline_energy_j = 0.0
	driveline_dissipation_w = 0.0


func request_shift(delta_gears: int) -> bool:
	if shift_phase != "idle":
		return false
	var target := clampi(current_gear + delta_gears, -1, maximum_forward_gear)
	if target == current_gear:
		return false
	set_gear(target)
	return true


func set_gear(target_gear: int) -> void:
	if shift_phase != "idle":
		return
	pending_gear = clampi(target_gear, -1, maximum_forward_gear)
	if pending_gear == current_gear:
		return
	revmatch_downshift = current_gear > 0 and pending_gear > 0 and pending_gear < current_gear
	shift_phase = "opening"
	shift_phase_seconds = 0.0
	shift_remaining_seconds = clutch_release_seconds + shift_time_seconds + gear_inertia_shift_seconds + clutch_reengage_seconds


func reset_shift() -> void:
	revmatch_downshift = false
	autoblip_active = false
	autoblip_target_rpm = 0.0
	autoblip_throttle = 0.0
	pending_gear = current_gear
	shift_phase = "idle"
	shift_phase_seconds = 0.0
	shift_remaining_seconds = 0.0


func _ratio_for_gear(gear: int) -> float:
	if gear == -1:
		return reverse_ratio
	if gear <= 0:
		return 0.0
	return gear_ratios[gear - 1] if gear <= gear_ratios.size() else 0.0


func gear_ratio() -> float:
	return _ratio_for_gear(current_gear)


func engine_torque_at_rpm(rpm: float, throttle: float, thermal_derating: float = 1.0) -> float:
	var throttle_value := clampf(throttle, 0.0, 1.0)
	var closed_throttle := 1.0 - throttle_value
	var rpm_fraction := clampf(rpm / maxf(maximum_rpm, 1.0), 0.0, 1.25)
	var rev_limit_band := maxf(maximum_rpm * 0.025, 100.0)
	var rev_cut := clampf((maximum_rpm - rpm) / rev_limit_band, 0.0, 1.0)
	var curve_val := _evaluate_torque_curve(clampf(rpm_fraction, 0.0, 1.0))
	var positive_torque := curve_val * peak_torque_nm * throttle_value * clampf(
		thermal_derating,
		0.0,
		1.0,
	) * rev_cut
	var variable_drag := rpm_fraction * peak_torque_nm * variable_drag_ratio * lerpf(
		0.15,
		1.0,
		closed_throttle,
	)
	var constant_brake := peak_torque_nm * constant_brake_ratio * closed_throttle
	var idle_support := 0.0
	if rpm < idle_rpm + 250.0:
		var idle_error := clampf((idle_rpm + 100.0 - rpm) / 250.0, 0.0, 1.5)
		idle_support = (variable_drag + constant_brake) * clampf(idle_error, 0.0, 1.0) + peak_torque_nm * 0.12 * maxf(
			idle_error - 0.4,
			0.0,
		)
	return positive_torque + idle_support - variable_drag - constant_brake


func advance(
	delta: float,
	throttle: float,
	clutch_engagement_input: float,
	thermal_derating: float,
	carrier_omega_rad_s: float = 0.0,
) -> void:
	var dt := maxf(delta, 0.00001)
	shift_phase_seconds += dt
	if shift_phase != "idle":
		shift_remaining_seconds = maxf(dt, shift_remaining_seconds - dt)
	var effective_throttle := _autoblip_command(throttle, thermal_derating, carrier_omega_rad_s, dt)
	_advance_engine_torque(dt, effective_throttle, thermal_derating)
	var engine_inertia := maxf(engine_inertia_kg_m2, 0.000001)
	engine_rpm = clampf(
		engine_rpm + engine_torque_nm / engine_inertia * dt * 60.0 / TAU,
		idle_rpm * 0.65,
		maximum_rpm * 1.25,
	)
	if engine_rpm < idle_rpm and clutch_engagement < 0.05:
		engine_rpm = move_toward(engine_rpm, idle_rpm, 1500.0 * dt)

	var manual_clutch_pedal := 1.0 - clampf(clutch_engagement_input, 0.0, 1.0)
	var shift_clutch := 1.0 if shift_phase == "opening" or shift_phase == "synchronizing" else 0.0
	var clutch_out_rpm := idle_rpm + clutch_out_rpm_offset
	var idle_floor_rpm := idle_rpm + idle_disengagement_hysteresis_rpm
	var idle_disengagement := 0.0
	if engine_rpm <= idle_floor_rpm:
		idle_disengagement = 1.0
	elif engine_rpm < clutch_out_rpm:
		idle_disengagement = (clutch_out_rpm - engine_rpm) / maxf(
			clutch_out_rpm - idle_floor_rpm,
			0.000001,
		)
	var clutch_disengagement := maxf(maxf(manual_clutch_pedal, shift_clutch), idle_disengagement)
	var target_engagement := 1.0 - clampf(clutch_disengagement, 0.0, 1.0)
	var actuation_time := clutch_release_seconds if target_engagement < clutch_engagement else clutch_reengage_seconds
	clutch_engagement = move_toward(clutch_engagement, target_engagement, dt / actuation_time)
	if shift_phase == "opening" and clutch_engagement <= 0.000001:
		clutch_engagement = 0.0
		current_gear = 0
		shift_phase = "synchronizing"
		shift_phase_seconds = 0.0
	elif shift_phase == "closing" and shift_phase_seconds >= clutch_reengage_seconds:
		reset_shift()

	clutch_torque_nm = 0.0


func _autoblip_command(
	driver_throttle: float,
	thermal_derating: float,
	carrier_omega: float,
	dt: float,
) -> float:
	autoblip_active = false
	autoblip_throttle = 0.0
	autoblip_target_rpm = 0.0
	if not downshift_rev_matching_enabled or not revmatch_downshift or shift_phase == "idle":
		return driver_throttle
	var target_omega := _ratio_for_gear(pending_gear) * final_drive_ratio * carrier_omega
	if target_omega <= 0.0:
		return driver_throttle
	autoblip_target_rpm = clampf(
		target_omega * 60.0 / TAU,
		idle_rpm,
		maxf(idle_rpm, maximum_rpm * downshift_target_rpm_fraction),
	)
	if clutch_engagement > 0.05 and shift_phase == "opening":
		return driver_throttle
	var error_rpm := autoblip_target_rpm - engine_rpm
	if error_rpm <= downshift_blip_tolerance_rpm:
		return driver_throttle
	var error_omega := error_rpm * TAU / 60.0
	var desired_torque := maxf(engine_inertia_kg_m2, 0.000001) * error_omega / maxf(
		downshift_blip_response_seconds,
		dt,
	)
	var closed_torque := engine_torque_at_rpm(engine_rpm, 0.0, thermal_derating)
	var available_torque := engine_torque_at_rpm(engine_rpm, 1.0, thermal_derating) - closed_torque
	if available_torque <= 0.000001:
		return driver_throttle
	autoblip_throttle = clampf(
		(desired_torque - closed_torque) / available_torque,
		0.0,
		downshift_blip_torque_fraction,
	)
	autoblip_active = autoblip_throttle > clampf(driver_throttle, 0.0, 1.0)
	return maxf(driver_throttle, autoblip_throttle)


func solve_rotation(
	delta: float,
	spins: Array[float],
	inertias: Array[float],
	tire_torques: Array[float],
	brakes: Array[float],
) -> Dictionary:
	var h := maxf(delta, 0.000001)
	var ie := maxf(engine_inertia_kg_m2, 0.000001)
	var shaft_inertia := gearbox_input_inertia_kg_m2
	var engine_omega := engine_rpm * TAU / 60.0
	var synchronizing := shift_phase == "synchronizing" and pending_gear != 0
	var ratio := (_ratio_for_gear(pending_gear) if synchronizing else gear_ratio()) * final_drive_ratio
	var geared := current_gear != 0 and absf(ratio) > 0.000001
	var connected := geared or synchronizing
	var weights: Array[float] = [
		front_torque_split * 0.5,
		front_torque_split * 0.5,
		(1.0 - front_torque_split) * 0.5,
		(1.0 - front_torque_split) * 0.5,
	]
	var inverse: Array[float] = []
	var brake_impulses: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var brake_work: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var carrier_inverse := 0.0
	var output_inverse := 1.0 / output_shaft_inertia_kg_m2
	var gear_effective_inverse := 1.0 / shaft_inertia
	for i in 4:
		inverse.append(1.0 / maxf(inertias[i], 0.000001))
		spins[i] -= h * tire_torques[i] * inverse[i]
		carrier_inverse += weights[i] * weights[i] * inverse[i]
	gear_effective_inverse += ratio * ratio * (
		output_inverse if driveline_compliance_enabled else carrier_inverse
	)
	var spring_inverse := output_inverse + carrier_inverse
	var implicit_damping := torsional_damping_nms_per_rad + h * torsional_stiffness_nm_per_rad
	var spring_denominator := 1.0 + h * implicit_damping * spring_inverse
	var spring_impulse := 0.0
	var clutch_impulse := 0.0
	var gear_impulse := 0.0
	var lsd_impulse := 0.0
	var clutch_work := 0.0
	var smooth_clutch := clutch_engagement * clutch_engagement * (3.0 - 2.0 * clutch_engagement)
	var clutch_capacity := clutch_max_torque_nm * smooth_clutch * h
	var nominal_sync_time := maxf(shift_time_seconds + gear_inertia_shift_seconds, 0.02)
	var sync_overtime := clampf(shift_phase_seconds / nominal_sync_time, 1.0, 4.0) if synchronizing else 1.0
	var effective_sync_cap := synchronizer_capacity_nm * sync_overtime * h
	var lsd_pair_inv := inverse[2] + inverse[3] + h * differential_slip_transition_threshold_rad_s * 0.35

	for iteration in 48:
		if connected:
			var carrier := 0.0
			for i in 4:
				carrier += weights[i] * spins[i]
			var gear_output := output_shaft_omega_rad_s if driveline_compliance_enabled else carrier
			var impulse := -(input_shaft_omega_rad_s - ratio * gear_output) / gear_effective_inverse
			if synchronizing:
				var next_gear_impulse := clampf(
					gear_impulse + impulse,
					-effective_sync_cap,
					effective_sync_cap,
				)
				impulse = next_gear_impulse - gear_impulse
			input_shaft_omega_rad_s += impulse / shaft_inertia
			gear_impulse += impulse
			if driveline_compliance_enabled:
				output_shaft_omega_rad_s -= ratio * impulse * output_inverse
			else:
				for i in 4:
					spins[i] -= ratio * weights[i] * impulse * inverse[i]
		if driveline_compliance_enabled:
			var carrier_speed := 0.0
			for i in 4:
				carrier_speed += weights[i] * spins[i]
			var relative_speed := output_shaft_omega_rad_s - carrier_speed
			var spring_delta := -(
				spring_impulse + h * torsional_stiffness_nm_per_rad * driveline_twist_rad
				+ h * implicit_damping * relative_speed
			) / spring_denominator
			spring_impulse += spring_delta
			output_shaft_omega_rad_s += spring_delta * output_inverse
			for i in 4:
				spins[i] -= weights[i] * spring_delta * inverse[i]
		var slip := engine_omega - input_shaft_omega_rad_s
		var next_clutch := clampf(
			clutch_impulse + slip / (1.0 / ie + 1.0 / shaft_inertia),
			-clutch_capacity,
			clutch_capacity,
		)
		var clutch_delta := next_clutch - clutch_impulse
		engine_omega -= clutch_delta / ie
		input_shaft_omega_rad_s += clutch_delta / shaft_inertia
		clutch_work += clutch_delta * (slip + engine_omega - input_shaft_omega_rad_s) * 0.5
		clutch_impulse = next_clutch

		var transmitted := (
			-spring_impulse / h
			if driveline_compliance_enabled
			else (-ratio * gear_impulse / h if connected else 0.0)
		)
		var differential_input := transmitted * (1.0 - front_torque_split)
		var rear_carrier := 0.5 * (spins[2] + spins[3])
		var driving_power := differential_input * (
			rear_carrier if absf(rear_carrier) > 0.5 else signf(differential_input)
		)
		var power_blend := clampf(0.5 + 0.5 * tanh(driving_power / 150.0), 0.0, 1.0)
		var ramp_deg := lerpf(
			differential_coast_ramp_angle_deg,
			differential_power_ramp_angle_deg,
			power_blend,
		)
		var friction_mu := lerpf(differential_coast_ratio, differential_power_ratio, power_blend)
		var cot_ramp := 1.0 / tan(clampf(deg_to_rad(ramp_deg), deg_to_rad(15.0), deg_to_rad(85.0)))
		var ramp_capacity := absf(differential_input) * cot_ramp * maxf(differential_clutches, 1.0) * maxf(
			friction_mu,
			0.0,
		) * 0.16
		var diff_speed := spins[2] - spins[3]
		var slip_scale := clampf(
			absf(diff_speed) / maxf(differential_slip_transition_threshold_rad_s, 0.05),
			0.25,
			1.0,
		)
		var lsd_capacity := (maxf(differential_preload_nm, 0.0) + ramp_capacity) * slip_scale * h if front_torque_split < 1.0 else 0.0
		var next_lsd := clampf(lsd_impulse + diff_speed / lsd_pair_inv, -lsd_capacity, lsd_capacity)
		var lsd_delta := next_lsd - lsd_impulse
		spins[2] -= lsd_delta * inverse[2]
		spins[3] += lsd_delta * inverse[3]
		lsd_impulse = next_lsd

		for i in 4:
			var before := spins[i]
			var capacity := absf(brakes[i]) * h
			var next_brake := clampf(brake_impulses[i] - before / inverse[i], -capacity, capacity)
			var brake_delta := next_brake - brake_impulses[i]
			spins[i] += brake_delta * inverse[i]
			brake_work[i] -= brake_delta * (before + spins[i]) * 0.5
			brake_impulses[i] = next_brake

	if shift_phase == "synchronizing" and shift_phase_seconds >= nominal_sync_time:
		var target_carrier := 0.0
		for i in 4:
			target_carrier += weights[i] * spins[i]
		var sync_output := output_shaft_omega_rad_s if driveline_compliance_enabled else target_carrier
		var dynamic_tol := synchronizer_tolerance_rad_s * sync_overtime * 2.5
		if (
			pending_gear == 0 or absf(input_shaft_omega_rad_s - ratio * sync_output) <= dynamic_tol
			or shift_phase_seconds >= nominal_sync_time * 1.75
		):
			input_shaft_omega_rad_s = ratio * sync_output if pending_gear != 0 else input_shaft_omega_rad_s
			current_gear = pending_gear
			shift_phase = "closing"
			shift_phase_seconds = 0.0

	if driveline_compliance_enabled:
		var final_carrier := 0.0
		for i in 4:
			final_carrier += weights[i] * spins[i]
		var twist_speed := output_shaft_omega_rad_s - final_carrier
		driveline_twist_rad = clampf(driveline_twist_rad + h * twist_speed, -0.35, 0.35)
		driveline_torque_nm = -spring_impulse / h
		driveline_energy_j = 0.5 * torsional_stiffness_nm_per_rad * driveline_twist_rad * driveline_twist_rad
		driveline_dissipation_w = torsional_damping_nms_per_rad * twist_speed * twist_speed

	engine_rpm = maxf(engine_omega, 0.0) * 60.0 / TAU
	clutch_torque_nm = clutch_impulse / h
	clutch_slip_power_w = maxf(clutch_work / h, 0.0)
	for i in 4:
		brake_work[i] = maxf(brake_work[i], 0.0)
	return {
		"brake_work_j": brake_work,
		"shaft_torque_nm": (
			driveline_torque_nm
			if driveline_compliance_enabled
			else (-ratio * gear_impulse / h if connected else 0.0)
		),
	}


func _advance_engine_torque(delta: float, throttle: float, thermal_derating: float) -> void:
	var throttle_clamped := clampf(throttle, 0.0, 1.0)
	var closed_throttle := 1.0 - throttle_clamped
	var rpm_fraction := clampf(engine_rpm / maxf(maximum_rpm, 1.0), 0.0, 1.25)
	var rev_limit_band := maxf(maximum_rpm * 0.025, 100.0)
	var rev_cut := clampf((maximum_rpm - engine_rpm) / rev_limit_band, 0.0, 1.0)
	var curve_val := _evaluate_torque_curve(clampf(rpm_fraction, 0.0, 1.0))
	var positive_target := curve_val * peak_torque_nm * throttle_clamped * clampf(
		thermal_derating,
		0.0,
		1.0,
	) * rev_cut
	if torque_attack_rate_nm_s > 0.0:
		if positive_target > engine_attack_limited_torque_nm:
			engine_attack_limited_torque_nm = minf(
				positive_target,
				engine_attack_limited_torque_nm + torque_attack_rate_nm_s * delta,
			)
		else:
			engine_attack_limited_torque_nm = maxf(
				positive_target,
				engine_attack_limited_torque_nm - torque_attack_rate_nm_s * 3.5 * delta,
			)
	else:
		engine_attack_limited_torque_nm = positive_target
	var variable_drag := rpm_fraction * peak_torque_nm * variable_drag_ratio * lerpf(
		0.15,
		1.0,
		closed_throttle,
	)
	var constant_brake := peak_torque_nm * constant_brake_ratio * closed_throttle
	var idle_support := 0.0
	if engine_rpm < idle_rpm + 250.0:
		var idle_error := clampf((idle_rpm + 100.0 - engine_rpm) / 250.0, 0.0, 1.5)
		idle_support = (variable_drag + constant_brake) * clampf(idle_error, 0.0, 1.0) + peak_torque_nm * 0.12 * maxf(
			idle_error - 0.4,
			0.0,
		)
	engine_torque_nm = engine_attack_limited_torque_nm + idle_support - variable_drag - constant_brake


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
			var fraction := (rpm_fraction - first_point.x) / maxf(
				second_point.x - first_point.x,
				0.000001,
			)
			return lerpf(first_point.y, second_point.y, fraction)
	return torque_curve[last_index].y
