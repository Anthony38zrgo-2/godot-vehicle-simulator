class_name RallyManiacMenu
extends Control

# =============================================================================
# CONSTANTES VISUALES — SISTEMA DE DISEÑO MOTORSPORT MINIMALISTA (FLAT PRECISION)
# =============================================================================

# 2.2. Estandarización Tipográfica (Sin fuentes Serif)
const FONT_TITLE: Font = preload("res://fonts/montserrat/Montserrat-Bold.ttf")
const FONT_REGULAR: Font = preload("res://fonts/montserrat/Montserrat-Regular.ttf")
const FONT_UI: Font = preload("res://fonts/D-DIN.ttf")
const FONT_UI_BOLD: Font = preload("res://fonts/D-DIN-Bold.ttf")
# Libron para opciones del menú principal (verificado en res://fonts/libron/)
const FONT_LIBRON: Font = preload("res://fonts/libron/Libron-Regular.ttf")
const FONT_LIBRON_BOLD: Font = preload("res://fonts/libron/Libron-Bold.ttf")
const FONT_LIBRON_ITALIC: Font = preload("res://fonts/libron/Libron-Italic.ttf")
const FONT_LIBRON_BOLD_ITALIC: Font = preload("res://fonts/libron/Libron-BoldItalic.ttf")
# Montserrat Bold Italic no existe como TTF en el proyecto (solo Bold/Regular);
# el título central usa faux-italic vía FontVariation (ver _montserrat_bold_italic()).
var _montserrat_bold_italic_cache: FontVariation

# 2.1. Paleta de Colores Funcional Unificada
const BG_BASE := Color("#0a0e14")         # Negro carbón mate
const BG_SURFACE := Color("#121820")      # Superficie de tarjetas y paneles
const BG_HOVER := Color("#1c2430")        # Interacción y selección
const BORDER_SUBTLE := Color(1.0, 1.0, 1.0, 0.08) # 1 px sin relieves ni biseles
const BORDER_FOCUS := Color("#ffffff")              # Blanco puro para foco
const TEXT_PRIMARY := Color("#f0f4f8")    # Blanco suave, contraste óptimo
const TEXT_MUTED := Color("#6b7a8d")      # Gris medio para etiquetas secundarias
const ACCENT_RALLY := Color("#e5a93c")    # Dorado histórico sobrio
const ACCENT_ALERT := Color("#f59e0b")    # Ámbar rally alertas
const STATUS_DANGER := Color("#ef4444")   # Pinchazos, abandonos, errores
const STATUS_SUCCESS := Color("#22c55e")  # Tiempos récord, verde de salida

# Aliases de compatibilidad interna
const C_BACK := BG_BASE
const C_GLASS := BG_SURFACE
const C_GLASS_DEEP := Color("#090e14")
const C_RIM := BORDER_SUBTLE
const C_CHROME_TEXT := TEXT_PRIMARY
const C_CHROME_DIM := TEXT_MUTED
const C_BLUE := Color("#5fa8e0")
const C_BLUE_DEEP := Color("#1a3144")

const C_FACE := BG_SURFACE
const C_FACE_HI := BG_HOVER
const C_FACE_LO := Color("#080c10")
const C_FIELD := Color("#080c10")
const C_HI := Color("#8ba6be")
const C_LIGHT := Color("#4b6072")
const C_SHADOW := BG_BASE
const C_DARK := Color("#000000")
const C_TEXT := TEXT_PRIMARY
const C_DIM := TEXT_MUTED
const C_GOLD := ACCENT_RALLY
const C_GOLD_HI := Color("#f8df9e")
const C_ROSE := STATUS_DANGER
const C_SEL := BG_HOVER
const C_GREEN := STATUS_SUCCESS

const REGISTRY_PATH := "res://data/vehicles/registry.json"
const DEFAULT_CREATOR_NAME := "DoomerDoge38"
const DEFAULT_GAME_VERSION := "1.0"
const StageLoaderScript := preload("res://scripts/rally/rally_stage_loader.gd")
const EventManagerScript := preload("res://scripts/rally/rally_event_manager.gd")

const STAGE_METADATA := {
	"russia_stage1": {"km": "5.0 KM", "surface": "Grava y barro", "tag": "Técnico"},
	"russia_stage2": {"km": "4.9 KM", "surface": "Tierra rápida", "tag": "Veloz"},
	"russia_stage3": {"km": "3.3 KM", "surface": "Tierra y nieve", "tag": "Mixto"},
	"russia_stage4": {"km": "5.4 KM", "surface": "Grava técnica", "tag": "Curvas"},
	"russia_stage5": {"km": "5.5 KM", "surface": "Grava húmeda", "tag": "Rápido"},
	"russia_stage6": {"km": "4.8 KM", "surface": "Tierra y bosque", "tag": "Estrecho"},
	"russia_stage7": {"km": "4.8 KM", "surface": "Nieve compacta", "tag": "Deslizante"},
	"russia_stage8": {"km": "4.6 KM", "surface": "Grava helada", "tag": "Técnico"},
	"russia_stage9": {"km": "1.4 KM", "surface": "Sprint corto", "tag": "Sprint"},
	"russia_stage10": {"km": "2.4 KM", "surface": "Super especial", "tag": "Final"},
	"kenya_stage1": {"km": "4.6 KM", "surface": "Grava africana", "tag": "Sabana"},
	"kenya_stage2": {"km": "6.8 KM", "surface": "Grava africana", "tag": "Rápido"},
	"kenya_stage3": {"km": "4.2 KM", "surface": "Tierra y selva", "tag": "Técnico"},
	"kenya_stage4": {"km": "5.0 KM", "surface": "Grava africana", "tag": "Curvas"},
	"kenya_stage5": {"km": "7.0 KM", "surface": "Tierra y río", "tag": "Resistencia"},
	"kenya_stage6": {"km": "6.8 KM", "surface": "Grava africana", "tag": "Rápido"},
	"kenya_stage7": {"km": "5.4 KM", "surface": "Sabana y chozas", "tag": "Estrecho"},
	"kenya_stage8": {"km": "2.4 KM", "surface": "Sprint sabana", "tag": "Sprint"},
	"finland_stage1": {"km": "4.5 KM", "surface": "Grava rápida", "tag": "Veloz"},
	"finland_stage2": {"km": "4.5 KM", "surface": "Grava y bosque", "tag": "Saltos"},
	"finland_stage3": {"km": "4.4 KM", "surface": "Grava rápida", "tag": "Ciego"},
	"finland_stage4": {"km": "4.9 KM", "surface": "Tierra y lagos", "tag": "Rápido"},
	"finland_stage5": {"km": "4.9 KM", "surface": "Grava y asfalto", "tag": "Mixto"},
	"finland_stage6": {"km": "4.7 KM", "surface": "Bosque y cercas", "tag": "Estrecho"},
	"finland_stage7": {"km": "2.2 KM", "surface": "Sprint bosque", "tag": "Sprint"},
	"finland_stage8": {"km": "2.8 KM", "surface": "Tierra rápida", "tag": "Final"},
	"sweden_stage1": {"km": "4.8 KM", "surface": "Nieve / hielo", "tag": "Deslizante"},
	"sweden_stage2": {"km": "4.8 KM", "surface": "Nieve compacta", "tag": "Veloz"},
	"sweden_stage3": {"km": "4.4 KM", "surface": "Nieve y bosque", "tag": "Técnico"},
	"sweden_stage4": {"km": "4.9 KM", "surface": "Hielo y nieve", "tag": "Rápido"},
	"sweden_stage5": {"km": "3.8 KM", "surface": "Nieve / hielo", "tag": "Estrecho"},
	"sweden_stage6": {"km": "3.3 KM", "surface": "Pista nevada", "tag": "Curvas"},
	"sweden_stage7": {"km": "1.6 KM", "surface": "Sprint nieve", "tag": "Sprint"},
	"sweden_stage8": {"km": "2.3 KM", "surface": "Hielo final", "tag": "Final"},
	"switzerland_stage1": {"km": "4.7 KM", "surface": "Asfalto alpino", "tag": "Montaña"},
	"switzerland_stage2": {"km": "3.8 KM", "surface": "Asfalto y puente", "tag": "Técnico"},
	"switzerland_stage3": {"km": "3.2 KM", "surface": "Asfalto alpino", "tag": "Horquillas"},
	"switzerland_stage4": {"km": "4.6 KM", "surface": "Túnel y asfalto", "tag": "Rápido"},
	"switzerland_stage5": {"km": "4.2 KM", "surface": "Asfalto alpino", "tag": "Curvas"},
	"switzerland_stage6": {"km": "4.6 KM", "surface": "Túnel largo", "tag": "Ciego"},
	"switzerland_stage7": {"km": "2.7 KM", "surface": "Sprint alpino", "tag": "Sprint"},
	"switzerland_stage8": {"km": "2.4 KM", "surface": "Asfalto final", "tag": "Final"},
}

