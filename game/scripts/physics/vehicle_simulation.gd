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
var unsprung_rig := UnsprungSuspensionRig.new()
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
var wheel_contact_casts: Array[ShapeCast3D] = []
var contact_frequency_samples: int = 0
var contact_frequency_elapsed_s: float = 0.0
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


func adjust_live_tire_pressure(delta_kpa: float) -> void:
	# Runtime tuning aid: modify only inflation, never fuel, temperatures or motion.
	var pressure: Dictionary = domains.get("tires", {}).get("tires", {}).get("pressure", {})
	var cold: Dictionary = pressure.get("cold_kpa_gauge", {})
	var atmosphere := float(pressure.get("atmospheric_pressure_kpa", 101.325)) / 100.0
	var reference_temp := float(pressure.get("reference_temperature_c", 25.0))
	for i in 4:
		var key: String = ["FL", "FR", "RL", "RR"][i]
		var field := RallySetupCatalog.field_for_path("tires.pressure.cold_kpa_gauge." + key)
		var next_kpa := clampf(float(cold.get(key, 180.0)) + delta_kpa, float(field.min), float(field.max))
		cold[key] = next_kpa
		var tire: Dictionary = thermal_model.tire_states[i]
		tire.pressure_reference_bar_gauge = next_kpa / 100.0
		tire.pressure_reference_temp_c = reference_temp
		tire.pressure_bar_gauge = maxf((next_kpa / 100.0 + atmosphere) * (float(tire.gas_c) + 273.15) / maxf(reference_temp + 273.15, 1.0) - atmosphere, 0.0)
		thermal_model.tire_states[i] = tire
	pressure["cold_kpa_gauge"] = cold


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
		var stop_base := maxf(float(design.get("stop_multiplier", 1.0)), 0.000001)
		var stop_multiplier := float(trim.get("bump_stop_multiplier", stop_base)) / stop_base
		var bump_stop_mult := float(design.get("physical_bump_stop_multiplier", 1.0)) * stop_multiplier
		for wheel_index in ([0, 1] if axle_index == 0 else [2, 3]):
			var parameters: Dictionary = suspension_model.axle_parameters[wheel_index]
			parameters.camber = float(trim.get("camber", 0.0))
			parameters.toe = float(trim.get("toe", 0.0))
			var current_rest := float(trim.get("spring_length", 0.3)) * float(trim.get("resting_ratio", 0.35))
			parameters.rest_compression_offset = current_rest - float(design.get("rest_compression", current_rest))
			var reference_mass := float(parameters.frequency_reference_mass_kg)
			var frequency := float(trim.get("ride_frequency_hz", parameters.ride_frequency_hz))
			var derived_k := reference_mass * pow(TAU * frequency, 2.0)
			var critical_c := 2.0 * sqrt(derived_k * reference_mass)
			parameters.ride_frequency_hz = frequency
			parameters.spring_rate = derived_k
			parameters.bump_damping = critical_c * float(trim.get("damping_ratio", 0.65)) * float(trim.get("bump_damp_multiplier", 1.0))
			parameters.rebound_damping = critical_c * float(trim.get("damping_ratio", 0.65)) * float(trim.get("rebound_damp_multiplier", 1.0))
			parameters.bump_stop_stiffness = derived_k * bump_stop_mult * 8.0
			suspension_model.axle_parameters[wheel_index] = parameters
		var arb: Dictionary = physical.get(axle + "_arb", {})
		var spring_rate := float(suspension_model.axle_parameters[axle_index * 2].spring_rate)
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
		state.pressure_bar_gauge = maxf((cold_bar + atmosphere_bar) * gas_kelvin / reference_kelvin - atmosphere_bar, 0.0)
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
		# Only the integration callback updates the cast: no duplicate automatic query.
		cast.enabled = false
		cast.margin = 0.002
		cast.max_results = 8
		cast.collide_with_areas = false
		cast.collide_with_bodies = true
		body.add_child(cast)
		cast.add_exception_rid(body.get_rid())
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
			print("RALLY_CONTACT_FREQUENCY ", JSON.stringify({"query_type": "ShapeCast3D", "wheel_count": wheel_contact_casts.size(), "configured_hz": Engine.physics_ticks_per_second, "integration_hz": contact_frequency_samples / contact_frequency_elapsed_s, "dt_s": dt}))
	var contacts: Array[Dictionary] = []
	contact_query_count = 0
	for i in 4:
		var cast := wheel_contact_casts[i]
		var bump := float(suspension_model.axle_parameters[i].get("bump_m", 0.22)) + 0.02
		var travel := bump + float(suspension_model.axle_parameters[i].get("droop_m", 0.18))
		var steer := _wheel_steer_angle(i, float(inputs.get("steering", 0.0))) + suspension_model.dynamic_toe(i)
		var orientation := Basis(Vector3.UP, steer) * Basis(Vector3.FORWARD, suspension_model.dynamic_wheel_camber(i)) * Basis(Vector3.BACK, PI * 0.5)
		cast.global_transform = state.transform * Transform3D(orientation, wheel_positions_local[i] + Vector3.UP * bump)
		cast.target_position = orientation.inverse() * (Vector3.DOWN * travel)
		cast.collision_mask = body.collision_mask
		cast.force_shapecast_update()
		var hit: Dictionary = {}
		var support := 0.1
		for collision_index in cast.get_collision_count():
			var normal := cast.get_collision_normal(collision_index).normalized()
			var alignment := normal.dot(state.transform.basis.y.normalized())
			if alignment > support:
				support = alignment
				hit = {"position": cast.get_collision_point(collision_index), "normal": normal, "collider": cast.get_collider(collision_index)}
		contact_query_count += 1
		if hit.is_empty():
			suspension_model.set_airborne(i)
			wheel_loads[i] = 0.0
			wheel_surfaces[i] = "Unknown"
			contacts.append({"hit": false})
			continue
		# Suspension length comes from swept wheel-centre displacement, not the
		# distance to a contact point that may lie at the tire's shoulder.
		var ray_distance: float = wheel_radii[i] + travel * cast.get_closest_collision_safe_fraction() - bump
		wheel_contact_points[i] = hit["position"]
		wheel_contact_normals[i] = (hit["normal"] as Vector3).normalized()
		wheel_surfaces[i] = _surface_for_collider(hit.get("collider"))
		contacts.append({"hit": true, "position": wheel_contact_points[i], "normal": wheel_contact_normals[i], "distance": ray_distance, "surface": wheel_surfaces[i], "collider": hit.get("collider")})
	var normal_loads := unsprung_rig.solve(state, suspension_model, contacts, wheel_radii, domains, thermal_model)
	var fade_factors: Array[float] = []
	for i in 4:
		fade_factors.append(thermal_model.brake_fade_factor(i))
	var brake_torques := brake_model.evaluate(float(inputs.get("brake", 0.0)), float(inputs.get("handbrake", 0.0)), fade_factors)
	var brake_powers: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var tire_powers: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var body_right := state.transform.basis.x.normalized()
	var count := maxi(1, ceili(dt / maximum_substep_seconds))
	var h := dt / float(count)
	var force_weight := 1.0 / float(count)
	for _substep_index in count:
		_prepare_powertrain(h, inputs)
		var tire_reactions: Array[float] = [0.0, 0.0, 0.0, 0.0]
		var thermal_speeds: Array[float] = [0.0, 0.0, 0.0, 0.0]
		var thermal_cambers: Array[float] = [0.0, 0.0, 0.0, 0.0]
		for i in 4:
			var contact: Dictionary = contacts[i]
			tire_model.states[i].radial_deflection_m = unsprung_rig.radial_deflection_m[i]
			wheel_loads[i] = normal_loads[i]
			if not bool(contact.get("hit", false)) or normal_loads[i] <= 0.0:
				var free_thermal_state := thermal_model.get_tire_thermal_state_snapshot(i)
				var free_result := tire_model.evaluate(
					i, 0.0, "Gravel", 0.0, 0.0, wheel_spins[i], wheel_radii[i], 0.0,
					thermal_model.tire_grip_factor(i),
					float(free_thermal_state.get("pressure_kpa_gauge", 180.0)), h,
					float(free_thermal_state.get("carcass_c", 25.0))
				)
				wheel_slips[i] = Vector2(float(free_result.get("slip_ratio", 0.0)), float(free_result.get("slip_angle_rad", 0.0)))
				tire_powers[i] = 0.0
				thermal_speeds[i] = state.linear_velocity.length()
				continue
			var point: Vector3 = contact["position"]
			var normal: Vector3 = contact["normal"]
			var hub := unsprung_rig.hubs[i]
			var point_velocity := hub.linear_velocity + hub.angular_velocity.cross(point - hub.global_position)
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
			tire_model.rotate_patch_frame(i, forward, right)
			var tire_result := _solve_contact_wheel(
				i, h, normal_load, str(contact["surface"]), longitudinal_speed, lateral_speed,
				camber, float(thermal_state.get("pressure_kpa_gauge", 180.0)),
				float(thermal_state.get("carcass_c", 25.0))
			)
			var tire_force := forward * float(tire_result.get("longitudinal_force_n", 0.0)) + right * float(tire_result.get("lateral_force_n", 0.0))
			if normal_load > 0.0:
				hub.apply_force(tire_force * force_weight, point - hub.global_position)
				hub.apply_torque(normal * float(tire_result.get("aligning_torque_nm", 0.0)) * force_weight)
			wheel_slips[i] = Vector2(float(tire_result.get("slip_ratio", 0.0)), float(tire_result.get("slip_angle_rad", 0.0)))
			tire_powers[i] = float(tire_result.get("friction_power_w", 0.0))
			tire_reactions[i] = float(tire_result.get("longitudinal_force_n", 0.0)) * wheel_radii[i]
			thermal_speeds[i] = point_velocity.length()
			thermal_cambers[i] = wheel_camber
		var rotation := powertrain_model.solve_rotation(h, wheel_spins, mass_model.wheel_spin_inertia, tire_reactions, brake_torques)
		var brake_work: Array = rotation.brake_work_j
		for i in 4:
			brake_powers[i] = float(brake_work[i]) / h
			thermal_model.advance_tire(i, tire_powers[i], brake_powers[i], thermal_speeds[i], h, thermal_cambers[i], unsprung_rig.radial_dissipation_w[i] if normal_loads[i] > 0.0 else 0.0)
		state.apply_torque(-body_right * float(rotation.shaft_torque_nm) * force_weight)

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
	if publication_sequence == 240:
		print("RALLY_UNSPRUNG_STATE ", JSON.stringify({"radial_deflection_m": unsprung_rig.radial_deflection_m, "suspension_compression_m": suspension_model.compression, "normal_load_n": normal_loads, "spring_force_n": unsprung_rig.spring_forces_n, "sprung_mass_kg": body.mass, "vehicle_mass_kg": mass_model.resolve(thermal_model.fuel_remaining_litres * mass_model.fuel_density_kg_per_litre).vehicle_total_mass_kg}))
	simulation_time_s += dt
	var wheels: Array[Dictionary] = []
	for index in 4:
		var wheel := thermal_model.get_tire_thermal_state_snapshot(index)
		wheel.merge({"surface": wheel_surfaces[index], "load_n": wheel_loads[index], "spin_rad_s": wheel_spins[index], "slip_ratio": wheel_slips[index].x, "slip_angle_rad": wheel_slips[index].y, "patch_pos": tire_model.states[index].patch_pos, "patch_energy_j": tire_model.states[index].patch_energy_j, "unsprung_mass_kg": mass_model.unsprung_mass_kg[index], "radial_deflection_m": unsprung_rig.radial_deflection_m[index], "radial": unsprung_rig.radial_states[index].duplicate(), "suspension_force_n": unsprung_rig.spring_forces_n[index]})
		wheels.append(wheel)
	published_state = {"sequence": publication_sequence, "generation": session_generation, "time_s": simulation_time_s, "dt_s": dt, "rpm": powertrain_model.engine_rpm, "rpm_max": powertrain_model.maximum_rpm, "rpm_idle": powertrain_model.idle_rpm, "gear": powertrain_model.current_gear, "torque_nm": powertrain_model.engine_torque_nm, "autoblip_active": powertrain_model.autoblip_active, "autoblip_target_rpm": powertrain_model.autoblip_target_rpm, "autoblip_throttle": powertrain_model.autoblip_throttle, "shift_phase": powertrain_model.shift_phase, "pending_gear": powertrain_model.pending_gear, "clutch_engagement": powertrain_model.clutch_engagement, "clutch_torque_nm": powertrain_model.clutch_torque_nm, "clutch_slip_power_w": powertrain_model.clutch_slip_power_w, "input_shaft_rad_s": powertrain_model.input_shaft_omega_rad_s, "driveline": {"enabled": powertrain_model.driveline_compliance_enabled, "twist_rad": powertrain_model.driveline_twist_rad, "torque_nm": powertrain_model.driveline_torque_nm, "energy_j": powertrain_model.driveline_energy_j, "dissipation_w": powertrain_model.driveline_dissipation_w, "output_rad_s": powertrain_model.output_shaft_omega_rad_s}, "load": clampf(absf(powertrain_model.engine_torque_nm) / maxf(powertrain_model.peak_torque_nm, 1.0), 0.0, 1.0), "speed_kph": state.linear_velocity.length() * 3.6, "throttle": float(inputs.get("throttle", 0.0)), "brake": float(inputs.get("brake", 0.0)), "steering": float(inputs.get("steering", 0.0)), "engine": thermal_model.get_engine_thermal_state_snapshot(), "fuel": thermal_model.get_fuel_state_snapshot(), "wheels": wheels, "contact_queries": contact_query_count, "aids": {"automatic_transmission": bool(inputs.get("automatic_transmission", false)), "traction_control": traction_control_enabled, "stability": stability_enabled, "anti_lock_brakes": abs_enabled}, "aids_available": assistance_available.duplicate()}



