extends CanvasLayer

signal results_workshop_closed
var opened_from_results := false

const HudPanelsScript := preload("res://scripts/rally/formula_hud_panels.gd")
const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _TelemetrySidebarScene := preload("res://ui/screens/pause/pause_telemetry_sidebar.tscn")
const _WorkshopScript := preload("res://scripts/rally/rally_service_workshop.gd")

# Variables públicas y de contrato
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
var ambient_temp_label: Label
var track_temp_label: Label
var telemetry_panel: PanelContainer
var telemetry_vbox: VBoxContainer
var content_panel: PanelContainer
var footer_nav_hint: Label
var current_view: String = "menu"

var wheel_action_sound: AudioStreamPlayer
var _pending_rescue_on_resume: bool = false


func _process(_delta: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var target_size := Vector2(
		minf(1350.0, maxf(viewport_size.x - 32.0, 640.0)),
		minf(775.0, maxf(viewport_size.y - 24.0, 480.0))
	)
	if modal.custom_minimum_size != target_size:
		modal.custom_minimum_size = target_size
	modal.position = (viewport_size - modal.size) * 0.5
	pause_button.position = Vector2(viewport_size.x - 150, 12)
	pause_button.visible = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	wheel_action_sound = AudioStreamPlayer.new()
	wheel_action_sound.volume_db = -5.0
	wheel_action_sound.stream = preload("res://sounds/rally_service/ClicksSmall.mclick2.wav")
	add_child(wheel_action_sound)

	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.theme = _Theme.get_menu_theme()
	add_child(screen)

	backdrop = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = _Tokens.get_color("bg_overlay")
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.visible = false
	screen.add_child(backdrop)

	pause_button = Button.new()
	pause_button.text = "PAUSA · ESC"
	_Theme.apply_tone_button(pause_button, "chrome", 15, 16, 8)
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	pause_button.size = Vector2(140, 36)
	pause_button.visible = false
	pause_button.disabled = true
	pause_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_button.pressed.connect(toggle)
	screen.add_child(pause_button)

	modal = PanelContainer.new()
	screen.add_child(modal)
	modal.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	modal.custom_minimum_size = Vector2(1350, 775)
	modal.add_theme_stylebox_override("panel", _Theme.make_flat_panel("bg_shell", "border_card", 1))
	modal.hide()
	var pause_sound := AudioStreamPlayer.new()
	pause_sound.volume_db = -5.0
	add_child(pause_sound)
	modal.visibility_changed.connect(func() -> void:
		pause_sound.stream = preload("res://sounds/rally_service/WindowOpen.wav") if modal.visible else preload("res://sounds/rally_service/WindowClose.wav")
		pause_sound.play()
	)

	_build_modal_skeleton()


func _build_modal_skeleton() -> void:
	var c_header := _Tokens.get_color("bg_header")
	var c_well := _Tokens.get_color("bg_well")
	var c_border := _Tokens.get_color("border_card")
	var c_text := _Tokens.get_color("text_primary")
	var c_muted := _Tokens.get_color("text_muted")
	var c_accent := _Tokens.get_color("accent_rally")
	var r := _Tokens.get_radius("default")

	var root_margin := MarginContainer.new()
	root_margin.add_theme_constant_override("margin_left", 20)
	root_margin.add_theme_constant_override("margin_right", 20)
	root_margin.add_theme_constant_override("margin_top", 14)
	root_margin.add_theme_constant_override("margin_bottom", 14)
	modal.add_child(root_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	root_margin.add_child(root_vbox)

	# 1. Cabecera
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_header, c_border, 1, r, 14, 8))
	root_vbox.add_child(header_panel)

	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 14)
	header_panel.add_child(header_hbox)

	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 2)
	header_hbox.add_child(title_vbox)

	header_title = Label.new()
	header_title.text = "PAUSA · COMPETICIÓN · RALLY"
	header_title.add_theme_font_override("font", _Tokens.get_font("title"))
	header_title.add_theme_font_size_override("font_size", 22)
	header_title.add_theme_color_override("font_color", c_text)
	title_vbox.add_child(header_title)

	header_subtitle = Label.new()
	header_subtitle.add_theme_font_override("font", _Tokens.get_font("medium"))
	header_subtitle.add_theme_font_size_override("font_size", 10)
	header_subtitle.add_theme_color_override("font_color", c_muted)
	title_vbox.add_child(header_subtitle)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	var temp_hbox := HBoxContainer.new()
	temp_hbox.add_theme_constant_override("separation", 14)
	temp_hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_hbox.add_child(temp_hbox)

	ambient_temp_label = _add_header_temp_item(temp_hbox, "AMB")
	var temp_sep := ColorRect.new()
	temp_sep.custom_minimum_size = Vector2(1, 16)
	temp_sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	temp_sep.color = _Tokens.get_color("border_subtle")
	temp_hbox.add_child(temp_sep)
	track_temp_label = _add_header_temp_item(temp_hbox, "PISTA")

	var badge_box := PanelContainer.new()
	badge_box.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_well, c_border, 1, r, 12, 4))
	header_hbox.add_child(badge_box)

	var badge_vbox := VBoxContainer.new()
	badge_vbox.add_theme_constant_override("separation", 1)
	badge_box.add_child(badge_vbox)

	badge_top = Label.new()
	badge_top.text = "ESTADO DE PRUEBA"
	badge_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_top.add_theme_font_override("font", _Tokens.get_font("subtitle"))
	badge_top.add_theme_font_size_override("font_size", 11)
	badge_top.add_theme_color_override("font_color", c_muted)
	badge_vbox.add_child(badge_top)

	badge_bottom = Label.new()
	badge_bottom.text = "EN PAUSA"
	badge_bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_bottom.add_theme_font_override("font", _Tokens.get_font("data_bold_tight"))
	badge_bottom.add_theme_font_size_override("font_size", 12)
	badge_bottom.add_theme_color_override("font_color", c_accent)
	badge_vbox.add_child(badge_bottom)

	# 2. Cuerpo dividido: PauseTelemetrySidebar + Panel derecho de acciones
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 12)
	root_vbox.add_child(body_hbox)

	var sidebar := _TelemetrySidebarScene.instantiate()
	body_hbox.add_child(sidebar)
	telemetry_panel = sidebar as PanelContainer
	telemetry_vbox = sidebar.telemetry_vbox

	content_panel = PanelContainer.new()
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_panel.add_theme_stylebox_override("panel", _Theme.make_panel_from_preset("panel.window"))
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

	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	content_scroll.add_child(content)

	# 3. Pie de página
	var footer_panel := PanelContainer.new()
	footer_panel.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(c_header, c_border, 1, r, 14, 6))
	root_vbox.add_child(footer_panel)

	var footer_hbox := HBoxContainer.new()
	footer_panel.add_child(footer_hbox)

	footer_nav_hint = Label.new()
	footer_nav_hint.text = "[ W/S / FLECHAS ] NAVEGAR  ·  [ ENTER ] SELECCIONAR  ·  [ ESC ] REANUDAR"
	footer_nav_hint.add_theme_font_override("font", _Tokens.get_font("medium"))
	footer_nav_hint.add_theme_font_size_override("font_size", 10)
	footer_nav_hint.add_theme_color_override("font_color", Color(c_muted, 0.8))
	footer_hbox.add_child(footer_nav_hint)


