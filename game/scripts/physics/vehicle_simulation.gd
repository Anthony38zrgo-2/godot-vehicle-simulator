class_name FordRallyVehicleSimulation
extends RefCounted

const PROFILE_PATH := "res://data/vehicles/ford-escort-rs2000/vehicle.json"
# preload directo: no depende de la caché global de clases del editor.
const RallyDifferentialCatalog = preload("res://scripts/rally/rally_differential_catalog.gd")
const TIRE_THERMAL_PERIOD := 1.0 / 30.0
const ENGINE_THERMAL_PERIOD := 1.0 / 20.0
const FUEL_PERIOD := 1.0 / 10.0

const WHEEL_KEYS := ["front_left", "front_right", "rear_left", "rear_right"]

var profile: Dictionary = { }
var domains: Dictionary = { }
var asset_manifest: Dictionary = { }
var domain_hashes: Dictionary = { }
var mass_model := VehicleMassModel.new()
var suspension_model := VehicleSuspensionModel.new()
var unsprung_rig := UnsprungSuspensionRig.new()
var tire_model := TireModel.new()
var powertrain_model := VehiclePowertrainModel.new()
var brake_model := VehicleBrakeModel.new()
var aero_model := VehicleAerodynamicModel.new()
var thermal_model := VehicleThermalModel.new()
var alignment_collision_damage: Array[float] = [0.0, 0.0, 0.0, 0.0]
var brake_collision_loss: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_positions_local: Array[Vector3] = []
var wheel_radii: Array[float] = []
var wheel_widths: Array[float] = []
var wheel_spins: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_slips: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var wheel_contact_points: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var wheel_contact_normals: Array[Vector3] = [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]
var wheel_surfaces: Array[String] = ["Unknown", "Unknown", "Unknown", "Unknown"]
var wheel_loads: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_visual_pivots: Array[Node3D] = []
var wheel_visuals: Array[Node3D] = []
var wheel_rotation_angles: Array[float] = [0.0, 0.0, 0.0, 0.0]
var contact_query_count: int = 0
var wheel_contact_casts: Array[ShapeCast3D] = []
var contact_frequency_samples: int = 0
var contact_frequency_elapsed_s: float = 0.0
var mass_state: Dictionary = { }
var maximum_substep_seconds: float = 0.002
var _tire_thermal_elapsed := 0.0
# Friction, brake and radial damping work, in joules per wheel.
var _wheel_thermal_work: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _engine_thermal_elapsed := 0.0
var _engine_thermal_inputs := Vector4.ZERO
var _fuel_elapsed := 0.0
var _fuel_work_j := 0.0
var last_step_seconds: float = 0.0
var published_state: Dictionary = { }
var publication_sequence: int = 0
var simulation_time_s: float = 0.0
var session_generation: int = 0
var setup_design_axles: Array[Dictionary] = []
var setup_design_values: Dictionary = { }
var wheelbase_m: float = 2.41
var ackermann: float = 0.18
var maximum_steering_angle_rad: float = 0.5585053606381855
var steering_exponent: float = 1.1
var front_steering_ratio: float = 1.0
var rear_steering_ratio: float = 0.0
var traction_control_enabled: bool = false
var stability_enabled: bool = false
var abs_enabled: bool = false
var assistance_available: Dictionary = { }
var underfloor_document: Dictionary = { }
var weather_controller = null
var puddle_system = null
const PuddleModel = preload("res://scripts/rally/rally_puddles.gd")
var active_compound_id: String = "gravel_normal"
var compound_catalog: Dictionary = {}
var last_local_conditions: Array = [{}, {}, {}, {}]
var last_puddle_depths_mm: Array[float] = [0.0, 0.0, 0.0, 0.0]
# v1 presets de diferencial: perfil activo y preset aplicado.
# El perfil activo nunca se toma de un payload: solo de configure().
const DIFFERENTIAL_PRESET_PATH := "powertrain.differential.preset_id"
const LEGACY_DIFFERENTIAL_PATHS: Array[String] = [
	"powertrain.differential.preload_nm",
	"powertrain.differential.power_ramp_angle_deg",
	"powertrain.differential.coast_ramp_angle_deg",
	"powertrain.differential.clutches",
]
var active_profile_id: String = ""
var active_differential_preset_id: String = ""


func configure(asset_document: Dictionary, manifest_path: String = PROFILE_PATH) -> Dictionary:
	asset_manifest = asset_document
	var loaded := VehicleProfileLoader.load_profile(manifest_path)
	if not bool(loaded.get("ok", false)):
		return loaded
	profile = loaded["manifest"]
	domains = loaded["domains"]
	domain_hashes = loaded["domain_hashes"]
	var mass_result := mass_model.configure(domains, asset_manifest)
	if not bool(mass_result.get("ok", false)):
		return mass_result
	mass_state = mass_model.resolve(mass_model.fuel_initial_kg)
	var suspension_result := suspension_model.configure(
		domains,
		asset_manifest.get("geometry", { }),
		mass_state,
	)
	if not bool(suspension_result.get("ok", false)):
		return suspension_result
	tire_model.configure(
		domains,
		loaded["resolved_tire_filters"],
		suspension_model.static_corner_loads_n,
	)
	var powertrain_result := powertrain_model.configure(domains)
	if not bool(powertrain_result.get("ok", false)):
		return powertrain_result
	brake_model.configure(domains)
	aero_model.configure(domains)
	var thermal_result := thermal_model.configure(domains)
	if not bool(thermal_result.get("ok", false)):
		return thermal_result
	underfloor_document = domains \
			.get("underfloor_contact", { }) \
			.get("underfloor_contact", { }) \
			.duplicate(true)
	var steering: Dictionary = domains.get("steering", { }).get("steering", { })
	maximum_steering_angle_rad = float(
		steering.get("max_steering_angle", maximum_steering_angle_rad)
	)
	steering_exponent = float(steering.get("steering_exponent", 1.0))
	front_steering_ratio = float(steering.get("front_steering_ratio", 1.0))
	rear_steering_ratio = float(steering.get("rear_steering_ratio", 0.0))
	ackermann = float(steering.get("ackermann", 0.0))
	var coupled: Dictionary = domains.get("coupled_world", { }).get("coupled_world", { })
	maximum_substep_seconds = maxf(float(coupled.get("maximum_substep_seconds", 0.002)), 0.0005)
	var coupled_suspension: Dictionary = coupled.get("suspension", { })
	maximum_substep_seconds = maxf(
		float(coupled_suspension.get("maximum_substep_seconds", maximum_substep_seconds)),
		0.0005,
	)
	var pivot_doc: Dictionary = asset_manifest.get("wheel_pivots", { })
	wheel_positions_local.clear()
	wheel_radii.clear()
	wheel_widths.clear()
	for key in WHEEL_KEYS:
		var wheel_doc: Dictionary = pivot_doc.get(key, { })
		wheel_positions_local.append(
			_vector_from_document(wheel_doc.get("center_metres", { }), Vector3.ZERO)
		)
		wheel_radii.append(float(wheel_doc.get("radius_metres", 0.28)))
		wheel_widths.append(float(wheel_doc.get("width_metres", 0.2)))
	if wheel_positions_local.size() != 4 or wheel_radii.size() != 4:
		return {
			"ok": false,
			"error": "Ford asset manifest must define four wheel pivots and radii.",
		}
	wheelbase_m = absf(wheel_positions_local[2].z - wheel_positions_local[0].z)
	var aids: Dictionary = domains.get("driving_assistance", { }).get("aids", { })
	assistance_available = {
		"traction_control": bool(aids.get("traction_control_available", false)),
		"stability": bool(aids.get("stability_available", false)),
		"anti_lock_brakes": bool(aids.get("abs_available", false)),
		"automatic_transmission": bool(powertrain_model.automatic_transmission),
	}
	active_profile_id = str(loaded.get("profile_id", ""))
	_apply_default_differential_preset()
	setup_design_values = filter_garage_values(RallySetupCatalog.defaults(domains))
	_capture_setup_design()
	set_compound(active_compound_id)
	return {
		"ok": true,
		"profile_id": str(loaded.get("profile_id", "")),
		"domain_hashes": domain_hashes.duplicate(true),
	}


