extends Control

# Paneles de contexto de la HUD: mapa vertical, neumáticos 2×2 y tiempos.
# Sistema de diseño Motorsport Minimalista (Flat Precision):
# Fondos oscuros mate, bordes sutiles de 1 px al 8-12%, títulos en Montserrat
# y telemetría/tiempos en D-DIN / D-DIN-Bold.

# 2.2. Estandarización Tipográfica (Sin Serif)
const FONT := preload("res://fonts/montserrat/Montserrat-Regular.ttf")
const BOLD := preload("res://fonts/montserrat/Montserrat-Bold.ttf")
const DIN := preload("res://fonts/D-DIN.ttf")
const DIN_BOLD := preload("res://fonts/D-DIN-Bold.ttf")
const FONT_TITLE := preload("res://fonts/montserrat/Montserrat-Bold.ttf")

# 2.1. Paleta de Colores Funcional Unificada
const BG_BASE := Color("#0a0e14")         # Negro carbón mate
const BG_SURFACE := Color("#121820")      # Superficie de tarjetas y paneles
const BG_HOVER := Color("#1c2430")        # Interacción y hover
const BORDER_SUBTLE := Color(1.0, 1.0, 1.0, 0.08) # 1 px sutil sin biseles
const BORDER_FOCUS := Color("#ffffff")              # Blanco puro para foco
const TEXT_PRIMARY := Color("#f0f4f8")    # Blanco suave, contraste óptimo
const TEXT_MUTED := Color("#6b7a8d")      # Gris medio para etiquetas
const ACCENT_RALLY := Color("#e5a93c")    # Dorado histórico sobrio
const ACCENT_ALERT := Color("#f59e0b")    # Ámbar rally alertas
const STATUS_DANGER := Color("#ef4444")   # Daños graves, pinchazos
const STATUS_SUCCESS := Color("#22c55e")  # Tiempos récord, verde de salida

# Aliases de compatibilidad interna
const C_FACE := BG_SURFACE
const C_FACE_HI := BG_HOVER
const C_FACE_LO := Color("#0e141c")
const C_FIELD := BG_BASE
const C_HI := Color(1.0, 1.0, 1.0, 0.12)
const C_LIGHT := Color(1.0, 1.0, 1.0, 0.08)
const C_SHADOW := Color(1.0, 1.0, 1.0, 0.04)
const C_DARK := Color("#000000")
const C_TEXT := TEXT_PRIMARY
const C_DIM := TEXT_MUTED
const C_GOLD := ACCENT_RALLY
const C_ROSE := STATUS_DANGER
const C_GREEN := STATUS_SUCCESS
const C_BLUE := Color("#5fa8e0")
const C_BLUE_DEEP := Color("#1a3144")
const C_GLASS := BG_SURFACE
const C_RIM := BORDER_SUBTLE

const MAP_RECT := Rect2(24, 24, 264, 330)
const TIMING_RECT := Rect2(1620, 24, 276, 132)
const DAMAGE_RECT := Rect2(1620, 482, 276, 150)
const TIRES_W := 300.0
const TIRES_H := 160.0
const BAND_MARGIN := 24.0

