class_name SweepGranularEngineBank
extends RefCounted

const SeamlessVehicleLoop = preload("res://scripts/audio/seamless_vehicle_loop.gd")

const FORMAT_NAME := "rr3_sweep_granular_bank"
const STREAM_RATE_HZ := 24000.0
const BUFFER_LENGTH_S := 0.12
const TARGET_QUEUED_FRAMES := 1200 # 50 ms a 24 kHz (baja latencia + bombeo desde _process y _physics_process)
const MAX_PUSH_FRAMES := 2048

static var _pcm_cache: Dictionary = {}


static func is_sweep_bank(bank: Dictionary) -> bool:
	return int(bank.get("schema_version", 0)) == 4 and str(bank.get("format", "")) == FORMAT_NAME


static func clear_pcm_cache() -> void:
	_pcm_cache.clear()


class SweepTap:
	extends RefCounted

	var samples: PackedFloat32Array = PackedFloat32Array()
	var sr: float = 24000.0
	var points: Array = []
	var time_points: Array = []
	var segments: Array = []
	var rpm_start: float = 1800.0
	var rpm_step: float = 50.0
	var target_rms: float = 0.14

	var pos_a: float = 2000.0
	var pos_b: float = 2000.0
	var pos_a_max: float = 1e9
	var pos_b_max: float = 1e9
	var seg_a: int = 0
	var seg_b: int = 0
	var speed_a: float = 1.0
	var speed_b: float = 1.0
	var gain_a: float = 1.0
	var gain_b: float = 1.0
	var fade_rem: int = 0
	var fade_total: int = 960
	var jitter_seed: int = 1337
	var firing_order_mult: float = 2.0
	var pitch_character: float = 1.0
	var prev_target_pos: float = 2000.0
	var vel_ema: float = 0.0
	var initialized: bool = false

	func setup(spec: Dictionary, pcm_samples: PackedFloat32Array, firing_mult: float, pitch_char: float) -> void:
		firing_order_mult = firing_mult
		pitch_character = pitch_char
		sr = STREAM_RATE_HZ
		target_rms = clampf(float(spec.get("target_rms", 0.14)), 0.04, 0.45)
		initialized = false
		vel_ema = 0.0
		fade_rem = 0
		# Ordenar puntos por RPM ascendente para soportar sweeps de desaceleración o pasos no uniformes
		var raw_pts: Array = spec.get("points", []).duplicate()
		raw_pts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("rpm", 0.0)) < float(b.get("rpm", 0.0))
		)
		points = raw_pts
		var raw_time_pts: Array = spec.get("points", []).duplicate()
		raw_time_pts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("time_s", 0.0)) < float(b.get("time_s", 0.0))
		)
		time_points = raw_time_pts
		segments = spec.get("segments", [])
		if points.size() >= 2:
			rpm_start = float(points[0].get("rpm", 1800.0))
			rpm_step = maxf(float(points[1].get("rpm", rpm_start + 50.0)) - rpm_start, 1.0)
		samples = pcm_samples
		pos_a_max = float(maxi(samples.size() - 4, 64))
		pos_b_max = pos_a_max
		if samples.size() > 64 and not points.is_empty():
			var init_t := float(points[0].get("time_s", 0.1))
			pos_a = clampf(init_t * sr, 64.0, float(samples.size() - 64))
			pos_b = pos_a
			prev_target_pos = pos_a

	func is_ready() -> bool:
		return samples.size() > 64 and not points.is_empty()

	func _seg_bounds(seg_id: int) -> Vector2:
		var max_s := float(samples.size() - 8)
		if seg_id >= 0 and seg_id < segments.size():
			var s_dict: Dictionary = segments[seg_id]
			var lo := clampf(float(s_dict.get("start_s", 0.0)) * sr + 8.0, 8.0, max_s - 64.0)
			var hi := clampf(float(s_dict.get("end_s", max_s / sr)) * sr - 8.0, lo + 32.0, max_s)
			return Vector2(lo, hi)
		return Vector2(8.0, max_s)

	func lookup(sweep_rpm: float) -> Dictionary:
		var n := points.size()
		if n == 0:
			return {"time_s": 0.0, "rms": target_rms, "ref_rpm": sweep_rpm, "seg": 0}
		if n == 1 or sweep_rpm <= float(points[0].get("rpm", 0.0)):
			var p_first: Dictionary = points[0]
			return {
				"time_s": float(p_first.get("time_s", 0.0)),
				"rms": float(p_first.get("rms", target_rms)),
				"ref_rpm": float(p_first.get("ref_rpm", sweep_rpm)),
				"seg": int(p_first.get("seg", 0)),
			}
		if sweep_rpm >= float(points[n - 1].get("rpm", 0.0)):
			var p_last: Dictionary = points[n - 1]
			return {
				"time_s": float(p_last.get("time_s", 0.0)),
				"rms": float(p_last.get("rms", target_rms)),
				"ref_rpm": float(p_last.get("ref_rpm", sweep_rpm)),
				"seg": int(p_last.get("seg", 0)),
			}

		# Búsqueda binaria robusta ante grillas de RPM no uniformes
		var lo_idx := 0
		var hi_idx := n - 1
		while hi_idx - lo_idx > 1:
			var mid := (lo_idx + hi_idx) >> 1
			if float(points[mid].get("rpm", 0.0)) <= sweep_rpm:
				lo_idx = mid
			else:
				hi_idx = mid

		var p0: Dictionary = points[lo_idx]
		var p1: Dictionary = points[hi_idx]
		var r0 := float(p0.get("rpm", sweep_rpm))
		var r1 := float(p1.get("rpm", r0 + 1.0))
		var alpha := clampf((sweep_rpm - r0) / maxf(r1 - r0, 1.0), 0.0, 1.0)
		var seg0 := int(p0.get("seg", 0))
		var seg1 := int(p1.get("seg", 0))
		if seg0 != seg1:
			var pick: Dictionary = p0 if alpha < 0.5 else p1
			return {
				"time_s": float(pick.get("time_s", 0.0)),
				"rms": float(pick.get("rms", target_rms)),
				"ref_rpm": float(pick.get("ref_rpm", sweep_rpm)),
				"seg": int(pick.get("seg", 0)),
			}
		return {
			"time_s": lerpf(float(p0.get("time_s", 0.0)), float(p1.get("time_s", 0.0)), alpha),
			"rms": lerpf(float(p0.get("rms", target_rms)), float(p1.get("rms", target_rms)), alpha),
			"ref_rpm": lerpf(float(p0.get("ref_rpm", sweep_rpm)), float(p1.get("ref_rpm", sweep_rpm)), alpha),
			"seg": seg0,
		}

	func lookup_at_time(time_s: float) -> Dictionary:
		var n := time_points.size()
		if n == 0:
			return {"time_s": time_s, "rms": target_rms, "ref_rpm": rpm_start, "seg": 0}
		if n == 1 or time_s <= float(time_points[0].get("time_s", 0.0)):
			var p_first: Dictionary = time_points[0]
			return {
				"time_s": float(p_first.get("time_s", 0.0)),
				"rms": float(p_first.get("rms", target_rms)),
				"ref_rpm": float(p_first.get("ref_rpm", p_first.get("rpm", rpm_start))),
				"seg": int(p_first.get("seg", 0)),
			}
		if time_s >= float(time_points[n - 1].get("time_s", 0.0)):
			var p_last: Dictionary = time_points[n - 1]
			return {
				"time_s": float(p_last.get("time_s", 0.0)),
				"rms": float(p_last.get("rms", target_rms)),
				"ref_rpm": float(p_last.get("ref_rpm", p_last.get("rpm", rpm_start))),
				"seg": int(p_last.get("seg", 0)),
			}

		var lo_idx := 0
		var hi_idx := n - 1
		while hi_idx - lo_idx > 1:
			var mid := (lo_idx + hi_idx) >> 1
			if float(time_points[mid].get("time_s", 0.0)) <= time_s:
				lo_idx = mid
			else:
				hi_idx = mid

		var p0: Dictionary = time_points[lo_idx]
		var p1: Dictionary = time_points[hi_idx]
		var t0 := float(p0.get("time_s", time_s))
		var t1 := float(p1.get("time_s", t0 + 0.01))
		var alpha := clampf((time_s - t0) / maxf(t1 - t0, 0.0005), 0.0, 1.0)
		var seg0 := int(p0.get("seg", 0))
		var seg1 := int(p1.get("seg", 0))
		if seg0 != seg1:
			var pick: Dictionary = p0 if alpha < 0.5 else p1
			return {
				"time_s": float(pick.get("time_s", time_s)),
				"rms": float(pick.get("rms", target_rms)),
				"ref_rpm": float(pick.get("ref_rpm", pick.get("rpm", rpm_start))),
				"seg": int(pick.get("seg", 0)),
			}
		return {
			"time_s": time_s,
			"rms": lerpf(float(p0.get("rms", target_rms)), float(p1.get("rms", target_rms)), alpha),
			"ref_rpm": lerpf(
				float(p0.get("ref_rpm", p0.get("rpm", rpm_start))),
				float(p1.get("ref_rpm", p1.get("rpm", rpm_start))),
				alpha
			),
			"seg": seg0,
		}

	func _next_jitter(half_range: float) -> float:
		jitter_seed = (jitter_seed * 1103515245 + 12345) & 0x7FFFFFFF
		var u := float(jitter_seed) / 2147483647.0
		return (u * 2.0 - 1.0) * half_range

	func _align_phase(ref_pos: float, anchor: float, lo_bound: float, hi_bound: float, period_samples: float) -> float:
		var count := samples.size()
		var tap_step := maxi(3, int(period_samples / 12.0))
		var safe_margin := 4 * tap_step + 4
		if count <= safe_margin * 2 + 16:
			return clampf(anchor, lo_bound, hi_bound)

		var ir := clampi(int(ref_pos), safe_margin, count - safe_margin - 1)
		var half_p := int(clampf(period_samples * 0.6, 36.0, 640.0))
		var s_lo := maxi(maxi(int(lo_bound) + 24, safe_margin), int(anchor) - half_p)
		var s_hi := mini(mini(int(hi_bound) - 24, count - safe_margin - 1), int(anchor) + half_p)
		if s_hi <= s_lo:
			return clampf(anchor, float(safe_margin), float(count - safe_margin - 1))

		var stride := maxi(2, int(period_samples / 26.0))
		var best_pos := float(clampi(int(anchor), s_lo, s_hi))
		var best_score := -1e18
		var cand := s_lo
		while cand <= s_hi:
			var dot := 0.0
			var energy := 1e-6
			for k in 8:
				var off := (k - 4) * tap_step
				var s_ref := samples[ir + off]
				var s_cnd := samples[cand + off]
				dot += s_ref * s_cnd
				energy += s_cnd * s_cnd
			var norm_score := dot / sqrt(energy)
			if norm_score > best_score:
				best_score = norm_score
				best_pos = float(cand)
			cand += stride
		return best_pos + (ref_pos - floor(ref_pos))

	func prepare_for_rpm(pitch_rpm: float, lookup_rpm: float, block_frames: int) -> void:
		if not is_ready() or block_frames <= 0:
			return
		var info := lookup(lookup_rpm)
		var seg := int(info["seg"])
		var bounds := _seg_bounds(seg)
		var lo := bounds.x
		var hi := bounds.y
		var seg_len := maxf(hi - lo, 128.0)
		var raw_target := clampf(float(info["time_s"]) * sr, lo + 32.0, hi - 32.0)
		var target_ref_rpm := maxf(float(info["ref_rpm"]), 400.0)
		var sr_scale := sr / STREAM_RATE_HZ

		# Mantener pista mínima antes del límite superior del segmento para evitar micro-bucles (~45 Hz)
		var min_hi_runway := clampf(seg_len * 0.45, 1800.0, 4800.0)
		var hi_anchor_cap := maxf(lo + 48.0, hi - min_hi_runway)
		var center_pos := clampf(raw_target, lo + 48.0, hi_anchor_cap)

		if not initialized:
			initialized = true
			seg_a = seg
			seg_b = seg
			pos_a = center_pos
			pos_b = center_pos
			pos_a_max = hi
			pos_b_max = hi
			prev_target_pos = raw_target
			vel_ema = 0.0
			fade_rem = 0

		# Anclar pitch y ganancia a center_pos (y no al cabezal móvil pos_a) para eliminar saltos de escalera / FM por grano
		var info_pitch := lookup_at_time(center_pos / sr)
		var ref_rpm_pitch := maxf(float(info_pitch["ref_rpm"]), 400.0)
		var loc_rms_pitch := maxf(float(info_pitch["rms"]), 0.025)
		var cur_speed_a := clampf((pitch_rpm / ref_rpm_pitch) * pitch_character, 0.52, 1.48) * sr_scale
		var cur_gain_a := clampf(target_rms / loc_rms_pitch, 0.55, 1.65)
		speed_a = cur_speed_a
		gain_a = cur_gain_a

		var freq_fire := maxf((target_ref_rpm / 60.0) * firing_order_mult, 25.0)
		var period := sr / freq_fire
		var period_out := STREAM_RATE_HZ / freq_fire
		var target_fade_total := clampi(int(round(clampf(period_out * 1.25, 360.0, 840.0))), 360, 840)

		var delta_target := raw_target - prev_target_pos
		prev_target_pos = raw_target

		# Normalizar velocidad de barrido por frames generados (inmune a variaciones de tamaño de bloque)
		var step_samples := maxf(float(block_frames), 1.0)
		if seg == seg_a:
			var inst_vel := clampf(delta_target / step_samples, -3.5, 4.5)
			var vel_alpha := clampf(step_samples / 1800.0, 0.08, 0.45)
			vel_ema = lerpf(vel_ema, inst_vel, vel_alpha)
		else:
			vel_ema *= 0.5

		var sweep_factor := clampf(absf(vel_ema) / 0.85, 0.0, 1.0)
		var fwd_radius := clampf(lerpf(0.10, 0.14, sweep_factor) * sr, 1800.0, 3600.0)
		var lag_radius := clampf(lerpf(0.11, 0.14, sweep_factor) * sr, 2000.0, 3600.0)
		fwd_radius = minf(fwd_radius, seg_len * 0.40)
		lag_radius = minf(lag_radius, seg_len * 0.40)
		fwd_radius = maxf(fwd_radius, 2.5 * float(target_fade_total) * speed_a)

		var margin_after := float(block_frames) * speed_a + 32.0
		var fade_headroom := float(target_fade_total) * speed_a
		var play_hi_limit := maxf(lo + 0.52 * seg_len, hi - minf(seg_len * 0.35, margin_after * 0.65 + fade_headroom))

		# Interrumpir crossfade en curso si cambió de segmento o superó play_hi_limit
		if fade_rem > 0 and (seg != seg_a or pos_a > play_hi_limit):
			fade_rem = 0

		if fade_rem <= 0:
			pos_a_max = play_hi_limit
			var out_of_seg := (seg != seg_a)
			var out_of_bounds := pos_a < lo + 12.0 or pos_a > play_hi_limit
			var err := pos_a - center_pos
			var out_of_window := (err > fwd_radius) or (err < -lag_radius)
			if out_of_seg or out_of_bounds or out_of_window:
				pos_b = pos_a
				seg_b = seg_a
				pos_b_max = _seg_bounds(seg_b).y - 4.0
				speed_b = cur_speed_a
				gain_b = cur_gain_a

				# Posicionar anchor cerca de center_pos según deriva normalizada (sin teletransportes largos)
				var rel_drift := clampf(speed_a - vel_ema, -1.5, 1.5)
				var lead := 0.0
				if rel_drift > 0.20:
					lead = 0.075 * sr * clampf(rel_drift, 0.45, 1.0)
				elif rel_drift < -0.20:
					lead = -0.045 * sr * clampf(-rel_drift, 0.35, 1.0)
				var jitter_lim := clampf(0.18 * minf(fwd_radius, lag_radius), 40.0, 260.0)
				var anchor := clampf(
					center_pos - lead + _next_jitter(jitter_lim),
					lo + 48.0,
					hi_anchor_cap
				)
				pos_a = _align_phase(pos_b, anchor, lo + 16.0, hi_anchor_cap + 24.0, period)
				seg_a = seg
				pos_a_max = play_hi_limit

				fade_total = target_fade_total
				fade_rem = fade_total
		else:
			# Mantener el grano saliente B sincronizado con el mismo pitch estable anclado a center_pos
			speed_b = cur_speed_a

	func _read_interp(pos: float) -> float:
		var count := samples.size()
		var i0 := clampi(int(floor(pos)), 0, count - 2)
		var frac := pos - float(i0)
		var s0 := samples[i0]
		return s0 + (samples[i0 + 1] - s0) * frac

	func next_sample() -> float:
		var va := _read_interp(pos_a) * gain_a
		pos_a += speed_a
		var limit_a := minf(pos_a_max, float(samples.size() - 3))
		if pos_a >= limit_a:
			pos_a = limit_a - 1.0
		if fade_rem > 0:
			var vb := _read_interp(pos_b) * gain_b
			vb *= clampf((pos_b_max - pos_b) / 96.0, 0.0, 1.0)
			pos_b += speed_b
			var limit_b := minf(pos_b_max, float(samples.size() - 3))
			if pos_b >= limit_b:
				pos_b = limit_b - 1.0
			var u := 1.0 - float(fade_rem) / float(maxi(fade_total, 1))
			var w := 0.5 * (1.0 - cos(PI * u))
			fade_rem -= 1
			return vb * (1.0 - w) + va * w
		return va


