class_name GarageStageTab
extends Control
## Real Control tree for Garage Tab 0 (Stage Briefing: 5-sector route preview, weather strip, terrain bars, altitude chart).

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _Presenter := preload("res://scripts/ui/services/garage_setup_presenter.gd")
const _RoutePreviewScript := preload("res://ui/organisms/ui_route_preview.gd")
const _ChartScript := preload("res://ui/organisms/ui_telemetry_chart.gd")
const _MeterScript := preload("res://ui/atoms/ui_progress_meter.gd")

var _chip_dist_val: Label
var _chip_weather_val: Label
var _chip_temp_val: Label
var _route_preview: Control
var _sectors_hbox: HBoxContainer
var _terrain_vbox: VBoxContainer
var _altitude_chart: Control
var _initialized: bool = false


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _initialized:
		return
	_initialized = true
	size = Vector2(1280.0, 800.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var r := _Tokens.get_radius("default")
	var c_card := _Tokens.get_color("bg_card")
	var c_well := _Tokens.get_color("bg_well")
	var c_subtle := _Tokens.get_color("border_subtle")

	# Left group: Route & Weather (36, 156, 636, 518)
	var left_panel := _make_group(Rect2(36, 156, 636, 518), "TRAZADO Y METEOROLOGÍA", c_card, c_subtle, r)
	add_child(left_panel)
	var l_vbox := left_panel.get_meta("body") as VBoxContainer

	var chips_row := HBoxContainer.new()
	chips_row.add_theme_constant_override("separation", 8)
	chips_row.custom_minimum_size = Vector2(0, 44)
	l_vbox.add_child(chips_row)
	_chip_dist_val = _add_chip(chips_row, "DISTANCIA", c_well, c_subtle, r)
	_chip_weather_val = _add_chip(chips_row, "CLIMA", c_well, c_subtle, r)
	_chip_temp_val = _add_chip(chips_row, "AIRE / PISTA", c_well, c_subtle, r)

	var map_wrap := PanelContainer.new()
	map_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_wrap.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_well, c_subtle, 1, r, 6, 6))
	l_vbox.add_child(map_wrap)
	_route_preview = _RoutePreviewScript.new()
	_route_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_route_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_wrap.add_child(_route_preview)

	_sectors_hbox = HBoxContainer.new()
	_sectors_hbox.add_theme_constant_override("separation", 8)
	_sectors_hbox.custom_minimum_size = Vector2(0, 102)
	l_vbox.add_child(_sectors_hbox)

	# Right top: Terrain Composition (684, 156, 560, 256)
	var terrain_panel := _make_group(Rect2(684, 156, 560, 256), "COMPOSICIÓN DEL TERRENO", c_card, c_subtle, r)
	add_child(terrain_panel)
	_terrain_vbox = terrain_panel.get_meta("body") as VBoxContainer

	# Right bottom: Altitude Profile (684, 424, 560, 250)
	var alt_panel := _make_group(Rect2(684, 424, 560, 250), "PERFIL DE ALTITUD", c_card, c_subtle, r)
	add_child(alt_panel)
	var alt_body := alt_panel.get_meta("body") as VBoxContainer
	_altitude_chart = _ChartScript.new()
	_altitude_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_altitude_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	alt_body.add_child(_altitude_chart)