func set_compound(compound_id: String, catalog: Dictionary = {}) -> void:
	var cid := str(compound_id) if str(compound_id) in ["gravel_normal", "gravel_wet"] else "gravel_normal"
	active_compound_id = cid
	if not catalog.is_empty():
		compound_catalog = (catalog as Dictionary).duplicate(true)
	if compound_catalog.is_empty() and FileAccess.file_exists("res://data/tires/rally_compounds.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/tires/rally_compounds.json"))
		if parsed is Dictionary:
			compound_catalog = parsed
	thermal_model.set_compound(cid, compound_catalog)
	tire_model.set_compound(cid, compound_catalog)


func get_compound_catalog() -> Dictionary:
	return RallyTireCompound.load_catalog()

func set_weather_controller(controller) -> void:
	weather_controller = controller


func local_conditions_for_wheel(index: int, surface_name: String) -> Dictionary:
	if index < 0 or index >= wheel_contact_points.size():
		return {}
	# Read-only query: step() owns the last completed wheel publication.
	return _local_conditions_at_contact(surface_name, wheel_contact_points[index], wheel_loads[index] > 0.0)


func _local_conditions_at_contact(surface_name: String, position: Vector3, loaded: bool) -> Dictionary:
	var local := {"air_c": thermal_model.ambient_temperature_c, "ground_c": 30.0,
		"water_mm": 0.0, "snow_mm": 0.0, "surface_name": surface_name,
		"puddle_depth_mm": 0.0, "puddle_drag": 0.0}
	if weather_controller != null and weather_controller.get("calendar_active"):
		var weather: Dictionary = weather_controller.call("local_conditions_for_contact", surface_name, position) if loaded else weather_controller.current_blend
		local.merge(weather, true)
	if loaded and is_instance_valid(puddle_system):
		var puddle: Dictionary = puddle_system.sample_contact(position)
		local["puddle_depth_mm"] = float(puddle.depth_mm)
		local["puddle_drag"] = float(puddle.drag)
		local["water_mm"] = maxf(float(local.get("water_mm", 0.0)), float(puddle.depth_mm))
	local["surface_name"] = surface_name
	return local


func surface_temperature_for_hud() -> Dictionary:
	if weather_controller != null and weather_controller.has_method("surface_temperature_at_vehicle"):
		return weather_controller.call("surface_temperature_at_vehicle")
	return {"ok": false, "text": "—"}


func adjust_live_tire_pressure(delta_kpa: float) -> void:
	var pressure: Dictionary = domains.get("tires", { }).get("tires", { }).get("pressure", { })
	var cold: Dictionary = pressure.get("cold_kpa_gauge", { })
	var atmosphere := float(pressure.get("atmospheric_pressure_kpa", 101.325)) / 100.0
	var reference_temp := float(pressure.get("reference_temperature_c", 25.0))
	for i in 4:
		var key: String = ["FL", "FR", "RL", "RR"][i]
		var field := RallySetupCatalog.field_for_path("tires.pressure.cold_kpa_gauge." + key)
		var next_kpa := clampf(
			float(cold.get(key, 180.0)) + delta_kpa,
			float(field.min),
			float(field.max),
		)
		cold[key] = next_kpa
		var tire: Dictionary = thermal_model.tire_states[i]
		tire.pressure_reference_bar_gauge = next_kpa / 100.0
		tire.pressure_reference_temp_c = reference_temp
		tire.pressure_bar_gauge = (1.0 - float(tire.get("pressure_loss_fraction", 0.0))) * maxf(
			(next_kpa / 100.0 + atmosphere) * (float(tire.gas_c) + 273.15)
			/ maxf(reference_temp + 273.15, 1.0)
			- atmosphere,
			0.0,
		)
		thermal_model.tire_states[i] = tire
	pressure["cold_kpa_gauge"] = cold


func active_differential_profile() -> String:
	if not active_profile_id.is_empty():
		return active_profile_id
	return str(profile.get("vehicle_identifier", ""))


## Modo dual de diferencial (v1):
## historic = presets de catálogo (solo si el perfil está cubierto);
## modern (defecto) = LSD autoblocante moderno totalmente configurable.
func is_historic_differential() -> bool:
	if RallyDifferentialCatalog.differential_mode() != RallyDifferentialCatalog.MODE_HISTORIC:
		return false
	return not RallyDifferentialCatalog.list_for_profile(active_differential_profile()).is_empty()


## Conjunto de valores apto para garaje/snapshots/fábrica según el modo:
## historic cubierto = preset + sin números libres; resto = números + sin preset.
func filter_garage_values(values: Dictionary) -> Dictionary:
	var out := values.duplicate(true)
	if is_historic_differential():
		for legacy_path in LEGACY_DIFFERENTIAL_PATHS:
			out.erase(legacy_path)
		out[DIFFERENTIAL_PRESET_PATH] = active_differential_preset_id
	else:
		out.erase(DIFFERENTIAL_PRESET_PATH)
	return out


func _base_differential_mu() -> Dictionary:
	return {
		"power": float(powertrain_model.base_differential_power_ratio),
		"coast": float(powertrain_model.base_differential_coast_ratio),
	}


func _sync_differential_to_domains(target_domains: Dictionary, resolved: Dictionary) -> void:
	var powertrain: Dictionary = (target_domains.get("powertrain", {}) as Dictionary).get("powertrain", {})
	var differential: Dictionary = powertrain.get("differential", {})
	differential["preset_id"] = str(resolved.get("preset_id", ""))
	differential["type"] = str(resolved.get("type", "clutch_lsd"))
	differential["preload_nm"] = float(resolved.get("preload_nm", 0.0))
	differential["power_ramp_angle_deg"] = float(resolved.get("power_ramp_deg", 45.0))
	differential["coast_ramp_angle_deg"] = float(resolved.get("coast_ramp_deg", 45.0))
	differential["clutches"] = float(resolved.get("active_friction_surfaces", 4))
	differential["clutch_friction_coefficient"] = float(resolved.get("friction_mu_power", 0.0))
	differential["coast_friction_coefficient"] = float(resolved.get("friction_mu_coast", 0.0))
	powertrain["differential"] = differential
	(target_domains.get("powertrain", {}) as Dictionary)["powertrain"] = powertrain


