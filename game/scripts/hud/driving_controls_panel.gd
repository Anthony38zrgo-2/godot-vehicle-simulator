extends Control

## Minimalist CMR2-styled bottom-center driving controls readout
## (steering wheel angle, throttle %, and brake %).

const Cmr2Style := preload("res://scripts/rally/cmr2_hud_style.gd")

const PANEL_SIZE := Vector2(348.0, 68.0)

var palette: RetroHudConfig = RetroHudConfig.new()
var steering_fraction := 0.0
var accelerator_fraction := 0.0
var brake_fraction := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	queue_redraw()


func set_palette(next_palette: RetroHudConfig) -> void:
	if next_palette == null:
		return
	palette = next_palette
	queue_redraw()


func set_controls(steering: float, accelerator: float, brake: float) -> void:
	steering_fraction = clampf(steering, -1.0, 1.0)
	accelerator_fraction = clampf(accelerator, 0.0, 1.0)
	brake_fraction = clampf(brake, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	Cmr2Style.draw_panel(self, Rect2(Vector2.ZERO, PANEL_SIZE), Cmr2Style.TACHO_PANEL_BG, Cmr2Style.TACHO_BORDER)

	# Left column: steering wheel purely visual (no text)
	var left_w := 76.0
	var wheel_center := Vector2(left_w * 0.5, PANEL_SIZE.y * 0.5)
	var radius := 21.0
	draw_circle(wheel_center, radius, Cmr2Style.TACHO_WELL_BG)
	draw_arc(wheel_center, radius, 0.0, TAU, 48, Cmr2Style.TEXT_WHITE, 2.5, true)
	var wheel_rotation := -steering_fraction * PI * 0.75
	for spoke_angle in [-PI * 0.5, PI / 6.0, PI * 5.0 / 6.0]:
		var direction := Vector2(cos(spoke_angle + wheel_rotation), sin(spoke_angle + wheel_rotation))
		var spoke_color := Cmr2Style.CYAN_ACCENT if spoke_angle < 0.0 else Cmr2Style.TEXT_STANDING
		draw_line(wheel_center + direction * 5.0, wheel_center + direction * (radius - 2.0), spoke_color, 2.5, true)
	draw_circle(wheel_center, 4.0, Cmr2Style.TEXT_WHITE, true, -1.0, true)

	# Vertical divider
	draw_line(Vector2(left_w, 8.0), Vector2(left_w, PANEL_SIZE.y - 8.0), Cmr2Style.TACHO_DIVIDER, 1.0)

	# Right column: Throttle and Brake visual bars (no text)
	var right_x := left_w + 14.0
	var right_w := PANEL_SIZE.x - right_x - 14.0
	_draw_pedal_bar(Rect2(right_x, 14.0, right_w, 15.0), accelerator_fraction, Cmr2Style.AHEAD_COLOR)
	_draw_pedal_bar(Rect2(right_x, 39.0, right_w, 15.0), brake_fraction, Cmr2Style.REDLINE_ACCENT)


func _draw_pedal_bar(bar: Rect2, fraction: float, fill_color: Color) -> void:
	draw_rect(bar, Cmr2Style.TACHO_WELL_BG)
	draw_rect(bar, Cmr2Style.TACHO_BORDER, false, 1.0)
	if fraction > 0.005:
		var fill_w := clampf(bar.size.x * fraction, 2.0, bar.size.x)
		draw_rect(Rect2(bar.position, Vector2(fill_w, bar.size.y)), fill_color)
