extends Node3D
## Deterministic spectators, grazing herds and stones for the Rajuntay verges.

const ASSETS := "res://assets/rally/cdi_stage1/props/"
const CELL_M := 24.0
const SPECTATOR := "people"
const ANIMAL := "animals"
const STONE := "rocks"
const STONE_COUNT := 200
const ROUTE_SPECTATOR_GROUPS := 9
const START_SPECTATORS := 8
const BEHIND_START_SPECTATORS := 5
const SPECTATORS_PER_GROUP := 6
const FINISH_SPECTATORS := 5
const HERD_COUNT := 9
const ANIMALS_PER_HERD := 5
const TALUS_STONE_PROFILE := {
	"offset": Vector2(5.0, 17.0), "size": Vector2(0.80, 1.85), "wide_clearance": true, "talus": true,
}
const STONE_PROFILES := [
	{"offset": Vector2(4.15, 6.80), "size": Vector2(0.55, 0.90), "wide_clearance": false},
	{"offset": Vector2(4.50, 8.50), "size": Vector2(0.65, 1.05), "wide_clearance": false},
	{"offset": Vector2(5.00, 10.0), "size": Vector2(0.85, 1.45), "wide_clearance": true},
	{"offset": Vector2(5.45, 10.0), "size": Vector2(1.16, 2.12), "wide_clearance": true},
	{"offset": Vector2(11.0, 32.0), "size": Vector2(1.22, 2.75), "wide_clearance": true},
]

var _route: RallyStageProgress
var _space: PhysicsDirectSpaceState3D
var _collision_mask: int
var _rng := RandomNumberGenerator.new()
var _variants := {}
var _road_cells := {}
var _occupied: Array[Vector3] = []
var _placements: Array[Dictionary] = []
var sector_stream: RallyVisualSectorStream
var finish_spectator_approach_m := 30.0

func occupied_points() -> Array[Vector3]:
	return _occupied


func build(route: RallyStageProgress, stage_seed: int, collision_mask: int) -> void:
	_route = route
	_collision_mask = collision_mask
	_space = get_world_3d().direct_space_state
	_build_road_index()
	if not _load_models():
		return
	var length := route.route_distances[-1]
	_rng.seed = stage_seed
	var people := _group(SPECTATOR, START_SPECTATORS, Vector2(-4, 23), Vector2(8, 17), "StartBank")
	people += _group(SPECTATOR, BEHIND_START_SPECTATORS, Vector2(-34, -12), Vector2(8, 17), "BehindStart")
	for i in range(ROUTE_SPECTATOR_GROUPS):
		var zone := _zone(i, ROUTE_SPECTATOR_GROUPS, 150, length - 95)
		people += _group(SPECTATOR, SPECTATORS_PER_GROUP, zone, Vector2(8, 21), "Spectators%02d" % i)
	people += _group(SPECTATOR, FINISH_SPECTATORS, Vector2(length - finish_spectator_approach_m, length + 10.0),
		Vector2(8, 21), "FinishSpectators")
	_rng.seed = stage_seed + 601
	var animals := 0
	for i in range(HERD_COUNT):
		var zone := _zone(i, HERD_COUNT, 210, length - 115)
		animals += _group(ANIMAL, ANIMALS_PER_HERD, zone, Vector2(21, 49), "Herd%02d" % i)
	_rng.seed = stage_seed + 1093
	var rocks := _scatter_rocks(length)
	for placement in _placements:
		var factory := _spawn_placement.bind(placement)
		if sector_stream != null:
			sector_stream.register_content(sector_stream.sector_for_point(placement.point), factory)
		else:
			factory.call(self)
	set_meta("counts", {"people": people, "animals": animals, "rocks": rocks})
	print("CDI_PROPS_READY people=", people, " animals=", animals, " rocks=", rocks)
	var expected_people := START_SPECTATORS + BEHIND_START_SPECTATORS + FINISH_SPECTATORS \
		+ ROUTE_SPECTATOR_GROUPS * SPECTATORS_PER_GROUP
	if people != expected_people or animals != HERD_COUNT * ANIMALS_PER_HERD or rocks != STONE_COUNT:
		push_warning("CDI props could not fill one or more safe placement zones")