func _apply_default_differential_preset() -> void:
	if not is_historic_differential():
		return
	var pid := active_differential_profile()
	if pid.is_empty():
		return
	var powertrain: Dictionary = domains.get("powertrain", {}).get("powertrain", {})
	var differential: Dictionary = powertrain.get("differential", {})
	var configured_id := str(differential.get("preset_id", ""))
	var wanted := configured_id
	if wanted.is_empty() or not RallyDifferentialCatalog.is_allowed(pid, wanted):
		wanted = RallyDifferentialCatalog.default_for_profile(pid)
	if wanted.is_empty():
		return
	var resolved := RallyDifferentialCatalog.resolve(pid, wanted, _base_differential_mu())
	if not bool(resolved.get("ok", false)):
		push_warning("Diferencial por defecto no resoluble: " + str(resolved.get("error", "")))
		return
	_sync_differential_to_domains(domains, resolved)
	var runtime := powertrain_model.apply_differential_preset(resolved)
	if bool(runtime.get("ok", false)):
		active_differential_preset_id = wanted


func apply_setup_values(values: Dictionary) -> Dictionary:
	# Modo dual v1: historic = presets de catálogo (validación estricta);
	# modern (defecto) = LSD autoblocante moderno libre (números directos).
	# El perfil activo nunca sale del payload.
	var historic := is_historic_differential()
	var pid := active_differential_profile()
	if historic:
		for legacy_path in LEGACY_DIFFERENTIAL_PATHS:
			if values.has(legacy_path):
				return {
					"ok": false,
					"error": "Reglaje de diferencial antiguo incompatible: use el preset " + DIFFERENTIAL_PRESET_PATH + " o restaure fábrica.",
				}
	var incoming := values.duplicate(true)
	var requested_preset: Variant = null
	if historic and incoming.has(DIFFERENTIAL_PRESET_PATH):
		var requested: Variant = incoming[DIFFERENTIAL_PRESET_PATH]
		if not requested is String or (requested as String).is_empty():
			return {
				"ok": false,
				"error": "preset_id inválido.",
			}
		requested_preset = incoming[DIFFERENTIAL_PRESET_PATH]
	incoming.erase(DIFFERENTIAL_PRESET_PATH)
	var validation := RallySetupCatalog.validate(incoming)
	if not bool(validation.get("ok", false)):
		return validation
	var effective_values: Dictionary = (validation as Dictionary).get("values", {}).duplicate(true)
	effective_values["fuel.initial_kg"] = minf(
		float(effective_values.get("fuel.initial_kg", 0.0)),
		mass_model.fuel_capacity_kg,
	)
	# Resolver preset (solicitado > activo > defecto) sin mutar estado.
	var resolved_preset: Dictionary = {}
	if historic:
		var wanted := ""
		if requested_preset is String and not (requested_preset as String).is_empty():
			wanted = str(requested_preset)
		elif not active_differential_preset_id.is_empty():
			wanted = active_differential_preset_id
		else:
			wanted = RallyDifferentialCatalog.default_for_profile(pid)
		if wanted.is_empty():
			return {"ok": false, "error": "Sin preset de diferencial por defecto para: " + pid}
		if requested_preset is String and not (requested_preset as String).is_empty():
			if not RallyDifferentialCatalog.is_allowed(pid, wanted):
				return {"ok": false, "error": "Preset no permitido para este vehículo: " + wanted}
			if not RallyDifferentialCatalog.is_enabled(pid, wanted):
				return {"ok": false, "error": "Preset deshabilitado pendiente de calibración: " + wanted}
		resolved_preset = RallyDifferentialCatalog.resolve(pid, wanted, _base_differential_mu())
		if not bool(resolved_preset.get("ok", false)):
			return resolved_preset
	# Staging atómico: aplicar numérico + diferencial sobre copia.
	var staging := domains.duplicate(true)
	var applied := RallySetupCatalog.apply(staging, effective_values)
	if not bool(applied.get("ok", false)):
		return applied
	if historic:
		_sync_differential_to_domains(staging, resolved_preset)
	# Commit: a partir de aquí el runtime se sincroniza desde staging.
	domains = staging
	if historic:
		var runtime := powertrain_model.apply_differential_preset(resolved_preset)
		if not bool(runtime.get("ok", false)):
			return runtime
		active_differential_preset_id = str(resolved_preset.get("preset_id", ""))
		effective_values[DIFFERENTIAL_PRESET_PATH] = active_differential_preset_id
	else:
		# Modern: sin preset activo; el solver usa los números libres.
		active_differential_preset_id = ""
	var fuel: Dictionary = domains.get("fuel", { }).get("fuel", { })
	var fuel_kg := clampf(
		float(fuel.get("initial_kg", mass_model.fuel_initial_kg)),
		0.0,
		mass_model.fuel_capacity_kg,
	)
	mass_model.fuel_initial_kg = fuel_kg
	mass_state = mass_model.resolve(fuel_kg)
	thermal_model.fuel_remaining_litres = fuel_kg / maxf(
		mass_model.fuel_density_kg_per_litre,
		0.000001,
	)
	var suspension: Dictionary = domains.get("suspension", { }).get("suspension", { })
	var physical: Dictionary = suspension.get("geometry_physical", { })
	for axle_index in 2:
		var axle := "front" if axle_index == 0 else "rear"
		var trim: Dictionary = suspension.get(axle, { })
		var design: Dictionary = setup_design_axles[axle_index]
		var stop_base := maxf(float(design.get("stop_multiplier", 1.0)), 0.000001)
		var stop_multiplier := float(trim.get("bump_stop_multiplier", stop_base)) / stop_base
		var bump_stop_mult := float(design.get("physical_bump_stop_multiplier", 1.0)) * stop_multiplier
		for wheel_index in ([0, 1] if axle_index == 0 else [2, 3]):
			var parameters: Dictionary = suspension_model.axle_parameters[wheel_index]
			parameters.camber = float(trim.get("camber", 0.0))
			parameters.toe = float(trim.get("toe", 0.0))
			var current_rest := float(trim.get("spring_length", 0.3)) * float(
				trim.get("resting_ratio", 0.35)
			)
			parameters.rest_compression_offset = current_rest - float(
				design.get("rest_compression", current_rest)
			)
			var reference_mass := float(parameters.frequency_reference_mass_kg)
			var frequency := float(trim.get("ride_frequency_hz", parameters.ride_frequency_hz))
			var derived_k := reference_mass * pow(TAU * frequency, 2.0)
			var critical_c := 2.0 * sqrt(derived_k * reference_mass)
			parameters.ride_frequency_hz = frequency
			parameters.spring_rate = derived_k
			parameters.bump_damping = critical_c * float(trim.get("damping_ratio", 0.65)) * float(
				trim.get("bump_damp_multiplier", 1.0)
			)
			parameters.rebound_damping = critical_c * float(trim.get("damping_ratio", 0.65)) * float(
				trim.get("rebound_damp_multiplier", 1.0)
			)
			parameters.bump_stop_stiffness = derived_k * bump_stop_mult * 8.0
			suspension_model.axle_parameters[wheel_index] = parameters
		var arb: Dictionary = physical.get(axle + "_arb", { })
		var spring_rate := float(suspension_model.axle_parameters[axle_index * 2].spring_rate)
		if axle_index == 0:
			suspension_model.front_arb_stiffness_n_per_m = spring_rate * float(
				arb.get("ratio", 0.0)
			)
		else:
			suspension_model.rear_arb_stiffness_n_per_m = spring_rate * float(arb.get("ratio", 0.0))
	var brakes: Dictionary = domains.get("brakes", { }).get("brakes", { })
	brake_model.front_brake_bias = clampf(float(brakes.get("front_brake_bias", 0.5)), 0.0, 1.0)
	brake_model.maximum_brake_torque_nm = float(
		brakes.get("max_brake_torque", brake_model.maximum_brake_torque_nm)
	)
	var powertrain: Dictionary = domains.get("powertrain", { }).get("powertrain", { })
	var differential: Dictionary = powertrain.get("differential", { })
	powertrain_model.maximum_rpm = float(powertrain.get("max_rpm", powertrain_model.maximum_rpm))
	powertrain_model.final_drive_gravel = float(powertrain.get("final_drive_gravel", powertrain_model.final_drive_gravel))
	powertrain_model.final_drive_tarmac = float(powertrain.get("final_drive_tarmac", powertrain_model.final_drive_tarmac))
	var _preset := str(powertrain.get("final_drive_preset", ""))
	if _preset == "gravel" and powertrain_model.final_drive_gravel > 0.0:
		powertrain_model.final_drive_ratio = powertrain_model.final_drive_gravel
	elif _preset == "tarmac" and powertrain_model.final_drive_tarmac > 0.0:
		powertrain_model.final_drive_ratio = powertrain_model.final_drive_tarmac
	else:
		powertrain_model.final_drive_ratio = float(
			powertrain.get("final_drive", powertrain_model.final_drive_ratio)
		)
	var _fw: Dictionary = powertrain.get("freewheel", {})
	if not _fw.is_empty():
		powertrain_model.freewheel_enabled = bool(_fw.get("enabled", powertrain_model.freewheel_enabled))
		powertrain_model.freewheel_idle_rpm = maxf(float(_fw.get("idle_rpm", powertrain_model.freewheel_idle_rpm)), 400.0)
	if powertrain.has("gear_ratios") and powertrain["gear_ratios"] is Array:
		var gr: Array = powertrain["gear_ratios"]
		powertrain_model.gear_ratios.clear()
		for r in gr:
			powertrain_model.gear_ratios.append(float(r))
		powertrain_model.maximum_forward_gear = powertrain_model.gear_ratios.size()
	if powertrain.has("reverse_ratio"):
		powertrain_model.reverse_ratio = -absf(float(powertrain.get("reverse_ratio", powertrain_model.reverse_ratio)))
	powertrain_model.differential_preload_nm = float(
		differential.get("preload_nm", powertrain_model.differential_preload_nm)
	)
	powertrain_model.differential_power_ratio = maxf(
		float(differential.get("clutch_friction_coefficient", powertrain_model.differential_power_ratio)),
		0.0
	)
	powertrain_model.differential_coast_ratio = maxf(
		float(differential.get("coast_friction_coefficient", powertrain_model.differential_power_ratio)),
		0.0
	)
	powertrain_model.differential_power_ramp_angle_deg = float(
		differential.get("power_ramp_angle_deg", powertrain_model.differential_power_ramp_angle_deg)
	)
	powertrain_model.differential_coast_ramp_angle_deg = float(
		differential.get("coast_ramp_angle_deg", powertrain_model.differential_coast_ramp_angle_deg)
	)
	powertrain_model.differential_clutches = float(
		differential.get("clutches", powertrain_model.differential_clutches)
	)
	powertrain_model.differential_slip_transition_threshold_rad_s = maxf(
		float(
			differential.get(
				"slip_transition_threshold_rad_s",
				powertrain_model.differential_slip_transition_threshold_rad_s,
			)
		),
		0.01,
	)
	powertrain_model.engine_rpm = minf(
		powertrain_model.engine_rpm,
		powertrain_model.maximum_rpm + 200.0,
	)
	var steering: Dictionary = domains.get("steering", { }).get("steering", { })
	maximum_steering_angle_rad = float(
		steering.get("max_steering_angle", maximum_steering_angle_rad)
	)
	var aero: Dictionary = domains.get("aerodynamics", { }).get("aero", { })
	aero_model.aero_model = aero.get("model", { }).duplicate(true)
	var pressure: Dictionary = domains.get("tires", { }).get("tires", { }).get("pressure", { })
	var cold_pressures: Dictionary = pressure.get("cold_kpa_gauge", { })
	var temperature_reference := float(pressure.get("reference_temperature_c", 25.0))
	var atmosphere_bar := float(pressure.get("atmospheric_pressure_kpa", 101.325)) / 100.0
	for wheel_index in 4:
		var wheel_key: String = ["FL", "FR", "RL", "RR"][wheel_index]
		var state: Dictionary = thermal_model.tire_states[wheel_index]
		var cold_bar := float(cold_pressures.get(wheel_key, 180.0)) / 100.0
		state.pressure_reference_bar_gauge = cold_bar
		state.pressure_reference_temp_c = temperature_reference
		var reference_kelvin := maxf(temperature_reference + 273.15, 1.0)
		var gas_kelvin := maxf(float(state.gas_c) + 273.15, 1.0)
		state.pressure_bar_gauge = maxf(
			(cold_bar + atmosphere_bar) * gas_kelvin / reference_kelvin - atmosphere_bar,
			0.0,
		)
		thermal_model.tire_states[wheel_index] = state
	return { "ok": true, "values": effective_values }


