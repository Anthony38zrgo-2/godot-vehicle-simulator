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
var _inertia_before: Array = []
var _jolt_inertia_before: Array = []
var capture_substeps := false
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
	if wheel_radii.size() == 4:
		wheel_radii_m.assign(wheel_radii)
	if neutral_positions.size() == 4:
		_track_front_m = maxf(absf(neutral_positions[1].x - neutral_positions[0].x), 0.5)
		_track_rear_m = maxf(absf(neutral_positions[3].x - neutral_positions[2].x), 0.5)
	reset_at(body.global_transform, suspension)
	print(
		"RALLY_UNSPRUNG_READY ",
		JSON.stringify(
			{"hub_masses_kg": masses, "sprung_mass_kg": body.mass, "mode": "1dof_scalar"}
		),
	)


## Fija el tensor de inercia local 3x3 completo (incluyendo productos Ixy, Ixz, Iyz)
## calculado por VehicleMassModel para el bloque 3..5 de M_factor.
func set_local_inertia_tensor(tensor: Basis) -> void:
	if tensor.x.x <= 1.0 or tensor.y.y <= 1.0 or tensor.z.z <= 1.0:
		has_full_inertia_tensor = false
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


## Configura el 1DOF de torsión estructural del chasis (rigidez, amortiguamiento e inercia).
func configure_chassis_torsion(chassis_doc: Dictionary, roll_inertia_izz: float) -> void:
	chassis_torsion_stiffness_nm_per_rad = maxf(float(chassis_doc.get("torsional_stiffness_nm_per_rad", 180000.0)), 10000.0)
	chassis_torsion_damping_ratio = clampf(float(chassis_doc.get("torsional_damping_ratio", 0.25)), 0.05, 1.5)
	var default_twist_i := maxf(roll_inertia_izz * 0.25, 20.0)
	chassis_torsion_inertia_kg_m2 = maxf(float(chassis_doc.get("torsional_inertia_kg_m2", default_twist_i)), 5.0)


func reset() -> void:
	if chassis != null and is_instance_valid(chassis):
		reset_at(chassis.global_transform, null)
	else:
		q = [0.0, 0.0, 0.0, 0.0]
		u = [0.0, 0.0, 0.0, 0.0]
		chassis_twist_rad = 0.0
		chassis_twist_vel_rad_s = 0.0
		has_pred = false


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
		radial_states[i] = {}
		apoyo_previo[i] = false
		spring_forces_n[i] = 0.0

		acc_Fz[i] = 0.0
		acc_defl[i] = 0.0
		acc_diss[i] = 0.0
		last_tick_trace[i] = {}
		last_damper_requested_n[i] = 0.0
		last_damper_applied_n[i] = 0.0
		last_damper_impulse_ns[i] = 0.0
		s_Jrad[i] = 0.0

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



# ---- Álgebra 10x10 ----

func _w_from_parts(V: Vector3, om: Vector3, uu: Array[float]) -> Array[float]:
	return [V.x, V.y, V.z, om.x, om.y, om.z, float(uu[0]), float(uu[1]), float(uu[2]), float(uu[3])]


func _w_to_V(ww: Array[float]) -> Vector3:
	return Vector3(float(ww[0]), float(ww[1]), float(ww[2]))


func _w_to_omega(ww: Array[float]) -> Vector3:
	return Vector3(float(ww[3]), float(ww[4]), float(ww[5]))


func _inertia_world_diag(R: Basis, d: Vector3) -> Array:
	var cx := R.x
	var cy := R.y
	var cz := R.z
	# I[i][j] = sum_k Rcol_k[i]*d[k]*Rcol_k[j].
	var out: Array = []
	var colset := [cx, cy, cz]
	for i in 3:
		var row2: Array[float] = [0.0, 0.0, 0.0]
		for j in 3:
			var s := 0.0
			for k in 3:
				var dk := d.x if k == 0 else (d.y if k == 1 else d.z)
				s += (colset[k] as Vector3)[i] * dk * (colset[k] as Vector3)[j]
			row2[j] = s
		out.append(row2)
	return out


