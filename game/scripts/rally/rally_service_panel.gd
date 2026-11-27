extends CanvasLayer
signal confirmed

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _Calc := preload("res://scripts/ui/services/service_repair_calculator.gd")
const _Catalog := preload("res://scripts/ui/services/menu_catalog_service.gd")
const _MeterScript := preload("res://ui/atoms/ui_progress_meter.gd")

const BG_IMAGE_PATHS: Array[String] = [
	"res://assets/rally/garage/service_repairs_bg.jpg",
	"res://assets/rally/garage/service_repairs_bg_2.jpg"
]

var PARTS: Dictionary = {}
var WASH_MINUTES: int = 5
var vehicle
var manager
var rows: Array[Dictionary] = []
var tire_actions: Array[Dictionary] = []
var summary: Label
var time_bar: ProgressBar
var commit: Button
var wash_box: CheckBox
var save_error := ""
var limit_minutes := 30.0
var penalty_per_minute := 10
var window_key := ""
var cost_inflate := 2
var cost_rim := 5


func _init() -> void:
	PARTS = _Calc.get_parts_dict()
	WASH_MINUTES = int(_Catalog.get_service_parts().get("wash_minutes", 5))


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
	var event_doc: Dictionary = (manager as RallyEventManager).event_doc if manager != null else {}
	return _Calc.resolve_service_costs(window, event_doc)


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

	var c_content := _Tokens.get_color("bg_content")
	var c_border := _Tokens.get_color("border_card")
	var c_text := _Tokens.get_color("text_primary")
	var c_muted := _Tokens.get_color("text_muted")
	var c_accent := _Tokens.get_color("accent_rally")
	var c_info := _Tokens.get_color("status_info")
	var c_success := _Tokens.get_color("status_success")
	var r := _Tokens.get_radius("default")

	var bg_rect := TextureRect.new()
	bg_rect.name = "BackgroundImage"
	bg_rect.texture = _load_bg_texture()
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_rect)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.06, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var modal_card := PanelContainer.new()
	modal_card.theme = _Theme.get_menu_theme()
	modal_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_card.offset_left = 60
	modal_card.offset_right = -60
	modal_card.offset_top = 32
	modal_card.offset_bottom = -32
	modal_card.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(Color(c_content, 0.94), c_border, 1, r, 24, 20))
	shade.add_child(modal_card)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)
	modal_card.add_child(panel)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	panel.add_child(header)
	var title := Label.new()
	title.text = "ÁREA DE SERVICIO · REPARACIONES"
	title.add_theme_font_override("font", _Tokens.get_font("title"))
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", c_text)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var weather_label := Label.new()
	weather_label.text = _weather_text()
	weather_label.add_theme_font_override("font", _Tokens.get_font("medium"))
	weather_label.add_theme_font_size_override("font_size", 11)
	weather_label.add_theme_color_override("font_color", c_info)
	header.add_child(weather_label)

	var hint := Label.new()
	hint.text = "Marca las piezas a reparar. Pinchazo %d min · Rin %d min · Destalonado irreparable.\nExceso: %d s de penalización por minuto iniciado." % [cost_inflate, cost_rim, penalty_per_minute]
	hint.add_theme_font_override("font", _Tokens.get_font("regular"))
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", c_muted)
	panel.add_child(hint)

	var time_meter := _MeterScript.new()
	time_meter.title_label.hide()
	time_meter.value_label.hide()
	time_bar = time_meter.progress_bar
	time_bar.max_value = maxf(limit_minutes, 1.0)
	time_bar.value = 0
	time_bar.show_percentage = false
	time_bar.custom_minimum_size = Vector2(0, 12)
	panel.add_child(time_meter)

	var hsplit := HBoxContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.add_theme_constant_override("separation", 20)
	panel.add_child(hsplit)

	var tire_box := VBoxContainer.new()
	tire_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tire_box.add_theme_constant_override("separation", 6)
	var tire_title := Label.new()
	tire_title.text = "RUEDAS Y NEUMÁTICOS"
	tire_title.add_theme_font_override("font", _Tokens.get_font("subtitle"))
	tire_title.add_theme_font_size_override("font_size", 16)
	tire_title.add_theme_color_override("font_color", c_accent)
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
	mech_title.add_theme_font_override("font", _Tokens.get_font("subtitle"))
	mech_title.add_theme_font_size_override("font_size", 16)
	mech_title.add_theme_color_override("font_color", c_accent)
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
	if vehicle.simulation.dirt.is_dirty():
		wash_box = _make_repair_checkbox()
		wash_box.text = "LAVADO  ·  %d min" % WASH_MINUTES
		mech_list.add_child(wash_box)
	if rows.is_empty() and tire_actions.is_empty() and wash_box == null:
		var healthy := Label.new()
		healthy.text = "No hay componentes que necesiten reparación."
		healthy.add_theme_font_override("font", _Tokens.get_font("regular"))
		healthy.add_theme_font_size_override("font_size", 11)
		healthy.add_theme_color_override("font_color", c_success)
		mech_list.add_child(healthy)

	summary = Label.new()
	summary.add_theme_font_override("font", _Tokens.get_font("data_bold_tight"))
	summary.add_theme_font_size_override("font_size", 12)
	panel.add_child(summary)

	commit = Button.new()
	commit.text = "CONFIRMAR REPARACIONES Y CONTINUAR"
	_Theme.apply_tone_button(commit, "gold", 16, 20, 10)
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
		_add_tire_row(list, wheel_names[i], inv.mounted[i])
	for i in inv.spares.size():
		_add_tire_row(list, "MALETERA #%d" % (i + 1), inv.spares[i])
	for i in inv.service_stock.size():
		_add_tire_row(list, "PARQUE #%d" % (i + 1), inv.service_stock[i])


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
	row_box.add_theme_stylebox_override("panel", _Tokens.get_flat_stylebox(_Tokens.get_color("bg_well"), _Tokens.get_color("border_subtle"), 1, _Tokens.get_radius("default"), 10, 8))
	list.add_child(row_box)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row_box.add_child(hbox)
	var info := Label.new()
	info.text = "🛞 %s (#%d · %s)\nDesgaste: %0.0f%% | %s" % [slot_label, tire_id, cid.to_upper(), wear, status]
	info.add_theme_font_override("font", _Tokens.get_font("regular"))
	info.add_theme_font_size_override("font_size", 10)
	info.add_theme_color_override("font_color", _Tokens.get_color("status_danger") if status != "OK" else _Tokens.get_color("text_primary"))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)
	if is_dest:
		var dest_lbl := Label.new()
		dest_lbl.text = "NO REPARABLE"
		dest_lbl.add_theme_color_override("font_color", _Tokens.get_color("status_danger"))
		dest_lbl.add_theme_font_override("font", _Tokens.get_font("data_bold_tight"))
		dest_lbl.add_theme_font_size_override("font_size", 9)
		hbox.add_child(dest_lbl)
		return
	if is_punc:
		var cb := _make_repair_checkbox()
		cb.text = "Inflar (%d min)" % cost_inflate
		cb.add_theme_font_override("font", _Tokens.get_font("medium"))
		cb.add_theme_font_size_override("font_size", 10)
		hbox.add_child(cb)
		tire_actions.append({"kind": "inflate", "tire_id": tire_id, "minutes": cost_inflate, "box": cb})
	if is_rim:
		var cb2 := _make_repair_checkbox()
		cb2.text = "Rin (%d min)" % cost_rim
		cb2.add_theme_font_override("font", _Tokens.get_font("medium"))
		cb2.add_theme_font_size_override("font_size", 10)
		hbox.add_child(cb2)
		tire_actions.append({"kind": "rim", "tire_id": tire_id, "minutes": cost_rim, "box": cb2})


