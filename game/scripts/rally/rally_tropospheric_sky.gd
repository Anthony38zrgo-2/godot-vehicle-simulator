extends Node3D
## Cubemap background and stage lighting driven by the event clock and local weather.
const SHADER := preload("res://scripts/rally/rally_tropospheric_sky.gdshader")
const SKY_DIR := "res://assets/weather/tropospheric/"
const CLEAR := preload("res://assets/weather/tropospheric/day_1.png")
const PRESETS_PATH := "res://data/weather/rally_weather_presets.json"
var variants := {"day": "day_1", "cloudy": "cloudy_1", "verycloudy": "verycloudy_4", "dusk": "dusk_3", "night": "night_2"}

func configure_event(rally_id: String, stage_id: String, date: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(JSON.stringify([rally_id, stage_id, date]))
	for group: String in ["day", "cloudy", "verycloudy", "dusk"]:
		variants[group] = "%s_%d" % [group, rng.randi_range(1, 6)]


var environment := Environment.new()
var sun := DirectionalLight3D.new()
var moon := DirectionalLight3D.new()
var material := ShaderMaterial.new()
var current_time := 11.0
var dreamcast_visual_mode := true
var exposure := 1.0
var climate: Dictionary = {}
var visual: Dictionary = {}
var _textures: Dictionary = {}
var _uniforms: Dictionary = {}
var _practice_target: Dictionary = {}
var _elapsed := 0.0

func _ready() -> void:
	_textures["day_1"] = CLEAR
	for sky_id: String in variants.values():
		var path := SKY_DIR + sky_id + ".png"
		var texture := load(path) as TextureLayered if ResourceLoader.exists(path) else null
		if texture == null:
			push_warning("Tropospheric sky missing %s; using day_1" % sky_id)
		_textures[sky_id] = texture if texture != null else CLEAR
	material.shader = SHADER
	var sky := Sky.new()
	sky.sky_material = material
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.ambient_light_color = Color(0.65, 0.72, 0.82)
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR if dreamcast_visual_mode else Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = exposure
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_curve = 1.0
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	add_child(sun)
	add_child(moon)
	sun.directional_shadow_max_distance = 60.0 if dreamcast_visual_mode else 80.0
	moon.shadow_enabled = false
	if visual.is_empty() and FileAccess.file_exists(PRESETS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRESETS_PATH))
		if parsed is Dictionary and (parsed as Dictionary).has("visual_response"):
			visual = ((parsed as Dictionary)["visual_response"] as Dictionary).duplicate()
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.08
	environment.adjustment_saturation = float(visual.get("saturation_clear", 1.25))
	update_visuals(0.0)

func apply_climate(next_climate: Dictionary, next_visual: Dictionary) -> void:
	_practice_target.clear()
	climate = next_climate.duplicate()
	if not next_visual.is_empty():
		visual = next_visual

func set_practice_weather(cover: float, fog: float) -> void:
	_practice_target = {"cumulus_coverage": cover, "fog_density": fog}
	if climate.is_empty():
		climate = _practice_target.duplicate()
		update_visuals(0.0)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.1:
		return
	update_visuals(_elapsed)
	_elapsed = 0.0

