class_name VehiclePowertrainModel
extends RefCounted

const GEVP_GEAR_INERTIA := 0.02

var idle_rpm: float = 900.0
var maximum_rpm: float = 7200.0
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
var base_differential_power_ratio: float = 0.0
var base_differential_coast_ratio: float = 0.25
var last_diff_speed_rad_s: float = 0.0
var last_lsd_capacity_nm: float = 0.0
var last_lsd_torque_nm: float = 0.0
var last_lsd_saturation: float = 0.0
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
# Telemetría por eje. Los last_* históricos reflejan el eje seleccionado
# (delantero si front_torque_split >= 1, trasero en otro caso) por
# compatibilidad con consumidores existentes.
var last_front_diff_speed_rad_s: float = 0.0
var last_front_lsd_capacity_nm: float = 0.0
var last_front_lsd_torque_nm: float = 0.0
var last_front_lsd_saturation: float = 0.0
var last_rear_diff_speed_rad_s: float = 0.0
var last_rear_lsd_capacity_nm: float = 0.0
var last_rear_lsd_torque_nm: float = 0.0
var last_rear_lsd_saturation: float = 0.0
var current_gear: int = 0
var engine_rpm: float = 0.0
var engine_torque_nm: float = 0.0
var maximum_forward_gear: int = 0
const MAX_TRANSMISSION_SHIFT_DELAY_SECONDS := 1.0

var transmission_damage: float = 0.0
var _shift_damage_delay_seconds: float = 0.0
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
var driveline_twist_rad: float = 0.0
var driveline_torque_nm: float = 0.0
var driveline_energy_j: float = 0.0
var driveline_dissipation_w: float = 0.0


func configure(domains: Dictionary) -> Dictionary:
	var staged := validate_powertrain_config(domains)
	if not bool(staged.get("ok", false)):
		return {"ok": false, "error": str(staged.get("error", "invalid powertrain"))}
	var values: Dictionary = staged["values"]
	# Commit atómico: solo se copian locales ya validados. Un error anterior
	# no muta configuración ni estado (plan §3: recarga inválida conserva todo).
	transmission_damage = 0.0
	idle_rpm = float(values["idle_rpm"])
	maximum_rpm = float(values["maximum_rpm"])
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
	front_torque_split = float(values["front_torque_split"])
	gear_inertia_shift_seconds = float(values["gear_inertia"])
	front_wheel_mass_kg = float(values["front_wheel_mass"])
	front_wheel_radius_m = float(values["front_wheel_radius"])
	rear_wheel_mass_kg = float(values["rear_wheel_mass"])
	rear_wheel_radius_m = float(values["rear_wheel_radius"])
	shift_time_seconds = float(values["shift_time"])
	clutch_release_seconds = float(values["clutch_release"])
	clutch_reengage_seconds = float(values["clutch_reengage"])
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
	default_gain: float = 0.16
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
		float(cur["gain"])
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


func set_final_drive_preset(preset: String) -> bool:
	if preset == "gravel" and final_drive_gravel > 0.0:
		final_drive_ratio = final_drive_gravel
		final_drive_preset = preset
		return true
	if preset == "tarmac" and final_drive_tarmac > 0.0:
		final_drive_ratio = final_drive_tarmac
		final_drive_preset = preset
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
	var inherited_gain := (
		front_differential_ramp_gain if target_axle == "front"
		else rear_differential_ramp_gain
	)
	if not is_finite(float(inherited_gain)) or float(inherited_gain) < 0.0:
		return {"ok": false, "error": "Ganancia de rampa inválida en el eje " + target_axle + " para preset: " + preset_id}
	var staged := {
		"type": dtype,
		"preload": preload_nm,
		"power_ratio": mu_power,
		"coast_ratio": mu_coast,
		"power_ramp": power_ramp,
		"coast_ramp": coast_ramp,
		"clutches": float(maxi(surfaces, 0)),
		"ramp_gain": float(inherited_gain),
		"preset_id": preset_id,
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
	shift_remaining_seconds = clutch_release_seconds + shift_time_seconds + gear_inertia_shift_seconds + clutch_reengage_seconds + _shift_damage_delay_seconds


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
	constant_brake_ratio_value: float, thermal_derating: float
) -> Dictionary:
	var throttle_value := clampf(throttle, 0.0, 1.0)
	var closed_throttle := 1.0 - throttle_value
	var rpm_fraction := clampf(rpm / maxf(max_rpm, 1.0), 0.0, 1.25)
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
	var rpm_fraction := clampf(rpm / maxf(maximum_rpm, 1.0), 0.0, 1.0)
	var terms := _engine_torque_terms(
		rpm, throttle, peak_torque_nm, maximum_rpm, _idle_target_rpm(),
		_evaluate_torque_curve(rpm_fraction), variable_drag_ratio,
		constant_brake_ratio, thermal_derating
	)
	return float(terms["positive_requested"]) + float(terms["idle_support"]) * thermal_derating - float(terms["variable_drag"]) - float(terms["constant_brake"])


