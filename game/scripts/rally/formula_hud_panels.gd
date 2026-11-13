extends Control

## Contextual CMR2-styled HUD panels:
## - Top-left: live 3-row split standings
## - Mid-left: minimalist vehicle damage readout
## - Top-right: segmented sector delta bar + 7-segment stage clock
## - Bottom-left: 2x2 tire/wheel/brake thermal grid + simplified fuel & engine block

const Cmr2Style := preload("res://scripts/rally/cmr2_hud_style.gd")

const DIN := preload("res://fonts/D-DIN.ttf")
const DIN_BOLD := preload("res://fonts/D-DIN-Bold.ttf")

const C_GREEN := Color("#22c55e")
const C_GOLD := Color("#e5a93c")
const C_ORANGE := Color("#f08c35")
const C_ROSE := Color("#ef4444")
const C_BLUE := Color("#5fa8e0")

const STANDINGS_ORIGIN := Vector2(88.0, 68.0)
const STANDINGS_ROW_SIZE := Vector2(500.0, 42.0)
const STANDINGS_ROW_GAP := 3.0

const DAMAGE_RECT := Rect2(88.0, 444.0, 226.0, 114.0)

const TIMING_MARGIN_RIGHT := 88.0
const TIMING_TOP := 86.0
const TIMING_WIDTH := 516.0
const SPLIT_BAR_HEIGHT := 38.0
const CLOCK_PANEL_HEIGHT := 82.0

const BOTTOM_LEFT_X := 40.0
const BOTTOM_LEFT_MARGIN := 20.0
const TIRES_W := 252.0
const VITALS_GAP := 8.0
const VITALS_W := 144.0
const BOTTOM_LEFT_H := 168.0

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
	var safe_factor := maxf(factor, 0.01)
	var logical_w := size.x / safe_factor
	var logical_h := size.y / safe_factor
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * factor)

	_draw_split_standings()
	_draw_damage(DAMAGE_RECT)

	var right_x := maxf(logical_w - TIMING_MARGIN_RIGHT - TIMING_WIDTH, 640.0)
	_draw_timing(Vector2(right_x, TIMING_TOP))

	var bottom_y := logical_h - BOTTOM_LEFT_H - BOTTOM_LEFT_MARGIN
	_draw_tires(Rect2(BOTTOM_LEFT_X, bottom_y, TIRES_W, BOTTOM_LEFT_H))
	_draw_fuel_and_engine(Rect2(BOTTOM_LEFT_X + TIRES_W + VITALS_GAP, bottom_y, VITALS_W, BOTTOM_LEFT_H))

	draw_set_transform(Vector2.ZERO)


# =============================================================================
# CLASIFICACIÓN PARCIAL (ARRIBA-IZQUIERDA)
# =============================================================================


func _draw_split_standings() -> void:
	var competition: Dictionary = snapshot.get("competition", {})
	var rows: Array = competition.get("split_standings", [])
	if rows.is_empty():
		return

	var count := mini(rows.size(), 3)
	for i in count:
		var entry: Dictionary = rows[i]
		var y := STANDINGS_ORIGIN.y + float(i) * (STANDINGS_ROW_SIZE.y + STANDINGS_ROW_GAP)
		var row_rect := Rect2(STANDINGS_ORIGIN.x, y, STANDINGS_ROW_SIZE.x, STANDINGS_ROW_SIZE.y)
		var is_player := bool(entry.get("player", false))
		var bg := Cmr2Style.PANEL_PLAYER_BG if is_player else Cmr2Style.PANEL_BG
		var fg := Cmr2Style.TEXT_WHITE if is_player else Cmr2Style.TEXT_STANDING
		Cmr2Style.draw_panel(self, row_rect, bg, Cmr2Style.PANEL_BORDER)

		var pos_text := str(int(entry.get("position", i + 1)))
		var code_text := Cmr2Style.driver_code(str(entry.get("name", "")))
		var time_text := Cmr2Style.format_stage_time_ms(entry.get("time_ms"))

		Cmr2Style.draw_box_text(self, Rect2(row_rect.position.x + 12.0, y, 36.0, row_rect.size.y), pos_text, 22, fg, true, HORIZONTAL_ALIGNMENT_LEFT)
		Cmr2Style.draw_box_text(self, Rect2(row_rect.position.x + 50.0, y, 220.0, row_rect.size.y), code_text, 22, fg, true, HORIZONTAL_ALIGNMENT_LEFT)
		Cmr2Style.draw_box_text(self, Rect2(row_rect.position.x + 260.0, y, row_rect.size.x - 274.0, row_rect.size.y), time_text, 22, fg, true, HORIZONTAL_ALIGNMENT_RIGHT)


