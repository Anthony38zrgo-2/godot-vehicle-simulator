class_name VehiclePowertrainModel
extends RefCounted

const GEVP_GEAR_INERTIA := 0.02

var idle_rpm: float = 900.0
var maximum_rpm: float = 7200.0
var torque_curve_reference_rpm: float = 0.0
var peak_torque_nm: float = 0.0
var torque_curve: Array[Vector2] = []
var variable_drag_ratio: float = 0.0
var constant_brake_ratio: float = 0.0
var gear_ratios: Array[float] = []
var reverse_ratio: float = 0.0
var final_drive_ratio: float = 1.0
var final_drive_gravel: float = 0.0
var final_drive_tarmac: float = 0.0
var final_drive_preset: String = ""

# P0: Saab freewheel (one-way clutch on primary shaft).
# Decisión única por subpaso con histéresis (plan POWERTRAIN_CORRECTION_PLAN §1):
# - freewheel_throttle guarda el acelerador del CONDUCTOR usado en la decisión;
#   el solver y la integración consumen esa misma decisión (sin inferir
#   acelerador a partir del signo del par).
# - Desacopla con delta > disengage; reacopla con delta <= reengage o con
#   reapertura de gas. El margen configurado se conserva como umbral de
#   reenganche; la separación se fija en FREEWHEEL_HYSTERESIS_RAD_S
#   (barrido de velocidad en tests/rally/powertrain_correction_contract.gd).
var freewheel_enabled: bool = false
var freewheel_idle_rpm: float = 1000.0
var freewheel_reengage_margin_rad_s: float = 1.5
var freewheel_disengage_margin_rad_s: float = 2.5
var freewheel_active: bool = false
var freewheel_throttle: float = 0.0
var freewheel_delta_rad_s: float = 0.0
const FREEWHEEL_HYSTERESIS_RAD_S := 1.0
const FREEWHEEL_DISENGAGE_THROTTLE := 0.1
const FREEWHEEL_REENGAGE_THROTTLE := 0.2
var engine_inertia_kg_m2: float = 0.1
var clutch_max_torque_nm: float = 0.0
var clutch_max_torque_ratio: float = 1.35
var clutch_out_rpm_offset: float = 300.0
var idle_disengagement_hysteresis_rpm: float = 150.0
var torque_attack_rate_nm_s: float = 0.0
var engine_attack_limited_torque_nm: float = 0.0
# Par solicitado antes del límite de ataque (plan §2). engine_torque_nm es el
# par entregado (limitado + ralentí − rozamiento); ambos comparten los mismos
# términos para que estimación e integración coincidan a límite estabilizado.
var engine_requested_torque_nm: float = 0.0
var throttle_response_enabled: bool = false
var throttle_tau_up_s: float = 0.0
var throttle_tau_down_s: float = 0.0
var throttle_rpm_reference: float = 3000.0
var throttle_rpm_scale_min: float = 0.6
var throttle_rpm_scale_max: float = 1.8
var throttle_response_attack_rate_nm_s: float = 0.0
var manifold_fill: float = 0.0
var front_wheel_mass_kg: float = 20.0
var front_wheel_radius_m: float = 0.28
var rear_wheel_mass_kg: float = 20.0
var rear_wheel_radius_m: float = 0.28
var front_torque_split: float = 0.0
var clutch_engagement: float = 0.0
var clutch_torque_nm: float = 0.0
var input_shaft_omega_rad_s: float = 0.0
var gearbox_input_inertia_kg_m2: float = GEVP_GEAR_INERTIA
var clutch_slip_power_w: float = 0.0
var clutch_bite_enabled: bool = false
var clutch_bite_start: float = 0.0
var clutch_bite_full: float = 1.0
var clutch_bite_exponent: float = 1.0
var clutch_two_phase_enabled: bool = false
var clutch_takeup_seconds: float = 0.0
var clutch_friction_zone_seconds: float = 0.12
var clutch_slip_time_gain: float = 0.0
var clutch_mu_static_ratio: float = 1.0
var clutch_static_slip_rad_s: float = 3.0
var clutch_bite: float = 0.0
var clutch_slip_rad_s: float = 0.0
var clutch_damper_enabled: bool = false
var clutch_damper_disc_inertia_kg_m2: float = 0.006
var clutch_damper_idle_stiffness_nm_per_rad: float = 220.0
var clutch_damper_idle_travel_deg: float = 2.5
var clutch_damper_main_stiffness_nm_per_rad: float = 1300.0
var clutch_damper_travel_deg: float = 10.0
var clutch_damper_stop_stiffness_factor: float = 15.0
var clutch_damper_hysteresis_nm: float = 8.0
var clutch_damper_viscous_nms_per_rad: float = 2.0
var clutch_damper_twist_rad: float = 0.0
var clutch_damper_twist_deg: float = 0.0
var clutch_damper_torque_nm: float = 0.0
var clutch_damper_at_stop: bool = false
var differential_preload_nm: float = 0.0
var differential_power_ratio: float = 0.0
var differential_coast_ratio: float = 0.25
var differential_power_ramp_angle_deg: float = 45.0
var differential_coast_ramp_angle_deg: float = 60.0
var differential_clutches: float = 4.0
# v1 presets: type discreto, ganancia de rampa explícita y telemetría LSD.
# differential_clutches = active_friction_surfaces (simulation_estimate_v1).
# physical_disc_count es solo informativo y no entra en la ecuación.
var differential_type: String = "clutch_lsd"
var differential_ramp_gain: float = 0.16
var differential_preset_id: String = ""
var differential_lock_stiffness_nm_per_rad: float = 0.0
var differential_lock_damping_ratio: float = 0.7
var differential_pressure_tau_s: float = 0.0
var differential_release_tau_s: float = 0.0
var differential_blend_band_fraction: float = 0.0
var differential_blend_band_nm: float = 0.0
var differential_static_friction_factor: float = 1.0
var differential_slip_reference_rad_s: float = 2.0
var base_differential_power_ratio: float = 0.0
var base_differential_coast_ratio: float = 0.25
var last_diff_speed_rad_s: float = 0.0
var last_lsd_capacity_nm: float = 0.0
var last_lsd_torque_nm: float = 0.0
var last_lsd_saturation: float = 0.0
var last_lsd_filtered_torque_nm: float = 0.0
var last_lsd_blend: float = 0.5
var last_lsd_lock_twist_rad: float = 0.0
var differential_slip_transition_threshold_rad_s: float = 4.0
# Diferencial por eje (plan §4). En FWD/RWD puros el bloque histórico
# `differential` se interpreta como el diferencial del eje motriz y el otro
# eje queda abierto. Para AWD (0 < front_torque_split < 1) cada eje se define
# explícitamente con `differential_front` / `differential_rear`.
# Tipos: clutch_lsd y adjustable_friction_lsd usan el solver de fricción;
# open no genera impulso de bloqueo; spool se rechaza en validación.
const DIFFERENTIAL_FRICTION_TYPES: Array[String] = ["clutch_lsd", "adjustable_friction_lsd"]
const DIFFERENTIAL_DRIVE_EPS := 0.000001
var front_differential_type: String = "open"
var rear_differential_type: String = "clutch_lsd"
var front_differential_preload_nm: float = 0.0
var rear_differential_preload_nm: float = 0.0
var front_differential_power_ratio: float = 0.0
var front_differential_coast_ratio: float = 0.25
var rear_differential_power_ratio: float = 0.0
var rear_differential_coast_ratio: float = 0.25
var front_differential_power_ramp_angle_deg: float = 45.0
var front_differential_coast_ramp_angle_deg: float = 60.0
var rear_differential_power_ramp_angle_deg: float = 45.0
var rear_differential_coast_ramp_angle_deg: float = 60.0
var front_differential_clutches: float = 4.0
var rear_differential_clutches: float = 4.0
var front_differential_ramp_gain: float = 0.16
var rear_differential_ramp_gain: float = 0.16
var front_differential_preset_id: String = ""
var rear_differential_preset_id: String = ""
var front_differential_lock_stiffness_nm_per_rad: float = 0.0
var rear_differential_lock_stiffness_nm_per_rad: float = 0.0
var front_differential_lock_damping_ratio: float = 0.7
var rear_differential_lock_damping_ratio: float = 0.7
var front_differential_pressure_tau_s: float = 0.0
var rear_differential_pressure_tau_s: float = 0.0
var front_differential_release_tau_s: float = 0.0
var rear_differential_release_tau_s: float = 0.0
var front_differential_blend_band_fraction: float = 0.0
var rear_differential_blend_band_fraction: float = 0.0
var front_differential_blend_band_nm: float = 0.0
var rear_differential_blend_band_nm: float = 0.0
var front_differential_static_friction_factor: float = 1.0
var rear_differential_static_friction_factor: float = 1.0
var front_differential_slip_reference_rad_s: float = 2.0
var rear_differential_slip_reference_rad_s: float = 2.0
var front_lsd_lock_twist_rad: float = 0.0
var rear_lsd_lock_twist_rad: float = 0.0
var front_lsd_filtered_torque_nm: float = 0.0
var rear_lsd_filtered_torque_nm: float = 0.0
var front_lsd_blend: float = 0.5
var rear_lsd_blend: float = 0.5
# Telemetría por eje. Los last_* históricos reflejan el eje seleccionado
# (delantero si front_torque_split >= 1, trasero en otro caso) por
# compatibilidad con consumidores existentes.
var last_front_diff_speed_rad_s: float = 0.0
var last_front_lsd_capacity_nm: float = 0.0
var last_front_lsd_torque_nm: float = 0.0
var last_front_lsd_saturation: float = 0.0
var last_front_lsd_filtered_torque_nm: float = 0.0
var last_front_lsd_blend: float = 0.5
var last_front_lsd_lock_twist_rad: float = 0.0
var last_rear_diff_speed_rad_s: float = 0.0
var last_rear_lsd_capacity_nm: float = 0.0
var last_rear_lsd_torque_nm: float = 0.0
var last_rear_lsd_saturation: float = 0.0
var last_rear_lsd_filtered_torque_nm: float = 0.0
var last_rear_lsd_blend: float = 0.5
var last_rear_lsd_lock_twist_rad: float = 0.0
var current_gear: int = 0
var engine_rpm: float = 0.0
var engine_torque_nm: float = 0.0
var maximum_forward_gear: int = 0
const MAX_TRANSMISSION_SHIFT_DELAY_SECONDS := 1.0

var transmission_damage: float = 0.0
var _shift_damage_delay_seconds: float = 0.0
var mechanical_damage_config: Dictionary = {}
var missgear_active: bool = false
var missgear_intensity: float = 0.0
var missgear_event_pending: bool = false
var last_overrev_ratio: float = 0.0
var _gearbox_popout_cooldown_s: float = 0.0
var shift_time_seconds: float = 0.0
var gear_inertia_shift_seconds: float = 0.0
var shift_remaining_seconds: float = 0.0
var automatic_transmission: bool = false
var pending_gear: int = 0
var shift_phase: String = "idle"
var shift_phase_seconds: float = 0.0
var clutch_release_seconds: float = 0.04
var clutch_reengage_seconds: float = 0.12
var synchronizer_capacity_nm: float = 25.0
var synchronizer_tolerance_rad_s: float = 0.1
var downshift_rev_matching_enabled: bool = false
var downshift_blip_torque_fraction: float = 0.8
var downshift_target_rpm_fraction: float = 0.92
var downshift_blip_response_seconds: float = 0.04
var downshift_blip_tolerance_rpm: float = 25.0
var revmatch_downshift: bool = false
var autoblip_active: bool = false
var autoblip_target_rpm: float = 0.0
var autoblip_throttle: float = 0.0
var driveline_compliance_enabled: bool = false
var output_shaft_inertia_kg_m2: float = 0.2
var output_shaft_omega_rad_s: float = 0.0
var torsional_stiffness_nm_per_rad: float = 8000.0
var torsional_damping_nms_per_rad: float = 120.0
var driveline_backlash_rad: float = 0.0
var driveline_backlash_damping_ratio: float = 0.04
var driveline_contact_soft_zone_rad: float = 0.0
var driveline_contact_restitution: float = 0.3
var driveline_end_stop_margin: float = 1.5
var driveline_end_stop_stiffness_factor: float = 8.0
var driveline_twist_rad: float = 0.0
var driveline_torque_nm: float = 0.0
var driveline_energy_j: float = 0.0
var driveline_dissipation_w: float = 0.0
var driveline_in_backlash: bool = false
var driveline_backlash_flank: int = 0
var driveline_backlash_impact_rad_s: float = 0.0
const MAX_CHASSIS_REACTION_NM := 1200.0
var chassis_reaction_enabled: bool = false
var chassis_reaction_orientation: String = "longitudinal"
var chassis_reaction_crank_sign: float = 1.0
var chassis_reaction_scale: float = 1.0
var chassis_reaction_mount_tau_s: float = 0.018
var chassis_reaction_driveshaft_roll_fraction: float = 0.0
var chassis_reaction_mount_model: String = "first_order"
var chassis_reaction_roll_inertia_kg_m2: float = 3.5
var chassis_reaction_pitch_inertia_kg_m2: float = 5.0
var chassis_reaction_mount_frequency_hz: float = 10.0
var chassis_reaction_mount_damping_ratio: float = 0.22
var chassis_reaction_snubber_angle_deg: float = 6.0
var chassis_reaction_snubber_stiffness_factor: float = 6.0
var chassis_reaction_transaxle_pitch_fraction: float = 0.0
var engine_mount_roll_rad: float = 0.0
var engine_mount_roll_omega_rad_s: float = 0.0
var engine_mount_pitch_rad: float = 0.0
var engine_mount_pitch_omega_rad_s: float = 0.0
var engine_roll_deg: float = 0.0
var engine_pitch_deg: float = 0.0
var chassis_reaction_torque_local_nm: Vector3 = Vector3.ZERO
var _reaction_prev_engine_omega: float = 0.0
var _reaction_prev_input_omega: float = 0.0
var _reaction_initialized: bool = false
var _mount_prev_chassis_omega_local: Vector3 = Vector3.ZERO
var _mount_chassis_omega_initialized: bool = false
# Backend nativo en Rust (rally_native::RustPowertrainSolver) con fallback automático a GDScript.
var use_rust_backend: bool = true
var _rust_solver: RefCounted = null
var _rust_cfg_dirty: bool = true
var _rust_cfg_sig: float = -1.0
var _rust_cfg50: PackedFloat64Array = PackedFloat64Array()
var _rust_axle32: PackedFloat64Array = PackedFloat64Array()
var _rust_inp53: PackedFloat64Array = PackedFloat64Array()
var _rust_brake_work: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _rust_weights: Array[float] = [0.0, 0.0, 0.0, 0.0]


func invalidate_rust_config() -> void:
	_rust_cfg_dirty = true


func _ensure_rust_solver() -> RefCounted:
	if not use_rust_backend:
		_rust_solver = null
		return null
	if _rust_solver == null and ClassDB.class_exists(&"RustPowertrainSolver"):
		_rust_solver = ClassDB.instantiate(&"RustPowertrainSolver") as RefCounted
		_rust_cfg_dirty = true
		if _rust_cfg50.size() != 50:
			_rust_cfg50.resize(50)
		if _rust_axle32.size() != 32:
			_rust_axle32.resize(32)
		if _rust_inp53.size() != 53:
			_rust_inp53.resize(53)
	return _rust_solver


func _sync_rust_config() -> void:
	if _rust_solver == null:
		return
	var flags := 0
	if driveline_compliance_enabled:
		flags |= (1 << 0)
	if clutch_bite_enabled:
		flags |= (1 << 1)
	if clutch_damper_enabled:
		flags |= (1 << 2)
	if chassis_reaction_enabled:
		flags |= (1 << 3)
	if chassis_reaction_mount_model == "second_order":
		flags |= (1 << 4)
	if chassis_reaction_orientation == "transverse":
		flags |= (1 << 5)
	if freewheel_enabled:
		flags |= (1 << 6)
	var sig := float(flags) * 1.0e6 + final_drive_ratio * 131.0 + front_torque_split * 97.0 + front_differential_preload_nm * 0.13 + rear_differential_preload_nm * 0.17 + torsional_stiffness_nm_per_rad * 0.001 + driveline_backlash_rad * 1000.0
	if not _rust_cfg_dirty and absf(sig - _rust_cfg_sig) <= 1.0e-9:
		return
	_rust_cfg50[0] = engine_inertia_kg_m2
	_rust_cfg50[1] = gearbox_input_inertia_kg_m2
	_rust_cfg50[2] = clutch_damper_disc_inertia_kg_m2
	_rust_cfg50[3] = output_shaft_inertia_kg_m2
	_rust_cfg50[4] = front_torque_split
	_rust_cfg50[5] = final_drive_ratio
	_rust_cfg50[6] = peak_torque_nm
	_rust_cfg50[7] = clutch_max_torque_nm
	_rust_cfg50[8] = clutch_max_torque_ratio
	_rust_cfg50[9] = clutch_bite_start
	_rust_cfg50[10] = clutch_bite_full
	_rust_cfg50[11] = clutch_bite_exponent
	_rust_cfg50[12] = clutch_mu_static_ratio
	_rust_cfg50[13] = clutch_static_slip_rad_s
	_rust_cfg50[14] = clutch_damper_idle_stiffness_nm_per_rad
	_rust_cfg50[15] = clutch_damper_idle_travel_deg
	_rust_cfg50[16] = clutch_damper_main_stiffness_nm_per_rad
	_rust_cfg50[17] = clutch_damper_travel_deg
	_rust_cfg50[18] = clutch_damper_stop_stiffness_factor
	_rust_cfg50[19] = clutch_damper_hysteresis_nm
	_rust_cfg50[20] = clutch_damper_viscous_nms_per_rad
	_rust_cfg50[21] = torsional_stiffness_nm_per_rad
	_rust_cfg50[22] = torsional_damping_nms_per_rad
	_rust_cfg50[23] = driveline_backlash_rad
	_rust_cfg50[24] = driveline_backlash_damping_ratio
	_rust_cfg50[25] = driveline_contact_soft_zone_rad
	_rust_cfg50[26] = driveline_contact_restitution
	_rust_cfg50[27] = driveline_end_stop_margin
	_rust_cfg50[28] = driveline_end_stop_stiffness_factor
	_rust_cfg50[29] = synchronizer_capacity_nm
	_rust_cfg50[30] = synchronizer_tolerance_rad_s
	_rust_cfg50[31] = shift_time_seconds
	_rust_cfg50[32] = gear_inertia_shift_seconds
	_rust_cfg50[33] = differential_slip_transition_threshold_rad_s
	_rust_cfg50[34] = chassis_reaction_scale
	_rust_cfg50[35] = chassis_reaction_crank_sign
	_rust_cfg50[36] = chassis_reaction_driveshaft_roll_fraction
	_rust_cfg50[37] = chassis_reaction_transaxle_pitch_fraction
	_rust_cfg50[38] = chassis_reaction_mount_tau_s
	_rust_cfg50[39] = chassis_reaction_mount_frequency_hz
	_rust_cfg50[40] = chassis_reaction_mount_damping_ratio
	_rust_cfg50[41] = chassis_reaction_roll_inertia_kg_m2
	_rust_cfg50[42] = chassis_reaction_pitch_inertia_kg_m2
	_rust_cfg50[43] = chassis_reaction_snubber_angle_deg
	_rust_cfg50[44] = chassis_reaction_snubber_stiffness_factor
	_rust_cfg50[45] = absf(gear_ratios[0]) if not gear_ratios.is_empty() else 1.0
	var mech_cfg := mechanical_damage_config
	_rust_cfg50[46] = clampf(float(mech_cfg.get("minimum_clutch_capacity_factor", 0.70)), 0.1, 1.0)
	_rust_cfg50[47] = clampf(float(mech_cfg.get("minimum_synchronizer_factor", 0.35)), 0.05, 1.0)
	_rust_cfg50[48] = maxf(float(mech_cfg.get("maximum_damage_backlash_rad", 0.05)), 0.0)
	_rust_cfg50[49] = MAX_CHASSIS_REACTION_NM

	_rust_axle32[0] = 1.0 if (front_differential_type in DIFFERENTIAL_FRICTION_TYPES) else 0.0
	_rust_axle32[1] = front_differential_preload_nm
	_rust_axle32[2] = front_differential_power_ratio
	_rust_axle32[3] = front_differential_coast_ratio
	_rust_axle32[4] = front_differential_power_ramp_angle_deg
	_rust_axle32[5] = front_differential_coast_ramp_angle_deg
	_rust_axle32[6] = front_differential_clutches
	_rust_axle32[7] = front_differential_ramp_gain
	_rust_axle32[8] = front_differential_lock_stiffness_nm_per_rad
	_rust_axle32[9] = front_differential_lock_damping_ratio
	_rust_axle32[10] = front_differential_pressure_tau_s
	_rust_axle32[11] = front_differential_release_tau_s
	_rust_axle32[12] = front_differential_blend_band_fraction
	_rust_axle32[13] = front_differential_blend_band_nm
	_rust_axle32[14] = front_differential_static_friction_factor
	_rust_axle32[15] = front_differential_slip_reference_rad_s

	_rust_axle32[16] = 1.0 if (rear_differential_type in DIFFERENTIAL_FRICTION_TYPES) else 0.0
	_rust_axle32[17] = rear_differential_preload_nm
	_rust_axle32[18] = rear_differential_power_ratio
	_rust_axle32[19] = rear_differential_coast_ratio
	_rust_axle32[20] = rear_differential_power_ramp_angle_deg
	_rust_axle32[21] = rear_differential_coast_ramp_angle_deg
	_rust_axle32[22] = rear_differential_clutches
	_rust_axle32[23] = rear_differential_ramp_gain
	_rust_axle32[24] = rear_differential_lock_stiffness_nm_per_rad
	_rust_axle32[25] = rear_differential_lock_damping_ratio
	_rust_axle32[26] = rear_differential_pressure_tau_s
	_rust_axle32[27] = rear_differential_release_tau_s
	_rust_axle32[28] = rear_differential_blend_band_fraction
	_rust_axle32[29] = rear_differential_blend_band_nm
	_rust_axle32[30] = rear_differential_static_friction_factor
	_rust_axle32[31] = rear_differential_slip_reference_rad_s

	_rust_solver.call("sync_config", _rust_cfg50, _rust_axle32, flags)
	_rust_cfg_dirty = false
	_rust_cfg_sig = sig


