extends CanvasLayer

signal results_workshop_closed
var opened_from_results := false

# =============================================================================
# CONSTANTES VISUALES — SISTEMA DE DISEÑO MOTORSPORT MINIMALISTA (FLAT PRECISION)
# =============================================================================

# 2.2. Estandarización Tipográfica (Sin Serif)
const FONT := preload("res://fonts/montserrat/Montserrat-Regular.ttf")
const BOLD := preload("res://fonts/montserrat/Montserrat-Bold.ttf")
const DIN := preload("res://fonts/D-DIN.ttf")
const DIN_BOLD := preload("res://fonts/D-DIN-Bold.ttf")
const FONT_TITLE := preload("res://fonts/montserrat/Montserrat-Bold.ttf")
const RallyHeldPartPreviewScript := preload("res://scripts/rally/rally_held_part_preview.gd")

# 2.3. Paleta Workbench Motorsport (Ventana Pausa / Inventario)
const WB_BG_SHELL := Color("#090e15")
const WB_BG_HEADER := Color("#0d141e")
const WB_BG_FOOTER := Color("#0d141e")
const WB_BG_TAB_INACTIVE := Color("#111822")
const WB_BG_TAB_ACTIVE := Color("#1a2636")
const WB_BG_CONTENT := Color("#1a2636")
const WB_BG_CARD := Color("#223246")
const WB_BG_CARD_HOVER := Color("#2a3d54")
const WB_BG_WELL := Color("#0c141e")
const WB_BORDER_SUBTLE := Color(1.0, 1.0, 1.0, 0.10)
const WB_BORDER_HOVER := Color(1.0, 1.0, 1.0, 0.20)
const WB_BORDER_FOCUS := Color("#ffffff")
const WB_BORDER_ACCENT := Color("#e5a93c")
const WB_SLIDER_TRACK := Color("#0c141e")
const WB_SLIDER_FILL := Color("#4a7bb0")
const WB_SLIDER_THUMB := Color("#eaf2fa")
const WB_SLIDER_STEPPER := Color("#25364b")
const WB_TEXT_TITLE := Color("#f0f5fa")
const WB_TEXT_LABEL := Color("#9ab0c7")
const WB_TEXT_DATA := Color("#ffffff")
const WB_TEXT_ACCENT := Color("#e5a93c")

const BG_BASE := WB_BG_SHELL
const BG_SURFACE := WB_BG_CONTENT
const BG_HOVER := WB_BG_CARD_HOVER
const BG_CARD := WB_BG_CARD
const BORDER_SUBTLE := WB_BORDER_SUBTLE
const BORDER_FOCUS := WB_BORDER_FOCUS
const TEXT_PRIMARY := WB_TEXT_TITLE
const TEXT_MUTED := WB_TEXT_LABEL
const ACCENT_RALLY := WB_BORDER_ACCENT
const ACCENT_ALERT := Color("#f59e0b")
const STATUS_DANGER := Color("#ef4444")
const STATUS_SUCCESS := Color("#22c55e")

# Aliases de compatibilidad interna
const C_BACK := WB_BG_SHELL
const C_GLASS := WB_BG_HEADER
const C_GLASS_DEEP := WB_BG_WELL
const C_RIM := WB_BORDER_SUBTLE
const C_CHROME_TEXT := WB_TEXT_TITLE
const C_CHROME_DIM := WB_TEXT_LABEL
const C_BLUE := WB_SLIDER_FILL
const C_BLUE_DEEP := Color("#16283b")

const C_FACE := WB_BG_CONTENT
const C_FACE_HI := WB_BG_CARD_HOVER
const C_FACE_LO := WB_BG_CARD
const C_FIELD := WB_BG_WELL
const C_HI := WB_BORDER_HOVER
const C_LIGHT := WB_BORDER_SUBTLE
const C_SHADOW := Color(0.0, 0.0, 0.0, 0.25)
const C_DARK := Color("#060a0f")
const C_TEXT := WB_TEXT_TITLE
const C_DIM := WB_TEXT_LABEL
const C_GOLD := ACCENT_RALLY
const C_GOLD_HI := Color("#f8df9e")
const C_ROSE := STATUS_DANGER
const C_SEL := WB_BG_CARD_HOVER
const C_GREEN := STATUS_SUCCESS

# =============================================================================
# VARIABLES PÚBLICAS Y DE CONTRATO
# =============================================================================

var session: Node
var screen: Control
var backdrop: ColorRect
var modal: PanelContainer
var content: VBoxContainer
var selected_wheel: int = 0
var spare_picker: OptionButton
var keep_removed: CheckButton
var notice: String = ""
var pause_button: Button

# Subcomponentes internos de layout
var header_title: Label
var header_subtitle: Label
var badge_top: Label
var badge_bottom: Label
var telemetry_panel: PanelContainer
var telemetry_vbox: VBoxContainer
var content_panel: PanelContainer
var footer_nav_hint: Label
var current_view: String = "menu"


# =============================================================================
# CICLO DE VIDA Y PROCESO
# =============================================================================

func _process(_delta: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	modal.position = (viewport_size - modal.size) * 0.5
	pause_button.position = Vector2(viewport_size.x - 150, 12)
	pause_button.visible = not modal.visible and allowed()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)

	# Velo oscuro atmosférico para ocluir interferencias de la HUD durante la pausa
	backdrop = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.06, 0.08, 0.88)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.visible = false
	screen.add_child(backdrop)

	# Botón de pausa en la esquina superior derecha de la HUD (estilo Aero Glass)
	pause_button = Button.new()
	pause_button.text = "PAUSA · ESC"
	_style_chrome_button(pause_button)
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	pause_button.size = Vector2(140, 36)
	pause_button.pressed.connect(toggle)
	screen.add_child(pause_button)

	# Ventana modal central en estilo Aero Glass + Motorsport
	modal = PanelContainer.new()
	screen.add_child(modal)
	modal.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	modal.custom_minimum_size = Vector2(1080, 620)
	modal.add_theme_stylebox_override("panel", _make_glass_style(10, Color(C_GLASS, 0.98), Color(C_RIM, 0.45)))
	modal.hide()

	_build_modal_skeleton()


# =============================================================================
# ESTRUCTURA BASE DEL MODAL (AERO GLASS + MOTORSPORT)
# =============================================================================