var engine_bus: String = ""
var exhaust_bus: String = ""
var engine_player: AudioStreamPlayer3D = null
var exhaust_player: AudioStreamPlayer3D = null
var idle_engine_player: AudioStreamPlayer3D = null
var idle_exhaust_player: AudioStreamPlayer3D = null

var _accel_tap: SweepTap = SweepTap.new()
var _decel_tap: SweepTap = SweepTap.new()
var _buf_eng: PackedVector2Array = PackedVector2Array()
var _buf_exh: PackedVector2Array = PackedVector2Array()
var _cap_eng: int = -1
var _cap_exh: int = -1

var _idle_rpm: float = 900.0
var _max_rpm: float = 7200.0
var _sweep_rpm_scale: float = 1.0
var _pitch_character: float = 1.0
var _idle_measured_rpm: float = 850.0
var _idle_xfade_lo: float = 1050.0
var _idle_xfade_hi: float = 1750.0
var _timbre_load_offset_rpm: float = 200.0
var _idle_level_match: float = 1.0

var _eq_lpf_base_hz: float = 9000.0
var _eng_lpf_eff: AudioEffectLowPassFilter = null
var _exh_lpf_eff: AudioEffectLowPassFilter = null

var _overrun_mix: float = 0.0
var _in_overrun: bool = false
var is_overrun: bool = false
var last_accel_weight: float = 1.0
var last_decel_weight: float = 0.0
var _smoothed_throttle: float = 0.0
var _smoothed_load: float = 0.2
var _prev_sa_lp: float = 0.0
var _prev_mono_lp: float = 0.0


