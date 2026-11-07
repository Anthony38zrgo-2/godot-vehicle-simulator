class_name RallyVehicleAudio
extends Node3D


# Estructura tipada en memoria para evitar llamadas costosas a get_meta/set_meta en _physics_process
class SampleVoice:
	var player: AudioStreamPlayer3D
	var reference_rpm: float
	var lower_rpm: float
	var upper_rpm: float
	var mode: String = "drive"
	var is_exhaust: bool
	var level_gain: float
	var base_gain: float
	var acceleration_gain: float
	var blend_weight: float = 0.0
	var layer_level: float = 0.0


# CMR4 native samples; RPM centres are local estimates (see bank manifest).
const ENGINE_SAMPLE_DEFINITIONS := [
	{"path": "res://sounds/banks/EscortRS1600/e_stat.wav", "reference": 1050.0, "lower": 0.0, "upper": 1800.0, "mode": "idle"},
	{"path": "res://sounds/banks/EscortRS1600/e_thr01.wav", "reference": 1800.0, "lower": 1050.0, "upper": 3000.0, "mode": "drive"},
	{"path": "res://sounds/banks/EscortRS1600/e_thr02.wav", "reference": 3000.0, "lower": 1800.0, "upper": 4200.0, "mode": "drive"},
	{"path": "res://sounds/banks/EscortRS1600/e_thr03.wav", "reference": 4200.0, "lower": 3000.0, "upper": 5500.0, "mode": "drive"},
	{"path": "res://sounds/banks/EscortRS1600/e_thr04.wav", "reference": 5500.0, "lower": 4200.0, "upper": 6800.0, "mode": "drive"},
	{"path": "res://sounds/banks/EscortRS1600/e_thr05.wav", "reference": 6800.0, "lower": 5500.0, "upper": 9500.0, "mode": "drive"},
]
const EXHAUST_SAMPLE_DEFINITIONS := [
	{"path": "res://sounds/banks/EscortRS1600/x_stat.wav", "reference": 1050.0, "lower": 0.0, "upper": 1800.0, "mode": "idle"},
	{"path": "res://sounds/banks/EscortRS1600/x_thr01.wav", "reference": 1800.0, "lower": 1050.0, "upper": 3000.0, "mode": "drive"},
	{"path": "res://sounds/banks/EscortRS1600/x_thr02.wav", "reference": 3000.0, "lower": 1800.0, "upper": 4200.0, "mode": "drive"},
	{"path": "res://sounds/banks/EscortRS1600/x_thr03.wav", "reference": 4200.0, "lower": 3000.0, "upper": 5500.0, "mode": "drive"},
	{"path": "res://sounds/banks/EscortRS1600/x_thr04.wav", "reference": 5500.0, "lower": 4200.0, "upper": 6800.0, "mode": "drive"},
	{"path": "res://sounds/banks/EscortRS1600/x_thr05.wav", "reference": 6800.0, "lower": 5500.0, "upper": 9500.0, "mode": "drive"},
]
const COAST_ENGINE_DEFINITIONS := [
	{"path": "res://sounds/banks/EscortRS1600/e_idle01.wav", "reference": 1800.0, "lower": 0.0, "upper": 3000.0, "mode": "coast"},
	{"path": "res://sounds/banks/EscortRS1600/e_idle02.wav", "reference": 3000.0, "lower": 1800.0, "upper": 4200.0, "mode": "coast"},
	{"path": "res://sounds/banks/EscortRS1600/e_idle03.wav", "reference": 4200.0, "lower": 3000.0, "upper": 5500.0, "mode": "coast"},
	{"path": "res://sounds/banks/EscortRS1600/e_idle04.wav", "reference": 5500.0, "lower": 4200.0, "upper": 6800.0, "mode": "coast"},
	{"path": "res://sounds/banks/EscortRS1600/e_idle05.wav", "reference": 6800.0, "lower": 5500.0, "upper": 9500.0, "mode": "coast"},
]
const COAST_EXHAUST_DEFINITIONS := [
	{"path": "res://sounds/banks/EscortRS1600/x_idle01.wav", "reference": 1800.0, "lower": 0.0, "upper": 3000.0, "mode": "coast"},
	{"path": "res://sounds/banks/EscortRS1600/x_idle02.wav", "reference": 3000.0, "lower": 1800.0, "upper": 4200.0, "mode": "coast"},
	{"path": "res://sounds/banks/EscortRS1600/x_idle03.wav", "reference": 4200.0, "lower": 3000.0, "upper": 5500.0, "mode": "coast"},
	{"path": "res://sounds/banks/EscortRS1600/x_idle04.wav", "reference": 5500.0, "lower": 4200.0, "upper": 6800.0, "mode": "coast"},
	{"path": "res://sounds/banks/EscortRS1600/x_idle05.wav", "reference": 6800.0, "lower": 5500.0, "upper": 9500.0, "mode": "coast"},
]

