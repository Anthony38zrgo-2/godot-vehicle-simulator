class_name FordRallyVehicleSimulation
extends RefCounted

const PROFILE_PATH := "res://data/vehicles/ford-escort-rs2000/vehicle.json"
const WHEEL_KEYS := ["front_left", "front_right", "rear_left", "rear_right"]

var profile: Dictionary = {}
var domains: Dictionary = {}
var asset_manifest: Dictionary = {}
var domain_hashes: Dictionary = {}
var mass_model := VehicleMassModel.new()
var suspension_model := VehicleSuspensionModel.new()
var tire_model := TireModel.new()
var powertrain_model := VehiclePowertrainModel.new()
var brake_model := VehicleBrakeModel.new()
var aero_model := VehicleAerodynamicModel.new()
var thermal_model := VehicleThermalModel.new()
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
var mass_state: Dictionary = {}
var maximum_substep_seconds: float = 0.002
var last_step_seconds: float = 0.0
var published_state: Dictionary = {}
var publication_sequence: int = 0
var simulation_time_s: float = 0.0
var session_generation: int = 0
var setup_design_axles: Array[Dictionary] = []
var setup_design_values: Dictionary = {}
var wheelbase_m: float = 2.41
var ackermann: float = 0.18
var maximum_steering_angle_rad: float = 0.5585053606381855
var steering_exponent: float = 1.1
var front_steering_ratio: float = 1.0
var rear_steering_ratio: float = 0.0
var traction_control_enabled: bool = false
var stability_enabled: bool = false
var abs_enabled: bool = false
var assistance_available: Dictionary = {}
var underfloor_document: Dictionary = {}


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
	var suspension_result := suspension_model.configure(domains, asset_manifest.get("geometry", {}), mass_state)
	if not bool(suspension_result.get("ok", false)):
		return suspension_result
	tire_model.configure(domains, loaded["resolved_tire_filters"], suspension_model.static_corner_loads_n)
	var powertrain_result := powertrain_model.configure(domains)
	if not bool(powertrain_result.get("ok", false)):
		return powertrain_result
	brake_model.configure(domains)
	aero_model.configure(domains)
	var thermal_result := thermal_model.configure(domains)
	if not bool(thermal_result.get("ok", false)):
		return thermal_result
	underfloor_document = domains.get("underfloor_contact", {}).get("underfloor_contact", {}).duplicate(true)
	var steering: Dictionary = domains.get("steering", {}).get("steering", {})
	maximum_steering_angle_rad = float(steering.get("max_steering_angle", maximum_steering_angle_rad))
	steering_exponent = float(steering.get("steering_exponent", 1.0))
	front_steering_ratio = float(steering.get("front_steering_ratio", 1.0))
	rear_steering_ratio = float(steering.get("rear_steering_ratio", 0.0))
	ackermann = float(steering.get("ackermann", 0.0))
	var coupled: Dictionary = domains.get("coupled_world", {}).get("coupled_world", {})
	maximum_substep_seconds = maxf(float(coupled.get("maximum_substep_seconds", 0.002)), 0.0005)
	var coupled_suspension: Dictionary = coupled.get("suspension", {})
	maximum_substep_seconds = maxf(float(coupled_suspension.get("maximum_substep_seconds", maximum_substep_seconds)), 0.0005)
	var pivot_doc: Dictionary = asset_manifest.get("wheel_pivots", {})
	wheel_positions_local.clear()
	wheel_radii.clear()
	wheel_widths.clear()
	for key in WHEEL_KEYS:
		var wheel_doc: Dictionary = pivot_doc.get(key, {})
		wheel_positions_local.append(_vector_from_document(wheel_doc.get("center_metres", {}), Vector3.ZERO))
		wheel_radii.append(float(wheel_doc.get("radius_metres", 0.28)))
		wheel_widths.append(float(wheel_doc.get("width_metres", 0.2)))
	if wheel_positions_local.size() != 4 or wheel_radii.size() != 4:
		return {"ok": false, "error": "Ford asset manifest must define four wheel pivots and radii."}
	wheelbase_m = absf(wheel_positions_local[2].z - wheel_positions_local[0].z)
	var aids: Dictionary = domains.get("driving_assistance", {}).get("aids", {})
	assistance_available = {
		"traction_control": bool(aids.get("traction_control_available", false)),
		"stability": bool(aids.get("stability_available", false)),
		"anti_lock_brakes": bool(aids.get("abs_available", false)),
		"automatic_transmission": bool(powertrain_model.automatic_transmission),
	}
	setup_design_values = RallySetupCatalog.defaults(domains)
	_capture_setup_design()
	return {"ok": true, "profile_id": str(loaded.get("profile_id", "")), "domain_hashes": domain_hashes.duplicate(true)}