func add_parking_spectators(center: Vector3, away: Vector3, along: Vector3, vehicle_half_width: float,
		station: float, parking_covers: Callable) -> int:
	if sector_stream == null or not _variants.has(SPECTATOR):
		return 0
	var added := 0
	for along_offset in [-2.0, 0.0, 2.0, -3.6, 3.6]:
		var point := center + away * (vehicle_half_width + 2.2) + along * float(along_offset)
		if parking_covers.call(point) or not _clear_of_road(point, 7.0) or not _spaced(point, _occupied, 1.1):
			continue
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.0, point - Vector3.UP * 3.0, _collision_mask)
		var hit := _space.intersect_ray(query)
		if hit.is_empty() or not hit.collider.is_in_group("RauraGrassGround") or (hit.normal as Vector3).y < 0.89:
			continue
		var ground: Vector3 = hit.position
		var variants: Array = _variants[SPECTATOR]
		var variant: Dictionary = variants[_rng.randi_range(0, variants.size() - 1)]
		var placement := {"group": "PublicoRellano", "kind": SPECTATOR, "variant": variant,
			"point": ground, "size": _rng.randf_range(0.82, 0.98), "yaw": 0.0, "station": station}
		sector_stream.register_content(sector_stream.sector_for_point(ground), _spawn_placement.bind(placement))
		_occupied.append(ground)
		added += 1
		if added == 3:
			break
	return added


func _zone(index: int, count: int, first: float, last: float) -> Vector2:
	return Vector2(lerpf(first, last, float(index) / count),
		lerpf(first, last, float(index + 1) / count))


func _group(kind: String, count: int, zone: Vector2, offsets: Vector2, group_name: String) -> int:
	var anchor := Vector3.ZERO
	for attempt in range(285):
		var station := _rng.randf_range(zone.x, zone.y)
		var offset := _rng.randf_range(offsets.x, offsets.y)
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var hit := _ground(kind, station, side * offset)
		if hit.is_empty():
			continue
		anchor = hit.position
		var spots: Array[Vector3] = [anchor]
		var spacing := 0.80 if kind == SPECTATOR else 1.45
		var depth := 6.0 if kind == SPECTATOR else 11.0
		for member_attempt in range(100):
			var s := station + _rng.randf_range(-depth, depth)
			var t := side * clampf(offset + _rng.randf_range(-4.5, 4.5), offsets.x, offsets.y)
			var member := _ground(kind, s, t)
			if member.is_empty():
				continue
			var point: Vector3 = member.position
			if absf(point.y - anchor.y) <= 3.5 and _spaced(point, spots, spacing):
				spots.append(point)
				if spots.size() == count:
					break
		if spots.size() != count:
			continue
		var variants: Array = _variants[kind]
		var herd := _rng.randi_range(0, variants.size() - 1) if kind == ANIMAL else -1
		var scale_factor := 0.90 if kind == SPECTATOR else 1.0
		for point in spots:
			var variant := herd if herd >= 0 else _rng.randi_range(0, variants.size() - 1)
			_placements.append({"group": group_name, "kind": kind, "variant": variants[variant], "point": point,
				"size": _rng.randf_range(0.90, 1.10) * scale_factor, "yaw": 0.0, "station": station})
		_occupied.append_array(spots)
		return count
	push_warning("No suitable terrain for " + group_name)
	return 0


func _scatter_rocks(length: float) -> int:
	var placed := 0
	var variants: Array = _variants[STONE].duplicate()
	var profiles := STONE_PROFILES.duplicate()
	for i in range(STONE_COUNT):
		# Reshuffle each cycle so each model can appear at different sizes.
		if i % variants.size() == 0:
			_shuffle(variants)
		if i % profiles.size() == 0:
			_shuffle(profiles)
		var variant: Dictionary = variants[i % variants.size()]
		var chosen: Dictionary = profiles[i % profiles.size()]
		var zone := _zone(i, STONE_COUNT, 8, length - 20)
		if i % 5 == 0 and _place_rock(variant, TALUS_STONE_PROFILE, zone):
			placed += 1
			continue
		if _place_rock(variant, chosen, zone):
			placed += 1
		else:
			# Preserve the slot and model if this section has no room for its
			# chosen size. Never relax the road clearance to fit a large stone.
			if _place_rock(variant, STONE_PROFILES[0], zone):
				placed += 1
	return placed


