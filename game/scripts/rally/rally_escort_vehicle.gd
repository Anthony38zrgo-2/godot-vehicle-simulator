class_name RallyEscortVehicle
extends RigidBody3D

const PROFILE_PATH := "res://data/vehicles/ford-escort-rs2000/vehicle.json"
const ASSET_MANIFEST_PATH := "res://assets/rally/ford_escort_rs2000_1971/manifest.json"
const COLLISION_PATH := "res://assets/rally/ford_escort_rs2000_1971/ford_escort_rs2000_1971_collision.json"

@export var rally_profile_path: String = PROFILE_PATH
@export var asset_manifest_path: String = ASSET_MANIFEST_PATH
@export var rally_collision_path: String = COLLISION_PATH

var simulation := FordRallyVehicleSimulation.new()
var rally_profile: Dictionary = {}
var rally_asset_manifest: Dictionary = {}
var driving_assistance_state: Dictionary = {
	"traction_control": false,
	"stability": false,
	"anti_lock_brakes": false,
	"countersteer": false,
	"automatic_transmission": false,
}
var maximum_forward_gear: int = 0
var maximum_steering_angle: float = 0.0
var steering_speed: float = 5.0
var countersteer_speed: float = 5.0
var steering_speed_decay: float = 0.05
var steering_filter_start_kph: float = 20.0
var steering_filter_reference_kph: float = 65.0
var steering_filter_minimum_gain: float = 0.20
var steering_exponent: float = 1.0
var front_steering_ratio: float = 1.0
var rear_steering_ratio: float = 0.0
var throttle_input: float = 0.0
var brake_input: float = 0.0
var steering_input: float = 0.0
var handbrake_input: float = 0.0
var clutch_input: float = 0.0
var throttle_amount: float = 0.0
var brake_amount: float = 0.0
var steering_amount: float = 0.0
var true_steering_amount: float = 0.0
var handbrake_amount: float = 0.0
var clutch_amount: float = 1.0
var automatic_transmission: bool = false
var is_shifting: bool = false
var traction_control_max_slip: float = 0.0
var enable_stability: bool = false
var stability_yaw_strength: float = 0.0
var countersteer_assist: float = 0.0
var steering_slip_assist: float = 0.0
var front_abs_spin_difference_threshold: float = INF
var rear_abs_spin_difference_threshold: float = INF
var last_impact_speed_metres_per_second: float = 0.0
var _physics_ready: bool = false
var _reset_pending: bool = false
var _input_smoothing: Dictionary = {}
var _applied_fuel_mass_kg: float = -1.0

var current_gear: int:
	get:
		return simulation.powertrain_model.current_gear
	set(value):
		simulation.powertrain_model.set_gear(value)

var motor_rpm: float:
	get:
		return simulation.powertrain_model.engine_rpm

var idle_rpm: float:
	get:
		return simulation.powertrain_model.idle_rpm

var max_rpm: float:
	get:
		return simulation.powertrain_model.maximum_rpm

var speed: float:
	get:
		return linear_velocity.length()

var max_steering_angle: float:
	get:
		return maximum_steering_angle


func _ready() -> void:
	var manifest := _load_json_document(asset_manifest_path)
	if manifest.is_empty():
		push_error("Ford Rally asset manifest is unavailable: " + asset_manifest_path)
		set_physics_process(false)
		return
	rally_asset_manifest = manifest
	var result := simulation.configure(manifest, rally_profile_path)
	if not bool(result.get("ok", false)):
		push_error("Ford Rally profile configuration failed: " + str(result.get("error", "unknown error")))
		set_physics_process(false)
		return
	var collision_document := _load_json_document(rally_collision_path)
	if collision_document.is_empty():
		push_error("Rally collision document is unavailable: " + rally_collision_path)
		set_physics_process(false)
		return
	rally_profile = {
		"profile_id": result.get("profile_id", "ford_escort_rs2000_1971"),
		"domain_hashes": result.get("domain_hashes", {}),
	}
	apply_vehicle_properties()
	build_collision_shapes(collision_document)
	bind_wheel_visuals()
	simulation.create_wheel_contact_casts(self)
	add_to_group("rally_vehicle")
	contact_monitor = true
	max_contacts_reported = 8
	if not body_entered.is_connected(record_impact):
		body_entered.connect(record_impact)
	_physics_ready = true
	print("RALLY_VEHICLE_PROFILE_READY id=", rally_profile.profile_id, " sprung_mass_kg=", mass, " vehicle_mass_kg=", simulation.mass_model.resolve(simulation.mass_model.fuel_initial_kg).vehicle_total_mass_kg, " domains=", simulation.domain_hashes.size(), " contact_type=ShapeCast3D shape_count=4")