func configure(domains: Dictionary) -> Dictionary:
	var staged := validate_powertrain_config(domains)
	if not bool(staged.get("ok", false)):
		return {"ok": false, "error": str(staged.get("error", "invalid powertrain"))}
	var values: Dictionary = staged["values"]
	# Commit atómico: solo se copian locales ya validados. Un error anterior
	# no muta configuración ni estado (plan §3: recarga inválida conserva todo).
	transmission_damage = 0.0
	var damage_doc: Dictionary = domains.get("damage", {})
	var damage_section: Dictionary = damage_doc.get("damage", damage_doc)
	mechanical_damage_config = (damage_section.get("mechanical", {}) as Dictionary).duplicate(true)
	missgear_active = false
	missgear_intensity = 0.0
	missgear_event_pending = false
	last_overrev_ratio = 0.0
	_gearbox_popout_cooldown_s = 0.0
	idle_rpm = float(values["idle_rpm"])
	maximum_rpm = float(values["maximum_rpm"])
	torque_curve_reference_rpm = maximum_rpm
	peak_torque_nm = float(values["max_torque"])
	torque_curve.clear()
	for point in values["torque_curve"]:
		torque_curve.append(point)
	variable_drag_ratio = float(values["variable_drag_ratio"])
	constant_brake_ratio = float(values["constant_brake_ratio"])
	reverse_ratio = float(values["reverse_ratio"])
	final_drive_ratio = float(values["final_drive"])
	final_drive_gravel = float(values["final_drive_gravel"])
	final_drive_tarmac = float(values["final_drive_tarmac"])
	final_drive_preset = str(values["final_drive_preset"])
	freewheel_enabled = bool(values["freewheel_enabled"])
	freewheel_idle_rpm = float(values["freewheel_idle_rpm"])
	freewheel_reengage_margin_rad_s = float(values["freewheel_reengage_margin"])
	freewheel_disengage_margin_rad_s = float(values["freewheel_reengage_margin"]) + FREEWHEEL_HYSTERESIS_RAD_S
	freewheel_active = false
	freewheel_throttle = 0.0
	freewheel_delta_rad_s = 0.0
	engine_inertia_kg_m2 = float(values["motor_moment"])
	gearbox_input_inertia_kg_m2 = float(values["gearbox_input_inertia"])
	clutch_max_torque_ratio = float(values["max_clutch_torque_ratio"])
	clutch_max_torque_nm = peak_torque_nm * clutch_max_torque_ratio
	clutch_out_rpm_offset = float(values["clutch_out_rpm_offset"])
	idle_disengagement_hysteresis_rpm = float(values["idle_disengagement_hysteresis"])
	torque_attack_rate_nm_s = float(values["torque_attack_rate"])
	throttle_response_enabled = bool(values["throttle_response_enabled"])
	throttle_tau_up_s = float(values["throttle_tau_up_s"])
	throttle_tau_down_s = float(values["throttle_tau_down_s"])
	throttle_rpm_reference = float(values["throttle_rpm_reference"])
	throttle_rpm_scale_min = float(values["throttle_rpm_scale_min"])
	throttle_rpm_scale_max = float(values["throttle_rpm_scale_max"])
	throttle_response_attack_rate_nm_s = float(values["throttle_response_attack_rate_nm_s"])
	manifold_fill = 0.0
	front_torque_split = float(values["front_torque_split"])
	gear_inertia_shift_seconds = float(values["gear_inertia"])
	front_wheel_mass_kg = float(values["front_wheel_mass"])
	front_wheel_radius_m = float(values["front_wheel_radius"])
	rear_wheel_mass_kg = float(values["rear_wheel_mass"])
	rear_wheel_radius_m = float(values["rear_wheel_radius"])
	shift_time_seconds = float(values["shift_time"])
	clutch_release_seconds = float(values["clutch_release"])
	clutch_reengage_seconds = float(values["clutch_reengage"])
	clutch_bite_enabled = bool(values["clutch_bite_enabled"])
	clutch_bite_start = float(values["clutch_bite_start"])
	clutch_bite_full = float(values["clutch_bite_full"])
	clutch_bite_exponent = float(values["clutch_bite_exponent"])
	clutch_two_phase_enabled = bool(values["clutch_two_phase_enabled"])
	clutch_takeup_seconds = float(values["clutch_takeup_seconds"])
	clutch_friction_zone_seconds = float(values["clutch_friction_zone_seconds"])
	clutch_slip_time_gain = float(values["clutch_slip_time_gain"])
	clutch_mu_static_ratio = float(values["clutch_mu_static_ratio"])
	clutch_static_slip_rad_s = float(values["clutch_static_slip_rad_s"])
	clutch_damper_enabled = bool(values["clutch_damper_enabled"])
	clutch_damper_disc_inertia_kg_m2 = float(values["clutch_damper_disc_inertia_kg_m2"])
	clutch_damper_idle_stiffness_nm_per_rad = float(values["clutch_damper_idle_stiffness_nm_per_rad"])
	clutch_damper_idle_travel_deg = float(values["clutch_damper_idle_travel_deg"])
	clutch_damper_main_stiffness_nm_per_rad = float(values["clutch_damper_main_stiffness_nm_per_rad"])
	clutch_damper_travel_deg = float(values["clutch_damper_travel_deg"])
	clutch_damper_stop_stiffness_factor = float(values["clutch_damper_stop_stiffness_factor"])
	clutch_damper_hysteresis_nm = float(values["clutch_damper_hysteresis_nm"])
	clutch_damper_viscous_nms_per_rad = float(values["clutch_damper_viscous_nms_per_rad"])
	synchronizer_capacity_nm = float(values["synchronizer_capacity"])
	synchronizer_tolerance_rad_s = float(values["synchronizer_tolerance"])
	automatic_transmission = bool(values["automatic_transmission"])
	downshift_rev_matching_enabled = bool(values["downshift_rev_matching"])
	downshift_blip_torque_fraction = float(values["downshift_blip_fraction"])
	downshift_target_rpm_fraction = float(values["downshift_target_fraction"])
	downshift_blip_response_seconds = float(values["downshift_blip_response"])
	downshift_blip_tolerance_rpm = float(values["downshift_blip_tolerance"])
	driveline_compliance_enabled = bool(values["compliance_enabled"])
	output_shaft_inertia_kg_m2 = float(values["compliance_inertia"])
	torsional_stiffness_nm_per_rad = float(values["compliance_stiffness"])
	torsional_damping_nms_per_rad = float(values["compliance_damping"])
	driveline_backlash_rad = float(values["compliance_backlash_rad"])
	driveline_backlash_damping_ratio = float(values["compliance_backlash_damping_ratio"])
	driveline_contact_soft_zone_rad = float(values["compliance_contact_soft_zone_rad"])
	driveline_contact_restitution = float(values["compliance_contact_restitution"])
	driveline_end_stop_margin = float(values["compliance_end_stop_margin"])
	driveline_end_stop_stiffness_factor = float(values["compliance_end_stop_stiffness_factor"])
	chassis_reaction_enabled = bool(values["chassis_reaction_enabled"])
	chassis_reaction_orientation = str(values["chassis_reaction_orientation"])
	chassis_reaction_crank_sign = float(values["chassis_reaction_crank_sign"])
	chassis_reaction_scale = float(values["chassis_reaction_scale"])
	chassis_reaction_mount_tau_s = float(values["chassis_reaction_mount_tau_s"])
	chassis_reaction_driveshaft_roll_fraction = float(values["chassis_reaction_driveshaft_roll_fraction"])
	chassis_reaction_mount_model = str(values["chassis_reaction_mount_model"])
	chassis_reaction_roll_inertia_kg_m2 = float(values["chassis_reaction_roll_inertia_kg_m2"])
	chassis_reaction_pitch_inertia_kg_m2 = float(values["chassis_reaction_pitch_inertia_kg_m2"])
	chassis_reaction_mount_frequency_hz = float(values["chassis_reaction_mount_frequency_hz"])
	chassis_reaction_mount_damping_ratio = float(values["chassis_reaction_mount_damping_ratio"])
	chassis_reaction_snubber_angle_deg = float(values["chassis_reaction_snubber_angle_deg"])
	chassis_reaction_snubber_stiffness_factor = float(values["chassis_reaction_snubber_stiffness_factor"])
	chassis_reaction_transaxle_pitch_fraction = float(values["chassis_reaction_transaxle_pitch_fraction"])
	reset_compliance()
	_apply_staged_differential(values["front_differential"], "front")
	_apply_staged_differential(values["rear_differential"], "rear")
	if front_torque_split >= 1.0:
		_apply_staged_differential(values["front_differential"], "")
	else:
		_apply_staged_differential(values["rear_differential"], "")
	base_differential_power_ratio = float(values["base_power_ratio"])
	base_differential_coast_ratio = float(values["base_coast_ratio"])
	differential_slip_transition_threshold_rad_s = float(values["slip_transition_threshold"])
	gear_ratios.clear()
	for ratio in values["gear_ratios"]:
		gear_ratios.append(float(ratio))
	maximum_forward_gear = gear_ratios.size()
	engine_rpm = idle_rpm
	engine_requested_torque_nm = 0.0
	engine_attack_limited_torque_nm = 0.0
	clutch_engagement = 0.0
	clutch_torque_nm = 0.0
	input_shaft_omega_rad_s = 0.0
	last_front_diff_speed_rad_s = 0.0
	last_front_lsd_capacity_nm = 0.0
	last_front_lsd_torque_nm = 0.0
	last_front_lsd_saturation = 0.0
	last_rear_diff_speed_rad_s = 0.0
	last_rear_lsd_capacity_nm = 0.0
	last_rear_lsd_torque_nm = 0.0
	last_rear_lsd_saturation = 0.0
	last_diff_speed_rad_s = 0.0
	last_lsd_capacity_nm = 0.0
	last_lsd_torque_nm = 0.0
	last_lsd_saturation = 0.0
	reset_shift()
	print(
		"RALLY_DRIVELINE_COMPLIANCE ",
		JSON.stringify(
			{
				"enabled": driveline_compliance_enabled,
				"output_inertia_kg_m2": output_shaft_inertia_kg_m2,
				"stiffness_nm_per_rad": torsional_stiffness_nm_per_rad,
				"damping_nms_per_rad": torsional_damping_nms_per_rad,
				"backlash_rad": driveline_backlash_rad,
				"backlash_damping_ratio": driveline_backlash_damping_ratio,
				"autoblip_enabled": downshift_rev_matching_enabled,
			}
		),
	)
	return { "ok": true }


# Valida el dominio powertrain en datos locales sin mutar el modelo (plan §3).
# Devuelve {ok, values} con todos los locales listos para aplicar, o
# {ok:false, error} identificando campo e índice. Se usa desde configure()
# (carga atómica) y desde el cargador de perfiles (validación temprana).
# Exige int o float finito. Rechaza booleanos, cadenas, diccionarios, arrays
# y nulos con el campo (y el índice) en el error: float() coerciona cadenas
# y otros tipos en silencio, así que el tipo se valida antes de convertir.
static func _require_finite_number(value: Variant, field: String) -> Dictionary:
	if value is bool or not (value is int or value is float):
		return {"ok": false, "error": field + " must be a finite number, got " + _type_name(value) + "."}
	var number := float(value)
	if not is_finite(number):
		return {"ok": false, "error": field + " must be finite."}
	return {"ok": true, "value": number}


static func _type_name(value: Variant) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "bool"
	if value is int:
		return "int"
	if value is float:
		return "float"
	if value is String:
		return "string"
	if value is Array:
		return "array"
	if value is Dictionary:
		return "dictionary"
	return "object"


