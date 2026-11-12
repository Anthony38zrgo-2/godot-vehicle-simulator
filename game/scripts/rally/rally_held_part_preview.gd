class_name RallyHeldPartPreview
extends Control
## Vista de pieza/rueda arrastrada con muelle críticamente amortiguado.
## Extracción sin cambios de comportamiento de PartDragPreview del taller.
const SPRING_FREQUENCY := 18.0
const MAX_LAG := 36.0

var model_view: Control
var pivot: Node3D
var previous_mouse: Vector2
var displacement := Vector2.ZERO
var velocity := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	previous_mouse = get_global_mouse_position()
	if model_view != null:
		model_view.position = -model_view.size * 0.5

func _process(delta: float) -> void:
	if model_view == null:
		return
	var mouse := get_global_mouse_position()
	displacement = (displacement - (mouse - previous_mouse)).limit_length(MAX_LAG)
	previous_mouse = mouse
	var decay := exp(-SPRING_FREQUENCY * delta)
	var slope := velocity + SPRING_FREQUENCY * displacement
	displacement = (displacement + slope * delta) * decay
	velocity = (velocity - SPRING_FREQUENCY * slope * delta) * decay
	model_view.position = displacement - model_view.size * 0.5
	if pivot != null:
		pivot.rotation = Vector3(displacement.y, displacement.x * 0.35, -displacement.x) * 0.009