const COUNTRY_ORDER: Array[String] = ["russia", "kenya", "finland", "sweden", "switzerland"]
const COUNTRY_LABELS := {
	"russia": "Russia",
	"kenya": "Kenya",
	"finland": "Finland",
	"sweden": "Sweden",
	"switzerland": "Switzerland",
}
const COUNTRY_STAGE_COUNTS := {
	"russia": 10,
	"kenya": 8,
	"finland": 8,
	"sweden": 8,
	"switzerland": 8,
}
const EVENT_PATH_BY_COUNTRY := {
	"russia": "res://data/competition/events/russia_rally.json",
	"kenya": "res://data/competition/events/kenya_rally.json",
	"finland": "res://data/competition/events/finland_rally.json",
	"sweden": "res://data/competition/events/sweden_rally.json",
	"switzerland": "res://data/competition/events/switzerland_rally.json",
}

const VIGNETTE_SHADER_CODE := """
shader_type canvas_item;

void fragment() {
	vec2 uv = UV;
	vec2 centered = uv - vec2(0.5);
	float dist = length(centered);
	// Viñeteado suave en los bordes del showroom
	float vignette = smoothstep(0.25, 0.95, dist) * 0.70;
	// Oscurecido lateral izquierdo para maximizar contraste y legibilidad de textos
	float left_shade = smoothstep(0.52, 0.0, uv.x) * 0.52;
	// Oscurecido sutil superior e inferior para las barras de cabecera y navegación
	float vertical_shade = (smoothstep(0.12, 0.0, uv.y) + smoothstep(0.88, 1.0, uv.y)) * 0.38;
	float alpha = clamp(vignette + left_shade + vertical_shade + 0.12, 0.0, 0.94);
	COLOR = vec4(0.04, 0.06, 0.08, alpha);
}
"""

# =============================================================================
# CLASE DE PREVISUALIZACIÓN VECTORIAL DEL TRAMO EN VERTICAL
# =============================================================================

class StageRoutePreview extends Control:
	var normalized_points: PackedVector2Array = PackedVector2Array()
	var aspect_ratio: float = 1.0
	var is_highlighted: bool = false

	func _init(pts: PackedVector2Array, asp: float = 1.0) -> void:
		normalized_points = pts
		aspect_ratio = asp
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 160)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL

	func set_highlight(val: bool) -> void:
		if is_highlighted != val:
			is_highlighted = val
			queue_redraw()

	func _draw() -> void:
		if normalized_points.size() < 2:
			return

		var pad := 14.0
		var avail_w := size.x - pad * 2.0
		var avail_h := size.y - pad * 2.0
		if avail_w <= 10.0 or avail_h <= 10.0:
			return

		# Calcular bounding box
		var min_p := Vector2(INF, INF)
		var max_p := Vector2(-INF, -INF)
		for p in normalized_points:
			min_p = min_p.min(p)
			max_p = max_p.max(p)
		var extent := max_p - min_p
		extent.x = maxf(extent.x, 0.001)
		extent.y = maxf(extent.y, 0.001)

		var fit_scale := minf(avail_w / extent.x, avail_h / extent.y)
		var draw_size := extent * fit_scale
		var offset := Vector2(pad, pad) + (Vector2(avail_w, avail_h) - draw_size) * 0.5 - min_p * fit_scale

		var screen_pts := PackedVector2Array()
		for p in normalized_points:
			screen_pts.append(offset + p * fit_scale)

		# 1. Trazo difuso de halo
		var glow_col := Color(0.95, 0.75, 0.25, 0.35) if is_highlighted else Color(1.0, 1.0, 1.0, 0.08)
		draw_polyline(screen_pts, glow_col, 5.0, true)

		# 2. Línea principal del trazado
		var core_col := Color("#f8df9e") if is_highlighted else Color("#c4d7e6")
		draw_polyline(screen_pts, core_col, 2.2, true)

		# 3. Puntos de Salida (Verde abajo) y Llegada (Rojo arriba)
		var start_pt := screen_pts[0]
		var finish_pt := screen_pts[-1]

		# Punto de salida (START)
		draw_circle(start_pt, 4.5, Color("#22c55e"))
		draw_circle(start_pt, 2.0, Color.WHITE)

		# Punto de meta (FINISH)
		draw_circle(finish_pt, 4.5, Color("#ef4444"))
		draw_circle(finish_pt, 2.0, Color.WHITE)


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
var stage_previews: Array[StageRoutePreview] = []
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

# Pantalla 4: Selector de Clima Inicial (Intermedias del simulador)
const WEATHER_OPTIONS: Array[Dictionary] = [
	{
		"id": "sunny",
		"title": "Soleado",
		"tag": "DESPEJADO",
		"icon": "☀",
		"summary": "Cielo abierto con máxima irradiancia solar y calentamiento rápido del neumático. Trazado completamente seco y agarre óptimo.",
		"surface": "Grava seca / Polvo",
		"temp": "19°C ~ 24°C",
		"grip": "100% Grip",
		"accent": Color("#f59e0b")
	},
	{
		"id": "cloudy",
		"title": "Nublado",
		"tag": "LUZ DIFUSA",
		"icon": "☁",
		"summary": "Cubierta nubosa uniforme con luz difusa y temperatura templada. Superficie firme y consistente sin presencia de lluvia.",
		"surface": "Grava compacta",
		"temp": "14°C ~ 18°C",
		"grip": "98% Grip",
		"accent": Color("#94a3b8")
	},
	{
		"id": "medium_precipitation",
		"title": "Lluvia",
		"tag": "MOJADO",
		"icon": "🌧",
		"summary": "Precipitación constante que moja activamente el tramo. Formación progresiva de charcos, reducción de tracción y menor visibilidad.",
		"surface": "Grava mojada / Barro",
		"temp": "10°C ~ 14°C",
		"grip": "85% Grip",
		"accent": Color("#38bdf8")
	},
	{
		"id": "random",
		"title": "Aleatorio",
		"tag": "DINÁMICO",
		"icon": "🎲",
		"summary": "Condición meteorológica determinada por el boletín meteorológico oficial del evento y el azar regional. Puede comenzar en cualquier estado.",
		"surface": "Condición variable",
		"temp": "Variable",
		"grip": "Variable",
		"accent": Color("#e5a93c")
	}
]

var selected_weather: String = "random"
var screen_weather_select: VBoxContainer
var weather_buttons: Array[Button] = []
var weather_indicator_labels: Array[Label] = []
var btn_weather_back: Button
var btn_weather_confirm: Button

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
	_load_registry()
	_load_all_vehicle_specs()
	_load_all_stage_routes()
	_build_ui()
	_ensure_menu_music()
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
	if car_turntable != null and is_instance_valid(car_turntable):
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
		elif current_screen == "stage_select":
			show_main_menu()
			get_viewport().set_input_as_handled()


# =============================================================================
# CONSTRUCCIÓN DE LA INTERFAZ MINIMALISTA (EDGE-TO-EDGE)
# =============================================================================

