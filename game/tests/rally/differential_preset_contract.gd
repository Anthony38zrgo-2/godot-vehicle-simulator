extends SceneTree

# Contrato de regresión P0: presets históricos de diferencial.
# - Fix 1: los identificadores reales (lancia_fulvia_1600_hf,
#   ford_escort_rs2000_1971) resuelven preset histórico (no legacy).
# - Fix 2: preset_id inválido ("", null, 123, otro coche, deshabilitado)
#   se rechaza sin mutar domains, solver ni preset activo.
# Sin cambios de calibración física.
# Ejecución: godot --headless --path game --script res://tests/rally/differential_preset_contract.gd

# preload directo: no depende de la caché global de clases del editor.
const RallyDifferentialCatalog = preload("res://scripts/rally/rally_differential_catalog.gd")

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func run_catalog_checks() -> void:
	var catalog_check := RallyDifferentialCatalog.validate_catalog()
	check(bool(catalog_check.get("ok", false)), "catalog validates")
	# Fix 1: identificadores reales resuelven.
	check(not RallyDifferentialCatalog.list_for_profile("lancia_fulvia_1600_hf").is_empty(), "fulvia real id covered")
	check(not RallyDifferentialCatalog.list_for_profile("ford_escort_rs2000_1971").is_empty(), "escort real id covered")
	check(RallyDifferentialCatalog.default_for_profile("lancia_fulvia_1600_hf") == "fulvia_gr4", "fulvia default fulvia_gr4")
	check(RallyDifferentialCatalog.default_for_profile("ford_escort_rs2000_1971") == "escort_tierra", "escort default escort_tierra")
	# Aliases previos siguen funcionando.
	check(RallyDifferentialCatalog.default_for_profile("lancia-fulvia") == "fulvia_gr4", "legacy fulvia alias kept")
	check(RallyDifferentialCatalog.default_for_profile("ford-escort-rs2000") == "escort_tierra", "legacy escort alias kept")
	# Aislamiento por coche.
	check(not RallyDifferentialCatalog.is_allowed("rt-mini-cooper-s", "stratos_tierra"), "stratos preset rejected for mini")
	check(not RallyDifferentialCatalog.is_allowed("rt-mini-cooper-s", "no_existe"), "unknown preset rejected")
	# R-Lock deshabilitado.
	check(not RallyDifferentialCatalog.is_enabled("rt-saab-96-v4", "saab_r_lock"), "r-lock disabled")
	check(not bool(RallyDifferentialCatalog.resolve("rt-saab-96-v4", "saab_r_lock", {}).get("ok", false)), "r-lock resolve fails")
	# Datos de la especificación.
	var mini := RallyDifferentialCatalog.resolve("rt-mini-cooper-s", "mini_asfalto", {"power": 0.09, "coast": 0.05})
	check(bool(mini.get("ok", false)) and float(mini.get("power_ramp_deg", 0.0)) == 45.0 and float(mini.get("coast_ramp_deg", 0.0)) == 80.0, "mini_asfalto 45/80")
	var tierra := RallyDifferentialCatalog.resolve("rt-lancia-stratos", "stratos_tierra", {"power": 0.1, "coast": 0.08})
	check(bool(tierra.get("ok", false)) and int(tierra.get("active_friction_surfaces", 0)) == 6, "stratos_tierra 6 surfaces")
	var fulvia := RallyDifferentialCatalog.resolve("lancia-fulvia", "fulvia_gr4", {"power": 0.1, "coast": 0.03})
	check(bool(fulvia.get("ok", false)) and float(fulvia.get("power_ramp_deg", 0.0)) == 45.0 and float(fulvia.get("coast_ramp_deg", 0.0)) == 75.0, "fulvia_gr4 45/75")
	check(float(fulvia.get("friction_mu_power", 0.0)) != float(fulvia.get("friction_mu_coast", 0.0)), "coast stays distinct from power")
	var amazon := RallyDifferentialCatalog.resolve("rt-volvo-amazon", "amazon_rsport", {"power": 0.11, "coast": 0.09})
	check(bool(amazon.get("ok", false)) and float(amazon.get("preload_nm", 0.0)) == 107.5, "rsport seed 107.5")