func update_visuals(delta: float) -> void:
	for key: String in _practice_target:
		var tau := 6.0 if key == "cumulus_coverage" else 4.0
		climate[key] = lerpf(float(climate[key]), float(_practice_target[key]), 1.0 - exp(-delta / tau))
	var angle := (current_time - 6.0) * TAU / 24.0
	var altitude := sin(angle)
	var morning := cos(angle) >= 0.0
	var daylight := smoothstep(-0.12, 0.18, altitude)
	var twilight := 1.0 - smoothstep(0.0, 0.32, absf(altitude))
	var cover := clampf(float(climate.get("cumulus_coverage", 0.2)), 0.0, 1.0)
	cover = maxf(cover, smoothstep(0.0, 12.0, float(climate.get("precipitation_mm_h", 0.0))) * 0.95)
	var overcast := smoothstep(0.35, 0.95, cover)
	var twilight_id: String = variants["day"] if morning else variants["dusk"]
	var twilight_yaw := 0.0 if morning else PI
	var twilight_tint := Vector3.ONE.lerp(Vector3(0.48, 0.58, 0.71), overcast)
	var day_mix := smoothstep(0.02, 0.36, altitude)
	if altitude < 0.02:
		_bind_sky(variants["night"], twilight_id, variants["night"], smoothstep(-0.25, 0.02, altitude), 1.0,
			0.0, twilight_yaw, Vector3.ONE.lerp(Vector3(0.15, 0.20, 0.28), overcast), twilight_tint, Vector3.ONE)
	else:
		var cloudy := cover >= 0.55
		var blend := smoothstep(0.55, 0.95, cover) if cloudy else smoothstep(0.15, 0.55, cover)
		_bind_sky(variants["cloudy"] if cloudy else variants["day"], variants["verycloudy"] if cloudy else variants["cloudy"], twilight_id,
			blend, day_mix, twilight_yaw, 0.0, Vector3.ONE, Vector3.ONE, twilight_tint)
	var clear_col: Array = visual.get("fog_color_clear", [0.64, 0.73, 0.82])
	var storm_col: Array = visual.get("fog_color_overcast", [0.46, 0.50, 0.55])
	var horizon := Color(float(clear_col[0]), float(clear_col[1]), float(clear_col[2])).lerp(
		Color(float(storm_col[0]), float(storm_col[1]), float(storm_col[2])), overcast)
	horizon = horizon.lerp(Color(0.58, 0.42, 0.36), twilight * daylight * (1.0 - overcast) * 0.55)
	horizon *= lerpf(0.10, 1.0, daylight)
	_set_uniform("horizon_color", horizon)
	var direction := Vector3(cos(angle), altitude, 0.16).normalized()
	sun.position = direction
	sun.look_at(Vector3.ZERO, Vector3.UP)
	moon.position = Vector3(1.0, 0.389, -0.729) # Moon painted on the +X face of night_2.
	moon.look_at(Vector3.ZERO, Vector3.UP)
	sun.light_color = Color(1.0, 0.95, 0.84).lerp(Color(1.0, 0.68, 0.40), twilight)
	sun.light_energy = daylight * lerpf(float(visual.get("sun_energy_clear", 0.95)),
		float(visual.get("sun_energy_overcast", 0.22)), overcast)
	sun.shadow_enabled = daylight > 0.1 and cover < 0.85
	sun.shadow_opacity = lerpf(float(visual.get("shadow_opacity_clear", 0.45)),
		float(visual.get("shadow_opacity_overcast", 0.15)), overcast)
	moon.light_color = Color(0.46, 0.56, 0.76)
	moon.light_energy = (1.0 - daylight) * lerpf(0.08, 0.025, overcast)
	environment.ambient_light_energy = lerpf(0.06, lerpf(float(visual.get("ambient_energy_clear", 0.72)),
		float(visual.get("ambient_energy_overcast", 0.52)), overcast), daylight)
	environment.fog_light_color = horizon
	var fog_weight := clampf(float(climate.get("fog_density", 0.0004)) / maxf(float(visual.get("fog_density_reference", 0.0045)), 0.00001), 0.0, 1.0)
	environment.fog_depth_end = lerpf(float(visual.get("fog_clear_end_m", 460.0)), float(visual.get("fog_storm_end_m", 175.0)), fog_weight)
	environment.fog_depth_begin = environment.fog_depth_end * float(visual.get("fog_start_fraction", 0.22))
	environment.fog_sky_affect = lerpf(float(visual.get("fog_sky_affect_clear", 0.05)),
		float(visual.get("fog_sky_affect_storm", 0.42)), fog_weight)
	if environment.adjustment_enabled:
		var sat_clear := float(visual.get("saturation_clear", 1.30))
		var sat_storm := float(visual.get("saturation_storm", 1.12))
		environment.adjustment_saturation = lerpf(sat_storm, sat_clear, daylight * (1.0 - overcast * 0.5))

func _bind_sky(a: String, b: String, c: String, weather_mix: float, daylight_mix: float,
		twilight_yaw: float, second_yaw: float, tint_a: Vector3, tint_b: Vector3, tint_c: Vector3) -> void:
	_set_uniform("sky_a", _textures[a])
	_set_uniform("sky_b", _textures[b])
	_set_uniform("sky_c", _textures[c])
	_set_uniform("weather_mix", weather_mix)
	_set_uniform("daylight_mix", daylight_mix)
	_set_uniform("twilight_yaw", twilight_yaw)
	_set_uniform("yaw_b", second_yaw)
	_set_uniform("tint_a", tint_a)
	_set_uniform("tint_b", tint_b)
	_set_uniform("tint_c", tint_c)

func _set_uniform(key: String, value: Variant) -> void:
	if _uniforms.get(key) != value:
		_uniforms[key] = value
		material.set_shader_parameter(key, value)
