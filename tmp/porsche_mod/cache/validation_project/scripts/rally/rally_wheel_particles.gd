extends Node3D
## Partículas de ruedas / escape / cristales con estética de rally retro de los 90.
##
## El "look" se elige con `look`:
##   MODERN  -> comportamiento original (sin estilización).
##   CMR2    -> Colin McRae Rally 2.0: polvo grueso y opaco, color de 15 bits,
##              bandas de color por vida, sombreado plano, jitter de vértices sutil.
##   VRALLY2 -> V-Rally 2: más saturado y contrastado, sprites más "chunky",
##              actualización a 25 Hz sin interpolación, bandas más marcadas.
##
## Son aproximaciones estilísticas, no réplicas exactas de cada motor.

const CAPACITY := 400
# The original race loop advances particles on the player car's 25 Hz step.
const STEP := 1.0 / 25.0
const SHADER := preload("res://scripts/rally/rally_vehicle_vfx.gdshader")

enum Kind {
	DUST,
	DIRT_DUST,
	SAND_DUST,
	SLIP_DUST,
	SMOKE,
	SPLASH,
	WATER,
	SNOW,
	LEAF,
	GRASS,
	GRASS_SHORT,
	ROCK,
	MUD,
	EXHAUST,
	BACKFIRE,
	GLASS,
	RAIN_SPLAT,
}

enum Look {
	MODERN,
	CMR2,
	VRALLY2,
}

# ---------------------------------------------------------------------------
# Presets de estilo retro
# ---------------------------------------------------------------------------
# snap             Rejilla (m) a la que se ajusta la posición: jitter tipo PS1. 0 = off.
# fraction_steps   Subpasos de interpolación entre ticks de 25 Hz. 0 = continuo,
#                  1 = sin interpolación (movimiento a saltos de 25 Hz).
# size_steps       Niveles discretos de crecimiento del sprite. 0 = continuo.
# alpha_steps      Niveles discretos de desvanecimiento. 0 = continuo.
# color_bits       Bits por canal (5 = color de 15 bits PS1). 8 = sin cuantizar.
# angle_steps      Ángulos de rotación permitidos (8 = múltiplos de 45°). 0 = libre.
# ramps            Usa rampas de color escalonadas según la edad de la partícula.
# shade_var        Cuánto varía el brillo plano por partícula (0..1).
# cloud_scale      Escala de polvo/humo. debris_scale: escala de piedras/barro/etc.
# alpha_boost      Multiplicador de opacidad (el polvo retro es más "sólido").
# saturation / contrast  Gradación de color.
# soft_particles   Intersección suave con el suelo (los juegos retro cortan duro).
# dither           Intensidad del dither, solo si el shader declara `dither_strength`.
const LOOKS := {
	Look.MODERN: {
		"snap": 0.0,
		"fraction_steps": 0,
		"size_steps": 0,
		"alpha_steps": 0,
		"color_bits": 8,
		"angle_steps": 0,
		"ramps": false,
		"shade_var": 0.0,
		"cloud_scale": 1.0,
		"debris_scale": 1.0,
		"alpha_boost": 1.0,
		"saturation": 1.0,
		"contrast": 1.0,
		"soft_particles": true,
		"dither": 0.0,
	},
	Look.CMR2: {
		"snap": 1.0 / 32.0,
		"fraction_steps": 2,
		"size_steps": 6,
		"alpha_steps": 5,
		"color_bits": 5,
		"angle_steps": 8,
		"ramps": true,
		"shade_var": 0.6,
		"cloud_scale": 1.2,
		"debris_scale": 1.5,
		"alpha_boost": 1.25,
		"saturation": 1.15,
		"contrast": 1.10,
		"soft_particles": false,
		"dither": 0.5,
	},
	Look.VRALLY2: {
		"snap": 1.0 / 16.0,
		"fraction_steps": 1,
		"size_steps": 4,
		"alpha_steps": 4,
		"color_bits": 5,
		"angle_steps": 8,
		"ramps": true,
		"shade_var": 1.0,
		"cloud_scale": 1.1,
		"debris_scale": 1.8,
		"alpha_boost": 1.4,
		"saturation": 1.35,
		"contrast": 1.20,
		"soft_particles": false,
		"dither": 1.0,
	},
}

