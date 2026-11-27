class_name ShaderEnvironmentBus
extends RefCounted
## Central publisher for global scene shader parameters declared in project.godot [shader_globals].

static var _known_globals: Dictionary = {}


static func _has_global(param_name: StringName) -> bool:
	if not _known_globals.has(param_name):
		_known_globals[param_name] = ProjectSettings.has_setting("shader_globals/" + String(param_name))
	return bool(_known_globals[param_name])


static func _set_global(param_name: StringName, value: Variant) -> void:
	if _has_global(param_name):
		RenderingServer.global_shader_parameter_set(param_name, value)


static func update_lighting(
	sun_dir: Vector3,
	sun_color: Color,
	ambient_color: Color,
	haze_color: Color
) -> void:
	_set_global(&"rally_sun_dir", sun_dir)
	_set_global(&"rally_sun_color", Vector3(sun_color.r, sun_color.g, sun_color.b))
	_set_global(&"rally_ambient_color", Vector3(ambient_color.r, ambient_color.g, ambient_color.b))
	_set_global(&"rally_haze_color", Vector3(haze_color.r, haze_color.g, haze_color.b))


static func update_weather(wind_vec: Vector2, rain_intensity: float) -> void:
	_set_global(&"rally_wind_vec", wind_vec)
	_set_global(&"rally_rain_intensity", clampf(rain_intensity, 0.0, 1.0))


static func update_sky(
	horizon_color: Color,
	weather_mix: float,
	daylight_mix: float,
	twilight_yaw: float,
	yaw_b: float,
	tint_a: Vector3,
	tint_b: Vector3,
	tint_c: Vector3,
	enabled: bool = true
) -> void:
	_set_global(&"rally_sky_horizon", Vector3(horizon_color.r, horizon_color.g, horizon_color.b))
	_set_global(&"rally_sky_mix", Vector4(weather_mix, daylight_mix, twilight_yaw, yaw_b))
	_set_global(&"rally_sky_tint_a", tint_a)
	_set_global(&"rally_sky_tint_b", tint_b)
	_set_global(&"rally_sky_tint_c", tint_c)
	_set_global(&"rally_sky_enabled", 1.0 if enabled else 0.0)
