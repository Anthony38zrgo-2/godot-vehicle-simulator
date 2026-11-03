class_name RallyVehicleVFX
extends Node3D

## Presentation only: reuses the four existing wheel casts and Jolt contacts.
const TEXTURES := "res://assets/vfx/brackeys/particles/alpha/"
const PARTICLE_SHADER = preload("res://scripts/rally/rally_vehicle_vfx.gdshader")
const SURFACES := {
	"gravel": { "color": Color(0.56, 0.46, 0.32), "dust": 0.60, "chips": 0.32 },
	"dirt": { "color": Color(0.40, 0.29, 0.18), "dust": 0.70, "chips": 0.24 },
	"sand": { "color": Color(0.72, 0.61, 0.40), "dust": 0.85, "chips": 0.16 },
	"grass": { "color": Color(0.32, 0.36, 0.15), "dust": 0.12, "chips": 0.40 },
	"road": { "color": Color(0.70, 0.73, 0.76), "dust": 0.0, "chips": 0.0 },
	"asphalt": { "color": Color(0.70, 0.73, 0.76), "dust": 0.0, "chips": 0.0 },
	"tarmac": { "color": Color(0.70, 0.73, 0.76), "dust": 0.0, "chips": 0.0 },
}

@export_range(0.0, 1.5, 0.025) var intensity: float = 0.975
@export var enabled: bool = true

var vehicle: RallyEscortVehicle
var wheel_cores: Array[GPUParticles3D] = [] # Núcleo denso y oscuro (Volumen)
var wheel_plumes: Array[GPUParticles3D] = [] # Estela amplia y suave
var wheel_chips: Array[GPUParticles3D] = []
var impact_pool: Array[GPUParticles3D] = []
var impact_busy: Array[float] = []
var impact_cooldown: float = 0.0
var wetness_node: Node
var generation: int = -1
var last_position := Vector3.ZERO
var emitted_impacts: int = 0
var wetness_lookup_cooldown: float = 0.0
var particle_materials: Array[ShaderMaterial] = []
var steam_emitter: GPUParticles3D
var steam_time: float = 0.0
var current_steam_strength: float = 0.0
var camera_rig: Node = null


func _ready() -> void:
	vehicle = get_parent() as RallyEscortVehicle
	if vehicle == null:
		set_physics_process(false)
		return
	for i in 4:
		# Doble capa por rueda para dar volumen real estilo CMR 2004
		wheel_cores.append(
			make_emitter(
				"WheelCore%d" % i,
				"smoke_03_a.png",
				40,
				0.85,
				Vector2(0.45, 0.90),
				false,
				false,
				true,
			)
		)
		wheel_plumes.append(
			make_emitter(
				"WheelPlume%d" % i,
				"smoke_01_a.png",
				56,
				1.60,
				Vector2(0.85, 1.65),
				false,
				false,
				false,
			)
		)
		wheel_chips.append(
			make_emitter(
				"WheelDebris%d" % i,
				"dirt_02_a.png",
				24,
				0.55,
				Vector2(0.07, 0.16),
				false,
				true,
				false,
			)
		)
	for i in 6:
		impact_pool.append(
			make_emitter(
				"Impact%d" % i,
				"dirt_02_a.png",
				36,
				0.65,
				Vector2(0.10, 0.24),
				true,
				true,
				false,
			)
		)
		impact_busy.append(0.0)
	steam_emitter = make_steam_emitter()
	last_position = vehicle.global_position
	print("RALLY_VFX_READY volumetric_layers=active intensity=", intensity)


