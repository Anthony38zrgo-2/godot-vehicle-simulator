class_name RallyVehicleVFX
extends Node3D

## Presentation only: reuses the four existing wheel casts and Jolt contacts.
const CMR2_TEXTURES := "res://assets/vfx/cmr2/"
const CMR4_TEXTURES := "res://assets/vfx/cmr4/"
const BACKFIRE := preload(CMR2_TEXTURES + "backfire_atlas.png")
var DUST_CORE: Texture2D
const TIRE_SMOKE := preload(CMR4_TEXTURES + "smoke_01.png")
const RAIN_SPLAT := preload(CMR2_TEXTURES + "splat.png")
const RADIATOR_STEAM := preload(CMR4_TEXTURES + "smoke_01.png")
const SPLASH_LOOSE := preload(CMR4_TEXTURES + "cr_splsh.png")
const SPLASH_PAVED := preload(CMR4_TEXTURES + "rd_splsh.png")
const WATER_CORE := preload(CMR4_TEXTURES + "water_1.png")
const SNOW_ROLL := [
	preload(CMR4_TEXTURES + "snw_rd0.png"),
	preload(CMR4_TEXTURES + "snw_rd1.png"),
	preload(CMR4_TEXTURES + "snw_rd2.png"),
	preload(CMR4_TEXTURES + "snw_rd3.png"),
]
const SMALL_SPARK := preload(CMR4_TEXTURES + "sprk_sml.png")
const SPARK := preload(CMR4_TEXTURES + "sprk_big.png")
var GRAVEL: Array = []
var MUD_CLOD: Texture2D
var LEAVES: Array = []
var DIRT_CHIPS: Texture2D
const SNOW_MIN_MM := 0.25
# Nieve pesada: el spray SNOW sale a la cadencia del polvo (intervalo 3) y la
# nube SMOKE, mas lenta, a su propio ritmo para simular polvo en suspension.
const SNOW_HAZE_TICKS := 9
const WHEEL_PARTICLES := preload("res://scripts/rally/rally_wheel_particles.gd")
const PARTICLE_SHADER = preload("res://scripts/rally/rally_vehicle_vfx.gdshader")
const ADDITIVE_SHADER = preload("res://scripts/rally/rally_vehicle_vfx_add.gdshader")
const TIRE_TRACKS = preload("res://scripts/rally/rally_tire_tracks.gd")
const SURFACES := {
	"gravel": { "dust": 0.60, "interval": 4, "dust_kind": WHEEL_PARTICLES.Kind.DUST, "burst": 2 },
	"dirt": { "dust": 0.70, "interval": 4, "dust_kind": WHEEL_PARTICLES.Kind.DIRT_DUST, "burst": 2 },
	"sand": { "dust": 0.85, "interval": 3, "dust_kind": WHEEL_PARTICLES.Kind.SAND_DUST, "burst": 3 },
	"grass": { "dust": 0.0, "interval": 10 },
	"snowdeep": { "dust": 0.85, "interval": 3, "dust_kind": WHEEL_PARTICLES.Kind.SNOW, "burst": 2 },
	"road": { "dust": 0.0, "interval": 10 },
	"asphalt": { "dust": 0.0, "interval": 10 },
	"tarmac": { "dust": 0.0, "interval": 10 },
}

@export_range(0.0, 1.5, 0.025) var intensity: float = 0.975
@export var enabled: bool = true
@export var soften_wheel_intersections: bool = true
@export var exhaust_tip := Vector3(-0.43, 0.23, 1.95)

var vehicle: RallyEscortVehicle
var wheel_previous_surface: Array[String] = ["", "", "", ""]
var wheel_was_wet: Array[bool] = [false, false, false, false]
var wheel_particles: WHEEL_PARTICLES
var wheel_particle_accumulator := 0.0
var exhaust_ticks := 0
var rain_splat_ticks := 0
var wheel_previous_point: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var wheel_has_previous_point: Array[bool] = [false, false, false, false]
var wheel_cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_snow_haze: Array[float] = [0.0, 0.0, 0.0, 0.0]
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
var _cached_weather_condition: Dictionary = {}


