extends Node3D
## Dense, deterministic roadside grass decoration built once per stage.
##
## Placement is a random point process, not a grid: candidates are drawn at a
## random arc length along the racing line and a random lateral offset, so no
## two rows line up and no visible lattice forms. Three filters shape it into
## something that reads as natural ground cover:
##
## - a low-frequency density field, so tufts clump into patches and leave gaps
##   instead of filling the band at a constant rate;
## - a minimum spacing, so cards never stack on top of each other;
## - one vertical ray against the stage trimesh, accepting only colliders
##   grouped "Grass" that are clear of the road.
##
## The instance budget is driven by arc length, so the density is the same on
## any stage. Everything is bucketed per sector and variant into
## MultiMeshInstance3D, so the whole stage costs one draw call per visible
## sector per variant.

## The source pack ships five grass types over two atlases. Four are used: the
## dry and aged shorts plus both tall types. short_fresh stays exported in the
## pack but is not scattered, so the verge reads dry rather than lush green.
const VARIANTS: Array[PackedScene] = [
	preload("res://assets/rally/grass/short_aged.glb"),
	preload("res://assets/rally/grass/short_dry.glb"),
	preload("res://assets/rally/grass/tall.glb"),
	preload("res://assets/rally/grass/tall_high.glb"),
]

## Lateral distance from the racing line, in metres. The road half-width is
## ~3 m, so anything closer is rejected by the collision test anyway; the list
## is denser near the verge, where the driver actually looks.
const OFFSETS := [2.5, 3.6, 4.8, 6.0, 7.4, 9.0, 10.6, 12.4, 14.4, 17.0, 20.0, 23.5]

## Tufts per metre of stage. The total budget is this times the route length,
## which keeps density identical across stages instead of scaling with length.
const TUFTS_PER_METRE := 3.36
## Hard ceiling on candidates as a multiple of the budget, so a stage whose
## terrain is mostly road or dirt cannot spin here.
const MAX_ATTEMPT_FACTOR := 6.0

## Wavelength of the coarse density field. Around 20-25 m gives patches that
## are readable from a car without turning into a checkerboard.
const NOISE_WAVELENGTH_M := 24.0
## Fraction of the budget that survives in the sparsest part of the field.
## Higher values flatten the field; lower values open bare gaps.
const DENSITY_FLOOR := 0.2
## Resolution of the arc-length table used to place candidates in O(1).
const ARC_TABLE_STEP := 1.0

## Vertical scale range per variant (index matches VARIANTS). The source meshes
## are 0.24 / 0.25 / 0.50 / 1.00 m tall: field-accurate but invisible from a
## car, so each range lifts them into a common 0.5-1.5 m band without letting
## the tall types swamp the verge.
const VARIANT_SCALE := [
	Vector2(1.8, 3.6),
	Vector2(1.8, 3.6),
	Vector2(1.3, 2.6),
	Vector2(0.80, 1.65),
]
## Selection weight per variant (index matches VARIANTS). Weights are relative
## and sum to 100 here: 20 aged / 30 dry / 10 tall low / 40 tall high.
const VARIANT_WEIGHT := [32.0, 38.0, 18.0, 12.0]
const MAX_TILT_DEGREES := 5.0

const SECTOR_LENGTH := 96.0
const TERRAIN_CLEARANCE := 0.02
const RAY_ORIGIN_LIFT := 8.0
const RAY_REACH_BELOW := 7.0
const MIN_SURFACE_UP := 0.72

## Must match RallyStageVisualMaterialAdjuster so scattered grass is shaded
## exactly like the baked stage foliage (per-vertex, unlit backfaces, no
## specular). A higher threshold than the rest of the stage erodes thin blades
## and dissolves the tufts with distance.
const ALPHA_SCISSOR_THRESHOLD := 0.38
const BACKLIGHT_COLOR := Color(0.65, 0.65, 0.65)

var use_rust_backend := true
var aged_only := false
var custom_variants: Array[PackedScene] = []
var custom_variant_weights: Array[float] = []
var custom_variant_scales: Array[Vector2] = []
var snowy_variants: Array[PackedScene] = []
var use_standard_variant_profile := false
var density_scale := 1.0
var density_floor := DENSITY_FLOOR
var instance_scale := 1.0
var outer_offset_scale := 1.0
var side_bias_strength := 0.0
var extra_height_variation_m := 0.0
var ground_group: StringName = &""
var grass_gis: Callable
var snow_coverage: Callable
var parking_covers: Callable
var collidable_bushes := false
var cluster_scatter := false
var min_spacing_m := 0.0
var variant_group_size := 1
var face_camera := false
var fog_enabled := true
var outline_bush_cards := false
var visual_range_m := 0.0
var reserved_points: Array[Vector3] = []
var sector_stream: RallyVisualSectorStream

var _sample_position := Vector3.ZERO
var _sample_base := Vector3.ZERO
var _sample_sector := 0


