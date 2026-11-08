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
var summary: Label
var commit: Button
var limit_minutes := 30.0
var penalty_per_minute := 10
var window_key := ""

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
	card_sb.bg_color = Color(WB_BG_CONTENT.r, WB_BG_CONTENT.g, WB_BG_CONTENT.b, 0.65)
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
	panel.add_theme_constant_override("separation", 12)
	modal_card.add_child(panel)

	var title := Label.new()
	title.text = "ÁREA DE SERVICIO · REPARACIONES"
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", WB_TEXT_TITLE)
	panel.add_child(title)

	var hint := Label.new()
	hint.text = "Marca las piezas a reparar. Neumáticos y rines se gestionan por separado.\nExceso: %d s de penalización por minuto iniciado." % penalty_per_minute
	hint.add_theme_font_override("font", FONT_REGULAR)
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", WB_TEXT_LABEL)
	panel.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
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
		healthy.add_theme_font_override("font", FONT_REGULAR)
		healthy.add_theme_font_size_override("font_size", 12)
		healthy.add_theme_color_override("font_color", STATUS_SUCCESS)
		list.add_child(healthy)

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
	if not rows.is_empty():
		(rows[0].box as CheckBox).grab_focus()
	else:
		commit.grab_focus()

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
		if row.box.button_pressed:
			total += int(row.minutes)
	return total

func _refresh() -> void:
	var total := _minutes()
	var excess := maxi(0, ceili(float(total) - limit_minutes))
	summary.text = "Disponible: %.0f min  ·  Seleccionado: %d min  ·  Exceso: %d min  ·  PENALIZACIÓN: +%d s" % [limit_minutes, total, excess, excess * penalty_per_minute]
	summary.add_theme_color_override("font_color", STATUS_DANGER if excess > 0 else STATUS_SUCCESS)

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

