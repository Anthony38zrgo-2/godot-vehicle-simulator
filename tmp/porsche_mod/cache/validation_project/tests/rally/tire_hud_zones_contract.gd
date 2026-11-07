extends SceneTree


func _initialize() -> void:
	var loaded := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	assert(loaded.ok)
	var panel = preload("res://scripts/rally/formula_hud_panels.gd").new()
	var thermal := VehicleThermalModel.new()
	thermal.configure(loaded.domains)
	for compound in ["gravel_normal", "gravel_wet"]:
		thermal.set_compound(compound)
		panel.thermal_config = thermal.tire_config
		var optimum := float(thermal.active_compound.tread_optimum_c)
		var half_window := float(thermal.active_compound.tread_window_c) * 0.5
		var overheat := float(thermal.active_compound.overheat_tread_c)
		assert(panel.tire_color(optimum - half_window) == panel.palette.thermal_cold_color)
		assert(panel.tire_color(optimum) == panel.palette.thermal_optimal_color)
		assert(panel.tire_color(overheat) == panel.palette.thermal_warm_color)
		assert(panel.tire_color(overheat + 1.0) == panel.palette.thermal_hot_color)
		assert(panel.tire_color(140.0) == panel.palette.thermal_critical_color)
		thermal.tire_states[0].tread_zones_c = [optimum - half_window, optimum, overheat + 1.0]
		var wheel := thermal.get_tire_thermal_state_snapshot(0)
		var left: Array[Color] = panel.tire_zone_colors(wheel, 0)
		var right: Array[Color] = panel.tire_zone_colors(wheel, 1)
		assert(left == [panel.palette.thermal_hot_color, panel.palette.thermal_optimal_color, panel.palette.thermal_cold_color])
		assert(right == [panel.palette.thermal_cold_color, panel.palette.thermal_optimal_color, panel.palette.thermal_hot_color])
		assert(panel.tire_zone_colors({}, 0)[0] == panel.palette.pending_color)
	panel.free()
	print("TIRE_HUD_ZONES_CONTRACT PASS")
	quit()
