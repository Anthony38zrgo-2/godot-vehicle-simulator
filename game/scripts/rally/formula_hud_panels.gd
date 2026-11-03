extends Control

# Paneles de contexto de la HUD: mapa vertical, neumáticos 2×2 y tiempos.
# Aero Glass en los marcos, Windows 98 en el interior, texto en Libron y
# números en D-DIN.

const FONT := preload("res://fonts/libron/Libron-Regular.ttf")
const BOLD := preload("res://fonts/libron/Libron-Bold.ttf")
const DIN := preload("res://fonts/D-DIN.ttf")
const DIN_BOLD := preload("res://fonts/D-DIN-Bold.ttf")

const C_FACE := Color("#2b3d4d")
const C_FACE_HI := Color("#374c5e")
const C_FACE_LO := Color("#22323f")
const C_FIELD := Color("#0c151d")
const C_HI := Color("#93afc8")
const C_LIGHT := Color("#5d7890")
const C_SHADOW := Color("#101b25")
const C_DARK := Color("#000000")
const C_TEXT := Color("#e2edf6")
const C_DIM := Color("#9eb3c5")
const C_GOLD := Color("#e3b23c")
const C_ROSE := Color("#ff6b61")
const C_GREEN := Color("#8fd36b")
const C_BLUE := Color("#6db2e8")
const C_BLUE_DEEP := Color("#2c6da3")
const C_GLASS := Color("#16232f")
const C_RIM := Color("#7fa8c9")

const MAP_RECT := Rect2(24, 24, 264, 330)
const TIMING_RECT := Rect2(1620, 24, 276, 132)
const DAMAGE_RECT := Rect2(1620, 482, 276, 116)
const TIRES_W := 300.0
const TIRES_H := 160.0
const BAND_MARGIN := 24.0

var snapshot: Dictionary = {}
var thermal_config: Dictionary = {}
var palette: RetroHudConfig = RetroHudConfig.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func present(state: Dictionary, limits: Dictionary) -> void:
	snapshot = state
	thermal_config = limits
	queue_redraw()


func set_palette(next_palette: RetroHudConfig) -> void:
	if next_palette == null:
		return
	palette = next_palette
	queue_redraw()


func _draw() -> void:
	var factor := minf(size.x / 1920.0, size.y / 1080.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * factor)
	var band_y := size.y / maxf(factor, 0.01) - TIRES_H - BAND_MARGIN
	_draw_timing(TIMING_RECT)
	_draw_damage(DAMAGE_RECT)
	_draw_map(MAP_RECT)
	_draw_tires(Rect2(24.0, band_y, TIRES_W, TIRES_H))
	draw_set_transform(Vector2.ZERO)


# =============================================================================
# DAÑOS
# =============================================================================


func _draw_damage(rect: Rect2) -> void:
	_glass(rect)
	var body := Rect2(rect.position.x + 8, rect.position.y + 8, rect.size.x - 16, rect.size.y - 16)
	draw_rect(body, C_FACE)
	_bevel(body, false, 2)

	_text(Rect2(body.position.x + 6, body.position.y + 2, 220, 14), "ESTADO DE DAÑOS", 9, C_BLUE, true)
	draw_rect(Rect2(body.position.x + 2, body.position.y + 18, body.size.x - 4, 1), C_SHADOW)

	var dmg: Dictionary = snapshot.get("damage", {})
	var eng_snap: Dictionary = snapshot.get("engine", {})
	var rad_ratio := clampf(float(dmg.get("radiator", eng_snap.get("radiator_damage", 0.0))), 0.0, 1.0)
	var eng_ratio := clampf(float(dmg.get("engine", eng_snap.get("engine_damage", 0.0))), 0.0, 1.0)

	var rows := [
		{"label": "RADIADOR", "ratio": rad_ratio, "y": 24.0},
		{"label": "MOTOR", "ratio": eng_ratio, "y": 58.0},
	]

	for row in rows:
		var y: float = body.position.y + float(row.y)
		var ratio: float = float(row.ratio)
		var color := _damage_color(ratio)
		_text(Rect2(body.position.x + 6, y, 90, 14), str(row.label), 9, C_DIM, true)
		var pct_str := "%d%%" % roundi(ratio * 100.0)
		_num(Rect2(body.position.x + body.size.x - 60, y, 54, 14), pct_str, 12, color, HORIZONTAL_ALIGNMENT_RIGHT)

		var bar_rect := Rect2(body.position.x + 6, y + 16, body.size.x - 12, 12)
		draw_rect(bar_rect, C_FIELD)
		_sunken(bar_rect)
		if ratio > 0.005:
			var fill_w := maxf((bar_rect.size.x - 4) * ratio, 2.0)
			draw_rect(Rect2(bar_rect.position.x + 2, bar_rect.position.y + 2, fill_w, bar_rect.size.y - 4), color)