const NEUTRAL_SAMPLE_PATH := "res://sounds/banks/commons/neutral_first_gear_transition.wav"
const NEUTRAL_FADE_WIDTH := 0.15

const GEAR_WHINE_PATH := "res://sounds/banks/EscortRS1600/whinelo.wav"
const GEAR_WHINE_HIGH_PATH := "res://sounds/banks/EscortRS1600/whinehi.wav"
# CMR4 lift-off events; not claimed to be isolated combustion detonations.
const BACKFIRE_SAMPLE_PATHS := [
	"res://sounds/banks/commons/backfire_ext_1.wav",
	"res://sounds/banks/commons/backfire_ext_2.wav",
	"res://sounds/banks/commons/backfire_ext_3.wav",
	"res://sounds/banks/commons/backfire_ext_4.wav",
]
# Cabin/bonnet backfires reuse the exterior exhaust recordings on a dedicated
# bus; audio_mixer.json ("backfire_cabin") gives that bus its high-pass filter.
const BACKFIRE_CABIN_BUS := "backfire_cabin"
const BACKFIRE_CABIN_VOLUME_DB := -6.0
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
const LIMITER_GAIN := 0.225
const SURFACE_GAIN := 0.45
const SURFACE_ROLL_GAIN_SCALE := 0.31622776601683794 # -10.0 dB
const TYRE_CONTACT_GAIN_SCALE := 0.31622776601683794 # -10.0 dB
const SCRAPE_GAIN_SCALE := 0.31622776601683794 # -10.0 dB
const ENGINE_GAIN_BOOST := 3.1622776601683795 # +10.0 dB (db_to_linear(10.0), boosted by additional +5.0 dB)
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
const LAND_VOLUME_DB := [-24.0, -21.0, -18.0]
const LAND_MIN_MS := 2.5
const LAND_MID_MS := 4.0
const LAND_HIGH_MS := 7.0
const LAND_POSITION := Vector3(0.0, -0.2, 0.0)
const SURFACE_BANK := "res://sounds/banks/surfaces/"
const WHEEL_DAMAGE_SAMPLES: Array[String] = ["flat_tyre_mono", "bad_brakes"]
const WHEEL_DAMAGE_GAIN_BUDGET := 0.46
const SurfaceMixer = preload("res://scripts/audio/surface_mix.gd")

const ENGINE_VOLUME_BASE := 0.269
const ENGINE_VOLUME_ACCELERATION := 0.112
const EXHAUST_VOLUME_BASE := 0.70
const EXHAUST_VOLUME_ACCELERATION := 0.30
# Desplazamiento del banco de samples bajo carga (cambia el timbre hacia samples más altos sin falsear el pitch)
const LOAD_TIMBRE_RPM_OFFSET := 380.0

@export var vehicle_path: NodePath
@export_file("*.json") var engine_bank_manifest_path: String = ""
@export var impact_cooldown_seconds: float = 0.25

var engine_definitions: Array = ENGINE_SAMPLE_DEFINITIONS
var exhaust_definitions: Array = EXHAUST_SAMPLE_DEFINITIONS
var coast_engine_definitions: Array = COAST_ENGINE_DEFINITIONS
var coast_exhaust_definitions: Array = COAST_EXHAUST_DEFINITIONS
var whine_paths: Array = [GEAR_WHINE_PATH, GEAR_WHINE_HIGH_PATH]
var backfire_paths: Array = BACKFIRE_SAMPLE_PATHS
var engine_position := Vector3(0.0, 0.55, -0.8)
var exhaust_position := BACKFIRE_POSITION

var vehicle: RallyEscortVehicle
var engine_voices: Array[SampleVoice] = []
var exhaust_voices: Array[SampleVoice] = []
var tyre_contact_players: Array[AudioStreamPlayer3D] = []
var tyre_contact_filters: Array[AudioEffectLowPassFilter] = []
var tyre_previous_velocity: Array[float] = []
var tyre_contact_cooldowns: Array[float] = []
var neutral_player: AudioStreamPlayer3D
var clunk_scale: float = 1.0
var packet_rpm_idle: float = 1050.0
var surface_map: Dictionary = {}
var sand_impact_player: AudioStreamPlayer3D
var sand_impact_cooldown := 0.0
var impact_small_players: Array[AudioStreamPlayer3D] = []
var impact_medium_players: Array[AudioStreamPlayer3D] = []
var impact_large_players: Array[AudioStreamPlayer3D] = []
var land_players: Array[AudioStreamPlayer3D] = []
var smoothed_revolutions: float = 1800.0
var current_slip_ratio: float = 0.0
var impact_cooldown: float = 0.0

