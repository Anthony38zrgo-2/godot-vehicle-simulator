class_name RallyStrategyScreen3DBoard
extends Control
## Tablero 3D interactivo en 2 pasos para la estrategia previa de neumáticos:
## Paso 1/2: Clima + selector de compuestos + montaje 3D del coche (4 ruedas).
## Paso 2/2: Maletero (peso extra) + inventario de reserva móvil mediante arrastrar y soltar.

const Tire3DViewScript := preload("res://scripts/rally/rally_tire_3d_view.gd")

const RECT_CAR_STEP1 := Rect2(832.0, 166.0, 188.0, 484.0)
const MOUNTED_STEP1_RECTS: Array[Rect2] = [
	Rect2(640.0, 166.0, 184.0, 230.0),
	Rect2(1026.0, 166.0, 184.0, 230.0),
	Rect2(640.0, 420.0, 184.0, 230.0),
	Rect2(1026.0, 420.0, 184.0, 230.0),
]
const PALETTE_STEP1_BOUNDS := Rect2(74.0, 434.0, 516.0, 126.0)

const PALETTE_STEP2_BOUNDS := Rect2(70.0, 142.0, 524.0, 62.0)
const SPARE_STEP2_RECTS: Array[Rect2] = [
	Rect2(70.0, 316.0, 524.0, 164.0),
	Rect2(70.0, 492.0, 524.0, 164.0),
]
const RESERVA_DROP_ZONE_RECT := Rect2(634.0, 276.0, 580.0, 386.0)

const FONT_TITLE: Font = RallyUITheme.FONT_TITLE
const FONT_BODY: Font = RallyUITheme.FONT_DATA
const FONT_NUM: Font = RallyUITheme.FONT_DATA_BOLD

var screen: Control = null
var _built_for_vehicle: Node3D = null
var _built_with_vehicle: bool = false
var _built_allowed_sig: String = ""

var _car_view: SubViewportContainer = null
var _chassis_drop_zone: BulkDropZone = null
var _reserva_drop_zone: BulkDropZone = null
var _palette_step1_cards: Array[CompoundBrushCard3D] = []
var _palette_step2_cards: Array[CompoundBrushCard3D] = []
var _mounted_slots: Array[StrategySlot3D] = []
var _spare_slots: Array[StrategySlot3D] = []
var _stock_slots: Array[StrategySlot3D] = []

var _drag_type: String = ""
var _drag_compound_id: String = ""
var _drag_src_kind: String = ""
var _drag_src_index: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_logical_size(Vector2(1280.0, 800.0))


func set_logical_size(logical_size: Vector2) -> void:
	size = logical_size
	custom_minimum_size = logical_size


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var payload: Variant = get_viewport().gui_get_drag_data()
		if payload is Dictionary:
			var d: Dictionary = payload
			var dt := str(d.get("drag_type", ""))
			if dt in ["strategy_pool_slot", "strategy_compound_brush"]:
				_drag_type = dt
				_drag_compound_id = str(d.get("compound_id", ""))
				_drag_src_kind = str(d.get("slot_kind", "palette"))
				_drag_src_index = int(d.get("slot_index", -1))
				_refresh_highlights()
				if is_instance_valid(screen):
					screen.queue_redraw()
	elif what == NOTIFICATION_DRAG_END:
		if _drag_type != "":
			_drag_type = ""
			_drag_compound_id = ""
			_drag_src_kind = ""
			_drag_src_index = -1
			_refresh_highlights()
			if is_instance_valid(screen):
				screen.queue_redraw()


func _exit_tree() -> void:
	clear_board()


func clear_board() -> void:
	_drag_type = ""
	_drag_compound_id = ""
	_drag_src_kind = ""
	_drag_src_index = -1
	_built_for_vehicle = null
	_built_with_vehicle = false
	_built_allowed_sig = ""
	_car_view = null
	_chassis_drop_zone = null
	_reserva_drop_zone = null
	_palette_step1_cards.clear()
	_palette_step2_cards.clear()
	_mounted_slots.clear()
	_spare_slots.clear()
	_stock_slots.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()


