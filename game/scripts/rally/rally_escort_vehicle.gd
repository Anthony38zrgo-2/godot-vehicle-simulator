class_name RallyEscortVehicle
extends RigidBody3D

signal backfire_triggered

const PROFILE_PATH := "res://data/vehicles/ford-escort-rs2000/vehicle.json"
const ASSET_MANIFEST_PATH := "res://assets/rally/ford_escort_rs2000_1971/manifest.json"
const COLLISION_PATH := "res://assets/rally/ford_escort_rs2000_1971/ford_escort_rs2000_1971_collision.json"

@export var rally_profile_path: String = PROFILE_PATH
@export var asset_manifest_path: String = ASSET_MANIFEST_PATH
@export var rally_collision_path: String = COLLISION_PATH
@export var cockpit_camera_enabled: bool = true
@export_group("Dreamcast Vehicle Aesthetics")
@export var dreamcast_car_visuals: bool = true
@export var dc_enable_blob_shadow: bool = true
@export var dc_blob_shadow_size: Vector2 = Vector2(1.95, 4.35)
@export var dc_blob_shadow_opacity: float = 0.78

var _blob_shadow_decal: Decal = null

var simulation := FordRallyVehicleSimulation.new()
var tire_inventory = preload("res://scripts/rally/rally_tire_inventory.gd").new()
# Política de temperatura de salida del compuesto (tire_rules del evento).
var start_temperature_policy: String = "selected_compound_optimum"
const TIRE_STATE_KEYS := ["surface_c", "tread_c", "tread_zones_c", "carcass_c", "gas_c", "pressure_bar_gauge", "pressure_reference_bar_gauge", "pressure_reference_temp_c", "wear_fraction", "thermal_damage_fraction", "pressure_loss_fraction", "leak_per_second", "rim_deformation", "carcass_failure"]
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
var _rescue_pose: Variant = null
@onready var _visual_damage := get_node_or_null("VisualDamage")
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
	# Lighter unsprung assemblies can require a faster world step than the Ford.
	var world_tune: Dictionary = simulation.domains.get("coupled_world", {}).get("coupled_world", {})
	Engine.physics_ticks_per_second = maxi(Engine.physics_ticks_per_second, int(world_tune.get("minimum_physics_ticks_per_second", 60)))
	build_collision_shapes(collision_document)
	bind_wheel_visuals()
	if dreamcast_car_visuals:
		_apply_dreamcast_vehicle_visuals()
	simulation.create_wheel_contact_casts(self)
	add_to_group("rally_vehicle")
	contact_monitor = true
	max_contacts_reported = 8
	if not body_entered.is_connected(record_impact):
		body_entered.connect(record_impact)
	_physics_ready = true
	print("RALLY_VEHICLE_PROFILE_READY id=", rally_profile.profile_id, " sprung_mass_kg=", mass, " vehicle_mass_kg=", simulation.mass_model.resolve(simulation.mass_model.fuel_initial_kg).vehicle_total_mass_kg, " contact_type=ShapeCast3D shape_count=4")


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
	physics_material_override.friction = 0.35
	physics_material_override.bounce = 0.0
	automatic_transmission = simulation.powertrain_model.automatic_transmission
	maximum_forward_gear = simulation.powertrain_model.maximum_forward_gear
	driving_assistance_state["automatic_transmission"] = automatic_transmission


func apply_setup_values(values: Dictionary) -> Dictionary:
	var effective := values.duplicate(true)
	var session := get_parent()
	var retained_fuel := simulation.thermal_model.fuel_remaining_litres
	var preserve_fuel := session != null and session.has_method("may_refuel") and not bool(session.call("may_refuel"))
	if preserve_fuel:
		effective["fuel.initial_kg"] = simulation.thermal_model.fuel_remaining_litres * simulation.mass_model.fuel_density_kg_per_litre
	var result := simulation.apply_setup_values(effective)
	if not bool(result.get("ok", false)):
		return result
	if preserve_fuel:
		simulation.thermal_model.fuel_remaining_litres = retained_fuel
		result.values["fuel.initial_kg"] = retained_fuel * simulation.mass_model.fuel_density_kg_per_litre
	maximum_steering_angle = simulation.maximum_steering_angle_rad
	var steering: Dictionary = simulation.domains.get("steering", {}).get("steering", {})
	steering_speed = float(steering.get("steering_speed", steering_speed))
	countersteer_speed = steering_speed
	var fuel_kg := simulation.thermal_model.fuel_remaining_litres * simulation.mass_model.fuel_density_kg_per_litre
	_apply_resolved_mass(simulation.mass_model.resolve(fuel_kg))
	_applied_fuel_mass_kg = fuel_kg
	return result