func build(route: Array[Vector3], stage_seed: int, collision_mask: int) -> void:
	_clear()
	if route.size() < 2:
		push_warning("Stage grass needs at least two route points")
		return
	var entries := _load_variant_entries()
	if entries.is_empty():
		push_error("Stage grass cannot resolve any usable variant mesh")
		return

	var started_at := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = stage_seed
	var space := get_world_3d().direct_space_state
	var cumulative := _cumulative_lengths(route)
	var total_length := cumulative[cumulative.size() - 1]
	if total_length <= 0.01:
		push_warning("Stage grass needs a route with length")
		return

	var budget := maxi(1, roundi(total_length * TUFTS_PER_METRE * density_scale))
	var attempt_factor := 10.0 if (cluster_scatter or grass_gis.is_valid()) else MAX_ATTEMPT_FACTOR
	var max_attempts := maxi(budget, roundi(float(budget) * attempt_factor))
	var bins := _offset_bins()
	if collidable_bushes:
		bins = bins.slice(4)
	if _try_build_with_rust(route, stage_seed, collision_mask, entries, started_at, space, total_length, budget, max_attempts, bins):
		return
	var arc_table := _arc_table(cumulative, total_length)
	var buckets: Dictionary = {}
	var stats := {
		"placed": 0,
		"clusters": 0,
		"snow_skipped": 0,
		"snow_placed": 0,
		"gis_skipped": 0,
		"min_height_m": INF,
		"max_height_m": 0.0,
		"min_delta_m": INF,
		"max_delta_m": -INF,
	}
	var attempts := 0
	var spacing_cells := {}
	var spacing_m := 3.5 if collidable_bushes else min_spacing_m
	var reservation_radius := 1.25 if collidable_bushes else 0.46
	var reserved := _reservation_grid(reservation_radius)

	while int(stats["placed"]) < budget and attempts < max_attempts:
		attempts += 1
		if not _sample_point(rng, route, cumulative, arc_table, total_length, bins):
			continue
		var point := _sample_position
		# The density field is the only filter that is not geometry-driven, so
		# it runs before the physics query and shapes the field into patches.
		var density := _density_chance(point.x, point.z)
		if rng.randf() > density:
			continue
		var hit := _raycast_ground(space, collision_mask, point)
		if hit.is_empty():
			continue
		var position: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		var habitat := _evaluate_habitat(position, normal, _sample_base)
		if cluster_scatter or grass_gis.is_valid():
			if rng.randf() > float(habitat["accept"]):
				stats["gis_skipped"] = int(stats["gis_skipped"]) + 1
				continue
		if not reserved.is_empty() and _near_reserved_point(reserved, position, reservation_radius):
			continue
		if spacing_m > 0.0 and not _reserve_position(spacing_cells, position, spacing_m):
			continue

		var lushness: float = habitat["lushness"]
		var parent_slot := _emit_tuft(rng, entries, buckets, stats, position, normal,
			_sample_base, _sample_sector, density, lushness, 0.0, -1)
		if not cluster_scatter or parent_slot < 0:
			continue
		stats["clusters"] = int(stats["clusters"]) + 1
		var parent_group := parent_slot / maxi(1, variant_group_size)
		var cluster_size := clampi(
			roundi(lerpf(2.0, 7.0, density * 0.50 + lushness * 0.50) + rng.randf_range(-1.2, 1.2)),
			2, 7)
		var radius := rng.randf_range(0.65, 2.35)
		var elongation := rng.randf_range(1.0, 1.75)
		var contour := Vector3.UP.cross(normal)
		if contour.length_squared() < 0.01:
			var angle := rng.randf_range(0.0, TAU)
			contour = Vector3(cos(angle), 0.0, sin(angle))
		else:
			contour = contour.normalized()
		var across := Vector3.UP.cross(contour).normalized()

		for _member in range(1, cluster_size):
			if int(stats["placed"]) >= budget:
				break
			var r_frac := (rng.randf() + rng.randf()) * 0.5
			var theta := rng.randf_range(0.0, TAU)
			var offset_vec := (contour * (cos(theta) * r_frac * radius * elongation)
				+ across * (sin(theta) * r_frac * radius))
			var d_hit := _raycast_ground(space, collision_mask, position + offset_vec)
			if d_hit.is_empty():
				continue
			var d_pos: Vector3 = d_hit.position
			if absf(d_pos.y - position.y) > 1.35:
				continue
			var d_normal: Vector3 = d_hit.normal
			var d_habitat := _evaluate_habitat(d_pos, d_normal, _sample_base)
			if rng.randf() > float(d_habitat["accept"]):
				stats["gis_skipped"] = int(stats["gis_skipped"]) + 1
				continue
			if not reserved.is_empty() and _near_reserved_point(reserved, d_pos, reservation_radius):
				continue
			if spacing_m > 0.0 and not _reserve_position(spacing_cells, d_pos, spacing_m):
				continue
			_emit_tuft(rng, entries, buckets, stats, d_pos, d_normal,
				_sample_base, _sample_sector, density, float(d_habitat["lushness"]), r_frac, parent_group)

	if snow_coverage.is_valid():
		set_meta("snow_skipped", int(stats["snow_skipped"]))
		set_meta("snow_placed", int(stats["snow_placed"]))
	if float(stats["min_height_m"]) < INF:
		set_meta("height_stats", {
			"instance_scale": instance_scale,
			"min_height_m": float(stats["min_height_m"]),
			"max_height_m": float(stats["max_height_m"]),
			"min_delta_m": float(stats["min_delta_m"]),
			"max_delta_m": float(stats["max_delta_m"]),
			"clusters": int(stats["clusters"]),
			"gis_skipped": int(stats["gis_skipped"]),
			"min_spacing_m": spacing_m,
		})
	var count := _commit_batches(buckets, entries, collision_mask)
	var outer_offset := bins[0].x + (bins[-1].y - bins[0].x) * outer_offset_scale
	print("RALLY_BUSHES_READY" if collidable_bushes else "RALLY_GRASS_READY",
		" instances=", count, " batches=", buckets.size(),
		" variants=", entries.size(), " budget=", budget, " attempts=", attempts,
		" clusters=", int(stats["clusters"]), " band_m=", bins[0].x, "-", outer_offset,
		" build_ms=", Time.get_ticks_msec() - started_at)


func _resolve_rust_gis() -> Dictionary:
	var sampler: RefCounted = null
	for cb: Callable in [grass_gis, snow_coverage]:
		if not cb.is_valid():
			continue
		var obj: Object = cb.get_object()
		if obj == null or not obj.has_method(&"get_rust_gis"):
			return {"ok": false, "sampler": null}
		var s: RefCounted = obj.call(&"get_rust_gis") as RefCounted
		if s == null:
			return {"ok": false, "sampler": null}
		sampler = s
	return {"ok": true, "sampler": sampler}


func _resolve_parking_rects() -> Dictionary:
	if not parking_covers.is_valid():
		return {"ok": true, "rects": PackedFloat32Array()}
	var obj: Object = parking_covers.get_object()
	if obj == null:
		return {"ok": false, "rects": PackedFloat32Array()}
	var raw_spaces: Variant = obj.get(&"_spaces")
	if not (raw_spaces is Array):
		return {"ok": false, "rects": PackedFloat32Array()}
	var spaces: Array = raw_spaces as Array
	var flat := PackedFloat32Array()
	flat.resize(spaces.size() * 11)
	for i in spaces.size():
		var site: Dictionary = spaces[i] as Dictionary
		var pt: Vector3 = site["point"] as Vector3
		var fwd: Vector3 = site["forward"] as Vector3
		var rgt: Vector3 = site["right"] as Vector3
		var base_i: int = i * 11
		flat[base_i] = pt.x
		flat[base_i + 1] = pt.y
		flat[base_i + 2] = pt.z
		flat[base_i + 3] = fwd.x
		flat[base_i + 4] = fwd.y
		flat[base_i + 5] = fwd.z
		flat[base_i + 6] = rgt.x
		flat[base_i + 7] = rgt.y
		flat[base_i + 8] = rgt.z
		flat[base_i + 9] = float(site["length"])
		flat[base_i + 10] = float(site["width"])
	return {"ok": true, "rects": flat}