func _inertia_world(R: Basis, d: Vector3) -> Array:
	if not has_full_inertia_tensor:
		return _inertia_world_diag(R, d)
	# Tensor 3x3 completo en espacio de mundo: I_world = R * I_local * R^T.
	var iw: Basis = R * tick_inertia_local * R.transposed()
	var i01 := 0.5 * (iw.y.x + iw.x.y)
	var i02 := 0.5 * (iw.z.x + iw.x.z)
	var i12 := 0.5 * (iw.z.y + iw.y.z)
	return [
		[iw.x.x, i01, i02],
		[i01, iw.y.y, i12],
		[i02, i12, iw.z.z],
	]


func _mat3_vec(M: Array, v: Vector3) -> Vector3:
	var vv := [v.x, v.y, v.z]
	var o := [0.0, 0.0, 0.0]
	for i in 3:
		var s := 0.0
		for j in 3:
			s += float((M[i] as Array)[j]) * float(vv[j])
		o[i] = s
	return Vector3(o[0], o[1], o[2])


static func _solver_rows(count: int) -> Array:
	var rows: Array = []
	for i in count:
		var row: Array[float] = []
		row.resize(10)
		row.fill(0.0)
		rows.append(row)
	return rows


func _factor_mass() -> void:
	for i in 10:
		var row: Array[float] = M_factor[i]
		for j in (i + 1):
			var other: Array[float] = M_factor[j]
			var pivot := row[j]
			for k in j:
				pivot -= row[k] * other[k]
			row[j] = sqrt(maxf(pivot, 1.0e-9)) if i == j else pivot / maxf(other[j], 1.0e-12)


func _solve_chol(rhs: Array[float], result: Array[float]) -> void:
	for i in 10:
		var row: Array[float] = M_factor[i]
		var value := rhs[i]
		for k in i:
			value -= row[k] * result[k]
		result[i] = value / maxf(row[i], 1.0e-12)
	for i in range(9, -1, -1):
		var value := result[i]
		for k in range(i + 1, 10):
			value -= float(M_factor[k][i]) * result[k]
		result[i] = value / maxf(float(M_factor[i][i]), 1.0e-12)


func _dot10(a: Array[float], b: Array[float]) -> float:
	var s := 0.0
	for i in 10:
		s += float(a[i]) * float(b[i])
	return s


func _fill_hub_jacobian(r: Vector3, e: Vector3, wheel: int) -> void:
	var x: Array[float] = _hub_jacobian[0]
	var y: Array[float] = _hub_jacobian[1]
	var z: Array[float] = _hub_jacobian[2]
	x.fill(0.0)
	y.fill(0.0)
	z.fill(0.0)
	x[0] = 1.0
	y[1] = 1.0
	z[2] = 1.0
	x[4] = r.z
	x[5] = -r.y
	y[3] = -r.z
	y[5] = r.x
	z[3] = r.y
	z[4] = -r.x
	x[6 + wheel] = e.x
	y[6 + wheel] = e.y
	z[6 + wheel] = e.z


func _fill_normal_row(r: Vector3, e: Vector3, normal: Vector3, wheel: int) -> void:
	var row: Array[float] = _normal_rows[wheel]
	row[0] = normal.x
	row[1] = normal.y
	row[2] = normal.z
	var torque := r.cross(normal)
	row[3] = torque.x
	row[4] = torque.y
	row[5] = torque.z
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
		var ew := R * suspension.suspension_axis_local(i, q[i])
		tick_e_wheel[i] = ew.normalized() if ew.length_squared() > 1.0e-9 else e_act
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
	w = _w_from_parts(V, om, u)
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
			t_radial_state[i] = {}
			t_rim_max[i] = 0.05
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
		t_radial_state[i] = TireRadialModel.prepare_state(tires, axle, press, carc, opt)
		var rim_r := rad * 0.58
		var g: Dictionary = t_radial_state[i]["geometry"]
		if float(g.get("rim_radius_m", 0.0)) > 0.01:
			rim_r = float(g.get("rim_radius_m", rim_r))
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


