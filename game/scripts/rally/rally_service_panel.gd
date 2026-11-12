extends CanvasLayer
signal confirmed

const FONT_TITLE: Font = preload("res://fonts/montserrat/Montserrat-Bold.ttf")
const FONT_REGULAR: Font = preload("res://fonts/montserrat/Montserrat-Regular.ttf")
const FONT_DATA: Font = preload("res://fonts/D-DIN.ttf")
const FONT_DATA_BOLD: Font = preload("res://fonts/D-DIN-Bold.ttf")
const BG_IMAGE_PATHS: Array[String] = [
	"res://assets/rally/garage/service_repairs_bg.jpg",
	"res://assets/rally/garage/service_repairs_bg_2.jpg"
]

const WB_BG_SHELL := Color("#090e15")
const WB_BG_CONTENT := Color("#1a2636")
const WB_BG_CARD := Color("#223246")
const WB_BG_WELL := Color("#0c141e")
const WB_BORDER_SUBTLE := Color(1.0, 1.0, 1.0, 0.10)
const WB_BORDER_FOCUS := Color("#ffffff")
const WB_TEXT_TITLE := Color("#f0f5fa")
const WB_TEXT_LABEL := Color("#9ab0c7")
const WB_TEXT_DATA := Color("#ffffff")
const ACCENT_RALLY := Color("#e5a93c")
const STATUS_DANGER := Color("#ef4444")
const STATUS_SUCCESS := Color("#22c55e")
const C_BLUE := Color("#60a5fa")

const PARTS := {
	"engine": ["Motor", 45.0],
	"radiator": ["Radiador", 20.0],
	"transmission": ["Transmisión", 35.0],
	"body": ["Carrocería", 15.0],
	"hood": ["Capó", 8.0],
	"trunk": ["Maletero", 8.0],
	"windshield": ["Parabrisas", 10.0],
	"headlight_left": ["Faro izquierdo", 5.0],
	"headlight_right": ["Faro derecho", 5.0]
}
var vehicle
var manager
var rows: Array[Dictionary] = []
var tire_actions: Array[Dictionary] = []
var summary: Label
var time_bar: ProgressBar
var commit: Button
var limit_minutes := 30.0
var penalty_per_minute := 10
var window_key := ""
var cost_inflate := 2
var cost_rim := 5

func _load_bg_texture() -> Texture2D:
	if BG_IMAGE_PATHS.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var path: String = BG_IMAGE_PATHS[rng.randi_range(0, BG_IMAGE_PATHS.size() - 1)]
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null

func _service_costs(window: Dictionary) -> Dictionary:
	# Prioridad: ventana JSON > tire_rules del evento > valores del plan (2/5/1).
	var costs: Dictionary = (window.get("service_costs", {}) as Dictionary).duplicate()
	if costs.is_empty() and manager != null and (manager as RallyEventManager).event_doc.has("tire_rules"):
		costs = (((manager as RallyEventManager).event_doc.get("tire_rules", {}) as Dictionary).get("service_costs", {}) as Dictionary).duplicate()
	return {"inflate": int(costs.get("inflate", 2)), "rim": int(costs.get("rim", 5)), "wheel_change": int(costs.get("wheel_change", 1))}

