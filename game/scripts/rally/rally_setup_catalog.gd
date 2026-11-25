class_name RallySetupCatalog
extends RefCounted

const PRESSURE_MIN := 100.0
const PRESSURE_MAX := 200.0
const RAD_TO_DEG := 180.0 / PI
const ANGLE_STEP := PI / 1800.0
const POSITION_LABELS := ["Rígida", "Semi-rígida", "Equilibrada", "Semi-blanda", "Blanda"]
const SPRING_FACTORS := [1.20, 1.10, 1.0, 0.90, 0.80]
const ARB_FACTORS := [1.30, 1.15, 1.0, 0.85, 0.70]
const DIFFERENTIAL_PREFIX := "powertrain.differential."
const DIFFERENTIAL_PRESET_PATH := DIFFERENTIAL_PREFIX + "preset_id"

const FIELDS: Array[Dictionary] = [
	{"path": "garage.suspension", "min": 1, "max": 5, "step": 1, "suffix": "", "scale": 1, "digits": 0},
	{"path": "garage.front_arb", "min": 1, "max": 5, "step": 1, "suffix": "", "scale": 1, "digits": 0},
	{"path": "garage.rear_arb", "min": 1, "max": 5, "step": 1, "suffix": "", "scale": 1, "digits": 0},
	{"path": "suspension.front.camber", "min": -40.0 * ANGLE_STEP, "max": 0, "step": ANGLE_STEP, "suffix": "°", "scale": RAD_TO_DEG, "digits": 1},
	{"path": "suspension.rear.camber", "min": -40.0 * ANGLE_STEP, "max": 0, "step": ANGLE_STEP, "suffix": "°", "scale": RAD_TO_DEG, "digits": 1},
	{"path": "suspension.front.toe", "min": -10.0 * ANGLE_STEP, "max": 10.0 * ANGLE_STEP, "step": ANGLE_STEP, "suffix": "°", "scale": RAD_TO_DEG, "digits": 1},
	{"path": "suspension.rear.toe", "min": -10.0 * ANGLE_STEP, "max": 10.0 * ANGLE_STEP, "step": ANGLE_STEP, "suffix": "°", "scale": RAD_TO_DEG, "digits": 1},
	{"path": "garage.front_pressure", "min": PRESSURE_MIN, "max": PRESSURE_MAX, "step": 1, "suffix": " kPa", "scale": 1, "digits": 0},
	{"path": "garage.rear_pressure", "min": PRESSURE_MIN, "max": PRESSURE_MAX, "step": 1, "suffix": " kPa", "scale": 1, "digits": 0},
	{"path": "powertrain.max_rpm", "min": 0, "max": 10000, "step": 50, "suffix": " rpm", "scale": 1, "digits": 0},
	{"path": "garage.cooling", "min": 0, "max": 4, "step": 1, "suffix": "", "scale": 1, "digits": 0},
	{"path": "garage.lsd", "min": 0, "max": 1, "step": 1, "suffix": "", "scale": 1, "digits": 0},
	{"path": "powertrain.differential.clutches", "min": 2, "max": 8, "step": 2, "suffix": "", "scale": 1, "digits": 0},
	{"path": "powertrain.differential.power_ramp_angle_deg", "min": 45, "max": 90, "step": 5, "suffix": "°", "scale": 1, "digits": 0},
	{"path": "powertrain.differential.coast_ramp_angle_deg", "min": 45, "max": 90, "step": 5, "suffix": "°", "scale": 1, "digits": 0},
	{"page": 1, "label": "Reparto de frenada delantero", "path": "brakes.front_brake_bias", "min": 0.30, "max": 0.80, "step": 0.005, "suffix": "%", "scale": 100.0, "digits": 1, "group": "FRENOS"},
	{"page": 2, "label": "Relación final", "path": "powertrain.final_drive", "min": 2.0, "max": 6.0, "step": 0.01, "suffix": "", "scale": 1.0, "digits": 2, "group": "TRANSMISIÓN"},
	{"page": 3, "label": "Combustible inicial", "path": "fuel.initial_kg", "min": 5.0, "max": 55.0, "step": 0.5, "suffix": " kg", "scale": 1.0, "digits": 1, "group": "ESTRATEGIA", "default": 25.0},
]

