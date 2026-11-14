extends VBoxContainer
## Fixed inspection board. Slots are semantic destinations shared by drag and pad input.
const Tire3DViewScript := preload("res://scripts/rally/rally_tire_3d_view.gd")
const WHEELS := Tire3DViewScript.WHEELS
const NAMES := ["DEL. IZQUIERDA", "DEL. DERECHA", "TRAS. IZQUIERDA", "TRAS. DERECHA", "RADIADOR", "MALETERA 1", "MALETERA 2"]
var host: CanvasLayer
var selected := 0
var held := -1
var category := "wheels"
var board: Control
var info: Label
var buttons: Array[Button] = []
var copies: Array[MeshInstance3D] = []
var pad := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme = RallyUITheme.build_menu_theme()
	_build()

func tire_at(index: int) -> Dictionary:
	var inv = host.session.vehicle.tire_inventory
	if index >= 0 and index < 4: return inv.mounted[index]
	if index >= 5 and index - 5 < inv.spares.size(): return inv.spares[index - 5]
	return {}

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	buttons.clear()
	copies.clear()
	var row := HBoxContainer.new()
	add_child(row)
	board = Control.new()
	board.custom_minimum_size = Vector2(760, 380)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(board)
	var backdrop := ColorRect.new()
	backdrop.color = RallyUITheme.BG_WELL
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(backdrop)
	var car := Tire3DViewScript.create_vehicle_top_view(host.session.vehicle, Vector2(260, 345), false, copies, SubViewport.UPDATE_ONCE)
	_place(car, 0.50, 0.51, Vector2(260, 345))
	_caption("MALETERA", 0.10, 0.045)
	_caption("DESCARTE", 0.92, 0.045)
	for x in [0.21, 0.82]:
		var line := ColorRect.new()
		line.color = RallyUITheme.BORDER_SUBTLE
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place(line, x, 0.50, Vector2(1, 360))
	var tabs := VBoxContainer.new()
	tabs.custom_minimum_size.x = 150
	tabs.add_theme_constant_override("separation", 6)
	row.add_child(tabs)
	host.button("RUEDAS", func(): _category("wheels"), tabs, true)
	host.button("RADIADOR", func(): _category("radiator"), tabs, true)
	if category == "wheels":
		var coords := [Vector2(.31,.27),Vector2(.69,.27),Vector2(.31,.74),Vector2(.69,.74),Vector2.ZERO,Vector2(.10,.27),Vector2(.10,.74)]
		for index in [0,1,2,3,5,6]:
			var tile := _slot(index, NAMES[index], coords[index])
			var tire := tire_at(index)
			if not tire.is_empty():
				var view := _wheel_view(index)
				view.name = "WheelView"
				view.position = Vector2(4, 14)
				tile.add_child(view)
				var text := Label.new()
				text.text = _condition(tire)
				text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				RallyUITheme.style_label(text, "white", 9, true, false)
				text.add_theme_font_override("font", RallyUITheme.FONT_MEDIUM_TIGHT)
				var scrim_sb := RallyUITheme.make_flat_panel(
					Color(0.03, 0.045, 0.07, 0.90),
					RallyUITheme.BORDER_SUBTLE,
					1,
					RallyUITheme.CORNER_RADIUS,
					4,
					3
				)
				text.add_theme_stylebox_override("normal", scrim_sb)
				text.position = Vector2(4, 88)
				text.size = Vector2(138, 68)
				text.mouse_filter = Control.MOUSE_FILTER_IGNORE
				tile.add_child(text)
		var bin := _slot(9, "DESCARTAR\n(solicita confirmación)", Vector2(.92,.50))
		bin.custom_minimum_size = Vector2(120,130)
	else:
		if tool_available(7):
			_tool_slot(7, "RÁPIDA · 1 USO\n+20 salud · 30 s", Vector2(.10,.27), Color("eadcc0"))
		else:
			_caption("Rápida: agotada", .10, .27)
		if tool_available(8):
			_tool_slot(8, "GRAVE · 1 USO\n+50 salud · 60 s", Vector2(.10,.74), Color("f28b87"))
		else:
			_caption("Grave: agotada", .10, .74)
		var radiator := _slot(4, "RADIADOR\nSalud %d%%" % roundi((1-host.get_radiator_damage())*100), Vector2(.50,.14))
		radiator.offset_top = -28
		radiator.offset_bottom = 28
		radiator.add_theme_color_override("font_color", RallyUITheme.ACCENT_RALLY)
		var tm = host.session.vehicle.simulation.thermal_model
		_caption("Agua %.0f °C · Aceite %.0f °C\nMotor %.0f °C" % [tm.water_temperature_c, tm.oil_temperature_c, tm.engine_block_temperature_c], .50, .86)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Arrastra o selecciona origen y destino · A tomar/colocar · B cancelar · LB/RB categoría · X aplicar herramienta"
	info.add_theme_font_override("font", RallyUITheme.FONT_MEDIUM)
	info.add_theme_font_size_override("font_size", 10)
	add_child(info)
	if not host.notice.is_empty(): info.text += "\n" + host.notice
	if not buttons.is_empty(): buttons[0].grab_focus()