func apply_vehicle_properties() -> void:
	var steering: Dictionary = simulation.domains.get("steering", {}).get("steering", {})
	maximum_steering_angle = simulation.maximum_steering_angle_rad
	steering_exponent = simulation.steering_exponent
	steering_speed = float(steering.get("steering_speed", 5.0))
	countersteer_speed = steering_speed
	steering_speed_decay = float(steering.get("steering_speed_decay", 0.0))
	steering_filter_start_kph = maxf(float(steering.get("speed_filter_start_kph", 20.0)), 0.0)
	steering_filter_reference_kph = maxf(float(steering.get("speed_filter_reference_kph", 65.0)), 1.0)
	steering_filter_minimum_gain = clampf(float(steering.get("speed_filter_minimum_gain", 0.20)), 0.05, 1.0)
	front_steering_ratio = simulation.front_steering_ratio
	rear_steering_ratio = simulation.rear_steering_ratio
	var aids: Dictionary = simulation.domains.get("driving_assistance", {}).get("aids", {})
	_input_smoothing = {
		"enabled": bool(aids.get("input_smoothing_enabled", false)),
		"throttle": float(aids.get("input_smoothing_throttle_rate", 0.0)),
		"brake": float(aids.get("input_smoothing_brake_rate", 0.0)),
		"steering": float(aids.get("input_smoothing_steering_rate", 0.0)),
	}
	var fuel := simulation.mass_model.fuel_initial_kg
	var mass_state: Dictionary = simulation.mass_model.resolve(fuel)
	_apply_resolved_mass(mass_state)
	_applied_fuel_mass_kg = fuel
	can_sleep = false
	sleeping = false
	continuous_cd = true
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	collision_layer = 2
	collision_mask = 1
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.9
	physics_material_override.bounce = 0.0
	automatic_transmission = simulation.powertrain_model.automatic_transmission
	maximum_forward_gear = simulation.powertrain_model.maximum_forward_gear
	driving_assistance_state["automatic_transmission"] = automatic_transmission


func apply_setup_values(values: Dictionary) -> Dictionary:
	var result := simulation.apply_setup_values(values)
	if not bool(result.get("ok", false)):
		return result
	maximum_steering_angle = simulation.maximum_steering_angle_rad
	var steering: Dictionary = simulation.domains.get("steering", {}).get("steering", {})
	steering_speed = float(steering.get("steering_speed", steering_speed))
	countersteer_speed = steering_speed
	var fuel_kg := simulation.thermal_model.fuel_remaining_litres * simulation.mass_model.fuel_density_kg_per_litre
	_apply_resolved_mass(simulation.mass_model.resolve(fuel_kg))
	_applied_fuel_mass_kg = fuel_kg
	return result


func service_new_tires() -> void:
	for index in 4:
		var state: Dictionary = simulation.thermal_model.tire_states[index]
		state.surface_c = simulation.thermal_model.ambient_temperature_c
		state.tread_c = simulation.thermal_model.ambient_temperature_c
		state.tread_zones_c = [simulation.thermal_model.ambient_temperature_c, simulation.thermal_model.ambient_temperature_c, simulation.thermal_model.ambient_temperature_c]
		state.carcass_c = simulation.thermal_model.ambient_temperature_c
		state.gas_c = simulation.thermal_model.ambient_temperature_c
		state.wear_fraction = 0.0
		state.brake_disc_c = simulation.thermal_model.ambient_temperature_c
		simulation.thermal_model.tire_states[index] = state
		simulation.tire_model.states[index] = {
			"effective_slip_angle": 0.0, "effective_slip_ratio": 0.0,
			"post_peak_decay_lat": 0.0, "post_peak_decay_lon": 0.0,
			"contact_blend": 0.0, "surface_initialized": false,
			"surface_friction": 0.0, "surface_stiffness": 0.0,
			"surface_rolling": 0.0, "slip_angle": 0.0, "slip_ratio": 0.0,
			"combined_utilization": 0.0, "longitudinal_force": 0.0,
			"lateral_force": 0.0, "aligning_torque": 0.0,
			"friction_power": 0.0, "surface": "Unknown",
		}