func begin_substep(h: float, suspension: VehicleSuspensionModel, F_body: Vector3, T_body: Vector3) -> void:
	t_h = maxf(h, 0.00001)
	var e := (R_pred * Vector3.UP)
	if e.length_squared() > 1.0e-9:
		e = e.normalized()
	tick_e = e
	_inertia_before = _inertia_world(R_pred, tick_inertia_diag)
	_jolt_inertia_before = _inertia_world_diag(R_pred, tick_inertia_diag) if has_full_inertia_tensor else _inertia_before
	for row in M_factor:
		row.fill(0.0)
	for i in 3:
		M_factor[i][i] = tick_m_s
		for j in (i + 1):
			M_factor[3 + i][3 + j] = _inertia_before[i][j]
	var om := _w_to_omega(w)
	for i in 4:
		var ew := R_pred * suspension.suspension_axis_local(i, q[i])
		var e_i := ew.normalized() if ew.length_squared() > 1.0e-9 else e
		tick_e_wheel[i] = e_i
		var r := R_pred * (neutral_positions[i] - tick_com_local) + e_i * q[i]
		tick_r[i] = r
		_fill_hub_jacobian(r, e_i, i)
		var mass := m_unsprung[i]
		var bx: Array[float] = _hub_jacobian[0]
		var by: Array[float] = _hub_jacobian[1]
		var bz: Array[float] = _hub_jacobian[2]
		# Cada rueda afecta seis coordenadas de chasis y su propia coordenada axial.
		for p in 7:
			var row_index := p if p < 6 else 6 + i
			var row: Array[float] = M_factor[row_index]
			for j in (p + 1):
				var col := j if j < 6 else 6 + i
				var product := bx[row_index] * bx[col] + by[row_index] * by[col] + bz[row_index] * bz[col]
				row[col] += mass * product
	_factor_mass()
	# Suspensión: q_nom (incluyendo torsión estructural del chasis en serie) y m_rel.
	var dq_twist: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var du_twist: Array[float] = [0.0, 0.0, 0.0, 0.0]
	if chassis_torsion_enabled:
		var hf_f := 0.25 * _track_front_m
		var hf_r := 0.25 * _track_rear_m
		dq_twist[0] = hf_f * chassis_twist_rad
		dq_twist[1] = -hf_f * chassis_twist_rad
		dq_twist[2] = -hf_r * chassis_twist_rad
		dq_twist[3] = hf_r * chassis_twist_rad
		du_twist[0] = hf_f * chassis_twist_vel_rad_s
		du_twist[1] = -hf_f * chassis_twist_vel_rad_s
		du_twist[2] = -hf_r * chassis_twist_vel_rad_s
		du_twist[3] = hf_r * chassis_twist_vel_rad_s
	var q_nom: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		var p: Dictionary = suspension.axle_parameters[i]
		q_nom[i] = clampf(q[i] - dq_twist[i], -float(p.get("droop_m", 0.18)), float(p.get("bump_m", 0.22)))
	for i in 4:
		suspension.compression[i] = q_nom[i]
		suspension.compression_velocity[i] = u[i] - du_twist[i]
		suspension.filtered_arb_travel[i] = q_nom[i]
		suspension.contact_active[i] = apoyo_previo[i]
	_rhs.fill(0.0)
	for i in 4:
		var axis := 6 + i
		_rhs[axis] = 1.0
		var response: Array[float] = _axis_response[i]
		_solve_chol(_rhs, response)
		_rhs[axis] = 0.0
		_relative_mass[i] = 1.0 / maxf(response[axis], 1.0e-9)
	var Fs: Array[float] = suspension.suspension_forces_1dof(t_h, _relative_mass)
	# Resistencia al droop semi-implícita usando la masa relativa 1DOF (_relative_mass[i]).
	for i in 4:
		var p2: Dictionary = suspension.axle_parameters[i]
		var droop := float(p2.get("droop_m", 0.18))
		if q_nom[i] < -droop + 0.025:
			var pen := (-droop + 0.025) - q_nom[i]
			var m_eff_d := maxf(float(_relative_mass[i]), 1.0)
			var k_droop := float(p2.get("spring_rate", 20000.0)) * 6.0
			var c_droop := float(p2.get("rebound_damping", 2000.0)) * 2.5
			var k_droop_eff := k_droop / (1.0 + (k_droop * t_h * t_h) / m_eff_d)
			var c_droop_eff := c_droop / (1.0 + (c_droop * t_h) / m_eff_d)
			var droop_delta := -(k_droop_eff * pen - c_droop_eff * minf(u[i], 0.0))
			Fs[i] = float(Fs[i]) + droop_delta
	# Avanzar 1DOF de torsión estructural del chasis (subchasis delantero vs trasero).
	if chassis_torsion_enabled:
		var m_roll_f := (float(Fs[0]) - float(Fs[1])) * (0.5 * _track_front_m)
		var m_roll_r := (float(Fs[2]) - float(Fs[3])) * (0.5 * _track_rear_m)
		var t_twist_ext := 0.5 * (m_roll_f - m_roll_r)
		var k_tw := maxf(chassis_torsion_stiffness_nm_per_rad, 10000.0)
		var i_tw := maxf(chassis_torsion_inertia_kg_m2, 5.0)
		var c_tw := 2.0 * sqrt(k_tw * i_tw) * clampf(chassis_torsion_damping_ratio, 0.05, 1.5)
		var k_f_roll := (float(suspension.axle_parameters[0].get("spring_rate", 20000.0)) + 2.0 * suspension.front_arb_stiffness_n_per_m) * (0.125 * _track_front_m * _track_front_m)
		var k_r_roll := (float(suspension.axle_parameters[2].get("spring_rate", 20000.0)) + 2.0 * suspension.rear_arb_stiffness_n_per_m) * (0.125 * _track_rear_m * _track_rear_m)
		var k_series := k_tw + k_f_roll + k_r_roll
		var denom_tw := i_tw + t_h * c_tw + t_h * t_h * k_series
		var acc_tw := (t_twist_ext - k_tw * chassis_twist_rad - c_tw * chassis_twist_vel_rad_s) / maxf(denom_tw, 1.0e-6)
		chassis_twist_vel_rad_s += acc_tw * t_h
		chassis_twist_rad = clampf(chassis_twist_rad + chassis_twist_vel_rad_s * t_h, -0.08, 0.08)

	spring_forces_n = Fs
	for i in 4:
		last_damper_requested_n[i] = suspension.last_damper_explicit_n[i]
		last_damper_applied_n[i] = suspension.last_damper_forces_n[i]
		last_damper_impulse_ns[i] += last_damper_applied_n[i] * t_h
		var spring_impulse := Fs[i] * t_h
		_spring_impulse_ns[i] += spring_impulse
		_suspension_axial_impulse_ns[i] -= spring_impulse * e.dot(_trace_axis)
	# Q generalizado.
	var Qv := tick_m_s * tick_grav + F_body
	var IwOm := _mat3_vec(_inertia_before, om)
	var gyro := om.cross(IwOm)
	var Qt := -gyro + T_body
	for i in 4:
		var r := tick_r[i]
		var e_i := tick_e_wheel[i]
		var bias := om.cross(om.cross(r)) + om.cross(e_i * u[i]) * 2.0
		var force := m_unsprung[i] * (tick_grav - bias)
		Qv += force
		Qt += r.cross(force)
		_rhs[6 + i] = e_i.dot(force) - Fs[i]
	for i in 3:
		_rhs[i] = Qv[i]
		_rhs[3 + i] = Qt[i]
	_solve_chol(_rhs, _response)
	for k in 10:
		w_free[k] = w[k] + t_h * _response[k]


