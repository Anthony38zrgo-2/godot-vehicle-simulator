extends Control
class_name RallyTireStrategyScreen
## Pantalla inicial en 2 pasos para configurar el pool de 10 neumáticos del evento.
## Migrada de _draw() inmediato a árbol real de nodos Control (TireStrategyStep1View + TireStrategyStep2View)
## manteniendo sincronización exacta con StrategyBoard3D.

signal strategy_confirmed(initial_inventory_data: Dictionary)

const StrategyBoard3DScript := preload("res://scripts/rally/rally_strategy_screen_3d_board.gd")
const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _Step1ViewScene := preload("res://ui/screens/strategy/tire_strategy_step1_view.tscn")
const _Step2ViewScene := preload("res://ui/screens/strategy/tire_strategy_step2_view.tscn")

const LOGICAL_SIZE := Vector2(1280.0, 800.0)
const POOL_SIZE := 10
const MOUNTED_COUNT := 4

var manager: RallyEventManager
var vehicle: Node3D = null
var vehicle_name: String = ""
var allowed_compounds: Array = []
var compound_labels: Dictionary = {}

var step: int = 0
var mounted_compounds: Array = ["gravel_normal", "gravel_normal", "gravel_normal", "gravel_normal"]
var carried_spares_count: int = 2
var spare_compounds: Array = ["gravel_normal", "gravel_normal"]
var service_extra_compounds: Array = []

var forecast_stage1 := {}
var forecast_stage2 := {}

var _canvas_scale := 1.0
var _canvas_offset := Vector2.ZERO
var _focus_id := "mounted:0"
var _board_3d: StrategyBoard3DScript = null

# Real Control node tree
var _logical_root: Control
var _pill1_btn: Button
var _pill2_btn: Button
var _step1_view: Control
var _step2_view: Control
var _footer_hint_lbl: Label
var _btn_back: Button
var _btn_reset: Button
var _btn_primary: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _Theme.get_menu_theme()

	_build_ui_tree()

	_board_3d = StrategyBoard3DScript.new()
	_board_3d.name = "StrategyBoard3D"
	_board_3d.screen = self
	add_child(_board_3d)

	_init_data()
	_resize_canvas()
	call_deferred("_resize_canvas")
	_sync_all()
	set_process_input(true)
	grab_focus()


func _exit_tree() -> void:
	if _board_3d != null and is_instance_valid(_board_3d):
		_board_3d.clear_board()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_resize_canvas()