func sync_from_screen() -> void:
	if not is_instance_valid(screen):
		clear_board()
		return
	var vehicle: Node3D = screen.get("vehicle") as Node3D
	var has_vehicle := is_instance_valid(vehicle)
	var allowed: Array = screen.get("allowed_compounds")
	var allowed_parts := PackedStringArray()
	for a in allowed:
		allowed_parts.append(str(a))
	var allowed_sig := ",".join(allowed_parts)
	if (
		_mounted_slots.size() != 4
		or _built_for_vehicle != vehicle
		or _built_with_vehicle != has_vehicle
		or _built_allowed_sig != allowed_sig
	):
		_build_board(vehicle, has_vehicle, allowed, allowed_sig)

	var current_step := int(screen.get("step"))
	var step1 := current_step == 0
	var step2 := current_step == 1

	var mounted: Array = screen.get("mounted_compounds")
	var spares: Array = screen.get("spare_compounds")
	var stock: Array = screen.get("service_extra_compounds")
	var spare_cap := clampi(int(screen.get("carried_spares_count")), 0, 2)
	var stock_cap := maxi(0, 6 - spare_cap)

	if is_instance_valid(_car_view):
		_car_view.visible = step1
	if is_instance_valid(_chassis_drop_zone):
		_chassis_drop_zone.visible = step1
	for card in _palette_step1_cards:
		card.visible = step1
		if step1:
			card.refresh_visual_style()
	for i in 4:
		_mounted_slots[i].visible = step1
		if step1:
			var cid := str(mounted[i]) if i < mounted.size() else ""
			_mounted_slots[i].update_slot(cid, true, i)

	if is_instance_valid(_reserva_drop_zone):
		_reserva_drop_zone.visible = step2
		if step2:
			_reserva_drop_zone.queue_redraw()
	for card in _palette_step2_cards:
		card.visible = step2
		if step2:
			card.refresh_visual_style()
	for s in _spare_slots.size():
		_spare_slots[s].visible = step2
		if step2:
			var active := s < spare_cap
			var cid := str(spares[s]) if (active and s < spares.size()) else ""
			_spare_slots[s].update_slot(cid, active, 0)
	for k in _stock_slots.size():
		var visible_slot := step2 and k < stock_cap and k < stock.size()
		_stock_slots[k].visible = visible_slot
		if visible_slot:
			_stock_slots[k].update_slot(str(stock[k]), true, 0)

	_refresh_highlights()


func play_settle(slot_kind: String, slot_index: int) -> void:
	var slot := _slot_for(slot_kind, slot_index)
	if slot != null and is_instance_valid(slot) and slot.wheel_view != null:
		Tire3DViewScript.play_settle_animation(self, slot.wheel_view, slot.base_model_rotation)


func play_mounted_settle_all() -> void:
	for i in _mounted_slots.size():
		play_settle("mounted", i)


func play_stock_settle_all() -> void:
	for slot in _stock_slots:
		if is_instance_valid(slot) and slot.visible and slot.wheel_view != null:
			Tire3DViewScript.play_settle_animation(self, slot.wheel_view, slot.base_model_rotation)


func _build_board(vehicle: Node3D, has_vehicle: bool, allowed: Array, allowed_sig: String) -> void:
	clear_board()
	_built_for_vehicle = vehicle
	_built_with_vehicle = has_vehicle
	_built_allowed_sig = allowed_sig

	if has_vehicle:
		_car_view = Tire3DViewScript.create_vehicle_top_view(vehicle, RECT_CAR_STEP1.size, true, [], SubViewport.UPDATE_ONCE)
		_car_view.position = RECT_CAR_STEP1.position
		_car_view.size = RECT_CAR_STEP1.size
		add_child(_car_view)

	_chassis_drop_zone = BulkDropZone.new()
	_chassis_drop_zone.setup(self, "mounted_all", RECT_CAR_STEP1)
	add_child(_chassis_drop_zone)

	_reserva_drop_zone = BulkDropZone.new()
	_reserva_drop_zone.setup(self, "reserva_zone", RESERVA_DROP_ZONE_RECT)
	add_child(_reserva_drop_zone)

	var pal_count := clampi(allowed.size(), 1, 4)
	_build_palette_strip(_palette_step1_cards, PALETTE_STEP1_BOUNDS, pal_count, allowed, vehicle if has_vehicle else null, false)
	_build_palette_strip(_palette_step2_cards, PALETTE_STEP2_BOUNDS, pal_count, allowed, vehicle if has_vehicle else null, true)

	for i in 4:
		var m_slot := StrategySlot3D.new()
		m_slot.setup(self, "mounted", i, MOUNTED_STEP1_RECTS[i], Vector3(0.14, 0.0, 0.0), vehicle if has_vehicle else null)
		add_child(m_slot)
		_mounted_slots.append(m_slot)

	for s in 2:
		var sp_slot := StrategySlot3D.new()
		sp_slot.setup(self, "spare", s, SPARE_STEP2_RECTS[s], Vector3(0.24, 0.34, -0.10), vehicle if has_vehicle else null)
		add_child(sp_slot)
		_spare_slots.append(sp_slot)

	for k in 6:
		var col := k % 2
		var row := k / 2
		var rect := Rect2(642.0 + float(col) * 288.0, 282.0 + float(row) * 130.0, 276.0, 116.0)
		var st_slot := StrategySlot3D.new()
		st_slot.setup(self, "stock", k, rect, Vector3(0.26, 0.36, -0.10), vehicle if has_vehicle else null)
		add_child(st_slot)
		_stock_slots.append(st_slot)


