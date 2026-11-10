extends RefCounted
## Mounted tires and carried complete wheel assemblies share unique identities.
var mounted: Array = []
var spares: Array = []
var next_id: int = 1
var capacity: int = 2
# One consumable of each type: quick, heavy.
var repair_kits: Array = [true, true]

func item(compound: String, state: Dictionary) -> Dictionary:
	var result := {"id": next_id, "compound_id": compound, "state": state.duplicate(true)}
	next_id += 1
	return result

func swap(wheel: int, spare_id: int, keep_removed: bool) -> bool:
	if wheel < 0 or wheel >= mounted.size():
		return false
	for i in spares.size():
		if int(spares[i].id) == spare_id:
			var removed: Dictionary = mounted[wheel]
			mounted[wheel] = spares[i]
			spares.remove_at(i)
			if keep_removed:
				spares.append(removed)
			return true
	return false

func discard(spare_id: int) -> bool:
	for i in spares.size():
		if int(spares[i].id) == spare_id:
			spares.remove_at(i)
			return true
	return false

func snapshot() -> Dictionary:
	return {"mounted": mounted.duplicate(true), "spares": spares.duplicate(true), "next_id": next_id, "repair_kits": repair_kits.duplicate()}

func restore(data: Dictionary) -> bool:
	var kits: Variant = data.get("repair_kits", [true, true])
	if not kits is Array or kits.size() != 2:
		return false
	for available in kits:
		if not available is bool:
			return false
	var loaded: Array = data.get("mounted", [])
	var carried: Array = data.get("spares", [])
	if loaded.size() != 4 or carried.size() > capacity:
		return false
	var seen := {}
	var highest := 0
	for tire in loaded + carried:
		if not tire is Dictionary or not tire.get("state", null) is Dictionary or not RallyTireCompound.is_valid(str(tire.get("compound_id", ""))):
			return false
		var id := int(tire.get("id", 0))
		if id <= 0 or seen.has(id):
			return false
		seen[id] = true
		highest = maxi(highest, id)
	repair_kits = kits.duplicate()
	mounted = loaded.duplicate(true)
	spares = carried.duplicate(true)
	next_id = maxi(highest + 1, int(data.get("next_id", 1)))
	return true