func _capture_setup_design() -> void:
	setup_design_axles.clear()
	var suspension: Dictionary = domains.get("suspension", { }).get("suspension", { })
	var physical: Dictionary = suspension.get("geometry_physical", { })
	for axle in ["front", "rear"]:
		var elements: Dictionary = physical.get(axle, { })
		var trim: Dictionary = suspension.get(axle, { })
		setup_design_axles.append(
			{
				"bump_damping": float(elements.get("damper_bump_Ns_per_m", 0.0)),
				"rebound_damping": float(elements.get("damper_rebound_Ns_per_m", 0.0)),
				"physical_bump_stop_multiplier": float(elements.get("bump_stop_mult", 1.0)),
				"damping_ratio": float(trim.get("damping_ratio", 1.0)),
				"bump_multiplier": float(trim.get("bump_damp_multiplier", 1.0)),
				"rebound_multiplier": float(trim.get("rebound_damp_multiplier", 1.0)),
				"stop_multiplier": float(trim.get("bump_stop_multiplier", 1.0)),
				"rest_compression": float(trim.get("spring_length", 0.3))
				* float(trim.get("resting_ratio", 0.35)),
			}
		)


func bind_wheel_visuals(pivots: Array[Node3D], visuals: Array[Node3D]) -> void:
	wheel_visual_pivots = pivots
	wheel_visuals = visuals