var upshift_players: Array[AudioStreamPlayer3D] = []
var downshift_players: Array[AudioStreamPlayer3D] = []
var onboard_upshift_players: Array[AudioStreamPlayer3D] = []
var onboard_downshift_players: Array[AudioStreamPlayer3D] = []
var extra_upshift_players: Array[AudioStreamPlayer3D] = []
var extra_downshift_players: Array[AudioStreamPlayer3D] = []
var backfire_players: Array[AudioStreamPlayer3D] = []
var backfire_cabin_players: Array[AudioStreamPlayer3D] = []
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
var wheel_damage_players: Array[Array] = []
var surface_players: Dictionary = { }
var scrape_player: AudioStreamPlayer3D
var limiter_player: AudioStreamPlayer3D
var whine_players: Array[AudioStreamPlayer3D] = []
var coast_engine_voices: Array[SampleVoice] = []
var coast_exhaust_voices: Array[SampleVoice] = []
var impact_index: int = 0
var exhaust_crackle_s: float = 0.0
var sample_levels: Dictionary = { }
var camera_rig: Node = null
var cockpit_audio_blend := 0.0
var cockpit_filter_buses: Dictionary = {}
var cockpit_surface_reverbs: Dictionary = {}
var view_engine_gain := 1.0
var view_exhaust_gain := 1.0


func _ready() -> void:
	vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	if vehicle == null:
		push_error("Rally audio cannot resolve its vehicle: " + str(vehicle_path))
		set_physics_process(false)
		return
	if not engine_bank_manifest_path.is_empty():
		var bank_file := FileAccess.open(engine_bank_manifest_path, FileAccess.READ)
		var bank: Variant = JSON.parse_string(bank_file.get_as_text()) if bank_file != null else null
		if not bank is Dictionary:
			push_error("Invalid vehicle audio bank: " + engine_bank_manifest_path)
			set_physics_process(false)
			return
		engine_definitions = bank.get("engine", [])
		exhaust_definitions = bank.get("exhaust", [])
		coast_engine_definitions = bank.get("coast_engine", [])
		coast_exhaust_definitions = bank.get("coast_exhaust", [])
		whine_paths = bank.get("whine", [])
		backfire_paths = bank.get("backfire", BACKFIRE_SAMPLE_PATHS)
		if backfire_paths.is_empty():
			backfire_paths = BACKFIRE_SAMPLE_PATHS
		# "backfire_interior" is intentionally ignored: the interior/bonnet backfire
		# reuses the exhaust recordings through the HP-filtered cabin bus.
		var ep: Array = bank.get("engine_position", [0.0, 0.55, -0.8])
		var xp: Array = bank.get("exhaust_position", [0.0, 0.20, 1.50])
		engine_position = Vector3(float(ep[0]), float(ep[1]), float(ep[2]))
		exhaust_position = Vector3(float(xp[0]), float(xp[1]), float(xp[2]))
		routing.configure_bank(engine_bank_manifest_path, "Rally:" + str(bank.get("vehicle_id", "custom")) + ":")
	var level_file := FileAccess.open("res://data/rally/audio_sample_levels.json", FileAccess.READ)
	if level_file != null:
		var parsed: Variant = JSON.parse_string(level_file.get_as_text())
		if parsed is Dictionary:
			sample_levels = parsed.get("samples", { })

	build_sample_layer(
		engine_definitions,
		engine_voices,
		engine_position,
		4.5,
		400.0,
		ENGINE_VOLUME_BASE,
		ENGINE_VOLUME_ACCELERATION,
		false,
	)
	build_sample_layer(
		exhaust_definitions,
		exhaust_voices,
		exhaust_position,
		6.0,
		1030.0,
		EXHAUST_VOLUME_BASE,
		EXHAUST_VOLUME_ACCELERATION,
		true,
	)
	build_tyre_contact_players()
	build_wheel_damage_players()
	build_neutral_player()
	build_surface_players()
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
		routing.route(player, path_str.get_file().get_basename())
		player.volume_db = -80.0
		player.unit_size = unit_size
		player.max_distance = maximum_distance
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(player)

		var voice := SampleVoice.new()
		voice.player = player
		voice.mode = str(definition.get("mode", "drive"))
		voice.reference_rpm = float(definition["reference"])
		voice.lower_rpm = float(definition["lower"])
		voice.upper_rpm = float(definition["upper"])
		voice.is_exhaust = is_exhaust
		voice.level_gain = float(definition.get("gain", sample_levels.get(path_str.get_file(), { }).get("gain", 1.0)))
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
# cada cambio confirmado, con presencia constante a cualquier RPM.
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


func shift_random_pitch(ascending: bool) -> float:
	var semitones := randf_range(0.0, 2.0) * (1.0 if ascending else -1.0)
	return pow(2.0, semitones / 12.0)


