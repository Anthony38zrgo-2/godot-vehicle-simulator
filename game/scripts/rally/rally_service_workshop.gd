extends VBoxContainer
## Fixed inspection board. Slots are semantic destinations shared by drag and pad input.
const WHEELS := ["WheelFrontLeft", "WheelFrontRight", "WheelRearLeft", "WheelRearRight"]
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
	backdrop.color = Color("101b29")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(backdrop)
	var car := _view(Vector2(260, 345), false)
	_place(car, 0.50, 0.51, Vector2(260, 345))
	_copy(host.session.vehicle, host.session.vehicle, car.get_child(0).get_child(0), -1)
	_caption("MALETERA", 0.10, 0.045)
	_caption("DESCARTE", 0.92, 0.045)
	for x in [0.21, 0.82]:
		var line := ColorRect.new()
		line.color = Color("344457")
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place(line, x, 0.50, Vector2(2, 360))
	var tabs := VBoxContainer.new()
	tabs.custom_minimum_size.x = 150
	row.add_child(tabs)
	host.button("RUEDAS", func(): _category("wheels"), tabs)
	host.button("RADIADOR", func(): _category("radiator"), tabs)
	if category == "wheels":
		var coords := [Vector2(.31,.27),Vector2(.69,.27),Vector2(.31,.74),Vector2(.69,.74),Vector2.ZERO,Vector2(.10,.27),Vector2(.10,.74)]
		for index in [0,1,2,3,5,6]:
			var tile := _slot(index, NAMES[index], coords[index])
			var tire := tire_at(index)
			if not tire.is_empty():
				var view := _wheel_view(index)
				view.name = "WheelView"
				view.position = Vector2(4, 22)
				tile.add_child(view)
				var text := Label.new()
				text.text = _condition(tire)
				text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				text.add_theme_font_size_override("font_size", 12)
				text.add_theme_color_override("font_shadow_color", Color.BLACK)
				text.add_theme_constant_override("shadow_offset_x", 2)
				text.add_theme_constant_override("shadow_offset_y", 2)
				text.position = Vector2(2, 50)
				text.size = Vector2(142,90)
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
		var radiator := _slot(4, "RADIADOR\nSalud %d%%" % roundi((1-host.get_radiator_damage())*100), Vector2(.50,.20))
		radiator.offset_top = -35
		radiator.offset_bottom = 35
		var transparent := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			radiator.add_theme_stylebox_override(state, transparent)
		var tm = host.session.vehicle.simulation.thermal_model
		_caption("Agua %.0f °C · Aceite %.0f °C\nMotor %.0f °C" % [tm.water_temperature_c, tm.oil_temperature_c, tm.engine_block_temperature_c], .50,.35)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Arrastra o selecciona origen y destino · A tomar/colocar · B cancelar · LB/RB categoría · X aplicar herramienta"
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
	text.add_theme_font_size_override("font_size", 12)
	text.position = Vector2(0, 122)
	text.size = Vector2(146, 36)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(text)

func _wheel_view(index: int) -> SubViewportContainer:
	var view := _view(Vector2(138, 138), true)
	var world: Node3D = view.get_child(0).get_child(0)
	var pivot := Node3D.new()
	pivot.name = "ModelPivot"
	world.add_child(pivot)
	var vehicle: Node3D = host.session.vehicle
	var wheel := vehicle.get_node(NodePath(WHEELS[index if index < 4 else 0]))
	_copy(wheel, vehicle, pivot, index)
	return view


func _settle_wheel(index: int) -> void:
	for button in buttons:
		if button.index != index:
			continue
		var view := button.get_node_or_null("WheelView") as SubViewportContainer
		if view == null:
			return
		var world: Node3D = view.get_child(0).get_child(0)
		var pivot := world.get_node("ModelPivot") as Node3D
		pivot.rotation = Vector3(0.16, 0.0, -0.12)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(pivot, "rotation", Vector3.ZERO, 0.28)
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

func _category(value: String) -> void:
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
	label.add_theme_font_size_override("font_size", 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(label,x,y,Vector2(260,32))

func _slot(index: int, title: String, point: Vector2) -> Button:
	var b := ServiceSlot.new()
	b.workshop = self
	b.index = index
	b.text = title
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_font_size_override("font_size", 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08,0.14,0.20,0.3)
	style.border_color = Color("53677a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	b.add_theme_stylebox_override("normal",style)
	_place(b,point.x,point.y,Vector2(146,160))
	if category == "wheels" and index != 9:
		b.text = ""
		var name_label := Label.new()
		name_label.text = title
		name_label.size = Vector2(146,20)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size",11)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(name_label)
	b.focus_entered.connect(func(): selected = index)
	b.pressed.connect(func(): selected = index; activate())
	buttons.append(b)
	return b

func _view(dimensions: Vector2, wheel: bool) -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.size = dimensions
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.stretch = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(dimensions)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	container.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.65 if wheel else 5.2
	camera.position = Vector3(0,3 if wheel else 8,0)
	camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.BACK if wheel else Vector3.FORWARD)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-80,20,0)
	light.light_energy = 2
	world.add_child(light)
	return container

