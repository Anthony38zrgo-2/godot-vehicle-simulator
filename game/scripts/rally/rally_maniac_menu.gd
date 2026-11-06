class_name RallyManiacMenu
extends Control

# =============================================================================
# CONSTANTES VISUALES — SISTEMA DE DISEÑO AERO GLASS + MOTORSPORT
# =============================================================================

const FONT_SERIF: Font = preload("res://fonts/libron/Libron-Regular.ttf")
const FONT_SERIF_BOLD: Font = preload("res://fonts/libron/Libron-Bold.ttf")
const FONT_UI: Font = preload("res://fonts/D-DIN.ttf")
const FONT_UI_BOLD: Font = preload("res://fonts/D-DIN-Bold.ttf")
const FONT_TITLE: Font = preload("res://fonts/montserrat/Montserrat-Bold.ttf")

const C_BACK := Color("#080d12")
const C_GLASS := Color("#16232f")
const C_GLASS_DEEP := Color("#0d151d")
const C_RIM := Color("#7fa8c9")
const C_CHROME_TEXT := Color("#eaf2f8")
const C_CHROME_DIM := Color("#93a9bb")
const C_BLUE := Color("#6db2e8")
const C_BLUE_DEEP := Color("#2c6da3")

const C_FACE := Color("#2b3d4d")
const C_FACE_HI := Color("#374c5e")
const C_FACE_LO := Color("#22323f")
const C_FIELD := Color("#0c151d")
const C_HI := Color("#93afc8")
const C_LIGHT := Color("#5d7890")
const C_SHADOW := Color("#101b25")
const C_DARK := Color("#000000")
const C_TEXT := Color("#e2edf6")
const C_DIM := Color("#9eb3c5")
const C_GOLD := Color("#e3b23c")
const C_GOLD_HI := Color("#f6d68a")
const C_ROSE := Color("#ff6b61")
const C_SEL := Color("#3b3324")
const C_GREEN := Color("#55d67b")

const REGISTRY_PATH := "res://data/vehicles/registry.json"
const StageLoaderScript := preload("res://scripts/rally/rally_stage_loader.gd")
const EventManagerScript := preload("res://scripts/rally/rally_event_manager.gd")

# =============================================================================
# VARIABLES DE ESTADO Y NAVEGACIÓN
# =============================================================================

var selected_mode: String = "championship"
var selected_stage_id: String = "russia_stage1"
var selected_car_key: String = "fulvia"
var vehicle_registry: Dictionary = {}
var is_loading: bool = false

# Componentes de interfaz
var modal_panel: PanelContainer
var header_title: Label
var header_subtitle: Label
var badge_top: Label
var badge_bottom: Label
var content_container: MarginContainer
var footer_hint: Label

var screen_main_menu: VBoxContainer
var screen_stage_select: VBoxContainer
var screen_car_select: VBoxContainer
var status_banner: PanelContainer
var status_label: Label

var btn_championship: Button
var btn_rally: Button
var btn_single_stage: Button
var btn_exit: Button

var stage_buttons: Array[Button] = []
var btn_stage_back: Button

var car_scroll: ScrollContainer
var car_buttons: Array[Button] = []
var btn_car_back: Button

var current_screen: String = "menu"


# =============================================================================
# CICLO DE VIDA
# =============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_registry()
	_build_ui()
	show_main_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_center_modal()


func _center_modal() -> void:
	if modal_panel != null:
		var vp_size := get_viewport_rect().size
		modal_panel.position = (vp_size - modal_panel.size) * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if current_screen == "car_select":
			show_stage_select()
			get_viewport().set_input_as_handled()
		elif current_screen == "stage_select":
			show_main_menu()
			get_viewport().set_input_as_handled()


# =============================================================================
# CONSTRUCCIÓN DE LA INTERFAZ
# =============================================================================