func open(car, event_manager, window: Dictionary) -> void:
	var music := get_node_or_null("/root/RallyMusic")
	if music != null and music.has_method("on_enter_service"):
		music.call("on_enter_service")
	elif music != null and music.has_method("on_enter_garage"):
		music.call("on_enter_garage")
	elif music != null and music.has_method("play_menu_music"):
		music.call("play_menu_music")
	vehicle = car
	manager = event_manager
	window_key = str(window.get("window_key", ""))
	limit_minutes = maxf(float(window.get("repair_minutes", 30.0)), 0.0)
	penalty_per_minute = maxi(int(window.get("repair_penalty_seconds_per_minute", 10)), 0)
	var costs := _service_costs(window)
	cost_inflate = int(costs.get("inflate", 2))
	cost_rim = int(costs.get("rim", 5))
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS

	var bg_rect := TextureRect.new()
	bg_rect.name = "BackgroundImage"
	bg_rect.texture = _load_bg_texture()
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_rect)

	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.06, 0.09, 0.48)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var modal_card := PanelContainer.new()
	modal_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_card.offset_left = 60
	modal_card.offset_right = -60
	modal_card.offset_top = 32
	modal_card.offset_bottom = -32
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color(WB_BG_CONTENT.r, WB_BG_CONTENT.g, WB_BG_CONTENT.b, 0.92)
	card_sb.border_color = WB_BORDER_SUBTLE
	card_sb.set_border_width_all(1)
	card_sb.set_corner_radius_all(6)
	card_sb.shadow_size = 0
	card_sb.content_margin_left = 24
	card_sb.content_margin_right = 24
	card_sb.content_margin_top = 20
	card_sb.content_margin_bottom = 20
	modal_card.add_theme_stylebox_override("panel", card_sb)
	shade.add_child(modal_card)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)
	modal_card.add_child(panel)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	panel.add_child(header)
	var title := Label.new()
	title.text = "ÁREA DE SERVICIO · REPARACIONES"
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", WB_TEXT_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var weather_label := Label.new()
	weather_label.text = _weather_text()
	weather_label.add_theme_font_override("font", FONT_REGULAR)
	weather_label.add_theme_font_size_override("font_size", 12)
	weather_label.add_theme_color_override("font_color", C_BLUE)
	header.add_child(weather_label)

	var hint := Label.new()
	hint.text = "Marca las piezas a reparar. Pinchazo %d min · Rin %d min · Destalonado irreparable.\nExceso: %d s de penalización por minuto iniciado." % [cost_inflate, cost_rim, penalty_per_minute]
	hint.add_theme_font_override("font", FONT_REGULAR)
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", WB_TEXT_LABEL)
	panel.add_child(hint)

	# Barra gráfica de presupuesto (plan §5).
	time_bar = ProgressBar.new()
	time_bar.max_value = maxf(limit_minutes, 1.0)
	time_bar.value = 0
	time_bar.show_percentage = false
	time_bar.custom_minimum_size = Vector2(0, 12)
	panel.add_child(time_bar)

	var hsplit := HBoxContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.add_theme_constant_override("separation", 20)
	panel.add_child(hsplit)

	var tire_box := VBoxContainer.new()
	tire_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tire_box.add_theme_constant_override("separation", 6)
	var tire_title := Label.new()
	tire_title.text = "RUEDAS Y NEUMÁTICOS"
	tire_title.add_theme_font_override("font", FONT_TITLE)
	tire_title.add_theme_font_size_override("font_size", 13)
	tire_title.add_theme_color_override("font_color", ACCENT_RALLY)
	tire_box.add_child(tire_title)
	var tire_scroll := ScrollContainer.new()
	tire_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tire_box.add_child(tire_scroll)
	var tire_list := VBoxContainer.new()
	tire_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tire_list.add_theme_constant_override("separation", 6)
	tire_scroll.add_child(tire_list)
	hsplit.add_child(tire_box)
	_build_tire_repairs(tire_list)

	var mech_box := VBoxContainer.new()
	mech_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mech_box.add_theme_constant_override("separation", 6)
	var mech_title := Label.new()
	mech_title.text = "MECÁNICA Y CARROCERÍA"
	mech_title.add_theme_font_override("font", FONT_TITLE)
	mech_title.add_theme_font_size_override("font_size", 13)
	mech_title.add_theme_color_override("font_color", ACCENT_RALLY)
	mech_box.add_child(mech_title)
	var mech_scroll := ScrollContainer.new()
	mech_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mech_box.add_child(mech_scroll)
	var mech_list := VBoxContainer.new()
	mech_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mech_list.add_theme_constant_override("separation", 6)
	mech_scroll.add_child(mech_list)
	hsplit.add_child(mech_box)

	var damage: Dictionary = vehicle.damage_snapshot()
	for key in PARTS:
		var amount := float(damage.get(key, 0.0)) if key in ["engine", "radiator", "transmission"] else (1.0 if bool(damage.get("visual", {}).get(key, false)) else 0.0)
		_add_row(mech_list, key, str(PARTS[key][0]), amount, float(PARTS[key][1]))
	for i in 4:
		var code: String = ["DI", "DD", "TI", "TD"][i]
		var wear := float(vehicle.simulation.thermal_model.brake_wear_fraction[i])
		var collision := float(vehicle.simulation.brake_collision_loss[i])
		_add_row(mech_list, "brake_%d" % i, "Freno " + code, 1.0 - (1.0 - wear) * (1.0 - collision), 15.0)
		_add_row(mech_list, "alignment_%d" % i, "Alineación / suspensión " + code, float(vehicle.simulation.alignment_collision_damage[i]), 12.0)
	if rows.is_empty() and tire_actions.is_empty():
		var healthy := Label.new()
		healthy.text = "No hay componentes que necesiten reparación."
		healthy.add_theme_font_override("font", FONT_REGULAR)
		healthy.add_theme_font_size_override("font_size", 12)
		healthy.add_theme_color_override("font_color", STATUS_SUCCESS)
		mech_list.add_child(healthy)

	summary = Label.new()
	summary.add_theme_font_override("font", FONT_DATA_BOLD)
	summary.add_theme_font_size_override("font_size", 13)
	panel.add_child(summary)

	commit = Button.new()
	commit.text = "CONFIRMAR REPARACIONES Y CONTINUAR"
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = ACCENT_RALLY
	btn_normal.border_color = Color("#fff3c4")
	btn_normal.set_border_width_all(1)
	btn_normal.set_corner_radius_all(2)
	btn_normal.content_margin_top = 10
	btn_normal.content_margin_bottom = 10
	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color("#f5b74c")
	commit.add_theme_stylebox_override("normal", btn_normal)
	commit.add_theme_stylebox_override("hover", btn_hover)
	commit.add_theme_stylebox_override("pressed", btn_hover)
	commit.add_theme_font_override("font", FONT_TITLE)
	commit.add_theme_font_size_override("font_size", 13)
	commit.add_theme_color_override("font_color", Color("#090e15"))
	commit.add_theme_color_override("font_hover_color", Color("#000000"))
	commit.pressed.connect(_commit)
	panel.add_child(commit)

	_refresh()
	if not tire_actions.is_empty():
		(tire_actions[0].box as CheckBox).grab_focus()
	elif not rows.is_empty():
		(rows[0].box as CheckBox).grab_focus()
	else:
		commit.grab_focus()

