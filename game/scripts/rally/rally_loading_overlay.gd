extends CanvasLayer
## Overlay global de carga con fondo borroso, spinner animado y texto "Loading...".
## Registrado como Autoload (RallyLoadingOverlay) para cubrir tanto transiciones
## de escena (menú -> tramo) como cargas de geometría entre tramos.

const ShaderMaterialFactory := preload("res://scripts/shaders/shader_material_factory.gd")
const UISpinnerScript := preload("res://ui/atoms/ui_spinner.gd")
const UIThemeBuilder := preload("res://scripts/ui/core/ui_theme_builder.gd")

var _root: Control
var _blur_rect: ColorRect
var _spinner: Control
var _label: Label
var _is_showing: bool = false


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_root = Control.new()
	_root.name = "LoadingRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_blur_rect = ColorRect.new()
	_blur_rect.name = "BlurBackground"
	_blur_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_rect.color = Color.WHITE
	var mat := ShaderMaterialFactory.create_from_preset("ui.loading_blur.default", {}, false)
	_blur_rect.material = mat
	_root.add_child(_blur_rect)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	_spinner = UISpinnerScript.new()
	_spinner.radius = 23.0
	_spinner.stroke_width = 4.2
	_spinner.spin_speed = 5.2
	_spinner.custom_minimum_size = Vector2(56.0, 56.0)
	_spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_spinner)

	_label = Label.new()
	_label.text = "Loading..."
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIThemeBuilder.apply_label(_label, "primary", 18, false, true)
	vbox.add_child(_label)


func show_loading(text: String = "Loading...") -> void:
	if _label != null:
		_label.text = text
	_is_showing = true
	visible = true
	if _spinner != null:
		_spinner.queue_redraw()


func hide_loading() -> void:
	_is_showing = false
	visible = false


func is_loading_visible() -> bool:
	return _is_showing


## Carga un PackedScene en segundo plano mientras el árbol sigue procesando
## frames para que el spinner gire de forma fluida.
func load_packed_scene_async(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if ResourceLoader.has_cached(path):
		return ResourceLoader.load(path) as PackedScene
	var err := ResourceLoader.load_threaded_request(path, "PackedScene")
	if err != OK:
		return ResourceLoader.load(path) as PackedScene
	while true:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			return ResourceLoader.load_threaded_get(path) as PackedScene
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return null
		await get_tree().process_frame
	return null