func _batch_raycast(
	space: PhysicsDirectSpaceState3D,
	candidates: PackedVector3Array,
	query: PhysicsRayQueryParameters3D,
	required_group: StringName,
	collider_cache: Dictionary,
	up_lift: Vector3,
	down_reach: Vector3,
) -> Array:
	var count: int = candidates.size()
	var hit_pos := PackedVector3Array()
	var hit_norm := PackedVector3Array()
	var hit_flags := PackedByteArray()
	hit_pos.resize(count)
	hit_norm.resize(count)
	hit_flags.resize(count)
	for i in count:
		var pt: Vector3 = candidates[i]
		query.from = pt + up_lift
		query.to = pt - down_reach
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			continue
		var nrm: Vector3 = hit["normal"] as Vector3
		if nrm.y < MIN_SURFACE_UP:
			continue
		var col_obj: Variant = hit.get("collider")
		if col_obj == null or not (col_obj is Node):
			continue
		var cid: int = (col_obj as Object).get_instance_id()
		var accepted: Variant = collider_cache.get(cid)
		if accepted == null:
			var cnode := col_obj as Node
			accepted = cnode.is_in_group(required_group) and not bool(cnode.get_meta("is_stage_road", false))
			collider_cache[cid] = accepted
		if not bool(accepted):
			continue
		hit_pos[i] = hit["position"] as Vector3
		hit_norm[i] = nrm
		hit_flags[i] = 1
	return [hit_pos, hit_norm, hit_flags]


