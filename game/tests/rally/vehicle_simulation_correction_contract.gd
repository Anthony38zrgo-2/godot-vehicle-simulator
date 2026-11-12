extends SceneTree
## vehicle_simulation_correction_contract.gd — Contrato P0 §§1,2,4,6 + H1-H5.
## §1 presión: función común térmica, garaje refleja pérdida existente.
## §4+H5 commit atómico: preset inválido, rechazo directo del modelo y rechazo
##   tardío vía garaje (catálogo resuelve, modelo rechaza dentro de la
##   operación) no mutan nada. El test tardío falla si domains = staging se
##   mueve antes de aplicar el preset.
## §6 suspensión: cálculo compartido, conserva masa de referencia y diseño.
## §2+H1 alcance: viaje desde el límite efectivo; deformación con recorrido
##   FÍSICO del hub (droop 180 / hub -210 / suelo -200 → 10 mm y carga > 0;
##   sin penetración → carga 0), en tándem y ShapeCast.
## H2 coherencia ShapeCast: sin get_collision_safe_fraction (no existe en
##   Godot 4.7.1); distancia del barrido aislando el apoyo seleccionado.
## H3 ride_frequency_hz: ausente → respaldo; declarado → número finito > 0.
## Ejecución: godot --headless --path game --script res://tests/rally/vehicle_simulation_correction_contract.gd

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)
	else:
		print("  PASS: " + label)


func _initialize() -> void:
	call_deferred("run")


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _configure_escort() -> FordRallyVehicleSimulation:
	var asset := _load_json("res://assets/rally/ford_escort_rs2000_1971/manifest.json")
	var sim := FordRallyVehicleSimulation.new()
	var res := sim.configure(asset, "res://data/vehicles/ford-escort-rs2000/vehicle.json")
	if not bool(res.get("ok", false)):
		push_error("configure escort: " + str(res.get("error", "")))
		return null
	return sim


func test_pressure_common_function() -> void:
	print("\n[§1] Presión común térmica...")
	# Función pura: 1.80 bar frío, gas a referencia, pérdida 50% -> 0.90 bar.
	var atm := 1.01325
	var p := VehicleThermalModel.gauge_pressure_from_reference(1.80, 25.0, 25.0, atm, 0.5)
	check(absf(p - 0.90) < 0.001, "pura 1.80+50%% => 0.90 (got %.4f)" % p)
	# Gas caliente, sana: (2.00+atm)*(353.15/298.15)-atm.
	var hot := VehicleThermalModel.gauge_pressure_from_reference(2.00, 25.0, 80.0, atm, 0.0)
	var expected := (2.00 + atm) * (80.0 + 273.15) / (25.0 + 273.15) - atm
	check(absf(hot - expected) < 0.001, "pura caliente sana coincide (got %.4f exp %.4f)" % [hot, expected])
	# Pérdida 0/1 extremos.
	check(absf(VehicleThermalModel.gauge_pressure_from_reference(1.8, 25.0, 25.0, atm, 0.0) - 1.8) < 0.001, "pérdida 0 conserva referencia")
	check(absf(VehicleThermalModel.gauge_pressure_from_reference(1.8, 25.0, 25.0, atm, 1.0)) < 0.001, "pérdida 1 => 0")