func _build_ui() -> void:
	# 1. Fondo base neutro oscuro
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = C_BACK
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
	preview_viewport.msaa_3d = Viewport.MSAA_2X
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	showroom_container.add_child(preview_viewport)

	_setup_3d_preview_scene()

	# 2b. Fondo de fotos históricas intercaladas para el menú principal
	_setup_photo_background()

	# 3. Viñeteado suave sobre el fondo para garantizar contraste y legibilidad
	vignette_rect = ColorRect.new()
	vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v_shader := Shader.new()
	v_shader.code = VIGNETTE_SHADER_CODE
	var v_mat := ShaderMaterial.new()
	v_mat.shader = v_shader
	vignette_rect.material = v_mat
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
	header_title.add_theme_font_override("font", FONT_TITLE)
	header_title.add_theme_font_size_override("font_size", 24)
	header_title.add_theme_color_override("font_color", C_CHROME_TEXT)
	title_vbox.add_child(header_title)

	header_subtitle = Label.new()
	header_subtitle.text = "HISTORIC RALLY SIMULATION · CAMPEONATO HISTÓRICO"
	header_subtitle.add_theme_font_override("font", FONT_TITLE)
	header_subtitle.add_theme_font_size_override("font_size", 10)
	header_subtitle.add_theme_color_override("font_color", C_CHROME_DIM)
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
	badge_top.add_theme_font_override("font", FONT_TITLE)
	badge_top.add_theme_font_size_override("font_size", 9)
	badge_top.add_theme_color_override("font_color", C_CHROME_DIM)
	badge_vbox.add_child(badge_top)

	badge_bottom = Label.new()
	badge_bottom.text = "RALLY MANIAC"
	badge_bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_bottom.add_theme_font_override("font", FONT_TITLE)
	badge_bottom.add_theme_font_size_override("font_size", 13)
	badge_bottom.add_theme_color_override("font_color", C_GOLD)
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

	# Banner de estado / aviso / error
	status_banner = PanelContainer.new()
	status_banner.add_theme_stylebox_override("panel", _make_flat_panel(Color("#1a1012"), Color(C_ROSE, 0.6), 4))
	status_banner.hide()
	root_vbox.add_child(status_banner)

	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override("margin_left", 16)
	status_margin.add_theme_constant_override("margin_right", 16)
	status_margin.add_theme_constant_override("margin_top", 8)
	status_margin.add_theme_constant_override("margin_bottom", 8)
	status_banner.add_child(status_margin)

	status_label = Label.new()
	status_label.text = ""
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_override("font", FONT_TITLE)
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", C_GOLD_HI)
	status_margin.add_child(status_label)

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
	footer_hint.add_theme_font_override("font", FONT_TITLE)
	footer_hint.add_theme_font_size_override("font_size", 12)
	footer_hint.add_theme_color_override("font_color", Color("#f5e6c8", 0.90))
	footer_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	footer_hint.add_theme_constant_override("shadow_offset_x", 1)
	footer_hint.add_theme_constant_override("shadow_offset_y", 1)
	footer_hbox.add_child(footer_hint)

	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(footer_spacer)

	footer_version = Label.new()
	footer_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer_version.add_theme_font_override("font", FONT_TITLE)
	footer_version.add_theme_font_size_override("font_size", 12)
	footer_version.add_theme_color_override("font_color", Color("#f5e6c8", 0.90))
	footer_version.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	footer_version.add_theme_constant_override("shadow_offset_x", 1)
	footer_version.add_theme_constant_override("shadow_offset_y", 1)
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
	screen_main_menu = VBoxContainer.new()
	screen_main_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen_main_menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_main_menu.alignment = BoxContainer.ALIGNMENT_BEGIN
	screen_main_menu.add_theme_constant_override("separation", 10)
	content_container.add_child(screen_main_menu)

	# Título superior-centro del menú principal (la cabecera tachada sigue oculta).
	# Montserrat Bold Italic: no existe el TTF en el proyecto, se emula con
	# FontVariation shear sobre Montserrat-Bold (ver _montserrat_bold_italic()).
	main_menu_title = Label.new()
	main_menu_title.text = "Rally Maniac"
	main_menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_menu_title.add_theme_font_override("font", _montserrat_bold_italic())
	main_menu_title.add_theme_font_size_override("font_size", 67)
	main_menu_title.add_theme_color_override("font_color", Color("#f5e6c8"))
	main_menu_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	main_menu_title.add_theme_constant_override("shadow_offset_x", 2)
	main_menu_title.add_theme_constant_override("shadow_offset_y", 2)
	screen_main_menu.add_child(main_menu_title)

	# Separador horizontal bajo el título (mismo estilo que la cabecera original).
	var main_menu_line := ColorRect.new()
	main_menu_line.custom_minimum_size = Vector2(0, 1)
	main_menu_line.color = Color(1, 1, 1, 0.08)
	main_menu_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_main_menu.add_child(main_menu_line)

	var spacer_top := Control.new()
	spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_main_menu.add_child(spacer_top)

	var buttons_box := HBoxContainer.new()
	buttons_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons_box.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_box.add_theme_constant_override("separation", 18)
	screen_main_menu.add_child(buttons_box)

	btn_championship = _create_menu_button("Campeonato", func(): _on_mode_selected("championship"), true)
	btn_championship.custom_minimum_size = Vector2(236, 52)
	buttons_box.add_child(btn_championship)

	btn_rally = _create_menu_button("Rally", func(): _on_mode_selected("rally"), true)
	btn_rally.custom_minimum_size = Vector2(236, 52)
	buttons_box.add_child(btn_rally)

	btn_single_stage = _create_menu_button("Tramo Único", func(): _on_mode_selected("single_stage"))
	btn_single_stage.custom_minimum_size = Vector2(236, 52)
	buttons_box.add_child(btn_single_stage)

	btn_exit = _create_menu_button("Salir", func(): get_tree().quit(), false, true)
	btn_exit.custom_minimum_size = Vector2(210, 52)
	buttons_box.add_child(btn_exit)

	var main_btns: Array[Button] = [btn_championship, btn_rally, btn_single_stage, btn_exit]
	for i in main_btns.size():
		var prev_btn: Button = main_btns[(i - 1 + main_btns.size()) % main_btns.size()]
		var next_btn: Button = main_btns[(i + 1) % main_btns.size()]
		var b: Button = main_btns[i]
		b.focus_neighbor_left = b.get_path_to(prev_btn)
		b.focus_neighbor_right = b.get_path_to(next_btn)

	var spacer_bottom := Control.new()
	spacer_bottom.custom_minimum_size = Vector2(0, 12)
	screen_main_menu.add_child(spacer_bottom)


func _montserrat_bold_italic() -> Font:
	if _montserrat_bold_italic_cache != null and is_instance_valid(_montserrat_bold_italic_cache):
		return _montserrat_bold_italic_cache
	var fv := FontVariation.new()
	fv.base_font = FONT_TITLE
	# Shear horizontal para faux-italic (x' = x + 0.22*y).
	fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2.ZERO)
	_montserrat_bold_italic_cache = fv
	return fv


# =============================================================================
# PANTALLA 2: SELECTOR DE TRAMO CON CARRUSEL DE 4 TRAMOS MÁXIMO Y TRAZADO VERTICAL
# =============================================================================

