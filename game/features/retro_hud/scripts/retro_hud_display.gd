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
	if config == null:
		return Vector2(932.0, 142.0)
	return Vector2(704.0 + 16.0 + 212.0, config.card_height)


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
# MODULAR CARDS RIBBON IMPLEMENTATION
# ==============================================================================

func _draw_cards_ribbon() -> void:
	var center_w := 704.0
	var fuel_w := 212.0
	var card_h := config.card_height

	if size.x >= 960.0:
		var card_y := size.y - card_h - 24.0
		# 1. Center Driving Card: perfectly centered horizontally
		var center_x := roundf((size.x - center_w) * 0.5)
		var center_rect := Rect2(center_x, card_y, center_w, card_h)
		_draw_center_driving_card(center_rect)

		# 2. Fuel Card: sent more to the right with 32px right margin
		var fuel_x := roundf(size.x - fuel_w - 32.0)
		var fuel_rect := Rect2(fuel_x, card_y, fuel_w, card_h)
		_draw_fuel_and_temps_card(fuel_rect)
	else:
		# Standalone / compact preview fallback:
		var total_w := center_w + 16.0 + fuel_w
		var scale_factor := minf(size.x / total_w, size.y / card_h)
		var origin := (size - Vector2(total_w, card_h) * scale_factor) * 0.5
		draw_set_transform(origin, 0.0, Vector2.ONE * scale_factor)

		var center_rect := Rect2(0.0, 0.0, center_w, card_h)
		_draw_center_driving_card(center_rect)

		var fuel_rect := Rect2(center_w + 16.0, 0.0, fuel_w, card_h)
		_draw_fuel_and_temps_card(fuel_rect)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_card_background(rect: Rect2) -> void:
	draw_style_box(_card_style_box, rect)


func _draw_center_driving_card(rect: Rect2) -> void:
	# Single outer card frame encompassing all 5 driving telemetry sections
	_draw_card_background(rect)

	# Section 0: Steering (width 92px)
	var s0_rect := Rect2(rect.position.x, rect.position.y, 92.0, rect.size.y)
	_draw_card_steering(s0_rect)

	# Vertical divider line 1
	draw_line(
		Vector2(rect.position.x + 92.0, rect.position.y + 12.0),
		Vector2(rect.position.x + 92.0, rect.position.y + rect.size.y - 12.0),
		config.divider_color.darkened(0.35),
		1.0
	)

	# Section 1: Pedals (width 88px)
	var s1_rect := Rect2(rect.position.x + 92.0, rect.position.y, 88.0, rect.size.y)
	_draw_card_pedals(s1_rect)

	# Vertical divider line 2
	draw_line(
		Vector2(rect.position.x + 180.0, rect.position.y + 12.0),
		Vector2(rect.position.x + 180.0, rect.position.y + rect.size.y - 12.0),
		config.divider_color.darkened(0.35),
		1.0
	)

	# Section 2: Shift lights & Gear (width 96px)
	var s2_rect := Rect2(rect.position.x + 180.0, rect.position.y, 96.0, rect.size.y)
	_draw_card_gear(s2_rect)

	# Vertical divider line 3
	draw_line(
		Vector2(rect.position.x + 276.0, rect.position.y + 12.0),
		Vector2(rect.position.x + 276.0, rect.position.y + rect.size.y - 12.0),
		config.divider_color.darkened(0.35),
		1.0
	)

	# Section 3: Tachometer (width 320px) - 20 vertical bars (double horizontal size) and 5 numbers
	var s3_rect := Rect2(rect.position.x + 276.0, rect.position.y, 320.0, rect.size.y)
	_draw_card_tachometer(s3_rect)

	# Vertical divider line 4
	draw_line(
		Vector2(rect.position.x + 596.0, rect.position.y + 12.0),
		Vector2(rect.position.x + 596.0, rect.position.y + rect.size.y - 12.0),
		config.divider_color.darkened(0.35),
		1.0
	)

	# Section 4: RPM & Speed (width 108px)
	var s4_rect := Rect2(rect.position.x + 596.0, rect.position.y, 108.0, rect.size.y)
	_draw_card_speed_rpm(s4_rect)