func _ready() -> void:
	vehicle = get_parent() as RallyEscortVehicle
	if vehicle == null:
		set_physics_process(false)
		return
	# Gravilla cuadrada: el índice aleatorio sobre GRAVEL varía el grano.
	# Mismo barro irregular aparte.
	DUST_CORE = WHEEL_PARTICLES.proc_sprite("dot")
	var speck := WHEEL_PARTICLES.proc_sprite("speck")
	var square_a := WHEEL_PARTICLES.proc_sprite("square", 0)
	var square_b := WHEEL_PARTICLES.proc_sprite("square", 1)
	GRAVEL = [square_a, square_b]
	MUD_CLOD = speck
	DIRT_CHIPS = speck
	LEAVES = [
		WHEEL_PARTICLES.proc_sprite("leaf", 0),
		WHEEL_PARTICLES.proc_sprite("leaf", 1),
		WHEEL_PARTICLES.proc_sprite("leaf", 2),
	]
	tire_tracks = TIRE_TRACKS.new()
	tire_tracks.name = "TireTracks"
	add_child(tire_tracks)
	wheel_particles = WHEEL_PARTICLES.new()
	wheel_particles.name = "WheelParticles"
	add_child(wheel_particles)
	vehicle.backfire_triggered.connect(emit_backfire)
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
		var emitter := impact_pool.back() as GPUParticles3D
		emitter.set_meta("impact_scale_curve", emitter.process_material.scale_curve)
		impact_busy.append(0.0)
	steam_emitter = make_steam_emitter()
	last_position = vehicle.global_position
	print("RALLY_VFX_READY wheel_particle_capacity=", WHEEL_PARTICLES.CAPACITY, " intensity=", intensity)


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
	wheel_particle_accumulator += delta
	while wheel_particle_accumulator >= WHEEL_PARTICLES.STEP:
		wheel_particle_accumulator -= WHEEL_PARTICLES.STEP
		advance_wheel_particles(wetness)
	for i in 4:
		update_tire_track(i)
	update_impacts(wetness)
	update_radiator_steam(delta)


func update_tire_track(index: int) -> void:
	var sim := vehicle.simulation
	if sim.wheel_contact_casts.size() != 4 or not sim.wheel_contact_casts[index].is_colliding() or sim.wheel_loads[index] < 60.0:
		tire_tracks.break_track(index)
		return
	var surface := sim.wheel_surfaces[index].to_lower()
	var track_winter := str(sim.tire_model.states[index].get("winter_layer_id", "")) if index < sim.tire_model.states.size() else ""
	var variant: int = tire_tracks.variant_for(surface, float(wheel_conditions(index).get("snow_mm", 0.0)), index, track_winter)
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
	var frame_progress := Engine.get_physics_interpolation_fraction() / float(Engine.physics_ticks_per_second)
	var fraction := clampf((wheel_particle_accumulator + frame_progress) / WHEEL_PARTICLES.STEP, 0.0, 1.0)
	wheel_particles.draw_particles(fraction, current_transform.affine_inverse(), soften_wheel_intersections)
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


func _resolve_weather_condition() -> Dictionary:
	for i in 4:
		var cond := wheel_conditions(i)
		if not cond.is_empty() and cond.has("climate"):
			_cached_weather_condition = cond
			return cond
	if vehicle != null and vehicle.simulation != null and vehicle.simulation.weather_controller != null:
		var wc: Object = vehicle.simulation.weather_controller
		var blend = wc.get("current_blend")
		if blend is Dictionary and blend.has("climate"):
			_cached_weather_condition = blend
			return blend
	return _cached_weather_condition


func advance_wheel_particles(wetness: float) -> void:
	var weather_cond := _resolve_weather_condition()
	var climate: Dictionary = weather_cond.get("climate", {})
	var direction := deg_to_rad(float(climate.get("wind_direction_deg", 0.0)))
	var wind := Vector3(cos(direction), 0.0, sin(direction)) * float(climate.get("wind_m_s", 0.0))
	for i in 4:
		wheel_cooldowns[i] = maxf(0.0, wheel_cooldowns[i] - WHEEL_PARTICLES.STEP)
		wheel_snow_haze[i] = maxf(0.0, wheel_snow_haze[i] - WHEEL_PARTICLES.STEP)
	wheel_particles.step(wind)
	for i in 4:
		update_wheel(i, wetness)
	_update_exhaust()
	_update_rain_splats(climate)


