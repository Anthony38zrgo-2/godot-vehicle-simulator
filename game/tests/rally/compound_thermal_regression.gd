extends SceneTree

func simulate(domains: Dictionary, compound: String, water: float) -> float:
	var thermal := VehicleThermalModel.new()
	thermal.configure(domains)
	thermal.set_compound(compound)
	thermal.reset_for_stage(domains)
	for step in 6000:
		thermal.advance_tire(0, 1800.0, 0.0, 20.0, 0.02, 0.0, 0.0, 0.0, "Gravel", 2500.0, 0.0, 70.0, 20.0, 0.28, water, 0.0, 18.0, 15.0)
	return thermal.tire_states[0].tread_c

func _initialize() -> void:
	var profile := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	assert(profile.ok)
	var normal_dry := simulate(profile.domains, "gravel_normal", 0.0)
	var normal_rain := simulate(profile.domains, "gravel_normal", 3.0)
	var wet_dry := simulate(profile.domains, "gravel_wet", 0.0)
	var wet_rain := simulate(profile.domains, "gravel_wet", 3.0)
	print("THERMAL normal dry/wet=", normal_dry, "/", normal_rain, " wet compound dry/wet=", wet_dry, "/", wet_rain)
	assert(normal_rain < normal_dry, "water cools normal tire")
	assert(wet_dry > wet_rain, "wet tire runs hotter without water")
	print("COMPOUND_THERMAL_REGRESSION PASS")
	quit()