func _build_stage_select_screen() -> void:
	screen_stage_select = VBoxContainer.new()
	screen_stage_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen_stage_select.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_stage_select.add_theme_constant_override("separation", 14)
	screen_stage_select.hide()
	content_container.add_child(screen_stage_select)

	var stage_header := HBoxContainer.new()
	stage_header.hide()
	screen_stage_select.add_child(stage_header)

	var stage_title := Label.new()
	stage_title.text = _stage_select_title()
	stage_title.add_theme_font_override("font", FONT_TITLE)
	stage_title.add_theme_font_size_override("font_size", 15)
	stage_title.add_theme_color_override("font_color", C_GOLD)
	stage_header.add_child(stage_title)
	stage_title_label = stage_title

	var stage_sub := Label.new()
	stage_sub.text = "   · Elige el tramo de entrada"
	stage_sub.add_theme_font_override("font", FONT_TITLE)
	stage_sub.add_theme_font_size_override("font_size", 11)
	stage_sub.add_theme_color_override("font_color", C_CHROME_DIM)
	stage_header.add_child(stage_sub)

	# Selector de país/evento: Russia (10) + Kenia, Finlandia, Suecia, Suiza (8).
	var country_row := HBoxContainer.new()
	country_row.add_theme_constant_override("separation", 8)
	screen_stage_select.add_child(country_row)
	country_buttons.clear()
	for country in COUNTRY_ORDER:
		var cbtn := Button.new()
		cbtn.text = str(COUNTRY_LABELS.get(country, country.capitalize()))
		cbtn.set_meta("country", country)
		cbtn.custom_minimum_size = Vector2(150, 38)
		cbtn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var target_country := country
		cbtn.pressed.connect(func(): _on_country_selected(target_country))
		country_row.add_child(cbtn)
		country_buttons.append(cbtn)
	_update_country_buttons()

	# Fila del carrusel: Flecha izquierda + Contenedor de 4 tramos + Flecha derecha
	var carousel_row := HBoxContainer.new()
	carousel_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	carousel_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	carousel_row.add_theme_constant_override("separation", 10)
	screen_stage_select.add_child(carousel_row)

	# Botón Flecha Izquierda (◀)
	btn_carousel_prev = Button.new()
	btn_carousel_prev.text = "◀"
	btn_carousel_prev.custom_minimum_size = Vector2(40, 0)
	btn_carousel_prev.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_arrow_button(btn_carousel_prev)
	btn_carousel_prev.pressed.connect(_on_carousel_prev_pressed)
	carousel_row.add_child(btn_carousel_prev)

	# Contenedor con scroll para visualizar exactamente 4 tramos a la vez
	stage_scroll = ScrollContainer.new()
	stage_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_scroll.clip_contents = true
	stage_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	stage_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stage_scroll.follow_focus = true
	stage_scroll.scroll_deadzone = 12
	_style_scroll_container(stage_scroll)
	carousel_row.add_child(stage_scroll)

	stage_strip = HBoxContainer.new()
	stage_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_strip.add_theme_constant_override("separation", 16)
	stage_scroll.add_child(stage_strip)

	# Botón Flecha Derecha (▶)
	btn_carousel_next = Button.new()
	btn_carousel_next.text = "▶"
	btn_carousel_next.custom_minimum_size = Vector2(40, 0)
	btn_carousel_next.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_arrow_button(btn_carousel_next)
	btn_carousel_next.pressed.connect(_on_carousel_next_pressed)
	carousel_row.add_child(btn_carousel_next)

	stage_buttons.clear()
	stage_previews.clear()
	carousel_scroll_index = 0
	var _stage_ids := _country_stage_ids()

	for _stage_pos in range(_stage_ids.size()):
		var i := _stage_pos + 1
		var sid := str(_stage_ids[_stage_pos])
		var country_label := str(COUNTRY_LABELS.get(selected_country, selected_country.capitalize()))
		var s_text := "%s Stage %d" % [country_label, i]
		var meta_info: Dictionary = STAGE_METADATA.get(sid, {"km": "5.0 KM", "surface": "Grava", "tag": "Tramo"})

		var btn := Button.new()
		btn.text = s_text
		btn.set_meta("stage_id", sid)
		btn.custom_minimum_size = Vector2(258, 360)
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_style_stage_card(btn)

		# Conexión al soltar (pressed) para evitar disparos en mouse-down y permitir cancelar arrastre
		var target_sid := sid
		btn.pressed.connect(func(): _on_stage_selected(target_sid))

		# Contenedor interior visual
		var card_inner := MarginContainer.new()
		card_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_inner.add_theme_constant_override("margin_left", 14)
		card_inner.add_theme_constant_override("margin_right", 14)
		card_inner.add_theme_constant_override("margin_top", 12)
		card_inner.add_theme_constant_override("margin_bottom", 12)
		btn.add_child(card_inner)

		var card_vbox := VBoxContainer.new()
		card_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card_vbox.add_theme_constant_override("separation", 6)
		card_inner.add_child(card_vbox)

		# 1. Cabecera de la tarjeta: STAGE 01 + Distancia (5.0 KM)
		var card_top_row := HBoxContainer.new()
		card_vbox.add_child(card_top_row)

		var lbl_stage_num := Label.new()
		lbl_stage_num.text = "STAGE %02d" % i
		lbl_stage_num.add_theme_font_override("font", FONT_TITLE)
		lbl_stage_num.add_theme_font_size_override("font_size", 10)
		lbl_stage_num.add_theme_color_override("font_color", C_GOLD)
		card_top_row.add_child(lbl_stage_num)

		var spacer_top := Control.new()
		spacer_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_top_row.add_child(spacer_top)

		var lbl_km := Label.new()
		lbl_km.text = str(meta_info.get("km", "5.0 KM"))
		lbl_km.add_theme_font_override("font", FONT_UI_BOLD)
		lbl_km.add_theme_font_size_override("font_size", 20)
		lbl_km.add_theme_color_override("font_color", C_CHROME_TEXT)
		card_top_row.add_child(lbl_km)

		var sep_line1 := ColorRect.new()
		sep_line1.custom_minimum_size = Vector2(0, 1)
		sep_line1.color = Color(1, 1, 1, 0.08)
		card_vbox.add_child(sep_line1)

		# 2. TRAZADO VERTICAL DEL TRAMO (StageRoutePreview)
		var norm_pts: PackedVector2Array = stage_routes_cache.get(sid, PackedVector2Array())
		var route_preview := StageRoutePreview.new(norm_pts)
		route_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card_vbox.add_child(route_preview)
		stage_previews.append(route_preview)

		var sep_line2 := ColorRect.new()
		sep_line2.custom_minimum_size = Vector2(0, 1)
		sep_line2.color = Color(1, 1, 1, 0.06)
		card_vbox.add_child(sep_line2)

		# 3. Título del tramo y metadatos de superficie
		var lbl_title := Label.new()
		lbl_title.text = s_text
		lbl_title.add_theme_font_override("font", FONT_TITLE)
		lbl_title.add_theme_font_size_override("font_size", 14)
		lbl_title.add_theme_color_override("font_color", Color.WHITE)
		card_vbox.add_child(lbl_title)

		var bottom_info_row := HBoxContainer.new()
		card_vbox.add_child(bottom_info_row)

		var lbl_surface := Label.new()
		lbl_surface.text = str(meta_info.get("surface", "Grava"))
		lbl_surface.add_theme_font_override("font", FONT_TITLE)
		lbl_surface.add_theme_font_size_override("font_size", 10)
		lbl_surface.add_theme_color_override("font_color", C_CHROME_DIM)
		bottom_info_row.add_child(lbl_surface)

		var spacer_bot := Control.new()
		spacer_bot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom_info_row.add_child(spacer_bot)

		var lbl_tag := Label.new()
		lbl_tag.text = str(meta_info.get("tag", "Rally")).to_upper()
		lbl_tag.add_theme_font_override("font", FONT_TITLE)
		lbl_tag.add_theme_font_size_override("font_size", 9)
		lbl_tag.add_theme_color_override("font_color", C_GOLD_HI)
		bottom_info_row.add_child(lbl_tag)

		# Reactividad de trazado y hover
		btn.mouse_entered.connect(func(): route_preview.set_highlight(true))
		btn.mouse_exited.connect(func(): route_preview.set_highlight(btn.has_focus()))
		var btn_ref := btn
		var preview_ref := route_preview
		var stage_idx := i - 1
		btn.focus_entered.connect(func():
			preview_ref.set_highlight(true)
			_sync_carousel_on_focus(stage_idx)
		)
		btn.focus_exited.connect(func(): preview_ref.set_highlight(false))

		# REGLA CRÍTICA: Asegurar que todos los nodos hijos ignoren el mouse para que el click no se pierda
		_set_mouse_filter_recursive(card_inner, Control.MOUSE_FILTER_IGNORE)

		stage_strip.add_child(btn)
		stage_buttons.append(btn)

	# Barra inferior: Botón Back + Indicador de página del carrusel
	var bottom_bar := HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 16)
	screen_stage_select.add_child(bottom_bar)

	btn_stage_back = Button.new()
	btn_stage_back.text = "◀ Volver"
	btn_stage_back.custom_minimum_size = Vector2(150, 40)
	_style_flat_button(btn_stage_back)
	btn_stage_back.pressed.connect(show_main_menu)
	bottom_bar.add_child(btn_stage_back)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(spacer)

	carousel_page_label = Label.new()
	carousel_page_label.text = "ETAPAS 1-4 DE %d" % int(COUNTRY_STAGE_COUNTS.get(selected_country, 10))
	carousel_page_label.add_theme_font_override("font", FONT_TITLE)
	carousel_page_label.add_theme_font_size_override("font_size", 11)
	carousel_page_label.add_theme_color_override("font_color", C_GOLD)
	bottom_bar.add_child(carousel_page_label)

	_update_carousel_ui()
	_update_stage_card_widths()


func _country_stage_ids() -> Array[String]:
	var out: Array[String] = []
	var count := int(COUNTRY_STAGE_COUNTS.get(selected_country, 10))
	for i in range(1, count + 1):
		out.append("%s_stage%d" % [selected_country, i])
	return out


func _stage_select_title() -> String:
	var count := int(COUNTRY_STAGE_COUNTS.get(selected_country, 10))
	var label := str(COUNTRY_LABELS.get(selected_country, selected_country.capitalize()))
	return "%s Stages · Especiales 1 a %d" % [label, count]


func _carousel_max_index() -> int:
	return maxi(0, int(COUNTRY_STAGE_COUNTS.get(selected_country, 10)) - 4)


func _on_country_selected(country: String) -> void:
	if not COUNTRY_STAGE_COUNTS.has(country):
		return
	selected_country = country
	selected_stage_id = "%s_stage1" % country
	carousel_scroll_index = 0
	# Reconstruir la pantalla con la tira del país (las tarjetas se generan en
	# _build_stage_select_screen a partir de selected_country).
	if screen_stage_select != null and is_instance_valid(screen_stage_select):
		content_container.remove_child(screen_stage_select)
		screen_stage_select.queue_free()
		screen_stage_select = null
	_build_stage_select_screen()
	_update_country_buttons()
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
	for b in country_buttons:
		var c := str(b.get_meta("country"))
		var is_sel := (c == selected_country)
		b.disabled = is_sel
		b.modulate.a = 1.0
		_style_beige_gold_button(b, FONT_TITLE, 13, 16, 8, is_sel)


func _update_stage_card_widths() -> void:
	if stage_scroll == null or stage_buttons.is_empty():
		return
	var vp_w := get_viewport_rect().size.x
	if vp_w <= 100.0:
		vp_w = 1280.0
	# Ancho total disponible en la fila del carrusel: viewport - márgenes - 2 flechas - separaciones
	var avail_w := vp_w - 96.0 - 80.0 - 20.0
	var gap := 16.0
	var card_w := floorf((avail_w - 3.0 * gap) / 4.0)
	card_w = maxf(card_w, 230.0)

	stage_scroll.custom_minimum_size.x = card_w * 4.0 + gap * 3.0
	for btn in stage_buttons:
		btn.custom_minimum_size.x = card_w


