extends Node3D
## Bounded world-space tire ribbons projected onto the contact receiver.
const CAPACITY := 768
const SEGMENTS_PER_BLOCK := 64
const SAMPLE_DISTANCE := 0.16
const MAX_MERGED_LENGTH := 0.72
const MAX_DISTANCE := 2.5
const TREAD_REPEAT := 0.28
const SURFACE_OFFSET := 0.006
const FLUSH_INTERVAL := 0.025
const TRIANGLES := [0, 1, 3, 3, 1, 4, 1, 2, 4, 4, 2, 5]
const TRACK_SHADER = preload("res://scripts/rally/rally_tire_tracks.gdshader")

var elapsed := 0.0
var _flush_accum := 0.0
var previous: Array[Dictionary] = [{}, {}, {}, {}]
var _active_slot: Array[int] = [-1, -1, -1, -1]
var segments: Array[Dictionary] = []
var cursor := 0
var dirty_blocks: Dictionary = {}
var ribbons: Array[MeshInstance3D] = []
var _ribbon_meshes: Array[ArrayMesh] = []
var _block_arrays: Array[Array] = []
var block_expiries: Array[float] = []
var material := ShaderMaterial.new()
var raycast_count := 0
var analytic_count := 0
var merged_count := 0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	material.shader = TRACK_SHADER
	@warning_ignore("integer_division")
	for block in CAPACITY / SEGMENTS_PER_BLOCK:
		var ribbon := MeshInstance3D.new()
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ribbon.sorting_offset = 0.01
		add_child(ribbon)
		ribbons.append(ribbon)
		_ribbon_meshes.append(ArrayMesh.new())
		block_expiries.append(0.0)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array()
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array()
		arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array()
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray()
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array()
		_block_arrays.append(arrays)


func _process(delta: float) -> void:
	elapsed += delta
	material.set_shader_parameter("track_time", elapsed)
	_flush_accum += delta
	if not dirty_blocks.is_empty() and _flush_accum >= FLUSH_INTERVAL:
		_flush_accum = 0.0
		flush_ribbons()
	for block in ribbons.size():
		if ribbons[block].mesh != null and elapsed >= block_expiries[block]:
			ribbons[block].mesh = null


func variant_for(surface: String, snow_mm: float, wheel: int, winter_layer_id: String = "") -> int:
	if winter_layer_id == "ice" or surface == "ice":
		return 4
	if snow_mm >= 0.25 or surface in ["snow", "snowdeep"] or winter_layer_id in ["snow_packed", "snow_loose", "snow_deep"]:
		return 2 + wheel % 2
	if surface in ["road", "asphalt", "tarmac", "curb"]:
		return wheel % 2
	return 5


func color_for(surface: String, variant: int) -> Color:
	# Neutral multipliers retain the local surface color and lighting.
	if variant < 2:
		return Color(0.42, 0.42, 0.42)
	if variant < 5:
		return Color(0.64, 0.64, 0.64)
	match surface:
		"sand": return Color(0.78, 0.78, 0.78)
		"grass": return Color(0.70, 0.70, 0.70)
		"dirt": return Color(0.68, 0.68, 0.68)
		"mud": return Color(0.60, 0.60, 0.60)
		"gravel": return Color(0.74, 0.74, 0.74)
		_: return Color(0.84, 0.84, 0.84)


func opacity_for(surface: String, variant: int, slip: Vector2, slip_speed: float = -1.0) -> float:
	# X is rolling opacity, Y is peak opacity under real lockup/slide.
	var opacity := Vector2(0.05, 0.30)
	if variant < 2:
		opacity = Vector2(0.0, 0.72)
	elif variant < 4:
		opacity = Vector2(0.24, 0.70)
	elif variant == 4:
		opacity = Vector2(0.08, 0.48)
	else:
		match surface:
			"gravel": opacity = Vector2(0.14, 0.56)
			"dirt": opacity = Vector2(0.16, 0.62)
			"sand": opacity = Vector2(0.20, 0.60)
			"grass": opacity = Vector2(0.10, 0.50)
			"mud": opacity = Vector2(0.22, 0.68)
	var hard_surface := variant < 2 or variant == 4
	var longitudinal := (smoothstep(0.16, 0.48, absf(slip.x)) if hard_surface
		else smoothstep(0.20, 0.55, absf(slip.x)))
	var lateral := (smoothstep(0.13, 0.38, absf(slip.y)) if hard_surface
		else smoothstep(0.16, 0.45, absf(slip.y))) * 0.82
	var skid := maxf(longitudinal, lateral)
	if slip_speed >= 0.0:
		skid *= smoothstep(0.5, 2.2, slip_speed)
	return lerpf(opacity.x, opacity.y, skid)


func break_track(wheel: int) -> void:
	previous[wheel] = {}
	_active_slot[wheel] = -1