func _build_modal_skeleton() -> void:
	var root_margin := MarginContainer.new()
	root_margin.add_theme_constant_override("margin_left", 20)
	root_margin.add_theme_constant_override("margin_right", 20)
	root_margin.add_theme_constant_override("margin_top", 14)
	root_margin.add_theme_constant_override("margin_bottom", 14)
	modal.add_child(root_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	root_margin.add_child(root_vbox)

	# 1. Cabecera Aero Glass
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", _make_glass_style(8, Color(C_GLASS, 0.95), Color(C_RIM, 0.35)))
	root_vbox.add_child(header_panel)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 14)
	header_margin.add_theme_constant_override("margin_right", 14)
	header_margin.add_theme_constant_override("margin_top", 8)
	header_margin.add_theme_constant_override("margin_bottom", 8)
	header_panel.add_child(header_margin)

	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 14)
	header_margin.add_child(header_hbox)

	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 2)
	header_hbox.add_child(title_vbox)

	header_title = Label.new()
	header_title.text = "PAUSA · COMPETICIÓN · RALLY"
	header_title.add_theme_font_override("font", FONT_TITLE)
	header_title.add_theme_font_size_override("font_size", 17)
	header_title.add_theme_color_override("font_color", C_CHROME_TEXT)
	title_vbox.add_child(header_title)

	header_subtitle = Label.new()
	header_subtitle.add_theme_font_override("font", FONT)
	header_subtitle.add_theme_font_size_override("font_size", 11)
	header_subtitle.add_theme_color_override("font_color", C_CHROME_DIM)
	title_vbox.add_child(header_subtitle)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	var badge_box := PanelContainer.new()
	badge_box.add_theme_stylebox_override("panel", _make_glass_style(6, C_GLASS_DEEP, Color(C_RIM, 0.30)))
	header_hbox.add_child(badge_box)

	var badge_margin := MarginContainer.new()
	badge_margin.add_theme_constant_override("margin_left", 12)
	badge_margin.add_theme_constant_override("margin_right", 12)
	badge_margin.add_theme_constant_override("margin_top", 4)
	badge_margin.add_theme_constant_override("margin_bottom", 4)
	badge_box.add_child(badge_margin)

	var badge_vbox := VBoxContainer.new()
	badge_vbox.add_theme_constant_override("separation", 1)
	badge_margin.add_child(badge_vbox)

	badge_top = Label.new()
	badge_top.text = "ESTADO DE PRUEBA"
	badge_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_top.add_theme_font_override("font", FONT_TITLE)
	badge_top.add_theme_font_size_override("font_size", 9)
	badge_top.add_theme_color_override("font_color", C_CHROME_DIM)
	badge_vbox.add_child(badge_top)

	badge_bottom = Label.new()
	badge_bottom.text = "EN PAUSA"
	badge_bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_bottom.add_theme_font_override("font", DIN_BOLD)
	badge_bottom.add_theme_font_size_override("font_size", 13)
	badge_bottom.add_theme_color_override("font_color", C_GOLD)
	badge_vbox.add_child(badge_bottom)

	# 2. Cuerpo dividido: Panel izquierdo de telemetría + Panel derecho de acciones
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 12)
	root_vbox.add_child(body_hbox)

	# Panel Izquierdo: Telemetría y diagnóstico en vivo
	telemetry_panel = PanelContainer.new()
	telemetry_panel.custom_minimum_size = Vector2(280, 0)
	telemetry_panel.add_theme_stylebox_override("panel", _make_classic_panel_style())
	body_hbox.add_child(telemetry_panel)

	var tel_margin := MarginContainer.new()
	tel_margin.add_theme_constant_override("margin_left", 12)
	tel_margin.add_theme_constant_override("margin_right", 12)
	tel_margin.add_theme_constant_override("margin_top", 10)
	tel_margin.add_theme_constant_override("margin_bottom", 10)
	telemetry_panel.add_child(tel_margin)

	var tel_scroll := ScrollContainer.new()
	tel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tel_margin.add_child(tel_scroll)

	telemetry_vbox = VBoxContainer.new()
	telemetry_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	telemetry_vbox.add_theme_constant_override("separation", 8)
	tel_scroll.add_child(telemetry_vbox)

	# Panel Derecho: Contenedor interactivo principal (content vive aquí para compatibilidad)
	content_panel = PanelContainer.new()
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_panel.add_theme_stylebox_override("panel", _make_classic_panel_style())
	body_hbox.add_child(content_panel)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 14)
	content_margin.add_theme_constant_override("margin_right", 14)
	content_margin.add_theme_constant_override("margin_top", 10)
	content_margin.add_theme_constant_override("margin_bottom", 10)
	content_panel.add_child(content_margin)

	var content_scroll := ScrollContainer.new()
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_margin.add_child(content_scroll)

	# content es el VBoxContainer de contrato público donde residen los botones
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	content_scroll.add_child(content)

	# 3. Pie de página Aero Glass
	var footer_panel := PanelContainer.new()
	footer_panel.add_theme_stylebox_override("panel", _make_glass_style(8, Color(C_GLASS, 0.95), Color(C_RIM, 0.35)))
	root_vbox.add_child(footer_panel)

	var footer_margin := MarginContainer.new()
	footer_margin.add_theme_constant_override("margin_left", 14)
	footer_margin.add_theme_constant_override("margin_right", 14)
	footer_margin.add_theme_constant_override("margin_top", 6)
	footer_margin.add_theme_constant_override("margin_bottom", 6)
	footer_panel.add_child(footer_margin)

	var footer_hbox := HBoxContainer.new()
	footer_margin.add_child(footer_hbox)

	footer_nav_hint = Label.new()
	footer_nav_hint.text = "[ W/S / FLECHAS ] NAVEGAR  ·  [ ENTER ] SELECCIONAR  ·  [ ESC ] REANUDAR"
	footer_nav_hint.add_theme_font_override("font", FONT)
	footer_nav_hint.add_theme_font_size_override("font_size", 11)
	footer_nav_hint.add_theme_color_override("font_color", Color(C_CHROME_DIM, 0.8))
	footer_hbox.add_child(footer_nav_hint)


# =============================================================================
# ENTRADAS DE TECLADO Y MANDO
# =============================================================================

func _input(event: InputEvent) -> void:
	if (event.is_action_pressed("ui_cancel") or event.is_action_pressed(InputBindings.UI_BACK_TO_MENU)) and not event.is_echo():
		if modal.visible:
			if current_view == "inventory":
				for child in content.get_children():
					if child.has_method("cancel_transfer") and child.cancel_transfer():
						get_viewport().set_input_as_handled()
						return
			if current_view != "menu" and not opened_from_results:
				show_menu()
			else:
				toggle()
			get_viewport().set_input_as_handled()
		elif allowed():
			toggle()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	_input(event)


func allowed() -> bool:
	return session != null and session.session_ready and not session.awaiting_setup and not session.stage_transition_running and not session.competition.complete and (session.garage_panel == null or not session.garage_panel.visible)


func open_from_results() -> void:
	if modal.visible or get_tree().paused:
		return
	opened_from_results = true
	session.vehicle.ensure_tire_inventory()
	get_tree().paused = true
	modal.show()
	backdrop.show()
	show_inventory()


func toggle() -> void:
	if opened_from_results:
		opened_from_results = false
		modal.hide()
		backdrop.hide()
		clear()
		get_tree().paused = false
		results_workshop_closed.emit()
		return
	if modal.visible:
		modal.hide()
		backdrop.hide()
		pause_button.show()
		get_tree().paused = false
		var _pause_out := get_node_or_null("/root/RallyMusic")
		if _pause_out != null and _pause_out.has_method("on_pause_closed"):
			_pause_out.call("on_pause_closed")
		if session != null and session.get("pacenotes") != null:
			session.pacenotes.on_pause(false)
		return
	if not allowed() or get_tree().paused:
		return
	if session != null and session.get("vehicle") != null:
		session.vehicle.ensure_tire_inventory()
		session.vehicle.sync_tire_inventory()
	get_tree().paused = true
	if session != null and session.get("pacenotes") != null:
		session.pacenotes.on_pause(true)
	var _pause_in := get_node_or_null("/root/RallyMusic")
	if _pause_in != null and _pause_in.has_method("on_pause_opened"):
		_pause_in.call("on_pause_opened")
	modal.show()
	backdrop.show()
	pause_button.hide()
	show_menu()


