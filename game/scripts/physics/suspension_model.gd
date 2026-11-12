class_name VehicleSuspensionModel
extends RefCounted
## Modelo de suspensión §SUSPENSION_CORRECTION_PLAN.
##
## Escritor único del estado físico por tick: UnsprungSuspensionRig.solve().
## Nadie más debe escribir `compression`, `compression_velocity`,
## `filtered_arb_travel`, `contact_active` ni `geometric_contact` durante el
## tick. FordRallyVehicleSimulation.step() solo registra la ausencia de
## contacto geométrico en su rama sin impacto (cargas a cero, contactos con
## `hit=false`); la llamada redundante a `set_airborne()` se retiró porque sus
## escrituras quedaban sobrescritas por el rig en el mismo tick.
##
## Contacto geométrico vs carga positiva:
## - `geometric_contact[i]` = el ray/ShapeCast tocó suelo (impacto geométrico).
## - `contact_active[i]` = la ley radial devolvió fuerza positiva
##   (`tire_force > 0`). Es la señal que consumen neumático, ARB, HUD y
##   detección de vuelo. Se conserva su semántica histórica para no alterar
##   las muestras que consume el vehículo.
##
## Filtros heredados (compatibilidad, sin efecto en el cálculo actual):
## - `suspension_filters` se sigue cargando y validando desde
##   `suspension_filters.json`, pero ninguna de sus claves interviene en el
##   cálculo actual por hubs. Claves aceptadas por compatibilidad:
##   `front/arb_travel_filter_tau_s`, `front/damper_velocity_filter_tau_s`,
##   `rear/arb_travel_filter_tau_s`, `rear/damper_velocity_filter_tau_s`,
##   `road_height_filter_tau_s`, `road_height_max_rate_m_s`.
##   La ruta antigua `update_contact()` (ray-distance filtrada) se retiró al
##   confirmar inventario sin consumidores; el recorrido y la velocidad salen
##   de la medida directa hub-vs-chasis del rig, y `filtered_arb_travel` copia
##   ese recorrido sin filtrado temporal (ver §tándem: con geometría activa se
##   revisa cuánto filtrado sigue haciendo falta para no duplicar retardo).
## - Campos retenidos solo por compatibilidad/serialización:
##   `filtered_ray_distance`, `road_height_max_rate_m_s`,
##   `road_height_filter_tau_s`, `initialized`, `previous_samples`.
##   `set_airborne()` queda como legado deprecado sin llamadas activas.

## Coeficiente de progresividad de la ley elástica (§4): factor de RATE, no de
## rigidez tangente. Con `n = travel_delta / max_range`:
## `progressive_rate = k * (1 + RATE * n * |n|)`,
## `F_el = static + progressive_rate * delta`.
## La tangente dentro del clamp es `k * (1 + 3 * RATE * n * |n|)`: con RATE=0.15
## hay +15% de rate a tope de compresión (n=1) y +45% de tangente; en extensión
## (n<0) la tangente cae por debajo de `k`. Fuera del clamp `n` es constante y
## la tangente es `k * (1 + RATE * n * |n|)` (sin factor 3). Si el objetivo
## fuese +15% de tangente, el coeficiente debería ser 0.05. Se conserva la
## curva actual como referencia; ver `elastic_force_reference()`.
const SPRING_PROGRESSIVITY_RATE := 0.15
## Cola exponencial de desasentado: umbral como fracción de la precarga.
const HELPER_ZONE_FRACTION := 0.08