func _prepare_powertrain(delta: float, inputs: Dictionary) -> void:
	var clutch := clampf(float(inputs.get("clutch", 1.0)), 0.0, 1.0)
	var split := powertrain_model.front_torque_split
	var carrier := 0.5 * (split * (wheel_spins[0] + wheel_spins[1]) + (1.0 - split) * (wheel_spins[2] + wheel_spins[3]))
	powertrain_model.advance(delta, float(inputs.get("throttle", 0.0)), clutch, thermal_model.engine_torque_factor(), carrier)


func update_wheel_visuals(steering_input: float, delta: float) -> void:
	for i in mini(4, wheel_visual_pivots.size()):
		var steer_angle := _wheel_steer_angle(i, steering_input)
		var toe := suspension_model.dynamic_toe(i)
		var wheel_camber := suspension_model.dynamic_wheel_camber(i)
		var pivot := wheel_visual_pivots[i]
		pivot.position = wheel_positions_local[i] + Vector3.UP * suspension_model.compression[i]
		pivot.rotation.y = steer_angle + toe
		if i < wheel_visuals.size():
			wheel_rotation_angles[i] = fposmod(wheel_rotation_angles[i] + wheel_spins[i] * delta, TAU)
			wheel_visuals[i].rotation = Vector3(wheel_rotation_angles[i], 0.0, wheel_camber)




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
	unsprung_rig.reset()
	session_generation += 1
	simulation_time_s = 0.0
	published_state = {}
	wheel_spins.fill(0.0)
	wheel_slips.fill(Vector2.ZERO)
	wheel_loads.fill(0.0)
	wheel_rotation_angles.fill(0.0)
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
		return Vector3(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)), float(value.get("z", fallback.z)))
	return fallback


# Advance tire memory sequentially by h; the sum of substeps is dt.
func _solve_contact_wheel(index: int, dt: float, load_n: float, surface: String, vx: float, vy: float, camber: float, pressure: float, carcass_temperature_c: float) -> Dictionary:
	# Called once per shared rotational substep; all wheel speeds are solved together.
	return tire_model.evaluate(index, load_n, surface, vx, vy, wheel_spins[index], wheel_radii[index], camber, thermal_model.tire_grip_factor(index), pressure, dt, carcass_temperature_c)
