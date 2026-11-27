class_name UIPanelFooter
extends PanelContainer
## Standard Motorsport panel footer: left navigation hint + right action buttons container.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _Factory := preload("res://scripts/ui/core/ui_component_factory.gd")

var hint_label: Label
var actions_box: HBoxContainer
var _row: HBoxContainer


func _ready() -> void:
	_ensure_nodes()
	_apply_style()


func _ensure_nodes() -> void:
	if _row != null:
		return
	_row = get_node_or_null("FooterRow") as HBoxContainer
	if _row == null:
		_row = HBoxContainer.new()
		_row.name = "FooterRow"
		_row.add_theme_constant_override("separation", 12)
		add_child(_row)

	hint_label = _row.get_node_or_null("HintLabel") as Label
	if hint_label == null:
		hint_label = Label.new()
		hint_label.name = "HintLabel"
		hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_row.add_child(hint_label)

	actions_box = _row.get_node_or_null("ActionsBox") as HBoxContainer
	if actions_box == null:
		actions_box = HBoxContainer.new()
		actions_box.name = "ActionsBox"
		actions_box.alignment = BoxContainer.ALIGNMENT_END
		actions_box.add_theme_constant_override("separation", 10)
		_row.add_child(actions_box)


func _apply_style() -> void:
	add_theme_stylebox_override("panel", _Theme.make_flat_panel("bg_shell", "border_subtle", 1, _Tokens.get_radius("technical"), 16, 10))
	_Theme.apply_label(hint_label, "muted", 12, false, false)


func set_hint(text: String) -> void:
	_ensure_nodes()
	_apply_style()
	hint_label.text = text


func clear_actions() -> void:
	_ensure_nodes()
	for child in actions_box.get_children():
		actions_box.remove_child(child)
		child.queue_free()


func add_action(text: String, preset_or_tone: String = "button.secondary_chrome", callback: Callable = Callable(), overrides: Dictionary = {}) -> Button:
	_ensure_nodes()
	var btn := _Factory.create_button(text, preset_or_tone, callback, overrides)
	actions_box.add_child(btn)
	return btn
