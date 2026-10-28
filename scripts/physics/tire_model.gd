class_name TireModel
extends RefCounted

var parameters: Dictionary

func evaluate(longitudinal_slip: float, lateral_slip: float, normal_load: float, friction: float) -> Vector2:
	var response: Dictionary = parameters.get("force_model", {}).get("rear", {})
	var peak_longitudinal := maxf(float(response.get("longitudinal_peak_slip_ratio", 0.2)), 0.000001)
	var peak_lateral := maxf(float(response.get("lateral_peak_slip_angle_rad", 0.18)), 0.000001)
	var rise := 1.8
	var falloff := float(response.get("falloff_sharpness", 1.2))
	var longitudinal_coefficient := pure_curve(absf(longitudinal_slip), peak_longitudinal, float(response.get("longitudinal_slide_mu_ratio", 0.95)), rise, falloff)
	var lateral_coefficient := pure_curve(absf(lateral_slip), peak_lateral, float(response.get("lateral_slide_mu_ratio", 0.94)), rise, falloff)
	var longitudinal_normalized := longitudinal_coefficient * signf(longitudinal_slip)
	var lateral_normalized := lateral_coefficient * signf(lateral_slip)
	var utilization := Vector2(longitudinal_normalized, lateral_normalized).length()
	var scale := combined_budget_scale(utilization, float(response.get("budget_blend_width", 0.15)))
	return Vector2(longitudinal_normalized, lateral_normalized) * normal_load * friction * scale

func pure_curve(slip: float, peak: float, slide_ratio: float, rise: float, sharpness: float) -> float:
	var normalized := slip / peak
	if normalized <= 1.0:
		return clampf(1.0 - pow(1.0 - normalized, maxf(rise, 1.2)), 0.0, 1.0)
	var distance := clampf(sharpness, 0.1, 16.0) * (normalized - 1.0)
	var decay := distance * distance / (1.0 + distance * distance)
	return clampf(slide_ratio + (1.0 - slide_ratio) * (1.0 - decay), 0.0, 1.0)

func combined_budget_scale(utilization: float, blend_width: float) -> float:
	var value := maxf(utilization, 0.0)
	var width := clampf(blend_width, 0.0, 0.5)
	if width <= 0.000000001:
		return 1.0 / value if value > 1.0 else 1.0
	var lower := 1.0 - width
	var upper := 1.0 + width
	if value <= lower:
		return 1.0
	if value >= upper:
		return 1.0 / value
	var amount := (value - lower) / (upper - lower)
	var amount_squared := amount * amount
	var amount_cubed := amount_squared * amount
	var endpoint := 1.0 / upper
	var slope := -1.0 / (upper * upper)
	var result := (2.0 * amount_cubed - 3.0 * amount_squared + 1.0) + (-2.0 * amount_cubed + 3.0 * amount_squared) * endpoint + (amount_cubed - amount_squared) * (upper - lower) * slope
	return clampf(result, endpoint, 1.0)
