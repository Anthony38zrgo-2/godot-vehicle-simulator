class_name RallyManiacMenu
extends Control

const REGISTRY_PATH := "res://data/vehicles/registry.json"
const DEFAULT_CREATOR_NAME := "DoomerDoge38"
const DEFAULT_GAME_VERSION := "1.0"
const StageLoaderScript := preload("res://scripts/rally/rally_stage_loader.gd")
const EventManagerScript := preload("res://scripts/rally/rally_event_manager.gd")
const VehicleLiveryScript := preload("res://scripts/rally/rally_vehicle_livery.gd")
const _ShaderMaterialFactory := preload("res://scripts/shaders/shader_material_factory.gd")
const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _ThemeBuilder := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _CatalogService := preload("res://scripts/ui/services/menu_catalog_service.gd")
const _NoticeBannerScript := preload("res://ui/atoms/ui_notice_banner.gd")
const _MainMenuViewScene := preload("res://ui/screens/main_menu/main_menu_view.tscn")
const _StageSelectViewScene := preload("res://ui/screens/main_menu/stage_select_view.tscn")
const _CarSelectViewScene := preload("res://ui/screens/main_menu/car_select_view.tscn")
const _WeatherSelectViewScene := preload("res://ui/screens/main_menu/weather_select_view.tscn")

# Data-Driven catalogs hydrated from res://data/ui/menus/countries_stages.json & weather_options.json
var STAGE_METADATA: Dictionary = {}
var COUNTRY_ORDER: Array[String] = []
var COUNTRY_LABELS: Dictionary = {}
var COUNTRY_STAGE_COUNTS: Dictionary = {}
var EVENT_PATH_BY_COUNTRY: Dictionary = {}
var CDI_START_STAGE: String = "cdi_stage1"
var CDI_STAGES: Dictionary = {}
var CDI_CARS: Array = []
var WEATHER_OPTIONS: Array = []


func _init() -> void:
	var cs := _CatalogService.get_countries_stages()
	STAGE_METADATA = cs.get("stage_metadata", {}) as Dictionary
	COUNTRY_ORDER.clear()
	for c in cs.get("country_order", []):
		COUNTRY_ORDER.append(str(c))
	COUNTRY_LABELS = cs.get("country_labels", {}) as Dictionary
	COUNTRY_STAGE_COUNTS = cs.get("country_stage_counts", {}) as Dictionary
	EVENT_PATH_BY_COUNTRY = cs.get("event_path_by_country", {}) as Dictionary
	CDI_START_STAGE = str(cs.get("cdi_start_stage", "cdi_stage1"))
	CDI_STAGES = cs.get("cdi_stages", {}) as Dictionary
	CDI_CARS = cs.get("cdi_cars", []) as Array
	WEATHER_OPTIONS = _CatalogService.get_weather_options().get("options", []) as Array


# =============================================================================
# VARIABLES DE ESTADO Y NAVEGACIÓN
# =============================================================================

@export var creator_name: String = DEFAULT_CREATOR_NAME:
	set(value):
		creator_name = value
		_refresh_footer_labels()

@export var game_version: String = DEFAULT_GAME_VERSION:
	set(value):
		game_version = value
		_refresh_footer_labels()

var selected_mode: String = "championship"
var selected_stage_id: String = "russia_stage1"
var selected_country: String = "russia"
var selected_car_key: String = "fulvia"
var selected_livery_id: String = ""
var selected_livery_by_car: Dictionary = {}
var _confirmed_car_click_key: String = ""
var _cdi_launch: bool = false
var vehicle_registry: Dictionary = {}
var vehicle_specs_cache: Dictionary = {}
var stage_routes_cache: Dictionary = {}
var is_loading: bool = false

# Componentes de fondo y showroom 3D fullscreen
var showroom_container: SubViewportContainer
var vignette_rect: ColorRect

# Componentes de fondo de fotos para el menú principal
const PHOTOS_DIR := "res://assets/photos"
var photo_container: Control
var photo_rect: TextureRect
var photo_timer: Timer
var photo_tween: Tween
var photo_paths: Array[String] = []
var photo_textures: Dictionary = {}
var current_photo_index: int = 0

# Componentes de interfaz (layout edge-to-edge)
var modal_panel: PanelContainer
var header_hbox_ref: HBoxContainer
var header_line_ref: ColorRect
var header_title: Label
var header_subtitle: Label
var header_badge_vbox: VBoxContainer
var badge_top: Label
var badge_bottom: Label
var content_container: MarginContainer
var footer_hint: Label
var footer_version: Label
var main_menu_title: Label

var screen_main_menu: VBoxContainer
var screen_stage_select: VBoxContainer
var car_title: Label
var screen_car_select: VBoxContainer
var status_banner: PanelContainer
var status_label: Label

var btn_championship: Button
var btn_rally: Button
var btn_single_stage: Button
var btn_exit: Button

# Carrusel de 4 tramos y navegación con flechas
var stage_scroll: ScrollContainer
var stage_strip: HBoxContainer
var stage_buttons: Array[Button] = []
var stage_previews: Array = []
var btn_carousel_prev: Button
var btn_carousel_next: Button
var carousel_page_label: Label
var carousel_scroll_index: int = 0
var btn_stage_back: Button
var stage_title_label: Label
var country_buttons: Array[Button] = []

var car_scroll: ScrollContainer
var car_buttons: Array[Button] = []
var btn_car_back: Button
var btn_car_confirm: Button
var livery_panel: PanelContainer
var livery_name_label: Label
var livery_hex_label: Label
var livery_buttons: Array[Button] = []
var btn_livery_prev: Button
var btn_livery_next: Button

var selected_weather: String = "random"
var screen_weather_select: VBoxContainer
var weather_buttons: Array[Button] = []
var btn_weather_back: Button
var btn_weather_confirm: Button
var _main_menu_view: Control = null
var _stage_select_view: Control = null
var _car_select_view: Control = null
var _weather_view: Control = null
var _notice_banner: Control = null

# Componentes del Showroom 3D y Especificaciones
var preview_viewport: SubViewport
var car_turntable: Node3D
var current_preview_car_key: String = ""
var current_car_model_instance: Node = null

var preview_car_title: Label
var preview_car_category: Label
var preview_layout_badge: Label

