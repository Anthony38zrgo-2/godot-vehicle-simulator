extends Node

## Godot-owned output bus for the standalone GDScript mixer. The Rust source
## mixer config supplies output gain and compressor threshold.

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

	var routing := preload("res://scripts/audio/vehicle_sound_routing.gd").new()
	var master: Dictionary = routing.config.get("master", {})
	AudioServer.set_bus_volume_db(idx, float(master.get("output_db", -2.0)))
	# Repeated initialization must not stack compressors.
	for e in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, e) is AudioEffectCompressor:
			return
	var comp := AudioEffectCompressor.new()
	comp.threshold = linear_to_db(maxf(float(master.get("limiter_threshold", 0.85)), 0.0001))
	comp.ratio = 3.5
	comp.attack_us = 5000.0
	comp.release_ms = 120.0
	AudioServer.add_bus_effect(idx, comp)
