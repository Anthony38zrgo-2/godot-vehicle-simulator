class_name UITabBar
extends PanelContainer
## Unified horizontal tab bar with semantic active state, cyclic keyboard focus, and step_tab() for LB/RB.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _Focus := preload("res://scripts/ui/core/ui_focus_navigator.gd")

signal tab_selected(index: int, tab_id: String)

var _row: HBoxContainer
var _tabs: Array[Dictionary] = []
var _buttons: Array[Button] = []
var active_index: int = 0


func _ready() -> void:
	_ensure_nodes()
	add_theme_stylebox_override("panel", _Theme.make_flat_panel("bg_shell", "border_subtle", 1, _Tokens.get_radius("technical"), 8, 6))


func _ensure_nodes() -> void:
	if _row != null:
		return
	_row = get_node_or_null("TabsRow") as HBoxContainer
	if _row == null:
		_row = HBoxContainer.new()
		_row.name = "TabsRow"
		_row.add_theme_constant_override("separation", 6)
		add_child(_row)


func set_tabs(tab_specs: Array, initial_index: int = 0) -> void:
	_ensure_nodes()
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_tabs.clear()
	_buttons.clear()
	for i in tab_specs.size():
		var item: Variant = tab_specs[i]
		var tab_id := str(item.get("id", str(i))) if item is Dictionary else str(item)
		var label_text := str(item.get("label", tab_id)) if item is Dictionary else str(item)
		_tabs.append({"id": tab_id, "label": label_text})
		var btn := Button.new()
		btn.text = label_text
		btn.focus_mode = Control.FOCUS_ALL
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		btn.pressed.connect(func() -> void: select_tab(idx, true))
		_row.add_child(btn)
		_buttons.append(btn)
	if is_inside_tree():
		_Focus.wire_horizontal_cycle(_buttons)
	select_tab(clampi(initial_index, 0, maxi(0, _tabs.size() - 1)), false)


func select_tab(index: int, emit_signal_flag: bool = true) -> void:
	if _tabs.is_empty():
		return
	active_index = clampi(index, 0, _tabs.size() - 1)
	for i in _buttons.size():
		var is_active := (i == active_index)
		_Theme.apply_tone_button(_buttons[i], "accent" if is_active else "muted", 13, 14, 7)
	if emit_signal_flag:
		tab_selected.emit(active_index, str(_tabs[active_index]["id"]))


func select_tab_by_id(tab_id: String, emit_signal_flag: bool = true) -> void:
	for i in _tabs.size():
		if str(_tabs[i]["id"]) == tab_id:
			select_tab(i, emit_signal_flag)
			return


func step_tab(delta: int) -> void:
	if _tabs.is_empty():
		return
	select_tab(posmod(active_index + delta, _tabs.size()), true)


func get_active_tab_id() -> String:
	if active_index >= 0 and active_index < _tabs.size():
		return str(_tabs[active_index]["id"])
	return ""


func get_tab_button(index: int) -> Button:
	if index >= 0 and index < _buttons.size():
		return _buttons[index]
	return null