var axle_parameters: Array[Dictionary] = []
var static_corner_loads_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var suspension_filters: Dictionary = { }
var front_arb_stiffness_n_per_m: float = 0.0
var rear_arb_stiffness_n_per_m: float = 0.0
var road_height_max_rate_m_s: float = 0.0
var road_height_filter_tau_s: float = 0.0
var compression: Array[float] = [0.0, 0.0, 0.0, 0.0]
var compression_velocity: Array[float] = [0.0, 0.0, 0.0, 0.0]
var filtered_ray_distance: Array[float] = [0.0, 0.0, 0.0, 0.0]
var filtered_arb_travel: Array[float] = [0.0, 0.0, 0.0, 0.0]
var initialized: Array[bool] = [false, false, false, false]
var previous_samples: Array[bool] = [false, false, false, false]
var contact_active: Array[bool] = [false, false, false, false]
## Impacto geométrico por rueda (ray/ShapeCast con suelo), independiente de
## que la carga radial sea positiva. Lo escribe el rig cada tick.
var geometric_contact: Array[bool] = [false, false, false, false]
## Desglose de la última evaluación de `suspension_forces()` por rueda, para
## traza ( §5 ) y para el límite de impulso del amortiguador en el rig.
var last_elastic_forces_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var last_damper_forces_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var last_bump_forces_n: Array[float] = [0.0, 0.0, 0.0, 0.0]