var spec_power_val: Label
var spec_power_sub: Label
var spec_gears_val: Label
var spec_gears_sub: Label
var spec_wb_val: Label
var spec_wb_sub: Label
var spec_track_val: Label
var spec_track_sub: Label
var spec_mass_val: Label
var spec_mass_sub: Label
var spec_layout_val: Label
var spec_layout_sub: Label

var current_screen: String = "menu"


# =============================================================================
# CICLO DE VIDA
# =============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cdi_launch = "--rally-cdi" in OS.get_cmdline_user_args()
	if _cdi_launch:
		selected_mode = "rally"
		selected_country = "cdi"
		selected_stage_id = CDI_START_STAGE
		selected_car_key = CDI_CARS[0]
	_load_registry()
	_load_all_vehicle_specs()
	_load_all_stage_routes()
	_build_ui()
	_ensure_menu_music()
	if _cdi_launch:
		show_stage_select()
	else:
		show_main_menu()


func _ensure_menu_music() -> void:
	var music := get_node_or_null("/root/RallyMusic")
	if music == null and get_tree() != null and get_tree().root != null:
		var music_script := load("res://scripts/audio/rally_music_manager.gd")
		if music_script != null:
			music = music_script.new()
			music.name = "RallyMusic"
			get_tree().root.add_child(music)
	if music != null and music.has_method("play_menu_music"):
		music.call("play_menu_music")


func _process(delta: float) -> void:
	if current_screen == "car_select" and car_turntable != null and is_instance_valid(car_turntable):
		car_turntable.rotate_y(delta * 0.45)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_stage_card_widths()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if current_screen == "weather_select":
			show_car_select()
			get_viewport().set_input_as_handled()
		elif current_screen == "car_select":
			show_stage_select()
			get_viewport().set_input_as_handled()
		elif current_screen == "stage_select" and not _cdi_launch:
			show_main_menu()
			get_viewport().set_input_as_handled()
	elif current_screen == "car_select" and not is_loading and not event.is_echo():
		var focus_owner := get_viewport().gui_get_focus_owner()
		var focused_in_swatches := focus_owner is Button and livery_buttons.has(focus_owner)
		if not focused_in_swatches:
			if event.is_action_pressed("ui_left") or (event is InputEventKey and event.pressed and event.keycode == KEY_Q):
				_cycle_livery(-1)
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_right") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
				_cycle_livery(1)
				get_viewport().set_input_as_handled()


# =============================================================================
# CONSTRUCCIÓN DE LA INTERFAZ MINIMALISTA (EDGE-TO-EDGE)
# =============================================================================

func _build_ui() -> void:
	theme = RallyUITheme.build_menu_theme()

	# 1. Fondo base neutro oscuro
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = _Tokens.get_color("bg_base")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	# 2. Showroom 3D Fullscreen en el fondo
	showroom_container = SubViewportContainer.new()
	showroom_container.stretch = true
	showroom_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	showroom_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(showroom_container)

	preview_viewport = SubViewport.new()
	var vp_size := get_viewport_rect().size
	preview_viewport.size = Vector2i(vp_size) if vp_size.x > 0 else Vector2i(1280, 720)
	preview_viewport.own_world_3d = true
	preview_viewport.transparent_bg = false
	preview_viewport.msaa_3d = Viewport.MSAA_DISABLED
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	showroom_container.add_child(preview_viewport)

	_setup_3d_preview_scene()

	# 2b. Fondo de fotos históricas intercaladas para el menú principal
	_setup_photo_background()

	# 3. Viñeteado suave sobre el fondo para garantizar contraste y legibilidad
	vignette_rect = ColorRect.new()
	vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_rect.material = _ShaderMaterialFactory.create_from_preset("ui.showroom_vignette.default", {}, false)
	add_child(vignette_rect)

	# 4. Contenedor de interfaz principal Edge-to-Edge
	modal_panel = PanelContainer.new()
	modal_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var empty_style := StyleBoxEmpty.new()
	modal_panel.add_theme_stylebox_override("panel", empty_style)
	add_child(modal_panel)

	var root_margin := MarginContainer.new()
	root_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_margin.add_theme_constant_override("margin_left", 48)
	root_margin.add_theme_constant_override("margin_right", 48)
	root_margin.add_theme_constant_override("margin_top", 28)
	root_margin.add_theme_constant_override("margin_bottom", 24)
	modal_panel.add_child(root_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 14)
	root_margin.add_child(root_vbox)

	# 5. Cabecera Minimalista
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 16)
	root_vbox.add_child(header_hbox)
	header_hbox_ref = header_hbox

	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 1)
	header_hbox.add_child(title_vbox)

	header_title = Label.new()
	header_title.text = "Rally Maniac"
	header_title.add_theme_font_override("font", _Tokens.get_font("logo"))
	header_title.add_theme_font_size_override("font_size", 22)
	header_title.add_theme_color_override("font_color", _Tokens.get_color("text_primary"))
	title_vbox.add_child(header_title)

	header_subtitle = Label.new()
	header_subtitle.text = "HISTORIC RALLY SIMULATION · CAMPEONATO HISTÓRICO"
	header_subtitle.add_theme_font_override("font", _Tokens.get_font("subtitle"))
	header_subtitle.add_theme_font_size_override("font_size", 11)
	header_subtitle.add_theme_color_override("font_color", _Tokens.get_color("text_muted"))
	header_subtitle.hide()
	title_vbox.add_child(header_subtitle)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(header_spacer)

	var badge_vbox := VBoxContainer.new()
	badge_vbox.add_theme_constant_override("separation", 1)
	badge_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	header_hbox.add_child(badge_vbox)
	header_badge_vbox = badge_vbox

	badge_top = Label.new()
	badge_top.text = "PANTALLA"
	badge_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_top.add_theme_font_override("font", _Tokens.get_font("medium"))
	badge_top.add_theme_font_size_override("font_size", 9)
	badge_top.add_theme_color_override("font_color", _Tokens.get_color("text_muted"))
	badge_vbox.add_child(badge_top)

	badge_bottom = Label.new()
	badge_bottom.text = "RALLY MANIAC"
	badge_bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_bottom.add_theme_font_override("font", _Tokens.get_font("subtitle"))
	badge_bottom.add_theme_font_size_override("font_size", 16)
	badge_bottom.add_theme_color_override("font_color", _Tokens.get_color("accent_rally"))
	badge_vbox.add_child(badge_bottom)

	# Separador de 1 px bajo la cabecera
	var header_line := ColorRect.new()
	header_line.custom_minimum_size = Vector2(0, 1)
	header_line.color = Color(1, 1, 1, 0.08)
	header_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vbox.add_child(header_line)
	header_line_ref = header_line

	# 6. Contenedor central de contenido
	content_container = MarginContainer.new()
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.add_theme_constant_override("margin_top", 10)
	content_container.add_theme_constant_override("margin_bottom", 10)
	root_vbox.add_child(content_container)

	_build_main_menu_screen()
	_build_stage_select_screen()
	_build_car_select_screen()
	_build_weather_select_screen()

	# Banner de estado / aviso / error (componente atómico UINoticeBanner)
	_notice_banner = _NoticeBannerScript.new()
	status_banner = _notice_banner as PanelContainer
	status_label = _notice_banner.label
	root_vbox.add_child(_notice_banner)

	# 7. Separador y Pie de página Minimalista
	var footer_line := ColorRect.new()
	footer_line.custom_minimum_size = Vector2(0, 1)
	footer_line.color = Color(1, 1, 1, 0.06)
	footer_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vbox.add_child(footer_line)

	var footer_hbox := HBoxContainer.new()
	footer_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(footer_hbox)

	footer_hint = Label.new()
	footer_hint.add_theme_font_override("font", _Tokens.get_font("medium"))
	footer_hint.add_theme_font_size_override("font_size", 11)
	footer_hint.add_theme_color_override("font_color", Color(_Tokens.get_color("text_muted"), 0.95))
	footer_hbox.add_child(footer_hint)

	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(footer_spacer)

	footer_version = Label.new()
	footer_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer_version.add_theme_font_override("font", _Tokens.get_font("medium"))
	footer_version.add_theme_font_size_override("font_size", 11)
	footer_version.add_theme_color_override("font_color", Color(_Tokens.get_color("text_muted"), 0.95))
	footer_hbox.add_child(footer_version)

	_refresh_footer_labels()


