extends "res://scripts/rally/rally_escort_visual_damage.gd"

# Resource defaults for the Fulvia; implementation shared with the Escort.
func _init() -> void:
	damage_meshes = preload("res://assets/rally/lancia_fulvia/damage/fulvia_damage.glb")
	broken_light = preload("res://assets/rally/lancia_fulvia/damage/lights_damaged.png")
	broken_glass = preload("res://assets/rally/lancia_fulvia/damage/windows_damaged.png")
	broken_glass_inside = preload("res://assets/rally/lancia_fulvia/damage/interior_windows_damaged.png")