func _build_palette_strip(
	target_list: Array[CompoundBrushCard3D],
	bounds: Rect2,
	count: int,
	allowed: Array,
	vehicle: Node3D,
	compact: bool
) -> void:
	var gap := 10.0
	var width := floorf((bounds.size.x - gap * float(count - 1)) / float(count))
	for i in count:
		var cid := str(allowed[i])
		var rect := Rect2(
			bounds.position.x + float(i) * (width + gap),
			bounds.position.y,
			width,
			bounds.size.y
		)
		var card := CompoundBrushCard3D.new()
		card.setup(self, cid, rect, vehicle, compact)
		add_child(card)
		target_list.append(card)


func _slot_for(slot_kind: String, slot_index: int) -> StrategySlot3D:
	match slot_kind:
		"mounted":
			return _mounted_slots[slot_index] if (slot_index >= 0 and slot_index < _mounted_slots.size()) else null
		"spare":
			return _spare_slots[slot_index] if (slot_index >= 0 and slot_index < _spare_slots.size()) else null
		"stock":
			return _stock_slots[slot_index] if (slot_index >= 0 and slot_index < _stock_slots.size()) else null
	return null


func _all_slots() -> Array[StrategySlot3D]:
	var all: Array[StrategySlot3D] = []
	all.append_array(_mounted_slots)
	all.append_array(_spare_slots)
	all.append_array(_stock_slots)
	return all


func _refresh_highlights() -> void:
	for slot in _all_slots():
		if is_instance_valid(slot) and slot.visible:
			slot.refresh_visual_style()
	for card in _palette_step1_cards:
		if is_instance_valid(card) and card.visible:
			card.refresh_visual_style()
	for card in _palette_step2_cards:
		if is_instance_valid(card) and card.visible:
			card.refresh_visual_style()
	if is_instance_valid(_chassis_drop_zone) and _chassis_drop_zone.visible:
		_chassis_drop_zone.queue_redraw()
	if is_instance_valid(_reserva_drop_zone) and _reserva_drop_zone.visible:
		_reserva_drop_zone.queue_redraw()


func _compound_short_label(compound_id: String) -> String:
	if is_instance_valid(screen):
		var labels: Variant = screen.get("compound_labels")
		if labels is Dictionary and (labels as Dictionary).has(compound_id):
			return str((labels as Dictionary)[compound_id]).to_upper()
	return compound_id.to_upper()


func _make_drag_preview(wheel_idx: int, compound_id: String) -> Control:
	var vehicle: Node3D = screen.get("vehicle") as Node3D if is_instance_valid(screen) else null
	return Tire3DViewScript.create_drag_preview(vehicle, wheel_idx, {"compound_id": compound_id}, Vector2(114.0, 114.0))