func _add_row(list: VBoxContainer, key: String, title: String, damage: float, full_minutes: float) -> void:
	if damage <= 0.0001:
		return
	var minutes := maxi(1, ceili(clampf(damage, 0.0, 1.0) * full_minutes))
	var box := _make_repair_checkbox()
	box.text = "%s  ·  daño %.1f%%  ·  %d min" % [title, damage * 100.0, minutes]
	box.add_theme_font_override("font", _Tokens.get_font("medium"))
	box.add_theme_font_size_override("font_size", 11)
	box.add_theme_color_override("font_color", _Tokens.get_color("text_primary"))
	list.add_child(box)
	rows.append({"key": key, "minutes": minutes, "box": box})


func _make_repair_checkbox() -> CheckBox:
	var box := CheckBox.new()
	box.set_meta("custom_button_sound", true)
	box.toggled.connect(func(_on: bool): _refresh())
	box.pressed.connect(func():
		var audio := get_node_or_null("/root/UIButtonAudio")
		if audio != null and audio.has_method("play_repair_selection"):
			audio.play_repair_selection()
	)
	return box


func _minutes() -> int:
	var total := 0
	for row in rows:
		if (row.box as CheckBox).button_pressed:
			total += int(row.minutes)
	for tact in tire_actions:
		if (tact.box as CheckBox).button_pressed:
			total += int(tact.minutes)
	return total + (WASH_MINUTES if wash_box != null and wash_box.button_pressed else 0)


