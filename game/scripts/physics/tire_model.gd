class_name TireModel
extends RefCounted

const CONTACT_PATCH_LOAD_GAIN := 0.12
const CONTACT_PATCH_DEFLECTION_GAIN := 0.20
const FRONT_CAMBER_THRUST_GAIN := 0.13
const REAR_CAMBER_THRUST_GAIN := 0.18

var axle_profiles: Array[Dictionary] = []
var surfaces: Dictionary = { }
var surface_transition_tau_s: float = 0.0
var base_contact_patch_m: Array[float] = []
var base_relaxation_length_m: Array[float] = []
var static_wheel_load_n: Array[float] = []
var maximum_tire_deflection_m: Array[float] = []
var reference_hot_pressure_kpa: Array[float] = []
var load_sensitivity_per_newton: float = 1.5e-5
var rolling_resistance_coefficient: float = 0.015
var pneumatic_trail_m: float = 0.035
var pressure_relaxation_sensitivity: float = 0.0
var pressure_rolling_resistance_sensitivity: float = 0.0
var optimal_carcass_temperature_c: float = 60.0
var radial_tires: Dictionary = { }
var states: Array[Dictionary] = []


func configure(
	domains: Dictionary,
	resolved_filters: Dictionary,
	static_wheel_loads: Array,
) -> void:
	var tires: Dictionary = domains.get("tires", { }).get("tires", { })
	radial_tires = tires
	surfaces = tires.get("surfaces", { }).duplicate(true)
	surface_transition_tau_s = float(resolved_filters.get("surface_transition_tau_s", 0.0))
	var front_tire: Dictionary = tires.get("front", { })
	var rear_tire: Dictionary = tires.get("rear", { })
	var axle_tires: Array[Dictionary] = [front_tire, front_tire, rear_tire, rear_tire]
	var tire_thermal: Dictionary = tires.get("thermal", { })
	var tire_pressure: Dictionary = tires.get("pressure", { })
	var hot_pressures: Dictionary = tire_pressure.get("reference_hot_kpa_gauge", { })
	var wheel_keys := ["FL", "FR", "RL", "RR"]
	var front_radius := float(front_tire.get("radius", tires.get("radius", 0.28)))
	var rear_radius := float(rear_tire.get("radius", tires.get("radius", 0.28)))
	base_contact_patch_m.clear()
	base_relaxation_length_m.clear()
	static_wheel_load_n.clear()
	maximum_tire_deflection_m.clear()
	reference_hot_pressure_kpa.clear()
	for i in 4:
		var axle_tire: Dictionary = axle_tires[i]
		var contact_patch := maxf(
			float(axle_tire.get("contact_patch", tires.get("contact_patch", 0.2))),
			0.03,
		)
		var tire_radius := front_radius if i < 2 else rear_radius
		base_contact_patch_m.append(contact_patch)
		base_relaxation_length_m.append(contact_patch * (1.85 if i < 2 else 1.55))
		static_wheel_load_n.append(
			maxf(float(static_wheel_loads[i]) if i < static_wheel_loads.size() else 0.0, 100.0)
		)
		maximum_tire_deflection_m.append(float(TireRadialModel.geometry(axle_tire).sidewall_m))
		reference_hot_pressure_kpa.append(
			maxf(float(hot_pressures.get(wheel_keys[i], 225.0)), 20.0)
		)
	optimal_carcass_temperature_c = float(tire_thermal.get("optimal_carcass_temperature_c", 60.0))
	var pressure_mechanics: Dictionary = tires.get("pressure_mechanics", { })
	pressure_relaxation_sensitivity = float(pressure_mechanics.get("response_sensitivity", 0.0))
	pressure_rolling_resistance_sensitivity = float(
		pressure_mechanics.get("rolling_resistance_sensitivity", 0.0)
	)
	axle_profiles = [
		resolved_filters.get("front", { }).duplicate(true),
		resolved_filters.get("front", { }).duplicate(true),
		resolved_filters.get("rear", { }).duplicate(true),
		resolved_filters.get("rear", { }).duplicate(true),
	]
	states.clear()
	for i in 4:
		states.append(
			{
				"patch_pos": Vector2.ZERO,
				"patch_forward": Vector3.ZERO,
				"patch_right": Vector3.ZERO,
				"patch_energy_j": 0.0,
				"brush_demand_n": 0.0,
				"effective_slip_angle": 0.0,
				"effective_slip_ratio": 0.0,
				"post_peak_decay_lat": 0.0,
				"post_peak_decay_lon": 0.0,
				"contact_blend": 0.0,
				"surface_initialized": false,
				"surface_friction": 0.0,
				"surface_stiffness": 0.0,
				"surface_rolling": 0.0,
				"slip_angle": 0.0,
				"slip_ratio": 0.0,
				"dynamic_contact_patch_m": base_contact_patch_m[i],
				"relaxation_length_m": base_relaxation_length_m[i],
				"estimated_carcass_deflection_m": 0.0,
				"combined_utilization": 0.0,
				"longitudinal_force": 0.0,
				"lateral_force": 0.0,
				"aligning_torque": 0.0,
				"friction_power": 0.0,
				"surface": "Unknown",
			}
		)


