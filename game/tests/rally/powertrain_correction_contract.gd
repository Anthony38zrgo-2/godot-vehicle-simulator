extends SceneTree

# Contrato de regresión del plan POWERTRAIN_CORRECTION_PLAN + 3 hallazgos.
# §1 rueda libre: decisión única por subpaso, histéresis, punto muerto.
# §2 par motor: estimación == integración a límite estabilizado, caída a ralentí.
# §3 validación y carga atómica: 11 perfiles + entradas inválidas + recarga.
# §4 diferencial por eje: FWD/RWD vigentes, AWD de prueba, open, spool.
# H1 tipos estrictos (sin coerción silenciosa) en la validación.
# H2 objetivo de ralentí de rueda libre vía par (1400/1000), sin rampa directa.
# H3 sync por eje al aplicar reglajes (AWD + FWD/RWD históricos).
# Ejecución: godot --headless --path game --script res://tests/rally/powertrain_correction_contract.gd

const RallyDifferentialCatalog = preload("res://scripts/rally/rally_differential_catalog.gd")

const PROFILE_BASE := "res://data/vehicles/"
const REGISTRY_PATH := "res://data/vehicles/registry.json"
const SAAB_MANIFEST := "res://data/vehicles/rt/rt-saab-96-v4/vehicle.json"

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"ok": false, "error": "no se puede leer " + path}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"ok": false, "error": "JSON inválido en " + path}
	return {"ok": true, "value": parsed}


func _configure_saab() -> VehiclePowertrainModel:
	var loaded := VehicleProfileLoader.load_profile(SAAB_MANIFEST)
	if not bool(loaded.get("ok", false)):
		check(false, "saab profile loads: " + str(loaded.get("error", "")))
		return null
	var model := VehiclePowertrainModel.new()
	var result := model.configure(loaded["domains"])
	if not bool(result.get("ok", false)):
		check(false, "saab configure ok: " + str(result.get("error", "")))
		return null
	return model


# §1: el caso del plan. 3.ª a gas cerrado con equivalente de 4.800 rpm:
# a 970 y 850 rpm la rueda libre sigue activa tras el solver y el impulso
# de la restricción de marcha es cero (transmisión rígida).
func _freewheel_saab_case(rpm: float) -> void:
	var model := _configure_saab()
	if model == null:
		return
	model.driveline_compliance_enabled = false
	model.current_gear = 3
	model.engine_rpm = rpm
	model.clutch_engagement = 1.0
	var ratio: float = model.gear_ratios[2] * model.final_drive_ratio
	var carrier := (4800.0 * TAU / 60.0) / ratio
	var spins: Array[float] = [carrier, carrier, carrier, carrier]
	var inertias: Array[float] = [1.5, 1.5, 1.5, 1.5]
	var zeros: Array[float] = [0.0, 0.0, 0.0, 0.0]
	# Subpaso real: advance (decisión con acelerador del conductor) + solver.
	model.advance(0.002, 0.0, 1.0, 1.0, carrier)
	check(model.freewheel_active, "saab %d rpm: rueda libre activa tras advance" % int(rpm))
	var result := model.solve_rotation(0.002, spins, inertias, zeros, zeros)
	check(model.freewheel_active, "saab %d rpm: rueda libre sigue activa tras solver" % int(rpm))
	check(absf(float(result.get("shaft_torque_nm", 1.0))) < 0.000001, "saab %d rpm: impulso de marcha cero" % int(rpm))