# =============================================================================
# DAÑOS MINIMALISTAS (IZQUIERDA-CENTRAL)
# =============================================================================


func _draw_damage(rect: Rect2) -> void:
	Cmr2Style.draw_panel(self, rect, Cmr2Style.PANEL_GAUGE_BG, Cmr2Style.PANEL_BORDER)

	var header_rect := Rect2(rect.position.x + 10.0, rect.position.y + 4.0, rect.size.x - 20.0, 16.0)
	Cmr2Style.draw_box_text(self, header_rect, "DAÑOS", 12, Cmr2Style.TEXT_WHITE, true, HORIZONTAL_ALIGNMENT_LEFT)
	draw_rect(Rect2(rect.position.x + 8.0, rect.position.y + 22.0, rect.size.x - 16.0, 1.0), Cmr2Style.PANEL_DIVIDER)

	var dmg: Dictionary = snapshot.get("damage", {})
	var eng_snap: Dictionary = snapshot.get("engine", {})
	var rows := [
		{"label": "RADIADOR", "ratio": clampf(float(dmg.get("radiator", eng_snap.get("radiator_damage", 0.0))), 0.0, 1.0)},
		{"label": "MOTOR", "ratio": clampf(float(dmg.get("engine", eng_snap.get("engine_damage", 0.0))), 0.0, 1.0)},
		{"label": "TRANS.", "ratio": clampf(float(dmg.get("transmission", 0.0)), 0.0, 1.0)},
	]

	var row_start_y := rect.position.y + 27.0
	var row_step := 28.0
	var inner_w := rect.size.x - 20.0
	for i in rows.size():
		var row: Dictionary = rows[i]
		var y := row_start_y + float(i) * row_step
		var ratio := float(row.ratio)
		var bar_color := _damage_color(ratio)
		var value_color := Cmr2Style.TEXT_WHITE if ratio < 0.05 else bar_color

		Cmr2Style.draw_box_text(self, Rect2(rect.position.x + 10.0, y, 120.0, 14.0), str(row.label), 12, Cmr2Style.TEXT_WHITE, true, HORIZONTAL_ALIGNMENT_LEFT)
		Cmr2Style.draw_box_text(self, Rect2(rect.end.x - 66.0, y, 56.0, 14.0), "%d%%" % roundi(ratio * 100.0), 12, value_color, true, HORIZONTAL_ALIGNMENT_RIGHT)

		var track := Rect2(rect.position.x + 10.0, y + 16.0, inner_w, 6.0)
		draw_rect(track, Cmr2Style.PANEL_WELL_BG)
		if ratio > 0.005:
			var fill_w := maxf(track.size.x * ratio, 3.0)
			draw_rect(Rect2(track.position, Vector2(fill_w, track.size.y)), bar_color)


func _damage_color(ratio: float) -> Color:
	if ratio < 0.25:
		return C_GREEN
	if ratio < 0.50:
		return C_GOLD
	if ratio < 0.75:
		return C_ORANGE
	return C_ROSE


# =============================================================================
# BARRA DE SECTORES Y CRONÓMETRO (ARRIBA-DERECHA)
# =============================================================================


