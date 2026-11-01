class_name RallyVehicleAudio
extends Node3D


# Estructura tipada en memoria para evitar llamadas costosas a get_meta/set_meta en _physics_process
class SampleVoice:
	var player: AudioStreamPlayer3D
	var reference_rpm: float
	var lower_rpm: float
	var upper_rpm: float
	var is_exhaust: bool
	var level_gain: float
	var base_gain: float
	var acceleration_gain: float
	var blend_weight: float = 0.0
	var layer_level: float = 0.0


const ENGINE_SAMPLE_DEFINITIONS := [
	{
		"path": "res://sounds/banks/ford_escort_rs2000_rally/EE_Idle5.wav",
		"reference": 900.0,
		"lower": 0.0,
		"upper": 2000.0,
	},
	{
		"path": "res://sounds/banks/ford_escort_rs2000_rally/EE_2k5.wav",
		"reference": 2000.0,
		"lower": 0.0,
		"upper": 3500.0,
	},
	{
		"path": "res://sounds/banks/ford_escort_rs2000_rally/EE_6k5.wav",
		"reference": 4000.0,
		"lower": 2500.0,
		"upper": 5500.0,
	},
	{
		"path": "res://sounds/banks/ford_escort_rs2000_rally/EE_9k5.wav",
		"reference": 6000.0,
		"lower": 4500.0,
		"upper": 9500.0,
	},
]
const EXHAUST_SAMPLE_DEFINITIONS := [
	{
		"path": "res://sounds/banks/ford_escort_rs2000_rally/EX_Idle6.wav",
		"reference": 900.0,
		"lower": 0.0,
		"upper": 2000.0,
	},
	{
		"path": "res://sounds/banks/ford_escort_rs2000_rally/EX_Idle6.wav",
		"reference": 2000.0,
		"lower": 0.0,
		"upper": 3500.0,
	},
	{
		"path": "res://sounds/banks/ford_escort_rs2000_rally/EX_6k5.wav",
		"reference": 4000.0,
		"lower": 2500.0,
		"upper": 5500.0,
	},
	{
		"path": "res://sounds/banks/ford_escort_rs2000_rally/EX_9k5.wav",
		"reference": 6000.0,
		"lower": 4500.0,
		"upper": 9500.0,
	},

]
const NEUTRAL_SAMPLE_PATH := "res://sounds/banks/commons/neutral_first_gear_transition.wav"
const NEUTRAL_FADE_WIDTH := 0.15

const GEAR_UP_PATHS := [
	"res://sounds/banks/commons/gear_up_1.wav",
	"res://sounds/banks/commons/gear_up_2.wav",
	"res://sounds/banks/commons/gear_up_3.wav",
]
const GEAR_DOWN_PATHS := [
	"res://sounds/banks/commons/gear_down_1.wav",
	"res://sounds/banks/commons/gear_down_2.wav",
	"res://sounds/banks/commons/gear_down_3.wav",
]
const GEAR_WHINE_PATH := "res://sounds/banks/ford_escort_rs2000_rally/whine.wav"
# Colin McRae Rally 2 — banco del Escort Cosworth, mismos roles que el original:
# Retención al levantar y detonaciones puntuales; motor/escape RT son la base.
const COS_RETENTION_FRONT := "res://sounds/banks/ford_escort_rs2000_rally/fm-cos.wav"
const COS_RETENTION_REAR := "res://sounds/banks/ford_escort_rs2000_rally/rm-cos.wav"
const RETENTION_FRONT_GAIN := 0.05
const RETENTION_REAR_GAIN := 0.06
const BACKFIRE_SAMPLE_PATHS := [
	"res://sounds/banks/ford_escort_rs2000_rally/det1.wav",
	"res://sounds/banks/ford_escort_rs2000_rally/det2.wav",
	"res://sounds/banks/ford_escort_rs2000_rally/det3.wav",
	"res://sounds/banks/ford_escort_rs2000_rally/det4.wav",
]
# Probabilidad de pop al soltar, por marcha (CMR2: mas probable en cortas).
const BACKFIRE_GEAR_PROB := [0.5, 0.9, 0.65, 0.4, 0.2]
const BACKFIRE_VOLUME_DB := -10.0

