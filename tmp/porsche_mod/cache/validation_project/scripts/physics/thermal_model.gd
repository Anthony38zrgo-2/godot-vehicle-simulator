class_name VehicleThermalModel
extends RefCounted

var engine_config: Dictionary = {}
var tire_config: Dictionary = {}
var tire_config_front: Dictionary = {}
var tire_config_rear: Dictionary = {}
var pressure_config: Dictionary = {}
var pressure_config_front: Dictionary = {}
var pressure_config_rear: Dictionary = {}
var pressure_mechanics: Dictionary = {}
var pressure_mechanics_front: Dictionary = {}
var pressure_mechanics_rear: Dictionary = {}
var powertrain_aero: VehicleAerodynamicModel
var engine_block_temperature_c: float = 0.0
var water_temperature_c: float = 0.0
var oil_temperature_c: float = 0.0
var available_engine_torque_fraction: float = 1.0
var water_cooling_conductance_w_k: float = 0.0
var oil_cooling_conductance_w_k: float = 0.0
var cooling_drag_force_n: float = 0.0
var tire_states: Array[Dictionary] = []
var fuel_remaining_litres: float = 0.0
var fuel_capacity_litres: float = 0.0
var fuel_density_kg_litre: float = 0.74
var fuel_specific_kg_kwh := 0.35
var fuel_idle_kg_hour := 3.0
var fuel_burned_litres: float = 0.0
var ambient_temperature_c: float = 25.0
var brake_thermal_config: Dictionary = {}
# Chassis-mounted consumables: independent of the replaceable tire inventory.
var brake_wear_fraction: Array[float] = [0.0, 0.0, 0.0, 0.0]
var brake_wear_config: Dictionary = {}
var brake_disc_heat_capacity_j_k: Array[float] = []
var brake_disc_area_m2: Array[float] = []
var brake_disc_emissivity: Array[float] = []
var active_compound_id: String = "gravel_normal"
var active_compound: Dictionary = {}
var wheel_compounds: Array[Dictionary] = []
var compound_catalog: Dictionary = {}
var radiator_damage: float = 0.0
var engine_damage: float = 0.0
var overheat_exposure_s: float = 0.0
var damage_config: Dictionary = {}
var oil_pressure_bar: float = 0.0
var oil_healthy_pressure_bar: float = 0.0


func configure(domains: Dictionary) -> Dictionary:
	var damage_doc: Dictionary = domains.get("damage", {})
	damage_config = (damage_doc.get("damage", damage_doc) as Dictionary).duplicate(true)
	var powertrain: Dictionary = domains.get("powertrain", {}).get("powertrain", {})
	engine_config = powertrain.get("thermal", {}).duplicate(true)
	if engine_config.is_empty():
		return {"ok": false, "error": "powertrain.thermal configuration is required for the thermal HUD and torque derating."}
	engine_block_temperature_c = float(engine_config.get("initial_engine_block_temperature_celsius", 85.0))
	water_temperature_c = float(engine_config.get("initial_water_temperature_celsius", 82.0))
	oil_temperature_c = float(engine_config.get("initial_oil_temperature_celsius", 85.0))
	var tires: Dictionary = domains.get("tires", {}).get("tires", {})
	tire_config = (tires.get("thermal", {}) as Dictionary).duplicate(true)
	pressure_config = (tires.get("pressure", {}) as Dictionary).duplicate(true)
	pressure_mechanics = (tires.get("pressure_mechanics", {}) as Dictionary).duplicate(true)
	var front_tire: Dictionary = tires.get("front", {}) if tires.get("front", {}) is Dictionary else {}
	var rear_tire: Dictionary = tires.get("rear", {}) if tires.get("rear", {}) is Dictionary else {}
	tire_config_front = _merged_config(tire_config, front_tire.get("thermal", {}))
	tire_config_rear = _merged_config(tire_config, rear_tire.get("thermal", {}))
	pressure_config_front = _merged_config(pressure_config, front_tire.get("pressure", {}))
	pressure_config_rear = _merged_config(pressure_config, rear_tire.get("pressure", {}))
	pressure_mechanics_front = _merged_config(pressure_mechanics, front_tire.get("pressure_mechanics", {}))
	pressure_mechanics_rear = _merged_config(pressure_mechanics, rear_tire.get("pressure_mechanics", {}))
	ambient_temperature_c = float(tire_config.get("ambient_fallback_c", 25.0))
	var fuel: Dictionary = domains.get("fuel", {}).get("fuel", {})
	fuel_specific_kg_kwh = maxf(float(fuel.get("brake_specific_consumption_kg_per_kwh", 0.35)), 0.0)
	fuel_idle_kg_hour = maxf(float(fuel.get("idle_consumption_kg_per_hour", 3.0)), 0.0)
	fuel_density_kg_litre = float(fuel.get("density_kg_per_litre", 0.74))
	fuel_capacity_litres = float(fuel.get("capacity_kg", 0.0)) / maxf(fuel_density_kg_litre, 0.000001)
	fuel_remaining_litres = float(fuel.get("initial_kg", fuel.get("capacity_kg", 0.0))) / maxf(fuel_density_kg_litre, 0.000001)
	var brakes: Dictionary = domains.get("brakes", {}).get("brakes", {})
	brake_thermal_config = brakes.get("thermal", {}).duplicate(true)
	if FileAccess.file_exists("res://data/brakes/rally_wear.json"):
		var wear_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/brakes/rally_wear.json"))
		if wear_doc is Dictionary:
			brake_wear_config = wear_doc
	brake_disc_heat_capacity_j_k.clear()
	brake_disc_area_m2.clear()
	brake_disc_emissivity.clear()
	for axle in ["front", "front", "rear", "rear"]:
		var rotor: Dictionary = brake_thermal_config.get(axle, {})
		# Grey cast iron specific heat: 500 J/(kg K), published material value.
		# Area is the two swept faces; hub/rim cooling is not assumed here.
		var radius_outer := float(rotor.get("rotor_outer_diameter_m", 0.0)) * 0.5
		var radius_inner := float(rotor.get("rotor_inner_diameter_m", 0.0)) * 0.5
		var rotor_mass := float(rotor.get("rotor_mass_kg", 0.0))
		var face_area := 2.0 * PI * maxf(radius_outer * radius_outer - radius_inner * radius_inner, 0.0)
		brake_disc_heat_capacity_j_k.append(maxf(rotor_mass * 500.0, 1.0))
		brake_disc_area_m2.append(face_area)
		brake_disc_emissivity.append(float(rotor.get("rotor_radiation_emissivity", 0.7)))
	var cold_pressures: Dictionary = pressure_config.get("cold_kpa_gauge", {})
	var reference_temp := float(pressure_config.get("reference_temperature_c", 25.0))
	var initial_tire_temp := float(tire_config.get("initial_temperature_c", ambient_temperature_c))
	var reference_pressure_bar := float(cold_pressures.get("FL", 180.0)) / 100.0
	tire_states.clear()
	for i in 4:
		var wheel_key: String = ["FL", "FR", "RL", "RR"][i]
		reference_pressure_bar = float(cold_pressures.get(wheel_key, 180.0)) / 100.0
		tire_states.append({
			"surface_c": initial_tire_temp,
			"tread_c": initial_tire_temp,
			"tread_zones_c": [initial_tire_temp, initial_tire_temp, initial_tire_temp],
			"carcass_c": initial_tire_temp,
			"gas_c": initial_tire_temp,
			"pressure_bar_gauge": reference_pressure_bar,
			"pressure_reference_bar_gauge": reference_pressure_bar,
			"pressure_reference_temp_c": reference_temp,
			"wear_fraction": 0.0,
			"thermal_damage_fraction": 0.0,
			"brake_disc_c": maxf(float(brake_thermal_config.get("initial_temperature_c", ambient_temperature_c)), ambient_temperature_c),
			"brake_heating_w": 0.0,
			"brake_cooling_w": 0.0,
		})
	_update_torque_derating()
	return {"ok": true}