func play_neutral_event(ascending: bool) -> void:
	if neutral_player == null:
		return
	var bus_index := AudioServer.get_bus_index(neutral_player.bus)
	var bus_db := AudioServer.get_bus_volume_db(bus_index) if bus_index >= 0 else 0.0
	neutral_player.volume_db = 2.0 - bus_db if is_onboard_camera() else -11.0 + linear_to_db(0.75 * 0.85 * 2.0)
	neutral_player.pitch_scale = shift_random_pitch(ascending)
	neutral_player.play()


func update_neutral_audio(_smoothing: float) -> void:
	var idle := maxf(float(packet_rpm_idle), 1.0)
	var rpm := float(acoustic.get("rpm", idle))
	clunk_scale = smoothstep(idle, idle * (1.0 + NEUTRAL_FADE_WIDTH), rpm)


func build_surface_players() -> void:
	sand_impact_player = AudioStreamPlayer3D.new()
	sand_impact_player.stream = load_event_stream(SURFACE_BANK + "synthetic/sand_body_impact.wav", "surface_sand_body_impact")
	sand_impact_player.position = Vector3(0.0, -0.1, 0.3)
	sand_impact_player.unit_size = 8.0
	sand_impact_player.max_distance = 45.0
	sand_impact_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	routing.route(sand_impact_player, "surface_sand_body_impact")
	add_child(sand_impact_player)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SURFACE_BANK + "manifest.json"))
	surface_map = manifest["runtime_map"]
	for surface in surface_map:
		for role in surface_map[surface]:
			var path: String = SURFACE_BANK + str(surface_map[surface][role])
			# The preparation tool already baked the loop seam. Do not crossfade twice.
			var stream := SeamlessVehicleLoop.load_pcm(path, false)
			if stream == null:
				push_error("Missing surface sample: " + path)
				continue
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = stream.data.size() / 2
			var player := AudioStreamPlayer3D.new()
			player.stream = stream
			player.position = Vector3(0.0, 0.1, 0.0)
			player.unit_size = 10.0
			player.max_distance = 90.0
			player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
			routing.route(player, "surface_" + str(surface) + "_" + str(role))
			player.volume_linear = 0.0
			add_child(player)
			player.play()
			surface_players[str(surface) + ":" + str(role)] = player


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
		land_player.volume_db = (LAND_VOLUME_DB[i] if i < LAND_VOLUME_DB.size() else -11.0) + linear_to_db(0.75 * 0.75)
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
	update_cockpit_audio(delta)
	update_layer(engine_voices, smoothed_revolutions, smoothing)
	update_layer(exhaust_voices, smoothed_revolutions, smoothing)
	update_limiter_audio(smoothing)
	update_neutral_audio(smoothing)

	if accepted_generation != int(packet.generation) or accepted_sequence != int(packet.sequence):
		var target_gear := int(packet.get("gear", 1))
		for event in acoustic.get("events", []):
			if event == "upshift":
				play_neutral_event(true)
				play_upshift_event(target_gear)
			elif event == "downshift":
				play_neutral_event(false)
				play_downshift_event(target_gear)
			elif event == "backfire":
				play_backfire_event(target_gear)
		accepted_generation = int(packet.generation)
		accepted_sequence = int(packet.sequence)

	if float(vehicle.body_contact_audio.get("landing_speed_ms", 0.0)) >= LAND_MIN_MS:
		play_landing(vehicle)
	elif float(vehicle.body_contact_audio.get("lateral_impulse_ns", 0.0)) > vehicle.mass * 0.8:
		play_impact(vehicle)

	update_tyre_contacts(delta)
	update_surface_audio(packet, delta)
	update_wheel_damage_audio(packet.get("wheels", []), delta)

	if scrape_player != null:
		var gain := 0.62 * SCRAPE_GAIN_SCALE * clampf(
			float(vehicle.body_contact_audio.get("scrape_power_w", 0.0)) / 15000.0,
			0.0,
			1.0,
		)
		scrape_player.volume_linear = lerpf(scrape_player.volume_linear, gain, smoothing)
		scrape_player.stream_paused = scrape_player.volume_linear < 0.00001

	update_whine_audio(smoothing)
	update_retention_audio(smoothing)


