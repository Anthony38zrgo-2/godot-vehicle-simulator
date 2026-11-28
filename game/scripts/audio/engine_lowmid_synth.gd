class_name EngineLowMidSynth
extends RefCounted

## Real-time mono low-mid (50-350 Hz) engine body & aggression synthesizer.
## Designed to splice seamlessly under sampled WAV engine/exhaust layers:
## - 16 kHz mono AudioStreamGenerator (~267 samples/frame at 60 FPS, < 0.012 ms).
## - 2 phase-locked wavetable oscillators: 1.0x combustion pulse + per-car aux order (0.5x or 1.5x).
## - Load/torque-driven rational soft saturation + fixed body formant + dynamic 2-pole SVF LPF.

const CONFIG_PATH := "res://data/rally/engine_lowmid_synth.json"
const STREAM_RATE_HZ := 16000.0
const BUFFER_LENGTH_S := 0.12
const TARGET_QUEUED_FRAMES := 720 # 45 ms at 16 kHz
const MAX_PUSH_FRAMES := 1280
const TABLE_SIZE := 2048
const TABLE_MASK := TABLE_SIZE - 1

static var _config_cache: Dictionary = {}
static var _config_loaded: bool = false
static var _pulse_table_cache: Dictionary = {} # pulse_skew_key -> PackedFloat32Array
static var _sub_table: PackedFloat32Array = PackedFloat32Array()

var enabled: bool = false
var vehicle_key: String = ""
var synth_bus: String = ""
var player: AudioStreamPlayer3D = null

var _pulse_table: PackedFloat32Array = PackedFloat32Array()
var _buf: PackedVector2Array = PackedVector2Array()
var _cap: int = -1

# Acoustic parameters (loaded from preset + vehicle overrides)
var _orders_per_rev: float = 2.0
var _aux_order_mult: float = 1.5
var _aux_order_gain: float = 0.45
var _roughness_idle: float = 0.045
var _roughness_load: float = 0.025
var _roughness_overrun: float = 0.060
var _drive_base: float = 1.15
var _drive_load: float = 1.65
var _drive_bias: float = 0.14
var _hpf_hz: float = 45.0
var _body_freq_hz: float = 135.0
var _body_q: float = 1.35
var _body_gain: float = 0.32
var _idle_lpf_hz: float = 185.0
var _wot_lpf_hz: float = 340.0
var _lpf_q: float = 0.85
var _post_lpf_hz: float = 460.0
var _base_gain: float = 0.14
var _load_gain: float = 0.24
var _overrun_gain: float = 0.11
var _output_gain: float = 1.0
var _idle_gain_scale: float = 0.55
var _idle_rpm: float = 900.0
var _max_rpm: float = 7500.0
var _high_rpm_taper_start: float = 5600.0
var _high_rpm_taper_end: float = 7800.0
var _high_rpm_taper_floor: float = 0.62
var _cockpit_boost: float = 1.18
var _chase_exhaust_blend: float = 0.72
var _onboard_exhaust_blend: float = 0.28

var _engine_pos: Vector3 = Vector3(0.0, 0.55, -0.8)
var _exhaust_pos: Vector3 = Vector3(0.0, 0.20, 1.50)

# Continuous control state
var _target_rpm: float = 900.0
var _cur_rpm: float = 900.0
var _smoothed_throttle: float = 0.0
var _smoothed_load: float = 0.0
var _smoothed_pos_torque: float = 0.0
var _smoothed_overrun: float = 0.0
var _smoothed_limiter_cut: float = 0.0
var _target_drive: float = 1.15
var _cur_drive: float = 1.15
var _target_lpf_hz: float = 185.0
var _cur_lpf_hz: float = 185.0
var _target_roughness: float = 0.045
var _target_crackle_boost: float = 1.0

