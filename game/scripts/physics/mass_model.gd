class_name VehicleMassModel
extends RefCounted

var chassis_components: Array[Dictionary] = []
var spare_component_baseline: Dictionary = {}
var fuel_capacity_kg: float = 0.0
var fuel_density_kg_per_litre: float = 0.0
var fuel_tank_position_local: Vector3 = Vector3.ZERO
var fuel_initial_kg: float = 0.0
var wheel_spin_inertia: Array[float] = [0.85, 0.85, 0.85, 0.85]
var inventory_mass_kg: float = 0.0
var inventory_base_budget_kg: float = 0.0
var non_wheel_inventory_mass_kg: float = 0.0
var unsupported_attachment_components: PackedStringArray = PackedStringArray()
var unsprung_mass_kg: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_centres_local: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var inertia_multipliers: Vector3 = Vector3.ONE
# Auditoría §5: inventario y recentrado por perfil (sin cambiar calibración).
# Se rellenan en configure() para la tabla reproducible por perfil.
var audit_pre_recenter_com := Vector3.ZERO
var audit_pre_recenter_sprung_mass_kg := 0.0
var audit_recenter_shift := Vector3.ZERO
var audit_recenter_fdist_target := -1.0
var audit_recenter_cgz_target := -1.0
var audit_recenter_clamped := false
var audit_wheel_authored_inertia: Array[float] = [0.0, 0.0, 0.0, 0.0]
var audit_wheel_fallback_inertia: Array[float] = [0.0, 0.0, 0.0, 0.0]
var audit_wheel_inertia_source: Array[String] = ["", "", "", ""]
var audit_unsprung_per_wheel_before_recenter: Array[float] = [0.0, 0.0, 0.0, 0.0]

# Dynamic fuel slosh state (2D spring-damper in local X-Z plane)
var _fuel_slosh_offset: Vector3 = Vector3.ZERO
var _fuel_slosh_velocity: Vector3 = Vector3.ZERO
const SLOSH_MAX_DISPLACEMENT_M := Vector3(0.11, 0.03, 0.08)
const SLOSH_STIFFNESS := 28.0
const SLOSH_DAMPING := 6.5

const WHEEL_NAMES := ["FrontLeft", "FrontRight", "RearLeft", "RearRight"]
const WHEEL_KEYS := ["front_left", "front_right", "rear_left", "rear_right"]


