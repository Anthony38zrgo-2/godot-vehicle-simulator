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

const PANEL_WIDTH := 0.88
const PANEL_OFFSET := 0.044
const POST_WIDTH := 0.055
const POST_EMBED := 0.35
const RELEASE_SPEED := 12.0 / 3.6
const SIGN_MASS := 12.0
const RELEASE_MAX_SPEED := 7.0
const SignBody := preload("res://scripts/rally/cdi_breakable_sign_body.gd")

const REAR_MATERIAL := preload("res://shaders/props/road_sign_rear.gdshader")
var _boards := {}
var _rear_boards := {}
var _placed_signs: Array[Dictionary] = []


func build(course: RallyStageProgress, mask: int, stream: RallyVisualSectorStream,
		stage_id: String = "cdi_stage4", reverse_route: bool = false) -> void:
	var space := get_world_3d().direct_space_state
	var spec_group: Dictionary = STAGE_SPECS.get(stage_id, STAGE_SPECS["cdi_stage4"])
	var warnings: Array = spec_group["warnings"]
	var hairpins: Array = spec_group["hairpins"]
	var count := 0
	_placed_signs.clear()
	var direction := -1 if reverse_route else 1
	for spec in warnings:
		var pk := float(spec[0])
		var face := str(spec[1])
		if reverse_route:
			if pk == 65.0:
				pk = course.route_distances[-1] - pk
			elif face.begins_with("herradura"):
				pk = _reverse_hairpin_warning_pk(pk, face, hairpins)
				face = _reverse_face(face)
		count += int(_place(course, pk, face, float(direction), space, mask, stream, stage_id, direction))
	for spec in hairpins:
		var face := str(spec[2])
		if reverse_route:
			face = _reverse_face(face)
		# The outside of the curve is the same physical shoulder both ways.
		for distance in [-13.0, 0.0, 13.0]:
			count += int(_place(course, float(spec[0]) + float(distance), face, float(spec[1]), space, mask, stream, stage_id, direction))
	for sign in _placed_signs:
		_add_collision(sign, mask)
	set_meta("sign_count", count)
	set_meta("placed_signs", _placed_signs)
	print("TICLIO_SIGNS_READY stage=", stage_id, " count=", count)


func _reverse_face(face: String) -> String:
	return face.trim_suffix("_izq") if face.ends_with("_izq") else face + "_izq"


func _reverse_hairpin_warning_pk(pk: float, face: String, hairpins: Array) -> float:
	var lead := INF
	var chevron := "chevron_izq" if face.ends_with("_izq") else "chevron"
	for hairpin in hairpins:
		var distance := float(hairpin[0]) - pk
		if str(hairpin[2]) == chevron and distance > 0.0 and distance <= 120.0:
			lead = minf(lead, distance)
	# Some warnings have no authored chevron group. Use the typical lead of 80 m.
	return pk + 2.0 * (lead if is_finite(lead) else 80.0)


func _place(course: RallyStageProgress, pk: float, face: String, side: float,
		space: PhysicsDirectSpaceState3D, mask: int, stream: RallyVisualSectorStream,
		stage_id: String, direction: int) -> bool:
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
			var approach := course.points[i - 3 * direction] - ground
			var facing := Vector3(approach.x, 0.0, approach.z).normalized()
			_placed_signs.append({"pk": pk, "face": face, "side": side, "ground": ground, "facing": facing, "released": false})
			stream.register_content(stream.sector_for_point(ground), _spawn_intact.bind(_placed_signs[-1]))
			return true
	push_warning("%s sign %s has no roadside support at %.0f m" % [stage_id, face, pk])
	return false


func _panel_height(face: String) -> float:
	return 0.97 if face.begins_with("chevron") else 1.65


func add_ticlio_panel(point: Vector3, forward: Vector3, mask: int, stream: RallyVisualSectorStream) -> void:
	var sign := {
		"ground": point, "facing": -forward, "released": false, "face": "cartel_verde_ticlio",
		"model": preload("res://assets/rally/cdi_stage4/monumentos/cartel_verde_ticlio.glb"),
		"mass": 27.0, "center_y": 1.85,
		"boxes": [
			[Vector3(3.30, 2.20, 0.075), Vector3(0.0, 3.10, 0.0)],
			[Vector3(0.075, 3.16, 0.075), Vector3(-1.22, 1.58, -0.09)],
			[Vector3(0.075, 3.16, 0.075), Vector3(1.22, 1.58, -0.09)],
			[Vector3(0.28, 0.82, 0.30), Vector3(-1.22, 0.18, -0.09)],
			[Vector3(0.28, 0.82, 0.30), Vector3(1.22, 0.18, -0.09)],
		],
	}
	_add_collision(sign, mask)
	stream.register_content(stream.sector_for_point(point), _spawn_intact.bind(sign))