func engine_torque_factor() -> float:
	return available_engine_torque_fraction


func set_compound(compound_id: String, catalog: Dictionary = {}) -> void:
	var cid := str(compound_id) if str(compound_id) in ["gravel_normal", "gravel_wet"] else "gravel_normal"
	active_compound_id = cid
	if not catalog.is_empty():
		compound_catalog = (catalog as Dictionary).duplicate(true)
	if compound_catalog.is_empty() and FileAccess.file_exists("res://data/tires/rally_compounds.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/tires/rally_compounds.json"))
		if parsed is Dictionary:
			compound_catalog = parsed
	active_compound = ((compound_catalog.get("compounds", {}) as Dictionary).get(cid, {}) as Dictionary).duplicate(true) if compound_catalog.has("compounds") else {}
	wheel_compounds.clear()
	for i in 4:
		wheel_compounds.append(active_compound.duplicate(true))
	_apply_compound_to_configs()


func _apply_compound_to_configs() -> void:
	if active_compound.is_empty():
		return
	# Ventanas/objetivos térmicos del compuesto elegido (banda y carcasa).
	for key in ["tire_config", "tire_config_front", "tire_config_rear"]:
		var cfg: Dictionary = get(key)
		cfg["optimal_tread_temperature_c"] = float(active_compound.get("tread_optimum_c", cfg.get("optimal_tread_temperature_c", 50.0)))
		cfg["optimal_tread_window_c"] = float(active_compound.get("tread_window_c", cfg.get("optimal_tread_window_c", 50.0)))
		cfg["overheat_tread_temperature_c"] = float(active_compound.get("overheat_tread_c", cfg.get("overheat_tread_temperature_c", 100.0)))
		cfg["optimal_carcass_temperature_c"] = float(active_compound.get("carcass_optimum_c", cfg.get("optimal_carcass_temperature_c", 60.0)))
		cfg["tread_zone_heat_capacity_j_k"] = float(active_compound.get("tread_zone_heat_capacity_j_k", cfg.get("tread_zone_heat_capacity_j_k", 6300.0)))
		cfg["carcass_heat_capacity_j_k"] = float(active_compound.get("carcass_heat_capacity_j_k", cfg.get("carcass_heat_capacity_j_k", 18000.0)))
		cfg["gas_heat_capacity_j_k"] = float(active_compound.get("gas_heat_capacity_j_k", cfg.get("gas_heat_capacity_j_k", 2200.0)))
		cfg["tread_to_carcass_w_k"] = float(active_compound.get("tread_to_carcass_w_k", cfg.get("tread_to_carcass_w_k", 60.0)))
		cfg["carcass_to_gas_w_k"] = float(active_compound.get("carcass_to_gas_w_k", cfg.get("carcass_to_gas_w_k", 25.0)))
		cfg["tread_to_air_w_k"] = float(active_compound.get("tread_to_air_w_k", cfg.get("tread_to_air_w_k", 30.0)))
		cfg["carcass_to_air_w_k"] = float(active_compound.get("carcass_to_air_w_k", cfg.get("carcass_to_air_w_k", 15.0)))
		cfg["road_conductance_w_k"] = float(active_compound.get("road_conductance_w_k", cfg.get("road_conductance_w_k", 55.0)))
		cfg["lateral_tread_conductance_w_k"] = float(active_compound.get("lateral_tread_conductance_w_k", cfg.get("lateral_tread_conductance_w_k", 25.0)))
		cfg["slip_heat_efficiency"] = float(active_compound.get("slip_heat_efficiency", cfg.get("slip_heat_efficiency", 0.55)))
		cfg["carcass_hysteresis_efficiency"] = float(active_compound.get("carcass_hysteresis_efficiency", cfg.get("carcass_hysteresis_efficiency", 0.55)))
		set(key, cfg)


