class_name VehicleThermalModel
extends RefCounted

var engine_config: Dictionary = {}
var tire_config: Dictionary = {}
var pressure_config: Dictionary = {}
var pressure_mechanics: Dictionary = {}
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


func configure(domains: Dictionary) -> Dictionary:
	var powertrain: Dictionary = domains.get("powertrain", {}).get("powertrain", {})
	engine_config = powertrain.get("thermal", {}).duplicate(true)
	if engine_config.is_empty():
		return {"ok": false, "error": "powertrain.thermal configuration is required for the thermal HUD and torque derating."}
	engine_block_temperature_c = float(engine_config.get("initial_engine_block_temperature_celsius", 85.0))
	water_temperature_c = float(engine_config.get("initial_water_temperature_celsius", 82.0))
	oil_temperature_c = float(engine_config.get("initial_oil_temperature_celsius", 85.0))
	var tires: Dictionary = domains.get("tires", {}).get("tires", {})
	tire_config = tires.get("thermal", {}).duplicate(true)
	pressure_config = tires.get("pressure", {}).duplicate(true)
	pressure_mechanics = tires.get("pressure_mechanics", {}).duplicate(true)
	ambient_temperature_c = float(tire_config.get("ambient_fallback_c", 25.0))
	var fuel: Dictionary = domains.get("fuel", {}).get("fuel", {})
	fuel_density_kg_litre = float(fuel.get("density_kg_per_litre", 0.74))
	fuel_capacity_litres = float(fuel.get("capacity_kg", 0.0)) / maxf(fuel_density_kg_litre, 0.000001)
	fuel_remaining_litres = float(fuel.get("initial_kg", fuel.get("capacity_kg", 0.0))) / maxf(fuel_density_kg_litre, 0.000001)
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
			"brake_disc_c": ambient_temperature_c,
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


func advance_tire(index: int, friction_power_w: float, braking_power_w: float, speed_m_s: float, delta: float, camber_rad: float = 0.0) -> void:
	if index < 0 or index >= tire_states.size():
		return
	var state: Dictionary = tire_states[index]
	var dt := maxf(delta, 0.0)
	var zones: Array = state.get("tread_zones_c", [state.tread_c, state.tread_c, state.tread_c]).duplicate()
	var tread := (float(zones[0]) + float(zones[1]) + float(zones[2])) / 3.0
	var carcass := float(state.carcass_c)
	var gas := float(state.gas_c)
	var tread_to_carcass := float(tire_config.get("tread_to_carcass_w_k", 0.0)) * (tread - carcass)
	var carcass_to_gas := float(tire_config.get("carcass_to_gas_w_k", 0.0)) * (carcass - gas)
	var slip_heat := maxf(friction_power_w, 0.0) * float(tire_config.get("slip_heat_efficiency", 0.0))
	var tread_capacity := maxf(float(tire_config.get("tread_zone_heat_capacity_j_k", 1.0)) / 3.0, 1.0)
	var carcass_capacity := maxf(float(tire_config.get("carcass_heat_capacity_j_k", 1.0)), 1.0)
	var gas_capacity := maxf(float(tire_config.get("gas_heat_capacity_j_k", 1.0)), 1.0)
	# Camber changes shoulder loading. Positive physical camber biases heat outward;
	# the center remains nearly neutral and total generated heat stays conserved.
	var shoulder_bias := clampf(camber_rad / deg_to_rad(8.0), -1.0, 1.0) * 0.18
	var heat_shares := [1.0 / 3.0 - shoulder_bias, 1.0 / 3.0, 1.0 / 3.0 + shoulder_bias]
	var air_conductance := float(tire_config.get("tread_to_air_w_k", 0.0)) / 3.0
	var road_conductance := float(tire_config.get("road_conductance_w_k", 0.0)) / 3.0
	var carcass_conductance := float(tire_config.get("tread_to_carcass_w_k", 0.0)) / 3.0
	var lateral_conductance := float(tire_config.get("lateral_tread_conductance_w_k", 0.0)) / 2.0
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
		zone_heat -= road_conductance * (zone_temperature - float(tire_config.get("track_fallback_c", ambient_temperature_c)))
		zone_heat += lateral_heat
		zones[zone_index] = clampf(zone_temperature + dt * zone_heat / tread_capacity, ambient_temperature_c, 150.0)
	tread = (float(zones[0]) + float(zones[1]) + float(zones[2])) / 3.0
	var next_carcass := carcass + dt * (tread_to_carcass - carcass_to_gas - float(tire_config.get("carcass_to_air_w_k", 0.0)) * (carcass - ambient_temperature_c)) / carcass_capacity
	var next_gas := gas + dt * carcass_to_gas / gas_capacity
	state.tread_zones_c = zones
	state.tread_c = tread
	state.surface_c = state.tread_c
	state.carcass_c = clampf(next_carcass, ambient_temperature_c, 180.0)
	state.gas_c = clampf(next_gas, ambient_temperature_c, 180.0)
	var atmosphere_bar := float(pressure_config.get("atmospheric_pressure_kpa", 101.325)) / 100.0
	var reference_absolute := float(state.pressure_reference_bar_gauge) + atmosphere_bar
	var reference_kelvin := maxf(float(state.pressure_reference_temp_c) + 273.15, 1.0)
	var current_kelvin := maxf(float(state.gas_c) + 273.15, 1.0)
	state.pressure_bar_gauge = clampf(reference_absolute * current_kelvin / reference_kelvin - atmosphere_bar, 0.5, 4.0)
	state.wear_fraction = clampf(float(state.wear_fraction) + maxf(friction_power_w, 0.0) * dt * 1.0e-9, 0.0, 1.0)
	var cooling_speed := maxf(absf(speed_m_s), 1.0)
	var disc_cooling := 20.0 + 12.0 * cooling_speed
	var disc_temperature := float(state.brake_disc_c)
	state.brake_disc_c = clampf(disc_temperature + (maxf(braking_power_w, 0.0) - disc_cooling * (disc_temperature - ambient_temperature_c)) / 2500.0 * dt, ambient_temperature_c, 900.0)
	tire_states[index] = state


func tire_grip_factor(index: int) -> float:
	var state: Dictionary = tire_states[index]
	var optimum := float(tire_config.get("optimal_tread_temperature_c", 50.0))
	var half_window := float(tire_config.get("optimal_tread_window_c", 50.0)) * 0.5
	var upper := optimum + half_window
	var lower := optimum - half_window
	var tread := float(state.tread_c)
	var overheat := float(tire_config.get("overheat_tread_temperature_c", 100.0))
	var thermal_factor := 1.0
	if tread < lower:
		thermal_factor = clampf(0.80 + 0.20 * clampf((tread - (lower - 30.0)) / 30.0, 0.0, 1.0), 0.70, 1.0)
	elif tread > upper:
		thermal_factor = clampf(1.0 - 0.25 * clampf((tread - upper) / maxf(overheat - upper, 1.0), 0.0, 1.0), 0.70, 1.0)
	var wear_factor := clampf(1.0 - 0.25 * float(state.wear_fraction), 0.70, 1.0)
	return thermal_factor * wear_factor


func brake_fade_factor(index: int) -> float:
	var temperature := float(tire_states[index].brake_disc_c)
	if temperature <= 550.0:
		return 1.0
	return clampf(1.0 - 0.50 * ((temperature - 550.0) / 300.0), 0.40, 1.0)


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