func _build_ui_tree() -> void:
	var r := _Tokens.get_radius("default")
	var c_surf := _Tokens.get_color("bg_surface")
	var c_border := _Tokens.get_color("border_card")

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = _Tokens.get_color("bg_overlay")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_logical_root = Control.new()
	_logical_root.name = "LogicalRoot"
	_logical_root.size = LOGICAL_SIZE
	_logical_root.custom_minimum_size = LOGICAL_SIZE
	_logical_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logical_root)

	# Outer window shell (30, 24, 1220, 752)
	var win_panel := Panel.new()
	win_panel.position = Vector2(30, 24)
	win_panel.size = Vector2(LOGICAL_SIZE.x - 60.0, LOGICAL_SIZE.y - 48.0)
	win_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_panel.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_surf, c_border, 1, r))
	_logical_root.add_child(win_panel)

	# Header
	var title_lbl := Label.new()
	title_lbl.position = Vector2(56, 38)
	title_lbl.text = "ESTRATEGIA DE NEUMÁTICOS"
	title_lbl.add_theme_font_override("font", _Tokens.get_font("title"))
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", _Tokens.get_color("text_primary"))
	_logical_root.add_child(title_lbl)

	_pill1_btn = Button.new()
	_pill1_btn.position = Vector2(LOGICAL_SIZE.x - 30.0 - 364.0, 42.0)
	_pill1_btn.size = Vector2(164.0, 34.0)
	_pill1_btn.text = "1 · COCHE (4)"
	_pill1_btn.focus_mode = Control.FOCUS_NONE
	_pill1_btn.pressed.connect(func() -> void: set_step(0))
	_logical_root.add_child(_pill1_btn)

	_pill2_btn = Button.new()
	_pill2_btn.position = Vector2(LOGICAL_SIZE.x - 30.0 - 190.0, 42.0)
	_pill2_btn.size = Vector2(164.0, 34.0)
	_pill2_btn.text = "2 · RESERVA (6)"
	_pill2_btn.focus_mode = Control.FOCUS_NONE
	_pill2_btn.pressed.connect(func() -> void: set_step(1))
	_logical_root.add_child(_pill2_btn)

	var header_line := ColorRect.new()
	header_line.position = Vector2(56, 90)
	header_line.size = Vector2(LOGICAL_SIZE.x - 112.0, 1)
	header_line.color = _Tokens.get_color("border_subtle")
	header_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logical_root.add_child(header_line)

	# Step views
	_step1_view = _Step1ViewScene.instantiate()
	_step1_view.preset_selected.connect(func(cid: String) -> void: apply_compound_to_mounted_all(cid))
	_logical_root.add_child(_step1_view)

	_step2_view = _Step2ViewScene.instantiate()
	_step2_view.spare_count_selected.connect(_set_spare_count)
	_logical_root.add_child(_step2_view)

	# Footer controls
	_footer_hint_lbl = Label.new()
	_footer_hint_lbl.position = Vector2(62, 704)
	_footer_hint_lbl.size = Vector2(530, 28)
	_Theme.apply_label(_footer_hint_lbl, "muted", 10, false, false)
	_logical_root.add_child(_footer_hint_lbl)

	_btn_back = Button.new()
	_btn_back.position = Vector2(604.0, 690.0)
	_btn_back.size = Vector2(168.0, 48.0)
	_btn_back.text = "← PASO 1"
	_btn_back.focus_mode = Control.FOCUS_NONE
	_btn_back.pressed.connect(func() -> void: set_step(0))
	_logical_root.add_child(_btn_back)

	_btn_reset = Button.new()
	_btn_reset.position = Vector2(786.0, 690.0)
	_btn_reset.size = Vector2(170.0, 48.0)
	_btn_reset.text = "RESTAURAR"
	_btn_reset.focus_mode = Control.FOCUS_NONE
	_btn_reset.pressed.connect(func() -> void:
		_init_data()
		_sync_all()
	)
	_logical_root.add_child(_btn_reset)

	_btn_primary = Button.new()
	_btn_primary.position = Vector2(970.0, 690.0)
	_btn_primary.size = Vector2(254.0, 48.0)
	_btn_primary.text = "SIGUIENTE"
	_btn_primary.focus_mode = Control.FOCUS_NONE
	_btn_primary.pressed.connect(_advance_or_confirm)
	_logical_root.add_child(_btn_primary)


func _resize_canvas() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_canvas_scale = minf(size.x / LOGICAL_SIZE.x, size.y / LOGICAL_SIZE.y)
	_canvas_offset = (size - LOGICAL_SIZE * _canvas_scale) * 0.5
	if _logical_root != null and is_instance_valid(_logical_root):
		_logical_root.position = _canvas_offset
		_logical_root.scale = Vector2.ONE * _canvas_scale
	if _board_3d != null and is_instance_valid(_board_3d):
		_board_3d.position = _canvas_offset
		_board_3d.scale = Vector2.ONE * _canvas_scale


func _stock_count() -> int:
	return POOL_SIZE - MOUNTED_COUNT - carried_spares_count


