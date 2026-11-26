extends Node3D
## Stage furniture is visual only. The finish uses the official timing plane.

const MARSHAL := preload("res://assets/rally/stage_markers/marshal.png")
const FLAG_MARSHAL := preload("res://assets/rally/stage_markers/flag_marshal.png")
const HALF_WIDTH := 3.0
const COLUMNS := 12
const ROWS := 3
const CELL_SIZE := 2.0 * HALF_WIDTH / COLUMNS

var _finish: Dictionary
var _road_mask: int
const ObjectMaterial := preload("res://scripts/rally/rally_object_psx_material.gd")
var _red: ShaderMaterial
var _green: ShaderMaterial
var _housing_materials := {}


func build(start: Vector3, forward: Vector3, finish: Dictionary, road_mask: int) -> void:
	_finish = finish
	_road_mask = road_mask
	_add_marker(start, forward, true)


func update_finish(vehicle_position: Vector3) -> void:
	# The finish collision may be streamed in only as the car approaches.
	if _finish.is_empty():
		return
	var center: Vector3 = _finish.origin
	if vehicle_position.distance_squared_to(center) > 250.0 * 250.0:
		return
	if _ground_hit(center).is_empty():
		return
	_add_marker(center, _finish.forward, false)
	_finish = {}


func set_phase(phase: String) -> void:
	_red.set_shader_parameter("emission_strength", 1.5 if phase == "ready" else 0.0)
	_green.set_shader_parameter("emission_strength", 1.5 if phase == "go" else 0.0)


func _add_marker(center: Vector3, direction: Vector3, is_start: bool) -> void:
	var forward := Vector3(direction.x, 0.0, direction.z).normalized()
	var right := forward.cross(Vector3.UP)
	var marker := Node3D.new()
	marker.name = "StartMarker" if is_start else "FinishMarker"
	add_child(marker)
	marker.position = center
	marker.basis = Basis(right, Vector3.UP, -forward)

	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices := PackedVector3Array()
	for row in range(ROWS + 1):
		for column in range(COLUMNS + 1):
			var point := center + right * (column * CELL_SIZE - HALF_WIDTH)
			point += forward * ((row - ROWS * 0.5) * CELL_SIZE)
			vertices.append(marker.to_local(_ground_point(point) + Vector3.UP * 0.035))
	for row in range(ROWS):
		for column in range(COLUMNS):
			var corner := row * (COLUMNS + 1) + column
			var next_row := corner + COLUMNS + 1
			var color := Color("#dedbd1") if (row + column) % 2 == 0 else Color("#242529")
			for index in [corner, next_row, corner + 1, corner + 1, next_row, next_row + 1]:
				mesh.set_color(color)
				mesh.add_vertex(vertices[index])
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	paint.roughness = 1.0
	mesh.generate_normals()
	var stripe := MeshInstance3D.new()
	stripe.mesh = mesh.commit()
	stripe.material_override = paint
	stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(stripe)

	_add_person(marker, -HALF_WIDTH - 0.9, MARSHAL)
	if is_start:
		_add_signal(marker, HALF_WIDTH + 0.85)
	else:
		_add_person(marker, HALF_WIDTH + 1.1, FLAG_MARSHAL, 11.0)


func _ground_hit(point: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 6.0, point - Vector3.UP * 8.0, _road_mask)
	return get_world_3d().direct_space_state.intersect_ray(ray)


func _ground_point(point: Vector3) -> Vector3:
	return _ground_hit(point).get("position", point)


func _add_person(marker: Node3D, lateral: float, texture: Texture2D, feet_offset_px: float = 0.0) -> void:
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.pixel_size = 1.8 / 48.0
	sprite.offset.x = feet_offset_px
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = true
	var surface := StandardMaterial3D.new()
	surface.albedo_texture = texture
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	surface.alpha_scissor_threshold = 0.5
	surface.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.material_override = ObjectMaterial.from_standard(surface)
	marker.add_child(sprite)
	var ground := _ground_point(marker.to_global(Vector3(lateral, 0.0, 0.0)))
	sprite.global_position = ground + Vector3.UP * (texture.get_height() * sprite.pixel_size * 0.5)


func _add_signal(marker: Node3D, lateral: float) -> void:
	var signal_post := Node3D.new()
	marker.add_child(signal_post)
	signal_post.global_position = _ground_point(marker.to_global(Vector3(lateral, 0.0, 0.0)))
	var housing := StandardMaterial3D.new()
	housing.albedo_color = Color("#272b30")
	_add_box(signal_post, Vector3(0.3, 0.09, 0.32), Vector3(0.0, 0.045, 0.0), housing)
	_add_box(signal_post, Vector3(0.09, 1.18, 0.09), Vector3(0.0, 0.59, 0.0), housing)
	_add_box(signal_post, Vector3(0.37, 0.68, 0.22), Vector3(0.0, 1.48, 0.0), housing)
	_red = _add_lamp(signal_post, 1.64, Color("#ff3627"), housing)
	_green = _add_lamp(signal_post, 1.32, Color("#35ff61"), housing)


func _add_lamp(parent: Node3D, height: float, color: Color, housing: StandardMaterial3D) -> ShaderMaterial:
	var lens := StandardMaterial3D.new()
	lens.albedo_color = color.darkened(0.78)
	lens.emission = color
	lens.emission_energy_multiplier = 1.5
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.105
	cylinder.bottom_radius = 0.105
	cylinder.height = 0.045
	cylinder.radial_segments = 12
	var lamp := MeshInstance3D.new()
	lamp.mesh = cylinder
	var surface := ObjectMaterial.from_standard(lens) as ShaderMaterial
	lamp.material_override = surface
	parent.add_child(lamp)
	lamp.rotation.x = PI * 0.5
	lamp.position = Vector3(0.0, height, 0.12)
	_add_box(parent, Vector3(0.26, 0.04, 0.14), Vector3(0.0, height + 0.115, 0.15), housing)
	return surface


func _add_box(parent: Node3D, size: Vector3, offset: Vector3, material: StandardMaterial3D) -> void:
	var box := BoxMesh.new()
	box.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = box
	instance.material_override = ObjectMaterial.cached(material, _housing_materials)
	parent.add_child(instance)
	instance.position = offset
