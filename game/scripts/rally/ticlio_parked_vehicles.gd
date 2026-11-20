extends Node3D
## Places only vehicles whose entire footprint is supported outside the road.

const ROOT := "res://assets/rally/cdi_stage4/parked/"
const MODELS := [
	["van", 4.3, 1.61, 1.78],
	["truck", 6.6, 2.73, 2.37],
	["cargo", 7.2, 2.44, 2.76],
	["bus", 9.4, 3.47, 3.94],
]
var _spaces: Array[Dictionary] = []
var _route: Array[Vector3] = []
var _distance := PackedFloat64Array()
var _physics: PhysicsDirectSpaceState3D
var _mask: int
var _stream: RallyVisualSectorStream
var _occupied: Array[Vector3] = []


func build(course: RallyStageProgress, route_doc: Dictionary, mask: int,
		stream: RallyVisualSectorStream, occupied: Array[Vector3], arrival_enabled: bool = true) -> void:
	_route.assign(course.points)
	for xyz: Array in route_doc.get("runout_probes", []):
		_route.append(Vector3(xyz[0], xyz[1], xyz[2]))
	_distance.append(0.0)
	for i in range(1, _route.size()):
		_distance.append(_distance[-1] + _route[i].distance_to(_route[i - 1]))
	_physics = get_world_3d().direct_space_state
	_mask = mask
	_stream = stream
	_occupied = occupied
	if not arrival_enabled:
		return
	var finish := course.route_distances[-1]
	var after_finish := _park(finish + 5.0, _distance[-1] - 3.0, 10, 0)
	var arrival := after_finish
	if arrival < 10:
		arrival += _park(finish - 110.0, finish - 6.0, 10 - arrival, arrival)
	var left_arrival: Array[Dictionary] = []
	for site in _spaces:
		if site.side < 0.0:
			left_arrival.append(site)
	left_arrival.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a.station) - finish - 6.0) < absf(float(b.station) - finish - 6.0))
	for index in mini(left_arrival.size(), 2):
		var site := left_arrival[index]
		_spaces.erase(site)
		arrival -= 1
		if float(site.station) > finish:
			after_finish -= 1
	var uphill := _park(finish - 180.0, finish - 15.0, 5, 3)
	if uphill < 5:
		uphill += _park(finish - 1400.0, finish - 185.0, 5 - uphill, uphill)
	for site in _spaces:
		var p: Vector3 = site.point
		_stream.register_content(_stream.sector_for_point(p), _spawn.bind(site.model, p, site.forward, site.up))
	set_meta("arrival_count", arrival)
	set_meta("uphill_count", uphill)
	print("TICLIO_PARKED arrival=", arrival, " uphill=", uphill, " after_finish=", after_finish)
	_place_monuments(finish)
	_place_buildings(finish)


func _place_monuments(finish: float) -> void:
	var parking_end := finish
	for site in _spaces:
		parking_end = maxf(parking_end, float(site.end_station))
	var first := maxf(finish + 28.0, parking_end + 3.0)
	for station in range(ceili(first), floori(_distance[-1]) + 1):
		var i := clampi(_distance.bsearch(float(station)), 1, _route.size() - 1)
		var a := _route[i - 1]
		var b := _route[i]
		var center := a.lerp(b, inverse_lerp(_distance[i - 1], _distance[i], station))
		var delta := b - a
		var forward := Vector3(delta.x, 0.0, delta.z).normalized()
		var right := forward.cross(Vector3.UP)
		var left_foot := _monument_ground(center - right * 4.93)
		var right_foot := _monument_ground(center + right * 4.93)
		if left_foot.is_empty() or right_foot.is_empty():
			continue
		var left_y := float(left_foot.position.y)
		var right_y := float(right_foot.position.y)
		if absf(left_y - right_y) > 0.82:
			continue
		var arch := Vector3(center.x, maxf(left_y, right_y) - 0.13, center.z)
		var sign_center := center + right * 8.10
		var sign_left := _monument_ground(sign_center - right * 1.22)
		var sign_right := _monument_ground(sign_center + right * 1.22)
		if sign_left.is_empty() or sign_right.is_empty() or absf(float(sign_left.position.y) - float(sign_right.position.y)) > 0.55:
			continue
		sign_center.y = maxf(float(sign_left.position.y), float(sign_right.position.y)) - 0.19
		_stream.register_content(_stream.sector_for_point(arch), _spawn_monument.bind(
			"arco_ticlio", arch, forward, 4.93, Vector3(1.06, 3.80, 0.69)))
		_stream.register_content(_stream.sector_for_point(sign_center), _spawn_monument.bind(
			"cartel_verde_ticlio", sign_center, forward, 1.22, Vector3(0.28, 3.16, 0.30)))
		set_meta("monument_station_m", station)
		set_meta("parking_end_m", parking_end)
		print("TICLIO_MONUMENTS_READY station_m=", station, " parking_end_m=", parking_end)
		return
	push_error("No roadside support for the two Ticlio monuments beyond the parked vehicles")