func _add_collision(sign: Dictionary, mask: int) -> void:
	var body := SignBody.new()
	body.name = "SignCollision"
	body.mass = float(sign.get("mass", SIGN_MASS))
	body.collision_layer = mask
	body.collision_mask = 2
	body.gravity_scale = 0.0
	body.continuous_cd = true
	body.max_contacts_reported = 8
	body.linear_damp = 0.20
	body.angular_damp = 1.1
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3(0.0, float(sign.get("center_y", _panel_height(sign.face) * 0.58)), 0.0)
	var material := PhysicsMaterial.new()
	material.friction = 0.55
	material.bounce = 0.0
	body.physics_material_override = material
	body.set_meta("collision_role", "road_sign")
	body.set_meta("sign_impact", _request_release.bind(body, sign))
	body.anchor = Transform3D(Basis.looking_at(sign.facing, Vector3.UP, true), sign.ground)
	_add_shapes(body, sign)
	add_child(body)
	body.global_transform = body.anchor
	body.sleeping = true


func _add_shapes(body: PhysicsBody3D, sign: Dictionary) -> void:
	var height := _panel_height(sign.face)
	var boxes: Array = sign.get("boxes", [
		[Vector3(PANEL_WIDTH, PANEL_WIDTH, 0.035), Vector3(0.0, height, PANEL_OFFSET)],
		[Vector3(POST_WIDTH, height + 0.22 + POST_EMBED, POST_WIDTH), Vector3(0.0, (height + 0.22 - POST_EMBED) * 0.5, 0.0)],
	])
	for box in boxes:
		var shape := BoxShape3D.new()
		var size: Vector3 = box[0]
		var center: Vector3 = box[1]
		# The buried visual portion has no collision. Releasing the sign
		# in place then avoids ground depenetration and a jump into the car.
		var trim := maxf(0.0, 0.025 - (center.y - size.y * 0.5))
		size.y -= trim
		center.y += trim * 0.5
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = center
		body.add_child(collision)


func _request_release(speed: float, impulse: float, normal: Vector3, point: Vector3, wheel_only: bool,
		body: SignBody, sign: Dictionary) -> float:
	if sign.released or speed < RELEASE_SPEED or impulse <= 0.0:
		return 0.0
	sign.released = true
	body.anchored = false
	var transfer := minf(impulse, float(sign.get("mass", SIGN_MASS)) * minf(speed * 0.48, RELEASE_MAX_SPEED))
	_release.call_deferred(body, sign, -normal * transfer, point, wheel_only)
	return transfer


func _release(body: SignBody, sign: Dictionary, impulse: Vector3, point: Vector3, wheel_only: bool) -> void:
	if not is_instance_valid(body) or is_queued_for_deletion():
		return
	body.name = "FallenSign"
	body.anchored = false
	body.gravity_scale = 1.0
	body.collision_mask |= body.collision_layer
	body.remove_meta("sign_impact")
	body.set_meta("collision_role", "fallen_sign")
	var intact: Variant = sign.get("visual")
	if is_instance_valid(intact):
		intact.queue_free()
	# Keep a solved chassis impulse when it is still present. The anchor
	# callback may have cleared it before the deferred release runs.
	_spawn_model(body, body.global_transform, sign)
	body.sleeping = false
	if wheel_only or body.linear_velocity.length_squared() < 0.01:
		body.apply_impulse(impulse, point - body.global_position)


func _spawn_intact(parent: Node3D, sign: Dictionary) -> void:
	if not sign.released:
		var pose := Transform3D(Basis.looking_at(sign.facing, Vector3.UP, true), sign.ground)
		sign["visual"] = _spawn_model(parent, pose, sign)


func _spawn_model(parent: Node3D, pose: Transform3D, sign: Dictionary) -> Node3D:
	var packed: PackedScene = sign.get("model")
	var assembly: Node3D = packed.instantiate() if packed != null else Node3D.new()
	assembly.name = "MTC_" + str(sign.face)
	parent.add_child(assembly)
	assembly.global_transform = pose
	if packed == null:
		_add_sign_meshes(assembly, sign.face)
	return assembly


func _add_sign_meshes(assembly: Node3D, face: String) -> void:
	var board: QuadMesh = _boards.get(face)
	var center_y := _panel_height(face)
	if board == null:
		board = QuadMesh.new()
		board.size = Vector2.ONE * PANEL_WIDTH
		var material := StandardMaterial3D.new()
		material.albedo_texture = load(FACES + face + ".png")
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.45
		material.roughness = 0.74
		board.material = material
		_boards[face] = board
		var rear := QuadMesh.new()
		rear.size = board.size
		var rear_material := ShaderMaterial.new()
		rear_material.shader = REAR_MATERIAL
		rear_material.set_shader_parameter("front_mask", material.albedo_texture)
		rear.material = rear_material
		_rear_boards[face] = rear
	var plate := MeshInstance3D.new()
	plate.mesh = board
	plate.position = Vector3(0.0, center_y, PANEL_OFFSET)
	assembly.add_child(plate)
	var back := MeshInstance3D.new()
	back.mesh = _rear_boards[face]
	back.rotation.y = PI
	back.position = Vector3(0.0, center_y, PANEL_OFFSET - 0.018)
	assembly.add_child(back)
	var pole := MeshInstance3D.new()
	var metal := BoxMesh.new()
	metal.size = Vector3(POST_WIDTH, center_y + 0.22 + POST_EMBED, POST_WIDTH)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.39, 0.41, 0.42)
	steel.roughness = 0.8
	metal.material = steel
	pole.mesh = metal
	pole.position.y = (center_y + 0.22 - POST_EMBED) * 0.5
	assembly.add_child(pole)
