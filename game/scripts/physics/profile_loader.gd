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

	var tires: Dictionary = domains["tires"].get("tires", {})
	for axle in ["front", "rear"]:
		var tire: Dictionary = tires.get(axle, {})
		var geometry := TireRadialModel.geometry(tire)
		if not is_finite(float(geometry.radius_m)) or not is_finite(float(geometry.rim_radius_m)) or float(geometry.rim_radius_m) <= 0.0 or float(geometry.sidewall_m) <= 0.01 or not is_finite(float(geometry.width_m)) or float(geometry.width_m) <= 0.0:
			return _failure(axle + " tire requires a positive width and outer radius greater than rim radius + 10 mm.")
	var radial: Dictionary = tires.get("radial_model", {})
	for key in ["carcass_stiffness_n_m", "pressure_stiffness_n_m_per_kpa", "reference_sidewall_m", "reference_width_m", "damping_contact_ramp_m", "rim_stop_stiffness_n_m"]:
		var value := float(radial.get(key, 1.0))
		if not is_finite(value) or value <= 0.0:
			return _failure("tires.radial_model." + key + " must be finite and positive.")
	var zeta := float(radial.get("damping_ratio", 0.12))
	var stop_fraction := float(radial.get("rim_stop_start_sidewall_fraction", 0.75))
	if not is_finite(zeta) or zeta < 0.0 or not is_finite(stop_fraction) or stop_fraction <= 0.0 or stop_fraction >= 1.0:
		return _failure("Tire radial damping must be nonnegative and rim stop fraction must lie between zero and one.")
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


const TIRE_FORCE_KEYS := [
	"budget_blend_width",
	"combined_lateral_peak_migration",
	"combined_longitudinal_peak_migration",
	"contact_ramp_tau_s",
	"falloff_sharpness",
	"lateral_peak_slip_angle_rad",
	"lateral_slide_mu_ratio",
	"longitudinal_peak_slip_ratio",
	"longitudinal_slide_mu_ratio",
	"min_relaxation_tau_s",
	"relaxation_recovery_scale",
	"slip_loss_tau_s",
	"slip_recovery_tau_s",
]
const TIRE_SCALAR_KEYS := [
	"surface_transition_tau_s",
	"rolling_resistance_coefficient",
	"load_sensitivity_per_newton",
	"load_sensitivity_axle_mult",
	"pneumatic_trail_m",
	"camber_thrust_gain",
	"relaxation_length_scale",
	"contact_patch_load_gain",
	"contact_patch_deflection_gain",
]
const TIRE_NESTED_KEYS := [
	"surfaces",
	"thermal",
	"pressure_mechanics",
	"radial_model",
	"pressure",
]