func configure(domains: Dictionary, asset_manifest: Dictionary) -> Dictionary:
	spare_component_baseline.clear()
	chassis_components.clear()
	unsprung_mass_kg.fill(0.0)
	wheel_spin_inertia.fill(0.0)
	unsupported_attachment_components.clear()
	_fuel_slosh_offset = Vector3.ZERO
	_fuel_slosh_velocity = Vector3.ZERO

	var chassis_doc: Dictionary = domains.get("chassis", { })
	var chassis_header: Dictionary = chassis_doc.get("chassis", { })
	inertia_multipliers = _vector_from_document(
		chassis_header.get("inertia_multipliers", { }),
		Vector3.ONE,
	)
	inertia_multipliers.x = maxf(inertia_multipliers.x, 0.1)
	inertia_multipliers.y = maxf(inertia_multipliers.y, 0.1)
	inertia_multipliers.z = maxf(inertia_multipliers.z, 0.1)

	var inventory: Dictionary = chassis_doc.get("physical_mass_inventory", { })
	var components: Variant = inventory.get("components", [])
	if not components is Array:
		return { "ok": false, "error": "Mass inventory components must be an array." }
	inventory_base_budget_kg = float(inventory.get("base_budget_kilograms", 0.0))
	inventory_mass_kg = 0.0
	non_wheel_inventory_mass_kg = 0.0
	var wheel_centres := _wheel_centres(asset_manifest)
	wheel_centres_local.assign(wheel_centres)
	var rotating_wheel_masses: Array[float] = [0.0, 0.0, 0.0, 0.0]

	for component_value in components:
		if not component_value is Dictionary:
			continue
		var properties: Dictionary = component_value.get("properties", { })
		var mass := float(properties.get("mass_kilograms", 0.0))
		if mass <= 0.0:
			continue
		var component_name := str(properties.get("name", "unnamed_component"))
		var rotating_wheel_value: Variant = component_value.get("rotating_wheel", null)
		var rotating_wheel := "" if rotating_wheel_value == null else str(rotating_wheel_value)
		var attachment: Dictionary = properties.get("attachment", { })
		var center := _vector_from_document(
			properties.get("center_of_mass_in_attachment_metres", { }),
			Vector3.ZERO,
		)
		var offset := Vector3.ZERO
		if not rotating_wheel.is_empty():
			var wheel_index := WHEEL_NAMES.find(rotating_wheel)
			if wheel_index < 0:
				return {
					"ok": false,
					"error": "Unknown rotating wheel attachment: " + rotating_wheel,
				}
			offset = wheel_centres[wheel_index]
			if wheel_index < wheel_spin_inertia.size():
				var component_inertia := _inertia_diagonal(properties)
				wheel_spin_inertia[wheel_index] += maxf(component_inertia.x, 0.0)
				rotating_wheel_masses[wheel_index] += mass
		elif str(attachment.get("kind", "body")) == "upright":
			var wheel_index := WHEEL_NAMES.find(str(attachment.get("wheel", "")))
			if wheel_index < 0:
				return {
					"ok": false,
					"error": "Unknown upright wheel attachment: " + str(attachment.get("wheel", "")),
				}
			offset = wheel_centres[wheel_index]
		elif str(attachment.get("kind", "body")) != "body":
			unsupported_attachment_components.append(component_name)
		var inertia_center := _inertia_matrix(properties)
		var raw_allocation: Variant = component_value.get(
			"unsprung_mass_distribution_kg",
			[0.0, 0.0, 0.0, 0.0],
		)
		if not raw_allocation is Array or (raw_allocation as Array).size() != 4:
			return {
				"ok": false,
				"error": "Unsprung allocation must have four entries: " + component_name,
			}
		var allocation: Array = (raw_allocation as Array).duplicate()
		if not rotating_wheel.is_empty():
			allocation.fill(0.0)
			allocation[WHEEL_NAMES.find(rotating_wheel)] = mass
		elif str(attachment.get("kind", "body")) == "upright":
			allocation.fill(0.0)
			allocation[WHEEL_NAMES.find(str(attachment.get("wheel", "")))] = mass
		var removed_mass := 0.0
		for i in 4:
			var corner_mass := float(allocation[i])
			if corner_mass < 0.0 or not is_finite(corner_mass):
				return { "ok": false, "error": "Invalid unsprung allocation for " + component_name }
			unsprung_mass_kg[i] += corner_mass
			removed_mass += corner_mass
		if removed_mass > mass + 1.0e-6:
			return {
				"ok": false,
				"error": "Unsprung allocation exceeds component mass: " + component_name,
			}
		var sprung_mass := maxf(mass - removed_mass, 0.0)
		if sprung_mass > 0.0:
			chassis_components.append(
				{
					"name": component_name,
					"mass_kg": sprung_mass,
					"position": offset + center,
					"inertia": inertia_center * (sprung_mass / mass),
				}
			)
		inventory_mass_kg += mass
		if rotating_wheel.is_empty():
			non_wheel_inventory_mass_kg += mass

	var tires_doc: Dictionary = domains.get("tires", { }).get("tires", { })
	var f_radius := float(tires_doc.get("front", { }).get("radius", tires_doc.get("radius", 0.28)))
	var r_radius := float(tires_doc.get("rear", { }).get("radius", tires_doc.get("radius", 0.28)))
	for i in 4:
		var r := f_radius if i < 2 else r_radius
		var w_mass := maxf(rotating_wheel_masses[i], unsprung_mass_kg[i] * 0.45)
		var fallback_inertia := maxf(0.55 * w_mass * r * r, 0.35)
		# Auditoría §5: distinguir sustitución (ausencia de dato) de
		# elevación por mínimo. Efecto en aceleración angular: I mayor =
		# menor alpha ante el mismo par (alpha = T / I).
		audit_wheel_authored_inertia[i] = float(wheel_spin_inertia[i])
		audit_wheel_fallback_inertia[i] = fallback_inertia
		if wheel_spin_inertia[i] <= 0.05:
			wheel_spin_inertia[i] = fallback_inertia
			audit_wheel_inertia_source[i] = "fallback_sustitucion"
		else:
			var elevated := maxf(wheel_spin_inertia[i], fallback_inertia * 0.5)
			if elevated > wheel_spin_inertia[i] + 1e-9:
				audit_wheel_inertia_source[i] = "elevada_minimo"
			else:
				audit_wheel_inertia_source[i] = "autorada"
			wheel_spin_inertia[i] = elevated
	audit_unsprung_per_wheel_before_recenter.assign(unsprung_mass_kg)

	# Auto-rebalanceo longitudinal y vertical según targets históricos.
	# CONTRATO PENDIENTE §5 (sin cambiar significado hasta acordar fichas):
	# `target_cg_z_m` (y alias `target_cgz_m`) se aplica al eje Y local
	# (altura), no al Z longitudinal, aunque su nombre sugiera Z. El contrato
	# de coordenadas del inventario es "Body -Z forward, +Y up": Z es
	# longitudinal (reparto delantero) e Y es altura. Los valores por perfil
	# (~0.44-0.51 m) confirman altura, no posición longitudinal (que estaría
	# cerca de 0 entre ejes -1.2..+1.2 m). No reubicar el tanque ni cambiar
	# este significado sin resolver compatibilidad de perfiles y documentar
	# qué masa/condición (vacío/inicial/lleno) representa cada ficha.
	# Límites de recentrado: shift.z en [-0.45, +0.45] m, shift.y en
	# [-0.20, +0.20] m; solo actúan si el target lo exige y la distancia
	# entre ejes supera 0.5 m (reparto). X nunca se recentra.
	var header_fdist := float(chassis_header.get("front_weight_distribution", -1.0))
	var header_cgz := float(chassis_header.get("target_cg_z_m", chassis_header.get("target_cgz_m", -1.0)))
	audit_recenter_fdist_target = header_fdist
	audit_recenter_cgz_target = header_cgz
	audit_pre_recenter_com = Vector3.ZERO
	audit_pre_recenter_sprung_mass_kg = 0.0
	audit_recenter_shift = Vector3.ZERO
	audit_recenter_clamped = false
	if (header_fdist >= 0.05 and header_fdist <= 0.95) or header_cgz > 0.05:
		var _sprung_mass := 0.0
		var _wcom := Vector3.ZERO
		for _c in chassis_components:
			_sprung_mass += float(_c.get("mass_kg", 0.0))
			_wcom += (_c.get("position") as Vector3) * float(_c.get("mass_kg", 0.0))
		if _sprung_mass > 0.0:
			var _cur := _wcom / _sprung_mass
			audit_pre_recenter_com = _cur
			audit_pre_recenter_sprung_mass_kg = _sprung_mass
			var _shift := Vector3.ZERO
			var _clamped := false
			if header_fdist >= 0.05 and header_fdist <= 0.95 and wheel_centres_local.size() == 4:
				var _fz := (wheel_centres_local[0].z + wheel_centres_local[1].z) * 0.5
				var _rz := (wheel_centres_local[2].z + wheel_centres_local[3].z) * 0.5
				var _wb := absf(_rz - _fz)
				if _wb > 0.5:
					var _want_z := _rz - header_fdist * _wb
					var _raw_z := _want_z - _cur.z
					_shift.z = clampf(_raw_z, -0.45, 0.45)
					if absf(_shift.z - _raw_z) > 1e-9:
						_clamped = true
			if header_cgz > 0.05:
				var _raw_y := header_cgz - _cur.y
				_shift.y = clampf(_raw_y, -0.20, 0.20)
				if absf(_shift.y - _raw_y) > 1e-9:
					_clamped = true
			audit_recenter_shift = _shift
			audit_recenter_clamped = _clamped
			if _shift.length_squared() > 0.00000001:
				for _c in chassis_components:
					_c["position"] = (_c.get("position") as Vector3) + _shift
			print("RALLY_MASS_RECENTER ", JSON.stringify({"fdist": header_fdist, "cgz": header_cgz, "shift": [_shift.x, _shift.y, _shift.z], "clamped": _clamped}))

	var fuel: Dictionary = domains.get("fuel", { }).get("fuel", { })
	fuel_density_kg_per_litre = float(fuel.get("density_kg_per_litre", 0.74))
	if fuel_density_kg_per_litre <= 0.0:
		return { "ok": false, "error": "fuel.density_kg_per_litre must be positive." }
	fuel_capacity_kg = float(fuel.get("capacity_kg", 0.0))
	fuel_initial_kg = float(fuel.get("initial_kg", fuel_capacity_kg))
	fuel_initial_kg = clampf(fuel_initial_kg, 0.0, fuel_capacity_kg)
	fuel_tank_position_local = _vector_from_document(
		fuel.get("tank_position_local_m", { }),
		Vector3(0.0, 0.46, 1.05),
	)
	if chassis_components.is_empty() or inventory_mass_kg <= 0.0:
		return { "ok": false, "error": "Mass inventory contains no positive-mass body components." }
	if (
		inventory_base_budget_kg > 0.0
		and absf(non_wheel_inventory_mass_kg - inventory_base_budget_kg) > 1.0
	):
		return {
			"ok": false,
			"error": "Non-wheel mass inventory does not close: components="
			+ str(non_wheel_inventory_mass_kg) + " kg, declared="
			+ str(inventory_base_budget_kg) + " kg.",
		}
	return { "ok": true }


