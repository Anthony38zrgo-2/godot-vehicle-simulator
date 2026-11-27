class_name UISpinner
extends Control
## Lightweight animated arc spinner used by loading overlays and async actions.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")

@export var radius: float = 12.0
@export var stroke_width: float = 3.0
@export var spin_speed: float = 4.6

var _angle: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2.0 + 12.0, radius * 2.0 + 12.0)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_angle = fmod(_angle + delta * spin_speed, TAU)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var accent := _Tokens.get_color("accent_rally")
	draw_arc(c, radius, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.14), stroke_width, true)
	draw_arc(c, radius, _angle, _angle + PI * 1.15, 24, accent, stroke_width, true)