func _init_data() -> void:
	if manager != null:
		allowed_compounds = manager.get_allowed_compound_ids()
		if allowed_compounds.is_empty():
			allowed_compounds = ["gravel_normal", "gravel_wet"]
		var cat := RallyTireCompound.load_catalog()
		var label_overrides: Dictionary = manager.get_compound_label_overrides() if manager.has_method("get_compound_label_overrides") else {}
		compound_labels.clear()
		for cid in allowed_compounds:
			compound_labels[cid] = RallyTireCompound.compound_label(str(cid), false, label_overrides, cat)
		if not manager.weather_schedule.is_empty():
			forecast_stage1 = RallyWeatherScheduler.get_stage_dominant_weather(manager.weather_schedule[0])
		if manager.stage_forecasts.size() > 1:
			forecast_stage2 = (manager.stage_forecasts[1] as Dictionary).get("weather", {})
		elif manager.weather_schedule.size() > 1:
			forecast_stage2 = RallyWeatherScheduler.get_stage_dominant_weather(manager.weather_schedule[1])
	else:
		allowed_compounds = ["gravel_normal", "gravel_wet"]
		compound_labels["gravel_normal"] = "Grava Normal"
		compound_labels["gravel_wet"] = "Grava Lluvia"
		forecast_stage1 = {"name": "Soleado", "icon": "☀️", "temp_c": 19.0, "precip_mm": 0.0}
		forecast_stage2 = {"name": "Lluvia estimada", "icon": "🌧️", "temp_c": 14.0, "precip_mm": 2.5}
	var def_cid: String = str(allowed_compounds[0]) if not allowed_compounds.is_empty() else "gravel_normal"
	var alt_cid: String = str(allowed_compounds[1]) if allowed_compounds.size() > 1 else def_cid
	mounted_compounds = [def_cid, def_cid, def_cid, def_cid]
	carried_spares_count = 2
	spare_compounds = [def_cid, def_cid]
	service_extra_compounds.clear()
	for i in _stock_count():
		service_extra_compounds.append(alt_cid)
	_focus_id = "mounted:0" if step == 0 else "count:%d" % carried_spares_count
	_sync_all()


func set_step(next_step: int) -> void:
	step = clampi(next_step, 0, 1)
	if step == 0:
		if not (_focus_id.begins_with("mounted:") or _focus_id.begins_with("preset:") or _focus_id in ["reset", "next"]):
			_focus_id = "mounted:0"
	else:
		if not (_focus_id.begins_with("count:") or _focus_id.begins_with("spare:") or _focus_id.begins_with("stock:") or _focus_id in ["back", "reset", "confirm"]):
			_focus_id = "count:%d" % carried_spares_count
	_sync_all()


func _sync_board() -> void:
	if _board_3d != null and is_instance_valid(_board_3d):
		_board_3d.sync_from_screen()


func _sync_all() -> void:
	_sync_board()
	_refresh_control_views()


func _refresh_control_views() -> void:
	if _step1_view == null or _step2_view == null:
		return
	var r := _Tokens.get_radius("default")
	var c_gold := _Tokens.get_color("accent_rally")
	var c_card := _Tokens.get_color("bg_card")
	var c_hover := _Tokens.get_color("bg_hover")
	var c_border := _Tokens.get_color("border_card")
	var c_focus := _Tokens.get_color("border_focus")
	var c_bg := _Tokens.get_color("bg_base")
	var c_text := _Tokens.get_color("text_primary")
	var c_muted := _Tokens.get_color("text_muted")

	# Step pills
	for pair in [[_pill1_btn, step == 0], [_pill2_btn, step == 1]]:
		var btn: Button = pair[0]
		var active: bool = pair[1]
		var sb := _Tokens.get_flat_stylebox(c_gold if active else c_card, Color("#f6c96e") if active else c_border, 1, r, 10, 4)
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, sb)
		btn.add_theme_font_override("font", _Tokens.get_font("button"))
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", c_bg if active else c_muted)

	_step1_view.visible = (step == 0)
	_step2_view.visible = (step == 1)

	if step == 0:
		var prob_pct := 80
		if manager != null and manager.has_method("_forecast_accuracy"):
			prob_pct = int(round(float(manager.call("_forecast_accuracy")) * 100.0))
		_step1_view.update_view({
			"forecast_stage1": forecast_stage1,
			"forecast_stage2": forecast_stage2,
			"prob_pct": prob_pct,
			"allowed_compounds": allowed_compounds,
			"compound_labels": compound_labels,
			"mounted_compounds": mounted_compounds,
			"focus_id": _focus_id,
		})
	else:
		_step2_view.update_view(carried_spares_count, _focus_id)

	_footer_hint_lbl.text = "FLECHAS / D-PAD MOVER · ENTER / A CAMBIAR · R RESTAURAR · Y / F5 SIGUIENTE" if step == 0 else "ARRASTRA MALETERO ↔ RESERVA · ESC / B VOLVER · Y / F5 CONFIRMAR"
	_btn_back.visible = (step == 1)
	_btn_primary.text = "SIGUIENTE" if step == 0 else "CONFIRMAR"

	_style_footer_btn(_btn_back, _focus_id == "back", false, c_card, c_hover, c_border, c_focus, c_gold, c_bg, c_text, r)
	_style_footer_btn(_btn_reset, _focus_id == "reset", false, c_card, c_hover, c_border, c_focus, c_gold, c_bg, c_text, r)
	_style_footer_btn(_btn_primary, _focus_id == ("next" if step == 0 else "confirm"), true, c_card, c_hover, c_border, c_focus, c_gold, c_bg, c_text, r)