func apply_setup_values(values: Dictionary) -> Dictionary:
	var validation := RallySetupCatalog.validate(values)
	if not bool(validation.get("ok", false)):
		return validation
	var effective_values: Dictionary = validation.values.duplicate(true)
	effective_values["fuel.initial_kg"] = minf(float(effective_values.get("fuel.initial_kg", 0.0)), mass_model.fuel_capacity_kg)
	var applied := RallySetupCatalog.apply(domains, effective_values)
	if not bool(applied.get("ok", false)):
		return applied
	var suspension: Dictionary = domains.get("suspension", {}).get("suspension", {})
	var physical: Dictionary = suspension.get("geometry_physical", {})
	for axle_index in 2:
		var axle := "front" if axle_index == 0 else "rear"
		var trim: Dictionary = suspension.get(axle, {})
		var elements: Dictionary = physical.get(axle, {})
		var design: Dictionary = setup_design_axles[axle_index]
		var damping_base := maxf(float(design.get("damping_ratio", 1.0)), 0.000001)
		var bump_base := maxf(float(design.get("bump_multiplier", 1.0)), 0.000001)
		var rebound_base := maxf(float(design.get("rebound_multiplier", 1.0)), 0.000001)
		var stop_base := maxf(float(design.get("stop_multiplier", 1.0)), 0.000001)
		var damping_ratio := float(trim.get("damping_ratio", damping_base)) / damping_base
		var bump_multiplier := float(trim.get("bump_damp_multiplier", bump_base)) / bump_base
		var rebound_multiplier := float(trim.get("rebound_damp_multiplier", rebound_base)) / rebound_base
		var stop_multiplier := float(trim.get("bump_stop_multiplier", stop_base)) / stop_base
		var bump_coefficient := float(design.get("bump_damping", 0.0)) * damping_ratio * bump_multiplier
		var rebound_coefficient := float(design.get("rebound_damping", 0.0)) * damping_ratio * rebound_multiplier
		var bump_stop_mult := float(design.get("physical_bump_stop_multiplier", 1.0)) * stop_multiplier
		for wheel_index in ([0, 1] if axle_index == 0 else [2, 3]):
			var parameters: Dictionary = suspension_model.axle_parameters[wheel_index]
			parameters.bump_damping = bump_coefficient
			parameters.rebound_damping = rebound_coefficient
			parameters.bump_stop_stiffness = float(elements.get("spring_rate_N_per_m", 0.0)) * bump_stop_mult * 8.0
			parameters.camber = float(trim.get("camber", 0.0))
			parameters.toe = float(trim.get("toe", 0.0))
			var current_rest := float(trim.get("spring_length", 0.3)) * float(trim.get("resting_ratio", 0.35))
			parameters.rest_compression_offset = current_rest - float(design.get("rest_compression", current_rest))
			suspension_model.axle_parameters[wheel_index] = parameters
		var arb: Dictionary = physical.get(axle + "_arb", {})
		var spring_rate := float(elements.get("spring_rate_N_per_m", 0.0))
		if axle_index == 0:
			suspension_model.front_arb_stiffness_n_per_m = spring_rate * float(arb.get("ratio", 0.0))
		else:
			suspension_model.rear_arb_stiffness_n_per_m = spring_rate * float(arb.get("ratio", 0.0))
	var brakes: Dictionary = domains.get("brakes", {}).get("brakes", {})
	brake_model.front_brake_bias = clampf(float(brakes.get("front_brake_bias", 0.5)), 0.0, 1.0)
	brake_model.maximum_brake_torque_nm = float(brakes.get("max_brake_torque", brake_model.maximum_brake_torque_nm))
	var powertrain: Dictionary = domains.get("powertrain", {}).get("powertrain", {})
	var differential: Dictionary = powertrain.get("differential", {})
	powertrain_model.maximum_rpm = float(powertrain.get("max_rpm", powertrain_model.maximum_rpm))
	powertrain_model.final_drive_ratio = float(powertrain.get("final_drive", powertrain_model.final_drive_ratio))
	powertrain_model.differential_preload_nm = float(differential.get("preload_nm", powertrain_model.differential_preload_nm))
	powertrain_model.differential_power_ratio = float(differential.get("clutch_friction_coefficient", powertrain_model.differential_power_ratio))
	powertrain_model.differential_coast_ratio = powertrain_model.differential_power_ratio
	powertrain_model.differential_power_ramp_angle_deg = float(differential.get("power_ramp_angle_deg", powertrain_model.differential_power_ramp_angle_deg))
	powertrain_model.differential_coast_ramp_angle_deg = float(differential.get("coast_ramp_angle_deg", powertrain_model.differential_coast_ramp_angle_deg))
	powertrain_model.differential_clutches = float(differential.get("clutches", powertrain_model.differential_clutches))
	powertrain_model.differential_slip_transition_threshold_rad_s = maxf(float(differential.get("slip_transition_threshold_rad_s", powertrain_model.differential_slip_transition_threshold_rad_s)), 0.01)
	powertrain_model.engine_rpm = minf(powertrain_model.engine_rpm, powertrain_model.maximum_rpm + 200.0)
	var steering: Dictionary = domains.get("steering", {}).get("steering", {})
	maximum_steering_angle_rad = float(steering.get("max_steering_angle", maximum_steering_angle_rad))
	var aero: Dictionary = domains.get("aerodynamics", {}).get("aero", {})
	aero_model.aero_model = aero.get("model", {}).duplicate(true)
	var pressure: Dictionary = domains.get("tires", {}).get("tires", {}).get("pressure", {})
	var cold_pressures: Dictionary = pressure.get("cold_kpa_gauge", {})
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
		state.pressure_bar_gauge = maxf((cold_bar + atmosphere_bar) * gas_kelvin / reference_kelvin - atmosphere_bar, 0.5)
		thermal_model.tire_states[wheel_index] = state
	var fuel: Dictionary = domains.get("fuel", {}).get("fuel", {})
	var fuel_kg := clampf(float(fuel.get("initial_kg", mass_model.fuel_initial_kg)), 0.0, mass_model.fuel_capacity_kg)
	mass_model.fuel_initial_kg = fuel_kg
	thermal_model.fuel_remaining_litres = fuel_kg / maxf(mass_model.fuel_density_kg_per_litre, 0.000001)
	return {"ok": true, "values": effective_values}