func _build_ui() -> void:
	# Fondo atmosférico completo
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = C_BACK
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	# Ventana central Aero Glass
	modal_panel = PanelContainer.new()
	modal_panel.custom_minimum_size = Vector2(880, 620)
	modal_panel.add_theme_stylebox_override("panel", _make_glass_style(12, Color(C_GLASS, 0.96), Color(C_RIM, 0.45)))
	add_child(modal_panel)

	var root_margin := MarginContainer.new()
	root_margin.add_theme_constant_override("margin_left", 26)
	root_margin.add_theme_constant_override("margin_right", 26)
	root_margin.add_theme_constant_override("margin_top", 20)
	root_margin.add_theme_constant_override("margin_bottom", 20)
	modal_panel.add_child(root_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 14)
	root_margin.add_child(root_vbox)

	# 1. Cabecera Aero Glass
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", _make_glass_style(8, Color(C_GLASS_DEEP, 0.90), Color(C_RIM, 0.35)))
	root_vbox.add_child(header_panel)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 18)
	header_margin.add_theme_constant_override("margin_right", 18)
	header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.add_theme_constant_override("margin_bottom", 10)
	header_panel.add_child(header_margin)

	var header_hbox := HBoxContainer.new()
	header_margin.add_child(header_hbox)

	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 2)
	header_hbox.add_child(title_vbox)

	header_title = Label.new()
	header_title.text = "Rally Maniac"
	header_title.add_theme_font_override("font", FONT_TITLE)
	header_title.add_theme_font_size_override("font_size", 24)
	header_title.add_theme_color_override("font_color", C_CHROME_TEXT)
	title_vbox.add_child(header_title)

	header_subtitle = Label.new()
	header_subtitle.text = "HISTORIC RALLY SIMULATION // CAMPEONATO HISTÓRICO"
	header_subtitle.add_theme_font_override("font", FONT_SERIF)
	header_subtitle.add_theme_font_size_override("font_size", 11)
	header_subtitle.add_theme_color_override("font_color", C_CHROME_DIM)
	title_vbox.add_child(header_subtitle)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	var badge_box := PanelContainer.new()
	badge_box.add_theme_stylebox_override("panel", _make_glass_style(6, C_FIELD, Color(C_RIM, 0.30)))
	header_hbox.add_child(badge_box)

	var badge_margin := MarginContainer.new()
	badge_margin.add_theme_constant_override("margin_left", 14)
	badge_margin.add_theme_constant_override("margin_right", 14)
	badge_margin.add_theme_constant_override("margin_top", 6)
	badge_margin.add_theme_constant_override("margin_bottom", 6)
	badge_box.add_child(badge_margin)

	var badge_vbox := VBoxContainer.new()
	badge_vbox.add_theme_constant_override("separation", 1)
	badge_margin.add_child(badge_vbox)

	badge_top = Label.new()
	badge_top.text = "PANTALLA"
	badge_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_top.add_theme_font_override("font", FONT_TITLE)
	badge_top.add_theme_font_size_override("font_size", 9)
	badge_top.add_theme_color_override("font_color", C_CHROME_DIM)
	badge_vbox.add_child(badge_top)

	badge_bottom = Label.new()
	badge_bottom.text = "MENÚ PRINCIPAL"
	badge_bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_bottom.add_theme_font_override("font", FONT_TITLE)
	badge_bottom.add_theme_font_size_override("font_size", 13)
	badge_bottom.add_theme_color_override("font_color", C_GOLD)
	badge_vbox.add_child(badge_bottom)

	# 2. Contenedor central de contenido
	content_container = MarginContainer.new()
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.add_theme_constant_override("margin_top", 6)
	content_container.add_theme_constant_override("margin_bottom", 6)
	root_vbox.add_child(content_container)

	_build_main_menu_screen()
	_build_stage_select_screen()
	_build_car_select_screen()

	# Banner de estado / aviso / error
	status_banner = PanelContainer.new()
	status_banner.add_theme_stylebox_override("panel", _make_glass_style(6, Color(C_GLASS_DEEP, 0.95), Color(C_GOLD, 0.6)))
	status_banner.hide()
	root_vbox.add_child(status_banner)

	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override("margin_left", 14)
	status_margin.add_theme_constant_override("margin_right", 14)
	status_margin.add_theme_constant_override("margin_top", 8)
	status_margin.add_theme_constant_override("margin_bottom", 8)
	status_banner.add_child(status_margin)

	status_label = Label.new()
	status_label.text = ""
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_override("font", FONT_SERIF)
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", C_GOLD_HI)
	status_margin.add_child(status_label)

	# 3. Pie de página Aero Glass
	var footer_panel := PanelContainer.new()
	footer_panel.add_theme_stylebox_override("panel", _make_glass_style(8, Color(C_GLASS_DEEP, 0.90), Color(C_RIM, 0.35)))
	root_vbox.add_child(footer_panel)

	var footer_margin := MarginContainer.new()
	footer_margin.add_theme_constant_override("margin_left", 16)
	footer_margin.add_theme_constant_override("margin_right", 16)
	footer_margin.add_theme_constant_override("margin_top", 6)
	footer_margin.add_theme_constant_override("margin_bottom", 6)
	footer_panel.add_child(footer_margin)

	footer_hint = Label.new()
	footer_hint.text = "[ W/S / FLECHAS ] NAVEGAR  ·  [ ENTER ] CONFIRMAR  ·  [ ESC ] VOLVER"
	footer_hint.add_theme_font_override("font", FONT_SERIF)
	footer_hint.add_theme_font_size_override("font_size", 11)
	footer_hint.add_theme_color_override("font_color", Color(C_CHROME_DIM, 0.8))
	footer_margin.add_child(footer_hint)