## Optional step before resolve(): updates dynamic fuel slosh offset based on local chassis acceleration
func step_fuel_slosh(dt: float, local_linear_accel_mps2: Vector3, fuel_mass_kg: float) -> void:
	if dt <= 0.0 or fuel_capacity_kg <= 0.0 or fuel_mass_kg <= 0.5:
		_fuel_slosh_offset = _fuel_slosh_offset.lerp(Vector3.ZERO, clampf(dt * 5.0, 0.0, 1.0))
		_fuel_slosh_velocity = Vector3.ZERO
		return
	var fill_ratio := clampf(fuel_mass_kg / fuel_capacity_kg, 0.0, 1.0)
	var slosh_activity := 4.0 * fill_ratio * (1.0 - fill_ratio)
	var inertial_force := -local_linear_accel_mps2 * (0.04 * slosh_activity)
	var spring_force := -SLOSH_STIFFNESS * _fuel_slosh_offset - SLOSH_DAMPING * _fuel_slosh_velocity
	_fuel_slosh_velocity += (inertial_force + spring_force) * dt
	_fuel_slosh_offset += _fuel_slosh_velocity * dt
	_fuel_slosh_offset = _fuel_slosh_offset.clamp(
		-SLOSH_MAX_DISPLACEMENT_M,
		SLOSH_MAX_DISPLACEMENT_M,
	)