const BACKFIRE_POSITION := Vector3(0.0, 0.20, 1.50)
const SHIFT_EVENT_POSITION := Vector3(0.0, 0.6, 0.4)
const UPSHIFT_RETRIGGER_SECONDS := 0.03
const DOWNSHIFT_RETRIGGER_SECONDS := 0.10
const BACKFIRE_RETRIGGER_SECONDS := 1.0
const LIMITER_SAMPLE_PATH := "res://sounds/banks/commons/limiter_cut_loop.wav"
const LIMITER_NATIVE_RPM := 18000.0
const LIMITER_GAIN := 0.30
const SURFACE_GAIN := 0.45
# Balance por camara (estilo CMR2: fuera/dentro conmutan el peso motor/escape).
# Chase trasera: el escape manda; capo (encima del motor): se contiene el motor.
const VIEW_ENGINE_GAIN := [1.0, 0.6]
const VIEW_EXHAUST_GAIN := [1.1, 0.8]

const IMPACT_SMALL_PATHS := [
	"res://sounds/banks/commons/impact_small_1.wav",
	"res://sounds/banks/commons/impact_small_2.wav",
	"res://sounds/banks/commons/impact_small_3.wav",
]
const IMPACT_MEDIUM_PATHS := [
	"res://sounds/banks/commons/impact_medium_1.wav",
	"res://sounds/banks/commons/impact_medium_2.wav",
]
const IMPACT_LARGE_PATHS := ["res://sounds/banks/commons/impact_large.wav"]
const IMPACT_SMALL_KPH := 40.0
const IMPACT_LARGE_KPH := 70.0
const IMPACT_MIN_KPH := 5.0
const IMPACT_POSITION_CLAMP := Vector3(1.2, 1.2, 2.4)
# Tomas de tierra CMR2 (land1-3): voz dedicada por velocidad vertical de
# caida, con prioridad sobre el impacto generico (comparten cooldown).
const IMPACT_LAND_PATHS := [
	"res://sounds/banks/commons/impact_land_1.wav",
	"res://sounds/banks/commons/impact_land_2.wav",
	"res://sounds/banks/commons/impact_land_3.wav",
]
const LAND_VOLUME_DB := [-14.0, -11.0, -8.0]
const LAND_MIN_MS := 2.5
const LAND_MID_MS := 4.0
const LAND_HIGH_MS := 7.0
const LAND_POSITION := Vector3(0.0, -0.2, 0.0)
const SCRUB_SAMPLE_PATH := "res://sounds/banks/commons/tyre_scrub.wav"

const ENGINE_VOLUME_BASE := 0.24
const ENGINE_VOLUME_ACCELERATION := 0.10
const EXHAUST_VOLUME_BASE := 0.70
const EXHAUST_VOLUME_ACCELERATION := 0.30
# Desplazamiento del banco de samples bajo carga (cambia el timbre hacia samples más altos sin falsear el pitch)
const LOAD_TIMBRE_RPM_OFFSET := 380.0

@export var vehicle_path: NodePath
@export var impact_cooldown_seconds: float = 0.25

var vehicle: RallyEscortVehicle
var engine_voices: Array[SampleVoice] = []
var exhaust_voices: Array[SampleVoice] = []
var neutral_player: AudioStreamPlayer3D
var clunk_scale: float = 1.0
var packet_rpm_idle: float = 1050.0
var scrub_player: AudioStreamPlayer3D
var impact_small_players: Array[AudioStreamPlayer3D] = []
var impact_medium_players: Array[AudioStreamPlayer3D] = []
var impact_large_players: Array[AudioStreamPlayer3D] = []
var land_players: Array[AudioStreamPlayer3D] = []
var smoothed_revolutions: float = 1800.0
var current_slip_ratio: float = 0.0
var impact_cooldown: float = 0.0

var upshift_players: Array[AudioStreamPlayer3D] = []
var downshift_players: Array[AudioStreamPlayer3D] = []
var backfire_players: Array[AudioStreamPlayer3D] = []
var upshift_cooldown: float = 0.0
var downshift_cooldown: float = 0.0
var backfire_event_cooldown: float = 0.0
var upshift_rr_index: int = 0
var downshift_rr_index: int = 0
var backfire_rng_state: int = 1

var policy := VehicleAudioMixPolicy.new()
var routing := VehicleSoundRouting.new()
var acoustic: Dictionary = { }
var accepted_sequence: int = -1
var accepted_generation: int = -1
var surface_players: Dictionary = { }
var scrape_player: AudioStreamPlayer3D
var limiter_player: AudioStreamPlayer3D
var whine_players: Array[AudioStreamPlayer3D] = []
var retention_front_player: AudioStreamPlayer3D
var retention_rear_player: AudioStreamPlayer3D
var impact_index: int = 0
var exhaust_crackle_s: float = 0.0
var sample_levels: Dictionary = { }
var camera_rig: Node = null
var view_engine_gain := 1.0
var view_exhaust_gain := 1.0