func _get_tachometer_scale_milestones(rpm_min: float, rpm_max: float) -> Array[float]:
	var span := rpm_max - rpm_min
	if is_equal_approx(rpm_min, 1000.0) and is_equal_approx(rpm_max, 8000.0):
		var default_milestones: Array[float] = [1000.0, 2000.0, 4000.0, 6000.0, 8000.0]
		return default_milestones

	# General fallback to 5 nicely rounded milestones
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
		# Tramo 1 (Barras 0..3, bajo '1' y '2'): Base inferior plana, techo en rampa continua biselada
		var ramp_x_start := start_x
		var ramp_x_end := start_x + 3.0 * (bar_w + bar_gap) + bar_w
		var frac_l := clampf((bx - ramp_x_start) / (ramp_x_end - ramp_x_start), 0.0, 1.0)
		var frac_r := clampf((bx_r - ramp_x_start) / (ramp_x_end - ramp_x_start), 0.0, 1.0)
		y_bl = bar_bottom_y
		y_br = bar_bottom_y
		y_tl = bar_bottom_y - lerpf(16.0, bar_bottom_y - bar_top_y, frac_l)
		y_tr = bar_bottom_y - lerpf(16.0, bar_bottom_y - bar_top_y, frac_r)
	elif bar_index <= 6:
		# Tramo 2 (Barras 4..6): Techo horizontal en bar_top_y, base inferior en rampa continua biselada
		var trans_x_start := start_x + 4.0 * (bar_w + bar_gap)
		var trans_x_end := start_x + 6.0 * (bar_w + bar_gap) + bar_w
		var frac_l := clampf((bx - trans_x_start) / (trans_x_end - trans_x_start), 0.0, 1.0)
		var frac_r := clampf((bx_r - trans_x_start) / (trans_x_end - trans_x_start), 0.0, 1.0)
		y_tl = bar_top_y
		y_tr = bar_top_y
		y_bl = lerpf(bar_bottom_y, bar_top_y + meseta_h, frac_l)
		y_br = lerpf(bar_bottom_y, bar_top_y + meseta_h, frac_r)
	else:
		# Tramo 3 (Barras 7..19, bajo '4', '6' y '8'): Meseta horizontal superior suspendida
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