func reset_for_stage(domains: Dictionary) -> void:
	var mounted_tires := tire_states.duplicate(true)
	var remaining_fuel := fuel_remaining_litres
	var previous_radiator_damage := radiator_damage
	var previous_engine_damage := engine_damage
	configure(domains)
	# Stage preparation resets temperatures, never repairs permanent damage.
	radiator_damage = previous_radiator_damage
	engine_damage = previous_engine_damage
	_update_torque_derating()
	overheat_exposure_s = 0.0
	oil_pressure_bar = 0.0
	oil_healthy_pressure_bar = 0.0
	fuel_remaining_litres = clampf(remaining_fuel, 0.0, fuel_capacity_litres)
	_apply_compound_to_configs()
	fuel_burned_litres = 0.0
	water_cooling_conductance_w_k = 0.0
	oil_cooling_conductance_w_k = 0.0
	cooling_drag_force_n = 0.0
	var brake_target := (float(brake_thermal_config.get("optimal_min_temperature_c", 150.0)) + float(brake_thermal_config.get("optimal_max_temperature_c", 450.0))) * 0.5
	for i in tire_states.size():
		var cfg := _axle_tire_config(i)
		var pressure := _axle_pressure_config(i)
		var tread := float(cfg.get("optimal_tread_temperature_c", 50.0))
		var carcass := float(cfg.get("optimal_carcass_temperature_c", 60.0))
		var state: Dictionary = tire_states[i]
		if i < mounted_tires.size():
			state.wear_fraction = float(mounted_tires[i].get("wear_fraction", 0.0))
			state.thermal_damage_fraction = float(mounted_tires[i].get("thermal_damage_fraction", 0.0))
			state.leak_per_second = float(mounted_tires[i].get("leak_per_second", 0.0))
			state.rim_deformation = float(mounted_tires[i].get("rim_deformation", 0.0))
			state.carcass_failure = float(mounted_tires[i].get("carcass_failure", 0.0))
			state.pressure_loss_fraction = float(mounted_tires[i].get("pressure_loss_fraction", 0.0))
		state.surface_c = tread
		state.tread_c = tread
		state.tread_zones_c = [tread, tread, tread]
		state.carcass_c = carcass
		state.gas_c = carcass
		state.brake_disc_c = brake_target
		var cold: Dictionary = pressure.get("cold_kpa_gauge", {})
		var cold_bar := float(cold.get(["FL", "FR", "RL", "RR"][i], 180.0)) / 100.0
		var reference := float(pressure.get("reference_temperature_c", 25.0))
		var atmosphere := float(pressure.get("atmospheric_pressure_kpa", 101.325)) / 100.0
		state.pressure_reference_bar_gauge = cold_bar
		state.pressure_reference_temp_c = reference
		var healthy_pressure := (cold_bar + atmosphere) * (carcass + 273.15) / (reference + 273.15) - atmosphere
		state.pressure_bar_gauge = healthy_pressure * (1.0 - float(state.get("pressure_loss_fraction", 0.0)))


func apply_damage(rad_delta: float, eng_delta: float) -> void:
	radiator_damage = clampf(radiator_damage + maxf(rad_delta, 0.0), 0.0, 1.0)
	engine_damage = clampf(engine_damage + maxf(eng_delta, 0.0), 0.0, 1.0)
	_update_torque_derating()


func quick_repair_radiator(custom_target: float = -1.0) -> bool:
	if radiator_damage < 0.05:
		return false
	var target_damage: float = custom_target if custom_target >= 0.0 else (0.50 if radiator_damage >= 0.70 else 0.0)
	radiator_damage = target_damage
	overheat_exposure_s = 0.0
	if water_temperature_c > 92.0:
		water_temperature_c = 90.0
	if oil_temperature_c > 105.0:
		oil_temperature_c = 100.0
	_update_torque_derating()
	return true


func oil_viscosity_factor(oil_c: float) -> float:
	var cfg: Dictionary = engine_config.get("oil_pressure", {})
	var reference := float(cfg.get("viscosity_reference_celsius", 90.0))
	var hot := float(cfg.get("viscosity_hot_celsius", 130.0))
	var hot_factor := float(cfg.get("hot_viscosity_factor", 0.6))
	return lerpf(1.0, hot_factor, clampf((oil_c - reference) / maxf(hot - reference, 1.0), 0.0, 1.0))


func _update_oil_pressure(rpm: float, dt: float) -> void:
	# presion = min(valvula, k*rpm) * viscosidad(T_aceite) * (1 - perdida por dano)
	var cfg: Dictionary = engine_config.get("oil_pressure", {})
	if cfg.is_empty():
		return
	var pump := minf(float(cfg.get("relief_valve_bar", 4.0)), float(cfg.get("bar_per_rpm", 0.0012)) * maxf(rpm, 0.0))
	var loss_at_full := float(damage_config.get("thermal", {}).get("oil_pressure_loss_at_full_engine_damage", 0.0))
	var damage_factor := 1.0 - clampf(loss_at_full, 0.0, 1.0) * engine_damage
	oil_healthy_pressure_bar = pump
	var target := pump * oil_viscosity_factor(oil_temperature_c) * damage_factor
	var response := maxf(float(cfg.get("pressure_response_seconds", 0.25)), 0.001)
	oil_pressure_bar += (target - oil_pressure_bar) * (1.0 - exp(-dt / response))


func oil_pressure_state() -> String:
	var cfg: Dictionary = engine_config.get("oil_pressure", {})
	if cfg.is_empty():
		return "ok"
	var healthy := maxf(oil_healthy_pressure_bar, 0.001)
	var ratio := oil_pressure_bar / healthy
	if oil_pressure_bar < float(cfg.get("warning_pressure_bar", 0.8)) or ratio < float(cfg.get("warning_ratio", 0.5)):
		return "critical"
	if ratio < float(cfg.get("low_ratio", 0.75)):
		return "low"
	return "ok"


