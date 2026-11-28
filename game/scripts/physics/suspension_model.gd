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
## Fuerza de amortiguador ANTES del escalado semi-implícito (la "solicitada"
## de la traza). La calcula la propia ruta implícita, de modo que el rig no
## necesita ejecutar una segunda vez la ley explícita completa solo para leer
## este valor de telemetría.
var last_damper_explicit_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var last_bump_forces_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
## Elastocinemática (flexión elástica filtrada de silentblocks y brazos bajo Fy y Fx):
## - `compliance_toe_rad[i]`: desvío de convergencia en marco de rueda (rad, +izquierda -X / -derecha +X).
## - `compliance_camber_rad[i]`: desvío de caída en marco de eje (rad, +parte alta hacia fuera).
const MAX_COMPLIANCE_TOE_RAD := 0.025
const MAX_COMPLIANCE_CAMBER_RAD := 0.045
var compliance_toe_rad: Array[float] = [0.0, 0.0, 0.0, 0.0]
var compliance_camber_rad: Array[float] = [0.0, 0.0, 0.0, 0.0]
var compliance_toe_target_rad: Array[float] = [0.0, 0.0, 0.0, 0.0]
var compliance_camber_target_rad: Array[float] = [0.0, 0.0, 0.0, 0.0]

# Espejo plano de axle_parameters para eliminar búsquedas por string en caliente.
var _flat_ready: bool = false
var _param_version: int = 0
var _any_inclined_axis: bool = false
var _spring_rate := PackedFloat64Array([20000.0, 20000.0, 20000.0, 20000.0])
var _static_load := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _rest_offset := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _bump_m := PackedFloat64Array([0.22, 0.22, 0.22, 0.22])
var _droop_m := PackedFloat64Array([0.18, 0.18, 0.18, 0.18])
var _bump_damping := PackedFloat64Array([2000.0, 2000.0, 2000.0, 2000.0])
var _rebound_damping := PackedFloat64Array([2000.0, 2000.0, 2000.0, 2000.0])
var _fast_factor := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
var _knee_speed := PackedFloat64Array([INF, INF, INF, INF])
var _bump_stop_travel := PackedFloat64Array([0.015, 0.015, 0.015, 0.015])
var _bump_stop_stiffness := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _bump_stop_damping := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _camber := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _camber_gain := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _toe := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _toe_gain := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _rc_height := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _rc_gain := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _anti_dive_tan := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _anti_squat_tan := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _anti_lift_tan := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _comp_steer_lat := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _comp_toe_lon := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _comp_camber_lat := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _comp_camber_lon := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _comp_tau := PackedFloat64Array([0.022, 0.022, 0.022, 0.022])
var _axis_pitch := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _axis_roll := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _axis_pitch_gain := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _axis_roll_gain := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _spring_can_unseat := PackedByteArray([1, 1, 1, 1])
var _solid_axle := PackedByteArray([0, 0, 0, 0])
var _has_inclined_axis := PackedByteArray([0, 0, 0, 0])
var _has_axis_roll := PackedByteArray([0, 0, 0, 0])
var _has_axis_pitch := PackedByteArray([0, 0, 0, 0])

# Buffers preasignados para cero allocs por subpaso.
var _forces_1dof_buf: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _target_toe_buf := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _target_camber_buf := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _comp_alpha_buf := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
var _last_comp_dt: float = -1.0
var ic_hub_forces_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var ic_geo_transfer_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var ic_rc_heights_m: Array[float] = [0.0, 0.0, 0.0, 0.0]
var ic_lat_jack_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var ic_lon_jack_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _ic_half_tracks_buf := PackedFloat64Array([0.65, 0.65, 0.65, 0.65])


func sync_flat_parameters() -> void:
	if axle_parameters.size() < 4:
		_flat_ready = false
		return
	_any_inclined_axis = false
	for i in 4:
		var p: Dictionary = axle_parameters[i]
		_spring_rate[i] = float(p.get("spring_rate", 20000.0))
		_static_load[i] = float(p.get("static_load", 0.0))
		_rest_offset[i] = float(p.get("rest_compression_offset", 0.0))
		_bump_m[i] = float(p.get("bump_m", 0.22))
		_droop_m[i] = float(p.get("droop_m", 0.18))
		_bump_damping[i] = float(p.get("bump_damping", 2000.0))
		_rebound_damping[i] = float(p.get("rebound_damping", 2000.0))
		_fast_factor[i] = float(p.get("fast_factor", 1.0))
		_knee_speed[i] = maxf(float(p.get("knee_speed", INF)), 1.0e-4)
		_bump_stop_travel[i] = maxf(float(p.get("bump_stop_travel", 0.0)), 0.015)
		_bump_stop_stiffness[i] = float(p.get("bump_stop_stiffness", 0.0))
		_bump_stop_damping[i] = float(p.get("bump_stop_damping", 0.0))
		_camber[i] = float(p.get("camber", 0.0))
		_camber_gain[i] = float(p.get("camber_gain", 0.0))
		_toe[i] = float(p.get("toe", 0.0))
		_toe_gain[i] = float(p.get("toe_gain", 0.0))
		_rc_height[i] = float(p.get("roll_center_height_m", 0.0))
		_rc_gain[i] = float(p.get("roll_center_height_gain", 0.0))
		_anti_dive_tan[i] = clampf(float(p.get("anti_dive_tan", 0.0)), -0.35, 0.35)
		_anti_squat_tan[i] = clampf(float(p.get("anti_squat_tan", 0.0)), -0.35, 0.35)
		_anti_lift_tan[i] = clampf(float(p.get("anti_lift_tan", 0.0)), -0.35, 0.35)
		_comp_steer_lat[i] = float(p.get("compliance_steer_lat_rad_per_n", 0.0))
		_comp_toe_lon[i] = float(p.get("compliance_toe_lon_rad_per_n", 0.0))
		_comp_camber_lat[i] = float(p.get("compliance_camber_lat_rad_per_n", 0.0))
		_comp_camber_lon[i] = float(p.get("compliance_camber_lon_rad_per_n", 0.0))
		_comp_tau[i] = maxf(float(p.get("compliance_tau_s", 0.022)), 0.001)
		_axis_pitch[i] = float(p.get("axis_pitch_rad", 0.0))
		_axis_roll[i] = float(p.get("axis_roll_rad", 0.0))
		_axis_pitch_gain[i] = float(p.get("axis_pitch_gain_rad_per_m", 0.0))
		_axis_roll_gain[i] = float(p.get("axis_roll_gain_rad_per_m", 0.0))
		_spring_can_unseat[i] = 1 if bool(p.get("spring_can_unseat", true)) else 0
		_solid_axle[i] = 1 if bool(p.get("solid_axle", false)) else 0
		var has_p := absf(_axis_pitch[i]) > 1.0e-6
		var has_r := absf(_axis_roll[i]) > 1.0e-6
		var incl := has_p or has_r or absf(_axis_pitch_gain[i]) > 1.0e-6 or absf(_axis_roll_gain[i]) > 1.0e-6
		_has_axis_pitch[i] = 1 if has_p else 0
		_has_axis_roll[i] = 1 if has_r else 0
		_has_inclined_axis[i] = 1 if incl else 0
		if incl:
			_any_inclined_axis = true
	_last_comp_dt = -1.0
	_flat_ready = true
	_param_version += 1