func set_carried_spares(count: int, policy: Dictionary) -> void:
	var name := str(policy.get("mass_component_name", "spare_wheels_and_tools"))
	for component in chassis_components:
		if str(component.get("name", "")) != name:
			continue
		if spare_component_baseline.is_empty():
			spare_component_baseline = component.duplicate(true)
		var mass := float(policy.get("tools_mass_kg", 7.0)) + count * float(policy.get("wheel_mass_kg", 18.0))
		component.mass_kg = mass
		component.inertia = (spare_component_baseline.inertia as Basis).scaled(Vector3.ONE * (mass / maxf(float(spare_component_baseline.mass_kg), 0.01)))
		return

func resolve(fuel_mass_kg: float) -> Dictionary:
	var fuel_mass := clampf(fuel_mass_kg, 0.0, fuel_capacity_kg)
	var effective_fuel_pos := fuel_tank_position_local + _fuel_slosh_offset
	var total_mass := fuel_mass
	var weighted_center := effective_fuel_pos * fuel_mass
	for component in chassis_components:
		var component_mass := float(component["mass_kg"])
		total_mass += component_mass
		weighted_center += component["position"] * component_mass
	if total_mass <= 0.0:
		return { "mass_kg": 1.0, "center_of_mass": Vector3.ZERO, "inertia": Vector3.ONE }
	var center := weighted_center / total_mass
	var tensor := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for component in chassis_components:
		var component_mass := float(component["mass_kg"])
		var component_center: Vector3 = component["position"]
		var component_inertia: Basis = component["inertia"]
		tensor = _add_matrix(tensor, component_inertia)
		tensor = _add_matrix(tensor, _parallel_axis(component_mass, component_center - center))
	if fuel_mass > 0.0:
		var fuel_box_inertia := Basis(
			Vector3(fuel_mass * (0.25 * 0.25 + 0.35 * 0.35) / 12.0, 0.0, 0.0),
			Vector3(0.0, fuel_mass * (0.55 * 0.55 + 0.35 * 0.35) / 12.0, 0.0),
			Vector3(0.0, 0.0, fuel_mass * (0.55 * 0.55 + 0.25 * 0.25) / 12.0),
		)
		tensor = _add_matrix(tensor, fuel_box_inertia)
		tensor = _add_matrix(tensor, _parallel_axis(fuel_mass, effective_fuel_pos - center))

	tensor = _scale_inertia_tensor(tensor, inertia_multipliers)

	# H4: tensor escalado ANTES del recorte (no cambia la calibración; solo
	# se reporta). Momentos principales = autovalores de la matriz simétrica.
	var scaled_tensor := Basis(tensor.x, tensor.y, tensor.z)
	var principal := principal_moments(scaled_tensor)
	var ixx := maxf(tensor.x.x, 10.0)
	var iyy := maxf(tensor.y.y, 10.0)
	var izz := maxf(tensor.z.z, 10.0)
	ixx = minf(ixx, iyy + izz - 1.0)
	iyy = minf(iyy, ixx + izz - 1.0)
	izz = minf(izz, ixx + iyy - 1.0)
	var corrected := absf(ixx - scaled_tensor.x.x) > 1e-9 or absf(iyy - scaled_tensor.y.y) > 1e-9 or absf(izz - scaled_tensor.z.z) > 1e-9
	tensor.x.x = ixx
	tensor.y.y = iyy
	tensor.z.z = izz
	var diagonal := Vector3(ixx, iyy, izz)
	var triangular_principal_ok := principal.x <= principal.y + principal.z - 1.0 and principal.y <= principal.x + principal.z - 1.0 and principal.z <= principal.x + principal.y - 1.0

	var i_yz := tensor.y.z
	var roll_axis_pitch_rad := 0.5 * atan2(2.0 * i_yz, iyy - izz)

	var total_unsprung := unsprung_mass_kg[0] + unsprung_mass_kg[1] + unsprung_mass_kg[2] + unsprung_mass_kg[
		3
	]
	var vehicle_total_mass := total_mass + total_unsprung
	var total_weighted_center := weighted_center
	for i in 4:
		total_weighted_center += wheel_centres_local[i] * unsprung_mass_kg[i]
	var total_center := total_weighted_center / maxf(vehicle_total_mass, 1.0)

	return {
		"mass_kg": total_mass,
		"vehicle_total_mass_kg": vehicle_total_mass,
		"unsprung_mass_kg": unsprung_mass_kg.duplicate(),
		"center_of_mass": center,
		"total_center_of_mass": total_center,
		"inertia": diagonal,
		"inertia_applied_diagonal": diagonal,
		"inertia_tensor": tensor,
		"inertia_tensor_scaled": Basis(scaled_tensor.x, scaled_tensor.y, scaled_tensor.z),
		"inertia_principal_moments": principal,
		"inertia_corrected": corrected,
		"triangular_principal_ok": triangular_principal_ok,
		"inertia_inverse_tensor": tensor.inverse(),
		"roll_axis_pitch_rad": roll_axis_pitch_rad,
		"fuel_mass_kg": fuel_mass,
		"fuel_slosh_offset_m": _fuel_slosh_offset,
		"inventory_mass_kg": inventory_mass_kg,
	}