# =============================================================================
# PANTALLA 1: MENÚ PRINCIPAL
# =============================================================================

func _build_main_menu_screen() -> void:
	screen_main_menu = VBoxContainer.new()
	screen_main_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen_main_menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_main_menu.alignment = BoxContainer.ALIGNMENT_CENTER
	screen_main_menu.add_theme_constant_override("separation", 14)
	content_container.add_child(screen_main_menu)

	var subtitle := Label.new()
	subtitle.text = "// SELECCIONA EL MODO DE JUEGO"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", FONT_TITLE)
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", C_GOLD)
	screen_main_menu.add_child(subtitle)

	var buttons_box := VBoxContainer.new()
	buttons_box.custom_minimum_size = Vector2(420, 0)
	buttons_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buttons_box.add_theme_constant_override("separation", 10)
	screen_main_menu.add_child(buttons_box)

	btn_championship = _create_menu_button("Championship", func(): _on_mode_selected("championship"), true)
	buttons_box.add_child(btn_championship)

	btn_rally = _create_menu_button("Rally", func(): _on_mode_selected("rally"), true)
	buttons_box.add_child(btn_rally)

	btn_single_stage = _create_menu_button("Single Stage", func(): _on_mode_selected("single_stage"))
	buttons_box.add_child(btn_single_stage)

	btn_exit = _create_menu_button("Exit", func(): get_tree().quit(), false, true)
	buttons_box.add_child(btn_exit)


# =============================================================================
# PANTALLA 2: SELECTOR DE TRAMO
# =============================================================================

