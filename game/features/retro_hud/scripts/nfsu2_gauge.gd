class_name Nfsu2Gauge
extends Control

## Pure vector/procedural NFSU2-inspired circular tachometer + digital speed & gear gauge.
## Dynamically scales its ticks, dial numbers (0..N), optimal shift band, and redline arc
## across the full 225 deg sweep based on the active vehicle's RPM envelope.

const Cmr2Style := preload("res://scripts/rally/cmr2_hud_style.gd")

const DESIGN_SIZE := Vector2(256.0, 256.0)
const DIAL_CENTER := Vector2(127.5, 128.0)
const DIAL_RADIUS := 114.6
const TRACK_INNER_RADIUS := 99.0
const TRACK_OUTER_RADIUS := 113.8
const NUMBER_RADIUS := 80.5
const ANGLE_AT_ZERO_DEG: float = 180.0
const ANGLE_AT_MAX_DEG: float = 405.0
const TRACK_PAD_DEG: float = 4.0

@export_range(0.0, 30.0, 0.1) var needle_smoothing: float = 14.0
@export var show_mph: bool = false
## Posición del indicador de marcha dentro del recorte superior derecho (256x256).
@export var gear_position: Vector2 = Vector2(160.0, 96.0)
## Inclinación cursiva aplicada a los glifos de la marcha.
@export_range(0.0, 0.5, 0.01) var gear_italic_slant: float = 0.0

var _rpm: float = 0.0
var _speed_kmh: float = 0.0
var _gear_text: String = "N"
var _vehicle_max_rpm: float = 7300.0
var _dial_max_rpm: float = 8000.0
var _ideal_shift_rpm: float = 6205.0
var _urgent_shift_rpm: float = 6716.0
var _display_angle_deg: float = ANGLE_AT_ZERO_DEG

var _needle_layer: Control
var _hub_layer: Control
var _speed_label: Label
var _unit_label: Label
var _gear_label: Label
var _shift_state: int = 0 # 0 = normal, 1 = ideal shift, 2 = urgent/redline


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = DESIGN_SIZE
	size = DESIGN_SIZE

	# Ventana superior derecha: marcha alineada sobre el separador horizontal (y=129)
	_gear_label = _add_label("Gear", gear_position, Vector2(66.0, 32.0), 28)
	if gear_italic_slant > 0.001:
		var gear_font := FontVariation.new()
		gear_font.base_font = Cmr2Style.FONT_BOLD
		gear_font.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(gear_italic_slant, 1.0), Vector2.ZERO)
		_gear_label.add_theme_font_override("font", gear_font)
	else:
		_gear_label.add_theme_font_override("font", Cmr2Style.FONT_BOLD)

	# Ventana inferior derecha: velocidad y unidad con tipografía unificada D-DIN
	_speed_label = _add_label("Speed", Vector2(154.0, 134.0), Vector2(74.0, 38.0), 34)
	_speed_label.add_theme_font_override("font", Cmr2Style.FONT_BOLD)

	_unit_label = _add_label("Units", Vector2(158.0, 169.0), Vector2(66.0, 16.0), 11)
	_unit_label.add_theme_font_override("font", Cmr2Style.FONT_BOLD)
	_unit_label.add_theme_color_override("font_color", Cmr2Style.TACHO_SILVER)

	_needle_layer = Control.new()
	_needle_layer.name = "NeedleLayer"
	_needle_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_needle_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_needle_layer.draw.connect(_draw_needle)
	add_child(_needle_layer)

	_hub_layer = Control.new()
	_hub_layer.name = "HubLayer"
	_hub_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hub_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hub_layer.draw.connect(_draw_hub)
	add_child(_hub_layer)

	_dial_max_rpm = _compute_dial_max_rpm(_vehicle_max_rpm)
	_display_angle_deg = _rpm_to_degrees(_rpm)
	_refresh_visuals()
	queue_redraw()


func _add_label(node_name: String, pos: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = pos
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Cmr2Style.TEXT_WHITE)
	label.add_theme_color_override("font_shadow_color", Cmr2Style.TEXT_SHADOW)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


## rpm = revoluciones reales por minuto, speed_kmh = módulo velocidad km/h,
## gear = -1 reversa, 0 neutro, 1..N marchas hacia adelante.
func set_telemetry(rpm: float, speed_kmh: float, gear: int) -> void:
	var label := "R" if gear < 0 else ("N" if gear == 0 else str(gear))
	set_telemetry_label(rpm, speed_kmh, label)


