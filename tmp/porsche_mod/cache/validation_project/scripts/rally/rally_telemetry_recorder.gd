class_name RallyTelemetryRecorder
extends Node

@export var vehicle_path: NodePath
@export var sample_every_physics_ticks: int = 4
@export var flush_every_seconds: float = 2.0
@export var measurement_start_delay_seconds: float = 0.5

var vehicle: RallyEscortVehicle
var telemetry_enabled: bool = false
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
	if vehicle == null and get_parent() != null:
		vehicle = get_parent().find_child("FordEscortRS2000", true, false) as RallyEscortVehicle
	if vehicle == null:
		push_error("Rally telemetry cannot resolve its vehicle: " + str(vehicle_path))
		set_physics_process(false)
		return
	configure_from_command_line()
	if not telemetry_file_path.is_empty():
		telemetry_enabled = true
	if not telemetry_enabled:
		set_physics_process(false)
		return

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
	var all_args: Array = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	for argument in all_args:
		if argument == "--rally-telemetry" or argument.begins_with("--rally-telemetry="):
			telemetry_enabled = true
			if argument.begins_with("--rally-telemetry="):
				telemetry_file_path = argument.trim_prefix("--rally-telemetry=")
		elif argument == "--rally-B0-audit" or argument.begins_with("--rally-B0-audit="):
			telemetry_enabled = true
		elif argument.begins_with("--rally-run-id="):
			run_identifier = argument.trim_prefix("--rally-run-id=")