func set_game_version(version_str: String) -> void:
	game_version = version_str


func _resolve_game_version() -> String:
	var v := game_version.strip_edges()
	if v != DEFAULT_GAME_VERSION and not v.is_empty():
		return v
	var proj_v := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	if not proj_v.is_empty():
		return proj_v
	return v if not v.is_empty() else DEFAULT_GAME_VERSION


func _refresh_footer_labels() -> void:
	if footer_hint != null:
		var cname := creator_name.strip_edges()
		if cname.is_empty():
			cname = DEFAULT_CREATOR_NAME
		footer_hint.text = "Creador: %s" % cname
	if footer_version != null:
		var ver := _resolve_game_version()
		if ver.to_lower().begins_with("v"):
			footer_version.text = ver
		else:
			footer_version.text = "Versión %s" % ver


# =============================================================================
# PANTALLA 1: MENÚ PRINCIPAL
# =============================================================================

func _build_main_menu_screen() -> void:
	_main_menu_view = _MainMenuViewScene.instantiate()
	content_container.add_child(_main_menu_view)
	screen_main_menu = _main_menu_view as VBoxContainer
	main_menu_title = _main_menu_view.title_label
	btn_championship = _main_menu_view.btn_championship
	btn_rally = _main_menu_view.btn_rally
	btn_single_stage = _main_menu_view.btn_single_stage
	btn_exit = _main_menu_view.btn_exit
	_main_menu_view.mode_selected.connect(_on_mode_selected)
	_main_menu_view.exit_requested.connect(func() -> void: get_tree().quit())
	_main_menu_view.wire_focus()


# =============================================================================
# PANTALLA 2: SELECTOR DE TRAMO (StageSelectView .tscn)
# =============================================================================

func _build_stage_select_screen() -> void:
	_stage_select_view = _StageSelectViewScene.instantiate()
	content_container.add_child(_stage_select_view)
	screen_stage_select = _stage_select_view as VBoxContainer
	_stage_select_view.stage_selected.connect(_on_stage_selected)
	_stage_select_view.country_selected.connect(_on_country_selected)
	_stage_select_view.back_requested.connect(show_main_menu)
	_populate_stage_select_view()


func _populate_stage_select_view() -> void:
	if _stage_select_view == null:
		return
	_stage_select_view.populate({
		"cdi_mode": _cdi_launch,
		"selected_country": selected_country,
		"country_order": COUNTRY_ORDER,
		"country_labels": COUNTRY_LABELS,
		"stage_ids": _country_stage_ids(),
		"stage_metadata": STAGE_METADATA,
		"cdi_stages": CDI_STAGES,
		"routes_cache": stage_routes_cache,
		"title": _stage_select_title(),
	})
	stage_title_label = _stage_select_view.stage_title_label
	country_buttons = _stage_select_view.country_buttons
	stage_scroll = _stage_select_view.stage_scroll
	stage_strip = _stage_select_view.stage_strip
	stage_buttons = _stage_select_view.stage_buttons
	stage_previews = _stage_select_view.stage_previews
	btn_carousel_prev = _stage_select_view.btn_carousel_prev
	btn_carousel_next = _stage_select_view.btn_carousel_next
	carousel_page_label = _stage_select_view.carousel_page_label
	btn_stage_back = _stage_select_view.btn_stage_back
	carousel_scroll_index = _stage_select_view.carousel_scroll_index
	_update_stage_card_widths()


func _country_stage_ids() -> Array[String]:
	var out: Array[String] = []
	var count := int(COUNTRY_STAGE_COUNTS.get(selected_country, 10))
	for i in range(1, count + 1):
		out.append("%s_stage%d" % [selected_country, i])
	return out


func _stage_select_title() -> String:
	if _cdi_launch:
		return "Caminos del Inca"
	var count := int(COUNTRY_STAGE_COUNTS.get(selected_country, 10))
	var label := str(COUNTRY_LABELS.get(selected_country, selected_country.capitalize()))
	return "%s Stages · Especiales 1 a %d" % [label, count]


func _carousel_max_index() -> int:
	return _stage_select_view.carousel_max_index() if _stage_select_view != null else maxi(0, int(COUNTRY_STAGE_COUNTS.get(selected_country, 10)) - 4)


