extends Node3D
## Cubemap background and stage lighting driven by the event clock and local weather.
const SHADER := preload("res://scripts/rally/rally_tropospheric_sky.gdshader")
const SKY_DIR := "res://assets/weather/tropospheric/"
const CLEAR := preload("res://assets/weather/tropospheric/day_1.png")
const PRESETS_PATH := "res://data/weather/rally_weather_presets.json"
var variants := {"day": "day_1", "cloudy": "cloudy_1", "verycloudy": "verycloudy_4", "dusk": "dusk_3", "night": "night_2"}

var event_seed := 0
var solar_sunrise_hour := 7.0
# Original IDs remain stable; windows come from mapping-time-of-day.csv.
const WINDOWS := {
	"day_1": [11.0,14.0], "day_4": [11.0,15.0], "day_5": [10.0,14.0], "day_6": [10.0,16.0], "day_3": [15.0,17.0],
	"cloudy_1": [10.0,14.0], "cloudy_3": [11.0,15.0], "cloudy_4": [13.0,17.0], "cloudy_5": [10.0,16.0], "cloudy_6": [15.0,18.0], "cloudy_2": [17.0,19.0],
	"verycloudy_1": [11.0,15.0], "verycloudy_2": [10.0,15.0], "verycloudy_3": [10.0,17.0], "verycloudy_4": [10.0,17.0], "verycloudy_5": [10.0,17.0], "dusk_6": [10.0,17.0], "verycloudy_6": [16.0,19.0],
	"dusk_1": [17.0,19.0], "dusk_3": [17.0,19.0], "dusk_5": [17.0,19.0], "day_2": [18.0,19.5], "dusk_2": [18.0,19.5], "dusk_4": [18.0,19.5]
}

func configure_event(rally_id: String, stage_id: String, date: String) -> void:
	event_seed = hash(JSON.stringify([rally_id, stage_id, date]))
	# Across the CDI route the tropical daylight cycle is close to 06:00–18:00.
	solar_sunrise_hour = 6.0 if rally_id == "cdi" else 7.0

func _pick(ids: Array, hour: float) -> String:
	var eligible: Array = []
	var nearest: String = ids[0]
	var distance := INF
	for id: String in ids:
		var window: Array = WINDOWS[id]
		var d := maxf(float(window[0]) - hour, maxf(hour - float(window[1]), 0.0))
		if d < distance:
			distance = d
			nearest = id
		if hour >= float(window[0]) and hour < float(window[1]):
			eligible.append(id)
	return nearest if eligible.is_empty() else str(eligible[posmod(event_seed, eligible.size())])

func _select_hour(hour: float) -> void:
	variants["day"] = _pick(["day_1", "day_4", "day_5"], hour)
	variants["cloudy"] = _pick(["cloudy_1", "cloudy_3", "cloudy_4", "cloudy_5", "cloudy_6"], hour)
	variants["verycloudy"] = _pick(["verycloudy_4", "verycloudy_5", "dusk_6"], hour)
	variants["dusk"] = _pick(["day_2", "dusk_2"], hour)


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
	for sky_id: String in WINDOWS.keys() + ["night_2"]:
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
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = float(visual.get("saturation_clear", 1.08))
	update_visuals(0.0)