class BulkDropZone extends Control:
	var board: RallyStrategyScreen3DBoard
	var mode: String = ""
	var _hovered_drag: bool = false

	func setup(parent_board: RallyStrategyScreen3DBoard, zone_mode: String, rect: Rect2) -> void:
		board = parent_board
		mode = zone_mode
		position = rect.position
		size = rect.size
		custom_minimum_size = rect.size
		mouse_filter = Control.MOUSE_FILTER_PASS
		focus_mode = Control.FOCUS_NONE
		mouse_exited.connect(_on_mouse_exited)

	func _on_mouse_exited() -> void:
		if _hovered_drag:
			_hovered_drag = false
			queue_redraw()

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if not visible or not (data is Dictionary) or board == null or not is_instance_valid(board.screen):
			_hovered_drag = false
			return false
		var d: Dictionary = data
		var dt := str(d.get("drag_type", ""))
		var ok := false
		if mode == "mounted_all":
			ok = dt == "strategy_compound_brush"
		elif mode == "reserva_zone":
			ok = dt == "strategy_compound_brush" or (dt == "strategy_pool_slot" and str(d.get("slot_kind", "")) == "spare")
		if _hovered_drag != ok:
			_hovered_drag = ok
			queue_redraw()
		return ok

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		_hovered_drag = false
		queue_redraw()
		if not visible or not (data is Dictionary) or board == null or not is_instance_valid(board.screen):
			return
		var d: Dictionary = data
		var dt := str(d.get("drag_type", ""))
		if mode == "mounted_all" and dt == "strategy_compound_brush":
			var cid := str(d.get("compound_id", ""))
			board.screen.call("apply_compound_to_mounted_all", cid)
		elif mode == "reserva_zone":
			if dt == "strategy_compound_brush":
				var cid := str(d.get("compound_id", ""))
				if bool(board.screen.call("apply_compound_to_stock_all", cid)):
					board.play_stock_settle_all()
			elif dt == "strategy_pool_slot" and str(d.get("slot_kind", "")) == "spare":
				var src_idx := int(d.get("slot_index", -1))
				board.screen.call("unload_spare_to_stock", src_idx)

	func _draw() -> void:
		if not visible or board == null:
			return
		if mode == "mounted_all":
			if board._drag_type != "strategy_compound_brush":
				return
			var col := Tire3DViewScript.compound_ring_color(board._drag_compound_id)
			var r := Rect2(Vector2.ZERO, size)
			draw_rect(r, Color(col, 0.16 if _hovered_drag else 0.06))
			draw_rect(r, Color(col, 0.9 if _hovered_drag else 0.55), false, 2.0)
			draw_string(
				FONT_TITLE,
				Vector2(8.0, size.y - 12.0),
				"SOLTAR: APLICAR A LOS 4 MONTADOS",
				HORIZONTAL_ALIGNMENT_CENTER,
				size.x - 16.0,
				10,
				Color("#f0f4f8")
			)
		elif mode == "reserva_zone":
			var spare_drag := board._drag_type == "strategy_pool_slot" and board._drag_src_kind == "spare"
			var brush_drag := board._drag_type == "strategy_compound_brush"
			if not spare_drag and not brush_drag:
				return
			var r := Rect2(Vector2.ZERO, size)
			var border_col := Color("#22c55e") if spare_drag else Tire3DViewScript.compound_ring_color(board._drag_compound_id)
			var fill_alpha := 0.14 if _hovered_drag else 0.06
			draw_rect(r, Color(border_col, fill_alpha))
			draw_rect(r, Color(border_col, 0.9 if _hovered_drag else 0.65), false, 2.0)
			var msg := "SOLTAR EN ZONA LIBRE → MOVER DE MALETERO A RESERVA (-18 KG)" if spare_drag else ("SOLTAR AQUÍ → APLICAR %s A TODA LA RESERVA" % board._compound_short_label(board._drag_compound_id))
			var text_col := Color("#86efac") if spare_drag else Color("#f0f4f8")
			draw_string(FONT_TITLE, Vector2(10.0, size.y - 10.0), msg, HORIZONTAL_ALIGNMENT_CENTER, size.x - 20.0, 10, text_col)


