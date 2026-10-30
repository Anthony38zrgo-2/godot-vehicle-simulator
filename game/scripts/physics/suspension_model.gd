class_name VehicleSuspensionModel
extends RefCounted

var axle_parameters: Array[Dictionary] = []
var static_corner_loads_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var suspension_filters: Dictionary = {}
var front_arb_stiffness_n_per_m: float = 0.0
var rear_arb_stiffness_n_per_m: float = 0.0
var road_height_max_rate_m_s: float = 0.0
var road_height_filter_tau_s: float = 0.0
var compression: Array[float] = [0.0, 0.0, 0.0, 0.0]
var compression_velocity: Array[float] = [0.0, 0.0, 0.0, 0.0]
var filtered_ray_distance: Array[float] = [0.0, 0.0, 0.0, 0.0]
var filtered_arb_travel: Array[float] = [0.0, 0.0, 0.0, 0.0]
var initialized: Array[bool] = [false, false, false, false]
var previous_samples: Array[bool] = [false, false, false, false]
var contact_active: Array[bool] = [false, false, false, false]


func configure(domains: Dictionary, chassis_geometry: Dictionary, resolved_mass: Dictionary) -> Dictionary:
	var suspension_doc: Dictionary = domains.get("suspension", {}).get("suspension", {})
	var physical: Dictionary = suspension_doc.get("geometry_physical", {})
	var filters_doc: Dictionary = domains.get("suspension_filters", {}).get("suspension_filters", {})
	var front_suspension: Dictionary = physical.get("front", {})
	var rear_suspension: Dictionary = physical.get("rear", {})
	var front_arb: Dictionary = physical.get("front_arb", {})
	var rear_arb: Dictionary = physical.get("rear_arb", {})
	# No explicit ARB stiffness in N/m is authored in this domain set. Interpret
	# its legacy ratio as an axle-spring-rate fraction; this is a documented local
	# approximation because the current Rapier profile loader expects topology
	# data that this coupled_world.json version does not contain.
	front_arb_stiffness_n_per_m = float(front_suspension.get("spring_rate_N_per_m", 0.0)) * float(front_arb.get("ratio", 0.0))
	rear_arb_stiffness_n_per_m = float(rear_suspension.get("spring_rate_N_per_m", 0.0)) * float(rear_arb.get("ratio", 0.0))
	suspension_filters = filters_doc
	road_height_max_rate_m_s = float(filters_doc.get("road_height_max_rate_m_s", 0.0))
	road_height_filter_tau_s = float(filters_doc.get("road_height_filter_tau_s", 0.0))
	var front_z := float(chassis_geometry.get("front_axle_z", -1.205))
	var rear_z := float(chassis_geometry.get("rear_axle_z", 1.205))
	var wheelbase := maxf(absf(rear_z - front_z), 0.1)
	var center: Vector3 = resolved_mass.get("center_of_mass", Vector3.ZERO)
	var front_fraction := clampf((rear_z - center.z) / wheelbase, 0.05, 0.95)
	var total_mass := float(resolved_mass.get("mass_kg", 0.0))
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.80665))
	var axle_docs := [physical.get("front", {}), physical.get("front", {}), physical.get("rear", {}), physical.get("rear", {})]
	var axle_fractions := [front_fraction, front_fraction, 1.0 - front_fraction, 1.0 - front_fraction]
	axle_parameters.clear()
	for i in 4:
		var values: Dictionary = axle_docs[i]
		var axle := "front" if i < 2 else "rear"
		var corner_tune: Dictionary = suspension_doc.get(axle, {})
		var spring_rate := float(values.get("spring_rate_N_per_m", 1.0))
		if spring_rate <= 0.0:
			return {"ok": false, "error": axle + " suspension spring rate must be positive."}
		var spring_free_length := float(values.get("spring_free_length_m", corner_tune.get("spring_length", 0.3)))
		var static_load := total_mass * gravity * float(axle_fractions[i]) * 0.5
		var reference_mass := static_load / maxf(gravity, 0.001)
		var frequency := float(corner_tune.get("ride_frequency_hz", sqrt(spring_rate / reference_mass) / TAU))
		if not is_finite(frequency) or frequency <= 0.0:
			return {"ok": false, "error": axle + " ride frequency must be positive and finite."}
		spring_rate = reference_mass * pow(TAU * frequency, 2.0)
		var critical_damping := 2.0 * sqrt(spring_rate * reference_mass)
		var damping_ratio := maxf(float(corner_tune.get("damping_ratio", 0.65)), 0.0)
		var unsprung: Array = resolved_mass.get("unsprung_mass_kg", [0.0, 0.0, 0.0, 0.0])
		static_corner_loads_n[i] = static_load + float(unsprung[i]) * gravity
		axle_parameters.append({
			"spring_rate": spring_rate,
			"spring_can_unseat": bool(corner_tune.get("spring_can_unseat", true)),
			"frequency_reference_mass_kg": reference_mass,
			"ride_frequency_hz": frequency,
			"free_length": spring_free_length,
			"installed_length": float(values.get("spring_installed_length_m", spring_free_length)),
			"bump_damping": critical_damping * damping_ratio * float(corner_tune.get("bump_damp_multiplier", 1.0)),
			"rebound_damping": critical_damping * damping_ratio * float(corner_tune.get("rebound_damp_multiplier", 1.0)),
			"fast_factor": float(values.get("damper_fast_factor", 1.0)),
			"knee_speed": float(values.get("damper_knee_m_per_s", INF)),
			"bump_stop_travel": float(values.get("bump_stop_travel_m", 0.0)),
			"bump_stop_stiffness": spring_rate * float(values.get("bump_stop_mult", 1.0)) * 8.0,
			"bump_stop_damping": float(values.get("bump_stop_damper_Ns_per_m", 0.0)),
			"bump_m": float(values.get("wheel_bump_m", 0.22)),
			"droop_m": float(values.get("wheel_droop_m", 0.18)),
			"hard_stop_overtravel": float(values.get("hard_stop_overtravel_m", 0.0)),
			"hard_stop_stiffness": float(values.get("hard_stop_stiffness_N_per_m", 0.0)),
			"hard_stop_damping": float(values.get("hard_stop_damper_Ns_per_m", 0.0)),
			"camber": float(corner_tune.get("camber", 0.0)),
			"camber_gain": float(corner_tune.get("camber_gain_rad_per_m", 0.0)),
			"toe": float(corner_tune.get("toe", 0.0)),
			"toe_gain": float(corner_tune.get("toe_gain_rad_per_m", 0.0)),
			"static_load": static_load,
			"rest_compression_offset": 0.0,
		})
	front_arb_stiffness_n_per_m = float(axle_parameters[0].spring_rate) * float(front_arb.get("ratio", 0.0))
	rear_arb_stiffness_n_per_m = float(axle_parameters[2].spring_rate) * float(rear_arb.get("ratio", 0.0))
	print("RALLY_SUSPENSION_FREQUENCY ", JSON.stringify({"front": {"mass_kg": axle_parameters[0].frequency_reference_mass_kg, "hz": axle_parameters[0].ride_frequency_hz, "k_n_m": axle_parameters[0].spring_rate, "c_bump_ns_m": axle_parameters[0].bump_damping, "c_rebound_ns_m": axle_parameters[0].rebound_damping}, "rear": {"mass_kg": axle_parameters[2].frequency_reference_mass_kg, "hz": axle_parameters[2].ride_frequency_hz, "k_n_m": axle_parameters[2].spring_rate, "c_bump_ns_m": axle_parameters[2].bump_damping, "c_rebound_ns_m": axle_parameters[2].rebound_damping}}))
	return {"ok": true}


