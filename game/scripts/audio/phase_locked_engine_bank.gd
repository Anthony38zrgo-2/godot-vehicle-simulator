extends RefCounted

const SLOT_ORDER: Array[String] = [
	"idle_idle",
	"low_partial",
	"low_high_load",
	"low_overrun",
	"mid_partial",
	"mid_high_load",
	"mid_overrun",
	"high_partial",
	"high_high_load",
	"high_overrun",
]

const CORR_TEMPLATE_LEN := 128
const PHASE_DRIFT_RESYNC_CYCLES := 0.025
const SEVEN_WOT_TARGETS_EXHAUST := [0.021, 0.095, 0.210, 0.048, 0.135, 0.275, 0.062, 0.180, 0.340, 0.078]
const SEVEN_WOT_TARGETS_MECHANICAL := [0.019, 0.075, 0.115, 0.064, 0.130, 0.185, 0.105, 0.210, 0.280, 0.160]

var idle_rpm: float = 900.0
var low_rpm: float = 2300.0
var mid_rpm: float = 4300.0
var high_rpm: float = 6400.0
var redline_rpm: float = 7300.0

var is_overrun: bool = false
var has_partial_slots: bool = true
var load_weights_smoothed: Array[float] = [1.0, 0.0, 0.0]
var slot_weights_smoothed: Array[float] = []

var exhaust_slots: Array = []
var mechanical_slots: Array = []
var exhaust_slot_trims: Array[float] = []
var mechanical_slot_trims: Array[float] = []
var exhaust_corr: Array = []
var mechanical_corr: Array = []
var exhaust_lpf: AudioEffectLowPassFilter = null

var smoothed_exhaust_bus_gain: float = 0.0
var smoothed_mechanical_bus_gain: float = 0.0


static func is_schema3_bank(bank: Dictionary) -> bool:
	return (
		str(bank.get("format", "")) == "rally_maniac_engine_bank"
		or (int(bank.get("schema_version", 1)) >= 3 and bank.has("buses"))
	)