func _damage_color(ratio: float) -> Color:
	if ratio < 0.25:
		return C_GREEN
	if ratio < 0.50:
		return C_GOLD
	if ratio < 0.75:
		return Color("#f08c35")
	return C_ROSE


# =============================================================================
# TIEMPOS
# =============================================================================


func _draw_timing(rect: Rect2) -> void:
	var course: Dictionary = snapshot.get("course", {})
	_glass(rect)
	var body := Rect2(rect.position.x + 8, rect.position.y + 8, rect.size.x - 16, rect.size.y - 16)
	draw_rect(body, C_FACE)
	_bevel(body, false, 2)

	_text(Rect2(body.position.x + 2, body.position.y, 220, 14), "TIEMPO DE ESPECIAL", 9, C_BLUE, true)
	draw_rect(Rect2(body.position.x + 2, body.position.y + 16, body.size.x - 4, 1), C_SHADOW)

	var rows := [
		{ "k": "ACTUAL", "v": time_text(course.get("current_s")), "size": 24, "c": C_TEXT, "y": 20.0, "h": 30.0 },
		{ "k": "ÚLTIMO", "v": time_text(course.get("last_s")), "size": 16, "c": C_DIM, "y": 54.0, "h": 26.0 },
		{ "k": "MEJOR", "v": time_text(course.get("best_s")), "size": 16, "c": C_GREEN, "y": 84.0, "h": 26.0 },
	]
	for row in rows:
		var y: float = body.position.y + float(row.y)
		var h: float = float(row.h)
		_text(Rect2(body.position.x + 2, y, 58, h), str(row.k), 9, C_DIM)
		_field(Rect2(body.position.x + 64, y, body.size.x - 66, h), str(row.v), int(row.size), row.c)


# =============================================================================
# MAPA VERTICAL
# =============================================================================


func _draw_map(rect: Rect2) -> void:
	_glass(rect)
	var body := Rect2(rect.position.x + 8, rect.position.y + 8, rect.size.x - 16, rect.size.y - 16)
	draw_rect(body, C_FIELD)
	_sunken(body)

	var course: Dictionary = snapshot.get("course", {})
	var points: Array = course.get("points", [])
	if points.size() >= 2:
		var rotation := map_rotation(points)
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for point: Vector3 in points:
			var flat := Vector2(point.x, point.z).rotated(rotation)
			minimum = minimum.min(flat)
			maximum = maximum.max(flat)
		var extent := maximum - minimum
		var fit := minf(
			(body.size.x - 32.0) / maxf(extent.x, 1.0), (body.size.y - 104.0) / maxf(extent.y, 1.0)
		)
		var origin := (
			body.position
			+ Vector2(16, 14)
			+ (Vector2(body.size.x - 32.0, body.size.y - 104.0) - extent * fit) * 0.5
		)
		var line := PackedVector2Array()
		for point: Vector3 in points:
			line.append(origin + (Vector2(point.x, point.z).rotated(rotation) - minimum) * fit)
		draw_polyline(line, Color(C_RIM, 0.35), 8.0, true)
		draw_polyline(line, C_TEXT, 2.5, true)
		var splits: Array = course.get("split_positions", [])
		for i in splits.size():
			var marker: Vector3 = splits[i]
			var passed := i < int(course.get("next_partial", 1)) - 1
			draw_circle(
				origin + (Vector2(marker.x, marker.z).rotated(rotation) - minimum) * fit,
				3.5,
				palette.map_start_color if passed else C_TEXT
			)
		draw_circle(origin + (Vector2(points[0].x, points[0].z).rotated(rotation) - minimum) * fit, 4.5, palette.map_start_color)
		draw_circle(origin + (Vector2(points[-1].x, points[-1].z).rotated(rotation) - minimum) * fit, 4.5, C_ROSE)
		var position: Vector3 = course.get("position", Vector3.ZERO)
		draw_circle(origin + (Vector2(position.x, position.z).rotated(rotation) - minimum) * fit, 6.0, palette.map_player_color)

	var label := str(course.get("label", ""))
	var strip := Rect2(body.position.x + 8, body.end.y - 68, body.size.x - 16, 60)
	draw_rect(strip, C_FACE)
	_bevel(strip, false, 1)
	_text(
		Rect2(strip.position.x + 8, strip.position.y, strip.size.x - 16, 24),
		label.to_upper(),
		11,
		C_TEXT,
		true,
		HORIZONTAL_ALIGNMENT_CENTER,
		strip.size.x - 16
	)

	_text(Rect2(strip.position.x + 8, strip.position.y + 25, strip.size.x - 16, 15), "Aire: " + number(snapshot.get("air_temp_c")) + " °C", 11, C_TEXT)
	_text(Rect2(strip.position.x + 8, strip.position.y + 41, strip.size.x - 16, 15), "Suelo: " + _surface_temperature(), 11, C_DIM)


