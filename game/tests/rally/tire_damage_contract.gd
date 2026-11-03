extends SceneTree

func _initialize() -> void:
	var loaded := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	assert(loaded.ok)
	for compound in ["gravel_normal", "gravel_wet"]:
		var thermal := VehicleThermalModel.new()
		thermal.configure(loaded.domains)
		thermal.set_compound(compound)
		thermal.reset_for_stage(loaded.domains)
		var tire: Dictionary = thermal.tire_states[0]
		thermal.accumulate_tire_damage(tire, 10000.0, 10.0)
		assert(tire.wear_fraction > 0.0 and tire.thermal_damage_fraction == 0.0, "friction wear at optimum without heat damage")
		var threshold := float(thermal.active_compound.thermal_damage_start_c)
		tire.tread_c = threshold + 20.0
		tire.tread_zones_c = [tire.tread_c, tire.tread_c, tire.tread_c]
		thermal.accumulate_tire_damage(tire, 0.0, 120.0)
		var damage: float = tire.thermal_damage_fraction
		var wear: float = tire.wear_fraction
		assert(damage > 0.0, "thermal damage accumulates even without sliding")
		thermal.reset_for_stage(loaded.domains)
		tire = thermal.tire_states[0]
		assert(is_equal_approx(tire.wear_fraction, wear) and is_equal_approx(tire.thermal_damage_fraction, damage), "preheating preserves permanent condition")
		var permanent_grip := thermal.tire_grip_factor(0)
		assert(permanent_grip < 1.0, "cooling cannot recover damaged grip")
		thermal.accumulate_tire_damage(tire, 0.0, 120.0)
		assert(is_equal_approx(tire.thermal_damage_fraction, damage), "no further damage at optimum")
		tire.wear_fraction = 0.0
		tire.thermal_damage_fraction = 0.0
		tire.tread_c = float(thermal.active_compound.overheat_tread_c)
		assert(is_equal_approx(thermal.tire_grip_factor(0), 1.0 - float(thermal.active_compound.overheat_grip_loss)), "runtime uses compound overheat grip loss")
		thermal.reset_for_stage(loaded.domains)
		tire = thermal.tire_states[0]
		tire.tread_zones_c = [120.0, 120.0, 120.0]
		tire.tread_c = 120.0
		thermal.advance_tire(0, 1000.0, 0.0, 20.0, 0.02)
		assert(thermal.tire_states[0].thermal_damage_fraction > 0.0, "live tire update accrues damage")
		print("TIRE_DAMAGE compound=", compound, " PASS")
	print("TIRE_DAMAGE_CONTRACT PASS")
	quit()