func configure(
	bank: Dictionary,
	manifest_path: String,
	owner: Node3D,
	sample_voice_class: Variant,
	routing: VehicleSoundRouting,
	engine_position: Vector3,
	exhaust_position: Vector3,
	engine_voices: Array,
	exhaust_voices: Array,
) -> bool:
	var anchors: Dictionary = bank.get("anchors", {})
	idle_rpm = float(anchors.get("idle_rpm", 900.0))
	low_rpm = float(anchors.get("low_rpm", 2300.0))
	mid_rpm = float(anchors.get("mid_rpm", 4300.0))
	high_rpm = float(anchors.get("high_rpm", 6400.0))
	redline_rpm = float(anchors.get("redline_rpm", 7300.0))

	is_overrun = false
	load_weights_smoothed = [1.0, 0.0, 0.0]
	slot_weights_smoothed.clear()
	for _i in SLOT_ORDER.size():
		slot_weights_smoothed.append(0.0)
	slot_weights_smoothed[0] = 1.0

	exhaust_slots.clear()
	mechanical_slots.clear()
	exhaust_slot_trims.clear()
	mechanical_slot_trims.clear()
	for _i in SLOT_ORDER.size():
		exhaust_slots.append(null)
		mechanical_slots.append(null)
		exhaust_slot_trims.append(1.0)
		mechanical_slot_trims.append(1.0)

	var prebaked_loop_seam := bool(bank.get("prebaked_loop_seam", true))
	if exhaust_lpf == null:
		exhaust_lpf = AudioEffectLowPassFilter.new()
		exhaust_lpf.cutoff_hz = 14000.0
		exhaust_lpf.resonance = 0.5
	var bank_dir := manifest_path.get_base_dir()
	var exhaust_templates: Array[PackedFloat32Array] = []
	var mechanical_templates: Array[PackedFloat32Array] = []
	for _i in SLOT_ORDER.size():
		exhaust_templates.append(PackedFloat32Array())
		mechanical_templates.append(PackedFloat32Array())

	for entry in bank.get("samples", []):
		if not (entry is Dictionary):
			continue
		var bus_name := str(entry.get("bus", ""))
		var rpm_zone := str(entry.get("rpm_zone", ""))
		var load_state := str(entry.get("load_state", ""))
		if bus_name.is_empty() or rpm_zone.is_empty() or load_state.is_empty():
			continue
		var slot_name := rpm_zone + "_" + load_state
		var slot_idx := SLOT_ORDER.find(slot_name)
		if slot_idx < 0:
			continue

		var rel_file := str(entry.get("file", ""))
		if rel_file.is_empty():
			continue
		var sample_path := bank_dir.path_join(rel_file)
		var is_corr_closed := prebaked_loop_seam or str(entry.get("crossfade_law", "")) == "correlation_compensated"
		var stream := SeamlessVehicleLoop.load_pcm(sample_path, true, {}, {}, not is_corr_closed)
		if stream == null:
			push_warning("PhaseLockedEngineBank missing PCM stream: " + sample_path)
			continue

		var sample_rate := int(entry.get("sample_rate", stream.mix_rate))
		var cycles := int(entry.get("cycles_in_loop", 1))
		var loop_len := int(entry.get("loop_length_samples", stream.loop_end))
		var native_rpm := float(entry.get("native_rpm", entry.get("nominal_rpm", 2300.0)))
		if cycles > 0 and loop_len > 0 and sample_rate > 0:
			native_rpm = float(cycles) * 120.0 * float(sample_rate) / float(loop_len)

		var is_exhaust := bus_name == "exhaust"
		var player := AudioStreamPlayer3D.new()
		player.stream = stream
		player.position = exhaust_position if is_exhaust else engine_position
		var routing_key := str(entry.get("key", rel_file.get_basename()))
		routing.route(player, routing_key, false)
		if is_exhaust and exhaust_lpf != null:
			var bus_idx := AudioServer.get_bus_index(player.bus)
			if bus_idx >= 0:
				var has_lpf := false
				for fx_idx in AudioServer.get_bus_effect_count(bus_idx):
					if AudioServer.get_bus_effect(bus_idx, fx_idx) == exhaust_lpf:
						has_lpf = true
						break
				if not has_lpf:
					AudioServer.add_bus_effect(bus_idx, exhaust_lpf)
		player.volume_linear = 0.0
		player.unit_size = 6.0 if is_exhaust else 4.5
		player.max_distance = 1030.0 if is_exhaust else 400.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		owner.add_child(player)

		var voice = sample_voice_class.new()
		voice.player = player
		voice.mode = load_state
		voice.reference_rpm = native_rpm
		voice.lower_rpm = 0.0
		voice.upper_rpm = redline_rpm * 1.2
		voice.is_exhaust = is_exhaust
		voice.level_gain = 1.0
		voice.base_gain = 1.0
		voice.acceleration_gain = 0.0
		voice.bus_name = bus_name
		voice.rpm_zone = rpm_zone
		voice.load_state = load_state
		voice.cycles_in_loop = maxi(cycles, 1)
		voice.loop_length_samples = maxi(loop_len, 1)
		voice.sample_rate = maxi(sample_rate, 1)
		voice.duration_s = float(voice.loop_length_samples) / float(voice.sample_rate)

		var tmpl := _extract_cycle_template(stream, voice.cycles_in_loop, voice.loop_length_samples)
		if is_exhaust:
			exhaust_slots[slot_idx] = voice
			exhaust_templates[slot_idx] = tmpl
			exhaust_voices.append(voice)
		else:
			mechanical_slots[slot_idx] = voice
			mechanical_templates[slot_idx] = tmpl
			engine_voices.append(voice)

	has_partial_slots = (
		exhaust_slots[1] != null
		or exhaust_slots[4] != null
		or exhaust_slots[7] != null
		or mechanical_slots[1] != null
		or mechanical_slots[4] != null
		or mechanical_slots[7] != null
	)
	if not has_partial_slots:
		load_weights_smoothed = [0.0, 1.0, 0.0]
		_compute_seven_wot_trims(exhaust_slots, SEVEN_WOT_TARGETS_EXHAUST, exhaust_slot_trims)
		_compute_seven_wot_trims(mechanical_slots, SEVEN_WOT_TARGETS_MECHANICAL, mechanical_slot_trims)

	exhaust_corr = _build_correlation_matrix(exhaust_templates)
	mechanical_corr = _build_correlation_matrix(mechanical_templates)

	# Start all loop players together at t=0 (crank phase 0 deg mod 720).
	for voice in exhaust_voices:
		voice.player.play(0.0)
	for voice in engine_voices:
		voice.player.play(0.0)

	return not exhaust_voices.is_empty() or not engine_voices.is_empty()


