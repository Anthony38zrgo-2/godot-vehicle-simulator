extends SceneTree
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var scene = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
 root.add_child(scene)
 await physics_frame
 var vehicle = scene.get_node("FordEscortRS2000")
 var ctl = scene.get_node("RallyInputController")
 vehicle.freeze = true
 ctl.set_physics_process(false)
 var setup = vehicle.get_setup_snapshot()
 assert(vehicle.apply_setup_snapshot(setup).ok)
 var engine = vehicle.simulation.powertrain_model
 assert(engine.reverse_ratio < 0.0, "setup must preserve negative reverse ratio")
 engine.current_gear = -1
 vehicle.current_gear = -1
 Input.action_press(ctl.action_throttle)
 ctl._physics_process(0.1)
 assert(vehicle.throttle_input > 0.9 and vehicle.brake_input == 0.0)
 Input.action_release(ctl.action_throttle)
 ctl.throttle_release_value = 0.0
 Input.action_press(ctl.action_brakes)
 ctl._physics_process(1.0)
 assert(vehicle.brake_input > 0.9 and vehicle.throttle_input == 0.0)
 Input.action_release(ctl.action_brakes)
 var spins: Array[float] = [0.0, 0.0, 0.0, 0.0]
 var inertias: Array[float] = [1.0, 1.0, 1.0, 1.0]
 var zeros: Array[float] = [0.0, 0.0, 0.0, 0.0]
 engine.clutch_engagement = 1.0
 engine.engine_rpm = 3000.0
 for i in 120:
  engine.advance(1.0 / 120.0, 1.0, 1.0, 1.0)
  engine.solve_rotation(1.0 / 120.0, spins, inertias, zeros, zeros)
 assert(spins[2] < 0.0 and spins[3] < 0.0, "reverse drives rear wheels backwards")
 print("REVERSE_CONTROLS_CONTRACT PASS rear_spins=", spins[2], ",", spins[3])
 scene.queue_free()
 quit()