func evaluate(
	index: int,
	normal_load_n: float,
	surface_name: String,
	longitudinal_speed_m_s: float,
	lateral_speed_m_s: float,
	wheel_speed_rad_s: float,
	rolling_radius_m: float,
	camber_rad: float,
	thermal_grip_factor: float,
	pressure_kpa_gauge: float,
	delta: float,
	carcass_temperature_c: float,
) -> Dictionary:
	var state: Dictionary = states[index]
	var target_surface: Dictionary = surfaces.get(
		surface_name,
		surfaces.get("Gravel", surfaces.get("Road", { })),
	)
	if target_surface.is_empty():
		target_surface = {
			"friction": 1.0,
			"stiffness": 1.0,
			"rolling_resistance": 1.0,
			"longitudinal_grip_ratio": 1.0,
			"lateral_grip_assist": 0.0,
		}
	var tau_surface := maxf(surface_transition_tau_s, 0.0)
	if not bool(state.surface_initialized):
		state.surface_friction = float(target_surface.get("friction", 1.0))
		state.surface_stiffness = float(target_surface.get("stiffness", 1.0))
		state.surface_rolling = float(target_surface.get("rolling_resistance", 1.0))
		state.surface_initialized = true
	else:
		var surface_alpha := (
			1.0
			if tau_surface <= 1e-9
			else 1.0 - exp(-maxf(delta, 0.0) / tau_surface)
		)
		state.surface_friction += (
			float(target_surface.get("friction", 1.0)) - float(state.surface_friction)
		) * surface_alpha
		state.surface_stiffness += (
			float(target_surface.get("stiffness", 1.0)) - float(state.surface_stiffness)
		) * surface_alpha
		state.surface_rolling += (
			float(target_surface.get("rolling_resistance", 1.0)) - float(state.surface_rolling)
		) * surface_alpha
	state.surface = surface_name
	var profile: Dictionary = axle_profiles[index]
	var contact_target := normal_load_n > 1e-4
	var contact_tau := clampf(float(profile.get("contact_ramp_tau_s", 0.0)), 0.0, 1.0)
	if contact_tau <= 1e-9:
		state.contact_blend = 1.0 if contact_target else 0.0
	else:
		var contact_alpha := 1.0 - exp(-maxf(delta, 0.0) / contact_tau)
		state.contact_blend = clampf(
			float(state.contact_blend)
			+ ((1.0 if contact_target else 0.0) - float(state.contact_blend)) * contact_alpha,
			0.0,
			1.0,
		)
	if not contact_target:
		_advance_unloaded(index, delta)
		return _output(state)

	var radius := maxf(rolling_radius_m, 0.05)
	var rim_speed := wheel_speed_rad_s * radius
	var speed_reference := maxf(maxf(absf(longitudinal_speed_m_s), absf(rim_speed)), 1.0)
	var target_ratio := clampf((rim_speed - longitudinal_speed_m_s) / speed_reference, -3.0, 3.0)
	var target_angle := clampf(
		atan2(-lateral_speed_m_s, maxf(absf(longitudinal_speed_m_s), 0.5)),
		-0.75,
		0.75,
	)
	state.slip_ratio = target_ratio
	state.slip_angle = target_angle
	var planar_speed := Vector2(longitudinal_speed_m_s, lateral_speed_m_s).length()
	var reference_load := maxf(static_wheel_load_n[index], 100.0)
	var load_ratio := maxf(maxf(normal_load_n, 0.0) / reference_load, 0.05)
	var pressure_ratio := maxf(pressure_kpa_gauge / reference_hot_pressure_kpa[index], 0.001)
	var radial := TireRadialModel.evaluate(
		radial_tires,
		"front" if index < 2 else "rear",
		pressure_kpa_gauge,
		carcass_temperature_c,
		1.0,
		0.0,
		0.0,
	)
	var estimated_deflection := maxf(normal_load_n, 0.0) / maxf(float(radial.stiffness_n_m), 1.0)
	if state.has("radial_deflection_m"):
		estimated_deflection = float(state.radial_deflection_m)
	estimated_deflection = clampf(estimated_deflection, 0.0, maximum_tire_deflection_m[index] * 1.5)
	var deflection_ratio := clampf(
		estimated_deflection / maximum_tire_deflection_m[index],
		0.0,
		1.5,
	)
	var patch_scale := clampf(
		1.0 + CONTACT_PATCH_LOAD_GAIN * (load_ratio - 1.0)
		+ CONTACT_PATCH_DEFLECTION_GAIN * deflection_ratio,
		0.70,
		1.45,
	)
	var dynamic_contact_patch := base_contact_patch_m[index] * patch_scale
	var patch_ratio := clampf(dynamic_contact_patch / base_contact_patch_m[index], 0.70, 1.50)
	var pressure_relaxation_scale := clampf(
		pow(pressure_ratio, clampf(pressure_relaxation_sensitivity, -3.0, 3.0)),
		0.80,
		1.30,
	)
	var relaxation_length := base_relaxation_length_m[index] * sqrt(patch_ratio) * pressure_relaxation_scale
	state.dynamic_contact_patch_m = dynamic_contact_patch
	state.relaxation_length_m = relaxation_length
	state.estimated_carcass_deflection_m = estimated_deflection
	var relaxation_tau := maxf(
		relaxation_length / maxf(planar_speed, 4.0),
		clampf(float(profile.get("min_relaxation_tau_s", 0.0)), 0.0, 0.5),
	)
	var recovery_scale := clampf(float(profile.get("relaxation_recovery_scale", 1.0)), 0.1, 5.0)
	var lat_recovering := absf(float(state.effective_slip_angle)) > absf(target_angle)
	var lon_recovering := absf(float(state.effective_slip_ratio)) > absf(target_ratio)
	var lat_tau := relaxation_tau * (recovery_scale if lat_recovering else 1.0)
	var lon_tau := relaxation_tau * (recovery_scale if lon_recovering else 1.0)
	var lat_alpha := 1.0 - exp(-maxf(delta, 0.0) / maxf(lat_tau, 1e-4))
	var lon_alpha := 1.0 - exp(-maxf(delta, 0.0) / maxf(lon_tau, 1e-4))
	state.effective_slip_angle += (target_angle - float(state.effective_slip_angle)) * lat_alpha
	state.effective_slip_ratio += (target_ratio - float(state.effective_slip_ratio)) * lon_alpha

	var fz := maxf(normal_load_n, 0.0)
	var pressure_rr := clampf(
		pow(pressure_ratio, clampf(pressure_rolling_resistance_sensitivity, -3.0, 3.0)),
		0.75,
		1.50,
	)
	var axle_load_mult := 2.85 if index < 2 else 2.15
	var load_sensitivity_exp := clampf(
		load_sensitivity_per_newton * reference_load * axle_load_mult,
		0.08,
		0.25,
	)
	var load_scale := clampf(pow(load_ratio, -load_sensitivity_exp), 0.60, 1.20)
	var mu := maxf(float(state.surface_friction), 0.0) * load_scale * clampf(
		thermal_grip_factor,
		0.05,
		1.0,
	)
	var longitudinal_ratio := clampf(
		float(target_surface.get("longitudinal_grip_ratio", 1.0)),
		0.10,
		1.50,
	)
	var lateral_assist := float(target_surface.get("lateral_grip_assist", 0.0))
	var rear_lat_bonus := 1.0 + (lateral_assist if index >= 2 else 0.0)
	var fx_capacity := maxf(mu * longitudinal_ratio * fz, 1e-6)
	var fy_capacity := maxf(mu * rear_lat_bonus * fz, 1e-6)
	var stiffness_scale := sqrt(clampf(maxf(float(state.surface_stiffness), 0.0) / 5.0, 0.15, 2.5))
	var rise_gamma := clampf(2.0 * stiffness_scale, 1.2, 4.0)
	var base_peak_lat := maxf(float(profile.get("lateral_peak_slip_angle_rad", 0.18)), 1e-6)
	var base_peak_lon := maxf(float(profile.get("longitudinal_peak_slip_ratio", 0.2)), 1e-6)
	var slide_lat := clampf(
		float(
			profile.get("lateral_slide_mu_ratio", profile.get("longitudinal_slide_mu_ratio", 0.94))
		),
		0.0,
		1.0,
	)
	var slide_lon := clampf(float(profile.get("longitudinal_slide_mu_ratio", 0.95)), 0.0, 1.0)
	var signed_camber := camber_rad * (1.0 if index in [0, 2] else -1.0)
	var camber_gain := FRONT_CAMBER_THRUST_GAIN if index < 2 else REAR_CAMBER_THRUST_GAIN
	var blend := float(state.contact_blend)

	var patch_before: Vector2 = state.patch_pos
	var transport_speed := maxf(absf(longitudinal_speed_m_s), absf(rim_speed))
	var renewal_rate := transport_speed / maxf(relaxation_length, 0.001)
	var patch_velocity := Vector2(rim_speed - longitudinal_speed_m_s, -lateral_speed_m_s)
	patch_velocity.y += absf(longitudinal_speed_m_s) * tan(signed_camber * camber_gain)
	var patch_dt := maxf(delta, 0.0)
	var renewal := exp(-renewal_rate * patch_dt)
	var integrated_time := (1.0 - renewal) / renewal_rate if renewal_rate > 1.0e-6 else patch_dt
	var patch_pos := patch_before * renewal + patch_velocity * integrated_time
	var stiffness_x := fx_capacity * rise_gamma / (base_peak_lon * maxf(relaxation_length, 0.001))
	var stiffness_y := fy_capacity * rise_gamma / (base_peak_lat * maxf(relaxation_length, 0.001))
	var trial := Vector2(stiffness_x * patch_pos.x, stiffness_y * patch_pos.y)

	var is_rear_accelerating := index >= 2 and patch_pos.x > 0.0
	var lon_coupling_relief := float(profile.get("combined_lateral_peak_migration", 0.3))
	var effective_norm_x := absf(trial.x) / fx_capacity
	if is_rear_accelerating:
		effective_norm_x *= (1.0 - clampf(lon_coupling_relief, 0.0, 0.65))

	var norm_demand_x := effective_norm_x
	var norm_demand_y := absf(trial.y) / fy_capacity
	var combined_theta := Vector2(norm_demand_x, norm_demand_y).length() / 3.0
	var sharpness := clampf(float(profile.get("falloff_sharpness", 1.2)), 0.2, 8.0)
	var over_peak := clampf((combined_theta - 0.68) / 0.32 * sharpness, 0.0, 1.0)
	var target_decay := over_peak * over_peak * (3.0 - 2.0 * over_peak)
	var lat_weight := norm_demand_y / maxf(norm_demand_x + norm_demand_y, 1.0e-6)
	var lon_weight := 1.0 - lat_weight
	state.post_peak_decay_lat = _advance_memory(
		float(state.post_peak_decay_lat),
		target_decay * lat_weight,
		profile,
		delta,
	)
	state.post_peak_decay_lon = _advance_memory(
		float(state.post_peak_decay_lon),
		target_decay * lon_weight,
		profile,
		delta,
	)

	var mu_fz := maxf(mu * fz, 0.0)
	var sliding_fraction := clampf(
		float(state.post_peak_decay_lon) + float(state.post_peak_decay_lat),
		0.0,
		1.0,
	)
	var directional_slide_mu := lerpf(slide_lon, slide_lat, lat_weight)
	var slide_scale := lerpf(1.0, directional_slide_mu, sliding_fraction)
	var limit_x := fx_capacity * slide_scale
	var limit_y := fy_capacity * slide_scale
	var grip_limit := mu_fz * slide_scale

	if limit_x <= 1.0e-6 or limit_y <= 1.0e-6:
		patch_pos = Vector2.ZERO
		trial = Vector2.ZERO
	else:
		var norm_trial := Vector2(trial.x / limit_x, trial.y / limit_y)
		var norm_length := norm_trial.length()
		var unloading := patch_pos.dot(patch_velocity) < 0.0
		var current_theta := norm_length / 3.0
		if unloading and current_theta > 0.5:
			var recovery_boost := exp(-clampf((current_theta - 0.5) * 12.0, 0.0, 15.0) * patch_dt)
			patch_pos *= recovery_boost
			trial *= recovery_boost
			norm_length *= recovery_boost
		var max_elastic_norm := 2.65
		if norm_length > max_elastic_norm:
			var plastic_scale := max_elastic_norm / norm_length
			patch_pos *= plastic_scale
			trial *= plastic_scale

	var brush_trial := trial
	if is_rear_accelerating:
		var max_coupled_fx := limit_x * (1.25 - 0.5 * clampf(lon_coupling_relief, 0.0, 0.8))
		brush_trial.x = minf(trial.x, max_coupled_fx)

	var brush := _brush_force_elliptical(brush_trial, limit_x, limit_y) * blend
	var fx := brush.x
	var fy := brush.y
	var patch_energy := 0.5 * brush.dot(patch_pos)
	var previous_patch_energy := float(state.patch_energy_j)
	state.patch_pos = patch_pos
	state.patch_energy_j = patch_energy
	var rolling_force := 0.0
	if absf(longitudinal_speed_m_s) > 0.05:
		rolling_force = fz * rolling_resistance_coefficient * float(state.surface_rolling) * pressure_rr * signf(
			longitudinal_speed_m_s
		)
		fx -= rolling_force * blend

	var bound_x := maxf(limit_x * blend, 1.0e-6)
	var bound_y := maxf(limit_y * blend, 1.0e-6)
	var budget_norm := Vector2(fx / bound_x, fy / bound_y).length()
	if budget_norm > 1.0:
		fx /= budget_norm
		fy /= budget_norm

	var brush_theta := clampf(
		Vector2(trial.x / maxf(limit_x, 1.0e-6), trial.y / maxf(limit_y, 1.0e-6)).length() / 3.0,
		0.0,
		1.0,
	)
	var lon_theta := clampf(absf(trial.x) / maxf(3.0 * limit_x, 1.0e-6), 0.0, 1.0)
	var trail := pneumatic_trail_m * pow(1.0 - brush_theta, 1.35) * (1.0 - 0.75 * lon_theta)
	var aligning_torque := -fy * trail
	var slip_longitudinal_speed := rim_speed - longitudinal_speed_m_s
	var contact_power := (fx + rolling_force * blend) * slip_longitudinal_speed - fy * lateral_speed_m_s
	var friction_power := maxf(
		contact_power - (patch_energy - previous_patch_energy) / maxf(patch_dt, 1.0e-6),
		0.0,
	)
	friction_power += absf(rolling_force * blend * longitudinal_speed_m_s)
	state.longitudinal_force = fx
	state.lateral_force = fy
	state.aligning_torque = aligning_torque
	state.friction_power = friction_power
	state.combined_utilization = Vector2(
		fx / maxf(fx_capacity, 1.0e-6),
		fy / maxf(fy_capacity, 1.0e-6),
	).length()
	state.brush_demand_n = trial.length()
	states[index] = state
	return _output(state)


