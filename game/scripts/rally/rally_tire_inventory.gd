extends RefCounted
class_name RallyTireInventory
## Pool fijo de 10 ruedas con identidad única: montadas + maletera + parque + bajas.
## Sin reposición: mover ≠ crear. Total siempre 10 en modo pool.
const TOTAL_POOL_SIZE := 10
const RIM_DAMAGE_THRESHOLD := 0.005

var mounted: Array = []
var spares: Array = []
var service_stock: Array = []
var discarded: Array = []
var next_id: int = 1
var capacity: int = 2
# One consumable of each type: quick, heavy.
var repair_kits: Array = [true, true]

func item(compound: String, state: Dictionary) -> Dictionary:
	var result := {"id": next_id, "compound_id": compound, "state": state.duplicate(true)}
	next_id += 1
	return result

func total_count() -> int:
	return mounted.size() + spares.size() + service_stock.size() + discarded.size()

func is_pool_mode() -> bool:
	# Modo pool una vez construido el pool de 10 (estrategia inicial).
	# Saves legacy: 4 montados + 0-2 repuestos, sin stock ni bajas.
	return total_count() == TOTAL_POOL_SIZE and not service_stock.is_empty() or total_count() == TOTAL_POOL_SIZE and not discarded.is_empty() or (mounted.size() == 4 and (service_stock.size() + discarded.size() > 0))

func find_tire(tire_id: int) -> Dictionary:
	for arr in [mounted, spares, service_stock, discarded]:
		for t in arr:
			if t is Dictionary and int(t.get("id", 0)) == tire_id:
				return t
	return {}

func _locate(tire_id: int) -> Dictionary:
	# Devuelve {collection:String, index:int} sin exponer referencias internas.
	var collections := {"mounted": mounted, "spares": spares, "service_stock": service_stock, "discarded": discarded}
	for key in collections:
		var arr: Array = collections[key]
		for i in arr.size():
			var t = arr[i]
			if t is Dictionary and int((t as Dictionary).get("id", 0)) == tire_id:
				return {"collection": key, "index": i}
	return {}

func _array_for(name: String) -> Array:
	match name:
		"mounted":
			return mounted
		"spares":
			return spares
		"service_stock":
			return service_stock
		"discarded":
			return discarded
	return []

func swap(wheel: int, spare_id: int, keep_removed: bool) -> bool:
	if wheel < 0 or wheel >= mounted.size():
		return false
	for i in spares.size():
		if spares[i] is Dictionary and int((spares[i] as Dictionary).get("id", 0)) == spare_id:
			var removed: Dictionary = mounted[wheel]
			mounted[wheel] = spares[i]
			spares.remove_at(i)
			if keep_removed:
				if spares.size() < capacity:
					spares.append(removed)
				else:
					service_stock.append(removed)
			else:
				discarded.append(removed)
			return true
	return false

func discard(spare_id: int) -> bool:
	for i in spares.size():
		if spares[i] is Dictionary and int((spares[i] as Dictionary).get("id", 0)) == spare_id:
			var removed: Dictionary = spares[i]
			spares.remove_at(i)
			discarded.append(removed)
			return true
	return false

## Mueve una rueda existente entre colecciones sin crear ni duplicar.
## 'mounted' siempre mantiene 4 huecos: mounted->mounted intercambia,
## colección->mounted intercambia con la desplazada. Nunca deja 3 montadas.
func move_tire(tire_id: int, target_collection: String, target_wheel: int = -1) -> bool:
	var loc := _locate(tire_id)
	if loc.is_empty():
		return false
	var from_name := str(loc["collection"])
	var from_idx := int(loc["index"])
	if target_collection == "mounted":
		if target_wheel < 0 or target_wheel >= 4:
			return false
		if mounted.size() != 4:
			return false
		if from_name == "mounted":
			if from_idx == target_wheel:
				return true
			var tmp: Dictionary = mounted[from_idx]
			mounted[from_idx] = mounted[target_wheel]
			mounted[target_wheel] = tmp
			return true
		var src: Array = _array_for(from_name)
		var tire: Dictionary = src[from_idx]
		var displaced: Dictionary = mounted[target_wheel]
		src.remove_at(from_idx)
		mounted[target_wheel] = tire
		src.append(displaced)
		return true
	elif target_collection == "spares":
		if from_name == "spares":
			return true
		if from_name == "mounted":
			return false # Usar swap_mounted para no dejar 3 montadas.
		if spares.size() >= capacity:
			return false
		var src: Array = _array_for(from_name)
		var tire: Dictionary = src[from_idx]
		src.remove_at(from_idx)
		spares.append(tire)
		return true
	elif target_collection == "service_stock":
		if from_name == "service_stock":
			return true
		if from_name == "mounted":
			return false
		var src: Array = _array_for(from_name)
		var tire: Dictionary = src[from_idx]
		src.remove_at(from_idx)
		service_stock.append(tire)
		return true
	elif target_collection == "discarded":
		if from_name == "discarded":
			return true
		if from_name == "mounted":
			return false
		var src: Array = _array_for(from_name)
		var tire: Dictionary = src[from_idx]
		src.remove_at(from_idx)
		discarded.append(tire)
		return true
	return false