func _on_carousel_prev_pressed() -> void:
	if carousel_scroll_index > 0:
		carousel_scroll_index -= 1
		_scroll_carousel_to_index(carousel_scroll_index)


func _on_carousel_next_pressed() -> void:
	if carousel_scroll_index < _carousel_max_index():
		carousel_scroll_index += 1
		_scroll_carousel_to_index(carousel_scroll_index)


func _scroll_carousel_to_index(idx: int) -> void:
	carousel_scroll_index = clampi(idx, 0, _carousel_max_index())
	if stage_scroll == null or stage_buttons.is_empty():
		return
	var card_w: float = stage_buttons[0].custom_minimum_size.x
	var gap: float = 16.0
	var target_x: int = int(carousel_scroll_index * (card_w + gap))
	var tw := create_tween()
	tw.tween_property(stage_scroll, "scroll_horizontal", target_x, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_update_carousel_ui()


func _sync_carousel_on_focus(card_index: int) -> void:
	if card_index < carousel_scroll_index:
		_scroll_carousel_to_index(card_index)
	elif card_index > carousel_scroll_index + 3:
		_scroll_carousel_to_index(card_index - 3)


func _update_carousel_ui() -> void:
	if btn_carousel_prev != null:
		btn_carousel_prev.disabled = (carousel_scroll_index <= 0)
		btn_carousel_prev.modulate.a = 0.35 if btn_carousel_prev.disabled else 1.0
	if btn_carousel_next != null:
		btn_carousel_next.disabled = (carousel_scroll_index >= _carousel_max_index())
		btn_carousel_next.modulate.a = 0.35 if btn_carousel_next.disabled else 1.0
	if carousel_page_label != null:
		var total := int(COUNTRY_STAGE_COUNTS.get(selected_country, 10))
		carousel_page_label.text = "ETAPAS %d-%d DE %d" % [carousel_scroll_index + 1, mini(carousel_scroll_index + 4, total), total]


func _set_mouse_filter_recursive(node: Node, filter: Control.MouseFilter) -> void:
	if node is Control:
		node.mouse_filter = filter
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter)


# =============================================================================
# PANTALLA 3: SELECTOR DE COCHE (EDITORIAL INDEX + SHOWROOM 3D)
# =============================================================================

func _build_car_select_screen() -> void:
	screen_car_select = VBoxContainer.new()
	screen_car_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen_car_select.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_car_select.add_theme_constant_override("separation", 12)
	screen_car_select.hide()
	content_container.add_child(screen_car_select)

	var car_header := HBoxContainer.new()
	car_header.hide()
	screen_car_select.add_child(car_header)

	var car_title := Label.new()
	car_title.text = "Select Car"
	car_title.add_theme_font_override("font", FONT_TITLE)
	car_title.add_theme_font_size_override("font_size", 16)
	car_title.add_theme_color_override("font_color", C_GOLD)
	car_header.add_child(car_title)

	var car_sub := Label.new()
	car_sub.text = "   · Selección de vehículo y especificaciones de homologación"
	car_sub.add_theme_font_override("font", FONT_TITLE)
	car_sub.add_theme_font_size_override("font_size", 11)
	car_sub.add_theme_color_override("font_color", C_CHROME_DIM)
	car_header.add_child(car_sub)

	var main_split := HBoxContainer.new()
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.add_theme_constant_override("separation", 28)
	screen_car_select.add_child(main_split)

	# --- COLUMNA IZQUIERDA: LISTA EDITORIAL DE VEHÍCULOS ---
	var list_vbox := VBoxContainer.new()
	list_vbox.custom_minimum_size = Vector2(280, 0)
	list_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 8)
	main_split.add_child(list_vbox)

	var list_label := Label.new()
	list_label.text = "VEHÍCULOS DISPONIBLES"
	list_label.add_theme_font_override("font", FONT_TITLE)
	list_label.add_theme_font_size_override("font_size", 10)
	list_label.add_theme_color_override("font_color", C_CHROME_DIM)
	list_label.hide()
	list_vbox.add_child(list_label)

	car_scroll = ScrollContainer.new()
	car_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	car_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	car_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	car_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	car_scroll.follow_focus = true
	_style_scroll_container(car_scroll)
	list_vbox.add_child(car_scroll)

	var cars_margin := MarginContainer.new()
	cars_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cars_margin.add_theme_constant_override("margin_left", 0)
	cars_margin.add_theme_constant_override("margin_right", 8)
	cars_margin.add_theme_constant_override("margin_top", 4)
	cars_margin.add_theme_constant_override("margin_bottom", 4)
	car_scroll.add_child(cars_margin)

	var cars_vbox := VBoxContainer.new()
	cars_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cars_vbox.add_theme_constant_override("separation", 4)
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
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

		var k := str(car_key)
		btn.pressed.connect(func(): _on_car_selected(k))
		btn.focus_entered.connect(func(): _preview_car(k))
		btn.mouse_entered.connect(func(): _preview_car(k))

		cars_vbox.add_child(btn)
		car_buttons.append(btn)

	_update_car_list_visuals()

	# --- COLUMNA DERECHA: SUPERFICIE NEGATIVA CON TITULO Y FICHA EN LÍNEA ---
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 10)
	main_split.add_child(right_vbox)

	# 1. Barra de título del vehículo activo (título centrado horizontalmente)
	var title_bar := HBoxContainer.new()
	title_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	title_bar.add_theme_constant_override("separation", 12)
	right_vbox.add_child(title_bar)

	var title_balance_spacer := Control.new()
	title_balance_spacer.custom_minimum_size = Vector2(54, 0)
	title_balance_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(title_balance_spacer)

	var title_vbox := VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 2)
	title_bar.add_child(title_vbox)

	preview_car_title = Label.new()
	preview_car_title.text = "---"
	preview_car_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_car_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_car_title.add_theme_font_override("font", FONT_TITLE)
	preview_car_title.add_theme_font_size_override("font_size", 22)
	preview_car_title.add_theme_color_override("font_color", C_CHROME_TEXT)
	title_vbox.add_child(preview_car_title)

	preview_car_category = Label.new()
	preview_car_category.text = "HISTORIC RALLY SPECIFICATION"
	preview_car_category.add_theme_font_override("font", FONT_TITLE)
	preview_car_category.add_theme_font_size_override("font_size", 10)
	preview_car_category.add_theme_color_override("font_color", C_CHROME_DIM)
	preview_car_category.hide()
	title_vbox.add_child(preview_car_category)

	var badge_box := PanelContainer.new()
	badge_box.custom_minimum_size = Vector2(54, 30)
	badge_box.add_theme_stylebox_override("panel", _make_flat_panel(Color("#131a24"), Color(C_GOLD, 0.7), 4))
	title_bar.add_child(badge_box)

	var badge_margin := MarginContainer.new()
	badge_margin.add_theme_constant_override("margin_left", 8)
	badge_margin.add_theme_constant_override("margin_right", 8)
	badge_margin.add_theme_constant_override("margin_top", 2)
	badge_margin.add_theme_constant_override("margin_bottom", 2)
	badge_box.add_child(badge_margin)

	preview_layout_badge = Label.new()
	preview_layout_badge.text = "FR"
	preview_layout_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_layout_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_layout_badge.add_theme_font_override("font", FONT_TITLE)
	preview_layout_badge.add_theme_font_size_override("font_size", 14)
	preview_layout_badge.add_theme_color_override("font_color", C_GOLD_HI)
	badge_margin.add_child(preview_layout_badge)

	# Espacio central amplio donde se contempla el coche en 3D
	var showroom_spacer := Control.new()
	showroom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(showroom_spacer)

	# 2. FICHA TÉCNICA INTEGRADA EN NEGATIVO (UNA SOLA FILA HORIZONTAL LIMPIA)
	var specs_strip := HBoxContainer.new()
	specs_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	specs_strip.add_theme_constant_override("separation", 12)
	right_vbox.add_child(specs_strip)

	spec_power_val = Label.new()
	spec_power_sub = Label.new()
	specs_strip.add_child(_create_minimal_spec_item("Potencia", spec_power_val, spec_power_sub, 1.25))
	specs_strip.add_child(_create_spec_divider())

	spec_gears_val = Label.new()
	spec_gears_sub = Label.new()
	specs_strip.add_child(_create_minimal_spec_item("Marchas", spec_gears_val, spec_gears_sub, 1.05))
	specs_strip.add_child(_create_spec_divider())

	spec_wb_val = Label.new()
	spec_wb_sub = Label.new()
	specs_strip.add_child(_create_minimal_spec_item("Batalla", spec_wb_val, spec_wb_sub, 1.05))
	specs_strip.add_child(_create_spec_divider())

	spec_track_val = Label.new()
	spec_track_sub = Label.new()
	specs_strip.add_child(_create_minimal_spec_item("Trochas", spec_track_val, spec_track_sub, 1.15))
	specs_strip.add_child(_create_spec_divider())

	spec_mass_val = Label.new()
	spec_mass_sub = Label.new()
	specs_strip.add_child(_create_minimal_spec_item("Peso Mínimo", spec_mass_val, spec_mass_sub, 1.15))
	specs_strip.add_child(_create_spec_divider())

	spec_layout_val = Label.new()
	spec_layout_sub = Label.new()
	specs_strip.add_child(_create_minimal_spec_item("Configuración", spec_layout_val, spec_layout_sub, 2.0))

	# Barra inferior
	var bottom_bar := HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 16)
	screen_car_select.add_child(bottom_bar)

	btn_car_back = Button.new()
	btn_car_back.text = "◀ Volver"
	btn_car_back.custom_minimum_size = Vector2(140, 42)
	_style_flat_button(btn_car_back)
	btn_car_back.pressed.connect(show_stage_select)
	bottom_bar.add_child(btn_car_back)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(spacer)

	btn_car_confirm = Button.new()
	btn_car_confirm.text = "Seleccionar y Conducir ▶"
	btn_car_confirm.custom_minimum_size = Vector2(264, 44)
	_style_gold_button(btn_car_confirm, 15, 24, 11)
	btn_car_confirm.pressed.connect(func(): _on_car_selected(selected_car_key))
	bottom_bar.add_child(btn_car_confirm)