func create_wheel_contact_casts(body: RigidBody3D) -> void:
	unsprung_rig.create(body, wheel_positions_local, mass_model.unsprung_mass_kg, suspension_model)
	for old_cast in wheel_contact_casts:
		old_cast.queue_free()
	wheel_contact_casts.clear()
	for i in 4:
		var cast := ShapeCast3D.new()
		cast.name = "WheelContact_" + WHEEL_KEYS[i]
		var cylinder := CylinderShape3D.new()
		cylinder.radius = wheel_radii[i]
		cylinder.height = wheel_widths[i]
		cast.shape = cylinder
		cast.enabled = false
		cast.margin = 0.002
		cast.max_results = 8
		cast.collide_with_areas = false
		cast.collide_with_bodies = true
		body.add_child(cast)
		cast.add_exception_rid(body.get_rid())
		for hub in unsprung_rig.hubs:
			cast.add_exception_rid(hub.get_rid())
		wheel_contact_casts.append(cast)


func step(body: RigidBody3D, state: PhysicsDirectBodyState3D, inputs: Dictionary) -> void:
	var dt := state.step
	if dt <= 0.0 or wheel_positions_local.size() != 4 or wheel_contact_casts.size() != 4:
		return
	last_step_seconds = dt
	if contact_frequency_samples < 120:
		contact_frequency_samples += 1
		contact_frequency_elapsed_s += dt
		if contact_frequency_samples == 120:
			print(
				"RALLY_CONTACT_FREQUENCY ",
				JSON.stringify(
					{
						"query_type": "ShapeCast3D",
						"wheel_count": wheel_contact_casts.size(),
						"configured_hz": Engine.physics_ticks_per_second,
						"integration_hz": contact_frequency_samples / contact_frequency_elapsed_s,
						"dt_s": dt,
					}
				),
			)

	var chassis_up := state.transform.basis.y.normalized()
	var com_world := state.transform * body.center_of_mass
	var contacts: Array[Dictionary] = []
	contact_query_count = 0
	for i in 4:
		var cast := wheel_contact_casts[i]
		var bump := float(suspension_model.axle_parameters[i].get("bump_m", 0.22)) + 0.02
		var travel := bump + float(suspension_model.axle_parameters[i].get("droop_m", 0.18))
		var steer := _wheel_steer_angle(i, float(inputs.get("steering", 0.0))) + _effective_toe(i)
		var orientation := Basis(Vector3.UP, steer) * Basis(
			Vector3.FORWARD,
			suspension_model.dynamic_wheel_camber(i),
		) * Basis(Vector3.BACK, PI * 0.5)
		cast.global_transform = state.transform * Transform3D(
			orientation,
			wheel_positions_local[i] + Vector3.UP * bump,
		)
		cast.target_position = orientation.inverse() * (Vector3.DOWN * travel)
		cast.collision_mask = body.collision_mask
		cast.force_shapecast_update()
		var hit: Dictionary = { }
		var support := 0.25
		for collision_index in cast.get_collision_count():
			var normal := cast.get_collision_normal(collision_index).normalized()
			var alignment := normal.dot(chassis_up)
			if alignment > support:
				support = alignment
				hit = {
					"position": cast.get_collision_point(collision_index),
					"normal": normal,
					"collider": cast.get_collider(collision_index),
				}
		contact_query_count += 1
		if hit.is_empty():
			suspension_model.set_airborne(i)
			wheel_loads[i] = 0.0
			wheel_surfaces[i] = "Unknown"
			contacts.append({ "hit": false })
			continue
		var ray_distance: float = wheel_radii[i] + travel * cast.get_closest_collision_safe_fraction() - bump
		wheel_contact_points[i] = hit["position"]
		wheel_contact_normals[i] = (hit["normal"] as Vector3).normalized()
		wheel_surfaces[i] = _surface_for_collider(hit.get("collider"))
		contacts.append(
			{
				"hit": true,
				"position": wheel_contact_points[i],
				"normal": wheel_contact_normals[i],
				"distance": ray_distance,
				"surface": wheel_surfaces[i],
				"collider": hit.get("collider"),
			}
		)

	var normal_loads := unsprung_rig.solve(
		state,
		suspension_model,
		contacts,
		wheel_radii,
		domains,
		thermal_model,
	)
	var fade_factors: Array[float] = []
	for i in 4:
		fade_factors.append(thermal_model.brake_fade_factor(i))
	var brake_torques := brake_model.evaluate(
		float(inputs.get("brake", 0.0)),
		float(inputs.get("handbrake", 0.0)),
		fade_factors,
	)
	var brake_demand := brake_torques.duplicate()
	for i in 4:
		brake_torques[i] *= (1.0 - brake_collision_loss[i]) * thermal_model.brake_wear_factor(i)
	var tire_powers: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var count := maxi(1, ceili(dt / maximum_substep_seconds))
	var h := dt / float(count)
	var force_weight := 1.0 / float(count)

	var substep_linear_vel := state.linear_velocity
	var substep_angular_vel := state.angular_velocity
	var effective_chassis_mass := maxf(body.mass, 100.0)

	var tire_thermal_states: Array[Dictionary] = []
	var thermal_speeds: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_cambers: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_slip_speeds: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_surfaces: Array[String] = ["Gravel", "Gravel", "Gravel", "Gravel"]
	var thermal_vx: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_fy: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_water: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_snow: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_ground: Array[float] = [30.0, 30.0, 30.0, 30.0]
	var thermal_air: Array[float] = [25.0, 25.0, 25.0, 25.0]

	for i in 4:
		var contact: Dictionary = contacts[i]
		var loaded_contact := bool(contact.get("hit", false)) and normal_loads[i] > 0.0
		var local := _local_conditions_at_contact(str(contact.get("surface", "Unknown")), contact.get("position", wheel_contact_points[i]), loaded_contact)
		var current_puddle_depth := float(local.get("puddle_depth_mm", 0.0))
		var depth_rate := maxf(current_puddle_depth - last_puddle_depths_mm[i], 0.0) / maxf(dt, 0.001)
		last_puddle_depths_mm[i] = current_puddle_depth
		local["puddle_depth_rate"] = depth_rate
		thermal_water[i] = float(local.get("water_mm", 0.0))
		thermal_snow[i] = float(local.get("snow_mm", 0.0))
		thermal_ground[i] = float(local.get("ground_c", 30.0))
		thermal_air[i] = float(local.get("air_c", thermal_model.ambient_temperature_c))
		if loaded_contact:
			last_local_conditions[i] = local.duplicate(true)
		else:
			last_local_conditions[i] = {}
		thermal_model.advance_tire_pressure(i, dt)
		tire_thermal_states.append(thermal_model.get_tire_thermal_state_snapshot(i))

	_tire_thermal_elapsed += dt
	for _substep_index in count:
		_prepare_powertrain(h, inputs)
		var tire_reactions: Array[float] = [0.0, 0.0, 0.0, 0.0]
		var substep_force_sum := Vector3.ZERO

		for i in 4:
			var contact: Dictionary = contacts[i]
			tire_model.states[i].radial_deflection_m = unsprung_rig.radial_deflection_m[i]
			wheel_loads[i] = normal_loads[i]
			if not bool(contact.get("hit", false)) or normal_loads[i] <= 0.0:
				var free_thermal_state := tire_thermal_states[i]
				var free_result := tire_model.evaluate(
					i,
					0.0,
					"Gravel",
					0.0,
					0.0,
					wheel_spins[i],
					wheel_radii[i],
					0.0,
					thermal_model.tire_grip_factor(i),
					float(free_thermal_state.get("pressure_kpa_gauge", 180.0)),
					h,
					float(free_thermal_state.get("carcass_c", 25.0)),
				)
				wheel_slips[i] = Vector2(
					float(free_result.get("slip_ratio", 0.0)),
					float(free_result.get("slip_angle_rad", 0.0)),
				)
				tire_powers[i] = 0.0
				thermal_speeds[i] = substep_linear_vel.length()
				thermal_slip_speeds[i] = 0.0
				thermal_surfaces[i] = "Gravel"
				thermal_vx[i] = 0.0
				thermal_fy[i] = 0.0
				continue

			var point: Vector3 = contact["position"]
			var normal: Vector3 = contact["normal"]
			var road_velocity := Vector3.ZERO
			var collider: Object = contact.get("collider")
			if collider is RigidBody3D:
				var road_body := collider as RigidBody3D
				road_velocity = road_body.linear_velocity + road_body.angular_velocity.cross(
					point - road_body.global_position
				)

			var r_com := point - com_world
			var point_velocity := substep_linear_vel + substep_angular_vel.cross(r_com) - road_velocity
			var steer_angle := _wheel_steer_angle(i, float(inputs.get("steering", 0.0)))
			var toe := _effective_toe(i)
			var camber := suspension_model.dynamic_camber(i)
			var wheel_camber := suspension_model.dynamic_wheel_camber(i)

			var heading := (-state.transform.basis.z).rotated(chassis_up, steer_angle + toe)
			var forward := (heading - normal * heading.dot(normal)).normalized()
			if forward.length_squared() < 0.5:
				forward = (-state.transform.basis.z).normalized()
			var right := forward.cross(normal).normalized()

			var longitudinal_speed := point_velocity.dot(forward)
			var lateral_speed := point_velocity.dot(right)
			var normal_load := maxf(float(normal_loads[i]), 0.0)
			wheel_loads[i] = normal_load
			var thermal_state := tire_thermal_states[i]
			var local_water := thermal_water[i]
			var local_snow := thermal_snow[i]
			var local_ground := thermal_ground[i]
			tire_model.rotate_patch_frame(i, forward, right)
			var tire_result := _solve_contact_wheel(
				i,
				h,
				normal_load,
				str(contact["surface"]),
				longitudinal_speed,
				lateral_speed,
				camber,
				float(thermal_state.get("pressure_kpa_gauge", 180.0)),
				float(thermal_state.get("carcass_c", 25.0)),
				local_water,
				local_snow,
				local_ground,
			)
			var fx := float(tire_result.get("longitudinal_force_n", 0.0))
			var fy := float(tire_result.get("lateral_force_n", 0.0))
			var mz := float(tire_result.get("aligning_torque_nm", 0.0))
			var flat_drag := -clampf(longitudinal_speed, -1.0, 1.0) * normal_load * 0.045 * float(thermal_state.pressure_loss_fraction)
			var puddle_response := PuddleModel.contact_response(
				float(last_local_conditions[i].get("puddle_depth_mm", 0.0)),
				point_velocity.slide(normal).length(),
				str(tire_model.wheel_compounds[i].get("id", active_compound_id)) == "gravel_wet",
				normal_load,
				wheel_widths[i],
				float(last_local_conditions[i].get("puddle_drag", 0.0)),
				float(last_local_conditions[i].get("puddle_depth_rate", 0.0)),
				wheel_radii[i]
			)
			var sup_x := float(puddle_response.get("support_longitudinal", puddle_response.support))
			var sup_y := float(puddle_response.get("support_lateral", puddle_response.support))
			var drag_n := float(puddle_response.drag_n)
			last_local_conditions[i]["puddle_support"] = sup_x
			last_local_conditions[i]["puddle_drag_n"] = drag_n
			fx *= sup_x
			fy *= sup_y
			mz *= sup_y

			# Asymmetrical front wheel steering pull moment
			if i < 2 and drag_n > 0.0:
				var steer_sign := -1.0 if i == 0 else 1.0
				mz += float(puddle_response.get("steering_pull_nm", 0.0)) * steer_sign

			var tire_force := forward * (fx + flat_drag) + right * fy
			tire_force -= point_velocity.slide(normal).normalized() * drag_n
			var sat_torque := normal * mz

			if normal_load > 0.0:
				var spin := wheel_spins[i]
				var phase := wheel_rotation_angles[i] + spin * h * 0.5
				var vibration := float(thermal_state.rim_deformation) * minf(spin * spin * 0.025, normal_load * 0.12) * sin(phase)
				state.apply_force((tire_force + normal * vibration) * force_weight, point - state.transform.origin)
				state.apply_torque(sat_torque * force_weight)
				substep_force_sum += tire_force

			wheel_slips[i] = Vector2(
				float(tire_result.get("slip_ratio", 0.0)),
				float(tire_result.get("slip_angle_rad", 0.0)),
			)
			tire_powers[i] = float(tire_result.get("friction_power_w", 0.0)) * sup_x
			var hydro_wheel_torque := float(puddle_response.get("wheel_torque_nm", drag_n * 0.75 * wheel_radii[i])) * signf(longitudinal_speed)
			tire_reactions[i] = (fx + float(tire_result.get("rolling_force_n", 0.0))) * wheel_radii[i] + hydro_wheel_torque
			thermal_speeds[i] = point_velocity.length()
			thermal_cambers[i] = wheel_camber
			thermal_slip_speeds[i] = wheel_spins[i] * wheel_radii[i] - longitudinal_speed
			thermal_surfaces[i] = str(contact["surface"])
			thermal_vx[i] = longitudinal_speed
			thermal_fy[i] = fy

		var rotation := powertrain_model.solve_rotation(
			h,
			wheel_spins,
			mass_model.wheel_spin_inertia,
			tire_reactions,
			brake_torques,
		)
		var brake_work: Array = rotation.brake_work_j
		for i in 4:
			wheel_rotation_angles[i] = fposmod(wheel_rotation_angles[i] + wheel_spins[i] * h, TAU)
			var radial_power := unsprung_rig.radial_dissipation_w[i] if normal_loads[i] > 0.0 else 0.0
			_wheel_thermal_work[i] += Vector3(tire_powers[i] * h, float(brake_work[i]), radial_power * h)
		substep_linear_vel += (substep_force_sum / effective_chassis_mass) * h
		# The suspension and collision torques are solved by Jolt outside these
		# substeps, so keep angular velocity fixed rather than integrating only
		# the tire torques and creating an unbalanced prediction.

	if _tire_thermal_elapsed + 1.0e-6 >= TIRE_THERMAL_PERIOD:
		for i in 4:
			var average_power := _wheel_thermal_work[i] / _tire_thermal_elapsed
			thermal_model.advance_tire(
				i, average_power.x, average_power.y, thermal_speeds[i], _tire_thermal_elapsed,
				thermal_cambers[i], average_power.z, thermal_slip_speeds[i], thermal_surfaces[i],
				maxf(float(normal_loads[i]), 0.0), thermal_fy[i], wheel_spins[i], thermal_vx[i],
				wheel_radii[i], thermal_water[i], thermal_snow[i], thermal_ground[i], thermal_air[i], false,
			)
		_wheel_thermal_work.fill(Vector3.ZERO)
		_tire_thermal_elapsed = 0.0

	var velocity := state.linear_velocity
	if velocity.length_squared() > 0.01:
		var speed := velocity.length()
		var drag := aero_model.drag_force(speed) + thermal_model.cooling_drag_force_n
		state.apply_central_force(-velocity.normalized() * drag)
		for wing_effect in aero_model.wing_forces(velocity, state.transform.basis):
			var wing_position: Vector3 = state.transform.basis * (wing_effect.position as Vector3)
			state.apply_force(wing_effect.force, wing_position)
	var rpm := powertrain_model.engine_rpm
	var torque := powertrain_model.engine_torque_nm
	_engine_thermal_elapsed += dt
	_engine_thermal_inputs += Vector4(rpm, torque, velocity.length(), aero_model.air_density_kg_m3) * dt
	if _engine_thermal_elapsed + 1.0e-6 >= ENGINE_THERMAL_PERIOD:
		var average := _engine_thermal_inputs / _engine_thermal_elapsed
		thermal_model.advance_engine(_engine_thermal_elapsed, average.x, average.y, average.z, average.w)
		_engine_thermal_elapsed = 0.0
		_engine_thermal_inputs = Vector4.ZERO

	_fuel_elapsed += dt
	_fuel_work_j += maxf(torque * rpm * TAU / 60.0, 0.0) * dt
	if _fuel_elapsed + 1.0e-6 >= FUEL_PERIOD:
		_flush_fuel_work()
	if bool(inputs.get("automatic_transmission", false)):
		_update_automatic_shift(float(inputs.get("throttle", 0.0)))
	publication_sequence += 1
	if publication_sequence == 240:
		print(
			"RALLY_UNSPRUNG_STATE ",
			JSON.stringify(
				{
					"radial_deflection_m": unsprung_rig.radial_deflection_m,
					"suspension_compression_m": suspension_model.compression,
					"normal_load_n": normal_loads,
					"spring_force_n": unsprung_rig.spring_forces_n,
					"sprung_mass_kg": body.mass,
					"vehicle_mass_kg": mass_model
					.resolve(thermal_model.fuel_remaining_litres
					* mass_model.fuel_density_kg_per_litre)
					.vehicle_total_mass_kg,
				}
			),
		)
	simulation_time_s += dt
	var wheels: Array[Dictionary] = []
	for index in 4:
		var wheel := thermal_model.get_tire_thermal_state_snapshot(index)
		wheel.merge(
			{
				"brake_collision_loss": brake_collision_loss[index],
				"brake_demand": clampf(brake_demand[index] / maxf(brake_model.maximum_brake_torque_nm * 0.25, 1.0), 0.0, 1.0),
				"alignment_collision_damage": alignment_collision_damage[index],
				"surface": wheel_surfaces[index],
				"load_n": wheel_loads[index],
				"spin_rad_s": wheel_spins[index],
				"slip_ratio": wheel_slips[index].x,
				"slip_angle_rad": wheel_slips[index].y,
				"puddle_depth_mm": float(last_local_conditions[index].get("puddle_depth_mm", 0.0)),
				"water_mm": float(last_local_conditions[index].get("water_mm", 0.0)),
				"puddle_support": float(last_local_conditions[index].get("puddle_support", 1.0)),
				"puddle_drag_n": float(last_local_conditions[index].get("puddle_drag_n", 0.0)),
				"patch_pos": tire_model.states[index].patch_pos,
				"patch_energy_j": tire_model.states[index].patch_energy_j,
				"unsprung_mass_kg": mass_model.unsprung_mass_kg[index],
				"radial_deflection_m": unsprung_rig.radial_deflection_m[index],
				"radial": unsprung_rig.radial_states[index].duplicate(),
				"suspension_force_n": unsprung_rig.spring_forces_n[index],
			}
		)
		wheels.append(wheel)
	published_state = {
		"sequence": publication_sequence,
		"generation": session_generation,
		"time_s": simulation_time_s,
		"dt_s": dt,
		"rpm": powertrain_model.engine_rpm,
		"rpm_max": powertrain_model.maximum_rpm,
		"rpm_idle": powertrain_model.idle_rpm,
		"gear": powertrain_model.current_gear,
		"torque_nm": powertrain_model.engine_torque_nm,
		"autoblip_active": powertrain_model.autoblip_active,
		"autoblip_target_rpm": powertrain_model.autoblip_target_rpm,
		"autoblip_throttle": powertrain_model.autoblip_throttle,
		"freewheel_active": powertrain_model.freewheel_active,
		"freewheel_enabled": powertrain_model.freewheel_enabled,
		"final_drive": powertrain_model.final_drive_ratio,
		"shift_phase": powertrain_model.shift_phase,
		"pending_gear": powertrain_model.pending_gear,
		"clutch_engagement": powertrain_model.clutch_engagement,
		"clutch_torque_nm": powertrain_model.clutch_torque_nm,
		"clutch_slip_power_w": powertrain_model.clutch_slip_power_w,
		"input_shaft_rad_s": powertrain_model.input_shaft_omega_rad_s,
		"driveline": {
			"enabled": powertrain_model.driveline_compliance_enabled,
			"twist_rad": powertrain_model.driveline_twist_rad,
			"torque_nm": powertrain_model.driveline_torque_nm,
			"energy_j": powertrain_model.driveline_energy_j,
			"dissipation_w": powertrain_model.driveline_dissipation_w,
			"output_rad_s": powertrain_model.output_shaft_omega_rad_s,
		},
		"load": clampf(
			absf(powertrain_model.engine_torque_nm) / maxf(powertrain_model.peak_torque_nm, 1.0),
			0.0,
			1.0,
		),
		"speed_kph": state.linear_velocity.length() * 3.6,
		"throttle": float(inputs.get("throttle", 0.0)),
		"brake": float(inputs.get("brake", 0.0)),
		"steering": float(inputs.get("steering", 0.0)),
		"engine": thermal_model.get_engine_thermal_state_snapshot(),
		"damage": {
			"radiator": thermal_model.radiator_damage,
			"engine": thermal_model.engine_damage,
			"transmission": powertrain_model.transmission_damage,
			"overheat_exposure_s": thermal_model.overheat_exposure_s,
		},
		"fuel": thermal_model.get_fuel_state_snapshot(),
		"wheels": wheels,
		"contact_queries": contact_query_count,
		"aids": {
			"automatic_transmission": bool(inputs.get("automatic_transmission", false)),
			"traction_control": traction_control_enabled,
			"stability": stability_enabled,
			"anti_lock_brakes": abs_enabled,
		},
		"aids_available": assistance_available.duplicate(),
		"differential": {
			"preset_id": active_differential_preset_id,
			"profile_id": active_differential_profile(),
			"type": powertrain_model.differential_type,
			"diff_speed_rad_s": powertrain_model.last_diff_speed_rad_s,
			"lsd_capacity_nm": powertrain_model.last_lsd_capacity_nm,
			"lsd_torque_nm": powertrain_model.last_lsd_torque_nm,
			"lsd_saturation": powertrain_model.last_lsd_saturation,
		},
	}