func run_freewheel_checks() -> void:
	_freewheel_saab_case(970.0)
	_freewheel_saab_case(850.0)
	var model := _configure_saab()
	if model == null:
		return
	# Con transmisión elástica la rueda libre también se mantiene; el par
	# transitorio por torsión almacenada queda documentado, no exigido cero.
	model.current_gear = 3
	model.engine_rpm = 970.0
	model.clutch_engagement = 1.0
	var ratio: float = model.gear_ratios[2] * model.final_drive_ratio
	var carrier := (4800.0 * TAU / 60.0) / ratio
	model.advance(0.002, 0.0, 1.0, 1.0, carrier)
	var spins: Array[float] = [carrier, carrier, carrier, carrier]
	var inertias: Array[float] = [1.5, 1.5, 1.5, 1.5]
	var zeros: Array[float] = [0.0, 0.0, 0.0, 0.0]
	model.solve_rotation(0.002, spins, inertias, zeros, zeros)
	check(model.freewheel_active, "saab elastica: rueda libre activa tras solver")
	# Reapertura de gas: reacopla de inmediato.
	model.resolve_freewheel(1.0, carrier)
	check(not model.freewheel_active, "reapertura de gas reacopla")
	# Barrido lento de ambos umbrales (histéresis con estado).
	model.engine_rpm = 1000.0
	model.current_gear = 3
	var engine_omega := 1000.0 * TAU / 60.0
	var total_ratio: float = model.gear_ratios[2] * model.final_drive_ratio
	var for_delta := func(d: float) -> float: return (engine_omega + d) / total_ratio
	model.invalidate_freewheel()
	model.resolve_freewheel(0.0, for_delta.call(2.0))
	check(not model.freewheel_active, "histeresis: 2.0 inactivo sigue inactivo")
	model.resolve_freewheel(0.0, for_delta.call(3.0))
	check(model.freewheel_active, "histeresis: 3.0 desacopla")
	model.resolve_freewheel(0.0, for_delta.call(2.0))
	check(model.freewheel_active, "histeresis: 2.0 activo sigue activo")
	model.resolve_freewheel(0.0, for_delta.call(1.0))
	check(not model.freewheel_active, "histeresis: 1.0 reacopla")
	# Histéresis de acelerador.
	model.resolve_freewheel(0.0, for_delta.call(3.0))
	check(model.freewheel_active, "gas: 0.0 desacopla")
	model.resolve_freewheel(0.15, for_delta.call(3.0))
	check(model.freewheel_active, "gas: 0.15 mantiene")
	model.resolve_freewheel(0.25, for_delta.call(3.0))
	check(not model.freewheel_active, "gas: 0.25 reacopla")
	# Punto muerto y marcha atrás invalidan.
	model.resolve_freewheel(0.0, for_delta.call(5.0))
	check(model.freewheel_active, "pre: activo en 3a")
	model.current_gear = 0
	model.resolve_freewheel(0.0, for_delta.call(5.0))
	check(not model.freewheel_active and model.freewheel_delta_rad_s == 0.0, "punto muerto invalida")
	model.current_gear = -1
	model.resolve_freewheel(0.0, for_delta.call(5.0))
	check(not model.freewheel_active, "marcha atras no usa rueda libre")
	# Entrada a punto muerto durante un cambio invalida en el mismo subpaso.
	model.current_gear = 3
	model.engine_rpm = 970.0
	model.resolve_freewheel(0.0, for_delta.call(5.0))
	check(model.freewheel_active, "pre-cambio: activo")
	model.set_gear(0)
	model.clutch_engagement = 0.0
	model.advance(0.002, 0.0, 1.0, 1.0, for_delta.call(5.0))
	check(model.current_gear == 0, "cambio entra a neutro")
	check(not model.freewheel_active, "neutro de cambio invalida rueda libre")


func run_torque_checks() -> void:
	var model := _configure_saab()
	if model == null:
		return
	# Estimación vs integración a 4.000 rpm, gas cerrado, límite estabilizado.
	model.engine_rpm = 4000.0
	var estimate: float = model.engine_torque_at_rpm(4000.0, 0.0, 1.0)
	model._advance_engine_torque(30.0, 0.0, 1.0)
	check(absf(model.engine_torque_nm - estimate) < 0.000001, "par 4000: integracion == estimacion")
	check(absf(model.engine_requested_torque_nm - estimate) < 0.000001, "par 4000: solicitado == estimacion")
	check(absf(model.engine_delivered_torque_at_rpm(4000.0, 0.0, 1.0) - estimate) < 0.000001, "par 4000: entregado == estimacion")
	check(estimate < 0.0, "par 4000 gas cerrado: retiene (rozamiento interno)")
	# El rozamiento ya no se anula con rueda libre: mismo par activa o no.
	model.freewheel_active = true
	var estimate_fw: float = model.engine_torque_at_rpm(4000.0, 0.0, 1.0)
	model.freewheel_active = false
	check(absf(estimate_fw - estimate) < 0.000001, "par: rueda libre no altera el par interno")
	# Caída a ralentí gobernada por par e inercia (sin rampa directa).
	model.engine_rpm = 4000.0
	model.current_gear = 3
	model.clutch_engagement = 1.0
	var ratio: float = model.gear_ratios[2] * model.final_drive_ratio
	var carrier := (4800.0 * TAU / 60.0) / ratio
	var steps := 0
	while model.engine_rpm > 1100.0 and steps < 20 * 240:
		model.advance(1.0 / 240.0, 0.0, 1.0, 1.0, carrier)
		steps += 1
	check(model.engine_rpm <= 1100.0, "caida: llega a ralenti")
	check(steps > 10, "caida: gobernada, no instantanea (%d pasos)" % steps)
	var drop_rpm := model.engine_rpm
	for i in 480:
		model.advance(1.0 / 240.0, 0.0, 1.0, 1.0, carrier)
	check(model.engine_rpm >= 650.0 and model.engine_rpm <= 1250.0, "caida: equilibrio en ralenti (%.0f rpm)" % model.engine_rpm)
	# Misma traza con rueda libre desactivada: el par interno ya no depende
	# del estado de la rueda libre (solo corta la transmisión en el solver).
	var plain := _configure_saab()
	plain.freewheel_enabled = false
	plain.current_gear = 3
	plain.engine_rpm = 4000.0
	plain.clutch_engagement = 1.0
	for i in steps:
		plain.advance(1.0 / 240.0, 0.0, 1.0, 1.0, carrier)
	check(absf(plain.engine_rpm - drop_rpm) < 0.001, "caida: on/off identicas (%.3f vs %.3f)" % [plain.engine_rpm, drop_rpm])