# =============================================================================
# PANTALLA 4: SELECTOR DE CLIMA INICIAL (INTERMEDIAS EXCLUSIVAS)
# =============================================================================

func _build_weather_select_screen() -> void:
	screen_weather_select = VBoxContainer.new()
	screen_weather_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen_weather_select.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_weather_select.add_theme_constant_override("separation", 16)
	screen_weather_select.hide()
	content_container.add_child(screen_weather_select)

	# 1. Cabecera de la pantalla de clima
	var weather_header := HBoxContainer.new()
	screen_weather_select.add_child(weather_header)

	var weather_title := Label.new()
	weather_title.text = "CLIMA INICIAL"
	weather_title.add_theme_font_override("font", FONT_TITLE)
	weather_title.add_theme_font_size_override("font_size", 16)
	weather_title.add_theme_color_override("font_color", C_GOLD)
	weather_header.add_child(weather_title)

	# Espaciador superior para centrar verticalmente las tarjetas y dejar respirar el fondo 3D
	var cards_top_spacer := Control.new()
	cards_top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_weather_select.add_child(cards_top_spacer)

	# 2. Contenedor horizontal con las 4 tarjetas de clima (compactas y centradas)
	var cards_hbox := HBoxContainer.new()
	cards_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cards_hbox.add_theme_constant_override("separation", 18)
	screen_weather_select.add_child(cards_hbox)

	weather_buttons.clear()
	weather_indicator_labels.clear()

	for opt in WEATHER_OPTIONS:
		var wid := str(opt.get("id", "random"))
		var wtitle := str(opt.get("title", ""))
		var wtag := str(opt.get("tag", ""))
		var wicon := str(opt.get("icon", ""))
		var wsummary := str(opt.get("summary", ""))
		var waccent: Color = opt.get("accent", C_GOLD)

		var btn := Button.new()
		btn.text = wtitle
		btn.set_meta("weather_id", wid)
		btn.custom_minimum_size = Vector2(230, 320)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.mouse_filter = Control.MOUSE_FILTER_STOP

		var target_wid := wid
		btn.pressed.connect(func():
			if selected_weather == target_wid:
				_on_weather_confirmed()
			else:
				_select_weather(target_wid)
		)
		btn.focus_entered.connect(func(): _select_weather(target_wid))

		# Contenedor interior de diseño
		var card_inner := MarginContainer.new()
		card_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_inner.add_theme_constant_override("margin_left", 18)
		card_inner.add_theme_constant_override("margin_right", 18)
		card_inner.add_theme_constant_override("margin_top", 16)
		card_inner.add_theme_constant_override("margin_bottom", 18)
		btn.add_child(card_inner)

		var card_vbox := VBoxContainer.new()
		card_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card_vbox.add_theme_constant_override("separation", 10)
		card_inner.add_child(card_vbox)

		# Cabecera de la tarjeta: Tag de estado + Indicador de selección
		var card_top := HBoxContainer.new()
		card_vbox.add_child(card_top)

		var lbl_tag := Label.new()
		lbl_tag.text = wtag
		lbl_tag.add_theme_font_override("font", FONT_TITLE)
		lbl_tag.add_theme_font_size_override("font_size", 10)
		lbl_tag.add_theme_color_override("font_color", waccent)
		card_top.add_child(lbl_tag)

		var spacer_top := Control.new()
		spacer_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_top.add_child(spacer_top)

		var lbl_sel := Label.new()
		lbl_sel.text = "● ACTIVO"
		lbl_sel.add_theme_font_override("font", FONT_TITLE)
		lbl_sel.add_theme_font_size_override("font_size", 10)
		lbl_sel.add_theme_color_override("font_color", C_GOLD_HI)
		lbl_sel.visible = (wid == selected_weather)
		card_top.add_child(lbl_sel)
		weather_indicator_labels.append(lbl_sel)

		var div1 := ColorRect.new()
		div1.custom_minimum_size = Vector2(0, 1)
		div1.color = Color(1, 1, 1, 0.08)
		card_vbox.add_child(div1)

		var mid_top_spacer := Control.new()
		mid_top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card_vbox.add_child(mid_top_spacer)

		# Bloque central (icono, título y descripción centrados verticalmente con mayor escala)
		var center_block := VBoxContainer.new()
		center_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center_block.add_theme_constant_override("separation", 10)
		card_vbox.add_child(center_block)

		var lbl_icon := Label.new()
		lbl_icon.text = wicon
		lbl_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl_icon.add_theme_font_override("font", FONT_TITLE)
		lbl_icon.add_theme_font_size_override("font_size", 52)
		lbl_icon.add_theme_color_override("font_color", waccent)
		center_block.add_child(lbl_icon)

		var lbl_name := Label.new()
		lbl_name.text = wtitle
		lbl_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_name.add_theme_font_override("font", FONT_TITLE)
		lbl_name.add_theme_font_size_override("font_size", 21)
		lbl_name.add_theme_color_override("font_color", Color.WHITE)
		center_block.add_child(lbl_name)

		var div2 := ColorRect.new()
		div2.custom_minimum_size = Vector2(0, 1)
		div2.color = Color(1, 1, 1, 0.08)
		center_block.add_child(div2)

		var lbl_desc := Label.new()
		lbl_desc.text = wsummary
		lbl_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl_desc.add_theme_font_override("font", FONT_REGULAR)
		lbl_desc.add_theme_font_size_override("font_size", 12)
		lbl_desc.add_theme_color_override("font_color", Color("#cbd5e1"))
		center_block.add_child(lbl_desc)

		var mid_bot_spacer := Control.new()
		mid_bot_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card_vbox.add_child(mid_bot_spacer)

		_set_mouse_filter_recursive(card_inner, Control.MOUSE_FILTER_IGNORE)

		cards_hbox.add_child(btn)
		weather_buttons.append(btn)

	# Espaciador inferior para centrar verticalmente las tarjetas
	var cards_bot_spacer := Control.new()
	cards_bot_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_bot_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_weather_select.add_child(cards_bot_spacer)

	# 3. Barra inferior de navegación
	var bottom_bar := HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 16)
	screen_weather_select.add_child(bottom_bar)

	btn_weather_back = Button.new()
	btn_weather_back.text = "◀ Volver"
	btn_weather_back.custom_minimum_size = Vector2(140, 40)
	_style_flat_button(btn_weather_back)
	btn_weather_back.pressed.connect(show_car_select)
	bottom_bar.add_child(btn_weather_back)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(spacer)

	btn_weather_confirm = Button.new()
	btn_weather_confirm.text = "Comenzar Rally ▶"
	btn_weather_confirm.custom_minimum_size = Vector2(240, 40)
	_style_gold_button(btn_weather_confirm)
	btn_weather_confirm.pressed.connect(_on_weather_confirmed)
	bottom_bar.add_child(btn_weather_confirm)

	_update_weather_cards_visuals()


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

	_stop_photo_slideshow()
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

	_stop_photo_slideshow()
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
	for i in weather_buttons.size():
		var btn: Button = weather_buttons[i]
		var wid := str(btn.get_meta("weather_id", ""))
		var is_sel := (wid == selected_weather)
		_style_weather_card(btn, is_sel)
		if i < weather_indicator_labels.size():
			weather_indicator_labels[i].visible = is_sel


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