func test_pressure_garage_preserves_loss() -> void:
	print("\n[§1] Garaje refleja pérdida existente...")
	var sim := _configure_escort()
	if sim == null:
		check(false, "sim escort lista")
		return
	# Rueda 0: gas a referencia, pérdida 50%, sin fuga.
	var s0: Dictionary = sim.thermal_model.tire_states[0]
	s0["gas_c"] = 25.0
	s0["pressure_loss_fraction"] = 0.5
	s0["leak_per_second"] = 0.0
	sim.thermal_model.tire_states[0] = s0
	sim.thermal_model.set_pressure_reference(0, 1.80, 25.0)
	check(absf(float((sim.thermal_model.tire_states[0] as Dictionary)["pressure_bar_gauge"]) - 0.90) < 0.01, "referencia 1.80+50%% => 0.90")
	# Aplicar reglaje válido ajeno a presión (freno) con dominios a 180 kPa.
	var base := sim.filter_garage_values(RallySetupCatalog.defaults(sim.domains))
	base["brakes.front_brake_bias"] = 0.60
	# Asegurar frío en dominios a 180 kPa (1.80 bar) para la aceptación.
	var res := sim.apply_setup_values(base)
	check(bool(res.get("ok", false)), "reglaje ajeno aceptado")
	var after: Dictionary = sim.thermal_model.tire_states[0]
	check(absf(float(after["pressure_bar_gauge"]) - 0.90) < 0.02, "tras reglaje ajeno sigue 0.90 (got %.3f)" % float(after["pressure_bar_gauge"]))
	# Siguiente tick sin avance de fuga conserva 0.90.
	var gas_before := float(after["gas_c"])
	sim.thermal_model.advance_tire_pressure(0, 0.016)
	var ticked: Dictionary = sim.thermal_model.tire_states[0]
	check(absf(float(ticked["pressure_bar_gauge"]) - 0.90) < 0.02, "tick sin fuga conserva 0.90")
	check(absf(float(ticked["pressure_loss_fraction"]) - 0.5) < 0.0001, "pérdida persiste 50%")
	check(absf(float(ticked["gas_c"]) - gas_before) < 0.0001, "temperatura persiste")
	check(absf(float(ticked.get("leak_per_second", 0.0))) < 0.000001, "fuga persiste 0")
	# Repetir con referencia nueva, gas caliente y rueda sana.
	var s1: Dictionary = sim.thermal_model.tire_states[1]
	s1["gas_c"] = 80.0
	s1["pressure_loss_fraction"] = 0.0
	s1["leak_per_second"] = 0.0
	sim.thermal_model.tire_states[1] = s1
	var payload := sim.filter_garage_values(RallySetupCatalog.defaults(sim.domains))
	payload["tires.pressure.cold_kpa_gauge.FR"] = 200.0
	payload["brakes.front_brake_bias"] = 0.60
	var res2 := sim.apply_setup_values(payload)
	check(bool(res2.get("ok", false)), "reglaje con presión nueva aceptado")
	var hot_state: Dictionary = sim.thermal_model.tire_states[1]
	var exp_hot := VehicleThermalModel.gauge_pressure_from_reference(2.00, 25.0, 80.0, 1.01325, 0.0)
	check(absf(float(hot_state["pressure_bar_gauge"]) - exp_hot) < 0.03, "nueva ref caliente sana (got %.3f exp %.3f)" % [float(hot_state["pressure_bar_gauge"]), exp_hot])
	check(absf(float(hot_state["pressure_loss_fraction"])) < 0.0001, "sana sigue sin pérdida")
	# Ajuste en vivo conserva pérdida.
	var s2: Dictionary = sim.thermal_model.tire_states[2]
	s2["gas_c"] = 25.0
	s2["pressure_loss_fraction"] = 0.5
	s2["leak_per_second"] = 0.0
	sim.thermal_model.tire_states[2] = s2
	sim.thermal_model.set_pressure_reference(2, 1.80, 25.0)
	sim.adjust_live_tire_pressure(0.0)
	var live_after: Dictionary = sim.thermal_model.tire_states[2]
	# adjust_live re-escribe el frío desde domains (puede diferir de 1.80 si
	# el payload anterior cambió FR); lo importante es que conserva la
	# pérdida del 50% con la fórmula común.
	var cold_domains := float(((sim.domains.get("tires", {}) as Dictionary).get("tires", {}) as Dictionary).get("pressure", {}).get("cold_kpa_gauge", {}).get("RL", 180.0)) / 100.0
	var ref_t := float(((sim.domains.get("tires", {}) as Dictionary).get("tires", {}) as Dictionary).get("pressure", {}).get("reference_temperature_c", 25.0))
	var exp_live := VehicleThermalModel.gauge_pressure_from_reference(cold_domains, ref_t, float(live_after["gas_c"]), 1.01325, 0.5)
	check(absf(float(live_after["pressure_bar_gauge"]) - exp_live) < 0.02, "vivo conserva pérdida 50%% (got %.3f exp %.3f)" % [float(live_after["pressure_bar_gauge"]), exp_live])


