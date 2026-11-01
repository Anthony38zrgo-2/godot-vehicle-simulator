extends Control

const FONT := preload("res://fonts/libron/Libron-Regular.ttf")
const BOLD := preload("res://fonts/libron/Libron-Bold.ttf")
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
	var bottom := size.y / maxf(factor, 0.01) - 22.0
	var origin := Vector2(32.0, bottom - 232.0)
	draw_style_box(_panel(), Rect2(origin, Vector2(330.0, 232.0)))
	var wheels: Array = snapshot.get("wheels", [])
	for i in 4:
		var wheel: Dictionary = wheels[i] if wheels.size() > i else {}
		var p := origin + Vector2(18 + (i % 2) * 160, 25 + (i / 2) * 112)
		draw_style_box(_wheel_panel(), Rect2(p + Vector2(-8, -17), Vector2(152, 109)))
		_draw_wheel_display(p, wheel, i)
	var aids: Dictionary = snapshot.get("aids", {})
	var available: Dictionary = snapshot.get("aids_available", {})
	var aid_text := "AUTO " + ("ON" if bool(aids.get("automatic_transmission", false)) else "OFF")
	for key in ["anti_lock_brakes", "traction_control", "stability"]:
		aid_text += "  |  " + {"anti_lock_brakes": "ABS", "traction_control": "TCS", "stability": "ESP"}[key] + " " + (("ON" if bool(aids.get(key, false)) else "OFF") if bool(available.get(key, false)) else "--")
	text_at(Vector2(size.x / maxf(factor, 0.01) * 0.5 - 180.0, size.y / maxf(factor, 0.01) - 182.0), aid_text, 16, palette.label_color)
	var course: Dictionary = snapshot.get("course", {})
	draw_style_box(_panel(), Rect2(Vector2(14, 10), Vector2(261, 153)))
	text_at(Vector2(28, 37), "STAGE TIMING" if not course.is_empty() else "SESSION", 22, palette.digital_color, true)
	text_at(Vector2(28, 70), time_text(course.get("current_s", snapshot.get("time_s"))), 26, palette.digital_color)
	text_at(Vector2(28, 98), "LAST   " + time_text(course.get("last_s")), 20, palette.label_color)
	text_at(Vector2(28, 128), "BEST   " + time_text(course.get("best_s")), 20, palette.best_lap_color)
	if not course.is_empty():
		draw_course(course)
	draw_set_transform(Vector2.ZERO)