func _ready() -> void:
	vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	if vehicle == null:
		push_error("Rally audio cannot resolve its vehicle: " + str(vehicle_path))
		set_physics_process(false)
		return
	var level_file := FileAccess.open("res://data/rally/audio_sample_levels.json", FileAccess.READ)
	if level_file != null:
		var parsed: Variant = JSON.parse_string(level_file.get_as_text())
		if parsed is Dictionary:
			sample_levels = parsed.get("samples", { })

	build_sample_layer(
		ENGINE_SAMPLE_DEFINITIONS,
		engine_voices,
		Vector3(0.0, 0.55, -0.8),
		3.0,
		400.0,
		ENGINE_VOLUME_BASE,
		ENGINE_VOLUME_ACCELERATION,
		false,
	)
	build_sample_layer(
		EXHAUST_SAMPLE_DEFINITIONS,
		exhaust_voices,
		Vector3(0.0, 0.20, 1.50),
		8.0,
		1030.0,
		EXHAUST_VOLUME_BASE,
		EXHAUST_VOLUME_ACCELERATION,
		true,
	)
	build_neutral_player()
	build_scrub_player()
	build_impact_players()
	build_auxiliary_audio()
	play_layer(engine_voices)
	play_layer(exhaust_voices)


func build_sample_layer(
	definitions: Array,
	voices: Array[SampleVoice],
	local_position: Vector3,
	unit_size: float,
	maximum_distance: float,
	base_gain: float,
	acceleration_gain: float,
	is_exhaust: bool,
) -> void:
	for definition in definitions:
		var path_str := str(definition["path"])
		var stream := load_looping_stream(path_str)
		if stream == null:
			continue
		var player := AudioStreamPlayer3D.new()
		player.stream = stream
		player.position = local_position
		player.bus = "Vehicle"
		player.volume_db = -80.0
		player.unit_size = unit_size
		player.max_distance = maximum_distance
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(player)

		var voice := SampleVoice.new()
		voice.player = player
		voice.reference_rpm = float(definition["reference"])
		voice.lower_rpm = float(definition["lower"])
		voice.upper_rpm = float(definition["upper"])
		voice.is_exhaust = is_exhaust
		voice.level_gain = float(sample_levels.get(path_str.get_file(), { }).get("gain", 1.0))
		voice.base_gain = base_gain
		voice.acceleration_gain = acceleration_gain
		voices.append(voice)


func load_looping_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var seamless := SeamlessVehicleLoop.load_pcm(path, true, {}, routing.loop_for(path.get_file().get_basename()))
	if seamless != null:
		return seamless
	push_warning("Unsupported PCM loop format: " + path)
	return load(path)


# Contacto neutral/primera como one-shot (no loop): suena una sola vez por
# flanco N<->1, con volumen segun RPM (lleno al ralenti, mudo por encima).
func build_neutral_player() -> void:
	var stream := load_event_stream(NEUTRAL_SAMPLE_PATH, NEUTRAL_SAMPLE_PATH.get_file().get_basename())
	if stream == null:
		return
	neutral_player = AudioStreamPlayer3D.new()
	neutral_player.stream = stream
	neutral_player.position = SHIFT_EVENT_POSITION
	routing.route(neutral_player, NEUTRAL_SAMPLE_PATH.get_file().get_basename())
	neutral_player.volume_db = -11.0
	neutral_player.unit_size = 12.0
	neutral_player.max_distance = 80.0
	neutral_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(neutral_player)


func play_neutral_event() -> void:
	if neutral_player == null:
		return
	var presence := 1.0 - clunk_scale
	if presence < 0.05:
		return
	neutral_player.volume_db = -11.0 + linear_to_db(maxf(presence, 0.001))
	neutral_player.pitch_scale = 1.0
	neutral_player.play()


func update_neutral_audio(_smoothing: float) -> void:
	var idle := maxf(float(packet_rpm_idle), 1.0)
	var rpm := float(acoustic.get("rpm", idle))
	clunk_scale = smoothstep(idle, idle * (1.0 + NEUTRAL_FADE_WIDTH), rpm)


func build_scrub_player() -> void:
	var stream := load_looping_stream(SCRUB_SAMPLE_PATH)
	if stream == null:
		return
	scrub_player = AudioStreamPlayer3D.new()
	scrub_player.stream = stream
	scrub_player.position = Vector3(0.0, 0.1, 0.0)
	routing.route(scrub_player, "tyre_scrub")
	scrub_player.volume_db = -80.0
	scrub_player.unit_size = 14.0
	scrub_player.max_distance = 90.0
	add_child(scrub_player)
	scrub_player.play()