func update(
	acoustic: Dictionary,
	rpm: float,
	delta: float,
	view_engine_gain: float,
	view_exhaust_gain: float,
	exhaust_crackle_s: float,
	exhaust_cfg: Dictionary,
	owner: Node3D,
) -> void:
	var dt := maxf(delta, 0.0001)
	var throttle := clampf(float(acoustic.get("throttle", 0.0)), 0.0, 1.0)
	var load_mag := clampf(float(acoustic.get("load", 0.0)), 0.0, 1.0)
	var norm_torque := clampf(float(acoustic.get("normalized_torque", load_mag if throttle >= 0.08 else -load_mag)), -1.0, 1.0)
	var clutch_engagement := clampf(float(acoustic.get("clutch_engagement", 0.0 if bool(acoustic.get("clutch_open", false)) else 1.0)), 0.0, 1.0)
	var rpm_norm := clampf(rpm / maxf(redline_rpm, 1000.0), 0.0, 1.2)

	# Schmitt hysteresis around zero signed torque to avoid overrun flip-flop chatter.
	if is_overrun:
		if norm_torque > 0.02 or throttle > 0.10 or clutch_engagement < 0.15 or rpm <= idle_rpm * 1.08:
			is_overrun = false
	elif clutch_engagement >= 0.25 and throttle < 0.05 and norm_torque < -0.015 and rpm > idle_rpm * 1.15:
		is_overrun = true

	var target_load := _compute_target_load_weights(throttle, load_mag, norm_torque, clutch_engagement)
	var load_alpha := 1.0 - exp(-22.0 * dt)
	var lw_sum := 0.0
	for k in 3:
		load_weights_smoothed[k] = lerpf(load_weights_smoothed[k], target_load[k], load_alpha)
		lw_sum += load_weights_smoothed[k]
	lw_sum = maxf(lw_sum, 0.00001)
	var load_w: Array[float] = [
		load_weights_smoothed[0] / lw_sum,
		load_weights_smoothed[1] / lw_sum,
		load_weights_smoothed[2] / lw_sum,
	]

	var target_slots := _compute_2d_slot_weights(rpm, load_w)
	var slot_alpha := 1.0 - exp(-26.0 * dt)
	for i in SLOT_ORDER.size():
		slot_weights_smoothed[i] = lerpf(slot_weights_smoothed[i], target_slots[i], slot_alpha)

	var eff_drive := clampf(0.35 * throttle + 0.65 * maxf(norm_torque, 0.0), 0.0, 1.0)
	if exhaust_lpf != null:
		exhaust_lpf.cutoff_hz = 1400.0 + 12600.0 * pow(eff_drive, 1.4)

	var exhaust_target_bus := 0.52 + 0.44 * eff_drive
	if not bool(exhaust_cfg.get("enabled", true)):
		exhaust_target_bus = 0.0
	elif exhaust_crackle_s > 0.0:
		exhaust_target_bus *= 1.0 + float(exhaust_cfg.get("crackle_gain", 0.08)) * (exhaust_crackle_s / 0.12)

	var mech_drive := maxf(throttle * 0.75, maxf(norm_torque, 0.0) * 0.55)
	var mech_target_bus := 0.50 + 0.25 * mech_drive

	var gain_alpha := 1.0 - exp(-18.0 * dt)
	smoothed_exhaust_bus_gain = lerpf(smoothed_exhaust_bus_gain, exhaust_target_bus, gain_alpha)
	smoothed_mechanical_bus_gain = lerpf(smoothed_mechanical_bus_gain, mech_target_bus, gain_alpha)

	var exhaust_adj := _correlation_normalized_weights(slot_weights_smoothed, exhaust_corr)
	var mech_adj := _correlation_normalized_weights(slot_weights_smoothed, mechanical_corr)

	var master_cycle_frac := _find_lead_cycle_fraction(exhaust_slots, slot_weights_smoothed)
	if master_cycle_frac < 0.0:
		master_cycle_frac = _find_lead_cycle_fraction(mechanical_slots, slot_weights_smoothed)

	_apply_bus_voices(
		exhaust_slots,
		exhaust_slot_trims,
		slot_weights_smoothed,
		exhaust_adj,
		rpm,
		smoothed_exhaust_bus_gain * (view_exhaust_gain / 0.8),
		master_cycle_frac,
		owner,
	)
	_apply_bus_voices(
		mechanical_slots,
		mechanical_slot_trims,
		slot_weights_smoothed,
		mech_adj,
		rpm,
		smoothed_mechanical_bus_gain * (view_engine_gain / 0.6),
		master_cycle_frac,
		owner,
	)


