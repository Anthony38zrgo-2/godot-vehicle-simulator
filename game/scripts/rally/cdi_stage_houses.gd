extends Node3D
## Places PSX Andean modular houses in low, flat roadside zones on CDI stages.

const HOUSE_DIR := "res://assets/rally/CDI/casas_andinas/glb/"

# Stage house placement specs:
#   asset: glb filename (without .glb)
#   pk: preferred timed route station (m) in the lowest & flattest basin
#   side: +1.0 = right, -1.0 = left
#   offsets: candidate lateral offsets from centerline (m)
#   size: Vector3(width_x, height_y, depth_z) for footprint flatness & collision
const STAGE_HOUSES := {
	"cdi_stage2": [
		{
			"asset": "04_quincha_calamina_un_agua",
			"pk": 4945.0,
			"side": 1.0,
			"offsets": [12.5, 14.5, 10.5, 17.0, 20.0],
			"size": Vector3(5.6, 3.6, 4.4),
		},
	],
	"cdi_stage3": [
		{
			"asset": "01_rural_blanco_humo_teja",
			"pk": 1918.0,
			"side": 1.0,
			"offsets": [18.0, 20.5, 16.0, 23.0],
			"size": Vector3(6.4, 4.2, 5.0),
		},
		{
			"asset": "04_quincha_calamina_un_agua",
			"pk": 1958.0,
			"side": 1.0,
			"offsets": [17.5, 20.0, 15.5, 22.5],
			"size": Vector3(5.6, 3.6, 4.4),
		},
		{
			"asset": "09_quincha_doble_calamina",
			"pk": 2050.0,
			"side": 1.0,
			"offsets": [22.0, 24.5, 19.5, 27.0, 17.5],
			"size": Vector3(8.6, 3.6, 6.2),
		},
	],
}

var _placements: Array[Dictionary] = []
var _mask: int = 0
var _space: PhysicsDirectSpaceState3D
var _stream: RallyVisualSectorStream


func build(stage_id: String, course: RallyStageProgress, mask: int,
		stream: RallyVisualSectorStream, occupied: Array[Vector3]) -> void:
	var specs: Array = STAGE_HOUSES.get(stage_id, [])
	if specs.is_empty() or stream == null:
		return
	_mask = mask
	_stream = stream
	_space = get_world_3d().direct_space_state
	_placements.clear()

	for spec: Dictionary in specs:
		_place_house(course, spec, occupied)

	set_meta("house_count", _placements.size())
	set_meta("placements", _placements)
	print("CDI_HOUSES_READY stage=", stage_id, " count=", _placements.size())


func covers(point: Vector3) -> bool:
	for site in _placements:
		var delta: Vector3 = point - (site.point as Vector3)
		var fwd: Vector3 = site.facing
		var right: Vector3 = site.right
		if absf(delta.dot(fwd)) <= float(site.half_depth) and absf(delta.dot(right)) <= float(site.half_width):
			return true
	return false


func occupied_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for site in _placements:
		pts.append(site.point as Vector3)
	return pts


func _ray_terrain(point: Vector3, reach: float = 14.0) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * reach, point - Vector3.UP * (reach + 10.0), _mask)
	var hit := _space.intersect_ray(q)
	if hit.is_empty():
		return {}
	var col: Node = hit.collider
	if col.get_meta("collision_role", "") != "terrain" or col.get_meta("is_stage_road", false):
		return {}
	return hit