func _try_build_with_rust(
	route: Array[Vector3],
	stage_seed: int,
	collision_mask: int,
	entries: Array[Dictionary],
	started_at: int,
	space: PhysicsDirectSpaceState3D,
	_total_length: float,
	budget: int,
	max_attempts: int,
	bins: Array[Vector2],
) -> bool:
	if not use_rust_backend or not ClassDB.class_exists(&"RustStageGrassPlanner"):
		return false
	var gis_info: Dictionary = _resolve_rust_gis()
	if not bool(gis_info["ok"]):
		return false
	var parking_info: Dictionary = _resolve_parking_rects()
	if not bool(parking_info["ok"]):
		return false

	var planner: RefCounted = ClassDB.instantiate(&"RustStageGrassPlanner") as RefCounted
	var bins_flat := PackedFloat32Array()
	bins_flat.resize(bins.size() * 2)
	for bi in bins.size():
		bins_flat[bi * 2] = bins[bi].x
		bins_flat[bi * 2 + 1] = bins[bi].y
	planner.call("set_route", PackedVector3Array(route), bins_flat, stage_seed, budget, max_attempts)

	var spacing_m := 3.5 if collidable_bushes else min_spacing_m
	var reservation_radius := 1.25 if collidable_bushes else 0.46
	var params := PackedFloat32Array([
		density_floor,
		instance_scale,
		outer_offset_scale,
		side_bias_strength,
		spacing_m,
		reservation_radius,
		MAX_TILT_DEGREES,
		TERRAIN_CLEARANCE,
		SECTOR_LENGTH,
		MIN_SURFACE_UP,
	])
	var flags := PackedInt32Array([
		1 if cluster_scatter else 0,
		1 if grass_gis.is_valid() else 0,
		1 if snow_coverage.is_valid() else 0,
		1 if face_camera else 0,
		1 if outline_bush_cards else 0,
		1 if collidable_bushes else 0,
		maxi(1, variant_group_size),
	])
	planner.call("set_scatter_params", params, flags, global_transform.affine_inverse())

	var v_count: int = entries.size()
	var v_weights := PackedFloat32Array()
	var v_scales := PackedFloat32Array()
	var v_heights := PackedFloat32Array()
	var v_hnorms := PackedFloat32Array()
	var v_snow := PackedInt32Array()
	var v_aabb_pos := PackedVector3Array()
	var v_aabb_size := PackedVector3Array()
	v_weights.resize(v_count)
	v_scales.resize(v_count * 2)
	v_heights.resize(v_count)
	v_hnorms.resize(v_count)
	v_snow.resize(v_count)
	v_aabb_pos.resize(v_count)
	v_aabb_size.resize(v_count)
	for vi in v_count:
		var entry: Dictionary = entries[vi]
		v_weights[vi] = float(entry["weight"])
		var sc: Vector2 = entry["scale"] as Vector2
		v_scales[vi * 2] = sc.x
		v_scales[vi * 2 + 1] = sc.y
		v_heights[vi] = float(entry["mesh_height"])
		v_hnorms[vi] = float(entry["height_norm"])
		v_snow[vi] = 1 if entry.has("snow_material") else 0
		var mesh_aabb: AABB = (entry["mesh"] as Mesh).get_aabb()
		v_aabb_pos[vi] = mesh_aabb.position
		v_aabb_size[vi] = mesh_aabb.size
	planner.call("set_variants", v_weights, v_scales, v_heights, v_hnorms, v_snow, v_aabb_pos, v_aabb_size)

	if not reserved_points.is_empty():
		planner.call("set_reserved_points", PackedVector3Array(reserved_points))
	var sampler_ref: RefCounted = gis_info["sampler"] as RefCounted
	if sampler_ref != null:
		planner.call("set_gis_sampler", sampler_ref)
	var p_rects: PackedFloat32Array = parking_info["rects"] as PackedFloat32Array
	if not p_rects.is_empty():
		planner.call("set_parking_rects", p_rects)

	var sector_paths: Array[String] = []
	if sector_stream != null:
		var sinfo: Dictionary = sector_stream.get_sectors_for_rust()
		sector_paths = sinfo["paths"] as Array[String]
		if not sector_paths.is_empty():
			planner.call("set_sectors", float(sinfo["cell_m"]), sinfo["grid_coords"] as PackedInt32Array, sinfo["rects_flat"] as PackedFloat32Array)

	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = collision_mask
	var required_group: StringName = ground_group
	if required_group.is_empty():
		required_group = &"RauraGrassGround" if aged_only else &"Grass"
	var up_lift := Vector3.UP * RAY_ORIGIN_LIFT
	var down_reach := Vector3.UP * RAY_REACH_BELOW
	var collider_cache := {}

	while not bool(planner.call("is_done")):
		var candidates: PackedVector3Array = planner.call("generate_parent_candidates", 2048) as PackedVector3Array
		if candidates.is_empty():
			break
		var hits: Array = _batch_raycast(space, candidates, query, required_group, collider_cache, up_lift, down_reach)
		var d_candidates: PackedVector3Array = planner.call("process_parent_hits", hits[0], hits[1], hits[2]) as PackedVector3Array
		if not d_candidates.is_empty():
			var d_hits: Array = _batch_raycast(space, d_candidates, query, required_group, collider_cache, up_lift, down_reach)
			planner.call("process_daughter_hits", d_hits[0], d_hits[1], d_hits[2])

	var st: PackedFloat32Array = planner.call("get_stats_array") as PackedFloat32Array
	var total_instances: int = int(st[0])
	var attempts_done: int = int(st[2])
	var clusters_done: int = int(st[3])
	if snow_coverage.is_valid():
		set_meta("snow_skipped", int(st[4]))
		set_meta("snow_placed", int(st[5]))
	if st[7] >= 0.0:
		set_meta("height_stats", {
			"instance_scale": instance_scale,
			"min_height_m": float(st[7]),
			"max_height_m": float(st[8]),
			"min_delta_m": float(st[9]),
			"max_delta_m": float(st[10]),
			"clusters": clusters_done,
			"gis_skipped": int(st[6]),
			"min_spacing_m": spacing_m,
		})

	var keys_flat: PackedInt32Array = planner.call("finalize_buckets") as PackedInt32Array
	var num_buckets: int = keys_flat.size() / 2
	if sector_stream == null or sector_paths.is_empty():
		for bi in num_buckets:
			var kx: int = keys_flat[bi * 2]
			var ky: int = keys_flat[bi * 2 + 1]
			var buf: PackedFloat32Array = planner.call("get_bucket_multimesh_buffer", bi) as PackedFloat32Array
			if buf.is_empty():
				continue
			var entry: Dictionary = _resolve_variant_entry(entries, ky)
			var b_aabb: AABB = planner.call("get_bucket_aabb", bi) as AABB
			var coll_flat: PackedFloat32Array = planner.call("get_bucket_bush_colliders", bi) as PackedFloat32Array if collidable_bushes else PackedFloat32Array()
			_create_batch_from_buffer(self, Vector2i(kx, ky), entry, buf, b_aabb, coll_flat, collision_mask)
	else:
		var last_kx: int = -1
		var sector_counter: int = -1
		for bi in num_buckets:
			var kx: int = keys_flat[bi * 2]
			var ky: int = keys_flat[bi * 2 + 1]
			var buf: PackedFloat32Array = planner.call("get_bucket_multimesh_buffer", bi) as PackedFloat32Array
			if buf.is_empty() or kx < 0 or kx >= sector_paths.size():
				continue
			if kx != last_kx:
				last_kx = kx
				sector_counter += 1
			var entry: Dictionary = _resolve_variant_entry(entries, ky)
			var b_aabb: AABB = planner.call("get_bucket_aabb", bi) as AABB
			var coll_flat: PackedFloat32Array = planner.call("get_bucket_bush_colliders", bi) as PackedFloat32Array if collidable_bushes else PackedFloat32Array()
			var batch_key := Vector2i(sector_counter, ky)
			sector_stream.register_content(
				sector_paths[kx],
				_create_batch_from_buffer.bind(batch_key, entry, buf, b_aabb, coll_flat, collision_mask),
			)

	var outer_offset := bins[0].x + (bins[-1].y - bins[0].x) * outer_offset_scale
	print("RALLY_BUSHES_READY" if collidable_bushes else "RALLY_GRASS_READY",
		" instances=", total_instances, " batches=", num_buckets,
		" variants=", entries.size(), " budget=", budget, " attempts=", attempts_done,
		" clusters=", clusters_done, " band_m=", bins[0].x, "-", outer_offset,
		" build_ms=", Time.get_ticks_msec() - started_at)
	return true


func _resolve_variant_entry(entries: Array[Dictionary], variant_slot: int) -> Dictionary:
	var entry: Dictionary = entries[variant_slot % entries.size()]
	if variant_slot >= entries.size():
		entry = entry.duplicate()
		entry["material"] = entry["snow_material"]
	return entry


func _create_batch_from_buffer(
	parent: Node3D,
	key: Vector2i,
	entry: Dictionary,
	buffer: PackedFloat32Array,
	billboard_bounds: AABB,
	colliders_flat: PackedFloat32Array,
	collision_layer: int,
) -> void:
	var inst_count: int = buffer.size() / 12
	if inst_count <= 0:
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = entry["mesh"]
	multimesh.instance_count = inst_count
	multimesh.buffer = buffer
	if face_camera:
		multimesh.custom_aabb = billboard_bounds
	var batch := MultiMeshInstance3D.new()
	batch.name = ("BushSector%02dVariant%d" if collidable_bushes else "GrassSector%02dVariant%d") % [key.x, key.y]
	batch.multimesh = multimesh
	batch.material_override = entry["material"]
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if visual_range_m > 0.0:
		batch.visibility_range_end = visual_range_m
		batch.visibility_range_end_margin = 24.0
	parent.add_child(batch)
	if collidable_bushes and not colliders_flat.is_empty():
		var body := StaticBody3D.new()
		body.name = "BushCollision"
		body.collision_layer = collision_layer
		body.collision_mask = 0
		body.set_meta("collision_role", "obstacle")
		batch.add_child(body)
		var c_count: int = colliders_flat.size() / 5
		for i in c_count:
			var b_i: int = i * 5
			var shape := CapsuleShape3D.new()
			shape.radius = colliders_flat[b_i + 3]
			shape.height = colliders_flat[b_i + 4]
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.position = Vector3(colliders_flat[b_i], colliders_flat[b_i + 1], colliders_flat[b_i + 2])
			body.add_child(collider)