func make_emitter(
	label: String,
	texture_name: String,
	count: int,
	seconds: float,
	sizes: Vector2,
	burst: bool,
	debris: bool = false,
	is_core: bool = false,
) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = label
	emitter.emitting = false
	emitter.amount = count
	emitter.lifetime = seconds
	emitter.one_shot = burst
	emitter.explosiveness = 1.0 if burst else 0.0
	emitter.local_coords = false
	emitter.visibility_aabb = AABB(Vector3(-12, -6, -12), Vector3(24, 14, 24))
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.12, 0.05, 0.12)
	process.direction = Vector3.UP
	process.spread = 35.0 if is_core else 55.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 1.8 if debris else (0.8 if is_core else 1.2)
	process.gravity = Vector3(0, -5.5, 0) if debris else Vector3(0, 0.35, 0)
	process.scale_min = sizes.x
	process.scale_max = sizes.y
	process.angle_min = -180.0
	process.angle_max = 180.0

	# Curva de escala para que la partícula nazca pequeña y se expanda (efecto volumétrico clásico)
	var curve := Curve.new()
	curve.max_value = 1.8
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.3, 0.8))
	curve.add_point(Vector2(1.0, 1.6))
	var curve_texture := CurveTexture.new()
	curve_texture.curve = curve
	process.scale_curve = curve_texture

	var gradient := Gradient.new()
	if debris:
		gradient.set_color(0, Color(1, 1, 1, 0.65))
		gradient.set_color(1, Color(1, 1, 1, 0))
	elif is_core:
		# El núcleo es más denso, opaco y con un tinte más oscuro para generar contraste de profundidad
		gradient.set_color(0, Color(1, 1, 1, 0.75))
		gradient.add_point(0.2, Color(1, 1, 1, 0.55))
		gradient.set_color(1, Color(1, 1, 1, 0))
	else:
		# El penacho exterior es más difuso y suave
		gradient.set_color(0, Color(1, 1, 1, 0.45))
		gradient.add_point(0.15, Color(1, 1, 1, 0.30))
		gradient.set_color(1, Color(1, 1, 1, 0))

	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	emitter.process_material = process

	var material := ShaderMaterial.new()
	material.shader = PARTICLE_SHADER
	material.set_shader_parameter("particle_texture", load(TEXTURES + texture_name))
	material.set_shader_parameter("unlit", not (is_core or debris))
	material.set_shader_parameter("world_to_vehicle", vehicle.global_transform.affine_inverse())
	particle_materials.append(material)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	emitter.draw_pass_1 = quad
	add_child(emitter)
	return emitter


func _physics_process(delta: float) -> void:
	wetness_lookup_cooldown = maxf(0.0, wetness_lookup_cooldown - delta)
	impact_cooldown = maxf(0.0, impact_cooldown - delta)
	for i in impact_busy.size():
		impact_busy[i] = maxf(0.0, impact_busy[i] - delta)
	var sim := vehicle.simulation
	if generation != sim.session_generation or vehicle.global_position.distance_to(last_position) > 15.0:
		reset_effects()
		generation = sim.session_generation
	last_position = vehicle.global_position
	if not enabled or intensity <= 0.0 or vehicle.freeze or not vehicle._physics_ready:
		stop_wheels()
		if steam_emitter != null:
			steam_emitter.emitting = false
		return
	var wetness := get_wetness()
	for i in 4:
		update_wheel(i, wetness)
	update_impacts(wetness)
	update_radiator_steam(delta)


func _process(_delta: float) -> void:
	if vehicle == null:
		return
	var inverse := vehicle.global_transform.affine_inverse()
	for material in particle_materials:
		material.set_shader_parameter("world_to_vehicle", inverse)


func get_wetness() -> float:
	if not is_instance_valid(wetness_node) and wetness_lookup_cooldown <= 0.0:
		wetness_node = get_tree().root.find_child("RallyTerrainWetness", true, false)
		wetness_lookup_cooldown = 1.0
	return clampf(float(wetness_node.get("wetness")), 0.0, 1.0) if is_instance_valid(wetness_node) else 0.0


