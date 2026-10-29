class_name TireModel
extends RefCounted

const STATIC_TIRE_DEFLECTION_M := 0.008
const CONTACT_PATCH_LOAD_GAIN := 0.12
const CONTACT_PATCH_DEFLECTION_GAIN := 0.20
const FRONT_CAMBER_THRUST_GAIN := 0.18
const REAR_CAMBER_THRUST_GAIN := 0.15

var axle_profiles: Array[Dictionary] = []
var surfaces: Dictionary = {}
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
var pressure_compliance_sensitivity: float = 0.0
var pressure_rolling_resistance_sensitivity: float = 0.0
var optimal_carcass_temperature_c: float = 60.0
var states: Array[Dictionary] = []


func configure(domains: Dictionary, resolved_filters: Dictionary, static_wheel_loads: Array) -> void:
	var tires: Dictionary = domains.get("tires", {}).get("tires", {})
	surfaces = tires.get("surfaces", {}).duplicate(true)
	surface_transition_tau_s = float(resolved_filters.get("surface_transition_tau_s", 0.0))
	var front_tire: Dictionary = tires.get("front", {})
	var rear_tire: Dictionary = tires.get("rear", {})
	var axle_tires: Array[Dictionary] = [front_tire, front_tire, rear_tire, rear_tire]
	var tire_thermal: Dictionary = tires.get("thermal", {})
	var tire_pressure: Dictionary = tires.get("pressure", {})
	var hot_pressures: Dictionary = tire_pressure.get("reference_hot_kpa_gauge", {})
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
		var contact_patch := maxf(float(axle_tire.get("contact_patch", tires.get("contact_patch", 0.2))), 0.03)
		var tire_radius := front_radius if i < 2 else rear_radius
		base_contact_patch_m.append(contact_patch)
		base_relaxation_length_m.append(contact_patch * (1.65 if i < 2 else 1.80))
		static_wheel_load_n.append(maxf(float(static_wheel_loads[i]) if i < static_wheel_loads.size() else 0.0, 100.0))
		maximum_tire_deflection_m.append(maxf(tire_radius * 0.12, 0.001))
		reference_hot_pressure_kpa.append(maxf(float(hot_pressures.get(wheel_keys[i], 225.0)), 20.0))
	optimal_carcass_temperature_c = float(tire_thermal.get("optimal_carcass_temperature_c", 60.0))
	var pressure_mechanics: Dictionary = tires.get("pressure_mechanics", {})
	pressure_relaxation_sensitivity = float(pressure_mechanics.get("response_sensitivity", 0.0))
	pressure_compliance_sensitivity = float(pressure_mechanics.get("compliance_sensitivity", 0.0))
	pressure_rolling_resistance_sensitivity = float(pressure_mechanics.get("rolling_resistance_sensitivity", 0.0))
	axle_profiles = [resolved_filters.get("front", {}).duplicate(true), resolved_filters.get("front", {}).duplicate(true), resolved_filters.get("rear", {}).duplicate(true), resolved_filters.get("rear", {}).duplicate(true)]
	states.clear()
	for i in 4:
		states.append({
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
		})


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
		carcass_temperature_c: float) -> Dictionary:
	var state: Dictionary = states[index]
	var target_surface: Dictionary = surfaces.get(surface_name, surfaces.get("Gravel", surfaces.get("Road", {})))
	if target_surface.is_empty():
		target_surface = {"friction": 1.0, "stiffness": 1.0, "rolling_resistance": 1.0, "longitudinal_grip_ratio": 1.0, "lateral_grip_assist": 0.0}
	var tau_surface := maxf(surface_transition_tau_s, 0.0)
	if not bool(state.surface_initialized):
		state.surface_friction = float(target_surface.get("friction", 1.0))
		state.surface_stiffness = float(target_surface.get("stiffness", 1.0))
		state.surface_rolling = float(target_surface.get("rolling_resistance", 1.0))
		state.surface_initialized = true
	else:
		var surface_alpha := 1.0 if tau_surface <= 1e-9 else 1.0 - exp(-maxf(delta, 0.0) / tau_surface)
		state.surface_friction += (float(target_surface.get("friction", 1.0)) - float(state.surface_friction)) * surface_alpha
		state.surface_stiffness += (float(target_surface.get("stiffness", 1.0)) - float(state.surface_stiffness)) * surface_alpha
		state.surface_rolling += (float(target_surface.get("rolling_resistance", 1.0)) - float(state.surface_rolling)) * surface_alpha
	state.surface = surface_name
	var profile: Dictionary = axle_profiles[index]
	var contact_target := normal_load_n > 1e-4
	var contact_tau := clampf(float(profile.get("contact_ramp_tau_s", 0.0)), 0.0, 1.0)
	if contact_tau <= 1e-9:
		state.contact_blend = 1.0 if contact_target else 0.0
	else:
		var contact_alpha := 1.0 - exp(-maxf(delta, 0.0) / contact_tau)
		state.contact_blend = clampf(float(state.contact_blend) + ((1.0 if contact_target else 0.0) - float(state.contact_blend)) * contact_alpha, 0.0, 1.0)
	if not contact_target and float(state.contact_blend) <= 1e-6:
		_advance_unloaded(index, delta)
		return _output(state)

	var radius := maxf(rolling_radius_m, 0.05)
	var rim_speed := wheel_speed_rad_s * radius
	var speed_reference := maxf(maxf(absf(longitudinal_speed_m_s), absf(rim_speed)), 1.0)
	var target_ratio := clampf((rim_speed - longitudinal_speed_m_s) / speed_reference, -3.0, 3.0)
	var target_angle := clampf(atan2(-lateral_speed_m_s, maxf(absf(longitudinal_speed_m_s), 0.5)), -0.75, 0.75)
	state.slip_ratio = target_ratio
	state.slip_angle = target_angle
	var planar_speed := Vector2(longitudinal_speed_m_s, lateral_speed_m_s).length()
	var reference_load := maxf(static_wheel_load_n[index], 100.0)
	var load_ratio := maxf(maxf(normal_load_n, 0.0) / reference_load, 0.05)
	var pressure_ratio := clampf(pressure_kpa_gauge / reference_hot_pressure_kpa[index], 0.45, 1.80)
	var compliance_scale := clampf(pow(pressure_ratio, clampf(pressure_compliance_sensitivity, -3.0, 3.0)), 0.55, 1.80)
	var carcass_structure := clampf(1.0 - 0.0015 * (carcass_temperature_c - optimal_carcass_temperature_c), 0.88, 1.12)
	var vertical_stiffness_scale := clampf(compliance_scale * carcass_structure, 0.55, 1.65)
	# This GDScript model has no separate unsprung-mass/carcass solver. Estimate its
	# quasi-static deflection from wheel load and the Rust reference radial stiffness
	# (static corner load / 8 mm), adjusted by pressure and carcass temperature.
	var estimated_deflection := STATIC_TIRE_DEFLECTION_M * load_ratio / vertical_stiffness_scale
	estimated_deflection = clampf(estimated_deflection, 0.0, maximum_tire_deflection_m[index] * 1.5)
	var deflection_ratio := clampf(estimated_deflection / maximum_tire_deflection_m[index], 0.0, 1.5)
	var patch_scale := clampf(
		1.0 + CONTACT_PATCH_LOAD_GAIN * (load_ratio - 1.0) + CONTACT_PATCH_DEFLECTION_GAIN * deflection_ratio,
		0.70,
		1.45
	)
	var dynamic_contact_patch := base_contact_patch_m[index] * patch_scale
	var patch_ratio := clampf(dynamic_contact_patch / base_contact_patch_m[index], 0.70, 1.50)
	var pressure_relaxation_scale := clampf(pow(pressure_ratio, clampf(pressure_relaxation_sensitivity, -3.0, 3.0)), 0.80, 1.30)
	var relaxation_length := base_relaxation_length_m[index] * sqrt(patch_ratio) * pressure_relaxation_scale
	state.dynamic_contact_patch_m = dynamic_contact_patch
	state.relaxation_length_m = relaxation_length
	state.estimated_carcass_deflection_m = estimated_deflection
	var relaxation_tau := maxf(relaxation_length / maxf(planar_speed, 4.0), clampf(float(profile.get("min_relaxation_tau_s", 0.0)), 0.0, 0.5))
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
	var pressure_rr := clampf(pow(pressure_ratio, clampf(pressure_rolling_resistance_sensitivity, -3.0, 3.0)), 0.75, 1.50)
	var load_scale := clampf(1.0 - load_sensitivity_per_newton * fz, 0.5, 1.1)
	var mu := maxf(float(state.surface_friction), 0.0) * load_scale * clampf(thermal_grip_factor, 0.05, 1.0)
	var longitudinal_ratio := clampf(float(target_surface.get("longitudinal_grip_ratio", 1.0)), 0.10, 1.50)
	var fx_capacity := maxf(mu * longitudinal_ratio * fz, 1e-6)
	var fy_capacity := maxf(mu * fz, 1e-6)
	var stiffness_scale := sqrt(clampf(maxf(float(state.surface_stiffness), 0.0) / 5.0, 0.15, 2.5))
	var rise_gamma := clampf(2.0 * stiffness_scale, 1.2, 4.0)
	var base_peak_lat := maxf(float(profile.get("lateral_peak_slip_angle_rad", 0.18)), 1e-6)
	var base_peak_lon := maxf(float(profile.get("longitudinal_peak_slip_ratio", 0.2)), 1e-6)
	var slide_lat := clampf(float(profile.get("lateral_slide_mu_ratio", profile.get("longitudinal_slide_mu_ratio", 0.94))), 0.0, 1.0)
	var slide_lon := clampf(float(profile.get("longitudinal_slide_mu_ratio", 0.95)), 0.0, 1.0)
	var alpha := float(state.effective_slip_angle)
	var kappa := float(state.effective_slip_ratio)
	var signed_camber := camber_rad * (1.0 if index in [0, 2] else -1.0)
	var camber_gain := FRONT_CAMBER_THRUST_GAIN if index < 2 else REAR_CAMBER_THRUST_GAIN
	var alpha_with_camber := alpha + signed_camber * camber_gain
	var base_lat := _pure_curve(absf(alpha_with_camber), base_peak_lat, slide_lat, rise_gamma, float(profile.get("falloff_sharpness", 1.2)))
	var base_lon := _pure_curve(absf(kappa), base_peak_lon, slide_lon, rise_gamma, float(profile.get("falloff_sharpness", 1.2)))
	var lateral_demand := clampf(absf(alpha_with_camber) / base_peak_lat, 0.0, 1.0)
	var longitudinal_demand := clampf(absf(kappa) / base_peak_lon, 0.0, 1.0)
	var lat_peak := base_peak_lat * maxf(0.1, 1.0 - clampf(float(profile.get("combined_lateral_peak_migration", 0.0)), 0.0, 0.9) * longitudinal_demand)
	var lon_peak := base_peak_lon * maxf(0.1, 1.0 - clampf(float(profile.get("combined_longitudinal_peak_migration", 0.0)), 0.0, 0.9) * lateral_demand)
	var lat_response := _pure_curve(absf(alpha_with_camber), lat_peak, slide_lat, rise_gamma, float(profile.get("falloff_sharpness", 1.2)))
	var lon_response := _pure_curve(absf(kappa), lon_peak, slide_lon, rise_gamma, float(profile.get("falloff_sharpness", 1.2)))
	state.post_peak_decay_lat = _advance_memory(float(state.post_peak_decay_lat), float(lat_response.decay), profile, delta)
	state.post_peak_decay_lon = _advance_memory(float(state.post_peak_decay_lon), float(lon_response.decay), profile, delta)
	var lat_flat := float(lat_response.coefficient) / maxf(1.0 - float(lat_response.decay) * (1.0 - slide_lat), 1e-6)
	var lon_flat := float(lon_response.coefficient) / maxf(1.0 - float(lon_response.decay) * (1.0 - slide_lon), 1e-6)
	var lat_coefficient := lat_flat * (1.0 - float(state.post_peak_decay_lat) * (1.0 - slide_lat))
	var lon_coefficient := lon_flat * (1.0 - float(state.post_peak_decay_lon) * (1.0 - slide_lon))
	var candidate_x := fx_capacity * lon_coefficient * signf(kappa)
	var candidate_y := fy_capacity * lat_coefficient * signf(alpha_with_camber)
	var base_norm := Vector2(float(base_lon.coefficient), float(base_lat.coefficient)).length()
	var migrated_norm := Vector2(lon_coefficient, lat_coefficient).length()
	var demand := maxf(base_norm, migrated_norm)
	var budget_scale := _combined_budget_scale(demand, float(profile.get("budget_blend_width", 0.15)))
	var blend := float(state.contact_blend)
	var fx := candidate_x * budget_scale * blend
	var fy := candidate_y * budget_scale * blend
	var rolling_force := 0.0
	if absf(longitudinal_speed_m_s) > 0.05:
		rolling_force = fz * rolling_resistance_coefficient * float(state.surface_rolling) * pressure_rr * signf(longitudinal_speed_m_s)
		fx -= rolling_force * blend
	var normalized_x := clampf(absf(fx) / fx_capacity, 0.0, 1.0)
	var normalized_y := clampf(absf(fy) / fy_capacity, 0.0, 1.0)
	var trail := pneumatic_trail_m * exp(-2.5 * normalized_y) * maxf(1.0 - 0.65 * normalized_x * normalized_x, 0.0)
	var aligning_torque := -fy * trail
	var slip_longitudinal_speed := rim_speed - longitudinal_speed_m_s
	var friction_power := absf(fx * slip_longitudinal_speed) + absf(fy * lateral_speed_m_s)
	state.longitudinal_force = fx
	state.lateral_force = fy
	state.aligning_torque = aligning_torque
	state.friction_power = friction_power
	state.combined_utilization = demand * budget_scale * blend
	states[index] = state
	return _output(state)