var snapshot: Dictionary = {}
var thermal_config: Dictionary = {}
var palette: RetroHudConfig = RetroHudConfig.new()
var _cached_map_points_hash: int = 0
var _cached_map_splits_hash: int = 0
var _cached_map_body: Rect2 = Rect2()
var _cached_map_rotation: float = 0.0
var _cached_map_minimum: Vector2 = Vector2.ZERO
var _cached_map_fit: float = 1.0
var _cached_map_origin: Vector2 = Vector2.ZERO
var _cached_map_line: PackedVector2Array = PackedVector2Array()
var _cached_split_points: PackedVector2Array = PackedVector2Array()
var _cached_start_screen_pos: Vector2 = Vector2.ZERO
var _cached_finish_screen_pos: Vector2 = Vector2.ZERO


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

	_title(Rect2(body.position.x + 6, body.position.y + 2, 220, 14), "ESTADO DE DAÑOS", 9, C_BLUE)
	draw_rect(Rect2(body.position.x + 2, body.position.y + 18, body.size.x - 4, 1), C_SHADOW)

	var dmg: Dictionary = snapshot.get("damage", {})
	var eng_snap: Dictionary = snapshot.get("engine", {})
	var rad_ratio := clampf(float(dmg.get("radiator", eng_snap.get("radiator_damage", 0.0))), 0.0, 1.0)
	var eng_ratio := clampf(float(dmg.get("engine", eng_snap.get("engine_damage", 0.0))), 0.0, 1.0)

	var transmission_ratio := clampf(float(dmg.get("transmission", 0.0)), 0.0, 1.0)

	var rows := [
		{"label": "RADIADOR", "ratio": rad_ratio, "y": 24.0},
		{"label": "MOTOR", "ratio": eng_ratio, "y": 58.0},
		{"label": "TRANSMISIÓN", "ratio": transmission_ratio, "y": 92.0},
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

	_title(Rect2(body.position.x + 2, body.position.y, 220, 14), "TIEMPO DE ESPECIAL", 9, C_BLUE)
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
		var start_p: Vector3 = points[0]
		var end_p: Vector3 = points[-1]
		var points_hash := points.size() ^ (int(start_p.x * 100.0) << 3) ^ int(end_p.z * 100.0)
		var splits: Array = course.get("split_positions", [])
		var splits_hash := hash(splits)
		var map_changed := points_hash != _cached_map_points_hash or body != _cached_map_body
		if map_changed:
			_cached_map_points_hash = points_hash
			_cached_map_body = body
			_cached_map_rotation = map_rotation(points)
			var minimum := Vector2(INF, INF)
			var maximum := Vector2(-INF, -INF)
			for point: Vector3 in points:
				var flat := Vector2(point.x, point.z).rotated(_cached_map_rotation)
				minimum = minimum.min(flat)
				maximum = maximum.max(flat)
			var extent := maximum - minimum
			_cached_map_minimum = minimum
			_cached_map_fit = minf(
				(body.size.x - 32.0) / maxf(extent.x, 1.0), (body.size.y - 104.0) / maxf(extent.y, 1.0)
			)
			_cached_map_origin = (
				body.position
				+ Vector2(16, 14)
				+ (Vector2(body.size.x - 32.0, body.size.y - 104.0) - extent * _cached_map_fit) * 0.5
			)
			_cached_map_line.clear()
			for point: Vector3 in points:
				_cached_map_line.append(_cached_map_origin + (Vector2(point.x, point.z).rotated(_cached_map_rotation) - minimum) * _cached_map_fit)

			_cached_start_screen_pos = _cached_map_origin + (Vector2(start_p.x, start_p.z).rotated(_cached_map_rotation) - minimum) * _cached_map_fit
			_cached_finish_screen_pos = _cached_map_origin + (Vector2(end_p.x, end_p.z).rotated(_cached_map_rotation) - minimum) * _cached_map_fit

		if map_changed or splits_hash != _cached_map_splits_hash:
			_cached_map_splits_hash = splits_hash
			_cached_split_points.clear()
			for i in splits.size():
				var marker: Vector3 = splits[i]
				_cached_split_points.append(_cached_map_origin + (Vector2(marker.x, marker.z).rotated(_cached_map_rotation) - _cached_map_minimum) * _cached_map_fit)

		draw_polyline(_cached_map_line, Color(C_RIM, 0.35), 8.0, true)
		draw_polyline(_cached_map_line, C_TEXT, 2.5, true)
		var next_partial := int(course.get("next_partial", 1))
		for i in _cached_split_points.size():
			var passed := i < next_partial - 1
			draw_circle(
				_cached_split_points[i],
				3.5,
				palette.map_start_color if passed else C_TEXT
			)
		draw_circle(_cached_start_screen_pos, 4.5, palette.map_start_color)
		draw_circle(_cached_finish_screen_pos, 4.5, C_ROSE)
		var position: Vector3 = course.get("position", Vector3.ZERO)
		var player_pos := _cached_map_origin + (Vector2(position.x, position.z).rotated(_cached_map_rotation) - _cached_map_minimum) * _cached_map_fit
		draw_circle(player_pos, 6.0, palette.map_player_color)

	var label := str(course.get("label", ""))
	var strip := Rect2(body.position.x + 8, body.end.y - 68, body.size.x - 16, 60)
	draw_rect(strip, C_FACE)
	_bevel(strip, false, 1)
	_title(
		Rect2(strip.position.x + 8, strip.position.y, strip.size.x - 16, 24),
		label.to_upper(),
		11,
		C_TEXT,
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

		if float(wheel.get("alignment_collision_damage", 0.0)) > 0.005:
			_text(Rect2(x + 24, y + 4, 34, 14), "ALIN.", 8, C_ROSE, true)
		if float(wheel.get("rim_deformation", 0.0)) > 0.005:
			_text(Rect2(x + 117, y + 28, 20, 14), "ARO", 8, C_ROSE, true)
		var center := Vector2(x + 30, y + 42)
		var brake_value: Variant = wheel.get("brake_disc_c")
		var disc_color := brake_temp_color(brake_value)
		draw_circle(center, 14.0, Color(0, 0, 0, 0.30))
		draw_circle(center, 14.0, C_FIELD)
		draw_arc(center, 14.0, 0.0, TAU, 28, disc_color, 3.0, true)
		draw_arc(center, 7.5, 0.0, TAU, 20, Color(disc_color, 0.4), 2.0, true)
		_num(Rect2(x + 8, y + 56, 44, 14), number(brake_value) + "°", 12, disc_color, HORIZONTAL_ALIGNMENT_CENTER, 44)

		if float(wheel.get("brake_collision_loss", 0.0)) > 0.005:
			_text(Rect2(x + 7, y + 16, 48, 11), "FRENO", 9, C_ROSE, true)
		else:
			var brake_remaining := 1.0 - clampf(float(wheel.get("brake_wear_fraction", 0.0)), 0.0, 1.0)
			_text(Rect2(x + 7, y + 16, 48, 11), "F %d%%" % roundi(brake_remaining * 100.0), 9, C_ROSE if brake_remaining < 0.3 else C_DIM, true)
		var tire := Rect2(x + 62, y + 18, 54, 36)
		if float(wheel.get("leak_per_second", 0.0)) > 0.0:
			var warning := "PINCHADO" if float(wheel.get("pressure_loss_fraction", 0.0)) > 0.85 else "FUGA"
			if float(wheel.get("carcass_failure", 0.0)) >= 1.0:
				warning = "DESTAL."
			_text(Rect2(x + 62, y + 16, 68, 11), warning, 9, C_ROSE, true)
			tire.position.y += 9.0
			tire.size.y -= 9.0
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
	body.bg_color = Color(BG_SURFACE, 0.92)
	body.border_color = BORDER_SUBTLE
	body.set_border_width_all(1)
	body.set_corner_radius_all(2)
	draw_style_box(body, rect)


func _bevel(rect: Rect2, _raised: bool, _thick: int = 2) -> void:
	# Sistema Minimalista: Borde plano sutil de 1 px sin relieves 3D ni biseles
	draw_rect(rect, BORDER_SUBTLE, false, 1.0)


func _sunken(rect: Rect2) -> void:
	# Sistema Minimalista: Contorno plano sutil de 1 px sin efecto hundido
	draw_rect(rect, BORDER_SUBTLE, false, 1.0)


func _field(rect: Rect2, value: String, size_px: int, color: Color) -> void:
	draw_rect(rect, BG_BASE)
	draw_rect(rect, BORDER_SUBTLE, false, 1.0)
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
	var line_height := DIN_BOLD.get_height(size_px)
	var baseline := rect.position.y + (rect.size.y + line_height) * 0.5 - DIN_BOLD.get_descent(size_px)
	draw_string(DIN_BOLD, Vector2(round(rect.position.x), round(baseline)), value, align, width, size_px, color)


func _title(
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
	var line_height := FONT_TITLE.get_height(size_px)
	var baseline := rect.position.y + (rect.size.y + line_height) * 0.5 - FONT_TITLE.get_descent(size_px)
	draw_string(FONT_TITLE, Vector2(round(rect.position.x), round(baseline)), value, align, width, size_px, color)


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
