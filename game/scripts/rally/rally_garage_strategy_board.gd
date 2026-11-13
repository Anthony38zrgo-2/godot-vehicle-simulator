class_name RallyGarageStrategyBoard
extends Control
## Tablero 3D interactivo para la pestaña Estrategia de RallyGaragePanel.
## Reutiliza RallyTire3DView y RallyHeldPartPreview permitiendo arrastrar y soltar
## neumáticos 3D entre el coche (FL/FR/RL/RR), maletero y parque de asistencia.

const Tire3DViewScript := preload("res://scripts/rally/rally_tire_3d_view.gd")

const RECT_CAR := Rect2(848.0, 198.0, 196.0, 444.0)
const MOUNTED_RECTS: Array[Rect2] = [
	Rect2(662.0, 194.0, 180.0, 218.0),
	Rect2(1050.0, 194.0, 180.0, 218.0),
	Rect2(662.0, 432.0, 180.0, 218.0),
	Rect2(1050.0, 432.0, 180.0, 218.0),
]
const SPARE_RECTS: Array[Rect2] = [
	Rect2(50.0, 372.0, 280.0, 92.0),
	Rect2(338.0, 372.0, 280.0, 92.0),
]
const STOCK_ZONE_RECT := Rect2(44.0, 470.0, 580.0, 196.0)
const FONT_TITLE: Font = RallyUITheme.FONT_TITLE
const FONT_BODY: Font = RallyUITheme.FONT_DATA
const FONT_NUM: Font = RallyUITheme.FONT_DATA_BOLD

var garage: Control = null
var _built_for_vehicle: Node3D = null
var _car_view: SubViewportContainer = null
var _mounted_slots: Array[GarageTireSlot3D] = []
var _spare_slots: Array[GarageTireSlot3D] = []
var _stock_slots: Array[GarageTireSlot3D] = []
var _stock_drop_zone: ParqueUnloadDropZone = null
var _active_drag_tire_id: int = -1
var _active_drag_src_kind: String = ""
var _active_drag_src_index: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_SizeAndScale(Vector2(1280.0, 800.0))


func set_SizeAndScale(logical_size: Vector2) -> void:
	size = logical_size
	custom_minimum_size = logical_size


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var payload: Variant = get_viewport().gui_get_drag_data()
		if payload is Dictionary and str((payload as Dictionary).get("drag_type", "")) == "garage_pool_tire":
			_active_drag_tire_id = int((payload as Dictionary).get("tire_id", -1))
			_active_drag_src_kind = str((payload as Dictionary).get("slot_kind", ""))
			_active_drag_src_index = int((payload as Dictionary).get("slot_index", -1))
			_refresh_all_highlights()
			if is_instance_valid(garage):
				garage.queue_redraw()
	elif what == NOTIFICATION_DRAG_END:
		if _active_drag_tire_id != -1:
			_active_drag_tire_id = -1
			_active_drag_src_kind = ""
			_active_drag_src_index = -1
			_refresh_all_highlights()
			if is_instance_valid(garage):
				garage.queue_redraw()


func _exit_tree() -> void:
	clear_board()


func clear_board() -> void:
	_active_drag_tire_id = -1
	_active_drag_src_kind = ""
	_active_drag_src_index = -1
	_built_for_vehicle = null
	_car_view = null
	_stock_drop_zone = null
	_mounted_slots.clear()
	_spare_slots.clear()
	_stock_slots.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()


func sync_from_garage() -> void:
	if not is_instance_valid(garage):
		clear_board()
		return
	var vehicle: Node3D = garage.get("vehicle") as Node3D
	if not is_instance_valid(vehicle) or not bool(garage.call("_is_pool_mode")):
		clear_board()
		return
	if _car_view == null or _built_for_vehicle != vehicle or _mounted_slots.size() != 4:
		_build_slots(vehicle)

	var spare_cap := clampi(int(garage.call("_tire_capacity")), 0, 2)
	var stock_ids: Array = garage.get("draft_stock_ids")
	var mounted_ids: Array = garage.get("draft_mounted_ids")
	var spare_ids: Array = garage.get("draft_spare_ids")

	for i in 4:
		var tid := int(mounted_ids[i]) if i < mounted_ids.size() else -1
		_mounted_slots[i].update_slot(tid, i)
	for s in _spare_slots.size():
		var slot := _spare_slots[s]
		slot.visible = s < spare_cap
		var tid := int(spare_ids[s]) if s < spare_ids.size() else -1
		slot.update_slot(tid, 0)
	for k in _stock_slots.size():
		var slot := _stock_slots[k]
		if k < stock_ids.size():
			slot.visible = true
			slot.update_slot(int(stock_ids[k]), 0)
		else:
			slot.visible = false
			slot.update_slot(-1, 0)
	_refresh_all_highlights()