func _profile_manifests() -> Array[String]:
	var out: Array[String] = []
	var reg := _load_json(REGISTRY_PATH)
	if not bool(reg.get("ok", false)):
		check(false, "registry legible")
		return out
	var vehicles: Dictionary = (reg["value"] as Dictionary).get("vehicles", {})
	for key in vehicles:
		var profile := str((vehicles[key] as Dictionary).get("Profile", ""))
		if profile.is_empty():
			continue
		out.append(PROFILE_BASE + profile + "/vehicle.json")
	return out


func run_validation_checks() -> void:
	var manifests := _profile_manifests()
	check(manifests.size() == 11, "11 perfiles vigentes (hay %d)" % manifests.size())
	var saab_curve_parity := 0.0
	for manifest in manifests:
		var loaded := VehicleProfileLoader.load_profile(manifest)
		check(bool(loaded.get("ok", false)), "loader ok: " + manifest + " " + str(loaded.get("error", "")))
		if not bool(loaded.get("ok", false)):
			continue
		var model := VehiclePowertrainModel.new()
		var result := model.configure(loaded["domains"])
		check(bool(result.get("ok", false)), "configure ok: " + manifest + " " + str(result.get("error", "")))
		if manifest == SAAB_MANIFEST and bool(result.get("ok", false)):
			saab_curve_parity = model._evaluate_torque_curve(0.6)
	check(absf(saab_curve_parity - 0.976) < 0.000001, "curva saab 0.6 -> 0.976 (dominio 0-1 intacto)")
	var empty_model := VehiclePowertrainModel.new()
	check(absf(empty_model._evaluate_torque_curve(0.4) - 1.0) < 0.000001, "curva ausente: fallback 1.0")
	var loaded_saab := VehicleProfileLoader.load_profile(SAAB_MANIFEST)
	var last_x := -1.0
	for point in (loaded_saab["domains"] as Dictionary)["powertrain"]["powertrain"]["torque_curve"]:
		last_x = float(point[0])
	check(last_x > 1.0, "curva: se conservan puntos por encima de 1")
	var probe := VehiclePowertrainModel.new()
	probe.configure(loaded_saab["domains"])
	check(absf(probe._evaluate_torque_curve(1.2) - 0.4) < 0.000001, "curva: consulta limitada a 0-1")
	# Entradas inválidas: error que identifica campo (e índice en listas).
	var base: Dictionary = (loaded_saab["domains"] as Dictionary).duplicate(true)
	var bad_missing := base.duplicate(true)
	(bad_missing["powertrain"] as Dictionary)["powertrain"].erase("max_torque")
	var r_missing := VehiclePowertrainModel.validate_powertrain_config(bad_missing)
	check(not bool(r_missing.get("ok", false)) and str(r_missing.get("error", "")).contains("max_torque"), "invalido: torque ausente")
	var bad_final := base.duplicate(true)
	var bad_final_pt: Dictionary = (bad_final["powertrain"] as Dictionary)["powertrain"]
	bad_final_pt["final_drive"] = 0.0
	bad_final_pt["final_drive_gravel"] = 0.0
	bad_final_pt["final_drive_tarmac"] = 0.0
	var r_final := VehiclePowertrainModel.validate_powertrain_config(bad_final)
	check(not bool(r_final.get("ok", false)) and str(r_final.get("error", "")).contains("final_drive"), "invalido: relacion efectiva cero")
	var bad_gear := base.duplicate(true)
	((bad_gear["powertrain"] as Dictionary)["powertrain"]["gear_ratios"] as Array)[1] = -1.6
	var r_gear := VehiclePowertrainModel.validate_powertrain_config(bad_gear)
	check(not bool(r_gear.get("ok", false)) and str(r_gear.get("error", "")).contains("gear_ratios[1]"), "invalido: marcha negativa")
	var bad_nan := base.duplicate(true)
	(bad_nan["powertrain"] as Dictionary)["powertrain"]["max_torque"] = 0.0 / 0.0
	var r_nan := VehiclePowertrainModel.validate_powertrain_config(bad_nan)
	check(not bool(r_nan.get("ok", false)), "invalido: no finito")
	var bad_dup := base.duplicate(true)
	(bad_dup["powertrain"] as Dictionary)["powertrain"]["torque_curve"] = [[0.5, 0.5], [0.5, 0.6]]
	var r_dup := VehiclePowertrainModel.validate_powertrain_config(bad_dup)
	check(not bool(r_dup.get("ok", false)) and str(r_dup.get("error", "")).contains("torque_curve[1]"), "invalido: abscisas duplicadas")
	var bad_ord := base.duplicate(true)
	(bad_ord["powertrain"] as Dictionary)["powertrain"]["torque_curve"] = [[0.5, 0.5], [0.3, 0.6]]
	var r_ord := VehiclePowertrainModel.validate_powertrain_config(bad_ord)
	check(not bool(r_ord.get("ok", false)) and str(r_ord.get("error", "")).contains("torque_curve[1]"), "invalido: abscisas desordenadas")
	var bad_spool := base.duplicate(true)
	((bad_spool["powertrain"] as Dictionary)["powertrain"]["differential"] as Dictionary)["type"] = "spool"
	var r_spool := VehiclePowertrainModel.validate_powertrain_config(bad_spool)
	check(not bool(r_spool.get("ok", false)) and str(r_spool.get("error", "")).to_lower().contains("spool"), "invalido: spool")
	var bad_unknown := base.duplicate(true)
	((bad_unknown["powertrain"] as Dictionary)["powertrain"]["differential"] as Dictionary)["type"] = "torsen_x"
	var r_unknown := VehiclePowertrainModel.validate_powertrain_config(bad_unknown)
	check(not bool(r_unknown.get("ok", false)) and str(r_unknown.get("error", "")).contains("torsen_x"), "invalido: tipo desconocido")
	# Recarga inválida sobre modelo válido: conserva configuración y estado.
	var model := VehiclePowertrainModel.new()
	check(bool(model.configure(base).get("ok", false)), "recarga: base valida")
	model.current_gear = 3
	model.engine_rpm = 2500.0
	model.clutch_engagement = 0.8
	model.freewheel_active = true
	model.transmission_damage = 0.5
	var snap := {
		"ratios": model.gear_ratios.duplicate(),
		"peak": model.peak_torque_nm,
		"final": model.final_drive_ratio,
		"rpm": model.engine_rpm,
		"gear": model.current_gear,
		"clutch": model.clutch_engagement,
		"fw": model.freewheel_active,
		"type": model.differential_type,
		"damage": model.transmission_damage,
	}
	var r_bad := model.configure(bad_missing)
	check(not bool(r_bad.get("ok", false)), "recarga invalida rechazada")
	check(str(model.gear_ratios) == str(snap["ratios"]), "recarga: conserva marchas")
	check(model.peak_torque_nm == float(snap["peak"]), "recarga: conserva par maximo")
	check(model.final_drive_ratio == float(snap["final"]), "recarga: conserva final")
	check(model.engine_rpm == float(snap["rpm"]), "recarga: conserva rpm")
	check(model.current_gear == int(snap["gear"]), "recarga: conserva marcha")
	check(model.clutch_engagement == float(snap["clutch"]), "recarga: conserva embrague")
	check(model.freewheel_active == bool(snap["fw"]), "recarga: conserva rueda libre")
	check(model.differential_type == str(snap["type"]), "recarga: conserva diferencial")
	check(model.transmission_damage == float(snap["damage"]), "recarga: conserva dano")