func _update_rain_splats(climate: Dictionary) -> void:
	rain_splat_ticks = maxi(0, rain_splat_ticks - 1)
	var weather_cond := _resolve_weather_condition()
	var effective_climate: Dictionary = climate if not climate.is_empty() else weather_cond.get("climate", {})
	var precipitation := float(effective_climate.get("precipitation_mm_h", 0.0))
	var vis: Node = vehicle.get_node_or_null("VisualDamage") if vehicle != null else null
	if vis != null and vis.has_method("update_weather_glass"):
		vis.update_weather_glass(precipitation, vehicle.linear_velocity.length() if vehicle != null else 0.0)
	if precipitation < 0.15:
		return
	var snow_mm := float(weather_cond.get("snow_mm", 0.0))
	var kind := str(weather_cond.get("precipitation_kind", "none"))
	if kind != "rain" and (kind != "none" or snow_mm > 0.0):
		return
	var intensity := clampf(precipitation / 12.0, 0.0, 1.0)
	var splats_to_emit := clampi(int(ceil(intensity * 4.0)), 1, 4)
	if rain_splat_ticks > 0:
		if intensity < 0.4:
			return
		splats_to_emit = 1
	rain_splat_ticks = clampi(roundi(lerpf(3.0, 1.0, intensity)), 1, 3)
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return
	var forward_lead := vehicle.linear_velocity * 0.35 if vehicle != null else Vector3.ZERO
	forward_lead.y = 0.0
	for i in splats_to_emit:
		var angle := wheel_particles.rng.randf_range(0.0, TAU)
		var radius := lerpf(1.1, 9.5, sqrt(wheel_particles.rng.randf()))
		var origin := vehicle.global_position + forward_lead + Vector3(cos(angle), 0.0, sin(angle)) * radius
		var ray := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 4.0, origin - Vector3.UP * 5.0, 1, [vehicle.get_rid()])
		var hit := space_state.intersect_ray(ray)
		if hit.is_empty() or (hit.normal as Vector3).y < 0.65:
			continue
		var point: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		wheel_particles.emit_particle(WHEEL_PARTICLES.Kind.RAIN_SPLAT, RAIN_SPLAT, point + normal * 0.08, normal * 0.25, point, normal)


func _update_exhaust() -> void:
	exhaust_ticks = maxi(0, exhaust_ticks - 1)
	if exhaust_ticks > 0 or vehicle.linear_velocity.length_squared() > 9.0:
		return
	var powertrain := vehicle.simulation.powertrain_model
	if powertrain.engine_rpm < powertrain.idle_rpm * 1.15:
		return
	exhaust_ticks = 7
	var tip := vehicle.to_global(exhaust_tip)
	var velocity := vehicle.global_basis.z * 1.4 + Vector3.UP * 0.22
	wheel_particles.emit_particle(WHEEL_PARTICLES.Kind.EXHAUST, TIRE_SMOKE, tip, velocity, tip - Vector3.UP, Vector3.UP)


func emit_backfire() -> void:
	if not enabled or intensity <= 0.0 or vehicle.freeze:
		return
	var rearward := vehicle.global_basis.z
	var tip := vehicle.to_global(exhaust_tip)
	wheel_particles.emit_particle(
		WHEEL_PARTICLES.Kind.BACKFIRE, BACKFIRE, tip + rearward * 0.13,
		rearward, tip - Vector3.UP, Vector3.UP
	)