func clear() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()


func label(text: String) -> void:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if text.begins_with("PAUSA") or text.begins_with("NEUMÁTICOS") or text.begins_with("REPARACIONES") or text.begins_with("OPCIONES") or text.begins_with("DIAGNÓSTICO"):
		node.add_theme_font_override("font", BOLD)
		node.add_theme_font_size_override("font_size", 12)
		node.add_theme_color_override("font_color", C_GOLD)
	else:
		node.add_theme_font_override("font", FONT)
		node.add_theme_font_size_override("font_size", 12)
		node.add_theme_color_override("font_color", C_TEXT)
	content.add_child(node)


func button(text: String, callback: Callable, parent: Node = null) -> void:
	var node := Button.new()
	node.text = text
	node.pressed.connect(callback)
	node.custom_minimum_size = Vector2(0, 36)

	if text == "Reanudar" or text.begins_with("Cambiar rueda") or text.begins_with("Reparación de radiador"):
		_style_gold_button(node)
	elif text == "Abandonar etapa" or text.begins_with("Descartar"):
		_style_danger_button(node)
	elif text == "Pedir rescate":
		_style_caution_button(node)
	else:
		_style_chrome_button(node)

	(parent if parent != null else content).add_child(node)


func _add_hint_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = "   ℹ " + text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_override("font", FONT)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(C_CHROME_DIM, 0.75))
	content.add_child(lbl)


# =============================================================================
# REPARACIONES RÁPIDAS (LÓGICA Y ESTADO)
# =============================================================================

func get_radiator_damage() -> float:
	if session != null:
		var v: Variant = session.get("vehicle")
		if v != null and v.get("simulation") != null and v.simulation.get("thermal_model") != null:
			return float(v.simulation.thermal_model.radiator_damage)
	return 0.0


func has_quick_repairs() -> bool:
	return get_radiator_damage() >= 0.05


# =============================================================================
# VISTA 1: MENÚ PRINCIPAL DE PAUSA
# =============================================================================

func show_menu() -> void:
	current_view = "menu"
	if telemetry_panel != null:
		telemetry_panel.visible = true
	clear()
	_update_header("PAUSA · COMPETICIÓN · RALLY", "GESTIÓN DEL VEHÍCULO Y OPCIONES EN TRAMO")
	_update_telemetry_panel()

	label("OPCIONES DISPONIBLES")
	
	# Acción primaria: Reanudar carrera
	button("Reanudar", toggle)

	# Submenú 1: Neumáticos e inventario
	button("Reparaciones · Taller 3D e inventario", show_inventory)

	# Submenú 2: Reparaciones rápidas
	var has_dmg := has_quick_repairs()
	if has_dmg:
		_add_hint_label("Radiador dañado: disponible en el taller 3D.")

	# Acción de rescate (penalización moderada)
	button("Pedir rescate", request_rescue)
	_add_hint_label("Reubica el vehículo sobre el trazado oficial (+15 s penalización fija).")

	# Acción destructiva: Abandonar etapa
	button("Abandonar etapa", abandon_stage)
	_add_hint_label("Retirada oficial de la especial (DNF). Aplica reenganche (+300 s) para continuar el rally.")


# =============================================================================
# VISTA 2: MENÚ DE REPARACIONES RÁPIDAS
# =============================================================================

func show_quick_repairs() -> void:
	show_inventory()
	content.get_child(0)._category("radiator")


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


# =============================================================================
# VISTA 3: MENÚ DE NEUMÁTICOS E INVENTARIO
# =============================================================================

func description(tire: Dictionary) -> String:
	var state: Dictionary = tire.state
	var compound := str(RallyTireCompound.get_compound(RallyTireCompound.load_catalog(), str(tire.compound_id)).get("short_label", tire.compound_id))
	var puncture := ""
	if float(state.get("leak_per_second", 0.0)) > 0.0:
		puncture = " / pinchado" if float(state.get("pressure_loss_fraction", 0.0)) > 0.85 else " / fuga"
	if float(state.get("rim_deformation", 0.0)) > 0.005:
		puncture += " / aro deformado"
	return "#%d %s · desgaste %.1f%% · daño térmico %.1f%% · %.0f °C" % [int(tire.id), compound, float(state.get("wear_fraction", 0.0)) * 100.0, float(state.get("thermal_damage_fraction", 0.0)) * 100.0, float(state.get("tread_c", 0.0))] + puncture


func show_inventory() -> void:
	current_view = "inventory"
	telemetry_panel.visible = false
	clear()
	_update_header("REPARACIONES · TALLER 3D", "RUEDAS · RADIADOR · MALETERA")
	session.vehicle.sync_tire_inventory()
	var workshop := preload("res://scripts/rally/rally_service_workshop.gd").new()
	workshop.host = self
	content.add_child(workshop)
	keep_removed = CheckButton.new()
	keep_removed.button_pressed = true
	keep_removed.hide()
	content.add_child(keep_removed)
	spare_picker = OptionButton.new()
	spare_picker.hide()
	for spare in session.vehicle.tire_inventory.spares:
		spare_picker.add_item(description(spare), int(spare.id))
	content.add_child(spare_picker)
	if session.may_service_tires() and session.vehicle.tire_inventory.spares.size() < session.vehicle.tire_inventory.capacity:
		var row := HBoxContainer.new()
		content.add_child(row)
		for entry in (get_session_allowed_compound_ids() if not get_session_allowed_compound_ids().is_empty() else RallyTireCompound.compound_ids(RallyTireCompound.load_catalog())):
			var cid := str(entry)
			button("+ " + cid, func(): load_spare(cid), row)
	var nav := HBoxContainer.new()
	content.add_child(nav)
	if opened_from_results:
		button("Volver a resultados", toggle, nav)
	else:
		button("Volver a pausa", show_menu, nav)
		button("Reanudar", toggle, nav)


func exchange() -> void:
	if spare_picker == null or spare_picker.item_count == 0:
		return
	var id := spare_picker.get_selected_id()
	var spare_compound := spare_compound_for_id(id)
	if not spare_compound.is_empty() and not is_compound_allowed_for_session(spare_compound):
		notice = "Compuesto no permitido en este evento: " + spare_compound
		show_inventory()
		return
	var keep: bool = keep_removed.button_pressed if keep_removed != null else true
	if session != null and session.get("vehicle") != null and session.vehicle.exchange_tire(selected_wheel, id, keep):
		notice = "Rueda cambiada. La condición de cada neumático se conserva."
		persist()
	show_inventory()


func discard() -> void:
	if spare_picker == null or spare_picker.item_count == 0:
		return
	var id := spare_picker.get_selected_id()
	if session != null and session.get("vehicle") != null and session.vehicle.discard_spare(id):
		notice = "Repuesto descartado: se ha actualizado la masa del coche."
		persist()
	show_inventory()