func _brush_force_elliptical(demand: Vector2, limit_x: float, limit_y: float) -> Vector2:
	if limit_x <= 1.0e-6 or limit_y <= 1.0e-6:
		return Vector2.ZERO
	var norm_demand := Vector2(demand.x / limit_x, demand.y / limit_y)
	var magnitude := norm_demand.length()
	if magnitude <= 1.0e-9:
		return Vector2.ZERO
	var theta := clampf(magnitude / 3.0, 0.0, 1.0)
	var factor := 3.0 * theta - 3.0 * theta * theta + theta * theta * theta
	var unit_force := norm_demand * (factor / magnitude)
	return Vector2(unit_force.x * limit_x, unit_force.y * limit_y)


func state_for(index: int) -> Dictionary:
	return states[index].duplicate(true) if index >= 0 and index < states.size() else { }


func reset_patch(index: int) -> void:
	states[index].patch_pos = Vector2.ZERO
	states[index].patch_forward = Vector3.ZERO
	states[index].patch_right = Vector3.ZERO
	states[index].patch_energy_j = 0.0


func rotate_patch_frame(index: int, forward: Vector3, right: Vector3) -> void:
	var state: Dictionary = states[index]
	var previous_forward: Vector3 = state.patch_forward
	if previous_forward.length_squared() > 0.5:
		var patch: Vector2 = state.patch_pos
		var world_patch := previous_forward * patch.x + (state.patch_right as Vector3) * patch.y
		state.patch_pos = Vector2(world_patch.dot(forward), world_patch.dot(right))
	state.patch_forward = forward
	state.patch_right = right
	states[index] = state