func build_impact_players() -> void:
	build_impact_tier(impact_small_players, IMPACT_SMALL_PATHS, -12.0, 12.0, 120.0)
	build_impact_tier(impact_medium_players, IMPACT_MEDIUM_PATHS, -9.0, 16.0, 160.0)
	build_impact_tier(impact_large_players, IMPACT_LARGE_PATHS, -6.0, 24.0, 240.0)
	for i in IMPACT_LAND_PATHS.size():
		var stream := load_event_stream(IMPACT_LAND_PATHS[i], IMPACT_LAND_PATHS[i].get_file().get_basename())
		if stream == null:
			continue
		var land_player := AudioStreamPlayer3D.new()
		land_player.stream = stream
		land_player.position = LAND_POSITION
		routing.route(land_player, IMPACT_LAND_PATHS[i].get_file().get_basename())
		land_player.volume_db = LAND_VOLUME_DB[i] if i < LAND_VOLUME_DB.size() else -11.0
		land_player.unit_size = 10.0
		land_player.max_distance = 160.0
		land_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		land_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(land_player)
		land_players.append(land_player)


func build_impact_tier(
	players: Array[AudioStreamPlayer3D],
	paths: Array,
	volume_db: float,
	unit_size: float,
	maximum_distance: float,
) -> void:
	for path in paths:
		if not ResourceLoader.exists(path):
			push_warning("Missing commons impact sample: " + str(path))
			continue
		var player := AudioStreamPlayer3D.new()
		player.stream = load_event_stream(path, path.get_file().get_basename())
		if player.stream == null:
			continue
		routing.route(player, path.get_file().get_basename())
		player.volume_db = volume_db
		player.unit_size = unit_size
		player.max_distance = maximum_distance
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(player)
		players.append(player)


func play_layer(voices: Array[SampleVoice]) -> void:
	for voice in voices:
		voice.player.play()


func _physics_process(delta: float) -> void:
	if vehicle == null:
		return
	impact_cooldown = maxf(0.0, impact_cooldown - delta)
	upshift_cooldown = maxf(0.0, upshift_cooldown - delta)
	downshift_cooldown = maxf(0.0, downshift_cooldown - delta)
	backfire_event_cooldown = maxf(0.0, backfire_event_cooldown - delta)
	exhaust_crackle_s = maxf(0.0, exhaust_crackle_s - delta)

	var packet := vehicle.get_presentation_snapshot()
	if packet.is_empty():
		return
	acoustic = policy.accept(packet)
	packet_rpm_idle = float(packet.get("rpm_idle", 1050.0))

	# El pitch sigue las RPM mecánicas reales sin sumar offsets artificiales por pedal
	var real_rpm := float(acoustic.get("rpm", 900.0))
	smoothed_revolutions = lerpf(smoothed_revolutions, real_rpm, 1.0 - exp(-18.0 * delta))
	var smoothing := 1.0 - exp(-24.0 * delta)

	update_view_balance()
	update_layer(engine_voices, smoothed_revolutions, smoothing)
	update_layer(exhaust_voices, smoothed_revolutions, smoothing)
	update_limiter_audio(smoothing)
	update_neutral_audio(smoothing)

	if accepted_generation != int(packet.generation) or accepted_sequence != int(packet.sequence):
		var target_gear := int(packet.get("gear", 1))
		for event in acoustic.get("events", []):
			if event == "neutral_first":
				play_neutral_event()
			elif event == "upshift":
				play_upshift_event(target_gear)
			elif event == "downshift":
				play_downshift_event(target_gear)
			elif event == "backfire":
				play_backfire_event(target_gear)
		accepted_generation = int(packet.generation)
		accepted_sequence = int(packet.sequence)

	if float(vehicle.body_contact_audio.get("landing_speed_ms", 0.0)) >= LAND_MIN_MS:
		play_landing(vehicle)
	elif float(vehicle.body_contact_audio.get("impulse_ns", 0.0)) > vehicle.mass * 0.8:
		play_impact(vehicle)

	update_scrub_audio(delta)

	var speed_kph := float(packet.get("speed_kph", 0.0))
	var active_surface := str(acoustic.get("surface", ""))
	var base_surface_gain := float(acoustic.get("surface_gain", 0.0))
	var speed_ramp := clampf((speed_kph - 2.0) / 25.0, 0.0, 1.0)
	# El deslizamiento lateral incrementa la proyección de piedras/grava contra el chasis
	var slip_boost := 1.0 + current_slip_ratio * 0.45

	for key in surface_players:
		var player: AudioStreamPlayer3D = surface_players[key]
		var is_current: bool = (key == active_surface)
		var target_vol := base_surface_gain * SURFACE_GAIN * speed_ramp * slip_boost if is_current else 0.0
		player.volume_linear = lerpf(player.volume_linear, target_vol, smoothing)
		player.pitch_scale = lerpf(
			player.pitch_scale,
			clampf(0.95 + speed_ramp * 0.15 + current_slip_ratio * 0.20, 0.85, 1.30),
			smoothing,
		)
		player.stream_paused = player.volume_linear < 0.00001

	if scrape_player != null:
		var gain := 0.62 * clampf(
			float(vehicle.body_contact_audio.get("scrape_power_w", 0.0)) / 15000.0,
			0.0,
			1.0,
		)
		scrape_player.volume_linear = lerpf(scrape_player.volume_linear, gain, smoothing)
		scrape_player.stream_paused = scrape_player.volume_linear < 0.00001

	update_whine_audio(smoothing)
	update_retention_audio(smoothing)