func bind_wheel_visuals() -> void:
	var pivots: Array[Node3D] = []
	var visuals: Array[Node3D] = []
	for node_name in ["WheelFrontLeft", "WheelFrontRight", "WheelRearLeft", "WheelRearRight"]:
		var pivot := get_node_or_null(NodePath(node_name)) as Node3D
		if pivot == null:
			push_error("Missing wheel visual pivot: " + node_name)
			return
		pivots.append(pivot)
		visuals.append(pivot.get_node("WheelVisual") as Node3D)
		pivot.position = simulation.wheel_positions_local[pivots.size() - 1]
	simulation.bind_wheel_visuals(pivots, visuals)


func build_collision_shapes(collision_document: Dictionary) -> void:
	for hull_document in collision_document.get("hulls", []):
		var points := PackedVector3Array()
		for point_document in hull_document.get("points", []):
			points.append(Vector3(float(point_document.get("x", 0.0)), float(point_document.get("y", 0.0)), float(point_document.get("z", 0.0))))
		if points.size() < 4:
			continue
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "CollisionHull" + str(hull_document.get("identifier", "body")).capitalize()
		collision_shape.shape = shape
		add_child(collision_shape)
	for box_document in collision_document.get("boxes", []):
		var half_extents: Dictionary = box_document.get("half_extents", {})
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(float(half_extents.get("x", 0.5)) * 2.0, float(half_extents.get("y", 0.5)) * 2.0, float(half_extents.get("z", 0.5)) * 2.0)
		var box_collision := CollisionShape3D.new()
		box_collision.name = "CollisionBox" + str(box_document.get("identifier", "body")).capitalize()
		box_collision.shape = box_shape
		var center: Dictionary = box_document.get("center", {})
		box_collision.position = Vector3(float(center.get("x", 0.0)), float(center.get("y", 0.0)), float(center.get("z", 0.0)))
		add_child(box_collision)


func _physics_process(delta: float) -> void:
	if _reset_pending:
		freeze = false
		_reset_pending = false
	if not _physics_ready:
		return
	simulation.unsprung_rig.sync_freeze()
	simulation.update_wheel_visuals(steering_amount, delta)
	_sync_mass_from_fuel()
	var smoothing_enabled := bool(_input_smoothing.get("enabled", false))
	throttle_amount = _shape_input(throttle_amount, throttle_input, float(_input_smoothing.get("throttle", 0.0)), delta, smoothing_enabled)
	brake_amount = _shape_input(brake_amount, brake_input, float(_input_smoothing.get("brake", 0.0)), delta, smoothing_enabled)
	handbrake_amount = clampf(handbrake_input, 0.0, 1.0)
	# Attenuate the command before the existing steering exponent and Ackermann.
	# Tangential speed avoids reducing authority merely because the car is falling.
	var local_velocity := global_basis.inverse() * linear_velocity
	var planar_speed_kph := Vector2(local_velocity.x, local_velocity.z).length() * 3.6
	var excess_speed := maxf(planar_speed_kph - steering_filter_start_kph, 0.0)
	var steering_gain := maxf(steering_filter_minimum_gain, 1.0 / (1.0 + pow(excess_speed / steering_filter_reference_kph, 2.0)))
	var steering_target := clampf(steering_input, -1.0, 1.0) * steering_gain
	var returning := absf(steering_target) < absf(steering_amount)
	var steering_rate := countersteer_speed if returning else steering_speed / (1.0 + steering_speed_decay * planar_speed_kph / 3.6)
	steering_amount = move_toward(steering_amount, steering_target, maxf(steering_rate, 0.0) * steering_gain * delta)
	true_steering_amount = steering_amount * maximum_steering_angle
	var auto_clutch: bool = bool(simulation.domains.get("driving_assistance", {}).get("aids", {}).get("auto_clutch_default_enabled", false))
	clutch_amount = 1.0 - clampf(clutch_input, 0.0, 1.0)
	if auto_clutch and clutch_input <= 0.0:
		clutch_amount = 0.0 if current_gear == 0 else 1.0
	if automatic_transmission and speed < 1.0 and brake_amount > 0.0 and throttle_amount > 0.1 and current_gear == 0:
		clutch_amount = 0.0
	is_shifting = simulation.powertrain_model.shift_remaining_seconds > 0.0


