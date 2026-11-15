extends CanvasLayer
## Overlay global de carga con fondo borroso, spinner animado y texto "Loading...".
## Registrado como Autoload (RallyLoadingOverlay) para cubrir tanto transiciones
## de escena (menú -> tramo) como cargas de geometría entre tramos.

const BLUR_SHADER_CODE := """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 5.0) = 3.2;
uniform vec4 tint_color : source_color = vec4(0.03, 0.05, 0.08, 0.58);

void fragment() {
	vec4 bg = textureLod(screen_tex, SCREEN_UV, blur_lod);
	COLOR = mix(bg, vec4(tint_color.rgb, 1.0), tint_color.a);
}
"""


class _SpinnerControl extends Control:
	var angle: float = 0.0
	var active: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(56.0, 56.0)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if not active:
			return
		angle = fmod(angle + delta * 5.2, TAU)
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 5.0
		if radius <= 2.0:
			return
		draw_arc(center, radius, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.16), 4.0, true)
		draw_arc(center, radius, angle, angle + TAU * 0.28, 28, RallyUITheme.ACCENT_RALLY, 4.5, true)


var _root: Control
var _blur_rect: ColorRect
var _spinner: _SpinnerControl
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
	var shader := Shader.new()
	shader.code = BLUR_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
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

	_spinner = _SpinnerControl.new()
	vbox.add_child(_spinner)

	_label = Label.new()
	_label.text = "Loading..."
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", RallyUITheme.FONT_SUBTITLE)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", RallyUITheme.TEXT_PRIMARY)
	vbox.add_child(_label)


func show_loading(text: String = "Loading...") -> void:
	if _label != null:
		_label.text = text
	_is_showing = true
	visible = true
	if _spinner != null:
		_spinner.active = true
		_spinner.queue_redraw()


func hide_loading() -> void:
	_is_showing = false
	visible = false
	if _spinner != null:
		_spinner.active = false


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