func _weather_text() -> String:
	if manager == null or (manager as RallyEventManager).weather_schedule.is_empty():
		return "CLIMA: —"
	var em := manager as RallyEventManager
	var cur := "—"
	var nxt := "—"
	if em.cursor >= 0 and em.cursor < em.weather_schedule.size():
		var cw := RallyWeatherScheduler.get_stage_dominant_weather(em.weather_schedule[em.cursor])
		cur = "%s %s %0.0f°C" % [str(cw.get("icon", "")), str(cw.get("name", "")), float(cw.get("temp_c", 18.0))]
	if em.cursor + 1 >= 0 and em.cursor + 1 < em.stage_forecasts.size():
		var nw: Dictionary = (em.stage_forecasts[em.cursor + 1] as Dictionary).get("weather", {})
		nxt = "%s %s %0.0f°C (~80%%)" % [str(nw.get("icon", "")), str(nw.get("name", "")), float(nw.get("temp_c", 15.0))]
	elif em.cursor + 1 >= 0 and em.cursor + 1 < em.weather_schedule.size():
		var nw2 := RallyWeatherScheduler.get_stage_dominant_weather(em.weather_schedule[em.cursor + 1])
		nxt = "%s %s %0.0f°C" % [str(nw2.get("icon", "")), str(nw2.get("name", "")), float(nw2.get("temp_c", 15.0))]
	return "ACTUAL: %s  |  SIGUIENTE: %s" % [cur, nxt]