func _on_country_selected(country: String) -> void:
	if not COUNTRY_STAGE_COUNTS.has(country):
		return
	selected_country = country
	selected_stage_id = "%s_stage1" % country
	carousel_scroll_index = 0
	_populate_stage_select_view()
	if screen_stage_select != null:
		screen_stage_select.show()
	if not stage_buttons.is_empty() and is_instance_valid(stage_buttons[0]):
		stage_buttons[0].grab_focus()
	else:
		for b in country_buttons:
			if is_instance_valid(b) and not b.disabled:
				b.grab_focus()
				break


func _update_country_buttons() -> void:
	if _stage_select_view != null:
		_stage_select_view.update_country_buttons(selected_country)


func _update_stage_card_widths() -> void:
	if _stage_select_view != null:
		_stage_select_view.update_card_widths(get_viewport_rect().size.x)


func _on_carousel_prev_pressed() -> void:
	if _stage_select_view != null:
		_stage_select_view.scroll_prev()
		carousel_scroll_index = _stage_select_view.carousel_scroll_index


func _on_carousel_next_pressed() -> void:
	if _stage_select_view != null:
		_stage_select_view.scroll_next()
		carousel_scroll_index = _stage_select_view.carousel_scroll_index


func _scroll_carousel_to_index(idx: int) -> void:
	if _stage_select_view != null:
		_stage_select_view.scroll_to_index(idx)
		carousel_scroll_index = _stage_select_view.carousel_scroll_index


func _sync_carousel_on_focus(card_index: int) -> void:
	if _stage_select_view != null:
		_stage_select_view.sync_carousel_on_focus(card_index)
		carousel_scroll_index = _stage_select_view.carousel_scroll_index


func _update_carousel_ui() -> void:
	if _stage_select_view != null:
		_stage_select_view.update_carousel_ui()


# =============================================================================
# PANTALLA 3: SELECTOR DE COCHE (CarSelectView .tscn + SHOWROOM 3D)
# =============================================================================

func _build_car_select_screen() -> void:
	_car_select_view = _CarSelectViewScene.instantiate()
	content_container.add_child(_car_select_view)
	screen_car_select = _car_select_view as VBoxContainer
	var vehicles: Dictionary = vehicle_registry.get("vehicles", {})
	_car_select_view.populate_vehicles(vehicles, _cdi_launch, CDI_CARS)
	_car_select_view.populate_liveries(VehicleLiveryScript.get_liveries())

	car_title = _car_select_view.car_title
	car_scroll = _car_select_view.car_scroll
	car_buttons = _car_select_view.car_buttons
	btn_car_back = _car_select_view.btn_back
	btn_car_confirm = _car_select_view.btn_confirm
	livery_panel = _car_select_view.livery_panel
	livery_name_label = _car_select_view.livery_name_label
	livery_hex_label = _car_select_view.livery_hex_label
	livery_buttons = _car_select_view.livery_buttons
	btn_livery_prev = _car_select_view.btn_livery_prev
	btn_livery_next = _car_select_view.btn_livery_next
	preview_car_title = _car_select_view.preview_car_title
	preview_car_category = _car_select_view.preview_car_category
	preview_layout_badge = _car_select_view.preview_layout_badge
	spec_power_val = _car_select_view.spec_power_val
	spec_power_sub = _car_select_view.spec_power_sub
	spec_gears_val = _car_select_view.spec_gears_val
	spec_gears_sub = _car_select_view.spec_gears_sub
	spec_wb_val = _car_select_view.spec_wb_val
	spec_wb_sub = _car_select_view.spec_wb_sub
	spec_track_val = _car_select_view.spec_track_val
	spec_track_sub = _car_select_view.spec_track_sub
	spec_mass_val = _car_select_view.spec_mass_val
	spec_mass_sub = _car_select_view.spec_mass_sub
	spec_layout_val = _car_select_view.spec_layout_val
	spec_layout_sub = _car_select_view.spec_layout_sub

	_car_select_view.car_pressed.connect(_on_car_button_pressed)
	_car_select_view.confirm_pressed.connect(func() -> void: _on_car_selected(selected_car_key))
	_car_select_view.back_requested.connect(show_stage_select)
	_car_select_view.livery_selected.connect(_select_livery)
	_car_select_view.livery_cycled.connect(_cycle_livery)
	_update_car_list_visuals()


# =============================================================================
# PANTALLA 4: SELECTOR DE CLIMA INICIAL (INTERMEDIAS EXCLUSIVAS)
# =============================================================================

func _build_weather_select_screen() -> void:
	_weather_view = _WeatherSelectViewScene.instantiate()
	content_container.add_child(_weather_view)
	screen_weather_select = _weather_view as VBoxContainer
	weather_buttons = _weather_view.weather_buttons
	btn_weather_back = _weather_view.btn_back
	btn_weather_confirm = _weather_view.btn_confirm
	_weather_view.set_selected_weather(selected_weather)
	_weather_view.weather_selected.connect(func(wid: String) -> void:
		selected_weather = wid
	)
	_weather_view.weather_confirmed.connect(func(wid: String) -> void:
		selected_weather = wid
		_on_weather_confirmed()
	)
	_weather_view.back_requested.connect(show_car_select)


# =============================================================================
# MANEJO DE PANTALLAS Y FOCO
# =============================================================================

func show_main_menu() -> void:
	current_screen = "menu"
	screen_stage_select.hide()
	screen_car_select.hide()
	if screen_weather_select != null:
		screen_weather_select.hide()
	screen_main_menu.show()
	RallyUITheme.transition_control(screen_main_menu, true)
	_hide_status()

	# La info tachada de la captura (cabecera sup. izq/der) se oculta en el principal;
	# el título vive ahora en el centro (main_menu_title).
	if header_hbox_ref != null:
		header_hbox_ref.hide()
	if header_line_ref != null:
		header_line_ref.hide()
	badge_top.text = "PANTALLA"
	badge_bottom.text = "RALLY MANIAC"

	_start_photo_slideshow()
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
	if screen_weather_select != null:
		screen_weather_select.hide()
	screen_stage_select.show()
	RallyUITheme.transition_control(screen_stage_select, true)
	_hide_status()

	if header_hbox_ref != null:
		header_hbox_ref.show()
	if header_line_ref != null:
		header_line_ref.show()
	if header_subtitle != null:
		header_subtitle.hide()
	if header_badge_vbox != null:
		header_badge_vbox.hide()
	badge_top.text = "MODO: " + selected_mode.to_upper()
	badge_bottom.text = "SELECCIONAR TRAMO"

	_stop_photo_slideshow(false)
	_update_stage_card_widths()
	call_deferred("_focus_stage_button")