func _emit_tuft(rng: RandomNumberGenerator, entries: Array[Dictionary], buckets: Dictionary,
		stats: Dictionary, position: Vector3, normal: Vector3, base: Vector3, sector: int,
		density: float, lushness: float, radial_frac: float, forced_group: int) -> int:
	stats["placed"] = int(stats["placed"]) + 1
	if parking_covers.is_valid() and bool(parking_covers.call(position)):
		return -1
	var snow := 0.0
	if snow_coverage.is_valid():
		snow = float(snow_coverage.call(position))
		if rng.randf() < smoothstep(0.18, 0.75, snow):
			stats["snow_skipped"] = int(stats["snow_skipped"]) + 1
			return -1
	var slot := (_pick_habitat_slot(rng, entries, position, lushness, forced_group)
		if cluster_scatter else _pick_variant(rng, entries))
	var scale_range: Vector2 = entries[slot]["scale"]
	var snowy := (snow > 0.0 and entries[slot].has("snow_material")
		and rng.randf() < smoothstep(0.13, 0.62, snow))
	if snowy:
		stats["snow_placed"] = int(stats["snow_placed"]) + 1
	var key := Vector2i(sector, slot + entries.size() if snowy else slot)
	if not buckets.has(key):
		buckets[key] = [] as Array[Transform3D]
	var bell := (rng.randf() + rng.randf()) * 0.5
	var vigor := clampf(density * 0.45 + lushness * 0.35 + (1.0 - radial_frac) * 0.20, 0.0, 1.0)
	var t := clampf(lerpf(bell, vigor if cluster_scatter else density, 0.25), 0.0, 1.0)
	var scale_y := lerpf(scale_range.x, scale_range.y, t) * instance_scale
	var mesh_h: float = entries[slot]["mesh_height"]
	var actual_h := mesh_h * scale_y
	var delta_h := actual_h - mesh_h * instance_scale
	stats["min_height_m"] = minf(float(stats["min_height_m"]), actual_h)
	stats["max_height_m"] = maxf(float(stats["max_height_m"]), actual_h)
	stats["min_delta_m"] = minf(float(stats["min_delta_m"]), delta_h)
	stats["max_delta_m"] = maxf(float(stats["max_delta_m"]), delta_h)
	(buckets[key] as Array[Transform3D]).append(
		_scatter_transform(position, scale_y, base, rng, normal))
	return slot


func _cumulative_lengths(route: Array[Vector3]) -> PackedFloat64Array:
	var cumulative := PackedFloat64Array()
	cumulative.resize(route.size())
	cumulative[0] = 0.0
	for i in range(1, route.size()):
		cumulative[i] = cumulative[i - 1] + (route[i] - route[i - 1]).length()
	return cumulative


## Turns the OFFSETS list into equiprobable lateral bins. Each gap between
## neighbours becomes one bin, so the sampling density still falls off with
## distance exactly like the original hand-placed rings did.
func _offset_bins() -> Array[Vector2]:
	var bins: Array[Vector2] = []
	var count := OFFSETS.size()
	for k in count:
		var low: float = OFFSETS[0] if k == 0 else (OFFSETS[k - 1] + OFFSETS[k]) * 0.5
		var high: float = OFFSETS[count - 1] if k == count - 1 else (OFFSETS[k] + OFFSETS[k + 1]) * 0.5
		bins.append(Vector2(low, high))
	return bins


## Maps one entry per metre of arc length to its route segment, so sampling a
## point costs a division and an array read instead of a binary search.
func _arc_table(cumulative: PackedFloat64Array, total_length: float) -> PackedInt32Array:
	var size := int(total_length / ARC_TABLE_STEP) + 1
	var table := PackedInt32Array()
	table.resize(size)
	var cursor := 0
	var last := cumulative.size() - 2
	for k in size:
		var travelled := float(k) * ARC_TABLE_STEP
		while cursor < last and cumulative[cursor + 1] <= travelled:
			cursor += 1
		table[k] = cursor
	return table


## Uniform-in-arc-length point on one side of the road. Arc length is weighted
## by segment length, so long straights receive proportionally more candidates.
## Results land in the _sample_* fields rather than a Dictionary: at ~135k
## candidates the allocation was a measurable share of the build.
func _sample_point(rng: RandomNumberGenerator, route: Array[Vector3],
		cumulative: PackedFloat64Array, arc_table: PackedInt32Array,
		total_length: float, bins: Array[Vector2]) -> bool:
	var travelled := rng.randf() * total_length
	var index := arc_table[mini(int(travelled / ARC_TABLE_STEP), arc_table.size() - 1)]
	var start := route[index]
	var delta := route[index + 1] - start
	var segment := cumulative[index + 1] - cumulative[index]
	if segment <= 0.0001:
		return false
	var lateral := Vector3.UP.cross(delta)
	if lateral.is_zero_approx():
		return false
	lateral = lateral.normalized()
	var bin: Vector2 = bins[rng.randi_range(0, bins.size() - 1)]
	var left_chance := 0.5
	if side_bias_strength > 0.0:
		var bias := (_value_noise(travelled / 73.0, 19.6) * 0.62
			+ _value_noise(travelled / 191.0 + 13.4, 41.2) * 0.38)
		left_chance += lerpf(-side_bias_strength, side_bias_strength, bias)
	var side := -1.0 if rng.randf() < left_chance else 1.0
	_sample_base = start + delta * ((travelled - cumulative[index]) / segment)
	_sample_sector = int(travelled / SECTOR_LENGTH)
	var offset := rng.randf_range(bin.x, bin.y)
	var effective_outer := outer_offset_scale
	if cluster_scatter:
		var side_seed := 17.0 if side < 0.0 else 61.0
		var reach_wave := _value_noise(travelled / 89.0 + side_seed, 27.1)
		effective_outer *= lerpf(0.68, 1.22, reach_wave)
		var setback_wave := smoothstep(0.42, 0.88, _value_noise(travelled / 53.0 + side_seed * 1.7, 9.4))
		offset += setback_wave * 3.4
	if effective_outer != 1.0:
		offset += (offset - bins[0].x) * (effective_outer - 1.0)
	_sample_position = _sample_base + lateral * (offset * side)
	return true