const LEGACY_PATHS := [
	"suspension.front.ride_frequency_hz",
	"suspension.rear.ride_frequency_hz",
	"suspension.front.resting_ratio",
	"suspension.rear.resting_ratio",
	"suspension.front.damping_ratio",
	"suspension.rear.damping_ratio",
	"suspension.front.bump_damp_multiplier",
	"suspension.rear.bump_damp_multiplier",
	"suspension.front.rebound_damp_multiplier",
	"suspension.rear.rebound_damp_multiplier",
	"suspension.geometry_physical.front_arb.ratio",
	"suspension.geometry_physical.rear_arb.ratio",
	"suspension.front.bump_stop_multiplier",
	"suspension.rear.bump_stop_multiplier",
	"tires.pressure.cold_kpa_gauge.FL",
	"tires.pressure.cold_kpa_gauge.FR",
	"tires.pressure.cold_kpa_gauge.RL",
	"tires.pressure.cold_kpa_gauge.RR",
	"aero.model.front_wing.incidence_deg",
	"aero.model.rear_wing.incidence_deg",
	"brakes.thermal.front_duct.opening",
	"brakes.thermal.rear_duct.opening",
	"brakes.max_brake_torque",
	"powertrain.gear_ratios.0",
	"powertrain.gear_ratios.1",
	"powertrain.gear_ratios.2",
	"powertrain.gear_ratios.3",
	"powertrain.reverse_ratio",
	"powertrain.differential.preload_nm",
	"steering.max_steering_angle",
	"steering.steering_speed",
]


static func defaults(domains: Dictionary) -> Dictionary:
	var result := {
		"garage.suspension": 3.0,
		"garage.front_arb": 3.0,
		"garage.rear_arb": 3.0,
		"garage.cooling": 0.0,
	}
	var powertrain: Dictionary = domains.get("powertrain", {}).get("powertrain", {})
	var differential: Dictionary = powertrain.get("differential", {})
	var open := str(differential.get("type", "clutch_lsd")) == "open"
	result["garage.lsd"] = 0.0 if open else 1.0
	for field in FIELDS:
		var path: String = field.path
		if path.begins_with("garage."):
			continue
		var value: Variant = _read_segments(domains, _domain_segments(path), 0)
		if open and path.begins_with(DIFFERENTIAL_PREFIX):
			value = 4.0 if path.ends_with(".clutches") else 45.0
		result[path] = float(value) if value is int or value is float else float(field.get("default", 0.0))
	var pressures: Dictionary = domains.get("tires", {}).get("tires", {}).get("pressure", {}).get("cold_kpa_gauge", {})
	result["garage.front_pressure"] = axle_pressure(pressures, "F")
	result["garage.rear_pressure"] = axle_pressure(pressures, "R")
	return result


static func axle_pressure(pressures: Dictionary, axle: String) -> float:
	return clampf((float(pressures.get(axle + "L", 180.0)) + float(pressures.get(axle + "R", 180.0))) * 0.5, PRESSURE_MIN, PRESSURE_MAX)


static func validate(values: Dictionary, design: Dictionary, stock_suspension: Dictionary) -> Dictionary:
	for raw_key in values:
		var key := str(raw_key)
		if key == DIFFERENTIAL_PRESET_PATH:
			continue
		if not key in LEGACY_PATHS and field_for_path(key).is_empty():
			return {"ok": false, "error": "Campo de reglaje no reconocido: " + key}
		var value: Variant = values[raw_key]
		if not (value is int or value is float) or not is_finite(float(value)):
			return {"ok": false, "error": "Valor numérico inválido en " + key}
	if not values.has("garage.suspension"):
		values = _migrate_suspension(values, stock_suspension)
	var result := design.duplicate()
	var has_old_preset := values.has(DIFFERENTIAL_PRESET_PATH)
	for field in FIELDS:
		var path: String = field.path
		if not values.has(path) or (has_old_preset and path.begins_with(DIFFERENTIAL_PREFIX)):
			continue
		result[path] = clamp_field(field_for_vehicle(path, design), float(values[path]), design)
	for axle in ["front", "rear"]:
		var path: String = "garage." + axle + "_pressure"
		var prefix := "tires.pressure.cold_kpa_gauge." + ("F" if axle == "front" else "R")
		if not values.has(path) and values.has(prefix + "L") and values.has(prefix + "R"):
			result[path] = clampf((float(values[prefix + "L"]) + float(values[prefix + "R"])) * 0.5, PRESSURE_MIN, PRESSURE_MAX)
	return {"ok": true, "values": result}