func _compute_target_load_weights(
	throttle: float,
	load_mag: float,
	norm_torque: float,
	clutch_engagement: float,
) -> Array[float]:
	if not has_partial_slots:
		if is_overrun:
			var overrun_depth := _smoothstep01((-norm_torque - 0.008) / 0.06)
			return [0.0, 1.0 - overrun_depth, overrun_depth]
		var eff_drive := clampf(0.35 * throttle + 0.65 * maxf(norm_torque, 0.0), 0.0, 1.0)
		var high_w := clampf(0.25 + 0.75 * eff_drive, 0.0, 1.0)
		return [0.0, high_w, 1.0 - high_w]
	if is_overrun:
		var overrun_depth := _smoothstep01((-norm_torque - 0.005) / 0.045)
		return [1.0 - overrun_depth, 0.0, overrun_depth]
	var drive_metric := throttle * 0.65 if clutch_engagement < 0.25 else maxf(0.65 * load_mag + 0.35 * maxf(norm_torque, 0.0), throttle)
	var high_w := _smoothstep01((drive_metric - 0.32) / 0.48)
	return [1.0 - high_w, high_w, 0.0]


func _compute_2d_slot_weights(rpm: float, load_w: Array[float]) -> Array[float]:
	var idle_start := idle_rpm * 1.05
	var idle_end := maxf(minf(idle_rpm + 0.90 * (low_rpm - idle_rpm), low_rpm * 0.96), idle_start + 80.0)
	var active_frac := _smoothstep01((rpm - idle_start) / (idle_end - idle_start))
	var idle_w := 1.0 - active_frac

	var low_z := 0.0
	var mid_z := 0.0
	var high_z := 0.0
	if rpm <= low_rpm:
		low_z = 1.0
	elif rpm <= mid_rpm:
		var u := _smoothstep01((rpm - low_rpm) / maxf(mid_rpm - low_rpm, 1.0))
		low_z = 1.0 - u
		mid_z = u
	elif rpm <= high_rpm:
		var u2 := _smoothstep01((rpm - mid_rpm) / maxf(high_rpm - mid_rpm, 1.0))
		mid_z = 1.0 - u2
		high_z = u2
	else:
		high_z = 1.0

	var low_band := active_frac * low_z
	var mid_band := active_frac * mid_z
	var high_band := active_frac * high_z
	return [
		idle_w,
		low_band * load_w[0],
		low_band * load_w[1],
		low_band * load_w[2],
		mid_band * load_w[0],
		mid_band * load_w[1],
		mid_band * load_w[2],
		high_band * load_w[0],
		high_band * load_w[1],
		high_band * load_w[2],
	]


func _apply_bus_voices(
	slots: Array,
	slot_trims: Array[float],
	raw_weights: Array[float],
	adj_weights: Array[float],
	rpm: float,
	bus_gain: float,
	master_cycle_frac: float,
	owner: Node3D,
) -> void:
	for i in slots.size():
		var voice = slots[i]
		if voice == null:
			continue
		var w := adj_weights[i]
		voice.blend_weight = raw_weights[i]
		voice.layer_level = bus_gain
		var player: AudioStreamPlayer3D = voice.player
		player.pitch_scale = clampf(rpm / maxf(float(voice.reference_rpm), 1.0), 0.20, 3.5)
		var dist_comp: float = owner.call("camera_distance_compensation", player)
		player.volume_linear = w * slot_trims[i] * bus_gain * dist_comp

		var dur_s := float(voice.duration_s)
		if master_cycle_frac >= 0.0 and w > 0.001 and dur_s > 0.0:
			var pos_s: float = player.get_playback_position()
			var cycles_f := float(voice.cycles_in_loop)
			var local_cycle_frac := fposmod((pos_s / dur_s) * cycles_f, 1.0)
			var diff := absf(local_cycle_frac - master_cycle_frac)
			diff = minf(diff, 1.0 - diff)
			if diff > PHASE_DRIFT_RESYNC_CYCLES:
				var cycle_dur_s: float = dur_s / cycles_f
				var current_cycle_idx := floorf(clampf(pos_s / cycle_dur_s, 0.0, maxf(cycles_f - 1.0, 0.0)))
				var target_s: float = (current_cycle_idx + master_cycle_frac) * cycle_dur_s
				if target_s >= dur_s:
					target_s = fposmod(target_s, dur_s)
				player.seek(target_s)