static func validate_powertrain_config(domains: Dictionary) -> Dictionary:
	var powertrain: Dictionary = domains.get("powertrain", { }).get("powertrain", { })
	var values := {}
	values["idle_rpm"] = float(powertrain.get("idle_rpm", 900.0))
	values["maximum_rpm"] = float(powertrain.get("max_rpm", 7200.0))
	if not powertrain.has("max_torque"):
		return {"ok": false, "error": "powertrain.max_torque is required."}
	var peak_check := _require_finite_number(powertrain.get("max_torque"), "powertrain.max_torque")
	if not bool(peak_check.get("ok", false)):
		return peak_check
	var peak := float(peak_check["value"])
	if peak <= 0.0:
		return {"ok": false, "error": "powertrain.max_torque must be explicit, finite and positive."}
	values["max_torque"] = peak
	var staged_curve: Array[Vector2] = []
	var curve_doc: Variant = powertrain.get("torque_curve", [])
	if not curve_doc is Array:
		return {"ok": false, "error": "powertrain.torque_curve must be an array of [x, y] pairs."}
	if not (curve_doc as Array).is_empty():
		var index := 0
		var last_x := -1.0
		for point in curve_doc:
			if not point is Array or (point as Array).size() < 2:
				return {"ok": false, "error": "powertrain.torque_curve[%d] must be a [x, y] pair." % index}
			var px_check := _require_finite_number(
				(point as Array)[0], "powertrain.torque_curve[%d].x" % index
			)
			if not bool(px_check.get("ok", false)):
				return px_check
			var py_check := _require_finite_number(
				(point as Array)[1], "powertrain.torque_curve[%d].y" % index
			)
			if not bool(py_check.get("ok", false)):
				return py_check
			var px := float(px_check["value"])
			var py := float(py_check["value"])
			if px < 0.0:
				return {"ok": false, "error": "powertrain.torque_curve[%d].x must be nonnegative." % index}
			if px <= last_x:
				return {"ok": false, "error": "powertrain.torque_curve[%d].x must be strictly increasing." % index}
			last_x = px
			staged_curve.append(Vector2(px, py))
			index += 1
	values["torque_curve"] = staged_curve
	values["variable_drag_ratio"] = maxf(float(powertrain.get("variable_drag_ratio", 0.0)), 0.0)
	values["constant_brake_ratio"] = maxf(float(powertrain.get("constant_brake_ratio", 0.0)), 0.0)
	if powertrain.has("reverse_ratio") and not is_finite(float(powertrain.get("reverse_ratio", 0.0))):
		return {"ok": false, "error": "powertrain.reverse_ratio must be finite."}
	values["reverse_ratio"] = -absf(float(powertrain.get("reverse_ratio", 3.317)))
	# Relación final: se conserva el valor por defecto si el campo se omite;
	# la efectiva tras resolver el preset debe ser positiva y finita.
	# Tipos estrictos: un booleano o una cadena ya no se coercionan en silencio.
	var staged_finals := {}
	for final_key in ["final_drive", "final_drive_gravel", "final_drive_tarmac"]:
		if powertrain.has(final_key):
			var final_check := _require_finite_number(
				powertrain.get(final_key), "powertrain." + final_key
			)
			if not bool(final_check.get("ok", false)):
				return final_check
			staged_finals[final_key] = float(final_check["value"])
		else:
			staged_finals[final_key] = 1.0 if final_key == "final_drive" else 0.0
	var gravel := float(staged_finals["final_drive_gravel"])
	var tarmac := float(staged_finals["final_drive_tarmac"])
	var preset := str(powertrain.get("final_drive_preset", ""))
	var effective := float(staged_finals["final_drive"])
	if preset == "gravel" and gravel > 0.0:
		effective = gravel
	elif preset == "tarmac" and tarmac > 0.0:
		effective = tarmac
	if not is_finite(effective) or effective <= 0.0:
		return {"ok": false, "error": "powertrain.final_drive effective ratio must be finite and positive after preset '%s'." % preset}
	values["final_drive"] = effective
	values["final_drive_gravel"] = gravel
	values["final_drive_tarmac"] = tarmac
	values["final_drive_preset"] = preset
	var freewheel_doc: Variant = powertrain.get("freewheel", {})
	if not freewheel_doc is Dictionary:
		return {"ok": false, "error": "powertrain.freewheel must be a dictionary."}
	values["freewheel_enabled"] = bool((freewheel_doc as Dictionary).get("enabled", false))
	var fw_idle := float((freewheel_doc as Dictionary).get("idle_rpm", 1000.0))
	if not is_finite(fw_idle):
		return {"ok": false, "error": "powertrain.freewheel.idle_rpm must be finite."}
	values["freewheel_idle_rpm"] = maxf(fw_idle, 400.0)
	var fw_margin := float((freewheel_doc as Dictionary).get("reengage_margin_rad_s", 1.5))
	if not is_finite(fw_margin):
		return {"ok": false, "error": "powertrain.freewheel.reengage_margin_rad_s must be finite."}
	values["freewheel_reengage_margin"] = clampf(fw_margin, 0.0, 10.0)
	var motor_moment := float(powertrain.get("motor_moment", 0.15))
	if not is_finite(motor_moment) or motor_moment <= 0.0:
		return {"ok": false, "error": "powertrain.motor_moment must be finite and positive."}
	values["motor_moment"] = motor_moment
	values["gearbox_input_inertia"] = maxf(
		float(powertrain.get("gearbox_input_inertia_kg_m2", GEVP_GEAR_INERTIA)),
		0.000001,
	)
	values["max_clutch_torque_ratio"] = maxf(float(powertrain.get("max_clutch_torque_ratio", 1.35)), 0.0)
	values["clutch_out_rpm_offset"] = maxf(float(powertrain.get("clutch_out_rpm_offset", 300.0)), 0.0)
	values["idle_disengagement_hysteresis"] = maxf(
		float(powertrain.get("idle_disengagement_hysteresis_rpm", 150.0)), 0.0
	)
	values["torque_attack_rate"] = maxf(float(powertrain.get("torque_attack_rate_nm_s", 0.0)), 0.0)
	var throttle_resp_raw: Variant = powertrain.get("throttle_response", null)
	if throttle_resp_raw != null and not throttle_resp_raw is Dictionary:
		return {"ok": false, "error": "powertrain.throttle_response must be a dictionary."}
	var throttle_resp_enabled := false
	var throttle_tau_up := 0.0
	var throttle_tau_down := 0.0
	var throttle_rpm_ref := 3000.0
	var throttle_scale_min := 0.6
	var throttle_scale_max := 1.8
	var throttle_resp_attack := 0.0
	if throttle_resp_raw is Dictionary:
		var tr_doc: Dictionary = throttle_resp_raw
		var tau_up_check := _pick_block_number(tr_doc, "tau_up_s", "powertrain.throttle_response", 0.0)
		if not bool(tau_up_check.get("ok", false)):
			return tau_up_check
		throttle_tau_up = float(tau_up_check["value"])
		if throttle_tau_up < 0.0 or throttle_tau_up > 1.0:
			return {"ok": false, "error": "powertrain.throttle_response.tau_up_s must be within [0.0, 1.0]."}
		var tau_down_check := _pick_block_number(tr_doc, "tau_down_s", "powertrain.throttle_response", throttle_tau_up)
		if not bool(tau_down_check.get("ok", false)):
			return tau_down_check
		throttle_tau_down = float(tau_down_check["value"])
		if throttle_tau_down < 0.0 or throttle_tau_down > 1.0:
			return {"ok": false, "error": "powertrain.throttle_response.tau_down_s must be within [0.0, 1.0]."}
		var rpm_ref_check := _pick_block_number(tr_doc, "rpm_reference", "powertrain.throttle_response", 3000.0)
		if not bool(rpm_ref_check.get("ok", false)):
			return rpm_ref_check
		throttle_rpm_ref = float(rpm_ref_check["value"])
		if throttle_rpm_ref < 500.0 or throttle_rpm_ref > 20000.0:
			return {"ok": false, "error": "powertrain.throttle_response.rpm_reference must be within [500.0, 20000.0]."}
		var smin_check := _pick_block_number(tr_doc, "rpm_scale_min", "powertrain.throttle_response", 0.6)
		if not bool(smin_check.get("ok", false)):
			return smin_check
		throttle_scale_min = float(smin_check["value"])
		if throttle_scale_min < 0.1 or throttle_scale_min > 2.0:
			return {"ok": false, "error": "powertrain.throttle_response.rpm_scale_min must be within [0.1, 2.0]."}
		var smax_check := _pick_block_number(tr_doc, "rpm_scale_max", "powertrain.throttle_response", 1.8)
		if not bool(smax_check.get("ok", false)):
			return smax_check
		throttle_scale_max = float(smax_check["value"])
		if throttle_scale_max < throttle_scale_min or throttle_scale_max > 5.0:
			return {"ok": false, "error": "powertrain.throttle_response.rpm_scale_max must be within [rpm_scale_min, 5.0]."}
		var tr_atk_check := _pick_block_number(tr_doc, "torque_attack_rate_nm_s", "powertrain.throttle_response", 0.0)
		if not bool(tr_atk_check.get("ok", false)):
			return tr_atk_check
		throttle_resp_attack = float(tr_atk_check["value"])
		if throttle_resp_attack < 0.0:
			return {"ok": false, "error": "powertrain.throttle_response.torque_attack_rate_nm_s must be >= 0."}
		throttle_resp_enabled = throttle_tau_up > 0.0 or throttle_tau_down > 0.0
	values["throttle_response_enabled"] = throttle_resp_enabled
	values["throttle_tau_up_s"] = throttle_tau_up
	values["throttle_tau_down_s"] = throttle_tau_down
	values["throttle_rpm_reference"] = throttle_rpm_ref
	values["throttle_rpm_scale_min"] = throttle_scale_min
	values["throttle_rpm_scale_max"] = throttle_scale_max
	values["throttle_response_attack_rate_nm_s"] = throttle_resp_attack
	var split_doc: Variant = powertrain.get("front_torque_split", 0.0)
	if not is_finite(float(split_doc)):
		return {"ok": false, "error": "powertrain.front_torque_split must be finite."}
	var split := clampf(float(split_doc), 0.0, 1.0)
	values["front_torque_split"] = split
	values["gear_inertia"] = maxf(float(powertrain.get("gear_inertia", 0.0)), 0.0)
	var tires: Dictionary = domains.get("tires", { }).get("tires", { })
	var front_tire: Dictionary = tires.get("front", { })
	var rear_tire: Dictionary = tires.get("rear", { })
	values["front_wheel_mass"] = maxf(float(front_tire.get("wheel_mass", 20.0)), 0.0)
	values["front_wheel_radius"] = maxf(float(front_tire.get("radius", 0.28)), 0.05)
	values["rear_wheel_mass"] = maxf(float(rear_tire.get("wheel_mass", 20.0)), 0.0)
	values["rear_wheel_radius"] = maxf(float(rear_tire.get("radius", 0.28)), 0.05)
	values["shift_time"] = maxf(float(powertrain.get("shift_time", 0.0)), 0.0)
	values["clutch_release"] = maxf(float(powertrain.get("clutch_release_seconds", 0.04)), 0.001)
	values["clutch_reengage"] = maxf(
		float(
			powertrain.get(
				"clutch_reengage_seconds",
				powertrain.get("downshift_clutch_reengagement_seconds", 0.12),
			)
		),
		0.001,
	)
	var clutch_raw: Variant = powertrain.get("clutch", null)
	if clutch_raw != null and not clutch_raw is Dictionary:
		return {"ok": false, "error": "powertrain.clutch must be a dictionary."}
	var clutch_bite_en := false
	var clutch_bite_s := 0.0
	var clutch_bite_f := 1.0
	var clutch_bite_exp := 1.0
	var clutch_two_phase_en := false
	var clutch_takeup_s := 0.0
	var clutch_fz_s := float(values["clutch_reengage"])
	var clutch_slip_gain := 0.0
	var clutch_mu_ratio := 1.0
	var clutch_static_slip := 3.0
	var damper_en := false
	var damper_disc_i := 0.006
	var damper_idle_k := 220.0
	var damper_idle_deg := 2.5
	var damper_main_k := 1300.0
	var damper_travel := 10.0
	var damper_stop_fac := 15.0
	var damper_hyst := 8.0
	var damper_visc := 2.0
	if clutch_raw is Dictionary:
		var cdoc: Dictionary = clutch_raw
		var bs_check := _pick_block_number(cdoc, "bite_start", "powertrain.clutch", 0.24)
		if not bool(bs_check.get("ok", false)):
			return bs_check
		clutch_bite_s = float(bs_check["value"])
		if clutch_bite_s < 0.0 or clutch_bite_s > 0.9:
			return {"ok": false, "error": "powertrain.clutch.bite_start must be within [0.0, 0.9]."}
		var bf_check := _pick_block_number(cdoc, "bite_full", "powertrain.clutch", 0.76)
		if not bool(bf_check.get("ok", false)):
			return bf_check
		clutch_bite_f = float(bf_check["value"])
		if clutch_bite_f <= clutch_bite_s or clutch_bite_f > 1.0:
			return {"ok": false, "error": "powertrain.clutch.bite_full must be within (bite_start, 1.0]."}
		var be_check := _pick_block_number(cdoc, "bite_exponent", "powertrain.clutch", 1.4)
		if not bool(be_check.get("ok", false)):
			return be_check
		clutch_bite_exp = float(be_check["value"])
		if clutch_bite_exp < 0.25 or clutch_bite_exp > 4.0:
			return {"ok": false, "error": "powertrain.clutch.bite_exponent must be within [0.25, 4.0]."}
		clutch_bite_en = (
			cdoc.has("bite_start") or cdoc.has("bite_full") or cdoc.has("bite_exponent")
		)
		var tk_check := _pick_block_number(cdoc, "takeup_seconds", "powertrain.clutch", 0.0)
		if not bool(tk_check.get("ok", false)):
			return tk_check
		clutch_takeup_s = float(tk_check["value"])
		if clutch_takeup_s < 0.0 or clutch_takeup_s > 1.0:
			return {"ok": false, "error": "powertrain.clutch.takeup_seconds must be within [0.0, 1.0]."}
		var fz_check := _pick_block_number(cdoc, "friction_zone_seconds", "powertrain.clutch", float(values["clutch_reengage"]))
		if not bool(fz_check.get("ok", false)):
			return fz_check
		clutch_fz_s = float(fz_check["value"])
		if clutch_fz_s < 0.001 or clutch_fz_s > 2.0:
			return {"ok": false, "error": "powertrain.clutch.friction_zone_seconds must be within [0.001, 2.0]."}
		var sg_check := _pick_block_number(cdoc, "slip_time_gain", "powertrain.clutch", 0.0)
		if not bool(sg_check.get("ok", false)):
			return sg_check
		clutch_slip_gain = float(sg_check["value"])
		if clutch_slip_gain < 0.0 or clutch_slip_gain > 3.0:
			return {"ok": false, "error": "powertrain.clutch.slip_time_gain must be within [0.0, 3.0]."}
		clutch_two_phase_en = (
			clutch_takeup_s > 0.0 or cdoc.has("friction_zone_seconds") or clutch_slip_gain > 0.0
		)
		var mr_check := _pick_block_number(cdoc, "mu_static_ratio", "powertrain.clutch", 1.0)
		if not bool(mr_check.get("ok", false)):
			return mr_check
		clutch_mu_ratio = float(mr_check["value"])
		if clutch_mu_ratio < 0.5 or clutch_mu_ratio > 2.0:
			return {"ok": false, "error": "powertrain.clutch.mu_static_ratio must be within [0.5, 2.0]."}
		var ss_check := _pick_block_number(cdoc, "static_slip_rad_s", "powertrain.clutch", 3.0)
		if not bool(ss_check.get("ok", false)):
			return ss_check
		clutch_static_slip = float(ss_check["value"])
		if clutch_static_slip < 0.1 or clutch_static_slip > 50.0:
			return {"ok": false, "error": "powertrain.clutch.static_slip_rad_s must be within [0.1, 50.0]."}
		var damper_raw: Variant = cdoc.get("damper", null)
		if damper_raw != null and not damper_raw is Dictionary:
			return {"ok": false, "error": "powertrain.clutch.damper must be a dictionary."}
		if damper_raw is Dictionary:
			var ddoc: Dictionary = damper_raw
			damper_en = bool(ddoc.get("enabled", false))
			var di_check := _pick_block_number(ddoc, "disc_inertia_kg_m2", "powertrain.clutch.damper", 0.006)
			if not bool(di_check.get("ok", false)):
				return di_check
			damper_disc_i = float(di_check["value"])
			if damper_disc_i < 0.0005 or damper_disc_i > 0.2:
				return {"ok": false, "error": "powertrain.clutch.damper.disc_inertia_kg_m2 must be within [0.0005, 0.2]."}
			var ik_check := _pick_block_number(ddoc, "idle_stiffness_nm_per_rad", "powertrain.clutch.damper", 220.0)
			if not bool(ik_check.get("ok", false)):
				return ik_check
			damper_idle_k = float(ik_check["value"])
			if damper_idle_k < 1.0 or damper_idle_k > 50000.0:
				return {"ok": false, "error": "powertrain.clutch.damper.idle_stiffness_nm_per_rad must be within [1.0, 50000.0]."}
			var id_check := _pick_block_number(ddoc, "idle_travel_deg", "powertrain.clutch.damper", 2.5)
			if not bool(id_check.get("ok", false)):
				return id_check
			damper_idle_deg = float(id_check["value"])
			if damper_idle_deg < 0.0 or damper_idle_deg > 20.0:
				return {"ok": false, "error": "powertrain.clutch.damper.idle_travel_deg must be within [0.0, 20.0]."}
			var mk_check := _pick_block_number(ddoc, "main_stiffness_nm_per_rad", "powertrain.clutch.damper", 1300.0)
			if not bool(mk_check.get("ok", false)):
				return mk_check
			damper_main_k = float(mk_check["value"])
			if damper_main_k < 10.0 or damper_main_k > 100000.0:
				return {"ok": false, "error": "powertrain.clutch.damper.main_stiffness_nm_per_rad must be within [10.0, 100000.0]."}
			var tr_check := _pick_block_number(ddoc, "travel_deg", "powertrain.clutch.damper", 10.0)
			if not bool(tr_check.get("ok", false)):
				return tr_check
			damper_travel = float(tr_check["value"])
			if damper_travel < damper_idle_deg or damper_travel < 1.0 or damper_travel > 35.0:
				return {"ok": false, "error": "powertrain.clutch.damper.travel_deg must be within [max(idle_travel_deg, 1.0), 35.0]."}
			var sf_check := _pick_block_number(ddoc, "stop_stiffness_factor", "powertrain.clutch.damper", 15.0)
			if not bool(sf_check.get("ok", false)):
				return sf_check
			damper_stop_fac = float(sf_check["value"])
			if damper_stop_fac < 1.0 or damper_stop_fac > 100.0:
				return {"ok": false, "error": "powertrain.clutch.damper.stop_stiffness_factor must be within [1.0, 100.0]."}
			var hy_check := _pick_block_number(ddoc, "hysteresis_nm", "powertrain.clutch.damper", 8.0)
			if not bool(hy_check.get("ok", false)):
				return hy_check
			damper_hyst = float(hy_check["value"])
			if damper_hyst < 0.0 or damper_hyst > 200.0:
				return {"ok": false, "error": "powertrain.clutch.damper.hysteresis_nm must be within [0.0, 200.0]."}
			var vi_check := _pick_block_number(ddoc, "viscous_nms_per_rad", "powertrain.clutch.damper", 2.0)
			if not bool(vi_check.get("ok", false)):
				return vi_check
			damper_visc = float(vi_check["value"])
			if damper_visc < 0.0 or damper_visc > 100.0:
				return {"ok": false, "error": "powertrain.clutch.damper.viscous_nms_per_rad must be within [0.0, 100.0]."}
	values["clutch_bite_enabled"] = clutch_bite_en
	values["clutch_bite_start"] = clutch_bite_s
	values["clutch_bite_full"] = clutch_bite_f
	values["clutch_bite_exponent"] = clutch_bite_exp
	values["clutch_two_phase_enabled"] = clutch_two_phase_en
	values["clutch_takeup_seconds"] = clutch_takeup_s
	values["clutch_friction_zone_seconds"] = clutch_fz_s
	values["clutch_slip_time_gain"] = clutch_slip_gain
	values["clutch_mu_static_ratio"] = clutch_mu_ratio
	values["clutch_static_slip_rad_s"] = clutch_static_slip
	values["clutch_damper_enabled"] = damper_en
	values["clutch_damper_disc_inertia_kg_m2"] = damper_disc_i
	values["clutch_damper_idle_stiffness_nm_per_rad"] = damper_idle_k
	values["clutch_damper_idle_travel_deg"] = damper_idle_deg
	values["clutch_damper_main_stiffness_nm_per_rad"] = damper_main_k
	values["clutch_damper_travel_deg"] = damper_travel
	values["clutch_damper_stop_stiffness_factor"] = damper_stop_fac
	values["clutch_damper_hysteresis_nm"] = damper_hyst
	values["clutch_damper_viscous_nms_per_rad"] = damper_visc
	values["synchronizer_capacity"] = maxf(float(powertrain.get("synchronizer_capacity_nm", 25.0)), 0.001)
	values["synchronizer_tolerance"] = maxf(
		float(powertrain.get("synchronizer_tolerance_rad_s", 0.1)), 0.0001
	)
	values["automatic_transmission"] = bool(powertrain.get("automatic_transmission", false))
	values["downshift_rev_matching"] = bool(powertrain.get("downshift_rev_matching_enabled", false))
	values["downshift_blip_fraction"] = clampf(
		float(powertrain.get("downshift_blip_torque_fraction", 0.8)), 0.0, 1.0
	)
	values["downshift_target_fraction"] = clampf(
		float(powertrain.get("downshift_maximum_target_revolutions_per_minute_fraction", 0.92)),
		0.0,
		1.0,
	)
	values["downshift_blip_response"] = maxf(
		float(powertrain.get("downshift_blip_response_seconds", 0.04)), 0.001
	)
	values["downshift_blip_tolerance"] = maxf(
		float(powertrain.get("downshift_blip_tolerance_rpm", 25.0)), 0.0
	)
	var compliance: Dictionary = powertrain.get("driveline_compliance", { })
	values["compliance_enabled"] = bool(compliance.get("enabled", false))
	var out_inertia := float(compliance.get("output_inertia_kg_m2", 0.2))
	var stiffness := float(compliance.get("stiffness_nm_per_rad", 8000.0))
	var damping := float(compliance.get("damping_nms_per_rad", 120.0))
	if (
		not is_finite(out_inertia) or out_inertia <= 0.0
		or not is_finite(stiffness) or stiffness <= 0.0
		or not is_finite(damping) or damping < 0.0
	):
		return {
			"ok": false,
			"error": "powertrain.driveline_compliance requires finite positive inertia/stiffness and nonnegative damping.",
		}
	values["compliance_inertia"] = out_inertia
	values["compliance_stiffness"] = stiffness
	values["compliance_damping"] = damping
	var backlash_rad := 0.0
	if compliance.has("backlash_rad"):
		var backlash_check := _require_finite_number(
			compliance.get("backlash_rad"), "powertrain.driveline_compliance.backlash_rad"
		)
		if not bool(backlash_check.get("ok", false)):
			return backlash_check
		backlash_rad = float(backlash_check["value"])
		if backlash_rad < 0.0 or backlash_rad > 0.25:
			return {
				"ok": false,
				"error": "powertrain.driveline_compliance.backlash_rad must be within [0.0, 0.25].",
			}
	var backlash_damping_ratio := 0.04
	if compliance.has("backlash_damping_ratio"):
		var lash_damp_check := _require_finite_number(
			compliance.get("backlash_damping_ratio"),
			"powertrain.driveline_compliance.backlash_damping_ratio",
		)
		if not bool(lash_damp_check.get("ok", false)):
			return lash_damp_check
		backlash_damping_ratio = float(lash_damp_check["value"])
		if backlash_damping_ratio < 0.0 or backlash_damping_ratio > 1.0:
			return {
				"ok": false,
				"error": "powertrain.driveline_compliance.backlash_damping_ratio must be within [0.0, 1.0].",
			}
	values["compliance_backlash_rad"] = backlash_rad
	values["compliance_backlash_damping_ratio"] = backlash_damping_ratio
	var contact_soft_zone := 0.0
	if compliance.has("contact_soft_zone_rad"):
		var csz_check := _require_finite_number(
			compliance.get("contact_soft_zone_rad"),
			"powertrain.driveline_compliance.contact_soft_zone_rad",
		)
		if not bool(csz_check.get("ok", false)):
			return csz_check
		contact_soft_zone = float(csz_check["value"])
		if contact_soft_zone < 0.0 or contact_soft_zone > 0.1:
			return {
				"ok": false,
				"error": "powertrain.driveline_compliance.contact_soft_zone_rad must be within [0.0, 0.1].",
			}
	var contact_restitution := 0.3
	if compliance.has("contact_restitution"):
		var cr_check := _require_finite_number(
			compliance.get("contact_restitution"),
			"powertrain.driveline_compliance.contact_restitution",
		)
		if not bool(cr_check.get("ok", false)):
			return cr_check
		contact_restitution = float(cr_check["value"])
		if contact_restitution < 0.05 or contact_restitution > 0.99:
			return {
				"ok": false,
				"error": "powertrain.driveline_compliance.contact_restitution must be within [0.05, 0.99].",
			}
	var end_stop_margin := 1.5
	if compliance.has("end_stop_margin"):
		var esm_check := _require_finite_number(
			compliance.get("end_stop_margin"),
			"powertrain.driveline_compliance.end_stop_margin",
		)
		if not bool(esm_check.get("ok", false)):
			return esm_check
		end_stop_margin = float(esm_check["value"])
		if end_stop_margin < 1.0 or end_stop_margin > 5.0:
			return {
				"ok": false,
				"error": "powertrain.driveline_compliance.end_stop_margin must be within [1.0, 5.0].",
			}
	var end_stop_stiff_fac := 8.0
	if compliance.has("end_stop_stiffness_factor"):
		var ess_check := _require_finite_number(
			compliance.get("end_stop_stiffness_factor"),
			"powertrain.driveline_compliance.end_stop_stiffness_factor",
		)
		if not bool(ess_check.get("ok", false)):
			return ess_check
		end_stop_stiff_fac = float(ess_check["value"])
		if end_stop_stiff_fac < 1.0 or end_stop_stiff_fac > 50.0:
			return {
				"ok": false,
				"error": "powertrain.driveline_compliance.end_stop_stiffness_factor must be within [1.0, 50.0].",
			}
	values["compliance_contact_soft_zone_rad"] = contact_soft_zone
	values["compliance_contact_restitution"] = contact_restitution
	values["compliance_end_stop_margin"] = end_stop_margin
	values["compliance_end_stop_stiffness_factor"] = end_stop_stiff_fac
	var reaction_raw: Variant = powertrain.get("chassis_reaction", {})
	if reaction_raw != null and not reaction_raw is Dictionary:
		return {"ok": false, "error": "powertrain.chassis_reaction must be a dictionary."}
	var reaction: Dictionary = reaction_raw if reaction_raw is Dictionary else {}
	var reaction_enabled := bool(reaction.get("enabled", false))
	var reaction_orientation := str(reaction.get("engine_orientation", "longitudinal")).strip_edges().to_lower()
	if reaction_orientation != "longitudinal" and reaction_orientation != "transverse":
		return {
			"ok": false,
			"error": "powertrain.chassis_reaction.engine_orientation must be 'longitudinal' or 'transverse'.",
		}
	var crank_sign := 1.0
	if reaction.has("crank_spin_sign"):
		var sign_check := _require_finite_number(
			reaction.get("crank_spin_sign"), "powertrain.chassis_reaction.crank_spin_sign"
		)
		if not bool(sign_check.get("ok", false)):
			return sign_check
		var s_val := float(sign_check["value"])
		if absf(s_val) != 1.0:
			return {
				"ok": false,
				"error": "powertrain.chassis_reaction.crank_spin_sign must be -1.0 or 1.0.",
			}
		crank_sign = s_val
	var reaction_scale := 1.0
	if reaction.has("reaction_scale"):
		var scale_check := _require_finite_number(
			reaction.get("reaction_scale"), "powertrain.chassis_reaction.reaction_scale"
		)
		if not bool(scale_check.get("ok", false)):
			return scale_check
		reaction_scale = float(scale_check["value"])
		if reaction_scale < 0.0 or reaction_scale > 3.0:
			return {
				"ok": false,
				"error": "powertrain.chassis_reaction.reaction_scale must be within [0.0, 3.0].",
			}
	var mount_tau := 0.018
	if reaction.has("mount_tau_s"):
		var tau_check := _require_finite_number(
			reaction.get("mount_tau_s"), "powertrain.chassis_reaction.mount_tau_s"
		)
		if not bool(tau_check.get("ok", false)):
			return tau_check
		mount_tau = float(tau_check["value"])
		if mount_tau < 0.0 or mount_tau > 0.25:
			return {
				"ok": false,
				"error": "powertrain.chassis_reaction.mount_tau_s must be within [0.0, 0.25].",
			}
	var driveshaft_roll := 0.0
	if reaction.has("driveshaft_roll_fraction"):
		var ds_check := _require_finite_number(
			reaction.get("driveshaft_roll_fraction"),
			"powertrain.chassis_reaction.driveshaft_roll_fraction",
		)
		if not bool(ds_check.get("ok", false)):
			return ds_check
		driveshaft_roll = float(ds_check["value"])
		if driveshaft_roll < 0.0 or driveshaft_roll > 1.0:
			return {
				"ok": false,
				"error": "powertrain.chassis_reaction.driveshaft_roll_fraction must be within [0.0, 1.0].",
			}
	var mount_model := str(reaction.get("mount_model", "first_order")).strip_edges().to_lower()
	if mount_model != "first_order" and mount_model != "second_order":
		return {
			"ok": false,
			"error": "powertrain.chassis_reaction.mount_model must be 'first_order' or 'second_order'.",
		}
	var roll_inertia_check := _pick_block_number(reaction, "roll_inertia_kg_m2", "powertrain.chassis_reaction", 3.5)
	if not bool(roll_inertia_check.get("ok", false)):
		return roll_inertia_check
	var roll_inertia := float(roll_inertia_check["value"])
	if roll_inertia < 0.1 or roll_inertia > 50.0:
		return {"ok": false, "error": "powertrain.chassis_reaction.roll_inertia_kg_m2 must be within [0.1, 50.0]."}
	var default_pitch_inertia := roll_inertia if reaction_orientation == "transverse" else roll_inertia * 1.5
	var pitch_inertia_check := _pick_block_number(reaction, "pitch_inertia_kg_m2", "powertrain.chassis_reaction", default_pitch_inertia)
	if not bool(pitch_inertia_check.get("ok", false)):
		return pitch_inertia_check
	var pitch_inertia := float(pitch_inertia_check["value"])
	if pitch_inertia < 0.1 or pitch_inertia > 60.0:
		return {"ok": false, "error": "powertrain.chassis_reaction.pitch_inertia_kg_m2 must be within [0.1, 60.0]."}
	var mfreq_check := _pick_block_number(reaction, "mount_frequency_hz", "powertrain.chassis_reaction", 10.0)
	if not bool(mfreq_check.get("ok", false)):
		return mfreq_check
	var mount_freq := float(mfreq_check["value"])
	if mount_freq < 1.0 or mount_freq > 40.0:
		return {"ok": false, "error": "powertrain.chassis_reaction.mount_frequency_hz must be within [1.0, 40.0]."}
	var mdamp_check := _pick_block_number(reaction, "mount_damping_ratio", "powertrain.chassis_reaction", 0.22)
	if not bool(mdamp_check.get("ok", false)):
		return mdamp_check
	var mount_damp := float(mdamp_check["value"])
	if mount_damp < 0.01 or mount_damp > 2.0:
		return {"ok": false, "error": "powertrain.chassis_reaction.mount_damping_ratio must be within [0.01, 2.0]."}
	var snub_ang_check := _pick_block_number(reaction, "snubber_angle_deg", "powertrain.chassis_reaction", 6.0)
	if not bool(snub_ang_check.get("ok", false)):
		return snub_ang_check
	var snub_angle := float(snub_ang_check["value"])
	if snub_angle < 0.5 or snub_angle > 30.0:
		return {"ok": false, "error": "powertrain.chassis_reaction.snubber_angle_deg must be within [0.5, 30.0]."}
	var snub_fac_check := _pick_block_number(reaction, "snubber_stiffness_factor", "powertrain.chassis_reaction", 6.0)
	if not bool(snub_fac_check.get("ok", false)):
		return snub_fac_check
	var snub_factor := float(snub_fac_check["value"])
	if snub_factor < 1.0 or snub_factor > 50.0:
		return {"ok": false, "error": "powertrain.chassis_reaction.snubber_stiffness_factor must be within [1.0, 50.0]."}
	var tx_pitch_check := _pick_block_number(reaction, "transaxle_pitch_fraction", "powertrain.chassis_reaction", 0.0)
	if not bool(tx_pitch_check.get("ok", false)):
		return tx_pitch_check
	var tx_pitch_frac := float(tx_pitch_check["value"])
	if tx_pitch_frac < 0.0 or tx_pitch_frac > 1.0:
		return {"ok": false, "error": "powertrain.chassis_reaction.transaxle_pitch_fraction must be within [0.0, 1.0]."}
	values["chassis_reaction_enabled"] = reaction_enabled
	values["chassis_reaction_orientation"] = reaction_orientation
	values["chassis_reaction_crank_sign"] = crank_sign
	values["chassis_reaction_scale"] = reaction_scale
	values["chassis_reaction_mount_tau_s"] = mount_tau
	values["chassis_reaction_driveshaft_roll_fraction"] = driveshaft_roll
	values["chassis_reaction_mount_model"] = mount_model
	values["chassis_reaction_roll_inertia_kg_m2"] = roll_inertia
	values["chassis_reaction_pitch_inertia_kg_m2"] = pitch_inertia
	values["chassis_reaction_mount_frequency_hz"] = mount_freq
	values["chassis_reaction_mount_damping_ratio"] = mount_damp
	values["chassis_reaction_snubber_angle_deg"] = snub_angle
	values["chassis_reaction_snubber_stiffness_factor"] = snub_factor
	values["chassis_reaction_transaxle_pitch_fraction"] = tx_pitch_frac
	# Marchas: al menos una hacia delante, todas positivas y finitas.
	var ratios: Variant = powertrain.get("gear_ratios", [])
	if not ratios is Array or (ratios as Array).is_empty():
		return {
			"ok": false,
			"error": "powertrain.gear_ratios must contain at least one forward ratio.",
		}
	var staged_ratios: Array[float] = []
	var ratio_index := 0
	for ratio in ratios:
		var ratio_check := _require_finite_number(
			ratio, "powertrain.gear_ratios[%d]" % ratio_index
		)
		if not bool(ratio_check.get("ok", false)):
			return ratio_check
		var staged_ratio := float(ratio_check["value"])
		if staged_ratio <= 0.0:
			return {
				"ok": false,
				"error": "powertrain.gear_ratios[%d] must be finite and positive." % ratio_index,
			}
		staged_ratios.append(staged_ratio)
		ratio_index += 1
	values["gear_ratios"] = staged_ratios
	# Diferenciales por eje (plan §4).
	var legacy_doc: Variant = powertrain.get("differential", {})
	var front_doc: Variant = powertrain.get("differential_front", null)
	var rear_doc: Variant = powertrain.get("differential_rear", null)
	if legacy_doc != null and not legacy_doc is Dictionary:
		return {"ok": false, "error": "powertrain.differential must be a dictionary."}
	if front_doc != null and not front_doc is Dictionary:
		return {"ok": false, "error": "powertrain.differential_front must be a dictionary."}
	if rear_doc != null and not rear_doc is Dictionary:
		return {"ok": false, "error": "powertrain.differential_rear must be a dictionary."}
	var is_awd := split > 0.0 and split < 1.0
	var legacy_staged := _validate_differential_block(
		legacy_doc if legacy_doc is Dictionary else {},
		"powertrain.differential", "clutch_lsd", 0.0, 45.0, 60.0, 4.0
	)
	if not bool(legacy_staged.get("ok", false)):
		return legacy_staged
	var legacy_values: Dictionary = legacy_staged["values"]
	if is_awd:
		if not front_doc is Dictionary:
			return {"ok": false, "error": "powertrain.differential_front is required for AWD (0 < front_torque_split < 1)."}
		if not rear_doc is Dictionary:
			return {"ok": false, "error": "powertrain.differential_rear is required for AWD (0 < front_torque_split < 1)."}
	var front_staged: Dictionary
	var rear_staged: Dictionary
	if front_doc is Dictionary:
		front_staged = _validate_differential_block(
			front_doc, "powertrain.differential_front", "open", 0.0, 45.0, 60.0, 4.0
		)
	elif split >= 1.0:
		front_staged = _validate_differential_block(
			legacy_doc if legacy_doc is Dictionary else {},
			"powertrain.differential", "clutch_lsd", 0.0, 45.0, 60.0, 4.0
		)
	else:
		front_staged = _validate_differential_block(
			{}, "powertrain.differential_front", "open", 0.0, 45.0, 60.0, 4.0
		)
	if not bool(front_staged.get("ok", false)):
		return front_staged
	if rear_doc is Dictionary:
		rear_staged = _validate_differential_block(
			rear_doc, "powertrain.differential_rear", "open", 0.0, 45.0, 60.0, 4.0
		)
	elif split < 1.0:
		rear_staged = _validate_differential_block(
			legacy_doc if legacy_doc is Dictionary else {},
			"powertrain.differential", "clutch_lsd", 0.0, 45.0, 60.0, 4.0
		)
	else:
		rear_staged = _validate_differential_block(
			{}, "powertrain.differential_rear", "open", 0.0, 45.0, 60.0, 4.0
		)
	if not bool(rear_staged.get("ok", false)):
		return rear_staged
	values["front_differential"] = front_staged["values"]
	values["rear_differential"] = rear_staged["values"]
	values["base_power_ratio"] = float(legacy_values["power_ratio"])
	values["base_coast_ratio"] = float(legacy_values["coast_ratio"])
	var slip_doc: Variant = (
		legacy_doc.get("slip_transition_threshold_rad_s", 4.0)
		if legacy_doc is Dictionary else 4.0
	)
	if not is_finite(float(slip_doc)):
		return {"ok": false, "error": "powertrain.differential.slip_transition_threshold_rad_s must be finite."}
	values["slip_transition_threshold"] = maxf(float(slip_doc), 0.01)
	return {"ok": true, "values": values}