func _focus_stage_button() -> void:
	for i in stage_buttons.size():
		var btn: Button = stage_buttons[i]
		if str(btn.get_meta("stage_id", "")) == selected_stage_id:
			btn.grab_focus()
			_sync_carousel_on_focus(i)
			return
	if not stage_buttons.is_empty():
		stage_buttons[0].grab_focus()
		_sync_carousel_on_focus(0)


func show_car_select() -> void:
	_confirmed_car_click_key = ""
	if _cdi_launch:
		car_title.text = "Caminos del Inca · SS%02d %s" % [
			int(selected_stage_id.get_slice("_stage", 1)), CDI_STAGES[selected_stage_id].name,
		]
	current_screen = "car_select"
	screen_main_menu.hide()
	screen_stage_select.hide()
	if screen_weather_select != null:
		screen_weather_select.hide()
	screen_car_select.show()
	RallyUITheme.transition_control(screen_car_select, true)
	_hide_status()

	if header_hbox_ref != null:
		header_hbox_ref.show()
	if header_line_ref != null:
		header_line_ref.show()
	if header_subtitle != null:
		header_subtitle.hide()
	if header_badge_vbox != null:
		header_badge_vbox.hide()
	badge_top.text = "TRAMO: " + selected_stage_id.to_upper()
	badge_bottom.text = "SELECCIONAR COCHE"

	_stop_photo_slideshow()
	_preview_car(selected_car_key)
	call_deferred("_focus_car_button")


func _focus_car_button() -> void:
	for btn in car_buttons:
		if str(btn.get_meta("car_key", "")) == selected_car_key:
			btn.grab_focus()
			_preview_car(selected_car_key)
			if car_scroll != null:
				car_scroll.ensure_control_visible(btn)
			return
	if not car_buttons.is_empty():
		car_buttons[0].grab_focus()
		var first_key := str(car_buttons[0].get_meta("car_key", ""))
		_preview_car(first_key)
		if car_scroll != null:
			car_scroll.ensure_control_visible(car_buttons[0])


func show_weather_select() -> void:
	current_screen = "weather_select"
	screen_main_menu.hide()
	screen_stage_select.hide()
	screen_car_select.hide()
	if screen_weather_select != null:
		screen_weather_select.show()
		RallyUITheme.transition_control(screen_weather_select, true)
	_hide_status()

	if header_hbox_ref != null:
		header_hbox_ref.show()
	if header_line_ref != null:
		header_line_ref.show()
	if header_subtitle != null:
		header_subtitle.hide()
	if header_badge_vbox != null:
		header_badge_vbox.show()
	badge_top.text = "CONDICIÓN"
	badge_bottom.text = "CLIMA INICIAL"

	_stop_photo_slideshow(false)
	_update_weather_cards_visuals()
	call_deferred("_focus_weather_button")


func _focus_weather_button() -> void:
	for btn in weather_buttons:
		if str(btn.get_meta("weather_id", "")) == selected_weather:
			btn.grab_focus()
			return
	if not weather_buttons.is_empty():
		weather_buttons[0].grab_focus()


func _select_weather(weather_id: String) -> void:
	selected_weather = weather_id
	_update_weather_cards_visuals()


func _update_weather_cards_visuals() -> void:
	if _weather_view != null:
		_weather_view.set_selected_weather(selected_weather)


func _on_weather_confirmed() -> void:
	if is_loading:
		return
	_launch_session()


# =============================================================================
# SELECCIÓN Y CONFIRMACIÓN
# =============================================================================

func _on_mode_selected(mode: String) -> void:
	selected_mode = mode
	show_stage_select()


func _on_stage_selected(stage_id: String) -> void:
	selected_stage_id = stage_id
	show_car_select()


func _on_car_button_pressed(car_key: String) -> void:
	if is_loading:
		return
	if _cdi_launch and car_key not in CDI_CARS:
		return
	if _confirmed_car_click_key == car_key and selected_car_key == car_key:
		_on_car_selected(car_key)
		return
	_confirmed_car_click_key = car_key
	_preview_car(car_key)


func _on_car_selected(car_key: String) -> void:
	if is_loading:
		return
	if _cdi_launch and car_key not in CDI_CARS:
		return
	selected_car_key = car_key
	if selected_livery_id.is_empty() or not VehicleLiveryScript.is_valid_livery(selected_livery_id):
		selected_livery_id = str(selected_livery_by_car.get(car_key, VehicleLiveryScript.default_livery_for(car_key)))
	selected_livery_by_car[car_key] = selected_livery_id
	show_weather_select()


func _select_livery(livery_id: String) -> void:
	if not VehicleLiveryScript.is_valid_livery(livery_id):
		return
	selected_livery_id = livery_id
	if not selected_car_key.is_empty():
		selected_livery_by_car[selected_car_key] = livery_id
	_update_livery_ui()
	_apply_preview_livery()


func _cycle_livery(delta: int) -> void:
	var all := VehicleLiveryScript.get_liveries()
	if all.is_empty():
		return
	var current_idx := 0
	for i in all.size():
		if str(all[i].get("id", "")) == selected_livery_id:
			current_idx = i
			break
	var next_idx := posmod(current_idx + delta, all.size())
	_select_livery(str(all[next_idx].get("id", "")))


func _update_livery_ui() -> void:
	var entry := VehicleLiveryScript.get_livery(selected_livery_id)
	if _car_select_view != null:
		_car_select_view.update_livery_visuals(selected_livery_id, entry)


