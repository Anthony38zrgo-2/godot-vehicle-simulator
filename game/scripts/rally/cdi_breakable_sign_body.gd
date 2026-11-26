extends RigidBody3D
## A light body even while anchored, so the contact solver never sees a wall.

var anchor := Transform3D.IDENTITY
var anchored := true


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not anchored:
		return
	# Read contacts on the sign as well as the car. Terrain contacts can
	# occupy the car's contact report, and the solver can already have moved
	# this light body before either callback observes the impact.
	for index in state.get_contact_count():
		var car := state.get_contact_collider_object(index) as RigidBody3D
		if car == null or not car.has_method("_apply_sign_impact"):
			continue
		var normal := (state.transform.basis * state.get_contact_local_normal(index)).normalized()
		var point := state.get_contact_collider_position(index)
		var velocity := state.get_contact_collider_velocity_at_position(index)
		var impulse := state.get_contact_impulse(index).length()
		var reduced_mass := mass * car.mass / maxf(mass + car.mass, 0.001)
		var speed := maxf(0.0, -velocity.dot(normal)) + impulse / maxf(car.mass, 0.001)
		# Normal for the car points away from the sign.
		car._apply_sign_impact(self, speed, maxf(impulse, reduced_mass * speed), -normal, point, car.global_transform)
		if not anchored:
			return
	state.transform = anchor
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO
