extends SceneTree

class FakeWeather:
	extends RefCounted
	var calendar_active: bool = true
	var current_blend: Dictionary = {}

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func _read_document(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _new_thermal_model() -> VehicleThermalModel:
	var model := VehicleThermalModel.new()
	var base := "res://data/vehicles/rt/rt-escort-rs2000/"
	var domains := {
		"powertrain": _read_document(base + "powertrain.json"),
		"brakes": _read_document(base + "brakes.json"),
		"tires": _read_document(base + "tires.json"),
	}
	var result := model.configure(domains)
	check(bool(result.get("ok", false)), "vehicle thermal configuration loads")
	return model


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# El clima físico se propaga al modelo térmico; el visual nunca es fuente.
	var simulation := FordRallyVehicleSimulation.new()
	var weather := FakeWeather.new()
	simulation.set_weather_controller(weather)
	weather.current_blend = {"air_c": 5.0}
	simulation._sync_ambient_air_temperature()
	check(is_equal_approx(simulation.thermal_model.ambient_temperature_c, 5.0), "cold air reaches thermal model")
	weather.current_blend = {"air_c": 35.0}
	simulation._sync_ambient_air_temperature()
	check(is_equal_approx(simulation.thermal_model.ambient_temperature_c, 35.0), "hot air reaches thermal model")
	weather.current_blend = {}
	simulation._sync_ambient_air_temperature()
	check(is_equal_approx(simulation.thermal_model.ambient_temperature_c, 25.0), "missing air falls back to configured ambient")
	weather.current_blend = {"air_c": 5.0}
	weather.calendar_active = false
	simulation._sync_ambient_air_temperature()
	check(is_equal_approx(simulation.thermal_model.ambient_temperature_c, 25.0), "disabled calendar uses fallback")

	var cold := _new_thermal_model()
	var hot := _new_thermal_model()
	if cold.tire_states.size() != 4 or hot.tire_states.size() != 4:
		quit(1)
		return

	cold.ambient_temperature_c = 5.0
	hot.ambient_temperature_c = 35.0
	cold.advance_engine(0.05, 4200.0, 110.0, 25.0, 1.225)
	hot.advance_engine(0.05, 4200.0, 110.0, 25.0, 1.225)
	check(cold.water_temperature_c < hot.water_temperature_c, "cooler air increases radiator heat rejection")
	check(cold.oil_temperature_c < hot.oil_temperature_c, "cooler air increases oil sump heat rejection")

	var brake_cold := cold._brake_heat_losses(0, 400.0, 25.0, 5.0)
	var brake_hot := hot._brake_heat_losses(0, 400.0, 25.0, 35.0)
	check(float(brake_cold.get("cooling_w", 0.0)) > float(brake_hot.get("cooling_w", 0.0)), "cooler air increases brake cooling")
	var brake_still := cold._brake_heat_losses(0, 400.0, 0.0, 5.0)
	check(float(brake_cold.get("cooling_w", 0.0)) > float(brake_still.get("cooling_w", 0.0)), "airflow increases brake cooling")
	var below_ambient := hot._brake_heat_losses(0, 25.0, 0.0, 35.0)
	check(float(below_ambient.get("cooling_w", 0.0)) < 0.0, "subambient brake warms through convection and radiation")

	# Un cambio de clima no puede modificar instantáneamente la masa térmica del disco.
	hot.tire_states[0]["brake_disc_c"] = 25.0
	hot.advance_tire(0, 0.0, 0.0, 0.0, 0.02)
	check(float(hot.tire_states[0].get("brake_disc_c", 0.0)) < 30.0, "ambient change does not snap brake temperature")

	print("AMBIENT_COOLING_REGRESSION ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