static func _resolve_tire_filters(tire_doc: Dictionary, filter_doc: Dictionary) -> Dictionary:
	# tire_filters.json es una capa opcional sobre tires.json.
	# - Las claves de TIRE_FORCE_KEYS van a force_model por eje.
	# - surfaces/thermal/pressure_mechanics/radial_model/pressure por eje se
	#   fusionan (global -> tires eje -> filters eje).
	# - Los escalares por eje (taus, rolling, trail, camber, etc.) resuelven
	#   filters eje > tires eje > tires global > builtin (builtin en tire_model).
	# Sin overrides por eje, el comportamiento es idéntico al legacy global,
	# salvo que el delantero mantiene lateral_grip_assist=0 por compatibilidad
	# (ver TireModel._resolve_axle_surfaces).
	var tires: Dictionary = tire_doc.get("tires", {})
	var force_model: Dictionary = tires.get("force_model", {})
	var filters: Dictionary = filter_doc.get("tire_filters", {})
	var resolved: Dictionary = {}
	for axle in ["front", "rear"]:
		var profile: Dictionary = (force_model.get(axle, {}) as Dictionary).duplicate(true) if force_model.get(axle, {}) is Dictionary else {}
		var overrides: Dictionary = filters.get(axle, {}) if filters.get(axle, {}) is Dictionary else {}
		for key in overrides:
			if key in TIRE_FORCE_KEYS:
				profile[key] = overrides[key]
		resolved[axle] = profile
		# Superficies por eje: deep-merge global -> tires eje -> filters eje.
		var global_surfaces: Dictionary = tires.get("surfaces", {}) if tires.get("surfaces", {}) is Dictionary else {}
		var tires_axle: Dictionary = tires.get(axle, {}) if tires.get(axle, {}) is Dictionary else {}
		var axle_surfaces: Dictionary = tires_axle.get("surfaces", {}) if tires_axle.get("surfaces", {}) is Dictionary else {}
		var filter_surfaces: Dictionary = overrides.get("surfaces", {}) if overrides.get("surfaces", {}) is Dictionary else {}
		resolved[axle + "_surfaces"] = _merge_surfaces(global_surfaces, axle_surfaces, filter_surfaces)
		for nested in ["thermal", "pressure_mechanics", "radial_model", "pressure"]:
			var global_nested: Dictionary = tires.get(nested, {}) if tires.get(nested, {}) is Dictionary else {}
			var axle_nested: Dictionary = tires_nested(tires_axle, nested)
			var filter_nested: Dictionary = overrides.get(nested, {}) if overrides.get(nested, {}) is Dictionary else {}
			resolved[axle + "_" + nested] = _merge_flat(global_nested, axle_nested, filter_nested)
		var scalars := {}
		for key in TIRE_SCALAR_KEYS:
			if overrides.has(key):
				scalars[key] = overrides[key]
			elif tires_axle.has(key):
				scalars[key] = tires_axle[key]
			elif tires.has(key):
				scalars[key] = tires[key]
		resolved[axle + "_tire_scalars"] = scalars
	resolved["surface_transition_tau_s"] = float(filters.get(
		"surface_transition_tau_s",
		tires.get("surface_transition_tau_s", 0.0)
	))
	for axle in ["front", "rear"]:
		var axle_filters: Dictionary = filters.get(axle, {}) if filters.get(axle, {}) is Dictionary else {}
		var tires_axle: Dictionary = tires.get(axle, {}) if tires.get(axle, {}) is Dictionary else {}
		var tau_default := float(resolved.get("surface_transition_tau_s", 0.0))
		var tau_value := tau_default
		if axle_filters.has("surface_transition_tau_s"):
			tau_value = float(axle_filters.get("surface_transition_tau_s", tau_default))
		elif tires_axle.has("surface_transition_tau_s"):
			tau_value = float(tires_axle.get("surface_transition_tau_s", tau_default))
		resolved[axle + "_surface_transition_tau_s"] = tau_value
		var scalars: Dictionary = resolved.get(axle + "_tire_scalars", {})
		scalars["surface_transition_tau_s"] = tau_value
		resolved[axle + "_tire_scalars"] = scalars
	return resolved


static func tires_nested(tires_axle: Dictionary, key: String) -> Dictionary:
	var d: Variant = tires_axle.get(key, {})
	return (d as Dictionary).duplicate(true) if d is Dictionary else {}


static func _merge_flat(global_dict: Dictionary, axle_dict: Dictionary, filter_dict: Dictionary) -> Dictionary:
	var out := (global_dict as Dictionary).duplicate(true) if global_dict is Dictionary else {}
	if axle_dict is Dictionary:
		for k in axle_dict:
			out[k] = axle_dict[k]
	if filter_dict is Dictionary:
		for k in filter_dict:
			out[k] = filter_dict[k]
	return out


static func _merge_surfaces(global_dict: Dictionary, axle_dict: Dictionary, filter_dict: Dictionary) -> Dictionary:
	var out := {}
	var names := {}
	if global_dict is Dictionary:
		for k in global_dict:
			names[k] = true
	if axle_dict is Dictionary:
		for k in axle_dict:
			names[k] = true
	if filter_dict is Dictionary:
		for k in filter_dict:
			names[k] = true
	for surface_name in names:
		var base: Dictionary = ((global_dict.get(surface_name, {}) as Dictionary).duplicate(true) if global_dict.get(surface_name, {}) is Dictionary else {})
		var ax: Dictionary = axle_dict.get(surface_name, {}) if axle_dict.get(surface_name, {}) is Dictionary else {}
		var flt: Dictionary = filter_dict.get(surface_name, {}) if filter_dict.get(surface_name, {}) is Dictionary else {}
		for k in ax:
			base[k] = ax[k]
		for k in flt:
			base[k] = flt[k]
		out[surface_name] = base
	return out


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
