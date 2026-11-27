class_name UITelemetryChart
extends Control
## Unified 2D scientific telemetry chart supporting tire force curves (baseline vs pending),
## powertrain gear-speed curves, and horizontal balance meters.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")

enum Mode { TIRE_CURVE, MULTI_LINE, BALANCE_METER }

var mode: Mode = Mode.TIRE_CURVE
# Exposed fields preserving RallyTireTunerPanel.CurvePlot contract (_current, _baseline).
var _current := PackedVector2Array()
var _baseline := PackedVector2Array()
var _lateral := true
var _summary := ""
var _condition := ""

var _named_series: Array[Dictionary] = []
var _x_label: String = ""
var _y_label: String = ""
var _balance_title: String = ""
var _balance_left: String = ""
var _balance_right: String = ""
var _balance_frac: float = 0.5


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(220, 114)


func set_samples(
	current: PackedVector2Array,
	baseline: PackedVector2Array,
	lateral: bool,
	load_n: float,
	pressure: float,
	exponent: float,
	loss: float
) -> void:
	mode = Mode.TIRE_CURVE
	_current = current
	_baseline = baseline
	_lateral = lateral
	if not current.is_empty():
		var peak := current[0]
		for sample in current:
			if sample.y > peak.y:
				peak = sample
		var unit := "°" if lateral else "%"
		var boundary := " · límite del barrido" if peak == current[-1] else ""
		var slope := (current[1].y - current[0].y) / maxf(current[1].x, 0.0001) if current.size() > 1 else 0.0
		_summary = "Máx. %.2f kN a %.1f %s%s · pendiente %.0f N/%s" % [peak.y * 0.001, peak.x, unit, boundary, slope, unit]
	tooltip_text = "Barrido con carga y presión fijas. Cada punto se mide tras 1 s en seco con la banda en su ventana de agarre."
	if not baseline.is_empty():
		tooltip_text += "\nGris: valores activos. Naranja: valores pendientes."
	_condition = "%.0f N · %.0f kPa · 72 km/h · k %.3f · μ −%.1f%% a 2× carga" % [load_n, pressure, exponent, loss]
	queue_redraw()


func set_multi_series(series_list: Array[Dictionary], summary_text: String = "", x_unit: String = "km/h", y_unit: String = "RPM") -> void:
	mode = Mode.MULTI_LINE
	_named_series = series_list
	_summary = summary_text
	_x_label = x_unit
	_y_label = y_unit
	queue_redraw()


func set_balance_meter(title_text: String, left_label: String, right_label: String, fraction: float) -> void:
	mode = Mode.BALANCE_METER
	_balance_title = title_text
	_balance_left = left_label
	_balance_right = right_label
	_balance_frac = clampf(fraction, 0.0, 1.0)
	custom_minimum_size = Vector2(180, 44)
	queue_redraw()


func _draw() -> void:
	var font := _Tokens.get_font("data")
	if font == null:
		font = get_theme_default_font()
	var bg := _Tokens.get_flat_stylebox(_Tokens.get_color("bg_well"), _Tokens.get_color("border_subtle"), 1, _Tokens.get_radius("technical"))
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	match mode:
		Mode.TIRE_CURVE:
			_draw_tire_curve(font)
		Mode.MULTI_LINE:
			_draw_multi_series(font)
		Mode.BALANCE_METER:
			_draw_balance(font)


func _draw_tire_curve(font: Font) -> void:
	var muted := _Tokens.get_color("text_muted")
	var rect := Rect2(Vector2(45.0, 22.0), Vector2(maxf(size.x - 60.0, 1.0), maxf(size.y - 59.0, 20.0)))
	if _current.is_empty():
		return
	var x_max := maxf(_current[-1].x, 0.001)
	var y_max := 1000.0
	var y_min := 0.0
	for series in [_current, _baseline]:
		for p: Vector2 in series:
			y_max = maxf(y_max, p.y)
			y_min = minf(y_min, p.y)
	y_max = ceilf(y_max / 1000.0) * 1000.0
	y_min = floorf(y_min / 1000.0) * 1000.0
	var axis_y := rect.end.y + 14.0
	draw_string(font, Vector2(4.0, axis_y), "kN", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, muted)
	for fraction in [0.0, 0.5, 1.0]:
		var y := rect.end.y - float(fraction) * rect.size.y
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), _Tokens.get_color("border_subtle"))
		draw_string(font, Vector2(4.0, y + 4.0), "%.1f" % (lerpf(y_min, y_max, fraction) * 0.001), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, muted)
	_draw_series(_baseline, rect, x_max, y_min, y_max, muted)
	_draw_series(_current, rect, x_max, y_min, y_max, _Tokens.get_color("accent_rally"))
	draw_string(font, Vector2(8.0, 15.0), _summary, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, 11, _Tokens.get_color("text_white"))
	draw_string(font, Vector2(rect.position.x, axis_y), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, muted)
	var axes := "%.0f%s" % [x_max, "°" if _lateral else "%"]
	draw_string(font, Vector2(rect.end.x - 40.0, axis_y), axes, HORIZONTAL_ALIGNMENT_RIGHT, 40.0, 10, muted)
	draw_string(font, Vector2(8.0, size.y - 8.0), _condition, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, 10, muted)