#352 vista (chase 0 / capo 1) conmuta el peso motor/escape como en CMR2.
func update_view_balance() -> void:
	if camera_rig == null and vehicle != null and vehicle.get_parent() != null:
		camera_rig = vehicle.get_parent().get_node_or_null("RallyCameraRig")
	var mode := int(camera_rig.get("camera_mode")) if camera_rig != null else 0
	mode = clampi(mode, 0, 1)
	view_engine_gain = VIEW_ENGINE_GAIN[mode]
	view_exhaust_gain = VIEW_EXHAUST_GAIN[mode]


func update_layer(voices: Array[SampleVoice], revolutions: float, volume_smoothing: float) -> void:
	var throttle := clampf(float(acoustic.get("throttle", 0.0)), 0.0, 1.0)
	var load_val := clampf(float(acoustic.get("load", 0.0)), -1.0, 1.0)
	var positive_load := maxf(load_val, 0.0)
	var rpm_norm := clampf(revolutions / 7500.0, 0.0, 1.0)

	# Desplazamos la lectura de pesos bajo carga para abrir el timbre sin alterar el pitch_scale
	var lookup_rpm := revolutions + LOAD_TIMBRE_RPM_OFFSET * positive_load
	var weights := layer_weights(voices, lookup_rpm)

	var energy := 0.0
	for index in voices.size():
		var voice := voices[index]
		voice.blend_weight = lerpf(voice.blend_weight, sqrt(weights[index]), volume_smoothing)
		energy += voice.blend_weight * voice.blend_weight

	var normalization := sqrt(maxf(energy, 0.0000001))

	for index in voices.size():
		var voice := voices[index]
		var gain := 0.0

		if not voice.is_exhaust:
			# Admisión (delantera): responde directamente a la apertura de mariposas (throttle)
			gain = 0.62 * (voice.base_gain + voice.acceleration_gain * throttle)
		else:
			# Escape (trasero): mantiene presencia en retención a altas RPM (overrun) + flujo bajo carga
			var overrun_retention := rpm_norm * 0.45 * (1.0 - throttle)
			var effective_drive := maxf(throttle, overrun_retention)
			gain = 0.62 * (voice.base_gain + voice.acceleration_gain * effective_drive)

			var exhaust_cfg: Dictionary = routing.config.get("exhaust", { })
			var gas_flow := maxf(positive_load, rpm_norm * 0.35)
			gain *= float(exhaust_cfg.get("base_gain", 0.2)) + float(
				exhaust_cfg.get("gas_flow_gain", 0.1)
			) * gas_flow
			if not bool(exhaust_cfg.get("enabled", true)):
				gain = 0.0
			if exhaust_crackle_s > 0.0:
				gain += float(exhaust_cfg.get("crackle_gain", 0.1)) * (exhaust_crackle_s / 0.12)

		voice.layer_level = lerpf(voice.layer_level, gain, volume_smoothing)
		var view_gain := view_exhaust_gain if voice.is_exhaust else view_engine_gain
		voice.player.volume_linear = (voice.blend_weight / normalization) * voice.layer_level * voice.level_gain * view_gain
		voice.player.pitch_scale = clampf(revolutions / voice.reference_rpm, 0.5, 3.5)


func sample_weight(revolutions: float, reference: float, lower: float, upper: float) -> float:
	if revolutions <= reference:
		return clampf((revolutions - lower) / maxf(reference - lower, 1.0), 0.0, 1.0)
	return clampf((upper - revolutions) / maxf(upper - reference, 1.0), 0.0, 1.0)


func play_upshift_event(target_gear: int) -> void:
	upshift_rr_index = _trigger_gear_clunk(upshift_players, target_gear, upshift_rr_index, true)


