class_name UnsprungSuspensionRig
extends RefCounted
## Migración suspensión 1DOF por rueda (§PLAN_MIGRACION_SUSPENSION_1DOF).
## Cada buje es una masa puntual sobre un eje fijo en el espacio local del
## chasis. Jolt integra carrocería y colisiones; el rig guarda 4 recorridos q
## (m, +compresión) y 4 velocidades u (m/s). Sin RigidBody ni joints de buje.

const JOINT_LIMIT_MARGIN_M := 0.10
static func effective_droop_limit_m(droop_m: float) -> float:
	return maxf(float(droop_m), 0.0) + JOINT_LIMIT_MARGIN_M


static func contact_query_travel_m(bump_m: float, droop_m: float, top_margin_m: float = 0.02) -> Dictionary:
	var bump := maxf(float(bump_m), 0.0) + maxf(float(top_margin_m), 0.0)
	var droop_eff := effective_droop_limit_m(droop_m)
	return {"bump": bump, "droop_effective": droop_eff, "travel": bump + droop_eff}


static func has_ground_support_at(
	space_state: PhysicsDirectSpaceState3D,
	from: Vector3,
	down: Vector3,
	probe_m: float,
	collision_mask: int,
	exclude: Array[RID],
) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		from,
		from + down.normalized() * maxf(probe_m, 0.01),
		collision_mask,
		exclude,
	)
	return not space_state.intersect_ray(query).is_empty()


const RADIAL_BISECTION_REL_TOL := 1.0e-4

# Compat: retirados los nodos, se conservan vacíos para no romper lecturas externas.
var chassis: RigidBody3D
var neutral_positions: Array[Vector3] = []
var wheel_radii_m: Array[float] = [0.30, 0.30, 0.30, 0.30]
var last_reset_q_eq: Array[float] = [0.0, 0.0, 0.0, 0.0]
var radial_deflection_m: Array[float] = [0.0, 0.0, 0.0, 0.0]
var radial_dissipation_w: Array[float] = [0.0, 0.0, 0.0, 0.0]
var radial_states: Array[Dictionary] = [{}, {}, {}, {}]
var spring_forces_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var radial_viscous_scale := 1.0
var substep_loads_n: Array = [[], [], [], []]
var substep_defl_m: Array = [[], [], [], []]
var tick_sequence: int = 0
var last_tick_trace: Array[Dictionary] = [{}, {}, {}, {}]
var last_damper_requested_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var last_damper_applied_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var last_damper_impulse_ns: Array[float] = [0.0, 0.0, 0.0, 0.0]

# Estado canónico 1DOF.
var q: Array[float] = [0.0, 0.0, 0.0, 0.0]
var u: Array[float] = [0.0, 0.0, 0.0, 0.0]
var m_unsprung: Array[float] = [15.0, 15.0, 15.0, 15.0]
var apoyo_previo: Array[bool] = [false, false, false, false]
# Predictor del tick.
var has_pred := false
var C_pred := Vector3.ZERO
var R_pred := Basis.IDENTITY
var V_pred := Vector3.ZERO
var omega_pred := Vector3.ZERO
var w: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var w_free: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var w_normal: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var w_cand: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var M_factor: Array = _solver_rows(10)
var _hub_jacobian: Array = _solver_rows(3)
var _axis_response: Array = _solver_rows(4)
var _normal_response: Array = _solver_rows(4)
var _normal_rows: Array = _solver_rows(4)
var _rhs: Array[float] = _solver_rows(1)[0]
var _response: Array[float] = _solver_rows(1)[0]
var _w_rad: Array[float] = _solver_rows(1)[0]
var _relative_mass: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _normal_deflection: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _normal_road_speed: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _inertia_before: Basis = Basis.IDENTITY
var _jolt_inertia_before: Basis = Basis.IDENTITY
var _schur_Svv_inv: Basis = Basis.IDENTITY
var _schur_Svw: Basis = Basis.IDENTITY
var _schur_K: Basis = Basis.IDENTITY
var _schur_Srot_inv: Basis = Basis.IDENTITY
var _tick_rx: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _inv_m_unsprung: PackedFloat64Array = PackedFloat64Array([1.0 / 15.0, 1.0 / 15.0, 1.0 / 15.0, 1.0 / 15.0])
var reuse_mass_factor_per_tick: bool = true
var _mass_factored_this_tick: bool = false
var _normals_prepared_this_tick: bool = false
var _prev_Jrad: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _prev_hh: float = 0.0083333333
var _last_v_fin: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _last_d_fin: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var capture_substeps := false
# Backend nativo en Rust (rally_native::RustSuspensionRig) con fallback automático a GDScript.
var use_rust_backend: bool = true
var _rust_rig: RefCounted = null
var _rust_param_version: int = -1
var _rust_params66: PackedFloat64Array = PackedFloat64Array()
var _rust_flags9: PackedByteArray = PackedByteArray()
var _rust_vec14: PackedVector3Array = PackedVector3Array()
var _rust_scalars18: PackedFloat64Array = PackedFloat64Array()
var _rust_radial56: PackedFloat64Array = PackedFloat64Array()
var _rust_q4: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _rust_np4: PackedVector3Array = PackedVector3Array()
var _rust_mu4: PackedFloat64Array = PackedFloat64Array([15.0, 15.0, 15.0, 15.0])
var tick_r: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var tick_e := Vector3.UP
var tick_e_wheel: Array[Vector3] = [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]
var tick_m_s := 1000.0
var tick_com_local := Vector3.ZERO
var tick_inertia_diag := Vector3(500.0, 800.0, 1200.0)
var tick_inertia_local := Basis.IDENTITY
var has_full_inertia_tensor := false
var tick_grav := Vector3(0.0, -9.80665, 0.0)
# 1DOF torsión estructural del chasis (subchasis delantero vs trasero en serie con muelles/ARB).
var chassis_torsion_enabled := true
var chassis_twist_rad := 0.0
var chassis_twist_vel_rad_s := 0.0
var chassis_torsion_stiffness_nm_per_rad := 180000.0
var chassis_torsion_damping_ratio := 0.25
var chassis_torsion_inertia_kg_m2 := 70.0
var _track_front_m := 1.4
var _track_rear_m := 1.4
# Datos anclados por tick.
var t_hit: Array[bool] = [false, false, false, false]
var t_H0: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var t_n: Array[Vector3] = [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]
var t_delta0: Array[float] = [0.0, 0.0, 0.0, 0.0]
var t_road_vel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var t_radial_state: Array[Dictionary] = [{}, {}, {}, {}]
var t_radial_packed: Array[PackedFloat64Array] = [
	PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array()
]
var t_rim_max: Array[float] = [0.05, 0.05, 0.05, 0.05]
var t_elapsed := 0.0
var t_h := 0.008
# Subpaso actual.
var s_Fz: Array[float] = [0.0, 0.0, 0.0, 0.0]
var s_defl: Array[float] = [0.0, 0.0, 0.0, 0.0]
var s_diss: Array[float] = [0.0, 0.0, 0.0, 0.0]
var s_Jrad: Array[float] = [0.0, 0.0, 0.0, 0.0]
var s_Kn: Array[float] = [1.0, 1.0, 1.0, 1.0]
# Acumuladores del tick.
var acc_J := Vector3.ZERO
var acc_L := Vector3.ZERO
var acc_Fz: Array[float] = [0.0, 0.0, 0.0, 0.0]
var acc_defl: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _trace_axis := Vector3.UP
var _trace_chassis_velocity := Vector3.ZERO
var _trace_start_hub_velocity: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _spring_impulse_ns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _suspension_axial_impulse_ns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _contact_axial_impulse_ns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _contact_vertical_impulse_ns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _radial_impulse_ns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var acc_diss: Array[float] = [0.0, 0.0, 0.0, 0.0]