func run_model_checks() -> void:
	var model := VehiclePowertrainModel.new()
	# Estado intacto ante presets inválidos.
	var before := [model.differential_preload_nm, model.differential_power_ratio, model.differential_type, model.differential_preset_id]
	check(not bool(model.apply_differential_preset({}).get("ok", false)), "empty preset rejected")
	check(not bool(model.apply_differential_preset({"preset_id": "", "type": "clutch_lsd", "preload_nm": 10.0, "power_ramp_deg": 45.0, "coast_ramp_deg": 45.0, "active_friction_surfaces": 4}).get("ok", false)), "empty id rejected")
	check(not bool(model.apply_differential_preset({"preset_id": "x", "type": "spool", "preload_nm": 10.0, "power_ramp_deg": 45.0, "coast_ramp_deg": 45.0, "active_friction_surfaces": 4}).get("ok", false)), "spool type rejected")
	check(not bool(model.apply_differential_preset({"preset_id": "x", "type": "clutch_lsd", "preload_nm": 10.0, "power_ramp_deg": 45.0, "coast_ramp_deg": 45.0, "active_friction_surfaces": 0}).get("ok", false)), "zero surfaces rejected")
	check(not bool(model.apply_differential_preset({"preset_id": "x", "type": "clutch_lsd", "preload_nm": -5.0, "power_ramp_deg": 45.0, "coast_ramp_deg": 45.0, "active_friction_surfaces": 4}).get("ok", false)), "negative preload rejected")
	var after := [model.differential_preload_nm, model.differential_power_ratio, model.differential_type, model.differential_preset_id]
	check(str(before) == str(after), "model untouched after rejections")
	var good := model.apply_differential_preset({"preset_id": "escort_tierra", "type": "clutch_lsd", "preload_nm": 75.0, "power_ramp_deg": 30.0, "coast_ramp_deg": 60.0, "active_friction_surfaces": 4, "friction_mu_power": 0.12, "friction_mu_coast": 0.10})
	check(bool(good.get("ok", false)), "valid preset applies")
	check(model.differential_preload_nm == 75.0 and model.differential_clutches == 4.0 and model.differential_type == "clutch_lsd", "surfaces drive clutches")
	check(model.differential_power_ratio != model.differential_coast_ratio, "mu power/coast independent")


func run_setup_catalog_checks() -> void:
	# Modo modern (defecto): los 4 números del LSD libre vuelven a existir
	# como campos numéricos (ya no se rechazan como "incompatible").
	for path in [
		"powertrain.differential.preload_nm",
		"powertrain.differential.power_ramp_angle_deg",
		"powertrain.differential.coast_ramp_angle_deg",
		"powertrain.differential.clutches",
	]:
		check(not RallySetupCatalog.field_for_path(path).is_empty(), "modern exposes " + path)
	var partial := RallySetupCatalog.validate({"powertrain.differential.preload_nm": 55.0})
	check(not bool(partial.get("ok", false)) and not str(partial.get("error", "")).to_lower().contains("incompatible"), "no incompatible rejection in modern")
	check(RallyDifferentialCatalog.differential_mode() == RallyDifferentialCatalog.MODE_MODERN, "modern is default")


func diff_state(vehicle: Node) -> String:
	var d: Dictionary = (vehicle.simulation.domains.get("powertrain", {}) as Dictionary).get("powertrain", {}).get("differential", {})
	return JSON.stringify({
		"preset": vehicle.simulation.active_differential_preset_id,
		"preload": float(d.get("preload_nm", -1.0)),
		"power_ramp": float(d.get("power_ramp_angle_deg", -1.0)),
		"coast_ramp": float(d.get("coast_ramp_angle_deg", -1.0)),
		"clutches": float(d.get("clutches", -1.0)),
		"solver_preload": vehicle.simulation.powertrain_model.differential_preload_nm,
	})