func set_telemetry_label(rpm: float, speed_kmh: float, gear_label: String) -> void:
	_rpm = clampf(rpm, 0.0, _dial_max_rpm)
	_speed_kmh = maxf(0.0, absf(speed_kmh))
	_gear_text = gear_label if not gear_label.is_empty() else "N"
	if needle_smoothing <= 0.0:
		_display_angle_deg = _rpm_to_degrees(_rpm)
		if _needle_layer != null:
			_needle_layer.queue_redraw()
	if is_node_ready():
		_refresh_visuals()


func set_rpm_thresholds(vehicle_max_rpm: float, ideal_shift_rpm: float, urgent_shift_rpm: float) -> void:
	if is_finite(vehicle_max_rpm) and vehicle_max_rpm > 0.0:
		_vehicle_max_rpm = vehicle_max_rpm
		_dial_max_rpm = _compute_dial_max_rpm(_vehicle_max_rpm)
	if is_finite(urgent_shift_rpm) and urgent_shift_rpm > 0.0:
		_urgent_shift_rpm = minf(urgent_shift_rpm, _dial_max_rpm)
	if is_finite(ideal_shift_rpm) and ideal_shift_rpm > 0.0:
		_ideal_shift_rpm = minf(ideal_shift_rpm, _urgent_shift_rpm)
	_rpm = clampf(_rpm, 0.0, _dial_max_rpm)
	if needle_smoothing <= 0.0:
		_display_angle_deg = _rpm_to_degrees(_rpm)
	if is_node_ready():
		_refresh_visuals()
		queue_redraw()
		if _needle_layer != null:
			_needle_layer.queue_redraw()
		if _hub_layer != null:
			_hub_layer.queue_redraw()


func _compute_dial_max_rpm(max_rpm: float) -> float:
	var safe_max := maxf(max_rpm, 3000.0)
	var thousands := maxi(3, int(ceilf(safe_max / 1000.0)))
	return float(thousands) * 1000.0


func _process(delta: float) -> void:
	var desired := _rpm_to_degrees(_rpm)
	if needle_smoothing <= 0.0:
		if not is_equal_approx(_display_angle_deg, desired):
			_display_angle_deg = desired
			if _needle_layer != null:
				_needle_layer.queue_redraw()
	else:
		var next_angle := lerpf(_display_angle_deg, desired, 1.0 - exp(-needle_smoothing * delta))
		if absf(next_angle - _display_angle_deg) > 0.01:
			_display_angle_deg = next_angle
			if _needle_layer != null:
				_needle_layer.queue_redraw()


func _dir_from_deg(compass_deg: float) -> Vector2:
	var rad := deg_to_rad(compass_deg)
	return Vector2(sin(rad), -cos(rad))


func _draw_annular_sector(
	center: Vector2,
	r_inner: float,
	r_outer: float,
	start_deg: float,
	end_deg: float,
	color: Color,
	segments: int = 32
) -> void:
	if end_deg <= start_deg + 0.05:
		return
	var steps := maxi(2, segments)
	var pts := PackedVector2Array()
	pts.resize((steps + 1) * 2)
	for i in steps + 1:
		var t := float(i) / float(steps)
		var dir := _dir_from_deg(lerpf(start_deg, end_deg, t))
		pts[i] = center + dir * r_outer
		pts[(steps * 2 + 1) - i] = center + dir * r_inner
	draw_colored_polygon(pts, color)