#352 vista (chase 0 / capo 1) conmuta el peso motor/escape como en CMR2.
func update_cockpit_audio(delta: float) -> void:
	var is_cockpit := is_onboard_camera()
	if not is_cockpit:
		for player in onboard_upshift_players + onboard_downshift_players:
			player.stop()
	cockpit_audio_blend = lerpf(cockpit_audio_blend, 1.0 if is_cockpit else 0.0, 1.0 - exp(-delta / 0.15))
	var players: Array = surface_players.values() + upshift_players + downshift_players + extra_upshift_players + extra_downshift_players + onboard_upshift_players + onboard_downshift_players
	for voice in engine_voices:
		if voice.mode == "idle":
			players.append(voice.player)
	if sand_impact_player != null:
		players.append(sand_impact_player)
	if neutral_player != null:
		players.append(neutral_player)
	for player: AudioStreamPlayer3D in players:
		var bus := AudioServer.get_bus_index(player.bus)
		if bus < 0:
			continue
		if not cockpit_filter_buses.has(player.bus):
			var filter := AudioEffectLowPassFilter.new()
			filter.cutoff_hz = 20500.0
			AudioServer.add_bus_effect(bus, filter)
			cockpit_filter_buses[player.bus] = filter
		var cutoff := 20500.0 if player == neutral_player else (2500.0 if player.bus == "Rally:e_stat" else (4800.0 if str(player.bus).begins_with("Rally:surface_") else 3500.0))
		var effect: AudioEffectLowPassFilter = cockpit_filter_buses[player.bus]
		effect.cutoff_hz = lerpf(20500.0, cutoff, cockpit_audio_blend)
		if str(player.bus).begins_with("Rally:surface_"):
			if not cockpit_surface_reverbs.has(player.bus):
				var reverb := AudioEffectReverb.new()
				reverb.room_size = 0.15
				reverb.damping = 0.85
				reverb.dry = 1.0
				reverb.wet = 0.0
				AudioServer.add_bus_effect(bus, reverb)
				cockpit_surface_reverbs[player.bus] = reverb
			var reverb: AudioEffectReverb = cockpit_surface_reverbs[player.bus]
			reverb.wet = 0.04 * cockpit_audio_blend


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
				gain *= 1.0 + float(exhaust_cfg.get("crackle_gain", 0.1)) * (exhaust_crackle_s / 0.12)

		# Equal-power transition between loaded and coast recordings.
		if voice.mode == "coast":
			gain *= sqrt(1.0 - throttle) * smoothstep(packet_rpm_idle, packet_rpm_idle * 1.7, revolutions)
		elif voice.mode == "drive":
			gain *= sqrt(throttle)
		voice.layer_level = lerpf(voice.layer_level, gain, volume_smoothing)
		var view_gain := view_exhaust_gain if voice.is_exhaust else view_engine_gain
		voice.player.volume_linear = (voice.blend_weight / normalization) * voice.layer_level * voice.level_gain * view_gain * ENGINE_GAIN_BOOST
		voice.player.pitch_scale = clampf(revolutions / voice.reference_rpm, 0.5, 3.5)


func sample_weight(revolutions: float, reference: float, lower: float, upper: float) -> float:
	if revolutions <= reference:
		return clampf((revolutions - lower) / maxf(reference - lower, 1.0), 0.0, 1.0)
	return clampf((upper - revolutions) / maxf(upper - reference, 1.0), 0.0, 1.0)


func play_upshift_event(_target_gear: int) -> void:
	if extra_upshift_players.is_empty() or clunk_scale < 0.05 or upshift_cooldown > 0.0:
		return
	upshift_rr_index += 1
	play_extra_shift(extra_upshift_players, upshift_rr_index, true)
	upshift_cooldown = UPSHIFT_RETRIGGER_SECONDS


func play_downshift_event(_target_gear: int) -> void:
	if extra_downshift_players.is_empty() or clunk_scale < 0.05 or downshift_cooldown > 0.0:
		return
	downshift_rr_index += 1
	play_extra_shift(extra_downshift_players, downshift_rr_index, false)
	downshift_cooldown = DOWNSHIFT_RETRIGGER_SECONDS


func is_onboard_camera() -> bool:
	return camera_rig != null and int(camera_rig.get("camera_mode")) == 2


func is_onboard_or_bonnet_camera() -> bool:
	if camera_rig == null and vehicle != null and vehicle.get_parent() != null:
		camera_rig = vehicle.get_parent().get_node_or_null("RallyCameraRig")
	if camera_rig == null:
		return false
	var mode := int(camera_rig.get("camera_mode"))
	return mode == 1 or mode == 2


func play_extra_shift(players: Array[AudioStreamPlayer3D], sequence: int, ascending: bool) -> void:
	if players.is_empty():
		return
	var player := players[(sequence - 1) % players.size()]
	player.pitch_scale = shift_random_pitch(ascending)
	player.volume_db = -20.0 + linear_to_db(0.75 * 0.85 * 0.85 * maxf(clunk_scale, 0.001))
	player.play()