func clear_tracks() -> void:
	previous = [{}, {}, {}, {}]
	_active_slot = [-1, -1, -1, -1]
	segments.clear()
	cursor = 0
	_flush_accum = 0.0
	for block in ribbons.size():
		ribbons[block].mesh = null
		_ribbon_meshes[block].clear_surfaces()
		var arrays: Array = _block_arrays[block]
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array()
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array()
		arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array()
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray()
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array()
	block_expiries.fill(0.0)
	dirty_blocks.clear()


func _is_continuous_terrain(collider: CollisionObject3D) -> bool:
	return (str(collider.get_meta("collision_role", "")) == "terrain"
		or bool(collider.get_meta("is_stage_road", false))
		or collider.name.begins_with("TrackCollision"))


func add_contact(wheel: int, contact: Dictionary, width: float, variant: int, strength: float, surface: String, slip: Vector2, mask: int, excluded: Array[RID]) -> void:
	var collider: CollisionObject3D = contact.get("collider") as CollisionObject3D
	if not is_instance_valid(collider):
		break_track(wheel)
		return
	var point: Vector3 = contact["position"]
	var normal: Vector3 = contact["normal"]
	var axle: Vector3 = contact["tread_axis"]
	var receiver := collider.get_rid()
	var prior := previous[wheel]
	var phase := 0.0
	var start := point
	var start_normal := normal
	if not prior.is_empty():
		start = prior.point
		start_normal = prior.get("normal", normal)
		phase = prior.phase
		var distance := start.distance_to(point)
		if distance > MAX_DISTANCE:
			break_track(wheel)
			return
		if prior.receiver != receiver or prior.variant != variant or prior.surface != surface:
			prior = {}
			_active_slot[wheel] = -1
			start = point
			start_normal = normal
		elif distance < SAMPLE_DISTANCE:
			return

	var tint := color_for(surface, variant)
	var smear := maxf(smoothstep(0.22, 0.55, absf(slip.x)), smoothstep(0.16, 0.42, absf(slip.y)))
	var relief := 0.0
	if variant == 2 or variant == 3 or surface in ["mud", "dirt", "sand", "gravel", "grass"]:
		relief = 0.55 if surface in ["sand", "gravel", "grass"] else 1.0
	var tone := Color(tint.r, clampf(strength, 0.0, 1.0), smear, relief)
	var span := start.distance_to(point)
	var prior_strength := float(prior.tone.g) if not prior.is_empty() else 0.0
	if tone.g < 0.015 and prior_strength < 0.015:
		_active_slot[wheel] = -1
		previous[wheel] = {
			"point": point,
			"vertices": PackedVector3Array(),
			"normal": normal,
			"side": axle.slide(normal).normalized(),
			"receiver": receiver,
			"variant": variant,
			"surface": surface,
			"phase": phase + span / TREAD_REPEAT,
			"tone": tone,
		}
		return
	var use_analytic := _is_continuous_terrain(collider)
	var steps := maxi(1, ceili(span / SAMPLE_DISTANCE))
	var space := get_world_3d().direct_space_state if not use_analytic else null
	var motion := (point - start).slide(normal).normalized()
	var side := axle.slide(normal).normalized()
	if motion.length_squared() > 0.5:
		# During a broadside slide, keep transverse coverage as the tread smears.
		var transverse := motion.cross(normal).normalized()
		if transverse.dot(side) < 0.0:
			transverse = -transverse
		side = side.lerp(transverse, smear).normalized()
	if not prior.is_empty() and (prior.vertices as PackedVector3Array).is_empty():
		var p_norm: Vector3 = prior.get("normal", normal)
		var p_side: Vector3 = prior.get("side", side)
		var start_row := (project_row_analytic(start, p_norm, p_side, width) if use_analytic
			else project_row(space, start, p_norm, p_side, width, receiver, mask, excluded))
		if start_row.is_empty():
			prior = {}
			_active_slot[wheel] = -1
		else:
			prior["vertices"] = start_row
	for step in range(1, steps + 1):
		var weight := float(step) / steps
		var center := start.lerp(point, weight)
		var step_normal := start_normal.lerp(normal, weight).normalized()
		var row := (project_row_analytic(center, step_normal, side, width) if use_analytic
			else project_row(space, center, step_normal, side, width, receiver, mask, excluded))
		if row.is_empty():
			prior = {}
			_active_slot[wheel] = -1
			continue
		var section := {
			"point": center,
			"vertices": row,
			"normal": step_normal,
			"side": side,
			"receiver": receiver,
			"variant": variant,
			"surface": surface,
			"phase": phase + span * weight / TREAD_REPEAT,
			"tone": tone,
		}
		if not prior.is_empty() and maxf(float(prior.tone.g), float(tone.g)) >= 0.015:
			if use_analytic and _try_merge_segment(wheel, section):
				merged_count += 1
			else:
				_active_slot[wheel] = append_segment(prior, section)
		else:
			_active_slot[wheel] = -1
		prior = section
	previous[wheel] = prior