func _capture_setup_design() -> void:
	setup_design_axles.clear()
	var suspension: Dictionary = domains.get("suspension", {}).get("suspension", {})
	var physical: Dictionary = suspension.get("geometry_physical", {})
	for axle in ["front", "rear"]:
		var elements: Dictionary = physical.get(axle, {})
		var trim: Dictionary = suspension.get(axle, {})
		setup_design_axles.append({
			"bump_damping": float(elements.get("damper_bump_Ns_per_m", 0.0)),
			"rebound_damping": float(elements.get("damper_rebound_Ns_per_m", 0.0)),
			"physical_bump_stop_multiplier": float(elements.get("bump_stop_mult", 1.0)),
			"damping_ratio": float(trim.get("damping_ratio", 1.0)),
			"bump_multiplier": float(trim.get("bump_damp_multiplier", 1.0)),
			"rebound_multiplier": float(trim.get("rebound_damp_multiplier", 1.0)),
			"stop_multiplier": float(trim.get("bump_stop_multiplier", 1.0)),
			"rest_compression": float(trim.get("spring_length", 0.3)) * float(trim.get("resting_ratio", 0.35)),
		})


func bind_wheel_visuals(pivots: Array[Node3D], visuals: Array[Node3D]) -> void:
	wheel_visual_pivots = pivots
	wheel_visuals = visuals