func update_wheel(index: int, wetness: float) -> void:
	var sim := vehicle.simulation
	var surface := sim.wheel_surfaces[index].to_lower()
	if (
		sim.wheel_loads[index] < 60.0 or not SURFACES.has(surface)
		or sim.wheel_contact_casts.size() != 4 or not sim.wheel_contact_casts[index].is_colliding()
	):
		wheel_has_previous_point[index] = false
		wheel_previous_surface[index] = ""
		wheel_was_wet[index] = false
		return

	var point := sim.wheel_contact_points[index]
	var previous := wheel_previous_point[index] if wheel_has_previous_point[index] else point
	wheel_previous_point[index] = point
	wheel_has_previous_point[index] = true
	var entered_grass := surface == "grass" and wheel_previous_surface[index] != "grass"
	var wet := maxf(clampf(wetness, 0.0, 1.0), clampf(float(wheel_conditions(index).get("water_mm", 0.0)) / 4.0, 0.0, 1.0))
	var conditions := wheel_conditions(index)
	var in_water := float(conditions.get("puddle_depth_mm", 0.0)) >= 1.0 if conditions.has("puddle_depth_mm") else wet >= 0.55
	var entered_water := in_water and not wheel_was_wet[index]
	if wheel_cooldowns[index] > 0.0 and not entered_grass and not entered_water:
		return

	var profile: Dictionary = SURFACES[surface]
	var slip := maxf(
		smoothstep(0.08, 0.40, absf(sim.wheel_slips[index].x)),
		smoothstep(0.06, 0.24, absf(sim.wheel_slips[index].y)),
	)
	var corner_speed := vehicle.linear_velocity + vehicle.angular_velocity.cross(point - vehicle.global_position)
	var tread_speed := absf(sim.wheel_spins[index]) * sim.wheel_radii[index]
	var motion := smoothstep(1.0, 12.0, maxf(corner_speed.length(), tread_speed if slip > 0.2 else 0.0))
	var strength := clampf(intensity * motion * (0.65 + 0.35 * slip), 0.0, 1.0)
	if strength <= 0.025:
		return

	wheel_previous_surface[index] = surface
	wheel_was_wet[index] = in_water
	var normal := sim.wheel_contact_normals[index].normalized()
	var rearward := -corner_speed.slide(normal).normalized()
	if rearward.is_zero_approx():
		rearward = vehicle.global_basis.z.slide(normal).normalized()
	var side := normal.cross(rearward) * (-1.0 if index % 2 == 0 else 1.0)
	var source := previous.lerp(point, wheel_particles.rng.randf())
	var velocity := rearward * clampf(corner_speed.length() * 0.16 + slip, 0.6, 4.0) + side * slip * 0.5
	var paved := surface in ["road", "asphalt", "tarmac"]
	var snow_mm := float(wheel_conditions(index).get("snow_mm", 0.0))
	# La capa invernal manda sobre la superficie base: en Suecia la carretera
	# es Gravel con snow_packed aunque snow_mm meteorologico sea 0.
	var winter_layer := str(sim.tire_model.states[index].get("winter_layer_id", "")) if index < sim.tire_model.states.size() else ""
	var snowy := snow_mm >= SNOW_MIN_MM or surface == "snowdeep" or winter_layer in ["snow_packed", "snow_loose", "snow_deep", "ice"]
	if snowy:
		wheel_particles.emit_particle(WHEEL_PARTICLES.Kind.SNOW, snow_texture_variant(index), source + normal * 0.09, velocity + normal * 1.3, point, normal)
		if surface == "snowdeep" or winter_layer != "":
			for i in int(profile.get("burst", 1 if surface == "snowdeep" else 0)):
				var flake_offset := source + side * wheel_particles.rng.randf_range(-0.22, 0.22) + normal * wheel_particles.rng.randf_range(0.0, 0.12)
				var flake_velocity := velocity * wheel_particles.rng.randf_range(0.85, 1.1) + normal * wheel_particles.rng.randf_range(1.0, 1.5)
				wheel_particles.emit_particle(WHEEL_PARTICLES.Kind.SNOW, snow_texture_variant(index), flake_offset, flake_velocity, point, normal)
		if surface == "snowdeep" and wheel_snow_haze[index] <= 0.0:
			wheel_snow_haze[index] = SNOW_HAZE_TICKS * WHEEL_PARTICLES.STEP
			var haze_velocity := rearward * 0.8 + normal * 0.6
			wheel_particles.emit_particle(WHEEL_PARTICLES.Kind.SMOKE, TIRE_SMOKE, source + normal * 0.35, haze_velocity, point, normal, clampf(strength * 0.7, 0.0, 1.0))
	elif wet >= 0.35:
		var spray := smoothstep(0.35, 1.0, wet)
		var splash := SPLASH_PAVED if paved else SPLASH_LOOSE
		var splash_origin := source + normal * 0.10
		if index >= 2 or entered_water or slip > 0.3:
			var splash_velocity := velocity * 0.55 + normal * lerpf(1.2, 2.2, spray)
			wheel_particles.emit_particle(
				WHEEL_PARTICLES.Kind.SPLASH, splash, splash_origin, splash_velocity, point, normal, spray
			)
		if entered_water:
			for i in 3:
				var jitter := side * wheel_particles.rng.randf_range(-0.25, 0.25)
				wheel_particles.emit_particle(
					WHEEL_PARTICLES.Kind.SPLASH, splash, splash_origin + jitter,
					velocity * 0.8 + normal * 2.4, point, normal, spray
				)
		if surface != "grass":
			wheel_particles.emit_particle(WHEEL_PARTICLES.Kind.WATER, WATER_CORE, source + normal * 0.06, velocity + normal * 1.4, point, normal)
		if surface == "dirt" and wet >= 0.55 and slip > 0.55:
			wheel_particles.emit_particle(WHEEL_PARTICLES.Kind.MUD, MUD_CLOD, source + normal * 0.04, velocity + normal * 1.1, point, normal)
	elif index >= 2:
		var dust := (slip * 0.65 if paved else float(profile.dust)) * strength * (1.0 - wet)
		if dust > 0.025:
			var kind: WHEEL_PARTICLES.Kind = profile.get("dust_kind", WHEEL_PARTICLES.Kind.SMOKE)
			if kind == WHEEL_PARTICLES.Kind.DUST and slip > 0.76:
				kind = WHEEL_PARTICLES.Kind.SLIP_DUST
			wheel_particles.emit_particle(kind, TIRE_SMOKE if paved else DUST_CORE, source + normal * 0.16, velocity + normal * 0.28, point, normal)
			for i in int(profile.get("burst", 0)):
				var puff_offset := source + side * wheel_particles.rng.randf_range(-0.22, 0.22) + normal * wheel_particles.rng.randf_range(0.0, 0.12)
				var puff_velocity := velocity * wheel_particles.rng.randf_range(0.85, 1.1) + normal * 0.28
				wheel_particles.emit_particle(kind, TIRE_SMOKE if paved else DUST_CORE, puff_offset, puff_velocity, point, normal)
	if snow_mm < SNOW_MIN_MM and winter_layer == "" and surface != "snowdeep":
		var cutting_grass := surface == "grass" and index >= 2 and (slip > 0.55 or corner_speed.length() > 8.0)
		if entered_grass or cutting_grass:
			for leaf in 2:
				var texture: Texture2D = LEAVES[(index + leaf) % LEAVES.size()]
				var kind := WHEEL_PARTICLES.Kind.LEAF if entered_grass else (WHEEL_PARTICLES.Kind.GRASS if leaf == 0 else WHEEL_PARTICLES.Kind.GRASS_SHORT)
				var leaf_velocity := velocity * 0.75 + side * (0.45 + leaf * 0.35) + normal * (1.25 + leaf * 0.25)
				wheel_particles.emit_particle(kind, texture, source + normal * 0.12 + side * 0.18, leaf_velocity, point, normal)
		elif surface == "gravel" and wet < 0.35:
			# Gravilla en las 4 ruedas: beige sólido y opaco, vida media,
			# forma cuadrada. 1 por rueda: nace del centro de
			# centro de atrás (atrás + deriva a la línea central + leve
			# elevación). Hereda el 85% de la velocidad de la rueda para viajar
			# con ella y quedarse cerca: drag bajo + vida contenida.
			var hub := _wheel_hub_center(index, point, normal)
			var chip_dir := (rearward * 1.0 - side * 0.35 + normal * 0.35).normalized()
			var chip: Texture2D = GRAVEL[wheel_particles.rng.randi_range(0, GRAVEL.size() - 1)]
			var chip_speed := wheel_particles.rng.randf_range(0.3, 0.5)
			var chip_velocity := chip_dir * chip_speed + corner_speed * 0.85
			wheel_particles.emit_particle(WHEEL_PARTICLES.Kind.GRAVEL_CHIP, chip, hub, chip_velocity, point, normal)
			if slip > 0.76:
				var rock: Texture2D = GRAVEL[wheel_particles.rng.randi_range(0, GRAVEL.size() - 1)]
				wheel_particles.emit_particle(WHEEL_PARTICLES.Kind.ROCK, rock, hub, velocity * 0.3 + normal * 0.2 + corner_speed * 0.7, point, normal)
	var dry_ticks := int(profile.interval)
	var ticks := roundi(lerpf(float(dry_ticks), 3.0, wet)) if wet >= 0.35 else dry_ticks
	wheel_cooldowns[index] = ticks * WHEEL_PARTICLES.STEP


