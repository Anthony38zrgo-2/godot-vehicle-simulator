extends CanvasLayer

var session: Node
var screen: Control
var modal: PanelContainer
var content: VBoxContainer
var selected_wheel: int = 0
var spare_picker: OptionButton
var keep_removed: CheckButton
var notice: String = ""
var pause_button: Button

func _process(_delta: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	screen.size = viewport_size
	modal.position = (viewport_size - modal.size) * 0.5
	pause_button.position = Vector2(viewport_size.x - 150, 12)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	screen.size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(func(): screen.size = get_viewport().get_visible_rect().size)
	var pause := Button.new()
	pause_button = pause
	pause.text = "Pausa · Esc"
	screen.add_child(pause)
	pause.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	pause.position = Vector2(-150, 12)
	pause.size = Vector2(140, 36)
	pause.pressed.connect(toggle)
	modal = PanelContainer.new()
	screen.add_child(modal)
	modal.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	modal.position = Vector2(-450, -285)
	modal.custom_minimum_size = Vector2(900, 570)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.07, 0.98)
	style.set_content_margin_all(20)
	modal.add_theme_stylebox_override("panel", style)
	modal.add_theme_font_override("font", load("res://fonts/libron/Libron-Regular.ttf"))
	modal.add_theme_font_size_override("font_size", 18)
	content = VBoxContainer.new()
	modal.add_child(content)
	modal.hide()

func _input(event: InputEvent) -> void:
	if (event.is_action_pressed("ui_cancel") or event.is_action_pressed(InputBindings.UI_BACK_TO_MENU)) and not event.is_echo():
		if allowed() or modal.visible:
			toggle()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	_input(event)

func allowed() -> bool:
	return session != null and session.session_ready and not session.awaiting_setup and not session.stage_transition_running and not session.competition.complete and (session.garage_panel == null or not session.garage_panel.visible)

func toggle() -> void:
	if modal.visible:
		modal.hide()
		get_tree().paused = false
		session.pacenotes.on_pause(false)
		return
	if not allowed() or get_tree().paused:
		return
	session.vehicle.ensure_tire_inventory()
	session.vehicle.sync_tire_inventory()
	get_tree().paused = true
	session.pacenotes.on_pause(true)
	modal.show()
	show_menu()

func clear() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()

func label(text: String) -> void:
	var node := Label.new()
	node.text = text
	content.add_child(node)

func button(text: String, callback: Callable, parent: Node = null) -> void:
	var node := Button.new()
	node.text = text
	node.pressed.connect(callback)
	(parent if parent != null else content).add_child(node)

func get_radiator_damage() -> float:
	if session != null:
		var v: Variant = session.get("vehicle")
		if v != null and v.get("simulation") != null and v.simulation.get("thermal_model") != null:
			return float(v.simulation.thermal_model.radiator_damage)
	return 0.0

func has_quick_repairs() -> bool:
	return get_radiator_damage() >= 0.05

func show_menu() -> void:
	clear()
	label("PAUSA · RALLY")
	button("Neumáticos · Inventario y cambios", show_inventory)
	button("Reparaciones rápidas", show_quick_repairs)
	button("Pedir rescate", request_rescue)
	button("Abandonar etapa", abandon_stage)
	button("Reanudar", toggle)

func show_quick_repairs() -> void:
	clear()
	label("REPARACIONES RÁPIDAS")
	var rad_damage := get_radiator_damage()
	var pct := roundi(rad_damage * 100.0)
	label("Estado del radiador: Daño al %d%% (Salud: %d%%)" % [pct, 100 - pct])
	if rad_damage >= 0.70:
		button("Reparación de radiador (Daño %d%% → 50%% · +1:00 min y restablecer coche)" % pct, repair_radiator)
	elif rad_damage >= 0.05:
		button("Reparación de radiador (Daño %d%% → 0%% · +1:00 min y restablecer coche)" % pct, repair_radiator)
	else:
		label("El radiador no presenta daños significativos. No requiere reparación.")
	button("Volver a pausa", show_menu)
	button("Reanudar", toggle)