static func radial_deflection_from_travel(
	road_compression_m: float,
	hub_travel_m: float,
	cos_angle: float
) -> float:
	return maxf((float(road_compression_m) - float(hub_travel_m)) * clampf(float(cos_angle), 0.25, 1.0), 0.0)


func substep_defl(wheel: int, k: int) -> float:
	if wheel < 0 or wheel >= substep_defl_m.size():
		return 0.0
	var arr: Array = substep_defl_m[wheel]
	if arr.is_empty():
		return 0.0
	return float(arr[clampi(k, 0, arr.size() - 1)])


func create(
	body: RigidBody3D,
	positions: Array[Vector3],
	masses: Array[float],
	suspension: VehicleSuspensionModel,
	wheel_radii: Array[float] = [],
) -> void:
	chassis = body
	neutral_positions.assign(positions)
	m_unsprung = [15.0, 15.0, 15.0, 15.0]
	for i in 4:
		if i < masses.size():
			m_unsprung[i] = maxf(float(masses[i]), 1.0)
		_inv_m_unsprung[i] = 1.0 / m_unsprung[i]
	if wheel_radii.size() == 4:
		wheel_radii_m.assign(wheel_radii)
	if neutral_positions.size() == 4:
		_track_front_m = maxf(absf(neutral_positions[1].x - neutral_positions[0].x), 0.5)
		_track_rear_m = maxf(absf(neutral_positions[3].x - neutral_positions[2].x), 0.5)
	_ensure_rust_rig()
	_sync_rust_rig_geometry()
	reset_at(body.global_transform, suspension)
	print(
		"RALLY_UNSPRUNG_READY ",
		JSON.stringify(
			{
				"hub_masses_kg": masses,
				"sprung_mass_kg": body.mass,
				"mode": "1dof_rust" if _rust_rig != null else "1dof_scalar",
			}
		),
	)


func _ensure_rust_rig() -> RefCounted:
	if not use_rust_backend:
		_rust_rig = null
		return null
	if _rust_rig == null and ClassDB.class_exists(&"RustSuspensionRig"):
		_rust_rig = ClassDB.instantiate(&"RustSuspensionRig") as RefCounted
		_rust_param_version = -1
		if _rust_params66.size() != 66:
			_rust_params66.resize(66)
		if _rust_flags9.size() != 9:
			_rust_flags9.resize(9)
		if _rust_vec14.size() != 14:
			_rust_vec14.resize(14)
		if _rust_scalars18.size() != 18:
			_rust_scalars18.resize(18)
		if _rust_radial56.size() != 56:
			_rust_radial56.resize(56)
		if _rust_np4.size() != 4:
			_rust_np4.resize(4)
		_sync_rust_rig_geometry()
		_rust_rig.call("set_local_inertia_tensor", has_full_inertia_tensor, tick_inertia_local)
		_rust_rig.call(
			"configure_chassis_torsion",
			chassis_torsion_stiffness_nm_per_rad,
			chassis_torsion_damping_ratio,
			chassis_torsion_inertia_kg_m2,
		)
	return _rust_rig


func _sync_rust_rig_geometry() -> void:
	if _rust_rig == null:
		return
	if _rust_np4.size() != 4:
		_rust_np4.resize(4)
	for i in 4:
		_rust_np4[i] = neutral_positions[i] if i < neutral_positions.size() else Vector3.ZERO
		_rust_mu4[i] = m_unsprung[i]
	_rust_rig.call("configure_rig", _rust_np4, _rust_mu4, _track_front_m, _track_rear_m)


func _sync_rust_suspension_params(suspension: VehicleSuspensionModel) -> void:
	if _rust_rig == null or suspension == null:
		return
	if not suspension._flat_ready:
		suspension.sync_flat_parameters()
	if _rust_param_version == suspension._param_version:
		return
	var p := _rust_params66
	var f := _rust_flags9
	for i in 4:
		p[i] = suspension._spring_rate[i]
		p[4 + i] = suspension._static_load[i]
		p[8 + i] = suspension._rest_offset[i]
		p[12 + i] = suspension._bump_m[i]
		p[16 + i] = suspension._droop_m[i]
		p[20 + i] = suspension._bump_damping[i]
		p[24 + i] = suspension._rebound_damping[i]
		p[28 + i] = suspension._fast_factor[i]
		p[32 + i] = suspension._knee_speed[i]
		p[36 + i] = suspension._bump_stop_travel[i]
		p[40 + i] = suspension._bump_stop_stiffness[i]
		p[44 + i] = suspension._bump_stop_damping[i]
		p[48 + i] = suspension._axis_pitch[i]
		p[52 + i] = suspension._axis_roll[i]
		p[56 + i] = suspension._axis_pitch_gain[i]
		p[60 + i] = suspension._axis_roll_gain[i]
		f[i] = suspension._spring_can_unseat[i]
		f[4 + i] = suspension._has_inclined_axis[i]
	p[64] = suspension.front_arb_stiffness_n_per_m
	p[65] = suspension.rear_arb_stiffness_n_per_m
	f[8] = 1 if suspension._any_inclined_axis else 0
	_rust_rig.call("sync_suspension_params", p, f)
	_rust_param_version = suspension._param_version


func _unpack_rust_normal(out: PackedFloat64Array, suspension: VehicleSuspensionModel) -> void:
	for i in 4:
		s_Fz[i] = out[i]
		s_defl[i] = out[4 + i]
		s_diss[i] = out[8 + i]
		s_Jrad[i] = out[12 + i]
		if suspension != null:
			suspension.compression[i] = out[16 + i]
			suspension.filtered_arb_travel[i] = out[16 + i]
		tick_r[i] = Vector3(out[20 + i * 3], out[21 + i * 3], out[22 + i * 3])
		tick_e_wheel[i] = Vector3(out[32 + i * 3], out[33 + i * 3], out[34 + i * 3])


func _unpack_rust_end(out: PackedFloat64Array) -> void:
	C_pred = Vector3(out[0], out[1], out[2])
	R_pred = Basis(
		Vector3(out[3], out[4], out[5]),
		Vector3(out[6], out[7], out[8]),
		Vector3(out[9], out[10], out[11]),
	)
	V_pred = Vector3(out[12], out[13], out[14])
	omega_pred = Vector3(out[15], out[16], out[17])
	for i in 4:
		q[i] = out[18 + i]
		u[i] = out[22 + i]
		apoyo_previo[i] = s_Fz[i] > 0.0
		if capture_substeps:
			substep_loads_n[i].append(s_Fz[i])
			substep_defl_m[i].append(s_defl[i])
	t_elapsed = out[26]


## Fija el tensor de inercia local 3x3 completo (incluyendo productos Ixy, Ixz, Iyz)
## calculado por VehicleMassModel para el bloque 3..5 de M_factor.
func set_local_inertia_tensor(tensor: Basis) -> void:
	if tensor.x.x <= 1.0 or tensor.y.y <= 1.0 or tensor.z.z <= 1.0:
		has_full_inertia_tensor = false
		if _rust_rig != null:
			_rust_rig.call("set_local_inertia_tensor", false, Basis.IDENTITY)
		return
	# Simetrizar explícitamente para garantizar M_factor simétrica definida positiva.
	var ixy := 0.5 * (tensor.x.y + tensor.y.x)
	var ixz := 0.5 * (tensor.x.z + tensor.z.x)
	var iyz := 0.5 * (tensor.y.z + tensor.z.y)
	tick_inertia_local = Basis(
		Vector3(tensor.x.x, ixy, ixz),
		Vector3(ixy, tensor.y.y, iyz),
		Vector3(ixz, iyz, tensor.z.z),
	)
	has_full_inertia_tensor = true
	if _rust_rig != null:
		_rust_rig.call("set_local_inertia_tensor", true, tick_inertia_local)


