class_name UISubViewportStage
extends SubViewportContainer
## Reusable isolated 3D SubViewport preview stage (showroom, 3D tires, service parts)
## with own_world_3d isolation so preview lights never hijack main stage lighting.

@export var auto_rotate_speed: float = 0.0
@export var transparent_bg: bool = true

var viewport: SubViewport
var world_root: Node3D
var camera: Camera3D
var turntable: Node3D
var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_stage()


func _ready() -> void:
	_ensure_stage()


func _process(delta: float) -> void:
	if auto_rotate_speed != 0.0 and turntable != null and is_visible_in_tree():
		turntable.rotation.y += auto_rotate_speed * delta


func _exit_tree() -> void:
	clear_subject()


func _ensure_stage() -> void:
	if viewport != null:
		return
	viewport = SubViewport.new()
	viewport.name = "PreviewSubViewport"
	viewport.own_world_3d = true
	viewport.transparent_bg = transparent_bg
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)

	world_root = Node3D.new()
	world_root.name = "StageRoot"
	viewport.add_child(world_root)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.78, 0.86)
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	world_root.add_child(we)

	key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-35.0, 42.0, 0.0)
	key_light.light_energy = 1.45
	key_light.light_color = Color(1.0, 0.96, 0.90)
	world_root.add_child(key_light)

	fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-18.0, -135.0, 0.0)
	fill_light.light_energy = 0.65
	fill_light.light_color = Color(0.78, 0.86, 1.0)
	world_root.add_child(fill_light)

	camera = Camera3D.new()
	camera.name = "PreviewCamera"
	camera.fov = 36.0
	camera.position = Vector3(0.0, 1.2, 4.4)
	world_root.add_child(camera)

	turntable = Node3D.new()
	turntable.name = "Turntable"
	world_root.add_child(turntable)


func set_camera_pose(pos: Vector3, look_target: Vector3 = Vector3.ZERO, fov_deg: float = 36.0) -> void:
	_ensure_stage()
	camera.fov = fov_deg
	camera.position = pos
	camera.look_at_from_position(pos, look_target, Vector3.UP)


func clear_subject() -> void:
	if turntable == null or not is_instance_valid(turntable):
		return
	for child in turntable.get_children():
		turntable.remove_child(child)
		child.queue_free()


func set_subject(node: Node3D) -> void:
	_ensure_stage()
	clear_subject()
	if node != null:
		turntable.add_child(node)
