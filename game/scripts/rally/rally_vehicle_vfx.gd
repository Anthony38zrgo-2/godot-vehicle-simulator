class_name RallyVehicleVFX
extends Node3D

## Presentation only: reuses the four existing wheel casts and Jolt contacts.
const TEXTURES := "res://assets/vfx/brackeys/particles/alpha/"
const CMR4_TEXTURES := "res://assets/vfx/cmr4/"
const CMR4_PARTICLE_SIZE_MULTIPLIER := 3.0
const DUST_CORE := preload("res://assets/vfx/cmr4/dust_01.png")
const TIRE_SMOKE := preload("res://assets/vfx/cmr4/smoke_01.png")
const SPLASH_LOOSE := preload(CMR4_TEXTURES + "cr_splsh.png")
const SPLASH_PAVED := preload(CMR4_TEXTURES + "rd_splsh.png")
const WATER_CORE := preload(CMR4_TEXTURES + "water_1.png")
const SNOW_ROLL := [
	preload(CMR4_TEXTURES + "snw_rd0.png"),
	preload(CMR4_TEXTURES + "snw_rd1.png"),
	preload(CMR4_TEXTURES + "snw_rd2.png"),
	preload(CMR4_TEXTURES + "snw_rd3.png"),
]
const SPARK_SMALL := preload(CMR4_TEXTURES + "sprk_sml.png")
const SPARK_BIG := preload(CMR4_TEXTURES + "sprk_big.png")
const MUD_CLOD := preload(CMR4_TEXTURES + "mud_rd1.png")
const LEAVES := [
	preload(CMR4_TEXTURES + "leaf_01.png"),
	preload(CMR4_TEXTURES + "leaf_02.png"),
	preload(CMR4_TEXTURES + "leaf_03.png"),
]
const DIRT_CHIPS := preload(TEXTURES + "dirt_02_a.png")
const SNOW_MIN_MM := 0.25
const WHEEL_BURST_SLOTS := 20
const WHEEL_BURST_LIFETIME := 0.36
const PARTICLE_SHADER = preload("res://scripts/rally/rally_vehicle_vfx.gdshader")
const GRAVEL_BOUNCE := preload("res://scripts/rally/rally_wheel_gravel_bounce.gdshader")
const ADDITIVE_SHADER = preload("res://scripts/rally/rally_vehicle_vfx_add.gdshader")
const TIRE_TRACKS = preload("res://scripts/rally/rally_tire_tracks.gd")
const SURFACES := {
	"gravel": { "color": Color(0.56, 0.46, 0.32), "dust": 0.60, "interval": 0.14 },
	"dirt": { "color": Color(0.40, 0.29, 0.18), "dust": 0.70, "interval": 0.16 },
	"sand": { "color": Color(0.72, 0.61, 0.40), "dust": 0.85, "interval": 0.12 },
	"grass": { "color": Color(0.32, 0.36, 0.15), "dust": 0.0, "interval": 0.19 },
	"road": { "color": Color(0.70, 0.73, 0.76), "dust": 0.0, "interval": 0.2 },
	"asphalt": { "color": Color(0.70, 0.73, 0.76), "dust": 0.0, "interval": 0.2 },
	"tarmac": { "color": Color(0.70, 0.73, 0.76), "dust": 0.0, "interval": 0.2 },
}

@export_range(0.0, 1.5, 0.025) var intensity: float = 0.975
@export var enabled: bool = true
@export var soften_wheel_intersections: bool = true

var vehicle: RallyEscortVehicle
var wheel_previous_surface: Array[String] = ["", "", "", ""]
var wheel_was_wet: Array[bool] = [false, false, false, false]
var wheel_bursts: Array[GPUParticles3D] = []
var wheel_burst_busy: Array[float] = []
var wheel_cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
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
var tire_tracks: Node3D
var _last_vfx_transform := Transform3D.IDENTITY


