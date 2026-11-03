class_name RetroHudDisplay
extends Control

const STATE_SCRIPT := preload("res://features/retro_hud/scripts/retro_hud_state.gd")
const CONFIG_SCRIPT := preload("res://features/retro_hud/scripts/retro_hud_config.gd")
const LIBRON_REGULAR_FONT: Font = preload("res://fonts/libron/Libron-Regular.ttf")
const LIBRON_BOLD_FONT: Font = preload("res://fonts/libron/Libron-Bold.ttf")
const REVOLUTIONS_PER_MINUTE_SEGMENT_TEXTURE := preload("res://features/retro_hud/assets/rpm_segment.svg")
const FUEL_SEGMENT_TEXTURE := preload("res://features/retro_hud/assets/fuel_segment.svg")
const FUEL_ICON_TEXTURE := preload("res://features/retro_hud/assets/fuel_icon.svg")
const DIVIDER_TEXTURE := preload("res://features/retro_hud/assets/divider.svg")

const DESIGN_SIZE := Vector2(1448.0, 1086.0)
const REVOLUTIONS_PER_MINUTE_CENTER := Vector2(650.0, 760.0)
const REVOLUTIONS_PER_MINUTE_RADIUS := 470.0
const REVOLUTIONS_PER_MINUTE_START_DEGREES := 180.0
const REVOLUTIONS_PER_MINUTE_END_DEGREES := 328.0
const REVOLUTIONS_PER_MINUTE_LABEL_RADIUS := 540.0
const REVOLUTIONS_PER_MINUTE_SCALE_FONT_SIZE := 88
const REVOLUTIONS_PER_MINUTE_VALUE_FONT_SIZE := 180
const REVOLUTIONS_PER_MINUTE_UNIT_FONT_SIZE := 52
const GEAR_FONT_SIZE := 400
const SPEED_FONT_SIZE := 160
const SPEED_UNIT_FONT_SIZE := 52
const TEMPERATURE_LABEL_FONT_SIZE := 52
const TEMPERATURE_VALUE_FONT_SIZE := 94
const FUEL_LABEL_FONT_SIZE := 52
const FUEL_VALUE_FONT_SIZE := 64
const DELTA_LABEL_FONT_SIZE := 64
const DELTA_VALUE_FONT_SIZE := 108

@export_file("*.json") var config_path := "res://features/retro_hud/config/retro_hud.json"
@export_file("*.json") var vehicle_profile_path := "res://data/vehicles/ford-escort-rs2000/vehicle.json"
@export var apply_layout_from_config := false

var state: RetroHudState = STATE_SCRIPT.new()
var config: RetroHudConfig = CONFIG_SCRIPT.new()
var _peak_rpm := 0.0
var _cached_vehicle_max_rpm := 0.0
var _cached_vehicle_idle_rpm := 0.0
var _design_origin := Vector2.ZERO
var _design_scale_factor := 1.0
var _powertrain_configuration: Dictionary = {}
var _card_style_box: StyleBoxFlat = StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	state.changed.connect(_on_state_changed)
	reload_config()
	_peak_rpm = state.rpm
	queue_redraw()


func is_ribbon_style() -> bool:
	return config != null and config.style == "competition_cards_ribbon"


func get_ribbon_size() -> Vector2:
	return Vector2(CLUSTER_W + BAND_MARGIN + FUEL_W, CLUSTER_H)


func set_readout(
		speed_kph: float,
		rpm: float,
		gear_label: String,
		throttle: float = 0.0,
		brake: float = 0.0,
		steering: float = 0.0) -> void:
	state.set_readout(speed_kph, rpm, gear_label, throttle, brake, steering)


func set_controls(steering: float, throttle: float, brake: float) -> void:
	state.set_controls(steering, throttle, brake)


func set_competition_readout(
		speed_kilometers_per_hour: float,
		engine_revolutions_per_minute: float,
		gear_label: String,
		oil_temperature_celsius: float,
		water_temperature_celsius: float,
		fuel_remaining_kg: float,
		fuel_capacity_kg: float,
		average_consumption_kg_per_lap: float,
		has_average_consumption: bool,
		fuel_delta_laps: float,
		has_fuel_delta: bool,
		oil_temperature_color: Color = Color.WHITE,
		water_temperature_color: Color = Color.WHITE,
		steering: float = 0.0,
		throttle: float = 0.0,
		brake: float = 0.0) -> void:
	state.set_competition_readout(
		speed_kilometers_per_hour,
		engine_revolutions_per_minute,
		gear_label,
		oil_temperature_celsius,
		water_temperature_celsius,
		fuel_remaining_kg,
		fuel_capacity_kg,
		average_consumption_kg_per_lap,
		has_average_consumption,
		fuel_delta_laps,
		has_fuel_delta,
		oil_temperature_color,
		water_temperature_color,
		steering,
		throttle,
		brake)


func set_state(next_state: RetroHudState) -> void:
	if next_state == null or state == next_state:
		return
	if state.changed.is_connected(_on_state_changed):
		state.changed.disconnect(_on_state_changed)
	state = next_state
	state.changed.connect(_on_state_changed)
	queue_redraw()


func reload_config() -> void:
	config = CONFIG_SCRIPT.load_from_json(config_path)
	_cached_vehicle_max_rpm = _load_vehicle_max_rpm_from_json()
	_cached_vehicle_idle_rpm = _load_vehicle_idle_rpm_from_json()
	if _cached_vehicle_max_rpm > 0.0 and not _powertrain_configuration.has("max_rpm"):
		_powertrain_configuration["max_rpm"] = _cached_vehicle_max_rpm
	if _cached_vehicle_idle_rpm > 0.0 and not _powertrain_configuration.has("idle_rpm"):
		_powertrain_configuration["idle_rpm"] = _cached_vehicle_idle_rpm
	config.apply_powertrain_configuration(_powertrain_configuration)
	_card_style_box.bg_color = config.background_color
	_card_style_box.border_color = config.divider_color
	_card_style_box.set_border_width_all(config.card_border_width)
	_card_style_box.set_corner_radius_all(config.card_corner_radius)
	if is_ribbon_style():
		custom_minimum_size = get_ribbon_size()
		size = get_ribbon_size()
	else:
		custom_minimum_size = Vector2(390, 292.5)
	if apply_layout_from_config:
		scale = Vector2.ONE * config.display_scale
		visible = config.visible
	queue_redraw()


