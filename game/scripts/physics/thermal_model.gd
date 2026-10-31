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
var fuel_burned_litres: float = 0.0
var ambient_temperature_c: float = 25.0
var brake_thermal_config: Dictionary = {}
var brake_disc_heat_capacity_j_k: Array[float] = []
var brake_disc_area_m2: Array[float] = []
var brake_disc_emissivity: Array[float] = []


func configure(domains: Dictionary) -> Dictionary:
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
	fuel_density_kg_litre = float(fuel.get("density_kg_per_litre", 0.74))
	fuel_capacity_litres = float(fuel.get("capacity_kg", 0.0)) / maxf(fuel_density_kg_litre, 0.000001)
	fuel_remaining_litres = float(fuel.get("initial_kg", fuel.get("capacity_kg", 0.0))) / maxf(fuel_density_kg_litre, 0.000001)
	var brakes: Dictionary = domains.get("brakes", {}).get("brakes", {})
	brake_thermal_config = brakes.get("thermal", {}).duplicate(true)
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
			"brake_disc_c": maxf(float(brake_thermal_config.get("initial_temperature_c", ambient_temperature_c)), ambient_temperature_c),
			"brake_heating_w": 0.0,
			"brake_cooling_w": 0.0,
		})
	_update_torque_derating()
	return {"ok": true}


func engine_torque_factor() -> float:
	return available_engine_torque_fraction


func advance_engine(delta: float, rpm: float, torque_nm: float, speed_m_s: float, air_density_kg_m3: float) -> void:
	var water_duct: Dictionary = engine_config.get("water_cooling_duct", {})
	var oil_duct: Dictionary = engine_config.get("oil_cooling_duct", {})
	var water_flow := _cooling_duct(water_duct, air_density_kg_m3, speed_m_s)
	var oil_flow := _cooling_duct(oil_duct, air_density_kg_m3, speed_m_s)
	water_cooling_conductance_w_k = float(water_duct.get("base_cooling_conductance_watts_per_kelvin", 0.0)) + float(water_flow.conductance)
	oil_cooling_conductance_w_k = float(oil_duct.get("base_cooling_conductance_watts_per_kelvin", 0.0)) + float(oil_flow.conductance)
	cooling_drag_force_n = float(water_flow.drag) + float(oil_flow.drag)
	var engine_omega := maxf(rpm, 0.0) * TAU / 60.0
	var mechanical_power := maxf(torque_nm * engine_omega, 0.0)
	var generated_heat := float(engine_config.get("idle_heat_generation_watts", 0.0)) + mechanical_power * float(engine_config.get("heat_generation_per_mechanical_power", 0.0))
	var dt := clampf(delta, 0.001, 0.05)
	var block_c := engine_block_temperature_c
	var water_c := water_temperature_c
	var oil_c := oil_temperature_c
	var to_water := float(engine_config.get("engine_to_water_conductance_watts_per_kelvin", 0.0)) * (block_c - water_c)
	var to_oil := float(engine_config.get("engine_to_oil_conductance_watts_per_kelvin", 0.0)) * (block_c - oil_c)
	var generated_block := generated_heat * float(engine_config.get("engine_block_heat_fraction", 1.0))
	var generated_water := generated_heat * float(engine_config.get("water_heat_fraction", 0.0))
	var generated_oil := generated_heat * float(engine_config.get("oil_heat_fraction", 0.0))
	var water_rejected := water_cooling_conductance_w_k * (water_c - ambient_temperature_c)
	var oil_rejected := oil_cooling_conductance_w_k * (oil_c - ambient_temperature_c)
	engine_block_temperature_c = block_c + (generated_block - to_water - to_oil) / maxf(float(engine_config.get("engine_block_heat_capacity_joules_per_kelvin", 1.0)), 1.0) * dt
	water_temperature_c = water_c + (generated_water + to_water - water_rejected) / maxf(float(engine_config.get("water_heat_capacity_joules_per_kelvin", 1.0)), 1.0) * dt
	oil_temperature_c = oil_c + (generated_oil + to_oil - oil_rejected) / maxf(float(engine_config.get("oil_heat_capacity_joules_per_kelvin", 1.0)), 1.0) * dt
	_update_torque_derating()