func play_downshift_event(target_gear: int) -> void:
	downshift_rr_index = _trigger_gear_clunk(
		downshift_players,
		target_gear,
		downshift_rr_index,
		false,
	)


func _trigger_gear_clunk(
	players: Array[AudioStreamPlayer3D],
	target_gear: int,
	rr_index: int,
	is_upshift: bool,
) -> int:
	if players.is_empty() or clunk_scale < 0.05:
		return rr_index
	if is_upshift and upshift_cooldown > 0.0:
		return rr_index
	if not is_upshift and downshift_cooldown > 0.0:
		return rr_index

	# Variante fijada por la marcha destino (1 -> primera, 2 -> segunda, 3+ -> tercera):
	# el up siempre suena a up y el down a down, sin rotar entre tomas.
	var player := players[clampi(target_gear - 1, 0, players.size() - 1)]

	# Tensión mecánica por marcha + micro-jitter determinista para evitar repetición robótica
	var gear_pitch_offset := float(clampi(target_gear, 1, 6) - 3) * 0.022
	var jitter := float((rr_index % 3) - 1) * 0.015
	player.pitch_scale = clampf(1.0 + gear_pitch_offset + jitter, 0.88, 1.15)

	# Escala dinámica según RPM actuales y carga del tren motriz
	var rpm_norm := clampf(float(acoustic.get("rpm", 1000.0)) / 7000.0, 0.2, 1.0)
	var load_stress := absf(float(acoustic.get("load", 0.5)))
	var dynamic_force := lerpf(0.65, 1.18, rpm_norm * 0.65 + load_stress * 0.35)

	player.volume_db = -20.0 + linear_to_db(maxf(clunk_scale * dynamic_force, 0.001))
	player.play()

	if is_upshift:
		upshift_cooldown = UPSHIFT_RETRIGGER_SECONDS
	else:
		downshift_cooldown = DOWNSHIFT_RETRIGGER_SECONDS

	return rr_index + 1


# Detonaciones Cosworth con ciclo de semilla + probabilidad por marcha destino
# (CMR2: mas probable en marchas cortas), manteniendo voice_limit 1.
func play_backfire_event(target_gear: int) -> void:
	if backfire_players.is_empty() or backfire_event_cooldown > 0.0:
		return
	var prob: float = BACKFIRE_GEAR_PROB[clampi(target_gear, 0, BACKFIRE_GEAR_PROB.size() - 1)]
	if randf() > prob:
		return
	backfire_rng_state = _next_rng_state(backfire_rng_state)
	var player := backfire_players[int((backfire_rng_state >> 33) % backfire_players.size())]
	player.pitch_scale = 0.96 + float(backfire_rng_state & 0x03) * 0.025
	player.volume_db = BACKFIRE_VOLUME_DB
	player.play()
	backfire_event_cooldown = BACKFIRE_RETRIGGER_SECONDS
	exhaust_crackle_s = 0.12


func _next_rng_state(state: int) -> int:
	var value := maxi(state, 1)
	value ^= (value << 13) & 0x7FFFFFFFFFFFFFFF
	value ^= value >> 7
	value ^= (value << 17) & 0x7FFFFFFFFFFFFFFF
	return maxi(value & 0x7FFFFFFFFFFFFFFF, 1)


func update_scrub_audio(delta: float) -> void:
	var maximum_slip := 0.0
	for slip in vehicle.get_wheel_slip_vectors():
		maximum_slip = maxf(maximum_slip, absf(slip.x))
		maximum_slip = maxf(maximum_slip, absf(slip.y) * 2.0)

	var speed_factor := clampf(vehicle.speed / 18.0, 0.0, 1.0)
	var slip_factor := clampf((maximum_slip - 0.08) / 0.5, 0.0, 1.0)
	current_slip_ratio = slip_factor

	if scrub_player == null:
		return

	var road := false
	for surface in vehicle.get_wheel_surface_types():
		road = road or str(surface).to_lower() in ["road", "asphalt", "tarmac"]

	var target_gain := speed_factor * slip_factor * 0.55 if road else 0.0
	var volume_smoothing := 1.0 - exp(-15.0 * delta)
	scrub_player.volume_linear = lerpf(scrub_player.volume_linear, target_gain, volume_smoothing)
	scrub_player.pitch_scale = lerpf(
		scrub_player.pitch_scale,
		clampf(0.86 + slip_factor * 0.28 + speed_factor * 0.10, 0.80, 1.25),
		volume_smoothing,
	)
	scrub_player.stream_paused = scrub_player.volume_linear < 0.00001