static func _migrate_suspension(values: Dictionary, stock: Dictionary) -> Dictionary:
	var migrated := values.duplicate()
	var spring_sum := 0.0
	var spring_count := 0
	var height_sum := 0.0
	var height_count := 0
	for axle in ["front", "rear"]:
		var tune: Dictionary = stock.get(axle, {})
		var frequency_path: String = "suspension." + axle + ".ride_frequency_hz"
		var frequency := maxf(float(tune.get("ride_frequency_hz", 1.0)), 0.01)
		var spring_factor := pow(float(values.get(frequency_path, frequency)) / frequency, 2.0)
		if values.has(frequency_path):
			spring_sum += spring_factor
			spring_count += 1
		var height_path: String = "suspension." + axle + ".resting_ratio"
		if values.has(height_path):
			height_sum += (float(tune.get("resting_ratio", 0.35)) - float(values[height_path])) * float(tune.get("spring_length", 0.3))
			height_count += 1
		var ratio_path: String = "suspension.geometry_physical." + axle + "_arb.ratio"
		var ratio := float(stock.get("geometry_physical", {}).get(axle + "_arb", {}).get("ratio", 0.0))
		var position_path: String = "garage." + axle + "_arb"
		if not values.has(position_path) and values.has(ratio_path):
			var factors := ARB_FACTORS if ratio > 0.0 else [0.10, 0.05, 0.0, 0.0, 0.0]
			var target := float(values[ratio_path]) * spring_factor
			migrated[position_path] = _nearest_position(factors, target / ratio if ratio > 0.0 else target)
	if not values.has("garage.suspension"):
		var spring_position := _nearest_position(SPRING_FACTORS, spring_sum / spring_count) if spring_count > 0 else 3.0
		if spring_position == 3.0 and height_count > 0:
			spring_position = clampf(3.0 + roundf(height_sum / height_count / 0.006), 1.0, 5.0)
		migrated["garage.suspension"] = spring_position
	return migrated


static func _nearest_position(factors: Array, target: float) -> float:
	var closest := 2
	for i in factors.size():
		if absf(float(factors[i]) - target) < absf(float(factors[closest]) - target):
			closest = i
	return float(closest + 1)


static func apply(domains: Dictionary, values: Dictionary) -> void:
	for path in values:
		if path.begins_with("garage.") or path == "powertrain.max_rpm" or path.begins_with(DIFFERENTIAL_PREFIX):
			continue
		_write_segments(domains, _domain_segments(path), 0, float(values[path]))


static func apply_pressures(domains: Dictionary, values: Dictionary) -> void:
	var tires: Dictionary = domains["tires"]["tires"]
	var pressure: Dictionary = tires.get("pressure", {})
	pressure["cold_kpa_gauge"] = {
		"FL": values["garage.front_pressure"], "FR": values["garage.front_pressure"],
		"RL": values["garage.rear_pressure"], "RR": values["garage.rear_pressure"],
	}
	tires["pressure"] = pressure


static func field_for_path(path: String) -> Dictionary:
	for field in FIELDS:
		if str(field.path) == path:
			return field
	return {}


static func field_for_vehicle(path: String, design: Dictionary) -> Dictionary:
	var field := field_for_path(path)
	if path == "powertrain.max_rpm" and design.has(path):
		field = field.duplicate()
		field.max = float(design[path])
		field.min = float(field.max) - floorf(float(field.max) * 0.10 / 50.0) * 50.0
	return field


static func clamp_field(field: Dictionary, value: float, design: Dictionary) -> float:
	if is_equal_approx(value, float(design.get(field.path, INF))):
		return value
	var minimum := float(field.min)
	var maximum := float(field.max)
	return clampf(minimum + snappedf(clampf(value, minimum, maximum) - minimum, float(field.step)), minimum, maximum)


static func _domain_segments(path: String) -> PackedStringArray:
	var split := path.split(".")
	var domain_name := str(split[0])
	var source_domain := "aerodynamics" if domain_name == "aero" else domain_name
	var result := PackedStringArray([source_domain, domain_name])
	for index in range(1, split.size()):
		result.append(split[index])
	return result


static func _read_segments(node: Variant, segments: PackedStringArray, index: int) -> Variant:
	if index >= segments.size() or node == null:
		return null
	var segment: String = segments[index]
	if node is Dictionary:
		var dict: Dictionary = node
		if not dict.has(segment):
			return null
		return dict[segment] if index == segments.size() - 1 else _read_segments(dict[segment], segments, index + 1)
	elif node is Array:
		var arr: Array = node
		var idx := segment.to_int()
		if idx < 0 or idx >= arr.size():
			return null
		return arr[idx] if index == segments.size() - 1 else _read_segments(arr[idx], segments, index + 1)
	return null


static func _write_segments(node: Variant, segments: PackedStringArray, index: int, value: float) -> void:
	if index >= segments.size() or node == null:
		return
	var segment: String = segments[index]
	if node is Dictionary:
		var dict: Dictionary = node
		if index == segments.size() - 1:
			dict[segment] = value
			return
		var child: Variant = dict.get(segment, null)
		if child == null:
			var next_is_int := (index + 1 < segments.size()) and segments[index + 1].is_valid_int()
			child = [] if next_is_int else {}
			dict[segment] = child
		_write_segments(child, segments, index + 1, value)
		dict[segment] = child
	elif node is Array:
		var arr: Array = node
		var idx := segment.to_int()
		while arr.size() <= idx:
			arr.append(0.0)
		if index == segments.size() - 1:
			arr[idx] = value
			return
		_write_segments(arr[idx], segments, index + 1, value)