func set_powertrain_configuration(powertrain_configuration: Dictionary) -> void:
	_powertrain_configuration = powertrain_configuration.duplicate(true)
	if powertrain_configuration.has("vehicle_profile_path"):
		vehicle_profile_path = str(powertrain_configuration["vehicle_profile_path"])
	_cached_vehicle_max_rpm = 0.0
	_cached_vehicle_idle_rpm = 0.0
	reload_config()


func get_vehicle_max_rpm() -> float:
	if _cached_vehicle_max_rpm > 0.0:
		return _cached_vehicle_max_rpm
	_cached_vehicle_max_rpm = _load_vehicle_max_rpm_from_json()
	return _cached_vehicle_max_rpm


func get_vehicle_idle_rpm() -> float:
	if _cached_vehicle_idle_rpm > 0.0:
		return _cached_vehicle_idle_rpm
	_cached_vehicle_idle_rpm = _load_vehicle_idle_rpm_from_json()
	return _cached_vehicle_idle_rpm


func _load_vehicle_max_rpm_from_json(path_hint: String = "") -> float:
	var path_candidates: Array[String] = []
	if not path_hint.is_empty():
		path_candidates.append(path_hint)
	if _powertrain_configuration.has("vehicle_profile_path") and not str(_powertrain_configuration["vehicle_profile_path"]).is_empty():
		path_candidates.append(str(_powertrain_configuration["vehicle_profile_path"]))
	if not vehicle_profile_path.is_empty():
		path_candidates.append(vehicle_profile_path)
	path_candidates.append("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	path_candidates.append("res://data/vehicles/ford-escort-rs2000/powertrain.json")

	for candidate in path_candidates:
		if not FileAccess.file_exists(candidate):
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if not (parsed is Dictionary):
			continue
		var doc: Dictionary = parsed

		# Case 1: vehicle.json with domains
		if doc.has("domains") and doc["domains"] is Dictionary:
			var domains: Dictionary = doc["domains"]
			if domains.has("powertrain"):
				var pt_rel: String = str(domains["powertrain"]).replace("\\", "/")
				var pt_path := candidate.get_base_dir().path_join(pt_rel)
				if FileAccess.file_exists(pt_path):
					var pt_file := FileAccess.open(pt_path, FileAccess.READ)
					if pt_file != null:
						var pt_parsed: Variant = JSON.parse_string(pt_file.get_as_text())
						if pt_parsed is Dictionary and pt_parsed.has("powertrain") and pt_parsed["powertrain"] is Dictionary:
							var rpm_val := float(pt_parsed["powertrain"].get("max_rpm", 0.0))
							if rpm_val > 0.0:
								return rpm_val

		# Case 2: powertrain.json directly
		if doc.has("powertrain") and doc["powertrain"] is Dictionary:
			var rpm_val := float(doc["powertrain"].get("max_rpm", 0.0))
			if rpm_val > 0.0:
				return rpm_val

		# Case 3: root max_rpm
		if doc.has("max_rpm"):
			var rpm_val := float(doc.get("max_rpm", 0.0))
			if rpm_val > 0.0:
				return rpm_val

	# Fallback to powertrain configuration or config
	var fallback := float(_powertrain_configuration.get("max_rpm", config.revolutions_per_minute_maximum))
	if fallback > 0.0:
		return fallback
	return 7500.0


func _load_vehicle_idle_rpm_from_json(path_hint: String = "") -> float:
	var path_candidates: Array[String] = []
	if not path_hint.is_empty():
		path_candidates.append(path_hint)
	if _powertrain_configuration.has("vehicle_profile_path") and not str(_powertrain_configuration["vehicle_profile_path"]).is_empty():
		path_candidates.append(str(_powertrain_configuration["vehicle_profile_path"]))
	if not vehicle_profile_path.is_empty():
		path_candidates.append(vehicle_profile_path)
	path_candidates.append("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	path_candidates.append("res://data/vehicles/ford-escort-rs2000/powertrain.json")

	for candidate in path_candidates:
		if not FileAccess.file_exists(candidate):
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if not (parsed is Dictionary):
			continue
		var doc: Dictionary = parsed

		# Case 1: vehicle.json with domains
		if doc.has("domains") and doc["domains"] is Dictionary:
			var domains: Dictionary = doc["domains"]
			if domains.has("powertrain"):
				var pt_rel: String = str(domains["powertrain"]).replace("\\", "/")
				var pt_path := candidate.get_base_dir().path_join(pt_rel)
				if FileAccess.file_exists(pt_path):
					var pt_file := FileAccess.open(pt_path, FileAccess.READ)
					if pt_file != null:
						var pt_parsed: Variant = JSON.parse_string(pt_file.get_as_text())
						if pt_parsed is Dictionary and pt_parsed.has("powertrain") and pt_parsed["powertrain"] is Dictionary:
							var rpm_val := float(pt_parsed["powertrain"].get("idle_rpm", 0.0))
							if rpm_val > 0.0:
								return rpm_val

		# Case 2: powertrain.json directly
		if doc.has("powertrain") and doc["powertrain"] is Dictionary:
			var rpm_val := float(doc["powertrain"].get("idle_rpm", 0.0))
			if rpm_val > 0.0:
				return rpm_val

		# Case 3: root idle_rpm
		if doc.has("idle_rpm"):
			var rpm_val := float(doc.get("idle_rpm", 0.0))
			if rpm_val > 0.0:
				return rpm_val

	# Fallback to powertrain configuration or default
	var fallback := float(_powertrain_configuration.get("idle_rpm", 1000.0))
	if fallback > 0.0:
		return fallback
	return 1000.0


func apply_hud_layout(scale_value: float, visible_value: bool) -> void:
	visible = visible_value
	scale = Vector2.ONE * maxf(scale_value, 0.1)
	queue_redraw()


func _on_state_changed() -> void:
	_peak_rpm = maxf(_peak_rpm, state.rpm)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return

	if is_ribbon_style():
		_draw_cards_ribbon()
		return

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(Vector2.ZERO, size), config.background_color)
	_design_scale_factor = minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	_design_origin = (size - DESIGN_SIZE * _design_scale_factor) * 0.5
	draw_set_transform(_design_origin, 0.0, Vector2.ONE * _design_scale_factor)

	_draw_revolutions_per_minute_scale()
	_draw_shift_lights()
	_draw_gear_and_speed()
	_draw_numeric_revolutions_per_minute()
	_draw_temperature_panel()
	_draw_fuel_bar()
	_draw_fuel_summary()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ==============================================================================
# CLÚSTER Y COMBUSTIBLE · AERO GLASS 2006 + WINDOWS 98
# ==============================================================================

const DIN: Font = preload("res://fonts/D-DIN.ttf")
const DIN_BOLD: Font = preload("res://fonts/D-DIN-Bold.ttf")

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
const C_GOLD_HI := Color("#f6d68a")
const C_ROSE := Color("#ff6b61")
const C_GREEN := Color("#8fd36b")
const C_BLUE := Color("#6db2e8")
const C_BLUE_DEEP := Color("#2c6da3")
const C_GLASS := Color("#16232f")
const C_RIM := Color("#7fa8c9")
const C_SEL := Color("#3b3324")

const CLUSTER_W := 1000.0
const CLUSTER_H := 160.0
const FUEL_W := 140.0
const BAND_MARGIN := 24.0


func _draw_cards_ribbon() -> void:
	var band_top := size.y - CLUSTER_H - BAND_MARGIN
	if size.x < 1180.0:
		var total := CLUSTER_W + BAND_MARGIN + FUEL_W
		var factor := minf(size.x / (total + BAND_MARGIN), size.y / (CLUSTER_H + BAND_MARGIN))
		var origin := (size - Vector2(total, CLUSTER_H) * factor) * 0.5
		draw_set_transform(origin, 0.0, Vector2.ONE * factor)
		_draw_cluster(Rect2(0, 0, CLUSTER_W, CLUSTER_H))
		_draw_fuel(Rect2(CLUSTER_W + BAND_MARGIN, 0, FUEL_W, CLUSTER_H))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	_draw_cluster(Rect2(roundf((size.x - CLUSTER_W) * 0.5), band_top, CLUSTER_W, CLUSTER_H))
	_draw_fuel(Rect2(size.x - BAND_MARGIN - FUEL_W, band_top, FUEL_W, CLUSTER_H))


# -----------------------------------------------------------------------------
# Clúster
# -----------------------------------------------------------------------------


func _draw_cluster(rect: Rect2) -> void:
	_glass_frame(rect)
	var body := Rect2(rect.position.x + 8, rect.position.y + 8, rect.size.x - 16, rect.size.y - 16)
	draw_rect(body, C_FACE)
	_bevel(body, false, 2)

	var cursor := body.position.x + 8.0
	var top := body.position.y + 8.0
	var height := body.size.y - 16.0

	_draw_steering_section(Rect2(cursor, top, 106.0, height))
	cursor += 106.0
	_divider(cursor, top, height)
	cursor += 2.0
	_draw_pedals_section(Rect2(cursor, top, 114.0, height))
	cursor += 114.0
	_divider(cursor, top, height)
	cursor += 2.0
	_draw_gear_section(Rect2(cursor, top, 106.0, height))
	cursor += 106.0
	_divider(cursor, top, height)
	cursor += 2.0
	_draw_tach_section(Rect2(cursor, top, 490.0, height))
	cursor += 490.0
	_divider(cursor, top, height)
	cursor += 2.0
	_draw_readouts_section(Rect2(cursor, top, 136.0, height))


func _divider(x: float, y: float, height: float) -> void:
	draw_rect(Rect2(x, y + 4, 1, height - 8), C_SHADOW)
	draw_rect(Rect2(x + 1, y + 4, 1, height - 8), C_LIGHT)


func _draw_steering_section(rect: Rect2) -> void:
	var center := Vector2(rect.get_center().x, rect.position.y + 44)
	draw_circle(center, 30.0, C_FIELD)
	draw_arc(center, 30.0, 0.0, TAU, 44, C_FACE_HI, 4.0, true)
	var rotation := -clampf(state.steering, -1.0, 1.0) * PI * 0.75
	for angle in [-PI * 0.5, PI * 0.22, PI * 0.78]:
		var direction := Vector2(cos(angle + rotation), sin(angle + rotation))
		draw_line(center + direction * 6.0, center + direction * 26.0, C_TEXT, 3.0, true)
	draw_circle(center, 5.5, C_HI)
	_num(
		Box(rect.position.x, rect.position.y + 84, rect.size.x, 22),
		"%d°" % roundi(absf(state.steering) * 32.0),
		16,
		C_TEXT,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x
	)


func _draw_pedals_section(rect: Rect2) -> void:
	var bar_w := 36.0
	var bar_h := rect.size.y - 26.0
	var left := Rect2(rect.position.x + 12, rect.position.y + 2, bar_w, bar_h)
	var right := Rect2(rect.position.x + rect.size.x - 12 - bar_w, rect.position.y + 2, bar_w, bar_h)
	for entry in [
		{"r": left, "v": clampf(state.throttle, 0.0, 1.0), "c": C_GREEN},
		{"r": right, "v": clampf(state.brake, 0.0, 1.0), "c": C_ROSE},
	]:
		var bar: Rect2 = entry.r
		var value := float(entry.v)
		draw_rect(bar, C_FIELD)
		_sunken(bar)
		var fill_h := floorf((bar.size.y - 4) * value)
		if fill_h > 0:
			draw_rect(
				Rect2(bar.position.x + 2, bar.end.y - 2 - fill_h, bar.size.x - 4, fill_h), entry.c
			)
			draw_rect(
				Rect2(bar.position.x + 2, bar.end.y - 2 - fill_h, bar.size.x - 4, 3),
				Color(entry.c, 0.5)
			)
		_num(
			Box(bar.position.x - 6, bar.end.y + 4, bar.size.x + 12, 16),
			"%d%%" % roundi(value * 100.0),
			11,
			C_TEXT if value > 0.02 else C_DIM,
			HORIZONTAL_ALIGNMENT_CENTER,
			bar.size.x + 12
		)


func _draw_gear_section(rect: Rect2) -> void:
	var rpm := maxf(state.engine_revolutions_per_minute, 0.0)
	var in_window := rpm >= config.ideal_shift_revolutions_per_minute
	var urgent := rpm >= config.urgent_shift_revolutions_per_minute
	var gear_color := C_ROSE if urgent else (C_GOLD if in_window else C_TEXT)

	var cell := Rect2(rect.position.x + 14, rect.position.y + 2, rect.size.x - 28, 96)
	draw_rect(cell, C_FIELD)
	_sunken(cell)
	_num(
		Box(cell.position.x, cell.position.y, cell.size.x, cell.size.y),
		state.gear_label,
		60,
		gear_color,
		HORIZONTAL_ALIGNMENT_CENTER,
		cell.size.x
	)

	var light_y := rect.position.y + 112
	_led(Vector2(rect.position.x + 32, light_y), in_window, C_GOLD)
	_led(Vector2(rect.position.x + rect.size.x - 32, light_y), urgent, C_ROSE)


func _draw_tach_section(rect: Rect2) -> void:
	var vehicle_max := get_vehicle_max_rpm()
	var vehicle_idle := get_vehicle_idle_rpm()
	var current_rpm := maxf(state.engine_revolutions_per_minute, 0.0)
	var rpm_min := maxf(1000.0, floorf(vehicle_idle / 1000.0) * 1000.0)
	var rpm_max := maxf(rpm_min + 3000.0, ceilf(vehicle_max / 1000.0) * 1000.0)
	var span := rpm_max - rpm_min
	var redline := vehicle_max
	var ideal := minf(config.ideal_shift_revolutions_per_minute, redline * 0.88)
	var urgent := minf(config.urgent_shift_revolutions_per_minute, redline * 0.97)

	var count := 20
	var bar_w := 18.0
	var bar_gap := 4.0
	var total_w := float(count) * bar_w + float(count - 1) * bar_gap
	var start_x := rect.position.x + (rect.size.x - total_w) * 0.5
	var bar_top := rect.position.y + 22.0
	var bar_bottom := rect.position.y + 94.0
	var meseta := 32.0
	var per_bar := span / float(count)

	var first_center := start_x + bar_w * 0.5
	var last_center := start_x + float(count - 1) * (bar_w + bar_gap) + bar_w * 0.5
	var milestones := _get_tachometer_scale_milestones(rpm_min, rpm_max)
	for milestone: float in milestones:
		var fraction := clampf((milestone - rpm_min) / span, 0.0, 1.0)
		var x := lerpf(first_center, last_center, fraction)
		var active := current_rpm >= milestone
		var color := C_TEXT
		if milestone >= urgent:
			color = C_ROSE
		elif milestone >= ideal:
			color = C_GOLD
		elif not active:
			color = C_DIM
		_num(
			Box(x - 15, rect.position.y, 30, 18),
			str(roundi(milestone / 1000.0)),
			13,
			color,
			HORIZONTAL_ALIGNMENT_CENTER,
			30
		)

	for i in count:
		var points := _get_tachometer_bar_polygon(
			i, start_x, bar_w, bar_gap, bar_top, bar_bottom, meseta
		)
		var outline := PackedVector2Array([points[0], points[1], points[2], points[3], points[0]])
		var bar_start := rpm_min + float(i) * per_bar
		var bar_target := bar_start + per_bar
		draw_colored_polygon(points, C_FIELD)
		draw_polyline(outline, C_SHADOW, 1.0, true)
		if current_rpm >= bar_start:
			var color := C_TEXT
			if current_rpm >= urgent:
				color = C_ROSE
			elif bar_target >= urgent:
				color = C_ROSE
			elif bar_target >= ideal:
				color = C_GOLD
			draw_colored_polygon(points, color)
			draw_line(points[0], points[1], Color(1, 1, 1, 0.35), 1.0, true)
			draw_line(points[3], points[2], Color(0, 0, 0, 0.45), 1.0, true)

	var shift_start := lerpf(first_center, last_center, clampf((ideal - rpm_min) / span, 0.0, 1.0))
	var urgent_start := lerpf(first_center, last_center, clampf((urgent - rpm_min) / span, 0.0, 1.0))
	draw_rect(Rect2(shift_start, bar_bottom + 6, urgent_start - shift_start, 5), C_GOLD)
	draw_rect(Rect2(urgent_start, bar_bottom + 6, last_center + 8.0 - urgent_start, 5), C_ROSE)


func _draw_readouts_section(rect: Rect2) -> void:
	var rpm := maxf(state.engine_revolutions_per_minute, 0.0)
	var urgent := rpm >= config.urgent_shift_revolutions_per_minute
	var in_window := rpm >= config.ideal_shift_revolutions_per_minute
	var box_w := 116.0
	var box_h := 44.0
	var gap := 10.0
	var left := rect.position.x + (rect.size.x - box_w) * 0.5
	var top := rect.position.y + (rect.size.y - (box_h * 2.0 + gap)) * 0.5
	_field_box(
		Rect2(left, top, box_w, box_h),
		"%d rpm" % roundi(rpm),
		17,
		C_ROSE if urgent else (C_GOLD if in_window else C_TEXT)
	)
	_field_box(
		Rect2(left, top + box_h + gap, box_w, box_h),
		"%d km/h" % roundi(maxf(state.speed_kilometers_per_hour, 0.0)),
		17,
		C_TEXT
	)


# -----------------------------------------------------------------------------
# Combustible vertical
# -----------------------------------------------------------------------------


func _draw_fuel(rect: Rect2) -> void:
	_glass_frame(rect)
	var body := Rect2(rect.position.x + 8, rect.position.y + 8, rect.size.x - 16, rect.size.y - 16)
	draw_rect(body, C_FACE)
	_bevel(body, false, 2)

	var bar := Rect2(body.position.x + 92, body.position.y + 2, 24, body.size.y - 4)
	draw_rect(bar, C_FIELD)
	_sunken(bar)
	var fraction := 0.0
	if state.fuel_capacity_kg > 0.0 and state.fuel_remaining_kg >= 0.0:
		fraction = clampf(state.fuel_remaining_kg / state.fuel_capacity_kg, 0.0, 1.0)
	var filled := floorf((bar.size.y - 4) * fraction)
	var low := fraction <= config.fuel_alert_fraction
	if filled > 0.5:
		draw_rect(
			Rect2(bar.position.x + 2, bar.end.y - 2 - filled, bar.size.x - 4, filled),
			Color(C_ROSE if low else C_BLUE_DEEP, 0.95)
		)
		draw_rect(
			Rect2(bar.position.x + 2, bar.end.y - 2 - filled, bar.size.x - 4, 3),
			Color(C_ROSE if low else C_BLUE, 0.9)
		)
	for l in 4:
		_text(
			Box(bar.position.x, bar.position.y + 18 + float(l) * 28, bar.size.x, 16),
			["F", "U", "E", "L"][l],
			9,
			C_TEXT,
			true,
			HORIZONTAL_ALIGNMENT_CENTER
		)

	var litres := "-- L"
	if state.fuel_remaining_kg >= 0.0:
		litres = "%d L" % roundi(state.fuel_remaining_kg)
	_text(
		Box(body.position.x + 6, body.position.y, body.size.x - 42, 24),
		litres,
		18,
		C_ROSE if low else C_TEXT,
		true,
		HORIZONTAL_ALIGNMENT_RIGHT,
		body.size.x - 42
	)

	var delta := "+0.0"
	if state.has_fuel_delta:
		delta = ("+%.1f" % state.fuel_delta_laps) if state.fuel_delta_laps >= 0.0 \
			else ("-%.1f" % absf(state.fuel_delta_laps))
	_text(Box(body.position.x + 6, body.position.y + 26, body.size.x - 42, 11), "DELTA", 8, C_DIM)
	_field_box(
		Rect2(body.position.x + 6, body.position.y + 38, body.size.x - 42, 24),
		delta,
		13,
		C_TEXT,
		true
	)
	_text(Box(body.position.x + 6, body.position.y + 64, body.size.x - 42, 11), "OIL BAR", 8, C_DIM)
	_field_box(
		Rect2(body.position.x + 6, body.position.y + 76, body.size.x - 42, 24),
		_pressure(state.oil_temperature_celsius),
		13,
		state.oil_temperature_color if state.oil_temperature_color != Color.WHITE else C_TEXT,
		true
	)
	_text(Box(body.position.x + 6, body.position.y + 102, body.size.x - 42, 11), "WATER", 8, C_DIM)
	_field_box(
		Rect2(body.position.x + 6, body.position.y + 114, body.size.x - 42, 24),
		_temperature(state.water_temperature_celsius),
		13,
		state.water_temperature_color if state.water_temperature_color != Color.WHITE else C_TEXT,
		true
	)


# oil_temperature_celsius transporta aqui la presion de aceite en bar (-1 = sin dato).
func _pressure(value: float) -> String:
	if value < 0.0:
		return "--"
	return "%.1f" % value


func _temperature(value: float) -> String:
	if value < 0.0:
		return "-- °C"
	return "%d °C" % roundi(value)


# -----------------------------------------------------------------------------
# Primitivas
# -----------------------------------------------------------------------------


func _glass_frame(rect: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_GLASS, 0.90)
	sb.border_color = Color(C_RIM, 0.40)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	draw_style_box(sb, rect)
	var gloss := StyleBoxFlat.new()
	gloss.bg_color = Color(1, 1, 1, 0.06)
	gloss.corner_radius_top_left = 10
	gloss.corner_radius_top_right = 10
	draw_style_box(gloss, Rect2(rect.position + Vector2(1, 1), Vector2(rect.size.x - 2, 10)))


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


func _field_box(rect: Rect2, value: String, size: int, color: Color, serif: bool = false) -> void:
	draw_rect(rect, C_FIELD)
	_sunken(rect)
	var inner := Box(rect.position.x + 6, rect.position.y, rect.size.x - 12, rect.size.y)
	if serif:
		_text(inner, value, size, color, true, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		_num(inner, value, size, color, HORIZONTAL_ALIGNMENT_RIGHT)


func _led(center: Vector2, on: bool, color: Color) -> void:
	draw_circle(center, 8.0, C_FIELD)
	draw_arc(center, 8.0, 0.0, TAU, 24, C_SHADOW, 1.5, true)
	draw_arc(center + Vector2(1, 1), 7.0, PI * 1.05, PI * 1.6, 10, C_LIGHT, 1.0, true)
	if on:
		draw_circle(center, 5.0, color)
		draw_circle(center, 7.0, Color(color, 0.22))
	else:
		draw_circle(center, 5.0, C_FACE_LO)


func Box(x: float, y: float, width: float, height: float) -> Rect2:
	return Rect2(x, y, width, height)


func _num(
	rect: Rect2,
	value: String,
	size: int,
	color: Color,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	width_override: float = -1.0
) -> void:
	if value.is_empty():
		return
	var width: float = rect.size.x if width_override < 0.0 else width_override
	var line_height := DIN_BOLD.get_height(size)
	var baseline := rect.position.y + (rect.size.y + line_height) * 0.5 - DIN_BOLD.get_descent(size)
	draw_string(
		DIN_BOLD,
		Vector2(round(rect.position.x), round(baseline)),
		value,
		align,
		width,
		size,
		color
	)


func _text(
	rect: Rect2,
	value: String,
	size: int,
	color: Color,
	bold: bool = false,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	width_override: float = -1.0
) -> void:
	if value.is_empty():
		return
	var font: Font = LIBRON_BOLD_FONT if bold else LIBRON_REGULAR_FONT
	var width: float = rect.size.x if width_override < 0.0 else width_override
	var line_height := font.get_height(size)
	var baseline := rect.position.y + (rect.size.y + line_height) * 0.5 - font.get_descent(size)
	draw_string(font, Vector2(round(rect.position.x), round(baseline)), value, align, width, size, color)


func _get_tachometer_scale_milestones(rpm_min: float, rpm_max: float) -> Array[float]:
	var span := rpm_max - rpm_min
	if is_equal_approx(rpm_min, 1000.0) and is_equal_approx(rpm_max, 8000.0):
		var default_milestones: Array[float] = [1000.0, 2000.0, 4000.0, 6000.0, 8000.0]
		return default_milestones
	var milestones: Array[float] = [rpm_min]
	var steps: Array[float] = [0.20, 0.45, 0.72]
	for step: float in steps:
		var target: float = rpm_min + span * step
		var rounded: float = roundf(target / 1000.0) * 1000.0
		if rounded <= milestones[-1]:
			rounded = milestones[-1] + 1000.0
		milestones.append(rounded)
	milestones.append(rpm_max)
	return milestones


# Forma original del tacómetro: rampa, transición y meseta suspendida.
func _get_tachometer_bar_polygon(
		bar_index: int,
		start_x: float,
		bar_w: float,
		bar_gap: float,
		bar_top_y: float,
		bar_bottom_y: float,
		meseta_h: float) -> PackedVector2Array:
	var bx := start_x + float(bar_index) * (bar_w + bar_gap)
	var bx_r := bx + bar_w
	var y_tl: float
	var y_tr: float
	var y_bl: float
	var y_br: float

	if bar_index <= 3:
		var ramp_x_start := start_x
		var ramp_x_end := start_x + 3.0 * (bar_w + bar_gap) + bar_w
		var frac_l := clampf((bx - ramp_x_start) / (ramp_x_end - ramp_x_start), 0.0, 1.0)
		var frac_r := clampf((bx_r - ramp_x_start) / (ramp_x_end - ramp_x_start), 0.0, 1.0)
		y_bl = bar_bottom_y
		y_br = bar_bottom_y
		y_tl = bar_bottom_y - lerpf(18.0, bar_bottom_y - bar_top_y, frac_l)
		y_tr = bar_bottom_y - lerpf(18.0, bar_bottom_y - bar_top_y, frac_r)
	elif bar_index <= 6:
		var trans_x_start := start_x + 4.0 * (bar_w + bar_gap)
		var trans_x_end := start_x + 6.0 * (bar_w + bar_gap) + bar_w
		var frac_l := clampf((bx - trans_x_start) / (trans_x_end - trans_x_start), 0.0, 1.0)
		var frac_r := clampf((bx_r - trans_x_start) / (trans_x_end - trans_x_start), 0.0, 1.0)
		y_tl = bar_top_y
		y_tr = bar_top_y
		y_bl = lerpf(bar_bottom_y, bar_top_y + meseta_h, frac_l)
		y_br = lerpf(bar_bottom_y, bar_top_y + meseta_h, frac_r)
	else:
		y_tl = bar_top_y
		y_tr = bar_top_y
		y_bl = bar_top_y + meseta_h
		y_br = bar_top_y + meseta_h

	return PackedVector2Array([
		Vector2(bx, y_tl),
		Vector2(bx_r, y_tr),
		Vector2(bx_r, y_br),
		Vector2(bx, y_bl)
	])


func _draw_card_text(
		value: String,
		pos: Vector2,
		width: float,
		font_size: int,
		color: Color,
		font: Font = LIBRON_BOLD_FONT) -> void:
	draw_string(font, pos, value, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)


# ==============================================================================
# ==============================================================================
# LEGACY COMPETITION CIRCULAR DISPLAY IMPLEMENTATION
# ==============================================================================

func _draw_revolutions_per_minute_scale() -> void:
	_draw_revolutions_per_minute_band(
		config.revolutions_per_minute_minimum,
		config.urgent_shift_revolutions_per_minute,
		config.inactive_color)
	_draw_revolutions_per_minute_band(
		config.revolutions_per_minute_minimum,
		clampf(state.engine_revolutions_per_minute, config.revolutions_per_minute_minimum, config.urgent_shift_revolutions_per_minute),
		config.alert_color if state.engine_revolutions_per_minute >= config.urgent_shift_revolutions_per_minute else config.dial_color)
	var segment_count := clampi(roundi(config.revolutions_per_minute_maximum / 1000.0), 5, 32)
	for segment_index in range(segment_count):
		var segment_ratio := float(segment_index) / float(segment_count - 1)
		var angle_degrees := lerpf(
			REVOLUTIONS_PER_MINUTE_START_DEGREES,
			REVOLUTIONS_PER_MINUTE_END_DEGREES,
			segment_ratio)
		var angle_radians := deg_to_rad(angle_degrees)
		var radial_direction := Vector2(cos(angle_radians), sin(angle_radians))
		var displayed_revolutions_per_minute := segment_index
		if displayed_revolutions_per_minute % 2 == 0:
			var label_center := (
				REVOLUTIONS_PER_MINUTE_CENTER
				+ radial_direction * REVOLUTIONS_PER_MINUTE_LABEL_RADIUS)
			_draw_competition_text(
				str(displayed_revolutions_per_minute),
				label_center,
				REVOLUTIONS_PER_MINUTE_SCALE_FONT_SIZE,
				config.dial_color,
				LIBRON_BOLD_FONT)
	_draw_redline_band()


func _draw_redline_band() -> void:
	var redline_color := (
		config.redline_color
		if state.engine_revolutions_per_minute >= config.urgent_shift_revolutions_per_minute
		else config.inactive_redline_color)
	_draw_revolutions_per_minute_band(
		config.urgent_shift_revolutions_per_minute,
		config.revolutions_per_minute_maximum,
		redline_color)


func _draw_revolutions_per_minute_band(start_revolutions_per_minute: float, end_revolutions_per_minute: float, color: Color) -> void:
	if end_revolutions_per_minute <= start_revolutions_per_minute:
		return
	var revolutions_per_minute_range := config.revolutions_per_minute_maximum - config.revolutions_per_minute_minimum
	var start_ratio := (start_revolutions_per_minute - config.revolutions_per_minute_minimum) / revolutions_per_minute_range
	var end_ratio := (end_revolutions_per_minute - config.revolutions_per_minute_minimum) / revolutions_per_minute_range
	draw_arc(
		REVOLUTIONS_PER_MINUTE_CENTER,
		REVOLUTIONS_PER_MINUTE_RADIUS,
		deg_to_rad(lerpf(REVOLUTIONS_PER_MINUTE_START_DEGREES, REVOLUTIONS_PER_MINUTE_END_DEGREES, start_ratio)),
		deg_to_rad(lerpf(REVOLUTIONS_PER_MINUTE_START_DEGREES, REVOLUTIONS_PER_MINUTE_END_DEGREES, end_ratio)),
		128,
		color,
		52.0,
		true)


func engine_readout_color() -> Color:
	return config.alert_color if state.engine_revolutions_per_minute >= config.urgent_shift_revolutions_per_minute else config.digital_color


func _draw_shift_lights() -> void:
	if state.engine_revolutions_per_minute >= config.ideal_shift_revolutions_per_minute:
		draw_circle(Vector2(130.0, 130.0), 57.0, config.inactive_color)
		draw_circle(Vector2(130.0, 130.0), 48.0, config.dial_color)
	if state.engine_revolutions_per_minute >= config.urgent_shift_revolutions_per_minute:
		draw_circle(Vector2(285.0, 130.0), 57.0, config.inactive_color)
		draw_circle(Vector2(285.0, 130.0), 48.0, config.alert_color)


func _draw_gear_and_speed() -> void:
	_draw_competition_text(
		state.gear_label,
		Vector2(617.0, 540.0),
		GEAR_FONT_SIZE,
		engine_readout_color(),
		LIBRON_BOLD_FONT)
	_draw_competition_text(
		str(int(round(state.speed_kilometers_per_hour))),
		Vector2(895.0, 594.0),
		SPEED_FONT_SIZE,
		config.digital_color,
		LIBRON_BOLD_FONT)
	_draw_competition_text("KM/H", Vector2(895.0, 694.0), SPEED_UNIT_FONT_SIZE, config.dial_color, LIBRON_BOLD_FONT)


func _draw_numeric_revolutions_per_minute() -> void:
	_draw_competition_text(
		str(int(round(maxf(state.engine_revolutions_per_minute, 0.0)))),
		Vector2(1240.0, 575.0),
		REVOLUTIONS_PER_MINUTE_VALUE_FONT_SIZE,
		engine_readout_color(),
		LIBRON_BOLD_FONT)
	_draw_competition_text(
		"RPM",
		Vector2(1240.0, 700.0),
		REVOLUTIONS_PER_MINUTE_UNIT_FONT_SIZE,
		config.dial_color,
		LIBRON_BOLD_FONT)


func _draw_temperature_panel() -> void:
	_draw_competition_text("OIL BAR", Vector2(1257.0, 123.0), TEMPERATURE_LABEL_FONT_SIZE, config.dial_color)
	_draw_pressure_value(state.oil_temperature_celsius, state.oil_temperature_color, Vector2(1268.0, 203.0))
	_draw_competition_text("°C", Vector2(1370.0, 204.0), TEMPERATURE_LABEL_FONT_SIZE, config.dial_color)

	_draw_horizontal_divider(Vector2(1164.0, 264.0), 224.0)

	_draw_competition_text("WATER TEMP", Vector2(1257.0, 304.0), TEMPERATURE_LABEL_FONT_SIZE, config.dial_color)
	_draw_temperature_value(state.water_temperature_celsius, state.water_temperature_color, Vector2(1268.0, 385.0))
	_draw_competition_text("°C", Vector2(1370.0, 386.0), TEMPERATURE_LABEL_FONT_SIZE, config.dial_color)


func _draw_pressure_value(pressure_bar: float, pressure_color: Color, center: Vector2) -> void:
	if pressure_bar < 0.0:
		_draw_competition_text("--", center, TEMPERATURE_VALUE_FONT_SIZE, config.inactive_color)
		return
	_draw_competition_text("%.1f" % pressure_bar, center, TEMPERATURE_VALUE_FONT_SIZE, pressure_color)


func _draw_temperature_value(temperature_celsius: float, temperature_color: Color, center: Vector2) -> void:
	if temperature_celsius < 0.0:
		_draw_competition_text("--", center, TEMPERATURE_VALUE_FONT_SIZE, config.inactive_color)
		return
	_draw_competition_text(
		str(int(round(temperature_celsius))),
		center,
		TEMPERATURE_VALUE_FONT_SIZE,
		temperature_color)


func _draw_fuel_bar() -> void:
	_draw_rotated_texture(
		FUEL_ICON_TEXTURE,
		Vector2(328.0, 783.0),
		Vector2(68.0, 78.0),
		0.0,
		config.dial_color)

	var fuel_track := Rect2(Vector2(383.0, 751.0), Vector2(690.0, 66.0))
	draw_rect(fuel_track, config.fuel_container_color)

	var fuel_fraction := 0.0
	if state.fuel_capacity_kg > 0.0 and state.fuel_remaining_kg >= 0.0:
		fuel_fraction = clampf(state.fuel_remaining_kg / state.fuel_capacity_kg, 0.0, 1.0)
	var segment_count := maxi(config.fuel_segment_count, 1)
	var segment_gap := 7.0
	var segment_width := (
		(fuel_track.size.x - 34.0 - segment_gap * float(segment_count - 1))
		/ float(segment_count))
	var first_segment_x := fuel_track.position.x + 17.0
	var fuel_color := (
		config.alert_color
		if fuel_fraction <= config.fuel_alert_fraction
		else config.fuel_active_segment_color)

	for segment_index in range(segment_count):
		var segment_center := Vector2(
			first_segment_x + (segment_width + segment_gap) * float(segment_index) + segment_width * 0.5,
			fuel_track.position.y + fuel_track.size.y * 0.5)
		var segment_fill_fraction := clampf(fuel_fraction * float(segment_count) - float(segment_index), 0.0, 1.0)
		_draw_fuel_segment(
			segment_center,
			Vector2(segment_width, fuel_track.size.y - 16.0),
			segment_fill_fraction,
			fuel_color)


func _draw_fuel_segment(center: Vector2, dimensions: Vector2, fill_fraction: float, active_color: Color) -> void:
	_draw_rotated_texture(FUEL_SEGMENT_TEXTURE, center, dimensions, 0.0, config.fuel_inactive_segment_color)
	if fill_fraction <= 0.0:
		return
	draw_set_transform(_design_origin + center * _design_scale_factor, 0.0, Vector2.ONE * _design_scale_factor)
	draw_texture_rect_region(
		FUEL_SEGMENT_TEXTURE,
		Rect2(-dimensions * 0.5, Vector2(dimensions.x * fill_fraction, dimensions.y)),
		Rect2(Vector2.ZERO, Vector2(FUEL_SEGMENT_TEXTURE.get_width() * fill_fraction, FUEL_SEGMENT_TEXTURE.get_height())),
		active_color)
	_restore_design_transform()


func _draw_fuel_summary() -> void:
	_draw_competition_text("FUEL", Vector2(290.0, 887.0), FUEL_LABEL_FONT_SIZE, config.dial_color)
	_draw_competition_text("AVG", Vector2(728.0, 887.0), FUEL_LABEL_FONT_SIZE, config.dial_color)
	_draw_competition_text("DELTA", Vector2(1154.0, 887.0), DELTA_LABEL_FONT_SIZE, config.dial_color)

	_draw_vertical_divider(Vector2(509.0, 879.0), 123.0)
	_draw_vertical_divider(Vector2(943.0, 879.0), 123.0)

	if state.fuel_remaining_kg < 0.0:
		_draw_competition_text("--.-", Vector2(291.0, 963.0), FUEL_VALUE_FONT_SIZE, config.inactive_color, LIBRON_BOLD_FONT)
	else:
		var fuel_color := config.dial_color
		if state.fuel_capacity_kg > 0.0:
			var fuel_fraction := state.fuel_remaining_kg / state.fuel_capacity_kg
			if fuel_fraction <= config.fuel_alert_fraction:
				fuel_color = config.alert_color
		_draw_competition_text(
			"%.1f L" % state.fuel_remaining_kg,
			Vector2(292.0, 960.0),
			FUEL_VALUE_FONT_SIZE,
			fuel_color,
			LIBRON_BOLD_FONT)
	_draw_competition_text("L", Vector2(408.0, 968.0), FUEL_LABEL_FONT_SIZE, config.dial_color)

	if state.has_average_consumption:
		_draw_competition_text(
			"%.2f" % state.average_consumption_kg_per_lap,
			Vector2(725.0, 960.0),
			FUEL_VALUE_FONT_SIZE,
			config.digital_color,
			LIBRON_BOLD_FONT)
	else:
		_draw_competition_text("--.--", Vector2(724.0, 963.0), FUEL_VALUE_FONT_SIZE, config.inactive_color, LIBRON_BOLD_FONT)
	_draw_competition_text("L/LAP", Vector2(866.0, 968.0), FUEL_LABEL_FONT_SIZE, config.dial_color)

	if state.has_fuel_delta:
		var fuel_delta_color := (
			config.alert_color
			if state.fuel_delta_laps < 0.0
			else config.digital_color)
		var fuel_delta_text := (
			"-%.2f" % absf(state.fuel_delta_laps)
			if state.fuel_delta_laps < 0.0
			else "%.2f" % state.fuel_delta_laps)
		_draw_competition_text(
			fuel_delta_text,
			Vector2(1078.0, 960.0),
			DELTA_VALUE_FONT_SIZE,
			fuel_delta_color,
			LIBRON_BOLD_FONT)
	else:
		_draw_competition_text("--.--", Vector2(1078.0, 963.0), DELTA_VALUE_FONT_SIZE, config.inactive_color, LIBRON_BOLD_FONT)
	_draw_competition_text("LAPS", Vector2(1305.0, 968.0), FUEL_LABEL_FONT_SIZE, config.dial_color)


func _draw_rotated_texture(
		texture: Texture2D,
		center: Vector2,
		dimensions: Vector2,
		rotation: float,
		color: Color) -> void:
	draw_set_transform(
		_design_origin + center * _design_scale_factor,
		rotation,
		Vector2.ONE * _design_scale_factor)
	draw_texture_rect(
		texture,
		Rect2(-dimensions * 0.5, dimensions),
		false,
		color)
	_restore_design_transform()


func _draw_competition_text(
	text: String,
	center: Vector2,
	font_size: int,
	color: Color,
	font: Font = LIBRON_REGULAR_FONT) -> void:
	var text_width := font.get_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size).x
	var baseline := Vector2(
		center.x - text_width * 0.5,
		center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	draw_set_transform(
		_design_origin,
		0.0,
		Vector2.ONE * _design_scale_factor)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
	_restore_design_transform()


func _draw_vertical_divider(position: Vector2, height: float) -> void:
	draw_texture_rect(
		DIVIDER_TEXTURE,
		Rect2(position, Vector2(4.0, height)),
		false,
		config.divider_color)


func _draw_horizontal_divider(position: Vector2, width: float) -> void:
	draw_set_transform(
		_design_origin + (position + Vector2(width * 0.5, 0.0)) * _design_scale_factor,
		PI * 0.5,
		Vector2.ONE * _design_scale_factor)
	draw_texture_rect(
		DIVIDER_TEXTURE,
		Rect2(Vector2(-2.0, -width * 0.5), Vector2(4.0, width)),
		false,
		config.divider_color)
	_restore_design_transform()


func _restore_design_transform() -> void:
	draw_set_transform(
		_design_origin,
		0.0,
		Vector2.ONE * _design_scale_factor)