func play_landing(_other_body: Node) -> void:
	if land_players.is_empty() or impact_cooldown > 0.0:
		return
	var fall := float(vehicle.body_contact_audio.get("landing_speed_ms", 0.0))
	if fall < LAND_MIN_MS:
		return
	var index := 0
	if fall >= LAND_HIGH_MS:
		index = 2
	elif fall >= LAND_MID_MS:
		index = 1
	var player := land_players[clampi(index, 0, land_players.size() - 1)]
	player.pitch_scale = 0.97 + float(impact_index % 3) * 0.015
	player.play()
	impact_index += 1
	impact_cooldown = impact_cooldown_seconds


func play_impact(_other_body: Node) -> void:
	if impact_cooldown > 0.0:
		return
	if float(vehicle.body_contact_audio.get("impulse_ns", 0.0)) <= vehicle.mass * 0.8:
		return
	var speed_kph := float(vehicle.body_contact_audio.get("impact_speed_kph", 0.0))
	if speed_kph < IMPACT_MIN_KPH:
		return
	var players := impact_small_players
	if speed_kph >= IMPACT_LARGE_KPH:
		players = impact_large_players
	elif speed_kph >= IMPACT_SMALL_KPH:
		players = impact_medium_players
	if players.is_empty():
		return
	var player := players[impact_index % players.size()]
	impact_index += 1
	var local := vehicle.body_contact_audio.get("impact_position", Vector3.ZERO) as Vector3
	player.position = Vector3(
		clampf(local.x, -IMPACT_POSITION_CLAMP.x, IMPACT_POSITION_CLAMP.x),
		clampf(local.y, -IMPACT_POSITION_CLAMP.y, IMPACT_POSITION_CLAMP.y),
		clampf(local.z, -IMPACT_POSITION_CLAMP.z, IMPACT_POSITION_CLAMP.z),
	)
	player.pitch_scale = 0.98 + float(impact_index % 3) * 0.02
	player.play()
	impact_cooldown = impact_cooldown_seconds


func build_auxiliary_audio() -> void:
	for key in ["surf_grass", "surf_gravel", "surf_sand", "surf_rumble"]:
		var player := continuous_player("res://sounds/banks/commons/" + key + ".wav")
		if player != null:
			surface_players[key] = player
	scrape_player = continuous_player("res://sounds/banks/commons/impact_scrape.wav")
	limiter_player = build_limiter_player()
	# 2 voces por variante en cambios para no cortar la cola de resonancia en rebajes rápidos
	build_event_voice_pool(
		upshift_players,
		GEAR_UP_PATHS,
		SHIFT_EVENT_POSITION,
		-11.0,
		12.0,
		80.0,
		2,
	)
	build_event_voice_pool(
		downshift_players,
		GEAR_DOWN_PATHS,
		SHIFT_EVENT_POSITION,
		-11.0,
		12.0,
		80.0,
		2,
	)
	build_event_voice_pool(
		backfire_players,
		BACKFIRE_SAMPLE_PATHS,
		BACKFIRE_POSITION,
		-10.0,
		8.0,
		160.0,
		1,
	)
	build_whine_voices()
	build_retention_voices()


# Una sola voz de transmisión, modulada por velocidad de eje y par.
func build_whine_voices() -> void:
	var defs := [
		[GEAR_WHINE_PATH, SHIFT_EVENT_POSITION],
	]
	for entry in defs:
		var stream := load_looping_stream(str(entry[0]))
		if stream == null:
			continue
		var player := AudioStreamPlayer3D.new()
		player.stream = stream
		player.position = entry[1]
		routing.route(player, str(entry[0]).get_file().get_basename())
		player.volume_linear = 0.0
		player.unit_size = 12.0
		player.max_distance = 80.0
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(player)
		player.play()
		whine_players.append(player)


func update_whine_audio(smoothing: float) -> void:
	if whine_players.is_empty():
		return
	var shaft := absf(
		(vehicle.simulation.wheel_spins[2] + vehicle.simulation.wheel_spins[3]) * 0.5
	)
	# La caja de dientes rectos silba cuando está acoplada bajo par (aceleración o retención)
	# y cae a un leve arrastre inercial cuando se pisa el embrague (clutch_open == true)
	var clutch_coupling := 0.12 if bool(acoustic.get("clutch_open", false)) else 1.0
	var torque_stress := absf(float(acoustic.get("load", 0.0)))
	var target := (0.008 + 0.028 * torque_stress) * clampf(shaft / 10.0, 0.0, 1.0) * clutch_coupling
	for index in whine_players.size():
		var player := whine_players[index]
		player.pitch_scale = clampf(shaft / 30.0, 0.5, 3.5)
		player.volume_linear = lerpf(player.volume_linear, target, smoothing)
		player.stream_paused = player.volume_linear < 0.00001


