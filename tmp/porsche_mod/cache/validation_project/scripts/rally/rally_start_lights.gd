extends Control
const FONT := preload("res://fonts/libron/Libron-Regular.ttf")
var state: Dictionary = {}
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
func present(value: Dictionary) -> void:
	state = value
	visible = bool(state.get("visible", false))
	queue_redraw()
func _draw() -> void:
	var scale_factor := minf(size.x / 1920.0, size.y / 1080.0)
	draw_set_transform(Vector2(size.x * 0.5, 125.0 * scale_factor), 0.0, Vector2.ONE * scale_factor)
	var phase := str(state.get("phase", "off"))
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035, 0.045, 0.055, 0.95)
	background.border_color = Color(0.4, 0.45, 0.5)
	background.set_border_width_all(2)
	background.set_corner_radius_all(12)
	draw_style_box(background, Rect2(-125, -70, 250, 175))
	for i in 2:
		var point := Vector2(-58 + 116 * i, -10)
		var lit := (i == 0 and phase == "ready") or (i == 1 and phase == "go")
		var color := Color(1.0, 0.08, 0.04) if i == 0 else Color(0.1, 1.0, 0.2)
		draw_circle(point, 43, Color(0.01, 0.01, 0.01))
		if lit:
			draw_circle(point, 39, Color(color, 0.18))
		draw_circle(point, 33, color if lit else color.darkened(0.88))
		draw_arc(point, 34, 0.0, TAU, 48, Color(0.4, 0.4, 0.4), 2.0, true)
	var label := "Ready" if phase == "ready" else ("Go!" if phase == "go" else "")
	draw_string(FONT, Vector2(-100, 82), label, HORIZONTAL_ALIGNMENT_CENTER, 200, 34, Color.WHITE)
	draw_set_transform(Vector2.ZERO)
