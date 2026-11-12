class_name UnsprungSuspensionRig
extends RefCounted
## Rig no suspendido §SUSPENSION_CORRECTION_PLAN §§1,5.
## Escritor único del estado físico por tick: `solve()` es la única vía que
## escribe `suspension.compression/compression_velocity/filtered_arb_travel/`
## `contact_active/geometric_contact` durante el tick. La simulación no escribe
## recorrido ni velocidad; en la rama sin impacto solo registra ausencia de
## contacto geométrico.
##
## Juntas (§5, inventario de ejes y límites efectivos): guías verticales.
## - Y lineal: libre entre `-droop-margin` y `+bump+margin`.
## - X/Z lineal: bloqueados a 0 (sin desplazamiento lateral/longitudinal).
## - Angular X/Y/Z: bloqueados a 0 (el giro de rueda lo integra el modelo
##   angular existente, no un cuerpo libre en Jolt).
## Los topes progresivos de compresión se resuelven en la ley de fuerza; los
## límites duros los resuelven estas juntas.

const JOINT_LIMIT_MARGIN_M := 0.03
## Alcance efectivo de extensión (§2): el joint permite
## `droop + JOINT_LIMIT_MARGIN_M` bajo el neutro. Las consultas de contacto
## (tándem y ShapeCast) deben derivar su alcance de este mismo límite para
## no recortar 30 mm de droop real. Distancias referidas al centro neutro.
static func effective_droop_limit_m(droop_m: float) -> float:
	return maxf(float(droop_m), 0.0) + JOINT_LIMIT_MARGIN_M


## Recorrido de consulta desde el neutro: arranque `bump` sobre el neutro
## más extensión efectiva. Mantiene la distancia referida al centro neutro.
static func contact_query_travel_m(bump_m: float, droop_m: float, top_margin_m: float = 0.02) -> Dictionary:
	var bump := maxf(float(bump_m), 0.0) + maxf(float(top_margin_m), 0.0)
	var droop_eff := effective_droop_limit_m(droop_m)
	return {"bump": bump, "droop_effective": droop_eff, "travel": bump + droop_eff}
## Recorte de diagnóstico del impulso del amortiguador (§5, hallazgo F1).
## DESACTIVADO POR DEFECTO: la ruta normal de producción aplica la fuerza de
## la curva digresiva sin recortar. Cuando se activa (solo diagnóstico), recorta
## el componente damper si su impulso invertiría la velocidad relativa del
## tick: |F| <= fracción*|vel|/(dt*(1/M+1/m)).
## Solo recorta el damper (no elástico, topes ni ARB).
## Limitación conocida: la fórmula solo usa masas traslacionales (chasis + hub);
## ignora la inercia rotacional del chasis y el acoplamiento entre esquinas vía
## chasis/ARB. Cualquier propuesta de activarla en producción debe validar
## rotación del chasis y acoplamiento entre esquinas, no solo caída vertical.
const DAMPER_IMPULSE_LIMIT_FRACTION := 0.9

var chassis: RigidBody3D
var hubs: Array[RigidBody3D] = []
var joints: Array[Generic6DOFJoint3D] = []
var neutral_positions: Array[Vector3] = []
var radial_deflection_m: Array[float] = [0.0, 0.0, 0.0, 0.0]
## Recorrido físico del hub sin clampear (H1): desplazamiento real medido
## hub-vs-chasis antes del clamp a [-droop, +bump]. Se usa SOLO para la
## deformación radial del neumático; el resto de consumidores del modelo de
## suspensión siguen leyendo el recorrido limitado (`suspension.compression`).
var compression_physical_m: Array[float] = [0.0, 0.0, 0.0, 0.0]
var radial_dissipation_w: Array[float] = [0.0, 0.0, 0.0, 0.0]
var radial_states: Array[Dictionary] = [{ }, { }, { }, { }]
var spring_forces_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
## Interruptor de diagnóstico (F1): `false` = producción (curva digresiva
## íntegra). `true` = recorte activo para comparativas controladas.
var damper_impulse_limit_enabled := false
## Identificador monotónico de tick Jolt leído por el solver (F3). No se
## reinicia en reset para que el último tick previo al rescate y los primeros
## posteriores sean comparables con un vehículo recién colocado.
var tick_sequence: int = 0
## Traza del último tick (§5/F3): velocidad relativa, fuerza de amortiguador
## solicitada/aplicada, impulso y potencias. Permite comparar ticks de Jolt y
## detectar inversión de velocidad o desfase entre cuerpos. Ver `solve()` para
## la convención de signo y las unidades (W vs J).
var last_tick_trace: Array[Dictionary] = [{ }, { }, { }, { }]
var last_damper_clamped: Array[bool] = [false, false, false, false]
## Fuerza de damper solicitada (curva digresiva) y aplicada (tras recorte
## opcional), por rueda. `suspension.last_damper_forces_n` conserva la
## solicitada; aquí se conserva la aplicada para la traza.
var last_damper_requested_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var last_damper_applied_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var last_damper_impulse_ns: Array[float] = [0.0, 0.0, 0.0, 0.0]
## Contador de eventos de recorte por rueda (diagnóstico F1).
var damper_clip_events: Array[int] = [0, 0, 0, 0]