func advance_engine(delta: float, rpm: float, torque_nm: float, speed_m_s: float, air_density_kg_m3: float) -> void:
	# Un solo radiador de agua enfria todo el motor. El aceite solo cede calor
	# al bloque, al agua (oil_to_water) y, muy poco, al aire por el carter.
	var water_duct: Dictionary = engine_config.get("water_cooling_duct", {})
	var water_flow := _cooling_duct(water_duct, air_density_kg_m3, speed_m_s)
	var thermal_damage_cfg: Dictionary = damage_config.get("thermal", {})
	var min_cooling_factor := float(thermal_damage_cfg.get("minimum_cooling_factor", 0.45))
	var radiator_cooling_factor := lerpf(1.0, min_cooling_factor, radiator_damage)
	water_cooling_conductance_w_k = (float(water_duct.get("base_cooling_conductance_watts_per_kelvin", 0.0)) + float(water_flow.conductance)) * radiator_cooling_factor
	oil_cooling_conductance_w_k = float(engine_config.get("oil_sump_cooling_conductance_watts_per_kelvin", 0.0))
	cooling_drag_force_n = float(water_flow.drag)
	var engine_omega := maxf(rpm, 0.0) * TAU / 60.0
	var mechanical_power := maxf(torque_nm * engine_omega, 0.0)
	var generated_heat := float(engine_config.get("idle_heat_generation_watts", 0.0)) + mechanical_power * float(engine_config.get("heat_generation_per_mechanical_power", 0.0))
	var dt := clampf(delta, 0.001, 0.05)
	var block_c := engine_block_temperature_c
	var water_c := water_temperature_c
	var oil_c := oil_temperature_c
	var to_water := float(engine_config.get("engine_to_water_conductance_watts_per_kelvin", 0.0)) * (block_c - water_c)
	var to_oil := float(engine_config.get("engine_to_oil_conductance_watts_per_kelvin", 0.0)) * (block_c - oil_c)
	var oil_to_water := float(engine_config.get("oil_to_water_conductance_watts_per_kelvin", 0.0)) * (oil_c - water_c)
	var generated_block := generated_heat * float(engine_config.get("engine_block_heat_fraction", 1.0))
	var generated_water := generated_heat * float(engine_config.get("water_heat_fraction", 0.0))
	var generated_oil := generated_heat * float(engine_config.get("oil_heat_fraction", 0.0))
	var water_rejected := water_cooling_conductance_w_k * (water_c - ambient_temperature_c)
	var oil_rejected := oil_cooling_conductance_w_k * (oil_c - ambient_temperature_c)
	engine_block_temperature_c = block_c + (generated_block - to_water - to_oil) / maxf(float(engine_config.get("engine_block_heat_capacity_joules_per_kelvin", 1.0)), 1.0) * dt
	water_temperature_c = water_c + (generated_water + to_water + oil_to_water - water_rejected) / maxf(float(engine_config.get("water_heat_capacity_joules_per_kelvin", 1.0)), 1.0) * dt
	oil_temperature_c = oil_c + (generated_oil + to_oil - oil_to_water - oil_rejected) / maxf(float(engine_config.get("oil_heat_capacity_joules_per_kelvin", 1.0)), 1.0) * dt
	_update_oil_pressure(rpm, dt)

	var damage_start_c := float(thermal_damage_cfg.get("damage_start_c", 110.0))
	var full_rate_temp_c := float(thermal_damage_cfg.get("full_rate_temperature_c", 120.0))
	var grace_seconds := float(thermal_damage_cfg.get("grace_seconds", 6.0))
	var max_damage_rate := float(thermal_damage_cfg.get("maximum_damage_per_second", 0.015))
	var recovery_rate := float(thermal_damage_cfg.get("recovery_rate_per_second", 2.0))
	if water_temperature_c > damage_start_c:
		overheat_exposure_s += dt
		if overheat_exposure_s > grace_seconds:
			var excess_ratio := clampf((water_temperature_c - damage_start_c) / maxf(full_rate_temp_c - damage_start_c, 0.001), 0.0, 1.0)
			var damage_rate := max_damage_rate * excess_ratio
			engine_damage = clampf(engine_damage + damage_rate * dt, 0.0, 1.0)
	else:
		overheat_exposure_s = maxf(overheat_exposure_s - recovery_rate * dt, 0.0)

	_update_torque_derating()