func map_rotation(points: Array) -> float:
	# Align the route's longest principal axis vertically, with finish above start.
	if points.size() < 2:
		return 0.0
	var center := Vector2.ZERO
	for point: Vector3 in points:
		center += Vector2(point.x, point.z)
	center /= float(points.size())
	var xx := 0.0
	var yy := 0.0
	var xy := 0.0
	for point: Vector3 in points:
		var offset := Vector2(point.x, point.z) - center
		xx += offset.x * offset.x
		yy += offset.y * offset.y
		xy += offset.x * offset.y
	var angle := -PI * 0.5 - atan2(2.0 * xy, xx - yy) * 0.5
	var route_direction: Vector3 = points[-1] - points[0]
	if Vector2(route_direction.x, route_direction.z).rotated(angle).y > 0.0:
		angle += PI
	return angle


func _surface_temperature() -> String:
	var st: Dictionary = snapshot.get("surface_temp", {})
	if st.is_empty() or not bool(st.get("ok", false)):
		return "-- °C"
	return "%d °C" % roundi(float(st.get("celsius", 0.0)))


# =============================================================================
# NEUMÁTICOS 2×2
# =============================================================================


func _draw_tires(rect: Rect2) -> void:
	var wheels: Array = snapshot.get("wheels", [])
	var codes := ["FL", "FR", "RL", "RR"]
	var cell_w := (rect.size.x - 8.0) * 0.5
	var cell_h := (rect.size.y - 8.0) * 0.5
	for i in 4:
		var col := i % 2
		var row := i / 2
		var x := rect.position.x + float(col) * (cell_w + 8.0)
		var y := rect.position.y + float(row) * (cell_h + 8.0)
		var card := Rect2(x, y, cell_w, cell_h)
		draw_rect(card, C_FACE)
		_bevel(card, false, 2)

		var wheel: Dictionary = wheels[i] if wheels.size() > i else {}
		_text(Rect2(x + 8, y + 4, 40, 14), codes[i], 8, Color(C_DIM, 0.85), true)
		_num(
			Rect2(x + 58, y + 4, 80, 14),
			number(wheel.get("pressure_kpa_gauge")) + " kPa",
			12,
			C_BLUE,
			HORIZONTAL_ALIGNMENT_CENTER,
			80
		)

		var center := Vector2(x + 30, y + 42)
		var brake_value: Variant = wheel.get("brake_disc_c")
		var disc_color := brake_temp_color(brake_value)
		draw_circle(center, 14.0, Color(0, 0, 0, 0.30))
		draw_circle(center, 14.0, C_FIELD)
		draw_arc(center, 14.0, 0.0, TAU, 28, disc_color, 3.0, true)
		draw_arc(center, 7.5, 0.0, TAU, 20, Color(disc_color, 0.4), 2.0, true)
		_num(Rect2(x + 8, y + 56, 44, 14), number(brake_value) + "°", 12, disc_color, HORIZONTAL_ALIGNMENT_CENTER, 44)

		var tire := Rect2(x + 62, y + 18, 54, 36)
		draw_rect(Rect2(tire.position + Vector2(2, 3), tire.size), Color(0, 0, 0, 0.35))
		draw_rect(tire, C_FIELD)
		_sunken(tire)
		var wear: Variant = wheel.get("wear_fraction")
		var wear_val := clampf(float(wear), 0.0, 1.0) if (wear != null and is_finite(float(wear))) else 0.0
		var zone_colors := tire_zone_colors(wheel, i)
		for band in 3:
			var band_rect := Rect2(tire.position.x + 3 + float(band) * 17.0, tire.position.y + 3, 15, tire.size.y - 6)
			var spent := floorf(band_rect.size.y * wear_val)
			draw_rect(Rect2(band_rect.position, Vector2(band_rect.size.x, spent)), C_FACE_LO)
			draw_rect(
				Rect2(band_rect.position.x, band_rect.position.y + spent, band_rect.size.x, band_rect.size.y - spent),
				zone_colors[band]
			)
		var tread_color := tire_color(wheel.get("tread_c"))
		_num(
			Rect2(x + 54, y + 56, 70, 14),
			number(wheel.get("tread_c")) + " °C",
			14,
			tread_color,
			HORIZONTAL_ALIGNMENT_CENTER,
			70
		)


# =============================================================================
# PRIMITIVAS
# =============================================================================


func _glass(rect: Rect2) -> void:
	var body := StyleBoxFlat.new()
	body.bg_color = Color(C_GLASS, 0.90)
	body.border_color = Color(C_RIM, 0.40)
	body.set_border_width_all(1)
	body.set_corner_radius_all(10)
	draw_style_box(body, rect)