class CompoundBrushCard3D extends Control:
	var board: RallyStrategyScreen3DBoard
	var compound_id: String = ""
	var compact: bool = false
	var panel_bg: Panel
	var wheel_view: SubViewportContainer
	var badge_dot: Panel
	var name_lbl: Label
	var hint_lbl: Label
	var _hovered: bool = false

	func setup(
		parent_board: RallyStrategyScreen3DBoard,
		cid: String,
		rect: Rect2,
		vehicle: Node3D,
		is_compact: bool
	) -> void:
		board = parent_board
		compound_id = cid
		compact = is_compact
		position = rect.position
		size = rect.size
		custom_minimum_size = rect.size
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

		panel_bg = Panel.new()
		panel_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel_bg)

		var has_vehicle := is_instance_valid(vehicle)
		var wdim := Vector2(46.0, 46.0) if compact else Vector2(86.0, 86.0)
		if has_vehicle:
			wheel_view = Tire3DViewScript.create_wheel_view(
				vehicle,
				0,
				{"compound_id": compound_id},
				wdim,
				Vector3(0.24, 0.36, -0.10),
				true,
				SubViewport.UPDATE_ONCE
			)
			wheel_view.position = Vector2(8.0 if compact else 12.0, (size.y - wdim.y) * 0.5)
			add_child(wheel_view)
		else:
			badge_dot = Panel.new()
			var dot_sz := 20.0 if compact else 32.0
			badge_dot.position = Vector2(14.0 if compact else 18.0, (size.y - dot_sz) * 0.5)
			badge_dot.size = Vector2(dot_sz, dot_sz)
			badge_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge_dot.add_theme_stylebox_override(
				"panel",
				Tire3DViewScript.make_slot_style(
					Color(Tire3DViewScript.compound_ring_color(compound_id), 0.28),
					Tire3DViewScript.compound_ring_color(compound_id),
					2,
					int(dot_sz * 0.5)
				)
			)
			add_child(badge_dot)

		var text_x := (wdim.x + (14.0 if compact else 20.0)) if has_vehicle else (46.0 if compact else 60.0)
		name_lbl = Label.new()
		name_lbl.position = Vector2(text_x, roundf(size.y * 0.5 - 20.0) if compact else roundf(size.y * 0.5 - 24.0))
		name_lbl.size = Vector2(size.x - text_x - 8.0, 24.0)
		name_lbl.add_theme_font_override("font", FONT_TITLE)
		name_lbl.add_theme_font_size_override("font_size", 11 if compact else 14)
		name_lbl.text = board._compound_short_label(compound_id)
		name_lbl.add_theme_color_override("font_color", Tire3DViewScript.compound_ring_color(compound_id))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(name_lbl)

		hint_lbl = Label.new()
		hint_lbl.position = Vector2(text_x, roundf(size.y * 0.5 + 2.0) if compact else roundf(size.y * 0.5 + 4.0))
		hint_lbl.size = Vector2(size.x - text_x - 8.0, 26.0)
		hint_lbl.add_theme_font_override("font", FONT_BODY)
		hint_lbl.add_theme_font_size_override("font_size", 10 if compact else 11)
		hint_lbl.text = "Arrastra al stock o maletero" if compact else "Arrastra a una rueda o al coche"
		hint_lbl.add_theme_color_override("font_color", RallyUITheme.TEXT_MUTED)
		hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hint_lbl)

		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
		refresh_visual_style()

	func _on_mouse_entered() -> void:
		_hovered = true
		refresh_visual_style()

	func _on_mouse_exited() -> void:
		_hovered = false
		refresh_visual_style()

	func refresh_visual_style() -> void:
		if panel_bg == null:
			return
		var ring_col := Tire3DViewScript.compound_ring_color(compound_id)
		var is_dragging_me := board != null and board._drag_type == "strategy_compound_brush" and board._drag_compound_id == compound_id
		var bg := RallyUITheme.BG_HOVER if (_hovered or is_dragging_me) else RallyUITheme.BG_CARD
		var border := ring_col if (_hovered or is_dragging_me) else Color(ring_col, 0.45)
		panel_bg.add_theme_stylebox_override("panel", Tire3DViewScript.make_slot_style(bg, border, 2 if (_hovered or is_dragging_me) else 1, RallyUITheme.CORNER_RADIUS))

	func _get_drag_data(_pos: Vector2) -> Variant:
		if not visible or board == null or not is_instance_valid(board.screen):
			return null
		set_drag_preview(board._make_drag_preview(0, compound_id))
		return {
			"drag_type": "strategy_compound_brush",
			"compound_id": compound_id,
			"slot_kind": "palette",
			"slot_index": -1,
		}


