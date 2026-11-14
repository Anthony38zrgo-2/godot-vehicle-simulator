class_name RallyF1HeadUpDisplay
extends Control

const UI_FONT := preload("res://fonts/montserrat/Montserrat-Regular.ttf")
const PartialDeltaBannerScript := preload("res://scripts/rally/cmr2_partial_delta_banner.gd")

@export var vehicle_path: NodePath
@export var retro_hud_path: NodePath = NodePath("RetroHud")
@export var driving_controls_path: NodePath = NodePath("DrivingControls")

var vehicle: RallyEscortVehicle
var retro_hud: RetroHudDisplay
var driving_controls: Control
var partial_banner: Control
var telemetry_path: String = ""
var session_state: Dictionary = {}
var formula_panels: Control
var published: Dictionary = {}
var start_lights: Control
var competition_panel: Control
var hud_palette: RetroHudConfig


func _ready() -> void:
	formula_panels = preload("res://scripts/rally/formula_hud_panels.gd").new()
	formula_panels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(formula_panels)
	retro_hud = get_node_or_null(retro_hud_path) as RetroHudDisplay
	hud_palette = retro_hud.config if retro_hud != null else RetroHudConfig.new()
	driving_controls = get_node_or_null(driving_controls_path) as Control
	partial_banner = PartialDeltaBannerScript.new()
	partial_banner.name = "PartialDeltaBanner"
	add_child(partial_banner)
	competition_panel = preload("res://scripts/rally/rally_competition_panel.gd").new()
	competition_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(competition_panel)
	start_lights = preload("res://scripts/rally/rally_start_lights.gd").new()
	start_lights.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(start_lights)
	formula_panels.call("set_palette", hud_palette)
	if driving_controls != null:
		driving_controls.call("set_palette", hud_palette)
	var hud_theme := Theme.new()
	hud_theme.default_font = UI_FONT
	hud_theme.default_font_size = 18
	theme = hud_theme
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


func show_status(_message: String, _color: Color = Color.WHITE, _duration_seconds: float = 2.2) -> void:
	# Los mensajes centrales de estado fueron reemplazados por el delta centrado estilo CMR2.
	pass


func show_partial(index: int, delta_ms: Variant) -> void:
	if partial_banner == null:
		return
	partial_banner.call("show_delta", index, delta_ms)


func _process(_delta: float) -> void:
	if vehicle == null and not vehicle_path.is_empty():
		vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	if vehicle == null:
		return
	published = vehicle.get_presentation_snapshot()
	published["course"] = session_state.get("course", {})
	published["competition"] = session_state.get("competition", {})
	start_lights.call("present", session_state.get("start_sequence", {}))
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
		oil_pressure_bar_for_hud(oil),
		float(water.get("temperature_c", -1.0)),
		float(fuel.get("remaining_litres", -1.0)),
		float(fuel.get("capacity_litres", -1.0)),
		0.0,
		false,
		0.0,
		false,
		oil_pressure_color(oil),
		engine_color(water),
		steering,
		throttle,
		brake
	)


func update_thermal_readout() -> void:
	var tire_config: Dictionary = {}
	var surface_temp := {"ok": false, "text": "—"}
	if vehicle != null and "simulation" in vehicle and vehicle.simulation != null and vehicle.simulation.thermal_model != null:
		tire_config = vehicle.simulation.thermal_model.tire_config
		if vehicle.simulation.has_method("surface_temperature_for_hud"):
			surface_temp = vehicle.simulation.surface_temperature_for_hud()
	published["surface_temp"] = surface_temp
	var air_c: Variant = null
	if vehicle != null and vehicle.simulation != null:
		var weather = vehicle.simulation.weather_controller
		if weather != null and bool(weather.get("calendar_active")):
			air_c = weather.current_blend.get("air_c")
		elif vehicle.simulation.thermal_model != null:
			air_c = vehicle.simulation.thermal_model.ambient_temperature_c
	published["air_temp_c"] = air_c
	var eng: Dictionary = published.get("engine", {})
	var oil: Dictionary = eng.get("oil", {})
	var water: Dictionary = eng.get("water", {})
	published["hud_indicators"] = {
		"oil_bar": oil_pressure_bar_for_hud(oil),
		"oil_color": oil_pressure_color(oil),
		"water_color": engine_color(water),
	}
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
		elif retro_hud.has_method("is_nfsu2_analog_style") and bool(retro_hud.call("is_nfsu2_analog_style")):
			var dash_size: Vector2 = retro_hud.call("get_nfsu2_dash_size")
			retro_hud.size = dash_size
			retro_hud.position = Vector2(
				size.x - dash_size.x * factor - 24.0 * factor,
				size.y - dash_size.y * factor - 10.0 * factor
			)
			if driving_controls != null and not driving_controls.visible:
				driving_controls.visible = true
		elif retro_hud.has_method("is_cmr2_digital_style") and bool(retro_hud.call("is_cmr2_digital_style")):
			var dash_size: Vector2 = retro_hud.call("get_cmr2_dash_size")
			retro_hud.size = dash_size
			retro_hud.position = Vector2(
				size.x - dash_size.x * factor - 32.0 * factor,
				size.y - dash_size.y * factor - 20.0 * factor
			)
			if driving_controls != null and not driving_controls.visible:
				driving_controls.visible = true
		else:
			retro_hud.size = Vector2(541.35, 370.0125)
			retro_hud.position = Vector2(size.x - 541.35 * factor - 16.0 * factor, size.y - (370.0125 + 48.0) * factor)
			if driving_controls != null and not driving_controls.visible:
				driving_controls.visible = true


# El HUD muestra la presion de aceite (bar) en el hueco historico de OIL:
# el conductor real ve presion, no temperatura. -1 = sin dato (perfil sin oil_pressure).
func oil_pressure_bar_for_hud(oil: Dictionary) -> float:
	if float(oil.get("healthy_pressure_bar", 0.0)) <= 0.0 and float(oil.get("pressure_bar", 0.0)) <= 0.0:
		return -1.0
	return float(oil.get("pressure_bar", -1.0))


func oil_pressure_color(oil: Dictionary) -> Color:
	match str(oil.get("pressure_state", "ok")):
		"critical":
			return hud_palette.thermal_critical_color
		"low":
			return hud_palette.thermal_warm_color
	return hud_palette.thermal_optimal_color


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
	var factor := minf(size.x / 1920.0, size.y / 1080.0)
	driving_controls.scale = Vector2.ONE * factor
	driving_controls.position = Vector2(
		(size.x - driving_controls.custom_minimum_size.x * factor) * 0.5,
		size.y - driving_controls.custom_minimum_size.y * factor - 20.0 * factor
	)
	var steering_fraction := float(published.get("steering", 0.0))
	driving_controls.call("set_controls", steering_fraction, float(published.get("throttle", 0.0)), float(published.get("brake", 0.0)))