# Valida un bloque de diferencial de un eje. defaults solo se usan cuando la
# clave se omite; type=spool y tipos desconocidos se rechazan (plan §4).
# Numéricos estrictos (hallazgo 1): int/float finitos, sin bool ni cadenas.
# default_coast_ratio < 0 hereda del power resuelto (compatibilidad).
static func _validate_differential_block(
	doc: Dictionary, field: String, default_type: String,
	default_preload: float, default_power_ramp: float,
	default_coast_ramp: float, default_clutches: float,
	default_power_ratio: float = 0.0, default_coast_ratio: float = -1.0,
	default_gain: float = 0.16,
	default_lock_stiffness: float = 0.0,
	default_lock_damping_ratio: float = 0.7,
	default_pressure_tau: float = 0.0,
	default_release_tau: float = -1.0,
	default_blend_band_fraction: float = 0.0,
	default_blend_band_nm: float = 0.0,
	default_static_friction_factor: float = 1.0,
	default_slip_reference: float = 2.0
) -> Dictionary:
	var dtype := str(doc.get("type", default_type))
	if dtype == "spool":
		return {
			"ok": false,
			"error": field + ".type 'spool' requires a rigid constraint (not implemented).",
		}
	if not dtype in DIFFERENTIAL_FRICTION_TYPES and dtype != "open":
		return {"ok": false, "error": field + ".type unknown: " + dtype}
	var preload_pick := _pick_block_number(doc, "preload_nm", field, default_preload)
	if not bool(preload_pick.get("ok", false)):
		return preload_pick
	var staged_preload := float(preload_pick["value"])
	if staged_preload < 0.0:
		return {"ok": false, "error": field + ".preload_nm must be finite and >= 0."}
	var power_pick := _pick_block_number(
		doc, "clutch_friction_coefficient", field, default_power_ratio
	)
	if not bool(power_pick.get("ok", false)):
		return power_pick
	var power_ratio := float(power_pick["value"])
	if power_ratio < 0.0:
		return {"ok": false, "error": field + ".clutch_friction_coefficient must be finite and >= 0."}
	var coast_fallback := power_ratio if default_coast_ratio < 0.0 else default_coast_ratio
	var coast_pick := _pick_block_number(
		doc, "coast_friction_coefficient", field, coast_fallback
	)
	if not bool(coast_pick.get("ok", false)):
		return coast_pick
	var coast_ratio := float(coast_pick["value"])
	if coast_ratio < 0.0:
		return {"ok": false, "error": field + ".coast_friction_coefficient must be finite and >= 0."}
	var power_ramp_pick := _pick_block_number(
		doc, "power_ramp_angle_deg", field, default_power_ramp
	)
	if not bool(power_ramp_pick.get("ok", false)):
		return power_ramp_pick
	var coast_ramp_pick := _pick_block_number(
		doc, "coast_ramp_angle_deg", field, default_coast_ramp
	)
	if not bool(coast_ramp_pick.get("ok", false)):
		return coast_ramp_pick
	var clutches_pick := _pick_block_number(doc, "clutches", field, default_clutches)
	if not bool(clutches_pick.get("ok", false)):
		return clutches_pick
	var clutches := float(clutches_pick["value"])
	if clutches < 0.0:
		return {"ok": false, "error": field + ".clutches must be finite and >= 0."}
	var gain_pick := _pick_block_number(doc, "ramp_gain", field, default_gain)
	if not bool(gain_pick.get("ok", false)):
		return gain_pick
	var gain := float(gain_pick["value"])
	if gain < 0.0:
		return {"ok": false, "error": field + ".ramp_gain must be finite and >= 0."}
	var lk_pick := _pick_block_number(doc, "lock_stiffness_nm_per_rad", field, default_lock_stiffness)
	if not bool(lk_pick.get("ok", false)):
		return lk_pick
	var lock_stiff := float(lk_pick["value"])
	if lock_stiff < 0.0 or lock_stiff > 200000.0:
		return {"ok": false, "error": field + ".lock_stiffness_nm_per_rad must be within [0.0, 200000.0]."}
	var lz_pick := _pick_block_number(doc, "lock_damping_ratio", field, default_lock_damping_ratio)
	if not bool(lz_pick.get("ok", false)):
		return lz_pick
	var lock_zeta := float(lz_pick["value"])
	if lock_zeta < 0.05 or lock_zeta > 3.0:
		return {"ok": false, "error": field + ".lock_damping_ratio must be within [0.05, 3.0]."}
	var pt_pick := _pick_block_number(doc, "pressure_tau_s", field, default_pressure_tau)
	if not bool(pt_pick.get("ok", false)):
		return pt_pick
	var pressure_tau := float(pt_pick["value"])
	if pressure_tau < 0.0 or pressure_tau > 0.5:
		return {"ok": false, "error": field + ".pressure_tau_s must be within [0.0, 0.5]."}
	var rel_fallback := pressure_tau if default_release_tau < 0.0 else default_release_tau
	var rt_pick := _pick_block_number(doc, "release_tau_s", field, rel_fallback)
	if not bool(rt_pick.get("ok", false)):
		return rt_pick
	var release_tau := float(rt_pick["value"])
	if release_tau < 0.0 or release_tau > 1.0:
		return {"ok": false, "error": field + ".release_tau_s must be within [0.0, 1.0]."}
	var bbf_pick := _pick_block_number(doc, "blend_band_fraction", field, default_blend_band_fraction)
	if not bool(bbf_pick.get("ok", false)):
		return bbf_pick
	var blend_frac := float(bbf_pick["value"])
	if blend_frac < 0.0 or blend_frac > 1.0:
		return {"ok": false, "error": field + ".blend_band_fraction must be within [0.0, 1.0]."}
	var bbn_pick := _pick_block_number(doc, "blend_band_nm", field, default_blend_band_nm)
	if not bool(bbn_pick.get("ok", false)):
		return bbn_pick
	var blend_nm := float(bbn_pick["value"])
	if blend_nm < 0.0 or blend_nm > 5000.0:
		return {"ok": false, "error": field + ".blend_band_nm must be within [0.0, 5000.0]."}
	var sff_pick := _pick_block_number(doc, "static_friction_factor", field, default_static_friction_factor)
	if not bool(sff_pick.get("ok", false)):
		return sff_pick
	var static_fac := float(sff_pick["value"])
	if static_fac < 0.2 or static_fac > 1.5:
		return {"ok": false, "error": field + ".static_friction_factor must be within [0.2, 1.5]."}
	var sref_pick := _pick_block_number(doc, "slip_reference_rad_s", field, default_slip_reference)
	if not bool(sref_pick.get("ok", false)):
		return sref_pick
	var slip_ref := float(sref_pick["value"])
	if slip_ref < 0.05 or slip_ref > 50.0:
		return {"ok": false, "error": field + ".slip_reference_rad_s must be within [0.05, 50.0]."}
	return {
		"ok": true,
		"values": {
			"type": dtype,
			"preload": staged_preload,
			"power_ratio": power_ratio,
			"coast_ratio": coast_ratio,
			"power_ramp": float(power_ramp_pick["value"]),
			"coast_ramp": float(coast_ramp_pick["value"]),
			"clutches": clutches,
			"ramp_gain": gain,
			"preset_id": str(doc.get("preset_id", "")),
			"lock_stiffness": lock_stiff,
			"lock_damping_ratio": lock_zeta,
			"pressure_tau": pressure_tau,
			"release_tau": release_tau,
			"blend_band_fraction": blend_frac,
			"blend_band_nm": blend_nm,
			"static_friction_factor": static_fac,
			"slip_reference": slip_ref,
		},
	}


# Lee un numérico del bloque o devuelve el fallback cuando la clave se omite.
# Las claves presentes pasan el chequeo estricto de tipos (hallazgo 1).
static func _pick_block_number(
	doc: Dictionary, key: String, field: String, fallback: float
) -> Dictionary:
	if not doc.has(key):
		return {"ok": true, "value": fallback}
	return _require_finite_number(doc.get(key), field + "." + key)


# Números actuales del eje indicado ("" = espejo histórico) como fallback
# del sync: las claves ausentes del bloque conservan el valor en curso.
func _current_differential_numbers(axle: String) -> Dictionary:
	if axle == "front":
		return {
			"type": front_differential_type,
			"preload": front_differential_preload_nm,
			"power_ratio": front_differential_power_ratio,
			"coast_ratio": front_differential_coast_ratio,
			"power_ramp": front_differential_power_ramp_angle_deg,
			"coast_ramp": front_differential_coast_ramp_angle_deg,
			"clutches": front_differential_clutches,
			"gain": front_differential_ramp_gain,
			"lock_stiffness": front_differential_lock_stiffness_nm_per_rad,
			"lock_damping_ratio": front_differential_lock_damping_ratio,
			"pressure_tau": front_differential_pressure_tau_s,
			"release_tau": front_differential_release_tau_s,
			"blend_band_fraction": front_differential_blend_band_fraction,
			"blend_band_nm": front_differential_blend_band_nm,
			"static_friction_factor": front_differential_static_friction_factor,
			"slip_reference": front_differential_slip_reference_rad_s,
		}
	if axle == "rear":
		return {
			"type": rear_differential_type,
			"preload": rear_differential_preload_nm,
			"power_ratio": rear_differential_power_ratio,
			"coast_ratio": rear_differential_coast_ratio,
			"power_ramp": rear_differential_power_ramp_angle_deg,
			"coast_ramp": rear_differential_coast_ramp_angle_deg,
			"clutches": rear_differential_clutches,
			"gain": rear_differential_ramp_gain,
			"lock_stiffness": rear_differential_lock_stiffness_nm_per_rad,
			"lock_damping_ratio": rear_differential_lock_damping_ratio,
			"pressure_tau": rear_differential_pressure_tau_s,
			"release_tau": rear_differential_release_tau_s,
			"blend_band_fraction": rear_differential_blend_band_fraction,
			"blend_band_nm": rear_differential_blend_band_nm,
			"static_friction_factor": rear_differential_static_friction_factor,
			"slip_reference": rear_differential_slip_reference_rad_s,
		}
	return {
		"type": differential_type,
		"preload": differential_preload_nm,
		"power_ratio": differential_power_ratio,
		"coast_ratio": differential_coast_ratio,
		"power_ramp": differential_power_ramp_angle_deg,
		"coast_ramp": differential_coast_ramp_angle_deg,
		"clutches": differential_clutches,
		"gain": differential_ramp_gain,
		"lock_stiffness": differential_lock_stiffness_nm_per_rad,
		"lock_damping_ratio": differential_lock_damping_ratio,
		"pressure_tau": differential_pressure_tau_s,
		"release_tau": differential_release_tau_s,
		"blend_band_fraction": differential_blend_band_fraction,
		"blend_band_nm": differential_blend_band_nm,
		"static_friction_factor": differential_static_friction_factor,
		"slip_reference": differential_slip_reference_rad_s,
	}


# Sincroniza un bloque de dominio en el eje indicado sin cambiar tipo ni
# preset. Si el bloque es inválido conserva todo y avisa (los bloques solo
# llegan del perfil ya validado o del garaje numérico ya acotado).
func sync_differential_from_doc(doc: Dictionary, axle: String, field: String) -> bool:
	var cur := _current_differential_numbers(axle)
	var keep_preset := (
		front_differential_preset_id if axle == "front"
		else rear_differential_preset_id if axle == "rear"
		else differential_preset_id
	)
	var staged := _validate_differential_block(
		doc, field, str(cur["type"]),
		float(cur["preload"]), float(cur["power_ramp"]), float(cur["coast_ramp"]),
		float(cur["clutches"]), float(cur["power_ratio"]), float(cur["coast_ratio"]),
		float(cur["gain"]),
		float(cur["lock_stiffness"]), float(cur["lock_damping_ratio"]),
		float(cur["pressure_tau"]), float(cur["release_tau"]),
		float(cur["blend_band_fraction"]), float(cur["blend_band_nm"]),
		float(cur["static_friction_factor"]), float(cur["slip_reference"])
	)
	if not bool(staged.get("ok", false)):
		push_warning(str(staged.get("error", "invalid differential block")))
		return false
	_apply_staged_differential(staged["values"], axle)
	if axle == "front":
		front_differential_preset_id = keep_preset
	elif axle == "rear":
		rear_differential_preset_id = keep_preset
	else:
		differential_preset_id = keep_preset
	return true


# Copia números, tipo y preset del eje al espejo histórico.
func _copy_axle_to_legacy(axle: String) -> void:
	var cur := _current_differential_numbers(axle)
	differential_type = str(cur["type"])
	differential_preload_nm = float(cur["preload"])
	differential_power_ratio = float(cur["power_ratio"])
	differential_coast_ratio = float(cur["coast_ratio"])
	differential_power_ramp_angle_deg = float(cur["power_ramp"])
	differential_coast_ramp_angle_deg = float(cur["coast_ramp"])
	differential_clutches = float(cur["clutches"])
	differential_ramp_gain = float(cur["gain"])
	differential_lock_stiffness_nm_per_rad = float(cur["lock_stiffness"])
	differential_lock_damping_ratio = float(cur["lock_damping_ratio"])
	differential_pressure_tau_s = float(cur["pressure_tau"])
	differential_release_tau_s = float(cur["release_tau"])
	differential_blend_band_fraction = float(cur["blend_band_fraction"])
	differential_blend_band_nm = float(cur["blend_band_nm"])
	differential_static_friction_factor = float(cur["static_friction_factor"])
	differential_slip_reference_rad_s = float(cur["slip_reference"])
	differential_preset_id = (
		front_differential_preset_id if axle == "front" else rear_differential_preset_id
	)


# Sincroniza diferenciales desde bloques de dominio (garaje/setup).
# AWD: cada eje desde su bloque y el espejo histórico refleja el eje
# seleccionado (trasero si reparto < 1). FWD/RWD: el bloque histórico
# alimenta el espejo y el eje motriz (hallazgo 3).
func sync_setup_differentials(legacy_doc: Variant, front_doc: Variant, rear_doc: Variant) -> void:
	var awd := front_torque_split > 0.0 and front_torque_split < 1.0
	if awd:
		if front_doc is Dictionary:
			sync_differential_from_doc(front_doc, "front", "powertrain.differential_front")
		if rear_doc is Dictionary:
			sync_differential_from_doc(rear_doc, "rear", "powertrain.differential_rear")
		_copy_axle_to_legacy("rear")
		return
	var legacy: Dictionary = legacy_doc if legacy_doc is Dictionary else {}
	var driven := "front" if front_torque_split >= 1.0 else "rear"
	sync_differential_from_doc(legacy, "", "powertrain.differential")
	sync_differential_from_doc(legacy, driven, "powertrain.differential")
	if legacy.has("slip_transition_threshold_rad_s"):
		var slip_check := _require_finite_number(
			legacy.get("slip_transition_threshold_rad_s"),
			"powertrain.differential.slip_transition_threshold_rad_s"
		)
		if bool(slip_check.get("ok", false)):
			differential_slip_transition_threshold_rad_s = maxf(float(slip_check["value"]), 0.01)
		else:
			push_warning(str(slip_check.get("error", "invalid slip threshold")))


# Copia un bloque ya validado al eje indicado ("" = espejo histórico del eje
# seleccionado, "front"/"rear" = parámetros propios del eje).
func _apply_staged_differential(staged: Dictionary, axle: String) -> void:
	if axle == "front":
		front_differential_type = str(staged["type"])
		front_differential_preload_nm = float(staged["preload"])
		front_differential_power_ratio = float(staged["power_ratio"])
		front_differential_coast_ratio = float(staged["coast_ratio"])
		front_differential_power_ramp_angle_deg = float(staged["power_ramp"])
		front_differential_coast_ramp_angle_deg = float(staged["coast_ramp"])
		front_differential_clutches = float(staged["clutches"])
		front_differential_ramp_gain = float(staged["ramp_gain"])
		front_differential_preset_id = str(staged["preset_id"])
		front_differential_lock_stiffness_nm_per_rad = float(staged.get("lock_stiffness", 0.0))
		front_differential_lock_damping_ratio = float(staged.get("lock_damping_ratio", 0.7))
		front_differential_pressure_tau_s = float(staged.get("pressure_tau", 0.0))
		front_differential_release_tau_s = float(staged.get("release_tau", 0.0))
		front_differential_blend_band_fraction = float(staged.get("blend_band_fraction", 0.0))
		front_differential_blend_band_nm = float(staged.get("blend_band_nm", 0.0))
		front_differential_static_friction_factor = float(staged.get("static_friction_factor", 1.0))
		front_differential_slip_reference_rad_s = float(staged.get("slip_reference", 2.0))
	elif axle == "rear":
		rear_differential_type = str(staged["type"])
		rear_differential_preload_nm = float(staged["preload"])
		rear_differential_power_ratio = float(staged["power_ratio"])
		rear_differential_coast_ratio = float(staged["coast_ratio"])
		rear_differential_power_ramp_angle_deg = float(staged["power_ramp"])
		rear_differential_coast_ramp_angle_deg = float(staged["coast_ramp"])
		rear_differential_clutches = float(staged["clutches"])
		rear_differential_ramp_gain = float(staged["ramp_gain"])
		rear_differential_preset_id = str(staged["preset_id"])
		rear_differential_lock_stiffness_nm_per_rad = float(staged.get("lock_stiffness", 0.0))
		rear_differential_lock_damping_ratio = float(staged.get("lock_damping_ratio", 0.7))
		rear_differential_pressure_tau_s = float(staged.get("pressure_tau", 0.0))
		rear_differential_release_tau_s = float(staged.get("release_tau", 0.0))
		rear_differential_blend_band_fraction = float(staged.get("blend_band_fraction", 0.0))
		rear_differential_blend_band_nm = float(staged.get("blend_band_nm", 0.0))
		rear_differential_static_friction_factor = float(staged.get("static_friction_factor", 1.0))
		rear_differential_slip_reference_rad_s = float(staged.get("slip_reference", 2.0))
	else:
		differential_type = str(staged["type"])
		differential_preload_nm = float(staged["preload"])
		differential_power_ratio = float(staged["power_ratio"])
		differential_coast_ratio = float(staged["coast_ratio"])
		differential_power_ramp_angle_deg = float(staged["power_ramp"])
		differential_coast_ramp_angle_deg = float(staged["coast_ramp"])
		differential_clutches = float(staged["clutches"])
		differential_ramp_gain = float(staged["ramp_gain"])
		differential_preset_id = str(staged["preset_id"])
		differential_lock_stiffness_nm_per_rad = float(staged.get("lock_stiffness", 0.0))
		differential_lock_damping_ratio = float(staged.get("lock_damping_ratio", 0.7))
		differential_pressure_tau_s = float(staged.get("pressure_tau", 0.0))
		differential_release_tau_s = float(staged.get("release_tau", 0.0))
		differential_blend_band_fraction = float(staged.get("blend_band_fraction", 0.0))
		differential_blend_band_nm = float(staged.get("blend_band_nm", 0.0))
		differential_static_friction_factor = float(staged.get("static_friction_factor", 1.0))
		differential_slip_reference_rad_s = float(staged.get("slip_reference", 2.0))


func set_final_drive_preset(preset: String) -> bool:
	if preset == "gravel" and final_drive_gravel > 0.0:
		final_drive_ratio = final_drive_gravel
		final_drive_preset = preset
		_rust_cfg_dirty = true
		return true
	if preset == "tarmac" and final_drive_tarmac > 0.0:
		final_drive_ratio = final_drive_tarmac
		final_drive_preset = preset
		_rust_cfg_dirty = true
		return true
	return false


