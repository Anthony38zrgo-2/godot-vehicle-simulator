extends SceneTree

func _initialize() -> void:
	var aero := VehicleAerodynamicModel.new()
	aero.aero_model = {"front_wing": {"area_m2": 1.0, "position_m": [0, 0, -1], "polar": [{"angle_deg": 0, "cl": 0.0, "cd": 0.5}]}}
	for yaw in [0.0, PI * 0.5, PI]:
		var basis := Basis(Vector3.UP, yaw)
		for local_velocity in [Vector3(0, 0, -20), Vector3(0, 0, 20), Vector3(20, 0, 0), Vector3(10, 0, -20)]:
			var velocity: Vector3 = basis * local_velocity
			var effect: Dictionary = aero.wing_forces(velocity, basis)[0]
			var drag: Vector3 = effect.force
			assert(drag.dot(velocity) < 0.0, "drag must remove energy")
			assert(drag.normalized().is_equal_approx(-velocity.normalized()), "drag opposes motion")
			assert(is_equal_approx(drag.length(), 0.5 * aero.air_density_kg_m3 * velocity.length_squared() * 0.5), "drag magnitude unchanged")
	assert((aero.wing_forces(Vector3.ZERO, Basis.IDENTITY)[0].force as Vector3).is_zero_approx(), "no force at rest")
	aero.aero_model.front_wing.polar[0].cl = 1.0
	var force: Vector3 = aero.wing_forces(Vector3(0, 0, -20), Basis.IDENTITY)[0].force
	assert(force.y < 0.0 and force.z > 0.0, "downforce and forward-motion drag have correct signs")
	aero.aero_model.clear()
	assert(aero.wing_forces(Vector3(0, 0, -20), Basis.IDENTITY).is_empty(), "no wings means no wing forces")
	print("AERODYNAMIC_DRAG_CONTRACT PASS")
	quit()
