class_name RallyF1HeadUpDisplay
extends Control

const UI_FONT := preload("res://fonts/libron/Libron-Regular.ttf")

@export var vehicle_path: NodePath
@export var retro_hud_path: NodePath = NodePath("RetroHud")
@export var driving_controls_path: NodePath = NodePath("DrivingControls")
@export var aid_message_path: NodePath = NodePath("AidMessage")

var vehicle: RallyEscortVehicle
var retro_hud: RetroHudDisplay
var driving_controls: Control
var aid_message: Label
var telemetry_path: String = ""
var session_state: Dictionary = {}
var status_remaining_seconds: float = 0.0
var formula_panels: Control
var published: Dictionary = {}
var competition_panel: Control
var hud_palette: RetroHudConfig


func _ready() -> void:
	formula_panels = preload("res://scripts/rally/formula_hud_panels.gd").new()
	formula_panels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(formula_panels)
	retro_hud = get_node_or_null(retro_hud_path) as RetroHudDisplay
	hud_palette = retro_hud.config if retro_hud != null else RetroHudConfig.new()
	driving_controls = get_node_or_null(driving_controls_path) as Control
	aid_message = get_node_or_null(aid_message_path) as Label
	competition_panel = preload("res://scripts/rally/rally_competition_panel.gd").new()
	competition_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(competition_panel)
	formula_panels.call("set_palette", hud_palette)
	if driving_controls != null:
		driving_controls.call("set_palette", hud_palette)
	var hud_theme := Theme.new()
	hud_theme.default_font = UI_FONT
	hud_theme.default_font_size = 18
	theme = hud_theme
	if aid_message != null:
		aid_message.add_theme_color_override("font_color", hud_palette.digital_color)
		aid_message.add_theme_color_override("font_outline_color", hud_palette.background_color)
		aid_message.add_theme_color_override("font_shadow_color", hud_palette.background_color)
		aid_message.visible = false
	vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	if retro_hud != null and vehicle != null:
		retro_hud.set_powertrain_configuration({
			"max_rpm": vehicle.max_rpm,
			"idle_rpm": vehicle.idle_rpm,
			"vehicle_profile_path": vehicle.rally_profile_path
		})


func set_vehicle(target_vehicle: RallyEscortVehicle) -> void:
	vehicle = target_vehicle
	vehicle_path = vehicle.get_path()
	if retro_hud != null:
		retro_hud.set_powertrain_configuration({
			"max_rpm": vehicle.max_rpm,
			"idle_rpm": vehicle.idle_rpm,
			"vehicle_profile_path": vehicle.rally_profile_path
		})


func set_telemetry_path(path: String) -> void:
	telemetry_path = path


func set_session_state(state: Dictionary) -> void:
	session_state = state


func show_status(message: String, color: Color = Color.WHITE, duration_seconds: float = 2.2) -> void:
	if aid_message == null:
		return
	aid_message.text = message
	aid_message.modulate = status_color(color)
	aid_message.visible = true
	status_remaining_seconds = duration_seconds


func _process(delta: float) -> void:
	if status_remaining_seconds > 0.0:
		status_remaining_seconds = maxf(0.0, status_remaining_seconds - delta)
		if status_remaining_seconds <= 0.0 and aid_message != null:
			aid_message.visible = false
	if vehicle == null and not vehicle_path.is_empty():
		vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	if vehicle == null:
		return
	published = vehicle.get_presentation_snapshot()
	published["course"] = session_state.get("course", {})
	if competition_panel != null:
		competition_panel.call("present", session_state.get("competition", {}), size)
	update_retro_hud()
	update_driving_controls()
	update_thermal_readout()