## Domain-warped 3-octave value noise (macro + broad + fine) shaped into organic
## patches with real bare gaps instead of a periodic roadside rhythm.
func _density_chance(x: float, z: float) -> float:
	var warp_x := (_value_noise(x / 37.0 + 11.3, z / 37.0 + 47.9) - 0.5) * 18.0
	var warp_z := (_value_noise(x / 37.0 + 83.1, z / 37.0 + 19.7) - 0.5) * 18.0
	var wx := x + warp_x
	var wz := z + warp_z
	var macro := _value_noise(wx / 118.0 + 5.2, wz / 118.0 + 23.4)
	var broad := _value_noise(wx / 29.0, wz / 29.0)
	var fine := _value_noise(wx / 11.5 + 31.7, wz / 11.5 + 17.3)
	var combined := clampf(macro * 0.38 + broad * 0.40 + fine * 0.22, 0.0, 1.0)
	var shaped := smoothstep(0.26, 0.74, combined)
	return lerpf(density_floor, 1.0, shaped)


func _evaluate_habitat(position: Vector3, normal: Vector3, base: Vector3) -> Dictionary:
	var sparse := 0.45
	var olive := 0.06
	var mineral := 0.15
	var gis_density := 1.0
	if grass_gis.is_valid():
		var sample: Color = grass_gis.call(position)
		sparse = lerpf(0.45, sample.r, sample.a)
		olive = lerpf(0.06, sample.g, sample.a)
		mineral = lerpf(0.15, sample.b, sample.a)
		var mineral_penalty := smoothstep(0.22, 0.68, mineral)
		gis_density = clampf(lerpf(1.0, 0.30, sparse) * (1.0 - mineral_penalty * 0.90) + olive * 0.20, 0.04, 1.15)
	var slope_factor := lerpf(0.25, 1.0, smoothstep(MIN_SURFACE_UP, 0.94, normal.y))
	var elevation_above_road := position.y - base.y
	var bank_factor := lerpf(1.0, 0.38, smoothstep(1.8, 5.5, elevation_above_road))
	var accept := clampf(gis_density * slope_factor * bank_factor, 0.0, 1.0)
	var lushness := clampf(
		(1.0 - sparse) * 0.45 + olive * 0.30 - mineral * 0.35 + slope_factor * 0.35
		+ clampf(0.20 - elevation_above_road * 0.06, -0.15, 0.20),
		0.0, 1.0)
	return {"accept": accept, "lushness": lushness}


func _value_noise(x: float, z: float) -> float:
	var cell_x := floorf(x)
	var cell_z := floorf(z)
	var frac_x := x - cell_x
	var frac_z := z - cell_z
	var smooth_x := frac_x * frac_x * (3.0 - 2.0 * frac_x)
	var smooth_z := frac_z * frac_z * (3.0 - 2.0 * frac_z)
	var ix := int(cell_x)
	var iz := int(cell_z)
	# The hash is inlined: as four calls per octave it dominated sampling cost.
	var h := ix * 374761393 + iz * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	var v00 := float((h ^ (h >> 16)) & 0x00FFFFFF) / 16777215.0
	h = (ix + 1) * 374761393 + iz * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	var v10 := float((h ^ (h >> 16)) & 0x00FFFFFF) / 16777215.0
	h = ix * 374761393 + (iz + 1) * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	var v01 := float((h ^ (h >> 16)) & 0x00FFFFFF) / 16777215.0
	h = (ix + 1) * 374761393 + (iz + 1) * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	var v11 := float((h ^ (h >> 16)) & 0x00FFFFFF) / 16777215.0
	var top := lerpf(v00, v10, smooth_x)
	var bottom := lerpf(v01, v11, smooth_x)
	return lerpf(top, bottom, smooth_z)



## Shared placement filter, kept in one place so the acceptance rules cannot
## drift between callers. Returns {} when the candidate is not on stage grass.
func _raycast_ground(space: PhysicsDirectSpaceState3D, collision_mask: int, point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * RAY_ORIGIN_LIFT, point - Vector3.UP * RAY_REACH_BELOW, collision_mask)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider := hit.collider as Node
	var required_group := ground_group
	if required_group.is_empty():
		required_group = &"RauraGrassGround" if aged_only else &"Grass"
	if collider == null or not collider.is_in_group(required_group):
		return {}
	if collider.get_meta("is_stage_road", false):
		return {}
	if (hit.normal as Vector3).y < MIN_SURFACE_UP:
		return {}
	return hit


func _reserve_position(cells: Dictionary, position: Vector3, spacing_m: float) -> bool:
	var point := Vector2(position.x, position.z)
	var cell := Vector2i(floori(point.x / spacing_m), floori(point.y / spacing_m))
	var min_sq := spacing_m * spacing_m
	for x in range(cell.x - 1, cell.x + 2):
		for y in range(cell.y - 1, cell.y + 2):
			var neighbour := Vector2i(x, y)
			if cells.has(neighbour) and point.distance_squared_to(cells[neighbour]) < min_sq:
				return false
	if cells.has(cell):
		return false
	cells[cell] = point
	return true


func _reservation_grid(radius: float) -> Dictionary:
	var grid := {}
	for point in reserved_points:
		var cell := Vector2i(floori(point.x / radius), floori(point.z / radius))
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(Vector2(point.x, point.z))
	return grid


func _near_reserved_point(grid: Dictionary, position: Vector3, radius: float) -> bool:
	var point := Vector2(position.x, position.z)
	var cell := Vector2i(floori(point.x / radius), floori(point.y / radius))
	for x in range(cell.x - 1, cell.x + 2):
		for y in range(cell.y - 1, cell.y + 2):
			for other: Vector2 in grid.get(Vector2i(x, y), []):
				if point.distance_squared_to(other) < radius * radius:
					return true
	return false


