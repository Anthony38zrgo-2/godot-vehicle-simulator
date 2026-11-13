extends Control

## Minimalist CMR2-styled bottom-center driving controls readout
## (steering wheel angle, throttle %, and brake %).

const Cmr2Style := preload("res://scripts/rally/cmr2_hud_style.gd")

const PANEL_SIZE := Vector2(380.0, 102.0)

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
	Cmr2Style.draw_panel(self, Rect2(Vector2.ZERO, PANEL_SIZE), Cmr2Style.PANEL_GAUGE_BG, Cmr2Style.PANEL_BORDER)

	# Left column: steering wheel + angle readout
	var left_w := 102.0
	Cmr2Style.draw_box_text(self, Rect2(8.0, 5.0, left_w - 16.0, 14.0), "VOLANTE", 11, Cmr2Style.TEXT_WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)

	var wheel_center := Vector2(left_w * 0.5, 49.0)
	var radius := 23.0
	draw_circle(wheel_center, radius, Cmr2Style.PANEL_WELL_BG)
	draw_arc(wheel_center, radius, 0.0, TAU, 48, Cmr2Style.TEXT_WHITE, 2.5, true)
	var wheel_rotation := -steering_fraction * PI * 0.75
	for spoke_angle in [-PI * 0.5, PI / 6.0, PI * 5.0 / 6.0]:
		var direction := Vector2(cos(spoke_angle + wheel_rotation), sin(spoke_angle + wheel_rotation))
		var spoke_color := Cmr2Style.CYAN_ACCENT if spoke_angle < 0.0 else Cmr2Style.TEXT_STANDING
		draw_line(wheel_center + direction * 5.0, wheel_center + direction * (radius - 2.0), spoke_color, 2.5, true)
	draw_circle(wheel_center, 4.5, Cmr2Style.TEXT_WHITE, true, -1.0, true)

	var steering_pct := roundi(absf(steering_fraction) * 100.0)
	var steering_text := "%d%%" % steering_pct
	if absf(steering_fraction) > 0.005:
		steering_text = ("IZQ " if steering_fraction > 0.0 else "DER ") + steering_text
	var steer_col := Cmr2Style.CYAN_ACCENT if absf(steering_fraction) > 0.02 else Cmr2Style.TEXT_MUTED
	Cmr2Style.draw_box_text(self, Rect2(6.0, 79.0, left_w - 12.0, 16.0), steering_text, 12, steer_col, true, HORIZONTAL_ALIGNMENT_CENTER)

	# Vertical CMR2 divider
	draw_line(Vector2(left_w, 8.0), Vector2(left_w, PANEL_SIZE.y - 8.0), Cmr2Style.PANEL_DIVIDER, 1.0)

	# Right column: Throttle and Brake bars
	var right_x := left_w + 14.0
	var right_w := PANEL_SIZE.x - right_x - 14.0
	_draw_pedal_row(Rect2(right_x, 12.0, right_w, 34.0), "ACELERADOR", accelerator_fraction, Cmr2Style.AHEAD_COLOR)
	_draw_pedal_row(Rect2(right_x, 56.0, right_w, 34.0), "FRENO", brake_fraction, Cmr2Style.REDLINE_ACCENT)


func _draw_pedal_row(rect: Rect2, label: String, fraction: float, fill_color: Color) -> void:
	Cmr2Style.draw_box_text(self, Rect2(rect.position.x, rect.position.y, 130.0, 15.0), label, 12, Cmr2Style.TEXT_WHITE, true)
	Cmr2Style.draw_box_text(
		self,
		Rect2(rect.end.x - 64.0, rect.position.y, 64.0, 15.0),
		"%d%%" % roundi(fraction * 100.0),
		13,
		fill_color if fraction > 0.01 else Cmr2Style.TEXT_MUTED,
		true,
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	var bar := Rect2(rect.position.x, rect.position.y + 18.0, rect.size.x, 13.0)
	draw_rect(bar, Cmr2Style.PANEL_WELL_BG)
	draw_rect(bar, Color(1.0, 1.0, 1.0, 0.20), false, 1.0)
	if fraction > 0.005:
		var fill_w := clampf(bar.size.x * fraction, 2.0, bar.size.x)
		draw_rect(Rect2(bar.position, Vector2(fill_w, bar.size.y)), fill_color)