func _build_stage_select_screen() -> void:
	screen_stage_select = VBoxContainer.new()
	screen_stage_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen_stage_select.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_stage_select.add_theme_constant_override("separation", 10)
	screen_stage_select.hide()
	content_container.add_child(screen_stage_select)

	var stage_header := HBoxContainer.new()
	screen_stage_select.add_child(stage_header)

	var stage_title := Label.new()
	stage_title.text = "Russia Stages · Especiales 1 a 10"
	stage_title.add_theme_font_override("font", FONT_TITLE)
	stage_title.add_theme_font_size_override("font_size", 14)
	stage_title.add_theme_color_override("font_color", C_GOLD)
	stage_header.add_child(stage_title)

	var stage_sub := Label.new()
	stage_sub.text = "   // Elige el tramo de entrada"
	stage_sub.add_theme_font_override("font", FONT_SERIF)
	stage_sub.add_theme_font_size_override("font_size", 11)
	stage_sub.add_theme_color_override("font_color", C_CHROME_DIM)
	stage_header.add_child(stage_sub)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_style_scroll_container(scroll)
	screen_stage_select.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)

	stage_buttons.clear()
	for i in range(1, 11):
		var sid := "russia_stage%d" % i
		var s_text := "Russia Stage %d" % i
		var btn := Button.new()
		btn.text = s_text
		btn.set_meta("stage_id", sid)
		btn.custom_minimum_size = Vector2(380, 42)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_chrome_button(btn)
		btn.pressed.connect(func(): _on_stage_selected(sid))
		grid.add_child(btn)
		stage_buttons.append(btn)

	var bottom_bar := HBoxContainer.new()
	screen_stage_select.add_child(bottom_bar)

	btn_stage_back = Button.new()
	btn_stage_back.text = "◀ Back"
	btn_stage_back.custom_minimum_size = Vector2(160, 38)
	_style_chrome_button(btn_stage_back)
	btn_stage_back.pressed.connect(show_main_menu)
	bottom_bar.add_child(btn_stage_back)


# =============================================================================
# PANTALLA 3: SELECTOR DE COCHE (SELECT CAR)
# =============================================================================

func _build_car_select_screen() -> void:
	screen_car_select = VBoxContainer.new()
	screen_car_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen_car_select.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_car_select.add_theme_constant_override("separation", 12)
	screen_car_select.hide()
	content_container.add_child(screen_car_select)

	var car_header := HBoxContainer.new()
	screen_car_select.add_child(car_header)

	var car_title := Label.new()
	car_title.text = "Select Car"
	car_title.add_theme_font_override("font", FONT_TITLE)
	car_title.add_theme_font_size_override("font_size", 16)
	car_title.add_theme_color_override("font_color", C_GOLD)
	car_header.add_child(car_title)

	var car_sub := Label.new()
	car_sub.text = "   // Vehículos de rally disponibles en el registro"
	car_sub.add_theme_font_override("font", FONT_SERIF)
	car_sub.add_theme_font_size_override("font_size", 11)
	car_sub.add_theme_color_override("font_color", C_CHROME_DIM)
	car_header.add_child(car_sub)

	car_scroll = ScrollContainer.new()
	car_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	car_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	car_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	car_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	car_scroll.follow_focus = true
	_style_scroll_container(car_scroll)
	screen_car_select.add_child(car_scroll)

	var cars_margin := MarginContainer.new()
	cars_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cars_margin.add_theme_constant_override("margin_left", 6)
	cars_margin.add_theme_constant_override("margin_right", 14)
	cars_margin.add_theme_constant_override("margin_top", 4)
	cars_margin.add_theme_constant_override("margin_bottom", 6)
	car_scroll.add_child(cars_margin)

	var cars_vbox := VBoxContainer.new()
	cars_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cars_vbox.add_theme_constant_override("separation", 8)
	cars_margin.add_child(cars_vbox)

	car_buttons.clear()
	var vehicles: Dictionary = vehicle_registry.get("vehicles", {})
	for car_key in vehicles:
		var v_data: Dictionary = vehicles[car_key]
		var display_name := str(v_data.get("DisplayName", car_key))
		var btn := Button.new()
		btn.text = display_name
		btn.set_meta("car_key", str(car_key))
		btn.custom_minimum_size = Vector2(0, 46)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_chrome_button(btn)
		btn.pressed.connect(func(): _on_car_selected(str(car_key)))
		cars_vbox.add_child(btn)
		car_buttons.append(btn)

	var bottom_bar := HBoxContainer.new()
	screen_car_select.add_child(bottom_bar)

	btn_car_back = Button.new()
	btn_car_back.text = "◀ Back"
	btn_car_back.custom_minimum_size = Vector2(160, 38)
	_style_chrome_button(btn_car_back)
	btn_car_back.pressed.connect(show_stage_select)
	bottom_bar.add_child(btn_car_back)