## Calibración de muelle y reparto (§3):
## - `ride_frequency_hz` tiene prioridad cuando se declara en
##   `suspension.front/rear`. La rigidez explícita `geometry_physical.*.spring_rate_N_per_m`
##   solo actúa como respaldo para derivar la frecuencia por defecto
##   (`sqrt(k/m)/TAU`) cuando no hay frecuencia declarada; en ambos casos la
##   rigidez vigente es `k = m_ref * (TAU * f)^2` con
##   `m_ref = carga_estática_esquina / g`.
## - Por eje se registran (traza RALLY_SUSPENSION_FREQUENCY): masa suspendida
##   de referencia, frecuencia efectiva, wheel rate `k` y coeficientes
##   `c_bump/c_rebound = 2*sqrt(k*m_ref)*zeta*mult`.
## - La precarga es simétrica por eje (`static_load` con reparto solo
##   longitudinal desde COM.z); un desplazamiento lateral de COM no cambia la
##   precarga, aparece como compresión diferencial en equilibrio. La suma de
##   cargas y sus momentos debe contrastarse con peso y COM del vehículo
##   completo; si se ajusta precarga, conservar equilibrio total y
##   longitudinal y frecuencias vigentes dentro de tolerancia.
func configure(
	domains: Dictionary,
	chassis_geometry: Dictionary,
	resolved_mass: Dictionary,
) -> Dictionary:
	var suspension_doc: Dictionary = domains.get("suspension", { }).get("suspension", { })
	var physical: Dictionary = suspension_doc.get("geometry_physical", { })
	var filters_doc: Dictionary = domains.get("suspension_filters", { }).get(
		"suspension_filters",
		{ },
	)
	var front_suspension: Dictionary = physical.get("front", { })
	var rear_suspension: Dictionary = physical.get("rear", { })
	var front_arb: Dictionary = physical.get("front_arb", { })
	var rear_arb: Dictionary = physical.get("rear_arb", { })
	front_arb_stiffness_n_per_m = float(front_suspension.get("spring_rate_N_per_m", 0.0)) * float(
		front_arb.get("ratio", 0.0)
	)
	rear_arb_stiffness_n_per_m = float(rear_suspension.get("spring_rate_N_per_m", 0.0)) * float(
		rear_arb.get("ratio", 0.0)
	)
	suspension_filters = filters_doc
	road_height_max_rate_m_s = float(filters_doc.get("road_height_max_rate_m_s", 0.0))
	road_height_filter_tau_s = float(filters_doc.get("road_height_filter_tau_s", 0.0))
	var front_z := float(chassis_geometry.get("front_axle_z", -1.205))
	var rear_z := float(chassis_geometry.get("rear_axle_z", 1.205))
	var wheelbase := maxf(absf(rear_z - front_z), 0.1)
	var center: Vector3 = resolved_mass.get("center_of_mass", Vector3.ZERO)
	var front_fraction := clampf((rear_z - center.z) / wheelbase, 0.05, 0.95)
	var total_mass := float(resolved_mass.get("mass_kg", 0.0))
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.80665))
	var axle_docs := [
		physical.get("front", { }),
		physical.get("front", { }),
		physical.get("rear", { }),
		physical.get("rear", { }),
	]
	var axle_fractions := [
		front_fraction,
		front_fraction,
		1.0 - front_fraction,
		1.0 - front_fraction,
	]
	axle_parameters.clear()
	for i in 4:
		var values: Dictionary = axle_docs[i]
		var axle := "front" if i < 2 else "rear"
		var corner_tune: Dictionary = suspension_doc.get(axle, { })
		var spring_rate := float(values.get("spring_rate_N_per_m", 1.0))
		if spring_rate <= 0.0:
			return { "ok": false, "error": axle + " suspension spring rate must be positive." }
		var spring_free_length := float(
			values.get("spring_free_length_m", corner_tune.get("spring_length", 0.3))
		)
		var static_load := total_mass * gravity * float(axle_fractions[i]) * 0.5
		var reference_mass := static_load / maxf(gravity, 0.001)
		var frequency := float(
			corner_tune.get("ride_frequency_hz", sqrt(spring_rate / reference_mass) / TAU)
		)
		if not is_finite(frequency) or frequency <= 0.0:
			return { "ok": false, "error": axle + " ride frequency must be positive and finite." }
		spring_rate = reference_mass * pow(TAU * frequency, 2.0)
		var critical_damping := 2.0 * sqrt(spring_rate * reference_mass)
		var damping_ratio := maxf(float(corner_tune.get("damping_ratio", 0.65)), 0.0)
		var unsprung: Array = resolved_mass.get("unsprung_mass_kg", [0.0, 0.0, 0.0, 0.0])
		static_corner_loads_n[i] = static_load + float(unsprung[i]) * gravity
		axle_parameters.append(
			{
				"spring_rate": spring_rate,
				"spring_can_unseat": bool(corner_tune.get("spring_can_unseat", true)),
				"frequency_reference_mass_kg": reference_mass,
				"ride_frequency_hz": frequency,
				"free_length": spring_free_length,
				"installed_length": float(
					values.get("spring_installed_length_m", spring_free_length)
				),
				"bump_damping": critical_damping * damping_ratio
				* float(corner_tune.get("bump_damp_multiplier", 1.0)),
				"rebound_damping": critical_damping * damping_ratio
				* float(corner_tune.get("rebound_damp_multiplier", 1.0)),
				"fast_factor": float(values.get("damper_fast_factor", 1.0)),
				"knee_speed": float(values.get("damper_knee_m_per_s", INF)),
				"bump_stop_travel": float(values.get("bump_stop_travel_m", 0.0)),
				"bump_stop_stiffness": spring_rate * float(values.get("bump_stop_mult", 1.0)) * 8.0,
				"bump_stop_damping": float(values.get("bump_stop_damper_Ns_per_m", 0.0)),
				"bump_m": float(values.get("wheel_bump_m", 0.22)),
				"droop_m": float(values.get("wheel_droop_m", 0.18)),
				"hard_stop_overtravel": float(values.get("hard_stop_overtravel_m", 0.0)),
				"hard_stop_stiffness": float(values.get("hard_stop_stiffness_N_per_m", 0.0)),
				"hard_stop_damping": float(values.get("hard_stop_damper_Ns_per_m", 0.0)),
				"camber": float(corner_tune.get("camber", 0.0)),
				"camber_gain": float(corner_tune.get("camber_gain_rad_per_m", 0.0)),
				"toe": float(corner_tune.get("toe", 0.0)),
				"toe_gain": float(corner_tune.get("toe_gain_rad_per_m", 0.0)),
				"static_load": static_load,
				"rest_compression_offset": 0.0,
			}
		)
	front_arb_stiffness_n_per_m = float(axle_parameters[0].spring_rate) * float(
		front_arb.get("ratio", 0.0)
	)
	rear_arb_stiffness_n_per_m = float(axle_parameters[2].spring_rate) * float(
		rear_arb.get("ratio", 0.0)
	)
	print(
		"RALLY_SUSPENSION_FREQUENCY ",
		JSON.stringify(
			{
				"front": {
					"mass_kg": axle_parameters[0].frequency_reference_mass_kg,
					"hz": axle_parameters[0].ride_frequency_hz,
					"k_n_m": axle_parameters[0].spring_rate,
					"c_bump_ns_m": axle_parameters[0].bump_damping,
					"c_rebound_ns_m": axle_parameters[0].rebound_damping,
				},
				"rear": {
					"mass_kg": axle_parameters[2].frequency_reference_mass_kg,
					"hz": axle_parameters[2].ride_frequency_hz,
					"k_n_m": axle_parameters[2].spring_rate,
					"c_bump_ns_m": axle_parameters[2].bump_damping,
					"c_rebound_ns_m": axle_parameters[2].rebound_damping,
				},
			}
		),
	)
	return { "ok": true }