# v1: actualiza SOLO parámetros del diferencial desde un preset resuelto.
# No toca caja, embrague, motor ni otros estados de transmisión.
# resolved: {preset_id, type, preload_nm, power_ramp_deg, coast_ramp_deg,
#   active_friction_surfaces, friction_mu_power, friction_mu_coast}
# axle: "" = eje motriz (compat), "front"/"rear" = eje explícito (AWD).
func apply_differential_preset(resolved: Dictionary, axle: String = "") -> Dictionary:
	var preset_id := str(resolved.get("preset_id", ""))
	if preset_id.is_empty():
		return {"ok": false, "error": "Preset de diferencial sin ID."}
	var target_axle := axle
	if target_axle.is_empty():
		target_axle = "front" if front_torque_split >= 1.0 else "rear"
	if target_axle != "front" and target_axle != "rear":
		return {"ok": false, "error": "Eje de diferencial inválido: " + axle}
	var dtype := str(resolved.get("type", "clutch_lsd"))
	if dtype == "spool":
		return {"ok": false, "error": "Tipo spool no soportado hasta disponer de restricción rígida: " + preset_id}
	if not dtype in DIFFERENTIAL_FRICTION_TYPES and dtype != "open":
		return {"ok": false, "error": "Tipo de diferencial no soportado: " + dtype}
	var surfaces := int(resolved.get("active_friction_surfaces", 0))
	if dtype != "open" and surfaces <= 0:
		return {"ok": false, "error": "Preset sin superficies activas válidas: " + preset_id}
	var preload_nm := float(resolved.get("preload_nm", -1.0))
	if not is_finite(preload_nm) or preload_nm < 0.0:
		return {"ok": false, "error": "Precarga inválida en preset: " + preset_id}
	var power_ramp := float(resolved.get("power_ramp_deg", -1.0))
	var coast_ramp := float(resolved.get("coast_ramp_deg", -1.0))
	if not is_finite(power_ramp) or not is_finite(coast_ramp):
		return {"ok": false, "error": "Rampas inválidas en preset: " + preset_id}
	if power_ramp < 15.0 or power_ramp > 85.0 or coast_ramp < 15.0 or coast_ramp > 85.0:
		return {"ok": false, "error": "Rampas fuera de 15-85° en preset: " + preset_id}
	var mu_power := float(resolved.get("friction_mu_power", base_differential_power_ratio))
	var mu_coast := float(resolved.get("friction_mu_coast", base_differential_coast_ratio))
	if not is_finite(mu_power) or not is_finite(mu_coast) or mu_power < 0.0 or mu_coast < 0.0:
		return {"ok": false, "error": "Fricción inválida en preset: " + preset_id}
	# adjustable_friction_lsd (R-Lock): acoplamiento limitado por fricción,
	# nunca restricción rígida de spool. El solver ya satura por capacidad.
	# open: impulso de bloqueo cero (capacidad nula en el solver).
	# H5: la ganancia de rampa se hereda del estado vigente del eje; debe ser
	# finita y no negativa, o el preset se rechaza ANTES de mutar nada. Esto
	# permite probar el rechazo tardío dentro de apply_setup_values() con un
	# preset que el catálogo resuelve pero el modelo rechaza.
	var cur_axle := _current_differential_numbers(target_axle)
	var inherited_gain := float(cur_axle["gain"])
	if not is_finite(inherited_gain) or inherited_gain < 0.0:
		return {"ok": false, "error": "Ganancia de rampa inválida en el eje " + target_axle + " para preset: " + preset_id}
	var staged_lock_stiff := float(resolved.get("lock_stiffness_nm_per_rad", cur_axle["lock_stiffness"]))
	var staged_lock_zeta := float(resolved.get("lock_damping_ratio", cur_axle["lock_damping_ratio"]))
	var staged_press_tau := float(resolved.get("pressure_tau_s", cur_axle["pressure_tau"]))
	var staged_rel_tau := float(resolved.get("release_tau_s", cur_axle["release_tau"]))
	var staged_blend_frac := float(resolved.get("blend_band_fraction", cur_axle["blend_band_fraction"]))
	var staged_blend_nm := float(resolved.get("blend_band_nm", cur_axle["blend_band_nm"]))
	var staged_static_fac := float(resolved.get("static_friction_factor", cur_axle["static_friction_factor"]))
	var staged_slip_ref := float(resolved.get("slip_reference_rad_s", cur_axle["slip_reference"]))
	if (
		not is_finite(staged_lock_stiff) or staged_lock_stiff < 0.0 or staged_lock_stiff > 200000.0
		or not is_finite(staged_lock_zeta) or staged_lock_zeta < 0.05 or staged_lock_zeta > 3.0
		or not is_finite(staged_press_tau) or staged_press_tau < 0.0 or staged_press_tau > 0.5
		or not is_finite(staged_rel_tau) or staged_rel_tau < 0.0 or staged_rel_tau > 1.0
		or not is_finite(staged_blend_frac) or staged_blend_frac < 0.0 or staged_blend_frac > 1.0
		or not is_finite(staged_blend_nm) or staged_blend_nm < 0.0 or staged_blend_nm > 5000.0
		or not is_finite(staged_static_fac) or staged_static_fac < 0.2 or staged_static_fac > 1.5
		or not is_finite(staged_slip_ref) or staged_slip_ref < 0.05 or staged_slip_ref > 50.0
	):
		return {"ok": false, "error": "Parámetros elásticos de diferencial inválidos en el eje " + target_axle + " para preset: " + preset_id}
	var staged := {
		"type": dtype,
		"preload": preload_nm,
		"power_ratio": mu_power,
		"coast_ratio": mu_coast,
		"power_ramp": power_ramp,
		"coast_ramp": coast_ramp,
		"clutches": float(maxi(surfaces, 0)),
		"ramp_gain": inherited_gain,
		"preset_id": preset_id,
		"lock_stiffness": staged_lock_stiff,
		"lock_damping_ratio": staged_lock_zeta,
		"pressure_tau": staged_press_tau,
		"release_tau": staged_rel_tau,
		"blend_band_fraction": staged_blend_frac,
		"blend_band_nm": staged_blend_nm,
		"static_friction_factor": staged_static_fac,
		"slip_reference": staged_slip_ref,
	}
	_apply_staged_differential(staged, target_axle)
	var selected := "front" if front_torque_split >= 1.0 else "rear"
	if target_axle == selected:
		_apply_staged_differential(staged, "")
	return {"ok": true, "preset_id": preset_id, "axle": target_axle}


func reset_compliance() -> void:
	output_shaft_omega_rad_s = 0.0
	driveline_twist_rad = 0.0
	driveline_torque_nm = 0.0
	driveline_energy_j = 0.0
	driveline_dissipation_w = 0.0
	driveline_in_backlash = false
	driveline_backlash_flank = 0
	driveline_backlash_impact_rad_s = 0.0
	manifold_fill = 0.0
	clutch_bite = 0.0
	clutch_slip_rad_s = 0.0
	clutch_damper_twist_rad = 0.0
	clutch_damper_twist_deg = 0.0
	clutch_damper_torque_nm = 0.0
	clutch_damper_at_stop = false
	front_lsd_lock_twist_rad = 0.0
	rear_lsd_lock_twist_rad = 0.0
	front_lsd_filtered_torque_nm = 0.0
	rear_lsd_filtered_torque_nm = 0.0
	front_lsd_blend = 0.5
	rear_lsd_blend = 0.5
	last_front_lsd_filtered_torque_nm = 0.0
	last_front_lsd_blend = 0.5
	last_front_lsd_lock_twist_rad = 0.0
	last_rear_lsd_filtered_torque_nm = 0.0
	last_rear_lsd_blend = 0.5
	last_rear_lsd_lock_twist_rad = 0.0
	last_lsd_filtered_torque_nm = 0.0
	last_lsd_blend = 0.5
	last_lsd_lock_twist_rad = 0.0
	engine_mount_roll_rad = 0.0
	engine_mount_roll_omega_rad_s = 0.0
	engine_mount_pitch_rad = 0.0
	engine_mount_pitch_omega_rad_s = 0.0
	engine_roll_deg = 0.0
	engine_pitch_deg = 0.0
	chassis_reaction_torque_local_nm = Vector3.ZERO
	_reaction_prev_engine_omega = 0.0
	_reaction_prev_input_omega = 0.0
	_reaction_initialized = false
	_mount_prev_chassis_omega_local = Vector3.ZERO
	_mount_chassis_omega_initialized = false


func request_shift(delta_gears: int) -> bool:
	if shift_phase != "idle":
		return false
	var target := clampi(current_gear + delta_gears, -1, maximum_forward_gear)
	if target == current_gear:
		return false
	set_gear(target)
	return true


func set_gear(target_gear: int) -> void:
	if shift_phase != "idle":
		return
	pending_gear = clampi(target_gear, -1, maximum_forward_gear)
	if pending_gear == current_gear:
		return
	revmatch_downshift = current_gear > 0 and pending_gear > 0 and pending_gear < current_gear
	shift_phase = "opening"
	shift_phase_seconds = 0.0
	_shift_damage_delay_seconds = transmission_damage * MAX_TRANSMISSION_SHIFT_DELAY_SECONDS
	var closing_seconds := (
		clutch_takeup_seconds + clutch_friction_zone_seconds
		if clutch_two_phase_enabled
		else clutch_reengage_seconds
	)
	shift_remaining_seconds = clutch_release_seconds + shift_time_seconds + gear_inertia_shift_seconds + closing_seconds + _shift_damage_delay_seconds


func consume_missgear_event() -> bool:
	var fired := missgear_event_pending
	missgear_event_pending = false
	return fired


func reset_shift() -> void:
	freewheel_active = false
	freewheel_throttle = 0.0
	freewheel_delta_rad_s = 0.0
	revmatch_downshift = false
	autoblip_active = false
	autoblip_target_rpm = 0.0
	autoblip_throttle = 0.0
	pending_gear = current_gear
	shift_phase = "idle"
	shift_phase_seconds = 0.0
	shift_remaining_seconds = 0.0


func _ratio_for_gear(gear: int) -> float:
	if gear == -1:
		return reverse_ratio
	if gear <= 0:
		return 0.0
	return gear_ratios[gear - 1] if gear <= gear_ratios.size() else 0.0


func gear_ratio() -> float:
	return _ratio_for_gear(current_gear)


# Resuelve el estado de rueda libre una vez por subpaso (plan §1) con el
# acelerador del conductor, la marcha efectiva y la diferencia de velocidad
# referida al primario (delta = equiv - motor). Histéresis con estado:
# desacopla con delta > disengage; solo reacopla con delta <= reengage
# (margen configurado) o reapertura de gas. Punto muerto (incluido el paso
# por N durante un cambio) y marcha atrás invalidan el estado.
# La integración del motor y el solver consumen esta misma decisión.
func resolve_freewheel(driver_throttle: float, carrier_omega_rad_s: float) -> void:
	freewheel_throttle = clampf(driver_throttle, 0.0, 1.0)
	if not freewheel_enabled:
		freewheel_active = false
		freewheel_delta_rad_s = 0.0
		return
	if current_gear <= 0:
		freewheel_active = false
		freewheel_delta_rad_s = 0.0
		return
	var engine_omega := engine_rpm * TAU / 60.0
	var equiv_omega := carrier_omega_rad_s * gear_ratio() * final_drive_ratio
	var delta := equiv_omega - engine_omega
	freewheel_delta_rad_s = delta
	if freewheel_active:
		if (
			freewheel_throttle >= FREEWHEEL_REENGAGE_THROTTLE
			or delta <= freewheel_reengage_margin_rad_s
		):
			freewheel_active = false
	else:
		if (
			freewheel_throttle <= FREEWHEEL_DISENGAGE_THROTTLE
			and delta > freewheel_disengage_margin_rad_s
		):
			freewheel_active = true


func _update_freewheel(throttle: float, carrier_omega_rad_s: float) -> void:
	resolve_freewheel(throttle, carrier_omega_rad_s)


func invalidate_freewheel() -> void:
	freewheel_active = false
	freewheel_delta_rad_s = 0.0


func is_freewheeling() -> bool:
	return freewheel_active


# Objetivo de ralentí (hallazgo 2): freewheel.idle_rpm con rueda libre
# activa, ralentí general cuando está acoplada. El aporte de ralentí vive
# en el cálculo compartido de par; sin rampas directas de régimen.
func _idle_target_rpm() -> float:
	if freewheel_enabled and freewheel_active:
		return freewheel_idle_rpm
	return idle_rpm


# Términos de par compartidos entre estimador e integrador (plan §2).
# El rozamiento interno del motor SIEMPRE se incluye; la rueda libre corta
# su transmisión a las ruedas (connected=false en el solver), no el par.
static func _engine_torque_terms(
	rpm: float, throttle: float, peak_torque: float, max_rpm: float,
	idle: float, curve_val: float, variable_drag_ratio_value: float,
	constant_brake_ratio_value: float, thermal_derating: float, curve_reference_rpm: float = 0.0
) -> Dictionary:
	var throttle_value := clampf(throttle, 0.0, 1.0)
	var closed_throttle := 1.0 - throttle_value
	var reference_rpm := curve_reference_rpm if curve_reference_rpm > 0.0 else max_rpm
	var rpm_fraction := clampf(rpm / maxf(reference_rpm, 1.0), 0.0, 1.25)
	var rev_limit_band := maxf(max_rpm * 0.025, 100.0)
	var rev_cut := clampf((max_rpm - rpm) / rev_limit_band, 0.0, 1.0)
	var positive_requested := curve_val * peak_torque * throttle_value * clampf(
		thermal_derating, 0.0, 1.0
	) * rev_cut
	var variable_drag := rpm_fraction * peak_torque * variable_drag_ratio_value * lerpf(
		0.15, 1.0, closed_throttle
	)
	var constant_brake := peak_torque * constant_brake_ratio_value * closed_throttle
	var idle_support := 0.0
	if rpm < idle + 250.0:
		var idle_error := clampf((idle + 100.0 - rpm) / 250.0, 0.0, 1.5)
		idle_support = (variable_drag + constant_brake) * clampf(idle_error, 0.0, 1.0) + peak_torque * 0.12 * maxf(
			idle_error - 0.4, 0.0
		)
	return {
		"positive_requested": positive_requested,
		"variable_drag": variable_drag,
		"constant_brake": constant_brake,
		"idle_support": idle_support,
	}


# Par solicitado (sin límite de ataque). El aporte de ralentí usa el objetivo
# vigente (hallazgo 2): freewheel.idle_rpm con rueda libre activa. El
# rozamiento interno se mantiene y la rueda libre solo corta la transmisión.
# freewheeling_override se conserva por compatibilidad pero ya no altera el par.
func engine_torque_at_rpm(rpm: float, throttle: float, thermal_derating: float = 1.0, freewheeling_override: float = -1.0) -> float:
	var rpm_fraction := clampf(rpm / maxf(torque_curve_reference_rpm if torque_curve_reference_rpm > 0.0 else maximum_rpm, 1.0), 0.0, 1.0)
	var terms := _engine_torque_terms(
		rpm, throttle, peak_torque_nm, maximum_rpm, _idle_target_rpm(),
		_evaluate_torque_curve(rpm_fraction), variable_drag_ratio,
		constant_brake_ratio, thermal_derating, torque_curve_reference_rpm
	)
	return float(terms["positive_requested"]) + float(terms["idle_support"]) * thermal_derating - float(terms["variable_drag"]) - float(terms["constant_brake"])


# Par entregado tras aplicar el límite de ataque, con la misma base que el
# estimador (sin mutar estado). A límite estabilizado
# (engine_attack_limited == positive_requested) coincide con la estimación.
func engine_delivered_torque_at_rpm(rpm: float, throttle: float, thermal_derating: float = 1.0) -> float:
	var rpm_fraction := clampf(rpm / maxf(torque_curve_reference_rpm if torque_curve_reference_rpm > 0.0 else maximum_rpm, 1.0), 0.0, 1.0)
	var effective_throttle := manifold_fill if throttle_response_enabled else throttle
	var terms := _engine_torque_terms(
		rpm, effective_throttle, peak_torque_nm, maximum_rpm, _idle_target_rpm(),
		_evaluate_torque_curve(rpm_fraction), variable_drag_ratio,
		constant_brake_ratio, thermal_derating, torque_curve_reference_rpm
	)
	return engine_attack_limited_torque_nm * (1.0 if thermal_derating > 0.0 else 0.0) + float(terms["idle_support"]) * thermal_derating - float(terms["variable_drag"]) - float(terms["constant_brake"])


func advance(
	delta: float,
	throttle: float,
	clutch_engagement_input: float,
	thermal_derating: float,
	carrier_omega_rad_s: float = 0.0,
) -> void:
	var dt := maxf(delta, 0.00001)
	_gearbox_popout_cooldown_s = maxf(_gearbox_popout_cooldown_s - dt, 0.0)
	# Decisión única de rueda libre por subpaso con el acelerador del
	# conductor (plan §1); la integración y el solver consumen este estado.
	resolve_freewheel(throttle, carrier_omega_rad_s)
	shift_phase_seconds += dt
	if shift_phase != "idle":
		shift_remaining_seconds = maxf(dt, shift_remaining_seconds - dt)
	var effective_throttle := _autoblip_command(throttle, thermal_derating, carrier_omega_rad_s, dt)
	_advance_engine_torque(dt, effective_throttle, thermal_derating)
	var engine_inertia := maxf(engine_inertia_kg_m2, 0.000001)
	var mechanical_ceiling_rpm := maxf(torque_curve_reference_rpm, maximum_rpm) * 1.30
	engine_rpm = clampf(
		engine_rpm + engine_torque_nm / engine_inertia * dt * 60.0 / TAU,
		idle_rpm * 0.65 if thermal_derating > 0.0 else 0.0,
		mechanical_ceiling_rpm,
	)
	# Sin rampa directa de rueda libre (plan §2): la caída de régimen la
	# gobiernan el par (rozamiento + aporte de ralentí) y la inercia.
	# La recuperación de ralentí con embrague abierto usa el mismo objetivo
	# que el par: freewheel.idle_rpm en rueda libre (hallazgo 2).
	var idle_recovery_target := _idle_target_rpm()
	if thermal_derating > 0.0 and engine_rpm < idle_recovery_target and clutch_engagement < 0.05:
		engine_rpm = move_toward(engine_rpm, idle_recovery_target, 1500.0 * dt)

	var manual_clutch_pedal := 1.0 - clampf(clutch_engagement_input, 0.0, 1.0)
	var shift_clutch := 1.0 if shift_phase == "opening" or shift_phase == "synchronizing" else 0.0
	var clutch_out_rpm := idle_rpm + clutch_out_rpm_offset
	var idle_floor_rpm := idle_rpm + idle_disengagement_hysteresis_rpm
	var idle_disengagement := 0.0
	if engine_rpm <= idle_floor_rpm:
		idle_disengagement = 1.0
	elif engine_rpm < clutch_out_rpm:
		idle_disengagement = (clutch_out_rpm - engine_rpm) / maxf(
			clutch_out_rpm - idle_floor_rpm,
			0.000001,
		)
	var clutch_disengagement := maxf(maxf(manual_clutch_pedal, shift_clutch), idle_disengagement)
	var target_engagement := 1.0 - clampf(clutch_disengagement, 0.0, 1.0)
	if clutch_two_phase_enabled and target_engagement > clutch_engagement:
		var remaining_dt := dt
		var bite_pt := clutch_bite_start if clutch_bite_enabled else 0.0
		if clutch_engagement < bite_pt and clutch_takeup_seconds > 0.0001:
			var takeup_rate := bite_pt / clutch_takeup_seconds
			var to_bite := minf(target_engagement, bite_pt) - clutch_engagement
			var step_takeup := takeup_rate * remaining_dt
			if step_takeup >= to_bite:
				clutch_engagement += to_bite
				remaining_dt = maxf(remaining_dt - to_bite / takeup_rate, 0.0)
			else:
				clutch_engagement += step_takeup
				remaining_dt = 0.0
		if remaining_dt > 0.0 and clutch_engagement < target_engagement:
			var engine_omega_now := engine_rpm * TAU / 60.0
			var slip_mag := absf(engine_omega_now - input_shaft_omega_rad_s)
			var slip_mult := 1.0 + clutch_slip_time_gain * clampf(slip_mag / 100.0, 0.0, 1.5)
			var fz_time := maxf(clutch_friction_zone_seconds * slip_mult, 0.001)
			var fz_span := maxf(1.0 - bite_pt, 0.01)
			clutch_engagement = move_toward(
				clutch_engagement,
				target_engagement,
				remaining_dt * fz_span / fz_time,
			)
	else:
		var actuation_time := clutch_release_seconds if target_engagement < clutch_engagement else clutch_reengage_seconds
		clutch_engagement = move_toward(clutch_engagement, target_engagement, dt / actuation_time)
	if shift_phase == "opening" and clutch_engagement <= 0.000001:
		clutch_engagement = 0.0
		current_gear = 0
		# Entrada a punto muerto durante el cambio: invalida la rueda libre
		# de forma explícita (plan §1); resolve_freewheel la mantiene a cero
		# mientras la marcha efectiva sea neutra.
		invalidate_freewheel()
		shift_phase = "synchronizing"
		# Wait in neutral before the normal synchronization starts.
		shift_phase_seconds = -_shift_damage_delay_seconds
	elif shift_phase == "closing":
		var closing_done := false
		if clutch_two_phase_enabled:
			var max_closing_s := clutch_takeup_seconds + clutch_friction_zone_seconds * (1.0 + 1.5 * clutch_slip_time_gain)
			closing_done = (
				(clutch_engagement >= 0.999 and target_engagement >= 0.999)
				or shift_phase_seconds >= max_closing_s
			)
		else:
			closing_done = shift_phase_seconds >= clutch_reengage_seconds
		if closing_done:
			reset_shift()

	clutch_torque_nm = 0.0


func _autoblip_command(
	driver_throttle: float,
	thermal_derating: float,
	carrier_omega: float,
	dt: float,
) -> float:
	autoblip_active = false
	autoblip_throttle = 0.0
	autoblip_target_rpm = 0.0
	if not downshift_rev_matching_enabled or not revmatch_downshift or shift_phase == "idle":
		return driver_throttle
	var target_omega := _ratio_for_gear(pending_gear) * final_drive_ratio * carrier_omega
	if target_omega <= 0.0:
		return driver_throttle
	autoblip_target_rpm = clampf(
		target_omega * 60.0 / TAU,
		idle_rpm,
		maxf(idle_rpm, maximum_rpm * downshift_target_rpm_fraction),
	)
	if clutch_engagement > 0.05 and shift_phase == "opening":
		return driver_throttle
	var error_rpm := autoblip_target_rpm - engine_rpm
	if error_rpm <= downshift_blip_tolerance_rpm:
		return driver_throttle
	var error_omega := error_rpm * TAU / 60.0
	var blip_response_s := (
		maxf(downshift_blip_response_seconds, throttle_tau_up_s)
		if throttle_response_enabled
		else downshift_blip_response_seconds
	)
	var desired_torque := maxf(engine_inertia_kg_m2, 0.000001) * error_omega / maxf(
		blip_response_s,
		dt,
	)
	var closed_torque := engine_torque_at_rpm(engine_rpm, 0.0, thermal_derating)
	var available_torque := engine_torque_at_rpm(engine_rpm, 1.0, thermal_derating) - closed_torque
	if available_torque <= 0.000001:
		return driver_throttle
	var desired_fill := clampf((desired_torque - closed_torque) / available_torque, 0.0, 1.0)
	if throttle_response_enabled and throttle_tau_up_s > 0.0001:
		var rpm_scale := clampf(
			throttle_rpm_reference / maxf(engine_rpm, 1.0),
			throttle_rpm_scale_min,
			throttle_rpm_scale_max,
		)
		var eff_tau_up := throttle_tau_up_s * rpm_scale
		var lead_cmd := desired_fill + (desired_fill - manifold_fill) * (eff_tau_up / maxf(blip_response_s, dt))
		autoblip_throttle = clampf(lead_cmd, 0.0, downshift_blip_torque_fraction)
	else:
		autoblip_throttle = clampf(
			desired_fill,
			0.0,
			downshift_blip_torque_fraction,
		)
	autoblip_active = autoblip_throttle > clampf(driver_throttle, 0.0, 1.0)
	return maxf(driver_throttle, autoblip_throttle)