func step(body: RigidBody3D, state: PhysicsDirectBodyState3D, inputs: Dictionary) -> void:
	var dt := state.step
	if dt <= 0.0 or wheel_positions_local.size() != 4:
		return
	last_step_seconds = dt
	var contacts: Array[Dictionary] = []
	contact_query_count = 0
	for i in 4:
		var pivot_world: Vector3 = state.transform * wheel_positions_local[i]
		var ray_length := wheel_radii[i] + float(suspension_model.axle_parameters[i].get("bump_m", 0.22)) + float(suspension_model.axle_parameters[i].get("droop_m", 0.18)) + 0.08
		var ray_end := pivot_world - state.transform.basis.y.normalized() * ray_length
		var query := PhysicsRayQueryParameters3D.create(pivot_world, ray_end, body.collision_mask)
		query.exclude = [body.get_rid()]
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
		contact_query_count += 1
		if hit.is_empty():
			suspension_model.set_airborne(i)
			wheel_loads[i] = 0.0
			wheel_surfaces[i] = "Unknown"
			contacts.append({"hit": false})
			continue
		var ray_distance: float = pivot_world.distance_to(hit["position"])
		suspension_model.update_contact(i, ray_distance, dt, wheel_radii[i])
		wheel_contact_points[i] = hit["position"]
		wheel_contact_normals[i] = (hit["normal"] as Vector3).normalized()
		wheel_surfaces[i] = _surface_for_collider(hit.get("collider"))
		contacts.append({"hit": true, "position": wheel_contact_points[i], "normal": wheel_contact_normals[i], "distance": ray_distance, "surface": wheel_surfaces[i]})
	var normal_loads := suspension_model.suspension_forces()
	var body_com_world: Vector3 = state.transform * body.center_of_mass
	var drive_torques := _drive_torques(dt, inputs)
	var fade_factors: Array[float] = []
	for i in 4:
		fade_factors.append(thermal_model.brake_fade_factor(i))
	var brake_torques := brake_model.evaluate(float(inputs.get("brake", 0.0)), float(inputs.get("handbrake", 0.0)), fade_factors)
	var brake_powers: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var tire_powers: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var body_right := state.transform.basis.x.normalized()
	for i in 4:
		var contact: Dictionary = contacts[i]
		if not bool(contact.get("hit", false)):
			var free_thermal_state := thermal_model.get_tire_thermal_state_snapshot(i)
			var free_result := tire_model.evaluate(
				i, 0.0, "Gravel", 0.0, 0.0, wheel_spins[i], wheel_radii[i], 0.0,
				thermal_model.tire_grip_factor(i),
				float(free_thermal_state.get("pressure_kpa_gauge", 180.0)), dt,
				float(free_thermal_state.get("carcass_c", 25.0))
			)
			wheel_slips[i] = Vector2(float(free_result.get("slip_ratio", 0.0)), float(free_result.get("slip_angle_rad", 0.0)))
			var free_brake_energy := _continue_wheel_spin(i, dt, float(drive_torques[i]), float(brake_torques[i]), 0.0)
			var free_brake_power := free_brake_energy / dt
			thermal_model.advance_tire(i, 0.0, free_brake_power, state.linear_velocity.length(), dt)
			continue
		var point: Vector3 = contact["position"]
		var normal: Vector3 = contact["normal"]
		var point_velocity := state.linear_velocity + state.angular_velocity.cross(point - body_com_world)
		var steer_angle := _wheel_steer_angle(i, float(inputs.get("steering", 0.0)))
		var toe := suspension_model.dynamic_toe(i)
		var camber := suspension_model.dynamic_camber(i)
		var wheel_camber := suspension_model.dynamic_wheel_camber(i)
		var forward := (-state.transform.basis.z).rotated(normal, steer_angle + toe)
		forward = (forward - normal * forward.dot(normal)).normalized()
		if forward.length_squared() < 0.5:
			forward = (-state.transform.basis.z).normalized()
		var right := forward.cross(normal).normalized()
		right = right.rotated(forward, wheel_camber).normalized()
		var longitudinal_speed := point_velocity.dot(forward)
		var lateral_speed := point_velocity.dot(right)
		var normal_load := maxf(float(normal_loads[i]), 0.0)
		wheel_loads[i] = normal_load
		var thermal_state := thermal_model.get_tire_thermal_state_snapshot(i)
		var tire_result := _solve_contact_wheel(
			i, dt, normal_load, str(contact["surface"]), longitudinal_speed, lateral_speed,
			camber, float(thermal_state.get("pressure_kpa_gauge", 180.0)),
			float(thermal_state.get("carcass_c", 25.0)),
			float(drive_torques[i]), float(brake_torques[i])
		)
		var tire_force := forward * float(tire_result.get("longitudinal_force_n", 0.0)) + right * float(tire_result.get("lateral_force_n", 0.0))
		if normal_load > 0.0:
			state.apply_force(normal * normal_load, point - state.transform.origin)
			state.apply_force(tire_force, point - state.transform.origin)
			state.apply_torque(normal * float(tire_result.get("aligning_torque_nm", 0.0)))
		wheel_slips[i] = Vector2(float(tire_result.get("slip_ratio", 0.0)), float(tire_result.get("slip_angle_rad", 0.0)))
		tire_powers[i] = float(tire_result.get("friction_power_w", 0.0))
		brake_powers[i] = float(tire_result.get("brake_power_w", 0.0))
		thermal_model.advance_tire(i, tire_powers[i], brake_powers[i], point_velocity.length(), dt, wheel_camber)
	var shaft_torque := float(drive_torques[0]) + float(drive_torques[1]) + float(drive_torques[2]) + float(drive_torques[3])
	if absf(shaft_torque) > 0.0:
		state.apply_torque(-body_right * shaft_torque)
	var velocity := state.linear_velocity
	if velocity.length_squared() > 0.01:
		var speed := velocity.length()
		var drag := aero_model.drag_force(speed) + thermal_model.cooling_drag_force_n
		state.apply_central_force(-velocity.normalized() * drag)
		for wing_effect in aero_model.wing_forces(speed, state.transform.basis):
			var wing_position: Vector3 = state.transform.basis * (wing_effect.position as Vector3)
			state.apply_force(wing_effect.force, wing_position)
	var engine_omega := powertrain_model.engine_rpm * TAU / 60.0
	thermal_model.advance_engine(dt, powertrain_model.engine_rpm, powertrain_model.engine_torque_nm, velocity.length(), aero_model.air_density_kg_m3)
	thermal_model.advance_fuel(maxf(powertrain_model.engine_torque_nm * engine_omega, 0.0), dt)
	if bool(inputs.get("automatic_transmission", false)):
		_update_automatic_shift(float(inputs.get("throttle", 0.0)))
	publication_sequence += 1
	simulation_time_s += dt
	var wheels: Array[Dictionary] = []
	for index in 4:
		var wheel := thermal_model.get_tire_thermal_state_snapshot(index)
		wheel.merge({"surface": wheel_surfaces[index], "load_n": wheel_loads[index], "spin_rad_s": wheel_spins[index], "slip_ratio": wheel_slips[index].x, "slip_angle_rad": wheel_slips[index].y})
		wheels.append(wheel)
	published_state = {"sequence": publication_sequence, "generation": session_generation, "time_s": simulation_time_s, "dt_s": dt, "rpm": powertrain_model.engine_rpm, "rpm_max": powertrain_model.maximum_rpm, "rpm_idle": powertrain_model.idle_rpm, "gear": powertrain_model.current_gear, "torque_nm": powertrain_model.engine_torque_nm, "load": clampf(absf(powertrain_model.engine_torque_nm) / maxf(powertrain_model.peak_torque_nm, 1.0), 0.0, 1.0), "speed_kph": state.linear_velocity.length() * 3.6, "throttle": float(inputs.get("throttle", 0.0)), "brake": float(inputs.get("brake", 0.0)), "steering": float(inputs.get("steering", 0.0)), "engine": thermal_model.get_engine_thermal_state_snapshot(), "fuel": thermal_model.get_fuel_state_snapshot(), "wheels": wheels, "contact_queries": contact_query_count, "aids": {"automatic_transmission": bool(inputs.get("automatic_transmission", false)), "traction_control": traction_control_enabled, "stability": stability_enabled, "anti_lock_brakes": abs_enabled}, "aids_available": assistance_available.duplicate()}