func _on_car_selected(car_key: String) -> void:
	if is_loading:
		return
	selected_car_key = car_key
	show_weather_select()


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

	# Transferir modo, ID de tramo, coche seleccionado y clima inicial
	session.track_id = selected_stage_id
	session.session_track_id = selected_stage_id
	session.set("session_mode", selected_mode)
	session.set("selected_vehicle_key", selected_car_key)
	session.set("selected_weather", selected_weather)

	if selected_mode in ["rally", "championship"]:
		var manager := EventManagerScript.new()
		var country := str(selected_stage_id).split("_stage")[0].to_lower()
		var choices := {
			"start_stage_id": selected_stage_id,
			"initial_weather": selected_weather,
			"event_path": str(EVENT_PATH_BY_COUNTRY.get(country, EVENT_PATH_BY_COUNTRY["russia"])),
		}
		if selected_mode == "championship":
			choices["save_path"] = "user://championship_event_v1.json"
		if not manager.begin_event(choices):
			_show_error("Error al iniciar el evento: %s" % manager.error)
			_set_loading(false)
			return
		session.begin_event_session(manager, selected_stage_id)
	else:
		# Single Stage: sesión independiente de un tramo sin guardado oficial
		session.practice_mode = true
		session.competition.save_path = ""
		session.set("single_stage_weather", selected_weather)

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
	for btn in weather_buttons:
		btn.disabled = loading
	if btn_weather_back != null:
		btn_weather_back.disabled = loading
	if btn_weather_confirm != null:
		btn_weather_confirm.disabled = loading


func _show_error(msg: String) -> void:
	status_banner.add_theme_stylebox_override("panel", _make_flat_panel(Color("#220f12"), Color(C_ROSE, 0.7), 4))
	status_label.text = "⚠ " + msg
	status_label.add_theme_color_override("font_color", Color("#ff9e97"))
	status_banner.show()


func _show_notice(msg: String, is_err: bool = false) -> void:
	if is_err:
		_show_error(msg)
		return
	status_banner.add_theme_stylebox_override("panel", _make_flat_panel(Color("#141c26"), Color(C_GOLD, 0.6), 4))
	status_label.text = "ℹ " + msg
	status_label.add_theme_color_override("font_color", C_GOLD_HI)
	status_banner.show()


func _hide_status() -> void:
	status_banner.hide()
	status_label.text = ""


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
	for sid in all_ids:
		var path := "res://data/rally/%s_route.json" % sid
		if not FileAccess.file_exists(path):
			continue
		var json_str := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(json_str)
		if not (parsed is Dictionary):
			continue
		var raw_pts: Array = parsed.get("points", [])
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


func _stop_photo_slideshow() -> void:
	if photo_timer != null:
		photo_timer.stop()
	if photo_tween != null and photo_tween.is_valid():
		photo_tween.kill()
	if photo_container != null:
		photo_container.hide()
	if showroom_container != null:
		showroom_container.show()


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


func _create_minimal_spec_item(title: String, val_label: Label, sub_label: Label, stretch: float = 1.0) -> VBoxContainer:
	var item_vbox := VBoxContainer.new()
	item_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_vbox.size_flags_stretch_ratio = stretch
	item_vbox.add_theme_constant_override("separation", 1)

	var lbl_title := Label.new()
	lbl_title.text = title.to_upper()
	lbl_title.add_theme_font_override("font", FONT_TITLE)
	lbl_title.add_theme_font_size_override("font_size", 9)
	lbl_title.add_theme_color_override("font_color", C_CHROME_DIM)
	item_vbox.add_child(lbl_title)

	val_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val_label.add_theme_font_override("font", FONT_UI_BOLD)
	val_label.add_theme_font_size_override("font_size", 16)
	val_label.add_theme_color_override("font_color", C_CHROME_TEXT)
	item_vbox.add_child(val_label)

	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_label.add_theme_font_override("font", FONT_TITLE)
	sub_label.add_theme_font_size_override("font_size", 9)
	sub_label.add_theme_color_override("font_color", Color(C_CHROME_DIM, 0.70))
	item_vbox.add_child(sub_label)

	return item_vbox


func _create_spec_divider() -> ColorRect:
	var div := ColorRect.new()
	div.custom_minimum_size = Vector2(1, 28)
	div.color = Color(1, 1, 1, 0.08)
	div.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return div


func _preview_car(car_key: String) -> void:
	if car_key.is_empty():
		return
	selected_car_key = car_key

	var specs: Dictionary = vehicle_specs_cache.get(car_key, {})
	var v_data: Dictionary = vehicle_registry.get("vehicles", {}).get(car_key, {})
	var display_name := str(v_data.get("DisplayName", car_key))

	if preview_car_title != null:
		preview_car_title.text = display_name
	if preview_car_category != null:
		preview_car_category.text = "HISTORIC RALLY SPECIFICATION · " + str(specs.get("layout_name", "")).to_upper()
	if preview_layout_badge != null:
		preview_layout_badge.text = str(specs.get("layout_code", "FR"))

	if spec_power_val != null:
		spec_power_val.text = str(specs.get("power_str", "---"))
		spec_power_sub.text = str(specs.get("power_sub", ""))
	if spec_gears_val != null:
		spec_gears_val.text = str(specs.get("gears_str", "---"))
		spec_gears_sub.text = str(specs.get("gears_sub", ""))
	if spec_wb_val != null:
		spec_wb_val.text = str(specs.get("wb_str", "---"))
		spec_wb_sub.text = str(specs.get("wb_sub", ""))
	if spec_track_val != null:
		spec_track_val.text = str(specs.get("track_str", "---"))
		spec_track_sub.text = str(specs.get("track_sub", ""))
	if spec_mass_val != null:
		spec_mass_val.text = str(specs.get("mass_str", "---"))
		spec_mass_sub.text = str(specs.get("mass_sub", ""))
	if spec_layout_val != null:
		spec_layout_val.text = str(specs.get("layout_code", "---")) + " · " + str(specs.get("layout_name", ""))
		spec_layout_sub.text = str(specs.get("layout_sub", ""))

	_update_car_list_visuals()

	if car_turntable == null or not is_instance_valid(car_turntable):
		return

	if car_key == current_preview_car_key and current_car_model_instance != null and is_instance_valid(current_car_model_instance):
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


func _update_car_list_visuals() -> void:
	for btn in car_buttons:
		var k := str(btn.get_meta("car_key", ""))
		var is_selected := (k == selected_car_key)
		_style_editorial_car_button(btn, is_selected)


# =============================================================================
# HELPERS DE ESTILO MINIMALISTA (FLAT PRECISION)
# =============================================================================

