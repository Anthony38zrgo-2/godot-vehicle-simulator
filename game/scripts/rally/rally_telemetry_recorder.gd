class_name RallyTelemetryRecorder
extends Node

@export var vehicle_path: NodePath
@export var sample_every_physics_ticks: int = 4
@export var flush_every_seconds: float = 2.0
@export var measurement_start_delay_seconds: float = 0.5

var vehicle: RallyEscortVehicle
var telemetry_file: FileAccess
var telemetry_file_path: String = ""
var summary_file_path: String = ""
var run_identifier: String = ""
var physics_tick_index: int = 0
var elapsed_seconds: float = 0.0
var flush_accumulator: float = 0.0
var maximum_speed_kilometres_per_hour: float = 0.0
var maximum_engine_revolutions_per_minute: float = 0.0
var maximum_wheel_compression_millimetres: float = 0.0
var minimum_contact_count: int = 4
var overturn_events: int = 0
var was_overturned: bool = false
var started_at_utc: String = ""


func _ready() -> void:
	vehicle = get_node_or_null(vehicle_path) as RallyEscortVehicle
	if vehicle == null:
		push_error("Rally telemetry cannot resolve its vehicle: " + str(vehicle_path))
		set_physics_process(false)
		return
	configure_from_command_line()
	if telemetry_file_path.is_empty():
		telemetry_file_path = "user://rally_logs/rally_telemetry_" + Time.get_datetime_string_from_system().replace(":", "-") + ".csv"
	summary_file_path = telemetry_file_path.get_basename() + "_summary.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(telemetry_file_path.get_base_dir()))
	telemetry_file = FileAccess.open(telemetry_file_path, FileAccess.WRITE)
	if telemetry_file == null:
		push_error("Rally telemetry cannot open " + telemetry_file_path)
		set_physics_process(false)
		return
	started_at_utc = Time.get_datetime_string_from_system(true)
	write_header()
	write_metadata()


func configure_from_command_line() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rally-telemetry="):
			telemetry_file_path = argument.trim_prefix("--rally-telemetry=")
		elif argument.begins_with("--rally-run-id="):
			run_identifier = argument.trim_prefix("--rally-run-id=")


func write_header() -> void:
	telemetry_file.store_line(",".join([
		"run_id",
		"utc_time",
		"elapsed_seconds",
		"physics_tick",
		"position_x",
		"position_y",
		"position_z",
		"linear_velocity_x",
		"linear_velocity_y",
		"linear_velocity_z",
		"angular_velocity_x",
		"angular_velocity_y",
		"angular_velocity_z",
		"speed_kilometres_per_hour",
		"engine_revolutions_per_minute",
		"current_gear",
		"throttle",
		"brake",
		"clutch",
		"steering",
		"true_steering",
		"contact_count",
		"airborne",
		"overturned",
		"sleeping",
		"front_left_compression_millimetres",
		"front_right_compression_millimetres",
		"rear_left_compression_millimetres",
		"rear_right_compression_millimetres",
		"front_left_surface",
		"front_right_surface",
		"rear_left_surface",
		"rear_right_surface",
		"front_left_slip_longitudinal",
		"front_left_slip_lateral",
		"front_right_slip_longitudinal",
		"front_right_slip_lateral",
		"rear_left_slip_longitudinal",
		"rear_left_slip_lateral",
		"rear_right_slip_longitudinal",
		"rear_right_slip_lateral",
		"traction_control_max_slip",
		"stability_enabled",
		"countersteer_assist",
		"steering_slip_assist",
		"anti_lock_brake_threshold",
		"automatic_transmission",
	]))


func write_metadata() -> void:
	var metadata := {
		"run_identifier": run_identifier,
		"started_at_utc": started_at_utc,
		"telemetry_file": telemetry_file_path,
		"vehicle_profile": vehicle.rally_profile_path,
		"vehicle_collision": vehicle.rally_collision_path,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"physics_engine": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"godot_version": Engine.get_version_info()["string"],
		"os": OS.get_name(),
	}
	var metadata_file := FileAccess.open(telemetry_file_path.get_basename() + "_metadata.json", FileAccess.WRITE)
	if metadata_file != null:
		metadata_file.store_string(JSON.stringify(metadata, "  "))


func _physics_process(delta: float) -> void:
	if telemetry_file == null or vehicle == null:
		return
	elapsed_seconds += delta
	physics_tick_index += 1
	if elapsed_seconds < measurement_start_delay_seconds:
		return
	update_extremes()
	if physics_tick_index % sample_every_physics_ticks != 0:
		return
	write_sample()
	flush_accumulator += delta * sample_every_physics_ticks
	if flush_accumulator >= flush_every_seconds:
		flush_accumulator = 0.0
		telemetry_file.flush()