# Par entregado tras aplicar el límite de ataque, con la misma base que el
# estimador (sin mutar estado). A límite estabilizado
# (engine_attack_limited == positive_requested) coincide con la estimación.
func engine_delivered_torque_at_rpm(rpm: float, throttle: float, thermal_derating: float = 1.0) -> float:
	var rpm_fraction := clampf(rpm / maxf(maximum_rpm, 1.0), 0.0, 1.0)
	var terms := _engine_torque_terms(
		rpm, throttle, peak_torque_nm, maximum_rpm, _idle_target_rpm(),
		_evaluate_torque_curve(rpm_fraction), variable_drag_ratio,
		constant_brake_ratio, thermal_derating
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
	# Decisión única de rueda libre por subpaso con el acelerador del
	# conductor (plan §1); la integración y el solver consumen este estado.
	resolve_freewheel(throttle, carrier_omega_rad_s)
	shift_phase_seconds += dt
	if shift_phase != "idle":
		shift_remaining_seconds = maxf(dt, shift_remaining_seconds - dt)
	var effective_throttle := _autoblip_command(throttle, thermal_derating, carrier_omega_rad_s, dt)
	_advance_engine_torque(dt, effective_throttle, thermal_derating)
	var engine_inertia := maxf(engine_inertia_kg_m2, 0.000001)
	engine_rpm = clampf(
		engine_rpm + engine_torque_nm / engine_inertia * dt * 60.0 / TAU,
		idle_rpm * 0.65 if thermal_derating > 0.0 else 0.0,
		maximum_rpm * 1.25,
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
	elif shift_phase == "closing" and shift_phase_seconds >= clutch_reengage_seconds:
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
	var desired_torque := maxf(engine_inertia_kg_m2, 0.000001) * error_omega / maxf(
		downshift_blip_response_seconds,
		dt,
	)
	var closed_torque := engine_torque_at_rpm(engine_rpm, 0.0, thermal_derating)
	var available_torque := engine_torque_at_rpm(engine_rpm, 1.0, thermal_derating) - closed_torque
	if available_torque <= 0.000001:
		return driver_throttle
	autoblip_throttle = clampf(
		(desired_torque - closed_torque) / available_torque,
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
) -> Dictionary:
	var h := maxf(delta, 0.000001)
	var ie := maxf(engine_inertia_kg_m2, 0.000001)
	var shaft_inertia := gearbox_input_inertia_kg_m2
	var engine_omega := engine_rpm * TAU / 60.0
	var synchronizing := shift_phase == "synchronizing" and shift_phase_seconds >= 0.0 and pending_gear != 0
	var ratio := (_ratio_for_gear(pending_gear) if synchronizing else gear_ratio()) * final_drive_ratio
	var geared := current_gear != 0 and absf(ratio) > 0.000001
	# La rueda libre consume la decisión única del subpaso (resolve_freewheel
	# en advance con el acelerador del conductor): sin inferir acelerador a
	# partir del signo del par ni reevaluar aquí (plan §1).
	var connected := (geared or synchronizing) and not (freewheel_enabled and freewheel_active)
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
	var output_inverse := 1.0 / output_shaft_inertia_kg_m2
	var gear_effective_inverse := 1.0 / shaft_inertia
	for i in 4:
		inverse.append(1.0 / maxf(inertias[i], 0.000001))
		spins[i] -= h * tire_torques[i] * inverse[i]
		carrier_inverse += weights[i] * weights[i] * inverse[i]
	gear_effective_inverse += ratio * ratio * (
		output_inverse if driveline_compliance_enabled else carrier_inverse
	)
	var spring_inverse := output_inverse + carrier_inverse
	var implicit_damping := torsional_damping_nms_per_rad + h * torsional_stiffness_nm_per_rad
	var spring_denominator := 1.0 + h * implicit_damping * spring_inverse
	var spring_impulse := 0.0
	var clutch_impulse := 0.0
	var gear_impulse := 0.0
	var clutch_work := 0.0
	var smooth_clutch := clutch_engagement * clutch_engagement * (3.0 - 2.0 * clutch_engagement)
	var clutch_capacity := clutch_max_torque_nm * smooth_clutch * h
	var nominal_sync_time := maxf(shift_time_seconds + gear_inertia_shift_seconds, 0.02)
	var sync_overtime := clampf(shift_phase_seconds / nominal_sync_time, 1.0, 4.0) if synchronizing else 1.0
	var effective_sync_cap := synchronizer_capacity_nm * sync_overtime * h
	# Diferencial por eje (plan §4): cada eje usa sus parámetros propios; el
	# eje no motriz (reparto ~0) queda abierto y open genera bloqueo cero.
	# B2 revertido temporalmente (decisión v1.6): se mantiene el término de
	# regularización para validar B1 de forma aislada. No reintroducir otro
	# término arbitrario sin justificar unidades si este se retira.
	var axle_left := [0, 2]
	var axle_shares := [front_torque_split, 1.0 - front_torque_split]
	var axle_types := [front_differential_type, rear_differential_type]
	var axle_preloads := [front_differential_preload_nm, rear_differential_preload_nm]
	var axle_power_ratios := [front_differential_power_ratio, rear_differential_power_ratio]
	var axle_coast_ratios := [front_differential_coast_ratio, rear_differential_coast_ratio]
	var axle_power_ramps := [
		front_differential_power_ramp_angle_deg, rear_differential_power_ramp_angle_deg
	]
	var axle_coast_ramps := [
		front_differential_coast_ramp_angle_deg, rear_differential_coast_ramp_angle_deg
	]
	var axle_clutches := [front_differential_clutches, rear_differential_clutches]
	var axle_gains := [front_differential_ramp_gain, rear_differential_ramp_gain]
	var axle_pair_invs := [
		inverse[0] + inverse[1] + h * differential_slip_transition_threshold_rad_s * 0.35,
		inverse[2] + inverse[3] + h * differential_slip_transition_threshold_rad_s * 0.35,
	]
	var lsd_impulses := [0.0, 0.0]
	var axle_speeds := [0.0, 0.0]
	var axle_capacities := [0.0, 0.0]
	var axle_torques := [0.0, 0.0]
	var axle_saturations := [0.0, 0.0]

	for iteration in 48:
		if connected:
			var carrier := 0.0
			for i in 4:
				carrier += weights[i] * spins[i]
			var gear_output := output_shaft_omega_rad_s if driveline_compliance_enabled else carrier
			var impulse := -(input_shaft_omega_rad_s - ratio * gear_output) / gear_effective_inverse
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
		if driveline_compliance_enabled:
			var carrier_speed := 0.0
			for i in 4:
				carrier_speed += weights[i] * spins[i]
			var relative_speed := output_shaft_omega_rad_s - carrier_speed
			var spring_delta := -(
				spring_impulse + h * torsional_stiffness_nm_per_rad * driveline_twist_rad
				+ h * implicit_damping * relative_speed
			) / spring_denominator
			spring_impulse += spring_delta
			output_shaft_omega_rad_s += spring_delta * output_inverse
			for i in 4:
				spins[i] -= weights[i] * spring_delta * inverse[i]
		var slip := engine_omega - input_shaft_omega_rad_s
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

		var transmitted := (
			-spring_impulse / h
			if driveline_compliance_enabled
			else (-ratio * gear_impulse / h if connected else 0.0)
		)
		for axle in 2:
			# Eje no motriz u open: bloqueo cero. spool/unknown son
			# inalcanzables (la validación los rechaza) y se tratan como open.
			if (
				float(axle_shares[axle]) <= DIFFERENTIAL_DRIVE_EPS
				or not str(axle_types[axle]) in DIFFERENTIAL_FRICTION_TYPES
			):
				continue
			var left := int(axle_left[axle])
			var axle_input := transmitted * float(axle_shares[axle])
			var axle_carrier := 0.5 * (spins[left] + spins[left + 1])
			var driving_power := axle_input * (
				axle_carrier if absf(axle_carrier) > 0.5 else signf(axle_input)
			)
			var power_blend := clampf(0.5 + 0.5 * tanh(driving_power / 150.0), 0.0, 1.0)
			var ramp_deg := lerpf(
				float(axle_coast_ramps[axle]),
				float(axle_power_ramps[axle]),
				power_blend,
			)
			var friction_mu := lerpf(
				float(axle_coast_ratios[axle]), float(axle_power_ratios[axle]), power_blend
			)
			var cot_ramp := 1.0 / tan(clampf(deg_to_rad(ramp_deg), deg_to_rad(15.0), deg_to_rad(85.0)))
			var ramp_capacity := absf(axle_input) * cot_ramp * maxf(float(axle_clutches[axle]), 1.0) * maxf(
				friction_mu,
				0.0,
			) * maxf(float(axle_gains[axle]), 0.0)
			var diff_speed := spins[left] - spins[left + 1]
			var preload_capacity := maxf(
				float(axle_preloads[axle]),
				0.0
			)
			var ramp_lock_capacity := maxf(
				ramp_capacity,
				0.0
			)
			var lsd_capacity := (
				preload_capacity + ramp_lock_capacity
			) * h
			var next_lsd := clampf(
				float(lsd_impulses[axle]) + diff_speed / float(axle_pair_invs[axle]),
				-lsd_capacity,
				lsd_capacity,
			)
			var lsd_delta := next_lsd - float(lsd_impulses[axle])
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

	last_front_diff_speed_rad_s = float(axle_speeds[0])
	last_front_lsd_capacity_nm = float(axle_capacities[0])
	last_front_lsd_torque_nm = float(axle_torques[0])
	last_front_lsd_saturation = float(axle_saturations[0])
	last_rear_diff_speed_rad_s = float(axle_speeds[1])
	last_rear_lsd_capacity_nm = float(axle_capacities[1])
	last_rear_lsd_torque_nm = float(axle_torques[1])
	last_rear_lsd_saturation = float(axle_saturations[1])
	# Espejo histórico del eje seleccionado (compat: delantero solo si el
	# reparto llega a 1; en otro caso trasero).
	var selected_axle := 0 if front_torque_split >= 1.0 else 1
	last_diff_speed_rad_s = float(axle_speeds[selected_axle])
	last_lsd_capacity_nm = float(axle_capacities[selected_axle])
	last_lsd_torque_nm = float(axle_torques[selected_axle])
	last_lsd_saturation = float(axle_saturations[selected_axle])

	if shift_phase == "synchronizing" and shift_phase_seconds >= nominal_sync_time:
		var target_carrier := 0.0
		for i in 4:
			target_carrier += weights[i] * spins[i]
		var sync_output := output_shaft_omega_rad_s if driveline_compliance_enabled else target_carrier
		var dynamic_tol := synchronizer_tolerance_rad_s * sync_overtime * 2.5
		if (
			pending_gear == 0 or absf(input_shaft_omega_rad_s - ratio * sync_output) <= dynamic_tol
			or shift_phase_seconds >= nominal_sync_time * 1.75
		):
			input_shaft_omega_rad_s = ratio * sync_output if pending_gear != 0 else input_shaft_omega_rad_s
			current_gear = pending_gear
			shift_phase = "closing"
			shift_phase_seconds = 0.0

	if driveline_compliance_enabled:
		var final_carrier := 0.0
		for i in 4:
			final_carrier += weights[i] * spins[i]
		var twist_speed := output_shaft_omega_rad_s - final_carrier
		driveline_twist_rad = clampf(driveline_twist_rad + h * twist_speed, -0.35, 0.35)
		driveline_torque_nm = -spring_impulse / h
		driveline_energy_j = 0.5 * torsional_stiffness_nm_per_rad * driveline_twist_rad * driveline_twist_rad
		driveline_dissipation_w = torsional_damping_nms_per_rad * twist_speed * twist_speed

	engine_rpm = maxf(engine_omega, 0.0) * 60.0 / TAU
	clutch_torque_nm = clutch_impulse / h
	clutch_slip_power_w = maxf(clutch_work / h, 0.0)
	for i in 4:
		brake_work[i] = maxf(brake_work[i], 0.0)
	return {
		"brake_work_j": brake_work,
		"shaft_torque_nm": (
			driveline_torque_nm
			if driveline_compliance_enabled
			else (-ratio * gear_impulse / h if connected else 0.0)
		),
	}


func _advance_engine_torque(delta: float, throttle: float, thermal_derating: float) -> void:
	# Mismos términos que el estimador (plan §2): par solicitado vs entregado
	# se distinguen solo por el límite de ataque; el rozamiento interno se
	# mantiene siempre y la rueda libre corta la transmisión en el solver.
	var rpm_fraction_full := clampf(engine_rpm / maxf(maximum_rpm, 1.0), 0.0, 1.0)
	var terms := _engine_torque_terms(
		engine_rpm, throttle, peak_torque_nm, maximum_rpm, _idle_target_rpm(),
		_evaluate_torque_curve(rpm_fraction_full), variable_drag_ratio,
		constant_brake_ratio, thermal_derating
	)
	var positive_target := float(terms["positive_requested"])
	if torque_attack_rate_nm_s > 0.0:
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
