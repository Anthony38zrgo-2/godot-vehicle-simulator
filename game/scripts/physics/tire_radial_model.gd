class_name TireRadialModel
extends RefCounted


static func geometry(tire: Dictionary) -> Dictionary:
	var radius := float(tire.get("radius", 0.28))
	var rim_radius := float(tire.get("rim_diameter_inches", 13.0)) * 0.0254 * 0.5
	return {"radius_m": radius, "rim_radius_m": rim_radius, "sidewall_m": radius - rim_radius, "width_m": float(tire.get("width", 0.2))}


static func evaluate(tires: Dictionary, axle: String, pressure_kpa: float, temperature_c: float, unsprung_mass: float, deflection: float, speed: float) -> Dictionary:
	var g := geometry(tires.get(axle, {}))
	var model: Dictionary = tires.get("radial_model", {})
	var reference_height := float(model.get("reference_sidewall_m", 0.1149))
	var geometry_scale := float(g.width_m) / float(model.get("reference_width_m", 0.2)) * reference_height / maxf(float(g.sidewall_m), 0.001)
	var optimal := float(tires.get("thermal", {}).get("optimal_carcass_temperature_c", 60.0))
	var thermal_scale := clampf(1.0 - 0.0015 * (temperature_c - optimal), 0.88, 1.12)
	# Carcass supports load even with no air. Gauge pressure contributes continuously.
	var carcass_k := float(model.get("carcass_stiffness_n_m", 30000.0)) * geometry_scale * thermal_scale
	var pressure_k := float(model.get("pressure_stiffness_n_m_per_kpa", 666.6666667)) * maxf(pressure_kpa, 0.0) * geometry_scale
	var stiffness := carcass_k + pressure_k
	var delta := maxf(deflection, 0.0)
	var fraction := float(model.get("rim_stop_start_sidewall_fraction", 0.75))
	var start := float(g.sidewall_m) * fraction
	var band := maxf(float(g.sidewall_m) - start, 0.001)
	var over := maxf(delta - start, 0.0)
	var stop_k := float(model.get("rim_stop_stiffness_n_m", 300000.0))
	var stop_force := 0.5 * stop_k * over * over / band if over < band else stop_k * (over - 0.5 * band)
	var stop_tangent := stop_k * minf(over / band, 1.0)
	var tangent := stiffness + stop_tangent
	var damping_ratio := float(model.get("damping_ratio", 0.12))
	var damping := 2.0 * damping_ratio * sqrt(tangent * maxf(unsprung_mass, 0.001))
	# Fade damping at first contact to avoid a finite force jump at zero compression.
	var contact_fraction := clampf(delta / maxf(float(model.get("damping_contact_ramp_m", 0.005)), 0.0001), 0.0, 1.0)
	damping *= contact_fraction * contact_fraction * (3.0 - 2.0 * contact_fraction)
	var elastic := stiffness * delta + stop_force
	var force := maxf(elastic + damping * speed, 0.0) if delta > 0.0 else 0.0
	return {"force_n": force, "stiffness_n_m": stiffness, "tangent_n_m": tangent, "damping_ns_m": damping, "carcass_stiffness_n_m": carcass_k, "pressure_stiffness_n_m": pressure_k, "rim_radius_m": g.rim_radius_m, "sidewall_m": g.sidewall_m, "rim_stop_force_n": stop_force, "dissipation_w": maxf((force - elastic) * speed, 0.0) if delta > 0.0 else 0.0}