func _style_footer_btn(btn: Button, focused: bool, primary: bool, c_card: Color, c_hover: Color, c_border: Color, c_focus: Color, c_gold: Color, c_bg: Color, c_text: Color, r: int) -> void:
	var bg := c_gold if primary else (c_hover if focused else c_card)
	var border := c_focus if focused else (Color("#f6c96e") if primary else c_border)
	var sb := _Tokens.get_flat_stylebox(bg, border, 2 if focused else 1, r, 10, 6)
	var hov := _Tokens.get_flat_stylebox(Color("#f2bb54") if primary else c_hover, c_focus, 2, r, 10, 6)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)
	btn.add_theme_stylebox_override("focus", hov)
	btn.add_theme_font_override("font", _Tokens.get_font("button"))
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", c_bg if primary else c_text)
	btn.add_theme_color_override("font_hover_color", c_bg if primary else Color.WHITE)


func _nav_rows() -> Array:
	var rows: Array = []
	if step == 0:
		rows.append(["mounted:0", "mounted:1", "mounted:2", "mounted:3"])
		var preset_row: Array[String] = []
		for i in mini(allowed_compounds.size(), 4):
			preset_row.append("preset:%d" % i)
		if not preset_row.is_empty():
			rows.append(preset_row)
		rows.append(["reset", "next"])
		return rows

	var r0: Array[String] = ["count:0", "count:1", "count:2"]
	for i in carried_spares_count:
		r0.append("spare:%d" % i)
	rows.append(r0)
	var stock_count := _stock_count()
	if stock_count > 0:
		var r1: Array[String] = []
		for i in stock_count:
			r1.append("stock:%d" % i)
		rows.append(r1)
	rows.append(["back", "reset", "confirm"])
	return rows


func _move_focus(dx: int, dy: int) -> void:
	var rows := _nav_rows()
	var r_idx := 0
	var c_idx := 0
	for ri in rows.size():
		var row: Array = rows[ri]
		var found := row.find(_focus_id)
		if found >= 0:
			r_idx = ri
			c_idx = found
			break
	if dy != 0:
		var next_r := posmod(r_idx + dy, rows.size())
		var target_row: Array = rows[next_r]
		_focus_id = str(target_row[clampi(c_idx, 0, target_row.size() - 1)])
	elif dx != 0:
		var cur_row: Array = rows[r_idx]
		_focus_id = str(cur_row[posmod(c_idx + dx, cur_row.size())])
	_sync_all()