# Oscillator & DSP filter state (2 oscillators: main 1.0x + aux 0.5x/1.5x)
var _phase_main: float = 0.0
var _phase_aux: float = 0.0
var _phase_limiter: float = 0.0
var _rng_state: int = 0x51A7F321
var _cycle_amp: float = 1.0
var _cycle_amp_target: float = 1.0

var _hp_x: float = 0.0
var _hp_y: float = 0.0
var _hp_a: float = 0.98

# Fixed-frequency body formant TPT SVF
var _body_ic1: float = 0.0
var _body_ic2: float = 0.0
var _body_a1: float = 0.0
var _body_a2: float = 0.0
var _body_a3: float = 0.0

# Dynamic low-pass splice TPT SVF
var _lpf_ic1: float = 0.0
var _lpf_ic2: float = 0.0

# Extra 1-pole post-LPF for clean -18 dB/oct splice
var _post_lp_y: float = 0.0
var _post_lp_a: float = 0.16


static func _load_config() -> Dictionary:
	if _config_loaded:
		return _config_cache
	_config_loaded = true
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return _config_cache
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_config_cache = parsed
	return _config_cache


static func reload_config() -> void:
	_config_loaded = false
	_config_cache.clear()
	_load_config()


static func resolve_vehicle_config(candidates: Array[String]) -> Dictionary:
	var cfg := _load_config()
	if cfg.is_empty():
		return {}
	var vehicles: Dictionary = cfg.get("vehicles", {})
	var presets: Dictionary = cfg.get("presets", {})
	var matched_key := ""
	var veh_entry: Dictionary = {}
	for cand in candidates:
		var k := str(cand).strip_edges()
		if k.is_empty():
			continue
		if vehicles.has(k) and vehicles[k] is Dictionary:
			matched_key = k
			veh_entry = vehicles[k]
			break
	if matched_key.is_empty():
		if not bool(cfg.get("default_enabled", false)):
			return {}
		matched_key = candidates[0] if not candidates.is_empty() else "default"
	var is_on := bool(veh_entry.get("enabled", cfg.get("default_enabled", false)))
	if not is_on:
		return {}
	var preset_name := str(veh_entry.get("preset", "i4_rally"))
	var resolved: Dictionary = {}
	if presets.has(preset_name) and presets[preset_name] is Dictionary:
		resolved = (presets[preset_name] as Dictionary).duplicate(true)
	for key in veh_entry:
		resolved[key] = veh_entry[key]
	resolved["_resolved_key"] = matched_key
	return resolved


static func _get_pulse_table(skew: float) -> PackedFloat32Array:
	var s := clampf(skew, 0.08, 0.45)
	var key := int(round(s * 1000.0))
	if _pulse_table_cache.has(key):
		return _pulse_table_cache[key]
	var tbl := PackedFloat32Array()
	tbl.resize(TABLE_SIZE)
	var sum := 0.0
	for i in TABLE_SIZE:
		var p := float(i) / float(TABLE_SIZE)
		# Asymmetric combustion blowdown wave:
		# - Fast raised-cosine rise (exhaust valve opening / pressure spike -> aggressive 2nd/3rd harmonics)
		# - Smooth convex-exponential decay (cylinder expansion -> heavy low-mid body)
		var v := 0.0
		if p < s:
			var u := p / s
			v = 0.5 - 0.5 * cos(PI * u)
		else:
			var u := (p - s) / (1.0 - s)
			v = pow(1.0 - u, 1.55) * (0.5 + 0.5 * cos(PI * u * 0.5))
		# Blend a touch of fundamental sine to reinforce 1st firing order stability
		v = v * 0.82 + (0.5 + 0.5 * sin(TAU * p - PI * 0.35)) * 0.18
		tbl[i] = v
		sum += v
	# Remove DC offset and normalize peak
	var mean := sum / float(TABLE_SIZE)
	var peak := 0.0001
	for i in TABLE_SIZE:
		tbl[i] -= mean
		peak = maxf(peak, absf(tbl[i]))
	var inv_peak := 1.0 / peak
	for i in TABLE_SIZE:
		tbl[i] *= inv_peak
	_pulse_table_cache[key] = tbl
	return tbl