func solve_rotation(
	delta: float,
	spins: Array[float],
	inertias: Array[float],
	tire_torques: Array[float],
	brakes: Array[float],
	spin_damping: Array[float] = [],
	chassis_omega_local: Vector3 = Vector3.ZERO,
) -> Dictionary:
	var h := maxf(delta, 0.000001)
	var ie := maxf(engine_inertia_kg_m2, 0.000001)
	var engine_omega := engine_rpm * TAU / 60.0
	var synchronizing := shift_phase == "synchronizing" and shift_phase_seconds >= 0.0 and pending_gear != 0
	var ratio := (_ratio_for_gear(pending_gear) if synchronizing else gear_ratio()) * final_drive_ratio
	var geared := current_gear != 0 and absf(ratio) > 0.000001
	# La rueda libre consume la decisión única del subpaso (resolve_freewheel
	# en advance con el acelerador del conductor): sin inferir acelerador a
	# partir del signo del par ni reevaluar aquí (plan §1).
	var connected := (geared or synchronizing) and not (freewheel_enabled and freewheel_active)
	if _ensure_rust_solver() != null:
		_sync_rust_config()
		_rust_inp53[0] = h
		for i in 4:
			_rust_inp53[1 + i] = spins[i]
			_rust_inp53[5 + i] = float(inertias[i])
			_rust_inp53[9 + i] = float(tire_torques[i])
			_rust_inp53[13 + i] = float(brakes[i])
			_rust_inp53[17 + i] = float(spin_damping[i]) if i < spin_damping.size() else 0.0
		_rust_inp53[21] = chassis_omega_local.x
		_rust_inp53[22] = chassis_omega_local.y
		_rust_inp53[23] = chassis_omega_local.z
		_rust_inp53[24] = engine_rpm
		_rust_inp53[25] = input_shaft_omega_rad_s
		_rust_inp53[26] = output_shaft_omega_rad_s
		_rust_inp53[27] = clutch_engagement
		_rust_inp53[28] = ratio
		_rust_inp53[29] = _ratio_for_gear(current_gear) if current_gear != 0 else 0.0
		_rust_inp53[30] = shift_phase_seconds
		_rust_inp53[31] = transmission_damage
		_rust_inp53[32] = clutch_damper_twist_rad
		_rust_inp53[33] = driveline_twist_rad
		_rust_inp53[34] = float(driveline_backlash_flank)
		_rust_inp53[35] = engine_mount_roll_rad
		_rust_inp53[36] = engine_mount_roll_omega_rad_s
		_rust_inp53[37] = engine_mount_pitch_rad
		_rust_inp53[38] = engine_mount_pitch_omega_rad_s
		_rust_inp53[39] = front_lsd_lock_twist_rad
		_rust_inp53[40] = rear_lsd_lock_twist_rad
		_rust_inp53[41] = front_lsd_filtered_torque_nm
		_rust_inp53[42] = rear_lsd_filtered_torque_nm
		_rust_inp53[43] = front_lsd_blend
		_rust_inp53[44] = rear_lsd_blend
		_rust_inp53[45] = _reaction_prev_engine_omega
		_rust_inp53[46] = _reaction_prev_input_omega
		_rust_inp53[47] = chassis_reaction_torque_local_nm.x
		_rust_inp53[48] = chassis_reaction_torque_local_nm.y
		_rust_inp53[49] = chassis_reaction_torque_local_nm.z
		_rust_inp53[50] = _mount_prev_chassis_omega_local.x
		_rust_inp53[51] = _mount_prev_chassis_omega_local.y
		_rust_inp53[52] = _mount_prev_chassis_omega_local.z
		var step_flags := 0
		if connected:
			step_flags |= (1 << 0)
		if synchronizing:
			step_flags |= (1 << 1)
		if current_gear != 0:
			step_flags |= (1 << 2)
		if pending_gear != 0:
			step_flags |= (1 << 3)
		if shift_phase == "synchronizing":
			step_flags |= (1 << 4)
		if _reaction_initialized:
			step_flags |= (1 << 5)
		if _mount_chassis_omega_initialized:
			step_flags |= (1 << 6)
		var out: PackedFloat64Array = _rust_solver.call("solve_rotation", _rust_inp53, step_flags)
		for i in 4:
			spins[i] = out[i]
			_rust_brake_work[i] = out[4 + i]
		engine_rpm = out[8]
		input_shaft_omega_rad_s = out[9]
		output_shaft_omega_rad_s = out[10]
		clutch_bite = out[11]
		clutch_torque_nm = out[12]
		clutch_slip_rad_s = out[13]
		clutch_slip_power_w = out[14]
		clutch_damper_twist_rad = out[15]
		clutch_damper_twist_deg = out[16]
		clutch_damper_torque_nm = out[17]
		clutch_damper_at_stop = out[18] > 0.5
		if driveline_compliance_enabled:
			driveline_twist_rad = out[19]
			driveline_backlash_flank = int(round(out[20]))
			driveline_in_backlash = out[21] > 0.5
			driveline_backlash_impact_rad_s = out[22]
			driveline_torque_nm = out[23]
			driveline_energy_j = out[24]
			driveline_dissipation_w = out[25]
		var shaft_torque_r := out[26]
		engine_mount_roll_rad = out[27]
		engine_mount_roll_omega_rad_s = out[28]
		engine_mount_pitch_rad = out[29]
		engine_mount_pitch_omega_rad_s = out[30]
		engine_roll_deg = out[31]
		engine_pitch_deg = out[32]
		chassis_reaction_torque_local_nm = Vector3(out[33], out[34], out[35])
		if out[36] > 0.5:
			current_gear = pending_gear
			shift_phase = "closing"
			shift_phase_seconds = 0.0
		last_front_diff_speed_rad_s = out[37]
		last_front_lsd_capacity_nm = out[38]
		last_front_lsd_torque_nm = out[39]
		last_front_lsd_saturation = out[40]
		front_lsd_filtered_torque_nm = out[41]
		last_front_lsd_filtered_torque_nm = out[41]
		front_lsd_blend = out[42]
		last_front_lsd_blend = out[42]
		front_lsd_lock_twist_rad = out[43]
		last_front_lsd_lock_twist_rad = out[43]
		last_rear_diff_speed_rad_s = out[44]
		last_rear_lsd_capacity_nm = out[45]
		last_rear_lsd_torque_nm = out[46]
		last_rear_lsd_saturation = out[47]
		rear_lsd_filtered_torque_nm = out[48]
		last_rear_lsd_filtered_torque_nm = out[48]
		rear_lsd_blend = out[49]
		last_rear_lsd_blend = out[49]
		rear_lsd_lock_twist_rad = out[50]
		last_rear_lsd_lock_twist_rad = out[50]
		var sel_b := 37 if front_torque_split >= 1.0 else 44
		last_diff_speed_rad_s = out[sel_b]
		last_lsd_capacity_nm = out[sel_b + 1]
		last_lsd_torque_nm = out[sel_b + 2]
		last_lsd_saturation = out[sel_b + 3]
		last_lsd_filtered_torque_nm = out[sel_b + 4]
		last_lsd_blend = out[sel_b + 5]
		last_lsd_lock_twist_rad = out[sel_b + 6]
		_reaction_prev_engine_omega = out[51]
		_reaction_prev_input_omega = out[52]
		_reaction_initialized = true
		_mount_prev_chassis_omega_local = chassis_omega_local
		_mount_chassis_omega_initialized = true
		_rust_weights[0] = front_torque_split * 0.5
		_rust_weights[1] = front_torque_split * 0.5
		_rust_weights[2] = (1.0 - front_torque_split) * 0.5
		_rust_weights[3] = (1.0 - front_torque_split) * 0.5
		var overrev_r := _evaluate_mechanical_overrev_and_missgear(
			h,
			spins,
			_rust_weights,
			ratio,
			connected,
			synchronizing,
			out[53],
			shaft_torque_r,
		)
		return {
			"brake_work_j": _rust_brake_work,
			"shaft_torque_nm": shaft_torque_r,
			"chassis_reaction_torque_local_nm": chassis_reaction_torque_local_nm,
			"engine_roll_deg": engine_roll_deg,
			"engine_pitch_deg": engine_pitch_deg,
			"engine_overrev_damage": float(overrev_r["engine_overrev_damage"]),
			"transmission_overrev_damage": float(overrev_r["transmission_overrev_damage"]),
			"missgear_active": missgear_active,
			"missgear_intensity": missgear_intensity,
		}
	var use_clutch_damper := clutch_damper_enabled and connected and not synchronizing
	var shaft_inertia := clutch_damper_disc_inertia_kg_m2 if clutch_damper_enabled else gearbox_input_inertia_kg_m2
	var weights: Array[float] = [
		front_torque_split * 0.5,
		front_torque_split * 0.5,
		(1.0 - front_torque_split) * 0.5,
		(1.0 - front_torque_split) * 0.5,
	]
	var inverse: Array[float] = []
	var brake_impulses: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var brake_work: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var carrier_inverse := 0.0
	var primary_reflected := (
		gearbox_input_inertia_kg_m2 * ratio * ratio
		if (use_clutch_damper and driveline_compliance_enabled)
		else 0.0
	)
	var output_inverse := 1.0 / maxf(output_shaft_inertia_kg_m2 + primary_reflected, 0.000001)
	for i in 4:
		var i_wheel := maxf(float(inertias[i]), 0.000001)
		var inv_wheel := 1.0 / i_wheel
		inverse.append(inv_wheel)
		var c_spin := maxf(float(spin_damping[i]), 0.0) if i < spin_damping.size() else 0.0
		var tire_damping_scale := 1.0 / (1.0 + h * c_spin * inv_wheel)
		spins[i] -= h * tire_torques[i] * inv_wheel * tire_damping_scale
		carrier_inverse += weights[i] * weights[i] * inv_wheel

	# Soporte de motor bidireccional de 2.º orden (eje de cigüeñal y cabeceo de transeje).
	var mount_second_order := chassis_reaction_enabled and chassis_reaction_mount_model == "second_order"
	var mount_is_transverse := chassis_reaction_orientation == "transverse"
	var mount_roll_active := mount_second_order and not mount_is_transverse
	var mount_pitch_active := mount_second_order and (mount_is_transverse or chassis_reaction_transaxle_pitch_fraction > 0.0)
	var mount_roll_inv := 1.0 / maxf(chassis_reaction_roll_inertia_kg_m2, 0.01)
	var mount_pitch_inv := 1.0 / maxf(chassis_reaction_pitch_inertia_kg_m2, 0.01)
	var mount_crank_inv := (mount_pitch_inv if mount_is_transverse else mount_roll_inv) if mount_second_order else 0.0
	var mount_omega_nat := TAU * chassis_reaction_mount_frequency_hz
	var mount_k_roll := chassis_reaction_roll_inertia_kg_m2 * mount_omega_nat * mount_omega_nat
	var mount_c_roll := 2.0 * chassis_reaction_mount_damping_ratio * sqrt(mount_k_roll * chassis_reaction_roll_inertia_kg_m2)
	var mount_k_pitch := chassis_reaction_pitch_inertia_kg_m2 * mount_omega_nat * mount_omega_nat
	var mount_c_pitch := 2.0 * chassis_reaction_mount_damping_ratio * sqrt(mount_k_pitch * chassis_reaction_pitch_inertia_kg_m2)
	var mount_snubber_rad := deg_to_rad(chassis_reaction_snubber_angle_deg)
	var ds_kappa_z := (
		chassis_reaction_driveshaft_roll_fraction / maxf(final_drive_ratio, 0.0001)
		if (mount_roll_active and chassis_reaction_driveshaft_roll_fraction > 0.0)
		else 0.0
	)
	var tx_kappa_x := chassis_reaction_transaxle_pitch_fraction if mount_pitch_active else 0.0
	if mount_second_order:
		# Acoplamiento inercial chasis -> soporte de motor.
		if _mount_chassis_omega_initialized:
			var ch_alpha := (chassis_omega_local - _mount_prev_chassis_omega_local) / h
			if mount_roll_active:
				engine_mount_roll_omega_rad_s -= clampf(ch_alpha.z, -50.0, 50.0) * h
			if mount_pitch_active:
				engine_mount_pitch_omega_rad_s -= clampf(ch_alpha.x, -50.0, 50.0) * h
		# Reacción de combustión/arrastre del paso advance() sobre el bloque.
		if _reaction_initialized:
			var max_adv_imp := maxf(peak_torque_nm, 100.0) * 2.5 * h
			var j_adv := clampf(ie * (engine_omega - _reaction_prev_engine_omega), -max_adv_imp, max_adv_imp)
			if mount_is_transverse:
				engine_mount_pitch_omega_rad_s -= chassis_reaction_crank_sign * j_adv * mount_pitch_inv
			else:
				engine_mount_roll_omega_rad_s -= chassis_reaction_crank_sign * j_adv * mount_roll_inv

	var gear_effective_inverse := 1.0 / shaft_inertia + ratio * ratio * (
		output_inverse if driveline_compliance_enabled else carrier_inverse
	) + mount_crank_inv
	var spring_inverse := (
		output_inverse
		+ carrier_inverse
		+ ds_kappa_z * ds_kappa_z * mount_roll_inv
		+ tx_kappa_x * tx_kappa_x * mount_pitch_inv
	)
	var implicit_damping := torsional_damping_nms_per_rad + h * torsional_stiffness_nm_per_rad
	var spring_denominator := 1.0 + h * implicit_damping * spring_inverse
	var progressive_contact_enabled := driveline_contact_soft_zone_rad > 0.0
	var contact_zeta := 0.0
	var end_stop_delta := 0.35
	if progressive_contact_enabled:
		var ln_e := log(clampf(driveline_contact_restitution, 0.05, 0.99))
		contact_zeta = -ln_e / sqrt(PI * PI + ln_e * ln_e)
		end_stop_delta = _driveline_end_stop_delta()
	var spring_j_eff := 1.0 / maxf(spring_inverse, 0.000001)
	var mech_cfg := mechanical_damage_config
	var min_clutch_fac := clampf(float(mech_cfg.get("minimum_clutch_capacity_factor", 0.70)), 0.1, 1.0)
	var clutch_damage_fac := lerpf(1.0, min_clutch_fac, transmission_damage)
	var min_sync_fac := clampf(float(mech_cfg.get("minimum_synchronizer_factor", 0.35)), 0.05, 1.0)
	var sync_damage_fac := lerpf(1.0, min_sync_fac, transmission_damage)
	var damage_backlash := transmission_damage * maxf(float(mech_cfg.get("maximum_damage_backlash_rad", 0.05)), 0.0)
	var effective_backlash_rad := driveline_backlash_rad + (damage_backlash if driveline_compliance_enabled else 0.0)
	var backlash_half_rad := 0.5 * effective_backlash_rad
	var lash_damping := torsional_damping_nms_per_rad * driveline_backlash_damping_ratio
	var lash_denominator := 1.0 + h * lash_damping * spring_inverse
	var initial_carrier := 0.0
	for i in 4:
		initial_carrier += weights[i] * spins[i]
	var initial_mount_offset := (
		(chassis_reaction_crank_sign * ds_kappa_z * engine_mount_roll_omega_rad_s)
		- (tx_kappa_x * engine_mount_pitch_omega_rad_s)
	)
	var initial_twist_speed := output_shaft_omega_rad_s - initial_carrier + initial_mount_offset
	var spring_impulse := 0.0
	var clutch_impulse := 0.0
	var gear_impulse := 0.0
	var damper_spring_impulse := 0.0
	var damper_hyst_impulse := 0.0
	var mount_roll_impulse := 0.0
	var mount_pitch_impulse := 0.0
	var clutch_work := 0.0
	var smooth_clutch := _evaluate_clutch_bite(clutch_engagement)
	clutch_bite = smooth_clutch
	var clutch_base_capacity := clutch_max_torque_nm * clutch_damage_fac * smooth_clutch * h
	var use_clutch_mu_curve := absf(clutch_mu_static_ratio - 1.0) > 0.000001
	var nominal_sync_time := maxf(shift_time_seconds + gear_inertia_shift_seconds, 0.02)
	var sync_overtime := clampf(shift_phase_seconds / nominal_sync_time, 1.0, 4.0) if synchronizing else 1.0
	var effective_sync_cap := synchronizer_capacity_nm * sync_damage_fac * sync_overtime * h
	var cd_hyst_cap := clutch_damper_hysteresis_nm * h
	var cd_t0_vec := _evaluate_clutch_damper_spring(clutch_damper_twist_rad) if use_clutch_damper else Vector3.ZERO
	# Diferencial por eje (plan §4): cada eje usa sus parámetros propios; el
	# eje no motriz (reparto ~0) queda abierto y open genera bloqueo cero.
	var axle_left: Array[int] = [0, 2]
	var axle_shares: Array[float] = [front_torque_split, 1.0 - front_torque_split]
	var axle_types: Array[String] = [front_differential_type, rear_differential_type]
	var axle_preloads: Array[float] = [front_differential_preload_nm, rear_differential_preload_nm]
	var axle_power_ratios: Array[float] = [front_differential_power_ratio, rear_differential_power_ratio]
	var axle_coast_ratios: Array[float] = [front_differential_coast_ratio, rear_differential_coast_ratio]
	var axle_power_ramps: Array[float] = [
		front_differential_power_ramp_angle_deg, rear_differential_power_ramp_angle_deg
	]
	var axle_coast_ramps: Array[float] = [
		front_differential_coast_ramp_angle_deg, rear_differential_coast_ramp_angle_deg
	]
	var axle_clutches: Array[float] = [front_differential_clutches, rear_differential_clutches]
	var axle_gains: Array[float] = [front_differential_ramp_gain, rear_differential_ramp_gain]
	var axle_lock_stiff: Array[float] = [
		front_differential_lock_stiffness_nm_per_rad, rear_differential_lock_stiffness_nm_per_rad
	]
	var axle_lock_zeta: Array[float] = [
		front_differential_lock_damping_ratio, rear_differential_lock_damping_ratio
	]
	var axle_press_tau: Array[float] = [
		front_differential_pressure_tau_s, rear_differential_pressure_tau_s
	]
	var axle_rel_tau: Array[float] = [
		front_differential_release_tau_s, rear_differential_release_tau_s
	]
	var axle_blend_frac: Array[float] = [
		front_differential_blend_band_fraction, rear_differential_blend_band_fraction
	]
	var axle_blend_nm: Array[float] = [
		front_differential_blend_band_nm, rear_differential_blend_band_nm
	]
	var axle_static_fac: Array[float] = [
		front_differential_static_friction_factor, rear_differential_static_friction_factor
	]
	var axle_slip_ref: Array[float] = [
		front_differential_slip_reference_rad_s, rear_differential_slip_reference_rad_s
	]
	var axle_lock_twists: Array[float] = [front_lsd_lock_twist_rad, rear_lsd_lock_twist_rad]
	var axle_filt_torques: Array[float] = [front_lsd_filtered_torque_nm, rear_lsd_filtered_torque_nm]
	var axle_blends: Array[float] = [front_lsd_blend, rear_lsd_blend]
	var axle_pair_invs_pure: Array[float] = [
		inverse[0] + inverse[1],
		inverse[2] + inverse[3],
	]
	var axle_pair_invs: Array[float] = [
		axle_pair_invs_pure[0] + h * differential_slip_transition_threshold_rad_s * 0.35,
		axle_pair_invs_pure[1] + h * differential_slip_transition_threshold_rad_s * 0.35,
	]
	var axle_lock_c_eff: Array[float] = [0.0, 0.0]
	var axle_lock_denom: Array[float] = [1.0, 1.0]
	var axle_use_filtered: Array[bool] = [false, false]
	var axle_precomp_base_cap_nm: Array[float] = [0.0, 0.0]
	var ref_ratio_abs := absf(ratio)
	if ref_ratio_abs <= 0.0001:
		ref_ratio_abs = (absf(gear_ratios[0]) * final_drive_ratio) if not gear_ratios.is_empty() else final_drive_ratio
	for axle in 2:
		if axle_lock_stiff[axle] > 0.0:
			var k_l := axle_lock_stiff[axle]
			var inv_p := axle_pair_invs_pure[axle]
			var c_l := 2.0 * axle_lock_zeta[axle] * sqrt(k_l / maxf(inv_p, 0.000001))
			var c_l_eff := c_l + h * k_l
			axle_lock_c_eff[axle] = c_l_eff
			axle_lock_denom[axle] = 1.0 + h * c_l_eff * inv_p
		var use_filt := axle_press_tau[axle] > 0.0 or axle_rel_tau[axle] > 0.0
		axle_use_filtered[axle] = use_filt
		if (
			use_filt
			and axle_shares[axle] > DIFFERENTIAL_DRIVE_EPS
			and axle_types[axle] in DIFFERENTIAL_FRICTION_TYPES
		):
			var left_p := axle_left[axle]
			var ax_in := axle_filt_torques[axle]
			var ax_car := 0.5 * (spins[left_p] + spins[left_p + 1])
			var blend_p := 0.5
			if axle_blend_frac[axle] > 0.0 or axle_blend_nm[axle] > 0.0:
				var dir_s := (1.0 if ax_car >= 0.0 else -1.0) if absf(ax_car) > 0.5 else signf(ax_in)
				var signed_t := ax_in * dir_s
				var band := maxf(
					maxf(axle_blend_nm[axle], axle_blend_frac[axle] * peak_torque_nm * ref_ratio_abs * axle_shares[axle]),
					1.0,
				)
				var xb := clampf(signed_t / band, -1.0, 1.0)
				blend_p = 0.5 + 0.5 * xb * (1.5 - 0.5 * xb * xb)
			else:
				var dp := ax_in * (ax_car if absf(ax_car) > 0.5 else signf(ax_in))
				blend_p = clampf(0.5 + 0.5 * tanh(dp / 150.0), 0.0, 1.0)
			axle_blends[axle] = blend_p
			var r_deg := lerpf(axle_coast_ramps[axle], axle_power_ramps[axle], blend_p)
			var mu_p := lerpf(axle_coast_ratios[axle], axle_power_ratios[axle], blend_p)
			var cot_r := 0.0 if r_deg >= 90.0 else 1.0 / tan(deg_to_rad(maxf(r_deg, 15.0)))
			var r_cap := absf(ax_in) * cot_r * maxf(axle_clutches[axle], 1.0) * maxf(mu_p, 0.0) * maxf(axle_gains[axle], 0.0)
			axle_precomp_base_cap_nm[axle] = maxf(axle_preloads[axle], 0.0) + maxf(r_cap, 0.0)
	var lsd_impulses: Array[float] = [0.0, 0.0]
	var axle_speeds: Array[float] = [0.0, 0.0]
	var axle_capacities: Array[float] = [0.0, 0.0]
	var axle_torques: Array[float] = [0.0, 0.0]
	var axle_saturations: Array[float] = [0.0, 0.0]

	for iteration in 48:
		if connected:
			var carrier := 0.0
			for i in 4:
				carrier += weights[i] * spins[i]
			var gear_output := output_shaft_omega_rad_s if driveline_compliance_enabled else carrier
			var housing_crank_omega := (
				(
					chassis_reaction_crank_sign * engine_mount_pitch_omega_rad_s
					if mount_is_transverse
					else chassis_reaction_crank_sign * engine_mount_roll_omega_rad_s
				)
				if mount_second_order
				else 0.0
			)
			if use_clutch_damper:
				var v_cd := input_shaft_omega_rad_s - housing_crank_omega - ratio * gear_output
				var theta_cd_pred := clutch_damper_twist_rad + h * v_cd
				var cd_pred_vec := _evaluate_clutch_damper_spring(theta_cd_pred)
				var k_cd_eff := cd_t0_vec.y
				if absf(v_cd) > 0.00001:
					var k_cd_sec := (cd_pred_vec.x - cd_t0_vec.x) / (h * v_cd)
					k_cd_eff = maxf(k_cd_eff, k_cd_sec)
				var c_cd_eff := clutch_damper_viscous_nms_per_rad + h * k_cd_eff
				var cd_denom := 1.0 + h * c_cd_eff * gear_effective_inverse
				var d_cd := -(damper_spring_impulse + h * cd_t0_vec.x + h * c_cd_eff * v_cd) / cd_denom
				damper_spring_impulse += d_cd
				input_shaft_omega_rad_s += d_cd / shaft_inertia
				if driveline_compliance_enabled:
					output_shaft_omega_rad_s -= ratio * d_cd * output_inverse
				else:
					for i in 4:
						spins[i] -= ratio * weights[i] * d_cd * inverse[i]
				if mount_second_order:
					if mount_is_transverse:
						engine_mount_pitch_omega_rad_s -= chassis_reaction_crank_sign * d_cd * mount_pitch_inv
					else:
						engine_mount_roll_omega_rad_s -= chassis_reaction_crank_sign * d_cd * mount_roll_inv
				if cd_hyst_cap > 0.0:
					var gear_out_h := output_shaft_omega_rad_s if driveline_compliance_enabled else (
						weights[0] * spins[0] + weights[1] * spins[1] + weights[2] * spins[2] + weights[3] * spins[3]
					)
					var housing_h := (
						(
							chassis_reaction_crank_sign * engine_mount_pitch_omega_rad_s
							if mount_is_transverse
							else chassis_reaction_crank_sign * engine_mount_roll_omega_rad_s
						)
						if mount_second_order
						else 0.0
					)
					var v_cd_h := input_shaft_omega_rad_s - housing_h - ratio * gear_out_h
					var next_hyst := clampf(
						damper_hyst_impulse - v_cd_h / gear_effective_inverse,
						-cd_hyst_cap,
						cd_hyst_cap,
					)
					var d_hyst := next_hyst - damper_hyst_impulse
					damper_hyst_impulse = next_hyst
					input_shaft_omega_rad_s += d_hyst / shaft_inertia
					if driveline_compliance_enabled:
						output_shaft_omega_rad_s -= ratio * d_hyst * output_inverse
					else:
						for i in 4:
							spins[i] -= ratio * weights[i] * d_hyst * inverse[i]
					if mount_second_order:
						if mount_is_transverse:
							engine_mount_pitch_omega_rad_s -= chassis_reaction_crank_sign * d_hyst * mount_pitch_inv
						else:
							engine_mount_roll_omega_rad_s -= chassis_reaction_crank_sign * d_hyst * mount_roll_inv
				gear_impulse = damper_spring_impulse + damper_hyst_impulse
			else:
				var impulse := -(input_shaft_omega_rad_s - housing_crank_omega - ratio * gear_output) / gear_effective_inverse
				if synchronizing:
					var next_gear_impulse := clampf(
						gear_impulse + impulse,
						-effective_sync_cap,
						effective_sync_cap,
					)
					impulse = next_gear_impulse - gear_impulse
				input_shaft_omega_rad_s += impulse / shaft_inertia
				gear_impulse += impulse
				if driveline_compliance_enabled:
					output_shaft_omega_rad_s -= ratio * impulse * output_inverse
				else:
					for i in 4:
						spins[i] -= ratio * weights[i] * impulse * inverse[i]
				if mount_second_order:
					if mount_is_transverse:
						engine_mount_pitch_omega_rad_s -= chassis_reaction_crank_sign * impulse * mount_pitch_inv
					else:
						engine_mount_roll_omega_rad_s -= chassis_reaction_crank_sign * impulse * mount_roll_inv
		if driveline_compliance_enabled:
			var carrier_speed := 0.0
			for i in 4:
				carrier_speed += weights[i] * spins[i]
			var mount_offset := (
				(chassis_reaction_crank_sign * ds_kappa_z * engine_mount_roll_omega_rad_s)
				- (tx_kappa_x * engine_mount_pitch_omega_rad_s)
			)
			var relative_speed := output_shaft_omega_rad_s - carrier_speed + mount_offset
			var spring_delta := 0.0
			if progressive_contact_enabled:
				var theta_pred := driveline_twist_rad + h * relative_speed
				if theta_pred > backlash_half_rad:
					var delta_pred := theta_pred - backlash_half_rad
					var f_pred_v := _evaluate_driveline_flank(delta_pred, end_stop_delta)
					var pen_frac := clampf(delta_pred / driveline_contact_soft_zone_rad, 0.0, 1.0)
					var c_active := lerpf(lash_damping, torsional_damping_nms_per_rad, pen_frac)
					if relative_speed > 0.0 and pen_frac < 1.0:
						var bell := 4.0 * pen_frac * (1.0 - pen_frac)
						c_active += 2.0 * contact_zeta * sqrt(maxf(f_pred_v.y, 1.0) * spring_j_eff) * bell
					var raw_delta := 0.0
					if driveline_twist_rad > backlash_half_rad:
						var delta0 := driveline_twist_rad - backlash_half_rad
						var f0_v := _evaluate_driveline_flank(delta0, end_stop_delta)
						var d_del := delta_pred - delta0
						var k_sec := (f_pred_v.x - f0_v.x) / d_del if absf(d_del) > 0.000001 else f0_v.y
						var c_imp := c_active + h * k_sec
						var denom := 1.0 + h * c_imp * spring_inverse
						raw_delta = -(spring_impulse + h * f0_v.x + h * c_imp * relative_speed) / denom
					else:
						var contact_frac := clampf(delta_pred / maxf(h * relative_speed, 0.000001), 0.0, 1.0)
						var k_sec := f_pred_v.x / maxf(delta_pred, 0.000001)
						var c_imp := c_active * contact_frac + h * k_sec
						var denom := 1.0 + h * c_imp * spring_inverse
						raw_delta = -(
							spring_impulse
							+ h * k_sec * (driveline_twist_rad - backlash_half_rad)
							+ h * c_imp * relative_speed
						) / denom
					if backlash_half_rad > 0.0:
						var next_spring := minf(spring_impulse + raw_delta, 0.0)
						spring_delta = next_spring - spring_impulse
					else:
						spring_delta = raw_delta
				elif theta_pred < -backlash_half_rad:
					var delta_pred := -theta_pred - backlash_half_rad
					var f_pred_v := _evaluate_driveline_flank(delta_pred, end_stop_delta)
					var pen_frac := clampf(delta_pred / driveline_contact_soft_zone_rad, 0.0, 1.0)
					var c_active := lerpf(lash_damping, torsional_damping_nms_per_rad, pen_frac)
					if relative_speed < 0.0 and pen_frac < 1.0:
						var bell := 4.0 * pen_frac * (1.0 - pen_frac)
						c_active += 2.0 * contact_zeta * sqrt(maxf(f_pred_v.y, 1.0) * spring_j_eff) * bell
					var raw_delta := 0.0
					if driveline_twist_rad < -backlash_half_rad:
						var delta0 := -driveline_twist_rad - backlash_half_rad
						var f0_v := _evaluate_driveline_flank(delta0, end_stop_delta)
						var d_del := delta_pred - delta0
						var k_sec := (f_pred_v.x - f0_v.x) / d_del if absf(d_del) > 0.000001 else f0_v.y
						var c_imp := c_active + h * k_sec
						var denom := 1.0 + h * c_imp * spring_inverse
						raw_delta = -(spring_impulse - h * f0_v.x + h * c_imp * relative_speed) / denom
					else:
						var contact_frac := clampf(delta_pred / maxf(-h * relative_speed, 0.000001), 0.0, 1.0)
						var k_sec := f_pred_v.x / maxf(delta_pred, 0.000001)
						var c_imp := c_active * contact_frac + h * k_sec
						var denom := 1.0 + h * c_imp * spring_inverse
						raw_delta = -(
							spring_impulse
							+ h * k_sec * (driveline_twist_rad + backlash_half_rad)
							+ h * c_imp * relative_speed
						) / denom
					if backlash_half_rad > 0.0:
						var next_spring := maxf(spring_impulse + raw_delta, 0.0)
						spring_delta = next_spring - spring_impulse
					else:
						spring_delta = raw_delta
				else:
					spring_delta = -(
						spring_impulse + h * lash_damping * relative_speed
					) / lash_denominator
			elif backlash_half_rad > 0.0:
				var theta_pred := driveline_twist_rad + h * relative_speed
				if theta_pred > backlash_half_rad:
					var raw_delta := -(
						spring_impulse
						+ h * torsional_stiffness_nm_per_rad * (driveline_twist_rad - backlash_half_rad)
						+ h * implicit_damping * relative_speed
					) / spring_denominator
					var next_spring := minf(spring_impulse + raw_delta, 0.0)
					spring_delta = next_spring - spring_impulse
				elif theta_pred < -backlash_half_rad:
					var raw_delta := -(
						spring_impulse
						+ h * torsional_stiffness_nm_per_rad * (driveline_twist_rad + backlash_half_rad)
						+ h * implicit_damping * relative_speed
					) / spring_denominator
					var next_spring := maxf(spring_impulse + raw_delta, 0.0)
					spring_delta = next_spring - spring_impulse
				else:
					spring_delta = -(
						spring_impulse + h * lash_damping * relative_speed
					) / lash_denominator
			else:
				spring_delta = -(
					spring_impulse + h * torsional_stiffness_nm_per_rad * driveline_twist_rad
					+ h * implicit_damping * relative_speed
				) / spring_denominator
			spring_impulse += spring_delta
			output_shaft_omega_rad_s += spring_delta * output_inverse
			for i in 4:
				spins[i] -= weights[i] * spring_delta * inverse[i]
			if ds_kappa_z > 0.0:
				engine_mount_roll_omega_rad_s += chassis_reaction_crank_sign * ds_kappa_z * spring_delta * mount_roll_inv
			if tx_kappa_x > 0.0:
				engine_mount_pitch_omega_rad_s -= tx_kappa_x * spring_delta * mount_pitch_inv
		var slip := engine_omega - input_shaft_omega_rad_s
		var clutch_capacity := clutch_base_capacity
		if use_clutch_mu_curve:
			var mu_fac := (
				1.0 + (clutch_mu_static_ratio - 1.0) * exp(-absf(slip) / clutch_static_slip_rad_s)
			) / clutch_mu_static_ratio
			clutch_capacity = clutch_base_capacity * mu_fac
		var next_clutch := clampf(
			clutch_impulse + slip / (1.0 / ie + 1.0 / shaft_inertia),
			-clutch_capacity,
			clutch_capacity,
		)
		var clutch_delta := next_clutch - clutch_impulse
		engine_omega -= clutch_delta / ie
		input_shaft_omega_rad_s += clutch_delta / shaft_inertia
		clutch_work += clutch_delta * (slip + engine_omega - input_shaft_omega_rad_s) * 0.5
		clutch_impulse = next_clutch

		if mount_roll_active:
			var roll_pred := engine_mount_roll_rad + h * engine_mount_roll_omega_rad_s
			var mr0 := _evaluate_mount_spring(engine_mount_roll_rad, mount_k_roll, mount_snubber_rad, chassis_reaction_snubber_stiffness_factor)
			var mr_pred := _evaluate_mount_spring(roll_pred, mount_k_roll, mount_snubber_rad, chassis_reaction_snubber_stiffness_factor)
			var k_mr := mr0.y
			if absf(engine_mount_roll_omega_rad_s) > 0.00001:
				k_mr = maxf(k_mr, (mr_pred.x - mr0.x) / (h * engine_mount_roll_omega_rad_s))
			var c_mr_eff := mount_c_roll + h * k_mr
			var mr_denom := 1.0 + h * c_mr_eff * mount_roll_inv
			var d_mr := -(mount_roll_impulse + h * mr0.x + h * c_mr_eff * engine_mount_roll_omega_rad_s) / mr_denom
			mount_roll_impulse += d_mr
			engine_mount_roll_omega_rad_s += d_mr * mount_roll_inv
		if mount_pitch_active:
			var pitch_pred := engine_mount_pitch_rad + h * engine_mount_pitch_omega_rad_s
			var mp0 := _evaluate_mount_spring(engine_mount_pitch_rad, mount_k_pitch, mount_snubber_rad, chassis_reaction_snubber_stiffness_factor)
			var mp_pred := _evaluate_mount_spring(pitch_pred, mount_k_pitch, mount_snubber_rad, chassis_reaction_snubber_stiffness_factor)
			var k_mp := mp0.y
			if absf(engine_mount_pitch_omega_rad_s) > 0.00001:
				k_mp = maxf(k_mp, (mp_pred.x - mp0.x) / (h * engine_mount_pitch_omega_rad_s))
			var c_mp_eff := mount_c_pitch + h * k_mp
			var mp_denom := 1.0 + h * c_mp_eff * mount_pitch_inv
			var d_mp := -(mount_pitch_impulse + h * mp0.x + h * c_mp_eff * engine_mount_pitch_omega_rad_s) / mp_denom
			mount_pitch_impulse += d_mp
			engine_mount_pitch_omega_rad_s += d_mp * mount_pitch_inv

		var transmitted := (
			-spring_impulse / h
			if driveline_compliance_enabled
			else (-ratio * gear_impulse / h if connected else 0.0)
		)
		for axle in 2:
			# Eje no motriz u open: bloqueo cero. spool/unknown son
			# inalcanzables (la validación los rechaza) y se tratan como open.
			if (
				axle_shares[axle] <= DIFFERENTIAL_DRIVE_EPS
				or not axle_types[axle] in DIFFERENTIAL_FRICTION_TYPES
			):
				continue
			var left := axle_left[axle]
			var diff_speed := spins[left] - spins[left + 1]
			var base_cap_nm := 0.0
			if axle_use_filtered[axle]:
				base_cap_nm = axle_precomp_base_cap_nm[axle]
			else:
				var axle_input := transmitted * axle_shares[axle]
				var axle_carrier := 0.5 * (spins[left] + spins[left + 1])
				var power_blend := 0.5
				if axle_blend_frac[axle] > 0.0 or axle_blend_nm[axle] > 0.0:
					var dir_s := (1.0 if axle_carrier >= 0.0 else -1.0) if absf(axle_carrier) > 0.5 else signf(axle_input)
					var signed_t := axle_input * dir_s
					var band := maxf(
						maxf(axle_blend_nm[axle], axle_blend_frac[axle] * peak_torque_nm * ref_ratio_abs * axle_shares[axle]),
						1.0,
					)
					var xb := clampf(signed_t / band, -1.0, 1.0)
					power_blend = 0.5 + 0.5 * xb * (1.5 - 0.5 * xb * xb)
				else:
					var driving_power := axle_input * (
						axle_carrier if absf(axle_carrier) > 0.5 else signf(axle_input)
					)
					power_blend = clampf(0.5 + 0.5 * tanh(driving_power / 150.0), 0.0, 1.0)
				axle_blends[axle] = power_blend
				var ramp_deg := lerpf(
					axle_coast_ramps[axle],
					axle_power_ramps[axle],
					power_blend,
				)
				var friction_mu := lerpf(
					axle_coast_ratios[axle], axle_power_ratios[axle], power_blend
				)
				var cot_ramp := 0.0 if ramp_deg >= 90.0 else 1.0 / tan(deg_to_rad(maxf(ramp_deg, 15.0)))
				var ramp_capacity := absf(axle_input) * cot_ramp * maxf(axle_clutches[axle], 1.0) * maxf(
					friction_mu,
					0.0,
				) * maxf(axle_gains[axle], 0.0)
				base_cap_nm = maxf(axle_preloads[axle], 0.0) + maxf(ramp_capacity, 0.0)
			var mu_slip_scale := 1.0
			if absf(axle_static_fac[axle] - 1.0) > 0.000001:
				mu_slip_scale = lerpf(
					axle_static_fac[axle],
					1.0,
					tanh(absf(diff_speed) / axle_slip_ref[axle]),
				)
			var lsd_capacity := base_cap_nm * mu_slip_scale * h
			var next_lsd := 0.0
			if axle_lock_stiff[axle] > 0.0:
				var raw_lsd_d := (
					h * axle_lock_stiff[axle] * axle_lock_twists[axle]
					+ h * axle_lock_c_eff[axle] * diff_speed
					- lsd_impulses[axle]
				) / axle_lock_denom[axle]
				next_lsd = clampf(
					lsd_impulses[axle] + raw_lsd_d,
					-lsd_capacity,
					lsd_capacity,
				)
			else:
				next_lsd = clampf(
					lsd_impulses[axle] + diff_speed / axle_pair_invs[axle],
					-lsd_capacity,
					lsd_capacity,
				)
			var lsd_delta := next_lsd - lsd_impulses[axle]
			spins[left] -= lsd_delta * inverse[left]
			spins[left + 1] += lsd_delta * inverse[left + 1]
			lsd_impulses[axle] = next_lsd
			axle_speeds[axle] = diff_speed
			axle_capacities[axle] = lsd_capacity / maxf(h, 0.000001)
			axle_torques[axle] = next_lsd / maxf(h, 0.000001)
			if lsd_capacity > 0.0:
				axle_saturations[axle] = clampf(absf(next_lsd) / maxf(lsd_capacity, 0.000001), 0.0, 1.0)
			else:
				axle_saturations[axle] = 0.0

		for i in 4:
			var before := spins[i]
			var capacity := absf(brakes[i]) * h
			var next_brake := clampf(brake_impulses[i] - before / inverse[i], -capacity, capacity)
			var brake_delta := next_brake - brake_impulses[i]
			spins[i] += brake_delta * inverse[i]
			brake_work[i] -= brake_delta * (before + spins[i]) * 0.5
			brake_impulses[i] = next_brake

	# Actualizar estados de torsión plástica y par filtrado del LSD por eje.
	var final_transmitted := (
		-spring_impulse / h
		if driveline_compliance_enabled
		else (-ratio * gear_impulse / h if connected else 0.0)
	)
	for axle in 2:
		if (
			axle_shares[axle] <= DIFFERENTIAL_DRIVE_EPS
			or not axle_types[axle] in DIFFERENTIAL_FRICTION_TYPES
		):
			axle_lock_twists[axle] = 0.0
			axle_filt_torques[axle] = 0.0
			axle_blends[axle] = 0.5
			continue
		var left := axle_left[axle]
		if axle_lock_stiff[axle] > 0.0:
			var final_diff := spins[left] - spins[left + 1]
			var next_twist := axle_lock_twists[axle] + h * final_diff
			var cap_nm := axle_capacities[axle]
			if cap_nm > 0.0:
				var max_tw := cap_nm / axle_lock_stiff[axle]
				next_twist = clampf(next_twist, -max_tw, max_tw)
			else:
				next_twist = 0.0
			axle_lock_twists[axle] = next_twist
		else:
			axle_lock_twists[axle] = 0.0
		var t_ax := final_transmitted * axle_shares[axle]
		if axle_use_filtered[axle]:
			var tau_f := axle_press_tau[axle] if absf(t_ax) > absf(axle_filt_torques[axle]) else axle_rel_tau[axle]
			if tau_f > 0.0001:
				axle_filt_torques[axle] += (t_ax - axle_filt_torques[axle]) * (1.0 - exp(-h / tau_f))
			else:
				axle_filt_torques[axle] = t_ax
		else:
			axle_filt_torques[axle] = t_ax
	front_lsd_lock_twist_rad = axle_lock_twists[0]
	rear_lsd_lock_twist_rad = axle_lock_twists[1]
	front_lsd_filtered_torque_nm = axle_filt_torques[0]
	rear_lsd_filtered_torque_nm = axle_filt_torques[1]
	front_lsd_blend = axle_blends[0]
	rear_lsd_blend = axle_blends[1]

	last_front_diff_speed_rad_s = axle_speeds[0]
	last_front_lsd_capacity_nm = axle_capacities[0]
	last_front_lsd_torque_nm = axle_torques[0]
	last_front_lsd_saturation = axle_saturations[0]
	last_front_lsd_filtered_torque_nm = front_lsd_filtered_torque_nm
	last_front_lsd_blend = front_lsd_blend
	last_front_lsd_lock_twist_rad = front_lsd_lock_twist_rad
	last_rear_diff_speed_rad_s = axle_speeds[1]
	last_rear_lsd_capacity_nm = axle_capacities[1]
	last_rear_lsd_torque_nm = axle_torques[1]
	last_rear_lsd_saturation = axle_saturations[1]
	last_rear_lsd_filtered_torque_nm = rear_lsd_filtered_torque_nm
	last_rear_lsd_blend = rear_lsd_blend
	last_rear_lsd_lock_twist_rad = rear_lsd_lock_twist_rad
	# Espejo histórico del eje seleccionado (compat: delantero solo si el
	# reparto llega a 1; en otro caso trasero).
	var selected_axle := 0 if front_torque_split >= 1.0 else 1
	last_diff_speed_rad_s = axle_speeds[selected_axle]
	last_lsd_capacity_nm = axle_capacities[selected_axle]
	last_lsd_torque_nm = axle_torques[selected_axle]
	last_lsd_saturation = axle_saturations[selected_axle]
	last_lsd_filtered_torque_nm = axle_filt_torques[selected_axle]
	last_lsd_blend = axle_blends[selected_axle]
	last_lsd_lock_twist_rad = axle_lock_twists[selected_axle]

	# Actualizar muelle amortiguador de disco.
	if use_clutch_damper:
		var cd_carrier := 0.0
		for i in 4:
			cd_carrier += weights[i] * spins[i]
		var cd_out := output_shaft_omega_rad_s if driveline_compliance_enabled else cd_carrier
		var cd_housing := (
			(
				chassis_reaction_crank_sign * engine_mount_pitch_omega_rad_s
				if mount_is_transverse
				else chassis_reaction_crank_sign * engine_mount_roll_omega_rad_s
			)
			if mount_second_order
			else 0.0
		)
		var final_v_cd := input_shaft_omega_rad_s - cd_housing - ratio * cd_out
		clutch_damper_twist_rad = clampf(clutch_damper_twist_rad + h * final_v_cd, -1.0, 1.0)
		clutch_damper_twist_deg = rad_to_deg(clutch_damper_twist_rad)
		clutch_damper_torque_nm = -gear_impulse / h
		var cd_eval := _evaluate_clutch_damper_spring(clutch_damper_twist_rad)
		clutch_damper_at_stop = cd_eval.z > 0.5
	elif clutch_damper_enabled:
		clutch_damper_twist_rad *= exp(-h / 0.02)
		clutch_damper_twist_deg = rad_to_deg(clutch_damper_twist_rad)
		clutch_damper_torque_nm = 0.0
		clutch_damper_at_stop = false
	else:
		clutch_damper_twist_rad = 0.0
		clutch_damper_twist_deg = 0.0
		clutch_damper_torque_nm = 0.0
		clutch_damper_at_stop = false

	if shift_phase == "synchronizing" and shift_phase_seconds >= nominal_sync_time:
		var target_carrier := 0.0
		for i in 4:
			target_carrier += weights[i] * spins[i]
		var sync_output := output_shaft_omega_rad_s if driveline_compliance_enabled else target_carrier
		var sync_housing := (
			(
				chassis_reaction_crank_sign * engine_mount_pitch_omega_rad_s
				if mount_is_transverse
				else chassis_reaction_crank_sign * engine_mount_roll_omega_rad_s
			)
			if mount_second_order
			else 0.0
		)
		var dynamic_tol := synchronizer_tolerance_rad_s * sync_overtime * 2.5
		if (
			pending_gear == 0 or absf(input_shaft_omega_rad_s - sync_housing - ratio * sync_output) <= dynamic_tol
			or shift_phase_seconds >= nominal_sync_time * 1.75
		):
			input_shaft_omega_rad_s = (ratio * sync_output + sync_housing) if pending_gear != 0 else input_shaft_omega_rad_s
			current_gear = pending_gear
			shift_phase = "closing"
			shift_phase_seconds = 0.0

	if driveline_compliance_enabled:
		var final_carrier := 0.0
		for i in 4:
			final_carrier += weights[i] * spins[i]
		var final_mount_offset := (
			(chassis_reaction_crank_sign * ds_kappa_z * engine_mount_roll_omega_rad_s)
			- (tx_kappa_x * engine_mount_pitch_omega_rad_s)
		)
		var twist_speed := output_shaft_omega_rad_s - final_carrier + final_mount_offset
		var prev_flank := driveline_backlash_flank
		var twist_limit := 2.0 if progressive_contact_enabled else 0.35
		driveline_twist_rad = clampf(driveline_twist_rad + h * twist_speed, -twist_limit, twist_limit)
		var effective_twist := driveline_twist_rad
		var current_flank := 0
		if backlash_half_rad > 0.0:
			if driveline_twist_rad > backlash_half_rad:
				effective_twist = driveline_twist_rad - backlash_half_rad
				current_flank = 1
			elif driveline_twist_rad < -backlash_half_rad:
				effective_twist = driveline_twist_rad + backlash_half_rad
				current_flank = -1
			else:
				effective_twist = 0.0
				current_flank = 0
			driveline_in_backlash = current_flank == 0
			driveline_backlash_impact_rad_s = (
				absf(initial_twist_speed)
				if (current_flank != 0 and current_flank != prev_flank)
				else 0.0
			)
		else:
			current_flank = 1 if driveline_twist_rad > 0.0 else (-1 if driveline_twist_rad < 0.0 else 0)
			driveline_in_backlash = false
			driveline_backlash_impact_rad_s = 0.0
		driveline_backlash_flank = current_flank
		driveline_torque_nm = -spring_impulse / h
		if progressive_contact_enabled:
			driveline_energy_j = _evaluate_driveline_energy(absf(effective_twist), end_stop_delta)
		else:
			driveline_energy_j = 0.5 * torsional_stiffness_nm_per_rad * effective_twist * effective_twist
		var active_damping := lash_damping if driveline_in_backlash else torsional_damping_nms_per_rad
		driveline_dissipation_w = active_damping * twist_speed * twist_speed

	engine_rpm = maxf(engine_omega, 0.0) * 60.0 / TAU
	clutch_torque_nm = clutch_impulse / h
	clutch_slip_rad_s = engine_omega - input_shaft_omega_rad_s
	clutch_slip_power_w = maxf(clutch_work / h, 0.0)
	var shaft_torque := (
		driveline_torque_nm
		if driveline_compliance_enabled
		else (-ratio * gear_impulse / h if connected else 0.0)
	)
	if chassis_reaction_enabled:
		if mount_second_order:
			if mount_roll_active:
				engine_mount_roll_rad = clampf(engine_mount_roll_rad + h * engine_mount_roll_omega_rad_s, -0.6, 0.6)
				engine_roll_deg = rad_to_deg(engine_mount_roll_rad)
			else:
				engine_mount_roll_rad = 0.0
				engine_mount_roll_omega_rad_s = 0.0
				engine_roll_deg = 0.0
			if mount_pitch_active:
				engine_mount_pitch_rad = clampf(engine_mount_pitch_rad + h * engine_mount_pitch_omega_rad_s, -0.6, 0.6)
				engine_pitch_deg = rad_to_deg(engine_mount_pitch_rad)
			else:
				engine_mount_pitch_rad = 0.0
				engine_mount_pitch_omega_rad_s = 0.0
				engine_pitch_deg = 0.0
			var tau_mount_z := (-mount_roll_impulse / h) if mount_roll_active else 0.0
			var tau_mount_x := (-mount_pitch_impulse / h) if mount_pitch_active else 0.0
			var tx_chassis := (tau_mount_x - tx_kappa_x * shaft_torque) * chassis_reaction_scale
			var tz_chassis := tau_mount_z * chassis_reaction_scale
			chassis_reaction_torque_local_nm = Vector3(
				clampf(tx_chassis, -MAX_CHASSIS_REACTION_NM, MAX_CHASSIS_REACTION_NM),
				0.0,
				clampf(tz_chassis, -MAX_CHASSIS_REACTION_NM, MAX_CHASSIS_REACTION_NM),
			)
		else:
			engine_mount_roll_rad = 0.0
			engine_mount_roll_omega_rad_s = 0.0
			engine_mount_pitch_rad = 0.0
			engine_mount_pitch_omega_rad_s = 0.0
			engine_roll_deg = 0.0
			engine_pitch_deg = 0.0
			var alpha_e := (engine_omega - _reaction_prev_engine_omega) / h if _reaction_initialized else 0.0
			var alpha_in := (input_shaft_omega_rad_s - _reaction_prev_input_omega) / h if _reaction_initialized else 0.0
			var inertial_reaction := -(ie * alpha_e + shaft_inertia * alpha_in)
			var raw_torque_local := Vector3.ZERO
			if chassis_reaction_orientation == "transverse":
				var tx := clampf(
					inertial_reaction * chassis_reaction_scale,
					-MAX_CHASSIS_REACTION_NM,
					MAX_CHASSIS_REACTION_NM,
				)
				raw_torque_local = Vector3(chassis_reaction_crank_sign * tx, 0.0, 0.0)
			else:
				var ds_roll := 0.0
				if chassis_reaction_driveshaft_roll_fraction > 0.0 and connected and current_gear != 0:
					ds_roll = -clutch_torque_nm * _ratio_for_gear(current_gear) * chassis_reaction_driveshaft_roll_fraction
				var tz := clampf(
					(inertial_reaction + ds_roll) * chassis_reaction_scale,
					-MAX_CHASSIS_REACTION_NM,
					MAX_CHASSIS_REACTION_NM,
				)
				raw_torque_local = Vector3(0.0, 0.0, chassis_reaction_crank_sign * tz)
			var mount_alpha := (
				1.0
				if chassis_reaction_mount_tau_s <= 0.0001
				else (1.0 - exp(-h / chassis_reaction_mount_tau_s))
			)
			chassis_reaction_torque_local_nm = chassis_reaction_torque_local_nm.lerp(raw_torque_local, mount_alpha)
	else:
		engine_mount_roll_rad = 0.0
		engine_mount_roll_omega_rad_s = 0.0
		engine_mount_pitch_rad = 0.0
		engine_mount_pitch_omega_rad_s = 0.0
		engine_roll_deg = 0.0
		engine_pitch_deg = 0.0
		chassis_reaction_torque_local_nm = Vector3.ZERO
	_reaction_prev_engine_omega = engine_omega
	_reaction_prev_input_omega = input_shaft_omega_rad_s
	_reaction_initialized = true
	_mount_prev_chassis_omega_local = chassis_omega_local
	_mount_chassis_omega_initialized = true
	for i in 4:
		brake_work[i] = maxf(brake_work[i], 0.0)
	var overrev_result := _evaluate_mechanical_overrev_and_missgear(
		h,
		spins,
		weights,
		ratio,
		connected,
		synchronizing,
		nominal_sync_time,
		shaft_torque,
	)
	return {
		"brake_work_j": brake_work,
		"shaft_torque_nm": shaft_torque,
		"chassis_reaction_torque_local_nm": chassis_reaction_torque_local_nm,
		"engine_roll_deg": engine_roll_deg,
		"engine_pitch_deg": engine_pitch_deg,
		"engine_overrev_damage": float(overrev_result["engine_overrev_damage"]),
		"transmission_overrev_damage": float(overrev_result["transmission_overrev_damage"]),
		"missgear_active": missgear_active,
		"missgear_intensity": missgear_intensity,
	}