## Ruta antigua de ray-distance filtrada RETIRADA (§1): inventario sin
## consumidores (ninguna llamada en el proyecto). El recorrido y la velocidad
## los escribe el rig desde la medida directa hub-vs-chasis. Se conserva este
## comentario como acta de retirada; los campos de filtro quedan documentados
## en la cabecera por compatibilidad con `suspension_filters.json`.


## Legado deprecado (§1): ya sin llamadas activas. Se conserva para no romper
## compatibilidad externa; el rig sobrescribía sus escrituras en el mismo tick.
## No llamar: la rama sin impacto de la simulación solo registra ausencia de
## contacto geométrico y deja al rig como escritor único.
func set_airborne(index: int) -> void:
	push_warning("VehicleSuspensionModel.set_airborne: ruta legada sin efecto; el rig es el escritor único.")
	var was_active := contact_active[index]
	contact_active[index] = false
	geometric_contact[index] = false
	if initialized[index]:
		var target_droop := -float(axle_parameters[index].droop_m)
		compression_velocity[index] = (target_droop - compression[index]) * 8.0
		compression[index] = lerpf(compression[index], target_droop, 0.25)
		filtered_arb_travel[index] = compression[index]
	else:
		compression_velocity[index] = 0.0
	if was_active:
		previous_samples[index] = false


## Limpia el estado transitorio publicado (§2): deja la primera muestra tras
## reset/teletransporte sin arrastre del estado previo. La llama
## FordRallyVehicleSimulation.reset_dynamics() y la rama de rescate.
func clear_transient() -> void:
	for i in 4:
		compression[i] = 0.0
		compression_velocity[i] = 0.0
		filtered_ray_distance[i] = 0.0
		filtered_arb_travel[i] = 0.0
		initialized[i] = false
		previous_samples[i] = false
		contact_active[i] = false
		geometric_contact[i] = false
		last_elastic_forces_n[i] = 0.0
		last_damper_forces_n[i] = 0.0
		last_bump_forces_n[i] = 0.0


## Ley elástica de referencia (§4): curva actual preservada para comparar
## candidatas. Aislada de amortiguador, barra y topes. Devuelve fuerza a
## recorrido dado (neutro = `rest_compression_offset`).
static func elastic_force_reference(
	p: Dictionary, travel: float, rate_coefficient: float = SPRING_PROGRESSIVITY_RATE
) -> float:
	var travel_delta := travel - float(p.get("rest_compression_offset", 0.0))
	var max_range := maxf(float(p.get("bump_m", 0.22)), 0.05)
	var norm_travel := clampf(travel_delta / max_range, -1.0, 1.5)
	var progressive_rate := float(p.get("spring_rate", 1.0)) * (
		1.0 + rate_coefficient * norm_travel * absf(norm_travel)
	)
	var elastic_force := float(p.get("static_load", 0.0)) + progressive_rate * travel_delta
	if bool(p.get("spring_can_unseat", true)):
		var helper_zone := float(p.get("static_load", 0.0)) * HELPER_ZONE_FRACTION
		if elastic_force < helper_zone:
			elastic_force = helper_zone * exp(
				(elastic_force - helper_zone) / maxf(helper_zone, 1.0)
			)
	return elastic_force