func _drive_torques(delta: float, inputs: Dictionary) -> Array[float]:
	var front_speeds := Vector2(wheel_spins[0], wheel_spins[1])
	var rear_speeds := Vector2(wheel_spins[2], wheel_spins[3])
	var front_reactions := Vector2(
		_tire_reaction_torque(0),
		_tire_reaction_torque(1))
	var rear_reactions := Vector2(
		_tire_reaction_torque(2),
		_tire_reaction_torque(3))
	var thermal_factor := thermal_model.engine_torque_factor()
	var clutch := clampf(float(inputs.get("clutch", 1.0)), 0.0, 1.0)
	powertrain_model.advance(delta, float(inputs.get("throttle", 0.0)), clutch, rear_speeds, thermal_factor, rear_reactions, front_speeds, front_reactions)
	return powertrain_model.drive_torques(float(inputs.get("throttle", 0.0)), clutch, rear_speeds, thermal_factor)


func _tire_reaction_torque(index: int) -> float:
	if index < 0 or index >= tire_model.states.size() or index >= wheel_radii.size():
		return 0.0
	return -float(tire_model.states[index].get("longitudinal_force", 0.0)) * wheel_radii[index]


func update_wheel_visuals(steering_input: float, delta: float) -> void:
	for i in mini(4, wheel_visual_pivots.size()):
		var steer_angle := _wheel_steer_angle(i, steering_input)
		var toe := suspension_model.dynamic_toe(i)
		var wheel_camber := suspension_model.dynamic_wheel_camber(i)
		var pivot := wheel_visual_pivots[i]
		pivot.position = wheel_positions_local[i] - Vector3.UP * suspension_model.compression[i]
		pivot.rotation.y = steer_angle + toe
		if i < wheel_visuals.size():
			wheel_rotation_angles[i] = fposmod(wheel_rotation_angles[i] + wheel_spins[i] * delta, TAU)
			wheel_visuals[i].rotation = Vector3(wheel_rotation_angles[i], 0.0, wheel_camber)