func update_extremes() -> void:
	var state := vehicle.get_rally_state()
	maximum_speed_kilometres_per_hour = maxf(maximum_speed_kilometres_per_hour, float(state["speed_kilometres_per_hour"]))
	maximum_engine_revolutions_per_minute = maxf(maximum_engine_revolutions_per_minute, float(state["engine_revolutions_per_minute"]))
	for compression in state["wheel_compressions_millimetres"]:
		maximum_wheel_compression_millimetres = maxf(maximum_wheel_compression_millimetres, float(compression))
	minimum_contact_count = mini(minimum_contact_count, int(state["number_of_contacting_wheels"]))
	var overturned := bool(state["overturned"])
	if overturned and not was_overturned:
		overturn_events += 1
	was_overturned = overturned


func write_sample() -> void:
	var state := vehicle.get_rally_state()
	var compressions: Array = state["wheel_compressions_millimetres"]
	var surfaces: Array = state["wheel_surface_types"]
	var slips: Array = state["wheel_slip_vectors"]
	var values := [
		run_identifier,
		Time.get_datetime_string_from_system(true),
		"%.4f" % elapsed_seconds,
		str(physics_tick_index),
		"%.4f" % float(state["position"].x),
		"%.4f" % float(state["position"].y),
		"%.4f" % float(state["position"].z),
		"%.4f" % float(state["linear_velocity"].x),
		"%.4f" % float(state["linear_velocity"].y),
		"%.4f" % float(state["linear_velocity"].z),
		"%.4f" % float(state["angular_velocity"].x),
		"%.4f" % float(state["angular_velocity"].y),
		"%.4f" % float(state["angular_velocity"].z),
		"%.3f" % float(state["speed_kilometres_per_hour"]),
		"%.1f" % float(state["engine_revolutions_per_minute"]),
		str(int(state["current_gear"])),
		"%.3f" % float(state["throttle"]),
		"%.3f" % float(state["brake"]),
		"%.3f" % float(state["clutch"]),
		"%.3f" % float(state["steering_amount"]),
		"%.3f" % float(state["true_steering_amount"]),
		str(int(state["number_of_contacting_wheels"])),
		str(bool(state["airborne"])),
		str(bool(state["overturned"])),
		str(bool(state["sleeping"])),
		"%.2f" % float(compressions[0]),
		"%.2f" % float(compressions[1]),
		"%.2f" % float(compressions[2]),
		"%.2f" % float(compressions[3]),
		str(surfaces[0]),
		str(surfaces[1]),
		str(surfaces[2]),
		str(surfaces[3]),
		"%.4f" % float(slips[0].x),
		"%.4f" % float(slips[0].y),
		"%.4f" % float(slips[1].x),
		"%.4f" % float(slips[1].y),
		"%.4f" % float(slips[2].x),
		"%.4f" % float(slips[2].y),
		"%.4f" % float(slips[3].x),
		"%.4f" % float(slips[3].y),
		"%.3f" % float(state["traction_control_max_slip"]),
		str(bool(state["stability_enabled"])),
		"%.3f" % float(state["countersteer_assist"]),
		"%.3f" % float(state["steering_slip_assist"]),
		"%.1f" % float(state["anti_lock_brake_spin_difference_threshold"]),
		str(bool(state["automatic_transmission"])),
	]
	telemetry_file.store_line(",".join(values))


func _exit_tree() -> void:
	if telemetry_file != null:
		telemetry_file.flush()
		telemetry_file.close()
		telemetry_file = null
	var summary := {
		"run_identifier": run_identifier,
		"started_at_utc": started_at_utc,
		"finished_at_utc": Time.get_datetime_string_from_system(true),
		"elapsed_seconds": elapsed_seconds,
		"physics_tick_samples": physics_tick_index,
		"maximum_speed_kilometres_per_hour": maximum_speed_kilometres_per_hour,
		"maximum_engine_revolutions_per_minute": maximum_engine_revolutions_per_minute,
		"maximum_wheel_compression_millimetres": maximum_wheel_compression_millimetres,
		"minimum_contact_count": minimum_contact_count,
		"overturn_events": overturn_events,
		"ended_position": [
			vehicle.global_position.x if vehicle != null else 0.0,
			vehicle.global_position.y if vehicle != null else 0.0,
			vehicle.global_position.z if vehicle != null else 0.0,
		],
	}
	var summary_file := FileAccess.open(summary_file_path, FileAccess.WRITE)
	if summary_file != null:
		summary_file.store_string(JSON.stringify(summary, "  "))