# Rampas de color escalonadas (sin interpolar) de "recién emitida" a "vieja".
# Dan las bandas de paleta típicas de los sprites de 16/32 bits.
const RAMPS := {
	Kind.DUST: [
		Color8(214, 184, 142),
		Color8(178, 146, 112),
		Color8(152, 126, 102),
		Color8(128, 108, 92),
	],
	Kind.DIRT_DUST: [Color8(176, 120, 76), Color8(150, 98, 62), Color8(120, 84, 60)],
	Kind.SAND_DUST: [Color8(240, 214, 150), Color8(220, 186, 124), Color8(196, 166, 120)],
	Kind.SLIP_DUST: [Color8(226, 208, 178), Color8(190, 170, 142), Color8(160, 142, 120)],
	Kind.SMOKE: [Color8(236, 236, 240), Color8(190, 194, 204), Color8(140, 146, 158)],
	Kind.EXHAUST: [Color8(255, 255, 255), Color8(220, 224, 232), Color8(170, 176, 188)],
	Kind.BACKFIRE: [
		Color8(255, 255, 224),
		Color8(255, 206, 72),
		Color8(255, 120, 24),
		Color8(200, 48, 16),
	],
	Kind.SPLASH: [Color8(232, 238, 242), Color8(200, 212, 222), Color8(168, 184, 198)],
}