func _advance_unloaded(index: int, delta: float) -> void:
	var state: Dictionary = states[index]
	var profile: Dictionary = axle_profiles[index]
	var recovery_tau := float(profile.get("slip_recovery_tau_s", 0.0))
	var release := 0.0 if recovery_tau <= 1e-6 else exp(-maxf(delta, 0.0) / recovery_tau)
	state.effective_slip_angle = 0.0
	# Detached tread cannot keep its ground anchor for the next landing.
	state.patch_pos = Vector2.ZERO
	state.patch_forward = Vector3.ZERO
	state.patch_right = Vector3.ZERO
	state.patch_energy_j = 0.0
	state.effective_slip_ratio = 0.0
	state.post_peak_decay_lat *= release
	state.post_peak_decay_lon *= release
	state.longitudinal_force = 0.0
	state.lateral_force = 0.0
	state.aligning_torque = 0.0
	state.friction_power = 0.0
	state.combined_utilization = 0.0
	state.brush_demand_n = 0.0
	states[index] = state


func _advance_memory(current: float, target: float, profile: Dictionary, delta: float) -> float:
	var tau := (
		float(profile.get("slip_loss_tau_s", 0.0))
		if target > current
		else float(profile.get("slip_recovery_tau_s", 0.0))
	)
	if tau <= 1e-6:
		return target
	var alpha := 1.0 - exp(-maxf(delta, 0.0) / tau)
	return clampf(current + (target - current) * alpha, 0.0, 1.0)


