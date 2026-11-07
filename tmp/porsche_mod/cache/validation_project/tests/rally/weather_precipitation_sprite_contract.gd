extends SceneTree

class TestManager:
	extends "res://scripts/rally/rally_event_manager.gd"
	func save() -> bool:
		return true

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func _initialize() -> void:
	call_deferred("run")


func precipitation_material(particles: GPUParticles3D, pass_index: int) -> ShaderMaterial:
	var mesh: Mesh = null
	match pass_index:
		1:
			mesh = particles.draw_pass_1
		2:
			mesh = particles.draw_pass_2
	if mesh == null:
		return null
	return mesh.surface_get_material(0) as ShaderMaterial


func force_weather(ctl, kind: String, precip_mm_h: float) -> void:
	ctl.current_blend = ctl.surface.state_for_zone(0)
	ctl.current_blend["precipitation_kind"] = kind
	ctl.current_blend["climate"]["precipitation_mm_h"] = precip_mm_h
	ctl.current_blend["climate"]["irradiance_w_m2"] = 90.0
	ctl.current_blend["climate"]["wind_m_s"] = 4.0
	ctl.current_blend["climate"]["wind_direction_deg"] = 90.0
	ctl.current_blend["water_mm"] = 4.0
	ctl.visual_state = ctl.current_blend.duplicate(true)


func run() -> void:
	var manager := TestManager.new()
	check(manager.begin_event({"seed": 42}), "event generates from JSON")
	if manager.weather_schedule.is_empty():
		quit(1)
		return
	var scene = load("res://scenes/rally/russia_stage1_ford_escort_rs2000.tscn").instantiate()
	scene.begin_event_session(manager, "russia_stage1")
	root.add_child(scene)
	current_scene = scene
	for i in 600:
		await process_frame
		if scene.session_ready:
			break
	check(scene.session_ready, "session ready")
	scene.set_physics_process(false)
	scene.set_process(false)
	scene.vehicle.freeze = true
	var ctl = scene.event_weather
	var tca = scene.weather_controller_node
	check(ctl.calendar_active, "calendar active")
	check(tca != null, "TCA controller present")
	if tca == null:
		quit(1)
		return

	force_weather(ctl, "rain", 6.0)
	ctl.apply_to_adapters(scene.weather_sky_node, tca, scene.terrain_wetness, 12.0)
	var rain = tca.particle_system as GPUParticles3D
	check(rain != null and rain.emitting, "rain precipitates")
	if rain != null:
		check(rain.draw_passes == 1, "each rain particle carries one raindrop")
		var rain_material := precipitation_material(rain, 1)
		check(rain_material != null, "rain material present")
		if rain_material != null:
			check(rain_material.shader.resource_path.ends_with("rally_weather_sprite.gdshader"), "rain shader")
			var rain_texture := rain_material.get_shader_parameter("particle_texture") as Texture2D
			check(rain_texture == ctl.RAIN_SPRITE, "rain uses the active sprite")
		check(rain.amount_ratio > 0.0 and rain.amount == 400, "rain intensity and CMR2 capacity")
		check(rain.get_node_or_null("RainFallSheet") == null, "CMR2 rain uses individual drops")

	force_weather(ctl, "snow", 8.0)
	ctl.apply_to_adapters(scene.weather_sky_node, tca, scene.terrain_wetness, 12.0)
	var snow = tca.particle_system as GPUParticles3D
	check(snow != null and snow != rain, "snow replaces the rain system")
	if snow != null:
		check(snow.draw_passes == 1, "snow uses one sprite pass")
		var snow_material := precipitation_material(snow, 1)
		check(snow_material != null, "snow material present")
		if snow_material != null:
			check(snow_material.shader.resource_path.ends_with("rally_weather_sprite.gdshader"), "snow shader")
			var snow_texture := snow_material.get_shader_parameter("particle_texture") as Texture2D
			check(snow_texture == ctl.SNOW_SPRITE, "snow uses the active sprite")
		var snow_quad := snow.draw_pass_1 as QuadMesh
		check(snow_quad != null and is_equal_approx(snow_quad.size.x, 0.24), "snow uses the configured size")
	await process_frame
	await process_frame
	check(not is_instance_valid(rain), "old rain system freed after the switch")

	force_weather(ctl, "rain", 6.0)
	ctl.apply_to_adapters(scene.weather_sky_node, tca, scene.terrain_wetness, 12.0)
	var rain_again = tca.particle_system as GPUParticles3D
	check(rain_again != null and rain_again != snow, "rain returns after snow")
	if rain_again != null:
		check(rain_again.draw_passes == 1, "rain returns with one drop pass")
	print("WEATHER_PRECIPITATION_SPRITE_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
