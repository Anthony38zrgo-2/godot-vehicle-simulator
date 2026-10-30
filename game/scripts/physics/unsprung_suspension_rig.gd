class_name UnsprungSuspensionRig
extends RefCounted

const JOINT_LIMIT_MARGIN_M := 0.03

var chassis: RigidBody3D
var hubs: Array[RigidBody3D] = []
var joints: Array[Generic6DOFJoint3D] = []
var neutral_positions: Array[Vector3] = []
var radial_deflection_m: Array[float] = [0.0, 0.0, 0.0, 0.0]
var radial_dissipation_w: Array[float] = [0.0, 0.0, 0.0, 0.0]
var radial_states: Array[Dictionary] = [{ }, { }, { }, { }]
var spring_forces_n: Array[float] = [0.0, 0.0, 0.0, 0.0]


func create(
	body: RigidBody3D,
	positions: Array[Vector3],
	masses: Array[float],
	suspension: VehicleSuspensionModel,
) -> void:
	chassis = body
	neutral_positions.assign(positions)
	for i in 4:
		var hub := RigidBody3D.new()
		hub.name = "UnsprungHub_" + str(i)
		hub.top_level = true
		hub.mass = masses[i]
		hub.collision_layer = 0
		hub.collision_mask = 0
		hub.can_sleep = false
		hub.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		hub.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		hub.linear_damp = 0.0
		hub.angular_damp = 0.0
		var shape_node := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.1
		shape_node.shape = shape
		hub.add_child(shape_node)
		body.add_child(hub)
		hub.global_transform = body.global_transform * Transform3D(Basis.IDENTITY, positions[i])
		hubs.append(hub)
		var joint := Generic6DOFJoint3D.new()
		joint.name = "SuspensionGuide_" + str(i)
		body.add_child(joint)
		joint.global_transform = hub.global_transform
		joint.node_a = joint.get_path_to(body)
		joint.node_b = joint.get_path_to(hub)
		joint.set_param_y(
			Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,
			-float(suspension.axle_parameters[i].droop_m) - JOINT_LIMIT_MARGIN_M,
		)
		joint.set_param_y(
			Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,
			float(suspension.axle_parameters[i].bump_m) + JOINT_LIMIT_MARGIN_M,
		)
		joints.append(joint)
	print(
		"RALLY_UNSPRUNG_READY ",
		JSON.stringify(
			{ "hub_masses_kg": masses, "sprung_mass_kg": body.mass, "hub_bodies": hubs.size() }
		),
	)


func reset() -> void:
	for i in hubs.size():
		var target_transform := chassis.global_transform * Transform3D(
			Basis.IDENTITY,
			neutral_positions[i],
		)
		hubs[i].global_transform = target_transform
		hubs[i].linear_velocity = Vector3.ZERO
		hubs[i].angular_velocity = Vector3.ZERO
		hubs[i].constant_force = Vector3.ZERO
		var hub_state := PhysicsServer3D.body_get_direct_state(hubs[i].get_rid())
		if hub_state != null:
			hub_state.transform = target_transform
			hub_state.linear_velocity = Vector3.ZERO
			hub_state.angular_velocity = Vector3.ZERO
		radial_deflection_m[i] = 0.0
		radial_dissipation_w[i] = 0.0
		radial_states[i] = { }


func sync_freeze() -> void:
	for hub in hubs:
		hub.freeze = chassis.freeze


