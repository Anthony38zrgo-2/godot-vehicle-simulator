class_name SurfaceMix
extends RefCounted

# Mezcla de superficies a partir del paquete publicado por el vehiculo. Solo lee
# contacto, carga, slip, velocidad y entradas; no altera la fisica.
#
# Rodadura: total = velocidad * carga * contacto * (1 - reduccion por deslizamiento),
# repartido entre las dos superficies predominantes segun la carga de sus ruedas.
# Deslizamiento: por rueda, lateral (slip angle) y longitudinal (slip ratio), separado
# en derrape (skid), traccion (peel) y frenada (lock), ponderado por carga.

const CONTACT_MIN_LOAD_N := 60.0
const MAX_SURFACES := 2
const WHEEL_COUNT := 4
const SPEED_START_KPH := 2.0
const SPEED_FULL_KPH := 30.0
const LOAD_FLOOR := 0.35
const LATERAL_SLIP_START_RAD := 0.04
const LATERAL_SLIP_FULL_RAD := 0.20
const LONGITUDINAL_SLIP_START := 0.05
const LONGITUDINAL_SLIP_FULL := 0.35
const SLIP_ROLE_GAIN := 2.0
const SLIP_ROLE_SPEED_START_KPH := 2.0
const SLIP_ROLE_SPEED_FULL_KPH := 15.0
const SLIP_REDUCTION_START := 0.25
const SLIP_REDUCTION_FULL := 0.75
const SLIP_REDUCTION_DEPTH := 0.70

# Nombres de superficie publicados por la simulacion (y sus alias) -> clave de banco.
# Solo las superficies identificadas por el escenario o su perfil de neumatico.
const SURFACE_KEYS := {
	"gravel": "gravel",
	"grass": "grass",
	"dirt": "dirt",
	"sand": "sand",
	"road": "tarmac",
	"asphalt": "tarmac",
	"tarmac": "tarmac",
	"curb": "rumble",
	"rumble": "rumble",
}


static func canonical_surface(name: String) -> String:
	return str(SURFACE_KEYS.get(name.to_lower(), ""))


# Suavizado exponencial independiente de la tasa de fotogramas.
static func smooth(current: float, target: float, delta: float, time_constant: float) -> float:
	if time_constant <= 0.0 or delta <= 0.0:
		return target
	return lerpf(current, target, 1.0 - exp(-delta / time_constant))


static func evaluate(wheels: Array, speed_kph: float, throttle: float, brake: float, reference_weight_n: float) -> Dictionary:
	var loads: Array[float] = []
	var surfaces: Array[String] = []
	var lateral: Array[float] = []
	var longitudinal: Array[float] = []
	var total_load := 0.0
	var contacts := 0
	for wheel in wheels:
		var load_n := maxf(float(wheel.get("load_n", 0.0)), 0.0)
		var surface := canonical_surface(str(wheel.get("surface", "")))
		var in_contact := load_n >= CONTACT_MIN_LOAD_N and not surface.is_empty()
		loads.append(load_n if in_contact else 0.0)
		surfaces.append(surface if in_contact else "")
		var slip_angle := absf(float(wheel.get("slip_angle_rad", 0.0)))
		var slip_ratio := absf(float(wheel.get("slip_ratio", 0.0)))
		lateral.append(smoothstep(LATERAL_SLIP_START_RAD, LATERAL_SLIP_FULL_RAD, slip_angle) if in_contact else 0.0)
		longitudinal.append(smoothstep(LONGITUDINAL_SLIP_START, LONGITUDINAL_SLIP_FULL, slip_ratio) if in_contact else 0.0)
		if in_contact:
			total_load += load_n
			contacts += 1

	# Pesos de carga por rueda: ninguna rueda domina en exclusiva salvo que tenga toda la carga.
	var shares: Dictionary = {}
	var slip_roles: Dictionary = {}
	var slip_total := 0.0
	var braking := brake > throttle
	for index in loads.size():
		if loads[index] <= 0.0:
			continue
		var weight := loads[index] / total_load
		var surface := surfaces[index]
		shares[surface] = float(shares.get(surface, 0.0)) + weight
		var roles: Dictionary = slip_roles.get(surface, {"skid": 0.0, "peel": 0.0, "lock": 0.0})
		roles["skid"] = float(roles["skid"]) + weight * lateral[index]
		var drive_part := 0.0 if braking else longitudinal[index]
		var brake_part := longitudinal[index] if braking else 0.0
		roles["peel"] = float(roles["peel"]) + weight * drive_part
		roles["lock"] = float(roles["lock"]) + weight * brake_part
		slip_roles[surface] = roles
		slip_total += weight * maxf(lateral[index], longitudinal[index])

	# Como maximo dos superficies: las de mayor carga, renormalizadas.
	var ranked: Array = shares.keys()
	ranked.sort_custom(func(a, b) -> bool:
		if is_equal_approx(float(shares[a]), float(shares[b])):
			return str(a) < str(b)
		return float(shares[a]) > float(shares[b]))
	var kept_shares: Dictionary = {}
	var kept_total := 0.0
	for index in mini(ranked.size(), MAX_SURFACES):
		kept_shares[ranked[index]] = float(shares[ranked[index]])
		kept_total += float(shares[ranked[index]])
	for surface in kept_shares:
		kept_shares[surface] = float(kept_shares[surface]) / maxf(kept_total, 1e-9)

	var speed_factor := smoothstep(SPEED_START_KPH, SPEED_FULL_KPH, speed_kph) * (0.6 + 0.4 * clampf(speed_kph / 120.0, 0.0, 1.0))
	var load_ratio := total_load / reference_weight_n if reference_weight_n > 0.0 else 1.0
	var load_factor := LOAD_FLOOR + (1.0 - LOAD_FLOOR) * clampf(load_ratio, 0.0, 1.0)
	var contact_factor := float(contacts) / float(WHEEL_COUNT)
	var slip_reduction := SLIP_REDUCTION_DEPTH * smoothstep(SLIP_REDUCTION_START, SLIP_REDUCTION_FULL, slip_total)
	var roll_total := speed_factor * load_factor * contact_factor * (1.0 - slip_reduction)

	var roll: Dictionary = {}
	var slip: Dictionary = {}
	var slip_speed := smoothstep(SLIP_ROLE_SPEED_START_KPH, SLIP_ROLE_SPEED_FULL_KPH, speed_kph)
	for surface in kept_shares:
		roll[surface] = roll_total * float(kept_shares[surface])
		var roles: Dictionary = slip_roles.get(surface, {"skid": 0.0, "peel": 0.0, "lock": 0.0})
		slip[surface] = {
			"skid": clampf(SLIP_ROLE_GAIN * float(roles["skid"]), 0.0, 1.0) * slip_speed,
			"peel": clampf(SLIP_ROLE_GAIN * float(roles["peel"]), 0.0, 1.0) * slip_speed,
			"lock": clampf(SLIP_ROLE_GAIN * float(roles["lock"]), 0.0, 1.0) * slip_speed,
		}

	var speed_norm := clampf(speed_kph / 120.0, 0.0, 1.0)
	return {
		"roll": roll,
		"slip": slip,
		"surfaces": kept_shares.keys(),
		"shares": shares,
		"contacts": contacts,
		"speed_factor": speed_factor,
		"load_factor": load_factor,
		"roll_total": roll_total,
		"slip_total": slip_total,
		"roll_pitch": clampf(0.92 + 0.10 * speed_norm + 0.04 * slip_total, 0.90, 1.10),
		"slip_pitch": clampf(0.95 + 0.08 * slip_total, 0.90, 1.12),
	}
