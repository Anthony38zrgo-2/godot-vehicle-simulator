extends SceneTree
## Guards the procedural roadside grass budget.
##
## The scatter used to place ~2.2k sub-30 cm tufts over 5 km (one per ~47 m2),
## which no camera could resolve: the three variants loaded and instanced
## correctly, so no logic test caught it and the decoration silently
## disappeared. These assertions encode the properties that make it visible.

const MIN_INSTANCES := 20000
## The pack ships five grass types; three of them were dropped by the original
## conversion and never reached the stage.
const EXPECTED_VARIANTS := 5
const MIN_VARIANT_SHARE := 0.05
const MAX_VARIANT_SHARE := 0.40
const MIN_TUFT_HEIGHT_M := 0.4
const MAX_TUFT_HEIGHT_M := 1.8
const MAX_LATERAL_M := 28.0
const ROUTE_SEED := "russia_stage1"

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var host := Node3D.new()
	root.add_child(host)

	var builder := RallyTrackCollisionBuilder.new()
	builder.collision_scene_path = "res://assets/rally/russia_stage1/russia_stage1_collision.glb"
	host.add_child(builder)
	check(builder.build_collision(null), "stage collision builds")

	await physics_frame
	await physics_frame

	var route := _load_route()
	check(route.size() > 400, "stage route loads")

	var grass: Node3D = preload("res://scripts/rally/rally_stage_grass.gd").new()
	host.add_child(grass)
	grass.build(route, hash(ROUTE_SEED), builder.collision_layer)

	var total := 0
	var groups := {}
	var cutout_ok := true
	var height_min := INF
	var height_max := 0.0
	var lateral_min := INF
	var lateral_max := 0.0
	var sampled := 0
	var identity_samples := 0
	for child in grass.get_children():
		var batch := child as MultiMeshInstance3D
		if batch == null or batch.multimesh == null:
			continue
		var material := batch.material_override as StandardMaterial3D
		if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			cutout_ok = false
		elif not is_equal_approx(material.alpha_scissor_threshold, 0.38) or material.cull_mode != BaseMaterial3D.CULL_DISABLED:
			cutout_ok = false
		var count := batch.multimesh.instance_count
		total += count
		# Variants are identified by their material + mesh height, not by node
		# names, so renaming batches cannot silently weaken this contract.
		var key := "%d:%d" % [material.get_instance_id() if material != null else 0,
			int(roundf(batch.multimesh.mesh.get_aabb().size.y * 1000.0))]
		var group: Dictionary = groups.get(key, {"count": 0, "height": batch.multimesh.mesh.get_aabb().size.y})
		group["count"] = int(group["count"]) + count
		groups[key] = group

	# Sample the transforms: full traversal of ~48k instances is unnecessary for
	# the invariants that matter and would make the contract slow.
	var sample_step := 1
	for child in grass.get_children():
		var batch := child as MultiMeshInstance3D
		if batch == null or batch.multimesh == null:
			continue
		var multimesh := batch.multimesh
		var source_height := multimesh.mesh.get_aabb().size.y
		var index := 0
		while index < multimesh.instance_count:
			var instance := multimesh.get_instance_transform(index)
			# What matters visually is the resulting height, not the raw scale:
			# the five source meshes differ by 4x (0.24 m to 1.00 m), so a 0.95
			# scale on tall_high is as tall as 3.4 on short_fresh.
			var tuft_height := instance.basis.get_scale().y * source_height
			height_min = minf(height_min, tuft_height)
			height_max = maxf(height_max, tuft_height)
			sampled += 1
			# A real scatter never lands on an exact identity transform: the
			# scale and yaw are both random. The dummy driver returns identity
			# for every instance, which is how headless is detected.
			if instance.origin.is_zero_approx() and instance.basis.is_equal_approx(Basis.IDENTITY):
				identity_samples += 1
			var lateral := _lateral_distance(route, instance.origin)
			lateral_min = minf(lateral_min, lateral)
			lateral_max = maxf(lateral_max, lateral)
			index += maxi(sample_step, 1)
		sample_step = maxi(sample_step, 37)

	check(total >= MIN_INSTANCES, "grass budget covers the stage (instances=%d, required>=%d)" % [total, MIN_INSTANCES])
	check(groups.size() == EXPECTED_VARIANTS,
		"all %d grass types scatter (got %d)" % [EXPECTED_VARIANTS, groups.size()])
	var min_share := 1.0
	var max_share := 0.0
	for key in groups:
		var share := float(groups[key]["count"]) / float(maxi(total, 1))
		min_share = minf(min_share, share)
		max_share = maxf(max_share, share)
	check(min_share >= MIN_VARIANT_SHARE, "no grass type is starved (smallest share=%.3f)" % min_share)
	check(max_share <= MAX_VARIANT_SHARE, "no grass type dominates (largest share=%.3f)" % max_share)
	check(cutout_ok, "scattered grass uses the stage cutout material")

	# MultiMesh.get_instance_transform() is backed by the RenderingServer, whose
	# dummy driver (--headless) reports identity for every instance. Placement is
	# therefore only assertable when a real driver is present; the budget, variant
	# mix and material checks above still run everywhere.
	var readback_available := sampled > 0 and identity_samples < sampled
	if readback_available:
		check(height_min >= MIN_TUFT_HEIGHT_M and height_max <= MAX_TUFT_HEIGHT_M,
			"tufts are tall enough to read from a car (height=%.2f..%.2f m)" % [height_min, height_max])
		# The band must hug the verge and reach past the point where the player
		# looks; the old 5.5-16 m band left the shoulder and the fields bare.
		check(lateral_min <= 6.0, "grass reaches the verge (nearest=%.1f m)" % lateral_min)
		check(lateral_max >= 18.0 and lateral_max <= MAX_LATERAL_M,
			"grass extends into the roadside fields (farthest=%.1f m)" % lateral_max)
	else:
		print("STAGE_GRASS_CONTRACT note=headless_skips_placement_assertions")
		lateral_min = -1.0
		lateral_max = -1.0
		height_min = -1.0
		height_max = -1.0

	if failures.is_empty():
		print("STAGE_GRASS_CONTRACT ", JSON.stringify({
			"passed": true,
			"instances": total,
			"variants": groups.size(),
			"share_range": [snappedf(min_share, 0.001), snappedf(max_share, 0.001)],
			"height_m": [snappedf(height_min, 0.01), snappedf(height_max, 0.01)],
			"lateral_m": [snappedf(lateral_min, 0.1), snappedf(lateral_max, 0.1)],
		}))
	else:
		print("STAGE_GRASS_CONTRACT ", JSON.stringify({"passed": false, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _load_route() -> Array[Vector3]:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/rally/%s_route.json" % ROUTE_SEED))
	var out: Array[Vector3] = []
	for point in (parsed as Dictionary)["points"]:
		out.append(Vector3(point[0], point[1], point[2]))
	return out


func _lateral_distance(route: Array[Vector3], position: Vector3) -> float:
	var best := INF
	var flat := Vector2(position.x, position.z)
	for i in range(1, route.size()):
		var a := Vector2(route[i - 1].x, route[i - 1].z)
		var b := Vector2(route[i].x, route[i].z)
		var segment := b - a
		var length_sq := segment.length_squared()
		var t := 0.0 if length_sq < 0.0001 else clampf((flat - a).dot(segment) / length_sq, 0.0, 1.0)
		best = minf(best, flat.distance_to(a + segment * t))
	return best