## Momentos principales de un tensor de inercia simétrico (H4): autovalores
## por Jacobi cíclico (10 barridos, suficiente para 3x3). Ordenados de mayor
## a menor. Solo auditoría; no cambia la diagonal que recibe Jolt.
static func principal_moments(t: Basis) -> Vector3:
	var a := [
		[t.x.x, t.x.y, t.x.z],
		[t.y.x, t.y.y, t.y.z],
		[t.z.x, t.z.y, t.z.z],
	]
	for _sweep in 10:
		for pq in [[0, 1], [0, 2], [1, 2]]:
			var p: int = pq[0]
			var q: int = pq[1]
			var apq: float = a[p][q]
			if absf(apq) < 1e-12:
				continue
			var app: float = a[p][p]
			var aqq: float = a[q][q]
			var theta := (aqq - app) / (2.0 * apq)
			var sgn := 1.0 if theta >= 0.0 else -1.0
			var t_rot := sgn / (absf(theta) + sqrt(theta * theta + 1.0))
			var c := 1.0 / sqrt(t_rot * t_rot + 1.0)
			var s := t_rot * c
			for r in 3:
				if r != p and r != q:
					var arp: float = a[r][p]
					var arq: float = a[r][q]
					a[r][p] = c * arp - s * arq
					a[p][r] = a[r][p]
					a[r][q] = s * arp + c * arq
					a[q][r] = a[r][q]
			a[p][p] = c * c * app - 2.0 * c * s * apq + s * s * aqq
			a[q][q] = s * s * app + 2.0 * c * s * apq + c * c * aqq
			a[p][q] = 0.0
			a[q][p] = 0.0
	var eig := [a[0][0], a[1][1], a[2][2]]
	eig.sort()
	eig.reverse()
	return Vector3(eig[0], eig[1], eig[2])


