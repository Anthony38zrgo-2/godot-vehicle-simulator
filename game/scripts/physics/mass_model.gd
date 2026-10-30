class_name VehicleMassModel
extends RefCounted

var chassis_components: Array[Dictionary] = []
var fuel_capacity_kg: float = 0.0
var fuel_density_kg_per_litre: float = 0.0
var fuel_tank_position_local: Vector3 = Vector3.ZERO
var fuel_initial_kg: float = 0.0
var wheel_spin_inertia: Array[float] = [0.8, 0.8, 0.8, 0.8]
var inventory_mass_kg: float = 0.0
var inventory_base_budget_kg: float = 0.0
var non_wheel_inventory_mass_kg: float = 0.0
var unsupported_attachment_components: PackedStringArray = PackedStringArray()
var unsprung_mass_kg: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_centres_local: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]

const WHEEL_NAMES := ["FrontLeft", "FrontRight", "RearLeft", "RearRight"]
const WHEEL_KEYS := ["front_left", "front_right", "rear_left", "rear_right"]


func configure(domains: Dictionary, asset_manifest: Dictionary) -> Dictionary:
	chassis_components.clear()
	unsprung_mass_kg.fill(0.0)
	wheel_spin_inertia.fill(0.0)
	unsupported_attachment_components.clear()
	var chassis_doc: Dictionary = domains.get("chassis", { })
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
		var w_mass := maxf(rotating_wheel_masses[i], unsprung_mass_kg[i] * 0.55)
		var fallback_inertia := maxf(0.55 * w_mass * r * r, 0.35)
		if wheel_spin_inertia[i] <= 0.05:
			wheel_spin_inertia[i] = fallback_inertia
		else:
			wheel_spin_inertia[i] = maxf(wheel_spin_inertia[i], fallback_inertia * 0.5)

	var fuel: Dictionary = domains.get("fuel", { }).get("fuel", { })
	fuel_density_kg_per_litre = float(fuel.get("density_kg_per_litre", 0.74))
	if fuel_density_kg_per_litre <= 0.0:
		return { "ok": false, "error": "fuel.density_kg_per_litre must be positive." }
	fuel_capacity_kg = float(fuel.get("capacity_kg", 0.0))
	fuel_initial_kg = float(fuel.get("initial_kg", fuel_capacity_kg))
	fuel_initial_kg = clampf(fuel_initial_kg, 0.0, fuel_capacity_kg)
	fuel_tank_position_local = _vector_from_document(
		fuel.get("tank_position_local_m", { }),
		Vector3.ZERO,
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


func resolve(fuel_mass_kg: float) -> Dictionary:
	var fuel_mass := clampf(fuel_mass_kg, 0.0, fuel_capacity_kg)
	var total_mass := fuel_mass
	var weighted_center := fuel_tank_position_local * fuel_mass
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
		tensor = _add_matrix(tensor, _parallel_axis(fuel_mass, fuel_tank_position_local - center))

	var ixx := maxf(tensor.x.x, 10.0)
	var iyy := maxf(tensor.y.y, 10.0)
	var izz := maxf(tensor.z.z, 10.0)
	ixx = minf(ixx, iyy + izz - 1.0)
	iyy = minf(iyy, ixx + izz - 1.0)
	izz = minf(izz, ixx + iyy - 1.0)
	var diagonal := Vector3(ixx, iyy, izz)

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
		"inertia_tensor": tensor,
		"fuel_mass_kg": fuel_mass,
		"inventory_mass_kg": inventory_mass_kg,
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


func _add_matrix(a: Basis, b: Basis) -> Basis:
	return Basis(a.x + b.x, a.y + b.y, a.z + b.z)