static func _resolve_wav_path(manifest_path: String, raw_path: String) -> String:
	if raw_path.is_empty() or raw_path.begins_with("res://") or raw_path.begins_with("user://"):
		return raw_path
	if not manifest_path.is_empty():
		return manifest_path.get_base_dir().path_join(raw_path)
	return raw_path


static func _load_pcm_f32(wav_path: String) -> PackedFloat32Array:
	if wav_path.is_empty():
		return PackedFloat32Array()
	if _pcm_cache.has(wav_path):
		return _pcm_cache[wav_path]
	var wav: AudioStreamWAV = SeamlessVehicleLoop.load_pcm(wav_path, false)
	if wav == null or wav.data.is_empty():
		push_warning("SweepGranularEngineBank: failed to load PCM data from '%s'" % wav_path)
		return PackedFloat32Array()
	if wav.format != AudioStreamWAV.FORMAT_16_BITS:
		push_warning("SweepGranularEngineBank: unsupported WAV format (%d) in '%s' (expected FORMAT_16_BITS)" % [wav.format, wav_path])
		return PackedFloat32Array()
	var bytes: PackedByteArray = wav.data
	var step := 4 if wav.stereo else 2
	var frames := int(bytes.size() / step)
	var out := PackedFloat32Array()
	out.resize(frames)
	if wav.stereo:
		for i in frames:
			var base := i * 4
			var l := float(bytes.decode_s16(base)) / 32768.0
			var r := float(bytes.decode_s16(base + 2)) / 32768.0
			out[i] = 0.5 * (l + r)
	else:
		for i in frames:
			out[i] = float(bytes.decode_s16(i * 2)) / 32768.0

	var src_rate := float(wav.mix_rate) if wav.mix_rate > 0 else STREAM_RATE_HZ
	if absf(src_rate - STREAM_RATE_HZ) > 1.0 and out.size() > 4:
		var ratio := src_rate / STREAM_RATE_HZ
		# Filtro antialiasing de 3 puntos antes de diezmar si src_rate > STREAM_RATE_HZ
		var src_buf := out
		if ratio > 1.05:
			var filtered := PackedFloat32Array()
			filtered.resize(out.size())
			filtered[0] = out[0]
			var last_idx := out.size() - 1
			for i in range(1, last_idx):
				filtered[i] = 0.25 * out[i - 1] + 0.50 * out[i] + 0.25 * out[i + 1]
			filtered[last_idx] = out[last_idx]
			src_buf = filtered
		var new_len := maxi(int(round(float(src_buf.size()) / ratio)), 64)
		var resampled := PackedFloat32Array()
		resampled.resize(new_len)
		var max_src := src_buf.size() - 2
		for i in new_len:
			var src_pos := float(i) * ratio
			var i0 := clampi(int(floor(src_pos)), 0, max_src)
			var frac := clampf(src_pos - float(i0), 0.0, 1.0)
			resampled[i] = src_buf[i0] + (src_buf[i0 + 1] - src_buf[i0]) * frac
		out = resampled

	_pcm_cache[wav_path] = out
	return out