func _build_tire_repairs(list: VBoxContainer) -> void:
	if vehicle == null or vehicle.tire_inventory == null:
		return
	vehicle.sync_tire_inventory()
	var inv: RallyTireInventory = vehicle.tire_inventory
	var wheel_names := ["DELANTERA IZQ (FL)", "DELANTERA DER (FR)", "TRASERA IZQ (RL)", "TRASERA DER (RR)"]
	for i in mini(inv.mounted.size(), 4):
		var tire: Dictionary = inv.mounted[i]
		_add_tire_row(list, wheel_names[i], tire)
	for i in inv.spares.size():
		var tire: Dictionary = inv.spares[i]
		_add_tire_row(list, "MALETERA #%d" % (i + 1), tire)
	# Permitir reparar también las ruedas del parque (pinchazo o rin) antes de montarlas en garaje.
	for i in inv.service_stock.size():
		var tire: Dictionary = inv.service_stock[i]
		_add_tire_row(list, "PARQUE #%d" % (i + 1), tire)

func _tire_status(inv: RallyTireInventory, tire: Dictionary) -> String:
	if inv.is_carcass_destroyed(tire):
		return "DESTALONADO (IRREPARABLE)"
	if inv.is_punctured(tire) and inv.is_rim_damaged(tire):
		return "PINCHADO + RIN DAÑADO"
	if inv.is_punctured(tire):
		return "PINCHADO"
	if inv.is_rim_damaged(tire):
		return "RIN DAÑADO"
	return "OK"

func _add_tire_row(list: VBoxContainer, slot_label: String, tire: Dictionary) -> void:
	var inv: RallyTireInventory = vehicle.tire_inventory
	var tire_id := int(tire.get("id", 0))
	var cid := str(tire.get("compound_id", "gravel_normal"))
	var state: Dictionary = tire.get("state", {})
	var wear := float(state.get("wear_fraction", 0.0)) * 100.0
	var status := _tire_status(inv, tire)
	var is_dest := inv.is_carcass_destroyed(tire)
	var is_punc := inv.is_punctured(tire)
	var is_rim := inv.is_rim_damaged(tire)
	var row_box := PanelContainer.new()
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.08, 0.12, 0.17, 0.7)
	rsb.set_corner_radius_all(4)
	rsb.content_margin_left = 10
	rsb.content_margin_right = 10
	rsb.content_margin_top = 8
	rsb.content_margin_bottom = 8
	row_box.add_theme_stylebox_override("panel", rsb)
	list.add_child(row_box)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row_box.add_child(hbox)
	var info := Label.new()
	info.text = "🛞 %s (#%d · %s)\nDesgaste: %0.0f%% | %s" % [slot_label, tire_id, cid.to_upper(), wear, status]
	info.add_theme_font_override("font", FONT_REGULAR)
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", STATUS_DANGER if status != "OK" else WB_TEXT_TITLE)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)
	if is_dest:
		var dest_lbl := Label.new()
		dest_lbl.text = "NO REPARABLE"
		dest_lbl.add_theme_color_override("font_color", STATUS_DANGER)
		dest_lbl.add_theme_font_override("font", FONT_DATA_BOLD)
		dest_lbl.add_theme_font_size_override("font_size", 10)
		hbox.add_child(dest_lbl)
		return
	if is_punc:
		var cb := CheckBox.new()
		cb.text = "Inflar (%d min)" % cost_inflate
		cb.add_theme_font_override("font", FONT_REGULAR)
		cb.add_theme_font_size_override("font_size", 11)
		hbox.add_child(cb)
		tire_actions.append({"kind": "inflate", "tire_id": tire_id, "minutes": cost_inflate, "box": cb})
		cb.toggled.connect(func(_on: bool): _refresh())
	if is_rim:
		var cb2 := CheckBox.new()
		cb2.text = "Rin (%d min)" % cost_rim
		cb2.add_theme_font_override("font", FONT_REGULAR)
		cb2.add_theme_font_size_override("font_size", 11)
		hbox.add_child(cb2)
		tire_actions.append({"kind": "rim", "tire_id": tire_id, "minutes": cost_rim, "box": cb2})
		cb2.toggled.connect(func(_on: bool): _refresh())