func _copy(node: Node, vehicle: Node3D, world: Node3D, index: int) -> void:
	if node is MeshInstance3D and node.mesh != null and node.is_visible_in_tree():
		var copy := MeshInstance3D.new()
		copy.mesh = node.mesh
		copy.material_override = node.material_override
		for surface in node.mesh.get_surface_count():
			copy.set_surface_override_material(surface, node.get_surface_override_material(surface))
		world.add_child(copy)
		copy.transform = vehicle.global_transform.affine_inverse()*node.global_transform
		if index >= 0:
			var pivot: Node3D = vehicle.get_node(NodePath(WHEELS[index if index < 4 else 0]))
			copy.transform = Transform3D(Basis(Vector3.FORWARD,PI/2),Vector3.ZERO) * (pivot.global_transform.affine_inverse()*node.global_transform)
			var state: Dictionary = tire_at(index).state
			var severity := maxf(float(state.get("wear_fraction", 0)), float(state.get("pressure_loss_fraction", 0)))
			if severity > 0.05:
				var damage_material := StandardMaterial3D.new()
				damage_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				damage_material.albedo_color = Color(1.0, 1.0 - severity, 0.0, 0.22)
				copy.material_overlay = damage_material
		if index < 0: copies.append(copy)
	for child in node.get_children(): _copy(child, vehicle, world, index)

func _condition(tire: Dictionary) -> String:
	var s: Dictionary = tire.state
	var lines := "#%d · Desgaste %.0f%%" % [tire.id,float(s.get("wear_fraction",0))*100]
	lines += "\nPinchada" if float(s.get("leak_per_second",0)) > 0 else "\nSin pinchadura"
	lines += "\nDestalonada" if bool(s.get("bead_unseated",false)) else ""
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
	return was

func _input(event: InputEvent) -> void:
	if not host.modal.visible or host.current_view != "inventory": return
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_LEFT_SHOULDER: _category("wheels")
			JOY_BUTTON_RIGHT_SHOULDER: _category("radiator")
			JOY_BUTTON_A:
				if not buttons.has(get_viewport().gui_get_focus_owner()): return
				activate()
			JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT:
				var next := 0
				for i in buttons.size():
					if buttons[i].index == selected: next = (i+1)%buttons.size()
				buttons[next].grab_focus()
			JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_LEFT:
				var prev := 0
				for i in buttons.size():
					if buttons[i].index == selected: prev = posmod(i-1,buttons.size())
				buttons[prev].grab_focus()
			JOY_BUTTON_X:
				if held in [7,8]: selected = 4; activate()
			_: return
		get_viewport().set_input_as_handled()

class PartDragPreview extends Control:
	const SPRING_FREQUENCY := 18.0
	const MAX_LAG := 36.0
	var model_view: SubViewportContainer
	var pivot: Node3D
	var previous_mouse: Vector2
	var displacement := Vector2.ZERO
	var velocity := Vector2.ZERO

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		previous_mouse = get_global_mouse_position()
		model_view.position = -model_view.size * 0.5

	func _process(delta: float) -> void:
		var mouse := get_global_mouse_position()
		displacement = (displacement - (mouse - previous_mouse)).limit_length(MAX_LAG)
		previous_mouse = mouse

		# Critically damped spring, integrated exactly for the current frame.
		var decay := exp(-SPRING_FREQUENCY * delta)
		var slope := velocity + SPRING_FREQUENCY * displacement
		displacement = (displacement + slope * delta) * decay
		velocity = (velocity - SPRING_FREQUENCY * slope * delta) * decay

		model_view.position = displacement - model_view.size * 0.5
		pivot.rotation = Vector3(displacement.y, displacement.x * 0.35, -displacement.x) * 0.009

class ServiceSlot extends Button:
	var workshop: VBoxContainer
	var index: int
	func _get_drag_data(_pos: Vector2) -> Variant:
		if workshop.tire_at(index).is_empty() and not workshop.tool_available(index): return null
		var preview := PartDragPreview.new()
		if index in [7, 8]:
			preview.model_view = workshop._tool_view(Color("eadcc0") if index == 7 else Color("f28b87"))
		else:
			preview.model_view = workshop._wheel_view(index)
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