func run_vehicle_checks(vehicle: Node) -> void:
	var pid: String = vehicle.simulation.active_differential_profile()
	check(pid == "ford_escort_rs2000_1971", "active profile is real escort id")
	# Fix 1: preset histórico cargado automáticamente, sin legacy.
	check(vehicle.simulation.active_differential_preset_id == "escort_tierra", "escort auto-loads escort_tierra")
	check(not RallyDifferentialCatalog.list_for_profile(pid).is_empty(), "garage resolves catalog (no legacy)")
	var pm = vehicle.simulation.powertrain_model
	check(pm.differential_preload_nm == 75.0, "seed preload 75 applied")
	check(pm.differential_power_ramp_angle_deg == 30.0 and pm.differential_coast_ramp_angle_deg == 60.0, "tierra ramps 30/60")
	check(pm.differential_clutches == 4.0 and pm.differential_type == "clutch_lsd", "4 surfaces / clutch_lsd")
	check(pm.differential_power_ratio == 0.12 and pm.differential_coast_ratio == 0.10, "mu inherited from base, distinct")
	var base = vehicle.simulation.setup_design_values.duplicate(true)
	var frozen := diff_state(vehicle)
	# Fix 2: inválidos rechazados sin mutar nada.
	for bad in ["", 123, null, "stratos_tierra", "saab_r_lock"]:
		var payload = base.duplicate(true)
		payload["powertrain.differential.preset_id"] = bad
		var result = vehicle.apply_setup_values(payload)
		check(not bool(result.get("ok", false)), "rejected: " + str(bad))
		check(diff_state(vehicle) == frozen, "state frozen after: " + str(bad))
	# Legacy numérico rechazado con aviso de migración.
	var legacy_payload = base.duplicate(true)
	legacy_payload["powertrain.differential.preload_nm"] = 55.0
	var legacy_result = vehicle.apply_setup_values(legacy_payload)
	check(not bool(legacy_result.get("ok", false)), "legacy numeric rejected")
	check(diff_state(vehicle) == frozen, "state frozen after legacy")
	# Válido aceptado.
	var good_payload = base.duplicate(true)
	good_payload["powertrain.differential.preset_id"] = "escort_asfalto"
	var good_result = vehicle.apply_setup_values(good_payload)
	check(bool(good_result.get("ok", false)), "escort_asfalto accepted")
	check(vehicle.simulation.active_differential_preset_id == "escort_asfalto", "active preset switches")
	check(vehicle.simulation.powertrain_model.differential_power_ramp_angle_deg == 45.0 and vehicle.simulation.powertrain_model.differential_coast_ramp_angle_deg == 45.0, "asfalto ramps 45/45")
	# Campo ausente conserva el activo.
	var keep_payload = base.duplicate(true)
	keep_payload.erase("powertrain.differential.preset_id")
	var keep_result = vehicle.apply_setup_values(keep_payload)
	check(bool(keep_result.get("ok", false)), "absent field accepted")
	check(vehicle.simulation.active_differential_preset_id == "escort_asfalto", "absent field keeps active")


func run_modern_checks(vehicle: Node) -> void:
	RallyDifferentialCatalog.set_mode_override(RallyDifferentialCatalog.MODE_MODERN)
	check(not vehicle.simulation.is_historic_differential(), "modern disables catalog")
	# Números libres aceptados, como antes de los presets.
	var payload = vehicle.simulation.filter_garage_values(RallySetupCatalog.defaults(vehicle.simulation.domains))
	check(payload.has("powertrain.differential.preload_nm"), "modern draft has free fields")
	check(not payload.has("powertrain.differential.preset_id"), "modern draft has no preset")
	payload["powertrain.differential.preload_nm"] = 40.0
	payload["powertrain.differential.power_ramp_angle_deg"] = 35.0
	payload["powertrain.differential.coast_ramp_angle_deg"] = 65.0
	payload["powertrain.differential.clutches"] = 6.0
	var result = vehicle.apply_setup_values(payload)
	check(bool(result.get("ok", false)), "free LSD applies")
	check(vehicle.simulation.active_differential_preset_id == "", "no active preset in modern")
	var pm = vehicle.simulation.powertrain_model
	check(pm.differential_preload_nm == 40.0, "free preload 40 applied")
	check(pm.differential_power_ramp_angle_deg == 35.0 and pm.differential_coast_ramp_angle_deg == 65.0, "free ramps applied")
	check(pm.differential_clutches == 6.0, "free clutches applied")
	# preset_id presente se ignora en modern: manda el LSD libre.
	var ignored = vehicle.simulation.filter_garage_values(RallySetupCatalog.defaults(vehicle.simulation.domains))
	ignored["powertrain.differential.preset_id"] = "escort_tierra"
	ignored["powertrain.differential.preload_nm"] = 50.0
	var ignored_result = vehicle.apply_setup_values(ignored)
	check(bool(ignored_result.get("ok", false)), "preset ignored in modern")
	check(vehicle.simulation.powertrain_model.differential_preload_nm == 50.0, "free value wins in modern")
	check(vehicle.simulation.active_differential_preset_id == "", "still no active preset")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	run_catalog_checks()
	run_model_checks()
	run_setup_catalog_checks()
	# La parte de vehículo se prueba en historic; el modo por defecto
	# del juego es modern y se cubre después en run_modern_checks.
	RallyDifferentialCatalog.set_mode_override(RallyDifferentialCatalog.MODE_HISTORIC)
	var scene = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 180:
		await physics_frame
		if scene.get_node_or_null("FordEscortRS2000") != null and scene.get_node("FordEscortRS2000").simulation != null and not scene.get_node("FordEscortRS2000").simulation.domains.is_empty():
			break
	var vehicle = scene.get_node("FordEscortRS2000")
	if vehicle == null or vehicle.simulation == null or vehicle.simulation.domains.is_empty():
		check(false, "proving ground vehicle ready")
	else:
		run_vehicle_checks(vehicle)
		run_modern_checks(vehicle)
	RallyDifferentialCatalog.set_mode_override(RallyDifferentialCatalog.MODE_MODERN)
	print("DIFFERENTIAL_PRESET_CONTRACT ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