func _on_slot_clicked(slot_type: String, index: int, tire_data: Dictionary) -> void:
	if slot_type == "mounted":
		selected_wheel = index
		var wheel_names: Array[String] = ["delantera izquierda", "delantera derecha", "trasera izquierda", "trasera derecha"]
		notice = "Rueda %s seleccionada." % wheel_names[index]
		show_inventory()
	elif slot_type == "spare":
		if spare_picker != null and spare_picker.item_count > index:
			spare_picker.select(index)
			notice = "Repuesto #%d seleccionado. Haz clic en 'Cambiar rueda' o arrástralo a una posición." % int(tire_data.get("id", 0))


func _on_drop_action(data: Dictionary, target_type: String, target_index: int) -> void:
	if session == null or session.get("vehicle") == null:
		return
	var vehicle = session.vehicle
	var inventory = vehicle.tire_inventory
	if inventory == null:
		return

	var src_type: String = str(data.get("source_type", ""))
	var src_idx: int = int(data.get("index", 0))
	var src_tire: Dictionary = data.get("tire", {})
	var src_id: int = int(src_tire.get("id", 0))

	# Caso 1: Arrastrar repuesto a rueda montada (sustitución directa)
	if src_type == "spare" and target_type == "mounted":
		var dropped_compound := spare_compound_for_id(src_id)
		if not dropped_compound.is_empty() and not is_compound_allowed_for_session(dropped_compound):
			notice = "Compuesto no permitido en este evento: " + dropped_compound
			show_inventory()
			return
		var keep: bool = keep_removed.button_pressed if keep_removed != null else true
		if vehicle.exchange_tire(target_index, src_id, keep):
			selected_wheel = target_index
			var wheel_names: Array[String] = ["delantera izquierda", "delantera derecha", "trasera izquierda", "trasera derecha"]
			notice = "Rueda %s sustituida con éxito por el repuesto #%d." % [wheel_names[target_index], src_id]
			persist()
		show_inventory()
		return

	# Caso 2: Rotar ruedas montadas (arrastrar esquina A sobre esquina B)
	if src_type == "mounted" and target_type == "mounted":
		if src_idx != target_index and src_idx >= 0 and src_idx < inventory.mounted.size() and target_index >= 0 and target_index < inventory.mounted.size():
			vehicle.sync_tire_inventory()
			var tmp: Dictionary = inventory.mounted[src_idx]
			inventory.mounted[src_idx] = inventory.mounted[target_index]
			inventory.mounted[target_index] = tmp
			vehicle.apply_tire_inventory()
			if vehicle.get("simulation") != null and vehicle.simulation.get("tire_model") != null:
				vehicle.simulation.tire_model.reset_patch(src_idx)
				vehicle.simulation.tire_model.reset_patch(target_index)
			selected_wheel = target_index
			var wheel_names: Array[String] = ["delantera izquierda", "delantera derecha", "trasera izquierda", "trasera derecha"]
			notice = "Neumáticos rotados: %s ⇄ %s." % [wheel_names[src_idx], wheel_names[target_index]]
			persist()
		show_inventory()
		return

	# Caso 3: Arrastrar rueda montada hacia el maletero (guardar en maletero y montar repuesto)
	if src_type == "mounted" and target_type == "spare":
		if not inventory.spares.is_empty():
			var spare_to_use: int = int(inventory.spares[clampi(target_index, 0, inventory.spares.size() - 1)].id)
			var case3_compound := spare_compound_for_id(spare_to_use)
			if not case3_compound.is_empty() and not is_compound_allowed_for_session(case3_compound):
				notice = "Compuesto no permitido en este evento: " + case3_compound
				show_inventory()
				return
			if vehicle.exchange_tire(src_idx, spare_to_use, true):
				selected_wheel = src_idx
				var wheel_names: Array[String] = ["delantera izquierda", "delantera derecha", "trasera izquierda", "trasera derecha"]
				notice = "Rueda %s guardada en el maletero y sustituida por repuesto #%d." % [wheel_names[src_idx], spare_to_use]
				persist()
		else:
			notice = "No hay repuestos en el maletero para montar en su lugar."
		show_inventory()
		return

	# Caso 4: Descartar repuesto en el cajón de desecho
	if src_type == "spare" and target_type == "bin":
		if vehicle.discard_spare(src_id):
			notice = "Repuesto #%d descartado en ruta (-18 kg). Se ha actualizado la masa." % src_id
			persist()
		show_inventory()
		return

	# Caso 5: Descartar rueda montada directamente en el cajón de desecho
	if src_type == "mounted" and target_type == "bin":
		if not inventory.spares.is_empty():
			var spare_to_use: int = int(inventory.spares[0].id)
			var case5_compound := spare_compound_for_id(spare_to_use)
			if not case5_compound.is_empty() and not is_compound_allowed_for_session(case5_compound):
				notice = "Compuesto no permitido en este evento: " + case5_compound
				show_inventory()
				return
			if vehicle.exchange_tire(src_idx, spare_to_use, false):
				selected_wheel = src_idx
				var wheel_names: Array[String] = ["delantera izquierda", "delantera derecha", "trasera izquierda", "trasera derecha"]
				notice = "Rueda %s dañada descartada en ruta (-18 kg). Repuesto #%d montado." % [wheel_names[src_idx], spare_to_use]
				persist()
		else:
			notice = "¡No puedes descartar una rueda en uso sin un repuesto disponible en el maletero!"
		show_inventory()
		return


func get_session_allowed_compound_ids() -> Array:
	if session != null and session.has_method("get_session_allowed_compound_ids"):
		return session.get_session_allowed_compound_ids()
	return []


func spare_compound_for_id(spare_id: int) -> String:
	if session == null or session.get("vehicle") == null:
		return ""
	var inventory = session.vehicle.tire_inventory
	if inventory == null:
		return ""
	for spare in inventory.spares:
		if int((spare as Dictionary).get("id", -1)) == spare_id:
			return str((spare as Dictionary).get("compound_id", ""))
	return ""


func is_compound_allowed_for_session(compound_id: String) -> bool:
	var allowed := get_session_allowed_compound_ids()
	if allowed.is_empty():
		return true
	return allowed.has(compound_id)


func load_spare(compound: String) -> void:
	if session == null or session.get("vehicle") == null:
		return
	if not is_compound_allowed_for_session(compound):
		notice = "Compuesto no permitido en este evento: " + compound
		show_inventory()
		return
	var vehicle = session.vehicle
	# Pool de 10: sin reposición, solo mover entre maletera/parque en servicio.
	if vehicle.tire_inventory != null and vehicle.tire_inventory.has_method("is_pool_mode") and vehicle.tire_inventory.is_pool_mode():
		notice = "Pool de 10: sin reposición en tramo. Gestiona tus %d ruedas restantes." % vehicle.tire_inventory.total_count()
		show_inventory()
		return
	if session.may_service_tires() and vehicle.tire_inventory.spares.size() < vehicle.tire_inventory.capacity:
		vehicle.tire_inventory.spares.append(vehicle.tire_inventory.item(compound, vehicle.fresh_tire_state(compound)))
		vehicle.apply_tire_inventory()
		persist()
	show_inventory()


func persist() -> void:
	if session == null:
		return
	if session.has_method("_save_mounted_tire_condition"):
		session._save_mounted_tire_condition()
	if session.event_manager != null:
		session.event_manager.save()


# =============================================================================
# PANEL DE TELEMETRÍA Y DIAGNÓSTICO EN VIVO
# =============================================================================

