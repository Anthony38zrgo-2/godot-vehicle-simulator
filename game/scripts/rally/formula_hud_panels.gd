extends Control

const FONT := preload("res://fonts/D-DINCondensed.ttf")
const BOLD := preload("res://fonts/D-DINCondensed-Bold.ttf")
var snapshot: Dictionary = {}
var thermal_config: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func present(state: Dictionary, limits: Dictionary) -> void:
	snapshot = state
	thermal_config = limits
	queue_redraw()

func _draw() -> void:
	var factor := minf(size.x / 1920.0, size.y / 1080.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * factor)
	var bottom := size.y / maxf(factor, 0.01) - 48.0
	var origin := Vector2(14.0, bottom - 286.0)
	draw_style_box(_panel(), Rect2(origin, Vector2(402.0, 286.0)))
	text_at(origin + Vector2(14, 26), "TYRES / BRAKES", 21, Color.WHITE, true)
	var wheels: Array = snapshot.get("wheels", [])
	for i in 4:
		var wheel: Dictionary = wheels[i] if wheels.size() > i else {}
		var p := origin + Vector2(14 + (i % 2) * 196, 55 + (i / 2) * 112)
		text_at(p, ["FL", "FR", "RL", "RR"][i], 23, Color.WHITE, true)
		text_at(p + Vector2(42, 0), number(wheel.get("pressure_kpa_gauge")) + " kPa", 18)
		text_at(p + Vector2(0, 24), "TREAD " + number(wheel.get("tread_c")) + "°", 20, tire_color(wheel.get("tread_c")))
		text_at(p + Vector2(0, 44), "I --  C --  O --", 15)
		text_at(p + Vector2(0, 64), "CAR " + number(wheel.get("carcass_c")) + "°  GAS " + number(wheel.get("gas_c")) + "°", 15)
		var wear: Variant = wheel.get("wear_fraction")
		text_at(p + Vector2(0, 84), "BRK " + number(wheel.get("brake_disc_c")) + "°  LIFE " + (number((1.0 - float(wear)) * 100.0) if wear != null else "--") + "%", 15)
	var aids: Dictionary = snapshot.get("aids", {})
	var available: Dictionary = snapshot.get("aids_available", {})
	var aid_text := "AUTO " + ("ON" if bool(aids.get("automatic_transmission", false)) else "OFF")
	for key in ["anti_lock_brakes", "traction_control", "stability"]:
		aid_text += "  |  " + {"anti_lock_brakes": "ABS", "traction_control": "TCS", "stability": "ESP"}[key] + " " + (("ON" if bool(aids.get(key, false)) else "OFF") if bool(available.get(key, false)) else "--")
	text_at(Vector2(size.x / maxf(factor, 0.01) * 0.5 - 180.0, size.y / maxf(factor, 0.01) - 158.0), aid_text, 16)
	var course: Dictionary = snapshot.get("course", {})
	draw_style_box(_panel(), Rect2(Vector2(14, 10), Vector2(261, 153)))
	text_at(Vector2(28, 37), "STAGE TIMING" if not course.is_empty() else "SESSION", 22, Color.WHITE, true)
	text_at(Vector2(28, 70), time_text(course.get("current_s", snapshot.get("time_s"))), 26)
	text_at(Vector2(28, 98), "LAST   " + time_text(course.get("last_s")), 20)
	text_at(Vector2(28, 128), "BEST   " + time_text(course.get("best_s")), 20, Color("#a6ff9e"))
	if not course.is_empty():
		draw_course(course)
	draw_set_transform(Vector2.ZERO)

func text_at(point: Vector2, value: String, pixels: int, color: Color = Color(0.88, 0.9, 0.92), bold: bool = false) -> void:
	draw_string(BOLD if bold else FONT, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, color)

func number(value: Variant) -> String:
	return str(roundi(float(value))) if value != null and is_finite(float(value)) else "--"

func tire_color(value: Variant) -> Color:
	if value == null:
		return Color.GRAY
	var optimum := float(thermal_config.get("optimal_tread_temperature_c", 50.0))
	if float(value) < optimum - float(thermal_config.get("optimal_tread_window_c", 50.0)) * 0.5:
		return Color(0.35, 0.7, 1.0)
	if float(value) > float(thermal_config.get("overheat_tread_temperature_c", 100.0)):
		return Color(1.0, 0.25, 0.15)
	return Color(0.4, 1.0, 0.5)

func _panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1e2429f2")
	style.border_color = Color("#607e91")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
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
	var origin := Vector2(28, 207) + (Vector2(215, 238) - extent * factor) * 0.5
	draw_style_box(_panel(), Rect2(Vector2(14, 179), Vector2(243, 288)))
	text_at(Vector2(28, 202), "RUSSIA STAGE 1", 18, Color.WHITE, true)
	var line := PackedVector2Array()
	for point: Vector3 in points:
		line.append(origin + (Vector2(point.x, point.z) - minimum) * factor)
	draw_polyline(line, Color("#607e91"), 3.0, true)
	draw_circle(line[0], 4.0, Color("#8fd36b"))
	draw_circle(line[-1], 4.0, Color("#f0182d"))
	var position: Vector3 = course.get("position", Vector3.ZERO)
	draw_circle(origin + (Vector2(position.x, position.z) - minimum) * factor, 5.0, Color("#73b8ff"))