func advance_tire(index: int, friction_power_w: float, braking_power_w: float, speed_m_s: float, delta: float, camber_rad: float = 0.0, radial_damping_power_w: float = 0.0, longitudinal_slip_speed_m_s: float = 0.0, surface_name: String = "Gravel", normal_load_n: float = 0.0, lateral_force_n: float = 0.0, wheel_omega_rad_s: float = 0.0, longitudinal_speed_m_s: float = 0.0, wheel_radius_m: float = 0.28, water_mm: float = 0.0, snow_mm: float = 0.0, ground_c: float = 9999.0, air_c: float = 9999.0, advance_pressure_leak: bool = true) -> void:
	if index < 0 or index >= tire_states.size():
		return
	var compound := compound_for_wheel(index)
	var axle_cfg := _axle_tire_config(index)
	var state: Dictionary = tire_states[index]
	var dt := maxf(delta, 0.0)
	# Condiciones locales por contacto (mismas que alimentan el grip).
	var local_ground := float(axle_cfg.get("track_fallback_c", ambient_temperature_c)) if ground_c > 9000.0 else ground_c
	var local_air := ambient_temperature_c if air_c > 9000.0 else air_c
	var local_water := clampf(water_mm, 0.0, 12.0)
	var local_snow := clampf(snow_mm, 0.0, 8.0)
	var zones: Array = state.get("tread_zones_c", [state.tread_c, state.tread_c, state.tread_c]).duplicate()
	var tread := (float(zones[0]) + float(zones[1]) + float(zones[2])) / 3.0
	var carcass := float(state.carcass_c)
	var gas := float(state.gas_c)
	var tread_to_carcass := float(axle_cfg.get("tread_to_carcass_w_k", 0.0)) * (tread - carcass)
	var carcass_to_gas := float(axle_cfg.get("carcass_to_gas_w_k", 0.0)) * (carcass - gas)
	# Opcion 4: particion de calor en grava. Patinando fuerte se excava y la
	# energia se va en piedras proyectadas, no al tread. Solo superficies sueltas.
	var eject_k := maxf(float(axle_cfg.get("gravel_eject_k", 0.0)), 0.0)
	var loose_surface := str(surface_name) in ["Gravel", "Dirt", "Sand"]
	var eta_base := float(axle_cfg.get("slip_heat_efficiency", 0.0))
	var eta_eff := eta_base / (1.0 + eject_k * absf(longitudinal_slip_speed_m_s)) if loose_surface else eta_base
	var slip_heat := maxf(friction_power_w, 0.0) * eta_eff
	var tread_capacity := maxf(float(axle_cfg.get("tread_zone_heat_capacity_j_k", 1.0)) / 3.0, 1.0)
	var carcass_capacity := maxf(float(axle_cfg.get("carcass_heat_capacity_j_k", 1.0)), 1.0)
	var gas_capacity := maxf(float(axle_cfg.get("gas_heat_capacity_j_k", 1.0)), 1.0)
	# Camber changes shoulder loading. Positive physical camber biases heat outward;
	# the center remains nearly neutral and total generated heat stays conserved.
	var shoulder_bias := clampf(camber_rad / deg_to_rad(8.0), -1.0, 1.0) * 0.18
	var heat_shares := [1.0 / 3.0 - shoulder_bias, 1.0 / 3.0, 1.0 / 3.0 + shoulder_bias]
	# Opcion 5c: conveccion dependiente de la velocidad del aire.
	# Combina avance del coche y centrifugacion de la rueda. Sin ganancia
	# configurada se conserva el comportamiento legacy constante.
	var base_air_total := float(axle_cfg.get("tread_to_air_w_k", 0.0))
	var conv_gain := maxf(float(axle_cfg.get("convection_velocity_gain_w_k", 0.0)), 0.0)
	var conv_alpha := clampf(float(axle_cfg.get("convection_alpha_airflow", 0.6)), 0.0, 1.0)
	var conv_ref := maxf(float(axle_cfg.get("convection_ref_speed_m_s", 20.0)), 1.0)
	var dyn_air_total := 0.0
	if conv_gain > 1e-9:
		var rim_speed := absf(wheel_omega_rad_s) * maxf(wheel_radius_m, 0.05)
		var v_air := conv_alpha * absf(speed_m_s) + (1.0 - conv_alpha) * rim_speed
		dyn_air_total = conv_gain * pow(v_air / conv_ref, 0.8)
	var air_conductance := (base_air_total + dyn_air_total) / 3.0
	var road_conductance := float(axle_cfg.get("road_conductance_w_k", 0.0)) / 3.0
	var carcass_conductance := float(axle_cfg.get("tread_to_carcass_w_k", 0.0)) / 3.0
	var lateral_conductance := float(axle_cfg.get("lateral_tread_conductance_w_k", 0.0)) / 2.0
	# Balance por compuesto: el agua residual enfría aunque haya dejado de llover;
	# la nieve ligera/moderada también enfría. Ganancias por compuesto.
	var water_gain := 1.0
	var snow_gain := 1.0
	var deform_gain := 1.0
	if not compound.is_empty():
		water_gain = float(compound.get("water_cooling_gain", 1.0))
		snow_gain = float(compound.get("snow_cooling_gain", 1.0))
		# Lluvia acumula más calor en seco por deformación del dibujo.
		if local_water < 0.4 and local_snow < 0.3:
			deform_gain = float(compound.get("deformation_heating_dry", 1.0))
		else:
			deform_gain = float(compound.get("deformation_heating_wet", 1.0))
	var water_cool_w_k := local_water * 9.0 * water_gain
	var snow_cool_w_k := local_snow * 7.0 * snow_gain
	for zone_index in 3:
		var zone_temperature := float(zones[zone_index])
		var lateral_heat := 0.0
		if zone_index > 0:
			lateral_heat += lateral_conductance * (float(zones[zone_index - 1]) - zone_temperature)
		if zone_index < 2:
			lateral_heat += lateral_conductance * (float(zones[zone_index + 1]) - zone_temperature)
		var zone_to_carcass := carcass_conductance * (zone_temperature - carcass)
		var zone_heat := slip_heat * float(heat_shares[zone_index]) - zone_to_carcass
		zone_heat -= air_conductance * (zone_temperature - local_air)
		zone_heat -= road_conductance * (zone_temperature - local_ground)
		zone_heat -= (water_cool_w_k / 3.0) * (zone_temperature - minf(local_ground, local_air))
		zone_heat -= (snow_cool_w_k / 3.0) * (zone_temperature - minf(local_ground, 2.0))
		zone_heat += lateral_heat
		zones[zone_index] = clampf(zone_temperature + dt * zone_heat / tread_capacity, minf(local_air, local_ground) - 5.0, 150.0)
	tread = (float(zones[0]) + float(zones[1]) + float(zones[2])) / 3.0
	var hysteresis_eff := clampf(float(axle_cfg.get("carcass_hysteresis_efficiency", 0.55)), 0.0, 1.0)
	# Opcion 5a: histeresis de rodadura por carga vertical. Calienta el eje
	# cargado (delantero en frenada/apoyo) aunque no patine.
	var roll_hyst_coef := maxf(float(axle_cfg.get("rolling_hysteresis_coef", 0.0)), 0.0)
	var p_roll_hyst := roll_hyst_coef * maxf(normal_load_n, 0.0) * absf(longitudinal_speed_m_s) * deform_gain
	# Opcion 5b: flexion lateral de tacos. Calor viscoelastico por deriva.
	var block_power := maxf(float(axle_cfg.get("block_bending_power_w", 0.0)), 0.0)
	var p_block := block_power * pow(absf(lateral_force_n) / 3000.0, 2.0) * (absf(wheel_omega_rad_s) / 90.0) * deform_gain
	var next_carcass := carcass + dt * (tread_to_carcass + maxf(radial_damping_power_w, 0.0) * hysteresis_eff + p_roll_hyst + p_block - carcass_to_gas - float(axle_cfg.get("carcass_to_air_w_k", 0.0)) * (carcass - local_air)) / carcass_capacity
	var next_gas := gas + dt * carcass_to_gas / gas_capacity
	state.tread_zones_c = zones
	state.tread_c = tread
	state.surface_c = state.tread_c
	state.carcass_c = clampf(next_carcass, ambient_temperature_c, 180.0)
	state.gas_c = clampf(next_gas, ambient_temperature_c, 180.0)
	advance_tire_pressure(index, dt if advance_pressure_leak else 0.0)
	var pressure_loss := float(state.pressure_loss_fraction)
	var carcass_failure := float(state.get("carcass_failure", 0.0))
	if pressure_loss >= 0.85 and normal_load_n > 0.0:
		var speed_factor := smoothstep(4.0, 22.0, speed_m_s)
		var load_factor := clampf(normal_load_n / 2500.0, 0.0, 2.0)
		var sliding := clampf(maxf(absf(longitudinal_slip_speed_m_s) / 5.0, friction_power_w / 3500.0), 0.0, 1.0)
		carcass_failure = minf(1.0, carcass_failure + dt * speed_factor * load_factor * lerpf(0.012, 0.16, sliding))
		state.carcass_failure = carcass_failure
		if carcass_failure >= 1.0:
			state.rim_deformation = minf(1.0, float(state.get("rim_deformation", 0.0)) + dt * speed_factor * maxf(load_factor - 1.25, 0.0) * 0.2)
	accumulate_tire_damage(state, friction_power_w, dt, compound, local_water)
	var disc_temperature := float(state.brake_disc_c)
	var heat_capacity := brake_disc_heat_capacity_j_k[index] if index < brake_disc_heat_capacity_j_k.size() else 2500.0
	var losses := _brake_heat_losses(index, disc_temperature, speed_m_s)
	var cooling_w := float(losses.cooling_w)
	var heat_fraction := float(brake_thermal_config.get("braking_heat_fraction", 0.95))
	state.brake_heating_w = maxf(braking_power_w, 0.0) * clampf(heat_fraction, 0.0, 1.0)
	state.brake_cooling_w = cooling_w
	state.brake_convection_w_k = losses.convection_w_k
	var next_disc_temperature := disc_temperature + (float(state.brake_heating_w) - cooling_w) / heat_capacity * dt
	state.brake_disc_c = clampf(next_disc_temperature, ambient_temperature_c, 1200.0)
	# Actual solver work, not pedal position: holding a stopped wheel causes no wear.
	var hot_start := float(brake_wear_config.get("overheat_start_c", 550.0))
	var hot_full := maxf(float(brake_wear_config.get("overheat_full_c", 800.0)), hot_start + 1.0)
	var heat_severity := clampf((0.5 * (disc_temperature + float(state.brake_disc_c)) - hot_start) / (hot_full - hot_start), 0.0, 1.0)
	var heat_multiplier := lerpf(1.0, maxf(float(brake_wear_config.get("maximum_heat_multiplier", 3.0)), 1.0), heat_severity)
	var wear_energy := maxf(braking_power_w, 0.0) * dt
	brake_wear_fraction[index] = clampf(brake_wear_fraction[index] + wear_energy * maxf(float(brake_wear_config.get("wear_per_j", 2.0e-8)), 0.0) * heat_multiplier, 0.0, 1.0)
	tire_states[index] = state

