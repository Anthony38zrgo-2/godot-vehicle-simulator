extends Node3D
## Bounded world-space tire ribbons projected onto the contact receiver.
const CAPACITY := 768
const SEGMENTS_PER_BLOCK := 64
const SAMPLE_DISTANCE := 0.16
const MAX_DISTANCE := 2.5
const TREAD_REPEAT := 0.28
const SURFACE_OFFSET := 0.006
const TRIANGLES := [0, 1, 3, 3, 1, 4, 1, 2, 4, 4, 2, 5]
const TRACK_SHADER = preload("res://scripts/rally/rally_tire_tracks.gdshader")

var elapsed := 0.0
var previous: Array[Dictionary] = [{}, {}, {}, {}]
var segments: Array[Dictionary] = []
var cursor := 0
var dirty_blocks: Dictionary = {}
var ribbons: Array[MeshInstance3D] = []
var block_expiries: Array[float] = []
var material := ShaderMaterial.new()


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
		block_expiries.append(0.0)


func _process(delta: float) -> void:
	elapsed += delta
	material.set_shader_parameter("track_time", elapsed)
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


func opacity_for(surface: String, variant: int, slip: Vector2) -> float:
	# X is rolling opacity, Y is peak opacity under slip.
	var opacity := Vector2(0.08, 0.32)
	if variant < 2:
		opacity = Vector2(0.02, 0.72)
	elif variant < 4:
		opacity = Vector2(0.34, 0.72)
	elif variant == 4:
		opacity = Vector2(0.12, 0.50)
	else:
		match surface:
			"gravel": opacity = Vector2(0.23, 0.57)
			"dirt": opacity = Vector2(0.26, 0.62)
			"sand": opacity = Vector2(0.30, 0.60)
			"grass": opacity = Vector2(0.16, 0.52)
			"mud": opacity = Vector2(0.34, 0.70)
	var longitudinal := smoothstep(0.10, 0.85, absf(slip.x))
	var lateral := smoothstep(0.07, 0.35, absf(slip.y)) * 0.75
	return lerpf(opacity.x, opacity.y, maxf(longitudinal, lateral))


func break_track(wheel: int) -> void:
	previous[wheel] = {}


func clear_tracks() -> void:
	previous = [{}, {}, {}, {}]
	segments.clear()
	cursor = 0
	for ribbon in ribbons:
		ribbon.mesh = null
	block_expiries.fill(0.0)
	dirty_blocks.clear()


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
	if not prior.is_empty():
		start = prior.point
		phase = prior.phase
		var distance := start.distance_to(point)
		if distance > MAX_DISTANCE:
			break_track(wheel)
			return
		if prior.receiver != receiver or prior.variant != variant or prior.surface != surface:
			prior = {}
			start = point
		elif distance < SAMPLE_DISTANCE:
			return

	var tint := color_for(surface, variant)
	var smear := maxf(smoothstep(0.18, 0.9, absf(slip.x)), smoothstep(0.10, 0.48, absf(slip.y)))
	var relief := 0.0
	if variant == 2 or variant == 3 or surface in ["mud", "dirt", "sand", "gravel", "grass"]:
		relief = 0.55 if surface in ["sand", "gravel", "grass"] else 1.0
	var tone := Color(tint.r, clampf(strength, 0.0, 1.0), smear, relief)
	var span := start.distance_to(point)
	var steps := maxi(1, ceili(span / SAMPLE_DISTANCE))
	var space := get_world_3d().direct_space_state
	var motion := (point - start).slide(normal).normalized()
	var side := axle.slide(normal).normalized()
	if motion.length_squared() > 0.5:
		# During a broadside slide, keep transverse coverage as the tread smears.
		var transverse := motion.cross(normal).normalized()
		if transverse.dot(side) < 0.0:
			transverse = -transverse
		side = side.lerp(transverse, smear).normalized()
	for step in range(1, steps + 1):
		var weight := float(step) / steps
		var center := start.lerp(point, weight)
		var row := project_row(space, center, normal, side, width, receiver, mask, excluded)
		if row.is_empty():
			prior = {}
			continue
		var section := {
			"point": center,
			"vertices": row,
			"receiver": receiver,
			"variant": variant,
			"surface": surface,
			"phase": phase + span * weight / TREAD_REPEAT,
			"tone": tone,
		}
		if not prior.is_empty():
			append_segment(prior, section)
		prior = section
	previous[wheel] = prior


func project_row(space: PhysicsDirectSpaceState3D, center: Vector3, normal: Vector3, side: Vector3, width: float, receiver: RID, mask: int, excluded: Array[RID]) -> PackedVector3Array:
	var row := PackedVector3Array()
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = mask
	query.exclude = excluded
	query.hit_back_faces = false
	for column in range(-1, 2):
		var sample := center + side * width * 0.5 * column
		query.from = sample + normal * 0.16
		query.to = sample - normal * 0.20
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.rid != receiver or normal.dot(hit.normal) < 0.60:
			return PackedVector3Array()
		row.append(hit.position + hit.normal * SURFACE_OFFSET)
	return row


func append_segment(first: Dictionary, last: Dictionary) -> void:
	var segment := {
		"first": first,
		"last": last,
		"born": elapsed,
		"life": 12.0 if int(last.variant) < 2 else 7.0,
	}
	if segments.size() < CAPACITY:
		segments.append(segment)
	else:
		segments[cursor] = segment
	@warning_ignore("integer_division")
	var block := cursor / SEGMENTS_PER_BLOCK
	dirty_blocks[block] = true
	cursor = (cursor + 1) % CAPACITY


func flush_ribbons() -> void:
	for block: int in dirty_blocks:
		rebuild_ribbon(block)
	dirty_blocks.clear()


func rebuild_ribbon(block: int) -> void:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var states := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var latest_expiry := 0.0
	var first := block * SEGMENTS_PER_BLOCK
	var end := mini(first + SEGMENTS_PER_BLOCK, segments.size())
	for slot in range(first, end):
		var segment := segments[slot]
		var expiry := float(segment.born) + float(segment.life)
		if elapsed >= expiry:
			continue
		latest_expiry = maxf(latest_expiry, expiry)
		var base := vertices.size()
		var life := float(segment.life)
		if int(segment.last.variant) < 2:
			life = -life
		for row: Dictionary in [segment.first, segment.last]:
			for column in 3:
				vertices.append(row.vertices[column])
				uvs.append(Vector2(float(column) * 0.5, row.phase))
				states.append(Vector2(segment.born, life))
				colors.append(row.tone)
		for index in TRIANGLES:
			indices.append(base + index)
	var mesh: ArrayMesh
	if not vertices.is_empty():
		mesh = ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = states
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
	ribbons[block].mesh = mesh
	block_expiries[block] = latest_expiry
