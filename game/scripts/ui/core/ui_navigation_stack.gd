class_name UINavigationStack
extends RefCounted
## Manages screen transitions, history stack, headless-safe fades, and focus memory.

const _Focus := preload("res://scripts/ui/core/ui_focus_navigator.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")

signal screen_changed(screen_id: String)

var focus_nav := _Focus.new()
var _screens: Dictionary = {}
var _history: Array[String] = []
var _current_id: String = ""


func register_screen(screen_id: String, node: Control) -> void:
	if screen_id.is_empty() or node == null:
		return
	_screens[screen_id] = node
	node.visible = false


func has_screen(screen_id: String) -> bool:
	return _screens.has(screen_id)


func get_screen(screen_id: String) -> Control:
	return _screens.get(screen_id, null) as Control


func current_screen_id() -> String:
	return _current_id


func show_screen(screen_id: String, context: Dictionary = {}, record_history: bool = true, restore_focus_memory: bool = false) -> bool:
	if not _screens.has(screen_id):
		push_error("UINavigationStack: unregistered screen '%s'" % screen_id)
		return false
	var prev_id := _current_id
	if not prev_id.is_empty() and _screens.has(prev_id):
		var prev_node := _screens[prev_id] as Control
		if prev_node != null and is_instance_valid(prev_node):
			var vp := prev_node.get_viewport()
			if vp != null:
				var owner := vp.gui_get_focus_owner()
				if owner != null and (owner == prev_node or prev_node.is_ancestor_of(owner)):
					focus_nav.remember_focus(prev_id, owner)
			if prev_node.has_method("exit"):
				prev_node.call("exit")
			else:
				prev_node.visible = false
		if record_history and prev_id != screen_id:
			_history.append(prev_id)

	_current_id = screen_id
	var next_node := _screens[screen_id] as Control
	if next_node != null and is_instance_valid(next_node):
		next_node.visible = true
		if next_node.has_method("enter"):
			next_node.call("enter", context)
		_Theme.transition_control(next_node, true)
		var fallback: Control = next_node.call("get_default_focus_control") if next_node.has_method("get_default_focus_control") else null
		if restore_focus_memory:
			focus_nav.restore_focus(screen_id, fallback)
		else:
			_Focus.focus_safe(fallback)
	screen_changed.emit(screen_id)
	return true


func pop_screen(fallback_id: String = "") -> bool:
	while not _history.is_empty():
		var target: String = _history.pop_back()
		if _screens.has(target):
			return show_screen(target, {}, false, true)
	if not fallback_id.is_empty() and _screens.has(fallback_id):
		return show_screen(fallback_id, {}, false, true)
	return false


func clear_history() -> void:
	_history.clear()