## Configura el 1DOF de torsión estructural del chasis (rigidez, amortiguamiento e inercia).
func configure_chassis_torsion(chassis_doc: Dictionary, roll_inertia_izz: float) -> void:
	chassis_torsion_stiffness_nm_per_rad = maxf(float(chassis_doc.get("torsional_stiffness_nm_per_rad", 180000.0)), 10000.0)
	chassis_torsion_damping_ratio = clampf(float(chassis_doc.get("torsional_damping_ratio", 0.25)), 0.05, 1.5)
	var default_twist_i := maxf(roll_inertia_izz * 0.25, 20.0)
	chassis_torsion_inertia_kg_m2 = maxf(float(chassis_doc.get("torsional_inertia_kg_m2", default_twist_i)), 5.0)
	if _rust_rig != null:
		_rust_rig.call(
			"configure_chassis_torsion",
			chassis_torsion_stiffness_nm_per_rad,
			chassis_torsion_damping_ratio,
			chassis_torsion_inertia_kg_m2,
		)


func reset() -> void:
	if chassis != null and is_instance_valid(chassis):
		reset_at(chassis.global_transform, null)
	else:
		q = [0.0, 0.0, 0.0, 0.0]
		u = [0.0, 0.0, 0.0, 0.0]
		chassis_twist_rad = 0.0
		chassis_twist_vel_rad_s = 0.0
		has_pred = false
		if _rust_rig != null:
			_rust_q4[0] = 0.0
			_rust_q4[1] = 0.0
			_rust_q4[2] = 0.0
			_rust_q4[3] = 0.0
			_rust_rig.call("reset_state", _rust_q4)


func reset_at(pose: Transform3D, suspension: VehicleSuspensionModel = null) -> void:
	if suspension != null:
		suspension.clear_transient()
	var q_eq: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var space_state: PhysicsDirectSpaceState3D = null
	if chassis != null and is_instance_valid(chassis) and chassis.is_inside_tree():
		var world := chassis.get_world_3d()
		if world != null:
			space_state = PhysicsServer3D.space_get_direct_state(world.space)
	var excluded: Array[RID] = []
	var collision_mask := 0xFFFFFFFF
	if chassis != null and is_instance_valid(chassis):
		excluded.append(chassis.get_rid())
		collision_mask = chassis.collision_mask
	var up := pose.basis.y.normalized()
	if suspension != null and suspension.axle_parameters.size() == 4:
		for w_i in 4:
			var p: Dictionary = suspension.axle_parameters[w_i]
			q_eq[w_i] = VehicleSuspensionModel.equilibrium_travel_m(p)
			if space_state != null:
				var droop := maxf(float(p.get("droop_m", 0.18)), 0.0)
				var radius := wheel_radii_m[w_i] if w_i < wheel_radii_m.size() else 0.30
				var from: Vector3 = pose * neutral_positions[w_i]
				if not has_ground_support_at(space_state, from, -up, radius + droop + 0.03, collision_mask, excluded):
					q_eq[w_i] = -droop
	last_reset_q_eq = q_eq.duplicate()
	for i in 4:
		q[i] = q_eq[i]
		u[i] = 0.0

		radial_deflection_m[i] = 0.0
		radial_dissipation_w[i] = 0.0
		radial_states[i].clear()
		apoyo_previo[i] = false
		spring_forces_n[i] = 0.0

		acc_Fz[i] = 0.0
		acc_defl[i] = 0.0
		acc_diss[i] = 0.0
		last_tick_trace[i].clear()
		last_damper_requested_n[i] = 0.0
		last_damper_applied_n[i] = 0.0
		last_damper_impulse_ns[i] = 0.0
		s_Jrad[i] = 0.0
		_prev_Jrad[i] = 0.0
		_last_v_fin[i] = 0.0
		_last_d_fin[i] = 0.0
		_inv_m_unsprung[i] = 1.0 / maxf(float(m_unsprung[i]), 1.0)

		s_Fz[i] = 0.0
		s_defl[i] = 0.0
		s_diss[i] = 0.0
	if suspension != null and suspension.axle_parameters.size() == 4:
		for i in 4:
			var p2: Dictionary = suspension.axle_parameters[i]
			var qc := clampf(q[i], -float(p2.get("droop_m", 0.18)), float(p2.get("bump_m", 0.22)))
			suspension.compression[i] = qc
			suspension.compression_velocity[i] = 0.0
			suspension.filtered_arb_travel[i] = qc
			suspension.initialized[i] = true
			suspension.previous_samples[i] = true
			suspension.contact_active[i] = false
			suspension.geometric_contact[i] = false
	chassis_twist_rad = 0.0
	chassis_twist_vel_rad_s = 0.0
	has_pred = false
	acc_J = Vector3.ZERO
	acc_L = Vector3.ZERO
	t_elapsed = 0.0
	for i in 4:
		substep_loads_n[i].clear()
		substep_defl_m[i].clear()
	if _rust_rig != null:
		for i in 4:
			_rust_q4[i] = q[i]
		_rust_rig.call("reset_state", _rust_q4)



# ---- Álgebra 10x10 por complemento de Schur (Basis 3x3 nativo C++) ----

func _w_from_parts(V: Vector3, om: Vector3, uu: Array[float]) -> Array[float]:
	return [V.x, V.y, V.z, om.x, om.y, om.z, float(uu[0]), float(uu[1]), float(uu[2]), float(uu[3])]


func _w_to_V(ww: Array[float]) -> Vector3:
	return Vector3(float(ww[0]), float(ww[1]), float(ww[2]))


func _w_to_omega(ww: Array[float]) -> Vector3:
	return Vector3(float(ww[3]), float(ww[4]), float(ww[5]))


static func _basis_add(a: Basis, b: Basis) -> Basis:
	return Basis(a.x + b.x, a.y + b.y, a.z + b.z)


static func _basis_sub(a: Basis, b: Basis) -> Basis:
	return Basis(a.x - b.x, a.y - b.y, a.z - b.z)


static func _skew(r: Vector3) -> Basis:
	return Basis(
		Vector3(0.0, r.z, -r.y),
		Vector3(-r.z, 0.0, r.x),
		Vector3(r.y, -r.x, 0.0),
	)


static func _perp_projector(e: Vector3) -> Basis:
	return Basis(
		Vector3(1.0 - e.x * e.x, -e.y * e.x, -e.z * e.x),
		Vector3(-e.x * e.y, 1.0 - e.y * e.y, -e.z * e.y),
		Vector3(-e.x * e.z, -e.y * e.z, 1.0 - e.z * e.z),
	)


func _inertia_world_diag_basis(R: Basis, d: Vector3) -> Basis:
	return R * Basis.from_scale(d) * R.transposed()


func _inertia_world_basis(R: Basis, d: Vector3) -> Basis:
	if not has_full_inertia_tensor:
		return _inertia_world_diag_basis(R, d)
	var iw: Basis = R * tick_inertia_local * R.transposed()
	var i01 := 0.5 * (iw.y.x + iw.x.y)
	var i02 := 0.5 * (iw.z.x + iw.x.z)
	var i12 := 0.5 * (iw.z.y + iw.y.z)
	return Basis(
		Vector3(iw.x.x, i01, i02),
		Vector3(i01, iw.y.y, i12),
		Vector3(i02, i12, iw.z.z),
	)


static func _solver_rows(count: int) -> Array:
	var rows: Array = []
	for i in count:
		var row: Array[float] = []
		row.resize(10)
		row.fill(0.0)
		rows.append(row)
	return rows