func _continue_wheel_spin(index: int, delta: float, drive_torque: float, brake_torque: float, tire_reaction_torque: float) -> float:
	# Input brake torque is a capacity (positive magnitude). Return dissipated
	# work in joules, integrating only the interval where the rotor actually moves.
	var inertia := maxf(mass_model.wheel_spin_inertia[index], 0.01)
	if powertrain_model.wheel_is_driven(index):
		# Reflect engine and gearbox inertia through the active ratio onto each driven wheel.
		inertia += maxf(powertrain_model.drive_inertia_kg_m2, 0.0)
	var substeps := maxi(1, ceili(delta / maximum_substep_seconds))
	var substep := delta / float(substeps)
	var capacity := absf(brake_torque)
	var external_torque := drive_torque - tire_reaction_torque
	var dissipated_j := 0.0
	for _step in substeps:
		var before := wheel_spins[index]
		if absf(before) < 1.0e-9 and absf(external_torque) <= capacity:
			wheel_spins[index] = 0.0
			continue
		var direction := signf(before) if absf(before) >= 1.0e-9 else signf(external_torque)
		var angular_acceleration := (external_torque - capacity * direction) / inertia
		var next_spin := before + angular_acceleration * substep
		if before * next_spin < 0.0 or (before != 0.0 and next_spin == 0.0):
			var stop_time := clampf(-before / angular_acceleration, 0.0, substep)
			dissipated_j += capacity * absf(before) * stop_time * 0.5
			next_spin = 0.0
			if absf(external_torque) > capacity:
				var remaining := substep - stop_time
				next_spin = (external_torque - capacity * signf(external_torque)) / inertia * remaining
				dissipated_j += capacity * absf(next_spin) * remaining * 0.5
		else:
			dissipated_j += capacity * (absf(before) + absf(next_spin)) * substep * 0.5
		wheel_spins[index] = clampf(next_spin, -1800.0, 1800.0)
	return dissipated_j


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
	elif powertrain_model.current_gear < powertrain_model.maximum_forward_gear and normalized_rpm > (0.90 if throttle > 0.65 else 0.70):
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