# Retención complementaria, fuera del ralentí.
func build_retention_voices() -> void:
	retention_front_player = build_retention_voice(COS_RETENTION_FRONT, Vector3(0.0, 0.55, -0.8))
	retention_rear_player = build_retention_voice(COS_RETENTION_REAR, BACKFIRE_POSITION)


func build_retention_voice(path: String, local_position: Vector3) -> AudioStreamPlayer3D:
	var stream := load_looping_stream(path)
	if stream == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.position = local_position
	routing.route(player, path.get_file().get_basename())
	player.volume_linear = 0.0
	player.unit_size = 8.0
	player.max_distance = 160.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(player)
	player.play()
	return player


func update_retention_audio(smoothing: float) -> void:
	var rpm_presence := smoothstep(packet_rpm_idle * 1.5, packet_rpm_idle * 3.0, float(acoustic.get("rpm", 0.0)))
	var lift := (1.0 - clampf(float(acoustic.get("throttle", 0.0)), 0.0, 1.0)) * rpm_presence
	if retention_front_player != null:
		retention_front_player.volume_linear = lerpf(retention_front_player.volume_linear, lift * RETENTION_FRONT_GAIN * view_engine_gain, smoothing)
		retention_front_player.stream_paused = retention_front_player.volume_linear < 0.00001
	if retention_rear_player != null:
		retention_rear_player.volume_linear = lerpf(retention_rear_player.volume_linear, lift * RETENTION_REAR_GAIN * view_exhaust_gain, smoothing)
		retention_rear_player.stream_paused = retention_rear_player.volume_linear < 0.00001


func build_event_voice_pool(
	players: Array[AudioStreamPlayer3D],
	paths: Array,
	local_position: Vector3,
	volume_db: float,
	unit_size: float,
	maximum_distance: float,
	voices_per_variant: int,
) -> void:
	for voice in voices_per_variant:
		for path in paths:
			if not ResourceLoader.exists(path):
				push_warning("Missing commons event sample: " + str(path))
				continue
			var player := AudioStreamPlayer3D.new()
			var voice_key := str(path).get_file().get_basename()
			player.stream = load_event_stream(path, voice_key)
			if player.stream == null:
				continue
			player.position = local_position
			routing.route(player, voice_key)
			player.volume_db = volume_db
			player.unit_size = unit_size
			player.max_distance = maximum_distance
			player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
			add_child(player)
			players.append(player)


func build_limiter_player() -> AudioStreamPlayer3D:
	var stream := load_looping_stream(LIMITER_SAMPLE_PATH)
	if stream == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.position = BACKFIRE_POSITION
	routing.route(player, LIMITER_SAMPLE_PATH.get_file().get_basename())
	player.volume_linear = 0.0
	player.unit_size = 8.0
	player.max_distance = 160.0
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(player)
	player.play()
	return player


func update_limiter_audio(smoothing: float) -> void:
	if limiter_player == null:
		return
	var cut := clampf(float(acoustic.get("limiter_cut", 0.0)), 0.0, 1.0)
	var rpm := float(acoustic.get("rpm", 0.0))
	limiter_player.volume_linear = lerpf(
		limiter_player.volume_linear,
		cut * LIMITER_GAIN * view_exhaust_gain,
		smoothing,
	)
	limiter_player.pitch_scale = clampf(rpm / LIMITER_NATIVE_RPM, 0.30, 1.0)
	limiter_player.stream_paused = limiter_player.volume_linear < 0.00001


func continuous_player(path: String) -> AudioStreamPlayer3D:
	var stream := load_looping_stream(path)
	if stream == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	routing.route(player, path.get_file().get_basename())
	player.volume_linear = 0.0
	player.unit_size = 10.0
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(player)
	player.play()
	return player


func load_event_stream(path: String, key: String) -> AudioStream:
	var stream := SeamlessVehicleLoop.load_pcm(path, false, routing.settings(key).get("adsr", { }))
	return stream if stream != null else load(path)


func layer_weights(voices: Array[SampleVoice], revolutions: float) -> Array[float]:
	var weights: Array[float] = []
	var total := 0.0
	var nearest := 0
	var nearest_distance := INF
	for index in voices.size():
		var voice := voices[index]
		var weight := sample_weight(
			revolutions,
			voice.reference_rpm,
			voice.lower_rpm,
			voice.upper_rpm,
		)
		weights.append(weight)
		total += weight
		var distance := absf(revolutions - voice.reference_rpm)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = index
	if total > 0.0:
		for index in weights.size():
			weights[index] /= total
	elif not weights.is_empty():
		weights[nearest] = 1.0
	return weights