## Auditoría reproducible por perfil §5 (sin cambiar calibración).
## Tabla con masas, COM, reparto, desplazamiento de recentrado e inercias.
## - `front_fraction(com_z)`: (rear_z - com_z) / wheelbase, misma fórmula que
##   la suspensión para la precarga (usa COM suspendido). Se reporta también
##   con COM total (incluye no suspendido) para contrastar.
## - Inercias por rueda: autorada (suma de componentes rotating_wheel),
##   fallback (0.55*m*r², mínimo 0.35) y efectiva; fuente distingue
##   sustitución (ausencia de dato, <=0.05) de elevación por mínimo.
## - Tensor completo vs diagonal aplicada: el vehículo aplica solo la
##   diagonal a Jolt (RigidBody3D.inertia); los productos (xy, xz, yz),
##   momentos principales y desigualdades triangulares se reportan para
##   decidir si compensa usar ejes principales (solo si las diferencias lo
##   justifican y tras verificar el marco de Jolt).
func front_distribution_for(com_z: float, front_z: float, rear_z: float) -> float:
	var wb := maxf(absf(rear_z - front_z), 0.1)
	return clampf((rear_z - com_z) / wb, 0.05, 0.95)


func audit_report(geometry: Dictionary) -> Dictionary:
	var front_z := float(geometry.get("front_axle_z", -1.205))
	var rear_z := float(geometry.get("rear_axle_z", 1.205))
	var states := {}
	for label in ["empty", "initial", "full"]:
		var fuel_kg := 0.0
		if label == "initial":
			fuel_kg = fuel_initial_kg
		elif label == "full":
			fuel_kg = fuel_capacity_kg
		var resolved := resolve(fuel_kg)
		var center: Vector3 = resolved.get("center_of_mass", Vector3.ZERO)
		var total_center: Vector3 = resolved.get("total_center_of_mass", Vector3.ZERO)
		var tensor: Basis = resolved.get("inertia_tensor", Basis.IDENTITY)
		var scaled: Basis = resolved.get("inertia_tensor_scaled", tensor)
		var diagonal: Vector3 = resolved.get("inertia", Vector3.ONE)
		var principal: Vector3 = resolved.get("inertia_principal_moments", diagonal)
		var off := Vector3(tensor.x.y, tensor.x.z, tensor.y.z)
		states[label] = {
			"fuel_kg": fuel_kg,
			"sprung_mass_kg": float(resolved.get("mass_kg", 0.0)),
			"vehicle_total_mass_kg": float(resolved.get("vehicle_total_mass_kg", 0.0)),
			"center_of_mass": [center.x, center.y, center.z],
			"total_center_of_mass": [total_center.x, total_center.y, total_center.z],
			"front_fraction_sprung": front_distribution_for(center.z, front_z, rear_z),
			"front_fraction_total": front_distribution_for(total_center.z, front_z, rear_z),
			"inertia_diagonal": [diagonal.x, diagonal.y, diagonal.z],
			"inertia_applied_diagonal": [diagonal.x, diagonal.y, diagonal.z],
			"inertia_tensor": [
				[tensor.x.x, tensor.x.y, tensor.x.z],
				[tensor.y.x, tensor.y.y, tensor.y.z],
				[tensor.z.x, tensor.z.y, tensor.z.z],
			],
			"inertia_tensor_scaled": [
				[scaled.x.x, scaled.x.y, scaled.x.z],
				[scaled.y.x, scaled.y.y, scaled.y.z],
				[scaled.z.x, scaled.z.y, scaled.z.z],
			],
			"inertia_principal_moments": [principal.x, principal.y, principal.z],
			"inertia_corrected": bool(resolved.get("inertia_corrected", false)),
			"off_diagonal": [off.x, off.y, off.z],
			"off_norm": off.length(),
			"triangular_ok": (diagonal.x <= diagonal.y + diagonal.z - 1.0) and (diagonal.y <= diagonal.x + diagonal.z - 1.0) and (diagonal.z <= diagonal.x + diagonal.y - 1.0),
			"triangular_principal_ok": bool(resolved.get("triangular_principal_ok", true)),
			"roll_axis_pitch_rad": float(resolved.get("roll_axis_pitch_rad", 0.0)),
		}
	return {
		"inventory_mass_kg": inventory_mass_kg,
		"non_wheel_inventory_mass_kg": non_wheel_inventory_mass_kg,
		"base_budget_kg": inventory_base_budget_kg,
		"unsprung_mass_kg": unsprung_mass_kg.duplicate(),
		"fuel_tank_position": [fuel_tank_position_local.x, fuel_tank_position_local.y, fuel_tank_position_local.z],
		"pre_recenter_com": [audit_pre_recenter_com.x, audit_pre_recenter_com.y, audit_pre_recenter_com.z],
		"pre_recenter_sprung_mass_kg": audit_pre_recenter_sprung_mass_kg,
		"recenter_shift": [audit_recenter_shift.x, audit_recenter_shift.y, audit_recenter_shift.z],
		"recenter_fdist_target": audit_recenter_fdist_target,
		"recenter_cgz_target": audit_recenter_cgz_target,
		"recenter_clamped": audit_recenter_clamped,
		"wheel_authored_inertia": audit_wheel_authored_inertia.duplicate(),
		"wheel_fallback_inertia": audit_wheel_fallback_inertia.duplicate(),
		"wheel_effective_inertia": wheel_spin_inertia.duplicate(),
		"wheel_inertia_source": audit_wheel_inertia_source.duplicate(),
		"inertia_multipliers": [inertia_multipliers.x, inertia_multipliers.y, inertia_multipliers.z],
		"states": states,
	}