func _awd_domains(split: float, front_type: String = "clutch_lsd", rear_type: String = "clutch_lsd") -> Dictionary:
	var block := func(dtype: String, preload_value: float) -> Dictionary:
		return {
			"type": dtype,
			"preload_nm": preload_value,
			"power_ramp_angle_deg": 45.0,
			"coast_ramp_angle_deg": 45.0,
			"clutches": 4.0,
			"clutch_friction_coefficient": 0.1,
			"coast_friction_coefficient": 0.1,
			"ramp_gain": 0.16,
		}
	return {
		"powertrain": {
			"powertrain": {
				"max_torque": 200.0,
				"max_rpm": 7000.0,
				"gear_ratios": [2.5, 1.6, 1.2, 1.0],
				"final_drive": 4.5,
				"front_torque_split": split,
				"differential_front": block.call(front_type, 40.0),
				"differential_rear": block.call(rear_type, 60.0),
			}
		},
		"tires": {"tires": {}},
	}


func _drive_awd(model: VehiclePowertrainModel) -> void:
	model.current_gear = 1
	model.engine_rpm = 3000.0
	model.clutch_engagement = 1.0
	model.input_shaft_omega_rad_s = 200.0


func run_differential_checks() -> void:
	# FWD y RWD vigentes con presets actuales.
	var saab := _configure_saab()
	if saab == null:
		return
	check(saab.front_differential_type == "clutch_lsd", "fwd saab: diferencial delante")
	check(saab.rear_differential_type == "open", "fwd saab: trasero abierto")
	check(saab.differential_type == saab.front_differential_type, "fwd saab: espejo historico = delantero")
	var loaded_escort := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	check(bool(loaded_escort.get("ok", false)), "escort loads")
	var escort := VehiclePowertrainModel.new()
	check(bool(escort.configure(loaded_escort["domains"]).get("ok", false)), "escort configure ok")
	check(escort.rear_differential_type == "clutch_lsd", "rwd escort: diferencial atras")
	check(escort.front_differential_type == "open", "rwd escort: delantero abierto")
	check(escort.differential_type == escort.rear_differential_type, "rwd escort: espejo historico = trasero")
	# AWD de prueba: barrido de reparto con adherencia desigual delante.
	var front_caps := {}
	var rear_caps := {}
	var front_torques := {}
	for split in [0.5, 0.95, 0.99, 1.0]:
		var model := VehiclePowertrainModel.new()
		var result := model.configure(_awd_domains(split))
		check(bool(result.get("ok", false)), "awd split %s configura" % str(split))
		_drive_awd(model)
		var spins: Array[float] = [30.0, 32.0, 30.0, 32.0]
		var inertias: Array[float] = [1.5, 1.5, 1.5, 1.5]
		var zeros: Array[float] = [0.0, 0.0, 0.0, 0.0]
		model.solve_rotation(0.002, spins, inertias, zeros, zeros)
		front_caps[split] = model.last_front_lsd_capacity_nm
		rear_caps[split] = model.last_rear_lsd_capacity_nm
		front_torques[split] = model.last_front_lsd_torque_nm
		if split < 1.0:
			check(float(front_caps[split]) > 0.0, "awd %s: LSD delantero actua antes de 1.00" % str(split))
			check(absf(float(front_torques[split])) > 0.0, "awd %s: par delantero no nulo" % str(split))
	check(float(front_caps[0.99]) > float(front_caps[0.5]), "awd: capacidad delantera sigue el reparto")
	check(float(rear_caps[0.5]) > float(rear_caps[0.99]), "awd: capacidad trasera sigue el reparto")
	check(float(rear_caps[1.0]) == 0.0, "awd 1.0: trasero sin bloqueo")
	var legacy_mirror := VehiclePowertrainModel.new()
	legacy_mirror.configure(_awd_domains(0.5))
	_drive_awd(legacy_mirror)
	var spins_m: Array[float] = [30.0, 32.0, 30.0, 32.0]
	var inertias_m: Array[float] = [1.5, 1.5, 1.5, 1.5]
	var zeros_m: Array[float] = [0.0, 0.0, 0.0, 0.0]
	legacy_mirror.solve_rotation(0.002, spins_m, inertias_m, zeros_m, zeros_m)
	check(legacy_mirror.last_diff_speed_rad_s == legacy_mirror.last_rear_diff_speed_rad_s, "telemetria: espejo = trasero si reparto < 1")
	# Tipo abierto: bloqueo cero; el par diferencial no acopla en neutro.
	var open_model := VehiclePowertrainModel.new()
	check(bool(open_model.configure(_awd_domains(1.0, "open", "open")).get("ok", false)), "open configura")
	open_model.current_gear = 0
	var spins_o: Array[float] = [10.0, 12.0, 20.0, 22.0]
	var before_o := spins_o.duplicate()
	open_model.solve_rotation(0.002, spins_o, inertias_m, zeros_m, zeros_m)
	check(str(spins_o) == str(before_o), "open: sin acoplamiento")
	check(open_model.last_front_lsd_capacity_nm == 0.0 and open_model.last_rear_lsd_capacity_nm == 0.0, "open: capacidad cero")
	check(open_model.last_front_lsd_torque_nm == 0.0 and open_model.last_rear_lsd_torque_nm == 0.0, "open: par cero")
	# Con precarga el eje motriz de fricción sí acopla en neutro; el abierto no.
	# (Reparto 0.5 para que ambos ejes tengan tracción; con 1.0 el trasero
	# queda sin tracción por diseño y tampoco acoplaría.)
	var mixed := VehiclePowertrainModel.new()
	check(bool(mixed.configure(_awd_domains(0.5, "open", "clutch_lsd")).get("ok", false)), "mixto configura")
	mixed.current_gear = 0
	var spins_x: Array[float] = [10.0, 12.0, 20.0, 22.0]
	mixed.solve_rotation(0.002, spins_x, inertias_m, zeros_m, zeros_m)
	check(absf(absf(spins_x[0] - spins_x[1]) - 2.0) < 0.0001, "mixto: eje abierto intacto")
	check(absf(spins_x[2] - spins_x[3]) < 1.9, "mixto: eje con precarga acopla")
	# spool se rechaza con error explícito; desconocidos también.
	var spool_preset := mixed.apply_differential_preset({"preset_id": "x", "type": "spool", "preload_nm": 10.0, "power_ramp_deg": 45.0, "coast_ramp_deg": 45.0, "active_friction_surfaces": 4})
	check(not bool(spool_preset.get("ok", false)), "preset spool rechazado")
	var awd_synth := _awd_domains(0.5)
	(awd_synth["powertrain"] as Dictionary)["powertrain"]["differential_front"]["type"] = "spool"
	var r_spool := VehiclePowertrainModel.validate_powertrain_config(awd_synth)
	check(not bool(r_spool.get("ok", false)) and str(r_spool.get("error", "")).to_lower().contains("spool"), "perfil spool rechazado")
	# apply con eje explícito no toca el espejo del otro eje.
	var rwd := VehiclePowertrainModel.new()
	rwd.configure(_awd_domains(0.0))
	var before_type := rwd.differential_type
	var before_preload := rwd.differential_preload_nm
	var applied := rwd.apply_differential_preset({"preset_id": "p", "type": "clutch_lsd", "preload_nm": 33.0, "power_ramp_deg": 30.0, "coast_ramp_deg": 60.0, "active_friction_surfaces": 4, "friction_mu_power": 0.1, "friction_mu_coast": 0.1}, "front")
	check(bool(applied.get("ok", false)), "preset a eje delantero aplica")
	check(rwd.front_differential_preload_nm == 33.0, "preset a eje delantero actualiza ese eje")
	check(rwd.differential_type == before_type and rwd.differential_preload_nm == before_preload, "preset a eje no seleccionado no toca espejo")