## Rigidez tangente de la ley de referencia (§4): dF/dx analítica sin topes y
## sin cambiar la ley de fuerza.
## - Dentro del intervalo del clamp (`n_raw` en [-1, 1.5]): la tasa es variable
##   y `dF/dd = k * (1 + 3*c*n*|n|)` con signo (en extensión la tangente cae
##   por debajo de `k`; en `n = 0` vale `k`).
## - Fuera del intervalo: `n` queda constante y la tasa es constante, así que
##   `dF/dd = k * (1 + c*n*|n|)` (sin factor 3).
## - Cola exponencial: `F = H*exp((raw-H)/M)` con `M = max(H,1)`; la derivada
##   completa es `exp((raw-H)/M) * (H/M) * dRaw/dd`. Con precargas reales
##   (`H >> 1`, `M = H`) el factor `H/M = 1` y la tangente es continua en el
##   umbral; se conserva el factor general para `H < 1`.
## Sin desasentado (`spring_can_unseat=false`) la ley es bilateral y puede
## tirar (fuerza negativa).
static func elastic_tangent_reference(
	p: Dictionary, travel: float, rate_coefficient: float = SPRING_PROGRESSIVITY_RATE
) -> float:
	var travel_delta := travel - float(p.get("rest_compression_offset", 0.0))
	var max_range := maxf(float(p.get("bump_m", 0.22)), 0.05)
	var k := float(p.get("spring_rate", 1.0))
	var n_raw := travel_delta / max_range
	var n := clampf(n_raw, -1.0, 1.5)
	var inside := n_raw >= -1.0 and n_raw <= 1.5
	var tangent_linear := 0.0
	if inside:
		tangent_linear = k * (1.0 + 3.0 * rate_coefficient * n * absf(n))
	else:
		tangent_linear = k * (1.0 + rate_coefficient * n * absf(n))
	var tangent := tangent_linear
	if bool(p.get("spring_can_unseat", true)):
		var raw := float(p.get("static_load", 0.0)) + k * (
			1.0 + rate_coefficient * n * absf(n)
		) * travel_delta
		var helper_zone := float(p.get("static_load", 0.0)) * HELPER_ZONE_FRACTION
		if raw < helper_zone:
			var m := maxf(helper_zone, 1.0)
			tangent = exp((raw - helper_zone) / m) * (helper_zone / m) * tangent_linear
	return tangent


## Muestreo de curva para graficar fuerza y tangente vs recorrido (§4).
## Recorre compresión/extensión aislando amortiguador, barra y topes.
func sample_elastic_curve(index: int, samples: int = 25) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if index < 0 or index >= axle_parameters.size():
		return out
	var p: Dictionary = axle_parameters[index]
	var lo := -float(p.get("droop_m", 0.18))
	var hi := float(p.get("bump_m", 0.22))
	for s in maxi(samples, 2):
		var travel := lerpf(lo, hi, float(s) / float(maxi(samples, 2) - 1))
		out.append(
			{
				"travel_m": travel,
				"force_n": elastic_force_reference(p, travel),
				"tangent_n_m": elastic_tangent_reference(p, travel),
				"neutral_m": float(p.get("rest_compression_offset", 0.0)),
			}
		)
	return out