func _draw_card_tachometer(rect: Rect2) -> void:
	var vehicle_max := get_vehicle_max_rpm()
	var vehicle_idle := get_vehicle_idle_rpm()
	var current_rpm := maxf(state.engine_revolutions_per_minute, 0.0)

	# Competition Scale (Option 3):
	# Starts at idle rounded down to the nearest thousand (min 1000.0)
	# Ends at vehicle max rounded up to the nearest thousand (e.g. 7500 -> 8000.0)
	var rpm_min := maxf(1000.0, floorf(vehicle_idle / 1000.0) * 1000.0)
	var rpm_max := maxf(rpm_min + 3000.0, ceilf(vehicle_max / 1000.0) * 1000.0)
	var rpm_range := rpm_max - rpm_min
	var total_bar_count := 20
	var rpm_per_bar := rpm_range / float(total_bar_count)

	var redline_rpm := vehicle_max
	var ideal_shift_rpm := minf(config.ideal_shift_revolutions_per_minute, redline_rpm * 0.88)
	var urgent_shift_rpm := minf(config.urgent_shift_revolutions_per_minute, redline_rpm * 0.97)
	var urgent_shift := current_rpm >= urgent_shift_rpm

	# Top label: "RPM"
	_draw_card_text("RPM", Vector2(rect.position.x, rect.position.y + 20.0), rect.size.x, 12, config.label_color, LIBRON_BOLD_FONT)

	# Bar and Number dimensions (20 bars, 12px width, 3px gap -> 297px total)
	var bar_w := 12.0
	var bar_gap := 3.0
	var total_bars_w := float(total_bar_count) * bar_w + float(total_bar_count - 1) * bar_gap  # 297.0px
	var start_x := rect.position.x + (rect.size.x - total_bars_w) * 0.5

	var max_bar_h := 50.0
	var bar_top_y := rect.position.y + 54.0
	var bar_bottom_y := bar_top_y + max_bar_h
	var meseta_h := 26.0
	var num_baseline_y := rect.position.y + 44.0

	var bar_0_center_x := start_x + bar_w * 0.5
	var bar_last_center_x := start_x + float(total_bar_count - 1) * (bar_w + bar_gap) + bar_w * 0.5

	# 1. Draw 5 numbers: the first digits of the RPM (e.g. 4 -> 4000)
	# Milestones for 1000-8000: [1, 2, 4, 6, 8]
	var milestones := _get_tachometer_scale_milestones(rpm_min, rpm_max)
	for m_rpm: float in milestones:
		var num_val := roundi(m_rpm / 1000.0)
		var num_text := str(num_val)

		var fraction := clampf((m_rpm - rpm_min) / rpm_range, 0.0, 1.0)
		var num_center_x: float = lerpf(bar_0_center_x, bar_last_center_x, fraction)

		var is_milestone_active := current_rpm >= m_rpm
		var num_color := config.inactive_color.darkened(0.1)
		if is_milestone_active:
			if urgent_shift or m_rpm >= urgent_shift_rpm:
				num_color = config.alert_color
			elif m_rpm >= ideal_shift_rpm:
				num_color = config.thermal_warm_color
			else:
				num_color = config.digital_color

		draw_string(LIBRON_BOLD_FONT, Vector2(num_center_x - 16.0, num_baseline_y), num_text, HORIZONTAL_ALIGNMENT_CENTER, 32.0, 14, num_color)

	# 2. Draw 20 vertical bars with Option 4 (Continuous Slanted Chamfer & Anti-Aliased Edges):
	# White below optimal shift, Yellow for optimal shift, Red for limiter
	for i in total_bar_count:
		var bar_pts := _get_tachometer_bar_polygon(i, start_x, bar_w, bar_gap, bar_top_y, bar_bottom_y, meseta_h)
		var bar_outline := PackedVector2Array([bar_pts[0], bar_pts[1], bar_pts[2], bar_pts[3], bar_pts[0]])
		var bar_start_rpm := rpm_min + float(i) * rpm_per_bar
		var bar_target_rpm := bar_start_rpm + rpm_per_bar

		# Dark background track for each bar
		draw_colored_polygon(bar_pts, config.bar_background_color)
		draw_polyline(bar_outline, config.divider_color.darkened(0.55), 1.0, true)

		# Bar activation threshold: active if engine rpm reaches this bar's range
		var is_bar_active := current_rpm >= bar_start_rpm

		if is_bar_active:
			var bar_color: Color
			if urgent_shift:
				bar_color = config.alert_color
			elif bar_target_rpm >= urgent_shift_rpm:
				bar_color = config.alert_color
			elif bar_target_rpm >= ideal_shift_rpm:
				bar_color = config.thermal_warm_color
			else:
				bar_color = config.digital_color

			draw_colored_polygon(bar_pts, bar_color)
			draw_polyline(bar_outline, bar_color.lightened(0.2), 1.0, true)

	# Bottom label: "x1000"
	_draw_card_text("x1000", Vector2(rect.position.x, rect.position.y + 124.0), rect.size.x, 11, config.label_color, LIBRON_BOLD_FONT)


func _draw_card_steering(rect: Rect2) -> void:
	var center := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.40)
	var rim_radius := rect.size.x * 0.28
	var steering_fraction := clampf(state.steering, -1.0, 1.0)
	var wheel_rotation := -steering_fraction * PI * 0.75

	# Outer rim
	draw_arc(center, rim_radius, 0.0, TAU, 48, config.wheel_ring_color, 2.5, true)

	# 3 Spokes: top (at -PI*0.5) and two lower spokes at 35° and 145° from bottom
	var spoke_angles: Array[float] = [-PI * 0.5, PI * 0.22, PI * 0.78]
	for i in spoke_angles.size():
		var angle: float = spoke_angles[i] + wheel_rotation
		var direction := Vector2(cos(angle), sin(angle))
		var is_top_spoke := (i == 0)
		var spoke_color := (config.steering_color if absf(steering_fraction) > 0.02 else config.wheel_spoke_color) if is_top_spoke else config.wheel_spoke_color
		draw_line(center + direction * 5.0, center + direction * (rim_radius - 1.5), spoke_color, 2.5, true)

	# Center hub
	draw_circle(center, 5.5, config.wheel_hub_color, true, -1.0, true)

	# Angle text below
	var angle_deg := roundi(absf(steering_fraction) * 32.0)
	var angle_text := str(angle_deg) + "°"
	var text_color := config.steering_color if absf(steering_fraction) > 0.02 else config.digital_color
	_draw_card_text(angle_text, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.85), rect.size.x, 24, text_color, LIBRON_BOLD_FONT)