func _place_house(course: RallyStageProgress, spec: Dictionary, occupied: Array[Vector3]) -> bool:
	var asset: String = str(spec["asset"])
	var base_pk: float = float(spec["pk"])
	var side: float = float(spec["side"])
	var offsets: Array = spec["offsets"]
	var size: Vector3 = spec["size"]
	var dists := course.route_distances
	var pts := course.points
	var total := float(dists[-1])

	for off_v in offsets:
		var offset := float(off_v)
		for delta_pk: float in [0.0, -10.0, 10.0, -20.0, 20.0, -32.0, 32.0, -48.0, 48.0, -64.0, 64.0]:
			var pk := clampf(base_pk + delta_pk, 20.0, total - 15.0)
			var i := clampi(dists.bsearch(pk), 2, pts.size() - 3)
			var center := pts[i - 1].lerp(pts[i], inverse_lerp(dists[i - 1], dists[i], pk))
			var heading := pts[i + 1] - pts[i - 2]
			var along := Vector3(heading.x, 0.0, heading.z).normalized()
			var right_road := along.cross(Vector3.UP)
			var outward := right_road * side
			var facing := -outward  # Front door (+Z) faces directly toward the road
			var p := center + outward * offset
			var half_w := size.x * 0.5 + 3.8
			var half_d := size.z * 0.5 + 3.8

			# Avoid overlapping previously placed houses or spectator/prop points
			var blocked := false
			for existing in _placements:
				if (p - (existing.point as Vector3)).length() < (half_w + float(existing.half_width) + 2.0):
					blocked = true
					break
			if blocked:
				continue
			for occ in occupied:
				var d := occ - p
				if absf(d.dot(facing)) < size.z * 0.5 + 2.0 and absf(d.dot(along)) < size.x * 0.5 + 2.0:
					blocked = true
					break
			if blocked:
				continue

			# Verify 3x3 terrain support & flatness across the house footprint
			var lo := INF
			var hi := -INF
			var min_ny := 1.0
			for gx: float in [-1.0, 0.0, 1.0]:
				for gz: float in [-1.0, 0.0, 1.0]:
					var sample := p + along * (size.x * 0.5 * gx) + facing * (size.z * 0.5 * gz)
					var hit := _ray_terrain(sample, 14.0)
					if hit.is_empty():
						blocked = true
						break
					lo = minf(lo, float(hit.position.y))
					hi = maxf(hi, float(hit.position.y))
					min_ny = minf(min_ny, float((hit.normal as Vector3).y))
				if blocked:
					break
			if blocked or (hi - lo) > 1.25 or min_ny < 0.88:
				continue

			# House GLB already has a 2.4m stone foundation skirt below y=0;
			# seat threshold flush with high corner so no edge ever floats.
			p.y = hi - 0.06
			var record := {
				"asset": asset,
				"pk": pk,
				"side": side,
				"offset": offset,
				"point": p,
				"facing": facing,
				"right": along,
				"size": size,
				"half_width": half_w,
				"half_depth": half_d,
				"relief": hi - lo,
			}
			_placements.append(record)
			_stream.register_content(_stream.sector_for_point(p), _spawn_house.bind(asset, p, facing, size))
			print("CDI_HOUSE_PLACED asset=", asset, " pk=", "%.1f" % pk,
				" side=", side, " off=", "%.1f" % offset, " y=", "%.2f" % p.y, " relief=", "%.2f" % (hi - lo))
			return true

	push_warning("CDI house %s could not find flat terrain near pk %.0f m" % [asset, base_pk])
	return false


func _spawn_house(parent: Node3D, asset: String, point: Vector3, facing: Vector3, size: Vector3) -> void:
	var packed := load(HOUSE_DIR + asset + ".glb") as PackedScene
	if packed == null:
		push_warning("Missing Andean house GLB: " + HOUSE_DIR + asset + ".glb")
		return
	var body := StaticBody3D.new()
	body.name = "Casa_" + asset
	body.collision_layer = _mask
	body.collision_mask = 0
	body.set_meta("collision_role", "obstacle")
	parent.add_child(body)
	body.global_transform = Transform3D(Basis.looking_at(facing, Vector3.UP, true), point)

	var model := packed.instantiate()
	body.add_child(model)
	_enforce_psx_matte_materials(model)

	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y + 1.5, size.z)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = (size.y - 1.5) * 0.5
	body.add_child(col)


func _enforce_psx_matte_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				if mat is StandardMaterial3D:
					var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					sm.roughness = 0.94
					sm.metallic = 0.0
					sm.metallic_specular = 0.0
					mi.set_surface_override_material(s, sm)
	for child in node.get_children():
		_enforce_psx_matte_materials(child)
