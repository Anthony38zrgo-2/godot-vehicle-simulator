class_name ServiceRepairCalculator
extends RefCounted
## Pure service calculating rally service park repair minutes, tire costs, and overtime penalties.

const _Catalog := preload("res://scripts/ui/services/menu_catalog_service.gd")


static func resolve_service_costs(window: Dictionary, event_doc: Dictionary = {}) -> Dictionary:
	var doc := _Catalog.get_service_parts()
	var defaults: Dictionary = doc.get("default_service_costs", {"inflate": 2, "rim": 5, "wheel_change": 1})
	var costs: Dictionary = (window.get("service_costs", {}) as Dictionary).duplicate()
	if costs.is_empty() and event_doc.has("tire_rules"):
		costs = ((event_doc.get("tire_rules", {}) as Dictionary).get("service_costs", {}) as Dictionary).duplicate()
	return {
		"inflate": int(costs.get("inflate", defaults.get("inflate", 2))),
		"rim": int(costs.get("rim", defaults.get("rim", 5))),
		"wheel_change": int(costs.get("wheel_change", defaults.get("wheel_change", 1))),
	}


static func get_parts_dict() -> Dictionary:
	var out := {}
	var doc := _Catalog.get_service_parts()
	for entry in doc.get("parts", []):
		if entry is Dictionary:
			out[str(entry.get("id", ""))] = [str(entry.get("label", "")), float(entry.get("max_minutes", 10.0))]
	return out


static func compute_overtime_penalty_seconds(total_minutes: float, limit_minutes: float, penalty_per_minute: int) -> int:
	var over := maxf(0.0, total_minutes - limit_minutes)
	return int(ceilf(over)) * maxi(0, penalty_per_minute)