func project_row_analytic(center: Vector3, normal: Vector3, side: Vector3, width: float) -> PackedVector3Array:
	analytic_count += 1
	var offset := normal * SURFACE_OFFSET
	var half := side * (width * 0.5)
	return PackedVector3Array([center - half + offset, center + offset, center + half + offset])


func project_row(space: PhysicsDirectSpaceState3D, center: Vector3, normal: Vector3, side: Vector3, width: float, receiver: RID, mask: int, excluded: Array[RID]) -> PackedVector3Array:
	var row := PackedVector3Array()
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = mask
	query.exclude = excluded
	query.hit_back_faces = false
	for column in range(-1, 2):
		raycast_count += 1
		var sample := center + side * width * 0.5 * column
		query.from = sample + normal * 0.16
		query.to = sample - normal * 0.20
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.rid != receiver or normal.dot(hit.normal) < 0.60:
			return PackedVector3Array()
		row.append(hit.position + hit.normal * SURFACE_OFFSET)
	return row


func _try_merge_segment(wheel: int, section: Dictionary) -> bool:
	var slot := _active_slot[wheel]
	if slot < 0 or slot >= segments.size():
		return false
	var seg: Dictionary = segments[slot]
	var first: Dictionary = seg.first
	var mid: Dictionary = seg.last
	var a: Vector3 = first.point
	var b: Vector3 = mid.point
	var c: Vector3 = section.point
	var total_len := a.distance_to(c)
	if total_len > MAX_MERGED_LENGTH:
		return false
	var dir1 := (b - a).normalized()
	var dir2 := (c - b).normalized()
	if dir1.dot(dir2) < 0.996:
		return false
	var n1: Vector3 = first.get("normal", Vector3.UP)
	var n2: Vector3 = section.get("normal", Vector3.UP)
	if n1.dot(n2) < 0.996:
		return false
	var t1: Color = mid.tone
	var t2: Color = section.tone
	if absf(t1.g - t2.g) > 0.06 or absf(t1.b - t2.b) > 0.08:
		return false
	seg["last"] = section
	_write_segment_to_block(slot, seg)
	return true


func append_segment(first: Dictionary, last: Dictionary) -> int:
	var segment := {
		"first": first,
		"last": last,
		"born": elapsed,
		"life": 12.0 if int(last.variant) < 2 else 7.0,
	}
	var slot := cursor
	if segments.size() < CAPACITY:
		slot = segments.size()
		segments.append(segment)
	else:
		segments[slot] = segment
	cursor = (slot + 1) % CAPACITY
	_write_segment_to_block(slot, segment)
	return slot


func _write_segment_to_block(slot: int, segment: Dictionary) -> void:
	@warning_ignore("integer_division")
	var block := slot / SEGMENTS_PER_BLOCK
	var local := slot % SEGMENTS_PER_BLOCK
	var arrays: Array = _block_arrays[block]
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var uvs := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	var states := arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array
	var colors := arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	arrays[Mesh.ARRAY_VERTEX] = null
	arrays[Mesh.ARRAY_TEX_UV] = null
	arrays[Mesh.ARRAY_TEX_UV2] = null
	arrays[Mesh.ARRAY_COLOR] = null
	arrays[Mesh.ARRAY_INDEX] = null
	var v_base := local * 6
	var i_base := local * 12
	if vertices.size() < v_base + 6:
		vertices.resize(v_base + 6)
		uvs.resize(v_base + 6)
		states.resize(v_base + 6)
		colors.resize(v_base + 6)
		indices.resize(i_base + 12)
		for k in 12:
			indices[i_base + k] = v_base + TRIANGLES[k]
	var life := float(segment.life)
	var signed_life := -life if int(segment.last.variant) < 2 else life
	var state_vec := Vector2(float(segment.born), signed_life)
	var write_v := v_base
	for row: Dictionary in [segment.first, segment.last]:
		var row_verts: PackedVector3Array = row.vertices
		var row_phase := float(row.phase)
		var row_tone: Color = row.tone
		for column in 3:
			vertices[write_v] = row_verts[column]
			uvs[write_v] = Vector2(float(column) * 0.5, row_phase)
			states[write_v] = state_vec
			colors[write_v] = row_tone
			write_v += 1
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = states
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var expiry := float(segment.born) + life
	block_expiries[block] = maxf(block_expiries[block], expiry)
	dirty_blocks[block] = true


func flush_ribbons() -> void:
	for block: int in dirty_blocks:
		rebuild_ribbon(block)
	dirty_blocks.clear()


func rebuild_ribbon(block: int) -> void:
	var arrays: Array = _block_arrays[block]
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	if vertices.is_empty() or elapsed >= block_expiries[block]:
		ribbons[block].mesh = null
		return
	var mesh := _ribbon_meshes[block]
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	ribbons[block].mesh = mesh