func update_wheel(index: int, wetness: float) -> void:
	var sim := vehicle.simulation
	var core := wheel_cores[index]
	var plume := wheel_plumes[index]
	var chips := wheel_chips[index]
	var surface := sim.wheel_surfaces[index].to_lower()

	if (
		index < 2 or sim.wheel_loads[index] < 60.0 or not SURFACES.has(surface)
		or sim.wheel_contact_casts.size() != 4 or not sim.wheel_contact_casts[index].is_colliding()
	):
		core.emitting = false
		plume.emitting = false
		chips.emitting = false
		return

	var profile: Dictionary = SURFACES[surface]
	var speed := vehicle.linear_velocity.length()
	var slip := maxf(
		smoothstep(0.08, 0.40, absf(sim.wheel_slips[index].x)),
		smoothstep(0.06, 0.24, absf(sim.wheel_slips[index].y)),
	)
	var tread_speed := absf(sim.wheel_spins[index]) * sim.wheel_radii[index]
	var motion := smoothstep(1.0, 12.0, maxf(speed, tread_speed if slip > 0.2 else speed))
	var strength := clampf(intensity * motion * (0.65 + 0.35 * slip), 0.0, 1.0)
	var asphalt := surface in ["road", "asphalt", "tarmac"]
	var dust := (slip * 0.65 if asphalt else float(profile.dust)) * strength * (1.0 - 0.9 * wetness)
	var debris := float(profile.chips) * strength * (0.25 + 0.75 * slip)
	var normal := sim.wheel_contact_normals[index]
	var point := sim.wheel_contact_points[index] + normal * 0.04
	var direction := (normal * 0.7 - vehicle.linear_velocity.normalized() * 0.4).normalized()

	# Separate dark cores, pale haze and solid flecks from similarly colored ground.
	var base_color: Color = profile.color
	var core_color := base_color.darkened(0.32)
	var plume_color := base_color.lightened(0.28)
	var chip_color := base_color.darkened(0.25)

	configure_continuous(core, point, direction, core_color, dust * 1.4)
	configure_continuous(plume, point, direction, plume_color, dust * 1.25)
	configure_continuous(chips, point, direction, chip_color, debris * 1.7)


func configure_continuous(
	emitter: GPUParticles3D,
	point: Vector3,
	direction: Vector3,
	color: Color,
	strength: float,
) -> void:
	emitter.global_transform = Transform3D(Basis.IDENTITY, point)
	var process := emitter.process_material as ParticleProcessMaterial
	process.direction = direction
	process.color = color
	emitter.amount_ratio = clampf(strength, 0.0, 1.0)
	emitter.emitting = strength > 0.025


func update_impacts(wetness: float) -> void:
	if impact_cooldown > 0.0:
		return
	var selected: Dictionary = { }
	var largest := 0.0
	for contact in vehicle.body_contact_vfx:
		var impulse := float(contact.impulse_ns)
		var closing := float(contact.speed_ms)
		var scrape := float(contact.tangent_ms)
		if (
			impulse < vehicle.mass * 0.20
			or (closing < 1.8 and scrape < 4.0 and impulse < vehicle.mass * 0.8)
		):
			continue
		if impulse > largest:
			largest = impulse
			selected = contact
	if selected.is_empty():
		return
	var surface := str(selected.surface).to_lower()
	var collider_name := str(selected.collider_name)
	var profile: Dictionary = SURFACES.get(surface, { "color": Color(0.48, 0.43, 0.35) })
	var hard := surface in ["road", "asphalt", "tarmac"] or "props" in collider_name
	var spark := hard and float(selected.tangent_ms) > 4.0 and wetness < 0.6
	var severity := clampf(largest / maxf(vehicle.mass * 3.0, 1.0), 0.15, 1.0)
	emit_impact(selected.position, selected.normal, profile.color, severity, spark)
	impact_cooldown = 0.22 if spark else 0.35