func service_new_tires(compound_id: String = "") -> void:
	var cid := str(compound_id) if str(compound_id) != "" else simulation.active_compound_id
	if cid == "":
		cid = "gravel_normal"
	set_tire_compound(cid)
	# Objetivos iniciales específicos del compuesto (no 50/60 fijos para ambos).
	var tread_target := 50.0
	var carcass_target := 60.0
	if not simulation.thermal_model.active_compound.is_empty():
		tread_target = float(simulation.thermal_model.active_compound.get("tread_optimum_c", tread_target))
		carcass_target = float(simulation.thermal_model.active_compound.get("carcass_optimum_c", carcass_target))
	else:
		# Respaldo por eje (ya refleja el compuesto tras set_compound).
		tread_target = float(simulation.thermal_model.tire_config.get("optimal_tread_temperature_c", tread_target))
		carcass_target = float(simulation.thermal_model.tire_config.get("optimal_carcass_temperature_c", carcass_target))
	for index in 4:
		var state: Dictionary = simulation.thermal_model.tire_states[index]
		state.surface_c = tread_target
		state.tread_c = tread_target
		state.tread_zones_c = [tread_target, tread_target, tread_target]
		state.carcass_c = carcass_target
		state.gas_c = carcass_target
		state.wear_fraction = 0.0
		state.thermal_damage_fraction = 0.0
		# Presión coherente con gas: conserva el reglaje frío y recalcula.
		var cold: Dictionary = (simulation.domains.get("tires", {}).get("tires", {}).get("pressure", {}) as Dictionary).get("cold_kpa_gauge", {})
		var key: String = ["FL", "FR", "RL", "RR"][index]
		var cold_bar := float(cold.get(key, 180.0)) / 100.0
		var ref_temp := float((simulation.domains.get("tires", {}).get("tires", {}).get("pressure", {}) as Dictionary).get("reference_temperature_c", 25.0))
		var atm := float((simulation.domains.get("tires", {}).get("tires", {}).get("pressure", {}) as Dictionary).get("atmospheric_pressure_kpa", 101.325)) / 100.0
		state.pressure_reference_bar_gauge = cold_bar
		state.pressure_reference_temp_c = ref_temp
		state.pressure_bar_gauge = maxf((cold_bar + atm) * (carcass_target + 273.15) / maxf(ref_temp + 273.15, 1.0) - atm, 0.0)
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


func set_tire_compound(compound_id: String) -> void:
	simulation.set_compound(compound_id)


func get_tire_compound() -> String:
	return simulation.active_compound_id


var wheel_rest_scales: Array[Vector3] = []


func _update_unseated_wheel_visuals() -> void:
	for i in wheel_rest_scales.size():
		var pivot := simulation.wheel_visual_pivots[i]
		var rest_scale := wheel_rest_scales[i]
		if tire_is_unseated(simulation.thermal_model.tire_states[i]):
			# Compress on the vertical axis after wheel spin, keeping the bottom near the road.
			pivot.scale = rest_scale * Vector3(1.08, 0.78, 1.0)
			pivot.position.y -= simulation.wheel_radii[i] * 0.22
		else:
			pivot.scale = rest_scale


func bind_wheel_visuals() -> void:
	wheel_rest_scales.clear()
	var pivots: Array[Node3D] = []
	var visuals: Array[Node3D] = []
	for node_name in ["WheelFrontLeft", "WheelFrontRight", "WheelRearLeft", "WheelRearRight"]:
		var pivot := get_node_or_null(NodePath(node_name)) as Node3D
		if pivot == null:
			push_error("Missing wheel visual pivot: " + node_name)
			return
		pivots.append(pivot)
		wheel_rest_scales.append(pivot.scale)
		visuals.append(pivot.get_node("WheelVisual") as Node3D)
		_make_wheel_matte(visuals.back())
		pivot.position = simulation.wheel_positions_local[pivots.size() - 1]
	simulation.bind_wheel_visuals(pivots, visuals)


