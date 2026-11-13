class_name TireRadialModel
extends RefCounted

# Caché de geometría/modelo por eje para evitar recomputar merges en el bucle
# de subpasos (hasta 500 Hz x 4 ruedas). Clave: axle + hash ligero del dict.
static var _geom_cache: Dictionary = {}
static var _model_cache: Dictionary = {}


static func geometry(tire: Dictionary) -> Dictionary:
	var radius := float(tire.get("radius", 0.28))
	var rim_radius := float(tire.get("rim_diameter_inches", 13.0)) * 0.0254 * 0.5
	return {
		"radius_m": radius,
		"rim_radius_m": rim_radius,
		"sidewall_m": maxf(radius - rim_radius, 0.03),
		"width_m": float(tire.get("width", 0.2)),
	}


# Coeficientes radiales preparados una sola vez por solución (§closure-2):
# evita reevaluar diccionarios dentro de la bisección. Incluye seating,
# tope de llanta, escala térmica y geométrica ya resueltas.
static func prepare_coefficients(
	tires: Dictionary,
	axle: String,
	pressure_kpa: float,
	temperature_c: float,
	resolved_optimum_c: float = INF,
) -> Dictionary:
	var g := geometry(tires.get(axle, { }))
	var axle_dict: Dictionary = tires.get(axle, { }) if tires.get(axle, { }) is Dictionary else { }
	var axle_radial_hash := 0
	if axle_dict.has("radial_model") and (axle_dict.get("radial_model", {}) is Dictionary):
		axle_radial_hash = (axle_dict.get("radial_model", {}) as Dictionary).hash()
	var cache_key := axle + ":" + str((tires.get("radial_model", {}) as Dictionary).hash()) + ":" + str(axle_radial_hash)
	var model: Dictionary = _model_cache.get(cache_key, {})
	if model.is_empty():
		var model_global: Dictionary = tires.get("radial_model", { })
		var model_axle: Dictionary = axle_dict.get("radial_model", { }) if axle_dict.get("radial_model", { }) is Dictionary else { }
		model = _merged(model_global, model_axle)
		_model_cache[cache_key] = model
		if _model_cache.size() > 32:
			_model_cache.clear()
	var sidewall := float(g.sidewall_m)
	var reference_height := float(model.get("reference_sidewall_m", 0.1149))
	var geometry_scale := float(g.width_m) / maxf(float(model.get("reference_width_m", 0.2)), 0.05) * reference_height / maxf(
		sidewall,
		0.02,
	)
	var thermal_global: Dictionary = tires.get("thermal", { })
	var thermal_axle: Dictionary = axle_dict.get("thermal", { }) if axle_dict.get("thermal", { }) is Dictionary else { }
	var optimal := float(thermal_axle.get("optimal_carcass_temperature_c", thermal_global.get("optimal_carcass_temperature_c", 60.0)))
	if is_finite(resolved_optimum_c):
		optimal = resolved_optimum_c
	var thermal_scale := clampf(1.0 - 0.0015 * (temperature_c - optimal), 0.88, 1.12)
	var carcass_k := float(model.get("carcass_stiffness_n_m", 30000.0)) * geometry_scale * thermal_scale
	var pressure_k := float(model.get("pressure_stiffness_n_m_per_kpa", 666.6666667)) * maxf(
		pressure_kpa,
		0.0,
	) * geometry_scale
	var stiffness := carcass_k + pressure_k
	var seating_band := clampf(sidewall * 0.12, 0.006, 0.018)
	var fraction := clampf(float(model.get("rim_stop_start_sidewall_fraction", 0.75)), 0.4, 0.95)
	var start := sidewall * fraction
	var band := maxf(sidewall - start, 0.005)
	var stop_k := float(model.get("rim_stop_stiffness_n_m", 300000.0))
	return {
		"sidewall_m": sidewall,
		"stiffness_n_m": stiffness,
		"carcass_stiffness_n_m": carcass_k,
		"pressure_stiffness_n_m": pressure_k,
		"seating_band_m": seating_band,
		"rim_stop_start_m": start,
		"rim_stop_band_m": band,
		"rim_stop_k_n_m": stop_k,
		"rim_radius_m": g.rim_radius_m,
	}


# Fuerza elástica F_elástica(δ) monótona con seating + tope (§closure-2).
# Sin viscosidad: la rutina compartida para referencia estática y fallback.
static func elastic_force_n(coeffs: Dictionary, deflection_m: float) -> float:
	var delta := maxf(deflection_m, 0.0)
	if delta <= 0.0:
		return 0.0
	var seating_band := float(coeffs.get("seating_band_m", 0.012))
	var stiffness := float(coeffs.get("stiffness_n_m", 30000.0))
	var effective_delta := delta - 0.35 * seating_band * (1.0 - exp(-delta / maxf(seating_band, 1.0e-6)))
	var stop_k := float(coeffs.get("rim_stop_k_n_m", 300000.0))
	var start := float(coeffs.get("rim_stop_start_m", 0.08))
	var band := maxf(float(coeffs.get("rim_stop_band_m", 0.02)), 0.005)
	var over := maxf(delta - start, 0.0)
	var stop_force := 0.5 * stop_k * over * over / band if over < band else stop_k * (
		over - 0.5 * band
	)
	return stiffness * effective_delta + stop_force


# Inversión F_elástica(δ) = Fz por bisección monótona (§closure-2).
# Presión y óptima ya resueltas en coeffs. Si Fz supera la fuerza en el
# límite admitido, satura en ese límite. Máx 24 iteraciones, sin dicts.
static func invert_deflection_m(coeffs: Dictionary, load_n: float, max_deflection_m: float) -> float:
	var target := maxf(load_n, 0.0)
	if target <= 0.0:
		return 0.0
	var hi := maxf(max_deflection_m, 0.001)
	var f_hi := elastic_force_n(coeffs, hi)
	if target >= f_hi:
		return hi
	var lo := 0.0
	for i in 24:
		var mid := (lo + hi) * 0.5
		if elastic_force_n(coeffs, mid) < target:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