func _draw() -> void:
	# 1. Sombra exterior y disco base gris carbón traslúcido
	draw_circle(DIAL_CENTER + Vector2(0.0, 2.5), DIAL_RADIUS + 2.5, Color(0.0, 0.0, 0.0, 0.34))
	draw_circle(DIAL_CENTER, DIAL_RADIUS, Cmr2Style.TACHO_PANEL_BG)

	# Gradiente radial suave hacia el interior para dar profundidad sin textura raster
	draw_circle(DIAL_CENTER, DIAL_RADIUS * 0.78, Color(0.05, 0.06, 0.08, 0.16))
	draw_circle(DIAL_CENTER, DIAL_RADIUS * 0.50, Color(0.03, 0.04, 0.05, 0.22))

	# Anillos concéntricos interiores siguiendo el barrido útil
	_draw_annular_sector(DIAL_CENTER, 44.0, 52.0, ANGLE_AT_ZERO_DEG, ANGLE_AT_MAX_DEG, Color(0.03, 0.04, 0.05, 0.28), 36)
	_draw_annular_sector(DIAL_CENTER, 25.0, 34.0, ANGLE_AT_ZERO_DEG, ANGLE_AT_MAX_DEG, Color(0.03, 0.04, 0.05, 0.34), 32)

	# 2. Pista exterior de marcas, rango óptimo y redline dinámico
	var track_start := ANGLE_AT_ZERO_DEG - TRACK_PAD_DEG
	var track_end := ANGLE_AT_MAX_DEG + TRACK_PAD_DEG
	var ideal_deg := _rpm_to_degrees(_ideal_shift_rpm)
	var urgent_deg := _rpm_to_degrees(_urgent_shift_rpm)
	var max_deg := _rpm_to_degrees(_vehicle_max_rpm)

	_draw_annular_sector(DIAL_CENTER, TRACK_INNER_RADIUS, TRACK_OUTER_RADIUS, track_start, track_end, Color(0.04, 0.05, 0.07, 0.52), 56)

	# Zona óptima de cambio (ámbar/dorado) continua hasta el bisel exterior sin franja divisoria
	if urgent_deg > ideal_deg + 0.5:
		_draw_annular_sector(
			DIAL_CENTER,
			TRACK_INNER_RADIUS + 0.6,
			TRACK_OUTER_RADIUS,
			ideal_deg,
			urgent_deg,
			Color(Cmr2Style.AMBER_ACCENT.r, Cmr2Style.AMBER_ACCENT.g, Cmr2Style.AMBER_ACCENT.b, 0.88),
			14
		)

	# Redline dinámico continuo hasta el bisel exterior (con corte visible en vehicle_max)
	if track_end > urgent_deg + 0.5:
		var solid_end := maxf(urgent_deg, max_deg)
		_draw_annular_sector(
			DIAL_CENTER,
			TRACK_INNER_RADIUS + 0.6,
			TRACK_OUTER_RADIUS,
			urgent_deg,
			minf(solid_end, track_end),
			Color(Cmr2Style.TACHO_RED.r, Cmr2Style.TACHO_RED.g, Cmr2Style.TACHO_RED.b, 0.94),
			16
		)
		if track_end > solid_end + 0.5:
			_draw_annular_sector(
				DIAL_CENTER,
				TRACK_INNER_RADIUS + 0.6,
				TRACK_OUTER_RADIUS,
				solid_end,
				track_end,
				Color(Cmr2Style.TACHO_RED.r * 0.72, Cmr2Style.TACHO_RED.g * 0.72, Cmr2Style.TACHO_RED.b * 0.72, 0.88),
				12
			)

	# 3. Ventana derecha recortada (marcha arriba, velocidad y unidad abajo)
	_draw_readout_cutout()

	# 4. Ticks mayores, ticks intermedios y números dinámicos 0..N repartidos en 225°
	_draw_scale_markings(ideal_deg, urgent_deg, max_deg)

	# 5. Bisel exterior limpio envolviendo el dial sin partir la pista superior
	draw_arc(DIAL_CENTER, DIAL_RADIUS, 0.0, TAU, 80, Cmr2Style.TACHO_BORDER, 1.4, true)


func _draw_readout_cutout() -> void:
	var r_clip := TRACK_OUTER_RADIUS - 0.5
	var top_y := 92.0
	var top_arc_deg := 90.0 - rad_to_deg(asin((DIAL_CENTER.y - top_y) / r_clip))
	var bottom_arc_deg := 154.0

	var pts := PackedVector2Array()
	pts.append(Vector2(154.0, top_y))
	var arc_steps := 18
	for i in arc_steps + 1:
		var t := float(i) / float(arc_steps)
		pts.append(DIAL_CENTER + _dir_from_deg(lerpf(top_arc_deg, bottom_arc_deg, t)) * r_clip)
	pts.append(Vector2(142.0, 170.0))
	pts.append(Vector2(117.0, 170.0))
	pts.append(Vector2(136.0, 129.0))
	pts.append(Vector2(149.0, 100.0))

	draw_colored_polygon(pts, Color(0.03, 0.04, 0.05, 0.72))

	# Borde interior limpio de la muesca y divisor horizontal entre marcha y velocidad
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		draw_line(a, b, Color(0.76, 0.79, 0.83, 0.16), 1.0, true)

	draw_line(
		Vector2(136.0, 129.0),
		Vector2(DIAL_CENTER.x + r_clip - 1.0, 129.0),
		Cmr2Style.TACHO_BORDER,
		1.4,
		true
	)