func set_final_drive_preset(preset: String) -> bool:
	return powertrain_model.set_final_drive_preset(preset)


func _prepare_powertrain(delta: float, inputs: Dictionary) -> void:
	var clutch := clampf(float(inputs.get("clutch", 1.0)), 0.0, 1.0)
	var split := powertrain_model.front_torque_split
	var carrier := 0.5 * (
		split * (wheel_spins[0] + wheel_spins[1])
		+ (1.0 - split) * (wheel_spins[2] + wheel_spins[3])
	)
	powertrain_model.advance(
		delta,
		float(inputs.get("throttle", 0.0)),
		clutch,
		thermal_model.engine_torque_factor() if thermal_model.fuel_remaining_litres > 0.0 else 0.0,
		carrier,
	)


func update_wheel_visuals(steering_input: float) -> void:
	for i in mini(4, wheel_visual_pivots.size()):
		var steer_angle := _wheel_steer_angle(i, steering_input)
		var toe := _effective_toe(i)
		var wheel_camber := suspension_model.dynamic_wheel_camber(i)
		var pivot := wheel_visual_pivots[i]
		pivot.position = wheel_positions_local[i] + Vector3.UP * suspension_model.compression[i]
		pivot.rotation.y = steer_angle + toe
		if i < wheel_visuals.size():
			wheel_visuals[i].rotation = Vector3(wheel_rotation_angles[i], 0.0, wheel_camber)