func _update_header(title_text: String, subtitle_text: String) -> void:
	if header_title != null:
		header_title.text = title_text
	if header_subtitle != null:
		header_subtitle.text = subtitle_text
		header_subtitle.visible = not subtitle_text.is_empty()
	if badge_bottom != null:
		if session != null and session.get("course") != null and session.course.get("elapsed_s") != null:
			var s: float = float(session.course.elapsed_s)
			badge_bottom.text = "%d:%02d.%03d · PAUSADO" % [int(s) / 60, int(s) % 60, int(s * 1000.0) % 1000]
		else:
			badge_bottom.text = "EN PAUSA"


func _update_telemetry_panel() -> void:
	if telemetry_vbox == null:
		return
	for child in telemetry_vbox.get_children():
		child.queue_free()

	if session == null:
		return

	var v: Variant = session.get("vehicle")
	var sim: Variant = v.get("simulation") if v != null else null
	var tm: Variant = sim.get("thermal_model") if sim != null else null

	# 1. Tarjeta Térmica / Radiador
	var rad_dmg := float(tm.radiator_damage) if tm != null and tm.get("radiator_damage") != null else 0.0
	var water_t := float(tm.water_temperature_c) if tm != null and tm.get("water_temperature_c") != null else 85.0
	var oil_t := float(tm.oil_temperature_c) if tm != null and tm.get("oil_temperature_c") != null else 90.0
	var fuel_l := float(tm.fuel_remaining_litres) if tm != null and tm.get("fuel_remaining_litres") != null else 12.0

	var rad_pct := roundi(rad_dmg * 100.0)
	var rad_title := "SALUD: %d%% [ÓPTIMO]" % (100 - rad_pct) if rad_dmg < 0.05 else ("DAÑO: %d%% [FUGA]" % rad_pct if rad_dmg < 0.70 else "DAÑO CRÍTICO: %d%%" % rad_pct)
	var rad_col := C_GREEN if rad_dmg < 0.05 else (C_GOLD if rad_dmg < 0.70 else C_ROSE)
	var rad_sub := "Agua: %.0f °C · Aceite: %.0f °C · Combustible: %.1f L" % [water_t, oil_t, fuel_l]
	telemetry_vbox.add_child(_create_telemetry_card("Circuito Térmico", rad_title, rad_sub, rad_col))

	# 2. Tarjeta de Neumáticos (4 esquinas)
	if v != null and v.get("tire_inventory") != null and v.tire_inventory.get("mounted") != null:
		var inv = v.tire_inventory
		var mounted: Array = inv.mounted
		var tire_card := PanelContainer.new()
		tire_card.add_theme_stylebox_override("panel", _make_card_style())
		var t_vbox := VBoxContainer.new()
		t_vbox.add_theme_constant_override("separation", 4)
		tire_card.add_child(t_vbox)

		var t_title := Label.new()
		t_title.text = "ESTADO DE NEUMÁTICOS"
		t_title.add_theme_font_override("font", FONT_TITLE)
		t_title.add_theme_font_size_override("font_size", 10)
		t_title.add_theme_color_override("font_color", C_CHROME_DIM)
		t_vbox.add_child(t_title)

		var corners := ["FL", "FR", "RL", "RR"]
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 4)
		t_vbox.add_child(grid)

		for i in mini(4, mounted.size()):
			var tire: Dictionary = mounted[i]
			var st: Dictionary = tire.get("state", {})
			var wear := float(st.get("wear_fraction", 0.0)) * 100.0
			var has_leak := float(st.get("leak_per_second", 0.0)) > 0.0
			var has_rim := float(st.get("rim_deformation", 0.0)) > 0.005
			var c_stat := "OK"
			var col := C_GREEN
			if has_leak:
				c_stat = "FUGA"
				col = C_ROSE
			elif has_rim:
				c_stat = "ARO"
				col = C_ROSE
			elif wear >= 50.0:
				c_stat = "%.0f%%" % wear
				col = C_GOLD

			var lbl := Label.new()
			lbl.text = "%s: %s [%s]" % [corners[i], str(RallyTireCompound.get_compound(RallyTireCompound.load_catalog(), str(tire.get("compound_id", ""))).get("short_label", tire.get("compound_id", ""))), c_stat]
			lbl.add_theme_font_override("font", DIN_BOLD)
			lbl.add_theme_font_size_override("font_size", 12)
			lbl.add_theme_color_override("font_color", col)
			grid.add_child(lbl)

		var spares_info := Label.new()
		if inv.has_method("is_pool_mode") and inv.is_pool_mode():
			spares_info.text = "Repuestos: %d de %d · Quedan %d / 10 en el rally" % [inv.spares.size(), inv.capacity, inv.total_count()]
		else:
			spares_info.text = "Repuestos disponibles: %d de %d" % [inv.spares.size(), inv.capacity]
		spares_info.add_theme_font_override("font", FONT)
		spares_info.add_theme_font_size_override("font_size", 11)
		spares_info.add_theme_color_override("font_color", C_CHROME_DIM)
		t_vbox.add_child(spares_info)

		telemetry_vbox.add_child(tire_card)

	# 3. Tarjeta de Carrera / Tiempo
	var course = session.get("course")
	var comp = session.get("competition")
	var elapsed_s := float(course.elapsed_s) if course != null and course.get("elapsed_s") != null else 0.0
	var elapsed_str := "%d:%02d.%03d" % [int(elapsed_s) / 60, int(elapsed_s) % 60, int(elapsed_s * 1000.0) % 1000]
	var pen_ms := int(comp.player_penalty_ms) if comp != null and comp.get("player_penalty_ms") != null else 0
	var pen_str := "Sin penalizaciones" if pen_ms <= 0 else "+%.0f s penalización acumulada" % (float(pen_ms) / 1000.0)
	var pen_col := C_DIM if pen_ms <= 0 else C_ROSE
	telemetry_vbox.add_child(_create_telemetry_card("Cronómetro de Etapa", elapsed_str, pen_str, C_BLUE, pen_col))


func _create_telemetry_card(title_text: String, prim_text: String, sub_text: String, prim_col: Color = C_TEXT, sub_col: Color = C_DIM) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)

	var l_t := Label.new()
	l_t.text = title_text.to_upper()
	l_t.add_theme_font_override("font", FONT_TITLE)
	l_t.add_theme_font_size_override("font_size", 10)
	l_t.add_theme_color_override("font_color", C_CHROME_DIM)
	box.add_child(l_t)

	var l_p := Label.new()
	l_p.text = prim_text
	l_p.add_theme_font_override("font", DIN_BOLD)
	l_p.add_theme_font_size_override("font_size", 15)
	l_p.add_theme_color_override("font_color", prim_col)
	box.add_child(l_p)

	if not sub_text.is_empty():
		var l_s := Label.new()
		l_s.text = sub_text
		l_s.add_theme_font_override("font", FONT)
		l_s.add_theme_font_size_override("font_size", 10)
		l_s.add_theme_color_override("font_color", sub_col)
		box.add_child(l_s)

	return card


# =============================================================================
# ESTILOS Y HELPERS VISUALES
# =============================================================================

