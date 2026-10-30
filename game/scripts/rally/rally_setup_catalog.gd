class_name RallySetupCatalog
extends RefCounted

const FIELDS: Array[Dictionary] = [
	{"page": 0, "label": "Frecuencia natural delantera", "path": "suspension.front.ride_frequency_hz", "min": 0.5, "max": 3.5, "step": 0.01, "suffix": " Hz", "scale": 1.0, "digits": 2, "group": "SUSPENSION DELANTERA", "default": 1.67},
	{"page": 0, "label": "Frecuencia natural trasera", "path": "suspension.rear.ride_frequency_hz", "min": 0.5, "max": 3.5, "step": 0.01, "suffix": " Hz", "scale": 1.0, "digits": 2, "group": "SUSPENSION TRASERA", "default": 1.70},
	{"page": 0, "label": "Altura de marcha delantera", "path": "suspension.front.resting_ratio", "min": 0.20, "max": 0.80, "step": 0.005, "suffix": "", "scale": 1.0, "digits": 3, "group": "SUSPENSION DELANTERA"},
	{"page": 0, "label": "Altura de marcha trasera", "path": "suspension.rear.resting_ratio", "min": 0.20, "max": 0.80, "step": 0.005, "suffix": "", "scale": 1.0, "digits": 3, "group": "SUSPENSION TRASERA"},
	{"page": 0, "label": "Relación de amortiguación delantera", "path": "suspension.front.damping_ratio", "min": 0.05, "max": 1.20, "step": 0.01, "suffix": "", "scale": 1.0, "digits": 2, "group": "SUSPENSION DELANTERA"},
	{"page": 0, "label": "Relación de amortiguación trasera", "path": "suspension.rear.damping_ratio", "min": 0.05, "max": 1.20, "step": 0.01, "suffix": "", "scale": 1.0, "digits": 2, "group": "SUSPENSION TRASERA"},
	{"page": 0, "label": "Compresión delantera", "path": "suspension.front.bump_damp_multiplier", "min": 0.20, "max": 3.00, "step": 0.01, "suffix": "x", "scale": 1.0, "digits": 2, "group": "SUSPENSION DELANTERA"},
	{"page": 0, "label": "Compresión trasera", "path": "suspension.rear.bump_damp_multiplier", "min": 0.20, "max": 3.00, "step": 0.01, "suffix": "x", "scale": 1.0, "digits": 2, "group": "SUSPENSION TRASERA"},
	{"page": 0, "label": "Rebote delantero", "path": "suspension.front.rebound_damp_multiplier", "min": 0.20, "max": 3.00, "step": 0.01, "suffix": "x", "scale": 1.0, "digits": 2, "group": "SUSPENSION DELANTERA"},
	{"page": 0, "label": "Rebote trasero", "path": "suspension.rear.rebound_damp_multiplier", "min": 0.20, "max": 3.00, "step": 0.01, "suffix": "x", "scale": 1.0, "digits": 2, "group": "SUSPENSION TRASERA"},
	{"page": 0, "label": "Barra estabilizadora delantera", "path": "suspension.geometry_physical.front_arb.ratio", "min": 0.00, "max": 2.00, "step": 0.01, "suffix": "", "scale": 1.0, "digits": 2, "group": "GEOMETRÍA"},
	{"page": 0, "label": "Barra estabilizadora trasera", "path": "suspension.geometry_physical.rear_arb.ratio", "min": 0.00, "max": 2.00, "step": 0.01, "suffix": "", "scale": 1.0, "digits": 2, "group": "GEOMETRÍA"},
	{"page": 1, "label": "Convergencia delantera", "path": "suspension.front.toe", "min": -0.05, "max": 0.05, "step": 0.001, "suffix": "°", "scale": 57.2957795, "digits": 2, "group": "GEOMETRÍA"},
	{"page": 1, "label": "Convergencia trasera", "path": "suspension.rear.toe", "min": -0.05, "max": 0.05, "step": 0.001, "suffix": "°", "scale": 57.2957795, "digits": 2, "group": "GEOMETRÍA"},
	{"page": 1, "label": "Caída delantera", "path": "suspension.front.camber", "min": -0.10, "max": 0.05, "step": 0.001, "suffix": "°", "scale": 57.2957795, "digits": 2, "group": "GEOMETRÍA"},
	{"page": 1, "label": "Caída trasera", "path": "suspension.rear.camber", "min": -0.10, "max": 0.05, "step": 0.001, "suffix": "°", "scale": 57.2957795, "digits": 2, "group": "GEOMETRÍA"},
	{"page": 0, "label": "Tope de suspensión delantero", "path": "suspension.front.bump_stop_multiplier", "min": 0.00, "max": 4.00, "step": 0.05, "suffix": "x", "scale": 1.0, "digits": 2, "group": "SUSPENSION DELANTERA"},
	{"page": 0, "label": "Tope de suspensión trasero", "path": "suspension.rear.bump_stop_multiplier", "min": 0.00, "max": 4.00, "step": 0.05, "suffix": "x", "scale": 1.0, "digits": 2, "group": "SUSPENSION TRASERA"},
	{"page": 1, "label": "Presión delantera izquierda", "path": "tires.pressure.cold_kpa_gauge.FL", "min": 80.0, "max": 220.0, "step": 1.0, "suffix": " kPa", "scale": 1.0, "digits": 0, "group": "NEUMÁTICOS"},
	{"page": 1, "label": "Presión delantera derecha", "path": "tires.pressure.cold_kpa_gauge.FR", "min": 80.0, "max": 220.0, "step": 1.0, "suffix": " kPa", "scale": 1.0, "digits": 0, "group": "NEUMÁTICOS"},
	{"page": 1, "label": "Presión trasera izquierda", "path": "tires.pressure.cold_kpa_gauge.RL", "min": 80.0, "max": 220.0, "step": 1.0, "suffix": " kPa", "scale": 1.0, "digits": 0, "group": "NEUMÁTICOS"},
	{"page": 1, "label": "Presión trasera derecha", "path": "tires.pressure.cold_kpa_gauge.RR", "min": 80.0, "max": 220.0, "step": 1.0, "suffix": " kPa", "scale": 1.0, "digits": 0, "group": "NEUMÁTICOS"},
	{"page": 1, "label": "Ala delantera", "path": "aero.model.front_wing.incidence_deg", "min": 0.0, "max": 20.0, "step": 0.5, "suffix": "°", "scale": 1.0, "digits": 1, "group": "AERODINÁMICA"},
	{"page": 1, "label": "Ala trasera", "path": "aero.model.rear_wing.incidence_deg", "min": 0.0, "max": 20.0, "step": 0.5, "suffix": "°", "scale": 1.0, "digits": 1, "group": "AERODINÁMICA"},
	{"page": 1, "label": "Reparto de frenada delantero", "path": "brakes.front_brake_bias", "min": 0.30, "max": 0.80, "step": 0.005, "suffix": "%", "scale": 100.0, "digits": 1, "group": "FRENOS"},
	{"page": 1, "label": "Par máximo de freno", "path": "brakes.max_brake_torque", "min": 500.0, "max": 8000.0, "step": 50.0, "suffix": " Nm", "scale": 1.0, "digits": 0, "group": "FRENOS"},
	{"page": 2, "label": "Régimen máximo", "path": "powertrain.max_rpm", "min": 6000.0, "max": 22000.0, "step": 100.0, "suffix": " rpm", "scale": 1.0, "digits": 0, "group": "MOTOR"},
	{"page": 2, "label": "Relación final", "path": "powertrain.final_drive", "min": 2.0, "max": 6.0, "step": 0.01, "suffix": "", "scale": 1.0, "digits": 2, "group": "TRANSMISIÓN"},
	{"page": 2, "label": "Precarga del diferencial", "path": "powertrain.differential.preload_nm", "min": 0.0, "max": 120.0, "step": 1.0, "suffix": " Nm", "scale": 1.0, "digits": 0, "group": "DIFERENCIAL"},
	{"page": 2, "label": "Rampa de aceleración", "path": "powertrain.differential.power_ramp_angle_deg", "min": 5.0, "max": 80.0, "step": 1.0, "suffix": "°", "scale": 1.0, "digits": 0, "group": "DIFERENCIAL"},
	{"page": 2, "label": "Rampa de retención", "path": "powertrain.differential.coast_ramp_angle_deg", "min": 5.0, "max": 80.0, "step": 1.0, "suffix": "°", "scale": 1.0, "digits": 0, "group": "DIFERENCIAL"},
	{"page": 2, "label": "Paquetes de discos", "path": "powertrain.differential.clutches", "min": 1.0, "max": 8.0, "step": 1.0, "suffix": "", "scale": 1.0, "digits": 0, "group": "DIFERENCIAL"},
	{"page": 0, "label": "Ángulo máximo de dirección", "path": "steering.max_steering_angle", "min": 0.15, "max": 0.70, "step": 0.005, "suffix": "°", "scale": 57.2957795, "digits": 1, "group": "DIRECCIÓN"},
	{"page": 2, "label": "Velocidad de dirección", "path": "steering.steering_speed", "min": 1.0, "max": 12.0, "step": 0.05, "suffix": " /s", "scale": 1.0, "digits": 2, "group": "DIRECCIÓN"},
	{"page": 3, "label": "Combustible inicial", "path": "fuel.initial_kg", "min": 0.0, "max": 120.0, "step": 0.5, "suffix": " kg", "scale": 1.0, "digits": 1, "group": "ESTRATEGIA"},
]