func _monument_ground(point: Vector3, reach: float = 3.0) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * reach, point - Vector3.UP * (reach + 1.0), _mask)
	var hit := _physics.intersect_ray(query)
	if hit.is_empty() or hit.collider.get_meta("collision_role", "") != "terrain" or hit.collider.get_meta("is_stage_road", false):
		return {}
	return hit


func _spawn_monument(parent: Node3D, asset: String, point: Vector3, forward: Vector3,
		post_offset: float, post_size: Vector3) -> void:
	var packed := load("res://assets/rally/cdi_stage4/monumentos/" + asset + ".glb") as PackedScene
	if packed == null:
		return
	var monument := StaticBody3D.new()
	monument.name = asset
	monument.collision_layer = _mask
	monument.collision_mask = 0
	parent.add_child(monument)
	monument.global_transform = Transform3D(Basis.looking_at(-forward, Vector3.UP, true), point)
	monument.add_child(packed.instantiate())
	for side in [-1.0, 1.0]:
		var shape := BoxShape3D.new()
		shape.size = post_size
		var support := CollisionShape3D.new()
		support.shape = shape
		support.position = Vector3(post_offset * float(side), post_size.y * 0.5, 0.0)
		monument.add_child(support)


func _place_buildings(finish: float) -> void:
	var count := 0
	var gate := float(get_meta("monument_station_m", finish + 28.0))
	count += int(_place_building("casa_azul", gate - 22.0, -1.0, [11.5, 14.0, 16.0, 18.0, 20.0, 23.0, 26.0, 30.0], Vector3(13.4, 3.0, 7.5)))
	count += int(_place_building("cobertizo", gate - 31.0, -1.0, [23.0, 26.0, 20.0, 30.0, 33.0, 17.0], Vector3(6.6, 2.8, 4.1)))
	count += int(_place_building("galpon", gate - 17.0, -1.0, [27.0, 30.0, 24.0], Vector3(9.0, 3.7, 5.0)))
	count += int(_place_building("casa_adobe", gate - 46.0, 1.0, [23.0, 26.0, 20.0], Vector3(13.4, 3.0, 7.5)))
	set_meta("building_count", count)
	print("TICLIO_BUILDINGS_READY count=", count)


func _place_building(asset: String, pk: float, side: float, offsets: Array, size: Vector3) -> bool:
	for offset in offsets:
		for adjustment in [0.0, -4.0, 4.0, -7.0, 7.0, -10.0, 10.0, -14.0, 14.0, -17.0, -21.0, -28.0, -36.0, -48.0]:
			var station := pk + float(adjustment)
			if station + size.x * 0.5 >= float(get_meta("monument_station_m", _distance[-1])):
				continue
			var i := clampi(_distance.bsearch(station), 1, _route.size() - 1)
			var a := _route[i - 1]
			var b := _route[i]
			var center := a.lerp(b, inverse_lerp(_distance[i - 1], _distance[i], station))
			var delta := b - a
			var along := Vector3(delta.x, 0.0, delta.z).normalized()
			var toward_road := along.cross(Vector3.UP) * -side
			var p := center - toward_road * float(offset)
			var half_depth := size.z * 0.5 + 0.75
			var half_width := size.x * 0.5 + 0.75
			var blocked := false
			for site in _spaces:
				if _overlaps(site, p - site.point, toward_road, along, half_depth, half_width):
					blocked = true
					break
			if blocked:
				continue
			var low := INF
			var high := -INF
			for x in [-1.0, 0.0, 1.0]:
				for z in [-1.0, 0.0, 1.0]:
					var corner := p + along * (size.x * 0.5 * float(x)) + toward_road * (size.z * 0.5 * float(z))
					var hit := _monument_ground(corner, 10.0)
					if hit.is_empty():
						blocked = true
						break
					low = minf(low, float(hit.position.y))
					high = maxf(high, float(hit.position.y))
				if blocked:
					break
			if blocked or high - low > 2.8:
				continue
			p.y = high - 0.12
			_spaces.append({"point": p, "forward": toward_road, "right": along,
				"length": half_depth, "width": half_width, "end_station": station + half_width})
			_stream.register_content(_stream.sector_for_point(p), _spawn_building.bind(asset, p, toward_road, size, p.y - low))
			print("TICLIO_BUILDING ", asset, " pk=", station, " offset=", offset)
			return true
	push_warning("No free ground for " + asset + " at Ticlio")
	return false