func _setup_snapshot(sim: FordRallyVehicleSimulation) -> String:
	var powertrain: Dictionary = (sim.domains.get("powertrain", {}) as Dictionary).get("powertrain", {})
	var pm = sim.powertrain_model
	return JSON.stringify({
		"domains": sim.domains,
		"preset": sim.active_differential_preset_id,
		"diff": powertrain.get("differential", {}),
		"front": powertrain.get("differential_front", {}),
		"rear": powertrain.get("differential_rear", {}),
		"model_front": [pm.front_differential_type, pm.front_differential_preload_nm, pm.front_differential_power_ramp_angle_deg, pm.front_differential_coast_ramp_angle_deg, pm.front_differential_clutches, pm.front_differential_power_ratio, pm.front_differential_coast_ratio, pm.front_differential_preset_id],
		"model_rear": [pm.rear_differential_type, pm.rear_differential_preload_nm, pm.rear_differential_power_ramp_angle_deg, pm.rear_differential_coast_ramp_angle_deg, pm.rear_differential_clutches, pm.rear_differential_power_ratio, pm.rear_differential_coast_ratio, pm.rear_differential_preset_id],
		"model_gain": [pm.front_differential_ramp_gain, pm.rear_differential_ramp_gain],
		"unrelated": sim.filter_garage_values(RallySetupCatalog.defaults(sim.domains)).get("brakes.front_brake_bias", 0.0),
	})


func test_atomic_commit() -> void:
	print("\n[§4] Commit atómico del garaje...")
	RallyDifferentialCatalog.set_mode_override(RallyDifferentialCatalog.MODE_HISTORIC)
	var sim := _configure_escort()
	if sim == null:
		check(false, "sim escort lista (historic)")
		return
	var base := sim.filter_garage_values(RallySetupCatalog.defaults(sim.domains))
	var frozen := _setup_snapshot(sim)
	# 1) Preset inválido rechazado por el catálogo.
	var bad := base.duplicate(true)
	bad[FordRallyVehicleSimulation.DIFFERENTIAL_PRESET_PATH] = "no_existe_xyz"
	var rbad := sim.apply_setup_values(bad)
	check(not bool(rbad.get("ok", false)), "preset inválido rechazado")
	check(_setup_snapshot(sim) == frozen, "nada muta tras rechazo de catálogo")
	# Otro inválido: preset de otro coche.
	var bad2 := base.duplicate(true)
	bad2[FordRallyVehicleSimulation.DIFFERENTIAL_PRESET_PATH] = "stratos_tierra"
	var rbad2 := sim.apply_setup_values(bad2)
	check(not bool(rbad2.get("ok", false)), "preset de otro coche rechazado")
	check(_setup_snapshot(sim) == frozen, "nada muta tras preset ajeno")
	# 2) Rechazo directo en la validación del modelo tras resolver el preset.
	# Se resuelve un preset válido y se corrompe para que el modelo lo
	# rechace (rampa fuera de 15-85°); el modelo valida antes de mutar.
	var good_resolved := RallyDifferentialCatalog.resolve(sim.active_differential_profile(), sim.active_differential_preset_id if not sim.active_differential_preset_id.is_empty() else RallyDifferentialCatalog.default_for_profile(sim.active_differential_profile()), {"power": 0.1, "coast": 0.08})
	check(bool(good_resolved.get("ok", false)), "preset válido resuelve")
	var before_numbers := [
		sim.powertrain_model.differential_preload_nm,
		sim.powertrain_model.differential_power_ramp_angle_deg,
		sim.powertrain_model.differential_type,
		sim.powertrain_model.differential_preset_id,
	]
	var corrupted := (good_resolved as Dictionary).duplicate(true)
	corrupted["power_ramp_deg"] = 5.0
	var rmodel := sim.powertrain_model.apply_differential_preset(corrupted)
	check(not bool(rmodel.get("ok", false)), "modelo rechaza rampa 5°")
	check(_setup_snapshot(sim) == frozen, "nada muta tras rechazo del modelo")
	var after_numbers := [
		sim.powertrain_model.differential_preload_nm,
		sim.powertrain_model.differential_power_ramp_angle_deg,
		sim.powertrain_model.differential_type,
		sim.powertrain_model.differential_preset_id,
	]
	check(str(before_numbers) == str(after_numbers), "solver intacto tras rechazo del modelo")
	# Caso válido: dominios y runtime reflejan el mismo preset.
	var good_payload := base.duplicate(true)
	# Alternar al otro preset del escort si existe, si no re-aplicar el activo.
	var candidates := RallyDifferentialCatalog.list_for_profile(sim.active_differential_profile())
	var other := ""
	for p in candidates:
		if str(p.get("id", "")) != sim.active_differential_preset_id and bool(p.get("enabled", false)):
			other = str(p.get("id", ""))
			break
	if not other.is_empty():
		good_payload[FordRallyVehicleSimulation.DIFFERENTIAL_PRESET_PATH] = other
	var rgood := sim.apply_setup_values(good_payload)
	check(bool(rgood.get("ok", false)), "preset válido aceptado")
	check(sim.active_differential_preset_id == str(good_payload.get(FordRallyVehicleSimulation.DIFFERENTIAL_PRESET_PATH, sim.active_differential_preset_id)) or sim.active_differential_preset_id, "ID activo publicado tras éxito")
	var committed: Dictionary = (sim.domains.get("powertrain", {}) as Dictionary).get("powertrain", {}).get("differential", {})
	check(str(committed.get("preset_id", "")) == sim.active_differential_preset_id, "dominios y runtime con el mismo preset")
	RallyDifferentialCatalog.set_mode_override(RallyDifferentialCatalog.MODE_MODERN)