func _activate_focused() -> void:
	if _focus_id.begins_with("mounted:"):
		_cycle_compound(mounted_compounds, int(_focus_id.trim_prefix("mounted:")))
	elif _focus_id.begins_with("preset:"):
		var p_idx := int(_focus_id.trim_prefix("preset:"))
		if p_idx >= 0 and p_idx < allowed_compounds.size():
			apply_compound_to_mounted_all(str(allowed_compounds[p_idx]))
			return
	elif _focus_id.begins_with("count:"):
		carried_spares_count = int(_focus_id.trim_prefix("count:"))
		_reconcile_pool()
	elif _focus_id.begins_with("spare:"):
		_cycle_compound(spare_compounds, int(_focus_id.trim_prefix("spare:")))
	elif _focus_id.begins_with("stock:"):
		_cycle_compound(service_extra_compounds, int(_focus_id.trim_prefix("stock:")))
	elif _focus_id == "back":
		set_step(0)
		return
	elif _focus_id == "next":
		set_step(1)
		return
	elif _focus_id == "reset":
		_init_data()
	elif _focus_id == "confirm":
		_on_confirm()
	_sync_all()


func _advance_or_confirm() -> void:
	if step == 0:
		set_step(1)
	else:
		_on_confirm()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		match ke.keycode:
			KEY_LEFT, KEY_A:
				_move_focus(-1, 0)
				get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_D:
				_move_focus(1, 0)
				get_viewport().set_input_as_handled()
			KEY_UP, KEY_W:
				_move_focus(0, -1)
				get_viewport().set_input_as_handled()
			KEY_DOWN, KEY_S:
				_move_focus(0, 1)
				get_viewport().set_input_as_handled()
			KEY_TAB:
				_move_focus(-1 if ke.shift_pressed else 1, 0)
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate_focused()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if step == 1:
					set_step(0)
					get_viewport().set_input_as_handled()
			KEY_R:
				_init_data()
				get_viewport().set_input_as_handled()
			KEY_F5:
				_advance_or_confirm()
				get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		var jb := event as InputEventJoypadButton
		match jb.button_index:
			JOY_BUTTON_DPAD_LEFT:
				_move_focus(-1, 0)
				get_viewport().set_input_as_handled()
			JOY_BUTTON_DPAD_RIGHT:
				_move_focus(1, 0)
				get_viewport().set_input_as_handled()
			JOY_BUTTON_DPAD_UP:
				_move_focus(0, -1)
				get_viewport().set_input_as_handled()
			JOY_BUTTON_DPAD_DOWN:
				_move_focus(0, 1)
				get_viewport().set_input_as_handled()
			JOY_BUTTON_A:
				_activate_focused()
				get_viewport().set_input_as_handled()
			JOY_BUTTON_B:
				if step == 1:
					set_step(0)
					get_viewport().set_input_as_handled()
			JOY_BUTTON_X:
				_init_data()
				get_viewport().set_input_as_handled()
			JOY_BUTTON_Y:
				_advance_or_confirm()
				get_viewport().set_input_as_handled()


func _pool_array_for(slot_kind: String) -> Array:
	match slot_kind:
		"mounted":
			return mounted_compounds
		"spare":
			return spare_compounds
		"stock":
			return service_extra_compounds
	return []


func _set_spare_count(next_count: int) -> void:
	carried_spares_count = clampi(next_count, 0, 2)
	_focus_id = "count:%d" % carried_spares_count
	_reconcile_pool()


func _cycle_slot(slot_kind: String, slot_index: int) -> void:
	var arr := _pool_array_for(slot_kind)
	if not arr.is_empty():
		_cycle_compound(arr, slot_index)
		_sync_all()


func apply_compound_to_slot(slot_kind: String, slot_index: int, cid: String) -> bool:
	if not allowed_compounds.has(cid):
		return false
	var arr := _pool_array_for(slot_kind)
	if slot_index < 0 or slot_index >= arr.size():
		return false
	if slot_kind == "spare" and slot_index >= carried_spares_count:
		return false
	arr[slot_index] = cid
	_sync_all()
	return true


func apply_compound_to_mounted_all(cid: String) -> bool:
	if not allowed_compounds.has(cid):
		return false
	for i in mounted_compounds.size():
		mounted_compounds[i] = cid
	_sync_all()
	if _board_3d != null and is_instance_valid(_board_3d):
		_board_3d.play_mounted_settle_all()
	return true