func advance_tire_pressure(index: int, dt: float) -> void:
	var state: Dictionary = tire_states[index]
	var atmosphere_bar := float(_axle_pressure_config(index).get("atmospheric_pressure_kpa", 101.325)) / 100.0
	var reference_absolute := float(state.pressure_reference_bar_gauge) + atmosphere_bar
	var reference_kelvin := maxf(float(state.pressure_reference_temp_c) + 273.15, 1.0)
	var current_kelvin := maxf(float(state.gas_c) + 273.15, 1.0)
	var pressure_loss := clampf(float(state.get("pressure_loss_fraction", 0.0)) + float(state.get("leak_per_second", 0.0)) * dt, 0.0, 1.0)
	state.pressure_loss_fraction = pressure_loss
	state.pressure_bar_gauge = (1.0 - pressure_loss) * clampf(reference_absolute * current_kelvin / reference_kelvin - atmosphere_bar, 0.0, 4.0)


func accumulate_tire_damage(state: Dictionary, friction_power_w: float, dt: float, selected_compound: Dictionary = {}, water_mm: float = 0.0) -> void:
	var compound := active_compound if selected_compound.is_empty() else selected_compound
	dt = maxf(dt, 0.0) / maxf(float(compound_catalog.get("durability_life_scale", 1.0)), 0.01)
	# Power * seconds is joules. The legacy key was misnamed but used /J.
	var wear_rate := maxf(float(compound.get("wear_per_j", compound.get("wear_per_mj", 1.0e-9))), 0.0)
	var abrasion_multiplier := lerpf(maxf(float(compound.get("dry_wear_multiplier", 1.0)), 0.0), maxf(float(compound.get("wet_wear_multiplier", 1.0)), 0.0), smoothstep(0.1, 1.0, water_mm))
	state.wear_fraction = clampf(float(state.get("wear_fraction", 0.0)) + maxf(friction_power_w, 0.0) * maxf(dt, 0.0) * wear_rate * abrasion_multiplier, 0.0, 1.0)
	var hottest := float(state.tread_c)
	for temperature in state.get("tread_zones_c", []):
		hottest = maxf(hottest, float(temperature))
	var start := float(compound.get("thermal_damage_start_c", compound.get("overheat_tread_c", 100.0)))
	var reference := maxf(float(compound.get("thermal_damage_excess_reference_c", 20.0)), 0.001)
	var severity := pow(maxf(hottest - start, 0.0) / reference, maxf(float(compound.get("thermal_damage_exponent", 2.0)), 0.1))
	var rate := maxf(float(compound.get("thermal_damage_rate_per_s", 0.0)), 0.0)
	state.thermal_damage_fraction = clampf(float(state.get("thermal_damage_fraction", 0.0)) + severity * rate * maxf(dt, 0.0), 0.0, 1.0)


func _brake_heat_losses(index: int, temperature_c: float, speed_m_s: float) -> Dictionary:
	var rotor: Dictionary = brake_thermal_config.get("front" if index < 2 else "rear", {})
	var length_m := maxf(float(rotor.get("rotor_outer_diameter_m", 0.245)), 0.01)
	var area := brake_disc_area_m2[index]
	var disc_k := temperature_c + 273.15
	var air_k := ambient_temperature_c + 273.15
	var film_k := maxf(0.5 * (disc_k + air_k), 200.0)
	# Air at one atmosphere, Sutherland viscosity; conductivity approximation.
	var viscosity := 1.716e-5 * pow(film_k / 273.15, 1.5) * 383.55 / (film_k + 110.4)
	var density := 101325.0 / (287.05 * film_k)
	var conductivity := 0.02624 * pow(film_k / 300.0, 0.85)
	var prandtl := 1005.0 * viscosity / conductivity
	var nu := viscosity / density
	var local_speed := absf(speed_m_s) * clampf(float(rotor.get("installation_airflow_scale", 0.6)), 0.0, 1.0)
	var reynolds := local_speed * length_m / nu
	# Flat-plate equivalent for the exposed annular faces, not a duct model.
	# ASHRAE/Incropera average laminar and transitional correlations.
	var forced_nusselt := 0.664 * sqrt(reynolds) * pow(prandtl, 1.0 / 3.0)
	if reynolds > 500000.0:
		forced_nusselt = (0.037 * pow(reynolds, 0.8) - 871.0) * pow(prandtl, 1.0 / 3.0)
	var delta_t := maxf(temperature_c - ambient_temperature_c, 0.0)
	var diffusivity := conductivity / (density * 1005.0)
	var rayleigh := 9.80665 * delta_t * pow(length_m, 3.0) / (film_k * nu * diffusivity)
	# Churchill-Chu vertical-surface approximation for stationary cooling.
	var natural_nusselt := pow(0.825 + 0.387 * pow(rayleigh, 1.0 / 6.0) / pow(1.0 + pow(0.492 / prandtl, 9.0 / 16.0), 8.0 / 27.0), 2.0)
	var conductance := area * conductivity / length_m * maxf(natural_nusselt, forced_nusselt)
	var view_factor := clampf(float(rotor.get("rotor_radiation_ambient_view_factor", 0.4)), 0.0, 1.0)
	var radiation := brake_disc_emissivity[index] * 5.670374419e-8 * area * view_factor * (pow(disc_k, 4.0) - pow(air_k, 4.0))
	return {"cooling_w": conductance * delta_t + radiation, "convection_w_k": conductance}