func _evaluate_mechanical_overrev_and_missgear(
	h: float,
	spins: Array[float],
	weights: Array[float],
	ratio: float,
	connected: bool,
	synchronizing: bool,
	nominal_sync_time: float,
	shaft_torque: float,
) -> Dictionary:
	var cfg := mechanical_damage_config
	var ref_rpm := torque_curve_reference_rpm if torque_curve_reference_rpm > 0.0 else maximum_rpm
	var overrev_start := clampf(float(cfg.get("overrev_start_fraction", 1.03)), 1.0, 1.5)
	var overrev_full := maxf(float(cfg.get("overrev_full_fraction", 1.20)), overrev_start + 0.01)
	var ov_eng_dps := maxf(float(cfg.get("overrev_engine_damage_per_second", 0.15)), 0.0) * VehicleThermalModel.MECHANICAL_ENGINE_DAMAGE_MULTIPLIER * maxf(float(cfg.get("engine_damage_multiplier", 1.0)), 0.0)
	var ov_trans_dps := maxf(float(cfg.get("overrev_transmission_damage_per_second", 0.18)), 0.0)
	var sync_ov_dps := maxf(float(cfg.get("sync_overrev_damage_per_second", 0.12)), 0.0)
	var engine_overrev_delta := 0.0
	var trans_overrev_delta := 0.0
	var prev_missgear := missgear_active
	missgear_active = false
	missgear_intensity = 0.0
	last_overrev_ratio = engine_rpm / maxf(ref_rpm, 1.0)
	var input_shaft_rpm := absf(input_shaft_omega_rad_s) * 60.0 / TAU
	if synchronizing and ref_rpm > 0.0 and pending_gear != 0:
		var sync_carrier := 0.0
		for i in 4:
			sync_carrier += weights[i] * spins[i]
		var sync_out := output_shaft_omega_rad_s if driveline_compliance_enabled else sync_carrier
		var sync_target_omega := ratio * sync_out
		var sync_target_rpm := absf(sync_target_omega) * 60.0 / TAU
		var sync_mismatch := absf(input_shaft_omega_rad_s - sync_target_omega)
		if sync_target_rpm > ref_rpm * overrev_start:
			var s_ratio := sync_target_rpm / ref_rpm
			var s_sev := pow(clampf((s_ratio - overrev_start) / (overrev_full - overrev_start), 0.0, 1.5), 1.35)
			trans_overrev_delta += sync_ov_dps * s_sev * h
			missgear_active = true
			missgear_intensity = maxf(missgear_intensity, clampf(0.45 + 0.55 * s_sev, 0.0, 1.0))
		elif transmission_damage >= 0.35 and sync_mismatch > synchronizer_tolerance_rad_s * 6.0 and shift_phase_seconds >= nominal_sync_time * 0.65:
			missgear_active = true
			missgear_intensity = maxf(missgear_intensity, clampf(transmission_damage * 0.75, 0.25, 0.85))
	var max_ov_sev := 0.0
	if connected and current_gear != 0 and clutch_engagement > 0.05 and ref_rpm > 0.0:
		var coupled_rpm := maxf(engine_rpm, input_shaft_rpm)
		var ov_ratio := coupled_rpm / ref_rpm
		last_overrev_ratio = maxf(last_overrev_ratio, ov_ratio)
		if ov_ratio > overrev_start:
			var ov_sev := pow(clampf((ov_ratio - overrev_start) / (overrev_full - overrev_start), 0.0, 1.5), 1.5)
			max_ov_sev = ov_sev
			engine_overrev_delta += ov_eng_dps * ov_sev * h
			trans_overrev_delta += ov_trans_dps * ov_sev * h
			if clutch_torque_nm < -10.0 or shaft_torque < -10.0 or ov_sev > 0.15:
				missgear_active = true
				missgear_intensity = maxf(missgear_intensity, clampf(0.4 + 0.6 * ov_sev, 0.0, 1.0))
	if transmission_damage >= 0.75 and current_gear > 0 and _gearbox_popout_cooldown_s <= 0.0 and shift_phase == "idle" and (driveline_backlash_impact_rad_s > 6.0 or max_ov_sev > 0.35):
		current_gear = 0
		invalidate_freewheel()
		reset_shift()
		_gearbox_popout_cooldown_s = 1.2
		missgear_active = true
		missgear_intensity = 1.0
		missgear_event_pending = true
	if trans_overrev_delta > 0.0:
		transmission_damage = clampf(transmission_damage + trans_overrev_delta, 0.0, 1.0)
	if missgear_active and not prev_missgear:
		missgear_event_pending = true
	return {
		"engine_overrev_damage": engine_overrev_delta,
		"transmission_overrev_damage": trans_overrev_delta,
	}


