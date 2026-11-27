class_name UIFocusNavigator
extends RefCounted
## Centralizes cyclic keyboard/gamepad focus wiring and per-screen focus memory.

var _saved_focus_by_screen: Dictionary = {}


func remember_focus(screen_id: String, control: Control) -> void:
	if screen_id.is_empty():
		return
	if control != null and is_instance_valid(control):
		_saved_focus_by_screen[screen_id] = weakref(control)


func get_remembered_focus(screen_id: String) -> Control:
	var wr: Variant = _saved_focus_by_screen.get(screen_id, null)
	if wr is WeakRef:
		var obj: Variant = (wr as WeakRef).get_ref()
		if obj is Control and is_instance_valid(obj):
			return obj as Control
	return null


func restore_focus(screen_id: String, fallback: Control = null) -> bool:
	var target := get_remembered_focus(screen_id)
	if target == null or not target.is_visible_in_tree():
		target = fallback
	return focus_safe(target)


static func focus_safe(control: Control) -> bool:
	if control == null or not is_instance_valid(control):
		return false
	if not control.is_inside_tree() or not control.visible:
		return false
	if control.focus_mode == Control.FOCUS_NONE:
		return false
	control.grab_focus()
	return true


static func wire_horizontal_cycle(controls: Array) -> void:
	var valid: Array[Control] = []
	for item in controls:
		if item is Control and is_instance_valid(item) and (item as Control).is_inside_tree():
			valid.append(item as Control)
	var n := valid.size()
	if n < 2:
		return
	for i in n:
		var cur := valid[i]
		var prev := valid[(i - 1 + n) % n]
		var nxt := valid[(i + 1) % n]
		cur.focus_neighbor_left = cur.get_path_to(prev)
		cur.focus_neighbor_right = cur.get_path_to(nxt)
		cur.focus_previous = cur.get_path_to(prev)
		cur.focus_next = cur.get_path_to(nxt)


static func wire_vertical_cycle(controls: Array) -> void:
	var valid: Array[Control] = []
	for item in controls:
		if item is Control and is_instance_valid(item) and (item as Control).is_inside_tree():
			valid.append(item as Control)
	var n := valid.size()
	if n < 2:
		return
	for i in n:
		var cur := valid[i]
		var prev := valid[(i - 1 + n) % n]
		var nxt := valid[(i + 1) % n]
		cur.focus_neighbor_top = cur.get_path_to(prev)
		cur.focus_neighbor_bottom = cur.get_path_to(nxt)
		cur.focus_previous = cur.get_path_to(prev)
		cur.focus_next = cur.get_path_to(nxt)
