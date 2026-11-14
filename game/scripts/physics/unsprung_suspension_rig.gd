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
## Traza de diagnóstico de impulsos (segunda prueba Fulvia 60 Hz): registro
## por rueda y tick leído en solve(), sin efecto físico. Permite cerrar el
## balance axial m·Δv frente a ΣJ por término entre ticks consecutivos.
var impulse_trace: Array[Dictionary] = [{ }, { }, { }, { }]
## Multiplicador de diagnóstico del término viscoso radial (segunda prueba):
## 1.0 = producción (bit-idéntico). La sonda lo pone a 0.0 en una variante
## para aislar el aporte viscoso conservando elástica, tope y unilateralidad.
## No se reinicia en reset_at para que la sonda lo fije una vez por pasada.
var radial_viscous_scale := 1.0
## Paso radial implícito (tercera prueba, variante de sonda): false =
## producción (fuerza instantánea). true = impulso normal unilateral del
## intervalo desde la deformación y velocidad predichas al final del paso,
## aplicado al buje una sola vez por tick como fuerza equivalente J/dt.
var radial_implicit_enabled := false
## Subpasos acoplados (quinta prueba, solo sonda): 1 = producción.
## 3/6 = integrador diagnóstico con N subpasos por tick de Jolt a 60 Hz
## (paso efectivo 180/360 Hz). Predice chasis (traslación) y bujes (eje de
## guía) con las mismas leyes de fuerza, acumula impulsos con el intervalo
## de cada subpaso y los transfiere una vez por tick a los cuerpos de Jolt.
## La orientación y la velocidad angular se congelan en el tick; la reacción
## de las juntas NO se predice (va al residual). Tiene precedencia sobre el
## paso radial implícito (avisa y usa radial explícito dentro del subpaso).
var coupled_substeps := 1
## Fz normal por rueda y subpaso del último tick (alimenta el bucle tangencial
## del neumático con la Fz de ese subpaso). Recorrido físico por subpaso.
var substep_loads_n: Array = [[], [], [], []]
var substep_defl_m: Array = [[], [], [], []]
## Traza por subpaso del último tick (diagnóstico Q5): un dict por rueda con
## arrays de N valores (travel, vel_rel, comp, damper, elastic, bump, arb,
## droop, defl, Fz, loaded) más J acumulados e impulsos transferidos.
var substep_trace: Array = []
## Predicción de fin de tick anterior (para error predicho vs observado en el
## siguiente solve): {tick_seq, hub_v_axial: [], chassis_v, hub_travel: []}.
var last_predicted := {}
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


## Impulso radial implícito (tercera prueba, variante de sonda): raíz acotada
## de J = dt·cos·F(δf, cf) con δf = max(0, δ0 − dt·vf), cf = −vf,
## vf = v_libre + J/m. v en separación (+up axial, positiva al separar);
## c en compresión (positiva al cerrar). v_libre incluye los impulsos
## conocidos de suspensión y gravedad. F es la curva radial vigente (misma
## elástica, tope y unilateralidad) evaluada por el llamante vía Callable.
## Si el contacto se abre dentro del paso (δf(0) <= 0), J = 0.
## Devuelve {impulse_ns, iterations, fallback, opening}.
static func solve_radial_impulse(
	hub_mass_kg: float,
	dt_s: float,
	cos_angle: float,
	deflection_0: float,
	separation_0: float,
	known_impulse_ns: float,
	force_at: Callable,
) -> Dictionary:
	var m := maxf(float(hub_mass_kg), 1.0)
	var dt := maxf(float(dt_s), 0.00001)
	var cos_a := clampf(float(cos_angle), 0.25, 1.0)
	var d0 := maxf(float(deflection_0), 0.0)
	var v_free := float(separation_0) + float(known_impulse_ns) / m
	# Apertura dentro del paso: aun sin impulso se separaría hasta δ <= 0.
	if d0 - dt * v_free <= 0.0:
		return {"impulse_ns": 0.0, "iterations": 0, "fallback": false, "opening": true}
	var lo := 0.0
	var f_lo: float = dt * cos_a * float(force_at.call(d0 - dt * v_free, -v_free))
	var hi: float = maxf(f_lo + m * maxf(0.0, -v_free), 1.0) + 1.0
	var grow := 0
	while grow < 60:
		var v_hi := v_free + hi / m
		var f_hi: float = dt * cos_a * float(force_at.call(maxf(d0 - dt * v_hi, 0.0), -v_hi))
		if f_hi - hi <= 0.0:
			break
		hi *= 2.0
		grow += 1
		if hi > dt * 2000000.0:
			return {"impulse_ns": f_lo, "iterations": grow, "fallback": true, "opening": false}
	if grow >= 60:
		return {"impulse_ns": f_lo, "iterations": grow, "fallback": true, "opening": false}
	var iters := 0
	for k in 48:
		var mid := 0.5 * (lo + hi)
		var v_mid := v_free + mid / m
		var f_mid: float = dt * cos_a * float(force_at.call(maxf(d0 - dt * v_mid, 0.0), -v_mid))
		if f_mid - mid >= 0.0:
			lo = mid
		else:
			hi = mid
		iters += 1
	return {"impulse_ns": 0.5 * (lo + hi), "iterations": iters, "fallback": false, "opening": false}