func emit_impact(
	point: Vector3,
	normal: Vector3,
	color: Color,
	severity: float,
	sparks: bool,
) -> void:
	for i in impact_pool.size():
		if impact_busy[i] > 0.0:
			continue
		var emitter := impact_pool[i]
		var process := emitter.process_material as ParticleProcessMaterial
		var quad := emitter.draw_pass_1 as QuadMesh
		var material := quad.material as ShaderMaterial
		material.set_shader_parameter("particle_texture", load(TEXTURES + ("trace_01_a.png" if sparks else "dirt_02_a.png")))
		material.set_shader_parameter("unlit", sparks)
		quad.size = Vector2(0.25, 1.5) if sparks else Vector2.ONE
		process.angle_min = -180.0
		process.angle_max = 180.0
		process.color = Color(1.0, 0.78, 0.32) if sparks else color.darkened(0.25)
		process.direction = (normal + Vector3.UP * 0.35).normalized()
		process.initial_velocity_min = 0.8
		process.initial_velocity_max = 2.5 + severity * 2.0
		emitter.global_transform = Transform3D(Basis.IDENTITY, point + normal * 0.04)
		emitter.amount_ratio = clampf(intensity * severity * 1.5, 0.25, 1.0)
		emitter.restart()
		emitter.emitting = true
		impact_busy[i] = emitter.lifetime + 0.12
		emitted_impacts += 1
		return


func stop_wheels() -> void:
	for emitter in wheel_cores + wheel_plumes + wheel_chips:
		emitter.emitting = false


func reset_effects() -> void:
	for emitter in wheel_cores + wheel_plumes + wheel_chips + impact_pool:
		emitter.restart()
		emitter.emitting = false
	if steam_emitter != null:
		steam_emitter.restart()
		steam_emitter.emitting = false
	impact_busy.fill(0.0)
	impact_cooldown = 0.0
	current_steam_strength = 0.0
	steam_time = 0.0