func _apply_preview_livery() -> void:
	if current_car_model_instance != null and is_instance_valid(current_car_model_instance):
		VehicleLiveryScript.apply_to_vehicle(current_car_model_instance, selected_car_key, selected_livery_id)


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
	var loading_overlay := get_node_or_null("/root/RallyLoadingOverlay")
	if loading_overlay != null and loading_overlay.has_method("show_loading"):
		loading_overlay.call("show_loading", "Loading...")
		await get_tree().process_frame
	var packed: PackedScene = null
	if loading_overlay != null and loading_overlay.has_method("load_packed_scene_async"):
		packed = await loading_overlay.load_packed_scene_async(scene_path)
	else:
		packed = load(scene_path) as PackedScene
	if packed == null:
		if loading_overlay != null and loading_overlay.has_method("hide_loading"):
			loading_overlay.call("hide_loading")
		_show_error("No se pudo cargar la escena: %s" % scene_path)
		_set_loading(false)
		return

	var session := packed.instantiate() as RallyRussiaStageSession
	if session == null:
		if loading_overlay != null and loading_overlay.has_method("hide_loading"):
			loading_overlay.call("hide_loading")
		_show_error("La escena %s no es un RallyRussiaStageSession válido." % scene_path)
		_set_loading(false)
		return

	# Transferir modo, ID de tramo, coche seleccionado, livery y clima inicial
	var active_livery_id := selected_livery_id
	if active_livery_id.is_empty() or not VehicleLiveryScript.is_valid_livery(active_livery_id):
		active_livery_id = str(selected_livery_by_car.get(selected_car_key, VehicleLiveryScript.default_livery_for(selected_car_key)))
	session.track_id = selected_stage_id
	session.session_track_id = selected_stage_id
	session.set("session_mode", selected_mode)
	session.set("selected_vehicle_key", selected_car_key)
	session.set("selected_livery_id", active_livery_id)
	session.set("selected_weather", selected_weather)
	if CDI_STAGES.has(selected_stage_id):
		session.stage_place = str(CDI_STAGES[selected_stage_id].name)
		session.stage_country = "Perú"
		var stage_camera := session.get_node_or_null("RallyCameraRig/Camera3D") as Camera3D
		if stage_camera != null:
			stage_camera.far = 18000.0

	if selected_mode in ["rally", "championship"]:
		var manager := EventManagerScript.new()
		var country := str(selected_stage_id).split("_stage")[0].to_lower()
		var choices := {
			"start_stage_id": selected_stage_id,
			"initial_weather": selected_weather,
			"livery_id": active_livery_id,
			"event_path": str(EVENT_PATH_BY_COUNTRY.get(country, EVENT_PATH_BY_COUNTRY["russia"])),
		}
		if selected_mode == "championship":
			choices["save_path"] = "user://championship_event_v1.json"
			choices["carry_championship_points"] = true
		elif country == "cdi":
			choices["save_path"] = "user://cdi_rally_event_v1.json"
		if not manager.begin_event(choices):
			if loading_overlay != null and loading_overlay.has_method("hide_loading"):
				loading_overlay.call("hide_loading")
			_show_error("Error al iniciar el evento: %s" % manager.error)
			_set_loading(false)
			return
		session.begin_event_session(manager, selected_stage_id)
	else:
		# Single Stage: sesión independiente de un tramo sin guardado oficial
		session.practice_mode = true
		session.competition.save_path = ""
		session.set("single_stage_weather", selected_weather)

	# Liberar mapas fuente de livery del menú antes de cargar el tramo
	VehicleLiveryScript.clear_data_map_cache()
	if preview_viewport != null:
		preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

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
	if btn_car_confirm != null:
		btn_car_confirm.disabled = loading
	for btn in livery_buttons:
		btn.disabled = loading
	if btn_livery_prev != null:
		btn_livery_prev.disabled = loading
	if btn_livery_next != null:
		btn_livery_next.disabled = loading
	for btn in weather_buttons:
		btn.disabled = loading
	if btn_weather_back != null:
		btn_weather_back.disabled = loading
	if btn_weather_confirm != null:
		btn_weather_confirm.disabled = loading


func _show_error(msg: String) -> void:
	if _notice_banner != null:
		_notice_banner.show_notice("⚠ " + msg, true)


func _show_notice(msg: String, is_err: bool = false) -> void:
	if _notice_banner != null:
		_notice_banner.show_notice(("⚠ " if is_err else "ℹ ") + msg, is_err)


func _hide_status() -> void:
	if _notice_banner != null:
		_notice_banner.clear_notice()


# =============================================================================
# DATOS DE VEHÍCULOS Y TRAZADOS DE TRAMOS
# =============================================================================