func _shape_input(previous: float, target: float, rate: float, delta: float, enabled: bool) -> float:
	var clamped_target := clampf(target, 0.0, 1.0)
	if not enabled or rate <= 0.0:
		return clamped_target
	return move_toward(previous, clamped_target, rate * delta)


func _sync_mass_from_fuel() -> void:
	var fuel_mass := simulation.thermal_model.fuel_remaining_litres * simulation.mass_model.fuel_density_kg_per_litre
	if absf(fuel_mass - _applied_fuel_mass_kg) < 0.01:
		return
	_apply_resolved_mass(simulation.mass_model.resolve(fuel_mass))
	_applied_fuel_mass_kg = fuel_mass


func _apply_resolved_mass(mass_state: Dictionary) -> void:
	mass = float(mass_state.get("mass_kg", 1.0))
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = mass_state.get("center_of_mass", Vector3.ZERO)
	inertia = mass_state.get("inertia", Vector3.ONE)


var body_contact_audio: Dictionary = {}
var _prev_body_contact_count: int = 0

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _physics_ready or freeze:
		return
	var contact_count := state.get_contact_count()
	# Toma de tierra: primer frame con contactos tras venir volando y cayendo.
	var landing_speed_ms := 0.0
	if contact_count > 0 and _prev_body_contact_count == 0:
		var fall_speed := -state.linear_velocity.y
		if fall_speed >= 2.5:
			landing_speed_ms = fall_speed
	_prev_body_contact_count = contact_count
	var impulse_peak := 0.0
	var scrape_power := 0.0
	var ground_drag_power := 0.0
	# Strongest closing contact this frame: speed selects the impact tier
	# (<40 small, 40-70 medium, >70 large km/h) and the local position stages
	# the one-shot in 3D where the hit landed.
	var impact_speed_ms := 0.0
	var impact_position := Vector3.ZERO
	for index in state.get_contact_count():
		var impulse := state.get_contact_impulse(index).length()
		impulse_peak = maxf(impulse_peak, impulse)
		var normal := (state.transform.basis * state.get_contact_local_normal(index)).normalized()
		var velocity := state.get_contact_local_velocity_at_position(index) - state.get_contact_collider_velocity_at_position(index)
		var closing_speed := absf(velocity.dot(normal))
		if closing_speed > impact_speed_ms:
			impact_speed_ms = closing_speed
			impact_position = state.get_contact_local_position(index)
		var tangent_speed := (velocity - normal * velocity.dot(normal)).length()
		var force := impulse / maxf(state.step, 0.0001)
		if force > mass * 9.81 * 0.10 and tangent_speed > 0.5:
			var collider := state.get_contact_collider_object(index)
			var is_ground: bool = collider is Node and (str(collider.get_meta("collision_role", "")) == "terrain" or collider.is_in_group("Gravel"))
			if is_ground:
				ground_drag_power += force * tangent_speed
			else:
				scrape_power += force * tangent_speed
	body_contact_audio = {"count": state.get_contact_count(), "impulse_ns": impulse_peak, "impact_speed_kph": impact_speed_ms * 3.6, "impact_position": impact_position, "landing_speed_ms": landing_speed_ms, "scrape_power_w": scrape_power, "ground_drag_power_w": ground_drag_power, "height_m": state.transform.origin.y}
	simulation.step(self, state, {
		"throttle": throttle_amount,
		"brake": brake_amount,
		"steering": steering_amount,
		"handbrake": handbrake_amount,
		"clutch": clutch_amount,
		"auto_clutch": bool(simulation.domains.get("driving_assistance", {}).get("aids", {}).get("auto_clutch_default_enabled", false)),
		"automatic_transmission": automatic_transmission,
	})


func shift(delta_gears: int) -> void:
	if automatic_transmission:
		return
	simulation.powertrain_model.request_shift(delta_gears)


func toggle_driving_assistance(assistance_name: String) -> Dictionary:
	if assistance_name == "automatic_transmission":
		automatic_transmission = not automatic_transmission
		simulation.powertrain_model.automatic_transmission = automatic_transmission
		driving_assistance_state[assistance_name] = automatic_transmission
	elif bool(simulation.assistance_available.get(assistance_name, false)):
		driving_assistance_state[assistance_name] = not bool(driving_assistance_state.get(assistance_name, false))
	match assistance_name:
		"traction_control":
			simulation.traction_control_enabled = bool(driving_assistance_state[assistance_name])
		"stability":
			enable_stability = bool(driving_assistance_state[assistance_name])
		"anti_lock_brakes":
			simulation.abs_enabled = bool(driving_assistance_state[assistance_name])
	return driving_assistance_state.duplicate(true)


