class_name UIScreenView
extends Control
## Liskov-substitutable base contract for all menu screens and modal sub-views.

signal navigate_requested(screen_id: String, context: Dictionary)
signal back_requested

@export var screen_id: String = ""


func enter(_context: Dictionary = {}) -> void:
	visible = true


func exit() -> void:
	visible = false


func get_default_focus_control() -> Control:
	return null


func handle_cancel() -> bool:
	back_requested.emit()
	return true