## Factoriza el sistema 10x10 por complemento de Schur exacto sobre los 4 bujes
## diagonales: colapsa a un sistema 6x6 resuelto con Basis.inverse() en C++.
func _factor_schur() -> void:
	var s_vv := Basis.from_scale(Vector3(tick_m_s, tick_m_s, tick_m_s))
	var s_vw := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var s_ww := _inertia_before
	for i in 4:
		var m_i := float(m_unsprung[i])
		var e_i := tick_e_wheel[i]
		var r_i := tick_r[i]
		_tick_rx[i] = r_i.cross(e_i)
		var p_i := _perp_projector(e_i)
		var r_skew := _skew(r_i)
		var m_p := p_i * m_i
		var m_pr := m_p * r_skew
		s_vv = _basis_add(s_vv, m_p)
		s_vw = _basis_sub(s_vw, m_pr)
		s_ww = _basis_add(s_ww, r_skew.transposed() * m_pr)
	_schur_Svv_inv = s_vv.inverse()
	_schur_Svw = s_vw
	_schur_K = s_vw.transposed() * _schur_Svv_inv
	var s_rot := _basis_sub(s_ww, _schur_K * s_vw)
	_schur_Srot_inv = s_rot.inverse()


func _solve_schur_parts(
	fV: Vector3, fW: Vector3, fu0: float, fu1: float, fu2: float, fu3: float, result: Array[float]
) -> void:
	var tV := fV - tick_e_wheel[0] * fu0 - tick_e_wheel[1] * fu1 - tick_e_wheel[2] * fu2 - tick_e_wheel[3] * fu3
	var tW := fW - _tick_rx[0] * fu0 - _tick_rx[1] * fu1 - _tick_rx[2] * fu2 - _tick_rx[3] * fu3
	var om_out := _schur_Srot_inv * (tW - _schur_K * tV)
	var v_out := _schur_Svv_inv * (tV - _schur_Svw * om_out)
	result[0] = v_out.x
	result[1] = v_out.y
	result[2] = v_out.z
	result[3] = om_out.x
	result[4] = om_out.y
	result[5] = om_out.z
	result[6] = fu0 * _inv_m_unsprung[0] - tick_e_wheel[0].dot(v_out + om_out.cross(tick_r[0]))
	result[7] = fu1 * _inv_m_unsprung[1] - tick_e_wheel[1].dot(v_out + om_out.cross(tick_r[1]))
	result[8] = fu2 * _inv_m_unsprung[2] - tick_e_wheel[2].dot(v_out + om_out.cross(tick_r[2]))
	result[9] = fu3 * _inv_m_unsprung[3] - tick_e_wheel[3].dot(v_out + om_out.cross(tick_r[3]))


func _solve_schur_axis(wheel: int, result: Array[float]) -> void:
	var tV := -tick_e_wheel[wheel]
	var tW := -_tick_rx[wheel]
	var om_out := _schur_Srot_inv * (tW - _schur_K * tV)
	var v_out := _schur_Svv_inv * (tV - _schur_Svw * om_out)
	result[0] = v_out.x
	result[1] = v_out.y
	result[2] = v_out.z
	result[3] = om_out.x
	result[4] = om_out.y
	result[5] = om_out.z
	for i in 4:
		var fu := _inv_m_unsprung[i] if i == wheel else 0.0
		result[6 + i] = fu - tick_e_wheel[i].dot(v_out + om_out.cross(tick_r[i]))


func _solve_schur_normal(wheel: int, nrm: Vector3, result: Array[float]) -> float:
	var e_i := tick_e_wheel[wheel]
	var r_i := tick_r[wheel]
	var en := e_i.dot(nrm)
	var n_perp := nrm - e_i * en
	if n_perp.length_squared() < 1.0e-12:
		result[0] = 0.0
		result[1] = 0.0
		result[2] = 0.0
		result[3] = 0.0
		result[4] = 0.0
		result[5] = 0.0
		result[6] = 0.0
		result[7] = 0.0
		result[8] = 0.0
		result[9] = 0.0
		var u_i := en * _inv_m_unsprung[wheel]
		result[6 + wheel] = u_i
		return maxf(en * u_i, 1.0e-9)
	var tW := r_i.cross(n_perp)
	var om_out := _schur_Srot_inv * (tW - _schur_K * n_perp)
	var v_out := _schur_Svv_inv * (n_perp - _schur_Svw * om_out)
	result[0] = v_out.x
	result[1] = v_out.y
	result[2] = v_out.z
	result[3] = om_out.x
	result[4] = om_out.y
	result[5] = om_out.z
	for i in 4:
		var fu := en * _inv_m_unsprung[i] if i == wheel else 0.0
		result[6 + i] = fu - tick_e_wheel[i].dot(v_out + om_out.cross(tick_r[i]))
	var rn := r_i.cross(nrm)
	return maxf(nrm.dot(v_out) + rn.dot(om_out) + en * result[6 + wheel], 1.0e-9)


func _dot10(a: Array[float], b: Array[float]) -> float:
	return (
		a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
		+ a[3] * b[3] + a[4] * b[4] + a[5] * b[5]
		+ a[6] * b[6] + a[7] * b[7] + a[8] * b[8] + a[9] * b[9]
	)


func _fill_normal_row(r: Vector3, e: Vector3, normal: Vector3, wheel: int) -> void:
	var row: Array[float] = _normal_rows[wheel]
	row[0] = normal.x
	row[1] = normal.y
	row[2] = normal.z
	var torque := r.cross(normal)
	row[3] = torque.x
	row[4] = torque.y
	row[5] = torque.z
	row[6] = 0.0
	row[7] = 0.0
	row[8] = 0.0
	row[9] = 0.0
	row[6 + wheel] = e.dot(normal)


# ---- Ciclo de tick ----