func _scatter_transform(position: Vector3, scale_y: float, base: Vector3,
		rng: RandomNumberGenerator, normal: Vector3 = Vector3.UP) -> Transform3D:
	var scale_xz := scale_y * rng.randf_range(0.82, 1.22)
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale_xz, scale_y, scale_xz))
	# Sources are anchored at y = 0, so tilting pivots on the ground and the
	# tuft never floats or sinks.
	if cluster_scatter:
		var wind_angle := (_value_noise(position.x / 95.0 + 7.1, position.z / 95.0 + 53.3) - 0.5) * 1.4 + 0.65
		var wind_dir := Vector3(cos(wind_angle), 0.0, sin(wind_angle))
		var wind_lean := deg_to_rad(rng.randf_range(1.5, 6.5))
		var jitter_angle := rng.randf_range(0.0, TAU)
		var jitter := Vector3(cos(jitter_angle), 0.0, sin(jitter_angle)) * deg_to_rad(rng.randf_range(0.0, 3.0))
		var target_up := (Vector3.UP.lerp(normal, 0.28) + wind_dir * sin(wind_lean) + jitter).normalized()
		if target_up.y > 0.70:
			basis = Basis(Quaternion(Vector3.UP, target_up)) * basis
	else:
		var tilt_axis := Vector3(position.x - base.x, 0.0, position.z - base.z)
		if tilt_axis.length() < 0.05:
			tilt_axis = Vector3.RIGHT
		var tilt := deg_to_rad(rng.randf_range(-MAX_TILT_DEGREES, MAX_TILT_DEGREES))
		basis = Basis(tilt_axis.normalized(), tilt) * basis
	return Transform3D(basis, to_local(position - Vector3.UP * TERRAIN_CLEARANCE))


## Resolves mesh + material + scale band per variant, dropping any variant that
## fails to load instead of crashing on a null mesh or material.
func _load_variant_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var variants := VARIANTS if custom_variants.is_empty() else custom_variants
	for index in (1 if aged_only and custom_variants.is_empty() else variants.size()):
		if variants[index] == null:
			push_warning("Stage grass variant could not be loaded: %d" % index)
			continue
		var instance := variants[index].instantiate()
		if instance == null:
			push_warning("Stage grass variant failed to instantiate: " + variants[index].resource_path)
			continue
		var visual := instance as MeshInstance3D
		if visual == null:
			var found := instance.find_children("*", "MeshInstance3D", true, false)
			if not found.is_empty():
				visual = found.front() as MeshInstance3D
		if visual == null or visual.mesh == null:
			push_warning("Stage grass variant has no mesh: " + variants[index].resource_path)
			instance.free()
			continue
		var standard_profile := custom_variants.is_empty() or use_standard_variant_profile
		var scale_range: Vector2 = VARIANT_SCALE[index] if standard_profile else Vector2(0.75, 1.35)
		var weight: float = VARIANT_WEIGHT[index] if standard_profile else 1.0
		if index < custom_variant_weights.size():
			weight = custom_variant_weights[index]
		if index < custom_variant_scales.size():
			scale_range = custom_variant_scales[index]
		if aged_only and custom_variants.is_empty():
			scale_range = Vector2(1.5, 2.6)
		var mesh_height := visual.mesh.get_aabb().size.y
		if extra_height_variation_m > 0.0:
			var height := mesh_height * instance_scale
			if height > 0.0:
				var extra_scale := extra_height_variation_m / height
				scale_range = Vector2(maxf(0.01, scale_range.x - extra_scale), scale_range.y + extra_scale)
		var entry := {
			"variant": index,
			"mesh": visual.mesh,
			"mesh_height": mesh_height,
			"material": _make_material(visual),
			"scale": scale_range,
			"weight": weight,
		}
		if index < snowy_variants.size() and snowy_variants[index] != null:
			var snow_instance := snowy_variants[index].instantiate()
			var meshes := snow_instance.find_children("*", "MeshInstance3D", true, false)
			if not meshes.is_empty():
				entry["snow_material"] = _make_material(meshes[0] as MeshInstance3D)
			snow_instance.free()
		entries.append(entry)
		instance.free()
	var min_h := INF
	var max_h := 0.0
	for entry in entries:
		var mh: float = entry["mesh_height"]
		min_h = minf(min_h, mh)
		max_h = maxf(max_h, mh)
	var span := maxf(0.001, max_h - min_h)
	for entry in entries:
		entry["height_norm"] = clampf((float(entry["mesh_height"]) - min_h) / span, 0.0, 1.0)
	return entries


