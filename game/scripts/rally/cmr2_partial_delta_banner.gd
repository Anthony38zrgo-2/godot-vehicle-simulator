class_name Cmr2PartialDeltaBanner
extends Control

## Centered translucent CMR2-style split time gap banner (-mm:ss.hh / +mm:ss.hh),
## replacing centered status/aid messages.

const Cmr2Style := preload("res://scripts/rally/cmr2_hud_style.gd")

const DISPLAY_DURATION_S := 3.0
const FADE_OUT_S := 0.40
const BOX_SIZE := Vector2(292.0, 68.0)
const CENTER_Y_RATIO := 0.48
const BACKGROUND_ALPHA := 0.72

var sector_index: int = 0
var delta_ms: Variant = null
var formatted_text: String = "--:--.--"
var remaining_seconds: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func show_delta(index: int, next_delta_ms: Variant, duration_seconds: float = DISPLAY_DURATION_S) -> void:
	sector_index = index
	delta_ms = next_delta_ms
	formatted_text = Cmr2Style.format_gap_ms(next_delta_ms)
	remaining_seconds = maxf(duration_seconds, 0.01)
	visible = true
	queue_redraw()


func box_color() -> Color:
	var base := Cmr2Style.PANEL_BG
	if delta_ms != null and (delta_ms is int or delta_ms is float):
		base = Cmr2Style.AHEAD_COLOR if int(delta_ms) <= 0 else Cmr2Style.BEHIND_COLOR
	return Color(base.r, base.g, base.b, BACKGROUND_ALPHA)


func _process(delta: float) -> void:
	if remaining_seconds <= 0.0:
		return
	remaining_seconds = maxf(0.0, remaining_seconds - delta)
	if remaining_seconds <= 0.0:
		visible = false
	elif remaining_seconds < FADE_OUT_S:
		queue_redraw()


func _draw() -> void:
	if not visible or formatted_text.is_empty():
		return
	var vp := size if size.x > 1.0 and size.y > 1.0 else Vector2(1920.0, 1080.0)
	var factor := minf(vp.x / 1920.0, vp.y / 1080.0)
	var fade := clampf(remaining_seconds / FADE_OUT_S, 0.0, 1.0) if remaining_seconds < FADE_OUT_S else 1.0
	var box_w := BOX_SIZE.x * factor
	var box_h := BOX_SIZE.y * factor
	var rect := Rect2(
		roundf((vp.x - box_w) * 0.5),
		roundf(vp.y * CENTER_Y_RATIO - box_h * 0.5),
		box_w,
		box_h
	)
	var bg := box_color()
	bg.a *= fade
	var border := Color(1.0, 1.0, 1.0, 0.34 * fade)
	Cmr2Style.draw_panel(self, rect, bg, border)

	var digit_h := 44.0 * factor
	var text_y := rect.position.y + (rect.size.y - digit_h) * 0.5
	var fg := Color(1.0, 1.0, 1.0, 0.94 * fade)
	Cmr2Style.draw_lcd_text(self, Vector2(rect.position.x, text_y), formatted_text, digit_h, fg, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER, 0.06)