func substep_count() -> int:
	return maxi(1, int(coupled_substeps))


func substep_load(wheel: int, k: int) -> float:
	if wheel < 0 or wheel >= substep_loads_n.size():
		return 0.0
	var arr: Array = substep_loads_n[wheel]
	if arr.is_empty():
		return 0.0
	return float(arr[clampi(k, 0, arr.size() - 1)])


func substep_defl(wheel: int, k: int) -> float:
	if wheel < 0 or wheel >= substep_defl_m.size():
		return 0.0
	var arr: Array = substep_defl_m[wheel]
	if arr.is_empty():
		return 0.0
	return float(arr[clampi(k, 0, arr.size() - 1)])


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
		# Condicionar la inercia rotacional del buje (Jolt Constraint Stability):
		# los 3 ejes angulares están bloqueados en Generic6DOFJoint3D; un radio mayor
		# evita un ratio de inercia ~10,000:1 frente al chasis sin alterar hub.mass.
		var shape_node := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.45
		shape_node.shape = shape
		hub.inertia = Vector3.ONE * (maxf(masses[i], 1.0) * 0.25)
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
		impulse_trace[i] = { }
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


## Integrador acoplado por subpasos (quinta prueba, solo sonda).
## N subpasos por tick de Jolt (h = dt/N; N=3 → 180 Hz, N=6 → 360 Hz).
## Predice chasis (traslación) y bujes (restringidos al eje de la guía) con
## las mismas leyes de fuerza de producción (muelle, digresiva, topes, ARB,
## radial explícito + tope de llanta, unilateralidad). Soporte: consulta
## ShapeCast del tick congelada + actualización analítica de la distancia
## desde la pose predicha; apertura declarada cuando la deflexión llega a 0;
## el recontacto se resuelve en la consulta del tick siguiente (retardo
## acotado a 1 tick, igual que producción). Orientación y velocidad angular
## congeladas en el tick; la reacción de las juntas NO se predice (residual).
## Acumula impulsos lineales (chasis y bujes) y angulares (chasis) con el
## intervalo h y los transfiere una vez por tick como fuerza/par equivalente.
## La gravedad se incluye en la predicción pero NO en la transferencia
## (Jolt la aplica por su cuenta); el residual la descuenta analíticamente.
## Tiene precedencia sobre radial_implicit_enabled (avisa y usa explícito).
func solve_coupled(
	state: PhysicsDirectBodyState3D,
	suspension: VehicleSuspensionModel,
	contacts: Array[Dictionary],
	radii: Array[float],
	domains: Dictionary,
	thermal: VehicleThermalModel,
) -> Array[float]:
	var dt := maxf(state.step, 0.00001)
	var n := maxi(2, int(coupled_substeps))
	var h := dt / float(n)
	tick_sequence += 1
	if radial_implicit_enabled:
		push_warning("solve_coupled: radial implícito subordinado al subpaso explícito")
	var up := state.transform.basis.y.normalized()
	var R0: Basis = state.transform.basis
	var Pc0: Vector3 = state.transform.origin
	var omega: Vector3 = state.angular_velocity
	var com_l: Vector3 = chassis.center_of_mass
	var chassis_mass := maxf(chassis.mass, 1.0)
	var grav_mag := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.80665))
	var grav := Vector3(0.0, -grav_mag, 0.0)
	var grav_axial := grav.dot(up)
	var tires: Dictionary = domains.get("tires", { }).get("tires", { })
	# Estado medido al inicio (resincronización desde Jolt cada tick).
	var hub_mass: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var hub_pos0: Array[Vector3] = []
	var hub_vel0: Array[Vector3] = []
	var s_meas: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var v_meas: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		hub_mass[i] = maxf(hubs[i].mass, 1.0)
		var hs := PhysicsServer3D.body_get_direct_state(hubs[i].get_rid())
		var hp: Vector3 = hs.transform.origin if hs != null else hubs[i].global_position
		var hv: Vector3 = hs.linear_velocity if hs != null else hubs[i].linear_velocity
		hub_pos0.append(hp)
		hub_vel0.append(hv)
		var neutral0: Vector3 = state.transform * neutral_positions[i]
		s_meas[i] = (hp - neutral0).dot(up)
		var anchor_v0: Vector3 = state.linear_velocity + omega.cross(neutral0 - (state.transform * com_l))
		v_meas[i] = (hv - anchor_v0).dot(up)
		compression_physical_m[i] = s_meas[i]
		suspension.compression[i] = clampf(s_meas[i], -float(suspension.axle_parameters[i].droop_m), float(suspension.axle_parameters[i].bump_m))
		suspension.compression_velocity[i] = v_meas[i]
		suspension.filtered_arb_travel[i] = suspension.compression[i]
		suspension.initialized[i] = true
		suspension.previous_samples[i] = true
		suspension.geometric_contact[i] = bool(contacts[i].get("hit", false))
		suspension.contact_active[i] = bool(contacts[i].get("hit", false))
	# Congelado del tick: suportes, normales y estado térmico.
	var hit: Array[bool] = [false, false, false, false]
	var nrm: Array[Vector3] = [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]
	var cos_a: Array[float] = [1.0, 1.0, 1.0, 1.0]
	var dist_0: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var road_vel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var press_kpa: Array[float] = [180.0, 180.0, 180.0, 180.0]
	var carc_c: Array[float] = [25.0, 25.0, 25.0, 25.0]
	var opt_c: Array[float] = [60.0, 60.0, 60.0, 60.0]
	for i in 4:
		hit[i] = bool(contacts[i].get("hit", false))
		if hit[i]:
			var nn: Vector3 = (contacts[i].normal as Vector3).normalized()
			nrm[i] = nn
			cos_a[i] = clampf(nn.dot(up), 0.25, 1.0)
			dist_0[i] = float(contacts[i].get("distance", 0.0))
			var collider: Object = contacts[i].get("collider")
			if collider is RigidBody3D:
				var rb := collider as RigidBody3D
				road_vel[i] = rb.linear_velocity + rb.angular_velocity.cross((contacts[i].position as Vector3) - rb.global_position)
		var ts: Dictionary = thermal.get_tire_thermal_state_snapshot(i)
		press_kpa[i] = float(ts.get("pressure_kpa_gauge", 180.0))
		carc_c[i] = float(ts.get("carcass_c", 25.0))
		opt_c[i] = float(thermal.optimal_carcass_temperature(i))
	# Estado predicho (local al tick).
	var Pc: Vector3 = Pc0
	var Vc: Vector3 = state.linear_velocity
	var zh: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var vh: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		zh[i] = hub_pos0[i].dot(up)
		vh[i] = hub_vel0[i].dot(up)
	# Acumuladores de impulso (sin gravedad; Jolt la aplica).
	var J_hub: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var J_chas_lin := Vector3.ZERO
	var J_ang := Vector3.ZERO
	var J_susp_acc: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var J_rad_acc: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var pre_anchor_axial: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		var anch0: Vector3 = state.transform * neutral_positions[i]
		var com0: Vector3 = state.transform * com_l
		pre_anchor_axial[i] = (state.linear_velocity + omega.cross(anch0 - com0)).dot(up)
	var sub_rows: Array = []
	for w in 4:
		sub_rows.append({"travel": [], "vel_rel": [], "comp": [], "damper_app": [], "damper_req": [], "elastic": [], "bump": [], "arb": [], "droop": [], "defl": [], "Fz": [], "loaded": []})
	var any_loaded := [false, false, false, false]
	var mean_F: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var last_internal: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var last_comp: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var last_vel: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var last_defl: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var last_F: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var last_elastic: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var last_damp_app: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var last_damp_req: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var last_bump: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var last_arb: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var last_droop: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var loads_acc: Array = [[], [], [], []]
	var defls_acc: Array = [[], [], [], []]
	var clamp_events := [0, 0, 0, 0]
	for k in n:
		# Anclajes predichos y cinemática relativa axial.
		var s_pred: Array[float] = [0.0, 0.0, 0.0, 0.0]
		var u_rel: Array[float] = [0.0, 0.0, 0.0, 0.0]
		var anchor_ax: Array[float] = [0.0, 0.0, 0.0, 0.0]
		var comp_in: Array[float] = [0.0, 0.0, 0.0, 0.0]
		for i in 4:
			var anch: Vector3 = Pc + R0 * neutral_positions[i]
			var com_w: Vector3 = Pc + R0 * com_l
			var anch_v: Vector3 = Vc + omega.cross(anch - com_w)
			anchor_ax[i] = anch_v.dot(up)
			s_pred[i] = zh[i] - anch.dot(up)
			u_rel[i] = vh[i] - anchor_ax[i]
			var dl := -float(suspension.axle_parameters[i].droop_m)
			var bl := float(suspension.axle_parameters[i].bump_m)
			comp_in[i] = clampf(s_pred[i], dl, bl)
			suspension.compression[i] = comp_in[i]
			suspension.compression_velocity[i] = u_rel[i]
			suspension.filtered_arb_travel[i] = comp_in[i]
		var forces: Array = suspension.suspension_forces()
		for i in 4:
			var p: Dictionary = suspension.axle_parameters[i]
			var elastic_f: float = suspension.last_elastic_forces_n[i]
			var damp_raw: float = suspension.last_damper_forces_n[i]
			var bump_f: float = suspension.last_bump_forces_n[i]
			var arb_f: float = float(forces[i]) - elastic_f - damp_raw - bump_f
			var damp_app := damp_raw
			var clamped := false
			if damper_impulse_limit_enabled and absf(u_rel[i]) > 1.0e-6 and absf(damp_raw) > 1.0e-9:
				var sum_inv := 1.0 / chassis_mass + 1.0 / hub_mass[i]
				var max_damp := DAMPER_IMPULSE_LIMIT_FRACTION * absf(u_rel[i]) / (h * sum_inv)
				if absf(damp_raw) > max_damp:
					damp_app = signf(damp_raw) * max_damp
					clamped = true
					clamp_events[i] = int(clamp_events[i]) + 1
			var droop_delta := 0.0
			if comp_in[i] < -float(p.droop_m) + 0.025:
				var pen := (-float(p.droop_m) + 0.025) - comp_in[i]
				droop_delta = -(float(p.spring_rate) * 6.0 * pen - float(p.rebound_damping) * 2.5 * minf(u_rel[i], 0.0))
			var internal: float = float(forces[i]) + (damp_app - damp_raw) + droop_delta
			# Radial explícito de producción sobre el estado predicho.
			var defl := 0.0
			var F_n := 0.0
			var damp_c := 0.0
			var rim_f := 0.0
			var elas_f := 0.0
			var visc_f := 0.0
			if hit[i]:
				var dist_pred: float = dist_0[i] - (Pc - Pc0).dot(up)
				var road_comp: float = float(radii[i]) - dist_pred
				defl = maxf((road_comp - s_pred[i]) * cos_a[i], 0.0)
				var cspeed := clampf(-(u_rel[i] - road_vel[i].dot(up)) * cos_a[i], -12.0, 12.0)
				var axle_str := "front" if i < 2 else "rear"
				var radial := TireRadialModel.evaluate(tires, axle_str, press_kpa[i], carc_c[i], hub_mass[i], defl, cspeed, opt_c[i], float(radial_viscous_scale))
				F_n = maxf(float(radial.force_n), 0.0)
				damp_c = float(radial.get("damping_ns_m", 0.0))
				rim_f = float(radial.get("rim_stop_force_n", 0.0))
				var eff := cspeed if cspeed >= 0.0 else cspeed * 0.45
				visc_f = damp_c * clampf(eff, -8.0, 8.0) * float(radial_viscous_scale)
				if F_n > 0.0 and defl > 0.0:
					elas_f = F_n - visc_f
				radial_states[i] = radial
				radial_dissipation_w[i] = float(radial.get("dissipation_w", 0.0))
			# Dinámica predicha (semi-implícita): el buje solo se mueve en el
			# eje de la guía; el chasis solo traslada (rotación congelada).
			var f_hub_ax := -internal + F_n * cos_a[i]
			var lat_vec: Vector3 = nrm[i] * F_n - up * (F_n * cos_a[i])
			var f_chas: Vector3 = up * internal + lat_vec
			vh[i] = vh[i] + (f_hub_ax / hub_mass[i] + grav_axial) * h
			zh[i] = zh[i] + vh[i] * h
			Vc = Vc + (f_chas / chassis_mass + grav) * h
			Pc = Pc + Vc * h
			var mount_k: Vector3 = Pc + R0 * neutral_positions[i]
			var com_k: Vector3 = Pc + R0 * com_l
			J_hub[i] = float(J_hub[i]) + f_hub_ax * h
			J_susp_acc[i] = float(J_susp_acc[i]) + (-internal) * h
			J_rad_acc[i] = float(J_rad_acc[i]) + F_n * cos_a[i] * h
			J_chas_lin = J_chas_lin + f_chas * h
			J_ang = J_ang + (mount_k - com_k).cross(f_chas) * h
			mean_F[i] = float(mean_F[i]) + F_n
			if F_n > 0.0:
				any_loaded[i] = true
			(sub_rows[i] as Dictionary)["travel"].append(s_pred[i])
			(sub_rows[i] as Dictionary)["vel_rel"].append(u_rel[i])
			(sub_rows[i] as Dictionary)["comp"].append(comp_in[i])
			(sub_rows[i] as Dictionary)["damper_app"].append(damp_app)
			(sub_rows[i] as Dictionary)["damper_req"].append(damp_raw)
			(sub_rows[i] as Dictionary)["elastic"].append(elastic_f)
			(sub_rows[i] as Dictionary)["bump"].append(bump_f)
			(sub_rows[i] as Dictionary)["arb"].append(arb_f)
			(sub_rows[i] as Dictionary)["droop"].append(droop_delta)
			(sub_rows[i] as Dictionary)["defl"].append(defl)
			(sub_rows[i] as Dictionary)["Fz"].append(F_n)
			(sub_rows[i] as Dictionary)["loaded"].append(F_n > 0.0)
			(loads_acc[i] as Array).append(F_n)
			(defls_acc[i] as Array).append(defl)
			last_internal[i] = internal
			last_comp[i] = comp_in[i]
			last_vel[i] = u_rel[i]
			last_defl[i] = defl
			last_F[i] = F_n
			last_elastic[i] = elastic_f
			last_damp_app[i] = damp_app
			last_damp_req[i] = damp_raw
			last_bump[i] = bump_f
			last_arb[i] = arb_f
			last_droop[i] = droop_delta
			last_damper_requested_n[i] = damp_raw
			last_damper_applied_n[i] = damp_app
			last_damper_clamped[i] = clamped or bool(last_damper_clamped[i])
			if clamped:
				damper_clip_events[i] = int(damper_clip_events[i]) + 1
			last_damper_impulse_ns[i] = damp_app * h
	# Transferencia única por tick como fuerza/par equivalente J/dt.
	for i in 4:
		var hub := hubs[i]
		var hs := PhysicsServer3D.body_get_direct_state(hub.get_rid())
		var f_eq: Vector3 = up * (float(J_hub[i]) / dt)
		if hs != null:
			hs.apply_central_force(f_eq)
		else:
			hub.apply_central_force(f_eq)
	state.apply_central_force(J_chas_lin / dt)
	state.apply_torque(J_ang / dt)
	# Publicación de fin de tick (último subpaso) para trazas y vehículo.
	var normal_loads: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		suspension.compression[i] = last_comp[i]
		suspension.compression_velocity[i] = last_vel[i]
		suspension.filtered_arb_travel[i] = last_comp[i]
		compression_physical_m[i] = zh[i] - (Pc + R0 * neutral_positions[i]).dot(up)
		radial_deflection_m[i] = last_defl[i]
		spring_forces_n[i] = last_internal[i]
		suspension.last_elastic_forces_n[i] = last_elastic[i]
		suspension.last_damper_forces_n[i] = last_damp_req[i]
		suspension.last_bump_forces_n[i] = last_bump[i]
		mean_F[i] = float(mean_F[i]) / float(n)
		normal_loads[i] = mean_F[i]
		suspension.contact_active[i] = mean_F[i] > 0.0
		substep_loads_n[i] = (loads_acc[i] as Array).duplicate()
		substep_defl_m[i] = (defls_acc[i] as Array).duplicate()
		var tr: Dictionary = impulse_trace[i]
		tr["tick_seq"] = tick_sequence
		tr["dt_s"] = dt
		tr["hub_mass_kg"] = hub_mass[i]
		tr["up"] = [up.x, up.y, up.z]
		tr["pre_hub_vel_axial"] = hub_vel0[i].dot(up)
		tr["pre_anchor_vel_axial"] = pre_anchor_axial[i]
		tr["pre_chassis_vel_axial"] = state.linear_velocity.dot(up)
		tr["hit"] = hit[i]
		tr["contact_loaded_final"] = mean_F[i] > 0.0
		tr["deflection_m"] = last_defl[i]
		tr["radial_force_n"] = last_F[i]
		tr["radial_F_mean_n"] = mean_F[i]
		tr["radial_J_imp_ns"] = float(J_rad_acc[i])
		tr["susp_elastic_n"] = last_elastic[i]
		tr["susp_damper_req_n"] = last_damp_req[i]
		tr["susp_damper_app_n"] = last_damp_app[i]
		tr["susp_bump_n"] = last_bump[i]
		tr["susp_arb_n"] = last_arb[i]
		tr["susp_droop_n"] = last_droop[i]
		tr["susp_internal_n"] = last_internal[i]
		tr["hub_susp_axial_n"] = 0.0
		tr["hub_radial_axial_n"] = 0.0
		tr["hub_gravity_axial_n"] = grav_axial * hub_mass[i]
		tr["J_susp_ns"] = float(J_susp_acc[i])
		tr["J_radial_ns"] = float(J_rad_acc[i])
		tr["J_gravity_ns"] = grav_axial * hub_mass[i] * dt
		tr["J_sum_known_ns"] = float(J_susp_acc[i]) + float(J_rad_acc[i]) + grav_axial * hub_mass[i] * dt
		tr["substep_mode"] = true
		tr["substep_n"] = n
	# Traza por subpaso + predicción para el error del tick siguiente.
	substep_trace = [{"tick_seq": tick_sequence, "dt": dt, "h": h, "rows": sub_rows, "J_chassis_lin": [J_chas_lin.x, J_chas_lin.y, J_chas_lin.z], "J_chassis_ang": [J_ang.x, J_ang.y, J_ang.z]}]
	var pred_hub_v: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var pred_travel: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		var anch_end: Vector3 = Pc + R0 * neutral_positions[i]
		pred_hub_v[i] = vh[i]
		pred_travel[i] = zh[i] - anch_end.dot(up)
	# Error predicho vs observado (usa la predicción del tick anterior).
	if not last_predicted.is_empty() and int(last_predicted.get("tick_seq", -2)) == tick_sequence - 1:
		var pv: Array = last_predicted.get("hub_v_axial", [])
		var pcv: float = float(last_predicted.get("chassis_v_axial", 0.0))
		var pt: Array = last_predicted.get("hub_travel", [])
		for i in 4:
			var tr2: Dictionary = impulse_trace[i]
			tr2["pred_err_hub_v"] = v_meas[i] - float(pv[i] if i < pv.size() else 0.0)
			tr2["pred_err_chassis_v"] = state.linear_velocity.dot(up) - pcv
			tr2["pred_err_hub_travel"] = s_meas[i] - float(pt[i] if i < pt.size() else 0.0)
	last_predicted = {
		"tick_seq": tick_sequence,
		"hub_v_axial": pred_hub_v.duplicate(),
		"chassis_v_axial": Vc.dot(up),
		"hub_travel": pred_travel.duplicate(),
	}
	# Traza comparable por tick Jolt (convención §5/F3).
	for i in 4:
		last_tick_trace[i] = {
			"tick_id": tick_sequence,
			"dt_s": dt,
			"chassis_pos": [state.transform.origin.x, state.transform.origin.y, state.transform.origin.z],
			"chassis_vel": [state.linear_velocity.x, state.linear_velocity.y, state.linear_velocity.z],
			"chassis_angvel": [state.angular_velocity.x, state.angular_velocity.y, state.angular_velocity.z],
			"hub_pos": [hub_pos0[i].x, hub_pos0[i].y, hub_pos0[i].z],
			"hub_vel": [hub_vel0[i].x, hub_vel0[i].y, hub_vel0[i].z],
			"hub_direct_state": true,
			"anchor_world": [(state.transform * neutral_positions[i]).x, (state.transform * neutral_positions[i]).y, (state.transform * neutral_positions[i]).z],
			"relative_velocity_m_s": v_meas[i],
			"damper_requested_n": last_damp_req[i],
			"damper_applied_n": last_damp_app[i],
			"damper_clamped": bool(last_damper_clamped[i]),
			"damper_impulse_ns": last_damp_app[i] * dt,
			"damper_power_w": last_damp_app[i] * last_vel[i],
			"damper_work_est_j": last_damp_app[i] * last_vel[i] * dt,
			"elastic_force_n": last_elastic[i],
			"internal_force_n": last_internal[i],
			"internal_impulse_ns": last_internal[i] * dt,
		}
	return normal_loads