func _draw_card_pedals(rect: Rect2) -> void:
	var bar_width := 22.0
	var bar_height := rect.size.y * 0.58
	var bar_y := rect.position.y + 14.0
	var left_x := rect.position.x + rect.size.x * 0.32 - bar_width * 0.5
	var right_x := rect.position.x + rect.size.x * 0.68 - bar_width * 0.5

	# Throttle pedal
	var throttle_val := clampf(state.throttle, 0.0, 1.0)
	var throttle_track := Rect2(left_x, bar_y, bar_width, bar_height)
	draw_rect(throttle_track, config.bar_background_color)
	if throttle_val > 0.001:
		var fill_h := bar_height * throttle_val
		draw_rect(Rect2(left_x, bar_y + bar_height - fill_h, bar_width, fill_h), config.throttle_color)

	# Brake pedal
	var brake_val := clampf(state.brake, 0.0, 1.0)
	var brake_track := Rect2(right_x, bar_y, bar_width, bar_height)
	draw_rect(brake_track, config.bar_background_color)
	if brake_val > 0.001:
		var fill_h := bar_height * brake_val
		draw_rect(Rect2(right_x, bar_y + bar_height - fill_h, bar_width, fill_h), config.brake_color)

	# Labels T & B
	var label_y := rect.position.y + rect.size.y * 0.88
	_draw_card_text("T", Vector2(left_x - 6.0, label_y), bar_width + 12.0, 20, config.pedal_label_color, LIBRON_BOLD_FONT)
	_draw_card_text("B", Vector2(right_x - 6.0, label_y), bar_width + 12.0, 20, config.pedal_label_color, LIBRON_BOLD_FONT)


func _draw_card_gear(rect: Rect2) -> void:
	var light_radius := 6.5
	var light_y := rect.position.y + 22.0
	var left_center := Vector2(rect.position.x + rect.size.x * 0.38, light_y)
	var right_center := Vector2(rect.position.x + rect.size.x * 0.62, light_y)

	var ideal_shift := state.engine_revolutions_per_minute >= config.ideal_shift_revolutions_per_minute
	var urgent_shift := state.engine_revolutions_per_minute >= config.urgent_shift_revolutions_per_minute

	var left_color := config.dial_color if ideal_shift else config.inactive_color.darkened(0.25)
	var right_color := config.alert_color if urgent_shift else config.inactive_redline_color.darkened(0.25)

	draw_circle(left_center, light_radius, left_color)
	draw_circle(right_center, light_radius, right_color)

	# Large Gear Indicator
	var gear_color := config.alert_color if urgent_shift else config.digital_color
	var gear_y := rect.position.y + rect.size.y * 0.84
	_draw_card_text(state.gear_label, Vector2(rect.position.x, gear_y), rect.size.x, 66, gear_color, LIBRON_BOLD_FONT)


func _draw_card_speed_rpm(rect: Rect2) -> void:
	var urgent_shift := state.engine_revolutions_per_minute >= config.urgent_shift_revolutions_per_minute
	var rpm_color := config.alert_color if urgent_shift else config.digital_color
	var rpm_val := roundi(maxf(state.engine_revolutions_per_minute, 0.0))
	var rpm_text := str(rpm_val) + " rpm"

	# Top: RPM
	_draw_card_text(rpm_text, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.36), rect.size.x, 17, rpm_color, LIBRON_BOLD_FONT)

	# Middle divider line
	var divider_y := rect.position.y + rect.size.y * 0.50
	draw_line(
		Vector2(rect.position.x + 16.0, divider_y),
		Vector2(rect.position.x + rect.size.x - 16.0, divider_y),
		config.divider_color,
		1.5
	)

	# Bottom: Speed
	var speed_val := roundi(maxf(state.speed_kilometers_per_hour, 0.0))
	var speed_text := str(speed_val) + " km/h"
	_draw_card_text(speed_text, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.82), rect.size.x, 17, config.digital_color, LIBRON_BOLD_FONT)