func begin_tick(
	state: PhysicsDirectBodyState3D,
	suspension: VehicleSuspensionModel,
	contacts: Array[Dictionary],
	radii: Array[float],
	domains: Dictionary,
	thermal: VehicleThermalModel,
) -> void:
	tick_sequence += 1
	_set_q_limits(suspension)
	var com_l: Vector3 = chassis.center_of_mass
	tick_com_local = com_l
	tick_m_s = maxf(float(chassis.mass), 1.0)
	tick_inertia_diag = chassis.inertia
	tick_grav = state.total_gravity
	var C: Vector3 = state.transform * com_l
	var R: Basis = state.transform.basis
	var V: Vector3 = state.linear_velocity
	var om: Vector3 = state.angular_velocity
	var e_act := (R * Vector3.UP)
	if e_act.length_squared() > 1.0e-9:
		e_act = e_act.normalized()
	for i in 4:
		if suspension._any_inclined_axis:
			var ew := R * suspension.suspension_axis_local(i, q[i])
			tick_e_wheel[i] = ew.normalized() if ew.length_squared() > 1.0e-9 else e_act
		else:
			tick_e_wheel[i] = e_act
	if has_pred:
		var dV := V - V_pred
		var dom := om - omega_pred
		for i in 4:
			var a: Vector3 = neutral_positions[i] - com_l
			var e_i := tick_e_wheel[i]
			var r_act := R * a + e_i * q[i]
			u[i] -= e_i.dot(dV + dom.cross(r_act))
	C_pred = C
	R_pred = R
	V_pred = V
	omega_pred = om
	tick_e = e_act
	w[0] = V.x
	w[1] = V.y
	w[2] = V.z
	w[3] = om.x
	w[4] = om.y
	w[5] = om.z
	w[6] = u[0]
	w[7] = u[1]
	w[8] = u[2]
	w[9] = u[3]
	_mass_factored_this_tick = false
	_normals_prepared_this_tick = false
	_trace_axis = e_act
	_trace_chassis_velocity = V
	_spring_impulse_ns.fill(0.0)
	_suspension_axial_impulse_ns.fill(0.0)
	_contact_axial_impulse_ns.fill(0.0)
	_contact_vertical_impulse_ns.fill(0.0)
	_radial_impulse_ns.fill(0.0)
	last_damper_impulse_ns.fill(0.0)
	# Anclar contactos.
	var tires: Dictionary = domains.get("tires", {}).get("tires", {})
	for i in 4:
		var c: Dictionary = contacts[i] if i < contacts.size() else {}
		var hit := bool(c.get("hit", false))
		t_hit[i] = hit
		var a2: Vector3 = neutral_positions[i] - com_l
		var e_i := tick_e_wheel[i]
		var r2 := R * a2 + e_i * q[i]
		tick_r[i] = r2
		var H0 := C + r2
		_trace_start_hub_velocity[i] = V + om.cross(r2) + e_i * u[i]
		t_H0[i] = H0
		if not hit:
			t_n[i] = e_i
			t_delta0[i] = 0.0
			t_road_vel[i] = Vector3.ZERO
			t_radial_state[i].clear()
			t_rim_max[i] = 0.05
			_prev_Jrad[i] = 0.0
			continue
		var nrm: Vector3 = (c.get("normal", Vector3.UP) as Vector3).normalized()
		if nrm.length_squared() < 0.5:
			nrm = Vector3.UP
		t_n[i] = nrm
		var dist := float(c.get("distance", 0.0))
		var rad := float(radii[i]) if i < radii.size() else 0.30
		t_delta0[i] = (rad - dist - q[i]) * nrm.dot(e_i)
		var rv := Vector3.ZERO
		var collider: Object = c.get("collider")
		if collider is RigidBody3D:
			var rb := collider as RigidBody3D
			rv = rb.linear_velocity + rb.angular_velocity.cross((c.get("position", H0) as Vector3) - rb.to_global(rb.center_of_mass))
		t_road_vel[i] = rv
		var axle := "front" if i < 2 else "rear"
		var ts: Dictionary = thermal.get_tire_thermal_state_snapshot(i)
		var press := float(ts.get("pressure_kpa_gauge", 180.0))
		var carc := float(ts.get("carcass_c", 25.0))
		var opt := float(thermal.optimal_carcass_temperature(i))
		var rp: PackedFloat64Array = t_radial_packed[i]
		TireRadialModel.prepare_packed_into(rp, tires, axle, press, carc, opt)
		t_radial_packed[i] = rp
		var rim_r := rad * 0.58
		if rp[TireRadialModel.P_RIM_RADIUS] > 0.01:
			rim_r = rp[TireRadialModel.P_RIM_RADIUS]
		var sidewall := maxf(rad - rim_r, 0.03)
		var min_rub := clampf(sidewall * 0.12, 0.010, 0.022)
		t_rim_max[i] = maxf(sidewall - min_rub, 0.02)
		suspension.geometric_contact[i] = true
	t_elapsed = 0.0
	acc_J = Vector3.ZERO
	acc_L = Vector3.ZERO
	for i in 4:
		acc_Fz[i] = 0.0
		acc_defl[i] = 0.0
		acc_diss[i] = 0.0
		s_Fz[i] = 0.0
		s_defl[i] = 0.0
		s_diss[i] = 0.0
		s_Jrad[i] = 0.0

	for i in 4:
		substep_loads_n[i].clear()
		substep_defl_m[i].clear()
	if _ensure_rust_rig() != null:
		_sync_rust_suspension_params(suspension)
		var v14 := _rust_vec14
		v14[0] = tick_com_local
		v14[1] = tick_inertia_diag
		v14[2] = tick_grav
		v14[3] = C
		v14[4] = V
		v14[5] = om
		var sc := _rust_scalars18
		sc[0] = tick_m_s
		sc[1] = float(radial_viscous_scale)
		var r56 := _rust_radial56
		var flags_mask := 0
		if reuse_mass_factor_per_tick:
			flags_mask |= (1 << 4)
		if chassis_torsion_enabled:
			flags_mask |= (1 << 5)
		for i in 4:
			v14[6 + i] = t_n[i]
			v14[10 + i] = t_road_vel[i]
			sc[2 + i] = t_delta0[i]
			sc[6 + i] = t_rim_max[i]
			sc[10 + i] = _qmin[i]
			sc[14 + i] = _qmax[i]
			if t_hit[i]:
				flags_mask |= (1 << i)
				var rp_i: PackedFloat64Array = t_radial_packed[i]
				var base_idx := i * TireRadialModel.PACK_SIZE
				for k in TireRadialModel.PACK_SIZE:
					r56[base_idx + k] = rp_i[k]
		_rust_rig.call("begin_tick", v14, R, sc, r56, flags_mask)


func step_substep_normal(h: float, suspension: VehicleSuspensionModel, F_body: Vector3, T_body: Vector3) -> void:
	if _rust_rig != null:
		t_h = maxf(h, 0.00001)
		var out: PackedFloat64Array = _rust_rig.call("step_substep_normal", h, F_body, T_body)
		_unpack_rust_normal(out, suspension)
		return
	begin_substep(h, suspension, F_body, T_body)
	solve_normal(h)


func step_substep_tangential_and_end(
	h: float, F_patch_J: Vector3, T_patch_J: Vector3, j0: float, j1: float, j2: float, j3: float
) -> void:
	if _rust_rig != null:
		var out: PackedFloat64Array = _rust_rig.call(
			"step_substep_tangential_and_end", h, F_patch_J, T_patch_J, j0, j1, j2, j3
		)
		_unpack_rust_end(out)
		return
	var J_tang: Array[float] = [
		F_patch_J.x, F_patch_J.y, F_patch_J.z,
		T_patch_J.x, T_patch_J.y, T_patch_J.z,
		j0, j1, j2, j3,
	]
	apply_tangential(J_tang)
	solve_hard_stops(h)
	end_substep(h)


