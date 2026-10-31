class_name TireRadialModel
extends RefCounted


static func geometry(tire: Dictionary) -> Dictionary:
	var radius := float(tire.get("radius", 0.28))
	var rim_radius := float(tire.get("rim_diameter_inches", 13.0)) * 0.0254 * 0.5
	return {
		"radius_m": radius,
		"rim_radius_m": rim_radius,
		"sidewall_m": maxf(radius - rim_radius, 0.03),
		"width_m": float(tire.get("width", 0.2)),
	}


static func evaluate(
	tires: Dictionary,
	axle: String,
	pressure_kpa: float,
	temperature_c: float,
	unsprung_mass: float,
	deflection: float,
	speed: float,
) -> Dictionary:
	var g := geometry(tires.get(axle, { }))
	var model_global: Dictionary = tires.get("radial_model", { })
	var axle_dict: Dictionary = tires.get(axle, { }) if tires.get(axle, { }) is Dictionary else { }
	var model_axle: Dictionary = axle_dict.get("radial_model", { }) if axle_dict.get("radial_model", { }) is Dictionary else { }
	var model := _merged(model_global, model_axle)
	var sidewall := float(g.sidewall_m)
	var reference_height := float(model.get("reference_sidewall_m", 0.1149))
	var geometry_scale := float(g.width_m) / maxf(float(model.get("reference_width_m", 0.2)), 0.05) * reference_height / maxf(
		sidewall,
		0.02,
	)
	var thermal_global: Dictionary = tires.get("thermal", { })
	var thermal_axle: Dictionary = axle_dict.get("thermal", { }) if axle_dict.get("thermal", { }) is Dictionary else { }
	var optimal := float(thermal_axle.get("optimal_carcass_temperature_c", thermal_global.get("optimal_carcass_temperature_c", 60.0)))
	var thermal_scale := clampf(1.0 - 0.0015 * (temperature_c - optimal), 0.88, 1.12)
	var carcass_k := float(model.get("carcass_stiffness_n_m", 30000.0)) * geometry_scale * thermal_scale
	var pressure_k := float(model.get("pressure_stiffness_n_m_per_kpa", 666.6666667)) * maxf(
		pressure_kpa,
		0.0,
	) * geometry_scale
	var stiffness := carcass_k + pressure_k
	var delta := maxf(deflection, 0.0)

	var seating_band := clampf(sidewall * 0.12, 0.006, 0.018)
	var effective_delta := delta - 0.35 * seating_band * (1.0 - exp(-delta / seating_band))
	var seating_tangent_scale := 1.0 - 0.35 * exp(-delta / seating_band)

	var fraction := clampf(float(model.get("rim_stop_start_sidewall_fraction", 0.75)), 0.4, 0.95)
	var start := sidewall * fraction
	var band := maxf(sidewall - start, 0.005)
	var over := maxf(delta - start, 0.0)
	var stop_k := float(model.get("rim_stop_stiffness_n_m", 300000.0))
	var stop_force := 0.5 * stop_k * over * over / band if over < band else stop_k * (
		over - 0.5 * band
	)
	var stop_tangent := stop_k * minf(over / band, 1.0)
	var tangent := stiffness * seating_tangent_scale + stop_tangent

	var base_damping_ratio := maxf(float(model.get("damping_ratio", 0.12)), 0.18)
	var critical_damping := 2.0 * sqrt(tangent * maxf(unsprung_mass, 1.0))
	var damping := critical_damping * base_damping_ratio
	var ramp_m := maxf(float(model.get("damping_contact_ramp_m", 0.015)), 0.012)
	var contact_fraction := clampf(delta / ramp_m, 0.0, 1.0)
	damping *= contact_fraction * contact_fraction * (3.0 - 2.0 * contact_fraction)

	var elastic := stiffness * effective_delta + stop_force
	var effective_speed := speed if speed >= 0.0 else speed * 0.45
	var viscous := damping * clampf(effective_speed, -8.0, 8.0)
	var force := maxf(elastic + viscous, elastic * 0.15) if delta > 0.0 else 0.0
	var dissipation := absf(viscous * speed) if delta > 0.0 else 0.0

	return {
		"force_n": force,
		"stiffness_n_m": stiffness,
		"tangent_n_m": tangent,
		"damping_ns_m": damping,
		"carcass_stiffness_n_m": carcass_k,
		"pressure_stiffness_n_m": pressure_k,
		"rim_radius_m": g.rim_radius_m,
		"sidewall_m": sidewall,
		"rim_stop_force_n": stop_force,
		"dissipation_w": dissipation,
	}


static func _merged(global_dict: Dictionary, axle_dict: Dictionary) -> Dictionary:
	var out := (global_dict as Dictionary).duplicate(true)
	for k in axle_dict:
		out[k] = axle_dict[k]
	return out
