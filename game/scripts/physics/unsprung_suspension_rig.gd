class_name UnsprungSuspensionRig
extends RefCounted

var chassis: RigidBody3D
var hubs: Array[RigidBody3D] = []
var joints: Array[Generic6DOFJoint3D] = []
var neutral_positions: Array[Vector3] = []
var radial_deflection_m: Array[float] = [0.0, 0.0, 0.0, 0.0]
var radial_dissipation_w: Array[float] = [0.0, 0.0, 0.0, 0.0]
var radial_states: Array[Dictionary] = [{}, {}, {}, {}]
var spring_forces_n: Array[float] = [0.0, 0.0, 0.0, 0.0]


func create(body: RigidBody3D, positions: Array[Vector3], masses: Array[float], suspension: VehicleSuspensionModel) -> void:
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
		# Shape defines hub inertia only. Tire-ground forces come from ShapeCast3D
		# and the compliant radial law, so collision masks deliberately disable it.
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
		# X/Z translation and all angular axes locked; Y is suspension travel.
		joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -float(suspension.axle_parameters[i].droop_m))
		joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, float(suspension.axle_parameters[i].bump_m))
		joints.append(joint)
	print("RALLY_UNSPRUNG_READY ", JSON.stringify({"hub_masses_kg": masses, "sprung_mass_kg": body.mass, "hub_bodies": hubs.size()}))


func reset() -> void:
	for i in hubs.size():
		hubs[i].global_transform = chassis.global_transform * Transform3D(Basis.IDENTITY, neutral_positions[i])
		hubs[i].linear_velocity = Vector3.ZERO
		hubs[i].angular_velocity = Vector3.ZERO
		hubs[i].constant_force = Vector3.ZERO
		radial_deflection_m[i] = 0.0
		radial_dissipation_w[i] = 0.0
		radial_states[i] = {}


func sync_freeze() -> void:
	for hub in hubs:
		hub.freeze = chassis.freeze


func solve(state: PhysicsDirectBodyState3D, suspension: VehicleSuspensionModel, contacts: Array[Dictionary], radii: Array[float], domains: Dictionary, thermal: VehicleThermalModel) -> Array[float]:
	var up := state.transform.basis.y.normalized()
	var com := state.transform * chassis.center_of_mass
	for i in 4:
		var neutral := state.transform * neutral_positions[i]
		var hub := hubs[i]
		var body_point_velocity := state.linear_velocity + state.angular_velocity.cross(hub.global_position - com)
		suspension.compression[i] = (hub.global_position - neutral).dot(up)
		suspension.compression_velocity[i] = (hub.linear_velocity - body_point_velocity).dot(up)
		suspension.filtered_arb_travel[i] = suspension.compression[i]
		suspension.initialized[i] = true
		suspension.previous_samples[i] = true
	spring_forces_n = suspension.suspension_forces()
	var normal_loads: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		var hub := hubs[i]
		var spring_force := up * spring_forces_n[i]
		state.apply_force(spring_force, hub.global_position - state.transform.origin)
		hub.apply_central_force(-spring_force)
		radial_deflection_m[i] = 0.0
		radial_dissipation_w[i] = 0.0
		radial_states[i] = {}
		if not bool(contacts[i].get("hit", false)):
			suspension.contact_active[i] = false
			continue
		var normal: Vector3 = contacts[i].normal
		var road_compression := radii[i] - float(contacts[i].distance)
		var deflection := maxf((road_compression - suspension.compression[i]) * normal.dot(up), 0.0)
		radial_deflection_m[i] = deflection
		var road_velocity := Vector3.ZERO
		var collider: Object = contacts[i].get("collider")
		if collider is RigidBody3D:
			var road_body := collider as RigidBody3D
			road_velocity = road_body.linear_velocity + road_body.angular_velocity.cross((contacts[i].position as Vector3) - road_body.global_position)
		var compression_speed := -(hub.linear_velocity - road_velocity).dot(normal)
		var tire_state := thermal.get_tire_thermal_state_snapshot(i)
		var tires: Dictionary = domains.get("tires", {}).get("tires", {})
		var radial := TireRadialModel.evaluate(tires, "front" if i < 2 else "rear", float(tire_state.get("pressure_kpa_gauge", 180.0)), float(tire_state.get("carcass_c", 25.0)), hub.mass, deflection, compression_speed)
		radial_states[i] = radial
		var tire_force := float(radial.force_n)
		radial_dissipation_w[i] = float(radial.dissipation_w)
		normal_loads[i] = tire_force
		suspension.contact_active[i] = tire_force > 0.0
		hub.apply_central_force(normal * tire_force)
	return normal_loads