func populate(data: Dictionary) -> void:
	_ensure_nodes()
	var sectors: Array = data.get("sectors", [])
	var terrain: Dictionary = data.get("terrain", {})
	var route_pts: PackedVector2Array = data.get("route_points", PackedVector2Array())
	var altitudes: PackedFloat32Array = data.get("altitudes", PackedFloat32Array())
	var dist_text := str(data.get("distance_text", "5.0 KM"))
	var weather_text := str(data.get("weather_text", "SOLEADO"))
	var total_km := maxf(float(data.get("length_m", 5000.0)) / 1000.0, 0.1)

	var air_sum := 0.0
	var gnd_sum := 0.0
	for s in sectors:
		air_sum += float((s as Dictionary).get("air_c", 15.0))
		gnd_sum += float((s as Dictionary).get("ground_c", 15.0))
	var n_sec := float(maxi(sectors.size(), 1))

	_chip_dist_val.text = dist_text
	_chip_weather_val.text = weather_text
	_chip_weather_val.add_theme_color_override("font_color", _Tokens.get_color("accent_rally"))
	_chip_temp_val.text = "%d° / %d°C" % [roundi(air_sum / n_sec), roundi(gnd_sum / n_sec)]

	var gold := _Tokens.get_color("accent_rally")
	var sector_colors: Array[Color] = []
	for si in mini(5, sectors.size()):
		var b := _Presenter.sector_weather_badge(sectors[si] as Dictionary, gold)
		sector_colors.append(b["color"] as Color)
	_route_preview.set_route(route_pts, 1.0, sector_colors, altitudes)

	# Rebuild S1..S5 cards
	for child in _sectors_hbox.get_children():
		child.queue_free()
	var r := _Tokens.get_radius("default")
	var c_well := _Tokens.get_color("bg_well")
	var c_subtle := _Tokens.get_color("border_subtle")
	for si in mini(5, sectors.size()):
		var sd: Dictionary = sectors[si]
		var badge := _Presenter.sector_weather_badge(sd, gold)
		var col: Color = badge["color"]
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_well, c_subtle, 1, r, 6, 6))
		_sectors_hbox.add_child(card)
		var cv := VBoxContainer.new()
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.add_theme_constant_override("separation", 4)
		card.add_child(cv)
		var top_bar := ColorRect.new()
		top_bar.custom_minimum_size = Vector2(0, 3)
		top_bar.color = col
		cv.add_child(top_bar)
		var s_lbl := Label.new()
		s_lbl.text = "S%d" % (si + 1)
		s_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_Theme.apply_label(s_lbl, "primary", 14, false, true)
		cv.add_child(s_lbl)
		var pill := PanelContainer.new()
		pill.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(Color(col, 0.16), Color(col, 0.70), 1, r, 4, 2))
		cv.add_child(pill)
		var p_lbl := Label.new()
		p_lbl.text = str(badge["label"])
		p_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_Theme.apply_label(p_lbl, "white", 10, false, true)
		p_lbl.add_theme_color_override("font_color", col)
		pill.add_child(p_lbl)
		var t_lbl := Label.new()
		t_lbl.text = "%d °C" % roundi(float(sd.get("air_c", 15.0)))
		t_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_Theme.apply_label(t_lbl, "primary", 12, true, true)
		cv.add_child(t_lbl)

	# Terrain bars
	for child in _terrain_vbox.get_children():
		child.queue_free()
	var bars := _Presenter.build_terrain_bars(terrain, sectors, gold)
	for b in bars:
		var pct := int(b["pct"])
		var meter := _MeterScript.new()
		meter.set_meter(str(b["label"]), float(pct) / 100.0, "%d%%" % pct, false)
		meter.set_fill_color(b["color"] as Color)
		_terrain_vbox.add_child(meter)

	# Altitude chart
	var series: Array[Dictionary] = []
	if altitudes.size() >= 2:
		var pts := PackedVector2Array()
		var min_h := INF
		var max_h := -INF
		for h in altitudes:
			min_h = minf(min_h, h)
			max_h = maxf(max_h, h)
		var n_pts := mini(64, altitudes.size())
		for i in n_pts:
			var t := float(i) / float(n_pts - 1)
			var idx := clampi(roundi(t * float(altitudes.size() - 1)), 0, altitudes.size() - 1)
			pts.append(Vector2(t * total_km, altitudes[idx] - min_h + 1.0))
		series.append({"points": pts, "color": gold})
		_altitude_chart.set_multi_series(series, "ALTITUD: %d m — %d m (Δ%d m)" % [roundi(min_h), roundi(max_h), roundi(max_h - min_h)], "km", "m")
	else:
		_altitude_chart.set_multi_series([], "SIN PERFIL DE ALTITUD", "km", "m")


func _make_group(rect: Rect2, caption: String, bg: Color, border: Color, radius: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(bg, border, 1, radius, 14, 10))
	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 6)
	p.add_child(root_v)
	var lbl := Label.new()
	lbl.text = caption
	_Theme.apply_label(lbl, "primary", 14, false, true)
	root_v.add_child(lbl)
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = border
	root_v.add_child(sep)
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root_v.add_child(body)
	p.set_meta("body", body)
	return p


func _add_chip(parent: HBoxContainer, title_txt: String, bg: Color, border: Color, radius: int) -> Label:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(bg, border, 1, radius, 10, 4))
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	p.add_child(v)
	var k := Label.new()
	k.text = title_txt
	_Theme.apply_label(k, "muted", 9, false, true)
	v.add_child(k)
	var val := Label.new()
	_Theme.apply_label(val, "primary", 12, true, true)
	v.add_child(val)
	return val