func _draw_scale_markings(ideal_deg: float, urgent_deg: float, max_deg: float) -> void:
	var step_count := maxi(3, int(round(_dial_max_rpm / 1000.0)))
	var number_font_size := 16 if step_count >= 10 else 18

	# Sub-marcas cada 500 RPM
	for i in step_count:
		var mid_rpm := (float(i) + 0.5) * 1000.0
		var mid_deg := _rpm_to_degrees(mid_rpm)
		var dir := _dir_from_deg(mid_deg)
		var p_in := DIAL_CENTER + dir * 105.0
		var p_out := DIAL_CENTER + dir * (TRACK_OUTER_RADIUS - 0.4)
		var minor_col := Cmr2Style.TEXT_WHITE if mid_rpm >= _urgent_shift_rpm else Cmr2Style.TACHO_SILVER
		draw_line(p_in + Vector2(1.0, 1.0), p_out + Vector2(1.0, 1.0), Color(0.0, 0.0, 0.0, 0.55), 1.6, true)
		draw_line(p_in, p_out, minor_col, 1.4, true)

	# Marcas mayores cada 1000 RPM y números 0..N
	for k in step_count + 1:
		var milestone_rpm := float(k) * 1000.0
		var deg := _rpm_to_degrees(milestone_rpm)
		var dir := _dir_from_deg(deg)
		var p_in := DIAL_CENTER + dir * 96.5
		var p_out := DIAL_CENTER + dir * (TRACK_OUTER_RADIUS - 0.2)

		draw_line(p_in + Vector2(1.0, 1.0), p_out + Vector2(1.0, 1.0), Color(0.0, 0.0, 0.0, 0.65), 2.8, true)
		draw_line(p_in, p_out, Cmr2Style.TEXT_WHITE, 2.4, true)

		var num_str := str(k)
		var num_center := DIAL_CENTER + dir * NUMBER_RADIUS
		var str_size := Cmr2Style.FONT_BOLD.get_string_size(num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, number_font_size)
		var baseline_pos := Vector2(
			num_center.x - str_size.x * 0.5,
			num_center.y + str_size.y * 0.30
		)
		var num_col := Cmr2Style.TEXT_WHITE
		if deg >= urgent_deg - 0.5 and _urgent_shift_rpm < _dial_max_rpm:
			num_col = Color(1.0, 0.92, 0.90, 0.98)
		elif deg >= ideal_deg - 0.5 and milestone_rpm < _urgent_shift_rpm:
			num_col = Color(1.0, 0.94, 0.80, 0.98)

		draw_string(Cmr2Style.FONT_BOLD, baseline_pos + Vector2(1.2, 1.5), num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, number_font_size, Cmr2Style.TEXT_SHADOW)
		draw_string(Cmr2Style.FONT_BOLD, baseline_pos, num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, number_font_size, num_col)

	# Marca exacta de corte del motor si no coincide con un millar exacto
	if fmod(_vehicle_max_rpm, 1000.0) > 60.0 and _vehicle_max_rpm < _dial_max_rpm:
		var lim_dir := _dir_from_deg(max_deg)
		var lp_in := DIAL_CENTER + lim_dir * 95.0
		var lp_out := DIAL_CENTER + lim_dir * TRACK_OUTER_RADIUS
		draw_line(lp_in, lp_out, Cmr2Style.TEXT_WHITE, 1.6, true)