func _make_wheel_matte(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var wheel_mesh := node as MeshInstance3D
		for surface in wheel_mesh.mesh.get_surface_count():
			var source := wheel_mesh.get_active_material(surface) as BaseMaterial3D
			if source == null and wheel_mesh.get_active_material(surface) != null:
				continue
			var matte := source.duplicate() as BaseMaterial3D if source != null else StandardMaterial3D.new()
			matte.roughness = 1.0
			matte.metallic = 0.0
			matte.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			matte.clearcoat_enabled = false
			if wheel_mesh.material_override != null:
				wheel_mesh.material_override = matte
				break
			wheel_mesh.set_surface_override_material(surface, matte)
	for child in node.get_children():
		_make_wheel_matte(child)


func build_collision_shapes(collision_document: Dictionary) -> void:
	# Keep the simplified chassis collision above the nominal wheel contact
	# plane; tire deflection otherwise makes the exported lower hull drag.
	var minimum_collision_y := simulation.wheel_positions_local[0].y - simulation.wheel_radii[0] + 0.14
	for hull_document in collision_document.get("hulls", []):
		var points := PackedVector3Array()
		for point_document in hull_document.get("points", []):
			points.append(Vector3(float(point_document.get("x", 0.0)), maxf(float(point_document.get("y", 0.0)), minimum_collision_y), float(point_document.get("z", 0.0))))
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
		box_collision.position = Vector3(float(center.get("x", 0.0)), maxf(float(center.get("y", 0.0)), minimum_collision_y + float(half_extents.get("y", 0.5))), float(center.get("z", 0.0)))
		add_child(box_collision)


func _physics_process(delta: float) -> void:
	if _reset_pending:
		freeze = false
		_reset_pending = false
	if not _physics_ready:
		return
	simulation.unsprung_rig.sync_freeze()
	simulation.update_wheel_visuals(steering_amount)
	_update_unseated_wheel_visuals()
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
var body_contact_vfx: Array[Dictionary] = []
var _prev_body_contact_count: int = 0
var _is_airborne: bool = false
var _airborne_fall_speed: float = 0.0
var _active_collision_zone: String = ""
var _separation_frames: int = 10
var _wheel_impact_peak: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _wheel_quiet_frames: Array[int] = [0, 0, 0, 0]

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	body_contact_vfx.clear()
	if not _physics_ready or freeze:
		return
	if _rescue_pose is Transform3D:
		state.transform = _rescue_pose
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_rescue_pose = null
		simulation.unsprung_rig.reset_at(state.transform)
		return
	var contact_count := state.get_contact_count()
	var landing_speed_ms := 0.0
	_prev_body_contact_count = contact_count
	var impulse_peak := 0.0
	var scrape_power := 0.0
	var ground_drag_power := 0.0
	# Strongest closing contact this frame: speed selects the impact tier
	# (<40 small, 40-70 medium, >70 large km/h) and the local position stages
	# the one-shot in 3D where the hit landed.
	var impact_speed_ms := 0.0
	var impact_position := Vector3.ZERO
	var lateral_impulse_peak := 0.0
	var lateral_speed_ms := 0.0
	var lateral_position := Vector3.ZERO

	var damage_doc: Dictionary = simulation.domains.get("damage", {})
	var wheel_cfg: Dictionary = damage_doc.get("wheel_collision", {})
	var visual_cfg: Dictionary = damage_doc.get("visual", {})
	var wheel_contacts: Array[bool] = [false, false, false, false]
	var wheel_speeds: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var bumper_speeds: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var wheel_lateral: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var collision_cfg: Dictionary = damage_doc.get("collision", {})
	var min_col_speed := float(collision_cfg.get("minimum_speed_m_s", 4.0))
	var full_col_speed := float(collision_cfg.get("full_severity_speed_m_s", 23.0))
	var max_col_rad := float(collision_cfg.get("maximum_radiator_damage", 0.55))
	var max_col_eng := float(collision_cfg.get("maximum_engine_damage", 0.26))
	var col_exponent := float(collision_cfg.get("severity_exponent", 1.2))
	var min_impulse_speed := float(collision_cfg.get("min_impulse_speed_m_s", 1.5))
	var min_impulse := mass * min_impulse_speed

	var peak_qualifying_closing_speed := 0.0
	var peak_qualifying_local_pos := Vector3.ZERO
	var peak_qualifying_normal := Vector3.ZERO
	var body_contact_locals: Array[Vector3] = []

	for index in contact_count:
		var impulse := state.get_contact_impulse(index).length()
		impulse_peak = maxf(impulse_peak, impulse)
		var normal := (state.transform.basis * state.get_contact_local_normal(index)).normalized()
		var velocity := state.get_contact_local_velocity_at_position(index) - state.get_contact_collider_velocity_at_position(index)
		var closing_speed := maxf(0.0, -velocity.dot(normal))
		var contact_local_pos := state.transform.affine_inverse() * state.get_contact_collider_position(index)
		body_contact_locals.append(contact_local_pos)

		var collider := state.get_contact_collider_object(index)
		var role := str(collider.get_meta("collision_role", "")) if (collider != null and collider.has_meta("collision_role")) else ""
		var is_obstacle: bool = (role in ["barrier", "obstacle"]) or (absf(normal.y) < 0.5)

		if is_obstacle and not wheel_cfg.is_empty():
			var wheel := _impact_wheel(contact_local_pos, wheel_cfg)
			var local_normal := state.transform.basis.transposed() * normal
			if wheel < 0 and local_normal.z > 0.65 and contact_local_pos.z < simulation.wheel_positions_local[0].z:
				# The bumper sits ahead of the wheel contact zones. Transfer
				# the frontal load to the nearer front corner, or both at center.
				for front in 2:
					var x := contact_local_pos.x
					if absf(x) > 0.15 and signf(x) != signf(simulation.wheel_positions_local[front].x):
						continue
					wheel_contacts[front] = true
					if impulse >= float(wheel_cfg.minimum_impulse_ns) and closing_speed > bumper_speeds[front]:
						bumper_speeds[front] = closing_speed
			if wheel >= 0:
				wheel_contacts[wheel] = true
				if impulse >= float(wheel_cfg.minimum_impulse_ns) and closing_speed > wheel_speeds[wheel]:
					wheel_speeds[wheel] = closing_speed
					wheel_lateral[wheel] = absf(normal.dot(state.transform.basis.x))

		# Only side-facing contacts contribute to generic collision sounds.
		# The horizontal normal component discounts vertical impulse on slopes.
		if absf(normal.y) < 0.5:
			var horizontal_fraction := Vector2(normal.x, normal.z).length()
			var lateral_impulse := impulse * horizontal_fraction
			if lateral_impulse > lateral_impulse_peak:
				lateral_impulse_peak = lateral_impulse
				lateral_speed_ms = closing_speed * horizontal_fraction
				lateral_position = state.get_contact_local_position(index)
		if closing_speed > impact_speed_ms:
			impact_speed_ms = closing_speed
			impact_position = state.get_contact_local_position(index)

		if _visual_damage != null and impulse >= min_impulse and closing_speed >= min_col_speed:
			var local_normal := state.transform.basis.transposed() * normal
			if is_obstacle or (contact_local_pos.y > 0.92 and local_normal.y < -0.35):
				var visual_severity := pow(clampf((closing_speed - min_col_speed) / maxf(full_col_speed - min_col_speed, 0.001), 0.0, 1.0), col_exponent)
				_visual_damage.register_impact(contact_local_pos, local_normal, visual_severity, visual_cfg)

		# Collision damage qualification
		if not collision_cfg.is_empty() and is_obstacle and impulse >= min_impulse and closing_speed >= min_col_speed:
			if closing_speed > peak_qualifying_closing_speed:
				peak_qualifying_closing_speed = closing_speed
				peak_qualifying_local_pos = contact_local_pos
				peak_qualifying_normal = state.transform.basis.transposed() * normal

		var tangent_speed := (velocity - normal * velocity.dot(normal)).length()
		var vfx_collider := state.get_contact_collider_object(index) as Node
		var vfx_surface := ""
		if vfx_collider != null:
			for group in ["Gravel", "Grass", "Dirt", "Sand", "Road", "Asphalt"]:
				if vfx_collider.is_in_group(group):
					vfx_surface = group
					break
		body_contact_vfx.append({
			"position": state.get_contact_collider_position(index), "normal": normal,
			"impulse_ns": impulse, "speed_ms": closing_speed, "tangent_ms": tangent_speed,
			"surface": vfx_surface,
			"collider_name": str(vfx_collider.name).to_lower() if vfx_collider != null else "",
		})
		var force := impulse / maxf(state.step, 0.0001)
		if force > mass * 9.81 * 0.10 and tangent_speed > 0.5:
			var is_ground: bool = collider is Node and (role == "terrain" or (collider as Node).is_in_group("Gravel"))
			if is_ground:
				ground_drag_power += force * tangent_speed
			else:
				scrape_power += force * tangent_speed

	# Resolve single debounced collision event this frame
	if peak_qualifying_closing_speed > 0.0:
		if _separation_frames >= 4 or _active_collision_zone.is_empty():
			var hit_zone := _resolve_impact_zone(peak_qualifying_local_pos, peak_qualifying_normal)
			var severity := pow(clampf((peak_qualifying_closing_speed - min_col_speed) / maxf(full_col_speed - min_col_speed, 0.001), 0.0, 1.0), col_exponent)
			var zone_weights: Dictionary = collision_cfg.get("zone_weights", {}).get(hit_zone, {})
			var rad_dmg := severity * max_col_rad * float(zone_weights.get("radiator", 0.5))
			var eng_dmg := severity * max_col_eng * float(zone_weights.get("engine", 0.5))
			simulation.thermal_model.apply_damage(rad_dmg, eng_dmg)
			var transmission_delta := severity * float(collision_cfg.get("maximum_transmission_damage", 0.0))
			var powertrain := simulation.powertrain_model
			powertrain.transmission_damage = clampf(powertrain.transmission_damage + transmission_delta, 0.0, 1.0)
			_active_collision_zone = hit_zone
		_separation_frames = 0
	else:
		_separation_frames += 1
		if _separation_frames >= 6:
			_active_collision_zone = ""

	simulation.step(self, state, {
		"throttle": throttle_amount,
		"brake": brake_amount,
		"steering": steering_amount,
		"handbrake": handbrake_amount,
		"clutch": clutch_amount,
		"auto_clutch": bool(simulation.domains.get("driving_assistance", {}).get("aids", {}).get("auto_clutch_default_enabled", false)),
		"automatic_transmission": automatic_transmission,
	})

	if not wheel_cfg.is_empty():
		_collect_wheel_cast_impacts(state, wheel_contacts, wheel_speeds, wheel_cfg, wheel_lateral)
		_apply_wheel_impacts(wheel_contacts, wheel_speeds, wheel_cfg, wheel_lateral, bumper_speeds)

	# Airborne and landing detection combining wheels and chassis body contacts
	var wheels_in_contact: bool = false
	for i in 4:
		if simulation.suspension_model.contact_active[i]:
			wheels_in_contact = true
			break
	var is_touching_ground := wheels_in_contact or (contact_count > 0)
	if not is_touching_ground:
		_is_airborne = true
		_airborne_fall_speed = maxf(_airborne_fall_speed, maxf(0.0, -state.linear_velocity.y))
	elif _is_airborne:
		var landing_fall_speed := _airborne_fall_speed
		_is_airborne = false
		_airborne_fall_speed = 0.0
		if landing_fall_speed >= 2.5:
			landing_speed_ms = landing_fall_speed
			var landing_cfg: Dictionary = damage_doc.get("landing", {})
			if not landing_cfg.is_empty():
				var min_land_speed := float(landing_cfg.get("minimum_speed_m_s", 2.5))
				var full_land_speed := float(landing_cfg.get("full_severity_speed_m_s", 9.0))
				if landing_fall_speed >= min_land_speed and full_land_speed > min_land_speed:
					var land_zone := _resolve_landing_zone(body_contact_locals, state)
					var land_exponent := float(landing_cfg.get("severity_exponent", 1.0))
					var severity := pow(clampf((landing_fall_speed - min_land_speed) / (full_land_speed - min_land_speed), 0.0, 1.0), land_exponent)
					var max_rad := float(landing_cfg.get("maximum_radiator_damage", 0.10))
					var max_eng := float(landing_cfg.get("maximum_engine_damage", 0.08))
					var zone_weights: Dictionary = landing_cfg.get("zone_weights", {}).get(land_zone, {})
					var rad_dmg := severity * max_rad * float(zone_weights.get("radiator", 0.2))
					var eng_dmg := severity * max_eng * float(zone_weights.get("engine", 0.2))
					simulation.thermal_model.apply_damage(rad_dmg, eng_dmg)

	body_contact_audio = {"count": contact_count, "impulse_ns": impulse_peak, "lateral_impulse_ns": lateral_impulse_peak, "lateral_speed_kph": lateral_speed_ms * 3.6, "lateral_position": lateral_position, "impact_speed_kph": impact_speed_ms * 3.6, "impact_position": impact_position, "landing_speed_ms": landing_speed_ms, "scrape_power_w": scrape_power, "ground_drag_power_w": ground_drag_power, "height_m": state.transform.origin.y}


func set_glass_cockpit_view(enabled: bool) -> void:
	if _visual_damage != null:
		_visual_damage.set_cockpit_view(enabled)


func set_stage_headlights(hour: float) -> void:
	if _visual_damage != null:
		_visual_damage.set_headlights_requested(hour >= 18.0 or hour < 6.0)


func toggle_headlights() -> void:
	if _visual_damage != null:
		_visual_damage.set_headlights_requested(not _visual_damage.headlights_requested)


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


func _resolve_impact_zone(local_pos: Vector3, normal: Vector3) -> String:
	if local_pos.z <= -1.25 and local_pos.y >= 0.22:
		return "nose"
	if local_pos.z < -0.35 and local_pos.y < 0.28:
		return "front_underbody"
	if local_pos.z > 1.35:
		return "rear"
	if absf(local_pos.x) > 0.55 or absf(normal.x) > 0.7:
		return "side"
	if local_pos.z <= -0.35:
		return "nose" if local_pos.y >= 0.25 else "front_underbody"
	return "side"


func _resolve_landing_zone(body_contacts: Array[Vector3], state: PhysicsDirectBodyState3D) -> String:
	for pos in body_contacts:
		if pos.z <= -1.25 and pos.y >= 0.22:
			return "nose"
		if pos.z < -0.35 and pos.y < 0.28:
			return "front_underbody"
		if pos.z > 1.35:
			return "rear"
	var front_has_contact := simulation.suspension_model.contact_active[0] or simulation.suspension_model.contact_active[1]
	var rear_has_contact := simulation.suspension_model.contact_active[2] or simulation.suspension_model.contact_active[3]
	if front_has_contact and not rear_has_contact:
		return "front_wheels"
	if rear_has_contact and not front_has_contact:
		return "rear_wheels"
	var front_load := simulation.wheel_loads[0] + simulation.wheel_loads[1]
	var rear_load := simulation.wheel_loads[2] + simulation.wheel_loads[3]
	var nose_down: bool = (-state.transform.basis.z.y < -0.05)
	if front_load > rear_load or nose_down:
		return "front_wheels"
	return "rear_wheels"


func rescue_to_pose(pose: Transform3D) -> void:
	_reset_to_transform(pose)
	_rescue_pose = pose


func reset_to_pose(target_position: Vector3, target_yaw: float) -> void:
	_reset_to_transform(Transform3D(Basis(Vector3.UP, target_yaw), target_position))


func _reset_to_transform(pose: Transform3D) -> void:
	_rescue_pose = null
	freeze = true
	simulation.unsprung_rig.sync_freeze()
	global_transform = pose
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
	handbrake_amount = 0.0
	steering_amount = 0.0
	true_steering_amount = 0.0
	clutch_amount = 1.0
	sleeping = false
	_reset_pending = true
	body_contact_audio.clear()
	body_contact_vfx.clear()
	_prev_body_contact_count = 0
	_is_airborne = false
	_airborne_fall_speed = 0.0
	_active_collision_zone = ""
	_separation_frames = 10
	_wheel_impact_peak.fill(0.0)
	_wheel_quiet_frames.fill(0)

func prepare_for_stage() -> void:
	simulation.thermal_model.start_temperature_policy = start_temperature_policy
	simulation.thermal_model.reset_for_stage(simulation.domains)
	_sync_mass_from_fuel()
	if not tire_inventory.mounted.is_empty():
		sync_tire_inventory()
	_is_airborne = false
	_airborne_fall_speed = 0.0
	_active_collision_zone = ""
	_separation_frames = 10
	_wheel_impact_peak.fill(0.0)
	_wheel_quiet_frames.fill(0)

func _collect_wheel_cast_impacts(state: PhysicsDirectBodyState3D, contacts: Array[bool], speeds: Array[float], cfg: Dictionary, lateral: Array[float]) -> void:
	# The hubs use suspension casts for contact instead of solid collision shapes.
	var inverse := state.transform.affine_inverse()
	var com_world := state.transform * center_of_mass
	for i in simulation.wheel_contact_casts.size():
		var cast: ShapeCast3D = simulation.wheel_contact_casts[i]
		for hit in cast.get_collision_count():
			var collider := cast.get_collider(hit) as StaticBody3D
			if collider == null:
				continue
			var role := str(collider.get_meta("collision_role", ""))
			var normal := cast.get_collision_normal(hit)
			if role not in ["barrier", "obstacle"] and absf(normal.y) >= 0.5:
				continue
			var point := cast.get_collision_point(hit)
			if _impact_wheel(inverse * point, cfg) != i:
				continue
			contacts[i] = true
			var velocity := state.linear_velocity + state.angular_velocity.cross(point - com_world)
			var closing_speed := maxf(0.0, -(velocity - collider.constant_linear_velocity).dot(normal))
			# Casts have no solved impulse. Use the effective corner mass as a proxy.
			if closing_speed * mass * 0.25 >= float(cfg.minimum_impulse_ns) and closing_speed > speeds[i]:
				speeds[i] = closing_speed
				lateral[i] = absf(normal.dot(state.transform.basis.x))


func _impact_wheel(position_local: Vector3, cfg: Dictionary) -> int:
	var closest := -1
	var closest_distance := INF
	for i in 4:
		var center: Vector3 = simulation.wheel_positions_local[i] + Vector3.UP * simulation.suspension_model.compression[i]
		var offset := position_local - center
		if absf(offset.x) > float(cfg.lateral_reach_m):
			continue
		if Vector2(offset.y, offset.z).length() > simulation.wheel_radii[i] + float(cfg.radial_reach_margin_m):
			continue
		if offset.length_squared() < closest_distance:
			closest = i
			closest_distance = offset.length_squared()
	return closest


func _apply_wheel_impacts(contacts: Array[bool], speeds: Array[float], cfg: Dictionary, lateral: Array[float] = [], bumper: Array[float] = []) -> void:
	for i in 4:
		if not contacts[i]:
			_wheel_quiet_frames[i] += 1
			if _wheel_quiet_frames[i] >= 6:
				_wheel_impact_peak[i] = 0.0
			continue
		_wheel_quiet_frames[i] = 0
		var direct_speed := speeds[i]
		var speed := maxf(direct_speed, bumper[i] if i < bumper.size() else 0.0)
		var previous := _wheel_impact_peak[i]
		if speed <= previous:
			continue
		_wheel_impact_peak[i] = speed
		var tire: Dictionary = simulation.thermal_model.tire_states[i]
		var lateral_fraction := lateral[i] if i < lateral.size() else 1.0
		if speed > direct_speed:
			lateral_fraction = 0.0
		var alignment_increase := _impact_severity_increase(speed, previous, float(cfg.alignment_start_speed_m_s), float(cfg.alignment_full_speed_m_s))
		simulation.alignment_collision_damage[i] = clampf(simulation.alignment_collision_damage[i] + alignment_increase * lerpf(0.5, 1.0, lateral_fraction), 0.0, 1.0)
		var component_weight := lerpf(0.25, 1.0, lateral_fraction)
		var rim_increase := _impact_severity_increase(speed, previous, float(cfg.rim_start_speed_m_s), float(cfg.rim_full_speed_m_s))
		tire.rim_deformation = clampf(float(tire.get("rim_deformation", 0.0)) + rim_increase * component_weight, 0.0, 1.0)
		var puncture_speed := speed / lerpf(1.0, 1.2, lateral_fraction)
		if speed <= direct_speed and puncture_speed >= float(cfg.puncture_speed_m_s):
			var leak := float(cfg.fast_leak_per_second) if puncture_speed >= float(cfg.cut_speed_m_s) else float(cfg.slow_leak_per_second)
			tire.leak_per_second = maxf(float(tire.get("leak_per_second", 0.0)), leak)
		var start := float(cfg.brake_damage_speed_m_s)
		var increase := _impact_severity_increase(speed, previous, start, float(cfg.full_brake_damage_speed_m_s))
		simulation.brake_collision_loss[i] = minf(
			simulation.brake_collision_loss[i] + increase * component_weight * float(cfg.maximum_brake_loss_per_impact),
			1.0 - float(cfg.minimum_brake_factor)
		)


func _impact_severity_increase(speed: float, previous: float, start: float, full: float) -> float:
	var span := full - start
	return clampf((speed - start) / span, 0.0, 1.0) - clampf((previous - start) / span, 0.0, 1.0)


static func tire_is_unseated(state: Dictionary) -> bool:
	return float(state.get("carcass_failure", 0.0)) >= 1.0


func tire_state(index: int) -> Dictionary:
	var state := {}
	for key in TIRE_STATE_KEYS:
		state[key] = simulation.thermal_model.tire_states[index].get(key, 0.0)
	return state.duplicate(true)

func is_controls_enabled() -> bool:
	var controller := get_parent().get_node_or_null("RallyInputController")
	return bool(controller.controls_enabled) if controller != null else true

func set_controls_enabled(enabled: bool) -> void:
	var controller := get_parent().get_node_or_null("RallyInputController")
	if controller != null:
		controller.set_controls_enabled(enabled)

func get_setup_snapshot() -> Dictionary:
	ensure_tire_inventory()
	var values := simulation.filter_garage_values(RallySetupCatalog.defaults(simulation.domains))
	values["fuel.initial_kg"] = simulation.thermal_model.fuel_remaining_litres * simulation.mass_model.fuel_density_kg_per_litre
	values["strategy.spare_wheels"] = tire_inventory.spares.size()
	for i in 4:
		values["strategy.wheel_compound." + ["FL", "FR", "RL", "RR"][i]] = tire_inventory.mounted[i].compound_id
	return values

func apply_setup_snapshot(values: Dictionary) -> Dictionary:
	ensure_tire_inventory()
	var physical := {}
	var compounds := {}
	var changed := false
	for key in values:
		if not str(key).begins_with("strategy."):
			physical[key] = values[key]
	for i in 4:
		var wheel: String = ["FL", "FR", "RL", "RR"][i]
		var compound := str(values.get("strategy.wheel_compound." + wheel, tire_inventory.mounted[i].compound_id))
		if not RallyTireCompound.is_valid(compound):
			return {"ok": false, "error": "Compuesto no disponible: " + compound}
		compounds[wheel] = compound
		changed = changed or compound != str(tire_inventory.mounted[i].compound_id)
	var count := int(values.get("strategy.spare_wheels", tire_inventory.spares.size()))
	changed = changed or count != tire_inventory.spares.size()
	if changed and get_parent().has_method("may_service_tires") and not bool(get_parent().call("may_service_tires")):
		return {"ok": false, "error": "En tramo solo se intercambian las ruedas del inventario de pausa."}
	var result := apply_setup_values(physical)
	if bool(result.get("ok", false)):
		service_tire_inventory(compounds, count)
	return result

func fresh_tire_state(compound: String, index: int = 0) -> Dictionary:
	var state := tire_state(index)
	var catalog := RallyTireCompound.load_catalog()
	var data: Dictionary = catalog.compounds[compound]
	var temps := RallyTireCompound.start_temperatures(
		data,
		simulation.thermal_model.ambient_temperature_c,
		start_temperature_policy
	)
	var tread := float(temps.tread_c)
	var carcass := float(temps.carcass_c)
	state.merge({"carcass_failure": 0.0, "rim_deformation": 0.0, "pressure_loss_fraction": 0.0, "leak_per_second": 0.0, "wear_fraction": 0.0, "thermal_damage_fraction": 0.0, "tread_c": tread, "surface_c": tread, "tread_zones_c": [tread, tread, tread], "carcass_c": carcass, "gas_c": carcass}, true)
	var atmosphere := 1.01325
	state.pressure_bar_gauge = (float(state.pressure_reference_bar_gauge) + atmosphere) * (carcass + 273.15) / (float(state.pressure_reference_temp_c) + 273.15) - atmosphere
	return state

func ensure_tire_inventory() -> void:
	if not tire_inventory.mounted.is_empty():
		return
	var catalog := RallyTireCompound.load_catalog()
	var policy: Dictionary = catalog.get("inventory", {})
	tire_inventory.capacity = int(policy.get("capacity", 2))
	for i in 4:
		var cid: String = simulation.active_compound_id
		tire_inventory.mounted.append(
			tire_inventory.item(cid, fresh_tire_state(cid, i))
		)
	for i in int(policy.get("default_spare_count", 2)):
		tire_inventory.spares.append(tire_inventory.item(simulation.active_compound_id, fresh_tire_state(simulation.active_compound_id)))
	apply_tire_inventory()

func sync_tire_inventory() -> void:
	for i in tire_inventory.mounted.size():
		tire_inventory.mounted[i].state = tire_state(i)

func apply_tire_inventory() -> void:
	for i in tire_inventory.mounted.size():
		var tire: Dictionary = tire_inventory.mounted[i]
		simulation.thermal_model.set_wheel_compound(i, tire.compound_id)
		simulation.tire_model.set_wheel_compound(i, tire.compound_id)
		for key in TIRE_STATE_KEYS:
			if tire.state.has(key):
				simulation.thermal_model.tire_states[i][key] = tire.state[key]
		for key in ["pressure_loss_fraction", "leak_per_second", "rim_deformation", "carcass_failure"]:
			simulation.thermal_model.tire_states[i][key] = tire.state.get(key, 0.0)
	var policy: Dictionary = RallyTireCompound.load_catalog().get("inventory", {})
	policy = policy.duplicate(true)
	policy.merge(simulation.domains.get("chassis", {}).get("physical_mass_inventory", {}).get("spare_policy", {}), true)
	simulation.mass_model.set_carried_spares(tire_inventory.spares.size(), policy)
	_applied_fuel_mass_kg = -1.0
	_sync_mass_from_fuel()

func exchange_tire(wheel: int, spare_id: int, keep_removed: bool) -> bool:
	ensure_tire_inventory()
	sync_tire_inventory()
	if not tire_inventory.swap(wheel, spare_id, keep_removed):
		return false
	apply_tire_inventory()
	simulation.tire_model.reset_patch(wheel)
	return true

func discard_spare(spare_id: int) -> bool:
	ensure_tire_inventory()
	sync_tire_inventory()
	if not tire_inventory.discard(spare_id):
		return false
	apply_tire_inventory()
	return true

func service_tire_inventory(wheel_compounds: Dictionary, spare_count: int, replace_all: bool = false) -> void:
	ensure_tire_inventory()
	sync_tire_inventory()
	for i in 4:
		var compound := str(wheel_compounds.get(["FL", "FR", "RL", "RR"][i], tire_inventory.mounted[i].compound_id))
		if replace_all or compound != str(tire_inventory.mounted[i].compound_id):
			tire_inventory.mounted[i] = tire_inventory.item(compound, fresh_tire_state(compound, i))
	var count := clampi(spare_count, 0, tire_inventory.capacity)
	while tire_inventory.spares.size() > count:
		tire_inventory.spares.pop_back()
	while tire_inventory.spares.size() < count:
		tire_inventory.spares.append(tire_inventory.item(simulation.active_compound_id, fresh_tire_state(simulation.active_compound_id)))
	apply_tire_inventory()


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


func _apply_dreamcast_vehicle_visuals() -> void:
	# Unica parte activa del pipeline visual: sombra blob bajo el chasis.
	# El coche va en la capa 2 para que el Decal (capa 1) no se proyecte sobre el propio coche.
	_set_vehicle_layers(self)
	if dc_enable_blob_shadow:
		_create_blob_shadow()
	print("RALLY_VEHICLE_BLOB_SHADOW_READY")


func _set_vehicle_layers(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = 2
	for child in node.get_children():
		_set_vehicle_layers(child)


func _create_blob_shadow() -> void:
	# Sombra suave bajo el chasis. Solo proyecta sobre la capa 1 (terreno); el coche esta en la capa 2.
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		var ny := (float(y) / 63.0) * 2.0 - 1.0
		for x in 64:
			var nx := (float(x) / 63.0) * 2.0 - 1.0
			# Silueta de chasis con esquinas redondeadas
			var dist := pow(absf(nx), 2.4) + pow(absf(ny), 3.2)
			var alpha := clampf(1.0 - dist, 0.0, 1.0)
			alpha = smoothstep(0.0, 1.0, alpha) * dc_blob_shadow_opacity
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))

	var shadow_tex := ImageTexture.create_from_image(img)
	_blob_shadow_decal = Decal.new()
	_blob_shadow_decal.name = "DreamcastBlobShadow"
	_blob_shadow_decal.size = Vector3(dc_blob_shadow_size.x, 1.8, dc_blob_shadow_size.y)
	_blob_shadow_decal.position = Vector3(0.0, -0.35, 0.0)
	_blob_shadow_decal.texture_albedo = shadow_tex
	_blob_shadow_decal.upper_fade = 0.05
	_blob_shadow_decal.lower_fade = 0.35
	_blob_shadow_decal.cull_mask = 1
	add_child(_blob_shadow_decal)


