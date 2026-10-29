class_name VehicleAerodynamicModel
extends RefCounted

var air_density_kg_m3: float = 1.225
var frontal_area_m2: float = 0.0
var drag_coefficient: float = 0.0
var aero_model: Dictionary = {}


func configure(domains: Dictionary) -> void:
	var aero: Dictionary = domains.get("aerodynamics", {}).get("aero", {})
	air_density_kg_m3 = float(aero.get("air_density", 1.225))
	frontal_area_m2 = float(aero.get("frontal_area", 0.0))
	drag_coefficient = float(aero.get("drag_coefficient", 0.0))
	aero_model = aero.get("model", {}).duplicate(true)


func drag_force(speed_m_s: float) -> float:
	var dynamic_pressure := 0.5 * air_density_kg_m3 * speed_m_s * speed_m_s
	return dynamic_pressure * frontal_area_m2 * drag_coefficient


func wing_forces(speed_m_s: float, body_basis: Basis) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dynamic_pressure := 0.5 * air_density_kg_m3 * speed_m_s * speed_m_s
	for wing_key in ["front_wing", "rear_wing"]:
		var wing: Dictionary = aero_model.get(wing_key, {})
		if wing.is_empty():
			continue
		var area := maxf(float(wing.get("area_m2", 0.0)), 0.0)
		if area <= 0.0:
			continue
		var angle := clampf(float(wing.get("incidence_deg", 0.0)), float(wing.get("min_angle_deg", 0.0)), float(wing.get("max_angle_deg", 20.0)))
		var coefficients := _polar_at(wing.get("polar", []), angle)
		var force := -body_basis.y.normalized() * (dynamic_pressure * area * coefficients.x)
		var drag := -body_basis.z.normalized() * (dynamic_pressure * area * coefficients.y)
		var position: Vector3 = _vector3(wing.get("position_m", [0.0, 0.0, 0.0]))
		result.append({"force": force + drag, "position": position})
	return result


func _polar_at(polar: Variant, angle_deg: float) -> Vector2:
	if not polar is Array or polar.is_empty():
		return Vector2.ZERO
	var points: Array = polar
	if angle_deg <= float(points[0].get("angle_deg", 0.0)):
		return Vector2(float(points[0].get("cl", 0.0)), float(points[0].get("cd", 0.0)))
	for index in range(1, points.size()):
		var lower: Dictionary = points[index - 1]
		var upper: Dictionary = points[index]
		var upper_angle := float(upper.get("angle_deg", 0.0))
		if angle_deg <= upper_angle:
			var lower_angle := float(lower.get("angle_deg", 0.0))
			var blend := inverse_lerp(lower_angle, upper_angle, angle_deg) if upper_angle > lower_angle else 0.0
			return Vector2(lerpf(float(lower.get("cl", 0.0)), float(upper.get("cl", 0.0)), blend), lerpf(float(lower.get("cd", 0.0)), float(upper.get("cd", 0.0)), blend))
	var last: Dictionary = points[points.size() - 1]
	return Vector2(float(last.get("cl", 0.0)), float(last.get("cd", 0.0)))


func _vector3(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