static func _get_sub_table() -> PackedFloat32Array:
	if not _sub_table.is_empty():
		return _sub_table
	_sub_table.resize(TABLE_SIZE)
	var peak := 0.0001
	for i in TABLE_SIZE:
		var p := float(i) / float(TABLE_SIZE)
		# Warm fundamental + subtle 2nd/3rd harmonic asymmetry (for 0.5x crank or 1.5x mechanical growl)
		var v := sin(TAU * p) + 0.28 * sin(TAU * 2.0 * p - 0.45) + 0.14 * sin(TAU * 3.0 * p)
		_sub_table[i] = v
		peak = maxf(peak, absf(v))
	var inv_peak := 1.0 / peak
	for i in TABLE_SIZE:
		_sub_table[i] *= inv_peak
	return _sub_table


func configure(
	candidates: Array[String],
	owner: Node3D,
	engine_pos: Vector3,
	exhaust_pos: Vector3
) -> bool:
	cleanup()
	var cfg := resolve_vehicle_config(candidates)
	if cfg.is_empty():
		return false

	enabled = true
	vehicle_key = str(cfg.get("_resolved_key", "vehicle"))
	_engine_pos = engine_pos
	_exhaust_pos = exhaust_pos

	_orders_per_rev = clampf(float(cfg.get("orders_per_rev", 2.0)), 0.5, 8.0)
	_aux_order_mult = clampf(float(cfg.get("aux_order_mult", 1.5)), 0.25, 3.0)
	_aux_order_gain = clampf(float(cfg.get("aux_order_gain", 0.45)), 0.0, 1.2)
	var pulse_skew := clampf(float(cfg.get("pulse_skew", 0.18)), 0.08, 0.45)
	_roughness_idle = clampf(float(cfg.get("roughness_idle", 0.045)), 0.0, 0.15)
	_roughness_load = clampf(float(cfg.get("roughness_load", 0.025)), 0.0, 0.15)
	_roughness_overrun = clampf(float(cfg.get("roughness_overrun", 0.060)), 0.0, 0.18)
	_drive_base = clampf(float(cfg.get("drive_base", 1.15)), 0.4, 4.0)
	_drive_load = clampf(float(cfg.get("drive_load", 1.65)), 0.0, 4.5)
	_drive_bias = clampf(float(cfg.get("drive_bias", 0.14)), 0.0, 0.45)
	_hpf_hz = clampf(float(cfg.get("hpf_hz", 65.0)), 20.0, 180.0)
	_body_freq_hz = clampf(float(cfg.get("body_freq_hz", 210.0)), 70.0, 420.0)
	_body_q = clampf(float(cfg.get("body_q", 1.20)), 0.5, 4.0)
	_body_gain = clampf(float(cfg.get("body_gain", 0.36)), 0.0, 1.0)
	_idle_lpf_hz = clampf(float(cfg.get("idle_lpf_hz", 280.0)), 90.0, 700.0)
	_wot_lpf_hz = clampf(float(cfg.get("wot_lpf_hz", 520.0)), _idle_lpf_hz, 1100.0)
	_lpf_q = clampf(float(cfg.get("lpf_q", 0.85)), 0.4, 2.5)
	_post_lpf_hz = clampf(float(cfg.get("post_lpf_hz", 680.0)), 200.0, 1800.0)
	_base_gain = clampf(float(cfg.get("base_gain", 0.14)), 0.0, 1.0)
	_load_gain = clampf(float(cfg.get("load_gain", 0.24)), 0.0, 1.0)
	_overrun_gain = clampf(float(cfg.get("overrun_gain", 0.11)), 0.0, 1.0)
	_output_gain = db_to_linear(clampf(float(cfg.get("output_db", 0.0)), -24.0, 12.0))
	_idle_gain_scale = clampf(float(cfg.get("idle_gain_scale", 0.55)), 0.1, 1.2)
	_idle_rpm = clampf(float(cfg.get("idle_rpm", 900.0)), 450.0, 1800.0)
	_max_rpm = clampf(float(cfg.get("max_rpm", 7500.0)), 3000.0, 14000.0)
	_high_rpm_taper_start = float(cfg.get("high_rpm_taper_start", _max_rpm * 0.75))
	_high_rpm_taper_end = maxf(_high_rpm_taper_start + 400.0, float(cfg.get("high_rpm_taper_end", _max_rpm * 1.04)))
	_high_rpm_taper_floor = clampf(float(cfg.get("high_rpm_taper_floor", 0.62)), 0.2, 1.0)
	_cockpit_boost = clampf(float(cfg.get("cockpit_boost", 1.18)), 0.7, 1.6)
	_chase_exhaust_blend = clampf(float(cfg.get("chase_exhaust_blend", 0.72)), 0.0, 1.0)
	_onboard_exhaust_blend = clampf(float(cfg.get("onboard_exhaust_blend", 0.28)), 0.0, 1.0)

	_pulse_table = _get_pulse_table(pulse_skew)
	_get_sub_table()

	# Precompute fixed filter coefficients (HPF, body formant SVF, post 1-pole LPF)
	var rc_hp := 1.0 / (TAU * _hpf_hz)
	var dt_s := 1.0 / STREAM_RATE_HZ
	_hp_a = rc_hp / (rc_hp + dt_s)

	var g_body := tan(PI * clampf(_body_freq_hz / STREAM_RATE_HZ, 0.002, 0.42))
	var k_body := 1.0 / _body_q
	_body_a1 = 1.0 / (1.0 + g_body * (g_body + k_body))
	_body_a2 = g_body * _body_a1
	_body_a3 = g_body * _body_a2

	var rc_post := 1.0 / (TAU * _post_lpf_hz)
	_post_lp_a = dt_s / (rc_post + dt_s)

	_cur_rpm = _idle_rpm
	_target_rpm = _idle_rpm
	_cur_drive = _drive_base
	_target_drive = _drive_base
	_cur_lpf_hz = _idle_lpf_hz
	_target_lpf_hz = _idle_lpf_hz

	_setup_bus(owner)

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = STREAM_RATE_HZ
	gen.buffer_length = BUFFER_LENGTH_S

	player = AudioStreamPlayer3D.new()
	player.name = "EngineLowMidSynth"
	player.stream = gen
	player.position = _engine_pos.lerp(_exhaust_pos, _chase_exhaust_blend)
	player.unit_size = 5.5
	player.max_distance = 550.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	player.bus = synth_bus
	player.volume_linear = 0.0
	owner.add_child(player)

	if owner.is_inside_tree():
		player.play()
	return true