func has_pointer_control(global_point: Vector2) -> bool:
	if not visible:
		return false
	for slot in _all_slots():
		if not is_instance_valid(slot) or not slot.visible:
			continue
		if slot.get_global_rect().has_point(global_point):
			return true
		if slot.unload_btn != null and slot.unload_btn.visible and slot.unload_btn.get_global_rect().has_point(global_point):
			return true
	return false


func play_settle(slot_kind: String, slot_index: int) -> void:
	var slot: GarageTireSlot3D = _slot_for(slot_kind, slot_index)
	if slot != null and is_instance_valid(slot) and slot.wheel_view != null:
		Tire3DViewScript.play_settle_animation(self, slot.wheel_view, slot.base_model_rotation)


func _build_slots(vehicle: Node3D) -> void:
	clear_board()
	_built_for_vehicle = vehicle

	_car_view = Tire3DViewScript.create_vehicle_top_view(vehicle, RECT_CAR.size, true, [], SubViewport.UPDATE_ONCE)
	_car_view.position = RECT_CAR.position
	_car_view.size = RECT_CAR.size
	add_child(_car_view)

	_stock_drop_zone = ParqueUnloadDropZone.new()
	_stock_drop_zone.board = self
	_stock_drop_zone.position = STOCK_ZONE_RECT.position
	_stock_drop_zone.size = STOCK_ZONE_RECT.size
	add_child(_stock_drop_zone)

	for i in 4:
		var m_slot := GarageTireSlot3D.new()
		m_slot.setup(self, "mounted", i, MOUNTED_RECTS[i], Vector3(0.14, 0.0, 0.0))
		add_child(m_slot)
		_mounted_slots.append(m_slot)

	for s in 2:
		var sp_slot := GarageTireSlot3D.new()
		sp_slot.setup(self, "spare", s, SPARE_RECTS[s], Vector3(0.24, 0.34, -0.10))
		add_child(sp_slot)
		_spare_slots.append(sp_slot)

	for k in 6:
		var col := k % 3
		var row := k / 3
		var rect := Rect2(50.0 + float(col) * 192.0, 474.0 + float(row) * 96.0, 184.0, 88.0)
		var st_slot := GarageTireSlot3D.new()
		st_slot.setup(self, "stock", k, rect, Vector3(0.26, 0.36, -0.10))
		add_child(st_slot)
		_stock_slots.append(st_slot)


func _slot_for(slot_kind: String, slot_index: int) -> GarageTireSlot3D:
	match slot_kind:
		"mounted":
			return _mounted_slots[slot_index] if (slot_index >= 0 and slot_index < _mounted_slots.size()) else null
		"spare":
			return _spare_slots[slot_index] if (slot_index >= 0 and slot_index < _spare_slots.size()) else null
		"stock":
			return _stock_slots[slot_index] if (slot_index >= 0 and slot_index < _stock_slots.size()) else null
	return null


func _all_slots() -> Array[GarageTireSlot3D]:
	var all: Array[GarageTireSlot3D] = []
	all.append_array(_mounted_slots)
	all.append_array(_spare_slots)
	all.append_array(_stock_slots)
	return all


func _refresh_all_highlights() -> void:
	for slot in _all_slots():
		if is_instance_valid(slot) and slot.visible:
			slot.refresh_visual_style()
	if _stock_drop_zone != null and is_instance_valid(_stock_drop_zone):
		_stock_drop_zone.queue_redraw()


func _make_drag_preview(wheel_idx: int, tire_data: Dictionary) -> Control:
	var vehicle: Node3D = garage.get("vehicle") as Node3D
	return Tire3DViewScript.create_drag_preview(vehicle, wheel_idx, tire_data, Vector2(118.0, 118.0))