func reset_dynamics() -> void:
	session_generation += 1
	simulation_time_s = 0.0
	published_state = {}
	wheel_spins.fill(0.0)
	wheel_slips.fill(Vector2.ZERO)
	wheel_loads.fill(0.0)
	wheel_rotation_angles.fill(0.0)
	for i in 4:
		suspension_model.compression[i] = 0.0
		suspension_model.compression_velocity[i] = 0.0
		suspension_model.contact_active[i] = false
		suspension_model.previous_samples[i] = false
		if i < wheel_visuals.size():
			wheel_visuals[i].rotation = Vector3.ZERO
	powertrain_model.current_gear = 0
	powertrain_model.engine_rpm = powertrain_model.idle_rpm
	powertrain_model.shift_remaining_seconds = 0.0
	powertrain_model.engine_torque_nm = 0.0
	powertrain_model.engine_attack_limited_torque_nm = 0.0
	powertrain_model.clutch_engagement = 0.0
	powertrain_model.clutch_torque_nm = 0.0
	powertrain_model.drive_inertia_kg_m2 = 0.0


func _vector_from_document(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		return Vector3(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)), float(value.get("z", fallback.z)))
	return fallback


# Trials reuse the accepted contact and original filter state. Only the final
# state is committed, so relaxation/memory advance by dt once, not N * dt.
func _solve_contact_wheel(index: int, dt: float, load_n: float, surface: String, vx: float, vy: float, camber: float, pressure: float, carcass_temperature_c: float, drive: float, brake: float) -> Dictionary:
	var initial_state: Dictionary = tire_model.states[index].duplicate(true)
	var count := maxi(1, ceili(dt / maximum_substep_seconds))
	var h := dt / float(count)
	var averages := {"longitudinal_force_n": 0.0, "lateral_force_n": 0.0, "aligning_torque_nm": 0.0, "friction_power_w": 0.0, "brake_power_w": 0.0}
	var result: Dictionary = {}
	for iteration in count:
		tire_model.states[index] = initial_state.duplicate(true)
		result = tire_model.evaluate(index, load_n, surface, vx, vy, wheel_spins[index], wheel_radii[index], camber, thermal_model.tire_grip_factor(index), pressure, dt, carcass_temperature_c)
		for key in ["longitudinal_force_n", "lateral_force_n", "aligning_torque_nm", "friction_power_w"]:
			averages[key] += float(result.get(key, 0.0)) / float(count)
		var brake_energy := _continue_wheel_spin(index, h, drive, brake, float(result.get("longitudinal_force_n", 0.0)) * wheel_radii[index])
		averages.brake_power_w += brake_energy / dt
	result.merge(averages, true)
	return result