func tire_grip_factor(index: int) -> float:
	if index < 0 or index >= tire_states.size():
		return 1.0
	var compound := compound_for_wheel(index)
	var axle_cfg := _axle_tire_config(index)
	var state: Dictionary = tire_states[index]
	var optimum := float(axle_cfg.get("optimal_tread_temperature_c", 50.0))
	var half_window := float(axle_cfg.get("optimal_tread_window_c", 50.0)) * 0.5
	var upper := optimum + half_window
	var lower := optimum - half_window
	var tread := float(state.tread_c)
	var overheat := float(axle_cfg.get("overheat_tread_temperature_c", 100.0))
	var thermal_factor := 1.0
	var cold_ramp := maxf(float(compound.get("cold_grip_ramp_c", 30.0)), 0.001)
	var cold_floor := clampf(float(compound.get("cold_grip_floor", 0.80)), 0.0, 1.0)
	if tread < lower:
		thermal_factor = lerpf(cold_floor, 1.0, clampf((tread - (lower - cold_ramp)) / cold_ramp, 0.0, 1.0))
	elif tread > upper:
		thermal_factor = 1.0 - clampf(float(compound.get("overheat_grip_loss", 0.25)), 0.0, 1.0) * clampf((tread - upper) / maxf(overheat - upper, 1.0), 0.0, 1.0)
	var wear_factor := 1.0 - clampf(float(compound.get("wear_grip_loss", 0.25)), 0.0, 1.0) * clampf(float(state.wear_fraction), 0.0, 1.0)
	var damage_factor := 1.0 - clampf(float(compound.get("thermal_damage_grip_loss", 0.35)), 0.0, 1.0) * clampf(float(state.get("thermal_damage_fraction", 0.0)), 0.0, 1.0)
	var puncture_factor := lerpf(1.0, 0.35, clampf(float(state.get("pressure_loss_fraction", 0.0)), 0.0, 1.0))
	var carcass_factor := lerpf(1.0, 0.55, clampf(float(state.get("carcass_failure", 0.0)), 0.0, 1.0))
	if float(state.get("carcass_failure", 0.0)) >= 1.0:
		carcass_factor = 0.30
	return thermal_factor * wear_factor * damage_factor * puncture_factor * carcass_factor


func brake_wear_factor(index: int) -> float:
	var loss := clampf(float(brake_wear_config.get("maximum_torque_loss", 0.65)), 0.0, 1.0)
	var exponent := maxf(float(brake_wear_config.get("response_exponent", 1.5)), 0.1)
	return 1.0 - loss * pow(brake_wear_fraction[index], exponent)


func brake_fade_factor(index: int) -> float:
	var temperature := float(tire_states[index].brake_disc_c)
	var start := float(brake_thermal_config.get("fade_start_temperature_c", 550.0))
	var critical := float(brake_thermal_config.get("critical_temperature_c", 750.0))
	var minimum := float(brake_thermal_config.get("minimum_fade_efficiency", 0.5))
	var cold_efficiency := float(brake_thermal_config.get("cold_efficiency", 0.85))
	var optimal_minimum := float(brake_thermal_config.get("optimal_min_temperature_c", 150.0))
	if temperature < optimal_minimum:
		return lerpf(clampf(cold_efficiency, 0.0, 1.0), 1.0, clampf(temperature / maxf(optimal_minimum, 1.0), 0.0, 1.0))
	if temperature <= start:
		return 1.0
	return lerpf(1.0, clampf(minimum, 0.0, 1.0), clampf((temperature - start) / maxf(critical - start, 1.0), 0.0, 1.0))


func advance_fuel(engine_power_w: float, delta: float) -> float:
	# Profile-specific consumption with an idle floor while fuel is available.
	var kg_per_second := maxf(maxf(engine_power_w, 0.0) * fuel_specific_kg_kwh / 3600000.0, fuel_idle_kg_hour / 3600.0) if fuel_remaining_litres > 0.0 else 0.0
	var burn := kg_per_second * maxf(delta, 0.0) / maxf(fuel_density_kg_litre, 0.000001)
	var actual_burn := minf(fuel_remaining_litres, burn)
	fuel_remaining_litres -= actual_burn
	fuel_burned_litres += actual_burn
	return actual_burn


func get_fuel_state_snapshot() -> Dictionary:
	return {
		"remaining_litres": fuel_remaining_litres,
		"capacity_litres": fuel_capacity_litres,
		"remaining_kg": fuel_remaining_litres * fuel_density_kg_litre,
		"capacity_kg": fuel_capacity_litres * fuel_density_kg_litre,
		"burned_litres": fuel_burned_litres,
	}


func get_engine_thermal_state_snapshot() -> Dictionary:
	return {
		"block": {"temperature_c": engine_block_temperature_c},
		"water": {
			"temperature_c": water_temperature_c,
			"optimal_min_c": engine_config.get("water_optimal_minimum_temperature_celsius"),
			"optimal_max_c": engine_config.get("water_optimal_maximum_temperature_celsius"),
			"derating_c": engine_config.get("water_hot_derating_temperature_celsius"),
			"critical_c": engine_config.get("water_critical_temperature_celsius"),
		},
		"oil": {
			"temperature_c": oil_temperature_c,
			"pressure_bar": oil_pressure_bar,
			"healthy_pressure_bar": oil_healthy_pressure_bar,
			"pressure_state": oil_pressure_state(),
			"optimal_min_c": engine_config.get("oil_optimal_minimum_temperature_celsius"),
			"optimal_max_c": engine_config.get("oil_optimal_maximum_temperature_celsius"),
			"derating_c": engine_config.get("oil_hot_derating_temperature_celsius"),
			"critical_c": engine_config.get("oil_critical_temperature_celsius"),
		},
		"available_torque_fraction": available_engine_torque_fraction,
		"cooling_drag_force_n": cooling_drag_force_n,
		"radiator_damage": radiator_damage,
		"engine_damage": engine_damage,
		"radiator_damage_percent": radiator_damage * 100.0,
		"engine_damage_percent": engine_damage * 100.0,
		"overheat_exposure_s": overheat_exposure_s,
	}


func get_tire_thermal_state_snapshot(index: int) -> Dictionary:
	if index < 0 or index >= tire_states.size():
		return {}
	var state: Dictionary = tire_states[index]
	return {
		"surface_c": state.surface_c,
		"tread_c": state.tread_c,
		"tread_inner_c": float(state.tread_zones_c[0]),
		"tread_center_c": float(state.tread_zones_c[1]),
		"tread_outer_c": float(state.tread_zones_c[2]),
		"carcass_c": state.carcass_c,
		"gas_c": state.gas_c,
		"pressure_bar_gauge": state.pressure_bar_gauge,
		"pressure_kpa_gauge": float(state.pressure_bar_gauge) * 100.0,
		"leak_per_second": state.get("leak_per_second", 0.0),
		"rim_deformation": state.get("rim_deformation", 0.0),
		"carcass_failure": state.get("carcass_failure", 0.0),
		"pressure_loss_fraction": state.get("pressure_loss_fraction", 0.0),
		"wear_fraction": state.wear_fraction,
		"thermal_damage_fraction": state.get("thermal_damage_fraction", 0.0),
		"brake_disc_c": state.brake_disc_c,
		"brake_wear_fraction": brake_wear_fraction[index],
		"brake_wear_factor": brake_wear_factor(index),
		"brake_heating_w": state.get("brake_heating_w", 0.0),
		"brake_cooling_w": state.get("brake_cooling_w", 0.0),
		"brake_convection_w_k": state.get("brake_convection_w_k", 0.0),
		"grip_factor": tire_grip_factor(index),
		"brake_fade_factor": brake_fade_factor(index),
	}