class ParqueUnloadDropZone extends Control:
	var board: RallyGarageStrategyBoard

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if not (data is Dictionary) or board == null or not is_instance_valid(board.garage):
			return false
		var g := board.garage
		if not bool(g.call("_is_pool_mode")) or not bool(g.call("_may_service_tires")) or not bool(g.get("compound_change_allowed")):
			return false
		var d: Dictionary = data
		return str(d.get("drag_type", "")) == "garage_pool_tire" and str(d.get("slot_kind", "")) == "spare"

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if not (data is Dictionary) or board == null or not is_instance_valid(board.garage):
			return
		var src_idx := int((data as Dictionary).get("slot_index", -1))
		board.garage.call("_unload_spare_slot", src_idx)

	func _draw() -> void:
		if board == null or board._active_drag_src_kind != "spare":
			return
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color("#22c55e", 0.08))
		draw_rect(r, Color("#22c55e", 0.65), false, 2.0)


class GarageTireSlot3D extends Control:
	var board: RallyGarageStrategyBoard
	var slot_kind: String = ""
	var slot_index: int = -1
	var tire_id: int = -1
	var base_model_rotation: Vector3 = Vector3.ZERO

	var panel_bg: Panel
	var wheel_view: SubViewportContainer
	var title_lbl: Label
	var compound_lbl: Label
	var status_lbl: Label
	var sub_lbl: Label
	var life_bar: ProgressBar
	var unload_btn: Button

	var _hovered: bool = false
	var _pressed_inside: bool = false
	var _rendered_signature: String = ""

	func setup(parent_board: RallyGarageStrategyBoard, kind: String, idx: int, rect: Rect2, model_rot: Vector3) -> void:
		board = parent_board
		slot_kind = kind
		slot_index = idx
		base_model_rotation = model_rot
		position = rect.position
		size = rect.size
		custom_minimum_size = rect.size
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		_build_children()
		mouse_entered.connect(func():
			_hovered = true
			refresh_visual_style()
		)
		mouse_exited.connect(func():
			_hovered = false
			_pressed_inside = false
			refresh_visual_style()
		)

	func _build_children() -> void:
		panel_bg = Panel.new()
		panel_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel_bg)

		var g := board.garage
		var vehicle: Node3D = g.get("vehicle") as Node3D if is_instance_valid(g) else null
		var wheel_dim := Vector2(88.0, 88.0) if slot_kind == "mounted" else (Vector2(68.0, 68.0) if slot_kind == "spare" else Vector2(62.0, 62.0))
		wheel_view = Tire3DViewScript.create_wheel_view(
			vehicle,
			slot_index if slot_kind == "mounted" else 0,
			{},
			wheel_dim,
			base_model_rotation,
			true,
			SubViewport.UPDATE_ONCE
		)
		if slot_kind == "mounted":
			wheel_view.position = Vector2((size.x - wheel_dim.x) * 0.5, 34.0)
		else:
			wheel_view.position = Vector2(6.0, (size.y - wheel_dim.y) * 0.5)
		add_child(wheel_view)

		title_lbl = Label.new()
		title_lbl.add_theme_font_override("font", FONT_TITLE)
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(title_lbl)

		compound_lbl = Label.new()
		compound_lbl.add_theme_font_override("font", FONT_NUM)
		compound_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(compound_lbl)

		status_lbl = Label.new()
		status_lbl.add_theme_font_override("font", FONT_NUM)
		status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(status_lbl)

		sub_lbl = Label.new()
		sub_lbl.add_theme_font_override("font", FONT_BODY)
		sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sub_lbl)

		life_bar = ProgressBar.new()
		life_bar.show_percentage = false
		life_bar.min_value = 0.0
		life_bar.max_value = 100.0
		life_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(life_bar)

		if slot_kind == "mounted":
			title_lbl.position = Vector2(10.0, 7.0)
			title_lbl.size = Vector2(92.0, 20.0)
			title_lbl.add_theme_font_size_override("font_size", 13)

			status_lbl.position = Vector2(90.0, 8.0)
			status_lbl.size = Vector2(size.x - 100.0, 18.0)
			status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			status_lbl.add_theme_font_size_override("font_size", 10)

			compound_lbl.position = Vector2(10.0, 132.0)
			compound_lbl.size = Vector2(size.x - 20.0, 18.0)
			compound_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			compound_lbl.add_theme_font_size_override("font_size", 11)

			sub_lbl.position = Vector2(10.0, 152.0)
			sub_lbl.size = Vector2(size.x - 20.0, 32.0)
			sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sub_lbl.add_theme_font_size_override("font_size", 11)

			life_bar.position = Vector2(12.0, size.y - 16.0)
			life_bar.size = Vector2(size.x - 24.0, 6.0)
		elif slot_kind == "spare":
			title_lbl.position = Vector2(78.0, 8.0)
			title_lbl.size = Vector2(138.0, 20.0)
			title_lbl.add_theme_font_size_override("font_size", 12)

			compound_lbl.position = Vector2(78.0, 30.0)
			compound_lbl.size = Vector2(130.0, 18.0)
			compound_lbl.add_theme_font_size_override("font_size", 11)

			sub_lbl.position = Vector2(78.0, 50.0)
			sub_lbl.size = Vector2(140.0, 18.0)
			sub_lbl.add_theme_font_size_override("font_size", 11)

			status_lbl.position = Vector2(size.x - 84.0, 8.0)
			status_lbl.size = Vector2(74.0, 18.0)
			status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			status_lbl.add_theme_font_size_override("font_size", 10)

			life_bar.position = Vector2(78.0, size.y - 14.0)
			life_bar.size = Vector2(size.x - 146.0, 5.0)

			unload_btn = Button.new()
			unload_btn.text = "SACAR"
			unload_btn.position = Vector2(size.x - 62.0, size.y - 34.0)
			unload_btn.size = Vector2(54.0, 24.0)
			unload_btn.focus_mode = Control.FOCUS_NONE
			RallyUITheme.style_tone_button(unload_btn, "chrome", 10, 8, 3, RallyUITheme.CORNER_RADIUS, FONT_NUM)
			unload_btn.pressed.connect(func():
				if board != null and is_instance_valid(board.garage):
					board.garage.call("_unload_spare_slot", slot_index)
			)
			add_child(unload_btn)
		else:
			title_lbl.position = Vector2(70.0, 7.0)
			title_lbl.size = Vector2(60.0, 18.0)
			title_lbl.add_theme_font_size_override("font_size", 12)

			status_lbl.position = Vector2(118.0, 8.0)
			status_lbl.size = Vector2(size.x - 126.0, 16.0)
			status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			status_lbl.add_theme_font_size_override("font_size", 9)

			compound_lbl.position = Vector2(70.0, 28.0)
			compound_lbl.size = Vector2(size.x - 78.0, 18.0)
			compound_lbl.add_theme_font_size_override("font_size", 11)

			sub_lbl.position = Vector2(70.0, 48.0)
			sub_lbl.size = Vector2(size.x - 78.0, 18.0)
			sub_lbl.add_theme_font_size_override("font_size", 10)

			life_bar.position = Vector2(70.0, size.y - 12.0)
			life_bar.size = Vector2(size.x - 78.0, 5.0)

	func update_slot(next_tire_id: int, wheel_idx_hint: int) -> void:
		tire_id = next_tire_id
		var g := board.garage
		var vehicle: Node3D = g.get("vehicle") as Node3D if is_instance_valid(g) else null
		var inv: RallyTireInventory = vehicle.get("tire_inventory") as RallyTireInventory if is_instance_valid(vehicle) else null
		var td := inv.find_tire(tire_id) if (inv != null and tire_id > 0) else {}

		if unload_btn != null:
			var can_service := bool(g.get("compound_change_allowed")) and bool(g.call("_may_service_tires")) if is_instance_valid(g) else false
			unload_btn.visible = not td.is_empty() and can_service

		if td.is_empty():
			wheel_view.visible = false
			life_bar.visible = false
			title_lbl.text = "LIBRE #%d" % (slot_index + 1)
			compound_lbl.text = "MALETERO VACÍO"
			compound_lbl.add_theme_color_override("font_color", RallyUITheme.TEXT_MUTED)
			sub_lbl.text = "Arrastra rueda del parque"
			sub_lbl.add_theme_color_override("font_color", RallyUITheme.TEXT_DIM)
			status_lbl.text = "LIBRE"
			status_lbl.add_theme_color_override("font_color", RallyUITheme.TEXT_DIM)
			_rendered_signature = "empty"
			refresh_visual_style()
			return

		wheel_view.visible = true
		life_bar.visible = true
		var st: Dictionary = td.get("state", {})
		var cid := str(td.get("compound_id", RallyTireCompound.DEFAULT_ID))
		var wear := clampf(float(st.get("wear_fraction", 0.0)), 0.0, 1.0)
		var life_pct := maxf(0.0, (1.0 - wear) * 100.0)
		var leak := float(st.get("leak_per_second", 0.0)) > 0.0
		var rim := float(st.get("rim_deformation", 0.0)) > 0.005
		var dead := float(st.get("carcass_failure", 0.0)) >= 0.99
		var sig := "%d:%s:%d:%.2f:%s:%s:%s" % [tire_id, cid, wheel_idx_hint, snappedf(wear, 0.05), leak, rim, dead]
		if sig != _rendered_signature and is_instance_valid(vehicle):
			_rendered_signature = sig
			var pivot := Tire3DViewScript.get_pivot(wheel_view)
			Tire3DViewScript.populate_wheel_pivot(pivot, vehicle, wheel_idx_hint, td, true)
			Tire3DViewScript.refresh_viewport(wheel_view)

		var codes := ["FL", "FR", "RL", "RR"]
		if slot_kind == "mounted":
			title_lbl.text = "#%d · %s" % [tire_id, codes[clampi(slot_index, 0, 3)]]
			var pressure := float(g.call("_wheel_pressure", slot_index))
			var temp_c := float(g.call("_wheel_temperature", slot_index))
			sub_lbl.text = "%.0f kPa · %.0f °C\nVIDA %.0f%%" % [pressure, temp_c, life_pct]
		else:
			title_lbl.text = "#%d" % tire_id
			sub_lbl.text = "VIDA %.0f%% · DESG. %.0f%%" % [life_pct, wear * 100.0]

		var short_lbl := str(g.call("_compound_label", cid, true)) if is_instance_valid(g) else cid.to_upper()
		compound_lbl.text = short_lbl
		compound_lbl.add_theme_color_override("font_color", Tire3DViewScript.compound_ring_color(cid, false))
		sub_lbl.add_theme_color_override("font_color", RallyUITheme.TEXT_MUTED)

		var st_info: Dictionary = g.call("_tire_status_info", inv, td) if inv != null else {"tag": "OK", "color": RallyUITheme.TEXT_MUTED}
		status_lbl.text = str(st_info.get("tag", "OK"))
		status_lbl.add_theme_color_override("font_color", st_info.get("color", RallyUITheme.TEXT_MUTED))

		life_bar.value = life_pct
		var bar_col := RallyUITheme.STATUS_DANGER if (dead or leak or life_pct < 35.0) else (RallyUITheme.ACCENT_RALLY if (rim or life_pct < 70.0) else RallyUITheme.STATUS_SUCCESS)
		var fill_box := RallyUITheme.make_flat_panel(bar_col, Color(0, 0, 0, 0), 0, 1)
		var bg_box := RallyUITheme.make_flat_panel(RallyUITheme.BG_WELL, Color(0, 0, 0, 0), 0, 1)
		life_bar.add_theme_stylebox_override("fill", fill_box)
		life_bar.add_theme_stylebox_override("background", bg_box)

		refresh_visual_style()

	func refresh_visual_style() -> void:
		if panel_bg == null or board == null or not is_instance_valid(board.garage):
			return
		var g := board.garage
		var sel_id := int(g.get("selected_pool_tire_id"))
		var focus_path := str(g.get("selected_field_path"))
		var my_path := "%s:%d" % [slot_kind, slot_index]
		var is_selected := sel_id > 0 and tire_id == sel_id
		var is_focused := focus_path == my_path

		var sb := RallyUITheme.make_flat_panel(
			RallyUITheme.BG_HOVER if (_hovered or is_selected) else RallyUITheme.BG_CARD,
			RallyUITheme.BORDER_CARD,
			1,
			RallyUITheme.CORNER_RADIUS
		)

		var drag_id := board._active_drag_tire_id
		if drag_id > 0:
			if drag_id == tire_id:
				sb.bg_color = Color("#2a2010")
				sb.border_color = RallyUITheme.ACCENT_RALLY
				sb.set_border_width_all(2)
			else:
				var check_res: Dictionary = g.call("can_pool_drop_from_id", drag_id, slot_kind, slot_index)
				if bool(check_res.get("ok", false)):
					sb.bg_color = Color("#193627") if _hovered else Color("#13281d")
					sb.border_color = RallyUITheme.STATUS_SUCCESS
					sb.set_border_width_all(2)
				else:
					sb.bg_color = Color("#241216")
					sb.border_color = Color(RallyUITheme.STATUS_DANGER, 0.55)
					sb.set_border_width_all(1)
		elif is_selected:
			sb.bg_color = Color("#2a2010")
			sb.border_color = RallyUITheme.ACCENT_RALLY
			sb.set_border_width_all(2)
		elif is_focused:
			sb.border_color = RallyUITheme.BORDER_FOCUS
			sb.set_border_width_all(2)
		elif _hovered:
			sb.border_color = RallyUITheme.BORDER_HOVER

		panel_bg.add_theme_stylebox_override("panel", sb)

	func _gui_input(event: InputEvent) -> void:
		if not visible or board == null or not is_instance_valid(board.garage):
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index != MOUSE_BUTTON_LEFT:
				return
			if mb.pressed:
				_pressed_inside = true
				accept_event()
			elif _pressed_inside:
				_pressed_inside = false
				if not get_viewport().gui_is_dragging() and Rect2(Vector2.ZERO, size).has_point(mb.position):
					board.garage.set("selected_field_path", "%s:%d" % [slot_kind, slot_index])
					board.garage.call("_pool_interact", slot_kind, slot_index)
				accept_event()

	func _get_drag_data(_pos: Vector2) -> Variant:
		if tire_id <= 0 or board == null or not is_instance_valid(board.garage):
			return null
		var g := board.garage
		if not bool(g.call("_is_pool_mode")) or not bool(g.call("_may_service_tires")) or not bool(g.get("compound_change_allowed")):
			return null
		var vehicle: Node3D = g.get("vehicle") as Node3D
		var inv: RallyTireInventory = vehicle.get("tire_inventory") as RallyTireInventory if is_instance_valid(vehicle) else null
		if inv == null:
			return null
		var td := inv.find_tire(tire_id)
		if td.is_empty():
			return null
		_pressed_inside = false
		var preview := board._make_drag_preview(slot_index if slot_kind == "mounted" else 0, td)
		set_drag_preview(preview)
		return {
			"drag_type": "garage_pool_tire",
			"tire_id": tire_id,
			"slot_kind": slot_kind,
			"slot_index": slot_index,
		}

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if not (data is Dictionary) or board == null or not is_instance_valid(board.garage):
			return false
		var d: Dictionary = data
		if str(d.get("drag_type", "")) != "garage_pool_tire":
			return false
		var src_id := int(d.get("tire_id", -1))
		var res: Dictionary = board.garage.call("can_pool_drop_from_id", src_id, slot_kind, slot_index)
		return bool(res.get("ok", false))

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if not (data is Dictionary) or board == null or not is_instance_valid(board.garage):
			return
		var d: Dictionary = data
		if str(d.get("drag_type", "")) != "garage_pool_tire":
			return
		var src_id := int(d.get("tire_id", -1))
		var src_kind := str(d.get("slot_kind", ""))
		var src_idx := int(d.get("slot_index", -1))
		board.garage.set("selected_field_path", "%s:%d" % [slot_kind, slot_index])
		if bool(board.garage.call("perform_pool_drop", src_id, slot_kind, slot_index)):
			board.play_settle(slot_kind, slot_index)
			if src_kind != "" and src_idx >= 0:
				board.play_settle(src_kind, src_idx)
			if not src_kind.is_empty() and src_idx >= 0:
				board.play_settle(src_kind, src_idx)