func configure(
	bank: Dictionary,
	manifest_path: String,
	owner: Node3D,
	_routing: Variant,
	engine_pos: Vector3,
	exhaust_pos: Vector3
) -> bool:
	cleanup()
	if not is_sweep_bank(bank):
		push_warning("SweepGranularEngineBank: invalid sweep bank format at '%s'" % manifest_path)
		return false

	var vid := str(bank.get("vehicle_id", "vehicle"))
	var cyl := int(bank.get("cylinders", 4))
	var firing_mult := float(bank.get("firing_order_multiplier", 3.0 if cyl == 6 else 2.0))

	var rp: Dictionary = bank.get("rpm_profile", {})
	_idle_rpm = float(rp.get("idle_rpm", 900.0))
	_max_rpm = float(rp.get("max_rpm", 7200.0))
	_sweep_rpm_scale = clampf(float(rp.get("sweep_rpm_scale", 1.0)), 0.7, 1.35)
	_pitch_character = clampf(float(rp.get("pitch_character", 1.0)), 0.72, 1.35)
	_idle_xfade_lo = float(rp.get("idle_crossfade_start_rpm", _idle_rpm * 1.15))
	_idle_xfade_hi = maxf(_idle_xfade_lo + 250.0, float(rp.get("idle_crossfade_end_rpm", _idle_rpm * 1.95)))
	_timbre_load_offset_rpm = float(rp.get("timbre_load_offset_rpm", 220.0))

	var ep_arr: Array = bank.get("engine_position", [])
	if ep_arr.size() >= 3:
		engine_pos = Vector3(float(ep_arr[0]), float(ep_arr[1]), float(ep_arr[2]))
	var xp_arr: Array = bank.get("exhaust_position", [])
	if xp_arr.size() >= 3:
		exhaust_pos = Vector3(float(xp_arr[0]), float(xp_arr[1]), float(xp_arr[2]))

	var acc_spec: Dictionary = bank.get("accel", {})
	var dec_spec: Dictionary = bank.get("decel", {})
	var acc_path := _resolve_wav_path(manifest_path, str(acc_spec.get("path", "")))
	var dec_path := _resolve_wav_path(manifest_path, str(dec_spec.get("path", "")))
	_accel_tap.setup(acc_spec, _load_pcm_f32(acc_path), firing_mult, _pitch_character)
	_decel_tap.setup(dec_spec, _load_pcm_f32(dec_path), firing_mult, _pitch_character)
	if not _accel_tap.is_ready():
		push_warning("SweepGranularEngineBank: accel tap is not ready for '%s' (path='%s')" % [vid, acc_path])
		return false

	var eq: Dictionary = bank.get("eq_profile", {})
	_eq_lpf_base_hz = clampf(float(eq.get("lpf_hz", 9000.0)), 1800.0, 18000.0)
	_setup_buses(vid, eq, owner)

	# Build idle WAV voice pair
	var idle_spec: Dictionary = bank.get("idle", {})
	var idle_path := _resolve_wav_path(manifest_path, str(idle_spec.get("path", "")))
	_idle_measured_rpm = clampf(float(idle_spec.get("measured_rpm", _idle_rpm)), 450.0, 1800.0)
	var idle_rms := maxf(float(idle_spec.get("rms", 0.08)), 0.02)
	_idle_level_match = clampf(_accel_tap.target_rms / idle_rms, 0.7, 2.2)

	if not idle_path.is_empty():
		var idle_loop: Dictionary = idle_spec.get("loop", {})
		var idle_stream := SeamlessVehicleLoop.load_pcm(idle_path, true, {}, idle_loop, true)
		if idle_stream != null:
			idle_engine_player = _make_player3d(owner, "SweepIdleEngine", engine_pos, 4.5, 400.0, engine_bus, idle_stream)
			idle_exhaust_player = _make_player3d(owner, "SweepIdleExhaust", exhaust_pos, 6.0, 1030.0, exhaust_bus, idle_stream)

	# Build dual AudioStreamGenerator sweep voices (front mechanical/intake & rear exhaust)
	var gen_eng := AudioStreamGenerator.new()
	gen_eng.mix_rate = STREAM_RATE_HZ
	gen_eng.buffer_length = BUFFER_LENGTH_S
	engine_player = _make_player3d(owner, "SweepGranularEngine", engine_pos, 4.5, 400.0, engine_bus, gen_eng)

	var gen_exh := AudioStreamGenerator.new()
	gen_exh.mix_rate = STREAM_RATE_HZ
	gen_exh.buffer_length = BUFFER_LENGTH_S
	exhaust_player = _make_player3d(owner, "SweepGranularExhaust", exhaust_pos, 6.0, 1030.0, exhaust_bus, gen_exh)

	if owner.is_inside_tree():
		_start_players()
	return true