func solve_normal(h: float) -> void:
	var hh := maxf(h, 0.00001)
	for k in 10:
		_w_rad[k] = w_free[k]
	for i in 4:
		s_Jrad[i] = 0.0
		s_Fz[i] = 0.0
		s_defl[i] = 0.0
		s_diss[i] = 0.0
		if not t_hit[i]:
			radial_states[i] = {}
			continue
		_fill_normal_row(tick_r[i], tick_e_wheel[i], t_n[i], i)
		var G: Array[float] = _normal_rows[i]
		var response: Array[float] = _normal_response[i]
		_solve_chol(G, response)
		var Kn := maxf(_dot10(G, response), 1.0e-9)
		s_Kn[i] = Kn
		var H := C_pred + tick_r[i]
		var delta := float(t_delta0[i]) - float(t_n[i].dot((H - t_H0[i]) - t_road_vel[i] * t_elapsed))
		_normal_deflection[i] = delta
		_normal_road_speed[i] = t_n[i].dot(t_road_vel[i])
		var v_free := _dot10(G, w_free) - _normal_road_speed[i]
		var mi := maxf(float(m_unsprung[i]), 1.0)
		var rs: Dictionary = t_radial_state[i]
		var v_scale := float(radial_viscous_scale)
		var J := 0.0
		var dfin := maxf(delta - hh * v_free, 0.0)
		if dfin > 0.0:
			var Jmax := maxf((delta / hh - v_free) / Kn, 0.0)
			var lo := 0.0
			var hi := Jmax
			for it in 48:
				var mid := 0.5 * (lo + hi)
				var v_mid := v_free + Kn * mid
				var d_mid := maxf(delta - hh * v_mid, 0.0)
				var c_mid := clampf(-v_mid, -12.0, 12.0)
				var f_mid := TireRadialModel.prepared_force_n(rs, mi, d_mid, c_mid, v_scale)
				var res := mid - hh * f_mid
				if res >= 0.0:
					hi = mid
				else:
					lo = mid
				if hi - lo <= RADIAL_BISECTION_REL_TOL * maxf(absf(lo), 1.0):
					break
			J = 0.5 * (lo + hi)
		s_Jrad[i] = maxf(J, 0.0)
		var v_fin := v_free + Kn * float(s_Jrad[i])
		var d_fin := maxf(delta - hh * v_fin, 0.0)
		var c_fin := clampf(-v_fin, -12.0, 12.0)
		var evf := TireRadialModel.evaluate_prepared(rs, mi, d_fin, c_fin, v_scale)
		s_defl[i] = d_fin
		s_diss[i] = float(evf.get("dissipation_w", 0.0))
		radial_states[i] = evf
		for k in 10:
			_w_rad[k] += response[k] * s_Jrad[i]

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
			radial_states[i] = {}
		var response: Array[float] = _normal_response[i]
		for k in 10:
			w_normal[k] += response[k] * impulse