# Detonaciones Cosworth con ciclo de semilla + probabilidad por marcha destino
# (CMR2: mas probable en marchas cortas), manteniendo voice_limit 1.
func play_backfire_event(target_gear: int) -> void:
	if (backfire_players.is_empty() and backfire_cabin_players.is_empty()) or backfire_event_cooldown > 0.0:
		return
	var prob: float = BACKFIRE_GEAR_PROB[clampi(target_gear, 0, BACKFIRE_GEAR_PROB.size() - 1)]
	if randf() > prob:
		return
	backfire_rng_state = _next_rng_state(backfire_rng_state)

	var is_cabin := is_onboard_or_bonnet_camera()
	var player: AudioStreamPlayer3D = null
	if is_cabin and not backfire_cabin_players.is_empty():
		player = backfire_cabin_players[int((backfire_rng_state >> 33) % backfire_cabin_players.size())]
		player.volume_db = BACKFIRE_CABIN_VOLUME_DB
	elif not backfire_players.is_empty():
		player = backfire_players[int((backfire_rng_state >> 33) % backfire_players.size())]
		player.volume_db = BACKFIRE_VOLUME_DB
	else:
		return

	player.pitch_scale = 0.96 + float(backfire_rng_state & 0x03) * 0.025
	player.play()
	backfire_event_cooldown = BACKFIRE_RETRIGGER_SECONDS
	vehicle.backfire_triggered.emit()
	exhaust_crackle_s = 0.12


func _next_rng_state(state: int) -> int:
	var value := maxi(state, 1)
	value ^= (value << 13) & 0x7FFFFFFFFFFFFFFF
	value ^= value >> 7
	value ^= (value << 17) & 0x7FFFFFFFFFFFFFFF
	return maxi(value & 0x7FFFFFFFFFFFFFFF, 1)


func update_surface_audio(packet: Dictionary, delta: float) -> void:
	var state: Dictionary = SurfaceMixer.evaluate(packet.get("wheels", []), absf(float(packet.get("speed_kph", 0.0))), float(packet.get("throttle", 0.0)), maxf(float(packet.get("brake", 0.0)), float(packet.get("handbrake", 0.0))), vehicle.mass * 9.81)
	update_sand_impacts(state, absf(float(packet.get("speed_kph", 0.0))), delta)
	current_slip_ratio = float(state.slip_total)
	for key in surface_players:
		var parts: PackedStringArray = str(key).split(":")
		var surface := parts[0]
		var role := parts[1]
		var target := 0.0
		if role == "roll":
			target = float(state.roll.get(surface, 0.0)) * 0.15 * SURFACE_ROLL_GAIN_SCALE
		else:
			# One slip role per surface; lateral and longitudinal slip never stack voices.
			var roles: Dictionary = state.slip.get(surface, {})
			var strongest := "skid"
			for candidate in ["peel", "lock"]:
				if float(roles.get(candidate, 0.0)) > float(roles.get(strongest, 0.0)):
					strongest = candidate
			var selected := strongest if surface_map[surface].has(strongest) else "skid"
			if role == selected:
				target = float(roles.get(strongest, 0.0)) * 0.135
		target *= 0.75 * lerpf(1.0, db_to_linear(-2.0), cockpit_audio_blend)
		var player: AudioStreamPlayer3D = surface_players[key]
		player.volume_linear = SurfaceMixer.smooth(player.volume_linear, target, delta, 0.08)
		player.pitch_scale = SurfaceMixer.smooth(player.pitch_scale, float(state.roll_pitch if role == "roll" else state.slip_pitch), delta, 0.12)
		player.stream_paused = player.volume_linear < 0.00001


func build_wheel_damage_players() -> void:
	for sample in WHEEL_DAMAGE_SAMPLES:
		var path := "res://sounds/banks/commons/" + sample + ".wav"
		# These loops already have a baked crossfade, like the rolling surface bank.
		var stream := SeamlessVehicleLoop.load_pcm(path, false)
		var players: Array[AudioStreamPlayer3D] = []
		wheel_damage_players.append(players)
		if stream == null:
			push_warning("Missing wheel damage sample: " + path)
			continue
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = stream.data.size() / 2
		for i in 4:
			var player := AudioStreamPlayer3D.new()
			player.stream = stream
			player.unit_size = 8.0
			player.max_distance = 45.0
			player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
			player.volume_linear = 0.0
			routing.route(player, sample)
			player.panning_strength = 2.0
			add_child(player)
			players.append(player)


