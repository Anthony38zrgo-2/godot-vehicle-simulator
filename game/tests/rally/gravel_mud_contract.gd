extends SceneTree

func _initialize() -> void:
	var profile := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	var tire := TireModel.new()
	tire.configure(profile.domains, profile.resolved_tire_filters, [3500.0, 3500.0, 3500.0, 3500.0])
	var compact := _grip(tire, 0.0, 0.0)
	var loose := _grip(tire, 0.70, 0.0) / compact
	var mixed := _grip(tire, 0.70, 0.35) / compact
	var mud := _grip(tire, 0.70, 0.70) / compact
	var drag := FordRallyVehicleSimulation.mud_plowing_force_n(0.70, 3500.0, 40.0 / 3.6)
	var creep := FordRallyVehicleSimulation.mud_plowing_force_n(0.70, 3500.0, 3.0)
	var ok := loose >= 0.92 and loose <= 0.95 and mud >= 0.65 and mud <= 0.75 and mixed < loose and mixed > mud
	ok = ok and drag > 350.0 and drag < 490.0 and creep > 260.0 and creep < drag
	ok = ok and FordRallyVehicleSimulation.mud_plowing_force_n(0.70, 0.0, 40.0) == 0.0
	ok = ok and FordRallyVehicleSimulation.mud_plowing_force_n(0.70, 3500.0, 0.0) == 0.0
	ok = ok and FordRallyVehicleSimulation.mud_plowing_force_n(0.0, 3500.0, 40.0) == 0.0
	print("GRAVEL_MUD_CONTRACT ", "PASS" if ok else "FAIL", " grip=", [loose, mixed, mud], " drag_N=", [creep, drag])
	quit(0 if ok else 1)


func _grip(tire: TireModel, loose: float, mud: float) -> float:
	for i in 40:
		tire.evaluate(0, 3500.0, "Gravel", 11.0, 0.0, 40.0, 0.30, 0.0, 1.0, 200.0, 0.025, 30.0,
			0.0, 0.0, 30.0, "", 0.0, -1.0, -1.0, loose, mud)
	return float(tire.states[0].surface_friction)