func _load_registry() -> void:
	if FileAccess.file_exists(REGISTRY_PATH):
		var text := FileAccess.get_file_as_string(REGISTRY_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			vehicle_registry = parsed
			return
	push_warning("No se pudo cargar el registro de vehículos desde " + REGISTRY_PATH)


func _load_all_vehicle_specs() -> void:
	vehicle_specs_cache.clear()
	var vehicles: Dictionary = vehicle_registry.get("vehicles", {})
	for car_key in vehicles:
		var v_data: Dictionary = vehicles[car_key]
		var prof: String = str(v_data.get("Profile", ""))
		var ch_path := "res://data/vehicles/" + prof + "/chassis.json"
		var pw_path := "res://data/vehicles/" + prof + "/powertrain.json"

		var ch: Dictionary = {}
		var pw: Dictionary = {}
		if FileAccess.file_exists(ch_path):
			var ch_txt := FileAccess.get_file_as_string(ch_path)
			var parsed_ch = JSON.parse_string(ch_txt)
			if parsed_ch is Dictionary:
				ch = parsed_ch
		if FileAccess.file_exists(pw_path):
			var pw_txt := FileAccess.get_file_as_string(pw_path)
			var parsed_pw = JSON.parse_string(pw_txt)
			if parsed_pw is Dictionary:
				pw = parsed_pw

		var geom: Dictionary = ch.get("geometry", {})
		var pwt: Dictionary = pw.get("powertrain", {})
		var ch_data: Dictionary = ch.get("chassis", {})

		var max_t: float = float(pwt.get("max_torque", 0.0))
		var max_rpm: float = float(pwt.get("max_rpm", 0.0))
		var t_curve: Array = pwt.get("torque_curve", [])
		var peak_w := 0.0
		var peak_rpm_val := 0.0
		for pt in t_curve:
			var nrpm: float = float(pt[0])
			var nt: float = float(pt[1])
			var r: float = nrpm * max_rpm
			var t: float = nt * max_t
			var w: float = t * r * 2.0 * PI / 60.0
			if w > peak_w:
				peak_w = w
				peak_rpm_val = r
		var cv := int(round(peak_w / 735.49875))
		var kw := int(round(peak_w / 1000.0))

		var gears := (pwt.get("gear_ratios", []) as Array).size()
		var wb: float = float(geom.get("wheelbase", 0.0))
		var ft: float = float(geom.get("front_track", 0.0))
		var rt: float = float(geom.get("rear_track", 0.0))
		var mass := int(round(float(ch_data.get("vehicle_mass", 0.0))))

		var split := float(pwt.get("front_torque_split", 0.0))
		var engine_z := 0.0
		for comp in ch.get("physical_mass_inventory", {}).get("components", []):
			var pname: String = str(comp.get("properties", {}).get("name", "")).to_lower()
			if "engine" in pname:
				engine_z = float(comp.get("properties", {}).get("center_of_mass_in_attachment_metres", {}).get("z", 0.0))
				break

		var layout_code := "FR"
		var layout_name := "Motor delantero / Propulsión trasera"
		if split >= 0.9:
			layout_code = "FF"
			layout_name = "Motor delantero / Tracción delantera"
		elif split <= 0.1:
			if engine_z > wb * 0.5:
				layout_code = "RR"
				layout_name = "Motor trasero / Propulsión trasera"
			elif engine_z > 0.1:
				layout_code = "MR"
				layout_name = "Motor central / Propulsión trasera"
			else:
				layout_code = "FR"
				layout_name = "Motor delantero / Propulsión trasera"
		else:
			layout_code = "4WD"
			layout_name = "Tracción integral permanente"

		vehicle_specs_cache[str(car_key)] = {
			"power_str": "%d CV (%d kW)" % [cv, kw],
			"power_sub": "@ %d RPM" % int(round(peak_rpm_val if peak_rpm_val > 0 else max_rpm)),
			"gears_str": "%d marchas" % gears,
			"gears_sub": "Manual sincronizada",
			"wb_str": "%.2f m" % wb,
			"wb_sub": "Distancia entre ejes",
			"track_str": "%.2f / %.2f m" % [ft, rt],
			"track_sub": "Vía delantera / trasera",
			"mass_str": "%d kg" % mass,
			"mass_sub": "Peso mínimo homologado",
			"layout_code": layout_code,
			"layout_name": layout_name,
			"layout_sub": "Configuración tren motriz"
		}


func _load_all_stage_routes() -> void:
	stage_routes_cache.clear()
	var all_ids: Array[String] = []
	for country in COUNTRY_ORDER:
		var count := int(COUNTRY_STAGE_COUNTS.get(country, 0))
		for i in range(1, count + 1):
			all_ids.append("%s_stage%d" % [country, i])
	if _cdi_launch:
		all_ids = _country_stage_ids()
	for sid in all_ids:
		var path := "res://data/rally/%s_route.json" % sid
		var reverse_route := false
		if _cdi_launch:
			var config_path := "res://data/competition/stages/%s.json" % sid
			var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
			if config is Dictionary:
				path = str(config.get("route_path", path))
				reverse_route = bool(config.get("reverse_route", false))
		if not FileAccess.file_exists(path):
			continue
		var json_str := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(json_str)
		if not (parsed is Dictionary):
			continue
		var raw_pts: Array = parsed.get("points", [])
		if reverse_route:
			raw_pts.reverse()
		var norm_pts := _compute_vertical_route_points(raw_pts)
		stage_routes_cache[sid] = norm_pts


func _compute_vertical_route_points(raw_points: Array) -> PackedVector2Array:
	if raw_points.size() < 2:
		return PackedVector2Array()

	var pts_2d: Array[Vector2] = []
	var center := Vector2.ZERO
	for p in raw_points:
		if p is Array and p.size() >= 3:
			var v := Vector2(float(p[0]), float(p[2]))
			pts_2d.append(v)
			center += v
	if pts_2d.size() < 2:
		return PackedVector2Array()
	center /= float(pts_2d.size())

	var xx := 0.0
	var yy := 0.0
	var xy := 0.0
	for v in pts_2d:
		var off := v - center
		xx += off.x * off.x
		yy += off.y * off.y
		xy += off.x * off.y

	var angle := -PI * 0.5 - atan2(2.0 * xy, xx - yy) * 0.5
	var route_dir := pts_2d[-1] - pts_2d[0]
	# Asegurar que el vector salida->llegada quede orientado verticalmente (Salida abajo, Llegada arriba)
	if route_dir.rotated(angle).y > 0.0:
		angle += PI

	var rotated_pts: Array[Vector2] = []
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for v in pts_2d:
		var rot_v := v.rotated(angle)
		rotated_pts.append(rot_v)
		min_v = min_v.min(rot_v)
		max_v = max_v.max(rot_v)

	var extent := max_v - min_v
	var max_dim := maxf(extent.x, extent.y)
	max_dim = maxf(max_dim, 0.001)

	var normalized := PackedVector2Array()
	for rot_v in rotated_pts:
		normalized.append((rot_v - min_v) / max_dim)
	return normalized


# =============================================================================
# FONDO DE FOTOS HISTÓRICAS PARA EL MENÚ PRINCIPAL
# =============================================================================

func _setup_photo_background() -> void:
	photo_paths = _discover_photo_paths()
	if photo_paths.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	current_photo_index = rng.randi_range(0, photo_paths.size() - 1)

	photo_container = Control.new()
	photo_container.name = "PhotoBackgroundContainer"
	photo_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	photo_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(photo_container)

	photo_rect = TextureRect.new()
	photo_rect.name = "PhotoRect"
	photo_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	photo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo_container.add_child(photo_rect)

	photo_timer = Timer.new()
	photo_timer.name = "PhotoTimer"
	photo_timer.one_shot = true
	photo_timer.wait_time = 4.0
	photo_timer.timeout.connect(_on_photo_timer_timeout)
	photo_container.add_child(photo_timer)

	_show_photo_at_index(current_photo_index)


func _discover_photo_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(PHOTOS_DIR)
	if dir == null:
		dir = DirAccess.open(ProjectSettings.globalize_path(PHOTOS_DIR))
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".import"):
				continue
			var lower := f.to_lower()
			if lower.ends_with(".jpg") or lower.ends_with(".jpeg") or lower.ends_with(".png") or lower.ends_with(".webp"):
				paths.append(PHOTOS_DIR + "/" + f)
	paths.sort()
	return paths