func _refresh() -> void:
	if summary == null:
		return
	var total := _minutes()
	if wash_box != null:
		var other_minutes := total - (WASH_MINUTES if wash_box.button_pressed else 0)
		wash_box.disabled = other_minutes + WASH_MINUTES > limit_minutes
		if wash_box.disabled and wash_box.button_pressed:
			wash_box.set_pressed_no_signal(false)
			total -= WASH_MINUTES
	var excess := maxi(0, ceili(float(total) - limit_minutes))
	var remaining := maxi(0, ceili(limit_minutes - float(total)))
	var penalty_s := _Calc.compute_overtime_penalty_seconds(float(total), limit_minutes, penalty_per_minute)
	if time_bar != null:
		time_bar.max_value = maxf(limit_minutes, 1.0)
		time_bar.value = mini(total, int(limit_minutes))
		if time_bar.has_method("set_fill_color"):
			time_bar.set_fill_color(_Tokens.get_color("status_danger") if excess > 0 else _Tokens.get_color("accent_rally"))
	summary.text = "Disponible: %.0f min  ·  Seleccionado: %d min  ·  Restan: %d min  ·  Exceso: %d min  ·  PENALIZACIÓN: +%d s" % [limit_minutes, total, remaining, excess, penalty_s]
	if not save_error.is_empty():
		summary.text += "\n" + save_error
	summary.add_theme_color_override("font_color", _Tokens.get_color("status_danger") if excess > 0 or not save_error.is_empty() else _Tokens.get_color("status_success"))


func _commit() -> void:
	if commit.disabled:
		return
	_refresh()
	var washing := wash_box != null and wash_box.button_pressed and _minutes() <= limit_minutes
	var previous_damage: Dictionary = vehicle.damage_snapshot() if washing else {}
	var previous_tires: Dictionary = vehicle.tire_inventory.snapshot() if washing else {}
	var previous_event_damage: Dictionary = manager.vehicle_damage_state
	var previous_event_tires: Dictionary = manager.tire_inventory_state
	var previous_penalties: Dictionary = manager.service_penalties_ms.duplicate() if washing else {}
	var previous_windows: Dictionary = manager.windows_attended.duplicate() if washing else {}
	commit.disabled = true
	var keys: Array[String] = []
	for row in rows:
		if (row.box as CheckBox).button_pressed:
			keys.append(str(row.key))
	vehicle.repair_service_components(keys)
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
	if washing:
		vehicle.service_clean_dirt()
	var penalty_s := _Calc.compute_overtime_penalty_seconds(float(_minutes()), limit_minutes, penalty_per_minute)
	var stage: String = manager.current_stage_id()
	manager.service_penalties_ms[stage] = int(manager.service_penalties_ms.get(stage, 0)) + penalty_s * 1000
	manager.windows_attended["repairs:" + window_key] = true
	vehicle.sync_tire_inventory()
	manager.vehicle_damage_state = vehicle.damage_snapshot()
	manager.tire_inventory_state = vehicle.tire_inventory.snapshot()
	var saved: bool = manager.save()
	if washing and not saved:
		manager.vehicle_damage_state = previous_event_damage
		manager.tire_inventory_state = previous_event_tires
		manager.service_penalties_ms = previous_penalties
		manager.windows_attended = previous_windows
		vehicle.tire_inventory.restore(previous_tires)
		vehicle.apply_tire_inventory()
		vehicle.restore_damage(previous_damage)
		save_error = manager.error
		commit.disabled = false
		_refresh()
		return
	confirmed.emit()
	queue_free()