func _spawn_building(parent: Node3D, asset: String, point: Vector3, facing: Vector3, size: Vector3, foundation: float) -> void:
	var packed := load("res://assets/rally/cdi_stage4/construcciones/" + asset + ".glb") as PackedScene
	if packed == null:
		return
	var building := StaticBody3D.new()
	building.name = asset
	building.collision_layer = _mask
	building.collision_mask = 0
	parent.add_child(building)
	building.global_transform = Transform3D(Basis.looking_at(facing, Vector3.UP, true), point)
	building.add_child(packed.instantiate())
	var support := MeshInstance3D.new()
	var block := BoxMesh.new()
	block.size = Vector3(size.x * 0.86, maxf(foundation + 0.10, 0.15), size.z * 0.76)
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.34, 0.32, 0.28)
	concrete.roughness = 0.95
	block.material = concrete
	support.mesh = block
	support.position.y = -block.size.y * 0.5 + 0.01
	building.add_child(support)
	var box := BoxShape3D.new()
	box.size = Vector3(size.x * 0.86, size.y + block.size.y, size.z * 0.76)
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position.y = (size.y - block.size.y) * 0.5
	building.add_child(collision)


func covers(point: Vector3) -> bool:
	for site in _spaces:
		var delta: Vector3 = point - site.point
		if absf(delta.dot(site.forward)) <= float(site.length) and absf(delta.dot(site.right)) <= float(site.width):
			return true
	return false


func add_viewing_group(pk: float, side: float, offset: float, props: Node3D) -> void:
	var start := _spaces.size()
	var count := _park(pk - 8.0, pk + 8.0, 2, 0, [side], [offset, offset + 2.0, offset - 2.0])
	var people := 0
	for index in range(start, _spaces.size()):
		var site := _spaces[index]
		var point: Vector3 = site.point
		_stream.register_content(_stream.sector_for_point(point), _spawn.bind(site.model, point, site.forward, site.up))
		var inward: Vector3 = site.right * side
		people += int(props.add_parking_spectators(point, inward, site.forward, float(site.width), float(site.station), covers))
	var groups: Dictionary = get_meta("viewing_groups", {})
	groups[int(pk)] = {"vehicles": count, "people": people}
	set_meta("viewing_groups", groups)
	print("CDI_VIEWING_GROUP pk=", int(pk), " vehicles=", count, " people=", people)