func _make_flat_panel(bg: Color, border: Color = Color(1, 1, 1, 0.08), radius: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1 if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.shadow_size = 0
	return s


func _make_glass_style(radius: int, fill: Color, rim: Color) -> StyleBoxFlat:
	return _make_flat_panel(fill, rim, radius)


func _style_scroll_container(scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	var v_bar := scroll.get_v_scroll_bar()
	if v_bar != null:
		v_bar.custom_minimum_size = Vector2(4, 0)
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0, 0, 0, 0.25)
		var grabber := StyleBoxFlat.new()
		grabber.bg_color = Color(1, 1, 1, 0.20)
		grabber.set_corner_radius_all(2)
		var grabber_hl := StyleBoxFlat.new()
		grabber_hl.bg_color = C_GOLD
		grabber_hl.set_corner_radius_all(2)

		v_bar.add_theme_stylebox_override("scroll", track)
		v_bar.add_theme_stylebox_override("grabber", grabber)
		v_bar.add_theme_stylebox_override("grabber_highlight", grabber_hl)
		v_bar.add_theme_stylebox_override("grabber_pressed", grabber_hl)

	var h_bar := scroll.get_h_scroll_bar()
	if h_bar != null:
		h_bar.custom_minimum_size = Vector2(0, 4)
		var h_track := StyleBoxFlat.new()
		h_track.bg_color = Color(0, 0, 0, 0.25)
		var h_grabber := StyleBoxFlat.new()
		h_grabber.bg_color = Color(1, 1, 1, 0.25)
		h_grabber.set_corner_radius_all(2)
		var h_grabber_hl := StyleBoxFlat.new()
		h_grabber_hl.bg_color = C_GOLD
		h_grabber_hl.set_corner_radius_all(2)

		h_bar.add_theme_stylebox_override("scroll", h_track)
		h_bar.add_theme_stylebox_override("grabber", h_grabber)
		h_bar.add_theme_stylebox_override("grabber_highlight", h_grabber_hl)
		h_bar.add_theme_stylebox_override("grabber_pressed", h_grabber_hl)


func _make_extruded_box(
	bg: Color,
	border: Color,
	pad_h: int = 18,
	pad_v: int = 10,
	is_pressed: bool = false,
	radius: int = 4,
	depth: int = 4
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	if is_pressed:
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.shadow_color = Color(border.r * 0.45, border.g * 0.45, border.b * 0.45, 0.35 * border.a)
		sb.shadow_size = 1
		sb.shadow_offset = Vector2(0, 1)
		if pad_h >= 0 and pad_v >= 0:
			sb.content_margin_left = pad_h
			sb.content_margin_right = pad_h
			sb.content_margin_top = pad_v + 2
			sb.content_margin_bottom = pad_v + 1
	else:
		sb.border_width_left = 2
		sb.border_width_top = 1
		sb.border_width_right = 3
		sb.border_width_bottom = 1 + depth
		sb.shadow_color = Color(border.r * 0.45, border.g * 0.45, border.b * 0.45, 0.50 * border.a)
		sb.shadow_size = 2
		sb.shadow_offset = Vector2(1, 2)
		if pad_h >= 0 and pad_v >= 0:
			sb.content_margin_left = pad_h
			sb.content_margin_right = pad_h
			sb.content_margin_top = pad_v
			sb.content_margin_bottom = pad_v + maxi(depth - 1, 0)
	return sb


func _create_menu_button(text: String, callback: Callable, is_gold: bool = false, is_danger: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 55)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_danger:
		_style_menu_exit_button(btn)
	else:
		_style_menu_option_button(btn)
	btn.pressed.connect(callback)
	return btn


func _style_beige_gold_button(
	btn: Button,
	font: Font,
	font_size: int,
	pad_h: int,
	pad_v: int,
	is_selected: bool = false
) -> void:
	var col_beige := Color("#f5e6c8", 0.96)
	var col_beige_focus := Color("#faefd8", 0.98)
	var col_gold := Color("#e5a93c", 0.98)
	var col_gold_pressed := Color("#c88e24", 0.98)
	var col_gold_border := Color("#e5a93c")
	var col_gold_hi := Color("#f8df9e")
	var col_brown := Color("#3a2a18")

	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	var focus: StyleBoxFlat
	var pressed := _make_extruded_box(col_gold_pressed, col_gold_hi, pad_h, pad_v, true)

	if is_selected:
		normal = _make_extruded_box(col_gold, col_gold_hi, pad_h, pad_v, false)
		hover = _make_extruded_box(col_gold, Color("#fff8e7"), pad_h, pad_v, false)
		focus = hover.duplicate() as StyleBoxFlat
		var disabled := _make_extruded_box(col_gold, col_gold_hi, pad_h, pad_v, false)
		btn.add_theme_stylebox_override("disabled", disabled)
		btn.add_theme_color_override("font_disabled_color", col_brown)
	else:
		normal = _make_extruded_box(col_beige, col_gold_border, pad_h, pad_v, false)
		hover = _make_extruded_box(col_gold, col_gold_hi, pad_h, pad_v, false)
		focus = _make_extruded_box(col_beige_focus, col_gold_hi, pad_h, pad_v, false)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover_pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", col_brown)
	btn.add_theme_color_override("font_hover_color", col_brown)
	btn.add_theme_color_override("font_pressed_color", col_brown)
	btn.add_theme_color_override("font_hover_pressed_color", col_brown)
	btn.add_theme_color_override("font_focus_color", col_brown)


func _style_red_gold_button(
	btn: Button,
	font: Font,
	font_size: int,
	pad_h: int,
	pad_v: int
) -> void:
	var normal := _make_extruded_box(Color("#6b0f1a", 0.94), Color("#e5a93c"), pad_h, pad_v, false)
	var hover := _make_extruded_box(Color("#8a1622", 0.98), Color("#f8df9e"), pad_h, pad_v, false)
	var focus := _make_extruded_box(Color("#7c121e", 0.96), Color("#f8df9e"), pad_h, pad_v, false)
	var pressed := _make_extruded_box(Color("#4a0a12", 0.98), Color("#e5a93c"), pad_h, pad_v, true)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover_pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color("#f8df9e"))
	btn.add_theme_color_override("font_hover_color", Color("#fff8e7"))
	btn.add_theme_color_override("font_pressed_color", Color("#e5a93c"))
	btn.add_theme_color_override("font_hover_pressed_color", Color("#e5a93c"))
	btn.add_theme_color_override("font_focus_color", Color("#fff8e7"))


# Opciones del menú principal: beige claro de fondo, texto marrón, bordes dorados + hover dorado.
func _style_menu_option_button(btn: Button) -> void:
	_style_beige_gold_button(btn, FONT_LIBRON_BOLD, 17, 20, 11, false)


# Exit: rojo-guinda de fondo, texto dorado y borde dorado con extrusión 3D.
func _style_menu_exit_button(btn: Button) -> void:
	_style_red_gold_button(btn, FONT_LIBRON_BOLD, 17, 20, 11)


func _style_flat_button(btn: Button, is_accent: bool = false) -> void:
	RallyUITheme.style_button(btn, 13, 18, 10, is_accent)


func _style_chrome_button(btn: Button) -> void:
	_style_flat_button(btn, false)


func _style_gold_button(btn: Button, font_size: int = 13, pad_h: int = 22, pad_v: int = 10) -> void:
	var normal := _make_extruded_box(Color("#d49b2f"), C_GOLD_HI, pad_h, pad_v, false)
	var hover := _make_extruded_box(Color("#e5aa37"), Color("#fff8e7"), pad_h, pad_v, false)
	var pressed := _make_extruded_box(Color("#b38020"), C_GOLD, pad_h, pad_v, true)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover_pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", FONT_TITLE)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color("#0a0e14"))
	btn.add_theme_color_override("font_hover_color", Color("#000000"))
	btn.add_theme_color_override("font_pressed_color", Color("#000000"))
	btn.add_theme_color_override("font_focus_color", Color("#0a0e14"))


func _style_danger_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.06, 0.08, 0.85)
	normal.border_color = Color(C_ROSE, 0.40)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
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
	btn.add_theme_font_override("font", FONT_TITLE)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color("#ff9e97"))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", C_ROSE)
	btn.add_theme_color_override("font_focus_color", Color("#ff9e97"))


func _style_editorial_car_button(btn: Button, is_selected: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(0)
	normal.content_margin_right = 14
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	normal.shadow_size = 0

	if is_selected:
		normal.bg_color = Color(1.0, 1.0, 1.0, 0.04)
		normal.border_color = C_GOLD
		normal.border_width_left = 3
		normal.border_width_top = 0
		normal.border_width_right = 0
		normal.border_width_bottom = 0
		normal.content_margin_left = 18
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_font_size_override("font_size", 15)
	else:
		normal.bg_color = Color(0, 0, 0, 0)
		normal.border_width_left = 0
		normal.border_width_top = 0
		normal.border_width_right = 0
		normal.border_width_bottom = 0
		normal.content_margin_left = 14
		btn.add_theme_color_override("font_color", C_CHROME_DIM)
		btn.add_theme_font_size_override("font_size", 13)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.06)
	hover.border_color = Color.WHITE
	hover.border_width_left = 3 if not is_selected else 3

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", FONT_TITLE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)


func _style_stage_card(btn: Button) -> void:
	var normal := _make_extruded_box(Color(0.07, 0.11, 0.15, 0.90), Color("#354659"), -1, -1, false, 4, 4)
	var hover := _make_extruded_box(Color(0.12, 0.18, 0.24, 0.96), C_GOLD, -1, -1, false, 4, 4)
	var pressed := _make_extruded_box(Color(0.05, 0.08, 0.11, 0.98), C_GOLD, -1, -1, true, 4, 4)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", FONT_TITLE)
	# Mantenemos el color transparente en el texto base del botón para que no colisione con el diseño interior
	btn.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))


func _style_arrow_button(btn: Button) -> void:
	var normal := _make_extruded_box(Color(0.07, 0.11, 0.15, 0.88), Color("#46586b"), -1, -1, false, 4, 4)
	var hover := _make_extruded_box(Color(0.14, 0.20, 0.27, 0.95), C_GOLD, -1, -1, false, 4, 4)
	var pressed := _make_extruded_box(Color(0.05, 0.08, 0.11, 0.95), C_GOLD, -1, -1, true, 4, 4)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", FONT_TITLE)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", C_CHROME_TEXT)
	btn.add_theme_color_override("font_hover_color", C_GOLD)
	btn.add_theme_color_override("font_focus_color", C_GOLD)


func _style_weather_card(btn: Button, is_selected: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.15, 0.21, 0.96) if is_selected else Color(0.07, 0.11, 0.15, 0.90)
	normal.border_color = C_GOLD if is_selected else Color(1.0, 1.0, 1.0, 0.09)
	normal.set_border_width_all(2 if is_selected else 1)
	normal.set_corner_radius_all(4)
	normal.shadow_size = 0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.13, 0.19, 0.26, 0.98)
	hover.border_color = C_GOLD_HI if is_selected else Color.WHITE
	hover.set_border_width_all(2)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.06, 0.09, 0.12, 0.98)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