func _input(event: InputEvent) -> void:
	if (event.is_action_pressed("ui_cancel") or event.is_action_pressed(InputBindings.UI_BACK_TO_MENU)) and not event.is_echo():
		if modal.visible:
			if current_view == "inventory":
				for child in content.get_children():
					if child.has_method("cancel_transfer") and child.cancel_transfer():
						get_viewport().set_input_as_handled()
						return
			toggle()
			get_viewport().set_input_as_handled()
		elif allowed():
			toggle()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	_input(event)


func allowed() -> bool:
	var tuner: Variant = session.get("tire_tuner") if session != null else null
	var tuner_open: bool = tuner != null and (tuner as Object).has_method("is_open") and bool((tuner as Object).call("is_open"))
	return session != null and session.session_ready and not session.awaiting_setup and not session.stage_transition_running and not session.competition.complete and not tuner_open and (session.garage_panel == null or not session.garage_panel.visible)


func open_from_results() -> void:
	if modal.visible or get_tree().paused:
		return
	opened_from_results = true
	session.vehicle.ensure_tire_inventory()
	get_tree().paused = true
	modal.show()
	backdrop.show()
	show_inventory()


func mark_service_change() -> void:
	if not opened_from_results:
		_pending_rescue_on_resume = true


func toggle() -> void:
	if opened_from_results:
		opened_from_results = false
		_pending_rescue_on_resume = false
		modal.hide()
		backdrop.hide()
		clear()
		get_tree().paused = false
		results_workshop_closed.emit()
		return
	if modal.visible:
		var should_rescue := _pending_rescue_on_resume
		_pending_rescue_on_resume = false
		modal.hide()
		backdrop.hide()
		pause_button.hide()
		clear()
		get_tree().paused = false
		var _pause_out := get_node_or_null("/root/RallyMusic")
		if _pause_out != null and _pause_out.has_method("on_pause_closed"):
			_pause_out.call("on_pause_closed")
		if session != null and session.get("pacenotes") != null:
			session.pacenotes.on_pause(false)
		if should_rescue and session != null and session.has_method("on_vehicle_reset_requested"):
			session.on_vehicle_reset_requested()
		return
	if not allowed() or get_tree().paused:
		return
	_pending_rescue_on_resume = false
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
	show_inventory()