func _tool_slot(index: int, title: String, point: Vector2, paint: Color) -> void:
	var tile := _slot(index, "", point)
	var view := _tool_view(paint)
	tile.add_child(view)
	var text := Label.new()
	text.text = title
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_theme_font_override("font", RallyUITheme.FONT_MEDIUM_TIGHT)
	text.add_theme_font_size_override("font_size", 9)
	text.position = Vector2(0, 122)
	text.size = Vector2(146, 36)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(text)

func _wheel_view(index: int, live_update: bool = false) -> SubViewportContainer:
	var mode := SubViewport.UPDATE_ALWAYS if live_update else SubViewport.UPDATE_ONCE
	return Tire3DViewScript.create_wheel_view(
		host.session.vehicle,
		index,
		tire_at(index),
		Vector2(138, 138),
		Vector3.ZERO,
		false,
		mode
	)


func _settle_wheel(index: int) -> void:
	for button in buttons:
		if button.index != index:
			continue
		var view := button.get_node_or_null("WheelView") as SubViewportContainer
		if view == null:
			return
		Tire3DViewScript.play_settle_animation(self, view, Vector3.ZERO)
		return


func _tool_view(paint: Color) -> SubViewportContainer:
	var view := _view(Vector2(142, 118), true)
	view.position = Vector2(2, 2)
	var world: Node3D = view.get_child(0).get_child(0)
	var model: Node3D = preload("res://assets/rally/service/toolbox/toolbox.scn").instantiate()
	var pivot := Node3D.new()
	pivot.name = "ModelPivot"
	world.add_child(pivot)
	var holder := Node3D.new()
	pivot.add_child(holder)
	holder.add_child(model)
	var bounds := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var local_transform := mesh_node.transform
		var ancestor := mesh_node.get_parent()
		while ancestor != holder:
			if ancestor is Node3D: local_transform = ancestor.transform * local_transform
			ancestor = ancestor.get_parent()
		var box: AABB = local_transform * mesh_node.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		for surface in mesh_node.mesh.get_surface_count():
			var source := mesh_node.get_active_material(surface) as StandardMaterial3D
			if source == null: continue
			var material := ShaderMaterial.new()
			material.shader = preload("res://assets/rally/service/toolbox/toolbox_tint.gdshader")
			material.set_shader_parameter("source_color_texture", source.albedo_texture)
			material.set_shader_parameter("paint", paint)
			mesh_node.set_surface_override_material(surface, material)
	var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var factor := 1.0 / maxf(extent, 0.001)
	holder.scale = Vector3.ONE * factor
	holder.position = -bounds.get_center() * factor
	var camera := world.get_child(0) as Camera3D
	camera.size = 1.45
	camera.position = Vector3(1.4, 1.2, 1.8)
	camera.look_at_from_position(camera.position, Vector3.ZERO)
	return view

func _category(value: String, play_sound: bool = true) -> void:
	if play_sound and category != value:
		get_node("/root/UIButtonAudio").play_tab_click()
	category = value
	held = -1
	_build()

func _place(control: Control, x: float, y: float, dimensions: Vector2) -> void:
	board.add_child(control)
	control.anchor_left = x
	control.anchor_right = x
	control.anchor_top = y
	control.anchor_bottom = y
	control.offset_left = -dimensions.x/2
	control.offset_right = dimensions.x/2
	control.offset_top = -dimensions.y/2
	control.offset_bottom = dimensions.y/2

func _caption(text: String, x: float, y: float) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	RallyUITheme.style_label(label, "primary", 10, true, true)
	label.add_theme_font_override("font", RallyUITheme.FONT_DATA_BOLD_TIGHT)
	label.add_theme_stylebox_override(
		"normal",
		RallyUITheme.make_flat_panel(Color(RallyUITheme.BG_WELL, 0.94), RallyUITheme.BORDER_CARD, 1, RallyUITheme.CORNER_RADIUS, 12, 6)
	)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(label, x, y, Vector2(280, 42))

