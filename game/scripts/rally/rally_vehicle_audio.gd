class_name RallyVehicleAudio
extends Node3D

const ENGINE_SAMPLE_DEFINITIONS := [
	{"path": "res://sounds/banks/ford_escort_rs2000_rally/EE_Idle5.wav", "reference": 900.0, "lower": 0.0, "upper": 2000.0},
	{"path": "res://sounds/banks/ford_escort_rs2000_rally/EE_2k5.wav", "reference": 2000.0, "lower": 0.0, "upper": 3500.0},
	{"path": "res://sounds/banks/ford_escort_rs2000_rally/EE_6k5.wav", "reference": 4000.0, "lower": 2500.0, "upper": 5500.0},
	{"path": "res://sounds/banks/ford_escort_rs2000_rally/EE_9k5.wav", "reference": 6000.0, "lower": 4500.0, "upper": 9500.0},
]
const EXHAUST_SAMPLE_DEFINITIONS := [
	# Sounds.ini uses this recording twice: idle and ExhaustSound1 at 2000 RPM.
	{"path": "res://sounds/banks/ford_escort_rs2000_rally/EX_Idle6.wav", "reference": 900.0, "lower": 0.0, "upper": 2000.0},
	{"path": "res://sounds/banks/ford_escort_rs2000_rally/EX_Idle6.wav", "reference": 2000.0, "lower": 0.0, "upper": 3500.0},
	{"path": "res://sounds/banks/ford_escort_rs2000_rally/EX_6k5.wav", "reference": 4000.0, "lower": 2500.0, "upper": 5500.0},
	{"path": "res://sounds/banks/ford_escort_rs2000_rally/EX_9k5.wav", "reference": 6000.0, "lower": 4500.0, "upper": 9500.0},
]
const SHIFT_SAMPLE_PATH := "res://sounds/banks/commons/neutral_first_gear_transition.wav"
const IMPACT_SAMPLE_PATHS := [
	"res://sounds/banks/commons/impact_hit_1.wav",
	"res://sounds/banks/commons/impact_hit_2.wav",
	"res://sounds/banks/commons/impact_hit_3.wav",
	"res://sounds/banks/commons/impact_hit_4.wav",
]
const SCRUB_SAMPLE_PATH := "res://sounds/banks/commons/tyre_scrub.wav"
const ENGINE_VOLUME_BASE := 0.24
const ENGINE_VOLUME_ACCELERATION := 0.10
const EXHAUST_VOLUME_BASE := 0.70
const EXHAUST_VOLUME_ACCELERATION := 0.30

@export var vehicle_path: NodePath
@export var impact_cooldown_seconds: float = 0.25

var vehicle: RallyEscortVehicle
var engine_players: Array[AudioStreamPlayer3D] = []
var exhaust_players: Array[AudioStreamPlayer3D] = []
var shift_player: AudioStreamPlayer3D
var scrub_player: AudioStreamPlayer3D
var impact_players: Array[AudioStreamPlayer3D] = []
var smoothed_revolutions: float = 1800.0
var impact_cooldown: float = 0.0
var previous_gear: int = 0
var policy := VehicleAudioMixPolicy.new()
var routing := VehicleSoundRouting.new()
var acoustic: Dictionary = {}
var accepted_sequence: int = -1
var accepted_generation: int = -1
var surface_players: Dictionary = {}
var scrape_player: AudioStreamPlayer3D
var backfire_player: AudioStreamPlayer3D
var whine_player: AudioStreamPlayer3D
var impact_index: int = 0
var exhaust_crackle_s: float = 0.0
var sample_levels: Dictionary = {}