func _place_rock(variant: Dictionary, profile: Dictionary, zone: Vector2) -> bool:
	var talus: bool = profile.get("talus", false)
	for attempt in range(80 if talus else 220):
		var station := _rng.randf_range(zone.x, zone.y)
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var distance := _rng.randf_range(profile.offset.x, profile.offset.y)
		var size := _rng.randf_range(profile.size.x, profile.size.y)
		var hit := _ground(STONE, station, side * distance, size if profile.wide_clearance else 0.0, talus)
		if hit.is_empty():
			continue
		var position: Vector3 = hit.position
		var group := "TalusStones" if talus else "Stones"
		var base := position - Vector3.UP * (size * 0.12 if talus else 0.0)
		_placements.append({"group": group, "kind": STONE, "variant": variant, "point": base,
			"size": size, "yaw": _rng.randf_range(0.0, TAU), "station": station,
			"lateral": distance})
		_occupied.append(position)
		return true
	return false


func _spawn_placement(parent: Node3D, info: Dictionary) -> void:
	var group := parent.get_node_or_null(NodePath(info.group)) as Node3D
	if group == null:
		group = Node3D.new()
		group.name = info.group
		group.set_meta("category", info.kind)
		parent.add_child(group)
	var instance := _add_prop(group, info.variant, info.point, info.size, info.yaw)
	instance.set_meta("station_m", info.station)
	if info.has("lateral"):
		instance.set_meta("lateral_m", info.lateral)
	if info.kind == STONE:
		_add_rock_collision(instance, info.variant.hull, info.size)


func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var item: Variant = items[i]
		items[i] = items[j]
		items[j] = item


func _add_prop(parent: Node3D, entry: Dictionary, point: Vector3, size: float, yaw: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = entry.label
	instance.mesh = entry.mesh
	instance.material_override = entry.material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if sector_stream == null:
		instance.visibility_range_end = 395.0
		instance.visibility_range_end_margin = 20.0
	instance.rotation.y = yaw
	instance.scale = Vector3.ONE * size
	parent.add_child(instance, true)
	instance.global_position = point - Vector3.UP * 0.025
	return instance


func _add_rock_collision(rock: MeshInstance3D, hull: PackedVector3Array, size: float) -> void:
	var points := PackedVector3Array()
	points.resize(hull.size())
	for i in hull.size():
		points[i] = hull[i] * size
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var body := StaticBody3D.new()
	body.name = "RockCollision"
	body.top_level = true
	body.collision_layer = _collision_mask
	body.collision_mask = 0
	body.set_meta("collision_role", "obstacle")
	rock.add_child(body)
	body.global_transform = Transform3D(rock.global_basis.orthonormalized(), rock.global_position)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)


func _ground(kind: String, station: float, offset: float, solid_diameter: float = 0.0, talus: bool = false) -> Dictionary:
	var distances := _route.route_distances
	var points := _route.points
	var index := clampi(distances.bsearch(station) - 1, 0, points.size() - 2)
	var fraction := (station - distances[index]) / (distances[index+1] - distances[index])
	var center := points[index].lerp(points[index+1], fraction)
	var direction := points[index+1] - points[index]
	var lateral := Vector3.UP.cross(direction).normalized()
	var position := center + lateral * offset
	var clearance := 6.4 if kind == SPECTATOR else (13.0 if kind == ANIMAL else 4.00)
	if solid_diameter > 0.0:
		clearance = 3.75 + solid_diameter * 0.72
	if not _clear_of_road(position, clearance):
		return {}
	var ray := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 25.0,
		position - Vector3.UP * 31.0, _collision_mask)
	var hit := _space.intersect_ray(ray)
	if hit.is_empty():
		return {}
	var ground := hit.collider as StaticBody3D
	var height := float(hit.position.y) - center.y
	if ground == null or ground.get_meta("collision_role", "") != "terrain" or not ground.is_in_group("Dirt"):
		return {}
	if kind != STONE and not ground.is_in_group("RauraGrassGround"):
		return {}
	match kind:
		SPECTATOR:
			if height < 0.55 or hit.normal.y < 0.78:
				return {}
		ANIMAL:
			if height > -1.5 or hit.normal.y < 0.87:
				return {}
		STONE:
			if hit.normal.y < 0.67:
				return {}
			if talus:
				if ground.is_in_group("RauraGrassGround") or height < 0.4 or hit.normal.y > 0.97:
					return {}
			elif height > (-0.12 if solid_diameter > 0.0 else 1.4):
				return {}
	if not _spaced(hit.position, _occupied, 1.2 if kind != ANIMAL else 1.9):
		return {}
	return hit