func _advance_engine_torque(delta: float, throttle: float, thermal_derating: float) -> void:
	# Mismos términos que el estimador (plan §2): par solicitado vs entregado
	# se distinguen solo por el límite de ataque; el rozamiento interno se
	# mantiene siempre y la rueda libre corta la transmisión en el solver.
	var rpm_fraction_full := clampf(engine_rpm / maxf(torque_curve_reference_rpm if torque_curve_reference_rpm > 0.0 else maximum_rpm, 1.0), 0.0, 1.0)
	var effective_throttle := clampf(throttle, 0.0, 1.0)
	if throttle_response_enabled:
		var base_tau := throttle_tau_up_s if effective_throttle > manifold_fill else throttle_tau_down_s
		var rpm_scale := clampf(
			throttle_rpm_reference / maxf(engine_rpm, 1.0),
			throttle_rpm_scale_min,
			throttle_rpm_scale_max,
		)
		var eff_tau := base_tau * rpm_scale
		if eff_tau > 0.0001:
			manifold_fill += (effective_throttle - manifold_fill) * (1.0 - exp(-delta / eff_tau))
		else:
			manifold_fill = effective_throttle
		manifold_fill = clampf(manifold_fill, 0.0, 1.0)
		effective_throttle = manifold_fill
	else:
		manifold_fill = effective_throttle
	var terms := _engine_torque_terms(
		engine_rpm, effective_throttle, peak_torque_nm, maximum_rpm, _idle_target_rpm(),
		_evaluate_torque_curve(rpm_fraction_full), variable_drag_ratio,
		constant_brake_ratio, thermal_derating, torque_curve_reference_rpm
	)
	var positive_target := float(terms["positive_requested"])
	if throttle_response_enabled:
		if throttle_response_attack_rate_nm_s > 0.0:
			engine_attack_limited_torque_nm = move_toward(
				engine_attack_limited_torque_nm,
				positive_target,
				throttle_response_attack_rate_nm_s * delta,
			)
		else:
			engine_attack_limited_torque_nm = positive_target
	elif torque_attack_rate_nm_s > 0.0:
		if positive_target > engine_attack_limited_torque_nm:
			engine_attack_limited_torque_nm = minf(
				positive_target,
				engine_attack_limited_torque_nm + torque_attack_rate_nm_s * delta,
			)
		else:
			engine_attack_limited_torque_nm = maxf(
				positive_target,
				engine_attack_limited_torque_nm - torque_attack_rate_nm_s * 3.5 * delta,
			)
	else:
		engine_attack_limited_torque_nm = positive_target
	engine_requested_torque_nm = (
		positive_target * (1.0 if thermal_derating > 0.0 else 0.0)
		+ float(terms["idle_support"]) * thermal_derating
		- float(terms["variable_drag"]) - float(terms["constant_brake"])
	)
	engine_torque_nm = engine_attack_limited_torque_nm * (1.0 if thermal_derating > 0.0 else 0.0) + float(terms["idle_support"]) * thermal_derating - float(terms["variable_drag"]) - float(terms["constant_brake"])


func _evaluate_clutch_bite(engagement: float) -> float:
	var e := clampf(engagement, 0.0, 1.0)
	if not clutch_bite_enabled:
		return e * e * (3.0 - 2.0 * e)
	var u := clampf(
		(e - clutch_bite_start) / maxf(clutch_bite_full - clutch_bite_start, 0.01),
		0.0,
		1.0,
	)
	var s := u * u * (3.0 - 2.0 * u)
	return pow(s, clutch_bite_exponent)


# Devuelve Vector3(torque_nm, k_tangent, at_stop_flag) para el muelle de disco.
func _evaluate_clutch_damper_spring(theta_rad: float) -> Vector3:
	var a := absf(theta_rad)
	var sgn := 1.0 if theta_rad >= 0.0 else -1.0
	var th1 := deg_to_rad(clutch_damper_idle_travel_deg)
	var th2 := deg_to_rad(clutch_damper_travel_deg)
	var k1 := clutch_damper_idle_stiffness_nm_per_rad
	var k2 := clutch_damper_main_stiffness_nm_per_rad
	if a <= th1:
		return Vector3(sgn * k1 * a, k1, 0.0)
	if a <= th2:
		return Vector3(sgn * (k1 * th1 + k2 * (a - th1)), k2, 0.0)
	var k3 := k2 * clutch_damper_stop_stiffness_factor
	var t_stop := k1 * th1 + k2 * (th2 - th1)
	var ex := a - th2
	var stop_band := maxf(0.15 * maxf(th2 - th1, 0.02), 0.005)
	var k_extra := k3 - k2
	if ex < stop_band:
		return Vector3(
			sgn * (t_stop + k2 * ex + k_extra * ex * ex / (2.0 * stop_band)),
			k2 + k_extra * (ex / stop_band),
			1.0,
		)
	return Vector3(
		sgn * (t_stop + k2 * ex + k_extra * (ex - 0.5 * stop_band)),
		k3,
		1.0,
	)


func _driveline_end_stop_delta() -> float:
	var g1 := absf(gear_ratios[0]) if not gear_ratios.is_empty() else 1.0
	var t_axle_max := maxf(
		peak_torque_nm * maxf(clutch_max_torque_ratio, 1.0) * g1 * final_drive_ratio,
		maxf(peak_torque_nm, 100.0),
	)
	return maxf(
		driveline_end_stop_margin * t_axle_max / maxf(torsional_stiffness_nm_per_rad, 1.0),
		0.15,
	)


# Devuelve Vector2(force_nm, k_tangent) para penetración delta_pen >= 0 en el flanco.
func _evaluate_driveline_flank(delta_pen: float, end_stop_delta: float) -> Vector2:
	var d := maxf(delta_pen, 0.0)
	var k := torsional_stiffness_nm_per_rad
	var ds := driveline_contact_soft_zone_rad
	if d < ds:
		return Vector2(k * d * d / (2.0 * ds), k * d / ds)
	if d < end_stop_delta:
		return Vector2(k * (d - 0.5 * ds), k)
	var ex := d - end_stop_delta
	var end_band := maxf(0.15 * end_stop_delta, 0.02)
	var k_extra := k * (driveline_end_stop_stiffness_factor - 1.0)
	if ex < end_band:
		return Vector2(
			k * (d - 0.5 * ds) + k_extra * ex * ex / (2.0 * end_band),
			k + k_extra * (ex / end_band),
		)
	return Vector2(
		k * (d - 0.5 * ds) + k_extra * (ex - 0.5 * end_band),
		k + k_extra,
	)


func _evaluate_driveline_energy(delta_pen: float, end_stop_delta: float) -> float:
	var d := maxf(delta_pen, 0.0)
	var k := torsional_stiffness_nm_per_rad
	var ds := driveline_contact_soft_zone_rad
	if d <= 0.0:
		return 0.0
	if d < ds:
		return k * d * d * d / (6.0 * ds)
	var e_soft := k * ds * ds / 6.0
	var d_lin := minf(d, end_stop_delta) - ds
	var e_lin := 0.5 * k * (d_lin * d_lin + ds * d_lin)
	if d <= end_stop_delta:
		return e_soft + e_lin
	var ex := d - end_stop_delta
	var end_band := maxf(0.15 * end_stop_delta, 0.02)
	var k_extra := k * (driveline_end_stop_stiffness_factor - 1.0)
	var e_base := e_soft + 0.5 * k * ((d - ds) * (d - ds) + ds * (d - ds))
	if ex < end_band:
		return e_base + k_extra * ex * ex * ex / (6.0 * end_band)
	var e_band := k_extra * end_band * end_band / 6.0
	var ex2 := ex - end_band
	return e_base + e_band + 0.5 * k_extra * (ex2 * ex2 + end_band * ex2)


# Devuelve Vector2(torque_nm, k_tangent) para soporte de motor con tope progresivo.
static func _evaluate_mount_spring(
	angle_rad: float, k_base: float, snubber_rad: float, snubber_factor: float
) -> Vector2:
	var a := absf(angle_rad)
	var sgn := 1.0 if angle_rad >= 0.0 else -1.0
	if a <= snubber_rad or snubber_factor <= 1.0:
		return Vector2(k_base * angle_rad, k_base)
	var ex := a - snubber_rad
	var band := maxf(0.25 * snubber_rad, 0.01)
	var k_extra := k_base * (snubber_factor - 1.0)
	if ex < band:
		return Vector2(
			sgn * (k_base * a + k_extra * ex * ex / (2.0 * band)),
			k_base + k_extra * (ex / band),
		)
	return Vector2(
		sgn * (k_base * a + k_extra * (ex - 0.5 * band)),
		k_base + k_extra,
	)


func _evaluate_torque_curve(normalized_rpm: float) -> float:
	var rpm_fraction := clampf(normalized_rpm, 0.0, 1.0)
	if torque_curve.is_empty():
		return 1.0
	if rpm_fraction <= torque_curve[0].x:
		return torque_curve[0].y
	var last_index := torque_curve.size() - 1
	if rpm_fraction >= torque_curve[last_index].x:
		return torque_curve[last_index].y
	for index in range(last_index):
		var first_point := torque_curve[index]
		var second_point := torque_curve[index + 1]
		if rpm_fraction >= first_point.x and rpm_fraction <= second_point.x:
			var fraction := (rpm_fraction - first_point.x) / maxf(
				second_point.x - first_point.x,
				0.000001,
			)
			return lerpf(first_point.y, second_point.y, fraction)
	return torque_curve[last_index].y
