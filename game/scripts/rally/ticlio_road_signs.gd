extends Node3D
## Roadside markers selected for the authored SS04 centerline. Stations are timed PKs.

const FACES := "res://assets/rally/CDI/senaletica/caras_mtc/"
const WARNINGS := [
	[65.0, "velocidad_40"],
	[1100.0, "sinuoso"],
	[2960.0, "resbaladizo"],
	[3050.0, "velocidad_30"],
	[3450.0, "herradura_izq"],
	[3838.0, "herradura"],
	[4638.0, "herradura_izq"],
	[6075.0, "despacio"],
]
# Exterior side of the three sharpest hairpins, relative to climbing traffic.
const HAIRPINS := [
	[3537.0, 1.0, "chevron_izq"],
	[3923.0, -1.0, "chevron"],
	[4727.0, 1.0, "chevron_izq"],
]
var _boards := {}


func build(course: RallyStageProgress, mask: int, stream: RallyVisualSectorStream) -> void:
	var space := get_world_3d().direct_space_state
	var count := 0
	for spec in WARNINGS:
		count += int(_place(course, float(spec[0]), str(spec[1]), 1.0, space, mask, stream))
	for spec in HAIRPINS:
		for distance in [-13.0, 0.0, 13.0]:
			count += int(_place(course, float(spec[0]) + float(distance), str(spec[2]), float(spec[1]), space, mask, stream))
	set_meta("sign_count", count)
	print("TICLIO_SIGNS_READY count=", count)


func _place(course: RallyStageProgress, pk: float, face: String, side: float,
		space: PhysicsDirectSpaceState3D, mask: int, stream: RallyVisualSectorStream) -> bool:
	var stations := course.route_distances
	var i := clampi(stations.bsearch(pk), 3, course.points.size() - 4)
	var a := course.points[i - 1]
	var b := course.points[i]
	var center := a.lerp(b, inverse_lerp(stations[i - 1], stations[i], pk))
	var heading := course.points[i + 1] - course.points[i - 2]
	var forward := Vector3(heading.x, 0.0, heading.z).normalized()
	var right := forward.cross(Vector3.UP)
	for offset in [5.2, 6.4, 4.35, 7.7]:
		var point := center + right * side * float(offset)
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3.0, point - Vector3.UP * 3.0, mask)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.collider.get_meta("collision_role", "") != "terrain" 				or hit.collider.get_meta("is_stage_road", false) or (hit.normal as Vector3).y < 0.59:
			continue
		var ground: Vector3 = hit.position
		var approach := course.points[i - 3] - ground
		var facing := Vector3(approach.x, 0.0, approach.z).normalized()
		stream.register_content(stream.sector_for_point(ground), _spawn.bind(ground, facing, face))
		return true
	push_warning("SS04 sign %s has no roadside support at %.0f m" % [face, pk])
	return false


func _spawn(parent: Node3D, ground: Vector3, facing: Vector3, face: String) -> void:
	var assembly := Node3D.new()
	assembly.name = "MTC_" + face
	parent.add_child(assembly)
	assembly.global_transform = Transform3D(Basis.looking_at(facing, Vector3.UP, true), ground)
	var board: QuadMesh = _boards.get(face)
	var panel_width := 0.88
	var center_y := 0.97 if face.begins_with("chevron") else 1.65
	if board == null:
		board = QuadMesh.new()
		board.size = Vector2.ONE * panel_width
		var material := StandardMaterial3D.new()
		material.albedo_texture = load(FACES + face + ".png")
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.45
		material.roughness = 0.74
		board.material = material
		_boards[face] = board
	var plate := MeshInstance3D.new()
	plate.mesh = board
	plate.position = Vector3(0.0, center_y, 0.044)
	assembly.add_child(plate)
	var pole := MeshInstance3D.new()
	var metal := BoxMesh.new()
	metal.size = Vector3(0.055, center_y + 0.22, 0.055)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.39, 0.41, 0.42)
	steel.roughness = 0.8
	metal.material = steel
	pole.mesh = metal
	pole.position.y = metal.size.y * 0.5
	assembly.add_child(pole)