## Calibración de muelle y reparto (§3 + §6):
## - `ride_frequency_hz` tiene prioridad cuando se declara en
##   `suspension.front/rear`. La rigidez explícita `geometry_physical.*.spring_rate_N_per_m`
##   solo actúa como respaldo para derivar la frecuencia por defecto
##   (`sqrt(k/m)/TAU`) cuando no hay frecuencia declarada; en ambos casos la
##   rigidez vigente es `k = m_ref * (TAU * f)^2` con
##   `m_ref = carga_estática_esquina / g`.
## - Cálculo compartido §6: `corner_rates()` concentra rigidez,
##   amortiguamiento y tope a partir de (masa de referencia, frecuencia,
##   factores y multiplicador de tope). `configure()` y el garaje
##   (`vehicle_simulation.apply_setup_values()`) lo usan con la misma
##   precedencia de frecuencia declarada; el garaje pasa la masa de
##   referencia ya calibrada y sus deltas de altura/tope sin recalibrarla.
##   Geometría y límites de joints quedan fuera de este cálculo; si se editan
##   bump/droop en vivo, actualizar de forma coordinada parámetros, alcance
##   de contacto y límites de juntas.
## - Por eje se registran (traza RALLY_SUSPENSION_FREQUENCY): masa suspendida
##   de referencia, frecuencia efectiva, wheel rate `k` y coeficientes
##   `c_bump/c_rebound = 2*sqrt(k*m_ref)*zeta*mult`.
## - La precarga es simétrica por eje (`static_load` con reparto solo
##   longitudinal desde COM.z); un desplazamiento lateral de COM no cambia la
##   precarga, aparece como compresión diferencial en equilibrio. La suma de
##   cargas y sus momentos debe contrastarse con peso y COM del vehículo
##   completo; si se ajusta precarga, conservar equilibrio total y
##   longitudinal y frecuencias vigentes dentro de tolerancia.
## H3: el llamante debe distinguir ausente (sin clave → respaldo) de
## declarado (con clave → validación estricta en configure()). Esta ayuda
## solo resuelve el caso ausente (null sin clave); un valor declarado pero
## inválido NUNCA debe silenciarse aquí: configure() lo rechaza con error
## de eje y campo. Se conserva por compatibilidad para llamadas ya
## discriminadas (los bool se tratan como ausentes por legado, no como 0/1).
static func resolve_corner_frequency_hz(
	declared_hz: Variant,
	fallback_rate_n_per_m: float,
	reference_mass_kg: float
) -> float:
	var ref := maxf(float(reference_mass_kg), 0.001)
	if (declared_hz is int or declared_hz is float) and not (declared_hz is bool):
		var f := float(declared_hz)
		if is_finite(f) and f > 0.0:
			return f
	return sqrt(maxf(float(fallback_rate_n_per_m), 0.001) / ref) / TAU


static func _describe_value(value: Variant) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "bool"
	if value is int:
		return "int"
	if value is float:
		return "float"
	if value is String:
		return "string"
	if value is Array:
		return "array"
	if value is Dictionary:
		return "dictionary"
	return "object"


## Cálculo común §6: rigidez, amortiguamiento crítico y topes.
## Entradas explícitas; sin leer dominios ni estado global.
static func corner_rates(
	reference_mass_kg: float,
	frequency_hz: float,
	damping_ratio: float,
	bump_multiplier: float,
	rebound_multiplier: float,
	bump_stop_multiplier: float
) -> Dictionary:
	var ref := maxf(float(reference_mass_kg), 0.001)
	var freq := maxf(float(frequency_hz), 0.01)
	var zeta := maxf(float(damping_ratio), 0.0)
	var spring_rate := ref * pow(TAU * freq, 2.0)
	var critical := 2.0 * sqrt(spring_rate * ref)
	return {
		"spring_rate": spring_rate,
		"critical_damping": critical,
		"bump_damping": critical * zeta * float(bump_multiplier),
		"rebound_damping": critical * zeta * float(rebound_multiplier),
		"bump_stop_stiffness": spring_rate * float(bump_stop_multiplier) * 8.0,
	}


## Paso 1.1 Jolt fix: masa reducida del par chasis-buje.
## m_eff = 1 / (1/m_u + 1/m_s_corner). Estabiliza el integrador explícito a
## 120 Hz para bujes ligeros (12-20 kg) sin límites artificiales.
static func reduced_mass_kg(hub_mass_kg: float, corner_sprung_mass_kg: float) -> float:
	var mu := maxf(float(hub_mass_kg), 1.0)
	var ms := maxf(float(corner_sprung_mass_kg), 1.0)
	return 1.0 / (1.0 / mu + 1.0 / ms)


## Amortiguador semi-implícito: c_eff = c / (1 + c*dt/m_eff).
## Elimina la oscilación por retardo de 1 tick. Devuelve fuerza.
static func semi_implicit_damper_n(c_damper: float, v_rel_axis: float, dt: float, m_eff: float) -> float:
	var c := maxf(float(c_damper), 0.0)
	var m := maxf(float(m_eff), 1.0)
	var d := maxf(float(dt), 0.00001)
	var c_eff := c / (1.0 + (c * d) / m)
	return -c_eff * float(v_rel_axis)


## Muelle / bumpstop / radial semi-implícito:
## k_eff = k / (1 + k*dt*dt/m_eff). Devuelve fuerza.
static func semi_implicit_spring_n(k_stop: float, penetration_m: float, dt: float, m_eff: float) -> float:
	var k := maxf(float(k_stop), 0.0)
	var m := maxf(float(m_eff), 1.0)
	var d := maxf(float(dt), 0.00001)
	var k_eff := k / (1.0 + (k * d * d) / m)
	return -k_eff * float(penetration_m)


## Compresión de equilibrio estático q_eq donde el muelle soporta el peso
## suspendido de la esquina (F_s(q_eq) = W_sprung_corner). Bisección sobre la
## ley elástica de referencia (incluye progresividad y cola de desasentado).
## Si no converge, cae a W/k clamped a [-droop, +bump].
static func equilibrium_travel_m(p: Dictionary) -> float:
	var w := float(p.get("static_load", 0.0))
	var droop := -maxf(float(p.get("droop_m", 0.18)), 0.01)
	var bump := maxf(float(p.get("bump_m", 0.22)), 0.01)
	var k := maxf(float(p.get("spring_rate", 1.0)), 1.0)
	var lo := droop
	var hi := bump
	var f_lo := elastic_force_reference(p, lo) - w
	var f_hi := elastic_force_reference(p, hi) - w
	if f_lo > 0.0:
		return droop
	if f_hi < 0.0:
		return clampf(w / k, droop, bump)
	for _i in 48:
		var mid := 0.5 * (lo + hi)
		var f_mid := elastic_force_reference(p, mid) - w
		if f_mid >= 0.0:
			hi = mid
		else:
			lo = mid
	return 0.5 * (lo + hi)