func _setup_bus(owner: Node3D) -> void:
	var parent_bus := "Vehicle" if AudioServer.get_bus_index("Vehicle") != -1 else "Master"
	var inst_tag := str(owner.get_instance_id()) if owner != null else "0"
	synth_bus = "Rally:%s:%s:lowmid_synth" % [vehicle_key, inst_tag]
	var idx := AudioServer.get_bus_index(synth_bus)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, synth_bus)
	AudioServer.set_bus_send(idx, parent_bus)
	AudioServer.set_bus_volume_db(idx, 0.0)


func update(
	acoustic: Dictionary,
	revolutions: float,
	dt: float,
	view_engine_gain: float,
	view_exhaust_gain: float,
	cockpit_audio_blend: float,
	exhaust_crackle_s: float,
	owner: Node3D
) -> void:
	if not enabled or player == null:
		return
	if owner != null and owner.is_inside_tree() and not player.playing:
		player.play()

	var snap := dt >= 0.5
	var step_dt := clampf(dt, 0.001, 0.05)
	var alpha := 1.0 if snap else (1.0 - exp(-step_dt / 0.035))

	var rpm := maxf(revolutions, _idle_rpm * 0.45)
	var throttle := clampf(float(acoustic.get("throttle", 0.0)), 0.0, 1.0)
	var load := clampf(float(acoustic.get("load", throttle)), 0.0, 1.0)
	var signed_tq := clampf(float(acoustic.get("normalized_torque", load if throttle > 0.08 else -load)), -1.0, 1.0)
	var pos_torque := maxf(signed_tq, 0.0)
	var limiter_cut := clampf(float(acoustic.get("limiter_cut", 0.0)), 0.0, 1.0)
	var rpm_norm := clampf((rpm - _idle_rpm) / maxf(_max_rpm - _idle_rpm, 1000.0), 0.0, 1.15)
	var overrun_target := 1.0 if (throttle < 0.08 and signed_tq < -0.04 and rpm > _idle_rpm * 1.25) else 0.0
	# Slow overrun entry (~200 ms) so brief gear shifts (~140-180 ms) never drop the synth out
	# while fast recovery (~35 ms) restores full drive punch the instant throttle returns.
	var ovr_alpha := 1.0 if snap else (1.0 - exp(-step_dt / (0.20 if overrun_target > _smoothed_overrun else 0.035)))

	_target_rpm = rpm
	_smoothed_throttle = lerpf(_smoothed_throttle, throttle, alpha)
	_smoothed_load = lerpf(_smoothed_load, load, alpha)
	_smoothed_pos_torque = lerpf(_smoothed_pos_torque, pos_torque, alpha)
	_smoothed_overrun = lerpf(_smoothed_overrun, overrun_target, ovr_alpha)
	_smoothed_limiter_cut = lerpf(_smoothed_limiter_cut, limiter_cut, alpha)

	# Load aggression index (peaks when stomping throttle under positive engine torque)
	var aggression := clampf(0.45 * _smoothed_throttle + 0.55 * _smoothed_pos_torque, 0.0, 1.0)
	_target_drive = _drive_base + _drive_load * aggression
	# Dynamic crossover LPF: stays warm at idle/coast, opens up into lower-midrange under WOT load
	_target_lpf_hz = lerpf(_idle_lpf_hz, _wot_lpf_hz, clampf(aggression * 0.80 + rpm_norm * 0.30, 0.0, 1.0))
	_target_roughness = lerpf(
		lerpf(_roughness_idle, _roughness_load, aggression),
		_roughness_overrun,
		_smoothed_overrun
	)
	_target_crackle_boost = 1.0 + clampf(exhaust_crackle_s * 1.4, 0.0, 0.16)

	# RPM envelope: tucked gently at idle, strongest through low/mid torque band, tapered slightly at redline
	var off_idle := smoothstep(_idle_rpm * 0.95, _idle_rpm * 1.85, rpm)
	var idle_env := lerpf(_idle_gain_scale, 1.0, off_idle)
	var high_taper := lerpf(1.0, _high_rpm_taper_floor, smoothstep(_high_rpm_taper_start, _high_rpm_taper_end, rpm))

	var drive_gain := _base_gain + _load_gain * aggression
	var coast_gain := _overrun_gain * (0.62 + 0.38 * rpm_norm)
	var dyn_gain := lerpf(drive_gain, coast_gain, _smoothed_overrun)
	var view_ref := clampf(0.5 * minf(view_engine_gain, 1.0) + 0.5 * minf(view_exhaust_gain, 1.0), 0.35, 1.0)
	var cabin_scale := lerpf(1.0, _cockpit_boost, clampf(cockpit_audio_blend, 0.0, 1.0))

	# Smoothly position the single mono source between exhaust (chase) and engine firewall (onboard)
	var is_onboard := cockpit_audio_blend > 0.35 or (owner != null and owner.has_method("is_onboard_or_bonnet_camera") and bool(owner.call("is_onboard_or_bonnet_camera")))
	var exhaust_blend := _onboard_exhaust_blend if is_onboard else _chase_exhaust_blend
	player.position = _engine_pos.lerp(_exhaust_pos, exhaust_blend)

	var cam_comp := 1.0
	if owner != null and owner.has_method("camera_distance_compensation"):
		cam_comp = float(owner.call("camera_distance_compensation", player))

	player.volume_linear = clampf(dyn_gain * _output_gain * idle_env * high_taper * view_ref * cabin_scale * _target_crackle_boost, 0.0, 0.85) * cam_comp

	_pump_generator()