func advance_tire(index: int, friction_power_w: float, braking_power_w: float, speed_m_s: float, delta: float, camber_rad: float = 0.0, radial_damping_power_w: float = 0.0) -> void:
	if index < 0 or index >= tire_states.size():
		return
	var axle_cfg := _axle_tire_config(index)
	var axle_pressure_cfg := _axle_pressure_config(index)
	var state: Dictionary = tire_states[index]
	var dt := maxf(delta, 0.0)
	var zones: Array = state.get("tread_zones_c", [state.tread_c, state.tread_c, state.tread_c]).duplicate()
	var tread := (float(zones[0]) + float(zones[1]) + float(zones[2])) / 3.0
	var carcass := float(state.carcass_c)
	var gas := float(state.gas_c)
	var tread_to_carcass := float(axle_cfg.get("tread_to_carcass_w_k", 0.0)) * (tread - carcass)
	var carcass_to_gas := float(axle_cfg.get("carcass_to_gas_w_k", 0.0)) * (carcass - gas)
	var slip_heat := maxf(friction_power_w, 0.0) * float(axle_cfg.get("slip_heat_efficiency", 0.0))
	var tread_capacity := maxf(float(axle_cfg.get("tread_zone_heat_capacity_j_k", 1.0)) / 3.0, 1.0)
	var carcass_capacity := maxf(float(axle_cfg.get("carcass_heat_capacity_j_k", 1.0)), 1.0)
	var gas_capacity := maxf(float(axle_cfg.get("gas_heat_capacity_j_k", 1.0)), 1.0)
	# Camber changes shoulder loading. Positive physical camber biases heat outward;
	# the center remains nearly neutral and total generated heat stays conserved.
	var shoulder_bias := clampf(camber_rad / deg_to_rad(8.0), -1.0, 1.0) * 0.18
	var heat_shares := [1.0 / 3.0 - shoulder_bias, 1.0 / 3.0, 1.0 / 3.0 + shoulder_bias]
	var air_conductance := float(axle_cfg.get("tread_to_air_w_k", 0.0)) / 3.0
	var road_conductance := float(axle_cfg.get("road_conductance_w_k", 0.0)) / 3.0
	var carcass_conductance := float(axle_cfg.get("tread_to_carcass_w_k", 0.0)) / 3.0
	var lateral_conductance := float(axle_cfg.get("lateral_tread_conductance_w_k", 0.0)) / 2.0
	for zone_index in 3:
		var zone_temperature := float(zones[zone_index])
		var lateral_heat := 0.0
		if zone_index > 0:
			lateral_heat += lateral_conductance * (float(zones[zone_index - 1]) - zone_temperature)
		if zone_index < 2:
			lateral_heat += lateral_conductance * (float(zones[zone_index + 1]) - zone_temperature)
		var zone_to_carcass := carcass_conductance * (zone_temperature - carcass)
		var zone_heat := slip_heat * float(heat_shares[zone_index]) - zone_to_carcass
		zone_heat -= air_conductance * (zone_temperature - ambient_temperature_c)
		zone_heat -= road_conductance * (zone_temperature - float(axle_cfg.get("track_fallback_c", ambient_temperature_c)))
		zone_heat += lateral_heat
		zones[zone_index] = clampf(zone_temperature + dt * zone_heat / tread_capacity, ambient_temperature_c, 150.0)
	tread = (float(zones[0]) + float(zones[1]) + float(zones[2])) / 3.0
	var hysteresis_eff := clampf(float(axle_cfg.get("carcass_hysteresis_efficiency", 0.55)), 0.0, 1.0)
	var next_carcass := carcass + dt * (tread_to_carcass + maxf(radial_damping_power_w, 0.0) * hysteresis_eff - carcass_to_gas - float(axle_cfg.get("carcass_to_air_w_k", 0.0)) * (carcass - ambient_temperature_c)) / carcass_capacity
	var next_gas := gas + dt * carcass_to_gas / gas_capacity
	state.tread_zones_c = zones
	state.tread_c = tread
	state.surface_c = state.tread_c
	state.carcass_c = clampf(next_carcass, ambient_temperature_c, 180.0)
	state.gas_c = clampf(next_gas, ambient_temperature_c, 180.0)
	var atmosphere_bar := float(axle_pressure_cfg.get("atmospheric_pressure_kpa", 101.325)) / 100.0
	var reference_absolute := float(state.pressure_reference_bar_gauge) + atmosphere_bar
	var reference_kelvin := maxf(float(state.pressure_reference_temp_c) + 273.15, 1.0)
	var current_kelvin := maxf(float(state.gas_c) + 273.15, 1.0)
	state.pressure_bar_gauge = clampf(reference_absolute * current_kelvin / reference_kelvin - atmosphere_bar, 0.0, 4.0)
	state.wear_fraction = clampf(float(state.wear_fraction) + maxf(friction_power_w, 0.0) * dt * 1.0e-9, 0.0, 1.0)
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
	tire_states[index] = state


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
	var axle_cfg := _axle_tire_config(index)
	var state: Dictionary = tire_states[index]
	var optimum := float(axle_cfg.get("optimal_tread_temperature_c", 50.0))
	var half_window := float(axle_cfg.get("optimal_tread_window_c", 50.0)) * 0.5
	var upper := optimum + half_window
	var lower := optimum - half_window
	var tread := float(state.tread_c)
	var overheat := float(axle_cfg.get("overheat_tread_temperature_c", 100.0))
	var thermal_factor := 1.0
	if tread < lower:
		thermal_factor = clampf(0.80 + 0.20 * clampf((tread - (lower - 30.0)) / 30.0, 0.0, 1.0), 0.70, 1.0)
	elif tread > upper:
		thermal_factor = clampf(1.0 - 0.25 * clampf((tread - upper) / maxf(overheat - upper, 1.0), 0.0, 1.0), 0.70, 1.0)
	var wear_factor := clampf(1.0 - 0.25 * float(state.wear_fraction), 0.70, 1.0)
	return thermal_factor * wear_factor


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
	# VehicleInternalState in vehicle-models uses 1.05e-7 litres per positive joule.
	var burn := maxf(engine_power_w, 0.0) * maxf(delta, 0.0) * 1.05e-7
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
			"optimal_min_c": engine_config.get("oil_optimal_minimum_temperature_celsius"),
			"optimal_max_c": engine_config.get("oil_optimal_maximum_temperature_celsius"),
			"derating_c": engine_config.get("oil_hot_derating_temperature_celsius"),
			"critical_c": engine_config.get("oil_critical_temperature_celsius"),
		},
		"available_torque_fraction": available_engine_torque_fraction,
		"cooling_drag_force_n": cooling_drag_force_n,
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
		"wear_fraction": state.wear_fraction,
		"brake_disc_c": state.brake_disc_c,
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
	available_engine_torque_fraction = clampf(minf(water_fraction, oil_fraction), float(engine_config.get("minimum_hot_engine_torque_fraction", 0.70)), 1.0)


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


func _axle_tire_config(index: int) -> Dictionary:
	if index < 2:
		return tire_config_front if not tire_config_front.is_empty() else tire_config
	return tire_config_rear if not tire_config_rear.is_empty() else tire_config


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