## Intercambio seguro montada<->colección (usado por servicio/garaje si hiciera falta).
func swap_mounted(wheel: int, other_collection: String, other_index: int) -> bool:
	if wheel < 0 or wheel >= mounted.size() or mounted.size() != 4:
		return false
	var other: Array = _array_for(other_collection)
	if other_collection == "mounted" or other.is_empty() or other_index < 0 or other_index >= other.size():
		return false
	if other_collection == "spares" or other_collection == "service_stock":
		var a: Dictionary = mounted[wheel]
		var b: Dictionary = other[other_index]
		mounted[wheel] = b
		other[other_index] = a
		return true
	return false

func is_punctured(tire: Dictionary) -> bool:
	if tire.is_empty():
		return false
	var state: Dictionary = tire.get("state", {})
	return float(state.get("pressure_loss_fraction", 0.0)) > 0.0 or float(state.get("leak_per_second", 0.0)) > 0.0

func is_rim_damaged(tire: Dictionary) -> bool:
	if tire.is_empty():
		return false
	var state: Dictionary = tire.get("state", {})
	return float(state.get("rim_deformation", 0.0)) > RIM_DAMAGE_THRESHOLD

func is_carcass_destroyed(tire: Dictionary) -> bool:
	if tire.is_empty():
		return false
	var state: Dictionary = tire.get("state", {})
	return float(state.get("carcass_failure", 0.0)) >= 1.0

func repair_puncture(tire: Dictionary) -> bool:
	if tire.is_empty():
		return false
	if is_carcass_destroyed(tire):
		return false # Destalonado irreparable: solo retirar o dar de baja.
	var state: Dictionary = tire.get("state", {})
	state["pressure_loss_fraction"] = 0.0
	state["leak_per_second"] = 0.0
	var atmosphere := 1.01325
	var carcass: float = float(state.get("carcass_c", 20.0))
	var pref: float = float(state.get("pressure_reference_bar_gauge", 2.0))
	var tref: float = float(state.get("pressure_reference_temp_c", 20.0))
	state["pressure_bar_gauge"] = (pref + atmosphere) * (carcass + 273.15) / (tref + 273.15) - atmosphere
	tire["state"] = state
	return true

func repair_rim(tire: Dictionary) -> bool:
	if tire.is_empty():
		return false
	if is_carcass_destroyed(tire):
		return false # Un destalonado tampoco admite reparación de rin.
	var state: Dictionary = tire.get("state", {})
	state["rim_deformation"] = 0.0
	tire["state"] = state
	return true

func snapshot() -> Dictionary:
	return {
		"mounted": mounted.duplicate(true),
		"spares": spares.duplicate(true),
		"service_stock": service_stock.duplicate(true),
		"discarded": discarded.duplicate(true),
		"next_id": next_id,
		"repair_kits": repair_kits.duplicate()
	}

func restore(data: Dictionary) -> bool:
	if not data is Dictionary:
		return false
	var kits: Variant = data.get("repair_kits", [true, true])
	if not kits is Array or (kits as Array).size() != 2:
		return false
	for available in (kits as Array):
		if not available is bool:
			return false
	var loaded: Array = data.get("mounted", [])
	var carried: Array = data.get("spares", [])
	var stock: Array = data.get("service_stock", [])
	var disc: Array = data.get("discarded", [])
	if loaded.size() != 4:
		return false
	if carried.size() > capacity:
		return false
	if loaded.size() + carried.size() + stock.size() + disc.size() > TOTAL_POOL_SIZE:
		return false
	var seen := {}
	var highest := 0
	for tire in loaded + carried + stock + disc:
		if not tire is Dictionary:
			return false
		var td: Dictionary = tire
		if not td.get("state", null) is Dictionary:
			return false
		if not RallyTireCompound.is_valid(str(td.get("compound_id", ""))):
			return false
		var tire_id := int(td.get("id", 0))
		if tire_id <= 0 or seen.has(tire_id):
			return false
		seen[tire_id] = true
		highest = maxi(highest, tire_id)
	repair_kits = (kits as Array).duplicate()
	mounted = loaded.duplicate(true)
	spares = carried.duplicate(true)
	service_stock = stock.duplicate(true)
	discarded = disc.duplicate(true)
	next_id = maxi(highest + 1, int(data.get("next_id", 1)))
	return true