func _draw_multi_series(font: Font) -> void:
	var muted := _Tokens.get_color("text_muted")
	var rect := Rect2(Vector2(42.0, 22.0), Vector2(maxf(size.x - 56.0, 1.0), maxf(size.y - 42.0, 20.0)))
	if not _summary.is_empty():
		draw_string(font, Vector2(8.0, 15.0), _summary, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, 11, _Tokens.get_color("text_white"))
	if _named_series.is_empty():
		return
	var x_max := 1.0
	var y_max := 1.0
	for s in _named_series:
		var pts: PackedVector2Array = s.get("points", PackedVector2Array())
		for p in pts:
			x_max = maxf(x_max, p.x)
			y_max = maxf(y_max, p.y)
	for frac in [0.0, 0.5, 1.0]:
		var y := rect.end.y - float(frac) * rect.size.y
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), _Tokens.get_color("border_subtle"))
	for s in _named_series:
		var pts: PackedVector2Array = s.get("points", PackedVector2Array())
		var col: Color = s.get("color", _Tokens.get_color("accent_rally"))
		_draw_series(pts, rect, x_max, 0.0, y_max, col)
	draw_string(font, Vector2(rect.end.x - 64.0, rect.end.y + 13.0), "%.0f %s" % [x_max, _x_label], HORIZONTAL_ALIGNMENT_RIGHT, 64.0, 10, muted)
	draw_string(font, Vector2(4.0, rect.position.y + 8.0), _y_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, muted)


func _draw_balance(font: Font) -> void:
	var muted := _Tokens.get_color("text_muted")
	var white := _Tokens.get_color("text_white")
	var accent := _Tokens.get_color("accent_rally")
	draw_string(font, Vector2(10.0, 15.0), _balance_title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20.0, 11, white)
	var bar := Rect2(10.0, 22.0, maxf(size.x - 20.0, 20.0), 8.0)
	draw_rect(bar, _Tokens.get_color("bg_card"), true)
	var cx := bar.position.x + bar.size.x * 0.5
	var mx := bar.position.x + bar.size.x * _balance_frac
	draw_line(Vector2(cx, bar.position.y - 2.0), Vector2(cx, bar.end.y + 2.0), _Tokens.get_color("border_hover"), 1.0)
	draw_rect(Rect2(minf(cx, mx), bar.position.y + 1.0, absf(mx - cx), bar.size.y - 2.0), accent, true)
	draw_circle(Vector2(mx, bar.position.y + bar.size.y * 0.5), 4.0, white)
	draw_string(font, Vector2(10.0, size.y - 4.0), _balance_left, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.48, 10, muted)
	draw_string(font, Vector2(size.x * 0.5, size.y - 4.0), _balance_right, HORIZONTAL_ALIGNMENT_RIGHT, size.x * 0.48 - 10.0, 10, muted)


func _draw_series(series: PackedVector2Array, rect: Rect2, x_max: float, y_min: float, y_max: float, color: Color) -> void:
	if series.size() < 2:
		return
	var span_y := maxf(y_max - y_min, 0.0001)
	var points := PackedVector2Array()
	points.resize(series.size())
	for i in series.size():
		var p := series[i]
		points[i] = Vector2(
			rect.position.x + rect.size.x * (p.x / x_max),
			rect.end.y - rect.size.y * ((p.y - y_min) / span_y)
		)
	draw_polyline(points, color, 2.0, true)