func _make_glass_style(radius: int, fill: Color, rim: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = rim
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.shadow_size = 0
	return s


func _make_classic_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BG_SURFACE
	s.border_color = BORDER_SUBTLE
	s.set_border_width_all(1)
	s.shadow_size = 0
	return s


func _make_card_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BG_CARD
	s.border_color = BORDER_SUBTLE
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.shadow_size = 0
	return s


func _style_gold_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#d49b2f")
	normal.border_color = C_GOLD_HI
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	normal.shadow_size = 0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#e5aa37")
	hover.border_color = Color.WHITE

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#b38020")
	pressed.border_color = C_GOLD

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", BOLD)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color("#0a0e14"))
	btn.add_theme_color_override("font_hover_color", Color("#000000"))
	btn.add_theme_color_override("font_pressed_color", Color("#000000"))
	btn.add_theme_color_override("font_focus_color", Color("#0a0e14"))


func _style_chrome_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = BG_CARD
	normal.border_color = BORDER_SUBTLE
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	normal.shadow_size = 0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = BG_HOVER
	hover.border_color = BORDER_FOCUS

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = BG_BASE
	pressed.border_color = ACCENT_RALLY

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", BOLD)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", ACCENT_RALLY)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)


func _style_caution_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.11, 0.06, 0.90)
	normal.border_color = Color(ACCENT_ALERT, 0.40)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	normal.shadow_size = 0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.20, 0.15, 0.08, 0.95)
	hover.border_color = ACCENT_ALERT

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.08, 0.06, 0.03, 0.95)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", BOLD)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", ACCENT_ALERT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", ACCENT_ALERT)
	btn.add_theme_color_override("font_focus_color", ACCENT_ALERT)


func _style_danger_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.06, 0.08, 0.85)
	normal.border_color = Color(STATUS_DANGER, 0.40)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	normal.shadow_size = 0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.08, 0.10, 0.95)
	hover.border_color = Color("#ff857d")

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.08, 0.04, 0.05, 0.95)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", BOLD)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color("#ff9e97"))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", STATUS_DANGER)
	btn.add_theme_color_override("font_focus_color", Color("#ff9e97"))


func _style_selected_wheel_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = BG_HOVER
	normal.border_color = ACCENT_RALLY
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	normal.shadow_size = 0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.24, 0.32, 0.95)
	hover.border_color = BORDER_FOCUS

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", BOLD)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", ACCENT_RALLY)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", ACCENT_RALLY)
	btn.add_theme_color_override("font_focus_color", ACCENT_RALLY)


func _style_option_button(opt: OptionButton) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_FIELD
	normal.border_color = Color(C_RIM, 0.40)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6

	opt.add_theme_stylebox_override("normal", normal)
	opt.add_theme_stylebox_override("hover", normal)
	opt.add_theme_stylebox_override("pressed", normal)
	opt.add_theme_font_override("font", FONT)
	opt.add_theme_font_size_override("font_size", 12)
	opt.add_theme_color_override("font_color", C_CHROME_TEXT)


# =============================================================================
# COMPONENTES VISUALES Y DE ARRASTRAR Y SOLTAR (SPATIAL TIRE INVENTORY)
# =============================================================================

class WheelGraphic extends Control:
	var tire_compound: String = "gravel_normal"
	var wear_fraction: float = 0.0
	var thermal_damage: float = 0.0
	var leak_rate: float = 0.0
	var pressure_loss: float = 0.0
	var rim_deformation: float = 0.0
	var is_selected: bool = false
	var is_hover_target: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(50, 50)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var center := size * 0.5
		var r_outer: float = minf(size.x, size.y) * 0.46
		var r_rim: float = r_outer * 0.58
		var r_hub: float = r_outer * 0.22

		# 1. Halo exterior de selección o hover
		if is_hover_target:
			draw_arc(center, r_outer + 3.0, 0.0, TAU, 32, Color("#f6d68a"), 3.0, true)
		elif is_selected:
			draw_arc(center, r_outer + 2.0, 0.0, TAU, 32, Color("#e3b23c"), 2.0, true)

		# 2. Neumático (Goma exterior)
		draw_circle(center, r_outer, Color("#131b22"))

		# Color de la banda según desgaste y fuga
		var is_punctured: bool = (leak_rate > 0.0 or pressure_loss > 0.85)
		var tread_col: Color
		if is_punctured:
			tread_col = Color("#ef4444")
		elif wear_fraction >= 0.70:
			tread_col = Color("#f43f5e")
		elif wear_fraction >= 0.35:
			tread_col = Color("#eab308")
		else:
			var details := RallyTireCompound.get_compound(RallyTireCompound.load_catalog(), tire_compound)
			tread_col = Color(str(details.get("visual_tread_color", "#22c55e")))

		draw_arc(center, r_outer - 2.0, 0.0, TAU, 32, tread_col, 4.0, true)

		# Dibujo de la banda / sipes
		var sipes_count: int = int(RallyTireCompound.get_compound(RallyTireCompound.load_catalog(), tire_compound).get("visual_sipes_count", 8))
		for k in sipes_count:
			var ang := (TAU / float(sipes_count)) * float(k)
			var p1 := center + Vector2(cos(ang), sin(ang)) * (r_outer - 4.5)
			var p2 := center + Vector2(cos(ang), sin(ang)) * (r_outer - 0.5)
			draw_line(p1, p2, Color(0.06, 0.09, 0.12, 0.8), 1.5)

		# 3. Rin / Llanta de aleación
		var rim_col: Color
		if rim_deformation >= 0.20:
			rim_col = Color("#dc2626")
		elif rim_deformation > 0.005:
			rim_col = Color("#f97316")
		else:
			rim_col = Color("#cbd5e1")

		if rim_deformation > 0.005:
			var pts := PackedVector2Array()
			var rim_pts := 24
			for k in rim_pts:
				var ang := (TAU / float(rim_pts)) * float(k)
				var radius_var: float = r_rim
				if k % 6 == 0 and rim_deformation >= 0.20:
					radius_var -= r_rim * 0.35
				elif k % 4 == 0:
					radius_var -= r_rim * (rim_deformation * 0.4)
				pts.append(center + Vector2(cos(ang), sin(ang)) * radius_var)
			draw_colored_polygon(pts, Color(0.10, 0.15, 0.20))
			draw_polyline(pts, rim_col, 2.0, true)
		else:
			draw_circle(center, r_rim, Color(0.10, 0.15, 0.20))
			draw_arc(center, r_rim, 0.0, TAU, 28, rim_col, 2.0, true)

		# 5 radios deportivos
		for k in 5:
			var ang := (TAU / 5.0) * float(k)
			var p1 := center + Vector2(cos(ang), sin(ang)) * r_hub
			var p2 := center + Vector2(cos(ang), sin(ang)) * (r_rim - 1.5)
			draw_line(p1, p2, rim_col, 2.0, true)

		# 4. Cubo central y 4 tuercas doradas
		draw_circle(center, r_hub, Color(0.06, 0.09, 0.12))
		draw_arc(center, r_hub, 0.0, TAU, 16, rim_col, 1.0)
		for k in 4:
			var ang := (TAU / 4.0) * float(k) + 0.4
			var nut_pos := center + Vector2(cos(ang), sin(ang)) * (r_hub * 0.6)
			draw_circle(nut_pos, 1.2, Color("#f6d68a"))