func update_wheel_damage_audio(wheels: Array, delta: float) -> void:
	var hubs := vehicle.simulation.unsprung_rig.hubs
	var targets: Array[Vector2] = []
	var pitches: Array[float] = []
	var total_gain := 0.0
	for i in mini(4, hubs.size()):
		var wheel: Dictionary = wheels[i] if i < wheels.size() else {}
		var spin := absf(float(wheel.get("spin_rad_s", 0.0)))
		var hub_velocity: Vector3 = hubs[i].linear_velocity
		var travel_speed := Vector2(hub_velocity.x, hub_velocity.z).length()
		var rolling := smoothstep(0.4, 5.0, maxf(travel_speed, spin * vehicle.simulation.wheel_radii[i]))
		var braking_rotation := smoothstep(1.0, 18.0, spin)
		var loaded := smoothstep(5.0, 160.0, float(wheel.get("load_n", 0.0)))
		var pressure_loss := clampf(float(wheel.get("pressure_loss_fraction", 0.0)), 0.0, 1.0)
		var brake := clampf(float(wheel.get("brake_collision_loss", 0.0)), 0.0, 1.0)
		var pedal := vehicle.brake_amount
		if i >= 2 or not vehicle.simulation.brake_model.handbrake_rear_only:
			pedal = maxf(pedal, vehicle.handbrake_amount)
		var demand := minf(float(wheel.get("brake_demand", 0.0)), pedal)
		var gain := Vector2(
			0.34 * pow(pressure_loss, 0.8) * loaded * rolling,
			0.105 * brake * brake * demand * braking_rotation
		) * rolling
		targets.append(gain)
		pitches.append(lerpf(0.85, 1.12, smoothstep(2.0, 95.0, spin)))
		total_gain += gain.x + gain.y

	var mix_gain := WHEEL_DAMAGE_GAIN_BUDGET / maxf(total_gain, WHEEL_DAMAGE_GAIN_BUDGET)
	mix_gain *= lerpf(1.0, db_to_linear(-2.0), cockpit_audio_blend)
	for effect in wheel_damage_players.size():
		for i in mini(targets.size(), wheel_damage_players[effect].size()):
			var player: AudioStreamPlayer3D = wheel_damage_players[effect][i]
			player.global_position = hubs[i].global_position
			var target := targets[i][effect] * mix_gain
			player.volume_linear = SurfaceMixer.smooth(player.volume_linear, target, delta, 0.08)
			player.pitch_scale = SurfaceMixer.smooth(player.pitch_scale, pitches[i], delta, 0.12)
			if player.volume_linear >= 0.0001:
				if not player.playing:
					player.play()
			elif player.playing:
				player.stop()


func update_sand_impacts(state: Dictionary, speed_kph: float, delta: float) -> void:
	sand_impact_cooldown = maxf(0.0, sand_impact_cooldown - delta)
	var sand_share := clampf(float(state.shares.get("sand", 0.0)) + float(state.shares.get("gravel", 0.0)), 0.0, 1.0)
	if sand_impact_player == null or sand_share <= 0.0 or speed_kph < 12.0:
		return
	if sand_impact_cooldown > 0.0 or sand_impact_player.playing:
		return
	var presence := smoothstep(12.0, 70.0, speed_kph) * sand_share * float(state.load_factor)
	sand_impact_player.volume_linear = 0.075 * presence * lerpf(1.0, db_to_linear(-2.0), cockpit_audio_blend)
	sand_impact_player.pitch_scale = randf_range(0.92, 1.08)
	sand_impact_player.play()
	sand_impact_cooldown = randf_range(0.85, 1.50)


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
	if float(vehicle.body_contact_audio.get("lateral_impulse_ns", 0.0)) <= vehicle.mass * 0.8:
		return
	var speed_kph := float(vehicle.body_contact_audio.get("lateral_speed_kph", 0.0))
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
	var local := vehicle.body_contact_audio.get("lateral_position", Vector3.ZERO) as Vector3
	player.position = Vector3(
		clampf(local.x, -IMPACT_POSITION_CLAMP.x, IMPACT_POSITION_CLAMP.x),
		clampf(local.y, -IMPACT_POSITION_CLAMP.y, IMPACT_POSITION_CLAMP.y),
		clampf(local.z, -IMPACT_POSITION_CLAMP.z, IMPACT_POSITION_CLAMP.z),
	)
	player.pitch_scale = 0.98 + float(impact_index % 3) * 0.02
	player.play()
	impact_cooldown = impact_cooldown_seconds


func build_auxiliary_audio() -> void:
	scrape_player = continuous_player("res://sounds/banks/commons/impact_scrape.wav")
	limiter_player = build_limiter_player()
	build_event_voice_pool(
		backfire_players,
		backfire_paths,
		exhaust_position,
		BACKFIRE_VOLUME_DB,
		8.0,
		160.0,
		1,
	)
	build_event_voice_pool(
		backfire_cabin_players,
		backfire_paths,
		exhaust_position,
		BACKFIRE_CABIN_VOLUME_DB,
		8.0,
		160.0,
		1,
		BACKFIRE_CABIN_BUS,
	)
	build_event_voice_pool(extra_upshift_players, ["res://sounds/banks/commons/f2002_gearup.wav"], SHIFT_EVENT_POSITION, -20.0, 12.0, 80.0, 2)
	build_event_voice_pool(extra_downshift_players, ["res://sounds/banks/commons/f2002_geardn.wav"], SHIFT_EVENT_POSITION, -20.0, 12.0, 80.0, 2)
	build_whine_voices()
	build_retention_voices()