func _draw_timing(origin: Vector2) -> void:
	var course: Dictionary = snapshot.get("course", {})
	var competition: Dictionary = snapshot.get("competition", {})
	var sector_deltas: Array = competition.get("sector_deltas_ms", [])
	var split_positions: Array = course.get("split_positions", [])
	var sector_count := maxi(int(competition.get("sector_count", 0)), split_positions.size())

	var clock_y := origin.y
	if sector_count > 0:
		var bar_rect := Rect2(origin.x, origin.y, TIMING_WIDTH, SPLIT_BAR_HEIGHT)
		_draw_split_progress_bar(bar_rect, sector_count, sector_deltas)
		clock_y += SPLIT_BAR_HEIGHT

	var clock_rect := Rect2(origin.x, clock_y, TIMING_WIDTH, CLOCK_PANEL_HEIGHT)
	Cmr2Style.draw_panel(self, clock_rect, Cmr2Style.PANEL_BG, Cmr2Style.PANEL_BORDER)

	var current_s: Variant = course.get("current_s")
	var current_ms: Variant = null if current_s == null else roundi(float(current_s) * 1000.0)
	var time_str := Cmr2Style.format_stage_time_ms(current_ms)
	var digit_h := 50.0
	var text_y := clock_rect.position.y + (clock_rect.size.y - digit_h) * 0.5
	Cmr2Style.draw_lcd_text(self, Vector2(clock_rect.position.x, text_y), time_str, digit_h, Cmr2Style.TEXT_WHITE, clock_rect.size.x, HORIZONTAL_ALIGNMENT_CENTER, 0.05)


func _draw_split_progress_bar(rect: Rect2, sector_count: int, sector_deltas: Array) -> void:
	var seg_w := rect.size.x / float(sector_count)
	var active_index := sector_deltas.size()
	for i in sector_count:
		var x0 := rect.position.x + float(i) * seg_w
		var next_x := rect.position.x + float(i + 1) * seg_w
		var cell := Rect2(x0, rect.position.y, next_x - x0, rect.size.y)
		if i < active_index:
			var delta_val: Variant = sector_deltas[i]
			var seg_color := Cmr2Style.PANEL_PLAYER_BG
			if delta_val != null and (delta_val is int or delta_val is float):
				seg_color = Color(Cmr2Style.AHEAD_COLOR, 0.94) if int(delta_val) <= 0 else Color(Cmr2Style.BEHIND_COLOR, 0.94)
			draw_rect(cell, seg_color)
		elif i == active_index:
			# Current split highlight mimics RallyData_LayoutPlayerSplitBars
			var upper_h := floorf(cell.size.y * 0.45)
			draw_rect(Rect2(cell.position, Vector2(cell.size.x, upper_h)), Cmr2Style.PANEL_BG_ACTIVE)
			draw_rect(Rect2(cell.position.x, cell.position.y + upper_h, cell.size.x, cell.size.y - upper_h), Cmr2Style.PANEL_BG_DIM)
		else:
			draw_rect(cell, Cmr2Style.PANEL_BG_DIM)

		if i > 0:
			draw_line(Vector2(x0, rect.position.y), Vector2(x0, rect.end.y), Color(1.0, 1.0, 1.0, 0.90), 1.0)
	draw_rect(rect, Cmr2Style.PANEL_BORDER, false, 1.0)


# =============================================================================
# NEUMÁTICOS / RUEDAS / FRENOS 2×2 (ABAJO-IZQUIERDA)
# =============================================================================