func begin_substep(h: float, suspension: VehicleSuspensionModel, F_body: Vector3, T_body: Vector3) -> void:
	if _rust_rig != null:
		t_h = maxf(h, 0.00001)
		var out: PackedFloat64Array = _rust_rig.call("begin_substep", h, F_body, T_body)
		for i in 4:
			if suspension != null:
				suspension.compression[i] = out[i]
				suspension.filtered_arb_travel[i] = out[i]
			tick_r[i] = Vector3(out[4 + i * 3], out[5 + i * 3], out[6 + i * 3])
			tick_e_wheel[i] = Vector3(out[16 + i * 3], out[17 + i * 3], out[18 + i * 3])
		return
	t_h = maxf(h, 0.00001)
	if not suspension._flat_ready:
		suspension.sync_flat_parameters()
	var e := (R_pred * Vector3.UP)
	if e.length_squared() > 1.0e-9:
		e = e.normalized()
	tick_e = e
	var om := Vector3(w[3], w[4], w[5])
	var need_factor := (not reuse_mass_factor_per_tick) or (not _mass_factored_this_tick)
	if need_factor:
		_inertia_before = _inertia_world_basis(R_pred, tick_inertia_diag)
		_jolt_inertia_before = _inertia_world_diag_basis(R_pred, tick_inertia_diag) if has_full_inertia_tensor else _inertia_before
		for i in 4:
			var e_i := e
			if suspension._any_inclined_axis:
				var ew := R_pred * suspension.suspension_axis_local(i, q[i])
				e_i = ew.normalized() if ew.length_squared() > 1.0e-9 else e
			tick_e_wheel[i] = e_i
			tick_r[i] = R_pred * (neutral_positions[i] - tick_com_local) + e_i * q[i]
		_factor_schur()
		for i in 4:
			var response: Array[float] = _axis_response[i]
			_solve_schur_axis(i, response)
			_relative_mass[i] = 1.0 / maxf(response[6 + i], 1.0e-9)
		_mass_factored_this_tick = true
	else:
		_inertia_before = _inertia_world_basis(R_pred, tick_inertia_diag)
		_jolt_inertia_before = _inertia_world_diag_basis(R_pred, tick_inertia_diag) if has_full_inertia_tensor else _inertia_before
		for i in 4:
			tick_r[i] = R_pred * (neutral_positions[i] - tick_com_local) + tick_e_wheel[i] * q[i]
	# Suspensión: q_nom (incluyendo torsión estructural del chasis en serie) y m_rel.
	var hf_f := 0.25 * _track_front_m if chassis_torsion_enabled else 0.0
	var hf_r := 0.25 * _track_rear_m if chassis_torsion_enabled else 0.0
	var dq0 := hf_f * chassis_twist_rad
	var dq2 := -hf_r * chassis_twist_rad
	var du0 := hf_f * chassis_twist_vel_rad_s
	var du2 := -hf_r * chassis_twist_vel_rad_s
	for i in 4:
		var dq_i := dq0 if i == 0 else (-dq0 if i == 1 else (dq2 if i == 2 else -dq2))
		var du_i := du0 if i == 0 else (-du0 if i == 1 else (du2 if i == 2 else -du2))
		var qn := clampf(q[i] - dq_i, -suspension._droop_m[i], suspension._bump_m[i])
		suspension.compression[i] = qn
		suspension.compression_velocity[i] = u[i] - du_i
		suspension.filtered_arb_travel[i] = qn
		suspension.contact_active[i] = apoyo_previo[i]
	var Fs: Array[float] = suspension.suspension_forces_1dof(t_h, _relative_mass)
	# Resistencia al droop semi-implícita usando la masa relativa 1DOF (_relative_mass[i]).
	for i in 4:
		var droop := suspension._droop_m[i]
		var qn := suspension.compression[i]
		if qn < -droop + 0.025:
			var pen := (-droop + 0.025) - qn
			var m_eff_d := maxf(_relative_mass[i], 1.0)
			var k_droop := suspension._spring_rate[i] * 6.0
			var c_droop := suspension._rebound_damping[i] * 2.5
			var k_droop_eff := k_droop / (1.0 + (k_droop * t_h * t_h) / m_eff_d)
			var c_droop_eff := c_droop / (1.0 + (c_droop * t_h) / m_eff_d)
			Fs[i] = Fs[i] - (k_droop_eff * pen - c_droop_eff * minf(u[i], 0.0))
	# Avanzar 1DOF de torsión estructural del chasis (subchasis delantero vs trasero).
	if chassis_torsion_enabled:
		var m_roll_f := (Fs[0] - Fs[1]) * (0.5 * _track_front_m)
		var m_roll_r := (Fs[2] - Fs[3]) * (0.5 * _track_rear_m)
		var t_twist_ext := 0.5 * (m_roll_f - m_roll_r)
		var k_tw := maxf(chassis_torsion_stiffness_nm_per_rad, 10000.0)
		var i_tw := maxf(chassis_torsion_inertia_kg_m2, 5.0)
		var c_tw := 2.0 * sqrt(k_tw * i_tw) * clampf(chassis_torsion_damping_ratio, 0.05, 1.5)
		var k_f_roll := (suspension._spring_rate[0] + 2.0 * suspension.front_arb_stiffness_n_per_m) * (0.125 * _track_front_m * _track_front_m)
		var k_r_roll := (suspension._spring_rate[2] + 2.0 * suspension.rear_arb_stiffness_n_per_m) * (0.125 * _track_rear_m * _track_rear_m)
		var k_series := k_tw + k_f_roll + k_r_roll
		var denom_tw := i_tw + t_h * c_tw + t_h * t_h * k_series
		var acc_tw := (t_twist_ext - k_tw * chassis_twist_rad - c_tw * chassis_twist_vel_rad_s) / maxf(denom_tw, 1.0e-6)
		chassis_twist_vel_rad_s += acc_tw * t_h
		chassis_twist_rad = clampf(chassis_twist_rad + chassis_twist_vel_rad_s * t_h, -0.08, 0.08)

	var e_dot_trace := e.dot(_trace_axis)
	for i in 4:
		spring_forces_n[i] = Fs[i]
		last_damper_requested_n[i] = suspension.last_damper_explicit_n[i]
		last_damper_applied_n[i] = suspension.last_damper_forces_n[i]
		last_damper_impulse_ns[i] += last_damper_applied_n[i] * t_h
		var spring_impulse := Fs[i] * t_h
		_spring_impulse_ns[i] += spring_impulse
		_suspension_axial_impulse_ns[i] -= spring_impulse * e_dot_trace
	# Q generalizado.
	var Qv := tick_m_s * tick_grav + F_body
	var IwOm := _inertia_before * om
	var Qt := -om.cross(IwOm) + T_body
	var fu0 := 0.0
	var fu1 := 0.0
	var fu2 := 0.0
	var fu3 := 0.0
	for i in 4:
		var r := tick_r[i]
		var e_i := tick_e_wheel[i]
		var bias := om.cross(om.cross(r)) + om.cross(e_i * u[i]) * 2.0
		var force := m_unsprung[i] * (tick_grav - bias)
		Qv += force
		Qt += r.cross(force)
		var fu_i := e_i.dot(force) - Fs[i]
		if i == 0:
			fu0 = fu_i
		elif i == 1:
			fu1 = fu_i
		elif i == 2:
			fu2 = fu_i
		else:
			fu3 = fu_i
	_solve_schur_parts(Qv, Qt, fu0, fu1, fu2, fu3, _response)
	for k in 10:
		w_free[k] = w[k] + t_h * _response[k]