func fuel_remaining_litres(fuel_mass_kg: float) -> float:
	return maxf(fuel_mass_kg, 0.0) / maxf(fuel_density_kg_per_litre, 0.000001)


func _wheel_centres(asset_manifest: Dictionary) -> Array[Vector3]:
	var pivots: Dictionary = asset_manifest.get("wheel_pivots", { })
	var result: Array[Vector3] = []
	for wheel_key in WHEEL_KEYS:
		var wheel: Dictionary = pivots.get(wheel_key, { })
		result.append(_vector_from_document(wheel.get("center_metres", { }), Vector3.ZERO))
	return result


func _vector_from_document(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		return Vector3(
			float(value.get("x", fallback.x)),
			float(value.get("y", fallback.y)),
			float(value.get("z", fallback.z)),
		)
	return fallback


func _inertia_matrix(properties: Dictionary) -> Basis:
	var tensor_doc: Dictionary = properties.get("inertia_about_center_of_mass", { })
	var entries: Variant = tensor_doc.get("entries_kilogram_square_metres", [])
	if not entries is Array or entries.size() != 3:
		return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var rows: Array = entries
	if not rows[0] is Array or not rows[1] is Array or not rows[2] is Array:
		return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	return Basis(
		Vector3(float(rows[0][0]), float(rows[1][0]), float(rows[2][0])),
		Vector3(float(rows[0][1]), float(rows[1][1]), float(rows[2][1])),
		Vector3(float(rows[0][2]), float(rows[1][2]), float(rows[2][2])),
	)


func _inertia_diagonal(properties: Dictionary) -> Vector3:
	var matrix := _inertia_matrix(properties)
	return Vector3(matrix.x.x, matrix.y.y, matrix.z.z)


func _parallel_axis(mass: float, offset: Vector3) -> Basis:
	var d2 := offset.length_squared()
	return Basis(
		Vector3(
			mass * (d2 - offset.x * offset.x),
			-mass * offset.x * offset.y,
			-mass * offset.x * offset.z,
		),
		Vector3(
			-mass * offset.x * offset.y,
			mass * (d2 - offset.y * offset.y),
			-mass * offset.y * offset.z,
		),
		Vector3(
			-mass * offset.x * offset.z,
			-mass * offset.y * offset.z,
			mass * (d2 - offset.z * offset.z),
		),
	)


func _scale_inertia_tensor(t: Basis, m: Vector3) -> Basis:
	var sx := sqrt(m.x)
	var sy := sqrt(m.y)
	var sz := sqrt(m.z)
	return Basis(
		Vector3(t.x.x * m.x, t.x.y * sx * sy, t.x.z * sx * sz),
		Vector3(t.y.x * sy * sx, t.y.y * m.y, t.y.z * sy * sz),
		Vector3(t.z.x * sz * sx, t.z.y * sz * sy, t.z.z * m.z),
	)


func _add_matrix(a: Basis, b: Basis) -> Basis:
	return Basis(a.x + b.x, a.y + b.y, a.z + b.z)