static func evaluate(
	tires: Dictionary,
	axle: String,
	pressure_kpa: float,
	temperature_c: float,
	unsprung_mass: float,
	deflection: float,
	speed: float,
	resolved_optimum_c: float = INF,
	viscous_scale: float = 1.0,
) -> Dictionary:
	var coeffs := prepare_coefficients(tires, axle, pressure_kpa, temperature_c, resolved_optimum_c)
	var g := geometry(tires.get(axle, { }))
	var axle_dict: Dictionary = tires.get(axle, { }) if tires.get(axle, { }) is Dictionary else { }
	var cache_key := axle + ":" + str((tires.get("radial_model", {}) as Dictionary).hash()) + ":" + str((axle_dict.get("radial_model", {}) as Dictionary).hash() if axle_dict.has("radial_model") else 0)
	var model: Dictionary = _model_cache.get(cache_key, {})
	if model.is_empty():
		var model_global: Dictionary = tires.get("radial_model", { })
		var model_axle: Dictionary = axle_dict.get("radial_model", { }) if axle_dict.get("radial_model", { }) is Dictionary else { }
		model = _merged(model_global, model_axle)
		_model_cache[cache_key] = model
	var sidewall := float(coeffs.sidewall_m)
	var stiffness := float(coeffs.stiffness_n_m)
	var carcass_k := float(coeffs.carcass_stiffness_n_m)
	var pressure_k := float(coeffs.pressure_stiffness_n_m)
	var delta := maxf(deflection, 0.0)

	var seating_band := float(coeffs.seating_band_m)
	var seating_tangent_scale := 1.0 - 0.35 * exp(-delta / maxf(seating_band, 1.0e-6))

	var start := float(coeffs.rim_stop_start_m)
	var band := maxf(float(coeffs.rim_stop_band_m), 0.005)
	var over := maxf(delta - start, 0.0)
	var stop_k := float(coeffs.rim_stop_k_n_m)
	var stop_tangent := stop_k * minf(over / band, 1.0)
	var tangent := stiffness * seating_tangent_scale + stop_tangent

	# Piso de amortiguación 0.18: mínimo de estabilidad a 60 Hz con tangente
	# al entrar el tope. Revisado §4.3: no bajar sin revalidar el rig a paso
	# físico completo (el tope dispara la tangente a rim_stop_stiffness).
	var base_damping_ratio := maxf(float(model.get("damping_ratio", 0.12)), 0.18)
	# Estabilidad al entrar el tope: la tangente para amortiguación se acota a
	# 2.5x la rigidez lineal + 5 kN/m. Sin esto el salto a 300 kN/m dispara c
	# y el rig a 60 Hz oscila. La fuerza sigue usando la tangente completa.
	var tangent_for_damping := minf(tangent, stiffness * 2.5 + 5000.0)
	var critical_damping := 2.0 * sqrt(maxf(tangent_for_damping, 1.0) * maxf(unsprung_mass, 1.0))
	var damping := critical_damping * base_damping_ratio
	var ramp_m := maxf(float(model.get("damping_contact_ramp_m", 0.015)), 0.012)
	var contact_fraction := clampf(delta / ramp_m, 0.0, 1.0)
	damping *= contact_fraction * contact_fraction * (3.0 - 2.0 * contact_fraction)

	var elastic := elastic_force_n(coeffs, delta)
	var stop_force := elastic - stiffness * (delta - 0.35 * seating_band * (1.0 - exp(-delta / maxf(seating_band, 1.0e-6))))
	var effective_speed := speed if speed >= 0.0 else speed * 0.45
	# Escala de diagnóstico (segunda prueba Fulvia 60 Hz): 1.0 = producción,
	# bit-idéntico. La sonda la pone a 0.0 en una variante para aislar el
	# término viscoso conservando elástica, tope y proyección unilateral.
	var viscous := damping * clampf(effective_speed, -8.0, 8.0) * float(viscous_scale)
	# Soporte falso eliminado: fuerza radial puede caer a cero en descarga
	# (maxf(..., 0.0), no 0.15x elástico). §4.3 verificado.
	# §closure-2: fuerza unilateral cero => disipación radial cero.
	var force := maxf(elastic + viscous, 0.0) if delta > 0.0 else 0.0
	var dissipation := 0.0
	if delta > 0.0 and force > 0.0:
		dissipation = maxf((force - elastic) * speed, 0.0)
	# Con contacto activo el signo se verifica: compresión (speed>0) y
	# rebote (speed<0) dan disipación >= 0 (viscoso*speed >= 0 salvo clamp).
	# Rigidez secante (fuerza/desplazamiento con seating+tope) vs lineal vs
	# tangente. La lineal (stiffness) es la base de construcción; la secante
	# es la que debe usarse para estimar deflexión Fz/k; la tangente es solo
	# para estabilidad/damping. Contrato §4.3: secante <= lineal <= tangente
	# (con tope activo la tangente domina; con seating la secante cae).
	var secant := elastic / maxf(delta, 1.0e-6) if delta > 1.0e-9 else stiffness

	return {
		"force_n": force,
		"stiffness_n_m": stiffness,
		"secant_n_m": secant,
		"static_stiffness_n_m": stiffness,
		"tangent_n_m": tangent,
		"damping_ns_m": damping,
		"damping_tangent_n_m": tangent_for_damping,
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
