extends Node3D
## World-space, bounded tire tracks; each batch uses one original CMR4 texture.
const TEXTURES = [
	preload("res://assets/vfx/cmr4/skid_tr1.png"), preload("res://assets/vfx/cmr4/skid_tr2.png"),
	preload("res://assets/vfx/cmr4/skid_sw1.png"), preload("res://assets/vfx/cmr4/skid_sw2.png"),
	preload("res://assets/vfx/cmr4/skid_ic1.png"), preload("res://assets/vfx/cmr4/skid_gr1.png"),
]
const CAPACITY := 256
const MIN_DISTANCE := 0.12
const MAX_DISTANCE := 2.5
var batches: Array[MultiMesh] = []
var counts := [0, 0, 0, 0, 0, 0]
var previous := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var previous_normal := [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]
var active := [false, false, false, false]
var previous_variant := [-1, -1, -1, -1]

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	for texture in TEXTURES:
		var material := ShaderMaterial.new()
		material.shader = preload("res://scripts/rally/rally_tire_tracks.gdshader")
		material.set_shader_parameter("track_texture", texture)
		var quad := PlaneMesh.new()
		quad.size = Vector2.ONE
		quad.material = material
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = quad
		batch.instance_count = CAPACITY
		batch.visible_instance_count = 0
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = batch
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		batches.append(batch)

func variant_for(surface: String, snow_mm: float, wheel: int) -> int:
	if snow_mm >= 0.25 or surface == "snow":
		return 2 + wheel % 2
	if surface == "ice":
		return 4
	if surface in ["road", "asphalt", "tarmac", "curb"]:
		return wheel % 2
	if surface in ["gravel", "dirt", "sand", "grass", "mud"]:
		return 5
	return -1


func color_for(surface: String, variant: int) -> Color:
	# CMR4's asphalt sprites have white RGB and carry the mark in alpha.
	# Tint every surface so light texels represent a darker disturbed track.
	if variant < 2:
		return Color(0.025, 0.023, 0.020)
	if variant == 2 or variant == 3:
		return Color(0.25, 0.28, 0.30)
	if variant == 4:
		return Color(0.23, 0.26, 0.28)
	match surface:
		"sand": return Color(0.22, 0.16, 0.10)
		"grass": return Color(0.10, 0.12, 0.05)
		"dirt", "mud": return Color(0.12, 0.08, 0.05)
		_: return Color(0.16, 0.14, 0.12)

func break_track(wheel: int) -> void:
	active[wheel] = false

func clear_tracks() -> void:
	active.fill(false)
	counts.fill(0)
	for batch in batches:
		batch.visible_instance_count = 0

func add_contact(wheel: int, point: Vector3, normal: Vector3, width: float, variant: int, strength: float, surface: String = "gravel") -> void:
	if variant < 0 or variant >= batches.size() or normal.length_squared() < 0.5:
		break_track(wheel)
		return
	var n := normal.normalized()
	if not active[wheel] or previous_variant[wheel] != variant:
		previous[wheel] = point
		previous_normal[wheel] = n
		previous_variant[wheel] = variant
		active[wheel] = true
		return
	var start: Vector3 = previous[wheel]
	var distance := point.distance_to(start)
	if distance < MIN_DISTANCE:
		return
	if distance > MAX_DISTANCE:
		break_track(wheel)
		return
	var up: Vector3 = (previous_normal[wheel] + n).normalized()
	var along := (point - start).slide(up).normalized()
	if along.length_squared() < 0.5:
		break_track(wheel)
		return
	var side := up.cross(along).normalized()
	var basis := Basis(side * width, up, along * distance)
	var batch := batches[variant]
	var slot: int = counts[variant] % CAPACITY
	batch.set_instance_transform(slot, Transform3D(basis, (start + point) * 0.5 + up * 0.025))
	var color := color_for(surface, variant)
	color.a = clampf(strength, 0.0, 1.0)
	batch.set_instance_color(slot, color)
	counts[variant] += 1
	batch.visible_instance_count = mini(counts[variant], CAPACITY)
	previous[wheel] = point
	previous_normal[wheel] = n