func _bevel(rect: Rect2, raised: bool, thick: int = 2) -> void:
	for i in thick:
		var top_color: Color
		var bottom_color: Color
		if i == 0:
			top_color = C_HI if raised else C_SHADOW
			bottom_color = C_DARK if raised else C_HI
		else:
			top_color = C_LIGHT if raised else C_DARK
			bottom_color = C_SHADOW if raised else C_LIGHT
		draw_rect(Rect2(rect.position.x + i, rect.position.y + i, rect.size.x - i * 2, 1), top_color)
		draw_rect(Rect2(rect.position.x + i, rect.position.y + i, 1, rect.size.y - i * 2), top_color)
		draw_rect(Rect2(rect.position.x + i, rect.end.y - 1 - i, rect.size.x - i * 2, 1), bottom_color)
		draw_rect(Rect2(rect.end.x - 1 - i, rect.position.y + i, 1, rect.size.y - i * 2), bottom_color)


func _sunken(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 1), C_SHADOW)
	draw_rect(Rect2(rect.position.x, rect.position.y, 1, rect.size.y), C_SHADOW)
	draw_rect(Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1), C_HI)
	draw_rect(Rect2(rect.end.x - 1, rect.position.y, 1, rect.size.y), C_HI)


func _field(rect: Rect2, value: String, size_px: int, color: Color) -> void:
	draw_rect(rect, C_FIELD)
	_sunken(rect)
	_num(
		Rect2(rect.position.x + 8, rect.position.y, rect.size.x - 16, rect.size.y),
		value,
		size_px,
		color,
		HORIZONTAL_ALIGNMENT_RIGHT
	)


func _num(
	rect: Rect2,
	value: String,
	size_px: int,
	color: Color,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	width_override: float = -1.0
) -> void:
	if value.is_empty():
		return
	var width: float = rect.size.x if width_override < 0.0 else width_override
	var line_height := BOLD.get_height(size_px)
	var baseline := rect.position.y + (rect.size.y + line_height) * 0.5 - BOLD.get_descent(size_px)
	draw_string(BOLD, Vector2(round(rect.position.x), round(baseline)), value, align, width, size_px, color)


func _text(
	rect: Rect2,
	value: String,
	size_px: int,
	color: Color,
	bold: bool = false,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	width_override: float = -1.0
) -> void:
	if value.is_empty():
		return
	var font: Font = BOLD if bold else FONT
	var width: float = rect.size.x if width_override < 0.0 else width_override
	var line_height := font.get_height(size_px)
	var baseline := rect.position.y + (rect.size.y + line_height) * 0.5 - font.get_descent(size_px)
	draw_string(font, Vector2(round(rect.position.x), round(baseline)), value, align, width, size_px, color)


# =============================================================================
# DATOS
# =============================================================================


func brake_temp_color(value: Variant) -> Color:
	if value == null or not is_finite(float(value)):
		return palette.pending_color
	var t := float(value)
	if t < 150.0:
		return palette.thermal_cold_color
	if t <= 450.0:
		return palette.thermal_optimal_color
	if t <= 600.0:
		return palette.thermal_warm_color
	if t <= 750.0:
		return palette.thermal_hot_color
	return palette.thermal_critical_color


func tire_color(value: Variant) -> Color:
	if value == null or not is_finite(float(value)):
		return palette.pending_color
	var optimum := float(thermal_config.get("optimal_tread_temperature_c", 50.0))
	var half_window := float(thermal_config.get("optimal_tread_window_c", 50.0)) * 0.5
	if float(value) <= optimum - half_window:
		return palette.thermal_cold_color
	if float(value) <= optimum + half_window:
		return palette.thermal_optimal_color
	if float(value) <= float(thermal_config.get("overheat_tread_temperature_c", 100.0)):
		return palette.thermal_warm_color
	if float(value) > maxf(float(thermal_config.get("overheat_tread_temperature_c", 100.0)) * 1.3, 130.0):
		return palette.thermal_critical_color
	return palette.thermal_hot_color


func tire_zone_colors(wheel: Dictionary, wheel_index: int) -> Array[Color]:
	# Viewed from above: the outer shoulder is on the outside of the car.
	var keys := ["tread_outer_c", "tread_center_c", "tread_inner_c"]
	if wheel_index % 2 == 1:
		keys = ["tread_inner_c", "tread_center_c", "tread_outer_c"]
	var colors: Array[Color] = []
	for key in keys:
		colors.append(tire_color(wheel.get(key)))
	return colors


func number(value: Variant) -> String:
	return str(roundi(float(value))) if value != null and is_finite(float(value)) else "--"


func time_text(value: Variant) -> String:
	if value == null:
		return "--:--.---"
	var seconds := float(value)
	return "%d:%06.3f" % [int(seconds / 60.0), fmod(seconds, 60.0)]