func _park(first: float, last: float, count: int, phase: int, sides: Array = [-1.0, 1.0],
		offsets: Array = [5.8, 7.8, 10.2, 13.0, 16.5, 20.0]) -> int:
	var placed := 0
	for station in range(ceili(first), floori(last) + 1, 2):
		var i := clampi(_distance.bsearch(float(station)), 1, _route.size() - 1)
		var a := _route[i - 1]
		var b := _route[i]
		var center := a.lerp(b, inverse_lerp(_distance[i - 1], _distance[i], station))
		var delta := _route[mini(i + 1, _route.size() - 1)] - _route[maxi(i - 2, 0)]
		var forward := Vector3(delta.x, 0.0, delta.z).normalized()
		var right := forward.cross(Vector3.UP)
		for side in sides:
			var model: Array = MODELS[(placed + phase) % MODELS.size()]
			for offset in offsets:
				var candidate: Vector3 = center + right * side * offset
				var half_length := float(model[1]) * 0.5 + 0.48
				var half_width := float(model[2]) * 0.5 + 0.47
				if sides.size() == 1:
					# The pull-off must have an open approach from this side of the road.
					var approach := center + right * float(side) * 3.2 + Vector3.UP * 0.66
					var lane := PhysicsRayQueryParameters3D.create(approach, candidate + Vector3.UP * 0.66, _mask)
					var obstacle := _physics.intersect_ray(lane)
					if not obstacle.is_empty() and obstacle.collider.get_meta("collision_role", "") == "barrier":
						continue
				var ground := _fit(candidate, forward, right, half_length, half_width, i)
				if ground.is_empty():
					continue
				var p: Vector3 = ground.position
				_spaces.append({"point": p, "forward": forward, "right": right, "model": model,
					"length": half_length, "width": half_width, "end_station": station + half_length,
					"station": station, "side": side, "up": ground.up})
				placed += 1
				if placed == count:
					return placed
				break
	return placed


func _fit(candidate: Vector3, forward: Vector3, right: Vector3, length: float, width: float, road_index: int) -> Dictionary:
	for site in _spaces:
		var delta: Vector3 = candidate - site.point
		if _overlaps(site, delta, forward, right, length, width):
			return {}
	for p in _occupied:
		var delta := p - candidate
		if absf(delta.dot(forward)) < length + 1.4 and absf(delta.dot(right)) < width + 1.4:
			return {}
	var ground := _ray(candidate)
	if ground.is_empty():
		return {}
	var up: Vector3 = ground.normal
	var center: Vector3 = ground.position
	if up.y < 0.985:
		return {}
	for longitudinal in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for lateral in [-1.0, 0.0, 1.0]:
			var shift: Vector3 = forward * length * longitudinal + right * width * lateral
			var p: Vector3 = center + shift
			for j in range(maxi(0, road_index - 14), mini(_route.size() - 1, road_index + 14)):
				var a := Vector2(_route[j].x, _route[j].z)
				var b := Vector2(_route[j + 1].x, _route[j + 1].z)
				var sample := Vector2(p.x, p.z)
				if sample.distance_squared_to(Geometry2D.get_closest_point_to_segment(sample, a, b)) < 3.65 * 3.65:
					return {}
			var hit := _ray(p)
			if hit.is_empty() or (hit.normal as Vector3).y < 0.96:
				return {}
			var expected := center.y - up.dot(shift) / up.y
			if absf(float(hit.position.y) - expected) > 0.23:
				return {}
	return {"position": center, "up": up}


func _overlaps(site: Dictionary, delta: Vector3, forward: Vector3, right: Vector3, length: float, width: float) -> bool:
	for axis: Vector3 in [forward, right, site.forward, site.right]:
		var extent := absf(axis.dot(forward)) * length + absf(axis.dot(right)) * width 			+ absf(axis.dot(site.forward)) * float(site.length) + absf(axis.dot(site.right)) * float(site.width)
		if absf(delta.dot(axis)) > extent:
			return false
	return true


func _ray(p: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.2, p - Vector3.UP * 2.2, _mask)
	var hit := _physics.intersect_ray(q)
	if hit.is_empty() or not hit.collider.is_in_group("RauraGrassGround"):
		return {}
	return hit


func _spawn(parent: Node3D, model: Array, p: Vector3, forward: Vector3, up: Vector3) -> void:
	var packed := load(ROOT + str(model[0]) + ".glb") as PackedScene
	var body := StaticBody3D.new()
	body.name = "Parked_" + str(model[0])
	body.collision_layer = _mask
	body.collision_mask = 0
	parent.add_child(body)
	body.global_transform = Transform3D(Basis.looking_at(forward, up), p + Vector3.UP * 0.04)
	body.add_child(packed.instantiate())
	var box := BoxShape3D.new()
	box.size = Vector3(float(model[2]), float(model[3]), float(model[1]))
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position.y = box.size.y * 0.5
	body.add_child(collision)