func clear() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()


func label(text: String) -> void:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if text.begins_with("PAUSA") or text.begins_with("NEUMÁTICOS") or text.begins_with("REPARACIONES") or text.begins_with("OPCIONES") or text.begins_with("DIAGNÓSTICO"):
		node.add_theme_font_override("font", _Tokens.get_font("subtitle"))
		node.add_theme_font_size_override("font_size", 15)
		node.add_theme_color_override("font_color", _Tokens.get_color("accent_rally"))
	else:
		node.add_theme_font_override("font", _Tokens.get_font("regular"))
		node.add_theme_font_size_override("font_size", 11)
		node.add_theme_color_override("font_color", _Tokens.get_color("text_primary"))
	content.add_child(node)


func button(text: String, callback: Callable, parent: Node = null, custom_sound: bool = false) -> void:
	var node := Button.new()
	if custom_sound:
		node.set_meta("custom_button_sound", true)
	node.text = text
	node.pressed.connect(callback)
	node.custom_minimum_size = Vector2(0, 36)

	if text == "Reanudar" or text.begins_with("Cambiar rueda") or text.begins_with("Reparación de radiador"):
		_Theme.apply_tone_button(node, "gold", 16, 20, 8)
	elif text.begins_with("Abandonar etapa") or text.begins_with("Descartar"):
		_Theme.apply_tone_button(node, "danger", 15, 16, 8)
	elif text.begins_with("Pedir rescate"):
		_Theme.apply_tone_button(node, "caution", 15, 16, 8)
	else:
		_Theme.apply_tone_button(node, "chrome", 15, 16, 8)

	(parent if parent != null else content).add_child(node)


func _add_hint_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = "   ℹ " + text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_override("font", _Tokens.get_font("regular"))
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(_Tokens.get_color("text_muted"), 0.75))
	content.add_child(lbl)