func _ready() -> void:
	vehicle = get_parent() as RallyEscortVehicle
	if vehicle == null:
		set_physics_process(false)
		return
	tire_tracks = TIRE_TRACKS.new()
	tire_tracks.name = "TireTracks"
	add_child(tire_tracks)
	for i in WHEEL_BURST_SLOTS:
		var emitter := make_emitter("WheelBurst%d" % i, DUST_CORE, 3, WHEEL_BURST_LIFETIME, Vector2.ONE, true, true)
		var material := (emitter.draw_pass_1 as QuadMesh).material as ShaderMaterial
		material.set_shader_parameter("body_exclusion_strength", 1.0)
		var process := emitter.process_material as ParticleProcessMaterial
		var ramp := process.color_ramp as GradientTexture1D
		ramp.gradient.set_color(0, Color(1, 1, 1, 0.9))
		ramp.gradient.add_point(0.25, Color(1, 1, 1, 0.7))
		emitter.set_meta("wheel_process", process)
		wheel_bursts.append(emitter)
		wheel_burst_busy.append(0.0)

	for i in 6:
		impact_pool.append(
			make_emitter(
				"Impact%d" % i,
				DIRT_CHIPS,
				18,
				0.45,
				Vector2(0.10, 0.24),
				true,
				true,
				false,
			)
		)
		impact_busy.append(0.0)
	steam_emitter = make_steam_emitter()
	last_position = vehicle.global_position
	print("RALLY_VFX_READY wheel_burst_slots=", WHEEL_BURST_SLOTS, " intensity=", intensity)