# Lifetimes are visual ticks. Dust follows the 8/10 templates and gravel
# follows the 0x1D/0x1E floor-bounce path in CMR2's StageTiming.cpp.
# StageTiming.cpp:6316–6365. The leaf/grass size ranges have an inverted
# upper bound. ParticleEdit_SetSizeRange keeps the first value in that case.
const FOLIAGE_TICKS := 0xC8
const LEAF_SIZE := 1.0 * (0xCCCC / 65536.0) * (0x1999 / 65536.0)
const GRASS_SIZE := 1.0 * (0x18000 / 65536.0) * (0x1999 / 65536.0)
const SHORT_GRASS_SIZE := 1.0 * (0x18000 / 65536.0) * (0x147A / 65536.0)
const FOLIAGE_SPIN := TAU * 0x71 / 4096.0 / STEP
const TYPES := {
	Kind.DUST: {
		"color": Color8(152, 126, 102),
		"ticks": 50,
		"size": Vector2(0.42, 2.10),
		"alpha": 100.0 / 255.0,
		"gravity": -0.32,
		"drag": 1.2,
	},
	Kind.DIRT_DUST: {
		"color": Color(0.60, 0.39, 0.24),
		"ticks": 46,
		"size": Vector2(0.38, 1.80),
		"alpha": 0.43,
		"gravity": -0.26,
		"drag": 1.4,
	},
	Kind.SAND_DUST: {
		"color": Color(0.86, 0.72, 0.47),
		"ticks": 54,
		"size": Vector2(0.44, 2.20),
		"alpha": 0.40,
		"gravity": -0.36,
		"drag": 1.1,
	},
	Kind.SLIP_DUST: {
		"color": Color(0.74, 0.66, 0.56),
		"ticks": 33,
		"size": Vector2(0.22, 0.83),
		"alpha": 100.0 / 255.0,
		"gravity": -0.32,
		"drag": 0.0,
	},
	Kind.SMOKE: {
		"color": Color(0.71, 0.74, 0.78),
		"ticks": 34,
		"size": Vector2(0.16, 0.68),
		"alpha": 0.32,
		"gravity": -0.15,
		"drag": 1.0,
	},
	Kind.SPLASH: {
		"color": Color(0.82, 0.90, 0.96),
		"ticks": 17,
		"size": Vector2(0.20, 0.83),
		"alpha": 0.65, # antes 1.0
		"gravity": 2.5, # antes 0.0: ahora el spray cae
		"drag": 0.6, # antes 0.0: se frena al avanzar
	},
	Kind.WATER: {
		"color": Color(0.76, 0.87, 0.96),
		"ticks": 25,
		"size": Vector2(0.16, 0.36),
		"alpha": 0.75,
		"gravity": 7.0,
		"drag": 0.0,
	},
	Kind.SNOW: {
		"color": Color(0.90, 0.95, 1.0),
		"ticks": 35,
		"size": Vector2(0.18, 0.52),
		"alpha": 0.82,
		"gravity": 2.0,
		"drag": 0.8,
	},
	Kind.LEAF: {
		"cmr2_ids": [0x10, 0x11],
		"frames": 5,
		"frame_delay": 2,
		"frame_ticks": 1,
		"color": Color(0.48, 0.53, 0.14),
		"ticks": FOLIAGE_TICKS,
		"size": Vector2(LEAF_SIZE, LEAF_SIZE),
		"alpha": 1.0,
		"gravity": 4.0,
		"drag": 0.7,
		"cutout": true,
	},
	Kind.GRASS: {
		"cmr2_ids": [0x12, 0x13, 0x14, 0x15],
		"frames": 2,
		"frame_delay": 4,
		"frame_ticks": 4,
		"color": Color(0.24, 0.43, 0.08),
		"ticks": FOLIAGE_TICKS,
		"size": Vector2(GRASS_SIZE, GRASS_SIZE),
		"alpha": 1.0,
		"gravity": 4.0,
		"drag": 0.7,
		"cutout": true,
	},
	Kind.GRASS_SHORT: {
		"cmr2_ids": [0x16, 0x17],
		"frames": 2,
		"frame_delay": 4,
		"frame_ticks": 4,
		"color": Color(0.37, 0.47, 0.10),
		"ticks": FOLIAGE_TICKS,
		"size": Vector2(SHORT_GRASS_SIZE, SHORT_GRASS_SIZE),
		"alpha": 1.0,
		"gravity": 4.0,
		"drag": 0.7,
		"cutout": true,
	},
	Kind.ROCK: {
		"cutout": true,
		"color": Color(0.63, 0.56, 0.46),
		"ticks": 15,
		"size": Vector2(0.10, 0.10),
		"alpha": 1.0,
		"gravity": 9.0,
		"drag": 0.0,
	},
	Kind.MUD: {
		"cutout": true,
		"color": Color(0.44, 0.31, 0.19),
		"ticks": 25,
		"size": Vector2(0.14, 0.14),
		"alpha": 1.0,
		"gravity": 13.0,
		"drag": 0.0,
	},
	Kind.EXHAUST: {
		"color": Color.WHITE,
		"ticks": 27,
		"size": Vector2(0.04, 0.42),
		"alpha": 80.0 / 255.0,
		"gravity": -0.18,
		"drag": 1.0,
	},
	Kind.BACKFIRE: {
		"color": Color(1.0, 0.85, 0.58),
		"ticks": 4,
		"size": Vector2(0.16, 0.28),
		"alpha": 1.0,
		"gravity": 0.0,
		"drag": 0.0,
	},
	Kind.GLASS: {
		"color": Color(0.78, 0.88, 0.95),
		"ticks": 26,
		"size": Vector2(0.11, 0.11),
		"alpha": 1.0,
		"gravity": 9.8,
		"drag": 0.0,
	},
	Kind.RAIN_SPLAT: {
		"color": Color(0.84, 0.91, 1.0),
		"ticks": 14,
		"size": Vector2(0.14, 0.32),
		"alpha": 0.65,
		"gravity": 0.0,
		"drag": 0.0,
	},
}
const DUST_KINDS := [Kind.DUST, Kind.DIRT_DUST, Kind.SAND_DUST, Kind.SLIP_DUST]
const CLOUD_KINDS := [
	Kind.DUST,
	Kind.DIRT_DUST,
	Kind.SAND_DUST,
	Kind.SLIP_DUST,
	Kind.SMOKE,
	Kind.EXHAUST,
	Kind.SPLASH,
]
const DEBRIS_KINDS := [Kind.ROCK, Kind.MUD, Kind.GLASS, Kind.WATER, Kind.SNOW]
# Variaciones de brillo plano por partícula (sombreado "cel" barato).
const SHADES := [0.88, 1.0, 1.12]