func repair_radiator() -> void:
	if not modal.visible or not allowed():
		return
	toggle()
	session.on_quick_repair_radiator_requested()

func request_rescue() -> void:
	if not modal.visible or not allowed():
		return
	toggle()
	session.on_vehicle_reset_requested()

func abandon_stage() -> void:
	if not modal.visible or not allowed():
		return
	toggle()
	session.retire_competition_player()

func description(tire: Dictionary) -> String:
	var state: Dictionary = tire.state
	var compound := "Lluvia" if tire.compound_id == "gravel_wet" else "Normal"
	return "#%d %s · desgaste %.1f%% · daño térmico %.1f%% · %.0f °C" % [int(tire.id), compound, float(state.get("wear_fraction", 0.0)) * 100.0, float(state.get("thermal_damage_fraction", 0.0)) * 100.0, float(state.get("tread_c", 0.0))]

func show_inventory() -> void:
	clear()
	session.vehicle.sync_tire_inventory()
	var inventory = session.vehicle.tire_inventory
	label("NEUMÁTICOS · Elige la rueda montada y un repuesto disponible")
	for i in 4:
		var wheel := i
		button(("▶ " if selected_wheel == i else "") + ["Delantera izquierda", "Delantera derecha", "Trasera izquierda", "Trasera derecha"][i] + " · " + description(inventory.mounted[i]), func(): selected_wheel = wheel; show_inventory())
	label("Repuestos: %d/%d · Carga: %.0f kg" % [inventory.spares.size(), inventory.capacity, inventory.spares.size() * float(RallyTireCompound.load_catalog().inventory.wheel_mass_kg)])
	spare_picker = OptionButton.new()
	content.add_child(spare_picker)
	for spare in inventory.spares:
		spare_picker.add_item(description(spare), int(spare.id))
	keep_removed = CheckButton.new()
	keep_removed.text = "Guardar la rueda retirada para reutilizarla (desmarcar para descartarla)"
	keep_removed.button_pressed = true
	content.add_child(keep_removed)
	var actions := HBoxContainer.new()
	content.add_child(actions)
	if not inventory.spares.is_empty():
		button("Cambiar rueda", exchange, actions)
		button("Descartar repuesto seleccionado", discard, actions)
	else:
		label("No quedan repuestos a bordo.")
	if session.may_service_tires() and inventory.spares.size() < inventory.capacity:
		button("Cargar repuesto nuevo de grava normal (servicio)", func(): load_spare("gravel_normal"))
		button("Cargar repuesto nuevo de lluvia (servicio)", func(): load_spare("gravel_wet"))
	label(notice)
	button("Volver a pausa", show_menu)
	button("Reanudar", toggle)

func exchange() -> void:
	var id := spare_picker.get_selected_id()
	if session.vehicle.exchange_tire(selected_wheel, id, keep_removed.button_pressed):
		notice = "Rueda cambiada. La condición de cada neumático se conserva."
		persist()
	show_inventory()

func discard() -> void:
	if session.vehicle.discard_spare(spare_picker.get_selected_id()):
		notice = "Repuesto descartado: se ha actualizado la masa del coche."
		persist()
	show_inventory()

func load_spare(compound: String) -> void:
	var vehicle = session.vehicle
	if session.may_service_tires() and vehicle.tire_inventory.spares.size() < vehicle.tire_inventory.capacity:
		vehicle.tire_inventory.spares.append(vehicle.tire_inventory.item(compound, vehicle.fresh_tire_state(compound)))
		vehicle.apply_tire_inventory()
		persist()
	show_inventory()

func persist() -> void:
	session._save_mounted_tire_condition()
	if session.event_manager != null:
		session.event_manager.save()