## Chequeo de estabilidad numérica (Paso 0.2): imprime\omega*dt y
## c*dt/m_eff por esquina. Si cualquiera supera 2.0 el integrador explícito
## diverge a 120 Hz por sí solo.
static func stability_metrics(p: Dictionary, hub_mass_kg: float, corner_sprung_mass_kg: float, dt: float) -> Dictionary:
	var m_eff := reduced_mass_kg(hub_mass_kg, corner_sprung_mass_kg)
	var k := maxf(float(p.get("spring_rate", 1.0)), 1.0)
	var mu := maxf(float(hub_mass_kg), 1.0)
	var omega := sqrt(k / mu)
	var c := maxf(float(p.get("bump_damping", 0.0)), float(p.get("rebound_damping", 0.0)))
	return {
		"omega_dt": float(omega * dt),
		"damper_dt_over_m": float(c * dt / m_eff),
		"m_eff_kg": float(m_eff),
		"stable": bool(omega * dt < 2.0 and c * dt / m_eff < 2.0),
	}


## Parámetros por defecto de cinemática de centros instantáneos según la
## arquitectura de suspensión declarada en el perfil (`spring_architecture`).
## - `roll_center_height_m`: altura estática del centro de alabeo sobre el suelo.
## - `roll_center_height_gain`: migración d(h_RC)/dq con la compresión (negativa
##   cuando el RC desciende al comprimirse la suspensión).
## - `anti_dive_ratio`: fracción geométrica de transferencia delantera en frenada.
## - `anti_squat_ratio`: fracción geométrica de transferencia trasera en tracción.
## - `anti_lift_ratio`: fracción geométrica anti-elevación (tracción delante en
##   FWD/AWD, frenada detrás).
## - `solid_axle`: true en ejes rígidos (live/dead axle), donde el centro de alabeo
##   acopla las dos ruedas del eje en par puro sin expansión de vía en bote simétrico.
static func default_instant_center_kinematics(
	spring_architecture: String,
	is_front: bool,
) -> Dictionary:
	var arch := spring_architecture.strip_edges().to_lower()
	match arch:
		"macpherson_coil":
			return {
				"roll_center_height_m": 0.085,
				"roll_center_height_gain": -0.50,
				"anti_dive_ratio": 0.22 if is_front else 0.0,
				"anti_squat_ratio": 0.0 if is_front else 0.25,
				"anti_lift_ratio": 0.12 if is_front else 0.16,
				"solid_axle": false,
			}
		"double_wishbone_transverse_leaf", "sla_coil_over_upper_arm", "double_wishbone":
			return {
				"roll_center_height_m": 0.065 if is_front else 0.11,
				"roll_center_height_gain": -0.35,
				"anti_dive_ratio": 0.25 if is_front else 0.0,
				"anti_squat_ratio": 0.0 if is_front else 0.28,
				"anti_lift_ratio": 0.14 if is_front else 0.18,
				"solid_axle": false,
			}
		"live_axle_leaf":
			return {
				"roll_center_height_m": 0.22,
				"roll_center_height_gain": -0.15,
				"anti_dive_ratio": 0.0,
				"anti_squat_ratio": 0.35,
				"anti_lift_ratio": 0.22,
				"solid_axle": true,
			}
		"dead_axle_longitudinal_leaf":
			return {
				"roll_center_height_m": 0.20,
				"roll_center_height_gain": -0.15,
				"anti_dive_ratio": 0.0,
				"anti_squat_ratio": 0.25,
				"anti_lift_ratio": 0.20,
				"solid_axle": true,
			}
		"live_axle_coil":
			return {
				"roll_center_height_m": 0.20,
				"roll_center_height_gain": -0.15,
				"anti_dive_ratio": 0.0,
				"anti_squat_ratio": 0.30,
				"anti_lift_ratio": 0.18,
				"solid_axle": true,
			}
		"dead_axle_coil":
			return {
				"roll_center_height_m": 0.19,
				"roll_center_height_gain": -0.15,
				"anti_dive_ratio": 0.0,
				"anti_squat_ratio": 0.20,
				"anti_lift_ratio": 0.16,
				"solid_axle": true,
			}
		"semi_trailing_arm":
			return {
				"roll_center_height_m": 0.16,
				"roll_center_height_gain": -0.42,
				"anti_dive_ratio": 0.0,
				"anti_squat_ratio": 0.30,
				"anti_lift_ratio": 0.14,
				"solid_axle": false,
			}
		"swing_axle":
			return {
				"roll_center_height_m": 0.28,
				"roll_center_height_gain": -0.35,
				"anti_dive_ratio": 0.0,
				"anti_squat_ratio": 0.22,
				"anti_lift_ratio": 0.12,
				"solid_axle": false,
			}
		"trailing_arm_torsion":
			if is_front:
				return {
					"roll_center_height_m": 0.055,
					"roll_center_height_gain": -0.25,
					"anti_dive_ratio": 0.10,
					"anti_squat_ratio": 0.0,
					"anti_lift_ratio": 0.08,
					"solid_axle": false,
				}
			return {
				"roll_center_height_m": 0.17,
				"roll_center_height_gain": -0.20,
				"anti_dive_ratio": 0.0,
				"anti_squat_ratio": 0.18,
				"anti_lift_ratio": 0.16,
				"solid_axle": false,
			}
		"torsion_bar":
			if is_front:
				return {
					"roll_center_height_m": 0.080,
					"roll_center_height_gain": -0.45,
					"anti_dive_ratio": 0.14,
					"anti_squat_ratio": 0.0,
					"anti_lift_ratio": 0.10,
					"solid_axle": false,
				}
			return {
				"roll_center_height_m": 0.16,
				"roll_center_height_gain": -0.40,
				"anti_dive_ratio": 0.0,
				"anti_squat_ratio": 0.28,
				"anti_lift_ratio": 0.14,
				"solid_axle": false,
			}
		"twin_i_beam_coil":
			return {
				"roll_center_height_m": 0.14,
				"roll_center_height_gain": -0.20,
				"anti_dive_ratio": 0.08,
				"anti_squat_ratio": 0.0,
				"anti_lift_ratio": 0.06,
				"solid_axle": false,
			}
		_:
			if is_front:
				return {
					"roll_center_height_m": 0.075,
					"roll_center_height_gain": -0.40,
					"anti_dive_ratio": 0.20,
					"anti_squat_ratio": 0.0,
					"anti_lift_ratio": 0.12,
					"solid_axle": false,
				}
			return {
				"roll_center_height_m": 0.16,
				"roll_center_height_gain": -0.25,
				"anti_dive_ratio": 0.0,
				"anti_squat_ratio": 0.30,
				"anti_lift_ratio": 0.18,
				"solid_axle": false,
			}