# Una sola voz de transmisión, modulada por velocidad de eje y par.
func build_whine_voices() -> void:
	var defs: Array = []
	for path in whine_paths:
		defs.append([path, SHIFT_EVENT_POSITION])
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
	var split := vehicle.simulation.powertrain_model.front_torque_split
	var spins := vehicle.simulation.wheel_spins
	var shaft := absf(0.5 * (split * (spins[0] + spins[1]) + (1.0 - split) * (spins[2] + spins[3])))
	# La caja de dientes rectos silba cuando está acoplada bajo par (aceleración o retención)
	# y cae a un leve arrastre inercial cuando se pisa el embrague (clutch_open == true)
	var clutch_coupling := 0.12 if bool(acoustic.get("clutch_open", false)) else 1.0
	var torque_stress := absf(float(acoustic.get("load", 0.0)))
	var target := 0.75 * (0.004 + 0.014 * torque_stress) * clampf(shaft / 10.0, 0.0, 1.0) * clutch_coupling
	for index in whine_players.size():
		var player := whine_players[index]
		player.pitch_scale = clampf(shaft / 30.0, 0.5, 3.5)
		var high_weight := smoothstep(20.0, 70.0, shaft)
		var band_weight := sqrt(1.0 - high_weight) if index == 0 else sqrt(high_weight)
		player.volume_linear = lerpf(player.volume_linear, target * band_weight, smoothing)
		player.stream_paused = player.volume_linear < 0.00001


# Five RPM layers for closed-throttle engine and exhaust, replacing CMR2 retention.
func build_retention_voices() -> void:
	build_sample_layer(coast_engine_definitions, coast_engine_voices, engine_position, 4.5, 400.0, ENGINE_VOLUME_BASE, ENGINE_VOLUME_ACCELERATION, false)
	build_sample_layer(coast_exhaust_definitions, coast_exhaust_voices, exhaust_position, 6.0, 1030.0, EXHAUST_VOLUME_BASE, EXHAUST_VOLUME_ACCELERATION, true)
	play_layer(coast_engine_voices)
	play_layer(coast_exhaust_voices)


func update_retention_audio(smoothing: float) -> void:
	update_layer(coast_engine_voices, smoothed_revolutions, smoothing)
	update_layer(coast_exhaust_voices, smoothed_revolutions, smoothing)


func build_event_voice_pool(
	players: Array[AudioStreamPlayer3D],
	paths: Array,
	local_position: Vector3,
	volume_db: float,
	unit_size: float,
	maximum_distance: float,
	voices_per_variant: int,
	bus_key: String = "",
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
			# bus_key keeps a second pool on its own filtered bus while sharing the sample.
			routing.route(player, bus_key if not bus_key.is_empty() else voice_key)
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
		cut * LIMITER_GAIN * view_exhaust_gain * ENGINE_GAIN_BOOST,
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


# Per-wheel upward velocity change is an effective vertical impact proxy.
# 0.6 m/s rejects road chatter; 4 m/s opens the LPF fully. Local calibration.
func build_tyre_contact_players() -> void:
	for i in 4:
		var player := AudioStreamPlayer3D.new()
		player.stream = load_event_stream("res://sounds/banks/commons/tyre_contact.wav", "tyre_contact")
		player.unit_size = 8.0
		player.max_distance = 90.0
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		routing.route(player, "tyre_contact_wheel_" + str(i))
		var filter := AudioEffectLowPassFilter.new()
		filter.cutoff_hz = 900.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(player.bus), filter)
		add_child(player)
		tyre_contact_players.append(player)
		tyre_contact_filters.append(filter)
		tyre_previous_velocity.append(0.0)
		tyre_contact_cooldowns.append(0.3)


func update_tyre_contacts(delta: float) -> void:
	for i in tyre_contact_players.size():
		var hub: RigidBody3D = vehicle.simulation.unsprung_rig.hubs[i]
		var speed := hub.linear_velocity.y
		var impact := maxf(speed - tyre_previous_velocity[i] - 9.81 * delta, 0.0)
		tyre_previous_velocity[i] = speed
		tyre_contact_cooldowns[i] = maxf(tyre_contact_cooldowns[i] - delta, 0.0)
		var player := tyre_contact_players[i]
		player.global_position = hub.global_position
		if not vehicle.simulation.suspension_model.contact_active[i] or impact < 0.6 or tyre_contact_cooldowns[i] > 0.0:
			continue
		var strength := clampf((impact - 0.6) / 3.4, 0.0, 1.0)
		player.volume_linear = lerpf(0.09375, 1.3125, strength) * TYRE_CONTACT_GAIN_SCALE
		tyre_contact_filters[i].cutoff_hz = lerpf(900.0, 4800.0, strength)
		player.play()
		tyre_contact_cooldowns[i] = 0.12