func _spaced(point: Vector3, others: Array[Vector3], minimum: float) -> bool:
	for other in others:
		if Vector2(point.x - other.x, point.z - other.z).length_squared() < minimum * minimum:
			return false
	return true


func _build_road_index() -> void:
	var points := _route.points
	var first := points[0] - (points[1] - points[0]).normalized() * 50.0
	for i in range(-1, points.size() - 1):
		var a := first if i < 0 else points[i]
		var b := points[i+1]
		var p := Vector2(a.x, a.z)
		var q := Vector2(b.x, b.z)
		var lower := (p.min(q) - Vector2.ONE * 14.0) / CELL_M
		var upper := (p.max(q) + Vector2.ONE * 14.0) / CELL_M
		for x in range(floori(lower.x), floori(upper.x) + 1):
			for y in range(floori(lower.y), floori(upper.y) + 1):
				var cell := Vector2i(x, y)
				if not _road_cells.has(cell):
					_road_cells[cell] = []
				_road_cells[cell].append([p, q])


func _clear_of_road(point: Vector3, clearance: float) -> bool:
	var position := Vector2(point.x, point.z)
	var cell := Vector2i(floori(position.x / CELL_M), floori(position.y / CELL_M))
	for segment in _road_cells.get(cell, []):
		var closest := Geometry2D.get_closest_point_to_segment(position, segment[0], segment[1])
		if position.distance_squared_to(closest) < clearance * clearance:
			return false
	return true


func _load_models() -> bool:
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(ASSETS + "index.json"))
	if not index is Dictionary:
		push_error("Missing CDI prop index")
		return false
	for kind in [SPECTATOR, ANIMAL, STONE]:
		_variants[kind] = []
		for entry: Dictionary in index.get(kind, []):
			if not entry.get("scatter", true):
				continue
			var path := ASSETS + str(entry.file)
			var packed := load(path) as PackedScene
			if packed == null:
				continue
			var scene := packed.instantiate()
			var mesh_node := scene as MeshInstance3D
			if mesh_node == null:
				var meshes := scene.find_children("*", "MeshInstance3D", true, false)
				if not meshes.is_empty():
					mesh_node = meshes.front() as MeshInstance3D
			if mesh_node != null and mesh_node.mesh != null:
				var material := mesh_node.get_active_material(0) as StandardMaterial3D
				if material != null:
					material = material.duplicate() as StandardMaterial3D
					material.disable_fog = true
					material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
					if kind == STONE:
						var suffix := "" if _variants[kind].size() % 2 == 0 else "_02"
						material.albedo_texture = load(RallyVisualSectorStream.CDI_TEXTURES
							+ "roca_suelta" + suffix + ".png") as Texture2D
						material.albedo_color = Color.WHITE
					else:
						material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
						material.billboard_keep_scale = true
						material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
						material.alpha_scissor_threshold = 0.44
						material.cull_mode = BaseMaterial3D.CULL_DISABLED
						material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
					var variant := {"label": str(entry.file).get_basename(), "mesh": mesh_node.mesh,
						"material": material}
					if kind == STONE:
						var hull := mesh_node.mesh.create_convex_shape(true, true)
						variant["hull"] = hull.points
					_variants[kind].append(variant)
			scene.free()
		if _variants[kind].is_empty():
			push_error("No models for Rajuntay prop category " + kind)
			return false
	return true