func _get_photo_texture(path: String) -> Texture2D:
	if photo_textures.has(path):
		return photo_textures[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		var abs_path := ProjectSettings.globalize_path(path)
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if tex != null:
		photo_textures[path] = tex
	return tex


func _show_photo_at_index(index: int) -> void:
	if photo_paths.is_empty() or photo_rect == null:
		return
	var idx := posmod(index, photo_paths.size())
	var path: String = photo_paths[idx]
	var tex := _get_photo_texture(path)
	if tex != null:
		photo_rect.texture = tex
	var next_idx := (idx + 1) % photo_paths.size()
	_get_photo_texture(photo_paths[next_idx])


func _start_photo_slideshow() -> void:
	if preview_viewport != null:
		preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if photo_paths.is_empty():
		return
	if showroom_container != null:
		showroom_container.hide()
	if photo_container != null:
		photo_container.show()
	if photo_rect != null and photo_rect.texture == null:
		_show_photo_at_index(current_photo_index)
	if photo_rect != null:
		photo_rect.modulate.a = 1.0
	if photo_timer != null:
		photo_timer.start(4.0)


func _stop_photo_slideshow(show_showroom: bool = true) -> void:
	if photo_timer != null:
		photo_timer.stop()
	if photo_tween != null and photo_tween.is_valid():
		photo_tween.kill()
	if photo_container != null:
		photo_container.hide()
	if showroom_container != null:
		showroom_container.visible = show_showroom
	if preview_viewport != null:
		preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if show_showroom else SubViewport.UPDATE_DISABLED


func _on_photo_timer_timeout() -> void:
	if current_screen != "menu" or photo_paths.is_empty() or photo_rect == null or not is_instance_valid(photo_rect):
		return
	if photo_tween != null and photo_tween.is_valid():
		photo_tween.kill()

	photo_tween = create_tween()
	photo_tween.tween_property(photo_rect, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	photo_tween.tween_callback(func():
		current_photo_index = (current_photo_index + 1) % photo_paths.size()
		_show_photo_at_index(current_photo_index)
	)
	photo_tween.tween_property(photo_rect, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	photo_tween.tween_callback(func():
		if current_screen == "menu" and photo_timer != null and is_instance_valid(photo_timer):
			photo_timer.start(4.0)
	)


# =============================================================================
# SHOWROOM 3D FULLSCREEN
# =============================================================================

func _setup_3d_preview_scene() -> void:
	if preview_viewport == null:
		return

	var env := WorldEnvironment.new()
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color("#070b0f")
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color("#384c5c")
	env_res.ambient_light_energy = 0.90
	env.environment = env_res
	preview_viewport.add_child(env)

	# Luces de estudio (3-point lighting suave)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-32, 38, 0)
	key_light.light_color = Color("#ffffff")
	key_light.light_energy = 1.60
	preview_viewport.add_child(key_light)

	var rim_light := DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(22, -145, 0)
	rim_light.light_color = Color("#5fa8e0")
	rim_light.light_energy = 1.10
	preview_viewport.add_child(rim_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-65, -45, 0)
	fill_light.light_color = Color("#f0e6d2")
	fill_light.light_energy = 0.40
	preview_viewport.add_child(fill_light)

	# Mesa giratoria (Turntable) desplazada levemente a la derecha para compensar la lista izquierda
	car_turntable = Node3D.new()
	car_turntable.position = Vector3(0.55, 0.0, 0.0)
	preview_viewport.add_child(car_turntable)
	car_turntable.rotation_degrees.y = 28.0

	# Plataforma / Disco de exhibición minimalista oscuro
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.45
	cyl.bottom_radius = 2.55
	cyl.height = 0.04
	disc.mesh = cyl
	disc.position.y = -0.02
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color("#0c1218")
	disc_mat.metallic = 0.5
	disc_mat.roughness = 0.4
	disc.material_override = disc_mat
	car_turntable.add_child(disc)

	# Anillo decorativo iluminado suave en el borde del disco
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.40
	torus.outer_radius = 2.44
	ring.mesh = torus
	ring.position.y = 0.005
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color("#ffffff")
	ring_mat.emission_enabled = true
	ring_mat.emission = Color("#e5a93c")
	ring_mat.emission_energy_multiplier = 0.6
	ring.material_override = ring_mat
	car_turntable.add_child(ring)

	# Cámara showroom
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(3.6, 1.35, 4.2)
	preview_viewport.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0.55, 0.45, 0.0))

	# Instanciar el coche inicial en el showroom
	_preview_car(selected_car_key)


func _preview_car(car_key: String) -> void:
	if car_key.is_empty():
		return
	selected_car_key = car_key

	var specs: Dictionary = vehicle_specs_cache.get(car_key, {})
	var v_data: Dictionary = vehicle_registry.get("vehicles", {}).get(car_key, {})
	var display_name := str(v_data.get("DisplayName", car_key))
	if _car_select_view != null:
		_car_select_view.update_specs(display_name, specs)

	_update_car_list_visuals()
	selected_livery_id = str(selected_livery_by_car.get(car_key, VehicleLiveryScript.default_livery_for(car_key)))
	if not VehicleLiveryScript.is_valid_livery(selected_livery_id):
		selected_livery_id = VehicleLiveryScript.default_livery_for(car_key)
	selected_livery_by_car[car_key] = selected_livery_id
	_update_livery_ui()

	if car_turntable == null or not is_instance_valid(car_turntable):
		return

	if car_key == current_preview_car_key and current_car_model_instance != null and is_instance_valid(current_car_model_instance):
		_apply_preview_livery()
		return

	current_preview_car_key = car_key

	if current_car_model_instance != null and is_instance_valid(current_car_model_instance):
		current_car_model_instance.queue_free()
		car_turntable.remove_child(current_car_model_instance)
		current_car_model_instance = null

	var scene_name := str(v_data.get("Scene", ""))
	var scene_path := "res://scenes/rally/%s.tscn" % scene_name
	if ResourceLoader.exists(scene_path):
		var packed := load(scene_path) as PackedScene
		if packed != null:
			var car_node := packed.instantiate()
			if car_node is RigidBody3D:
				car_node.freeze = true
			car_node.process_mode = Node.PROCESS_MODE_DISABLED
			car_node.position = Vector3.ZERO
			car_turntable.add_child(car_node)
			current_car_model_instance = car_node
			_apply_preview_livery()


func _update_car_list_visuals() -> void:
	if _car_select_view != null:
		_car_select_view.update_car_list_visuals(selected_car_key)