func get_radiator_damage() -> float:
	if session != null:
		var v: Variant = session.get("vehicle")
		if v != null and v.get("simulation") != null and v.simulation.get("thermal_model") != null:
			return float(v.simulation.thermal_model.radiator_damage)
	return 0.0


func has_quick_repairs() -> bool:
	return get_radiator_damage() >= 0.05


func show_menu() -> void:
	current_view = "menu"
	if telemetry_panel != null:
		telemetry_panel.visible = true
	clear()
	_update_header("PAUSA · COMPETICIÓN · RALLY", "GESTIÓN DEL VEHÍCULO Y OPCIONES EN TRAMO")
	_update_telemetry_panel()

	label("OPCIONES DISPONIBLES")
	button("Reanudar", toggle)
	button("Reparaciones · Taller 3D e inventario", show_inventory)
	if has_quick_repairs():
		_add_hint_label("Radiador dañado: disponible en el taller 3D.")
	button("Pedir rescate", request_rescue)
	_add_hint_label("Reubica el vehículo sobre el trazado oficial (+30 s penalización fija).")
	button("Abandonar etapa", abandon_stage)
	_add_hint_label("Retirada oficial de la especial (DNF). Aplica reenganche (+300 s) para continuar el rally.")


func show_quick_repairs() -> void:
	show_inventory()
	content.get_child(0)._category("radiator", false)


func repair_radiator() -> void:
	if not modal.visible or not allowed():
		return
	if session.on_quick_repair_radiator_requested():
		mark_service_change()
	toggle()


func request_rescue() -> void:
	if not modal.visible or not allowed():
		return
	_pending_rescue_on_resume = false
	toggle()
	session.on_vehicle_reset_requested()


func abandon_stage() -> void:
	if not modal.visible or not allowed():
		return
	_pending_rescue_on_resume = false
	toggle()
	session.retire_competition_player()


func description(tire: Dictionary) -> String:
	var state: Dictionary = tire.state
	var compound := _compound_label(str(tire.compound_id), true)
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
	var workshop := _WorkshopScript.new()
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
	var is_pool: bool = session.vehicle.tire_inventory != null and session.vehicle.tire_inventory.has_method("is_pool_mode") and bool(session.vehicle.tire_inventory.is_pool_mode())
	if session.may_service_tires() and session.vehicle.tire_inventory.spares.size() < session.vehicle.tire_inventory.capacity:
		if is_pool:
			if not session.vehicle.tire_inventory.service_stock.is_empty():
				var row := HBoxContainer.new()
				content.add_child(row)
				for stock_td in session.vehicle.tire_inventory.service_stock:
					var sd: Dictionary = stock_td
					var sid := int(sd.get("id", 0))
					var scid := str(sd.get("compound_id", ""))
					if not is_compound_allowed_for_session(scid):
						continue
					button("+ #%d %s" % [sid, _compound_label(scid, true)], func(): load_spare_from_stock(sid), row)
		else:
			var row := HBoxContainer.new()
			content.add_child(row)
			for entry in (get_session_allowed_compound_ids() if not get_session_allowed_compound_ids().is_empty() else RallyTireCompound.compound_ids(RallyTireCompound.load_catalog())):
				var cid := str(entry)
				button("+ " + _compound_label(cid), func(): load_spare(cid), row)
	if not opened_from_results:
		_add_minimal_damage_strip()
	var nav := HBoxContainer.new()
	nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_theme_constant_override("separation", 10)
	content.add_child(nav)
	if opened_from_results:
		button("Volver a resultados", toggle, nav)
	else:
		button("Reanudar", toggle, nav)
		var nav_spacer := Control.new()
		nav_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav.add_child(nav_spacer)
		button("Pedir rescate (+30 s)", request_rescue, nav)
		button("Abandonar etapa (+300 s)", abandon_stage, nav)


