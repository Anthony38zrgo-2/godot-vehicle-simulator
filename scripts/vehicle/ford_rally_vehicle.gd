extends RigidBody3D

const VehicleSimulationScript = preload("res://scripts/physics/vehicle_simulation.gd")
const ProfileRoot := "res://data/vehicles/ford-escort-rs2000/"

var simulation := VehicleSimulationScript.new()
var profile_documents: Dictionary = {}
var wheel_spin_speeds: Array[float] = [0.0, 0.0, 0.0, 0.0]
var engine_revolutions_per_minute := 1800.0

func _ready() -> void:
	for domain_name in ["chassis", "suspension", "tires", "tire_filters", "powertrain", "aerodynamics"]:
		profile_documents[domain_name] = load_domain(domain_name)
	simulation.configure(profile_documents["tires"])
	mass = float(profile_documents["chassis"]["chassis"]["vehicle_mass"]) + 80.0
	position.y = 1.0

func load_domain(domain_name: String) -> Dictionary:
	var file := FileAccess.open(ProfileRoot + domain_name + ".json", FileAccess.READ)
	if file == null:
		push_error("Missing vehicle domain: " + domain_name)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func _physics_process(delta: float) -> void:
	var steering := Input.get_axis("ui_left", "ui_right")
	var throttle := Input.get_action_strength("ui_up")
	var brake := Input.get_action_strength("ui_down")
	var wheel_names := ["WheelFrontLeft", "WheelFrontRight", "WheelRearLeft", "WheelRearRight"]
	var tire_data: Dictionary = profile_documents["tires"]["tires"]
	var suspension_data: Dictionary = profile_documents["suspension"]["suspension"]
	for wheel_index in 4:
		var wheel: RayCast3D = get_node(wheel_names[wheel_index])
		wheel.force_raycast_update()
		if not wheel.is_colliding():
			continue
		var axle := "front" if wheel_index < 2 else "rear"
		var axle_suspension: Dictionary = suspension_data[axle]
		var compression := clampf(0.32 - wheel.get_collision_point().distance_to(wheel.global_position), -0.12, 0.18)
		var spring_force := maxf(0.0, compression * (28000.0 if axle == "front" else 24000.0))
		var contact_point := wheel.get_collision_point()
		var contact_velocity := linear_velocity + angular_velocity.cross(contact_point - global_position)
		var local_velocity := global_basis.inverse() * contact_velocity
		var target_slip := Vector2((wheel_spin_speeds[wheel_index] * 0.28 - local_velocity.z) / maxf(absf(local_velocity.z), 0.5), atan(-local_velocity.x / maxf(absf(local_velocity.z), 0.5)))
		var filtered_slip: Vector2 = simulation.advance_tire_filter(wheel_index, target_slip, linear_velocity.length(), delta, profile_documents["tire_filters"])
		var normal_load := maxf(spring_force, mass * 9.81 / 4.0)
		var tire_force: Vector2 = simulation.tire_model.evaluate(filtered_slip.x, filtered_slip.y, normal_load, 1.08)
		var steer_angle := steering * 0.52 if wheel_index < 2 else 0.0
		var wheel_basis := Basis(Vector3.UP, steer_angle)
		var force := wheel_basis * Vector3(tire_force.y, spring_force, -tire_force.x)
		apply_force(force, contact_point - global_position)
		wheel_spin_speeds[wheel_index] += ((throttle * 180.0 if wheel_index >= 2 else 0.0) - brake * 70.0 * signf(wheel_spin_speeds[wheel_index]) - tire_force.x * 0.28) / 0.8 * delta
		var friction_power := absf(tire_force.x * (wheel_spin_speeds[wheel_index] * 0.28 - local_velocity.z)) + absf(tire_force.y * local_velocity.x)
		simulation.advance_tire_temperature(wheel_index, friction_power, 25.0, delta)
	engine_revolutions_per_minute = move_toward(engine_revolutions_per_minute, 1800.0 + throttle * 7000.0, 6000.0 * delta)
	var air_data: Dictionary = profile_documents["aerodynamics"]["aerodynamics"]
	var drag := 0.5 * 1.225 * 1.85 * float(air_data.get("drag_coefficient", 0.42)) * linear_velocity.length_squared()
	apply_central_force(-linear_velocity.normalized() * drag)