func apply_climate(next_climate: Dictionary, next_visual: Dictionary, precipitation_kind: String = "") -> void:
	_practice_target.clear()
	climate = next_climate.duplicate()
	if not precipitation_kind.is_empty():
		climate["precipitation_kind"] = precipitation_kind
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
	_select_hour(current_time)
	var angle := (current_time - solar_sunrise_hour) * TAU / 24.0
	var altitude := sin(angle)
	var morning := cos(angle) >= 0.0
	var daylight := smoothstep(-0.12, 0.18, altitude)
	var twilight := 1.0 - smoothstep(0.0, 0.32, absf(altitude))
	var cover := clampf(float(climate.get("cumulus_coverage", 0.2)), 0.0, 1.0)
	var cirrus := clampf(float(climate.get("cirrus_coverage", 0.0)), 0.0, 1.0)
	var precip := float(climate.get("precipitation_mm_h", 0.0))
	var fog_weight := clampf(float(climate.get("fog_density", 0.0004)) / maxf(float(visual.get("fog_density_reference", 0.0052)), 0.00001), 0.0, 1.0)
	var precipitation_cover := smoothstep(0.01, 0.40, precip) * lerpf(0.80, 0.97, smoothstep(0.4, 8.0, precip))
	cover = maxf(cover, maxf(precipitation_cover, fog_weight * 0.84))
	var overcast := smoothstep(0.28, 0.95, cover)
	var sun_clarity := clampf(1.0 - smoothstep(0.06, 0.90, cover) * 0.88 - cirrus * 0.14, 0.0, 1.0)
	var phase := str(climate.get("precipitation_kind", "rain"))
	var snow_light := phase == "snow" or phase == "mixed"
	var weather_tint := Vector3.ONE.lerp(
		Vector3(0.89, 0.93, 0.98) if snow_light else Vector3(0.66, 0.72, 0.80),
		smoothstep(0.05, 6.0, precip)
	)
	var twilight_id: String = "day_2" if morning else variants["dusk"]
	var twilight_yaw := 0.0 if morning else PI
	var twilight_tint := Vector3.ONE.lerp(Vector3(0.48, 0.58, 0.71), overcast) * weather_tint
	if altitude < 0.02:
		_bind_sky(variants["night"], twilight_id, variants["verycloudy"], smoothstep(-0.25, 0.02, altitude),
			1.0 - overcast * 0.85 * (1.0 - smoothstep(-0.25, 0.02, altitude)),
			0.0, twilight_yaw, Vector3.ONE, twilight_tint, Vector3(0.045, 0.06, 0.09))
	else:
		var cloudy := cover >= 0.55
		var blend := smoothstep(0.55, 0.84, cover) if cloudy else smoothstep(0.15, 0.55, cover)
		_bind_sky(variants["cloudy"] if cloudy else variants["day"], variants["verycloudy"] if cloudy else variants["cloudy"], twilight_id,
			blend, smoothstep(0.02, 0.35, altitude), twilight_yaw, 0.0, weather_tint, weather_tint, twilight_tint)
	var mist_boost := fog_weight * (1.0 - smoothstep(0.5, 4.0, precip))
	var clear_col: Array = visual.get("fog_color_clear", [0.68, 0.76, 0.86])
	var storm_col: Array = visual.get("fog_color_overcast", [0.57, 0.61, 0.66])
	var storm_horizon := Color(float(storm_col[0]), float(storm_col[1]), float(storm_col[2])).lerp(Color(0.67, 0.71, 0.74), mist_boost * 0.65)
	var horizon := Color(float(clear_col[0]), float(clear_col[1]), float(clear_col[2])).lerp(
		storm_horizon, maxf(overcast, fog_weight * 0.85))
	horizon = horizon.lerp(Color(0.58, 0.42, 0.36), twilight * daylight * (1.0 - overcast) * 0.55)
	horizon *= lerpf(0.10, 1.0, daylight)
	_set_uniform("horizon_color", horizon)
	var direction := Vector3(cos(angle), altitude, 0.16).normalized()
	sun.position = direction
	sun.look_at(Vector3.ZERO, Vector3.UP)
	moon.position = Vector3(1.0, 0.389, -0.729) # Moon painted on the +X face of night_2.
	moon.look_at(Vector3.ZERO, Vector3.UP)
	sun.light_color = Color(1.0, 0.94, 0.82).lerp(Color(1.0, 0.68, 0.40), twilight).lerp(Color(0.94, 0.96, 1.0), overcast * 0.65)
	sun.light_energy = daylight * lerpf(float(visual.get("sun_energy_overcast", 0.38)),
		float(visual.get("sun_energy_clear", 1.24)), sun_clarity)
	# Hysteresis prevents shadow_enabled pipeline thrashing when light rain starts (cover ~0.80-0.88).
	if daylight <= 0.1:
		if sun.shadow_enabled:
			sun.shadow_enabled = false
	elif sun.shadow_enabled:
		if cover >= 0.90:
			sun.shadow_enabled = false
	elif cover < 0.80:
		sun.shadow_enabled = true
	var shadow_fade := 1.0 - smoothstep(0.76, 0.90, cover)
	sun.shadow_opacity = lerpf(float(visual.get("shadow_opacity_clear", 0.45)),
		float(visual.get("shadow_opacity_overcast", 0.15)), overcast) * shadow_fade
	moon.light_color = Color(0.46, 0.56, 0.76)
	moon.light_energy = (1.0 - daylight) * lerpf(0.08, 0.025, overcast)
	var clear_amb := Color(0.68, 0.77, 0.90).lerp(Color(0.66, 0.65, 0.76), twilight * 0.55)
	environment.ambient_light_color = clear_amb.lerp(Color(0.71, 0.75, 0.80), overcast)
	environment.ambient_light_energy = lerpf(0.06, lerpf(float(visual.get("ambient_energy_clear", 0.70)),
		float(visual.get("ambient_energy_overcast", 0.86)), overcast), daylight)
	environment.fog_light_color = horizon
	environment.fog_depth_end = lerpf(float(visual.get("fog_clear_end_m", 420.0)), float(visual.get("fog_storm_end_m", 165.0)), fog_weight)
	environment.fog_depth_begin = environment.fog_depth_end * lerpf(float(visual.get("fog_start_fraction", 0.22)), 0.16, mist_boost)
	environment.fog_sky_affect = lerpf(float(visual.get("fog_sky_affect_clear", 0.08)),
		float(visual.get("fog_sky_affect_storm", 0.44)), maxf(fog_weight, overcast * 0.35))
	if environment.adjustment_enabled:
		var sat_clear := float(visual.get("saturation_clear", 1.08))
		var sat_storm := float(visual.get("saturation_storm", 0.92))
		environment.adjustment_saturation = lerpf(sat_storm, sat_clear, daylight * (1.0 - overcast))

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