func _ready() -> void:
	vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	if vehicle == null:
		push_error("Rally audio cannot resolve its vehicle: " + str(vehicle_path))
		set_physics_process(false)
		return
	var level_file := FileAccess.open("res://data/rally/audio_sample_levels.json", FileAccess.READ)
	if level_file != null:
		sample_levels = JSON.parse_string(level_file.get_as_text()).get("samples", {})
	build_sample_layer(ENGINE_SAMPLE_DEFINITIONS, engine_players, Vector3(0.0, 0.55, -0.8), 3.0, 400.0, ENGINE_VOLUME_BASE, ENGINE_VOLUME_ACCELERATION)
	build_sample_layer(EXHAUST_SAMPLE_DEFINITIONS, exhaust_players, Vector3(0.0, 0.20, 1.50), 8.0, 1030.0, EXHAUST_VOLUME_BASE, EXHAUST_VOLUME_ACCELERATION, "exhaust")
	build_shift_player()
	build_scrub_player()
	build_impact_players()
	build_auxiliary_audio()
	# Impact audio is driven by solver impulses, not body-entered notifications.
	play_layer(engine_players)
	play_layer(exhaust_players)


func build_sample_layer(definitions: Array, players: Array[AudioStreamPlayer3D], local_position: Vector3, unit_size: float, maximum_distance: float, base_gain: float, acceleration_gain: float, role: String = "engine") -> void:
	for definition in definitions:
		var stream := load_looping_stream(str(definition["path"]))
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
		player.set_meta("reference_revolutions", float(definition["reference"]))
		player.set_meta("lower_revolutions", float(definition["lower"]))
		player.set_meta("upper_revolutions", float(definition["upper"]))
		player.set_meta("role", role)
		player.set_meta("level_gain", float(sample_levels.get(str(definition["path"]).get_file(), {}).get("gain", 1.0)))
		player.set_meta("blend_weight", 0.0)
		player.set_meta("base_gain", base_gain)
		player.set_meta("acceleration_gain", acceleration_gain)
		add_child(player)
		players.append(player)


func load_looping_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var seamless := SeamlessVehicleLoop.load_pcm(path)
	if seamless != null:
		return seamless
	push_warning("Unsupported PCM loop format: " + path)
	return load(path)


func build_shift_player() -> void:
	shift_player = AudioStreamPlayer3D.new()
	shift_player.stream = load_event_stream(SHIFT_SAMPLE_PATH, "neutral_first_gear_transition")
	shift_player.position = Vector3(0.0, 0.6, 0.4)
	routing.route(shift_player, "neutral_first_gear_transition")
	shift_player.volume_db = -11.0
	shift_player.unit_size = 12.0
	shift_player.max_distance = 80.0
	add_child(shift_player)


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
	for path in IMPACT_SAMPLE_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var player := AudioStreamPlayer3D.new()
		player.stream = load_event_stream(path, path.get_file().get_basename())
		routing.route(player, path.get_file().get_basename())
		player.volume_db = -12.0
		player.unit_size = 20.0
		player.max_distance = 160.0
		add_child(player)
		impact_players.append(player)


func play_layer(players: Array[AudioStreamPlayer3D]) -> void:
	for player in players:
		player.play()