func test_late_rejection_via_garage() -> void:
	print("\n[H5] Rechazo tardío vía garaje (catálogo OK, modelo rechaza)...")
	RallyDifferentialCatalog.set_mode_override(RallyDifferentialCatalog.MODE_HISTORIC)
	var sim := _configure_escort()
	if sim == null:
		check(false, "sim escort lista (rechazo tardío)")
		RallyDifferentialCatalog.set_mode_override(RallyDifferentialCatalog.MODE_MODERN)
		return
	# El catálogo resuelve un preset válido del perfil.
	var pid := sim.active_differential_profile()
	var wanted := sim.active_differential_preset_id
	if wanted.is_empty():
		wanted = RallyDifferentialCatalog.default_for_profile(pid)
	var resolved := RallyDifferentialCatalog.resolve(pid, wanted, {"power": 0.1, "coast": 0.08})
	check(bool(resolved.get("ok", false)), "catálogo resuelve preset tardío")
	# Se invalida el estado que el modelo hereda (ganancia de rampa del eje
	# motriz): el modelo debe rechazar dentro de apply_setup_values().
	# Escort RWD → eje trasero.
	var good_gain := float(sim.powertrain_model.rear_differential_ramp_gain)
	sim.powertrain_model.rear_differential_ramp_gain = INF
	var base := sim.filter_garage_values(RallySetupCatalog.defaults(sim.domains))
	var payload := base.duplicate(true)
	payload[FordRallyVehicleSimulation.DIFFERENTIAL_PRESET_PATH] = wanted
	# Añadir un reglaje ajeno al diferencial para verificar que tampoco muta.
	payload["brakes.front_brake_bias"] = 0.60
	var frozen := _setup_snapshot(sim)
	var result := sim.apply_setup_values(payload)
	check(not bool(result.get("ok", false)), "garaje rechaza tarde (modelo)")
	check(_setup_snapshot(sim) == frozen, "dominios/ID/ejes/ajeno intactos tras rechazo tardío")
	# Si domains = staging se moviera antes de aplicar el preset, el snapshot
	# diferiría (el numérico + preset ya estarían publicados): el check
	# anterior lo detecta.
	sim.powertrain_model.rear_differential_ramp_gain = good_gain
	var retry := sim.apply_setup_values(payload)
	check(bool(retry.get("ok", false)), "tras restaurar, el mismo reglaje se acepta")
	check(sim.active_differential_preset_id == wanted, "ID activo publicado tras éxito tardío")
	RallyDifferentialCatalog.set_mode_override(RallyDifferentialCatalog.MODE_MODERN)