func _draw_tires(rect: Rect2) -> void:
	var wheels: Array = snapshot.get("wheels", [])
	var codes := ["FL", "FR", "RL", "RR"]
	var gap := 6.0
	var cell_w := (rect.size.x - gap) * 0.5
	var cell_h := (rect.size.y - gap) * 0.5

	for i in 4:
		var col := i % 2
		var row := i / 2
		var x := rect.position.x + float(col) * (cell_w + gap)
		var y := rect.position.y + float(row) * (cell_h + gap)
		var card := Rect2(x, y, cell_w, cell_h)
		Cmr2Style.draw_panel(self, card, Cmr2Style.PANEL_GAUGE_BG, Cmr2Style.PANEL_BORDER)

		var wheel: Dictionary = wheels[i] if wheels.size() > i else {}
		Cmr2Style.draw_box_text(self, Rect2(x + 6.0, y + 3.0, 22.0, 13.0), codes[i], 11, Cmr2Style.TEXT_WHITE, true)

		var has_align := float(wheel.get("alignment_collision_damage", 0.0)) > 0.005
		var has_rim := float(wheel.get("rim_deformation", 0.0)) > 0.005
		if has_align:
			Cmr2Style.draw_box_text(self, Rect2(x + 26.0, y + 3.0, 32.0, 13.0), "ALIN.", 8, C_ROSE, true)
		Cmr2Style.draw_box_text(
			self,
			Rect2(x + 54.0, y + 3.0, cell_w - 60.0, 13.0),
			number(wheel.get("pressure_kpa_gauge")) + " kPa",
			11,
			Cmr2Style.TEXT_WHITE,
			true,
			HORIZONTAL_ALIGNMENT_RIGHT
		)

		var disc_center := Vector2(x + 24.0, y + 43.0)
		var brake_value: Variant = wheel.get("brake_disc_c")
		var disc_color := brake_temp_color(brake_value)
		draw_circle(disc_center, 12.5, Cmr2Style.PANEL_WELL_BG)
		draw_arc(disc_center, 12.5, 0.0, TAU, 24, disc_color, 2.5, true)
		draw_arc(disc_center, 6.5, 0.0, TAU, 16, Color(disc_color, 0.45), 1.5, true)
		Cmr2Style.draw_box_text(self, Rect2(x + 4.0, y + 59.0, 40.0, 14.0), number(brake_value) + "°", 11, disc_color, true, HORIZONTAL_ALIGNMENT_CENTER)

		if float(wheel.get("brake_collision_loss", 0.0)) > 0.005:
			Cmr2Style.draw_box_text(self, Rect2(x + 5.0, y + 17.0, 42.0, 11.0), "FRENO", 8, C_ROSE, true)
		else:
			var brake_remaining := 1.0 - clampf(float(wheel.get("brake_wear_fraction", 0.0)), 0.0, 1.0)
			Cmr2Style.draw_box_text(
				self,
				Rect2(x + 5.0, y + 17.0, 42.0, 12.0),
				"F%d%%" % roundi(brake_remaining * 100.0),
				10,
				C_ROSE if brake_remaining < 0.3 else Cmr2Style.TEXT_MUTED,
				true
			)

		var tire := Rect2(x + 52.0, y + 22.0, 52.0, 36.0)
		var is_dest := float(wheel.get("carcass_failure", 0.0)) >= 1.0
		var has_leak := float(wheel.get("leak_per_second", 0.0)) > 0.0
		if is_dest or has_leak:
			var warning := "DEST." if is_dest else ("PINCH." if float(wheel.get("pressure_loss_fraction", 0.0)) > 0.85 else "FUGA")
			Cmr2Style.draw_box_text(self, Rect2(x + 50.0, y + 16.0, cell_w - 54.0, 11.0), warning, 8, C_ROSE, true)
			tire.position.y += 8.0
			tire.size.y -= 8.0
		elif has_rim:
			Cmr2Style.draw_box_text(self, Rect2(x + 50.0, y + 16.0, cell_w - 54.0, 11.0), "ARO", 8, C_ROSE, true)
			tire.position.y += 8.0
			tire.size.y -= 8.0

		draw_rect(tire, Cmr2Style.PANEL_WELL_BG)
		draw_rect(tire, Cmr2Style.PANEL_BORDER, false, 1.0)
		var wear: Variant = wheel.get("wear_fraction")
		var wear_val := clampf(float(wear), 0.0, 1.0) if (wear != null and is_finite(float(wear))) else 0.0
		var zone_colors := tire_zone_colors(wheel, i)
		for band in 3:
			var band_rect := Rect2(tire.position.x + 3.0 + float(band) * 16.0, tire.position.y + 3.0, 14.0, tire.size.y - 6.0)
			var spent := floorf(band_rect.size.y * wear_val)
			draw_rect(Rect2(band_rect.position, Vector2(band_rect.size.x, spent)), Color(0.05, 0.07, 0.12, 0.75))
			draw_rect(
				Rect2(band_rect.position.x, band_rect.position.y + spent, band_rect.size.x, band_rect.size.y - spent),
				zone_colors[band]
			)
		var tread_color := tire_color(wheel.get("tread_c"))
		Cmr2Style.draw_box_text(
			self,
			Rect2(x + 48.0, y + 60.0, cell_w - 52.0, 15.0),
			number(wheel.get("tread_c")) + " °C",
			12,
			tread_color,
			true,
			HORIZONTAL_ALIGNMENT_CENTER
		)