func _setup_buses(vid: String, eq: Dictionary, owner: Node3D = null) -> void:
	var target_parent := "Vehicle" if AudioServer.get_bus_index("Vehicle") != -1 else "Master"
	var inst_tag := str(owner.get_instance_id()) if owner != null else "0"
	engine_bus = "Rally:%s:%s:sweep_eng" % [vid, inst_tag]
	exhaust_bus = "Rally:%s:%s:sweep_exh" % [vid, inst_tag]
	var hpf_hz := clampf(float(eq.get("hpf_hz", 45.0)), 25.0, 260.0)
	_eng_lpf_eff = _configure_single_bus(engine_bus, target_parent, hpf_hz, _eq_lpf_base_hz, eq.get("engine_bands_db", []))
	_exh_lpf_eff = _configure_single_bus(exhaust_bus, target_parent, maxf(35.0, hpf_hz * 0.85), _eq_lpf_base_hz * 0.9, eq.get("exhaust_bands_db", []))


func _configure_single_bus(bus_name: String, parent_bus: String, hpf_hz: float, lpf_hz: float, bands: Array) -> AudioEffectLowPassFilter:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, parent_bus)
	while AudioServer.get_bus_effect_count(idx) > 0:
		AudioServer.remove_bus_effect(idx, 0)

	var hpf := AudioEffectHighPassFilter.new()
	hpf.cutoff_hz = hpf_hz
	AudioServer.add_bus_effect(idx, hpf)

	var eq10 := AudioEffectEQ10.new()
	for bi in mini(bands.size(), 10):
		eq10.set_band_gain_db(bi, clampf(float(bands[bi]), -18.0, 12.0))
	AudioServer.add_bus_effect(idx, eq10)

	var lpf := AudioEffectLowPassFilter.new()
	lpf.cutoff_hz = lpf_hz
	lpf.resonance = 0.65
	AudioServer.add_bus_effect(idx, lpf)
	return lpf