func damage_snapshot() -> Dictionary:
	return {
		"brake_wear_fraction": simulation.thermal_model.brake_wear_fraction.duplicate(),
		"radiator": simulation.thermal_model.radiator_damage,
		"engine": simulation.thermal_model.engine_damage,
		"transmission": simulation.powertrain_model.transmission_damage,
		"brake_collision_loss": simulation.brake_collision_loss.duplicate(),
		"alignment_collision_damage": simulation.alignment_collision_damage.duplicate(),
		"visual": _visual_damage.damage_snapshot() if _visual_damage != null else {},
	}


func restore_damage(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var thermal = simulation.thermal_model
	var saved_wear: Array = snapshot.get("brake_wear_fraction", [])
	for i in mini(4, saved_wear.size()):
		thermal.brake_wear_fraction[i] = clampf(float(saved_wear[i]), 0.0, 1.0)
	thermal.radiator_damage = clampf(float(snapshot.get("radiator", thermal.radiator_damage)), 0.0, 1.0)
	thermal.engine_damage = clampf(float(snapshot.get("engine", thermal.engine_damage)), 0.0, 1.0)
	thermal.apply_damage(0.0, 0.0)
	simulation.powertrain_model.transmission_damage = clampf(float(snapshot.get("transmission", simulation.powertrain_model.transmission_damage)), 0.0, 1.0)
	for key in ["brake_collision_loss", "alignment_collision_damage"]:
		var saved: Array = snapshot.get(key, [])
		var target: Array = simulation.get(key)
		for i in mini(4, saved.size()):
			target[i] = clampf(float(saved[i]), 0.0, 1.0)
	if _visual_damage != null:
		_visual_damage.restore_damage(snapshot.get("visual", {}))


func repair_service_components(parts: Array[String]) -> void:
	var visual: Array[String] = []
	for part in parts:
		match part:
			"engine": simulation.thermal_model.engine_damage = 0.0
			"radiator": simulation.thermal_model.radiator_damage = 0.0
			"transmission": simulation.powertrain_model.transmission_damage = 0.0
			_:
				if part.begins_with("brake_"):
					var i := int(part.trim_prefix("brake_"))
					simulation.brake_collision_loss[i] = 0.0
					simulation.thermal_model.brake_wear_fraction[i] = 0.0
				elif part.begins_with("alignment_"):
					simulation.alignment_collision_damage[int(part.trim_prefix("alignment_"))] = 0.0
				else:
					visual.append(part)
	simulation.thermal_model.apply_damage(0.0, 0.0)
	if _visual_damage != null:
		_visual_damage.repair_parts(visual)