func _effective_toe(index: int) -> float:
	var config: Dictionary = domains.get("damage", {}).get("wheel_collision", {})
	var inward := -1.0 if index in [0, 2] else 1.0
	var damage_offset := deg_to_rad(float(config.get("maximum_toe_offset_deg", 0.0))) * alignment_collision_damage[index]
	return suspension_model.dynamic_toe(index) + inward * damage_offset


func _wheel_steer_angle(index: int, input_value: float) -> float:
	var shaped := signf(input_value) * pow(absf(input_value), maxf(steering_exponent, 0.1))
	var center_angle := shaped * maximum_steering_angle_rad * front_steering_ratio
	if index >= 2:
		return shaped * maximum_steering_angle_rad * rear_steering_ratio
	if ackermann <= 0.0 or wheelbase_m <= 0.0:
		return center_angle
	var x := wheel_positions_local[index].x
	var correction := atan2(wheelbase_m * tan(center_angle), wheelbase_m + x * tan(center_angle))
	return lerp_angle(center_angle, correction, clampf(ackermann, 0.0, 1.0))


func _update_automatic_shift(throttle: float) -> void:
	if not powertrain_model.automatic_transmission or powertrain_model.shift_remaining_seconds > 0.0:
		return
	var normalized_rpm := powertrain_model.engine_rpm / maxf(powertrain_model.maximum_rpm, 1.0)
	if powertrain_model.current_gear == 0 and absf(wheel_spins[2]) * wheel_radii[2] > 1.0:
		powertrain_model.set_gear(1)
	elif (
		powertrain_model.current_gear < powertrain_model.maximum_forward_gear
		and normalized_rpm > (0.90 if throttle > 0.65 else 0.70)
	):
		powertrain_model.request_shift(1)
	elif powertrain_model.current_gear > 1 and normalized_rpm < 0.34:
		powertrain_model.request_shift(-1)