func update_retro_hud() -> void:
	if retro_hud == null:
		return
	var speed_kilometres_per_hour := float(published.get("speed_kph", 0.0))
	var revolutions_per_minute := float(published.get("rpm", 0.0))
	var gear := int(published.get("gear", 0))
	var gear_label := "R" if gear < 0 else ("N" if gear == 0 else str(gear))
	var fuel: Dictionary = published.get("fuel", {})
	var engine: Dictionary = published.get("engine", {})
	var oil: Dictionary = engine.get("oil", {})
	var water: Dictionary = engine.get("water", {})
	var steering := float(published.get("steering", 0.0))
	var throttle := float(published.get("throttle", 0.0))
	var brake := float(published.get("brake", 0.0))
	retro_hud.set_competition_readout(
		speed_kilometres_per_hour,
		revolutions_per_minute,
		gear_label,
		float(oil.get("temperature_c", -1.0)),
		float(water.get("temperature_c", -1.0)),
		float(fuel.get("remaining_kg", -1.0)),
		float(fuel.get("capacity_kg", -1.0)),
		0.0,
		false,
		0.0,
		false,
		engine_color(oil),
		engine_color(water),
		steering,
		throttle,
		brake
	)


func update_thermal_readout() -> void:
	var tire_config: Dictionary = {}
	if vehicle != null and "simulation" in vehicle and vehicle.simulation != null and vehicle.simulation.thermal_model != null:
		tire_config = vehicle.simulation.thermal_model.tire_config
	if formula_panels != null:
		formula_panels.call("present", published, tire_config)
	var factor := minf(size.x / 1920.0, size.y / 1080.0)
	if retro_hud != null:
		retro_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
		retro_hud.scale = Vector2.ONE * factor
		if retro_hud.is_ribbon_style():
			retro_hud.position = Vector2.ZERO
			retro_hud.size = Vector2(size.x / maxf(factor, 0.01), size.y / maxf(factor, 0.01))
			if driving_controls != null and driving_controls.visible:
				driving_controls.visible = false
		else:
			retro_hud.size = Vector2(541.35, 370.0125)
			retro_hud.position = Vector2(size.x - 541.35 * factor - 16.0 * factor, size.y - (370.0125 + 48.0) * factor)
			if driving_controls != null and not driving_controls.visible:
				driving_controls.visible = true


func engine_color(node: Dictionary) -> Color:
	if not node.has("temperature_c") or not is_finite(float(node.get("temperature_c", NAN))):
		return hud_palette.pending_color
	var temperature := float(node.temperature_c)
	if node.get("optimal_min_c") != null and temperature < float(node.optimal_min_c):
		return hud_palette.thermal_cold_color
	if node.get("optimal_max_c") != null and temperature <= float(node.optimal_max_c):
		return hud_palette.thermal_optimal_color
	if node.get("derating_c") != null and temperature < float(node.derating_c):
		return hud_palette.thermal_warm_color
	if node.get("critical_c") != null and temperature < float(node.critical_c):
		return hud_palette.thermal_hot_color
	if node.get("critical_c") != null:
		return hud_palette.thermal_critical_color
	return hud_palette.pending_color


func status_color(source: Color) -> Color:
	if source.is_equal_approx(Color.WHITE):
		return hud_palette.digital_color
	if source.g > source.r * 1.3:
		return hud_palette.thermal_optimal_color
	if source.r > 0.75 and source.g > 0.35:
		return hud_palette.thermal_warm_color
	if source.r > 0.75:
		return hud_palette.thermal_hot_color
	return hud_palette.digital_color


func _temperature(value: Variant) -> String:
	if value == null or not (value is int or value is float) or not is_finite(float(value)):
		return "--"
	return str(roundi(float(value))) + "°C"


func update_driving_controls() -> void:
	if driving_controls == null or not driving_controls.visible:
		return
	var scale_factor := 1.1 * minf(size.x / 1920.0, size.y / 1080.0)
	driving_controls.scale = Vector2.ONE * scale_factor
	driving_controls.position = Vector2(
		(size.x - driving_controls.custom_minimum_size.x * scale_factor) * 0.5,
		size.y - driving_controls.custom_minimum_size.y * scale_factor - 18.0
	)
	var steering_fraction := float(published.get("steering", 0.0))
	driving_controls.call("set_controls", steering_fraction, float(published.get("throttle", 0.0)), float(published.get("brake", 0.0)))