func _draw_fuel_and_temps_card(rect: Rect2) -> void:
	# Single outer card frame for the Fuel & Temps module
	_draw_card_background(rect)

	# =========================================================================
	# COLUMN 1: VERTICAL FUEL GAUGE BAR WITH F-U-E-L
	# =========================================================================
	var bar_rect := Rect2(rect.position.x + 12.0, rect.position.y + 14.0, 32.0, 114.0)
	var fuel_frac := 0.0
	if state.fuel_capacity_kg > 0.0 and state.fuel_remaining_kg >= 0.0:
		fuel_frac = clampf(state.fuel_remaining_kg / state.fuel_capacity_kg, 0.0, 1.0)

	var spent_h := roundf(bar_rect.size.y * (1.0 - fuel_frac))
	var rem_h := bar_rect.size.y - spent_h

	# 1a. Upper portion (consumed/spent): dark blue background
	if spent_h > 0.5:
		draw_rect(Rect2(bar_rect.position.x, bar_rect.position.y, bar_rect.size.x, spent_h), config.bar_background_color.darkened(0.2))

	# 1b. Lower portion (remaining fuel): light steel, warning yellow, or alert red
	if rem_h > 0.5:
		var fuel_color := config.alert_color if fuel_frac <= config.fuel_alert_fraction else (
			config.thermal_warm_color if fuel_frac <= 0.15 else config.divider_color)
		draw_rect(Rect2(bar_rect.position.x, bar_rect.position.y + spent_h, bar_rect.size.x, rem_h), fuel_color)

	# Border around the vertical bar
	draw_rect(bar_rect, config.divider_color.darkened(0.25), false, 1.5)

	# Vertical letters F - U - E - L in crisp white
	var letters := ["F", "U", "E", "L"]
	for l in 4:
		var ly := bar_rect.position.y + 24.0 + l * 26.0
		draw_string(LIBRON_BOLD_FONT, Vector2(bar_rect.position.x, ly), letters[l], HORIZONTAL_ALIGNMENT_CENTER, bar_rect.size.x, 16, config.dial_color)

	# Vertical divider line between Column 1 and Column 2
	draw_line(
		Vector2(rect.position.x + 55.0, rect.position.y + 12.0),
		Vector2(rect.position.x + 55.0, rect.position.y + 130.0),
		config.divider_color.darkened(0.3),
		1.0
	)

	# =========================================================================
	# COLUMN 2: FUEL LITRES & DELTA
	# =========================================================================
	var col2_x := rect.position.x + 57.0
	var col2_w := 74.0

	# Top row: Remaining Fuel (e.g. 20 L)
	var fuel_text := str(roundi(state.fuel_remaining_kg)) + " L" if state.fuel_remaining_kg >= 0.0 else "-- L"
	var fuel_text_col := config.alert_color if fuel_frac <= config.fuel_alert_fraction else (
		config.thermal_warm_color if fuel_frac <= 0.15 else config.digital_color)
	draw_string(LIBRON_BOLD_FONT, Vector2(col2_x, rect.position.y + 44.0), fuel_text, HORIZONTAL_ALIGNMENT_CENTER, col2_w, 18, fuel_text_col)

	# Horizontal divider in Column 2
	draw_line(
		Vector2(col2_x + 6.0, rect.position.y + 71.0),
		Vector2(col2_x + col2_w - 6.0, rect.position.y + 71.0),
		config.divider_color,
		1.0
	)

	# Bottom row: DELTA & Value
	draw_string(LIBRON_BOLD_FONT, Vector2(col2_x, rect.position.y + 92.0), "DELTA", HORIZONTAL_ALIGNMENT_CENTER, col2_w, 12, config.label_color)
	var delta_text := ("+%.1f" % state.fuel_delta_laps) if state.fuel_delta_laps >= 0.0 else ("-%.1f" % absf(state.fuel_delta_laps))
	var delta_col := config.thermal_optimal_color if state.fuel_delta_laps >= 0.0 else config.alert_color
	if not state.has_fuel_delta:
		delta_text = "+0.0"
		delta_col = config.digital_color
	draw_string(LIBRON_BOLD_FONT, Vector2(col2_x, rect.position.y + 116.0), delta_text, HORIZONTAL_ALIGNMENT_CENTER, col2_w, 16, delta_col)

	# Vertical divider line between Column 2 and Column 3
	draw_line(
		Vector2(rect.position.x + 133.0, rect.position.y + 12.0),
		Vector2(rect.position.x + 133.0, rect.position.y + 130.0),
		config.divider_color.darkened(0.3),
		1.0
	)

	# =========================================================================
	# COLUMN 3: ENGINE TEMPERATURES (OIL & WATER)
	# =========================================================================
	var col3_x := rect.position.x + 135.0
	var col3_w := 73.0

	# Top row: OIL & Temperature
	draw_string(LIBRON_BOLD_FONT, Vector2(col3_x, rect.position.y + 32.0), "OIL", HORIZONTAL_ALIGNMENT_CENTER, col3_w, 13, config.label_color)
	var oil_val := str(roundi(state.oil_temperature_celsius)) + "°C" if state.oil_temperature_celsius >= 0.0 else "--°C"
	var oil_col := state.oil_temperature_color if state.oil_temperature_color != Color.WHITE else config.digital_color
	draw_string(LIBRON_BOLD_FONT, Vector2(col3_x, rect.position.y + 54.0), oil_val, HORIZONTAL_ALIGNMENT_CENTER, col3_w, 16, oil_col)

	# Horizontal divider in Column 3
	draw_line(
		Vector2(col3_x + 6.0, rect.position.y + 71.0),
		Vector2(col3_x + col3_w - 6.0, rect.position.y + 71.0),
		config.divider_color,
		1.0
	)

	# Bottom row: WATER & Temperature
	draw_string(LIBRON_BOLD_FONT, Vector2(col3_x, rect.position.y + 92.0), "WATER", HORIZONTAL_ALIGNMENT_CENTER, col3_w, 13, config.label_color)
	var water_val := str(roundi(state.water_temperature_celsius)) + "°C" if state.water_temperature_celsius >= 0.0 else "--°C"
	var water_col := state.water_temperature_color if state.water_temperature_color != Color.WHITE else config.digital_color
	draw_string(LIBRON_BOLD_FONT, Vector2(col3_x, rect.position.y + 116.0), water_val, HORIZONTAL_ALIGNMENT_CENTER, col3_w, 16, water_col)