# =============================================================================
# MANEJO DE PANTALLAS Y FOCO
# =============================================================================

func show_main_menu() -> void:
	current_screen = "menu"
	screen_stage_select.hide()
	screen_car_select.hide()
	screen_main_menu.show()
	_hide_status()

	badge_top.text = "PANTALLA"
	badge_bottom.text = "RALLY MANIAC"

	# Dar foco al modo seleccionado o a Championship por defecto
	call_deferred("_focus_mode_button")


func _focus_mode_button() -> void:
	if selected_mode == "rally" and btn_rally != null:
		btn_rally.grab_focus()
	elif selected_mode == "single_stage" and btn_single_stage != null:
		btn_single_stage.grab_focus()
	elif btn_championship != null:
		btn_championship.grab_focus()


func show_stage_select() -> void:
	current_screen = "stage_select"
	screen_main_menu.hide()
	screen_car_select.hide()
	screen_stage_select.show()
	_hide_status()

	badge_top.text = "MODO: " + selected_mode.to_upper()
	badge_bottom.text = "SELECT STAGE"

	call_deferred("_focus_stage_button")


func _focus_stage_button() -> void:
	for btn in stage_buttons:
		if str(btn.get_meta("stage_id", "")) == selected_stage_id:
			btn.grab_focus()
			return
	if not stage_buttons.is_empty():
		stage_buttons[0].grab_focus()


func show_car_select() -> void:
	current_screen = "car_select"
	screen_main_menu.hide()
	screen_stage_select.hide()
	screen_car_select.show()
	_hide_status()

	badge_top.text = "TRAMO: " + selected_stage_id.to_upper()
	badge_bottom.text = "SELECT CAR"

	call_deferred("_focus_car_button")


func _focus_car_button() -> void:
	for btn in car_buttons:
		if str(btn.get_meta("car_key", "")) == selected_car_key:
			btn.grab_focus()
			if car_scroll != null:
				car_scroll.ensure_control_visible(btn)
			return
	if not car_buttons.is_empty():
		car_buttons[0].grab_focus()
		if car_scroll != null:
			car_scroll.ensure_control_visible(car_buttons[0])


# =============================================================================
# SELECCIÓN Y CONFIRMACIÓN
# =============================================================================

func _on_mode_selected(mode: String) -> void:
	selected_mode = mode
	show_stage_select()


func _on_stage_selected(stage_id: String) -> void:
	selected_stage_id = stage_id
	show_car_select()


func _on_car_selected(car_key: String) -> void:
	if is_loading:
		return
	selected_car_key = car_key
	_launch_session()


