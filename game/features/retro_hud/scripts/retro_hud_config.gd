class_name RetroHudConfig
extends RefCounted

const DEFAULT_PATH := "res://features/retro_hud/config/retro_hud.json"

var style := "competition_cards_ribbon"
var card_width := 100.0
var card_height := 142.0
var card_gap := 12.0
var card_corner_radius := 10
var card_border_width := 2

var revolutions_per_minute_minimum := 0.0
var revolutions_per_minute_maximum := 19000.0
var revolutions_per_minute_redline := 18000.0
var ideal_shift_revolutions_per_minute := 17400.0
var urgent_shift_revolutions_per_minute := 17800.0
var revolutions_per_minute_segment_count := 20
var fuel_segment_count := 12
var fuel_alert_fraction := 0.05
var fuel_container_color := Color("#607e91")
var fuel_inactive_segment_color := Color("#343e46")
var fuel_active_segment_color := Color("#e3b23c")
var background_color := Color("#1e2429f2")
var dial_color := Color("#e9ece8")
var digital_color := Color("#e9ece8")
var inactive_color := Color("#607e91")
var redline_color := Color("#f0182d")
var inactive_redline_color := Color("#67202b")
var alert_color := Color("#f0182d")
var divider_color := Color("#607e91")
var thermal_cold_color := Color("#73b8ff")
var thermal_optimal_color := Color("#8fd36b")
var thermal_warm_color := Color("#e3b23c")
var thermal_hot_color := Color("#ff6b61")
var thermal_critical_color := Color("#d91f1f")
var pending_color := Color("#a8b5ba")
var label_color := Color("#a8b5ba")
var pedal_label_color := Color("#e9ece8")
var controls_background_color := Color("#1e2429f2")
var controls_border_color := Color("#607e91")
var throttle_color := Color("#8fd36b")
var brake_color := Color("#ff665c")
var steering_color := Color("#e3b23c")
var bar_background_color := Color("#293340")
var wheel_ring_color := Color("#ebf2ff")
var wheel_spoke_color := Color("#b3c2d9")
var wheel_hub_color := Color("#737f9c")
var best_lap_color := Color("#a6ff9e")
var map_outline_color := Color("#f8faf0fa")
var map_shadow_color := Color("#030508eb")
var map_start_color := Color("#47ff57")
var map_player_color := Color("#3380ff")
var map_player_outline_color := Color("#030514fa")
var display_scale := 1.0
var visible := true
var rpm_min := 0.0
var rpm_max := 19000.0
var rpm_redline := 18000.0
var speed_segments := 19
var peak_activation_rpm := 12000.0


static func load_from_json(path: String = DEFAULT_PATH) -> RetroHudConfig:
	var config := RetroHudConfig.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Retro HUD config missing: %s. Using defaults." % path)
		return config
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_warning("Retro HUD config is invalid: %s. Using defaults." % path)
		return config
	config._apply(parsed)
	return config


func apply(data: Dictionary) -> void:
	_apply(data)


func apply_powertrain_configuration(powertrain_configuration: Dictionary) -> void:
	var engine_limit := float(powertrain_configuration.get("max_rpm", 0.0))
	if not is_finite(engine_limit) or engine_limit <= revolutions_per_minute_minimum:
		return
	var threshold_scale := engine_limit / maxf(revolutions_per_minute_redline, 1.0)
	revolutions_per_minute_maximum = maxf(
		revolutions_per_minute_minimum + 1.0,
		engine_limit)
	ideal_shift_revolutions_per_minute *= threshold_scale
	urgent_shift_revolutions_per_minute *= threshold_scale
	revolutions_per_minute_redline = engine_limit
	rpm_min = revolutions_per_minute_minimum
	rpm_max = revolutions_per_minute_maximum
	rpm_redline = revolutions_per_minute_redline
	peak_activation_rpm = clampf(peak_activation_rpm * threshold_scale, rpm_min, rpm_max)