func state_for(index: int) -> Dictionary:
	return states[index].duplicate(true) if index >= 0 and index < states.size() else {}


func _advance_unloaded(index: int, delta: float) -> void:
	var state: Dictionary = states[index]
	var profile: Dictionary = axle_profiles[index]
	var recovery_tau := float(profile.get("slip_recovery_tau_s", 0.0))
	var release := 0.0 if recovery_tau <= 1e-6 else exp(-maxf(delta, 0.0) / recovery_tau)
	state.effective_slip_angle = 0.0
	state.effective_slip_ratio = 0.0
	state.post_peak_decay_lat *= release
	state.post_peak_decay_lon *= release
	state.longitudinal_force = 0.0
	state.lateral_force = 0.0
	state.aligning_torque = 0.0
	state.friction_power = 0.0
	state.combined_utilization = 0.0
	states[index] = state


func _advance_memory(current: float, target: float, profile: Dictionary, delta: float) -> float:
	var tau := float(profile.get("slip_loss_tau_s", 0.0)) if target > current else float(profile.get("slip_recovery_tau_s", 0.0))
	if tau <= 1e-6:
		return target
	var alpha := 1.0 - exp(-maxf(delta, 0.0) / tau)
	return clampf(current + (target - current) * alpha, 0.0, 1.0)


func _pure_curve(slip: float, peak: float, slide: float, rise: float, sharpness: float) -> Dictionary:
	var normalized := maxf(slip, 0.0) / maxf(peak, 1e-6)
	if normalized <= 1.0:
		return {"coefficient": clampf(1.0 - pow(1.0 - normalized, maxf(rise, 1.2)), 0.0, 1.0), "decay": 0.0}
	var distance := clampf(sharpness, 0.1, 16.0) * (normalized - 1.0)
	var decay := distance * distance / (1.0 + distance * distance)
	return {"coefficient": clampf(slide + (1.0 - slide) * (1.0 - decay), 0.0, 1.0), "decay": decay}


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
	}