func _surface_for_collider(collider: Variant) -> String:
	if collider is Node:
		for surface_name in tire_model.surfaces:
			if collider.is_in_group(str(surface_name)):
				return str(surface_name)
		var surface_meta: Variant = collider.get_meta("surface", "")
		if tire_model.surfaces.has(str(surface_meta)):
			return str(surface_meta)
	return "Gravel" if tire_model.surfaces.has("Gravel") else str(tire_model.surfaces.keys()[0])


func _flush_fuel_work() -> void:
	if _fuel_elapsed > 0.0:
		thermal_model.advance_fuel(_fuel_work_j / _fuel_elapsed, _fuel_elapsed)
	_fuel_elapsed = 0.0
	_fuel_work_j = 0.0


func reset_dynamics() -> void:
	_flush_fuel_work()
	_tire_thermal_elapsed = 0.0
	_wheel_thermal_work.fill(Vector3.ZERO)
	_engine_thermal_elapsed = 0.0
	_engine_thermal_inputs = Vector4.ZERO
	unsprung_rig.reset()
	session_generation += 1
	simulation_time_s = 0.0
	published_state = { }
	wheel_spins.fill(0.0)
	wheel_slips.fill(Vector2.ZERO)
	wheel_loads.fill(0.0)
	wheel_rotation_angles.fill(0.0)
	wheel_contact_points.fill(Vector3.ZERO)
	wheel_contact_normals.fill(Vector3.UP)
	wheel_surfaces.fill("Unknown")
	brake_model.smoothed_service_input = 0.0
	brake_model.smoothed_handbrake_input = 0.0
	for i in 4:
		tire_model.reset_patch(i)
		suspension_model.compression[i] = 0.0
		suspension_model.compression_velocity[i] = 0.0
		suspension_model.contact_active[i] = false
		suspension_model.previous_samples[i] = false
		if i < wheel_visuals.size():
			wheel_visuals[i].rotation = Vector3.ZERO
	powertrain_model.current_gear = 0
	powertrain_model.engine_rpm = powertrain_model.idle_rpm
	powertrain_model.reset_shift()
	powertrain_model.engine_torque_nm = 0.0
	powertrain_model.engine_attack_limited_torque_nm = 0.0
	powertrain_model.clutch_engagement = 0.0
	powertrain_model.clutch_torque_nm = 0.0
	powertrain_model.input_shaft_omega_rad_s = 0.0
	powertrain_model.reset_compliance()
	powertrain_model.clutch_slip_power_w = 0.0


func _vector_from_document(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		return Vector3(
			float(value.get("x", fallback.x)),
			float(value.get("y", fallback.y)),
			float(value.get("z", fallback.z)),
		)
	return fallback


func _solve_contact_wheel(
	index: int,
	dt: float,
	load_n: float,
	surface: String,
	vx: float,
	vy: float,
	camber: float,
	pressure: float,
	carcass_temperature_c: float,
	water_mm: float = 0.0,
	snow_mm: float = 0.0,
	ground_c: float = 30.0,
) -> Dictionary:
	return tire_model.evaluate(
		index,
		load_n,
		surface,
		vx,
		vy,
		wheel_spins[index],
		wheel_radii[index],
		camber,
		thermal_model.tire_grip_factor(index),
		pressure,
		dt,
		carcass_temperature_c,
		water_mm,
		snow_mm,
		ground_c,
	)
