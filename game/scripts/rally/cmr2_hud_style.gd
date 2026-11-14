class_name Cmr2HudStyle
extends RefCounted

## Shared palette, formatting helpers, and vector 7-segment LCD drawing
## matching the OpenCMR2 HUD aesthetics.

const FONT_REG := preload("res://fonts/D-DIN.ttf")
const FONT_BOLD := preload("res://fonts/D-DIN-Bold.ttf")

# Exact RGBA values unpacked from OpenCMR2 (RallyData.cpp, HudDash.cpp, gfx.h)
const PANEL_BG := Color(0.737255, 0.745098, 0.862745, 0.588235)         # #bcbedc alpha 0x96
const PANEL_BG_DIM := Color(0.737255, 0.745098, 0.862745, 0.32)         # Future split segments / subtle cards
const PANEL_BG_ACTIVE := Color(0.737255, 0.745098, 0.862745, 0.86)      # Active split highlight strip (0xdd)
const PANEL_PLAYER_BG := Color(0.396078, 0.572549, 1.0, 0.588235)       # #6592ff alpha 0x96
const PANEL_GAUGE_BG := Color(0.24, 0.27, 0.39, 0.72)                   # Deeper cool slate for dense gauge panels
const PANEL_WELL_BG := Color(0.055, 0.082, 0.137, 0.68)                 # Translucent dark inner well for colored bands
const TACHO_PANEL_BG := Color(0.08, 0.09, 0.11, 0.76)                   # Dark translucent charcoal matching NFSU2 dial
const TACHO_PANEL_DIM := Color(0.08, 0.09, 0.11, 0.56)                  # Dimmed tachometer charcoal for future split segments
const TACHO_PANEL_ACTIVE := Color(0.24, 0.28, 0.36, 0.88)               # Highlighted split segment in dark slate charcoal
const TACHO_PLAYER_BG := Color(0.45, 0.07, 0.06, 0.80)                  # Deep red-tinted charcoal
const TACHO_CMR_PLAYER_BG := Color(0.12, 0.25, 0.58, 0.82)              # Deep CMR2 blue for player row on dark HUD
const TACHO_CMR_PLAYER_BORDER := Color(0.40, 0.60, 1.0, 0.52)
const TACHO_WELL_BG := Color(0.04, 0.05, 0.06, 0.82)                    # Deep inner cutout well matching dial center
const TACHO_BORDER := Color(0.76, 0.79, 0.83, 0.34)                     # Subtle silver rim matching dial ticks
const TACHO_DIVIDER := Color(0.76, 0.79, 0.83, 0.24)
const TACHO_SILVER := Color(0.76, 0.79, 0.83, 0.92)
const TACHO_RED := Color("#f0280c")
const PANEL_BORDER := Color(1.0, 1.0, 1.0, 0.28)
const PANEL_DIVIDER := Color(1.0, 1.0, 1.0, 0.24)

const TEXT_WHITE := Color(1.0, 1.0, 1.0, 0.96)
const TEXT_STANDING := Color(1.0, 1.0, 1.0, 0.90)                       # #ffffff high-legibility label/standing ink
const TEXT_MUTED := Color(0.92, 0.94, 1.0, 0.86)
const TEXT_SHADOW := Color(0.0, 0.0, 0.0, 0.92)

const AHEAD_COLOR := Color("#2efaa4")                                   # 0xffa4fa2e
const BEHIND_COLOR := Color("#8a0000")                                  # 0xff00008a
const CYAN_ACCENT := Color("#00f8f8")                                   # g_dashBarColour
const REDLINE_ACCENT := Color("#f83400")                                # g_dashBarRedColour
const AMBER_ACCENT := Color("#f59e0b")

const LCD_DIGIT_MASKS := {
	"0": 63,
	"1": 6,
	"2": 91,
	"3": 79,
	"4": 102,
	"5": 109,
	"6": 125,
	"7": 7,
	"8": 127,
	"9": 111,
}


static func draw_panel(canvas: CanvasItem, rect: Rect2, fill: Color = PANEL_BG, border: Color = PANEL_BORDER) -> void:
	canvas.draw_rect(rect, fill)
	if border.a > 0.0:
		canvas.draw_rect(rect, border, false, 1.0)


static func draw_shadowed_string(
	canvas: CanvasItem,
	font: Font,
	pos: Vector2,
	text: String,
	align: HorizontalAlignment,
	width: float,
	size_px: int,
	color: Color,
	shadow_offset: Vector2 = Vector2(1.5, 1.5)
) -> void:
	if text.is_empty():
		return
	var p := Vector2(roundf(pos.x), roundf(pos.y))
	canvas.draw_string(font, p + shadow_offset, text, align, width, size_px, Color(TEXT_SHADOW, TEXT_SHADOW.a * color.a))
	canvas.draw_string(font, p, text, align, width, size_px, color)


