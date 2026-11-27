class_name UIVehicleShowroom
extends Control
## Reusable 3D vehicle showroom organism encapsulating UISubViewportStage, turntable rotation,
## safe scene instantiation (physics frozen/disabled), and shader vignette overlay.

const _StageScript := preload("res://ui/molecules/ui_subviewport_stage.gd")
const _ShaderMaterialFactory := preload("res://scripts/shaders/shader_material_factory.gd")

var stage_3d: _StageScript
var vignette_rect: ColorRect
var current_model: Node3D = null


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if stage_3d != null:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	stage_3d = get_node_or_null("Stage3D") as _StageScript
	if stage_3d == null:
		stage_3d = _StageScript.new()
		stage_3d.name = "Stage3D"
		stage_3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stage_3d.auto_rotate_speed = 0.28
		stage_3d.transparent_bg = false
		add_child(stage_3d)

	vignette_rect = get_node_or_null("VignetteOverlay") as ColorRect
	if vignette_rect == null:
		vignette_rect = ColorRect.new()
		vignette_rect.name = "VignetteOverlay"
		vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vignette_rect)
	vignette_rect.material = _ShaderMaterialFactory.create_from_preset("ui.showroom_vignette.default", {}, false)
	stage_3d.set_camera_pose(Vector3(3.15, 1.32, 3.65), Vector3(0.0, 0.55, 0.0), 34.0)


func get_viewport_node() -> SubViewport:
	_ensure_nodes()
	return stage_3d.viewport


func get_turntable() -> Node3D:
	_ensure_nodes()
	return stage_3d.turntable


func set_rotation_speed(rad_per_sec: float) -> void:
	_ensure_nodes()
	stage_3d.auto_rotate_speed = rad_per_sec


func load_vehicle_scene(scene_path: String) -> Node3D:
	_ensure_nodes()
	current_model = null
	stage_3d.clear_subject()
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	_disable_runtime_simulation(inst)
	stage_3d.set_subject(inst)
	current_model = inst
	return inst


func _disable_runtime_simulation(node: Node) -> void:
	if node is RigidBody3D:
		(node as RigidBody3D).freeze = true
	node.set_physics_process(false)
	for child in node.get_children():
		_disable_runtime_simulation(child)