func _add_minimal_damage_strip() -> void:
	var strip := HBoxContainer.new()
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 20)
	content.add_child(strip)

	for item in _collect_hud_damage_metrics():
		var key := str(item["key"])
		var ratio := clampf(float(item["ratio"]), 0.0, 1.0)
		var col: Color = HudPanelsScript.damage_icon_color(ratio)

		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		strip.add_child(cell)

		var icon_path := str(HudPanelsScript.DAMAGE_ICON_PATHS.get(key, ""))
		if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
			var icon := TextureRect.new()
			icon.texture = load(icon_path) as Texture2D
			icon.custom_minimum_size = Vector2(20, 20)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.modulate = col
			cell.add_child(icon)

		var name_lbl := Label.new()
		name_lbl.text = str(item["label"])
		name_lbl.add_theme_font_override("font", _Tokens.get_font("medium"))
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", _Tokens.get_color("text_muted"))
		cell.add_child(name_lbl)

		var pct_lbl := Label.new()
		pct_lbl.text = "%d%%" % roundi(ratio * 100.0)
		pct_lbl.add_theme_font_override("font", _Tokens.get_font("data_bold_tight"))
		pct_lbl.add_theme_font_size_override("font_size", 13)
		pct_lbl.add_theme_color_override("font_color", col)
		cell.add_child(pct_lbl)


func _collect_hud_damage_metrics() -> Array[Dictionary]:
	var v: Variant = session.get("vehicle") if session != null else null
	var sim: Variant = v.get("simulation") if v != null else null
	var tm: Variant = sim.get("thermal_model") if sim != null else null
	var pm: Variant = sim.get("powertrain_model") if sim != null else null
	var pub: Dictionary = v.get("published_state") if v != null and v.get("published_state") is Dictionary else {}
	var pub_dmg: Dictionary = pub.get("damage", {})
	var pub_eng: Dictionary = pub.get("engine", {})
	var wheels: Array = pub.get("wheels", [])

	var eng_dmg := float(tm.engine_damage) if tm != null and tm.get("engine_damage") != null else float(pub_dmg.get("engine", pub_eng.get("engine_damage", 0.0)))
	var rad_dmg := float(tm.radiator_damage) if tm != null and tm.get("radiator_damage") != null else float(pub_dmg.get("radiator", pub_eng.get("radiator_damage", 0.0)))
	var trans_dmg := float(pm.transmission_damage) if pm != null and pm.get("transmission_damage") != null else float(pub_dmg.get("transmission", 0.0))

	var worst_align := 0.0
	var brake_sum := 0.0
	var brake_count := 0
	var worst_wheel := 0.0

	if not wheels.is_empty():
		for wheel_var in wheels:
			if not (wheel_var is Dictionary):
				continue
			var wheel: Dictionary = wheel_var
			worst_align = maxf(worst_align, float(wheel.get("alignment_collision_damage", 0.0)))
			var b_col := clampf(float(wheel.get("brake_collision_loss", 0.0)), 0.0, 1.0)
			var b_wear := clampf(float(wheel.get("brake_wear_fraction", 0.0)), 0.0, 1.0)
			brake_sum += 1.0 - (1.0 - b_col) * (1.0 - b_wear)
			brake_count += 1
			var is_puncture := (
				float(wheel.get("carcass_failure", 0.0)) >= 1.0
				or float(wheel.get("leak_per_second", 0.0)) > 0.0
				or float(wheel.get("pressure_loss_fraction", 0.0)) > 0.85
			)
			worst_wheel = 1.0 if is_puncture else maxf(worst_wheel, maxf(float(wheel.get("wear_fraction", 0.0)), float(wheel.get("rim_deformation", 0.0))))
	elif v != null and v.get("tire_inventory") != null and v.tire_inventory.get("mounted") != null:
		var align_arr: Array = sim.alignment_collision_damage if sim != null and sim.get("alignment_collision_damage") != null else []
		var brake_arr: Array = sim.brake_collision_loss if sim != null and sim.get("brake_collision_loss") != null else []
		for i in v.tire_inventory.mounted.size():
			if i < align_arr.size():
				worst_align = maxf(worst_align, float(align_arr[i]))
			if i < brake_arr.size():
				brake_sum += clampf(float(brake_arr[i]), 0.0, 1.0)
				brake_count += 1
			var st: Dictionary = v.tire_inventory.mounted[i].get("state", {})
			if float(st.get("leak_per_second", 0.0)) > 0.0 or float(st.get("pressure_loss_fraction", 0.0)) > 0.85:
				worst_wheel = 1.0
			else:
				worst_wheel = maxf(worst_wheel, maxf(float(st.get("wear_fraction", 0.0)), float(st.get("rim_deformation", 0.0))))

	var brake_dmg := (brake_sum / float(brake_count)) if brake_count > 0 else 0.0
	return [
		{"key": "engine", "label": "MOTOR", "ratio": eng_dmg},
		{"key": "radiator", "label": "RADIADOR", "ratio": rad_dmg},
		{"key": "transmission", "label": "TRANS.", "ratio": trans_dmg},
		{"key": "steering", "label": "DIRECCIÓN", "ratio": worst_align},
		{"key": "wheel", "label": "RUEDAS", "ratio": worst_wheel},
		{"key": "brake", "label": "FRENOS", "ratio": brake_dmg},
	]


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
		_finish_wheel_action()
	show_inventory()