func _slot(index: int, title: String, point: Vector2) -> Button:
	var b := ServiceSlot.new()
	b.workshop = self
	b.index = index
	b.text = title
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_font_override("font", RallyUITheme.FONT_BUTTON)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", RallyUITheme.TEXT_PRIMARY)
	b.add_theme_color_override("font_hover_color", RallyUITheme.TEXT_WHITE)
	b.add_theme_color_override("font_focus_color", RallyUITheme.TEXT_WHITE)
	var style := RallyUITheme.make_flat_panel(Color(RallyUITheme.BG_CARD, 0.92), RallyUITheme.BORDER_CARD, 1, RallyUITheme.CORNER_RADIUS, 8, 8)
	var style_hover := RallyUITheme.make_flat_panel(Color(RallyUITheme.BG_HOVER, 0.96), RallyUITheme.BORDER_HOVER, 1, RallyUITheme.CORNER_RADIUS, 8, 8)
	var style_focus := RallyUITheme.make_flat_panel(Color(RallyUITheme.BG_ELEVATED, 0.98), RallyUITheme.BORDER_FOCUS, 2, RallyUITheme.CORNER_RADIUS, 8, 8)
	var style_pressed := RallyUITheme.make_flat_panel(Color("#2a2010", 0.96), RallyUITheme.ACCENT_RALLY, 2, RallyUITheme.CORNER_RADIUS, 8, 8)
	var style_disabled := RallyUITheme.make_flat_panel(Color(RallyUITheme.BG_SURFACE, 0.45), RallyUITheme.BORDER_SUBTLE, 1, RallyUITheme.CORNER_RADIUS, 8, 8)
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("hover", style_hover)
	b.add_theme_stylebox_override("focus", style_focus)
	b.add_theme_stylebox_override("pressed", style_pressed)
	b.add_theme_stylebox_override("disabled", style_disabled)
	_place(b,point.x,point.y,Vector2(146,160))
	if category == "wheels" and index != 9:
		b.text = ""
		var name_label := Label.new()
		name_label.text = title
		name_label.size = Vector2(146,20)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		RallyUITheme.style_label(name_label, "muted", 12, false, true)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(name_label)
	b.focus_entered.connect(func(): selected = index)
	b.pressed.connect(func(): selected = index; activate())
	buttons.append(b)
	return b

func _view(dimensions: Vector2, wheel: bool) -> SubViewportContainer:
	return Tire3DViewScript.create_viewport_container(
		dimensions,
		0.65 if wheel else 5.2,
		Vector3(0.0, 3.0 if wheel else 8.0, 0.0),
		Vector3.BACK if wheel else Vector3.FORWARD,
		SubViewport.UPDATE_ALWAYS
	)

func _condition(tire: Dictionary) -> String:
	var s: Dictionary = tire.state
	var lines := "#%d · Desgaste %.0f%%" % [tire.id,float(s.get("wear_fraction",0))*100]
	lines += "\nPinchada" if float(s.get("leak_per_second",0)) > 0 else "\nSin pinchadura"
	lines += "\nDestalonada" if RallyEscortVehicle.tire_is_unseated(s) else ""
	lines += "\nRin dañado" if float(s.get("rim_deformation",0)) > .005 else "\nRin sano"
	return lines

func tool_available(index: int) -> bool:
	return index in [7,8] and bool(host.session.vehicle.tire_inventory.repair_kits[index-7])

func compatible(source: int, target: int) -> bool:
	if source in [7,8]: return target == 4 and tool_available(source)
	if tire_at(source).is_empty(): return false
	if target == 9: return source >= 5
	if target == 4: return false
	return target < 4 or (source < 4 and not tire_at(target).is_empty())

func select_slot(index: int) -> void:
	selected = index

func activate() -> void:
	if held < 0:
		if not tire_at(selected).is_empty() or tool_available(selected): held = selected
	elif held == selected: cancel_transfer()
	elif compatible(held,selected):
		var source := held
		held = -1
		if selected == 4:
			if host.session.on_quick_repair_radiator_requested(source == 8):
				host.notice = "Radiador reparado · +%d s. Caja consumida." % (60 if source == 8 else 30)
				host.persist()
			_build()
		elif selected == 9:
			var id: int = tire_at(source).id
			var dialog := ConfirmationDialog.new()
			dialog.dialog_text = "¿Descartar repuesto #%d?" % id
			add_child(dialog)
			dialog.confirmed.connect(func(): host.session.vehicle.discard_spare(id); host.persist(); host.show_inventory())
			dialog.canceled.connect(dialog.queue_free)
			dialog.popup_centered()
		else:
			host._on_drop_action({"source_type":"mounted" if source<4 else "spare","index":source if source<4 else source-5,"tire":tire_at(source)},"mounted" if selected<4 else "spare",selected if selected<4 else selected-5)
	for b in buttons:
		b.modulate = Color("e5a93c") if b.index == held else (Color("8bdfac") if held>=0 and compatible(held,b.index) else Color.WHITE)