func _physics_process(delta: float) -> void:
	if vehicle == null:
		return
	impact_cooldown = maxf(0.0, impact_cooldown - delta)
	exhaust_crackle_s = maxf(0.0, exhaust_crackle_s - delta)
	var packet := vehicle.get_presentation_snapshot()
	if packet.is_empty():
		return
	acoustic = policy.accept(packet)
	var target_revolutions := float(acoustic.get("rpm", 900.0)) + 500.0 * float(acoustic.get("throttle", 0.0))
	smoothed_revolutions = lerpf(smoothed_revolutions, target_revolutions, 1.0 - exp(-12.0 * delta))
	var smoothing := 1.0 - exp(-24.0 * delta)
	update_layer(engine_players, smoothed_revolutions, smoothing)
	update_layer(exhaust_players, smoothed_revolutions, smoothing)
	if accepted_generation != int(packet.generation) or accepted_sequence != int(packet.sequence):
		for event in acoustic.get("events", []):
			if event == "neutral_first":
				shift_player.play()
			elif event == "backfire" and backfire_player != null:
				backfire_player.play()
				exhaust_crackle_s = 0.12
		accepted_generation = int(packet.generation)
		accepted_sequence = int(packet.sequence)
	if float(vehicle.body_contact_audio.get("impulse_ns", 0.0)) > vehicle.mass * 0.8:
		play_impact(vehicle)
	update_scrub_audio(delta)
	for key in surface_players:
		var player: AudioStreamPlayer3D = surface_players[key]
		var gain := float(acoustic.get("surface_gain", 0.0)) if key == str(acoustic.get("surface", "")) else 0.0
		player.volume_linear = lerpf(player.volume_linear, gain * 0.08 * clampf((float(packet.speed_kph) - 2.0) / 25.0, 0.0, 1.0), smoothing)
		player.stream_paused = player.volume_linear < 0.00001
	if scrape_player != null:
		var gain := 0.62 * clampf(float(vehicle.body_contact_audio.get("scrape_power_w", 0.0)) / 15000.0, 0.0, 1.0)
		scrape_player.volume_linear = lerpf(scrape_player.volume_linear, gain, smoothing)
		scrape_player.stream_paused = scrape_player.volume_linear < 0.00001
	if whine_player != null:
		var shaft := absf((vehicle.simulation.wheel_spins[2] + vehicle.simulation.wheel_spins[3]) * 0.5)
		whine_player.pitch_scale = clampf(shaft / 30.0, 0.5, 3.5)
		var gain := (0.025 + 0.05 * float(acoustic.get("load", 0.0))) * clampf(shaft / 10.0, 0.0, 1.0) if int(packet.gear) != 0 else 0.0
		whine_player.volume_db = lerpf(whine_player.volume_db, linear_to_db(maxf(gain, 0.0001)), smoothing)


func update_layer(players: Array[AudioStreamPlayer3D], revolutions: float, volume_smoothing: float) -> void:
	var weights := layer_weights(players, revolutions)
	var energy := 0.0
	for index in players.size():
		var player := players[index]
		var weight := lerpf(float(player.get_meta("blend_weight", 0.0)), sqrt(weights[index]), volume_smoothing)
		player.set_meta("blend_weight", weight)
		energy += weight * weight
	var normalization := sqrt(maxf(energy, 0.0000001))
	for index in players.size():
		var player := players[index]
		var throttle := float(acoustic.get("throttle", 0.0))
		# A single Ford load envelope. Do not multiply three throttle curves.
		var gain := 0.62 * (float(player.get_meta("base_gain")) + float(player.get_meta("acceleration_gain")) * throttle)
		if str(player.get_meta("role", "engine")) == "exhaust":
			var exhaust: Dictionary = routing.config.get("exhaust", {})
			gain *= float(exhaust.get("base_gain", 0.2)) + float(exhaust.get("gas_flow_gain", 0.1)) * float(acoustic.get("load", 0.0))
			if not bool(exhaust.get("enabled", true)):
				gain = 0.0
			if exhaust_crackle_s > 0.0:
				gain += float(exhaust.get("crackle_gain", 0.1)) * exhaust_crackle_s / 0.12
		# Physical RPM/torque already carry the limiter. A second 0.35 gain gate
		# created repeated ~9 dB jumps and is deliberately not applied here.
		var level := lerpf(float(player.get_meta("layer_level", gain)), gain, volume_smoothing)
		player.set_meta("layer_level", level)
		player.volume_linear = float(player.get_meta("blend_weight")) / normalization * level * float(player.get_meta("level_gain", 1.0))
		var reference := float(player.get_meta("reference_revolutions"))
		player.pitch_scale = clampf(revolutions / reference, 0.5, 3.5)


func sample_weight(revolutions: float, reference: float, lower: float, upper: float) -> float:
	if revolutions <= reference:
		return clampf((revolutions - lower) / maxf(reference - lower, 1.0), 0.0, 1.0)
	return clampf((upper - revolutions) / maxf(upper - reference, 1.0), 0.0, 1.0)


func update_shift_audio() -> void:
	if shift_player == null:
		return
	if vehicle.current_gear != previous_gear:
		shift_player.pitch_scale = 0.75 + 0.05 * absf(float(vehicle.current_gear - previous_gear))
		shift_player.play()
		previous_gear = vehicle.current_gear