static func draw_box_text(
	canvas: CanvasItem,
	rect: Rect2,
	text: String,
	size_px: int,
	color: Color,
	bold: bool = true,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	if text.is_empty():
		return
	var font: Font = FONT_BOLD if bold else FONT_REG
	var line_h := font.get_height(size_px)
	var baseline := rect.position.y + (rect.size.y + line_h) * 0.5 - font.get_descent(size_px)
	draw_shadowed_string(canvas, font, Vector2(rect.position.x, baseline), text, align, rect.size.x, size_px, color)


static func format_stage_time_ms(ms_value: Variant) -> String:
	if ms_value == null or not (ms_value is int or ms_value is float):
		return "--:--.--"
	var total_cs := maxi(0, int(ms_value) / 10)
	var mins := total_cs / 6000
	var secs := (total_cs % 6000) / 100
	var cs := total_cs % 100
	return "%02d:%02d.%02d" % [mins, secs, cs]


static func format_gap_ms(delta_ms: Variant) -> String:
	if delta_ms == null or not (delta_ms is int or delta_ms is float):
		return "--:--.--"
	var raw := int(delta_ms)
	var sign_char := "-" if raw <= 0 else "+"
	var abs_cs := absi(raw) / 10
	var mins := abs_cs / 6000
	var secs := (abs_cs % 6000) / 100
	var cs := abs_cs % 100
	return "%s%02d:%02d.%02d" % [sign_char, mins, secs, cs]


static func driver_code(full_name: String) -> String:
	var trimmed := full_name.strip_edges()
	if trimmed.is_empty():
		return "---"
	var parts := trimmed.split(" ", false)
	var chosen := parts[-1] if parts.size() > 1 else parts[0]
	var upper := chosen.to_upper()
	return upper.substr(0, mini(upper.length(), 8))


static func measure_lcd_text_width(text: String, digit_h: float) -> float:
	if text.is_empty():
		return 0.0
	var digit_w := digit_h * 0.54
	var narrow_w := digit_h * 0.20
	var spacing := maxf(2.0, digit_h * 0.11)
	var total := 0.0
	for idx in text.length():
		var ch := text.substr(idx, 1)
		if idx > 0:
			total += spacing
		total += narrow_w if ch in [":", "."] else digit_w
	return total


static func draw_lcd_text(
	canvas: CanvasItem,
	origin: Vector2,
	text: String,
	digit_h: float,
	color: Color,
	align_width: float = -1.0,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER,
	ghost_alpha: float = 0.07
) -> void:
	if text.is_empty():
		return
	var digit_w := digit_h * 0.54
	var narrow_w := digit_h * 0.20
	var spacing := maxf(2.0, digit_h * 0.11)
	var total_w := measure_lcd_text_width(text, digit_h)
	var cursor_x := origin.x
	if align_width > 0.0:
		if align == HORIZONTAL_ALIGNMENT_CENTER:
			cursor_x += (align_width - total_w) * 0.5
		elif align == HORIZONTAL_ALIGNMENT_RIGHT:
			cursor_x += align_width - total_w

	var shadow := Color(0.0, 0.0, 0.0, 0.55 * color.a)
	var shadow_off := Vector2(maxf(1.0, digit_h * 0.035), maxf(1.0, digit_h * 0.035))
	var ghost := Color(color.r, color.g, color.b, ghost_alpha * color.a)

	for idx in text.length():
		var ch := text.substr(idx, 1)
		var cell_w := narrow_w if ch in [":", "."] else digit_w
		var cell := Rect2(cursor_x, origin.y, cell_w, digit_h)
		if ch == ":":
			_draw_lcd_colon(canvas, cell, color, shadow, shadow_off)
		elif ch == ".":
			_draw_lcd_dot(canvas, cell, color, shadow, shadow_off)
		elif ch == "-":
			_draw_lcd_digit(canvas, cell, 64, color, shadow, shadow_off, ghost)
		elif ch == "+":
			_draw_lcd_plus(canvas, cell, color, shadow, shadow_off)
		elif LCD_DIGIT_MASKS.has(ch):
			_draw_lcd_digit(canvas, cell, int(LCD_DIGIT_MASKS[ch]), color, shadow, shadow_off, ghost)
		elif ch != " ":
			draw_box_text(canvas, cell, ch, roundi(digit_h * 0.8), color, true, HORIZONTAL_ALIGNMENT_CENTER)
		cursor_x += cell_w + spacing


static func _draw_lcd_colon(canvas: CanvasItem, rect: Rect2, color: Color, shadow: Color, off: Vector2) -> void:
	var side := maxf(3.0, rect.size.y * 0.13)
	var cx := rect.position.x + (rect.size.x - side) * 0.5
	for frac in [0.27, 0.65]:
		var dot := Rect2(cx, rect.position.y + rect.size.y * frac - side * 0.5, side, side)
		canvas.draw_rect(Rect2(dot.position + off, dot.size), shadow)
		canvas.draw_rect(dot, color)


static func _draw_lcd_dot(canvas: CanvasItem, rect: Rect2, color: Color, shadow: Color, off: Vector2) -> void:
	var side := maxf(3.0, rect.size.y * 0.13)
	var dot := Rect2(rect.position.x + (rect.size.x - side) * 0.5, rect.end.y - side, side, side)
	canvas.draw_rect(Rect2(dot.position + off, dot.size), shadow)
	canvas.draw_rect(dot, color)


static func _draw_lcd_plus(canvas: CanvasItem, rect: Rect2, color: Color, shadow: Color, off: Vector2) -> void:
	var s := rect.size.y * 0.135
	var hs := s * 0.5
	var cx := rect.position.x + rect.size.x * 0.5
	var cy := rect.position.y + rect.size.y * 0.5
	var reach := rect.size.x * 0.44
	var h_poly := PackedVector2Array([
		Vector2(cx - reach, cy),
		Vector2(cx - reach + hs, cy - hs),
		Vector2(cx + reach - hs, cy - hs),
		Vector2(cx + reach, cy),
		Vector2(cx + reach - hs, cy + hs),
		Vector2(cx - reach + hs, cy + hs),
	])
	var v_poly := PackedVector2Array([
		Vector2(cx, cy - reach),
		Vector2(cx + hs, cy - reach + hs),
		Vector2(cx + hs, cy + reach - hs),
		Vector2(cx, cy + reach),
		Vector2(cx - hs, cy + reach - hs),
		Vector2(cx - hs, cy - reach + hs),
	])
	for poly in [h_poly, v_poly]:
		_draw_offset_poly(canvas, poly, off, shadow)
		canvas.draw_colored_polygon(poly, color)


static func _draw_lcd_digit(
	canvas: CanvasItem,
	rect: Rect2,
	mask: int,
	color: Color,
	shadow: Color,
	off: Vector2,
	ghost: Color
) -> void:
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	var s := h * 0.145
	var hs := s * 0.5
	var g := maxf(1.0, h * 0.022)
	var m := y + h * 0.5

	var segs: Array[PackedVector2Array] = [
		# 0: A (top)
		PackedVector2Array([
			Vector2(x + hs + g, y),
			Vector2(x + w - hs - g, y),
			Vector2(x + w - s - g, y + s),
			Vector2(x + s + g, y + s),
		]),
		# 1: B (top-right)
		PackedVector2Array([
			Vector2(x + w, y + hs + g),
			Vector2(x + w, m - hs - g),
			Vector2(x + w - hs, m - g * 0.5),
			Vector2(x + w - s, m - hs - g),
			Vector2(x + w - s, y + s + g),
		]),
		# 2: C (bottom-right)
		PackedVector2Array([
			Vector2(x + w, m + hs + g),
			Vector2(x + w, y + h - hs - g),
			Vector2(x + w - s, y + h - s - g),
			Vector2(x + w - s, m + hs + g),
			Vector2(x + w - hs, m + g * 0.5),
		]),
		# 3: D (bottom)
		PackedVector2Array([
			Vector2(x + s + g, y + h - s),
			Vector2(x + w - s - g, y + h - s),
			Vector2(x + w - hs - g, y + h),
			Vector2(x + hs + g, y + h),
		]),
		# 4: E (bottom-left)
		PackedVector2Array([
			Vector2(x, m + hs + g),
			Vector2(x + hs, m + g * 0.5),
			Vector2(x + s, m + hs + g),
			Vector2(x + s, y + h - s - g),
			Vector2(x, y + h - hs - g),
		]),
		# 5: F (top-left)
		PackedVector2Array([
			Vector2(x, y + hs + g),
			Vector2(x + s, y + s + g),
			Vector2(x + s, m - hs - g),
			Vector2(x + hs, m - g * 0.5),
			Vector2(x, m - hs - g),
		]),
		# 6: G (middle)
		PackedVector2Array([
			Vector2(x + hs + g, m),
			Vector2(x + s + g, m - hs),
			Vector2(x + w - s - g, m - hs),
			Vector2(x + w - hs - g, m),
			Vector2(x + w - s - g, m + hs),
			Vector2(x + s + g, m + hs),
		]),
	]

	for bit in 7:
		var poly := segs[bit]
		if (mask & (1 << bit)) != 0:
			_draw_offset_poly(canvas, poly, off, shadow)
			canvas.draw_colored_polygon(poly, color)
		elif ghost.a > 0.005:
			canvas.draw_colored_polygon(poly, ghost)


static func _draw_offset_poly(canvas: CanvasItem, poly: PackedVector2Array, off: Vector2, color: Color) -> void:
	var shifted := PackedVector2Array()
	shifted.resize(poly.size())
	for i in poly.size():
		shifted[i] = poly[i] + off
	canvas.draw_colored_polygon(shifted, color)