func _update_torque_derating() -> void:
	var water_fraction := _temperature_torque_fraction(
		water_temperature_c,
		float(engine_config.get("water_optimal_minimum_temperature_celsius", 80.0)),
		float(engine_config.get("water_hot_derating_temperature_celsius", 110.0)),
		float(engine_config.get("water_critical_temperature_celsius", 120.0)),
		float(engine_config.get("water_minimum_cold_engine_torque_fraction", 0.96))
	)
	var oil_fraction := _temperature_torque_fraction(
		oil_temperature_c,
		float(engine_config.get("oil_optimal_minimum_temperature_celsius", 95.0)),
		float(engine_config.get("oil_hot_derating_temperature_celsius", 130.0)),
		float(engine_config.get("oil_critical_temperature_celsius", 145.0)),
		float(engine_config.get("oil_minimum_cold_engine_torque_fraction", 0.88))
	)
	var thermal_torque_fraction := clampf(minf(water_fraction, oil_fraction), float(engine_config.get("minimum_hot_engine_torque_fraction", 0.70)), 1.0)
	var thermal_damage_cfg: Dictionary = damage_config.get("thermal", {})
	var permanent_min_factor := float(thermal_damage_cfg.get("permanent_minimum_torque_factor", 0.70))
	var min_torque_floor := float(thermal_damage_cfg.get("minimum_torque_factor", 0.60))
	var permanent_torque_fraction := lerpf(1.0, permanent_min_factor, engine_damage)
	available_engine_torque_fraction = clampf(thermal_torque_fraction * permanent_torque_fraction, min_torque_floor, 1.0)


func _temperature_torque_fraction(temperature: float, optimum_min: float, hot: float, critical: float, minimum_cold: float) -> float:
	var minimum_hot := float(engine_config.get("minimum_hot_engine_torque_fraction", 0.70))
	if temperature < optimum_min:
		var cold_fraction := clampf((optimum_min - temperature) / 45.0, 0.0, 1.0)
		return clampf(1.0 - (1.0 - minimum_cold) * cold_fraction, minimum_hot, 1.0)
	if temperature <= hot:
		return 1.0
	var hot_fraction := pow(clampf((temperature - hot) / maxf(critical - hot, 1.0), 0.0, 1.0), 1.35)
	return clampf(1.0 - (1.0 - minimum_hot) * hot_fraction, minimum_hot, 1.0)


func _cooling_duct(duct: Dictionary, density: float, speed: float) -> Dictionary:
	var rho := clampf(density, 0.5, 1.6)
	var vehicle_speed := absf(speed)
	var opening := clampf(float(duct.get("opening", 0.0)), 0.0, 1.0)
	var area := maxf(float(duct.get("maximum_inlet_area_square_meters", 0.0)), 0.0) * pow(opening, clampf(float(duct.get("area_response_exponent", 1.0)), 0.05, 5.0))
	var dynamic_pressure := 0.5 * rho * vehicle_speed * vehicle_speed
	var pressure_delta := dynamic_pressure * maxf(float(duct.get("pressure_recovery", 0.0)), 0.0)
	var discharge := maxf(float(duct.get("discharge_coefficient", 0.0)), 0.0)
	var mass_flow := discharge * area * sqrt(2.0 * rho * pressure_delta) if area > 0.0 and pressure_delta > 0.0 else 0.0
	var capacity_rate := mass_flow * maxf(float(duct.get("air_specific_heat_joules_per_kilogram_kelvin", 0.0)), 0.0)
	var exchanger := maxf(float(duct.get("heat_exchanger_conductance_watts_per_kelvin", 0.0)), 0.0)
	var conductance := capacity_rate * (1.0 - exp(-exchanger / capacity_rate)) if capacity_rate > 1.0e-9 and exchanger > 0.0 else 0.0
	var drag := dynamic_pressure * maxf(float(duct.get("drag_coefficient", 0.0)), 0.0) * area
	return {"conductance": conductance, "drag": drag}


func compound_for_wheel(index: int) -> Dictionary:
	return wheel_compounds[index] if index >= 0 and index < wheel_compounds.size() else active_compound

func set_wheel_compound(index: int, compound_id: String) -> void:
	while wheel_compounds.size() < 4:
		wheel_compounds.append(active_compound.duplicate(true))
	wheel_compounds[index] = (compound_catalog.get("compounds", {}).get(compound_id, {}) as Dictionary).duplicate(true)

func _axle_tire_config(index: int) -> Dictionary:
	var base := tire_config_front if index < 2 else tire_config_rear
	var cfg: Dictionary = (base if not base.is_empty() else tire_config).duplicate()
	var compound := compound_for_wheel(index)
	var aliases := {"optimal_tread_temperature_c": "tread_optimum_c", "optimal_tread_window_c": "tread_window_c", "overheat_tread_temperature_c": "overheat_tread_c", "optimal_carcass_temperature_c": "carcass_optimum_c"}
	for key in aliases:
		if compound.has(aliases[key]):
			cfg[key] = compound[aliases[key]]
	for key in compound:
		if cfg.has(key):
			cfg[key] = compound[key]
	return cfg


func _axle_pressure_config(index: int) -> Dictionary:
	if index < 2:
		return pressure_config_front if not pressure_config_front.is_empty() else pressure_config
	return pressure_config_rear if not pressure_config_rear.is_empty() else pressure_config


func _axle_pressure_mechanics(index: int) -> Dictionary:
	if index < 2:
		return pressure_mechanics_front if not pressure_mechanics_front.is_empty() else pressure_mechanics
	return pressure_mechanics_rear if not pressure_mechanics_rear.is_empty() else pressure_mechanics


static func _merged_config(global_dict: Dictionary, axle_override: Variant) -> Dictionary:
	var out := (global_dict as Dictionary).duplicate(true) if global_dict is Dictionary else { }
	if axle_override is Dictionary:
		for k in (axle_override as Dictionary):
			out[k] = (axle_override as Dictionary)[k]
	return out