func solve_normal(h: float) -> void:
	if _rust_rig != null:
		var out: PackedFloat64Array = _rust_rig.call("solve_normal", h)
		_unpack_rust_normal(out, null)
		return
	var hh := maxf(h, 0.00001)
	var hh_scale := hh / maxf(_prev_hh, 0.00001)
	for k in 10:
		_w_rad[k] = w_free[k]
	var need_normals := (not reuse_mass_factor_per_tick) or (not _normals_prepared_this_tick)
	var v_scale := float(radial_viscous_scale)
	for i in 4:
		s_Jrad[i] = 0.0
		s_Fz[i] = 0.0
		s_defl[i] = 0.0
		s_diss[i] = 0.0
		if not t_hit[i]:
			radial_states[i].clear()
			_prev_Jrad[i] = 0.0
			continue
		var response: Array[float] = _normal_response[i]
		var G: Array[float] = _normal_rows[i]
		if need_normals:
			_fill_normal_row(tick_r[i], tick_e_wheel[i], t_n[i], i)
			s_Kn[i] = _solve_schur_normal(i, t_n[i], response)
		var Kn := s_Kn[i]
		var H := C_pred + tick_r[i]
		var delta := t_delta0[i] - t_n[i].dot((H - t_H0[i]) - t_road_vel[i] * t_elapsed)
		_normal_deflection[i] = delta
		_normal_road_speed[i] = t_n[i].dot(t_road_vel[i])
		var v_free := _dot10(G, w_free) - _normal_road_speed[i]
		var mi := maxf(m_unsprung[i], 1.0)
		var rp: PackedFloat64Array = t_radial_packed[i]
		var J := 0.0
		var dfin := maxf(delta - hh * v_free, 0.0)
		if dfin > 0.0:
			var Jmax := maxf((delta / hh - v_free) / Kn, 0.0)
			var lo := 0.0
			var hi := Jmax
			var f_lo := TireRadialModel.packed_force_n(rp, mi, dfin, clampf(-v_free, -12.0, 12.0), v_scale)
			var r_lo := -hh * f_lo
			var r_hi := Jmax
			if r_lo < 0.0 and Jmax > 0.0:
				var j_try := clampf(_prev_Jrad[i] * hh_scale, lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo)) if _prev_Jrad[i] > 0.0 else (0.5 * Jmax)
				for it in 24:
					var v_try := v_free + Kn * j_try
					var d_try := maxf(delta - hh * v_try, 0.0)
					var c_try := clampf(-v_try, -12.0, 12.0)
					var f_try := TireRadialModel.packed_force_n(rp, mi, d_try, c_try, v_scale)
					var res := j_try - hh * f_try
					if absf(res) <= RADIAL_BISECTION_REL_TOL * maxf(absf(j_try), 1.0):
						J = j_try
						lo = j_try
						hi = j_try
						break
					if res >= 0.0:
						hi = j_try
						r_hi = res
					else:
						lo = j_try
						r_lo = res
					if hi - lo <= RADIAL_BISECTION_REL_TOL * maxf(absf(lo), 1.0):
						J = 0.5 * (lo + hi)
						break
					var denom_sec := r_hi - r_lo
					var j_next := 0.5 * (lo + hi)
					if denom_sec > 1.0e-12:
						var j_sec := (lo * r_hi - hi * r_lo) / denom_sec
						var margin := 0.08 * (hi - lo)
						if j_sec > lo + margin and j_sec < hi - margin:
							j_next = j_sec
					j_try = j_next
				if hi > lo:
					J = 0.5 * (lo + hi)
		s_Jrad[i] = maxf(J, 0.0)
		_prev_Jrad[i] = s_Jrad[i]
		var v_fin := v_free + Kn * s_Jrad[i]
		var d_fin := maxf(delta - hh * v_fin, 0.0)
		var c_fin := clampf(-v_fin, -12.0, 12.0)
		_last_v_fin[i] = c_fin
		_last_d_fin[i] = d_fin
		var fd := TireRadialModel.packed_force_and_dissipation(rp, mi, d_fin, c_fin, v_scale)
		s_defl[i] = d_fin
		s_diss[i] = fd.y
		for k in 10:
			_w_rad[k] += response[k] * s_Jrad[i]
	_normals_prepared_this_tick = true
	_prev_hh = hh

	# Todas las correcciones de llanta leen la misma velocidad posterior al radial.
	for k in 10:
		w_normal[k] = _w_rad[k]
	var rim_impulse_cap := 8.0 * maxf(tick_m_s, 100.0) * tick_grav.length() * hh
	for i in 4:
		if not t_hit[i]:
			continue
		var gap := t_rim_max[i] - _normal_deflection[i]
		var target := -gap / hh if gap >= 0.0 else minf(2.0, -0.18 * gap / hh)
		var normal_speed := _dot10(_normal_rows[i], _w_rad) - _normal_road_speed[i]
		var impulse := clampf((target - normal_speed) / s_Kn[i], 0.0, rim_impulse_cap)
		var normal_impulse := s_Jrad[i] + impulse
		s_Fz[i] = normal_impulse / hh
		_radial_impulse_ns[i] += s_Jrad[i]
		_contact_axial_impulse_ns[i] += normal_impulse * t_n[i].dot(_trace_axis)
		_contact_vertical_impulse_ns[i] += normal_impulse * t_n[i].y
		if normal_impulse <= 0.0:
			radial_states[i].clear()
		var response: Array[float] = _normal_response[i]
		for k in 10:
			w_normal[k] += response[k] * impulse


func contact_patch_position(wheel: int, initial_point: Vector3) -> Vector3:
	var road_displacement := t_road_vel[wheel] * t_elapsed
	var hub_displacement := C_pred + tick_r[wheel] - t_H0[wheel]
	return initial_point + road_displacement + (hub_displacement - road_displacement).slide(t_n[wheel])


func apply_tangential(J_tang: Array[float]) -> void:
	if _rust_rig != null:
		_rust_rig.call(
			"apply_tangential",
			Vector3(J_tang[0], J_tang[1], J_tang[2]),
			Vector3(J_tang[3], J_tang[4], J_tang[5]),
			J_tang[6],
			J_tang[7],
			J_tang[8],
			J_tang[9],
		)
		return
	_solve_schur_parts(
		Vector3(J_tang[0], J_tang[1], J_tang[2]),
		Vector3(J_tang[3], J_tang[4], J_tang[5]),
		J_tang[6], J_tang[7], J_tang[8], J_tang[9],
		_response,
	)
	for k in 10:
		w_cand[k] = w_normal[k] + _response[k]


func solve_hard_stops(h: float) -> void:
	if _rust_rig != null:
		_rust_rig.call("solve_hard_stops", h)
		return
	var hh := maxf(h, 0.00001)
	var lo: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var hi: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var needs_stop := false
	for i in 4:
		lo[i] = (_qmin[i] - q[i]) / hh
		hi[i] = (_qmax[i] - q[i]) / hh
		needs_stop = needs_stop or w_cand[6 + i] < lo[i] or w_cand[6 + i] > hi[i]
	if not needs_stop:
		return
	var lam: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for sweep in 20:
		var maxd := 0.0
		for i in 4:
			var d: Array[float] = _axis_response[i]
			var inverse_mass := maxf(d[6 + i], 1.0e-9)
			var w_s := float(w_cand[6 + i]) - inverse_mass * lam[i]
			var ul := clampf(w_s, float(lo[i]), float(hi[i]))
			var lam_new := (ul - w_s) / maxf(inverse_mass, 1.0e-12)
			var dl := lam_new - lam[i]
			maxd = maxf(maxd, absf(dl))
			if absf(dl) > 1.0e-12:
				for k in 10:
					w_cand[k] = float(w_cand[k]) + float(d[k]) * dl
				lam[i] = lam_new
		if maxd < 1.0e-9:
			break


var _qmin: Array[float] = [-0.28, -0.28, -0.28, -0.28]
var _qmax: Array[float] = [0.32, 0.32, 0.32, 0.32]


func end_substep(h: float) -> void:
	if _rust_rig != null:
		var out: PackedFloat64Array = _rust_rig.call("end_substep", h)
		_unpack_rust_end(out)
		return
	var hh := maxf(h, 0.00001)
	var V_old := _w_to_V(w)
	var om_old := _w_to_omega(w)
	var Iw_old := _inertia_before
	var V_new := _w_to_V(w_cand)
	var om_new := _w_to_omega(w_cand)
	for i in 4:
		u[i] = float(w_cand[6 + i])
		q[i] += hh * u[i]
		# Clamp numérico al intervalo efectivo.
		q[i] = clampf(q[i], float(_qmin[i]), float(_qmax[i]))
	# Avanzar pose predicha.
	C_pred += hh * V_new
	var om_len := om_new.length()
	if om_len > 1.0e-9:
		var axis := om_new / om_len
		R_pred = Basis(axis, om_len * hh) * R_pred
	# Acumular envío a Jolt (cambio de momento menos gravedad suspendida).
	# Cuando el rig usa tensor 3x3 completo, proyectamos Δω con la inercia diagonal
	# de Jolt para que Jolt alcance exactamente om_new (conservando el acoplamiento cruzado).
	acc_J += tick_m_s * (V_new - V_old) - hh * tick_m_s * tick_grav
	var Iw_jolt_new := _inertia_world_diag_basis(R_pred, tick_inertia_diag) if has_full_inertia_tensor else _inertia_world_basis(R_pred, tick_inertia_diag)
	var Iw_jolt_old := _jolt_inertia_before if has_full_inertia_tensor else Iw_old
	acc_L += Iw_jolt_new * om_new - Iw_jolt_old * om_old
	var previous_w := w
	w = w_cand
	w_cand = previous_w
	V_pred = V_new
	omega_pred = om_new
	for i in 4:
		apoyo_previo[i] = float(s_Fz[i]) > 0.0
		acc_Fz[i] = float(acc_Fz[i]) + float(s_Fz[i]) * hh
		acc_defl[i] = float(acc_defl[i]) + float(s_defl[i]) * hh
		acc_diss[i] = float(acc_diss[i]) + float(s_diss[i]) * hh
		if capture_substeps:
			substep_loads_n[i].append(s_Fz[i])
			substep_defl_m[i].append(s_defl[i])
	t_elapsed += hh