func _launch_session() -> void:
	_set_loading(true)
	_show_notice("Cargando sesión... Por favor, espere.", false)

	# 1. Validar ID del tramo
	if not StageLoaderScript.is_valid_track_id(selected_stage_id):
		_show_error("ID de tramo no válido: %s (sin sustitución por Stage 1)" % selected_stage_id)
		_set_loading(false)
		return

	# 2. Validar recursos del tramo con RallyStageLoader
	var stage_loader := StageLoaderScript.new()
	var resolved := stage_loader.resolve(selected_stage_id)
	if resolved.is_empty():
		_show_error("Fallo al resolver recursos para %s:\n%s" % [selected_stage_id, stage_loader.error])
		_set_loading(false)
		return

	# 3. Validar coche en el registro
	var vehicles: Dictionary = vehicle_registry.get("vehicles", {})
	if not vehicles.has(selected_car_key):
		_show_error("Coche no encontrado en registro: %s" % selected_car_key)
		_set_loading(false)
		return

	var v_data: Dictionary = vehicles[selected_car_key]
	var stage_scene_name := str(v_data.get("Stage", ""))
	var scene_path := "res://scenes/rally/%s.tscn" % stage_scene_name
	if not ResourceLoader.exists(scene_path):
		_show_error("Escena base del coche ausente: %s" % scene_path)
		_set_loading(false)
		return

	# 4. Validar perfil del coche
	var profile_name := str(v_data.get("Profile", ""))
	var profile_path := "res://data/vehicles/%s/vehicle.json" % profile_name
	if not FileAccess.file_exists(profile_path):
		_show_error("Perfil del vehículo ausente: %s" % profile_path)
		_set_loading(false)
		return

	# 5. Instanciar escena base y configurar ANTES de _ready()
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_show_error("No se pudo cargar la escena: %s" % scene_path)
		_set_loading(false)
		return

	var session := packed.instantiate() as RallyRussiaStageSession
	if session == null:
		_show_error("La escena %s no es un RallyRussiaStageSession válido." % scene_path)
		_set_loading(false)
		return

	# Transferir modo, ID de tramo y coche seleccionado
	session.track_id = selected_stage_id
	session.session_track_id = selected_stage_id
	session.set("session_mode", selected_mode)
	session.set("selected_vehicle_key", selected_car_key)

	if selected_mode == "rally":
		var manager := EventManagerScript.new()
		if not manager.begin_event({"start_stage_id": selected_stage_id}):
			_show_error("Error al iniciar el evento Rally: %s" % manager.error)
			_set_loading(false)
			return
		session.begin_event_session(manager, selected_stage_id)
	else:
		# Single Stage y Championship: sesión independiente de un tramo sin guardado oficial
		session.practice_mode = true
		session.competition.save_path = ""

	# Conectar y cambiar de escena
	var tree := get_tree()
	tree.root.add_child(session)
	tree.current_scene = session
	queue_free()


# =============================================================================
# GESTIÓN DE ERRORES Y ESTADO DE CARGA
# =============================================================================

func _set_loading(loading: bool) -> void:
	is_loading = loading
	for btn in car_buttons:
		btn.disabled = loading
	btn_car_back.disabled = loading


func _show_error(msg: String) -> void:
	status_banner.add_theme_stylebox_override("panel", _make_glass_style(6, Color(0.18, 0.08, 0.10, 0.95), Color(C_ROSE, 0.8)))
	status_label.text = "⚠ " + msg
	status_label.add_theme_color_override("font_color", Color("#ff9e97"))
	status_banner.show()
	_center_modal()


func _show_notice(msg: String, is_err: bool = false) -> void:
	if is_err:
		_show_error(msg)
		return
	status_banner.add_theme_stylebox_override("panel", _make_glass_style(6, Color(C_GLASS_DEEP, 0.95), Color(C_GOLD, 0.6)))
	status_label.text = "ℹ " + msg
	status_label.add_theme_color_override("font_color", C_GOLD_HI)
	status_banner.show()
	_center_modal()


func _hide_status() -> void:
	status_banner.hide()
	status_label.text = ""