## Cutout treatment mirrored from RallyStageVisualMaterialAdjuster. Going
## through that node is not an option because it only walks the baked stage
## visual, and this material is built before the instances exist.
func _make_material(visual: MeshInstance3D) -> StandardMaterial3D:
	var source: Material = null
	if visual.mesh.get_surface_count() > 0:
		source = visual.mesh.surface_get_material(0)
	var material: StandardMaterial3D
	if source is StandardMaterial3D:
		material = (source as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		material = StandardMaterial3D.new()
		if source is BaseMaterial3D:
			material.albedo_texture = (source as BaseMaterial3D).albedo_texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = ALPHA_SCISSOR_THRESHOLD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if face_camera:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		material.billboard_keep_scale = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.roughness = 1.0
	material.metallic = 0.0
	material.backlight_enabled = true
	material.backlight = BACKLIGHT_COLOR
	material.disable_receive_shadows = true
	material.disable_fog = not fog_enabled
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if outline_bush_cards and material.albedo_texture != null:
		var outlined := ShaderMaterial.new()
		outlined.shader = preload("res://scripts/rally/cdi_bush_outline.gdshader")
		outlined.set_shader_parameter("bush_texture", material.albedo_texture)
		outlined.set_shader_parameter("bush_color", material.albedo_color)
		outlined.set_shader_parameter("card_center", visual.mesh.get_aabb().get_center())
		outlined.set_shader_parameter("alpha_cutoff", ALPHA_SCISSOR_THRESHOLD)
		outlined.set_shader_parameter("face_camera", face_camera)
		material.next_pass = outlined
	return material


func _pick_variant(rng: RandomNumberGenerator, entries: Array[Dictionary]) -> int:
	if entries.size() == 1:
		return 0
	var total := 0.0
	for entry in entries:
		total += float(entry["weight"])
	if total <= 0.0:
		return rng.randi_range(0, entries.size() - 1)
	var roll := rng.randf() * total
	for slot in entries.size():
		roll -= float(entries[slot]["weight"])
		if roll <= 0.0:
			return slot
	return entries.size() - 1


## Picks a variant group coherently across 30-60 m stands modulated by terrain
## lushness, while keeping cluster daughters mostly inside their parent's group.
func _pick_habitat_slot(rng: RandomNumberGenerator, entries: Array[Dictionary],
		position: Vector3, lushness: float, forced_group: int) -> int:
	var group_size := maxi(1, variant_group_size)
	var group_count := entries.size() / group_size
	if group_count <= 1 or entries.size() % group_size != 0:
		return _pick_variant(rng, entries)
	if forced_group >= 0 and forced_group < group_count and rng.randf() < 0.75:
		return forced_group * group_size + rng.randi_range(0, group_size - 1)
	var warp_x := (_value_noise(position.x / 58.0 + 21.1, position.z / 58.0 + 67.3) - 0.5) * 22.0
	var warp_z := (_value_noise(position.x / 58.0 + 91.7, position.z / 58.0 + 14.9) - 0.5) * 22.0
	var stand_field := _value_noise((position.x + warp_x) / 48.0 + 3.7, (position.z + warp_z) / 48.0 + 29.5)
	var dominant := stand_field * float(group_count)
	var group_weights: Array[float] = []
	var total := 0.0
	for g in group_count:
		var rep: Dictionary = entries[g * group_size]
		var base_w := maxf(0.01, float(rep["weight"]))
		var dist := absf(float(g) + 0.5 - dominant)
		var stand_affinity := lerpf(0.18, 1.0, exp(-dist * dist * 1.9))
		var h_norm: float = rep["height_norm"]
		var habitat_affinity := lerpf(0.55, 1.45, 1.0 - absf(h_norm - lushness))
		var w := base_w * stand_affinity * habitat_affinity
		group_weights.append(w)
		total += w
	var chosen_group := group_count - 1
	var roll := rng.randf() * total
	for g in group_count:
		roll -= group_weights[g]
		if roll <= 0.0:
			chosen_group = g
			break
	return chosen_group * group_size + rng.randi_range(0, group_size - 1)


func _commit_batches(buckets: Dictionary, entries: Array[Dictionary], collision_layer: int) -> int:
	var count := 0
	if sector_stream == null:
		for key: Vector2i in buckets:
			var transforms: Array[Transform3D] = buckets[key]
			if transforms.is_empty():
				continue
			var entry: Dictionary = entries[key.y % entries.size()]
			if key.y >= entries.size():
				entry = entry.duplicate()
				entry["material"] = entry["snow_material"]
			_create_batch(self, key, entry, transforms, collision_layer)
			count += transforms.size()
		return count

	var by_sector_variant := {}
	for key: Vector2i in buckets:
		var transforms: Array[Transform3D] = buckets[key]
		for transform in transforms:
			var path := sector_stream.sector_for_point(to_global(transform.origin))
			if not by_sector_variant.has(path):
				by_sector_variant[path] = {}
			var sector_variants: Dictionary = by_sector_variant[path]
			if not sector_variants.has(key.y):
				sector_variants[key.y] = [] as Array[Transform3D]
			(sector_variants[key.y] as Array[Transform3D]).append(transform)
			count += 1
	var sector_index := 0
	for path: String in by_sector_variant:
		var sector_variants: Dictionary = by_sector_variant[path]
		for variant_slot: int in sector_variants:
			var entry: Dictionary = entries[variant_slot % entries.size()]
			if variant_slot >= entries.size():
				entry = entry.duplicate()
				entry["material"] = entry["snow_material"]
			var batch_key := Vector2i(sector_index, variant_slot)
			var list: Array[Transform3D] = sector_variants[variant_slot]
			sector_stream.register_content(path, _create_batch.bind(batch_key, entry, list, collision_layer))
		sector_index += 1
	return count


func _create_batch(parent: Node3D, key: Vector2i, entry: Dictionary,
		transforms: Array[Transform3D], collision_layer: int) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = entry["mesh"]
	multimesh.instance_count = transforms.size()
	var mesh_bounds := multimesh.mesh.get_aabb()
	var billboard_bounds := AABB()
	for index in transforms.size():
		var instance := transforms[index]
		multimesh.set_instance_transform(index, instance)
		if face_camera:
			var scale := instance.basis.get_scale()
			var expansion := 1.6 if outline_bush_cards else 1.0
			var radius := mesh_bounds.size.x * scale.x * 0.5 * expansion
			var half_height := mesh_bounds.size.y * scale.y * 0.5 * expansion
			var center := instance.origin + Vector3.UP * mesh_bounds.get_center().y * scale.y
			var extent := Vector3(radius, half_height, radius)
			var bounds := AABB(center - extent, extent * 2.0)
			billboard_bounds = bounds if index == 0 else billboard_bounds.merge(bounds)
	if face_camera:
		multimesh.custom_aabb = billboard_bounds
	var batch := MultiMeshInstance3D.new()
	batch.name = ("BushSector%02dVariant%d" if collidable_bushes else "GrassSector%02dVariant%d") % [key.x, key.y]
	batch.multimesh = multimesh
	batch.material_override = entry["material"]
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if visual_range_m > 0.0:
		batch.visibility_range_end = visual_range_m
		batch.visibility_range_end_margin = 24.0
	parent.add_child(batch)
	if collidable_bushes:
		_add_bush_colliders(batch, transforms, mesh_bounds, collision_layer)


func _add_bush_colliders(batch: MultiMeshInstance3D, transforms: Array[Transform3D],
		bounds: AABB, collision_layer: int) -> void:
	var body := StaticBody3D.new()
	body.name = "BushCollision"
	body.collision_layer = collision_layer
	body.collision_mask = 0
	body.set_meta("collision_role", "obstacle")
	batch.add_child(body)
	for instance in transforms:
		var scale := instance.basis.get_scale()
		var shape := CapsuleShape3D.new()
		# The old crossed cards spanned the same width on both horizontal axes.
		var depth := bounds.size.x if face_camera else bounds.size.z
		shape.radius = maxf(0.12, minf(bounds.size.x * scale.x, depth * scale.z) * 0.29)
		shape.height = maxf(shape.radius * 2.0, bounds.size.y * scale.y * 0.80)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = instance * Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
		collider.position.y += shape.height * 0.5
		body.add_child(collider)


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
