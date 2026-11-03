extends Node3D
## Single visual owner. Physics and the event clock remain authoritative.
const SHADER := preload("res://scripts/rally/rally_hybrid_sky.gdshader")
var environment := Environment.new()
var sun := DirectionalLight3D.new()
var moon := DirectionalLight3D.new()
var material := ShaderMaterial.new()
var current_time := 11.0
var minutes_per_day := 24.0
var game_time_enabled := false
var cumulus_coverage := 0.55
var wind_speed := 3.0
var wind_direction := 0.0
var climate: Dictionary = {}
var visual: Dictionary = {}
var cloud_offset := Vector2.ZERO
var _elapsed := 0.0
var update_count := 0

func _ready() -> void:
	material.shader = SHADER
	material.set_shader_parameter("clear_panorama", load("res://assets/weather/hybrid_sky/clear_panorama.png"))
	material.set_shader_parameter("overcast_panorama", load("res://assets/weather/hybrid_sky/overcast_panorama.png"))
	material.set_shader_parameter("cloud_density", load("res://assets/weather/hybrid_sky/cloud_density.png"))
	var sky := Sky.new()
	sky.sky_material = material
	# The sky is animated, but ambient/reflected lighting uses fixed colors.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.ambient_light_color = Color(0.65, 0.72, 0.82)
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.volumetric_fog_enabled = false
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_curve = 1.0
	environment.fog_sky_affect = 0.35
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	add_child(sun)
	add_child(moon)
	sun.directional_shadow_max_distance = 80.0
	moon.shadow_enabled = false
	update_visuals(0.0)

func apply_climate(next_climate: Dictionary, next_visual: Dictionary) -> void:
	climate = next_climate.duplicate()
	visual = next_visual

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.1:
		return
	var elapsed := _elapsed
	_elapsed = 0.0
	update_visuals(elapsed)

func update_visuals(delta: float) -> void:
	update_count += 1
	var angle := (current_time - 6.0) * TAU / 24.0
	var direction := Vector3(cos(angle), sin(angle), 0.25).normalized()
	var daylight := smoothstep(-0.12, 0.18, direction.y)
	var twilight := (1.0 - smoothstep(0.0, 0.32, absf(direction.y)))
	var cover := clampf(float(climate.get("cumulus_coverage", cumulus_coverage)), 0.0, 1.0)
	var overcast := smoothstep(0.35, 0.95, cover)
	var wind := float(climate.get("wind_m_s", wind_speed))
	var heading := deg_to_rad(float(climate.get("wind_direction_deg", rad_to_deg(wind_direction))))
	cloud_offset = (cloud_offset + Vector2(cos(heading), sin(heading)) * wind * delta * 0.00006).posmod(1.0)
	var clear_col: Array = visual.get("fog_color_clear", [0.64, 0.73, 0.82])
	var storm_col: Array = visual.get("fog_color_overcast", [0.46, 0.50, 0.55])
	var horizon := Color(float(clear_col[0]), float(clear_col[1]), float(clear_col[2])).lerp(Color(float(storm_col[0]), float(storm_col[1]), float(storm_col[2])), overcast)
	material.set_shader_parameter("coverage", cover)
	material.set_shader_parameter("daylight", daylight)
	material.set_shader_parameter("twilight", twilight)
	material.set_shader_parameter("sun_direction", direction)
	material.set_shader_parameter("horizon_color", horizon)
	material.set_shader_parameter("cloud_offset", cloud_offset)
	sun.position = direction
	sun.look_at(Vector3.ZERO, Vector3.UP)
	moon.position = -direction
	moon.look_at(Vector3.ZERO, Vector3.UP)
	sun.light_color = Color(1.0, 0.95, 0.84).lerp(Color(1.0, 0.68, 0.40), twilight)
	sun.light_energy = daylight * lerpf(0.95, 0.22, overcast)
	sun.shadow_enabled = daylight > 0.1 and cover < 0.85
	sun.shadow_opacity = 0.45
	moon.light_color = Color(0.46, 0.56, 0.76)
	moon.light_energy = (1.0 - daylight) * 0.08
	environment.ambient_light_energy = lerpf(0.06, lerpf(0.72, 0.52, overcast), daylight)
	environment.fog_light_color = horizon * lerpf(0.08, 1.0, daylight)
	var fog_weight := clampf(float(climate.get("fog_density", 0.0004)) / maxf(float(visual.get("fog_density_reference", 0.0045)), 0.00001), 0.0, 1.0)
	environment.fog_depth_end = lerpf(float(visual.get("fog_clear_end_m", 460.0)), float(visual.get("fog_storm_end_m", 175.0)), fog_weight)
	environment.fog_depth_begin = environment.fog_depth_end * float(visual.get("fog_start_fraction", 0.22))