func solve(
	state: PhysicsDirectBodyState3D,
	suspension: VehicleSuspensionModel,
	contacts: Array[Dictionary],
	radii: Array[float],
	domains: Dictionary,
	thermal: VehicleThermalModel,
) -> Array[float]:
	if int(coupled_substeps) > 1:
		return solve_coupled(state, suspension, contacts, radii, domains, thermal)
	var up := state.transform.basis.y.normalized()
	var com := state.transform * chassis.center_of_mass
	var hub_states: Array[PhysicsDirectBodyState3D] = []
	var hub_positions: Array[Vector3] = []
	var hub_velocities: Array[Vector3] = []
	var neutral_world: Array[Vector3] = []
	## Pre-estado axial para la traza de impulsos (segunda prueba): velocidades
	## proyectadas sobre el eje de guía tomado al inicio del intervalo.
	var pre_hub_axial: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var pre_anchor_axial: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var pre_chassis_axial: float = state.linear_velocity.dot(up)

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
		pre_hub_axial[i] = h_vel.dot(up)
		pre_anchor_axial[i] = body_point_velocity.dot(up)
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
		# Traza de impulsos (segunda prueba): descomposición exacta por término
		# del solver con signo del buje sobre el eje de guía (+up). Permite
		# cerrar m·Δv frente a ΣJ entre ticks consecutivos en la sonda.
		var susp_elastic: float = suspension.last_elastic_forces_n[i]
		var susp_bump: float = suspension.last_bump_forces_n[i]
		var susp_droop_delta := 0.0
		if comp < -droop_m + 0.025:
			var droop_pen := (-droop_m + 0.025) - comp
			susp_droop_delta = -(
				float(p.spring_rate) * 6.0 * droop_pen - float(p.rebound_damping) * 2.5 * minf(rel_vel, 0.0)
			)
		var susp_arb: float = (internal_force_n - susp_droop_delta) - susp_elastic - damper_applied - susp_bump
		var gravity_mag := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.80665))
		var hub_gravity_axial: float = maxf(hub.mass, 1.0) * gravity_mag * Vector3.DOWN.dot(up)
		var hub_susp_axial := -internal_force_n
		impulse_trace[i] = {
			"tick_seq": tick_sequence,
			"dt_s": dt,
			"hub_mass_kg": maxf(hub.mass, 1.0),
			"up": [up.x, up.y, up.z],
			"pre_hub_vel_axial": pre_hub_axial[i],
			"pre_anchor_vel_axial": pre_anchor_axial[i],
			"pre_chassis_vel_axial": pre_chassis_axial,
			"pre_hub_vel": [hub_velocities[i].x, hub_velocities[i].y, hub_velocities[i].z],
			"pre_chassis_vel": [state.linear_velocity.x, state.linear_velocity.y, state.linear_velocity.z],
			"hit": bool(contacts[i].get("hit", false)),
			"contact_loaded_final": false,
			"distance_m": float(contacts[i].get("distance", 0.0)),
			"safe_fraction": float(contacts[i].get("safe_fraction", 0.0)),
			"road_compression_m": 0.0,
			"hub_travel_physical_m": compression_physical_m[i],
			"comp_raw_m": (hub_positions[i] - neutral_world[i]).dot(up),
			"comp_clamped_m": comp,
			"deflection_m": 0.0,
			"compression_speed_raw": 0.0,
			"compression_speed_used": 0.0,
			"pressure_kpa": 0.0,
			"carcass_c": 0.0,
			"optimal_carcass_c": 0.0,
			"radial_elastic_n": 0.0,
			"radial_viscous_full_n": 0.0,
			"radial_viscous_scale": float(radial_viscous_scale),
			"radial_viscous_applied_n": 0.0,
			"radial_rim_stop_n": 0.0,
			"radial_force_n": 0.0,
			"radial_clamped_zero": false,
			"radial_damping_ns_m": 0.0,
			"susp_elastic_n": susp_elastic,
			"susp_damper_req_n": last_damper_requested_n[i],
			"susp_damper_app_n": damper_applied,
			"susp_damper_clamped": last_damper_clamped[i],
			"susp_bump_n": susp_bump,
			"susp_arb_n": susp_arb,
			"susp_droop_n": susp_droop_delta,
			"susp_internal_n": internal_force_n,
			"hub_susp_axial_n": hub_susp_axial,
			"hub_radial_axial_n": 0.0,
			"hub_gravity_axial_n": hub_gravity_axial,
			"J_susp_ns": hub_susp_axial * dt,
			"J_radial_ns": 0.0,
			"J_gravity_ns": hub_gravity_axial * dt,
			"J_sum_known_ns": (hub_susp_axial + hub_gravity_axial) * dt,
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
			float(radial_viscous_scale),
		)
		radial_states[i] = radial
		var tire_force := maxf(float(radial.force_n), 0.0)
		radial_dissipation_w[i] = float(radial.dissipation_w)
		normal_loads[i] = tire_force
		suspension.contact_active[i] = tire_force > 0.0
		# Cierre de la traza de impulsos (segunda prueba): desglose radial y
		# suma axial conocida sobre el mismo eje de guía del intervalo.
		var radial_damping: float = radial.get("damping_ns_m", 0.0)
		var eff_speed := compression_speed if compression_speed >= 0.0 else compression_speed * 0.45
		var viscous_full: float = radial_damping * clampf(eff_speed, -8.0, 8.0)
		var viscous_applied := viscous_full * float(radial_viscous_scale)
		var radial_elastic := 0.0
		if tire_force > 0.0 and deflection > 0.0:
			radial_elastic = tire_force - viscous_applied
		var radial_axial: float = tire_force * cos_angle
		var tr: Dictionary = impulse_trace[i]
		tr["contact_loaded_final"] = tire_force > 0.0
		tr["road_compression_m"] = road_compression
		tr["deflection_m"] = deflection
		tr["compression_speed_raw"] = axial_compression_speed
		tr["compression_speed_used"] = compression_speed
		tr["pressure_kpa"] = float(tire_state.get("pressure_kpa_gauge", 180.0))
		tr["carcass_c"] = float(tire_state.get("carcass_c", 25.0))
		tr["optimal_carcass_c"] = float(thermal.optimal_carcass_temperature(i))
		tr["radial_elastic_n"] = radial_elastic
		tr["radial_viscous_full_n"] = viscous_full
		tr["radial_viscous_applied_n"] = viscous_applied
		tr["radial_rim_stop_n"] = float(radial.get("rim_stop_force_n", 0.0))
		tr["radial_force_n"] = tire_force
		tr["radial_clamped_zero"] = tire_force <= 0.0 and deflection > 0.0
		tr["radial_damping_ns_m"] = radial_damping
		tr["hub_radial_axial_n"] = radial_axial
		tr["J_radial_ns"] = radial_axial * dt
		tr["J_sum_known_ns"] = float(tr["J_susp_ns"]) + radial_axial * dt + float(tr["J_gravity_ns"])
		tr["radial_implicit"] = false
		tr["radial_F_inst_n"] = tire_force
		tr["radial_F_mean_n"] = tire_force
		tr["radial_J_imp_ns"] = radial_axial * dt
		tr["radial_iters"] = 0
		tr["radial_fallback"] = false
		tr["radial_opening"] = false

		# Variante radial implícita (tercera prueba, solo sonda): resuelve el
		# impulso normal unilateral del intervalo con la deformación y la
		# velocidad predichas al final del paso y lo aplica al buje una sola
		# vez por tick como fuerza equivalente J/dt. La carga media alimenta
		# el modelo tangencial (normal_loads). Llamadas repetidas al modelo
		# con la misma pose y velocidad: iteración de función, no subpasos.
		var applied_normal_force := tire_force
		if radial_implicit_enabled:
			var axle_str := "front" if i < 2 else "rear"
			var press_kpa := float(tire_state.get("pressure_kpa_gauge", 180.0))
			var carc_c := float(tire_state.get("carcass_c", 25.0))
			var opt_c := float(thermal.optimal_carcass_temperature(i))
			var hub_m := maxf(hub.mass, 1.0)
			var visc_scale := float(radial_viscous_scale)
			var force_at := func(delta_m: float, speed_m_s: float) -> float:
				var ev := TireRadialModel.evaluate(tires, axle_str, press_kpa, carc_c, hub_m, delta_m, speed_m_s, opt_c, visc_scale)
				return float(ev.get("force_n", 0.0))
			var sep_0 := float(relative_hub_vel.dot(up))
			var known_j: float = float(tr["J_susp_ns"]) + float(tr["J_gravity_ns"])
			var solved := solve_radial_impulse(hub_m, dt, cos_angle, deflection, sep_0, known_j, force_at)
			var j_ax: float = solved["impulse_ns"]
			var f_mean := j_ax / maxf(dt, 0.00001) / cos_angle
			tr["radial_implicit"] = true
			tr["radial_F_mean_n"] = maxf(f_mean, 0.0)
			tr["radial_J_imp_ns"] = j_ax
			tr["radial_iters"] = int(solved["iterations"])
			tr["radial_fallback"] = bool(solved["fallback"])
			tr["radial_opening"] = bool(solved["opening"])
			tr["hub_radial_axial_n"] = j_ax / maxf(dt, 0.00001)
			tr["J_radial_ns"] = j_ax
			tr["J_sum_known_ns"] = float(tr["J_susp_ns"]) + j_ax + float(tr["J_gravity_ns"])
			applied_normal_force = maxf(f_mean, 0.0)
			normal_loads[i] = applied_normal_force
			suspension.contact_active[i] = applied_normal_force > 0.0

		var total_tire_vec := normal * applied_normal_force
		var axial_tire_vec := up * total_tire_vec.dot(up)
		var lateral_normal_vec := total_tire_vec - axial_tire_vec

		if h_state != null:
			h_state.apply_central_force(axial_tire_vec)
		else:
			hub.apply_central_force(axial_tire_vec)
		state.apply_force(lateral_normal_vec, mount_offset)

	return normal_loads
