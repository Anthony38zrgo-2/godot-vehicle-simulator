extends CanvasLayer
signal confirmed
const FONT_TITLE: Font = preload("res://fonts/montserrat/Montserrat-Bold.ttf")
const PARTS := {"engine": ["Motor", 45.0], "radiator": ["Radiador", 20.0], "transmission": ["Transmisión", 35.0], "body": ["Carrocería", 15.0], "hood": ["Capó", 8.0], "trunk": ["Maletero", 8.0], "windshield": ["Parabrisas", 10.0], "headlight_left": ["Faro izquierdo", 5.0], "headlight_right": ["Faro derecho", 5.0]}
var vehicle
var manager
var rows: Array[Dictionary] = []
var summary: Label
var commit: Button
var limit_minutes := 30.0
var penalty_per_minute := 10
var window_key := ""

func open(car, event_manager, window: Dictionary) -> void:
	vehicle = car
	manager = event_manager
	window_key = str(window.get("window_key", ""))
	limit_minutes = maxf(float(window.get("repair_minutes", 30.0)), 0.0)
	penalty_per_minute = maxi(int(window.get("repair_penalty_seconds_per_minute", 10)), 0)
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.96)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 70
	panel.offset_right = -70
	panel.offset_top = 35
	panel.offset_bottom = -35
	shade.add_child(panel)
	var title := Label.new()
	title.text = "ÁREA DE SERVICIO · REPARACIONES"
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 26)
	panel.add_child(title)
	var hint := Label.new()
	hint.text = "Marca las piezas a reparar. Neumáticos y rines se gestionan por separado.\nExceso: %d s de penalización por minuto iniciado." % penalty_per_minute
	panel.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var damage: Dictionary = vehicle.damage_snapshot()
	for key in PARTS:
		var amount := float(damage.get(key, 0.0)) if key in ["engine", "radiator", "transmission"] else (1.0 if bool(damage.get("visual", {}).get(key, false)) else 0.0)
		_add_row(list, key, str(PARTS[key][0]), amount, float(PARTS[key][1]))
	for i in 4:
		var code: String = ["DI", "DD", "TI", "TD"][i]
		var wear := float(vehicle.simulation.thermal_model.brake_wear_fraction[i])
		var collision := float(vehicle.simulation.brake_collision_loss[i])
		_add_row(list, "brake_%d" % i, "Freno " + code, 1.0 - (1.0 - wear) * (1.0 - collision), 15.0)
		_add_row(list, "alignment_%d" % i, "Alineación / suspensión " + code, float(vehicle.simulation.alignment_collision_damage[i]), 12.0)
	if rows.is_empty():
		var healthy := Label.new()
		healthy.text = "No hay componentes que necesiten reparación."
		list.add_child(healthy)
	summary = Label.new()
	panel.add_child(summary)
	commit = Button.new()
	commit.text = "CONFIRMAR REPARACIONES Y CONTINUAR"
	commit.pressed.connect(_commit)
	panel.add_child(commit)
	_refresh()
	if not rows.is_empty():
		(rows[0].box as CheckBox).grab_focus()
	else:
		commit.grab_focus()

func _add_row(list: VBoxContainer, key: String, title: String, damage: float, full_minutes: float) -> void:
	if damage <= 0.0001:
		return
	var minutes := maxi(1, ceili(clampf(damage, 0.0, 1.0) * full_minutes))
	var box := CheckBox.new()
	box.text = "%s · daño %.1f%% · %d min" % [title, damage * 100.0, minutes]
	list.add_child(box)
	rows.append({"key": key, "minutes": minutes, "box": box})
	box.toggled.connect(func(_on: bool): _refresh())

func _minutes() -> int:
	var total := 0
	for row in rows:
		if row.box.button_pressed:
			total += int(row.minutes)
	return total

func _refresh() -> void:
	var total := _minutes()
	var excess := maxi(0, ceili(float(total) - limit_minutes))
	summary.text = "Disponible: %.0f min · Seleccionado: %d min · Exceso: %d min · PENALIZACIÓN: +%d s" % [limit_minutes, total, excess, excess * penalty_per_minute]
	summary.modulate = Color(1.0, 0.45, 0.3) if excess > 0 else Color(0.65, 0.95, 0.75)

func _commit() -> void:
	commit.disabled = true
	var keys: Array[String] = []
	for row in rows:
		if row.box.button_pressed:
			keys.append(str(row.key))
	vehicle.repair_service_components(keys)
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
