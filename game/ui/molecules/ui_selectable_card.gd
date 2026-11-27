class_name UISelectableCard
extends Button
## Interactive selectable card surface for stages, weather conditions, and presets.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")

signal card_selected(card_id: String)

@export var card_id: String = ""
@export var accent_token: String = "accent_rally"

var is_selected: bool = false
var content_box: VBoxContainer


func _init() -> void:
	focus_mode = Control.FOCUS_ALL


func _ready() -> void:
	_ensure_nodes()
	pressed.connect(func() -> void: card_selected.emit(card_id))
	set_selected(is_selected)


func _ensure_nodes() -> void:
	if content_box != null:
		return
	content_box = get_node_or_null("ContentBox") as VBoxContainer
	if content_box == null:
		content_box = VBoxContainer.new()
		content_box.name = "ContentBox"
		content_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content_box.add_theme_constant_override("separation", 4)
		add_child(content_box)


func set_selected(selected: bool, accent_override: Color = Color(-1, -1, -1, -1)) -> void:
	is_selected = selected
	var col := _Tokens.get_color(accent_token) if accent_override.r < 0.0 else accent_override
	_Theme.apply_card_surface(self, is_selected, 14, 14, 10, col)