const PAGE_TITLES := ["SUSPENSIÓN", "AERO / RUEDAS", "MOTOR / TRANSMISIÓN", "ESTRATEGIA / BOXES", "REGLAJES"]


static func defaults(domains: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for field in FIELDS:
		var path: String = field.path
		var segments := _domain_segments(path)
		var value: Variant = _read_segments(domains, segments, 0)
		if value is int or value is float:
			result[path] = float(value)
	return result


static func apply(domains: Dictionary, values: Dictionary) -> Dictionary:
	var sanitized := validate(values)
	if not bool(sanitized.get("ok", false)):
		return sanitized
	for field in FIELDS:
		var path: String = field.path
		if not sanitized.values.has(path):
			continue
		var segments := _domain_segments(path)
		_write_segments(domains, segments, 0, float(sanitized.values[path]))
	# These two representations describe the same legacy anti-roll quantity. The
	# geometric control is the garage authority; copy it to the value read by the solver.
	var suspension: Dictionary = domains.get("suspension", {}).get("suspension", {})
	var physical: Dictionary = suspension.get("geometry_physical", {})
	for axle in ["front", "rear"]:
		var bar: Dictionary = physical.get(axle + "_arb", {})
		var tune: Dictionary = suspension.get(axle, {})
		tune["arb_ratio"] = float(bar.get("ratio", tune.get("arb_ratio", 0.0)))
		suspension[axle] = tune
		physical[axle + "_arb"] = bar
	suspension["geometry_physical"] = physical
	domains["suspension"]["suspension"] = suspension
	return {"ok": true, "values": sanitized.values}


static func validate(values: Dictionary) -> Dictionary:
	var allowed: Dictionary = {}
	for field in FIELDS:
		allowed[field.path] = field
	var result: Dictionary = {}
	for key in values:
		if not allowed.has(str(key)):
			return {"ok": false, "error": "Campo de reglaje no reconocido: " + str(key)}
		var value: Variant = values[key]
		if not (value is int or value is float) or not is_finite(float(value)):
			return {"ok": false, "error": "Valor numerico invalido en " + str(key)}
		var field: Dictionary = allowed[str(key)]
		result[str(key)] = snappedf(clampf(float(value), float(field.min), float(field.max)), float(field.step))
	for field in FIELDS:
		if not result.has(str(field.path)):
			if field.has("default"):
				result[str(field.path)] = float(field.default)
				continue
			return {"ok": false, "error": "El reglaje no incluye " + str(field.path)}
	return {"ok": true, "values": result}


static func fields_for_page(page: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for field in FIELDS:
		if int(field.page) == page:
			result.append(field)
	return result


static func field_for_path(path: String) -> Dictionary:
	for field in FIELDS:
		if str(field.path) == path:
			return field
	return {}


static func _domain_segments(path: String) -> PackedStringArray:
	var split := path.split(".")
	var domain_name := str(split[0])
	var source_domain := "aerodynamics" if domain_name == "aero" else domain_name
	var result := PackedStringArray([source_domain, domain_name])
	for index in range(1, split.size()):
		result.append(split[index])
	return result


static func _read_segments(node: Variant, segments: PackedStringArray, index: int) -> Variant:
	if index >= segments.size() or not node is Dictionary:
		return null
	var segment: String = segments[index]
	if not node.has(segment):
		return null
	return node[segment] if index == segments.size() - 1 else _read_segments(node[segment], segments, index + 1)


static func _write_segments(node: Dictionary, segments: PackedStringArray, index: int, value: float) -> void:
	if index == segments.size() - 1:
		node[segments[index]] = value
		return
	var child: Dictionary = node.get(segments[index], {})
	_write_segments(child, segments, index + 1, value)
	node[segments[index]] = child
