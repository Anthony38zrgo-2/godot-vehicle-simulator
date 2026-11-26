extends SceneTree

func _initialize() -> void:
	var profile := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	var tire := TireModel.new()
	tire.configure(profile.domains, profile.resolved_tire_filters, [3500.0, 3500.0, 3500.0, 3500.0])
	var compact := _grip(tire, 0.0, 0.0)
	var loose := _grip(tire, 0.70, 0.0) / compact
	var mixed := _grip(tire, 0.70, 0.35) / compact
	var mud := _grip(tire, 0.70, 0.70) / compact
	var drag_40 := FordRallyVehicleSimulation.mud_plowing_force_n(0.85, 3500.0, 40.0 / 3.6)
	var drag_70 := FordRallyVehicleSimulation.mud_plowing_force_n(0.85, 3500.0, 70.0 / 3.6)
	var creep := FordRallyVehicleSimulation.mud_plowing_force_n(0.85, 3500.0, 3.0)
	var ok := loose >= 0.92 and loose <= 0.95 and mud >= 0.64 and mud <= 0.75 and mixed < loose and mixed > mud
	ok = ok and creep > 800.0 and drag_40 > 1300.0 and drag_40 < 1700.0 and drag_70 > 2000.0 and drag_70 < 2500.0 and creep < drag_40 and drag_40 < drag_70
	ok = ok and FordRallyVehicleSimulation.mud_plowing_force_n(0.85, 0.0, 40.0) == 0.0
	ok = ok and FordRallyVehicleSimulation.mud_plowing_force_n(0.85, 3500.0, 0.0) == 0.0
	ok = ok and FordRallyVehicleSimulation.mud_plowing_force_n(0.0, 3500.0, 40.0) == 0.0
	print("GRAVEL_MUD_CONTRACT ", "PASS" if ok else "FAIL", " grip=", [loose, mixed, mud], " drag_N=", [creep, drag_40, drag_70])
	quit(0 if ok else 1)


func _grip(tire: TireModel, loose: float, mud: float) -> float:
	for i in 40:
		tire.evaluate(0, 3500.0, "Gravel", 11.0, 0.0, 40.0, 0.30, 0.0, 1.0, 200.0, 0.025, 30.0,
			0.0, 0.0, 30.0, "", 0.0, -1.0, -1.0, loose, mud)
	return float(tire.states[0].surface_friction)