# H1: tipos estrictos. int/float finitos aceptados; bool, cadenas,
# diccionarios y no finitos rechazados con campo (e índice) en el error.
func run_type_checks() -> void:
	var loaded := VehicleProfileLoader.load_profile(SAAB_MANIFEST)
	var base: Dictionary = (loaded["domains"] as Dictionary).duplicate(true)
	var bad_string := base.duplicate(true)
	(bad_string["powertrain"] as Dictionary)["powertrain"]["max_torque"] = "195"
	var r_string := VehiclePowertrainModel.validate_powertrain_config(bad_string)
	check(not bool(r_string.get("ok", false)) and str(r_string.get("error", "")).contains("powertrain.max_torque"), "tipo: max_torque cadena")
	var bad_bool := base.duplicate(true)
	(bad_bool["powertrain"] as Dictionary)["powertrain"]["max_torque"] = true
	var r_bool := VehiclePowertrainModel.validate_powertrain_config(bad_bool)
	check(not bool(r_bool.get("ok", false)) and str(r_bool.get("error", "")).contains("powertrain.max_torque"), "tipo: max_torque bool")
	var bad_dict := base.duplicate(true)
	(bad_dict["powertrain"] as Dictionary)["powertrain"]["max_torque"] = {"v": 1.0}
	var r_dict := VehiclePowertrainModel.validate_powertrain_config(bad_dict)
	check(not bool(r_dict.get("ok", false)) and str(r_dict.get("error", "")).contains("powertrain.max_torque"), "tipo: max_torque dict")
	var bad_gear_bool := base.duplicate(true)
	((bad_gear_bool["powertrain"] as Dictionary)["powertrain"]["gear_ratios"] as Array)[0] = true
	var r_gear_bool := VehiclePowertrainModel.validate_powertrain_config(bad_gear_bool)
	check(not bool(r_gear_bool.get("ok", false)) and str(r_gear_bool.get("error", "")).contains("gear_ratios[0]"), "tipo: marcha bool")
	var bad_gear_str := base.duplicate(true)
	((bad_gear_str["powertrain"] as Dictionary)["powertrain"]["gear_ratios"] as Array)[1] = "1.6"
	var r_gear_str := VehiclePowertrainModel.validate_powertrain_config(bad_gear_str)
	check(not bool(r_gear_str.get("ok", false)) and str(r_gear_str.get("error", "")).contains("gear_ratios[1]"), "tipo: marcha cadena")
	var bad_final := base.duplicate(true)
	(bad_final["powertrain"] as Dictionary)["powertrain"]["final_drive"] = "4.5"
	var r_final := VehiclePowertrainModel.validate_powertrain_config(bad_final)
	check(not bool(r_final.get("ok", false)) and str(r_final.get("error", "")).contains("powertrain.final_drive"), "tipo: final cadena")
	var bad_final_bool := base.duplicate(true)
	(bad_final_bool["powertrain"] as Dictionary)["powertrain"]["final_drive_gravel"] = false
	var r_final_bool := VehiclePowertrainModel.validate_powertrain_config(bad_final_bool)
	check(not bool(r_final_bool.get("ok", false)) and str(r_final_bool.get("error", "")).contains("powertrain.final_drive_gravel"), "tipo: final bool")
	var bad_curve := base.duplicate(true)
	(bad_curve["powertrain"] as Dictionary)["powertrain"]["torque_curve"] = [[0.1, "x"], [0.2, 0.5]]
	var r_curve := VehiclePowertrainModel.validate_powertrain_config(bad_curve)
	check(not bool(r_curve.get("ok", false)) and str(r_curve.get("error", "")).contains("torque_curve[0]"), "tipo: curva cadena")
	var bad_curve_bool := base.duplicate(true)
	(bad_curve_bool["powertrain"] as Dictionary)["powertrain"]["torque_curve"] = [[true, 0.5]]
	var r_curve_bool := VehiclePowertrainModel.validate_powertrain_config(bad_curve_bool)
	check(not bool(r_curve_bool.get("ok", false)) and str(r_curve_bool.get("error", "")).contains("torque_curve[0]"), "tipo: curva bool")
	# int válido sigue aceptado (compatibilidad con JSON enteros).
	var ok_int := base.duplicate(true)
	(ok_int["powertrain"] as Dictionary)["powertrain"]["max_torque"] = 195
	((ok_int["powertrain"] as Dictionary)["powertrain"]["gear_ratios"] as Array)[0] = 3
	check(bool(VehiclePowertrainModel.validate_powertrain_config(ok_int).get("ok", false)), "tipo: int aceptado")
	# Recarga inválida por tipo conserva configuración y estado.
	var model := VehiclePowertrainModel.new()
	check(bool(model.configure(base).get("ok", false)), "tipo: base valida")
	model.current_gear = 3
	model.engine_rpm = 2500.0
	model.clutch_engagement = 0.8
	var r_bad := model.configure(bad_string)
	check(not bool(r_bad.get("ok", false)), "tipo: recarga con cadena rechazada")
	check(model.current_gear == 3, "tipo: recarga conserva marcha")
	check(model.engine_rpm == 2500.0, "tipo: recarga conserva rpm")
	check(model.clutch_engagement == 0.8, "tipo: recarga conserva embrague")
	check(model.peak_torque_nm == 195.0, "tipo: recarga conserva par maximo")
	check(str(model.gear_ratios) == str([2.64, 1.6, 1.19, 0.92]), "tipo: recarga conserva marchas")