func _apply(data: Dictionary) -> void:
	style = str(data.get("style", style))
	card_width = maxf(float(data.get("card_width", card_width)), 40.0)
	card_height = maxf(float(data.get("card_height", card_height)), 40.0)
	card_gap = maxf(float(data.get("card_gap", card_gap)), 0.0)
	card_corner_radius = clampi(int(data.get("card_corner_radius", card_corner_radius)), 0, 32)
	card_border_width = clampi(int(data.get("card_border_width", card_border_width)), 0, 10)

	revolutions_per_minute_minimum = maxf(
		float(data.get("revolutions_per_minute_minimum", revolutions_per_minute_minimum)),
		0.0)
	revolutions_per_minute_maximum = maxf(
		float(data.get("revolutions_per_minute_maximum", revolutions_per_minute_maximum)),
		revolutions_per_minute_minimum + 1.0)
	revolutions_per_minute_redline = clampf(
		float(data.get("revolutions_per_minute_redline", revolutions_per_minute_redline)),
		revolutions_per_minute_minimum,
		revolutions_per_minute_maximum)
	ideal_shift_revolutions_per_minute = clampf(
		float(data.get("ideal_shift_revolutions_per_minute", ideal_shift_revolutions_per_minute)),
		revolutions_per_minute_minimum,
		revolutions_per_minute_redline)
	urgent_shift_revolutions_per_minute = clampf(
		float(data.get("urgent_shift_revolutions_per_minute", urgent_shift_revolutions_per_minute)),
		ideal_shift_revolutions_per_minute,
		revolutions_per_minute_redline)
	rpm_min = revolutions_per_minute_minimum
	rpm_max = revolutions_per_minute_maximum
	rpm_redline = revolutions_per_minute_redline
	peak_activation_rpm = clampf(peak_activation_rpm, rpm_min, rpm_max)
	speed_segments = clampi(speed_segments, 4, 19)
	revolutions_per_minute_segment_count = clampi(
		int(data.get("revolutions_per_minute_segment_count", revolutions_per_minute_segment_count)),
		2,
		40)
	fuel_segment_count = clampi(int(data.get("fuel_segment_count", fuel_segment_count)), 4, 24)
	fuel_alert_fraction = clampf(float(data.get("fuel_alert_fraction", fuel_alert_fraction)), 0.0, 1.0)
	display_scale = maxf(float(data.get("scale", display_scale)), 0.1)
	visible = bool(data.get("visible", visible))

	background_color = _color(data.get("background_color", "#1e2429f2"), background_color)
	fuel_container_color = _color(data.get("fuel_container_color", "#607e91"), fuel_container_color)
	fuel_inactive_segment_color = _color(data.get("fuel_inactive_segment_color", "#343e46"), fuel_inactive_segment_color)
	fuel_active_segment_color = _color(data.get("fuel_active_segment_color", "#e3b23c"), fuel_active_segment_color)
	dial_color = _color(data.get("dial_color", "#e9ece8"), dial_color)
	digital_color = _color(data.get("digital_color", "#e9ece8"), digital_color)
	inactive_color = _color(data.get("inactive_color", "#607e91"), inactive_color)
	redline_color = _color(data.get("redline_color", "#f0182d"), redline_color)
	inactive_redline_color = _color(data.get("inactive_redline_color", "#67202b"), inactive_redline_color)
	alert_color = _color(data.get("alert_color", "#f0182d"), alert_color)
	divider_color = _color(data.get("divider_color", "#607e91"), divider_color)
	thermal_cold_color = _color(data.get("thermal_cold_color", "#73b8ff"), thermal_cold_color)
	thermal_optimal_color = _color(data.get("thermal_optimal_color", "#8fd36b"), thermal_optimal_color)
	thermal_warm_color = _color(data.get("thermal_warm_color", "#e3b23c"), thermal_warm_color)
	thermal_hot_color = _color(data.get("thermal_hot_color", "#ff6b61"), thermal_hot_color)
	thermal_critical_color = _color(data.get("thermal_critical_color", "#d91f1f"), thermal_critical_color)
	pending_color = _color(data.get("pending_color", "#a8b5ba"), pending_color)
	label_color = _color(data.get("label_color", "#a8b5ba"), label_color)
	pedal_label_color = _color(data.get("pedal_label_color", "#e9ece8"), pedal_label_color)
	controls_background_color = _color(data.get("controls_background_color", "#1e2429f2"), controls_background_color)
	controls_border_color = _color(data.get("controls_border_color", "#607e91"), controls_border_color)
	throttle_color = _color(data.get("throttle_color", "#8fd36b"), throttle_color)
	brake_color = _color(data.get("brake_color", "#ff665c"), brake_color)
	steering_color = _color(data.get("steering_color", "#e3b23c"), steering_color)
	bar_background_color = _color(data.get("bar_background_color", "#293340"), bar_background_color)
	wheel_ring_color = _color(data.get("wheel_ring_color", "#ebf2ff"), wheel_ring_color)
	wheel_spoke_color = _color(data.get("wheel_spoke_color", "#b3c2d9"), wheel_spoke_color)
	wheel_hub_color = _color(data.get("wheel_hub_color", "#737f9c"), wheel_hub_color)
	best_lap_color = _color(data.get("best_lap_color", "#a6ff9e"), best_lap_color)
	map_outline_color = _color(data.get("map_outline_color", "#f8faf0fa"), map_outline_color)
	map_shadow_color = _color(data.get("map_shadow_color", "#030508eb"), map_shadow_color)
	map_start_color = _color(data.get("map_start_color", "#47ff57"), map_start_color)
	map_player_color = _color(data.get("map_player_color", "#3380ff"), map_player_color)
	map_player_outline_color = _color(data.get("map_player_outline_color", "#030514fa"), map_player_outline_color)


func _color(value: Variant, fallback: Color) -> Color:
	if value is String and Color.html_is_valid(value):
		return Color(value)
	return fallback