func _wheel_hub_center(index: int, contact_point: Vector3, contact_normal: Vector3) -> Vector3:
	# Centro de la rueda en mundo: pivote local + compresión de suspensión.
	# Si no hay datos del tren, aproxima con el contacto + radio.
	var sim := vehicle.simulation
	if sim != null and index >= 0 and index < sim.wheel_positions_local.size():
		var local: Vector3 = sim.wheel_positions_local[index]
		var compression := 0.0
		if sim.suspension_model != null and index < sim.suspension_model.compression.size():
			compression = float(sim.suspension_model.compression[index])
		return vehicle.global_transform * (local + Vector3.UP * compression)
	if sim != null and index >= 0 and index < sim.wheel_radii.size():
		return contact_point + contact_normal * float(sim.wheel_radii[index])
	return contact_point


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
			"texture": SPARK if big else SMALL_SPARK,
			"additive": true,
			"color": Color(1.0, 0.74, 0.28),
			"quad_size": Vector2(0.18, 0.78) if big else Vector2(0.10, 0.48),
		}
	if "tree" in collider_name or surface == "grass":
		var leaf := emitted_impacts % LEAVES.size()
		return {
			"kind": "leaf",
			"texture": LEAVES[leaf] as Texture2D,
			"additive": false,
			"color": WHEEL_PARTICLES.TYPES[WHEEL_PARTICLES.Kind.LEAF].color,
			"quad_size": Vector2.ONE,
		}
	if surface == "mud" or (surface == "dirt" and wetness >= 0.35):
		return {
			"kind": "mud",
			"texture": MUD_CLOD,
			"additive": false,
			"color": WHEEL_PARTICLES.TYPES[WHEEL_PARTICLES.Kind.MUD].color,
			"quad_size": Vector2(0.12, 0.22),
		}
	return {
		"kind": "dirt",
		"texture": DIRT_CHIPS,
		"additive": false,
		"color": Color(0.44, 0.37, 0.29),
		"quad_size": Vector2.ONE,
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
			"texture": SPARK if big else SMALL_SPARK,
			"additive": true,
			"color": Color(1.0, 0.74, 0.28) if color == Color.WHITE else color,
			"quad_size": Vector2(0.18, 0.78) if big else Vector2(0.10, 0.48),
		}
	else:
		effect = {
			"kind": "dirt",
			"texture": DIRT_CHIPS,
			"additive": false,
			"color": color.darkened(0.25),
			"quad_size": Vector2.ONE,
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
		var spark := bool(effect.get("additive", false))
		material.shader = ADDITIVE_SHADER if spark else PARTICLE_SHADER
		var effect_texture: Texture2D = effect.get("texture")
		var effect_color: Color = effect.get("color", Color.WHITE)
		var quad_size: Vector2 = effect.get("quad_size", Vector2.ONE)
		material.set_shader_parameter("particle_texture", effect_texture)
		material.set_shader_parameter("body_exclusion_strength", 0.0)
		material.set_shader_parameter("world_to_vehicle", vehicle.global_transform.affine_inverse())
		var foliage := effect_texture in LEAVES
		if not spark:
			material.set_shader_parameter("opaque_sprite_mask", foliage or effect_texture in [MUD_CLOD, DIRT_CHIPS])
		quad.size = quad_size
		process.scale_min = WHEEL_PARTICLES.LEAF_SIZE if foliage else 0.10
		process.scale_max = WHEEL_PARTICLES.LEAF_SIZE if foliage else 0.24
		process.scale_curve = null if foliage else emitter.get_meta("impact_scale_curve")
		emitter.lifetime = 0.19 if spark else 0.32
		emitter.amount = 3 + roundi(severity * 5.0) if spark else 2 + roundi(severity * 4.0)
		process.particle_flag_align_y = spark
		process.gravity = Vector3(0.0, -6.5 if spark else -9.8, 0.0)
		process.spread = 19.0 if spark else 55.0
		process.angle_min = -180.0
		process.angle_max = 180.0
		process.color = effect_color
		process.direction = effect.get("direction", (normal + Vector3.UP * 0.35).normalized())
		process.initial_velocity_min = 0.8
		process.initial_velocity_max = 2.5 + severity * 2.0
		emitter.global_transform = Transform3D(Basis.IDENTITY, point + normal * 0.04)
		emitter.amount_ratio = clampf(intensity, 0.25, 1.0)
		emitter.restart()
		emitter.emitting = true
		impact_busy[i] = emitter.lifetime + 0.12
		emitted_impacts += 1
		return


func clear_wheel_bursts() -> void:
	wheel_particles.clear()
	wheel_particle_accumulator = 0.0
	exhaust_ticks = 0
	rain_splat_ticks = 0
	wheel_cooldowns.fill(0.0)
	wheel_snow_haze.fill(0.0)
	wheel_previous_surface.fill("")
	wheel_was_wet.fill(false)
	wheel_has_previous_point.fill(false)


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
	_cached_weather_condition = {}


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
	material.set_shader_parameter("particle_texture", RADIATOR_STEAM)
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