# H2: objetivo de ralentí de rueda libre vía par. Perfil de prueba con
# freewheel.idle_rpm = 1400 y ralentí general 1000: el motor converge al
# objetivo configurado sin rampa directa de 4000 rpm/s.
func run_idle_target_checks() -> void:
	var loaded := VehicleProfileLoader.load_profile(SAAB_MANIFEST)
	var domains: Dictionary = (loaded["domains"] as Dictionary).duplicate(true)
	var pt: Dictionary = (domains["powertrain"] as Dictionary)["powertrain"]
	pt["idle_rpm"] = 1000.0
	(pt["freewheel"] as Dictionary)["idle_rpm"] = 1400.0
	var model := VehiclePowertrainModel.new()
	check(bool(model.configure(domains).get("ok", false)), "ralenti 1400: configura")
	model.freewheel_active = true
	var pull: float = model.engine_torque_at_rpm(1200.0, 0.0, 1.0)
	check(pull > 0.0, "ralenti 1400 libre: tira hacia arriba a 1200 (%.2f)" % pull)
	var push: float = model.engine_torque_at_rpm(1600.0, 0.0, 1.0)
	check(push < 0.0, "ralenti 1400 libre: empuja hacia abajo a 1600 (%.2f)" % push)
	model.freewheel_active = false
	var coupled: float = model.engine_torque_at_rpm(1200.0, 0.0, 1.0)
	check(coupled < 0.0, "ralenti 1000 acoplada: retiene a 1200 (%.2f)" % coupled)
	# Paridad estimación/integración también con el objetivo de rueda libre.
	model.engine_rpm = 1200.0
	model.freewheel_active = true
	var est: float = model.engine_torque_at_rpm(1200.0, 0.0, 1.0)
	model._advance_engine_torque(30.0, 0.0, 1.0)
	check(absf(model.engine_torque_nm - est) < 0.00001, "ralenti 1400: integracion == estimacion")
	# Caída gobernada por par/inercia hacia el objetivo, sin rampa directa:
	# la rampa de 4000 rpm/s cubriría 4000->1450 en ~150 pasos; el par
	# necesita varios segundos.
	model.engine_rpm = 4000.0
	model.current_gear = 3
	model.clutch_engagement = 1.0
	var ratio: float = model.gear_ratios[2] * model.final_drive_ratio
	var carrier := (4800.0 * TAU / 60.0) / ratio
	var steps := 0
	while model.engine_rpm > 1450.0 and steps < 2400:
		model.advance(1.0 / 240.0, 0.0, 1.0, 1.0, carrier)
		steps += 1
	check(model.engine_rpm <= 1450.0, "ralenti 1400: cae hacia el objetivo")
	check(steps > 300, "ralenti 1400: gobernada por par (%d pasos, sin rampa)" % steps)
	for i in 480:
		model.advance(1.0 / 240.0, 0.0, 1.0, 1.0, carrier)
	check(model.engine_rpm >= 1300.0 and model.engine_rpm <= 1450.0, "ralenti 1400: equilibrio en objetivo (%.0f)" % model.engine_rpm)