# =============================================================================
# COMBUSTIBLE Y MOTOR SIMPLIFICADOS (ABAJO-IZQUIERDA)
# =============================================================================


func _draw_fuel_and_engine(rect: Rect2) -> void:
	Cmr2Style.draw_panel(self, rect, Cmr2Style.PANEL_GAUGE_BG, Cmr2Style.PANEL_BORDER)

	var pad := 10.0
	var inner_w := rect.size.x - pad * 2.0
	var fuel: Dictionary = snapshot.get("fuel", {})
	var rem := float(fuel.get("remaining_litres", -1.0))
	var cap := float(fuel.get("capacity_litres", -1.0))
	var has_fuel := rem >= 0.0 and cap > 0.0
	var fuel_frac := clampf(rem / maxf(cap, 0.001), 0.0, 1.0) if has_fuel else 0.0
	var fuel_color := Cmr2Style.CYAN_ACCENT
	if has_fuel:
		if fuel_frac <= 0.10:
			fuel_color = Cmr2Style.REDLINE_ACCENT
		elif fuel_frac <= 0.22:
			fuel_color = Cmr2Style.AMBER_ACCENT

	Cmr2Style.draw_box_text(self, Rect2(rect.position.x + pad, rect.position.y + 7.0, 56.0, 14.0), "COMB.", 12, Cmr2Style.TEXT_WHITE, true)
	var fuel_text := ("%.1f L" % rem) if rem >= 0.0 else "-- L"
	Cmr2Style.draw_box_text(self, Rect2(rect.position.x + pad + 50.0, rect.position.y + 6.0, inner_w - 50.0, 16.0), fuel_text, 13, fuel_color if has_fuel else Cmr2Style.TEXT_MUTED, true, HORIZONTAL_ALIGNMENT_RIGHT)

	var seg_count := 10
	var seg_gap := 2.0
	var seg_w := (inner_w - seg_gap * float(seg_count - 1)) / float(seg_count)
	var bar_y := rect.position.y + 26.0
	var lit_count := int(ceil(fuel_frac * float(seg_count))) if (has_fuel and rem > 0.01) else 0
	for s in seg_count:
		var seg_rect := Rect2(rect.position.x + pad + float(s) * (seg_w + seg_gap), bar_y, seg_w, 12.0)
		draw_rect(seg_rect, fuel_color if s < lit_count else Cmr2Style.PANEL_WELL_BG)

	draw_rect(Rect2(rect.position.x + 8.0, rect.position.y + 46.0, rect.size.x - 16.0, 1.0), Cmr2Style.PANEL_DIVIDER)

	# Motor simplificado: Presión de aceite, Temperatura de agua y Alerta/Salud
	var engine: Dictionary = snapshot.get("engine", {})
	var oil: Dictionary = engine.get("oil", {})
	var water: Dictionary = engine.get("water", {})
	var indicators: Dictionary = snapshot.get("hud_indicators", {})

	Cmr2Style.draw_box_text(self, Rect2(rect.position.x + pad, rect.position.y + 51.0, 70.0, 14.0), "MOTOR", 12, Cmr2Style.TEXT_WHITE, true)
	var torque_frac := clampf(float(engine.get("available_torque_fraction", 1.0)), 0.0, 1.0)
	var eng_dmg := clampf(float(engine.get("engine_damage", snapshot.get("damage", {}).get("engine", 0.0))), 0.0, 1.0)
	var pressure_state := str(oil.get("pressure_state", "ok"))
	var status_label := "OK"
	var status_col := Cmr2Style.AHEAD_COLOR
	if pressure_state == "critical" or eng_dmg >= 0.50:
		status_label = "CRIT"
		status_col = Cmr2Style.REDLINE_ACCENT
	elif pressure_state == "low" or torque_frac < 0.99 or eng_dmg >= 0.15:
		status_label = "AVISO"
		status_col = Cmr2Style.AMBER_ACCENT
	Cmr2Style.draw_box_text(self, Rect2(rect.position.x + pad + 60.0, rect.position.y + 51.0, inner_w - 60.0, 14.0), status_label, 11, status_col, true, HORIZONTAL_ALIGNMENT_RIGHT)

	# Temperatura de agua (AGUA / H2O)
	var water_c := float(water.get("temperature_c", -1.0))
	var water_color: Color = indicators.get("water_color", Cmr2Style.TEXT_STANDING)
	var water_frac := clampf((water_c - 40.0) / 90.0, 0.0, 1.0) if water_c >= 0.0 else 0.0
	_draw_vital_row(
		Rect2(rect.position.x + pad, rect.position.y + 72.0, inner_w, 36.0),
		"H2O",
		("%d °C" % roundi(water_c)) if water_c >= 0.0 else "-- °C",
		water_frac,
		water_color
	)

	# Presión de aceite (ACEITE / OIL)
	var oil_bar := float(indicators.get("oil_bar", -1.0))
	var oil_healthy := maxf(float(oil.get("healthy_pressure_bar", 4.5)), 1.0)
	var oil_color: Color = indicators.get("oil_color", Cmr2Style.TEXT_STANDING)
	var oil_frac := clampf(oil_bar / oil_healthy, 0.0, 1.0) if oil_bar >= 0.0 else 0.0
	_draw_vital_row(
		Rect2(rect.position.x + pad, rect.position.y + 116.0, inner_w, 36.0),
		"OIL",
		("%.1f b" % oil_bar) if oil_bar >= 0.0 else "-- b",
		oil_frac,
		oil_color
	)