func _pure_curve(
	slip: float,
	peak: float,
	slide: float,
	rise: float,
	sharpness: float,
) -> Dictionary:
	var normalized := maxf(slip, 0.0) / maxf(peak, 1e-6)
	if normalized <= 1.0:
		return {
			"coefficient": clampf(1.0 - pow(1.0 - normalized, maxf(rise, 1.2)), 0.0, 1.0),
			"decay": 0.0,
		}
	var distance := clampf(sharpness, 0.1, 16.0) * (normalized - 1.0)
	var decay := distance * distance / (1.0 + distance * distance)
	return {
		"coefficient": clampf(slide + (1.0 - slide) * (1.0 - decay), 0.0, 1.0),
		"decay": decay,
	}


func _brush_force(demand: Vector2, friction_limit_n: float) -> Vector2:
	var magnitude := demand.length()
	if magnitude <= 1.0e-9 or friction_limit_n <= 1.0e-6:
		return Vector2.ZERO
	var theta := clampf(magnitude / (3.0 * friction_limit_n), 0.0, 1.0)
	var force_magnitude := friction_limit_n * (
		3.0 * theta - 3.0 * theta * theta + theta * theta * theta
	)
	return demand * (force_magnitude / magnitude)


func _combined_budget_scale(utilization: float, blend_width: float) -> float:
	var value := maxf(utilization, 0.0)
	var width := clampf(blend_width, 0.0, 0.5)
	if width <= 1e-9:
		return 1.0 / value if value > 1.0 else 1.0
	var low := 1.0 - width
	var high := 1.0 + width
	if value <= low:
		return 1.0
	if value >= high:
		return 1.0 / value
	var span := high - low
	var t := (value - low) / span
	var end_value := 1.0 / high
	var end_slope := -1.0 / (high * high)
	var t2 := t * t
	var t3 := t2 * t
	var h00 := 2.0 * t3 - 3.0 * t2 + 1.0
	var h01 := -2.0 * t3 + 3.0 * t2
	var h11 := t3 - t2
	return clampf(h00 + h01 * end_value + h11 * span * end_slope, end_value, 1.0)


func _output(state: Dictionary) -> Dictionary:
	return {
		"longitudinal_force_n": float(state.longitudinal_force),
		"lateral_force_n": float(state.lateral_force),
		"aligning_torque_nm": float(state.aligning_torque),
		"friction_power_w": float(state.friction_power),
		"slip_ratio": float(state.slip_ratio),
		"slip_angle_rad": float(state.slip_angle),
		"combined_utilization": float(state.combined_utilization),
		"surface": str(state.surface),
		"patch_pos": state.patch_pos,
		"patch_energy_j": state.patch_energy_j,
		"brush_demand_n": state.get("brush_demand_n", 0.0),
	}