class Particle:
	var kind: Kind
	var texture: Texture2D
	var previous: Vector3
	var position: Vector3
	var velocity: Vector3
	var floor_point: Vector3
	var floor_normal: Vector3
	var ticks := 0
	var frame_offset := 0
	var size_factor := 1.0
	var spin := 0.0
	var angle := 0.0
	var shade := 1.0
	var bounced := false
	var intensity := 1.0


@export var look: Look = Look.VRALLY2:
	set(value):
		look = value
		_cfg = LOOKS[value]
		_restyle_batches()

var particles: Array[Particle] = []
var batches: Dictionary = { }
var batch_kinds: Dictionary = { }
var next_slot := 0
var rng := RandomNumberGenerator.new()
# RNG aparte para el estilo: no altera la secuencia determinista original.
var style_rng := RandomNumberGenerator.new()
var _cfg: Dictionary = LOOKS[Look.CMR2]
var _shader_uniforms: Dictionary = { }


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	rng.seed = 0x434d5232
	style_rng.seed = 0x56524c32
	_cfg = LOOKS[look]
	for u in SHADER.get_shader_uniform_list():
		_shader_uniforms[u.name] = true
	for i in CAPACITY:
		particles.append(Particle.new())
	_restyle_batches()


func emit_particle(
	kind: Kind,
	texture: Texture2D,
	point: Vector3,
	velocity: Vector3,
	floor_point: Vector3,
	floor_normal: Vector3,
	intensity: float = 1.0,
) -> void:
	var slot := next_slot
	var oldest_age := -1
	for i in CAPACITY:
		var candidate := (next_slot + i) % CAPACITY
		var existing := particles[candidate]
		if existing.ticks == 0:
			slot = candidate
			break
		var age := int(TYPES[existing.kind].ticks) - existing.ticks
		if age > oldest_age:
			oldest_age = age
			slot = candidate
	next_slot = (slot + 1) % CAPACITY
	var p := particles[slot]
	p.kind = kind
	p.texture = texture
	p.previous = point
	p.position = point
	p.velocity = velocity
	p.floor_point = floor_point
	p.floor_normal = floor_normal
	p.intensity = intensity
	var profile: Dictionary = TYPES[kind]
	var foliage := profile.has("frame_delay")
	p.ticks = int(profile.ticks)
	p.frame_offset = 0
	if foliage:
		p.frame_offset = rng.randi_range(0, int(profile.frames) - 1)
	elif kind in DUST_KINDS and kind != Kind.SLIP_DUST:
		p.frame_offset = rng.randi_range(0, 7)
	p.size_factor = 1.0 if foliage else rng.randf_range(0.82, 1.18)
	p.spin = (
		FOLIAGE_SPIN
		if foliage
		else (rng.randf_range(-5.0, 5.0) if kind == Kind.GLASS else 0.0)
	)
	p.angle = rng.randf_range(-PI, PI) if foliage or kind in [Kind.ROCK, Kind.MUD, Kind.GLASS] else 0.0
	p.shade = SHADES[style_rng.randi_range(0, SHADES.size() - 1)]
	p.bounced = false
	if not batches.has(texture):
		_make_batch(texture, kind)


func step(wind: Vector3) -> void:
	for p in particles:
		if p.ticks == 0:
			continue
		p.ticks -= 1
		p.previous = p.position
		var profile: Dictionary = TYPES[p.kind]
		p.velocity = p.velocity.lerp(wind, float(profile.drag) * STEP)
		p.velocity.y -= float(profile.gravity) * STEP
		p.position += p.velocity * STEP
		p.angle += p.spin * STEP
		var height := (p.position - p.floor_point).dot(p.floor_normal)
		if height >= 0.0:
			continue
		if p.kind in [Kind.ROCK, Kind.MUD]:
			p.position -= p.floor_normal * height
			var vertical := p.velocity.dot(p.floor_normal)
			if vertical < 0.0:
				var rebound := -vertical * 0.7
				p.velocity -= p.floor_normal * vertical
				if rebound > 0.20:
					p.velocity += p.floor_normal * rebound
				p.bounced = true
		elif bool(profile.get("cutout", false)) or p.kind in [Kind.WATER, Kind.SNOW, Kind.GLASS]:
			p.ticks = 0