func _add_row(list: VBoxContainer, key: String, title: String, damage: float, full_minutes: float) -> void:
	if damage <= 0.0001:
		return
	var minutes := maxi(1, ceili(clampf(damage, 0.0, 1.0) * full_minutes))
	var box := CheckBox.new()
	box.text = "%s  ·  daño %.1f%%  ·  %d min" % [title, damage * 100.0, minutes]
	box.add_theme_font_override("font", FONT_REGULAR)
	box.add_theme_font_size_override("font_size", 12)
	box.add_theme_color_override("font_color", WB_TEXT_TITLE)
	list.add_child(box)
	rows.append({"key": key, "minutes": minutes, "box": box})
	box.toggled.connect(func(_on: bool): _refresh())

func _minutes() -> int:
	var total := 0
	for row in rows:
		if (row.box as CheckBox).button_pressed:
			total += int(row.minutes)
	for tact in tire_actions:
		if (tact.box as CheckBox).button_pressed:
			total += int(tact.minutes)
	return total

func _refresh() -> void:
	if summary == null:
		return
	var total := _minutes()
	var excess := maxi(0, ceili(float(total) - limit_minutes))
	var remaining := maxi(0, ceili(limit_minutes - float(total)))
	if time_bar != null:
		time_bar.max_value = maxf(limit_minutes, 1.0)
		time_bar.value = mini(total, int(limit_minutes))
	summary.text = "Disponible: %.0f min  ·  Seleccionado: %d min  ·  Restan: %d min  ·  Exceso: %d min  ·  PENALIZACIÓN: +%d s" % [limit_minutes, total, remaining, excess, excess * penalty_per_minute]
	summary.add_theme_color_override("font_color", STATUS_DANGER if excess > 0 else STATUS_SUCCESS)

func _commit() -> void:
	commit.disabled = true
	var keys: Array[String] = []
	for row in rows:
		if (row.box as CheckBox).button_pressed:
			keys.append(str(row.key))
	vehicle.repair_service_components(keys)
	# Reparaciones de goma conservando desgaste; destalonado nunca entra aquí.
	var inv: RallyTireInventory = vehicle.tire_inventory
	for tact in tire_actions:
		if (tact.box as CheckBox).button_pressed:
			var tire := inv.find_tire(int(tact.tire_id))
			if tire.is_empty():
				continue
			if str(tact.kind) == "inflate":
				inv.repair_puncture(tire)
			elif str(tact.kind) == "rim":
				inv.repair_rim(tire)
	vehicle.apply_tire_inventory()
	var excess := maxi(0, ceili(float(_minutes()) - limit_minutes))
	var stage: String = manager.current_stage_id()
	manager.service_penalties_ms[stage] = int(manager.service_penalties_ms.get(stage, 0)) + excess * penalty_per_minute * 1000
	manager.windows_attended["repairs:" + window_key] = true
	vehicle.sync_tire_inventory()
	manager.vehicle_damage_state = vehicle.damage_snapshot()
	manager.tire_inventory_state = vehicle.tire_inventory.snapshot()
	manager.save()
	confirmed.emit()
	queue_free()
