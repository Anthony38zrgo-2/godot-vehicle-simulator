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
const TUFTS_PER_METRE := 4.8
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
	Vector2(2.2, 3.4),
	Vector2(2.2, 3.4),
	Vector2(1.6, 2.4),
	Vector2(0.95, 1.45),
]
## Selection weight per variant (index matches VARIANTS). Weights are relative
## and sum to 100 here: 20 aged / 30 dry / 10 tall low / 40 tall high.
const VARIANT_WEIGHT := [20.0, 30.0, 10.0, 40.0]
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

	var budget := maxi(1, roundi(total_length * TUFTS_PER_METRE))
	var max_attempts := maxi(budget, roundi(float(budget) * MAX_ATTEMPT_FACTOR))
	var bins := _offset_bins()
	var arc_table := _arc_table(cumulative, total_length)
	var buckets: Dictionary = {}
	var placed := 0
	var attempts := 0

	while placed < budget and attempts < max_attempts:
		attempts += 1
		if not _sample_point(rng, route, cumulative, arc_table, total_length, bins):
			continue
		var point := _sample_position
		# The density field is the only filter that is not geometry-driven, so
		# it runs before the physics query and shapes the field into patches.
		if rng.randf() > _density_chance(point.x, point.z):
			continue
		var hit := _raycast_ground(space, collision_mask, point)
		if hit.is_empty():
			continue
		var position: Vector3 = hit.position
		placed += 1
		var slot := _pick_variant(rng, entries)
		var scale_range: Vector2 = entries[slot]["scale"]
		var key := Vector2i(_sample_sector, slot)
		if not buckets.has(key):
			buckets[key] = [] as Array[Transform3D]
		var scale := rng.randf_range(scale_range.x, scale_range.y)
		(buckets[key] as Array[Transform3D]).append(
			_scatter_transform(position, scale, _sample_base, rng))

	var count := _commit_batches(buckets, entries)
	print("RALLY_GRASS_READY instances=", count, " batches=", buckets.size(),
		" budget=", budget, " attempts=", attempts, " band_m=", OFFSETS[0], "-", OFFSETS[OFFSETS.size() - 1],
		" build_ms=", Time.get_ticks_msec() - started_at)


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
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	_sample_base = start + delta * ((travelled - cumulative[index]) / segment)
	_sample_sector = int(travelled / SECTOR_LENGTH)
	_sample_position = _sample_base + lateral * (rng.randf_range(bin.x, bin.y) * side)
	return true


## Two octaves of value noise shaped into a field with real contrast, so tufts
## clump into patches and leave bare gaps instead of spreading evenly. A raw
## bilinear value noise clusters near 0.5, which reads as uniform static; the
## smoothstep stretches it back across the full range.
func _density_chance(x: float, z: float) -> float:
	var broad := _value_noise(x / NOISE_WAVELENGTH_M, z / NOISE_WAVELENGTH_M)
	var fine := _value_noise(x / (NOISE_WAVELENGTH_M * 0.4) + 31.7, z / (NOISE_WAVELENGTH_M * 0.4) + 17.3)
	var shaped := smoothstep(0.28, 0.72, clampf(broad * 0.72 + fine * 0.28, 0.0, 1.0))
	return lerpf(DENSITY_FLOOR, 1.0, shaped)


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
	if collider == null or not collider.is_in_group("Grass"):
		return {}
	if collider.get_meta("is_stage_road", false):
		return {}
	if (hit.normal as Vector3).y < MIN_SURFACE_UP:
		return {}
	return hit


func _scatter_transform(position: Vector3, scale: float, base: Vector3, rng: RandomNumberGenerator) -> Transform3D:
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale)
	# Sources are anchored at y = 0, so tilting pivots on the ground and the
	# tuft never floats or sinks.
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
	for index in VARIANTS.size():
		var instance := VARIANTS[index].instantiate()
		if instance == null:
			push_warning("Stage grass variant failed to instantiate: " + VARIANTS[index].resource_path)
			continue
		var visual := instance as MeshInstance3D
		if visual == null:
			var found := instance.find_children("*", "MeshInstance3D", true, false)
			if not found.is_empty():
				visual = found.front() as MeshInstance3D
		if visual == null or visual.mesh == null:
			push_warning("Stage grass variant has no mesh: " + VARIANTS[index].resource_path)
			instance.free()
			continue
		entries.append({
			"variant": index,
			"mesh": visual.mesh,
			"material": _make_material(visual),
			"scale": VARIANT_SCALE[mini(index, VARIANT_SCALE.size() - 1)],
			"weight": VARIANT_WEIGHT[mini(index, VARIANT_WEIGHT.size() - 1)],
		})
		instance.free()
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
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.roughness = 1.0
	material.metallic = 0.0
	material.backlight_enabled = true
	material.backlight = BACKLIGHT_COLOR
	material.disable_receive_shadows = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
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


func _commit_batches(buckets: Dictionary, entries: Array[Dictionary]) -> int:
	var count := 0
	for key: Vector2i in buckets:
		var transforms: Array[Transform3D] = buckets[key]
		if transforms.is_empty() or key.y < 0 or key.y >= entries.size():
			continue
		var entry: Dictionary = entries[key.y]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = entry["mesh"]
		multimesh.instance_count = transforms.size()
		for index in transforms.size():
			multimesh.set_instance_transform(index, transforms[index])
		var batch := MultiMeshInstance3D.new()
		batch.name = "GrassSector%02dVariant%d" % [key.x, key.y]
		batch.multimesh = multimesh
		batch.material_override = entry["material"]
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)
		count += transforms.size()
	return count


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