func pump_frame() -> void:
	if not enabled or player == null:
		return
	_pump_generator()


func _frames_needed(pb: AudioStreamGeneratorPlayback) -> int:
	if pb == null:
		return 0
	var avail := pb.get_frames_available()
	if avail <= 0:
		return 0
	_cap = maxi(_cap, avail)
	var queued := _cap - avail
	var target := mini(TARGET_QUEUED_FRAMES, maxi(_cap - 64, 320))
	return clampi(target - queued, 0, avail)


func _pump_generator() -> void:
	var pb := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var frames := mini(_frames_needed(pb), MAX_PUSH_FRAMES)
	if frames <= 0:
		return

	if _buf.size() < frames:
		_buf.resize(frames)

	var inv_frames := 1.0 / float(frames)
	var rpm_start := _cur_rpm
	var rpm_step := (_target_rpm - rpm_start) * inv_frames
	var drive_start := _cur_drive
	var drive_step := (_target_drive - drive_start) * inv_frames
	var lpf_hz := lerpf(_cur_lpf_hz, _target_lpf_hz, 0.35)
	_cur_lpf_hz = lpf_hz

	# Block-rate TPT SVF coefficients for dynamic LPF crossover (0 trig per sample!)
	var g_lp := tan(PI * clampf(lpf_hz / STREAM_RATE_HZ, 0.003, 0.42))
	var k_lp := 1.0 / _lpf_q
	var lp_a1 := 1.0 / (1.0 + g_lp * (g_lp + k_lp))
	var lp_a2 := g_lp * lp_a1
	var lp_a3 := g_lp * lp_a2

	var pulse_tbl := _pulse_table
	var sub_tbl := _sub_table
	var tbl_f := float(TABLE_SIZE)
	var inv_sr := 1.0 / STREAM_RATE_HZ
	var order_scale := (_orders_per_rev / 60.0) * inv_sr
	var aux_mult := _aux_order_mult
	var aux_g := _aux_order_gain
	var bias := _drive_bias
	var bias_dc := bias / (1.0 + absf(bias))
	var hp_a := _hp_a
	var b_a1 := _body_a1
	var b_a2 := _body_a2
	var b_a3 := _body_a3
	var b_gain := _body_gain
	var post_a := _post_lp_a
	var rough := _target_roughness
	var lim_cut := _smoothed_limiter_cut
	var lim_step := 28.0 * inv_sr # ~28 Hz mechanical spark-cut stutter

	# Cache state locals for fast GDScript inner loop
	var p_main := _phase_main
	var p_aux := _phase_aux
	var p_lim := _phase_limiter
	var rng := _rng_state
	var cyc_amp := _cycle_amp
	var cyc_tgt := _cycle_amp_target
	var hp_x := _hp_x
	var hp_y := _hp_y
	var b_ic1 := _body_ic1
	var b_ic2 := _body_ic2
	var l_ic1 := _lpf_ic1
	var l_ic2 := _lpf_ic2
	var post_y := _post_lp_y

	for i in frames:
		var rpm_i := rpm_start + rpm_step * float(i)
		var dp_main := rpm_i * order_scale

		p_main += dp_main
		if p_main >= 1.0:
			p_main -= floor(p_main)
			rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
			var u := (float(rng) / 2147483647.0) * 2.0 - 1.0
			cyc_tgt = 1.0 + u * rough

		p_aux += dp_main * aux_mult
		if p_aux >= 1.0:
			p_aux -= floor(p_aux)

		cyc_amp += 0.08 * (cyc_tgt - cyc_amp)

		# 2-oscillator wavetable linear interpolation (1.0x combustion pulse + aux 0.5x/1.5x)
		var fm := p_main * tbl_f
		var im := int(fm)
		var frac_m := fm - float(im)
		var im0 := im & TABLE_MASK
		var w_main := pulse_tbl[im0] + (pulse_tbl[(im0 + 1) & TABLE_MASK] - pulse_tbl[im0]) * frac_m

		var fa := p_aux * tbl_f
		var ia := int(fa)
		var frac_a := fa - float(ia)
		var ia0 := ia & TABLE_MASK
		var w_aux := sub_tbl[ia0] + (sub_tbl[(ia0 + 1) & TABLE_MASK] - sub_tbl[ia0]) * frac_a

		var raw := (w_main + aux_g * w_aux) * cyc_amp

		# Load-modulated asymmetric soft saturation (adds aggressive 2nd/3rd low-mid harmonics)
		var drv := drive_start + drive_step * float(i)
		var x_drv := raw * drv + bias
		var sat := x_drv / (1.0 + absf(x_drv)) - bias_dc

		# 1-pole HPF (~45 Hz) to remove DC and sub-audible rumble
		hp_y = hp_a * (hp_y + sat - hp_x)
		hp_x = sat

		# Fixed-frequency physical body/exhaust chest formant (TPT SVF bandpass tap)
		var bv3 := hp_y - b_ic2
		var bv1 := b_a1 * b_ic1 + b_a2 * bv3
		var bv2 := b_ic2 + b_a2 * b_ic1 + b_a3 * bv3
		b_ic1 = 2.0 * bv1 - b_ic1
		b_ic2 = 2.0 * bv2 - b_ic2
		var shaped := hp_y + bv1 * b_gain

		# Dynamic 2-pole TPT SVF Low-Pass splice filter (185 -> 340 Hz)
		var lv3 := shaped - l_ic2
		var lv1 := lp_a1 * l_ic1 + lp_a2 * lv3
		var lv2 := l_ic2 + lp_a2 * l_ic1 + lp_a3 * lv3
		l_ic1 = 2.0 * lv1 - l_ic1
		l_ic2 = 2.0 * lv2 - l_ic2

		# Extra 1-pole post-LPF (-18 dB/oct total slope above crossover)
		post_y += post_a * (lv2 - post_y)

		var out := post_y
		if lim_cut > 0.01:
			p_lim += lim_step
			if p_lim >= 1.0:
				p_lim -= 1.0
			# Gentle ignition-cut pulse so low-mid body stays glued to the sample on redline cuts
			var gate := 0.78 if p_lim < 0.40 else 1.0
			out *= lerpf(1.0, gate, lim_cut)

		out = clampf(out, -0.95, 0.95)
		_buf[i] = Vector2(out, out)

	# Commit state back
	_cur_rpm = _target_rpm
	_cur_drive = _target_drive
	_phase_main = p_main
	_phase_aux = p_aux
	_phase_limiter = p_lim
	_rng_state = rng
	_cycle_amp = cyc_amp
	_cycle_amp_target = cyc_tgt
	_hp_x = hp_x
	_hp_y = hp_y
	_body_ic1 = b_ic1
	_body_ic2 = b_ic2
	_lpf_ic1 = l_ic1
	_lpf_ic2 = l_ic2
	_post_lp_y = post_y

	pb.push_buffer(_buf if frames == _buf.size() else _buf.slice(0, frames))


func cleanup() -> void:
	if player != null and is_instance_valid(player):
		player.stop()
		player.queue_free()
	player = null
	enabled = false
	_cap = -1
	_hp_x = 0.0
	_hp_y = 0.0
	_body_ic1 = 0.0
	_body_ic2 = 0.0
	_lpf_ic1 = 0.0
	_lpf_ic2 = 0.0
	_post_lp_y = 0.0