class StrategySlot3D extends Control:
	var board: RallyStrategyScreen3DBoard
	var slot_kind: String = ""
	var slot_index: int = -1
	var compound_id: String = ""
	var slot_active: bool = true
	var base_model_rotation: Vector3 = Vector3.ZERO

	var panel_bg: Panel
	var wheel_view: SubViewportContainer
	var badge_dot: Panel
	var title_lbl: Label
	var compound_lbl: Label
	var sub_lbl: Label
	var action_btn: Button

	var _hovered: bool = false
	var _pressed_inside: bool = false
	var _rendered_signature: String = ""

	func setup(
		parent_board: RallyStrategyScreen3DBoard,
		kind: String,
		idx: int,
		rect: Rect2,
		model_rot: Vector3,
		vehicle: Node3D
	) -> void:
		board = parent_board
		slot_kind = kind
		slot_index = idx
		base_model_rotation = model_rot
		position = rect.position
		size = rect.size
		custom_minimum_size = rect.size
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		_build_children(vehicle)
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)

	func _on_mouse_entered() -> void:
		_hovered = true
		refresh_visual_style()

	func _on_mouse_exited() -> void:
		_hovered = false
		_pressed_inside = false
		refresh_visual_style()

	func _on_action_btn_pressed() -> void:
		if board == null or not is_instance_valid(board.screen):
			return
		if slot_kind == "spare":
			if slot_active:
				board.screen.call("unload_spare_to_stock", slot_index)
			else:
				board.screen.call("_set_spare_count", slot_index + 1)

	func _build_children(vehicle: Node3D) -> void:
		panel_bg = Panel.new()
		panel_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel_bg)

		var has_vehicle := is_instance_valid(vehicle)
		var wheel_dim := Vector2(106.0, 106.0) if slot_kind == "mounted" else (Vector2(104.0, 104.0) if slot_kind == "spare" else Vector2(78.0, 78.0))
		if has_vehicle:
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
				wheel_view.position = Vector2((size.x - wheel_dim.x) * 0.5, 44.0)
			else:
				wheel_view.position = Vector2(14.0 if slot_kind == "spare" else 12.0, (size.y - wheel_dim.y) * 0.5)
			add_child(wheel_view)
		else:
			badge_dot = Panel.new()
			badge_dot.size = Vector2(32.0, 32.0) if slot_kind == "mounted" else Vector2(28.0, 28.0)
			if slot_kind == "mounted":
				badge_dot.position = Vector2((size.x - badge_dot.size.x) * 0.5, 82.0)
			else:
				badge_dot.position = Vector2(18.0, (size.y - 28.0) * 0.5)
			badge_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(badge_dot)

		title_lbl = Label.new()
		title_lbl.add_theme_font_override("font", FONT_TITLE)
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(title_lbl)

		compound_lbl = Label.new()
		compound_lbl.add_theme_font_override("font", FONT_NUM)
		compound_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(compound_lbl)

		sub_lbl = Label.new()
		sub_lbl.add_theme_font_override("font", FONT_BODY)
		sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sub_lbl)

		if slot_kind == "mounted":
			title_lbl.position = Vector2(10.0, 14.0)
			title_lbl.size = Vector2(size.x - 20.0, 20.0)
			title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title_lbl.add_theme_font_size_override("font_size", 13)

			compound_lbl.position = Vector2(10.0, 160.0)
			compound_lbl.size = Vector2(size.x - 20.0, 24.0)
			compound_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			compound_lbl.add_theme_font_size_override("font_size", 14)

			sub_lbl.position = Vector2(10.0, 188.0)
			sub_lbl.size = Vector2(size.x - 20.0, 20.0)
			sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sub_lbl.add_theme_font_size_override("font_size", 10)
		elif slot_kind == "spare":
			var tx := 130.0 if has_vehicle else 58.0
			title_lbl.position = Vector2(tx, 16.0)
			title_lbl.size = Vector2(size.x - tx - 16.0, 20.0)
			title_lbl.add_theme_font_size_override("font_size", 12)

			compound_lbl.position = Vector2(tx, 44.0)
			compound_lbl.size = Vector2(size.x - tx - 16.0, 24.0)
			compound_lbl.add_theme_font_size_override("font_size", 15)

			sub_lbl.position = Vector2(tx, 74.0)
			sub_lbl.size = Vector2(size.x - tx - 16.0, 34.0)
			sub_lbl.add_theme_font_size_override("font_size", 11)

			action_btn = Button.new()
			action_btn.position = Vector2(tx, size.y - 40.0)
			action_btn.size = Vector2(174.0, 28.0)
			action_btn.focus_mode = Control.FOCUS_NONE
			RallyUITheme.style_tone_button(action_btn, "chrome", 10, 8, 4, RallyUITheme.CORNER_RADIUS, FONT_NUM)
			action_btn.pressed.connect(_on_action_btn_pressed)
			add_child(action_btn)
		else:
			var sx := 100.0 if has_vehicle else 58.0
			title_lbl.position = Vector2(sx, 16.0)
			title_lbl.size = Vector2(size.x - sx - 10.0, 20.0)
			title_lbl.add_theme_font_size_override("font_size", 12)

			compound_lbl.position = Vector2(sx, 44.0)
			compound_lbl.size = Vector2(size.x - sx - 10.0, 24.0)
			compound_lbl.add_theme_font_size_override("font_size", 14)

			sub_lbl.position = Vector2(sx, 74.0)
			sub_lbl.size = Vector2(size.x - sx - 10.0, 22.0)
			sub_lbl.add_theme_font_size_override("font_size", 10)

	func update_slot(next_compound_id: String, active: bool, wheel_idx_hint: int) -> void:
		compound_id = next_compound_id
		slot_active = active
		var vehicle: Node3D = board.screen.get("vehicle") as Node3D if (board != null and is_instance_valid(board.screen)) else null

		if not slot_active:
			if wheel_view != null:
				wheel_view.visible = false
			if badge_dot != null:
				badge_dot.visible = false
			title_lbl.text = "MALETERO #%d (LIBRE)" % (slot_index + 1)
			title_lbl.add_theme_color_override("font_color", RallyUITheme.TEXT_MUTED)
			compound_lbl.text = "SIN RUEDA CARGADA"
			compound_lbl.add_theme_color_override("font_color", RallyUITheme.TEXT_DIM)
			sub_lbl.text = "Arrastra desde Reserva aquí para llevar repuesto (+18 kg)"
			sub_lbl.add_theme_color_override("font_color", RallyUITheme.TEXT_DIM)
			if action_btn != null:
				action_btn.text = "CARGAR DESDE RESERVA (+18 KG)"
				action_btn.visible = true
			_rendered_signature = "inactive"
			refresh_visual_style()
			return

		var sig := "%s:%d" % [compound_id, wheel_idx_hint]
		if wheel_view != null:
			wheel_view.visible = true
			if sig != _rendered_signature and is_instance_valid(vehicle):
				_rendered_signature = sig
				var pivot := Tire3DViewScript.get_pivot(wheel_view)
				Tire3DViewScript.populate_wheel_pivot(pivot, vehicle, wheel_idx_hint, {"compound_id": compound_id}, true)
				Tire3DViewScript.refresh_viewport(wheel_view)

		var ring_col := Tire3DViewScript.compound_ring_color(compound_id)
		if badge_dot != null:
			badge_dot.visible = true
			badge_dot.add_theme_stylebox_override("panel", Tire3DViewScript.make_slot_style(Color(ring_col, 0.28), ring_col, 2, 14))

		var corner_names := ["FL", "FR", "RL", "RR"]
		if slot_kind == "mounted":
			title_lbl.text = corner_names[clampi(slot_index, 0, 3)]
			sub_lbl.text = "Clic cambia · Arrastra"
		elif slot_kind == "spare":
			title_lbl.text = "MALETERO #%d" % (slot_index + 1)
			sub_lbl.text = "Arrastra a Reserva para aligerar (-18 kg)"
			if action_btn != null:
				action_btn.text = "MOVER A RESERVA (-18 KG)"
				action_btn.visible = true
		else:
			title_lbl.text = "RESERVA #%d" % (slot_index + 1)
			sub_lbl.text = "Clic cambia · Arrastra al Maletero"

		title_lbl.add_theme_color_override("font_color", RallyUITheme.TEXT_MUTED)
		compound_lbl.text = board._compound_short_label(compound_id)
		compound_lbl.add_theme_color_override("font_color", ring_col)
		sub_lbl.add_theme_color_override("font_color", RallyUITheme.TEXT_MUTED)
		refresh_visual_style()

	func refresh_visual_style() -> void:
		if panel_bg == null or board == null or not is_instance_valid(board.screen):
			return
		var focus_id := str(board.screen.get("_focus_id"))
		var is_focused := focus_id == ("%s:%d" % [slot_kind, slot_index])

		var bg := RallyUITheme.BG_CARD if slot_active else Color(RallyUITheme.BG_SURFACE, 0.80)
		var border := RallyUITheme.BORDER_CARD if slot_active else RallyUITheme.BORDER_SUBTLE
		var width := 1

		if board._drag_type == "strategy_compound_brush":
			if slot_active and compound_id != board._drag_compound_id:
				bg = Color("#193627") if _hovered else Color("#13281d")
				border = RallyUITheme.STATUS_SUCCESS
				width = 2
			else:
				border = Color(RallyUITheme.TEXT_DIM, 0.35)
		elif board._drag_type == "strategy_pool_slot":
			if board._drag_src_kind == slot_kind and board._drag_src_index == slot_index:
				bg = Color("#2a2010")
				border = RallyUITheme.ACCENT_RALLY
				width = 2
			elif not slot_active and slot_kind == "spare" and board._drag_src_kind == "stock":
				bg = Color("#193627") if _hovered else Color("#13281d")
				border = RallyUITheme.STATUS_SUCCESS
				width = 2
			elif slot_active:
				bg = Color("#193627") if _hovered else Color("#13281d")
				border = RallyUITheme.STATUS_SUCCESS
				width = 2
			else:
				border = Color(RallyUITheme.TEXT_DIM, 0.35)
		elif is_focused:
			bg = RallyUITheme.BG_HOVER
			border = RallyUITheme.BORDER_FOCUS
			width = 2
		elif _hovered and slot_active:
			bg = RallyUITheme.BG_ELEVATED
			border = Color(RallyUITheme.ACCENT_RALLY, 0.78)
			width = 1

		panel_bg.add_theme_stylebox_override("panel", Tire3DViewScript.make_slot_style(bg, border, width, RallyUITheme.CORNER_RADIUS))

	func _gui_input(event: InputEvent) -> void:
		if not visible or board == null or not is_instance_valid(board.screen):
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
					if slot_active:
						board.screen.set("_focus_id", "%s:%d" % [slot_kind, slot_index])
						board.screen.call("_cycle_slot", slot_kind, slot_index)
					elif slot_kind == "spare":
						board.screen.call("_set_spare_count", slot_index + 1)
				accept_event()

	func _get_drag_data(_pos: Vector2) -> Variant:
		if not visible or not slot_active or compound_id.is_empty() or board == null or not is_instance_valid(board.screen):
			return null
		_pressed_inside = false
		set_drag_preview(board._make_drag_preview(slot_index if slot_kind == "mounted" else 0, compound_id))
		return {
			"drag_type": "strategy_pool_slot",
			"compound_id": compound_id,
			"slot_kind": slot_kind,
			"slot_index": slot_index,
		}

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if not visible or not (data is Dictionary) or board == null or not is_instance_valid(board.screen):
			return false
		var d: Dictionary = data
		var dt := str(d.get("drag_type", ""))
		if dt == "strategy_compound_brush":
			if not slot_active:
				return false
			var cid := str(d.get("compound_id", ""))
			var allowed: Array = board.screen.get("allowed_compounds")
			return allowed.has(cid)
		if dt == "strategy_pool_slot":
			var src_kind := str(d.get("slot_kind", ""))
			var src_idx := int(d.get("slot_index", -1))
			if src_kind == slot_kind and src_idx == slot_index:
				return false
			if slot_active:
				return true
			return slot_kind == "spare" and src_kind == "stock"
		return false

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if not visible or not (data is Dictionary) or board == null or not is_instance_valid(board.screen):
			return
		var d: Dictionary = data
		var dt := str(d.get("drag_type", ""))
		if dt == "strategy_compound_brush" and slot_active:
			var cid := str(d.get("compound_id", ""))
			board.screen.set("_focus_id", "%s:%d" % [slot_kind, slot_index])
			if bool(board.screen.call("apply_compound_to_slot", slot_kind, slot_index, cid)):
				board.play_settle(slot_kind, slot_index)
		elif dt == "strategy_pool_slot":
			var src_kind := str(d.get("slot_kind", ""))
			var src_idx := int(d.get("slot_index", -1))
			if slot_active:
				board.screen.set("_focus_id", "%s:%d" % [slot_kind, slot_index])
				if bool(board.screen.call("swap_pool_slots", src_kind, src_idx, slot_kind, slot_index)):
					board.play_settle(slot_kind, slot_index)
					board.play_settle(src_kind, src_idx)
			elif slot_kind == "spare" and src_kind == "stock":
				if bool(board.screen.call("load_stock_to_spare", src_idx)):
					board.play_settle("spare", clampi(int(board.screen.get("carried_spares_count")) - 1, 0, 1))