## Parámetros por defecto de elastocinemática (flexión de silentblocks y brazos)
## según la arquitectura de suspensión. Unidades en rad/N (1 deg/kN = 1.7453e-5 rad/N).
## - `compliance_steer_lat_rad_per_n > 0`: subviraje elástico estabilizador bajo Fy
##   (delante abre ligeramente hacia fuera de la curva; detrás acompaña hacia dentro).
## - `compliance_toe_lon_rad_per_n`:
##     * Independiente: d(axle_toe)/d(Fx_lon). Positivo => toe-out al frenar (Fx < 0,
##       radio de pivotamiento positivo); negativo => toe-in estabilizador al frenar.
##     * Eje rígido (`solid_axle = true`): guiñada elástica del puente bajo asimetría
##       longitudinal (Fx_L - Fx_R), nula en frenada simétrica.
## - `compliance_camber_lat_rad_per_n > 0`: pérdida elástica de caída negativa (+camber
##   en marco de eje en la rueda exterior cargada) al flexionarse mangueta/silentblocks.
## - `compliance_camber_lon_rad_per_n`: flexión menor de caída bajo par de frenada/tracción.
## - `compliance_tau_s`: constante de tiempo viscoelástica de los silentblocks (15–30 ms).
static func default_elastokinematics(
	spring_architecture: String,
	is_front: bool,
) -> Dictionary:
	const DEG_PER_KN := PI / 180000.0
	var arch := spring_architecture.strip_edges().to_lower()
	match arch:
		"macpherson_coil":
			return {
				"compliance_steer_lat_rad_per_n": (0.11 if is_front else 0.06) * DEG_PER_KN,
				"compliance_toe_lon_rad_per_n": (0.055 if is_front else -0.04) * DEG_PER_KN,
				"compliance_camber_lat_rad_per_n": 0.24 * DEG_PER_KN,
				"compliance_camber_lon_rad_per_n": (-0.025 if is_front else 0.0) * DEG_PER_KN,
				"compliance_tau_s": 0.022,
			}
		"double_wishbone_transverse_leaf", "sla_coil_over_upper_arm", "double_wishbone":
			return {
				"compliance_steer_lat_rad_per_n": (0.09 if is_front else 0.06) * DEG_PER_KN,
				"compliance_toe_lon_rad_per_n": (0.045 if is_front else -0.04) * DEG_PER_KN,
				"compliance_camber_lat_rad_per_n": (0.17 if is_front else 0.15) * DEG_PER_KN,
				"compliance_camber_lon_rad_per_n": (-0.020 if is_front else 0.0) * DEG_PER_KN,
				"compliance_tau_s": 0.020,
			}
		"live_axle_leaf":
			return {
				"compliance_steer_lat_rad_per_n": 0.055 * DEG_PER_KN,
				"compliance_toe_lon_rad_per_n": 0.035 * DEG_PER_KN,
				"compliance_camber_lat_rad_per_n": 0.05 * DEG_PER_KN,
				"compliance_camber_lon_rad_per_n": 0.0,
				"compliance_tau_s": 0.024,
			}
		"dead_axle_longitudinal_leaf":
			return {
				"compliance_steer_lat_rad_per_n": 0.050 * DEG_PER_KN,
				"compliance_toe_lon_rad_per_n": 0.030 * DEG_PER_KN,
				"compliance_camber_lat_rad_per_n": 0.045 * DEG_PER_KN,
				"compliance_camber_lon_rad_per_n": 0.0,
				"compliance_tau_s": 0.024,
			}
		"live_axle_coil":
			return {
				"compliance_steer_lat_rad_per_n": 0.045 * DEG_PER_KN,
				"compliance_toe_lon_rad_per_n": 0.030 * DEG_PER_KN,
				"compliance_camber_lat_rad_per_n": 0.045 * DEG_PER_KN,
				"compliance_camber_lon_rad_per_n": 0.0,
				"compliance_tau_s": 0.022,
			}
		"dead_axle_coil":
			return {
				"compliance_steer_lat_rad_per_n": 0.045 * DEG_PER_KN,
				"compliance_toe_lon_rad_per_n": 0.025 * DEG_PER_KN,
				"compliance_camber_lat_rad_per_n": 0.040 * DEG_PER_KN,
				"compliance_camber_lon_rad_per_n": 0.0,
				"compliance_tau_s": 0.024,
			}
		"semi_trailing_arm":
			return {
				"compliance_steer_lat_rad_per_n": 0.025 * DEG_PER_KN,
				"compliance_toe_lon_rad_per_n": 0.080 * DEG_PER_KN,
				"compliance_camber_lat_rad_per_n": 0.20 * DEG_PER_KN,
				"compliance_camber_lon_rad_per_n": 0.025 * DEG_PER_KN,
				"compliance_tau_s": 0.020,
			}
		"swing_axle":
			return {
				"compliance_steer_lat_rad_per_n": 0.020 * DEG_PER_KN,
				"compliance_toe_lon_rad_per_n": 0.060 * DEG_PER_KN,
				"compliance_camber_lat_rad_per_n": 0.22 * DEG_PER_KN,
				"compliance_camber_lon_rad_per_n": 0.020 * DEG_PER_KN,
				"compliance_tau_s": 0.020,
			}
		"trailing_arm_torsion":
			if is_front:
				return {
					"compliance_steer_lat_rad_per_n": 0.085 * DEG_PER_KN,
					"compliance_toe_lon_rad_per_n": 0.040 * DEG_PER_KN,
					"compliance_camber_lat_rad_per_n": 0.16 * DEG_PER_KN,
					"compliance_camber_lon_rad_per_n": -0.015 * DEG_PER_KN,
					"compliance_tau_s": 0.022,
				}
			return {
				"compliance_steer_lat_rad_per_n": 0.040 * DEG_PER_KN,
				"compliance_toe_lon_rad_per_n": 0.020 * DEG_PER_KN,
				"compliance_camber_lat_rad_per_n": 0.12 * DEG_PER_KN,
				"compliance_camber_lon_rad_per_n": 0.0,
				"compliance_tau_s": 0.022,
			}
		"torsion_bar":
			if is_front:
				return {
					"compliance_steer_lat_rad_per_n": 0.080 * DEG_PER_KN,
					"compliance_toe_lon_rad_per_n": 0.045 * DEG_PER_KN,
					"compliance_camber_lat_rad_per_n": 0.20 * DEG_PER_KN,
					"compliance_camber_lon_rad_per_n": -0.020 * DEG_PER_KN,
					"compliance_tau_s": 0.020,
				}
			return {
				"compliance_steer_lat_rad_per_n": 0.030 * DEG_PER_KN,
				"compliance_toe_lon_rad_per_n": 0.065 * DEG_PER_KN,
				"compliance_camber_lat_rad_per_n": 0.19 * DEG_PER_KN,
				"compliance_camber_lon_rad_per_n": 0.020 * DEG_PER_KN,
				"compliance_tau_s": 0.020,
			}
		"twin_i_beam_coil":
			return {
				"compliance_steer_lat_rad_per_n": 0.14 * DEG_PER_KN,
				"compliance_toe_lon_rad_per_n": 0.070 * DEG_PER_KN,
				"compliance_camber_lat_rad_per_n": 0.18 * DEG_PER_KN,
				"compliance_camber_lon_rad_per_n": -0.025 * DEG_PER_KN,
				"compliance_tau_s": 0.026,
			}
		_:
			if is_front:
				return {
					"compliance_steer_lat_rad_per_n": 0.10 * DEG_PER_KN,
					"compliance_toe_lon_rad_per_n": 0.05 * DEG_PER_KN,
					"compliance_camber_lat_rad_per_n": 0.20 * DEG_PER_KN,
					"compliance_camber_lon_rad_per_n": -0.020 * DEG_PER_KN,
					"compliance_tau_s": 0.022,
				}
			return {
				"compliance_steer_lat_rad_per_n": 0.06 * DEG_PER_KN,
				"compliance_toe_lon_rad_per_n": -0.04 * DEG_PER_KN,
				"compliance_camber_lat_rad_per_n": 0.16 * DEG_PER_KN,
				"compliance_camber_lon_rad_per_n": 0.0,
				"compliance_tau_s": 0.022,
			}