## Deformación radial desde el recorrido FÍSICO del hub (H1): con
## `road_compression = radio - distancia` (distancia neutro-superficie) y
## `hub_travel` = desplazamiento real del hub (sin clamp), la penetración es
## `(road_compression - hub_travel) * cos`, nunca negativa. Ejemplo: droop
## nominal 180 mm, hub en -210 mm y superficie compatible con centro de rueda
## en -200 mm → road_compression = -200 mm, hub_travel = -210 mm →
## deformación 10 mm y carga positiva. Sin penetración (p. ej. distancia que
## deja road_compression <= hub_travel) la deformación es 0 y la carga 0.
static func radial_deflection_from_travel(
	road_compression_m: float,
	hub_travel_m: float,
	cos_angle: float
) -> float:
	return maxf((float(road_compression_m) - float(hub_travel_m)) * clampf(float(cos_angle), 0.25, 1.0), 0.0)


## Activa/desactiva el recorte de diagnóstico y reinicia contadores.
func set_damper_impulse_limit(enabled: bool) -> void:
	damper_impulse_limit_enabled = enabled
	damper_clip_events = [0, 0, 0, 0]
	for i in 4:
		last_damper_clamped[i] = false


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
		# Eje Y: guía vertical libre en el recorrido. Resto de ejes: límites
		# efectivos inventariados (§5) para que la junta no aporte grados de
		# libertad ocultos.
		joint.set_flag_y(
			Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true
		)
		joint.set_param_y(
			Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,
			-float(suspension.axle_parameters[i].droop_m) - JOINT_LIMIT_MARGIN_M,
		)
		joint.set_param_y(
			Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,
			float(suspension.axle_parameters[i].bump_m) + JOINT_LIMIT_MARGIN_M,
		)
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
		joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
		joints.append(joint)
	print(
		"RALLY_UNSPRUNG_READY ",
		JSON.stringify(
			{ "hub_masses_kg": masses, "sprung_mass_kg": body.mass, "hub_bodies": hubs.size() }
		),
	)


func reset() -> void:
	reset_at(chassis.global_transform)