func _draw_card_text(
		value: String,
		pos: Vector2,
		width: float,
		font_size: int,
		color: Color,
		font: Font = LIBRON_BOLD_FONT) -> void:
	draw_string(font, pos, value, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)


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
	_draw_competition_text("OIL TEMP", Vector2(1257.0, 123.0), TEMPERATURE_LABEL_FONT_SIZE, config.dial_color)
	_draw_temperature_value(state.oil_temperature_celsius, state.oil_temperature_color, Vector2(1268.0, 203.0))
	_draw_competition_text("°C", Vector2(1370.0, 204.0), TEMPERATURE_LABEL_FONT_SIZE, config.dial_color)

	_draw_horizontal_divider(Vector2(1164.0, 264.0), 224.0)

	_draw_competition_text("WATER TEMP", Vector2(1257.0, 304.0), TEMPERATURE_LABEL_FONT_SIZE, config.dial_color)
	_draw_temperature_value(state.water_temperature_celsius, state.water_temperature_color, Vector2(1268.0, 385.0))
	_draw_competition_text("°C", Vector2(1370.0, 386.0), TEMPERATURE_LABEL_FONT_SIZE, config.dial_color)


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
			"%.1f" % state.fuel_remaining_kg,
			Vector2(292.0, 960.0),
			FUEL_VALUE_FONT_SIZE,
			fuel_color,
			LIBRON_BOLD_FONT)
	_draw_competition_text("KG", Vector2(408.0, 968.0), FUEL_LABEL_FONT_SIZE, config.dial_color)

	if state.has_average_consumption:
		_draw_competition_text(
			"%.2f" % state.average_consumption_kg_per_lap,
			Vector2(725.0, 960.0),
			FUEL_VALUE_FONT_SIZE,
			config.digital_color,
			LIBRON_BOLD_FONT)
	else:
		_draw_competition_text("--.--", Vector2(724.0, 963.0), FUEL_VALUE_FONT_SIZE, config.inactive_color, LIBRON_BOLD_FONT)
	_draw_competition_text("KG/LAP", Vector2(866.0, 968.0), FUEL_LABEL_FONT_SIZE, config.dial_color)

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