func reset_to_pose(target_position: Vector3, target_yaw: float) -> void:
	freeze = true
	global_transform = Transform3D(Basis(Vector3.UP, target_yaw), target_position)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	simulation.reset_dynamics()
	throttle_input = 0.0
	brake_input = 0.0
	steering_input = 0.0
	handbrake_input = 0.0
	clutch_input = 0.0
	throttle_amount = 0.0
	brake_amount = 0.0
	steering_amount = 0.0
	true_steering_amount = 0.0
	clutch_amount = 1.0
	sleeping = false
	_reset_pending = true


func record_impact(_other_body: Node) -> void:
	last_impact_speed_metres_per_second = linear_velocity.length()


func get_number_of_contacting_wheels() -> int:
	var count := 0
	for contact in simulation.suspension_model.contact_active:
		if contact:
			count += 1
	return count


func get_wheel_compressions_millimetres() -> Array[float]:
	var values: Array[float] = []
	for value in simulation.suspension_model.compression:
		values.append(value * 1000.0)
	return values


func get_wheel_surface_types() -> Array[String]:
	return simulation.wheel_surfaces.duplicate()


func get_wheel_spin_radians_per_second() -> Array[float]:
	return simulation.wheel_spins.duplicate()


func get_wheel_slip_vectors() -> Array[Vector2]:
	return simulation.wheel_slips.duplicate()


func get_engine_thermal_state() -> Dictionary:
	return simulation.thermal_model.get_engine_thermal_state_snapshot()


func get_tire_thermal_state(index: int) -> Dictionary:
	return simulation.thermal_model.get_tire_thermal_state_snapshot(index)


func get_fuel_state() -> Dictionary:
	return simulation.thermal_model.get_fuel_state_snapshot()


func get_wheel_contact_count() -> int:
	return get_number_of_contacting_wheels()


func is_airborne() -> bool:
	return get_number_of_contacting_wheels() == 0


func is_overturned() -> bool:
	return global_transform.basis.y.dot(Vector3.UP) < 0.25


func get_rally_state() -> Dictionary:
	return {
		"position": global_position,
		"linear_velocity": linear_velocity,
		"angular_velocity": angular_velocity,
		"speed_metres_per_second": speed,
		"speed_kilometres_per_hour": speed * 3.6,
		"engine_revolutions_per_minute": motor_rpm,
		"current_gear": current_gear,
		"maximum_forward_gear": maximum_forward_gear,
		"throttle": throttle_amount,
		"brake": brake_amount,
		"clutch": clutch_amount,
		"steering_amount": steering_amount,
		"true_steering_amount": true_steering_amount,
		"number_of_contacting_wheels": get_number_of_contacting_wheels(),
		"contact_query_count": simulation.contact_query_count,
		"wheel_compressions_millimetres": get_wheel_compressions_millimetres(),
		"wheel_surface_types": get_wheel_surface_types(),
		"wheel_spin_radians_per_second": get_wheel_spin_radians_per_second(),
		"wheel_slip_vectors": get_wheel_slip_vectors(),
		"wheel_loads_newtons": simulation.wheel_loads.duplicate(),
		"airborne": is_airborne(),
		"overturned": is_overturned(),
		"sleeping": sleeping,
		"driving_assistance": driving_assistance_state.duplicate(true),
		"traction_control_max_slip": traction_control_max_slip,
		"stability_enabled": enable_stability,
		"countersteer_assist": countersteer_assist,
		"steering_slip_assist": steering_slip_assist,
		"anti_lock_brake_spin_difference_threshold": -1.0 if not bool(simulation.assistance_available.get("anti_lock_brakes", false)) else front_abs_spin_difference_threshold,
		"engine_thermal": get_engine_thermal_state(),
		"tire_thermal": [get_tire_thermal_state(0), get_tire_thermal_state(1), get_tire_thermal_state(2), get_tire_thermal_state(3)],
		"fuel": get_fuel_state(),
		"automatic_transmission": automatic_transmission,
	}


func _load_json_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	return value if value is Dictionary else {}


func get_presentation_snapshot() -> Dictionary:
	return simulation.published_state.duplicate(true)
