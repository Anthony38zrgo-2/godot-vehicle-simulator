extends Node

## Godot-owned output bus for the standalone GDScript mixer. The Rust source
## mixer config supplies output gain, saturation and limiter ceiling.

func _ready() -> void:
	_ensure_vehicle_bus()


func _ensure_vehicle_bus() -> void:
	var idx := -1
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) == "Vehicle":
			idx = i
			break

	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Vehicle")
		AudioServer.set_bus_send(idx, "Master")

	# Don't add a second limiter if the bus already has one.
	for e in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, e) is AudioEffectLimiter:
			return

	var routing := preload("res://scripts/audio/vehicle_sound_routing.gd").new()
	var master: Dictionary = routing.config.get("master", {})
	AudioServer.set_bus_volume_db(idx, float(master.get("output_db", 0.0)))
	# Rust saturation is not equivalent to Godot ATAN; retain clean headroom.
	var lim := AudioEffectLimiter.new()
	lim.threshold_db = linear_to_db(float(master.get("limiter_threshold", 0.90)))
	lim.ceiling_db = -0.3
	AudioServer.add_bus_effect(idx, lim)