func update_contact(index: int, ray_distance: float, delta: float, wheel_radius_m: float) -> void:
	var current_length := maxf(ray_distance, 0.0)
	var axle := "front" if index < 2 else "rear"
	var axle_filter: Dictionary = suspension_filters.get(axle, {})
	if not initialized[index]:
		filtered_ray_distance[index] = current_length
		initialized[index] = true
	else:
		var target_length := current_length
		if road_height_filter_tau_s > 0.0 and delta > 0.0:
			var alpha := 1.0 - exp(-delta / road_height_filter_tau_s)
			target_length = filtered_ray_distance[index] + (current_length - filtered_ray_distance[index]) * alpha
		var max_rate := road_height_max_rate_m_s
		if max_rate > 0.0 and delta > 0.0:
			var maximum_change := max_rate * delta
			filtered_ray_distance[index] += clampf(target_length - filtered_ray_distance[index], -maximum_change, maximum_change)
		else:
			filtered_ray_distance[index] = target_length
	# The contact adapter supplies radius + swept-centre displacement. This
	# equivalent length equals the radius at neutral ride height; it is not
	# the distance from the wheel centre to a shoulder contact point.
	var next_compression := wheel_radius_m - maxf(filtered_ray_distance[index], 0.0)
	var raw_velocity := 0.0
	if previous_samples[index] and delta > 0.0:
		raw_velocity = (next_compression - compression[index]) / delta
	var damper_tau := float(axle_filter.get("damper_velocity_filter_tau_s", 0.0))
	if damper_tau > 0.0 and previous_samples[index] and delta > 0.0:
		var alpha_velocity := 1.0 - exp(-delta / damper_tau)
		compression_velocity[index] += (raw_velocity - compression_velocity[index]) * alpha_velocity
	else:
		compression_velocity[index] = raw_velocity
	compression[index] = next_compression
	var arb_tau := float(axle_filter.get("arb_travel_filter_tau_s", 0.0))
	if not previous_samples[index] or arb_tau <= 0.0 or delta <= 0.0:
		filtered_arb_travel[index] = next_compression
	else:
		var alpha_arb := 1.0 - exp(-delta / arb_tau)
		filtered_arb_travel[index] += (next_compression - filtered_arb_travel[index]) * alpha_arb
	previous_samples[index] = true
	contact_active[index] = true