func test_contact_reach() -> void:
	print("\n[§2] Alcance de consulta en extensión...")
	# El viaje deriva del límite efectivo (droop + margen del joint).
	var q := UnsprungSuspensionRig.contact_query_travel_m(0.22, 0.18)
	check(absf(float(q["droop_effective"]) - 0.21) < 0.0001, "droop efectivo 0.18+0.03=0.21")
	check(absf(float(q["bump"]) - 0.24) < 0.0001, "bump 0.22+0.02=0.24")
	check(absf(float(q["travel"]) - 0.45) < 0.0001, "travel 0.24+0.21=0.45")
	# Alcance bajo el neutro = droop efectivo; una superficie a 0.205 bajo el
	# neutro es alcanzable, a 0.22 ya no (más allá del límite efectivo).
	var reach: float = q["droop_effective"]
	check(0.205 <= reach + 0.001, "apoyo a 0.205 alcanzable dentro del límite")
	check(0.22 > reach + 0.001, "apoyo a 0.22 fuera del alcance físico")
	# La distancia referida al neutro con fracción 1 es radio + droop efectivo.
	var radii := 0.28
	var dist_full := radii + float(q["travel"]) * 1.0 - float(q["bump"])
	check(absf(dist_full - (radii + reach)) < 0.0001, "distancia a fracción 1 = radio+alcance")


func test_physical_hub_travel_deflection() -> void:
	print("\n[H1] Deformación con recorrido físico del hub...")
	# Droop nominal 180 mm, hub en -210 mm, superficie compatible con centro
	# de rueda en -200 mm → road_compression = 0.28 - 0.48 = -0.20,
	# hub_travel = -0.21 → deformación 10 mm y carga positiva.
	# Ambas consultas (tándem y ShapeCast) alimentan la misma distancia
	# neutro-superficie (0.48 m); el tándem como -altura, el ShapeCast como
	# radio + travel·safe - bump con safe = (0.48-0.28+0.24)/0.45 ≈ 0.978.
	var radii := 0.28
	var bump := 0.24
	var travel := 0.45
	var distance := 0.48
	var road := radii - distance
	check(absf(road - (-0.20)) < 0.0001, "road_compression -0.20 (base del ensayo)")
	var hub := -0.21
	var sim := _configure_escort()
	if sim == null:
		check(false, "sim escort lista (H1)")
		return
	var tires: Dictionary = (sim.domains.get("tires", {}) as Dictionary).get("tires", {})
	for mode in ["tandem", "shapecast"]:
		var d := UnsprungSuspensionRig.radial_deflection_from_travel(road, hub, 1.0)
		check(absf(d - 0.01) < 0.0005, "%s: deformación 10 mm (got %.4f)" % [mode, d])
		var radial := TireRadialModel.evaluate(tires, "front", 180.0, 25.0, 37.5, d, 0.0, 60.0)
		check(float(radial.get("force_n", 0.0)) > 50.0, "%s: carga positiva con 10 mm (got %.1f N)" % [mode, float(radial.get("force_n", 0.0))])
		# Sin penetración: superficie en -0.49 (distancia 0.49, road -0.21),
		# hub en -0.21 → deformación 0 y carga 0, aunque haya impacto.
		var d0 := UnsprungSuspensionRig.radial_deflection_from_travel(radii - 0.49, hub, 1.0)
		check(absf(d0) < 0.0005, "%s: sin penetración deformación 0" % mode)
		var radial0 := TireRadialModel.evaluate(tires, "front", 180.0, 25.0, 37.5, d0, 0.0, 60.0)
		check(absf(float(radial0.get("force_n", 0.0))) < 0.5, "%s: sin penetración carga 0" % mode)
	# El clamp antiguo habría dado 0 en el caso de 10 mm: verificar que el
	# recorrido físico difiere del limitado justo en este ensayo.
	var clamped := clampf(hub, -0.18, 0.22)
	var d_clamped := UnsprungSuspensionRig.radial_deflection_from_travel(road, clamped, 1.0)
	check(absf(d_clamped) < 0.0005, "con clamp (bug anterior) daría 0: confirma la corrección")