func _find_lead_cycle_fraction(slots: Array, weights: Array[float]) -> float:
	var best_idx := -1
	var best_w := -1.0
	for i in slots.size():
		if slots[i] != null and weights[i] > best_w and slots[i].player.playing:
			best_w = weights[i]
			best_idx = i
	if best_idx < 0:
		return -1.0
	var lead = slots[best_idx]
	if lead.duration_s <= 0.0:
		return -1.0
	return fposmod((lead.player.get_playback_position() / lead.duration_s) * float(lead.cycles_in_loop), 1.0)


func _correlation_normalized_weights(weights: Array[float], corr_matrix: Array) -> Array[float]:
	var n := weights.size()
	var energy := 0.0
	for i in n:
		var wi := weights[i]
		if wi <= 0.00001:
			continue
		energy += wi * wi
		var row: PackedFloat32Array = corr_matrix[i]
		for j in range(i + 1, n):
			var wj := weights[j]
			if wj <= 0.00001:
				continue
			energy += 2.0 * wi * wj * row[j]
	var norm := pow(maxf(energy, 0.000001), -0.25)
	var out: Array[float] = []
	out.resize(n)
	for i in n:
		out[i] = weights[i] * norm
	return out


func _extract_cycle_template(stream: AudioStreamWAV, cycles: int, loop_len: int) -> PackedFloat32Array:
	var tmpl := PackedFloat32Array()
	tmpl.resize(CORR_TEMPLATE_LEN)
	var bytes := stream.data
	if bytes.is_empty() or cycles <= 0 or loop_len <= 0:
		return tmpl
	var total_frames := mini(loop_len, int(bytes.size() / 2))
	var cycle_frames := maxf(float(total_frames) / float(cycles), 1.0)
	var energy := 0.0
	for k in CORR_TEMPLATE_LEN:
		var idx := clampi(int(float(k) * cycle_frames / float(CORR_TEMPLATE_LEN)), 0, total_frames - 1)
		var v := float(bytes.decode_s16(idx * 2)) / 32768.0
		tmpl[k] = v
		energy += v * v
	var rms := sqrt(energy / float(CORR_TEMPLATE_LEN))
	if rms > 0.00001:
		for k in CORR_TEMPLATE_LEN:
			tmpl[k] /= rms
	return tmpl


func _build_correlation_matrix(templates: Array[PackedFloat32Array]) -> Array:
	var n := templates.size()
	var mat: Array = []
	mat.resize(n)
	for i in n:
		var row := PackedFloat32Array()
		row.resize(n)
		row[i] = 1.0
		mat[i] = row
	for i in n:
		if templates[i].is_empty():
			continue
		for j in range(i + 1, n):
			if templates[j].is_empty():
				continue
			var dot := 0.0
			for k in CORR_TEMPLATE_LEN:
				dot += templates[i][k] * templates[j][k]
			var r := clampf(dot / float(CORR_TEMPLATE_LEN), 0.0, 0.98)
			mat[i][j] = r
			mat[j][i] = r
	return mat


static func _compute_seven_wot_trims(slots: Array, targets: Array, trims_out: Array[float]) -> void:
	for i in mini(slots.size(), targets.size()):
		var voice = slots[i]
		if voice == null:
			continue
		var player: AudioStreamPlayer3D = voice.player
		var stream := player.stream as AudioStreamWAV
		if stream == null:
			continue
		var bytes := stream.data
		var total_frames := mini(int(voice.loop_length_samples), int(bytes.size() / 2))
		if total_frames <= 0:
			continue
		var sum_sq := 0.0
		var peak := 0.00001
		var count := 0
		var step := 2
		for frame_idx in range(0, total_frames, step):
			var v := float(bytes.decode_s16(frame_idx * 2)) / 32768.0
			sum_sq += v * v
			peak = maxf(peak, absf(v))
			count += 1
		var rms := sqrt(sum_sq / float(maxi(count, 1)))
		if rms > 0.00001:
			var safe_cap := 0.89 / peak
			trims_out[i] = clampf(float(targets[i]) / rms, 0.05, minf(safe_cap, 6.0))


static func _smoothstep01(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