func _make_player3d(owner: Node3D, node_name: String, pos: Vector3, unit_sz: float, max_dist: float, bus_name: String, stream: AudioStream) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.stream = stream
	p.position = pos
	p.unit_size = unit_sz
	p.max_distance = max_dist
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.bus = bus_name
	p.volume_linear = 0.0
	owner.add_child(p)
	return p


func _start_players() -> void:
	for p in [idle_engine_player, idle_exhaust_player, engine_player, exhaust_player]:
		if p != null and p.is_inside_tree() and not p.playing:
			p.play()


func get_active_players() -> Array[AudioStreamPlayer3D]:
	var out: Array[AudioStreamPlayer3D] = []
	for p in [idle_engine_player, idle_exhaust_player, engine_player, exhaust_player]:
		if p != null:
			out.append(p)
	return out


func update(
	acoustic: Dictionary,
	revolutions: float,
	dt: float,
	view_engine_gain: float,
	view_exhaust_gain: float,
	exhaust_crackle_s: float,
	_exhaust_cfg: Dictionary,
	owner: Node3D
) -> void:
	if engine_player == null or exhaust_player == null:
		return
	if owner != null and owner.is_inside_tree():
		_start_players()

	var snap := dt >= 0.5
	var step_dt := clampf(dt, 0.001, 0.05)
	var rpm := maxf(float(acoustic.get("rpm", revolutions)), _idle_rpm * 0.45)
	if revolutions > _idle_rpm * 0.45:
		rpm = revolutions
	var throttle := clampf(float(acoustic.get("throttle", 0.0)), 0.0, 1.0)
	var load := clampf(float(acoustic.get("load", throttle)), 0.0, 1.2)
	var engine_gain := clampf(float(acoustic.get("engine_gain", 1.0)), 0.0, 2.5)
	var limiter_active := bool(acoustic.get("limiter", false))
	var limiter_cut_val := clampf(float(acoustic.get("limiter_cut", 0.0)), 0.0, 1.0)

	var s_alpha := 1.0 if snap else (1.0 - exp(-step_dt / 0.04))
	_smoothed_throttle = lerpf(_smoothed_throttle, throttle, s_alpha)
	_smoothed_load = lerpf(_smoothed_load, load, s_alpha)

	# Hysteresis overrun switch matching RallyVehicleAudio semantics
	var norm_tq := float(acoustic.get("normalized_torque", 0.0))
	if not _in_overrun:
		if (_smoothed_throttle < 0.08 or norm_tq < -0.05) and rpm > _idle_rpm * 1.32:
			_in_overrun = true
	elif _smoothed_throttle > 0.16 or rpm <= _idle_rpm * 1.12:
		_in_overrun = false
	is_overrun = _in_overrun
	var overrun_target := 1.0 if _in_overrun else 0.0
	var ovr_alpha := 1.0 if snap else (1.0 - exp(-step_dt / 0.055))
	_overrun_mix = lerpf(_overrun_mix, overrun_target, ovr_alpha)
	var has_decel := _decel_tap.is_ready()
	last_accel_weight = (1.0 - _overrun_mix) * (0.28 + 0.72 * _smoothed_throttle) if has_decel else 1.0
	last_decel_weight = (1.0 - last_accel_weight) if has_decel else 0.0

	# Idle <-> Sweep crossfade
	var u_xfade := clampf((rpm - _idle_xfade_lo) / maxf(_idle_xfade_hi - _idle_xfade_lo, 100.0), 0.0, 1.0)
	var sweep_env := sin(u_xfade * PI * 0.5)
	var idle_env := cos(u_xfade * PI * 0.5)

	var rpm_norm := clampf((rpm - _idle_rpm) / maxf(_max_rpm - _idle_rpm, 1000.0), 0.0, 1.15)
	var rev_scale := 0.52 + 0.48 * rpm_norm
	var load_eng_drive := clampf(maxf(0.45 * _smoothed_load + 0.55 * _smoothed_throttle, _overrun_mix * 0.48), 0.0, 1.0)
	var load_scale_eng := 0.66 + 0.34 * load_eng_drive
	var load_scale_exh := 0.56 + 0.44 * maxf(_smoothed_throttle, _overrun_mix * 0.72)
	var cut_scale := clampf(1.0 - 0.65 * limiter_cut_val - (0.12 if limiter_active else 0.0), 0.25, 1.0)
	var crackle_boost := 1.0 + clampf(exhaust_crackle_s * 1.5, 0.0, 0.18)

	# Normalización continua de view_engine_gain (evita salto escalón de 5 dB al transicionar desde CHASE_ENGINE_BOOST = 4.4668x)
	var eff_view_eng := clampf(view_engine_gain, 0.0, 0.65)
	if view_engine_gain > 0.65:
		var t_boost := clampf((view_engine_gain - 0.65) / (2.39 - 0.65), 0.0, 1.0)
		eff_view_eng = lerpf(0.65, 0.55, t_boost)
	var eff_view_exh := clampf(view_exhaust_gain, 0.0, 1.2)

	var cam_comp_idle_eng := 1.0
	var cam_comp_idle_exh := 1.0
	var cam_comp_sw_eng := 1.0
	var cam_comp_sw_exh := 1.0
	if owner != null and owner.has_method("camera_distance_compensation"):
		if idle_engine_player != null:
			cam_comp_idle_eng = float(owner.call("camera_distance_compensation", idle_engine_player))
		if idle_exhaust_player != null:
			cam_comp_idle_exh = float(owner.call("camera_distance_compensation", idle_exhaust_player))
		cam_comp_sw_eng = float(owner.call("camera_distance_compensation", engine_player))
		cam_comp_sw_exh = float(owner.call("camera_distance_compensation", exhaust_player))

	# 1. Update Idle WAV pair
	var idle_pitch := clampf((rpm / _idle_measured_rpm) * lerpf(1.0, _pitch_character, 0.35), 0.68, 1.55)
	var idle_base_lin := clampf(idle_env * engine_gain * 0.30 * _idle_level_match, 0.0, 0.85)
	if idle_engine_player != null:
		idle_engine_player.pitch_scale = idle_pitch
		idle_engine_player.volume_linear = idle_base_lin * eff_view_eng * 0.85 * cam_comp_idle_eng
	if idle_exhaust_player != null:
		idle_exhaust_player.pitch_scale = idle_pitch
		idle_exhaust_player.volume_linear = idle_base_lin * eff_view_exh * cam_comp_idle_exh

	# 2. Update Granular Sweep pair (engine + exhaust 3D streams)
	var sw_eng_lin := clampf(sweep_env * rev_scale * load_scale_eng * engine_gain * cut_scale * eff_view_eng * 0.52, 0.0, 0.95) * cam_comp_sw_eng
	var sw_exh_lin := clampf(sweep_env * rev_scale * load_scale_exh * engine_gain * cut_scale * crackle_boost * eff_view_exh * 0.60, 0.0, 0.95) * cam_comp_sw_exh
	engine_player.volume_linear = sw_eng_lin
	exhaust_player.volume_linear = sw_exh_lin

	# Leer cockpit_audio_blend real de RallyVehicleAudio en lugar de inferirlo de view_exhaust_gain
	var cockpit_blend := float(owner.get("cockpit_audio_blend")) if owner != null and owner.get("cockpit_audio_blend") != null else 0.0
	var cockpit_factor := lerpf(1.0, 0.42, clampf(cockpit_blend, 0.0, 1.0))
	if _eng_lpf_eff != null:
		var eng_cut := _eq_lpf_base_hz * (0.68 + 0.32 * _smoothed_throttle) * cockpit_factor
		_eng_lpf_eff.cutoff_hz = clampf(eng_cut, 1200.0, 18000.0)
	if _exh_lpf_eff != null:
		var exh_cut := _eq_lpf_base_hz * (0.45 + 0.40 * _smoothed_throttle + 0.15 * rpm_norm) * cockpit_factor
		_exh_lpf_eff.cutoff_hz = clampf(exh_cut, 900.0, 18000.0)

	_pump_generators(rpm)