func update_scrub_audio(delta: float) -> void:
	if scrub_player == null:
		return
	var maximum_slip := 0.0
	for slip in vehicle.get_wheel_slip_vectors():
		maximum_slip = maxf(maximum_slip, absf(slip.x))
		maximum_slip = maxf(maximum_slip, absf(slip.y) * 2.0)
	var speed_factor := clampf(vehicle.speed / 18.0, 0.0, 1.0)
	var slip_factor := clampf((maximum_slip - 0.08) / 0.5, 0.0, 1.0)
	var road := false
	for surface in vehicle.get_wheel_surface_types():
		road = road or str(surface).to_lower() in ["road", "asphalt", "tarmac"]
	var target_gain := speed_factor * slip_factor * 0.55 if road else 0.0
	var volume_smoothing := 1.0 - exp(-15.0 * delta)
	scrub_player.volume_linear = lerpf(scrub_player.volume_linear, target_gain, volume_smoothing)
	scrub_player.stream_paused = scrub_player.volume_linear < 0.00001


func play_impact(_other_body: Node) -> void:
	if impact_players.is_empty() or impact_cooldown > 0.0:
		return
	var speed := float(vehicle.body_contact_audio.get("impulse_ns", 0.0)) / maxf(vehicle.mass, 1.0)
	if speed < 0.8:
		return
	var player := impact_players[impact_index % impact_players.size()]
	impact_index += 1
	player.pitch_scale = 0.98 + float(impact_index % 3) * 0.02
	player.volume_db = clampf(-16.0 + speed * 0.8, -16.0, -2.0)
	player.play()
	impact_cooldown = impact_cooldown_seconds


func build_auxiliary_audio() -> void:
	for key in ["surf_grass", "surf_sand", "surf_rumble"]:
		var player := continuous_player("res://sounds/banks/commons/" + key + ".wav")
		if player != null:
			surface_players[key] = player
	scrape_player = continuous_player("res://sounds/banks/commons/impact_scrape.wav")
	var path := "res://sounds/banks/ford_escort_rs2000_rally/backfire.wav"
	if ResourceLoader.exists(path):
		backfire_player = AudioStreamPlayer3D.new()
		backfire_player.stream = load_event_stream(path, "engine_backfire")
		backfire_player.bus = "Vehicle"
		backfire_player.volume_db = -14.0
		backfire_player.unit_size = 8.0
		add_child(backfire_player)
	# No calibrated Ford transmission recording exists. Do not synthesize a
	# permanent sine underneath the engine. whine_player intentionally stays null.


func continuous_player(path: String) -> AudioStreamPlayer3D:
	var stream := load_looping_stream(path)
	if stream == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	routing.route(player, path.get_file().get_basename())
	player.volume_db = -80.0
	player.unit_size = 10.0
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(player)
	player.play()
	return player


func load_event_stream(path: String, key: String) -> AudioStream:
	var stream := SeamlessVehicleLoop.load_pcm(path, false, routing.settings(key).get("adsr", {}))
	return stream if stream != null else load(path)


func layer_weights(players: Array[AudioStreamPlayer3D], revolutions: float) -> Array[float]:
	var weights: Array[float] = []
	var total := 0.0
	var nearest := 0
	var nearest_distance := INF
	for index in players.size():
		var player := players[index]
		var reference := float(player.get_meta("reference_revolutions"))
		var weight := sample_weight(revolutions, reference, float(player.get_meta("lower_revolutions")), float(player.get_meta("upper_revolutions")))
		weights.append(weight)
		total += weight
		var distance := absf(revolutions - reference)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = index
	if total > 0.0:
		for index in weights.size():
			weights[index] /= total
	elif not weights.is_empty():
		# Preserve the nearest boundary layer through throttle offset and limiter
		# overshoot. Never replace a high-RPM engine with the idle recording.
		weights[nearest] = 1.0
	return weights