func reset_at(pose: Transform3D) -> void:
	for i in hubs.size():
		var target_transform := pose * Transform3D(
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
		compression_physical_m[i] = 0.0
		radial_dissipation_w[i] = 0.0
		radial_states[i] = { }
		if i < spring_forces_n.size():
			spring_forces_n[i] = 0.0
		if i < last_tick_trace.size():
			last_tick_trace[i] = { }
		if i < last_damper_clamped.size():
			last_damper_clamped[i] = false
		if i < last_damper_requested_n.size():
			last_damper_requested_n[i] = 0.0
		if i < last_damper_applied_n.size():
			last_damper_applied_n[i] = 0.0
		if i < last_damper_impulse_ns.size():
			last_damper_impulse_ns[i] = 0.0
		if i < damper_clip_events.size():
			damper_clip_events[i] = 0
	# Nota §2: el estado transitorio de la suspensión (recorrido, velocidad,
	# contactos, ARB filtrado) lo limpia FordRallyVehicleSimulation
	# (reset_dynamics / clear_teleport_residual) junto a este reset de hubs,
	# para que la primera muestra tras teletransporte no arrastre el estado
	# previo.


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
		compression_physical_m[i] = raw_comp
		suspension.compression[i] = clampf(raw_comp, droop_limit, bump_limit)
		suspension.compression_velocity[i] = raw_vel
		suspension.filtered_arb_travel[i] = suspension.compression[i]
		suspension.initialized[i] = true
		suspension.previous_samples[i] = true
		# Impacto geométrico (ray/ShapeCast) vs carga positiva (§1): aquí se
		# registra el impacto geométrico; `contact_active` se resuelve abajo
		# a carga radial positiva para conservar la semántica que consume el
		# vehículo (neumático, ARB, HUD, vuelo).
		suspension.geometric_contact[i] = bool(contacts[i].get("hit", false))
		suspension.contact_active[i] = bool(contacts[i].get("hit", false))

	spring_forces_n = suspension.suspension_forces()
	# Recorte de diagnóstico del damper (F1, §5): DESACTIVADO POR DEFECTO.
	# Ruta normal: se aplica la fuerza de la curva digresiva íntegra
	# (`suspension.last_damper_forces_n` = solicitada). Con
	# `damper_impulse_limit_enabled = true` se recorta solo el damper si su
	# impulso invertiría la velocidad relativa del tick:
	# J = F*dt (+ al chasis, − al hub): dvel_rel = −J*(1/M+1/m).
	# Sin inversión: |F| <= fracción*|vel|/(dt*(1/M+1/m)).
	# La fórmula solo usa masas traslacionales; ver limitación en la cabecera.
	tick_sequence += 1
	var dt := maxf(state.step, 0.00001)
	var chassis_mass := maxf(chassis.mass, 1.0)
	for i in 4:
		var rel_vel_clamp: float = suspension.compression_velocity[i]
		var damper_raw: float = suspension.last_damper_forces_n[i]
		last_damper_requested_n[i] = damper_raw
		last_damper_applied_n[i] = damper_raw
		last_damper_clamped[i] = false
		if damper_impulse_limit_enabled and absf(rel_vel_clamp) > 1.0e-6 and absf(damper_raw) > 1.0e-9:
			var hub_mass := maxf(hubs[i].mass, 1.0)
			var sum_inv := 1.0 / chassis_mass + 1.0 / hub_mass
			var max_damper := DAMPER_IMPULSE_LIMIT_FRACTION * absf(rel_vel_clamp) / (dt * sum_inv)
			if absf(damper_raw) > max_damper:
				var clamped := signf(damper_raw) * max_damper
				last_damper_applied_n[i] = clamped
				last_damper_clamped[i] = true
				damper_clip_events[i] += 1
		var applied: float = last_damper_applied_n[i]
		spring_forces_n[i] += applied - damper_raw
		last_damper_impulse_ns[i] = applied * dt
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
			spring_forces_n[i] = internal_force_n

		var spring_force := up * internal_force_n
		var mount_offset := neutral_world[i] - state.transform.origin
		state.apply_force(spring_force, mount_offset)
		if h_state != null:
			h_state.apply_central_force(-spring_force)
		else:
			hub.apply_central_force(-spring_force)
		# Traza comparable por tick Jolt (§5/F3). Todo lo registrado es lo que
		# el solver leyó en ESTA llamada (mismo paso): si chasis y hub
		# respondieran a pasos distintos se vería como velocidad relativa
		# incoherente con el impulso.
		# Convención de signo: eje +Y del chasis (up). `relative_velocity > 0`
		# = compresión (el hub sube respecto al anclaje del chasis).
		# `damper >= 0` en compresión: empuja el chasis hacia +up y el hub
		# hacia −up (se opone al movimiento relativo; `damper` lleva el signo
		# de `relative_velocity` en la curva digresiva).
		# Unidades: `damper_power_w` es potencia instantánea en W
		# (F_aplicada * vel_rel); `damper_work_est_j` es trabajo estimado del
		# tick en J (potencia * dt, Euler explícito; no es la integración
		# interna de Jolt). Impulsos en N·s.
		var damper_applied: float = last_damper_applied_n[i]
		var damper_power_w := damper_applied * rel_vel
		last_tick_trace[i] = {
			"tick_id": tick_sequence,
			"dt_s": dt,
			"chassis_pos": [state.transform.origin.x, state.transform.origin.y, state.transform.origin.z],
			"chassis_vel": [state.linear_velocity.x, state.linear_velocity.y, state.linear_velocity.z],
			"chassis_angvel": [state.angular_velocity.x, state.angular_velocity.y, state.angular_velocity.z],
			"hub_pos": [hub_positions[i].x, hub_positions[i].y, hub_positions[i].z],
			"hub_vel": [hub_velocities[i].x, hub_velocities[i].y, hub_velocities[i].z],
			"hub_direct_state": hub_states[i] != null,
			"anchor_world": [neutral_world[i].x, neutral_world[i].y, neutral_world[i].z],
			"relative_velocity_m_s": rel_vel,
			"damper_requested_n": last_damper_requested_n[i],
			"damper_applied_n": damper_applied,
			"damper_clamped": last_damper_clamped[i],
			"damper_impulse_ns": damper_applied * dt,
			"damper_power_w": damper_power_w,
			"damper_work_est_j": damper_power_w * dt,
			"elastic_force_n": suspension.last_elastic_forces_n[i],
			"internal_force_n": internal_force_n,
			"internal_impulse_ns": internal_force_n * dt,
		}

		radial_deflection_m[i] = 0.0
		radial_dissipation_w[i] = 0.0
		radial_states[i] = { }
		if not bool(contacts[i].get("hit", false)):
			suspension.contact_active[i] = false
			suspension.geometric_contact[i] = false
			continue

		var normal: Vector3 = (contacts[i].normal as Vector3).normalized()
		var cos_angle := clampf(normal.dot(up), 0.25, 1.0)
		var road_compression := radii[i] - float(contacts[i].distance)
		# H1: la deformación usa el recorrido FÍSICO del hub, no el clamp.
		# Con hub en -210 mm y superficie en -200 mm (droop 180): 10 mm.
		var deflection := radial_deflection_from_travel(
			road_compression, compression_physical_m[i], cos_angle
		)
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
			thermal.optimal_carcass_temperature(i),
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