class ChassisDiagram extends PanelContainer:
	var panel_ref: Variant

	func _init(p_panel: Variant) -> void:
		panel_ref = p_panel
		custom_minimum_size = Vector2(185, 212)
		add_theme_stylebox_override("panel", panel_ref._make_classic_panel_style())
		_setup_ui()

	func _setup_ui() -> void:
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 6)
		margin.add_theme_constant_override("margin_right", 6)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_bottom", 6)
		add_child(margin)

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 4)
		margin.add_child(vbox)

		var front_lbl := Label.new()
		front_lbl.text = "▲ DIRECCIÓN (FRENTE) ▲"
		front_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		front_lbl.add_theme_font_override("font", panel_ref.BOLD)
		front_lbl.add_theme_font_size_override("font_size", 9)
		front_lbl.add_theme_color_override("font_color", panel_ref.C_RIM)
		vbox.add_child(front_lbl)

		var car_box := PanelContainer.new()
		var c_sb := StyleBoxFlat.new()
		c_sb.bg_color = Color(panel_ref.C_GLASS_DEEP, 0.95)
		c_sb.border_color = Color(panel_ref.C_RIM, 0.45)
		c_sb.set_border_width_all(1)
		c_sb.set_corner_radius_all(8)
		car_box.add_theme_stylebox_override("panel", c_sb)
		car_box.custom_minimum_size = Vector2(165, 134)
		vbox.add_child(car_box)

		var car_margin := MarginContainer.new()
		car_margin.add_theme_constant_override("margin_left", 6)
		car_margin.add_theme_constant_override("margin_right", 6)
		car_margin.add_theme_constant_override("margin_top", 6)
		car_margin.add_theme_constant_override("margin_bottom", 6)
		car_box.add_child(car_margin)

		var car_vbox := VBoxContainer.new()
		car_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		car_vbox.add_theme_constant_override("separation", 2)
		car_margin.add_child(car_vbox)

		var v_name := Label.new()
		v_name.text = "FORD ESCORT RS2000"
		v_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v_name.add_theme_font_override("font", panel_ref.BOLD)
		v_name.add_theme_font_size_override("font_size", 10)
		v_name.add_theme_color_override("font_color", panel_ref.C_GOLD_HI)
		car_vbox.add_child(v_name)

		var v_spec := Label.new()
		v_spec.text = "PROPULSIÓN TRASERA (RWD)\nGRUPO 4 HISTÓRICO"
		v_spec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v_spec.add_theme_font_override("font", panel_ref.FONT)
		v_spec.add_theme_font_size_override("font_size", 8)
		v_spec.add_theme_color_override("font_color", panel_ref.C_CHROME_DIM)
		car_vbox.add_child(v_spec)

		var v_mass := Label.new()
		var mass_kg: float = 1095.0
		if panel_ref.session != null and panel_ref.session.get("vehicle") != null:
			mass_kg = panel_ref.session.vehicle.mass
		v_mass.text = "Masa: %.0f kg" % mass_kg
		v_mass.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v_mass.add_theme_font_override("font", panel_ref.DIN_BOLD)
		v_mass.add_theme_font_size_override("font_size", 11)
		v_mass.add_theme_color_override("font_color", panel_ref.C_GREEN)
		car_vbox.add_child(v_mass)

		var rear_lbl := Label.new()
		rear_lbl.text = "▼ TRACCIÓN (TRASERA) ▼"
		rear_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rear_lbl.add_theme_font_override("font", panel_ref.BOLD)
		rear_lbl.add_theme_font_size_override("font_size", 9)
		rear_lbl.add_theme_color_override("font_color", panel_ref.C_RIM)
		vbox.add_child(rear_lbl)