func dust_frame(p: Particle) -> int:
	var age := int(TYPES[p.kind].ticks) - p.ticks
	var frame := p.frame_offset + (age >> 1)
	return mini(frame, 7) if p.kind == Kind.SLIP_DUST else frame % 8


func draw_particles(fraction: float, world_to_vehicle: Transform3D, soften: bool) -> void:
	var snap: float = _cfg.snap
	var fraction_steps: int = _cfg.fraction_steps
	var size_steps: int = _cfg.size_steps
	var alpha_steps: int = _cfg.alpha_steps
	var angle_steps: int = _cfg.angle_steps
	var alpha_boost: float = _cfg.alpha_boost
	var cloud_scale: float = _cfg.cloud_scale
	var debris_scale: float = _cfg.debris_scale
	var retro := look != Look.MODERN

	# Interpolación recortada a subpasos: el movimiento "salta" como en los 90.
	if fraction_steps > 0:
		fraction = ceilf(fraction * fraction_steps) / float(fraction_steps)

	var draw_counts: Dictionary = { }
	for texture in batches:
		draw_counts[texture] = 0
		var batch: MultiMesh = batches[texture]
		var kind: Kind = batch_kinds[texture]
		var soft_here := soften and (bool(_cfg.soft_particles) or kind == Kind.SPLASH)
		var material := batch.mesh.surface_get_material(0) as ShaderMaterial
		material.set_shader_parameter("world_to_vehicle", world_to_vehicle)
		material.set_shader_parameter("soft_intersection_metres", 0.15 if soft_here else 0.0)

	for p in particles:
		if p.ticks == 0:
			continue
		var batch: MultiMesh = batches[p.texture]
		var slot: int = draw_counts[p.texture]
		var profile: Dictionary = TYPES[p.kind]
		var progress := 1.0 - float(p.ticks) / float(profile.ticks)

		# --- Frame de sprite ---
		var frame := dust_frame(p) if p.kind in DUST_KINDS else 0
		if profile.has("frame_delay"):
			var age := int(profile.ticks) - p.ticks
			var delay := int(profile.frame_delay)
			if age > delay:
				frame = (p.frame_offset + int(float(age - delay) / float(profile.frame_ticks))) % int(
					profile.frames
				)
		elif p.kind == Kind.BACKFIRE:
			frame = int(profile.ticks) - p.ticks

		# --- Tamaño: crecimiento en escalones + escala retro ---
		var sizes: Vector2 = profile.size
		var size := lerpf(sizes.x, sizes.y, _stepped(progress, size_steps)) * p.size_factor
		size *= lerpf(0.6, 1.0, p.intensity)
		if p.kind in CLOUD_KINDS:
			size *= cloud_scale
		elif p.kind in DEBRIS_KINDS:
			size *= debris_scale
		if retro and p.kind == Kind.BACKFIRE and frame % 2 == 1:
			size *= 0.75 # parpadeo del fogonazo

		# --- Posición: interpolación recortada + snap a rejilla (jitter) ---
		var position := p.previous.lerp(p.position, fraction)
		if snap > 0.0:
			position = position.snapped(Vector3.ONE * snap)

		# --- Opacidad: desvanecimiento en bandas ---
		var constant_alpha := (
			bool(profile.get("cutout", false)) or p.kind == Kind.SLIP_DUST
			or (retro and p.kind == Kind.BACKFIRE)
		)
		var fade := 1.0
		if not constant_alpha:
			fade = (
				1.0 - progress
				if alpha_steps <= 0
				else 1.0 - floorf(progress * alpha_steps) / float(alpha_steps)
			)
		var alpha := clampf(float(profile.alpha) * alpha_boost * fade * lerpf(0.5, 1.0, p.intensity), 0.0, 1.0)

		# --- Rotación: ángulos discretos ---
		var angle := p.angle
		if angle_steps > 0:
			angle = snappedf(angle, TAU / float(angle_steps))

		batch.set_instance_transform(
			slot,
			Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), position),
		)
		batch.set_instance_color(slot, _particle_color(p, profile, progress, alpha))
		batch.set_instance_custom_data(slot, Color(angle, float(frame), 0.0, 0.0))
		draw_counts[p.texture] = slot + 1
	for texture in batches:
		batches[texture].visible_instance_count = draw_counts[texture]