func _axle_snapshot(model: VehiclePowertrainModel, axle: String) -> Array:
	if axle == "front":
		return [model.front_differential_type, model.front_differential_preload_nm, model.front_differential_power_ratio, model.front_differential_coast_ratio, model.front_differential_power_ramp_angle_deg, model.front_differential_coast_ramp_angle_deg, model.front_differential_clutches, model.front_differential_ramp_gain, model.front_differential_preset_id]
	if axle == "rear":
		return [model.rear_differential_type, model.rear_differential_preload_nm, model.rear_differential_power_ratio, model.rear_differential_coast_ratio, model.rear_differential_power_ramp_angle_deg, model.rear_differential_coast_ramp_angle_deg, model.rear_differential_clutches, model.rear_differential_ramp_gain, model.rear_differential_preset_id]
	return [model.differential_type, model.differential_preload_nm, model.differential_power_ratio, model.differential_coast_ratio, model.differential_power_ramp_angle_deg, model.differential_coast_ramp_angle_deg, model.differential_clutches, model.differential_ramp_gain, model.differential_preset_id]


# H3: el setup conserva el diferencial por eje. En AWD cada eje se sincroniza
# desde su bloque; en FWD/RWD el histórico alimenta el eje motriz. Un reglaje
# ajeno al diferencial no debe alterar ningún eje.
func run_setup_axle_checks() -> void:
	RallyDifferentialCatalog.set_mode_override(RallyDifferentialCatalog.MODE_MODERN)
	var scene = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 180:
		await physics_frame
		if scene.get_node_or_null("FordEscortRS2000") != null and scene.get_node("FordEscortRS2000").simulation != null and not scene.get_node("FordEscortRS2000").simulation.domains.is_empty():
			break
	var vehicle = scene.get_node("FordEscortRS2000")
	if vehicle == null or vehicle.simulation == null or vehicle.simulation.domains.is_empty():
		check(false, "setup ejes: vehiculo listo")
		return
	var sim = vehicle.simulation
	# RWD vigente: el bloque histórico alimenta espejo + eje motriz vía setup.
	var base: Dictionary = sim.setup_design_values.duplicate(true)
	var payload: Dictionary = base.duplicate(true)
	payload["powertrain.differential.preload_nm"] = 77.0
	var applied: Dictionary = sim.apply_setup_values(payload)
	check(bool(applied.get("ok", false)), "setup rwd: aplica (" + str(applied.get("error", "")) + ")")
	check(sim.powertrain_model.differential_preload_nm == 77.0, "setup rwd: espejo 77")
	check(sim.powertrain_model.rear_differential_preload_nm == 77.0, "setup rwd: eje motriz 77")
	check(sim.powertrain_model.front_differential_type == "open", "setup rwd: delantero sigue abierto")
	check(sim.powertrain_model.front_differential_preload_nm == 0.0, "setup rwd: delantero intacto")
	# AWD de prueba con precargas y rampas distintas por eje.
	var pt: Dictionary = (sim.domains["powertrain"] as Dictionary)["powertrain"]
	pt["front_torque_split"] = 0.5
	pt["differential_front"] = {"type": "clutch_lsd", "preload_nm": 40.0, "power_ramp_angle_deg": 45.0, "coast_ramp_angle_deg": 45.0, "clutches": 4.0, "clutch_friction_coefficient": 0.1, "coast_friction_coefficient": 0.08, "ramp_gain": 0.16}
	pt["differential_rear"] = {"type": "clutch_lsd", "preload_nm": 60.0, "power_ramp_angle_deg": 30.0, "coast_ramp_angle_deg": 60.0, "clutches": 6.0, "clutch_friction_coefficient": 0.12, "coast_friction_coefficient": 0.10, "ramp_gain": 0.20}
	var configured: Dictionary = sim.powertrain_model.configure(sim.domains)
	check(bool(configured.get("ok", false)), "setup awd: configura (" + str(configured.get("error", "")) + ")")
	var snap_front := _axle_snapshot(sim.powertrain_model, "front")
	var snap_rear := _axle_snapshot(sim.powertrain_model, "rear")
	check(sim.powertrain_model.front_differential_preload_nm == 40.0, "setup awd: delantera 40")
	check(sim.powertrain_model.rear_differential_preload_nm == 60.0, "setup awd: trasera 60")
	# Reglaje ajeno al diferencial.
	var payload2: Dictionary = base.duplicate(true)
	var fuel_now := float(payload2.get("fuel.initial_kg", 25.0))
	payload2["fuel.initial_kg"] = 20.0 if fuel_now != 20.0 else 30.0
	var applied2: Dictionary = sim.apply_setup_values(payload2)
	check(bool(applied2.get("ok", false)), "setup awd: aplica ajeno (" + str(applied2.get("error", "")) + ")")
	check(str(_axle_snapshot(sim.powertrain_model, "front")) == str(snap_front), "setup awd: delantera intacta")
	check(str(_axle_snapshot(sim.powertrain_model, "rear")) == str(snap_rear), "setup awd: trasera intacta")
	check(sim.powertrain_model.differential_preload_nm == 60.0, "setup awd: espejo sigue al trasero")
	RallyDifferentialCatalog.set_mode_override(RallyDifferentialCatalog.MODE_MODERN)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	run_freewheel_checks()
	run_torque_checks()
	run_idle_target_checks()
	run_type_checks()
	run_validation_checks()
	run_differential_checks()
	run_setup_axle_checks()
	print("POWERTRAIN_CORRECTION_CONTRACT ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