func _draw_needle() -> void:
	if _needle_layer == null:
		return
	var rad := deg_to_rad(_display_angle_deg)

	# Sombra proyectada en espacio de pantalla para conservar ángulo de iluminación consistente
	_needle_layer.draw_set_transform(DIAL_CENTER + Vector2(2.4, 3.0), rad, Vector2.ONE)
	var shadow_poly := PackedVector2Array([
		Vector2(-3.8, 6.0),
		Vector2(-2.5, -90.0),
		Vector2(0.0, -106.0),
		Vector2(2.5, -90.0),
		Vector2(3.8, 6.0),
	])
	_needle_layer.draw_colored_polygon(shadow_poly, Color(0.0, 0.0, 0.0, 0.48))

	# Acabado plateado cromado multifaceta (base acero + facetas cromo + destellos especulares)
	_needle_layer.draw_set_transform(DIAL_CENTER, rad, Vector2.ONE)
	var base_bezel := PackedVector2Array([
		Vector2(-4.0, 6.2),
		Vector2(-2.5, -90.0),
		Vector2(0.0, -106.0),
		Vector2(2.5, -90.0),
		Vector2(4.0, 6.2),
	])
	var left_chrome := PackedVector2Array([
		Vector2(-3.4, 5.8),
		Vector2(-2.05, -89.8),
		Vector2(0.0, -104.8),
		Vector2(0.0, 5.8),
	])
	var left_specular := PackedVector2Array([
		Vector2(-1.45, 5.8),
		Vector2(-0.85, -89.8),
		Vector2(0.0, -104.0),
		Vector2(0.0, 5.8),
	])
	var right_chrome := PackedVector2Array([
		Vector2(0.0, 5.8),
		Vector2(0.0, -104.8),
		Vector2(2.05, -89.8),
		Vector2(3.4, 5.8),
	])
	var right_rim_highlight := PackedVector2Array([
		Vector2(2.05, 5.8),
		Vector2(1.25, -89.8),
		Vector2(2.05, -89.8),
		Vector2(3.4, 5.8),
	])

	_needle_layer.draw_colored_polygon(base_bezel, Color(0.22, 0.25, 0.30, 1.0))
	_needle_layer.draw_colored_polygon(left_chrome, Color(0.84, 0.88, 0.93, 1.0))
	_needle_layer.draw_colored_polygon(left_specular, Color(0.98, 0.99, 1.0, 1.0))
	_needle_layer.draw_colored_polygon(right_chrome, Color(0.45, 0.50, 0.56, 1.0))
	_needle_layer.draw_colored_polygon(right_rim_highlight, Color(0.76, 0.80, 0.86, 0.95))
	_needle_layer.draw_line(Vector2(0.0, 5.5), Vector2(0.0, -104.5), Color(1.0, 1.0, 1.0, 0.92), 1.0, true)
	_needle_layer.draw_set_transform(Vector2.ZERO)


func _draw_hub() -> void:
	if _hub_layer == null:
		return
	var ring_color := Color(0.88, 0.91, 0.95, 1.0)
	if _shift_state == 2:
		ring_color = Cmr2Style.TACHO_RED
	elif _shift_state == 1:
		ring_color = Cmr2Style.AMBER_ACCENT
	_hub_layer.draw_circle(DIAL_CENTER, 10.6, Color(0.0, 0.0, 0.0, 0.50))
	_hub_layer.draw_circle(DIAL_CENTER, 8.8, Color(0.08, 0.09, 0.11, 1.0))
	_hub_layer.draw_arc(DIAL_CENTER, 6.8, 0.0, TAU, 28, Color(0.34, 0.38, 0.44, 0.85), 1.0, true)
	_hub_layer.draw_arc(DIAL_CENTER, 8.8, 0.0, TAU, 32, ring_color, 2.2, true)


func _rpm_to_degrees(rpm_val: float) -> float:
	var safe_max := maxf(_dial_max_rpm, 1000.0)
	return lerpf(ANGLE_AT_ZERO_DEG, ANGLE_AT_MAX_DEG, clampf(rpm_val, 0.0, safe_max) / safe_max)


func _refresh_visuals() -> void:
	var shown_speed: float = _speed_kmh * (0.621371 if show_mph else 1.0)
	_speed_label.text = str(roundi(shown_speed))
	_unit_label.text = "MPH" if show_mph else "KM/H"
	_gear_label.text = _gear_text

	var next_shift_state := 0
	if _rpm >= _urgent_shift_rpm:
		next_shift_state = 2
	elif _rpm >= _ideal_shift_rpm:
		next_shift_state = 1

	var gear_color := Cmr2Style.TEXT_WHITE
	if next_shift_state == 2:
		gear_color = Cmr2Style.TACHO_RED
	elif next_shift_state == 1:
		gear_color = Cmr2Style.AMBER_ACCENT
	_gear_label.add_theme_color_override("font_color", gear_color)

	if next_shift_state != _shift_state:
		_shift_state = next_shift_state
		if _needle_layer != null:
			_needle_layer.queue_redraw()
		if _hub_layer != null:
			_hub_layer.queue_redraw()