func _load_registry() -> void:
	if FileAccess.file_exists(REGISTRY_PATH):
		var text := FileAccess.get_file_as_string(REGISTRY_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			vehicle_registry = parsed
			return
	push_warning("No se pudo cargar el registro de vehículos desde " + REGISTRY_PATH)


# =============================================================================
# HELPERS DE ESTILO
# =============================================================================

func _make_glass_style(radius: int, fill: Color, rim: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = rim
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s


func _style_scroll_container(scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	var v_bar := scroll.get_v_scroll_bar()
	if v_bar != null:
		v_bar.custom_minimum_size = Vector2(10, 0)
		var track := StyleBoxFlat.new()
		track.bg_color = Color(C_FIELD.r, C_FIELD.g, C_FIELD.b, 0.60)
		track.border_color = Color(C_RIM.r, C_RIM.g, C_RIM.b, 0.20)
		track.set_border_width_all(1)
		track.set_corner_radius_all(4)

		var grabber := StyleBoxFlat.new()
		grabber.bg_color = Color(C_RIM.r, C_RIM.g, C_RIM.b, 0.65)
		grabber.border_color = Color(C_RIM.r, C_RIM.g, C_RIM.b, 0.85)
		grabber.set_border_width_all(1)
		grabber.set_corner_radius_all(4)

		var grabber_hl := StyleBoxFlat.new()
		grabber_hl.bg_color = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.90)
		grabber_hl.border_color = C_GOLD_HI
		grabber_hl.set_border_width_all(1)
		grabber_hl.set_corner_radius_all(4)

		var grabber_pr := StyleBoxFlat.new()
		grabber_pr.bg_color = Color(C_GOLD_HI.r, C_GOLD_HI.g, C_GOLD_HI.b, 1.0)
		grabber_pr.border_color = Color.WHITE
		grabber_pr.set_border_width_all(1)
		grabber_pr.set_corner_radius_all(4)

		v_bar.add_theme_stylebox_override("scroll", track)
		v_bar.add_theme_stylebox_override("scroll_focus", track)
		v_bar.add_theme_stylebox_override("grabber", grabber)
		v_bar.add_theme_stylebox_override("grabber_highlight", grabber_hl)
		v_bar.add_theme_stylebox_override("grabber_pressed", grabber_pr)


func _create_menu_button(text: String, callback: Callable, is_gold: bool = false, is_danger: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 48)
	if is_gold:
		_style_gold_button(btn)
	elif is_danger:
		_style_danger_button(btn)
	else:
		_style_chrome_button(btn)
	btn.pressed.connect(callback)
	return btn


func _style_chrome_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(C_GLASS, 0.92)
	normal.border_color = Color(C_RIM, 0.35)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.14, 0.22, 0.30, 0.95)
	hover.border_color = Color(C_BLUE, 0.75)
	hover.shadow_color = Color(C_BLUE.r, C_BLUE.g, C_BLUE.b, 0.35)
	hover.shadow_size = 5

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.08, 0.12, 0.18, 0.95)
	pressed.border_color = Color(C_RIM, 0.5)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", FONT_SERIF_BOLD)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", C_CHROME_TEXT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", C_BLUE)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)


func _style_gold_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#b8862a")
	normal.border_color = C_GOLD_HI
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	normal.shadow_color = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.4)
	normal.shadow_size = 6

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#cf9932")
	hover.border_color = Color("#fff2c2")
	hover.shadow_size = 8
	hover.shadow_color = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.65)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#996e1f")
	pressed.border_color = C_GOLD
	pressed.shadow_size = 2

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", FONT_SERIF_BOLD)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color("#1a1206"))
	btn.add_theme_color_override("font_hover_color", Color("#000000"))
	btn.add_theme_color_override("font_pressed_color", Color("#000000"))
	btn.add_theme_color_override("font_focus_color", Color("#1a1206"))


func _style_danger_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.18, 0.08, 0.08, 0.90)
	normal.border_color = Color(C_ROSE, 0.5)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.26, 0.10, 0.10, 0.95)
	hover.border_color = Color(1.0, 0.45, 0.45)
	hover.shadow_color = Color(C_ROSE.r, C_ROSE.g, C_ROSE.b, 0.3)
	hover.shadow_size = 4

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.10, 0.05, 0.05, 0.95)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", FONT_SERIF_BOLD)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color("#ff9e97"))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", C_ROSE)
	btn.add_theme_color_override("font_focus_color", Color("#ff9e97"))