class WheelSlotControl extends PanelContainer:
	var panel_ref: Variant
	var slot_type: String
	var slot_index: int = 0
	var tire_data: Dictionary = {}
	var is_empty: bool = false
	var wheel_graphic: WheelGraphic
	var title_label: Label
	var compound_label: Label
	var cond_label: Label
	var rim_label: Label

	func _init(p_panel: Variant, p_type: String, p_index: int, p_tire: Dictionary, p_empty: bool = false) -> void:
		panel_ref = p_panel
		slot_type = p_type
		slot_index = p_index
		tire_data = p_tire
		is_empty = p_empty
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0, 88)
		_setup_ui()

	func _setup_ui() -> void:
		var is_sel: bool = (slot_type == "mounted" and panel_ref.selected_wheel == slot_index)
		_update_style(is_sel, false)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_bottom", 6)
		add_child(margin)

		if is_empty:
			var empty_vbox := VBoxContainer.new()
			empty_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			margin.add_child(empty_vbox)
			var lbl := Label.new()
			lbl.text = "MALETERO #%d\n[ ESPACIO LIBRE ]" % (slot_index + 1)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.add_theme_font_override("font", panel_ref.BOLD)
			lbl.add_theme_font_size_override("font_size", 10)
			lbl.add_theme_color_override("font_color", panel_ref.C_CHROME_DIM)
			empty_vbox.add_child(lbl)
			return

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		margin.add_child(hbox)

		wheel_graphic = WheelGraphic.new()
		if not tire_data.is_empty():
			var state: Dictionary = tire_data.get("state", {})
			wheel_graphic.tire_compound = str(tire_data.get("compound_id", "gravel_normal"))
			wheel_graphic.wear_fraction = float(state.get("wear_fraction", 0.0))
			wheel_graphic.thermal_damage = float(state.get("thermal_damage_fraction", 0.0))
			wheel_graphic.leak_rate = float(state.get("leak_per_second", 0.0))
			wheel_graphic.pressure_loss = float(state.get("pressure_loss_fraction", 0.0))
			wheel_graphic.rim_deformation = float(state.get("rim_deformation", 0.0))
			wheel_graphic.is_selected = is_sel
		hbox.add_child(wheel_graphic)

		var info_vbox := VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vbox.add_theme_constant_override("separation", 2)
		hbox.add_child(info_vbox)

		var title_text: String
		if slot_type == "mounted":
			var names: Array[String] = ["FL · DELANT. IZQ", "FR · DELANT. DER", "RL · TRAS. IZQ", "RR · TRAS. DER"]
			title_text = names[slot_index]
		else:
			title_text = "MALETERO #%d (#%d)" % [slot_index + 1, int(tire_data.get("id", 0))]

		var head_box := HBoxContainer.new()
		info_vbox.add_child(head_box)

		title_label = Label.new()
		title_label.text = title_text
		title_label.add_theme_font_override("font", panel_ref.FONT_TITLE)
		title_label.add_theme_font_size_override("font_size", 11)
		title_label.add_theme_color_override("font_color", panel_ref.C_GOLD if is_sel else panel_ref.C_CHROME_TEXT)
		head_box.add_child(title_label)

		var head_sp := Control.new()
		head_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head_box.add_child(head_sp)

		var state: Dictionary = tire_data.get("state", {})
		var compound_info := RallyTireCompound.get_compound(RallyTireCompound.load_catalog(), str(tire_data.get("compound_id", "")))
		var comp_name := str(compound_info.get("label", tire_data.get("compound_id", ""))).to_upper()
		compound_label = Label.new()
		compound_label.text = comp_name
		compound_label.add_theme_font_override("font", panel_ref.DIN_BOLD)
		compound_label.add_theme_font_size_override("font_size", 10)
		compound_label.add_theme_color_override("font_color", Color(str(compound_info.get("visual_tread_color", "#d9d9d9"))))
		head_box.add_child(compound_label)

		var wear_pct := float(state.get("wear_fraction", 0.0)) * 100.0
		var is_punctured: bool = float(state.get("leak_per_second", 0.0)) > 0.0 or float(state.get("pressure_loss_fraction", 0.0)) > 0.85
		cond_label = Label.new()
		if is_punctured:
			cond_label.text = "¡PINCHADO! · Fuga de presión activa"
			cond_label.add_theme_color_override("font_color", panel_ref.C_ROSE)
		else:
			cond_label.text = "Goma: %.0f%% desg · %.0f°C" % [wear_pct, float(state.get("tread_c", 0.0))]
			cond_label.add_theme_color_override("font_color", panel_ref.C_GREEN if wear_pct < 35 else (panel_ref.C_GOLD if wear_pct < 70 else panel_ref.C_ROSE))
		cond_label.add_theme_font_override("font", panel_ref.DIN)
		cond_label.add_theme_font_size_override("font_size", 10)
		info_vbox.add_child(cond_label)

		var rim_def: float = float(state.get("rim_deformation", 0.0))
		rim_label = Label.new()
		if rim_def >= 0.20:
			rim_label.text = "Rin: ¡DEFORMADO! (%.0f%%)" % (rim_def * 100.0)
			rim_label.add_theme_color_override("font_color", panel_ref.C_ROSE)
		elif rim_def > 0.005:
			rim_label.text = "Rin: Golpe (%.0f%%)" % (rim_def * 100.0)
			rim_label.add_theme_color_override("font_color", Color("#f97316"))
		else:
			rim_label.text = "Rin: Óptimo (0% daño)"
			rim_label.add_theme_color_override("font_color", panel_ref.C_CHROME_DIM)
		rim_label.add_theme_font_override("font", panel_ref.DIN)
		rim_label.add_theme_font_size_override("font_size", 9)
		info_vbox.add_child(rim_label)

	func _update_style(selected: bool, hover_drop: bool) -> void:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(5)
		if hover_drop:
			sb.bg_color = Color(panel_ref.C_SEL, 0.95)
			sb.border_color = panel_ref.C_GOLD_HI
			sb.set_border_width_all(2)
		elif selected:
			sb.bg_color = panel_ref.C_SEL
			sb.border_color = panel_ref.C_GOLD
			sb.set_border_width_all(2)
		elif is_empty:
			sb.bg_color = Color(panel_ref.C_FIELD, 0.4)
			sb.border_color = Color(panel_ref.C_SHADOW, 0.8)
			sb.set_border_width_all(1)
		else:
			sb.bg_color = panel_ref.C_FIELD
			sb.border_color = Color(panel_ref.C_RIM, 0.35)
			sb.set_border_width_all(1)
		add_theme_stylebox_override("panel", sb)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			panel_ref._on_slot_clicked(slot_type, slot_index, tire_data)

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if is_empty or tire_data.is_empty():
			return null
		var holder := RallyHeldPartPreviewScript.new()
		holder.custom_minimum_size = Vector2(140, 40)
		holder.size = Vector2(140, 40)
		var preview := PanelContainer.new()
		var p_sb := StyleBoxFlat.new()
		p_sb.bg_color = Color(panel_ref.C_GLASS, 0.95)
		p_sb.border_color = panel_ref.C_GOLD
		p_sb.set_border_width_all(2)
		p_sb.set_corner_radius_all(6)
		preview.add_theme_stylebox_override("panel", p_sb)
		var p_lbl := Label.new()
		var prefix := "🛞 " + ("DELANT. " if slot_index < 2 else "TRAS. ") if slot_type == "mounted" else "🛞 REPUESTO "
		p_lbl.text = prefix + "#%d" % int(tire_data.get("id", 0))
		p_lbl.add_theme_font_override("font", panel_ref.BOLD)
		p_lbl.add_theme_font_size_override("font_size", 11)
		p_lbl.add_theme_color_override("font_color", panel_ref.C_GOLD_HI)
		preview.add_child(p_lbl)
		preview.custom_minimum_size = Vector2(140, 40)
		preview.size = Vector2(140, 40)
		holder.model_view = preview
		# model_view debe entrar al árbol con el holder para que _ready lo centre.
		holder.add_child(preview)
		set_drag_preview(holder)
		return {"source_type": slot_type, "index": slot_index, "tire": tire_data}

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		if not data is Dictionary:
			return false
		var src_type: String = str(data.get("source_type", ""))
		var src_idx: int = int(data.get("index", -1))
		if slot_type == "mounted":
			return (src_type == "spare") or (src_type == "mounted" and src_idx != slot_index)
		elif slot_type == "spare":
			return (src_type == "mounted")
		return false

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if data is Dictionary:
			panel_ref._on_drop_action(data, slot_type, slot_index)


class DiscardBinSlot extends PanelContainer:
	var panel_ref: Variant

	func _init(p_panel: Variant) -> void:
		panel_ref = p_panel
		custom_minimum_size = Vector2(230, 95)
		mouse_filter = Control.MOUSE_FILTER_STOP
		_update_style(false)
		_setup_ui()

	func _setup_ui() -> void:
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_bottom", 6)
		add_child(margin)

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 2)
		margin.add_child(vbox)

		var title := Label.new()
		title.text = "🗑️ DESECHAR EN RUTA"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_override("font", panel_ref.FONT_TITLE)
		title.add_theme_font_size_override("font_size", 11)
		title.add_theme_color_override("font_color", panel_ref.C_ROSE)
		vbox.add_child(title)

		var sub := Label.new()
		sub.text = "Suelta aquí para aligerar (-18 kg)"
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_override("font", panel_ref.DIN_BOLD)
		sub.add_theme_font_size_override("font_size", 9)
		sub.add_theme_color_override("font_color", panel_ref.C_GOLD)
		vbox.add_child(sub)

		var hint := Label.new()
		hint.text = "Arrastra rueda averiada o repuesto inservible"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_override("font", panel_ref.FONT)
		hint.add_theme_font_size_override("font_size", 8)
		hint.add_theme_color_override("font_color", panel_ref.C_CHROME_DIM)
		vbox.add_child(hint)

	func _update_style(hover: bool) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.18, 0.08, 0.10, 0.90) if hover else Color(0.12, 0.05, 0.07, 0.75)
		sb.border_color = panel_ref.C_ROSE if hover else Color(panel_ref.C_ROSE, 0.5)
		sb.set_border_width_all(2 if hover else 1)
		sb.set_corner_radius_all(6)
		add_theme_stylebox_override("panel", sb)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		if not data is Dictionary:
			return false
		var src_type: String = str(data.get("source_type", ""))
		if src_type == "spare":
			return true
		if src_type == "mounted":
			if panel_ref.session != null and panel_ref.session.get("vehicle") != null:
				return not panel_ref.session.vehicle.tire_inventory.spares.is_empty()
		return false

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if data is Dictionary:
			panel_ref._on_drop_action(data, "bin", 0)
