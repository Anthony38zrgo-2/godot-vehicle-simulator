class_name UIDivider
extends ColorRect
## Thin 1px horizontal or vertical separator sourced from UITokenRegistry.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")

@export var vertical: bool = false
@export var color_token: String = "border_subtle"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = _Tokens.get_color(color_token)
	if vertical:
		custom_minimum_size = Vector2(1, 0)
		size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		custom_minimum_size = Vector2(0, 1)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
