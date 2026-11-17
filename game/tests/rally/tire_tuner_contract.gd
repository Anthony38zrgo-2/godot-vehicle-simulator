extends SceneTree

const PROFILE := "res://data/vehicles/ford-escort-rs2000/vehicle.json"
const ASSET := "res://assets/rally/ford_escort_rs2000_1971/manifest.json"

class TestVehicle extends Node:
	var simulation := FordRallyVehicleSimulation.new()

class TestSession extends Node:
	var vehicle := TestVehicle.new()
	var session_ready := true
	var awaiting_setup := false
	var stage_transition_running := false
	var competition: Node
	var garage_panel: Control
	var pause_inventory: Node
	var pacenotes: Node

class TestPanel extends RallyTireTunerPanel:
	func _play_window_sound(_opening: bool) -> void:
		pass

	func _sync_pause_audio_and_pacenotes(_paused_state: bool) -> void:
		pass

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var session := TestSession.new()
	root.add_child(session)
	session.add_child(session.vehicle)
	var sim := session.vehicle.simulation
	var asset: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSET))
	var loaded := sim.configure(asset, PROFILE)
	if not loaded.get("ok", false):
		push_error(str(loaded))
		quit(1)
		return
	_check(sim.tire_model.set_wheel_compound(1, "gravel_wet"), "Mixed fitment is available")
	sim.thermal_model.set_wheel_compound(1, "gravel_wet")
	sim.tire_sources["tire_filters"] = {"tire_filters": {"rear": {"falloff_sharpness": 1.33}}}
	_check(sim.reload_tire_catalog_runtime(), "Reload accepts vehicle filters")
	sim.domains["tires"]["tires"]["pressure"]["cold_kpa_gauge"]["FL"] = 174.0
	var catalog := RallyTireCompound.load_catalog()
	var reference := sim.make_tire_calibration_model(catalog)
	var trace := _sample(sim.tire_model)
	var states := sim.tire_model.states.duplicate(true)
	var thermal_states := sim.thermal_model.tire_states.duplicate(true)
	_check(sim.reload_tire_catalog_runtime(), "Reload succeeds with the same catalog")
	_check(sim.tire_model.states == states and sim.thermal_model.tire_states == thermal_states, "Reload preserves contact and thermal state")
	_check(sim.domains["tires"]["tires"]["pressure"]["cold_kpa_gauge"]["FL"] == 174.0, "Reload preserves session pressure")
	_check(sim.tire_model.axle_profiles[2]["falloff_sharpness"] == 1.33, "Reload preserves vehicle tire filters")
	_check(sim.tire_model.wheel_compounds[1]["id"] == "gravel_wet", "Reload preserves each mounted compound")
	_check(sim.tire_model.states == states, "Preview configuration does not affect live contact")
	_check(trace == _sample(reference) and trace == _sample(sim.make_tire_calibration_model(catalog)), "Preview and unchanged reload give identical force and state traces")

	var panel := TestPanel.new()
	panel.session = session
	root.add_child(panel)
	panel.open_panel()
	_check(panel.is_open(), "Calibration opens from a ready session")
	_check(panel._count_pending_changes() == 0 and panel._apply_button.disabled, "Opening the panel is a no-op")
	_check(panel._curve_plots["front"]._current.size() == 101, "Live panel samples the front pure curve")
	_check(panel._routes["rear"]["fm.falloff_sharpness"]["blocked"], "Panel respects the vehicle override")
	_check(panel._loaded_values["front"]["rad.damping_ratio"] == TireRadialModel.MIN_DAMPING_RATIO, "Panel shows effective radial floor")
	panel._wheel_side = 1
	panel._reload_from_disk_into_ui()
	var compound_id := "fm.combined_longitudinal_peak_migration"
	_check(panel._routes["front"][compound_id]["path"][1] == "gravel_wet", "Compound edit follows the selected wheel")
	var rows: Array = panel._rows_by_param["front"][compound_id]
	var edit: LineEdit = rows[0]["edit"]
	edit.text = "0.4"
	edit.text_changed.emit(edit.text)
	var changes: Dictionary = panel._collect_validated_values()["values"]
	_check(changes["front"].size() == 1 and changes["rear"].is_empty(), "Only changed rows are collected")
	var edited := panel._apply_values_to_catalog(catalog, changes)
	var expected := catalog.duplicate(true)
	expected["compounds"]["gravel_wet"]["force_model"]["front"]["combined_longitudinal_peak_migration"] = 0.4
	_check(edited == expected, "Single edit writes the mounted compound only")
	var preview := sim.make_tire_calibration_model(edited)
	_check(preview.axle_profiles[1]["combined_longitudinal_peak_migration"] == 0.4 and preview.axle_profiles[0] == reference.axle_profiles[0], "Only wheels with the edited compound and axle change")

	var load_id := "ax.load_sensitivity_per_newton"
	var length_id := "ax.relaxation_length_scale"
	var requested_length := 0.31
	var requested_load := 45.0
	var reshaped := panel._apply_values_to_catalog(catalog, {"front": {load_id: requested_load, length_id: requested_length}, "rear": {}})
	preview = sim.make_tire_calibration_model(reshaped)
	_check(is_equal_approx(preview.base_relaxation_length_m[1], requested_length), "Metre control resolves to the requested relaxation length")
	_check(is_equal_approx(preview.axle_load_sensitivity[1] * preview.axle_load_mult[1] * 1.0e6, requested_load), "Load control preserves hidden multiplier semantics")
	_check(sim.tire_model.states == states, "Curves and edit previews leave running contact untouched")

	var path := "user://tire_tuner_contract_%d.json" % OS.get_process_id()
	_check(panel._write_json_dict(path, catalog) and panel._write_json_dict(path, edited), "Atomic save can replace an existing JSON file")
	_check(panel._read_json_dict(path) == edited, "Saved JSON round-trips without changing other coefficients")
	DirAccess.remove_absolute(path)
	panel.close_panel()
	if failures == 0:
		print("TIRE TUNER CONTRACT PASSED")
	quit(1 if failures else 0)


func _sample(model: TireModel) -> Array[Dictionary]:
	var trace: Array[Dictionary] = []
	for step in 120:
		var load := 3300.0 if step < 60 else 1900.0
		var surface := "Road" if step < 40 else "Gravel"
		trace.append(model.evaluate(1, load, surface, 20.0, -1.7, 79.0, 0.28, 0.03, 0.92, 175.0, 1.0 / 120.0, 60.0))
	return trace