func make_emitter(
	label: String,
	texture: Texture2D,
	count: int,
	seconds: float,
	sizes: Vector2,
	burst: bool,
	debris: bool = false,
	is_core: bool = false,
	gravity_y: float = NAN,
	unlit_override: int = -1,
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
	process.gravity = Vector3(0, gravity_y if not is_nan(gravity_y) else (-5.5 if debris else 0.35), 0)
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
	material.set_shader_parameter("soft_intersection_metres", 0.0 if debris else 0.22)
	material.set_shader_parameter("particle_texture", texture)
	material.set_shader_parameter("unlit", (unlit_override == 1) if unlit_override >= 0 else not (is_core or debris))
	# Wheel effects stay outside the cabin; impacts happen on the contact
	# surface and must not be clipped by the body box.
	material.set_shader_parameter("body_exclusion_strength", 0.0 if burst else 1.0)
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
	for i in wheel_burst_busy.size():
		wheel_burst_busy[i] = maxf(0.0, wheel_burst_busy[i] - delta)
	for i in wheel_cooldowns.size():
		wheel_cooldowns[i] = maxf(0.0, wheel_cooldowns[i] - delta)
	var sim := vehicle.simulation
	if generation != sim.session_generation or vehicle.global_position.distance_to(last_position) > 15.0:
		reset_effects()
		generation = sim.session_generation
	last_position = vehicle.global_position
	if not enabled or intensity <= 0.0 or vehicle.freeze or not vehicle._physics_ready:
		clear_wheel_bursts()
		for i in 4:
			tire_tracks.break_track(i)
		if steam_emitter != null:
			steam_emitter.emitting = false
		return
	var wetness := get_wetness()
	for i in 4:
		update_wheel(i, wetness)
		update_tire_track(i)
	update_impacts(wetness)
	update_radiator_steam(delta)


func update_tire_track(index: int) -> void:
	var sim := vehicle.simulation
	if sim.wheel_contact_casts.size() != 4 or not sim.wheel_contact_casts[index].is_colliding() or sim.wheel_loads[index] < 60.0:
		tire_tracks.break_track(index)
		return
	var surface := sim.wheel_surfaces[index].to_lower()
	var variant: int = tire_tracks.variant_for(surface, float(wheel_conditions(index).get("snow_mm", 0.0)), index)
	var offset := sim.wheel_contact_points[index] - vehicle.global_position
	var velocity := vehicle.linear_velocity + vehicle.angular_velocity.cross(offset)
	var forward_speed := velocity.dot(-vehicle.global_basis.z)
	if variant < 0 or velocity.length_squared() < 1.0:
		tire_tracks.break_track(index)
		return
	var slip := sim.wheel_slips[index]
	var lock := smoothstep(0.10, 0.85, -slip.x * signf(forward_speed))
	var lateral := smoothstep(0.07, 0.35, absf(slip.y)) * 0.55
	var load := clampf(sim.wheel_loads[index] / (vehicle.mass * 9.81 * 0.25), 0.0, 1.0)
	var rolling := 0.12 if variant < 2 else 0.22
	var strength := intensity * load * lerpf(rolling, 0.68, maxf(lock, lateral))
	tire_tracks.add_contact(index, sim.wheel_contact_points[index], sim.wheel_contact_normals[index], sim.wheel_widths[index], variant, strength, surface)


func _process(_delta: float) -> void:
	if vehicle == null:
		return
	var current_transform := vehicle.global_transform
	if current_transform == _last_vfx_transform:
		return
	_last_vfx_transform = current_transform
	var inverse := current_transform.affine_inverse()
	for material in particle_materials:
		material.set_shader_parameter("world_to_vehicle", inverse)


func get_wetness() -> float:
	if not is_instance_valid(wetness_node) and wetness_lookup_cooldown <= 0.0:
		wetness_node = get_tree().root.find_child("RallyTerrainWetness", true, false)
		wetness_lookup_cooldown = 1.0
	return clampf(float(wetness_node.get("wetness")), 0.0, 1.0) if is_instance_valid(wetness_node) else 0.0


func update_wheel(index: int, wetness: float) -> void:
	var sim := vehicle.simulation
	var surface := sim.wheel_surfaces[index].to_lower()

	if (
		index < 2 or sim.wheel_loads[index] < 60.0 or not SURFACES.has(surface)
		or sim.wheel_contact_casts.size() != 4 or not sim.wheel_contact_casts[index].is_colliding()
	):
		return

	var entered_grass := surface == "grass" and wheel_previous_surface[index] != "grass"
	var wet := clampf(wetness, 0.0, 1.0)
	var entered_water := wet >= 0.55 and not wheel_was_wet[index]
	if wheel_cooldowns[index] > 0.0 and not entered_grass and not entered_water:
		return
	var profile: Dictionary = SURFACES[surface]
	var speed := vehicle.linear_velocity.length()
	var slip := maxf(
		smoothstep(0.08, 0.40, absf(sim.wheel_slips[index].x)),
		smoothstep(0.06, 0.24, absf(sim.wheel_slips[index].y)),
	)
	var tread_speed := absf(sim.wheel_spins[index]) * sim.wheel_radii[index]
	var normal := sim.wheel_contact_normals[index]
	var point := sim.wheel_contact_points[index]
	var motion := smoothstep(1.0, 12.0, maxf(speed, tread_speed if slip > 0.2 else speed))
	var strength := clampf(intensity * motion * (0.65 + 0.35 * slip), 0.0, 1.0)
	if strength <= 0.025:
		return

	wheel_previous_surface[index] = surface
	wheel_was_wet[index] = wet >= 0.55
	var direction := (normal * 0.45 - vehicle.linear_velocity.normalized() * 0.75).normalized()
	var color: Color = profile.color
	var paved := surface in ["road", "asphalt", "tarmac"]
	var snow_mm := float(wheel_conditions(index).get("snow_mm", 0.0))
	var interval := float(profile.interval)
	if snow_mm >= SNOW_MIN_MM:
		emit_wheel_burst(point + normal * 0.09, direction, snow_texture_variant(index), Color(0.92, 0.95, 0.99, strength), 3, Vector2(0.14, 0.25), -4.5)
	elif wet >= 0.35:
		emit_wheel_burst(point + normal * 0.10, direction, SPLASH_PAVED if paved else SPLASH_LOOSE, Color(0.86, 0.91, 0.95, strength * wet), 3 if entered_water else 2, Vector2(0.16, 0.25), -4.5)
		if surface != "grass":
			emit_wheel_burst(point + normal * 0.14, direction, WATER_CORE, Color(0.80, 0.88, 0.92, strength * wet), 1, Vector2(0.26, 0.35), -2.5)
	else:
		var dust := (slip * 0.65 if paved else float(profile.dust)) * strength * (1.0 - wet)
		if dust > 0.025:
			var trail := (direction if speed > 1.0 else vehicle.global_basis.z).slide(normal).normalized()
			var dust_point := point + trail * 0.70 + normal * 0.42
			emit_wheel_burst(dust_point, direction, TIRE_SMOKE if paved else DUST_CORE, Color(color.lightened(0.46), minf(dust * 2.15, 0.95)), 1, Vector2(0.58, 0.78), 0.15)
	if snow_mm < SNOW_MIN_MM:
		if entered_grass:
			emit_wheel_burst(point + normal * 0.16, direction, LEAVES[index % LEAVES.size()], Color(color.lightened(0.24), strength), 2, Vector2(0.34, 0.48), -3.0)
		elif surface == "dirt" and wet >= 0.55 and slip > 0.55:
			emit_wheel_burst(point + normal * 0.10, direction, MUD_CLOD, Color(color, strength), 2, Vector2(0.15, 0.21), -8.0)
		elif surface == "gravel" and wet < 0.35 and slip > 0.76:
			var rearward := (direction if speed > 1.0 else vehicle.global_basis.z).slide(normal).normalized()
			emit_gravel_bounce(point, normal, rearward, color.darkened(0.23))
	wheel_cooldowns[index] = interval * lerpf(1.7, 1.0, strength)


func emit_gravel_bounce(point: Vector3, normal: Vector3, direction: Vector3, color: Color) -> void:
	var slot := wheel_burst_busy.find(0.0)
	if slot < 0:
		return
	var emitter := wheel_bursts[slot]
	var bounce := emitter.get_meta("gravel_process", null) as ShaderMaterial if emitter.has_meta("gravel_process") else null
	if bounce == null:
		bounce = ShaderMaterial.new()
		bounce.shader = GRAVEL_BOUNCE
		emitter.set_meta("gravel_process", bounce)
	bounce.set_shader_parameter("ground_normal", normal)
	bounce.set_shader_parameter("travel_direction", direction)
	bounce.set_shader_parameter("rock_color", color)
	emitter.process_material = bounce
	emitter.amount = 2
	emitter.global_position = point
	var quad := emitter.draw_pass_1 as QuadMesh
	quad.size = Vector2.ONE
	var material := quad.material as ShaderMaterial
	material.set_shader_parameter("particle_texture", DIRT_CHIPS)
	material.set_shader_parameter("soft_intersection_metres", 0.0)
	emitter.restart()
	emitter.emitting = true
	wheel_burst_busy[slot] = WHEEL_BURST_LIFETIME + 0.025


func emit_wheel_burst(
	point: Vector3, direction: Vector3, texture: Texture2D, color: Color,
	count: int, sizes: Vector2, gravity_y: float,
) -> void:
	var slot := wheel_burst_busy.find(0.0)
	if slot < 0:
		return
	var emitter := wheel_bursts[slot]
	emitter.amount = count
	emitter.global_position = point
	var process := emitter.get_meta("wheel_process") as ParticleProcessMaterial
	emitter.process_material = process
	process.emission_box_extents = Vector3(0.05, 0.015, 0.05)
	process.angular_velocity_min = -260.0 if texture in LEAVES else 0.0
	process.angular_velocity_max = 260.0 if texture in LEAVES else 0.0
	process.direction = direction
	process.spread = 35.0
	process.initial_velocity_min = 0.55
	process.initial_velocity_max = 1.65
	process.gravity = Vector3(0.0, gravity_y, 0.0)
	process.scale_min = sizes.x
	process.scale_max = sizes.y
	process.color = color
	var quad := emitter.draw_pass_1 as QuadMesh
	quad.size = Vector2.ONE * _particle_size_multiplier(texture)
	var material := quad.material as ShaderMaterial
	material.set_shader_parameter("particle_texture", texture)
	material.set_shader_parameter("soft_intersection_metres", 0.22 if soften_wheel_intersections and texture.resource_path.begins_with(CMR4_TEXTURES) else 0.0)
	emitter.restart()
	emitter.emitting = true
	wheel_burst_busy[slot] = WHEEL_BURST_LIFETIME + 0.025


func _particle_size_multiplier(texture: Texture2D) -> float:
	return CMR4_PARTICLE_SIZE_MULTIPLIER if texture.resource_path.begins_with(CMR4_TEXTURES) else 1.0


func wheel_conditions(index: int) -> Dictionary:
	var conditions: Array = vehicle.simulation.last_local_conditions
	if index >= 0 and index < conditions.size() and conditions[index] is Dictionary:
		return conditions[index]
	return {}


func snow_texture_variant(index: int) -> Texture2D:
	# Slow rotation across the four source variants keeps the clumps varied.
	var step := int(Time.get_ticks_msec() / 500)
	return SNOW_ROLL[(index + step) % SNOW_ROLL.size()] as Texture2D


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
	var tangent := float(selected.tangent_ms)
	var hard := (
		surface in ["road", "asphalt", "tarmac", "curb"]
		or "barrier" in collider_name
		or "props" in collider_name
		or "building" in collider_name
	)
	var spark := hard and tangent > 4.0 and wetness < 0.6
	var severity := clampf(largest / maxf(vehicle.mass * 3.0, 1.0), 0.15, 1.0)
	var effect := classify_impact(surface, collider_name, severity, wetness, spark)
	if spark:
		var normal: Vector3 = selected.normal
		effect["direction"] = (normal * 0.32 - vehicle.linear_velocity.slide(normal).normalized()).normalized()
	emit_impact_effect(selected.position, selected.normal, effect, severity)
	impact_cooldown = 0.22 if str(effect.get("kind", "dirt")) == "spark" else 0.35


## Chooses one sprite per contact. Sparks are additive; leaves and mud keep
## the alpha shader. The material only ever receives a single texture per event.
func classify_impact(
	surface: String,
	collider_name: String,
	severity: float,
	wetness: float,
	spark: bool,
) -> Dictionary:
	if spark:
		var big := severity >= 0.5
		return {
			"kind": "spark",
			"texture": SPARK_BIG if big else SPARK_SMALL,
			"additive": true,
			"color": Color(1.0, 0.74, 0.28),
			"quad_size": Vector2(0.18, 0.78) if big else Vector2(0.10, 0.48),
			"unlit": true,
		}
	if "tree" in collider_name or surface == "grass":
		var leaf := emitted_impacts % LEAVES.size()
		return {
			"kind": "leaf",
			"texture": LEAVES[leaf] as Texture2D,
			"additive": false,
			"color": Color(0.34, 0.44, 0.17).lightened(0.06 * leaf),
			"quad_size": Vector2(0.16, 0.24),
			"unlit": false,
		}
	if surface == "mud" or (surface == "dirt" and wetness >= 0.35):
		return {
			"kind": "mud",
			"texture": MUD_CLOD,
			"additive": false,
			"color": Color(0.34, 0.25, 0.15),
			"quad_size": Vector2(0.12, 0.22),
			"unlit": true,
		}
	var profile: Dictionary = SURFACES.get(surface, { "color": Color(0.48, 0.43, 0.35) })
	return {
		"kind": "dirt",
		"texture": DIRT_CHIPS,
		"additive": false,
		"color": Color(profile.color).darkened(0.25),
		"quad_size": Vector2.ONE,
		"unlit": false,
	}


func emit_impact(
	point: Vector3,
	normal: Vector3,
	color: Color,
	severity: float,
	sparks: bool,
) -> void:
	var effect: Dictionary
	if sparks:
		var big := severity >= 0.5
		effect = {
			"kind": "spark",
			"texture": SPARK_BIG if big else SPARK_SMALL,
			"additive": true,
			"color": Color(1.0, 0.74, 0.28) if color == Color.WHITE else color,
			"quad_size": Vector2(0.18, 0.78) if big else Vector2(0.10, 0.48),
			"unlit": true,
		}
	else:
		effect = {
			"kind": "dirt",
			"texture": DIRT_CHIPS,
			"additive": false,
			"color": color.darkened(0.25),
			"quad_size": Vector2.ONE,
			"unlit": false,
		}
	emit_impact_effect(point, normal, effect, severity)


func emit_impact_effect(
	point: Vector3,
	normal: Vector3,
	effect: Dictionary,
	severity: float,
) -> void:
	for i in impact_pool.size():
		if impact_busy[i] > 0.0:
			continue
		var emitter := impact_pool[i]
		var process := emitter.process_material as ParticleProcessMaterial
		var quad := emitter.draw_pass_1 as QuadMesh
		var material := quad.material as ShaderMaterial
		material.shader = ADDITIVE_SHADER if bool(effect.get("additive", false)) else PARTICLE_SHADER
		var effect_texture: Texture2D = effect.get("texture")
		var effect_color: Color = effect.get("color", Color.WHITE)
		var quad_size: Vector2 = effect.get("quad_size", Vector2.ONE)
		material.set_shader_parameter("particle_texture", effect_texture)
		material.set_shader_parameter("unlit", bool(effect.get("unlit", false)))
		material.set_shader_parameter("body_exclusion_strength", 0.0)
		material.set_shader_parameter("world_to_vehicle", vehicle.global_transform.affine_inverse())
		quad.size = quad_size * _particle_size_multiplier(effect_texture)
		process.angle_min = -180.0
		process.angle_max = 180.0
		process.color = effect_color
		process.direction = effect.get("direction", (normal + Vector3.UP * 0.35).normalized())
		process.initial_velocity_min = 0.8
		process.initial_velocity_max = 2.5 + severity * 2.0
		emitter.global_transform = Transform3D(Basis.IDENTITY, point + normal * 0.04)
		emitter.amount_ratio = clampf(intensity * severity * 1.5, 0.25, 1.0)
		emitter.restart()
		emitter.emitting = true
		impact_busy[i] = emitter.lifetime + 0.12
		emitted_impacts += 1
		return


func clear_wheel_bursts() -> void:
	for i in wheel_bursts.size():
		if wheel_burst_busy[i] > 0.0:
			wheel_bursts[i].restart()
			wheel_bursts[i].emitting = false
	wheel_burst_busy.fill(0.0)
	wheel_cooldowns.fill(0.0)
	wheel_previous_surface.fill("")
	wheel_was_wet.fill(false)


func reset_effects() -> void:
	if tire_tracks != null:
		tire_tracks.clear_tracks()
	clear_wheel_bursts()
	for emitter in impact_pool:
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
	emitter.amount = 20
	emitter.lifetime = 0.85
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
	material.set_shader_parameter("soft_intersection_metres", 0.22)
	material.set_shader_parameter("particle_texture", load(TEXTURES + "smoke_01_a.png"))
	material.set_shader_parameter("unlit", false)
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