func suspension_forces() -> Array[float]:
	var forces: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		var p: Dictionary = axle_parameters[i]
		var travel := compression[i]
		var speed := compression_velocity[i]
		var damper_rate := float(p.bump_damping if speed >= 0.0 else p.rebound_damping)
		var abs_speed := absf(speed)
		var knee := maxf(float(p.knee_speed), 1.0e-4)
		var fast_f := float(p.fast_factor)
		var damper_force := 0.0
		if is_finite(knee) and abs_speed > 0.0:
			var slow_part := knee * tanh(abs_speed / knee)
			var fast_part := maxf(abs_speed - slow_part, 0.0) * fast_f
			damper_force = signf(speed) * damper_rate * (slow_part + fast_part)
		else:
			damper_force = damper_rate * speed
		var travel_delta := travel - float(p.get("rest_compression_offset", 0.0))
		var max_range := maxf(float(p.bump_m), 0.05)
		var norm_travel := clampf(travel_delta / max_range, -1.0, 1.5)
		var progressive_rate := float(p.spring_rate) * (
			1.0 + SPRING_PROGRESSIVITY_RATE * norm_travel * absf(norm_travel)
		)
		var elastic_force := float(p.static_load) + progressive_rate * travel_delta
		if bool(p.spring_can_unseat):
			var helper_zone := float(p.static_load) * HELPER_ZONE_FRACTION
			if elastic_force < helper_zone:
				elastic_force = helper_zone * exp(
					(elastic_force - helper_zone) / maxf(helper_zone, 1.0)
				)
		var force := elastic_force + damper_force
		last_elastic_forces_n[i] = elastic_force
		last_damper_forces_n[i] = damper_force
		var bump_range := maxf(float(p.bump_stop_travel), 0.015)
		var bump_threshold := float(p.bump_m) - bump_range
		var bump_force := 0.0
		if travel > bump_threshold:
			var overtravel := travel - bump_threshold
			var norm_over := clampf(overtravel / bump_range, 0.0, 2.0)
			var bump_elastic := float(p.bump_stop_stiffness) * overtravel * norm_over * (
				0.5 + 0.5 * norm_over
			)
			var bump_damp := float(p.bump_stop_damping) * maxf(speed, 0.0) * clampf(
				norm_over,
				0.0,
				1.0,
			)
			bump_force = bump_elastic + bump_damp
			force += bump_force
		last_bump_forces_n[i] = bump_force
		forces[i] = force
	var front_roll := filtered_arb_travel[0] - filtered_arb_travel[1]
	var rear_roll := filtered_arb_travel[2] - filtered_arb_travel[3]
	var front_arb := front_arb_stiffness_n_per_m * front_roll
	var rear_arb := rear_arb_stiffness_n_per_m * rear_roll
	var f_weight_0 := clampf(
		forces[0] / maxf(float(axle_parameters[0].static_load) * 0.25, 1.0),
		0.0,
		1.0,
	) if not contact_active[0] else 1.0
	var f_weight_1 := clampf(
		forces[1] / maxf(float(axle_parameters[1].static_load) * 0.25, 1.0),
		0.0,
		1.0,
	) if not contact_active[1] else 1.0
	front_arb *= minf(f_weight_0, f_weight_1)
	var r_weight_2 := clampf(
		forces[2] / maxf(float(axle_parameters[2].static_load) * 0.25, 1.0),
		0.0,
		1.0,
	) if not contact_active[2] else 1.0
	var r_weight_3 := clampf(
		forces[3] / maxf(float(axle_parameters[3].static_load) * 0.25, 1.0),
		0.0,
		1.0,
	) if not contact_active[3] else 1.0
	rear_arb *= minf(r_weight_2, r_weight_3)
	forces[0] += front_arb
	forces[1] -= front_arb
	forces[2] += rear_arb
	forces[3] -= rear_arb
	return forces


## Convenio de camber explícito §4.3:
## dynamic_camber = AXLE-FRAME (mismo valor FL/FR, positivo = parte alta
## hacia fuera en espejo). dynamic_wheel_camber = WHEEL-FRAME con espejo
## (izquierda [0,2] +1, derecha [1,3] -1). TireModel.evaluate espera
## axle-frame y re-aplica el mismo espejo interno; pasarle dynamic_camber,
## no dynamic_wheel_camber (doble espejo).
func dynamic_camber(index: int) -> float:
	var p: Dictionary = axle_parameters[index]
	var travel_delta := compression[index] - float(p.get("rest_compression_offset", 0.0))
	return float(p.camber) + float(p.camber_gain) * travel_delta


func dynamic_wheel_camber(index: int) -> float:
	var side_sign := 1.0 if index in [0, 2] else -1.0
	return side_sign * dynamic_camber(index)


func dynamic_toe(index: int) -> float:
	var p: Dictionary = axle_parameters[index]
	var side_sign := 1.0 if index in [0, 2] else -1.0
	var travel_delta := compression[index] - float(p.get("rest_compression_offset", 0.0))
	var axle_toe := float(p.toe) + float(p.toe_gain) * travel_delta
	return clampf(-side_sign * axle_toe, -0.05, 0.05)


func maximum_wheel_travel(index: int) -> float:
	var p: Dictionary = axle_parameters[index]
	return float(p.free_length) + float(p.droop_m) + float(p.bump_m)