func apply_compound_to_stock_all(cid: String) -> bool:
	if not allowed_compounds.has(cid):
		return false
	for i in _stock_count():
		if i < service_extra_compounds.size():
			service_extra_compounds[i] = cid
	_sync_all()
	return true


func unload_spare_to_stock(spare_index: int) -> bool:
	if spare_index < 0 or spare_index >= carried_spares_count or spare_index >= spare_compounds.size():
		return false
	var moved_cid := str(spare_compounds[spare_index])
	spare_compounds.remove_at(spare_index)
	carried_spares_count = maxi(0, carried_spares_count - 1)
	service_extra_compounds.append(moved_cid)
	_focus_id = "count:%d" % carried_spares_count
	_reconcile_pool()
	return true


func load_stock_to_spare(stock_index: int) -> bool:
	if carried_spares_count >= 2 or stock_index < 0 or stock_index >= service_extra_compounds.size():
		return false
	var moved_cid := str(service_extra_compounds[stock_index])
	service_extra_compounds.remove_at(stock_index)
	carried_spares_count += 1
	spare_compounds.append(moved_cid)
	_focus_id = "spare:%d" % maxi(0, spare_compounds.size() - 1)
	_reconcile_pool()
	return true


func swap_pool_slots(src_kind: String, src_index: int, dst_kind: String, dst_index: int) -> bool:
	if src_kind == dst_kind and src_index == dst_index:
		return false
	var src_arr := _pool_array_for(src_kind)
	var dst_arr := _pool_array_for(dst_kind)
	if src_index < 0 or src_index >= src_arr.size() or dst_index < 0 or dst_index >= dst_arr.size():
		return false
	if (src_kind == "spare" and src_index >= carried_spares_count) or (dst_kind == "spare" and dst_index >= carried_spares_count):
		return false
	var tmp: String = str(src_arr[src_index])
	src_arr[src_index] = str(dst_arr[dst_index])
	dst_arr[dst_index] = tmp
	_sync_all()
	return true


func _cycle_compound(arr: Array, idx: int) -> void:
	if allowed_compounds.is_empty() or idx < 0 or idx >= arr.size():
		return
	var cur := str(arr[idx])
	var next_idx := (allowed_compounds.find(cur) + 1) % allowed_compounds.size()
	arr[idx] = allowed_compounds[next_idx]


func _reconcile_pool() -> void:
	var def_cid: String = str(allowed_compounds[0]) if not allowed_compounds.is_empty() else "gravel_normal"
	while spare_compounds.size() > carried_spares_count:
		service_extra_compounds.append(str(spare_compounds.pop_back()))
	while spare_compounds.size() < carried_spares_count:
		if not service_extra_compounds.is_empty():
			spare_compounds.append(str(service_extra_compounds.pop_back()))
		else:
			spare_compounds.append(def_cid)
	var want_stock := _stock_count()
	while service_extra_compounds.size() > want_stock:
		service_extra_compounds.pop_back()
	while service_extra_compounds.size() < want_stock:
		service_extra_compounds.append(def_cid)
	_sync_all()


func _on_confirm() -> void:
	_reconcile_pool()
	var mounted_out: Array = mounted_compounds.duplicate()
	var spares_out: Array = []
	for i in carried_spares_count:
		spares_out.append(str(spare_compounds[i]) if i < spare_compounds.size() else str(allowed_compounds[0]))
	var service_out: Array = []
	for i in _stock_count():
		service_out.append(str(service_extra_compounds[i]) if i < service_extra_compounds.size() else str(allowed_compounds[0]))
	if mounted_out.size() + spares_out.size() + service_out.size() != POOL_SIZE:
		return
	strategy_confirmed.emit({
		"mounted_compounds": mounted_out,
		"spares_compounds": spares_out,
		"service_compounds": service_out,
		"carried_spares_count": carried_spares_count
	})