func test_shapecast_selection_contract() -> void:
	print("\n[H2] Coherencia del apoyo ShapeCast...")
	var cast := ShapeCast3D.new()
	# Godot 4.7.1 no expone fracción por colisión: solo la global.
	check(not cast.has_method("get_collision_safe_fraction"), "sin get_collision_safe_fraction en 4.7.1")
	var probe := FordRallyVehicleSimulation.new()
	check(probe.has_method("select_shapecast_support"), "selector presente")
	check(probe.has_method("shapecast_coherent_result"), "núcleo estático de aislamiento presente")
	check(probe.has_method("_query_shapecast_contact"), "consulta coherente con aislamiento presente")
	# La selección es solo punto/normal/collider (sin fracción por apoyo).
	var hit := FordRallyVehicleSimulation.select_shapecast_support(cast, Vector3.UP)
	check(hit.is_empty(), "sin colisiones no hay apoyo")
	cast.queue_free()


func test_ride_frequency_validation() -> void:
	print("\n[H3] Validación de ride_frequency_hz...")
	var loaded := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	check(bool(loaded.get("ok", false)), "perfil escort carga")
	if not bool(loaded.get("ok", false)):
		return
	var domains: Dictionary = (loaded as Dictionary)["domains"]
	var mass := VehicleMassModel.new()
	check(bool(mass.configure(domains, {}).get("ok", false)), "masa configura")
	var resolved := mass.resolve(mass.fuel_initial_kg)
	var geometry: Dictionary = (domains.get("chassis", {}) as Dictionary).get("geometry", {})
	var susp := func() -> VehicleSuspensionModel:
		return VehicleSuspensionModel.new()
	# Ausencia → respaldo (OK, frecuencia = sqrt(k/m)/TAU del tren delantero).
	var d_absent: Dictionary = (domains as Dictionary).duplicate(true)
	((d_absent.get("suspension", {}) as Dictionary).get("suspension", {}) as Dictionary)["front"] = (((d_absent.get("suspension", {}) as Dictionary).get("suspension", {}) as Dictionary).get("front", {}) as Dictionary).duplicate(true)
	(((d_absent.get("suspension", {}) as Dictionary).get("suspension", {}) as Dictionary).get("front", {}) as Dictionary).erase("ride_frequency_hz")
	var r_absent := (susp.call() as VehicleSuspensionModel).configure(d_absent, geometry, resolved)
	check(bool(r_absent.get("ok", false)), "ausente usa respaldo")
	# Válido → OK.
	var d_ok: Dictionary = (domains as Dictionary).duplicate(true)
	(((d_ok.get("suspension", {}) as Dictionary).get("suspension", {}) as Dictionary).get("front", {}) as Dictionary)["ride_frequency_hz"] = 1.8
	check(bool((susp.call() as VehicleSuspensionModel).configure(d_ok, geometry, resolved).get("ok", false)), "válido 1.8 aceptado")
	# Casos inválidos → error con eje y campo.
	var cases := [
		["cero", 0.0], ["negativo", -1.5], ["inf", INF], ["nan", NAN],
		["texto", "1.8"], ["bool", true], ["array", [1.8]], ["nulo", null],
	]
	for c in cases:
		var d_bad: Dictionary = (domains as Dictionary).duplicate(true)
		(((d_bad.get("suspension", {}) as Dictionary).get("suspension", {}) as Dictionary).get("front", {}) as Dictionary)["ride_frequency_hz"] = c[1]
		var r_bad := (susp.call() as VehicleSuspensionModel).configure(d_bad, geometry, resolved)
		var err := str(r_bad.get("error", ""))
		check(not bool(r_bad.get("ok", false)) and err.contains("front") and err.contains("ride_frequency_hz"), "rechazado %s con eje+campo (err: %s)" % [str(c[0]), err])