func discard() -> void:
	if spare_picker == null or spare_picker.item_count == 0:
		return
	var id := spare_picker.get_selected_id()
	if session != null and session.get("vehicle") != null and session.vehicle.discard_spare(id):
		notice = "Repuesto descartado: se ha actualizado la masa del coche."
		_finish_wheel_action()
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
	var wheel_names: Array[String] = ["delantera izquierda", "delantera derecha", "trasera izquierda", "trasera derecha"]

	if src_type == "spare" and target_type == "mounted":
		var dropped_compound := spare_compound_for_id(src_id)
		if not dropped_compound.is_empty() and not is_compound_allowed_for_session(dropped_compound):
			notice = "Compuesto no permitido en este evento: " + dropped_compound
			show_inventory()
			return
		var keep: bool = keep_removed.button_pressed if keep_removed != null else true
		if vehicle.exchange_tire(target_index, src_id, keep):
			selected_wheel = target_index
			notice = "Rueda %s sustituida con éxito por el repuesto #%d." % [wheel_names[target_index], src_id]
			_finish_wheel_action()
		show_inventory()
		return

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
			notice = "Neumáticos rotados: %s ⇄ %s." % [wheel_names[src_idx], wheel_names[target_index]]
			_finish_wheel_action()
		show_inventory()
		return

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
				notice = "Rueda %s guardada en el maletero y sustituida por repuesto #%d." % [wheel_names[src_idx], spare_to_use]
				_finish_wheel_action()
		else:
			notice = "No hay repuestos en el maletero para montar en su lugar."
		show_inventory()
		return

	if src_type == "spare" and target_type == "bin":
		if vehicle.discard_spare(src_id):
			notice = "Repuesto #%d descartado en ruta (-18 kg). Se ha actualizado la masa." % src_id
			_finish_wheel_action()
		show_inventory()
		return

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
				notice = "Rueda %s dañada descartada en ruta (-18 kg). Repuesto #%d montado." % [wheel_names[src_idx], spare_to_use]
				_finish_wheel_action()
		else:
			notice = "¡No puedes descartar una rueda en uso sin un repuesto disponible en el maletero!"
		show_inventory()
		return


func _finish_wheel_action() -> void:
	persist()
	if modal.visible and not opened_from_results:
		mark_service_change()
		wheel_action_sound.play()


func get_session_allowed_compound_ids() -> Array:
	if session != null and session.has_method("get_session_allowed_compound_ids"):
		return session.get_session_allowed_compound_ids()
	return []