func make_steam_emitter() -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = "RadiatorSteam"
	emitter.emitting = false
	emitter.amount = 48
	emitter.lifetime = 1.2
	emitter.one_shot = false
	emitter.explosiveness = 0.0
	emitter.local_coords = false
	emitter.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 12, 16))
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.25, 0.10, 0.05)
	process.direction = Vector3.UP
	process.spread = 30.0
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 1.8
	process.gravity = Vector3(0, 0.6, 0)
	process.scale_min = 0.25
	process.scale_max = 0.85
	process.angle_min = -180.0
	process.angle_max = 180.0

	var curve := Curve.new()
	curve.max_value = 2.0
	curve.add_point(Vector2(0.0, 0.25))
	curve.add_point(Vector2(0.3, 0.8))
	curve.add_point(Vector2(1.0, 1.8))
	var curve_texture := CurveTexture.new()
	curve_texture.curve = curve
	process.scale_curve = curve_texture

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.95, 0.96, 0.98, 0.0))
	gradient.add_point(0.12, Color(0.95, 0.96, 0.98, 0.55))
	gradient.add_point(0.65, Color(0.90, 0.92, 0.95, 0.25))
	gradient.set_color(1, Color(0.90, 0.92, 0.95, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	emitter.process_material = process

	var material := ShaderMaterial.new()
	material.shader = PARTICLE_SHADER
	material.set_shader_parameter("particle_texture", load(TEXTURES + "smoke_01_a.png"))
	material.set_shader_parameter("unlit", true)
	material.set_shader_parameter("body_exclusion_strength", 0.0)
	material.set_shader_parameter("world_to_vehicle", vehicle.global_transform.affine_inverse())
	particle_materials.append(material)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)
	quad.material = material
	emitter.draw_pass_1 = quad
	add_child(emitter)
	return emitter


func update_radiator_steam(delta: float) -> void:
	if steam_emitter == null or vehicle == null or vehicle.simulation == null:
		return
	steam_time += delta
	var thermal_snap := vehicle.simulation.thermal_model.get_engine_thermal_state_snapshot()
	var rad_damage := float(thermal_snap.get("radiator_damage", 0.0))
	var water_temp := float(thermal_snap.get("water", {}).get("temperature_c", 80.0))

	var damage_doc: Dictionary = vehicle.simulation.domains.get("damage", {})
	var steam_cfg: Dictionary = damage_doc.get("steam", {})
	var start_dmg := float(steam_cfg.get("start_damage", 0.25))
	var cont_dmg := float(steam_cfg.get("continuous_damage", 0.50))
	var heavy_dmg := float(steam_cfg.get("heavy_damage", 0.75))
	var max_int := float(steam_cfg.get("max_intensity", 1.0))
	var bonnet_att := float(steam_cfg.get("bonnet_attenuation", 0.35))
	var cold_temp := float(steam_cfg.get("cold_temperature_c", 75.0))
	var hot_temp := float(steam_cfg.get("hot_temperature_c", 95.0))
	var local_pos_arr: Array = steam_cfg.get("local_position", [0.0, 0.48, -1.76])
	var local_pos := Vector3(float(local_pos_arr[0]), float(local_pos_arr[1]), float(local_pos_arr[2]))

	if rad_damage < start_dmg or not enabled or intensity <= 0.0 or vehicle.freeze:
		steam_emitter.emitting = false
		current_steam_strength = move_toward(current_steam_strength, 0.0, delta * 2.0)
		return

	var tier_strength := 0.0
	if rad_damage < cont_dmg:
		var pulse := maxf(0.0, sin(steam_time * 11.0))
		var norm := (rad_damage - start_dmg) / maxf(cont_dmg - start_dmg, 0.01)
		tier_strength = lerpf(0.25, 0.55, norm) * pulse
	elif rad_damage < heavy_dmg:
		var norm := (rad_damage - cont_dmg) / maxf(heavy_dmg - cont_dmg, 0.01)
		tier_strength = lerpf(0.55, 0.80, norm)
	else:
		var norm := (rad_damage - heavy_dmg) / maxf(1.0 - heavy_dmg, 0.01)
		tier_strength = lerpf(0.80, 1.0, norm)

	var temp_factor := clampf((water_temp - cold_temp) / maxf(hot_temp - cold_temp, 1.0), 0.2, 1.35)
	var load_factor := 0.85 + 0.25 * float(vehicle.throttle_amount)
	var camera_factor := bonnet_att if is_bonnet_camera() else 1.0
	var target_strength := tier_strength * temp_factor * load_factor * camera_factor * max_int * intensity
	current_steam_strength = lerpf(current_steam_strength, target_strength, clampf(delta * 4.0, 0.0, 1.0))

	var global_spawn := vehicle.global_transform * local_pos
	var speed := vehicle.linear_velocity.length()
	var vehicle_back := vehicle.global_transform.basis.z
	var stream_blend := clampf(speed / 18.0, 0.0, 0.85)
	var stream_dir := (Vector3.UP * (1.0 - stream_blend * 0.6) + vehicle_back * (stream_blend * 1.2)).normalized()

	steam_emitter.global_transform = Transform3D(Basis.IDENTITY, global_spawn)
	var process := steam_emitter.process_material as ParticleProcessMaterial
	process.direction = stream_dir
	process.initial_velocity_min = lerpf(0.8, 2.5, stream_blend)
	process.initial_velocity_max = lerpf(1.8, 5.0, stream_blend)
	steam_emitter.amount_ratio = clampf(current_steam_strength, 0.0, 1.0)
	steam_emitter.emitting = current_steam_strength > 0.03


func is_bonnet_camera() -> bool:
	if not is_instance_valid(camera_rig) and vehicle != null and vehicle.get_parent() != null:
		camera_rig = vehicle.get_parent().get_node_or_null("RallyCameraRig")
	return camera_rig != null and int(camera_rig.get("camera_mode")) == 1
