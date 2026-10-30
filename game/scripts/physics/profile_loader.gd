class_name VehicleProfileLoader
extends RefCounted

const REQUIRED_DOMAINS := [
	"aerodynamics", "brakes", "chassis", "coupled_world", "driving_assistance",
	"fuel", "powertrain", "steering", "suspension", "suspension_filters",
	"tire_filters", "tires", "underfloor_contact",
]
const EXPECTED_COORDINATES := {"forward": "-Z", "right": "+X", "up": "+Y"}


static func load_profile(manifest_path: String) -> Dictionary:
	var manifest_result := _read_json(manifest_path)
	if not bool(manifest_result.get("ok", false)):
		return manifest_result
	var manifest: Dictionary = manifest_result["value"]
	if str(manifest.get("units", "")) != "SI":
		return _failure("Profile units must be SI.")
	if manifest.get("coordinate_contract", {}) != EXPECTED_COORDINATES:
		return _failure("Profile coordinate contract must be forward -Z, right +X, up +Y.")
	if int(manifest.get("schema_version", 0)) < 1:
		return _failure("Profile schema_version must be positive.")
	var domain_paths: Variant = manifest.get("domains", null)
	if not domain_paths is Dictionary:
		return _failure("vehicle.json is missing its domains object.")
	for domain_name in REQUIRED_DOMAINS:
		if not domain_paths.has(domain_name):
			return _failure("vehicle.json is missing required domain: " + domain_name)

	var domains: Dictionary = {}
	var domain_hashes: Dictionary = {"vehicle.json": manifest_result["sha256"]}
	var base_path := manifest_path.get_base_dir()
	for domain_name in domain_paths:
		var relative_path := str(domain_paths[domain_name]).replace("\\", "/")
		if relative_path.is_empty() or relative_path.begins_with("/") or relative_path.contains(".."):
			return _failure("Unsafe relative profile path for domain " + str(domain_name))
		var domain_path := base_path.path_join(relative_path)
		var domain_result := _read_json(domain_path)
		if not bool(domain_result.get("ok", false)):
			return _failure("Domain '" + str(domain_name) + "': " + str(domain_result.get("error", "load failed")))
		var domain_value: Variant = domain_result["value"]
		if not domain_value is Dictionary:
			return _failure("Domain '" + str(domain_name) + "' must contain a JSON object.")
		domains[str(domain_name)] = domain_value
		domain_hashes[str(domain_name)] = domain_result["sha256"]

	var suspension_doc: Dictionary = domains["suspension"]
	var suspension: Dictionary = suspension_doc.get("suspension", {})
	if str(suspension.get("contact_query_type", "")) != "ShapeCast3D" or int(suspension.get("contact_shape_count", -1)) != 1:
		return _failure("This vehicle contract requires one ShapeCast3D per wheel.")
	var inventory: Dictionary = domains["chassis"].get("physical_mass_inventory", {})
	if not inventory.get("components", []) is Array or inventory.get("components", []).is_empty():
		return _failure("chassis.physical_mass_inventory.components is required.")
	var powertrain: Dictionary = domains["powertrain"].get("powertrain", {})
	if not powertrain.get("gear_ratios", []) is Array or powertrain.get("gear_ratios", []).is_empty():
		return _failure("powertrain.gear_ratios is required.")

	var resolved_filters := _resolve_tire_filters(domains["tires"], domains["tire_filters"])
	return {
		"ok": true,
		"manifest": manifest,
		"domains": domains,
		"domain_hashes": domain_hashes,
		"resolved_tire_filters": resolved_filters,
		"profile_id": str(manifest.get("vehicle_identifier", "")),
	}


static func _resolve_tire_filters(tire_doc: Dictionary, filter_doc: Dictionary) -> Dictionary:
	# Open Formula's version-3 legacy-profile conversion treats tire_filters.json as
	# an optional override layer over tires.force_model. Missing override keys keep
	# their tires.json values. The separate surface transition tau overrides the
	# tires.json value when present.
	var tires: Dictionary = tire_doc.get("tires", {})
	var force_model: Dictionary = tires.get("force_model", {})
	var filters: Dictionary = filter_doc.get("tire_filters", {})
	var resolved: Dictionary = {}
	for axle in ["front", "rear"]:
		var profile: Dictionary = force_model.get(axle, {}).duplicate(true)
		var overrides: Dictionary = filters.get(axle, {})
		for key in overrides:
			profile[key] = overrides[key]
		resolved[axle] = profile
	resolved["surface_transition_tau_s"] = float(filters.get(
		"surface_transition_tau_s",
		tires.get("surface_transition_tau_s", 0.0)
	))
	return resolved


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("JSON file not found: " + path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Cannot open JSON file: " + path)
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var parser := JSON.new()
	var error := parser.parse(bytes.get_string_from_utf8())
	if error != OK:
		return _failure("Invalid JSON in " + path + ": " + parser.get_error_message())
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(bytes)
	return {"ok": true, "value": parser.data, "sha256": hash_context.finish().hex_encode()}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