func _draw_vital_row(rect: Rect2, label: String, value_str: String, fill_fraction: float, bar_color: Color) -> void:
	Cmr2Style.draw_box_text(self, Rect2(rect.position.x, rect.position.y, 44.0, 16.0), label, 12, Cmr2Style.TEXT_WHITE, true)
	Cmr2Style.draw_box_text(self, Rect2(rect.position.x + 42.0, rect.position.y, rect.size.x - 42.0, 16.0), value_str, 13, bar_color, true, HORIZONTAL_ALIGNMENT_RIGHT)
	var track := Rect2(rect.position.x, rect.position.y + 20.0, rect.size.x, 8.0)
	draw_rect(track, Cmr2Style.PANEL_WELL_BG)
	if fill_fraction > 0.01:
		draw_rect(Rect2(track.position, Vector2(maxf(track.size.x * fill_fraction, 3.0), track.size.y)), bar_color)


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
	var keys := ["tread_outer_c", "tread_center_c", "tread_inner_c"]
	if wheel_index % 2 == 1:
		keys = ["tread_inner_c", "tread_center_c", "tread_outer_c"]
	var colors: Array[Color] = []
	for key in keys:
		colors.append(tire_color(wheel.get(key)))
	return colors


func number(value: Variant) -> String:
	return str(roundi(float(value))) if value != null and is_finite(float(value)) else "--"