func _draw_wheel_display(p: Vector2, wheel: Dictionary, i: int) -> void:
	# 1. Wheel Label (FL, FR, RL, RR)
	text_at(p + Vector2(-3, -3), ["FL", "FR", "RL", "RR"][i], 14, palette.dial_color, true)

	# 2. Brake Disc and Temperature (Left side of sub-panel)
	var brake_center := Vector2(p.x + 19.0, p.y + 44.0)
	var brake_value: Variant = wheel.get("brake_disc_c")
	var brake_color := brake_temp_color(brake_value)

	text_at(Vector2(p.x + 2.0, p.y + 16.0), "FRENO", 11, palette.label_color)
	# Brake disc outer ring and interior ventilation with dynamic temperature colors
	draw_arc(brake_center, 15.0, 0.0, TAU, 32, brake_color, 2.5, true)
	draw_arc(brake_center, 9.5, 0.0, TAU, 24, brake_color.darkened(0.35), 1.5, true)
	draw_circle(brake_center, 4.0, palette.wheel_hub_color)
	# Brake temp text below disc
	var brake_text := number(brake_value) + "°"
	draw_string(BOLD, Vector2(p.x - 2.0, p.y + 79.0), brake_text, HORIZONTAL_ALIGNMENT_CENTER, 42.0, 13, brake_color)

	# 3. Tire Footprint (Right side of sub-panel)
	var tire_x := p.x + 60.0
	var tire_y := p.y + 15.0
	var tire_w := 66.0
	var tire_h := 57.0

	# Pressure on top of tire
	var press_text := number(wheel.get("pressure_kpa_gauge")) + " kPa"
	draw_string(BOLD, Vector2(tire_x - 4.0, tire_y - 4.0), press_text, HORIZONTAL_ALIGNMENT_CENTER, tire_w + 8.0, 12, palette.digital_color)

	# 3 vertical tread zones with vertical wear depletion
	var col_w := (tire_w - 4.0) / 3.0
	var wear: Variant = wheel.get("wear_fraction")
	var wear_val := clampf(float(wear), 0.0, 1.0) if (wear != null and is_finite(float(wear))) else 0.0
	var spent_h := roundf(tire_h * wear_val)
	var rem_h := tire_h - spent_h
	var zones := [wheel.get("tread_inner_c"), wheel.get("tread_center_c"), wheel.get("tread_outer_c")]

	for col in 3:
		var cx := tire_x + col * (col_w + 2.0)
		# Worn rubber portion (top): dark background with subtle wear hatching
		if spent_h > 0.5:
			draw_rect(Rect2(cx, tire_y, col_w, spent_h), palette.bar_background_color.darkened(0.25))
			draw_line(Vector2(cx, tire_y + spent_h), Vector2(cx + col_w, tire_y), palette.divider_color.darkened(0.45), 1.0)
		# Remaining rubber portion (bottom): active thermal zone color
		if rem_h > 0.5:
			var zone_col := tire_color(zones[col])
			draw_rect(Rect2(cx, tire_y + spent_h, col_w, rem_h), zone_col)

	# Outer border for tire silhouette
	draw_rect(Rect2(tire_x, tire_y, tire_w, tire_h), palette.divider_color.darkened(0.2), false, 1.0)

	# Tread general temperature below tire
	var tread_text := number(wheel.get("tread_c")) + "°C"
	var tread_color := tire_color(wheel.get("tread_c"))
	draw_string(BOLD, Vector2(tire_x - 4.0, tire_y + tire_h + 16.0), tread_text, HORIZONTAL_ALIGNMENT_CENTER, tire_w + 8.0, 14, tread_color)

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

func text_at(point: Vector2, value: String, pixels: int, color: Color = Color("#e9ece8"), bold: bool = false) -> void:
	draw_string(BOLD if bold else FONT, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, color)

func number(value: Variant) -> String:
	return str(roundi(float(value))) if value != null and is_finite(float(value)) else "--"

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

func _panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = palette.background_color
	style.border_color = palette.divider_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style

func _wheel_panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = palette.bar_background_color.darkened(0.18)
	style.bg_color.a = 0.78
	style.border_color = palette.divider_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style

func time_text(value: Variant) -> String:
	if value == null:
		return "--:--.---"
	var seconds := float(value)
	return "%d:%06.3f" % [int(seconds / 60.0), fmod(seconds, 60.0)]

func draw_course(course: Dictionary) -> void:
	var points: Array = course.get("points", [])
	if points.size() < 2:
		return
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for point: Vector3 in points:
		minimum = minimum.min(Vector2(point.x, point.z))
		maximum = maximum.max(Vector2(point.x, point.z))
	var extent := maximum - minimum
	var factor := minf(215.0 / maxf(extent.x, 1.0), 238.0 / maxf(extent.y, 1.0))
	var origin := Vector2(28, 447) + (Vector2(215, 238) - extent * factor) * 0.5
	draw_style_box(_panel(), Rect2(Vector2(14, 419), Vector2(243, 288)))
	text_at(Vector2(28, 442), "RUSSIA STAGE 1", 18, palette.digital_color, true)
	var line := PackedVector2Array()
	for point: Vector3 in points:
		line.append(origin + (Vector2(point.x, point.z) - minimum) * factor)
	draw_polyline(line, palette.divider_color, 3.0, true)
	var split_positions: Array = course.get("split_positions", [])
	for i in split_positions.size():
		var marker: Vector3 = split_positions[i]
		var marker_position := origin + (Vector2(marker.x, marker.z) - minimum) * factor
		var passed := i < int(course.get("next_partial", 1)) - 1
		draw_circle(marker_position, 3.5, palette.map_start_color if passed else palette.digital_color)
	draw_circle(line[0], 4.0, palette.map_start_color)
	draw_circle(line[-1], 4.0, palette.thermal_hot_color)
	var position: Vector3 = course.get("position", Vector3.ZERO)
	draw_circle(origin + (Vector2(position.x, position.z) - minimum) * factor, 5.0, palette.map_player_color)