func set_airborne(index: int) -> void:
	contact_active[index] = false
	compression_velocity[index] = 0.0
	if initialized[index]:
		compression[index] = -float(axle_parameters[index].droop_m)
		filtered_arb_travel[index] = compression[index]


func suspension_forces() -> Array[float]:
	var forces: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		var p: Dictionary = axle_parameters[i]
		var travel := compression[i]
		var speed := compression_velocity[i]
		var damper_rate := float(p.bump_damping if speed >= 0.0 else p.rebound_damping)
		if absf(speed) > float(p.knee_speed):
			damper_rate *= float(p.fast_factor)
		var elastic_force := float(p.static_load) + float(p.spring_rate) * (travel - float(p.get("rest_compression_offset", 0.0)))
		# A seated coil cannot pull; an attached leaf spring remains bilateral.
		# Never clamp the damper, bump stop or anti-roll-bar contributions here.
		if bool(p.spring_can_unseat):
			elastic_force = maxf(elastic_force, 0.0)
		var force := elastic_force + damper_rate * speed
		var bump_threshold := float(p.bump_m) - float(p.bump_stop_travel)
		if travel > bump_threshold:
			var overtravel := travel - bump_threshold
			force += float(p.bump_stop_stiffness) * overtravel * (1.0 + 5.0 * overtravel)
			force += float(p.bump_stop_damping) * maxf(speed, 0.0)
		# Travel hard limits are enforced by Jolt suspension-guide constraints.
		# Internal suspension forces act even while the tire is airborne.
		forces[i] = force
	var front_roll := filtered_arb_travel[0] - filtered_arb_travel[1]
	var rear_roll := filtered_arb_travel[2] - filtered_arb_travel[3]
	var front_arb := front_arb_stiffness_n_per_m * front_roll
	var rear_arb := rear_arb_stiffness_n_per_m * rear_roll
	forces[0] += front_arb
	forces[1] -= front_arb
	forces[2] += rear_arb
	forces[3] -= rear_arb
	return forces


func dynamic_camber(index: int) -> float:
	var p: Dictionary = axle_parameters[index]
	var travel_delta := compression[index] - float(p.get("rest_compression_offset", 0.0))
	return float(p.camber) + float(p.camber_gain) * travel_delta


func dynamic_wheel_camber(index: int) -> float:
	# Axle camber stays side-independent for the tire model; physical wheel pose
	# mirrors it across the car, matching Rust's wheel-basis convention.
	var side_sign := 1.0 if index in [0, 2] else -1.0
	return side_sign * dynamic_camber(index)


func dynamic_toe(index: int) -> float:
	var p: Dictionary = axle_parameters[index]
	var side_sign := 1.0 if index in [0, 2] else -1.0
	var travel_delta := compression[index] - float(p.get("rest_compression_offset", 0.0))
	var axle_toe := float(p.toe) + float(p.toe_gain) * travel_delta
	# Rust mirrors positive axle toe as a negative yaw on the left and positive
	# yaw on the right. Godot uses -Z as forward and +Y as positive yaw.
	return clampf(-side_sign * axle_toe, -0.05, 0.05)


func maximum_wheel_travel(index: int) -> float:
	var p: Dictionary = axle_parameters[index]
	return float(p.free_length) + float(p.droop_m) + float(p.bump_m)
