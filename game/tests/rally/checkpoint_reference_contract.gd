extends SceneTree

func _initialize() -> void:
	var sim = preload("res://scripts/rally/rally_competition.gd").new()
	sim.save_path = ""
	for stage in range(1, 11):
		assert(sim.configure("res://data/competition/stages/russia_stage%d.json" % stage))
		sim.observe_progress({"checkpoint_times": [{"index": 1, "time_ms": 1000}, {"index": 2, "time_ms": 2000}]})
		assert(sim.observation_cursor == 2, "missing optional references still consume observations")
		assert(not sim.complete and sim.sector == 0, "timing remains active")
	sim.begin_stage()
	sim.stage.checkpoint_reference_s = [1.0, 0.0]
	sim.observe_progress({"checkpoint_times": [{"index": 1, "time_ms": 1000}, {"index": 2, "time_ms": 2000}, {"index": 999, "time_ms": 3000}]})
	assert(sim.observed_factors.size() == 1, "only valid references calibrate")
	assert(sim.observation_cursor == 3, "invalid references cannot stall cursor")
	sim.observe_progress({"checkpoint_times": [{"index": 1, "time_ms": 1000}, {"index": 2, "time_ms": 2000}, {"index": 999, "time_ms": 3000}]})
	assert(sim.observed_factors.size() == 1, "observations are not counted twice")
	print("CHECKPOINT_REFERENCE_CONTRACT PASS")
	quit()