func get_session_compound_label_overrides() -> Dictionary:
	if session != null and session.has_method("get_session_compound_label_overrides"):
		return session.get_session_compound_label_overrides()
	return {}


func _compound_label(compound_id: String, short: bool = false) -> String:
	return RallyTireCompound.compound_label(compound_id, short, get_session_compound_label_overrides())


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


func load_spare_from_stock(tire_id: int) -> void:
	if session == null or session.get("vehicle") == null:
		return
	var vehicle = session.vehicle
	if vehicle.tire_inventory == null or not session.may_service_tires():
		return
	var td: Dictionary = vehicle.tire_inventory.find_tire(tire_id)
	if td.is_empty():
		return
	var scid := str(td.get("compound_id", ""))
	if not is_compound_allowed_for_session(scid):
		notice = "Compuesto no permitido en este evento: " + scid
		show_inventory()
		return
	if vehicle.tire_inventory.move_tire(tire_id, "spares"):
		vehicle.apply_tire_inventory()
		notice = "Rueda #%d movida del parque al maletero." % tire_id
		persist()
	show_inventory()


func load_spare(compound: String) -> void:
	if session == null or session.get("vehicle") == null:
		return
	if not is_compound_allowed_for_session(compound):
		notice = "Compuesto no permitido en este evento: " + compound
		show_inventory()
		return
	var vehicle = session.vehicle
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
	_update_header_temperatures()


func _add_header_temp_item(parent: HBoxContainer, title: String) -> Label:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 6)
	item.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(item)

	var key_lbl := Label.new()
	key_lbl.text = title
	key_lbl.add_theme_font_override("font", _Tokens.get_font("medium"))
	key_lbl.add_theme_font_size_override("font_size", 11)
	key_lbl.add_theme_color_override("font_color", _Tokens.get_color("text_muted"))
	item.add_child(key_lbl)

	var val_lbl := Label.new()
	val_lbl.text = "—"
	val_lbl.add_theme_font_override("font", _Tokens.get_font("data_bold_tight"))
	val_lbl.add_theme_font_size_override("font_size", 13)
	val_lbl.add_theme_color_override("font_color", _Tokens.get_color("text_primary"))
	item.add_child(val_lbl)
	return val_lbl


func _update_header_temperatures() -> void:
	var amb_text := "—"
	var track_text := "—"
	if session != null:
		var ew: Variant = session.get("event_weather")
		var v: Variant = session.get("vehicle")
		var sim: Variant = v.get("simulation") if v != null else null
		var tm: Variant = sim.get("thermal_model") if sim != null else null
		var has_ambient := false
		var amb_c := 0.0

		if ew != null and ew.get("current_blend") is Dictionary:
			var blend: Dictionary = ew.current_blend
			if not blend.is_empty() and blend.has("air_c"):
				amb_c = float(blend["air_c"])
				has_ambient = true
		if not has_ambient and tm != null and tm.get("ambient_temperature_c") != null:
			amb_c = float(tm.ambient_temperature_c)
			has_ambient = true
		if has_ambient:
			amb_text = "%d°C" % roundi(amb_c)

		if ew != null and ew.has_method("surface_temperature_at_vehicle"):
			var surf: Variant = ew.call("surface_temperature_at_vehicle")
			if surf is Dictionary and bool((surf as Dictionary).get("ok", false)):
				track_text = "%d°C" % roundi(float((surf as Dictionary).get("celsius", 0.0)))
		if track_text == "—" and has_ambient:
			track_text = "%d°C" % roundi(amb_c)

	if ambient_temp_label != null:
		ambient_temp_label.text = amb_text
	if track_temp_label != null:
		track_temp_label.text = track_text


func _update_telemetry_panel() -> void:
	if telemetry_panel != null and telemetry_panel.has_method("populate"):
		telemetry_panel.populate(session, _compound_label)