## Barra estabilizadora: rigidez = wheel rate * ratio geométrico.
static func arb_stiffness_n_per_m(wheel_rate_n_per_m: float, ratio: float) -> float:
	return maxf(float(wheel_rate_n_per_m), 0.0) * float(ratio)
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
	var domain_geom: Dictionary = domains.get("chassis", { }).get("geometry", { })
	var kin_wheelbase := maxf(
		float(domain_geom.get("wheelbase", absf(float(domain_geom.get("rear_axle_z", rear_z)) - float(domain_geom.get("front_axle_z", front_z))))),
		0.5,
	)
	var center: Vector3 = resolved_mass.get("center_of_mass", Vector3.ZERO)
	var kin_cg_height_m := clampf(center.y if center.y > 0.15 else 0.50, 0.20, 1.20)
	var brakes_doc: Dictionary = domains.get("brakes", { }).get("brakes", { })
	var nominal_front_brake_bias := clampf(float(brakes_doc.get("front_brake_bias", 0.65)), 0.30, 0.85)
	var powertrain_doc: Dictionary = domains.get("powertrain", { }).get("powertrain", { })
	var nominal_front_drive_split := clampf(float(powertrain_doc.get("front_torque_split", 0.0)), 0.0, 1.0)
	var pitch_aspect := kin_cg_height_m / kin_wheelbase
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
		var fallback_rate := float(values.get("spring_rate_N_per_m", 1.0))
		if fallback_rate <= 0.0:
			return { "ok": false, "error": axle + " suspension spring rate must be positive." }
		var spring_free_length := float(
			values.get("spring_free_length_m", corner_tune.get("spring_length", 0.3))
		)
		var static_load := total_mass * gravity * float(axle_fractions[i]) * 0.5
		var reference_mass := static_load / maxf(gravity, 0.001)
		# H3: distinguir ausente (respaldo) de declarado (validación estricta).
		# Solo si falta el campo se usa la rigidez de respaldo; declarado
		# exige número positivo y finito, o error con eje y campo.
		var frequency := 0.0
		if not corner_tune.has("ride_frequency_hz"):
			frequency = sqrt(maxf(fallback_rate, 0.001) / maxf(reference_mass, 0.001)) / TAU
		else:
			var declared: Variant = corner_tune.get("ride_frequency_hz")
			if declared is bool or not (declared is int or declared is float):
				return { "ok": false, "error": axle + " suspension.ride_frequency_hz must be a positive finite number, got " + _describe_value(declared) + "." }
			var fval := float(declared)
			if not is_finite(fval) or fval <= 0.0:
				return { "ok": false, "error": axle + " suspension.ride_frequency_hz must be a positive finite number." }
			frequency = fval
		if not is_finite(frequency) or frequency <= 0.0:
			return { "ok": false, "error": axle + " suspension.ride_frequency_hz must be positive and finite." }
		var rates := corner_rates(
			reference_mass,
			frequency,
			float(corner_tune.get("damping_ratio", 0.65)),
			float(corner_tune.get("bump_damp_multiplier", 1.0)),
			float(corner_tune.get("rebound_damp_multiplier", 1.0)),
			float(values.get("bump_stop_mult", 1.0))
		)
		var spring_rate: float = rates["spring_rate"]
		var unsprung: Array = resolved_mass.get("unsprung_mass_kg", [0.0, 0.0, 0.0, 0.0])
		static_corner_loads_n[i] = static_load + float(unsprung[i]) * gravity
		var is_front := i < 2
		var kin_defaults := default_instant_center_kinematics(
			str(corner_tune.get("spring_architecture", "")),
			is_front,
		)
		var elasto_defaults := default_elastokinematics(
			str(corner_tune.get("spring_architecture", "")),
			is_front,
		)
		var rc_height_m := float(values.get("roll_center_height_m", corner_tune.get("roll_center_height_m", kin_defaults["roll_center_height_m"])))
		var rc_gain := float(values.get("roll_center_height_gain", corner_tune.get("roll_center_height_gain", kin_defaults["roll_center_height_gain"])))
		var anti_dive_ratio := float(values.get("anti_dive_ratio", corner_tune.get("anti_dive_ratio", kin_defaults["anti_dive_ratio"])))
		var anti_squat_ratio := float(values.get("anti_squat_ratio", corner_tune.get("anti_squat_ratio", kin_defaults["anti_squat_ratio"])))
		var anti_lift_ratio := float(values.get("anti_lift_ratio", corner_tune.get("anti_lift_ratio", kin_defaults["anti_lift_ratio"])))
		var is_solid_axle := bool(values.get("solid_axle", corner_tune.get("solid_axle", kin_defaults["solid_axle"])))
		var comp_steer_lat := float(values.get("compliance_steer_lat_rad_per_n", corner_tune.get("compliance_steer_lat_rad_per_n", elasto_defaults["compliance_steer_lat_rad_per_n"])))
		var comp_toe_lon := float(values.get("compliance_toe_lon_rad_per_n", corner_tune.get("compliance_toe_lon_rad_per_n", elasto_defaults["compliance_toe_lon_rad_per_n"])))
		var comp_camber_lat := float(values.get("compliance_camber_lat_rad_per_n", corner_tune.get("compliance_camber_lat_rad_per_n", elasto_defaults["compliance_camber_lat_rad_per_n"])))
		var comp_camber_lon := float(values.get("compliance_camber_lon_rad_per_n", corner_tune.get("compliance_camber_lon_rad_per_n", elasto_defaults["compliance_camber_lon_rad_per_n"])))
		var comp_tau_s := clampf(float(values.get("compliance_tau_s", corner_tune.get("compliance_tau_s", elasto_defaults["compliance_tau_s"]))), 0.005, 0.12)
		var anti_dive_tan := 0.0
		var anti_squat_tan := 0.0
		var anti_lift_tan := 0.0
		if is_front:
			anti_dive_tan = clampf((anti_dive_ratio / maxf(nominal_front_brake_bias, 0.30)) * pitch_aspect, -0.35, 0.35)
			var front_drive_denom := maxf(nominal_front_drive_split, 0.35) if nominal_front_drive_split > 0.01 else 1.0
			anti_lift_tan = clampf((anti_lift_ratio / front_drive_denom) * pitch_aspect, -0.35, 0.35)
		else:
			var rear_drive_split := 1.0 - nominal_front_drive_split
			var rear_drive_denom := maxf(rear_drive_split, 0.35) if rear_drive_split > 0.01 else 1.0
			anti_squat_tan = clampf((anti_squat_ratio / rear_drive_denom) * pitch_aspect, -0.35, 0.35)
			var rear_brake_bias := maxf(1.0 - nominal_front_brake_bias, 0.25)
			anti_lift_tan = clampf((anti_lift_ratio / rear_brake_bias) * pitch_aspect, -0.35, 0.35)
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
				"bump_damping": float(rates["bump_damping"]),
				"rebound_damping": float(rates["rebound_damping"]),
				"fast_factor": float(values.get("damper_fast_factor", 1.0)),
				"knee_speed": float(values.get("damper_knee_m_per_s", INF)),
				"bump_stop_travel": float(values.get("bump_stop_travel_m", 0.0)),
				"bump_stop_stiffness": float(rates["bump_stop_stiffness"]),
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
				"axis_pitch_rad": float(values.get("axis_pitch_rad", values.get("anti_dive_rad" if i < 2 else "anti_squat_rad", corner_tune.get("axis_pitch_rad", 0.0)))),
				"axis_roll_rad": float(values.get("axis_roll_rad", values.get("jacking_rad", corner_tune.get("axis_roll_rad", 0.0)))),
				"axis_pitch_gain_rad_per_m": float(values.get("axis_pitch_gain_rad_per_m", corner_tune.get("axis_pitch_gain_rad_per_m", 0.0))),
				"axis_roll_gain_rad_per_m": float(values.get("axis_roll_gain_rad_per_m", corner_tune.get("axis_roll_gain_rad_per_m", 0.0))),
				"roll_center_height_m": rc_height_m,
				"roll_center_height_gain": rc_gain,
				"anti_dive_ratio": anti_dive_ratio,
				"anti_squat_ratio": anti_squat_ratio,
				"anti_lift_ratio": anti_lift_ratio,
				"anti_dive_tan": anti_dive_tan,
				"anti_squat_tan": anti_squat_tan,
				"anti_lift_tan": anti_lift_tan,
				"solid_axle": is_solid_axle,
				"compliance_steer_lat_rad_per_n": comp_steer_lat,
				"compliance_toe_lon_rad_per_n": comp_toe_lon,
				"compliance_camber_lat_rad_per_n": comp_camber_lat,
				"compliance_camber_lon_rad_per_n": comp_camber_lon,
				"compliance_tau_s": comp_tau_s,
				"static_load": static_load,
				"rest_compression_offset": 0.0,
			}
		)
	front_arb_stiffness_n_per_m = arb_stiffness_n_per_m(
		float(axle_parameters[0].spring_rate),
		float(front_arb.get("ratio", 0.0))
	)
	rear_arb_stiffness_n_per_m = arb_stiffness_n_per_m(
		float(axle_parameters[2].spring_rate),
		float(rear_arb.get("ratio", 0.0))
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
	sync_flat_parameters()
	clear_compliance_state()
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
		last_damper_explicit_n[i] = 0.0
		last_bump_forces_n[i] = 0.0
		compliance_toe_rad[i] = 0.0
		compliance_camber_rad[i] = 0.0
		compliance_toe_target_rad[i] = 0.0
		compliance_camber_target_rad[i] = 0.0


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
		last_damper_explicit_n[i] = damper_force
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


## Ley semiimplícita de suspensión con las cuatro masas relativas del rig.
## Aplica +F al chasis y −F al buje por la misma coordenada axial.
func suspension_forces_1dof(dt: float, m_rel_kg: Array = []) -> Array[float]:
	if dt <= 0.0 or m_rel_kg.size() != 4:
		return suspension_forces()
	if not _flat_ready:
		sync_flat_parameters()
	var forces := _forces_1dof_buf
	var dt_safe := maxf(dt, 0.00001)
	for i in 4:
		var travel := compression[i]
		var speed := compression_velocity[i]
		var damper_rate := _bump_damping[i] if speed >= 0.0 else _rebound_damping[i]
		var abs_speed := absf(speed)
		var knee := _knee_speed[i]
		var damper_explicit := 0.0
		if is_finite(knee) and abs_speed > 0.0:
			var slow_part := knee * tanh(abs_speed / knee)
			var fast_part := maxf(abs_speed - slow_part, 0.0) * _fast_factor[i]
			damper_explicit = signf(speed) * damper_rate * (slow_part + fast_part)
		else:
			damper_explicit = damper_rate * speed
		var c_lin := damper_rate
		if abs_speed > 1.0e-4:
			c_lin = absf(damper_explicit) / abs_speed
		var m_eff := maxf(float(m_rel_kg[i]), 1.0)
		var damper_force := damper_explicit / (1.0 + (c_lin * dt_safe) / m_eff) if abs_speed > 1.0e-9 else 0.0
		var travel_delta := travel - _rest_offset[i]
		var bump_m_i := _bump_m[i]
		var max_range := maxf(bump_m_i, 0.05)
		var norm_travel := clampf(travel_delta / max_range, -1.0, 1.5)
		var progressive_rate := _spring_rate[i] * (
			1.0 + SPRING_PROGRESSIVITY_RATE * norm_travel * absf(norm_travel)
		)
		var static_load_i := _static_load[i]
		var elastic_force := static_load_i + progressive_rate * travel_delta
		if _spring_can_unseat[i] != 0:
			var helper_zone := static_load_i * HELPER_ZONE_FRACTION
			if elastic_force < helper_zone:
				elastic_force = helper_zone * exp(
					(elastic_force - helper_zone) / maxf(helper_zone, 1.0)
				)
		var force := elastic_force + damper_force
		last_elastic_forces_n[i] = elastic_force
		last_damper_forces_n[i] = damper_force
		last_damper_explicit_n[i] = damper_explicit
		var bump_range := _bump_stop_travel[i]
		var bump_threshold := bump_m_i - bump_range
		var bump_force := 0.0
		if travel > bump_threshold:
			var overtravel := travel - bump_threshold
			var norm_over := clampf(overtravel / bump_range, 0.0, 2.0)
			var b_stiff := _bump_stop_stiffness[i]
			var bump_elastic := b_stiff * overtravel * norm_over * (
				0.5 + 0.5 * norm_over
			)
			var bump_damp := _bump_stop_damping[i] * maxf(speed, 0.0) * clampf(
				norm_over,
				0.0,
				1.0,
			)
			var bump_explicit := bump_elastic + bump_damp
			var k_lin := b_stiff * norm_over * (0.5 + 0.5 * norm_over)
			k_lin = maxf(k_lin, absf(bump_explicit) / maxf(overtravel, 1.0e-4))
			bump_force = bump_explicit / (1.0 + (k_lin * dt * dt) / m_eff)
			force += bump_force
		last_bump_forces_n[i] = bump_force
		forces[i] = force
	var front_roll := filtered_arb_travel[0] - filtered_arb_travel[1]
	var rear_roll := filtered_arb_travel[2] - filtered_arb_travel[3]
	# ARB semi-implícita con acoplamiento 2x2 izquierda-derecha:
	# masa reducida del modo rollo m_roll = 1 / (1/m_L + 1/m_R).
	var m_roll_front := 1.0 / (1.0 / maxf(float(m_rel_kg[0]), 1.0) + 1.0 / maxf(float(m_rel_kg[1]), 1.0))
	var m_roll_rear := 1.0 / (1.0 / maxf(float(m_rel_kg[2]), 1.0) + 1.0 / maxf(float(m_rel_kg[3]), 1.0))
	var dt2 := dt_safe * dt_safe
	var k_arb_front_eff := front_arb_stiffness_n_per_m / (1.0 + (front_arb_stiffness_n_per_m * dt2) / m_roll_front)
	var k_arb_rear_eff := rear_arb_stiffness_n_per_m / (1.0 + (rear_arb_stiffness_n_per_m * dt2) / m_roll_rear)
	var front_arb := k_arb_front_eff * front_roll
	var rear_arb := k_arb_rear_eff * rear_roll
	var f_weight_0 := clampf(
		forces[0] / maxf(_static_load[0] * 0.25, 1.0),
		0.0,
		1.0,
	) if not contact_active[0] else 1.0
	var f_weight_1 := clampf(
		forces[1] / maxf(_static_load[1] * 0.25, 1.0),
		0.0,
		1.0,
	) if not contact_active[1] else 1.0
	front_arb *= minf(f_weight_0, f_weight_1)
	var r_weight_2 := clampf(
		forces[2] / maxf(_static_load[2] * 0.25, 1.0),
		0.0,
		1.0,
	) if not contact_active[2] else 1.0
	var r_weight_3 := clampf(
		forces[3] / maxf(_static_load[3] * 0.25, 1.0),
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
	if not _flat_ready:
		sync_flat_parameters()
	var travel_delta := compression[index] - _rest_offset[index]
	var compliance_delta := compliance_camber_rad[index] if index < compliance_camber_rad.size() else 0.0
	return _camber[index] + _camber_gain[index] * travel_delta + compliance_delta


func dynamic_wheel_camber(index: int) -> float:
	var side_sign := 1.0 if (index == 0 or index == 2) else -1.0
	return side_sign * dynamic_camber(index)


func dynamic_toe(index: int) -> float:
	if not _flat_ready:
		sync_flat_parameters()
	var side_sign := 1.0 if (index == 0 or index == 2) else -1.0
	var travel_delta := compression[index] - _rest_offset[index]
	var axle_toe := _toe[index] + _toe_gain[index] * travel_delta
	var compliance_delta := compliance_toe_rad[index] if index < compliance_toe_rad.size() else 0.0
	return clampf(-side_sign * axle_toe + compliance_delta, -0.06, 0.06)


func clear_compliance_state() -> void:
	for i in 4:
		compliance_toe_rad[i] = 0.0
		compliance_camber_rad[i] = 0.0
		compliance_toe_target_rad[i] = 0.0
		compliance_camber_target_rad[i] = 0.0


## Avanza el filtro viscoelástico de primer orden (silentblocks/brazos, τ ≈ 20-24 ms)
## para convergencia (`compliance_toe_rad`) y caída (`compliance_camber_rad`) bajo
## cargas horizontales en marco de chasis (`chassis_lat_forces_n` +X derecha,
## `chassis_lon_forces_n` -Z avance).
## - Suspensión independiente: cada esquina flexiona según su propia carga Fy y Fx.
## - Eje rígido (`solid_axle = true`): el puente gira coherentemente como un bloque
##   bajo la media lateral del eje y bajo la diferencia longitudinal izq-der (nula
##   en frenada simétrica), con flexión de caída mínima por tubo/rodamiento.
func step_elastokinematics(
	dt: float,
	chassis_lat_forces_n: Array[float],
	chassis_lon_forces_n: Array[float],
) -> void:
	if axle_parameters.size() < 4:
		return
	if not _flat_ready:
		sync_flat_parameters()
	var lat_sz := chassis_lat_forces_n.size()
	var lon_sz := chassis_lon_forces_n.size()
	if absf(dt - _last_comp_dt) > 1.0e-7:
		_last_comp_dt = dt
		for i in 4:
			_comp_alpha_buf[i] = 1.0 if dt <= 0.0 else (1.0 - exp(-dt / _comp_tau[i]))
	for axle in 2:
		var left := axle * 2
		var right := left + 1
		var fy_l := float(chassis_lat_forces_n[left]) if left < lat_sz else 0.0
		var fy_r := float(chassis_lat_forces_n[right]) if right < lat_sz else 0.0
		var fx_l := float(chassis_lon_forces_n[left]) if left < lon_sz else 0.0
		var fx_r := float(chassis_lon_forces_n[right]) if right < lon_sz else 0.0
		var lat_steer_sign := 1.0 if axle == 0 else -1.0
		if _solid_axle[left] != 0 or _solid_axle[right] != 0:
			var k_lat_s := 0.5 * (_comp_steer_lat[left] + _comp_steer_lat[right])
			var k_lon_s := 0.5 * (_comp_toe_lon[left] + _comp_toe_lon[right])
			var fy_avg := 0.5 * (fy_l + fy_r)
			var fx_diff := 0.5 * (fx_l - fx_r)
			var beam_steer := lat_steer_sign * k_lat_s * fy_avg - k_lon_s * fx_diff
			_target_toe_buf[left] = beam_steer
			_target_toe_buf[right] = beam_steer
		else:
			_target_toe_buf[left] = lat_steer_sign * _comp_steer_lat[left] * fy_l - (_comp_toe_lon[left] * fx_l)
			_target_toe_buf[right] = lat_steer_sign * _comp_steer_lat[right] * fy_r + (_comp_toe_lon[right] * fx_r)
		# Convenio AXLE-FRAME: rueda exterior cargada (ej. FR con side_sign=-1 y Fy<0)
		# gana camber positivo (+side_sign * k_cam_lat * Fy > 0).
		_target_camber_buf[left] = _comp_camber_lat[left] * fy_l + _comp_camber_lon[left] * fx_l
		_target_camber_buf[right] = -_comp_camber_lat[right] * fy_r + _comp_camber_lon[right] * fx_r

	for i in 4:
		var t_toe := clampf(_target_toe_buf[i], -MAX_COMPLIANCE_TOE_RAD, MAX_COMPLIANCE_TOE_RAD)
		var t_cam := clampf(_target_camber_buf[i], -MAX_COMPLIANCE_CAMBER_RAD, MAX_COMPLIANCE_CAMBER_RAD)
		compliance_toe_target_rad[i] = t_toe
		compliance_camber_target_rad[i] = t_cam
		var alpha := _comp_alpha_buf[i]
		compliance_toe_rad[i] = lerpf(compliance_toe_rad[i], t_toe, alpha)
		compliance_camber_rad[i] = lerpf(compliance_camber_rad[i], t_cam, alpha)


func maximum_wheel_travel(index: int) -> float:
	var p: Dictionary = axle_parameters[index]
	return float(p.free_length) + float(p.droop_m) + float(p.bump_m)


## Eje cinemático local e_i(q) en espacio de chasis para modelar anti-dive,
## anti-squat y efecto jacking sin añadir DOFs adicionales.
## Con ángulos cero devuelve exactamente Vector3.UP.
func suspension_axis_local(index: int, travel_m: float) -> Vector3:
	if index < 0 or index >= axle_parameters.size():
		return Vector3.UP
	if not _flat_ready:
		sync_flat_parameters()
	if _has_inclined_axis[index] == 0:
		return Vector3.UP
	var travel_delta := travel_m - _rest_offset[index]
	var pitch := _axis_pitch[index] + _axis_pitch_gain[index] * travel_delta
	var side_sign := 1.0 if (index == 0 or index == 2) else -1.0
	var roll := side_sign * (_axis_roll[index] + _axis_roll_gain[index] * travel_delta)
	if absf(pitch) < 1.0e-7 and absf(roll) < 1.0e-7:
		return Vector3.UP
	var axis := Vector3(sin(roll), cos(pitch) * cos(roll), sin(pitch))
	return axis.normalized() if axis.length_squared() > 1.0e-9 else Vector3.UP


## Altura dinámica del centro de alabeo (Roll Center) sobre el plano de apoyo,
## incluyendo migración con la compresión de suspensión (`roll_center_height_gain`).
## Se acota por debajo de 0.70 * h_CG para garantizar estabilidad numérica y física.
func dynamic_roll_center_height_m(
	index: int,
	travel_m: float,
	cg_height_m: float = 0.50,
) -> float:
	if index < 0 or index >= axle_parameters.size():
		return 0.0
	if not _flat_ready:
		sync_flat_parameters()
	var travel_delta := travel_m - _rest_offset[index]
	var rc_raw := _rc_height[index] + _rc_gain[index] * travel_delta
	var max_rc := clampf(maxf(cg_height_m, 0.20) * 0.70, 0.14, 0.45)
	return clampf(rc_raw, -0.15, max_rc)


## Evaluación sin asignaciones de cinemática de centros instantáneos.
## Escribe en ic_hub_forces_n, ic_geo_transfer_n, ic_rc_heights_m,
## ic_lat_jack_n e ic_lon_jack_n.
func evaluate_instant_center_jacking(
	chassis_lat_forces_n: Array[float],
	chassis_lon_forces_n: Array[float],
	wheel_travels_m: Array[float],
	wheel_positions_local: Array[Vector3],
	cg_heights_m: Array[float],
) -> void:
	for i in 4:
		ic_hub_forces_n[i] = 0.0
		ic_geo_transfer_n[i] = 0.0
		ic_rc_heights_m[i] = 0.0
		ic_lat_jack_n[i] = 0.0
		ic_lon_jack_n[i] = 0.0
	if axle_parameters.size() < 4:
		return
	if not _flat_ready:
		sync_flat_parameters()
	var tr_sz := wheel_travels_m.size()
	var cg_sz := cg_heights_m.size()
	var pos_sz := wheel_positions_local.size()
	var lat_sz := chassis_lat_forces_n.size()
	var lon_sz := chassis_lon_forces_n.size()
	for i in 4:
		var travel := float(wheel_travels_m[i]) if i < tr_sz else compression[i]
		var cg_h := float(cg_heights_m[i]) if i < cg_sz else 0.50
		var rc_raw := _rc_height[i] + _rc_gain[i] * (travel - _rest_offset[i])
		var max_rc := clampf(maxf(cg_h, 0.20) * 0.70, 0.14, 0.45)
		ic_rc_heights_m[i] = clampf(rc_raw, -0.15, max_rc)
		_ic_half_tracks_buf[i] = maxf(absf(wheel_positions_local[i].x), 0.25) if i < pos_sz else 0.65

	# 1. Vista frontal/trasera: Roll Center y fuerzas de jacking lateral.
	for axle in 2:
		var left := axle * 2
		var right := left + 1
		if _has_axis_roll[left] != 0 or _has_axis_roll[right] != 0:
			continue
		var fy_l := float(chassis_lat_forces_n[left]) if left < lat_sz else 0.0
		var fy_r := float(chassis_lat_forces_n[right]) if right < lat_sz else 0.0
		if _solid_axle[left] != 0 or _solid_axle[right] != 0:
			var rc_axle := 0.5 * (ic_rc_heights_m[left] + ic_rc_heights_m[right])
			var b_axle := 0.5 * (_ic_half_tracks_buf[left] + _ic_half_tracks_buf[right])
			var tan_rc_axle := clampf(rc_axle / maxf(b_axle, 0.25), -0.55, 0.55)
			var fy_avg := 0.5 * (fy_l + fy_r)
			ic_lat_jack_n[left] = -fy_avg * tan_rc_axle
			ic_lat_jack_n[right] = fy_avg * tan_rc_axle
		else:
			var tan_rc_l := clampf(ic_rc_heights_m[left] / _ic_half_tracks_buf[left], -0.55, 0.55)
			var tan_rc_r := clampf(ic_rc_heights_m[right] / _ic_half_tracks_buf[right], -0.55, 0.55)
			ic_lat_jack_n[left] = -fy_l * tan_rc_l
			ic_lat_jack_n[right] = fy_r * tan_rc_r

	# 2. Vista lateral: Pitch Center (Anti-Dive delante, Anti-Squat detrás, Anti-Lift).
	for i in 4:
		if _has_axis_pitch[i] != 0:
			continue
		var fx_c := float(chassis_lon_forces_n[i]) if i < lon_sz else 0.0
		if absf(fx_c) <= 1.0e-9:
			continue
		if i < 2:
			var tan_front := _anti_dive_tan[i] if fx_c < 0.0 else _anti_lift_tan[i]
			ic_lon_jack_n[i] = fx_c * tan_front
		else:
			var tan_rear := _anti_squat_tan[i] if fx_c > 0.0 else _anti_lift_tan[i]
			ic_lon_jack_n[i] = -fx_c * tan_rear

	for i in 4:
		var q_kin := ic_lat_jack_n[i] + ic_lon_jack_n[i]
		ic_hub_forces_n[i] = q_kin
		ic_geo_transfer_n[i] = -q_kin


func instant_center_jacking_forces(
	chassis_lat_forces_n: Array[float],
	chassis_lon_forces_n: Array[float],
	wheel_travels_m: Array[float],
	wheel_positions_local: Array[Vector3],
	cg_heights_m: Array[float],
) -> Dictionary:
	evaluate_instant_center_jacking(
		chassis_lat_forces_n,
		chassis_lon_forces_n,
		wheel_travels_m,
		wheel_positions_local,
		cg_heights_m,
	)
	return {
		"hub_forces_n": ic_hub_forces_n.duplicate(),
		"geometric_load_transfer_n": ic_geo_transfer_n.duplicate(),
		"roll_center_heights_m": ic_rc_heights_m.duplicate(),
		"lateral_jacking_n": ic_lat_jack_n.duplicate(),
		"longitudinal_jacking_n": ic_lon_jack_n.duplicate(),
	}