func contact_patch_position(wheel: int, initial_point: Vector3) -> Vector3:
	var road_displacement := t_road_vel[wheel] * t_elapsed
	var hub_displacement := C_pred + tick_r[wheel] - t_H0[wheel]
	return initial_point + road_displacement + (hub_displacement - road_displacement).slide(t_n[wheel])


func apply_tangential(J_tang: Array[float]) -> void:
	_solve_chol(J_tang, _response)
	for k in 10:
		w_cand[k] = w_normal[k] + _response[k]


func solve_hard_stops(h: float) -> void:
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
	var Iw_jolt_new := _inertia_world_diag(R_pred, tick_inertia_diag) if has_full_inertia_tensor else _inertia_world(R_pred, tick_inertia_diag)
	var Iw_jolt_old := _jolt_inertia_before if has_full_inertia_tensor else Iw_old
	acc_L += _mat3_vec(Iw_jolt_new, om_new) - _mat3_vec(Iw_jolt_old, om_old)
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
	for i in 4:
		var mean_F := float(acc_Fz[i]) / dtt
		var mean_d := float(acc_defl[i]) / dtt
		var mean_s := float(acc_diss[i]) / dtt
		radial_deflection_m[i] = mean_d
		radial_dissipation_w[i] = mean_s

		var p: Dictionary = suspension.axle_parameters[i] if i < suspension.axle_parameters.size() else {}
		var qn := clampf(q[i], -float(p.get("droop_m", 0.18)), float(p.get("bump_m", 0.22)))
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
		last_tick_trace[i] = {
			"chassis_vel": [_trace_chassis_velocity.x, _trace_chassis_velocity.y, _trace_chassis_velocity.z],
			"hub_vel": [start_velocity.x, start_velocity.y, start_velocity.z],
			"hub_mass_kg": m_unsprung[i],
			"pre_hub_vel_axial": start_velocity.dot(_trace_axis),
			"post_hub_vel_axial": end_velocity.dot(_trace_axis),
			"J_susp_ns": _suspension_axial_impulse_ns[i],
			"J_radial_ns": _contact_axial_impulse_ns[i],
			"contact_vertical_impulse_ns": _contact_vertical_impulse_ns[i],
			"J_gravity_ns": gravity_impulse,
			"J_sum_known_ns": _suspension_axial_impulse_ns[i] + _contact_axial_impulse_ns[i] + gravity_impulse,
			"tick_id": tick_sequence,
			"dt_s": dtt,
			"relative_velocity_m_s": u[i],
			"damper_requested_n": last_damper_requested_n[i],
			"damper_applied_n": last_damper_applied_n[i],
			"damper_impulse_ns": last_damper_impulse_ns[i],
			"internal_force_n": spring_forces_n[i],
			"internal_impulse_ns": _spring_impulse_ns[i],
			"radial_F_mean_n": mean_F,
			"radial_J_imp_ns": _radial_impulse_ns[i],
		}