# Fijar límites efectivos antes de resolver topes (llamado por begin_substep).
func _set_q_limits(suspension: VehicleSuspensionModel) -> void:
	for i in 4:
		var p: Dictionary = suspension.axle_parameters[i]
		_qmin[i] = -float(p.get("droop_m", 0.18)) - JOINT_LIMIT_MARGIN_M
		_qmax[i] = float(p.get("bump_m", 0.22)) + JOINT_LIMIT_MARGIN_M


func end_tick(state: PhysicsDirectBodyState3D, dt: float, suspension: VehicleSuspensionModel) -> Array[float]:
	var dtt := maxf(dt, 0.00001)
	if _rust_rig != null:
		var snap: PackedFloat64Array = _rust_rig.call("end_tick_snapshot")
		acc_J = Vector3(snap[0], snap[1], snap[2])
		acc_L = Vector3(snap[3], snap[4], snap[5])
		for i in 4:
			acc_Fz[i] = snap[6 + i]
			acc_defl[i] = snap[10 + i]
			acc_diss[i] = snap[14 + i]
			q[i] = snap[18 + i]
			u[i] = snap[22 + i]
			_last_d_fin[i] = snap[26 + i]
			_last_v_fin[i] = snap[30 + i]
			spring_forces_n[i] = snap[34 + i]
			last_damper_requested_n[i] = snap[38 + i]
			last_damper_applied_n[i] = snap[42 + i]
			last_damper_impulse_ns[i] = snap[46 + i]
			_spring_impulse_ns[i] = snap[50 + i]
			_suspension_axial_impulse_ns[i] = snap[54 + i]
			_contact_axial_impulse_ns[i] = snap[58 + i]
			_contact_vertical_impulse_ns[i] = snap[62 + i]
			_radial_impulse_ns[i] = snap[66 + i]
			if suspension != null:
				suspension.last_elastic_forces_n[i] = snap[70 + i]
				suspension.last_bump_forces_n[i] = snap[74 + i]
				suspension.last_damper_explicit_n[i] = snap[38 + i]
				suspension.last_damper_forces_n[i] = snap[42 + i]
		chassis_twist_rad = snap[78]
		chassis_twist_vel_rad_s = snap[79]
		_trace_axis = Vector3(snap[80], snap[81], snap[82])
		_trace_chassis_velocity = Vector3(snap[83], snap[84], snap[85])
		for i in 4:
			_trace_start_hub_velocity[i] = Vector3(snap[86 + i * 3], snap[87 + i * 3], snap[88 + i * 3])
	state.apply_central_force(acc_J / dtt)
	state.apply_torque(acc_L / dtt)
	has_pred = true
	_publish_tick(suspension, dtt)
	var out: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		out[i] = float(acc_Fz[i]) / dtt
	return out


# ---- API §4 ----

func muestra_de_rueda(i: int, t: Transform3D, V: Vector3, om: Vector3) -> Dictionary:
	var com_l: Vector3 = chassis.center_of_mass if chassis != null else Vector3.ZERO
	var R: Basis = t.basis
	var e := (R * Vector3.UP)
	if e.length_squared() > 1.0e-9:
		e = e.normalized()
	var C: Vector3 = t * com_l
	var a: Vector3 = neutral_positions[i] - com_l if i < neutral_positions.size() else Vector3.ZERO
	var r := R * a + e * float(q[i])
	var H := C + r
	var vH := V + om.cross(r) + e * float(u[i])
	return {"travel": float(q[i]), "H": H, "vH": vH}


func _publish_tick(suspension: VehicleSuspensionModel, dtt: float) -> void:
	var end_axis := R_pred.y.normalized()
	if not suspension._flat_ready:
		suspension.sync_flat_parameters()
	var v_scale := float(radial_viscous_scale)
	for i in 4:
		var mean_F := acc_Fz[i] / dtt
		var mean_d := acc_defl[i] / dtt
		var mean_s := acc_diss[i] / dtt
		radial_deflection_m[i] = mean_d
		radial_dissipation_w[i] = mean_s
		if t_hit[i] and mean_F > 0.0 and t_radial_packed[i].size() >= TireRadialModel.PACK_SIZE:
			TireRadialModel.populate_radial_dict_from_packed(
				radial_states[i],
				t_radial_packed[i],
				maxf(m_unsprung[i], 1.0),
				_last_d_fin[i],
				_last_v_fin[i],
				v_scale,
			)
		else:
			radial_states[i].clear()

		var qn := clampf(q[i], -suspension._droop_m[i], suspension._bump_m[i])
		suspension.compression[i] = qn
		suspension.compression_velocity[i] = u[i]
		suspension.filtered_arb_travel[i] = qn
		suspension.contact_active[i] = mean_F > 0.0
		suspension.geometric_contact[i] = t_hit[i]

		# El balance axial usa el eje del inicio del tick para todos los impulsos.
		var end_arm := R_pred * (neutral_positions[i] - tick_com_local) + end_axis * q[i]
		var end_velocity := V_pred + omega_pred.cross(end_arm) + end_axis * u[i]
		var start_velocity := _trace_start_hub_velocity[i]
		var gravity_impulse := m_unsprung[i] * tick_grav.dot(_trace_axis) * dtt
		var tr: Dictionary = last_tick_trace[i]
		var cv: Array = tr.get("chassis_vel", [])
		if cv.size() != 3:
			cv = [_trace_chassis_velocity.x, _trace_chassis_velocity.y, _trace_chassis_velocity.z]
			tr["chassis_vel"] = cv
		else:
			cv[0] = _trace_chassis_velocity.x
			cv[1] = _trace_chassis_velocity.y
			cv[2] = _trace_chassis_velocity.z
		var hv: Array = tr.get("hub_vel", [])
		if hv.size() != 3:
			hv = [start_velocity.x, start_velocity.y, start_velocity.z]
			tr["hub_vel"] = hv
		else:
			hv[0] = start_velocity.x
			hv[1] = start_velocity.y
			hv[2] = start_velocity.z
		tr["hub_mass_kg"] = m_unsprung[i]
		tr["pre_hub_vel_axial"] = start_velocity.dot(_trace_axis)
		tr["post_hub_vel_axial"] = end_velocity.dot(_trace_axis)
		tr["J_susp_ns"] = _suspension_axial_impulse_ns[i]
		tr["J_radial_ns"] = _contact_axial_impulse_ns[i]
		tr["contact_vertical_impulse_ns"] = _contact_vertical_impulse_ns[i]
		tr["J_gravity_ns"] = gravity_impulse
		tr["J_sum_known_ns"] = _suspension_axial_impulse_ns[i] + _contact_axial_impulse_ns[i] + gravity_impulse
		tr["tick_id"] = tick_sequence
		tr["dt_s"] = dtt
		tr["relative_velocity_m_s"] = u[i]
		tr["damper_requested_n"] = last_damper_requested_n[i]
		tr["damper_applied_n"] = last_damper_applied_n[i]
		tr["damper_impulse_ns"] = last_damper_impulse_ns[i]
		tr["internal_force_n"] = spring_forces_n[i]
		tr["internal_impulse_ns"] = _spring_impulse_ns[i]
		tr["radial_F_mean_n"] = mean_F
		tr["radial_J_imp_ns"] = _radial_impulse_ns[i]