func cancel_transfer() -> bool:
	var was := held >= 0
	held = -1
	for b in buttons:
		if is_instance_valid(b):
			b.modulate = Color.WHITE
	return was


func _move_spatial(dir: Vector2) -> void:
	if buttons.is_empty():
		return
	var cur := buttons[0]
	for b in buttons:
		if is_instance_valid(b) and b.index == selected:
			cur = b
			break
	var origin := cur.position + cur.size * 0.5
	var best: Button = null
	var best_score := 1e12
	for b in buttons:
		if not is_instance_valid(b) or b == cur:
			continue
		var delta := (b.position + b.size * 0.5) - origin
		var proj := delta.dot(dir)
		if proj <= 4.0:
			continue
		var perp := absf(delta.cross(dir))
		var score := proj + perp * 2.5
		if score < best_score:
			best_score = score
			best = b
	if best == null:
		# Wrap around to the farthest button on the opposite side of dir.
		var worst_proj := 1e12
		for b in buttons:
			if not is_instance_valid(b) or b == cur:
				continue
			var proj := ((b.position + b.size * 0.5) - origin).dot(dir)
			if proj < worst_proj:
				worst_proj = proj
				best = b
	if best != null:
		best.grab_focus()


func _input(event: InputEvent) -> void:
	if not host.modal.visible or host.current_view != "inventory":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_LEFT:
				_move_spatial(Vector2.LEFT)
			KEY_RIGHT:
				_move_spatial(Vector2.RIGHT)
			KEY_UP:
				_move_spatial(Vector2.UP)
			KEY_DOWN:
				_move_spatial(Vector2.DOWN)
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_LEFT_SHOULDER: _category("wheels")
			JOY_BUTTON_RIGHT_SHOULDER: _category("radiator")
			JOY_BUTTON_A:
				if not buttons.has(get_viewport().gui_get_focus_owner()): return
				activate()
			JOY_BUTTON_DPAD_RIGHT:
				_move_spatial(Vector2.RIGHT)
			JOY_BUTTON_DPAD_LEFT:
				_move_spatial(Vector2.LEFT)
			JOY_BUTTON_DPAD_DOWN:
				_move_spatial(Vector2.DOWN)
			JOY_BUTTON_DPAD_UP:
				_move_spatial(Vector2.UP)
			JOY_BUTTON_X:
				if held in [7,8]: selected = 4; activate()
			_: return
		get_viewport().set_input_as_handled()

const HeldPreviewScript := preload("res://scripts/rally/rally_held_part_preview.gd")

class PartDragPreview extends HeldPreviewScript:
	pass

class ServiceSlot extends Button:
	var workshop: VBoxContainer
	var index: int
	func _get_drag_data(_pos: Vector2) -> Variant:
		if workshop.tire_at(index).is_empty() and not workshop.tool_available(index): return null
		var preview := PartDragPreview.new()
		if index in [7, 8]:
			preview.model_view = workshop._tool_view(Color("eadcc0") if index == 7 else Color("f28b87"))
		else:
			preview.model_view = workshop._wheel_view(index, true)
		var world: Node3D = preview.model_view.get_child(0).get_child(0)
		preview.pivot = world.get_node("ModelPivot")
		preview.add_child(preview.model_view)
		set_drag_preview(preview)
		return {"slot":index}
	func _can_drop_data(_pos: Vector2,data: Variant) -> bool:
		return data is Dictionary and data.has("slot") and workshop.compatible(int(data.slot),index)
	func _drop_data(_pos: Vector2,data: Variant) -> void:
		workshop.held = int(data.slot)
		workshop.selected = index
		var host: CanvasLayer = workshop.host
		var wheel_id: int = int(workshop.tire_at(int(data.slot)).get("id", -1))
		workshop.activate()
		if wheel_id >= 0 and index in [0, 1, 2, 3, 5, 6]:
			var refreshed = host.content.get_child(0)
			if int(refreshed.tire_at(index).get("id", -1)) == wheel_id:
				refreshed._settle_wheel(index)

