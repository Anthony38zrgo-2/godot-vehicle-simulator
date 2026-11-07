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

	if domains.has("damage"):
		var damage_validation := _validate_damage_domain(domains["damage"])
		if not bool(damage_validation.get("ok", false)):
			return damage_validation

	var resolved_filters := resolve_tire_filters(domains["tires"], domains["tire_filters"])
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
	return resolve_tire_filters(tire_doc, filter_doc)


static func resolve_tire_filters(tire_doc: Dictionary, filter_doc: Dictionary) -> Dictionary:
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


static func _validate_damage_domain(doc: Dictionary) -> Dictionary:
	if int(doc.get("schema_version", 0)) < 1:
		return _failure("damage.schema_version must be >= 1.")
	for category in ["collision", "landing"]:
		var section: Variant = doc.get(category, null)
		if not section is Dictionary:
			return _failure("damage." + category + " must be a dictionary.")
		var min_speed := float(section.get("minimum_speed_m_s", -1.0))
		var full_speed := float(section.get("full_severity_speed_m_s", -1.0))
		if not is_finite(min_speed) or not is_finite(full_speed) or min_speed <= 0.0 or full_speed <= min_speed:
			return _failure("damage." + category + ": 0.0 < minimum_speed_m_s < full_severity_speed_m_s required.")
		var max_rad := float(section.get("maximum_radiator_damage", -1.0))
		var max_eng := float(section.get("maximum_engine_damage", -1.0))
		if not is_finite(max_rad) or max_rad < 0.0 or max_rad > 1.0:
			return _failure("damage." + category + ".maximum_radiator_damage must be in [0.0, 1.0].")
		if not is_finite(max_eng) or max_eng < 0.0 or max_eng > 1.0:
			return _failure("damage." + category + ".maximum_engine_damage must be in [0.0, 1.0].")
		if category == "collision":
			var max_transmission := float(section.get("maximum_transmission_damage", 0.0))
			if not is_finite(max_transmission) or max_transmission < 0.0 or max_transmission > 1.0:
				return _failure("damage.collision.maximum_transmission_damage must be in [0.0, 1.0].")
		var exponent := float(section.get("severity_exponent", 0.0))
		if not is_finite(exponent) or exponent <= 0.0:
			return _failure("damage." + category + ".severity_exponent must be positive.")
		var weights: Variant = section.get("zone_weights", null)
		if not weights is Dictionary:
			return _failure("damage." + category + ".zone_weights must be a dictionary.")
		for zone_name in weights:
			var zw: Variant = weights[zone_name]
			if not zw is Dictionary:
				return _failure("damage." + category + ".zone_weights." + str(zone_name) + " must be a dictionary.")
			var zw_rad := float(zw.get("radiator", -1.0))
			var zw_eng := float(zw.get("engine", -1.0))
			if not is_finite(zw_rad) or zw_rad < 0.0 or zw_rad > 1.0 or not is_finite(zw_eng) or zw_eng < 0.0 or zw_eng > 1.0:
				return _failure("damage." + category + ".zone_weights." + str(zone_name) + " weights must be in [0.0, 1.0].")

	if doc.has("visual"):
		var visual: Variant = doc.visual
		if not visual is Dictionary:
			return _failure("damage.visual must be a dictionary.")
		for part in ["headlight", "windshield", "windshield_frontal", "hood", "trunk", "body"]:
			var threshold: Variant = visual.get(part, 0.55 if part == "windshield_frontal" else null)
			if not (threshold is float or threshold is int) or not is_finite(float(threshold)) or threshold <= 0.0 or threshold > 1.0:
				return _failure("damage.visual." + part + " must be in (0.0, 1.0].")

	if doc.has("wheel_collision"):
		var wheel: Variant = doc.wheel_collision
		if not wheel is Dictionary:
			return _failure("damage.wheel_collision must be a dictionary.")
		for key in ["lateral_reach_m", "radial_reach_margin_m", "minimum_impulse_ns", "puncture_speed_m_s", "cut_speed_m_s", "brake_damage_speed_m_s", "full_brake_damage_speed_m_s", "slow_leak_per_second", "fast_leak_per_second", "maximum_brake_loss_per_impact", "minimum_brake_factor", "rim_start_speed_m_s", "rim_full_speed_m_s", "alignment_start_speed_m_s", "alignment_full_speed_m_s", "maximum_toe_offset_deg"]:
			var value: Variant = wheel.get(key)
			if not (value is float or value is int) or not is_finite(float(value)) or float(value) <= 0.0:
				return _failure("damage.wheel_collision." + key + " must be positive and finite.")
		if wheel.cut_speed_m_s <= wheel.puncture_speed_m_s or wheel.full_brake_damage_speed_m_s <= wheel.brake_damage_speed_m_s or wheel.fast_leak_per_second <= wheel.slow_leak_per_second:
			return _failure("damage.wheel_collision requires increasing impact thresholds and leak rates.")
		if wheel.rim_full_speed_m_s <= wheel.rim_start_speed_m_s or wheel.alignment_full_speed_m_s <= wheel.alignment_start_speed_m_s:
			return _failure("damage.wheel_collision requires increasing rim and alignment impact thresholds.")
		if wheel.maximum_brake_loss_per_impact > 1.0 or wheel.minimum_brake_factor >= 1.0:
			return _failure("damage.wheel_collision brake factors are out of range.")

	var thermal: Variant = doc.get("thermal", null)
	if not thermal is Dictionary:
		return _failure("damage.thermal must be a dictionary.")
	var min_cooling := float(thermal.get("minimum_cooling_factor", 0.0))
	var min_torque := float(thermal.get("minimum_torque_factor", 0.0))
	if not is_finite(min_cooling) or min_cooling <= 0.0 or min_cooling > 1.0:
		return _failure("damage.thermal.minimum_cooling_factor must be in (0.0, 1.0].")
	if not is_finite(min_torque) or min_torque <= 0.0 or min_torque > 1.0:
		return _failure("damage.thermal.minimum_torque_factor must be in (0.0, 1.0].")
	var start_c := float(thermal.get("damage_start_c", 0.0))
	var full_c := float(thermal.get("full_rate_temperature_c", 0.0))
	if not is_finite(start_c) or not is_finite(full_c) or start_c >= full_c:
		return _failure("damage.thermal: damage_start_c < full_rate_temperature_c required.")
	var grace := float(thermal.get("grace_seconds", -1.0))
	var max_rate := float(thermal.get("maximum_damage_per_second", -1.0))
	if not is_finite(grace) or grace < 0.0 or not is_finite(max_rate) or max_rate < 0.0:
		return _failure("damage.thermal: grace_seconds and maximum_damage_per_second must be >= 0.0.")

	var steam: Variant = doc.get("steam", null)
	if not steam is Dictionary:
		return _failure("damage.steam must be a dictionary.")
	var s_start := float(steam.get("start_damage", -1.0))
	var s_cont := float(steam.get("continuous_damage", -1.0))
	var s_heavy := float(steam.get("heavy_damage", -1.0))
	if not is_finite(s_start) or not is_finite(s_cont) or not is_finite(s_heavy):
		return _failure("damage.steam damage thresholds must be finite.")
	if not (0.0 <= s_start and s_start < s_cont and s_cont < s_heavy and s_heavy <= 1.0):
		return _failure("damage.steam: 0.0 <= start_damage < continuous_damage < heavy_damage <= 1.0 required.")
	return {"ok": true}


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
