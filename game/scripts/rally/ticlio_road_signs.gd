extends Node3D
## Roadside MTC curve and warning signs for all CDI stages (SS01-SS04).
## Uses the exact same MTC Peru sign set authored for SS04 (Abra Ticlio).

const FACES := "res://assets/rally/CDI/senaletica/caras_mtc/"

# Default SS04 constants preserved for backwards compatibility
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

const STAGE_SPECS := {
	"cdi_stage1": {
		"warnings": [
			[65.0, "velocidad_40"],
			[820.0, "sinuoso"],
			[1150.0, "resbaladizo"],
			[1265.0, "herradura"],
			[1850.0, "velocidad_40"],
			[2240.0, "sinuoso"],
			[2285.0, "despacio"],
			[2330.0, "velocidad_30"],
			[2375.0, "herradura_izq"],
			[2488.0, "herradura_izq"],
			[2665.0, "herradura"],
			[3340.0, "herradura"],
			[3980.0, "sinuoso"],
			[4025.0, "despacio"],
			[4385.0, "herradura_izq"],
			[4890.0, "despacio"],
		],
		"hairpins": [
			[1345.0, -1.0, "chevron"],
			[1382.0, 1.0, "chevron_izq"],
			[2445.0, 1.0, "chevron_izq"],
			[2560.0, 1.0, "chevron_izq"],
			[2750.0, -1.0, "chevron"],
			[3424.0, -1.0, "chevron"],
			[4470.0, 1.0, "chevron_izq"],
		],
	},
	"cdi_stage2": {
		"warnings": [
			[65.0, "velocidad_40"],
			[455.0, "sinuoso"],
			[500.0, "despacio"],
			[545.0, "herradura_izq"],
			[1265.0, "velocidad_30"],
			[1310.0, "herradura"],
			[1700.0, "resbaladizo"],
			[2025.0, "sinuoso"],
			[2065.0, "despacio"],
			[2105.0, "velocidad_30"],
			[2145.0, "herradura_izq"],
			[2362.0, "herradura"],
			[2545.0, "sinuoso"],
			[2602.0, "herradura_izq"],
			[2740.0, "herradura"],
			[2890.0, "herradura_izq"],
			[3015.0, "herradura"],
			[3890.0, "velocidad_40"],
			[4860.0, "despacio"],
		],
		"hairpins": [
			[627.0, 1.0, "chevron_izq"],
			[1396.0, -1.0, "chevron"],
			[2214.0, 1.0, "chevron_izq"],
			[2447.0, -1.0, "chevron"],
			[2686.0, 1.0, "chevron_izq"],
			[2814.0, -1.0, "chevron"],
			[2969.0, 1.0, "chevron_izq"],
			[3081.0, -1.0, "chevron"],
		],
	},
	"cdi_stage3": {
		"warnings": [
			[65.0, "velocidad_40"],
			[1430.0, "sinuoso"],
			[1715.0, "despacio"],
			[1755.0, "velocidad_30"],
			[1796.0, "herradura_izq"],
			[2995.0, "sinuoso"],
			[4420.0, "resbaladizo"],
			[4920.0, "sinuoso"],
			[6110.0, "despacio"],
		],
		"hairpins": [
			[1881.0, 1.0, "chevron_izq"],
			[1922.0, -1.0, "chevron"],
			[3078.0, 1.0, "chevron_izq"],
		],
	},
	"cdi_stage4": {
		"warnings": WARNINGS,
		"hairpins": HAIRPINS,
	},
}

var _boards := {}
var _placed_signs: Array[Dictionary] = []


func build(course: RallyStageProgress, mask: int, stream: RallyVisualSectorStream,
		stage_id: String = "cdi_stage4") -> void:
	var space := get_world_3d().direct_space_state
	var spec_group: Dictionary = STAGE_SPECS.get(stage_id, STAGE_SPECS["cdi_stage4"])
	var warnings: Array = spec_group["warnings"]
	var hairpins: Array = spec_group["hairpins"]
	var count := 0
	_placed_signs.clear()
	for spec in warnings:
		count += int(_place(course, float(spec[0]), str(spec[1]), 1.0, space, mask, stream, stage_id))
	for spec in hairpins:
		for distance in [-13.0, 0.0, 13.0]:
			count += int(_place(course, float(spec[0]) + float(distance), str(spec[2]), float(spec[1]), space, mask, stream, stage_id))
	set_meta("sign_count", count)
	set_meta("placed_signs", _placed_signs)
	print("TICLIO_SIGNS_READY stage=", stage_id, " count=", count)


func _place(course: RallyStageProgress, pk: float, face: String, side: float,
		space: PhysicsDirectSpaceState3D, mask: int, stream: RallyVisualSectorStream,
		stage_id: String) -> bool:
	var stations := course.route_distances
	var i := clampi(stations.bsearch(pk), 3, course.points.size() - 4)
	var a := course.points[i - 1]
	var b := course.points[i]
	var center := a.lerp(b, inverse_lerp(stations[i - 1], stations[i], pk))
	var heading := course.points[i + 1] - course.points[i - 2]
	var forward := Vector3(heading.x, 0.0, heading.z).normalized()
	var right := forward.cross(Vector3.UP)

	var offsets: Array = [5.2, 6.4, 4.35, 7.7] if stage_id == "cdi_stage4" else [4.5, 5.2, 3.85, 6.4, 7.7]
	var min_normals: Array = [0.59] if stage_id == "cdi_stage4" else [0.59, 0.42]
	for min_ny_v in min_normals:
		var min_ny := float(min_ny_v)
		for offset_v in offsets:
			var offset := float(offset_v)
			var point := center + right * side * offset
			var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 4.0, point - Vector3.UP * 5.0, mask)
			var hit := space.intersect_ray(query)
			if hit.is_empty() or hit.collider.get_meta("collision_role", "") != "terrain" \
					or hit.collider.get_meta("is_stage_road", false) or (hit.normal as Vector3).y < min_ny:
				continue
			var ground: Vector3 = hit.position
			var approach := course.points[i - 3] - ground
			var facing := Vector3(approach.x, 0.0, approach.z).normalized()
			stream.register_content(stream.sector_for_point(ground), _spawn.bind(ground, facing, face))
			_placed_signs.append({"pk": pk, "face": face, "side": side, "ground": ground, "facing": facing})
			return true
	push_warning("%s sign %s has no roadside support at %.0f m" % [stage_id, face, pk])
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
	var embed := 0.35
	metal.size = Vector3(0.055, center_y + 0.22 + embed, 0.055)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.39, 0.41, 0.42)
	steel.roughness = 0.8
	metal.material = steel
	pole.mesh = metal
	pole.position.y = (center_y + 0.22 - embed) * 0.5
	assembly.add_child(pole)