func _frames_needed(pb: AudioStreamGeneratorPlayback, is_eng: bool) -> int:
	if pb == null:
		return 0
	var avail := pb.get_frames_available()
	if avail <= 0:
		return 0
	if is_eng:
		_cap_eng = maxi(_cap_eng, avail)
		var queued := _cap_eng - avail
		var target := mini(TARGET_QUEUED_FRAMES, maxi(_cap_eng - 128, 480))
		return clampi(target - queued, 0, avail)
	else:
		_cap_exh = maxi(_cap_exh, avail)
		var queued := _cap_exh - avail
		var target := mini(TARGET_QUEUED_FRAMES, maxi(_cap_exh - 128, 480))
		return clampi(target - queued, 0, avail)


func pump_frame(rpm: float) -> void:
	_pump_generators(rpm)


func _pump_generators(rpm: float) -> void:
	var pb_eng := engine_player.get_stream_playback() as AudioStreamGeneratorPlayback if engine_player != null else null
	var pb_exh := exhaust_player.get_stream_playback() as AudioStreamGeneratorPlayback if exhaust_player != null else null
	if pb_eng == null and pb_exh == null:
		return

	var need_eng := _frames_needed(pb_eng, true)
	var need_exh := _frames_needed(pb_exh, false)
	if pb_eng != null and pb_exh != null and _cap_eng > 0 and _cap_exh > 0:
		var q_eng := _cap_eng - pb_eng.get_frames_available()
		var q_exh := _cap_exh - pb_exh.get_frames_available()
		if absi(q_eng - q_exh) > 240:
			pb_eng.clear_buffer()
			pb_exh.clear_buffer()
			need_eng = _frames_needed(pb_eng, true)
			need_exh = _frames_needed(pb_exh, false)

	need_eng = mini(need_eng, MAX_PUSH_FRAMES)
	need_exh = mini(need_exh, MAX_PUSH_FRAMES)
	var frames := maxi(need_eng, need_exh)
	if frames <= 0:
		return

	var pitch_rpm := maxf(rpm * _sweep_rpm_scale, 800.0)
	var timbre_shift := (_smoothed_throttle - 0.5) * _timbre_load_offset_rpm
	var lookup_rpm := maxf(pitch_rpm + timbre_shift, 800.0)
	_accel_tap.prepare_for_rpm(pitch_rpm, lookup_rpm, frames)
	var has_decel := _decel_tap.is_ready()
	if has_decel:
		_decel_tap.prepare_for_rpm(pitch_rpm, lookup_rpm, frames)

	var accel_w := clampf(last_accel_weight, 0.0, 1.0)
	var decel_w := clampf(last_decel_weight, 0.0, 1.0)
	# Crossfade de potencia constante entre fuentes no correlacionadas (evita caída de -3 dB al 50%)
	var w_acc := sqrt(accel_w) if has_decel else 1.0
	var w_dec := sqrt(decel_w) if has_decel else 0.0
	var rpm_norm := clampf((rpm - _idle_rpm) / maxf(_max_rpm - _idle_rpm, 1000.0), 0.0, 1.15)
	var hf_sheen_gain := decel_w * clampf(0.32 + 0.22 * rpm_norm, 0.32, 0.58) if has_decel else 0.0
	var low_trim := lerpf(0.28, 0.46, decel_w) if has_decel else 0.28

	if _buf_eng.size() < frames:
		_buf_eng.resize(frames)
		_buf_exh.resize(frames)

	for i in frames:
		var sa := _accel_tap.next_sample()
		var sd := _decel_tap.next_sample() if has_decel else sa
		var mono := clampf((sa * w_acc + sd * w_dec) * 0.40, -0.75, 0.75)
		_prev_sa_lp += 0.14 * (mono - _prev_sa_lp)
		var mono_hf := mono - _prev_sa_lp
		_prev_mono_lp += 0.15 * (mono - _prev_mono_lp)
		# Capa mecánica/admisión delantera: realce limpio sobre la mezcla real sin contaminar overrun con accel puro
		var eng_sample := clampf((mono - low_trim * _prev_mono_lp) + mono_hf * hf_sheen_gain, -0.75, 0.75)
		_buf_eng[i] = Vector2(eng_sample, eng_sample)
		_buf_exh[i] = Vector2(mono, mono)

	if pb_eng != null and need_eng > 0:
		pb_eng.push_buffer(_buf_eng if need_eng == _buf_eng.size() else _buf_eng.slice(0, need_eng))
	if pb_exh != null and need_exh > 0:
		pb_exh.push_buffer(_buf_exh if need_exh == _buf_exh.size() else _buf_exh.slice(0, need_exh))


func get_engine_energy() -> float:
	var sum := 0.0
	for p in [idle_engine_player, engine_player]:
		if p != null:
			sum += p.volume_linear * p.volume_linear
	return sum


func get_exhaust_energy() -> float:
	var sum := 0.0
	for p in [idle_exhaust_player, exhaust_player]:
		if p != null:
			sum += p.volume_linear * p.volume_linear
	return sum


func cleanup() -> void:
	for p in [idle_engine_player, idle_exhaust_player, engine_player, exhaust_player]:
		if p != null and is_instance_valid(p):
			p.stop()
			p.queue_free()
	idle_engine_player = null
	idle_exhaust_player = null
	engine_player = null
	exhaust_player = null
	_eng_lpf_eff = null
	_exh_lpf_eff = null
	_cap_eng = -1
	_cap_exh = -1
	_overrun_mix = 0.0
	_in_overrun = false
	is_overrun = false
	last_accel_weight = 1.0
	last_decel_weight = 0.0
	_smoothed_throttle = 0.0
	_smoothed_load = 0.2
	_prev_sa_lp = 0.0
	_prev_mono_lp = 0.0
	_accel_tap.initialized = false
	_decel_tap.initialized = false