func clear() -> void:
	for p in particles:
		p.ticks = 0
	for batch in batches.values():
		batch.visible_instance_count = 0
	next_slot = 0
	rng.seed = 0x434d5232
	style_rng.seed = 0x56524c32


# ---------------------------------------------------------------------------
# Estilo
# ---------------------------------------------------------------------------
## Cuantiza t (0..1) en `steps` niveles; el último nivel se alcanza en el último tramo.
func _stepped(t: float, steps: int) -> float:
	if steps <= 1:
		return t
	return minf(floorf(t * steps) / float(steps - 1), 1.0)


func _particle_color(p: Particle, profile: Dictionary, progress: float, alpha: float) -> Color:
	var base: Color = profile.color
	if bool(_cfg.ramps) and RAMPS.has(p.kind):
		var ramp: Array = RAMPS[p.kind]
		base = ramp[mini(int(progress * ramp.size()), ramp.size() - 1)]
	return Color(_grade(base, p.shade), alpha)


## Gradación retro: saturación, contraste, brillo plano por partícula y paleta reducida.
func _grade(c: Color, shade: float) -> Color:
	if look == Look.MODERN:
		return c
	var saturation: float = _cfg.saturation
	var contrast: float = _cfg.contrast
	var brightness := lerpf(1.0, shade, float(_cfg.shade_var))
	var gray := c.get_luminance()
	var rgb := Vector3(c.r, c.g, c.b)
	rgb = Vector3.ONE * gray + (rgb - Vector3.ONE * gray) * saturation
	rgb = ((rgb - Vector3.ONE * 0.5) * contrast + Vector3.ONE * 0.5) * brightness
	var bits: int = _cfg.color_bits
	var out := Color(clampf(rgb.x, 0.0, 1.0), clampf(rgb.y, 0.0, 1.0), clampf(rgb.z, 0.0, 1.0))
	if bits < 8:
		var levels := float((1 << bits) - 1)
		out = Color(
			roundf(out.r * levels) / levels,
			roundf(out.g * levels) / levels,
			roundf(out.b * levels) / levels,
		)
	return out


func _restyle_batches() -> void:
	for texture in batches:
		var batch: MultiMesh = batches[texture]
		_apply_material_style(
			batch.mesh.surface_get_material(0) as ShaderMaterial,
			batch_kinds[texture],
		)


func _apply_material_style(material: ShaderMaterial, kind: Kind) -> void:
	# Parámetros opcionales: solo se aplican si el shader los declara.
	var bits: int = _cfg.color_bits
	_set_optional(material, "dither_strength", float(_cfg.dither))
	_set_optional(material, "color_levels", float((1 << bits) - 1))
	_set_optional(material, "nearest_filter", look != Look.MODERN)


func _set_optional(material: ShaderMaterial, uniform_name: String, value: Variant) -> void:
	if _shader_uniforms.has(uniform_name):
		material.set_shader_parameter(uniform_name, value)


func _make_batch(texture: Texture2D, kind: Kind) -> void:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("particle_texture", texture)
	material.set_shader_parameter("manual_particle_state", true)
	material.set_shader_parameter("opaque_sprite_mask", bool(TYPES[kind].get("cutout", false)))
	var frames := float(TYPES[kind].get("frames", 1))
	if kind in DUST_KINDS:
		frames = 8.0
	elif kind == Kind.BACKFIRE:
		frames = 4.0
	if texture.resource_path.begins_with("res://assets/vfx/cmr4/"):
		frames = 1.0
	material.set_shader_parameter("sprite_frames", frames)
	_apply_material_style(material, kind)
	var mesh := QuadMesh.new()
	mesh.material = material
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.use_custom_data = true
	batch.mesh = mesh
	batch.instance_count = CAPACITY
	batch.visible_instance_count = 0
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = batch
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	batches[texture] = batch
	batch_kinds[texture] = kind