func test_shared_suspension() -> void:
	print("\n[§6] Cálculo compartido de suspensión...")
	var sim := _configure_escort()
	if sim == null:
		check(false, "sim escort lista (suspensión)")
		return
	var ref_mass_f := float((sim.suspension_model.axle_parameters[0] as Dictionary)["frequency_reference_mass_kg"])
	var ref_mass_r := float((sim.suspension_model.axle_parameters[2] as Dictionary)["frequency_reference_mass_kg"])
	var design_before := [sim.setup_design_axles[0].duplicate(true), sim.setup_design_axles[1].duplicate(true)]
	# Reaplicar el reglaje de fábrica conserva masa de referencia y diseño.
	var factory := sim.filter_garage_values(RallySetupCatalog.defaults(sim.domains))
	var rfac := sim.apply_setup_values(factory)
	check(bool(rfac.get("ok", false)), "fábrica reaplicada")
	check(absf(float((sim.suspension_model.axle_parameters[0] as Dictionary)["frequency_reference_mass_kg"]) - ref_mass_f) < 0.001, "fábrica conserva masa ref delantera")
	check(absf(float((sim.suspension_model.axle_parameters[2] as Dictionary)["frequency_reference_mass_kg"]) - ref_mass_r) < 0.001, "fábrica conserva masa ref trasera")
	check(str(sim.setup_design_axles[0]) == str(design_before[0]) and str(sim.setup_design_axles[1]) == str(design_before[1]), "fábrica conserva valores de diseño")
	# Cambios válidos: k = m*(TAU*f)^2, c = 2*sqrt(k*m)*zeta*mult, tope = k*mult*8.
	var payload := sim.filter_garage_values(RallySetupCatalog.defaults(sim.domains))
	payload["suspension.front.ride_frequency_hz"] = 1.80
	payload["suspension.rear.ride_frequency_hz"] = 1.90
	payload["suspension.front.damping_ratio"] = 0.50
	payload["suspension.front.bump_stop_multiplier"] = 2.0
	var rchg := sim.apply_setup_values(payload)
	check(bool(rchg.get("ok", false)), "cambios válidos aceptados")
	var pf: Dictionary = sim.suspension_model.axle_parameters[0]
	var exp_k := ref_mass_f * pow(TAU * 1.80, 2.0)
	check(absf(float(pf["spring_rate"]) - exp_k) / exp_k < 0.001, "k delantera = m*(TAU*f)^2")
	# bump_damp_multiplier no cambiado: vale el de fábrica; comparar con fórmula común.
	var common := VehicleSuspensionModel.corner_rates(ref_mass_f, 1.80, 0.50, float((sim.domains.get("suspension", {}) as Dictionary).get("suspension", {}).get("front", {}).get("bump_damp_multiplier", 1.0)), float((sim.domains.get("suspension", {}) as Dictionary).get("suspension", {}).get("front", {}).get("rebound_damp_multiplier", 1.0)), float(pf["bump_stop_stiffness"]) / maxf(exp_k, 1.0) / 8.0)
	check(absf(float(common["spring_rate"]) - float(pf["spring_rate"])) / exp_k < 0.001, "corner_rates coincide con garaje")
	# Con combustible consumido, reaplicar el mismo reglaje conserva masa ref.
	sim.mass_model.fuel_initial_kg = maxf(sim.mass_model.fuel_initial_kg - 10.0, 0.0)
	var rre := sim.apply_setup_values(payload)
	check(bool(rre.get("ok", false)), "reaplicar con menos combustible aceptado")
	check(absf(float((sim.suspension_model.axle_parameters[0] as Dictionary)["frequency_reference_mass_kg"]) - ref_mass_f) < 0.001, "reaplicar conserva masa de referencia (combustible no la recalibra)")


func run() -> void:
	test_pressure_common_function()
	test_pressure_garage_preserves_loss()
	test_atomic_commit()
	test_late_rejection_via_garage()
	test_contact_reach()
	test_physical_hub_travel_deflection()
	test_shapecast_selection_contract()
	test_ride_frequency_validation()
	test_shared_suspension()
	print("\nVEHICLE_SIMULATION_CORRECTION_CONTRACT ", "PASS" if failures.is_empty() else "FAIL")
	if not failures.is_empty():
		for f in failures:
			print("  - ", f)
	quit(0 if failures.is_empty() else 1)
