extends Control

const FONT_REGULAR: Font = preload("res://fonts/libron/Libron-Regular.ttf")
var palette: RetroHudConfig = RetroHudConfig.new()

const PANEL_SIZE := Vector2(396.0, 116.0)

var steering_fraction := 0.0
var accelerator_fraction := 0.0
var brake_fraction := 0.0
var panel_background := StyleBoxFlat.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	panel_background.set_border_width_all(1)
	panel_background.set_corner_radius_all(12)
	_apply_palette()
	queue_redraw()

func set_palette(next_palette: RetroHudConfig) -> void:
	if next_palette == null:
		return
	palette = next_palette
	_apply_palette()
	queue_redraw()

func _apply_palette() -> void:
	panel_background.bg_color = palette.controls_background_color
	panel_background.border_color = palette.controls_border_color

func set_controls(steering: float, accelerator: float, brake: float) -> void:
	steering_fraction = clampf(steering, -1.0, 1.0)
	accelerator_fraction = clampf(accelerator, 0.0, 1.0)
	brake_fraction = clampf(brake, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	draw_style_box(panel_background, Rect2(Vector2.ZERO, PANEL_SIZE))
	var font := FONT_REGULAR
	var wheel_center := Vector2(62.0, 64.0)
	var wheel_rotation := -steering_fraction * PI * 0.75
	draw_string(font, Vector2(26.0, 21.0), "VOLANTE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, palette.label_color)
	draw_arc(wheel_center, 27.0, 0.0, TAU, 64, palette.wheel_ring_color, 3.0, true)
	for spoke_angle in [-PI * 0.5, PI / 6.0, PI * 5.0 / 6.0]:
		var direction := Vector2(cos(spoke_angle + wheel_rotation), sin(spoke_angle + wheel_rotation))
		draw_line(wheel_center + direction * 6.0, wheel_center + direction * 25.0, palette.steering_color if spoke_angle < 0.0 else palette.wheel_spoke_color, 3.0, true)
	draw_circle(wheel_center, 6.0, palette.wheel_hub_color, true, -1.0, true)
	var steering_text := "%d%%" % roundi(absf(steering_fraction) * 100.0)
	if absf(steering_fraction) > 0.005:
		steering_text = ("IZQ " if steering_fraction > 0.0 else "DER ") + steering_text
	draw_string(font, Vector2(16.0, 106.0), steering_text, HORIZONTAL_ALIGNMENT_CENTER, 92.0, 13, palette.steering_color)
	draw_pedal(font, "ACELERADOR", accelerator_fraction, 30.0, palette.throttle_color)
	draw_pedal(font, "FRENO", brake_fraction, 77.0, palette.brake_color)

func draw_pedal(font: Font, label: String, fraction: float, baseline: float, color: Color) -> void:
	draw_string(font, Vector2(126.0, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, palette.pedal_label_color)
	draw_string(font, Vector2(320.0, baseline), "%d%%" % roundi(fraction * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, 56.0, 15, color)
	var bar := Rect2(126.0, baseline + 9.0, 250.0, 15.0)
	draw_rect(bar, palette.bar_background_color)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), color)