func write_header() -> void:
	if telemetry_file == null:
		return
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
	var track_id_val := ""
	if get_parent() != null and "session_track_id" in get_parent():
		track_id_val = str(get_parent().session_track_id)
	var vehicle_id_val := ""
	if vehicle != null and vehicle.rally_profile != null:
		vehicle_id_val = str(vehicle.rally_profile.get("vehicle_identifier", ""))
	var metadata := {
		"run_identifier": run_identifier,
		"track_id": track_id_val,
		"vehicle_id": vehicle_id_val,
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
	if not telemetry_enabled or vehicle == null:
		return
	elapsed_seconds += delta
	physics_tick_index += 1
	if elapsed_seconds < measurement_start_delay_seconds:
		return

	var state := vehicle.get_rally_state()
	update_extremes(state)

	if telemetry_file != null and physics_tick_index % sample_every_physics_ticks == 0:
		write_sample(state)
		flush_accumulator += delta * sample_every_physics_ticks
		if flush_accumulator >= flush_every_seconds:
			flush_accumulator = 0.0
			telemetry_file.flush()


func update_extremes(state: Dictionary = {}) -> void:
	if state.is_empty() and vehicle != null:
		state = vehicle.get_rally_state()
	if state.is_empty():
		return

	maximum_speed_kilometres_per_hour = maxf(maximum_speed_kilometres_per_hour, float(state.get("speed_kilometres_per_hour", 0.0)))
	maximum_engine_revolutions_per_minute = maxf(maximum_engine_revolutions_per_minute, float(state.get("engine_revolutions_per_minute", 0.0)))
	var compressions: Array = state.get("wheel_compressions_millimetres", [])
	for compression in compressions:
		maximum_wheel_compression_millimetres = maxf(maximum_wheel_compression_millimetres, float(compression))
	minimum_contact_count = mini(minimum_contact_count, int(state.get("number_of_contacting_wheels", 4)))
	var overturned := bool(state.get("overturned", false))
	if overturned and not was_overturned:
		overturn_events += 1
	was_overturned = overturned


func write_sample(state: Dictionary = {}) -> void:
	if telemetry_file == null:
		return
	if state.is_empty() and vehicle != null:
		state = vehicle.get_rally_state()
	if state.is_empty():
		return

	var compressions: Array = state.get("wheel_compressions_millimetres", [0.0, 0.0, 0.0, 0.0])
	var surfaces: Array = state.get("wheel_surface_types", ["", "", "", ""])
	var slips: Array = state.get("wheel_slip_vectors", [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var pos: Vector3 = state.get("position", Vector3.ZERO)
	var lin_vel: Vector3 = state.get("linear_velocity", Vector3.ZERO)
	var ang_vel: Vector3 = state.get("angular_velocity", Vector3.ZERO)

	var values := [
		run_identifier,
		Time.get_datetime_string_from_system(true),
		"%.4f" % elapsed_seconds,
		str(physics_tick_index),
		"%.4f" % pos.x,
		"%.4f" % pos.y,
		"%.4f" % pos.z,
		"%.4f" % lin_vel.x,
		"%.4f" % lin_vel.y,
		"%.4f" % lin_vel.z,
		"%.4f" % ang_vel.x,
		"%.4f" % ang_vel.y,
		"%.4f" % ang_vel.z,
		"%.3f" % float(state.get("speed_kilometres_per_hour", 0.0)),
		"%.1f" % float(state.get("engine_revolutions_per_minute", 0.0)),
		str(int(state.get("current_gear", 0))),
		"%.3f" % float(state.get("throttle", 0.0)),
		"%.3f" % float(state.get("brake", 0.0)),
		"%.3f" % float(state.get("clutch", 0.0)),
		"%.3f" % float(state.get("steering_amount", 0.0)),
		"%.3f" % float(state.get("true_steering_amount", 0.0)),
		str(int(state.get("number_of_contacting_wheels", 0))),
		str(bool(state.get("airborne", false))),
		str(bool(state.get("overturned", false))),
		str(bool(state.get("sleeping", false))),
		"%.2f" % float(compressions[0] if compressions.size() > 0 else 0.0),
		"%.2f" % float(compressions[1] if compressions.size() > 1 else 0.0),
		"%.2f" % float(compressions[2] if compressions.size() > 2 else 0.0),
		"%.2f" % float(compressions[3] if compressions.size() > 3 else 0.0),
		str(surfaces[0] if surfaces.size() > 0 else ""),
		str(surfaces[1] if surfaces.size() > 1 else ""),
		str(surfaces[2] if surfaces.size() > 2 else ""),
		str(surfaces[3] if surfaces.size() > 3 else ""),
		"%.4f" % float(slips[0].x if slips.size() > 0 else 0.0),
		"%.4f" % float(slips[0].y if slips.size() > 0 else 0.0),
		"%.4f" % float(slips[1].x if slips.size() > 1 else 0.0),
		"%.4f" % float(slips[1].y if slips.size() > 1 else 0.0),
		"%.4f" % float(slips[2].x if slips.size() > 2 else 0.0),
		"%.4f" % float(slips[2].y if slips.size() > 2 else 0.0),
		"%.4f" % float(slips[3].x if slips.size() > 3 else 0.0),
		"%.4f" % float(slips[3].y if slips.size() > 3 else 0.0),
		"%.3f" % float(state.get("traction_control_max_slip", 0.0)),
		str(bool(state.get("stability_enabled", false))),
		"%.3f" % float(state.get("countersteer_assist", 0.0)),
		"%.3f" % float(state.get("steering_slip_assist", 0.0)),
		"%.1f" % float(state.get("anti_lock_brake_spin_difference_threshold", 0.0)),
		str(bool(state.get("automatic_transmission", false))),
	]
	telemetry_file.store_line(",".join(values))


func _exit_tree() -> void:
	if telemetry_file != null:
		telemetry_file.flush()
		telemetry_file.close()
		telemetry_file = null
	if not telemetry_enabled:
		return
	var track_id_val := ""
	if get_parent() != null and "session_track_id" in get_parent():
		track_id_val = str(get_parent().session_track_id)
	var vehicle_id_val := ""
	if vehicle != null and vehicle.rally_profile != null:
		vehicle_id_val = str(vehicle.rally_profile.get("vehicle_identifier", ""))
	var summary := {
		"run_identifier": run_identifier,
		"track_id": track_id_val,
		"vehicle_id": vehicle_id_val,
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