func solve(
	state: PhysicsDirectBodyState3D,
	suspension: VehicleSuspensionModel,
	contacts: Array[Dictionary],
	radii: Array[float],
	domains: Dictionary,
	thermal: VehicleThermalModel,
) -> Array[float]:
	var up := state.transform.basis.y.normalized()
	var com := state.transform * chassis.center_of_mass
	var hub_states: Array[PhysicsDirectBodyState3D] = []
	var hub_positions: Array[Vector3] = []
	var hub_velocities: Array[Vector3] = []
	var neutral_world: Array[Vector3] = []

	for i in 4:
		var hub := hubs[i]
		var h_state := PhysicsServer3D.body_get_direct_state(hub.get_rid())
		hub_states.append(h_state)
		var h_pos := h_state.transform.origin if h_state != null else hub.global_position
		var h_vel := h_state.linear_velocity if h_state != null else hub.linear_velocity
		hub_positions.append(h_pos)
		hub_velocities.append(h_vel)
		var neutral := state.transform * neutral_positions[i]
		neutral_world.append(neutral)
		var body_point_velocity := state.linear_velocity + state.angular_velocity.cross(
			neutral - com
		)
		var droop_limit := -float(suspension.axle_parameters[i].droop_m)
		var bump_limit := float(suspension.axle_parameters[i].bump_m)
		var raw_comp := (h_pos - neutral).dot(up)
		var raw_vel := (h_vel - body_point_velocity).dot(up)
		suspension.compression[i] = clampf(raw_comp, droop_limit, bump_limit)
		suspension.compression_velocity[i] = raw_vel
		suspension.filtered_arb_travel[i] = suspension.compression[i]
		suspension.initialized[i] = true
		suspension.previous_samples[i] = true
		suspension.contact_active[i] = bool(contacts[i].get("hit", false))

	spring_forces_n = suspension.suspension_forces()
	var normal_loads: Array[float] = [0.0, 0.0, 0.0, 0.0]

	for i in 4:
		var hub := hubs[i]
		var h_state := hub_states[i]
		var p: Dictionary = suspension.axle_parameters[i]
		var droop_m := float(p.droop_m)
		var bump_m := float(p.bump_m)
		var comp := suspension.compression[i]
		var rel_vel := suspension.compression_velocity[i]
		var internal_force_n := spring_forces_n[i]

		if comp < -droop_m + 0.025:
			var droop_penetration := (-droop_m + 0.025) - comp
			var droop_stop_k := float(p.spring_rate) * 6.0
			var droop_stop_c := float(p.rebound_damping) * 2.5
			internal_force_n -= droop_stop_k * droop_penetration - droop_stop_c * minf(rel_vel, 0.0)

		var spring_force := up * internal_force_n
		var mount_offset := neutral_world[i] - state.transform.origin
		state.apply_force(spring_force, mount_offset)
		if h_state != null:
			h_state.apply_central_force(-spring_force)
		else:
			hub.apply_central_force(-spring_force)

		radial_deflection_m[i] = 0.0
		radial_dissipation_w[i] = 0.0
		radial_states[i] = { }
		if not bool(contacts[i].get("hit", false)):
			suspension.contact_active[i] = false
			continue

		var normal: Vector3 = (contacts[i].normal as Vector3).normalized()
		var cos_angle := clampf(normal.dot(up), 0.25, 1.0)
		var road_compression := radii[i] - float(contacts[i].distance)
		var prev_deflection := radial_deflection_m[i]
		var deflection := maxf((road_compression - comp) * cos_angle, 0.0)
		radial_deflection_m[i] = deflection

		var road_velocity := Vector3.ZERO
		var collider: Object = contacts[i].get("collider")
		if collider is RigidBody3D:
			var road_body := collider as RigidBody3D
			road_velocity = road_body.linear_velocity + road_body.angular_velocity.cross(
				(contacts[i].position as Vector3) - road_body.global_position
			)

		var relative_hub_vel := hub_velocities[i] - road_velocity
		var axial_compression_speed := -relative_hub_vel.dot(up) * cos_angle
		var compression_speed := clampf(axial_compression_speed, -12.0, 12.0)

		var tire_state := thermal.get_tire_thermal_state_snapshot(i)
		var tires: Dictionary = domains.get("tires", { }).get("tires", { })
		var radial := TireRadialModel.evaluate(
			tires,
			"front" if i < 2 else "rear",
			float(tire_state.get("pressure_kpa_gauge", 180.0)),
			float(tire_state.get("carcass_c", 25.0)),
			hub.mass,
			deflection,
			compression_speed,
		)
		radial_states[i] = radial
		var tire_force := maxf(float(radial.force_n), 0.0)
		radial_dissipation_w[i] = float(radial.dissipation_w)
		normal_loads[i] = tire_force
		suspension.contact_active[i] = tire_force > 0.0

		var total_tire_vec := normal * tire_force
		var axial_tire_vec := up * total_tire_vec.dot(up)
		var lateral_normal_vec := total_tire_vec - axial_tire_vec

		if h_state != null:
			h_state.apply_central_force(axial_tire_vec)
		else:
			hub.apply_central_force(axial_tire_vec)
		state.apply_force(lateral_normal_vec, mount_offset)

	return normal_loads
