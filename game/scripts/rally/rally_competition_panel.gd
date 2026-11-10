extends Control

signal retire_requested
signal retry_requested
signal next_requested
signal workshop_requested
signal new_rally_requested

# =============================================================================
# CONSTANTES VISUALES — SISTEMA DE DISEÑO MOTORSPORT MINIMALISTA (FLAT PRECISION)
# =============================================================================

# 2.2. Estandarización Tipográfica (Sin Serif)
const FONT := preload("res://fonts/montserrat/Montserrat-Regular.ttf")
const BOLD := preload("res://fonts/montserrat/Montserrat-Bold.ttf")
const DIN := preload("res://fonts/D-DIN.ttf")
const DIN_BOLD := preload("res://fonts/D-DIN-Bold.ttf")
const FONT_TITLE := preload("res://fonts/montserrat/Montserrat-Bold.ttf")

# 2.3. Paleta Workbench Motorsport (Ventana Competición / Resultados)
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
const C_SILVER := Color("#d0dbe5")
const C_BRONZE := Color("#e29b63")

const BLOCK_RECT := Rect2(1620, 168, 276, 150)

# =============================================================================
# NODOS PRINCIPALES DE INTERFAZ (PRESERVANDO CONTRATO PÚBLICO)
# =============================================================================

var results: PanelContainer
var title: Label
var header_subtitle: Label
var badge_label: Label
var badge_value: Label

var hero_panel: PanelContainer
var hero_header_label: Label
var hero_content_vbox: VBoxContainer

var table_panel: PanelContainer
var table_title: Label
var table_legend: Label
var table: Tree
var notice: Label

var retry_button: Button
var next_button: Button
var workshop_button: Button
var restart_button: Button
var shortcuts_label: Label

var last_signature: String = ""
var rows_cache: Array = []
var state_cache: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


# =============================================================================
# CONSTRUCCIÓN DE LA INTERFAZ COMPLETA (ESTILO GARAJE)
# =============================================================================

func _build_ui() -> void:
	# Contenedor raíz a pantalla completa con fondo opaco que cubre la HUD de carrera
	results = PanelContainer.new()
	results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results.mouse_filter = Control.MOUSE_FILTER_STOP
	var root_style := StyleBoxFlat.new()
	root_style.bg_color = C_BACK
	results.add_theme_stylebox_override("panel", root_style)
	add_child(results)

	var root_margin := MarginContainer.new()
	root_margin.add_theme_constant_override("margin_left", 28)
	root_margin.add_theme_constant_override("margin_right", 28)
	root_margin.add_theme_constant_override("margin_top", 18)
	root_margin.add_theme_constant_override("margin_bottom", 18)
	results.add_child(root_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	root_margin.add_child(root_vbox)

	# -------------------------------------------------------------------------
	# 1. CABECERA AERO GLASS
	# -------------------------------------------------------------------------
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", _make_glass_style(8, Color(C_GLASS, 0.95), Color(C_RIM, 0.40)))
	root_vbox.add_child(header_panel)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 18)
	header_margin.add_theme_constant_override("margin_right", 18)
	header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.add_theme_constant_override("margin_bottom", 10)
	header_panel.add_child(header_margin)

	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 16)
	header_margin.add_child(header_hbox)

	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 2)
	header_hbox.add_child(title_vbox)

	title = Label.new()
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", C_CHROME_TEXT)
	title_vbox.add_child(title)

	header_subtitle = Label.new()
	header_subtitle.add_theme_font_override("font", FONT)
	header_subtitle.add_theme_font_size_override("font_size", 11)
	header_subtitle.add_theme_color_override("font_color", C_CHROME_DIM)
	title_vbox.add_child(header_subtitle)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(header_spacer)

	var status_badge := PanelContainer.new()
	status_badge.add_theme_stylebox_override("panel", _make_glass_style(6, C_GLASS_DEEP, Color(C_RIM, 0.35)))
	header_hbox.add_child(status_badge)

	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override("margin_left", 14)
	status_margin.add_theme_constant_override("margin_right", 14)
	status_margin.add_theme_constant_override("margin_top", 4)
	status_margin.add_theme_constant_override("margin_bottom", 4)
	status_badge.add_child(status_margin)

	var status_vbox := VBoxContainer.new()
	status_vbox.add_theme_constant_override("separation", 1)
	status_margin.add_child(status_vbox)

	badge_label = Label.new()
	badge_label.text = "ESTADO DE PRUEBA"
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_label.add_theme_font_override("font", FONT_TITLE)
	badge_label.add_theme_font_size_override("font_size", 9)
	badge_label.add_theme_color_override("font_color", C_CHROME_DIM)
	status_vbox.add_child(badge_label)

	badge_value = Label.new()
	badge_value.text = "OFICIAL"
	badge_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_value.add_theme_font_override("font", DIN_BOLD)
	badge_value.add_theme_font_size_override("font_size", 14)
	badge_value.add_theme_color_override("font_color", C_BLUE)
	status_vbox.add_child(badge_value)

	# -------------------------------------------------------------------------
	# 2. CUERPO PRINCIPAL DIVIDIDO (PANEL IZQUIERDO HERO + PANEL DERECHO TABLA)
	# -------------------------------------------------------------------------
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 14)
	root_vbox.add_child(body_hbox)

	# --- Panel Izquierdo (Hero Cards & Podio) ---
	hero_panel = PanelContainer.new()
	hero_panel.custom_minimum_size = Vector2(360, 0)
	hero_panel.add_theme_stylebox_override("panel", _make_classic_panel_style())
	body_hbox.add_child(hero_panel)

	var hero_margin := MarginContainer.new()
	hero_margin.add_theme_constant_override("margin_left", 14)
	hero_margin.add_theme_constant_override("margin_right", 14)
	hero_margin.add_theme_constant_override("margin_top", 12)
	hero_margin.add_theme_constant_override("margin_bottom", 12)
	hero_panel.add_child(hero_margin)

	var hero_vbox := VBoxContainer.new()
	hero_vbox.add_theme_constant_override("separation", 10)
	hero_margin.add_child(hero_vbox)

	hero_header_label = Label.new()
	hero_header_label.text = "RESUMEN DEL PILOTO"
	hero_header_label.add_theme_font_override("font", FONT_TITLE)
	hero_header_label.add_theme_font_size_override("font_size", 12)
	hero_header_label.add_theme_color_override("font_color", C_GOLD)
	hero_vbox.add_child(hero_header_label)

	var hero_line := ColorRect.new()
	hero_line.custom_minimum_size = Vector2(0, 1)
	hero_line.color = Color(C_HI, 0.25)
	hero_vbox.add_child(hero_line)

	var hero_scroll := ScrollContainer.new()
	hero_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hero_vbox.add_child(hero_scroll)

	hero_content_vbox = VBoxContainer.new()
	hero_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_content_vbox.add_theme_constant_override("separation", 8)
	hero_scroll.add_child(hero_content_vbox)

	# --- Panel Derecho (Tabla Clasificación y Aviso) ---
	table_panel = PanelContainer.new()
	table_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_panel.add_theme_stylebox_override("panel", _make_classic_panel_style())
	body_hbox.add_child(table_panel)

	var table_margin := MarginContainer.new()
	table_margin.add_theme_constant_override("margin_left", 14)
	table_margin.add_theme_constant_override("margin_right", 14)
	table_margin.add_theme_constant_override("margin_top", 12)
	table_margin.add_theme_constant_override("margin_bottom", 12)
	table_panel.add_child(table_margin)

	var table_vbox := VBoxContainer.new()
	table_vbox.add_theme_constant_override("separation", 8)
	table_margin.add_child(table_vbox)

	var table_header_hbox := HBoxContainer.new()
	table_vbox.add_child(table_header_hbox)

	table_title = Label.new()
	table_title.text = "CLASIFICACIÓN OFICIAL"
	table_title.add_theme_font_override("font", FONT_TITLE)
	table_title.add_theme_font_size_override("font_size", 12)
	table_title.add_theme_color_override("font_color", C_CHROME_TEXT)
	table_header_hbox.add_child(table_title)

	var table_spacer := Control.new()
	table_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_header_hbox.add_child(table_spacer)

	table_legend = Label.new()
	table_legend.text = "FILA DESTACADA: TU VEHÍCULO"
	table_legend.add_theme_font_override("font", FONT)
	table_legend.add_theme_font_size_override("font_size", 10)
	table_legend.add_theme_color_override("font_color", C_GOLD)
	table_header_hbox.add_child(table_legend)

	table = Tree.new()
	table.columns = 6
	table.hide_root = true
	table.column_titles_visible = true
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_tree(table)
	var headers := ["Posición", "Piloto", "Coche - equipo", "Tiempo del stage", "Tiempo acumulado", "Estado"]
	for i in headers.size():
		table.set_column_title(i, headers[i])
		table.set_column_expand(i, true)
		table.set_column_clip_content(i, true)
		table.set_column_custom_minimum_width(i, [55, 145, 200, 130, 145, 200][i])
		table.set_column_expand_ratio(i, [1, 3, 5, 2, 2, 5][i])
	table_vbox.add_child(table)

	# Caja de aviso / estado
	var notice_panel := PanelContainer.new()
	notice_panel.add_theme_stylebox_override("panel", _make_glass_style(6, Color(C_GLASS_DEEP, 0.9), Color(C_RIM, 0.25)))
	table_vbox.add_child(notice_panel)

	var notice_margin := MarginContainer.new()
	notice_margin.add_theme_constant_override("margin_left", 12)
	notice_margin.add_theme_constant_override("margin_right", 12)
	notice_margin.add_theme_constant_override("margin_top", 6)
	notice_margin.add_theme_constant_override("margin_bottom", 6)
	notice_panel.add_child(notice_margin)

	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_font_override("font", FONT)
	notice.add_theme_font_size_override("font_size", 11)
	notice.add_theme_color_override("font_color", C_TEXT)
	notice_margin.add_child(notice)

	# -------------------------------------------------------------------------
	# 3. PIE DE PÁGINA AERO GLASS Y BOTONES DE ACCIÓN
	# -------------------------------------------------------------------------
	var footer_panel := PanelContainer.new()
	footer_panel.add_theme_stylebox_override("panel", _make_glass_style(8, Color(C_GLASS, 0.95), Color(C_RIM, 0.40)))
	root_vbox.add_child(footer_panel)

	var footer_margin := MarginContainer.new()
	footer_margin.add_theme_constant_override("margin_left", 18)
	footer_margin.add_theme_constant_override("margin_right", 18)
	footer_margin.add_theme_constant_override("margin_top", 8)
	footer_margin.add_theme_constant_override("margin_bottom", 8)
	footer_panel.add_child(footer_margin)

	var footer_hbox := HBoxContainer.new()
	footer_hbox.add_theme_constant_override("separation", 14)
	footer_margin.add_child(footer_hbox)

	retry_button = Button.new()
	retry_button.text = "REINTENTAR ESPECIAL (PRÁCTICA)"
	_style_chrome_button(retry_button)
	retry_button.pressed.connect(func(): retry_requested.emit())
	footer_hbox.add_child(retry_button)

	var footer_spacer1 := Control.new()
	footer_spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(footer_spacer1)

	shortcuts_label = Label.new()
	shortcuts_label.text = "ENTER CONTINUAR  ·  R REINTENTAR  ·  ESC SALIR"
	shortcuts_label.add_theme_font_override("font", FONT)
	shortcuts_label.add_theme_font_size_override("font_size", 11)
	shortcuts_label.add_theme_color_override("font_color", Color(C_CHROME_DIM, 0.8))
	footer_hbox.add_child(shortcuts_label)

	var footer_spacer2 := Control.new()
	footer_spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(footer_spacer2)

	restart_button = Button.new()
	restart_button.text = "NUEVO RALLY"
	_style_muted_button(restart_button)
	restart_button.pressed.connect(func(): new_rally_requested.emit())
	footer_hbox.add_child(restart_button)

	workshop_button = Button.new()
	workshop_button.text = "RUEDAS Y REPARACIONES"
	_style_gold_button(workshop_button)
	workshop_button.hide()
	workshop_button.pressed.connect(func(): workshop_requested.emit())
	footer_hbox.add_child(workshop_button)

	next_button = Button.new()
	next_button.text = "CONTINUAR A LA SIGUIENTE ESPECIAL ▶"
	_style_gold_button(next_button)
	next_button.pressed.connect(func(): next_requested.emit())
	footer_hbox.add_child(next_button)

	results.visible = false


# =============================================================================
# MANEJO DE TECLADO / NAVEGACIÓN RÁPIDA
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not results.visible:
		return
	if event.is_action_pressed("ui_accept"):
		if next_button != null and next_button.visible and not next_button.disabled:
			next_requested.emit()
			get_viewport().set_input_as_handled()
		elif restart_button != null and restart_button.visible and not next_button.visible:
			new_rally_requested.emit()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if not next_button.visible and restart_button != null and restart_button.visible:
			new_rally_requested.emit()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			if retry_button != null and retry_button.visible and not retry_button.disabled:
				retry_requested.emit()
				get_viewport().set_input_as_handled()


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


func _style_gold_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#d49b2f")
	normal.border_color = C_GOLD_HI
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	normal.shadow_size = 0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#e5aa37")
	hover.border_color = Color.WHITE

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#b38020")
	pressed.border_color = C_GOLD

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.12, 0.16, 0.20, 0.5)
	disabled.border_color = BORDER_SUBTLE
	disabled.set_border_width_all(1)
	disabled.set_corner_radius_all(2)
	disabled.content_margin_left = 24
	disabled.content_margin_right = 24
	disabled.content_margin_top = 8
	disabled.content_margin_bottom = 8

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_font_override("font", BOLD)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color("#0a0e14"))
	btn.add_theme_color_override("font_hover_color", Color("#000000"))
	btn.add_theme_color_override("font_pressed_color", Color("#000000"))
	btn.add_theme_color_override("font_focus_color", Color("#0a0e14"))
	btn.add_theme_color_override("font_disabled_color", TEXT_MUTED)


func _style_chrome_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = BG_CARD
	normal.border_color = BORDER_SUBTLE
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	normal.shadow_size = 0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = BG_HOVER
	hover.border_color = BORDER_FOCUS

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = BG_BASE
	pressed.border_color = ACCENT_RALLY

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.08, 0.11, 0.14, 0.4)
	disabled.border_color = BORDER_SUBTLE
	disabled.set_border_width_all(1)
	disabled.set_corner_radius_all(2)
	disabled.content_margin_left = 18
	disabled.content_margin_right = 18
	disabled.content_margin_top = 8
	disabled.content_margin_bottom = 8

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_font_override("font", BOLD)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", ACCENT_RALLY)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", TEXT_MUTED)


func _style_muted_button(btn: Button) -> void:
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
	hover.bg_color = Color(0.18, 0.10, 0.10, 0.95)
	hover.border_color = STATUS_DANGER

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.08, 0.05, 0.05, 0.95)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", FONT)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", C_CHROME_DIM)
	btn.add_theme_color_override("font_hover_color", C_ROSE)
	btn.add_theme_color_override("font_pressed_color", C_ROSE)


func _style_tree(tree_node: Tree) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = C_FIELD
	panel.border_color = Color(C_SHADOW, 0.8)
	panel.set_border_width_all(1)
	panel.content_margin_left = 6
	panel.content_margin_right = 6
	panel.content_margin_top = 4
	panel.content_margin_bottom = 4
	tree_node.add_theme_stylebox_override("panel", panel)

	var title_normal := StyleBoxFlat.new()
	title_normal.bg_color = C_FACE_HI
	title_normal.border_color = C_FACE_LO
	title_normal.border_width_bottom = 2
	title_normal.content_margin_left = 8
	title_normal.content_margin_right = 8
	title_normal.content_margin_top = 6
	title_normal.content_margin_bottom = 6
	tree_node.add_theme_stylebox_override("title_button_normal", title_normal)
	tree_node.add_theme_stylebox_override("title_button_hover", title_normal)
	tree_node.add_theme_stylebox_override("title_button_pressed", title_normal)

	var selected_box := StyleBoxFlat.new()
	selected_box.bg_color = C_SEL
	selected_box.border_color = C_GOLD
	selected_box.set_border_width_all(1)
	tree_node.add_theme_stylebox_override("selected", selected_box)
	tree_node.add_theme_stylebox_override("selected_focus", selected_box)
	tree_node.add_theme_stylebox_override("cursor", selected_box)
	tree_node.add_theme_stylebox_override("cursor_unfocused", selected_box)

	tree_node.add_theme_font_override("title_button_font", FONT_TITLE)
	tree_node.add_theme_font_size_override("title_button_font_size", 12)
	tree_node.add_theme_color_override("title_button_color", C_CHROME_TEXT)

	tree_node.add_theme_font_override("font", DIN_BOLD)
	tree_node.add_theme_font_size_override("font_size", 13)
	tree_node.add_theme_color_override("font_color", C_TEXT)
	tree_node.add_theme_constant_override("v_separation", 4)
	tree_node.add_theme_constant_override("h_separation", 8)
	tree_node.add_theme_constant_override("item_margin", 6)


func _create_card(label_text: String, primary_text: String, sub_text: String, primary_color: Color = C_TEXT, sub_color: Color = C_DIM) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(C_FIELD, 0.95)
	style.border_color = Color(0.18, 0.26, 0.34, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)

	var l_title := Label.new()
	l_title.text = label_text.to_upper()
	l_title.add_theme_font_override("font", FONT_TITLE)
	l_title.add_theme_font_size_override("font_size", 10)
	l_title.add_theme_color_override("font_color", C_CHROME_DIM)
	box.add_child(l_title)

	var l_prim := Label.new()
	l_prim.text = primary_text
	l_prim.add_theme_font_override("font", DIN_BOLD)
	l_prim.add_theme_font_size_override("font_size", 20)
	l_prim.add_theme_color_override("font_color", primary_color)
	box.add_child(l_prim)

	if not sub_text.is_empty():
		var l_sub := Label.new()
		l_sub.text = sub_text
		l_sub.add_theme_font_override("font", FONT)
		l_sub.add_theme_font_size_override("font_size", 11)
		l_sub.add_theme_color_override("font_color", sub_color)
		box.add_child(l_sub)

	return card


func _create_podium_card(rank: int, competitor_name: String, car_team: String, total_time: String, points_text: String, is_player: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	var rank_color := C_GOLD if rank == 1 else (C_SILVER if rank == 2 else C_BRONZE)
	style.bg_color = Color("#221d12", 0.95) if is_player else Color(C_FIELD, 0.95)
	style.border_color = C_GOLD if is_player else Color(rank_color, 0.6)
	style.set_border_width_all(2 if is_player or rank == 1 else 1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)

	var top_row := HBoxContainer.new()
	box.add_child(top_row)

	var l_rank := Label.new()
	l_rank.text = "%dº PUESTO" % rank
	l_rank.add_theme_font_override("font", BOLD)
	l_rank.add_theme_font_size_override("font_size", 11)
	l_rank.add_theme_color_override("font_color", rank_color)
	top_row.add_child(l_rank)

	if is_player:
		var tag := Label.new()
		tag.text = " [TU VEHÍCULO]"
		tag.add_theme_font_override("font", BOLD)
		tag.add_theme_font_size_override("font_size", 10)
		tag.add_theme_color_override("font_color", C_GOLD_HI)
		top_row.add_child(tag)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)

	var l_pts := Label.new()
	l_pts.text = points_text
	l_pts.add_theme_font_override("font", DIN_BOLD)
	l_pts.add_theme_font_size_override("font_size", 13)
	l_pts.add_theme_color_override("font_color", C_GOLD if rank == 1 else C_TEXT)
	top_row.add_child(l_pts)

	var l_name := Label.new()
	l_name.text = competitor_name
	l_name.add_theme_font_override("font", BOLD)
	l_name.add_theme_font_size_override("font_size", 15)
	l_name.add_theme_color_override("font_color", C_GOLD_HI if is_player else C_CHROME_TEXT)
	box.add_child(l_name)

	var bottom_row := HBoxContainer.new()
	box.add_child(bottom_row)

	var l_car := Label.new()
	l_car.text = car_team
	l_car.add_theme_font_override("font", FONT)
	l_car.add_theme_font_size_override("font_size", 11)
	l_car.add_theme_color_override("font_color", C_DIM)
	bottom_row.add_child(l_car)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(spacer2)

	var l_time := Label.new()
	l_time.text = total_time
	l_time.add_theme_font_override("font", DIN_BOLD)
	l_time.add_theme_font_size_override("font_size", 13)
	l_time.add_theme_color_override("font_color", C_TEXT)
	bottom_row.add_child(l_time)

	return card


func clock(milliseconds: Variant) -> String:
	if milliseconds == null:
		return "—"
	var value := int(milliseconds)
	return "%d:%02d.%03d" % [value / 60000, (value / 1000) % 60, value % 1000]


# =============================================================================
# PRESENTACIÓN DEL ESTADO
# =============================================================================

func present(state: Dictionary, viewport_size: Vector2) -> void:
	visible = not state.is_empty()
	if state.is_empty():
		return
	state_cache = state
	rows_cache = state.get("rows", [])
	results.visible = bool(state.complete)
	var signature := JSON.stringify(state)
	if signature == last_signature:
		return
	last_signature = signature
	if results.visible:
		# Competición/resultados usa el tema del menú (sin fade, con corte).
		var _rm := get_node_or_null("/root/RallyMusic")
		if _rm != null and _rm.has_method("on_enter_results"):
			_rm.call("on_enter_results")
		_present_results(state)
	queue_redraw()


func _present_results(state: Dictionary) -> void:
	var final_result := str(state.get("event_status", "")) == "finished"
	var allow_next: bool = bool(state.get("allow_next", true))
	var is_single_stage: bool = bool(state.get("single_stage_mode", false))
	var mode_name: String = str(state.get("session_mode", "rally"))
	var workshop_available := not final_result and bool(state.get("allow_workshop", false))
	var focus_workshop := workshop_available and not workshop_button.visible
	workshop_button.visible = workshop_available
	if focus_workshop:
		workshop_button.grab_focus()
	next_button.visible = not final_result and allow_next
	retry_button.visible = (not state.has("event_stage_id") or is_single_stage) and not final_result
	if final_result:
		_present_final(state)
		return

	# Título y Subtítulo de cabecera
	title.text = _event_title(state)
	var num := _stage_number(state)
	var total := int(state.get("event_total", 10))
	var sid := _stage_id(state).to_upper()
	if is_single_stage:
		header_subtitle.text = "TRAMO ÚNICO · %s · CRONOMETRAJE INDEPENDIENTE" % sid
	elif mode_name == "championship":
		header_subtitle.text = "CAMPEONATO · ESPECIAL %d DE %d · %s · CRONOMETRAJE OFICIAL" % [num, total, sid]
	else:
		header_subtitle.text = "ESPECIAL %d DE %d · %s · CRONOMETRAJE OFICIAL" % [num, total, sid]

	# Badge de estado
	var retired := bool(state.get("event_player_retired", state.get("player_retired", false)))
	if retired:
		badge_label.text = "SITUACIÓN DEL PILOTO"
		badge_value.text = "REENGANCHE (+300s)"
		badge_value.add_theme_color_override("font_color", C_ROSE)
	elif is_single_stage:
		badge_label.text = "MODO DE PRUEBA"
		badge_value.text = "SINGLE STAGE"
		badge_value.add_theme_color_override("font_color", C_BLUE)
	elif mode_name == "championship":
		badge_label.text = "ESTADO DE PRUEBA"
		badge_value.text = "CAMPEONATO · COMPLETADO"
		badge_value.add_theme_color_override("font_color", C_GOLD)
	else:
		badge_label.text = "ESTADO DE PRUEBA"
		badge_value.text = "OFICIAL · COMPLETADO"
		badge_value.add_theme_color_override("font_color", C_BLUE)

	# Botones
	if is_single_stage:
		retry_button.text = "REINTENTAR TRAMO"
		_style_chrome_button(retry_button)
	next_button.disabled = _next_disabled(state)
	next_button.text = _next_label(state)
	_style_gold_button(next_button)
	_style_muted_button(restart_button)
	restart_button.text = "NUEVO RALLY"
	shortcuts_label.text = ("[ ENTER ] CONTINUAR   ·   " if allow_next else "") + "[ R ] REINTENTAR"
	notice.text = _event_notice(state)

	# --- Actualizar panel izquierdo (Hero Cards) ---
	_update_stage_hero_cards(state)

	# --- Actualizar tabla derecha ---
	table_title.text = "CLASIFICACIÓN GENERAL TRAS ESPECIAL %d" % num
	table.clear()
	table.columns = 6
	var headers := ["Pos.", "Piloto", "Coche - equipo", "Tiempo stage", "Tiempo total", "Estado"]
	for i in headers.size():
		table.set_column_title(i, headers[i])
		table.set_column_expand(i, true)
		table.set_column_clip_content(i, true)
		table.set_column_custom_minimum_width(i, [45, 130, 160, 95, 95, 120][i])
		table.set_column_expand_ratio(i, [1, 3, 4, 2, 2, 3][i])

	var root := table.create_item()
	var row_idx := 0
	for row: Dictionary in state.rows:
		var item := table.create_item(root)
		var is_player := bool(row.get("player", false))
		var rank_val := int(row.get("position", 0))
		var rank_str := "%d" % rank_val if rank_val > 0 else "—"
		var car_team := str(row.get("car", "")) + " - " + str(row.get("team", ""))
		var pen := float(row.get("penalty_ms", 0)) / 1000.0
		var status_str := str(row.get("status", ""))
		if pen > 0.0:
			status_str += " (+%.0f s)" % pen

		var columns := [
			rank_str,
			str(row.get("name", "")),
			car_team,
			clock(row.get("stage_ms")),
			clock(row.get("total_ms")),
			status_str
		]
		var base_bg := Color(0.06, 0.09, 0.12, 0.7) if (row_idx % 2 == 0) else Color(0.045, 0.065, 0.085, 0.7)
		for i in columns.size():
			item.set_text(i, columns[i])
			item.set_tooltip_text(i, columns[i])
			if is_player:
				item.set_custom_color(i, Color("#ffd700"))
				item.set_custom_bg_color(i, Color("#3b3324"))
			else:
				item.set_custom_bg_color(i, base_bg)
				if i == 0:
					if rank_val == 1:
						item.set_custom_color(0, Color("#ffd700"))
					elif rank_val == 2:
						item.set_custom_color(0, Color("#d0dbe5"))
					elif rank_val == 3:
						item.set_custom_color(0, Color("#e29b63"))
					else:
						item.set_custom_color(0, C_DIM)
				elif i == 1:
					item.set_custom_color(1, C_TEXT)
				elif i == 2:
					item.set_custom_color(2, C_DIM)
				else:
					item.set_custom_color(i, C_TEXT)
		row_idx += 1


func _update_stage_hero_cards(state: Dictionary) -> void:
	hero_header_label.text = "RENDIMIENTO DEL PILOTO"
	for child in hero_content_vbox.get_children():
		child.queue_free()

	var rows: Array = state.get("rows", [])
	var player_row: Dictionary = {}
	var best_stage_ms: int = 999999999
	var total_classified := 0

	for r: Dictionary in rows:
		if bool(r.get("player", false)):
			player_row = r
		var s_ms = r.get("stage_ms")
		if s_ms != null and int(s_ms) > 0 and not bool(r.get("retired", false)):
			total_classified += 1
			if int(s_ms) < best_stage_ms:
				best_stage_ms = int(s_ms)

	var retired := bool(player_row.get("retired", false))
	var player_stage_ms = player_row.get("stage_ms")
	var player_total_ms = player_row.get("total_ms")
	var player_pos := int(player_row.get("position", 0))
	var penalty_ms := int(player_row.get("penalty_ms", 0))

	# 1. Tiempo de Especial
	if not retired and player_stage_ms != null:
		var p_ms := int(player_stage_ms)
		var diff := (p_ms - best_stage_ms) / 1000.0
		var sub := "★ SCRATCH DE ESPECIAL (MEJOR TIEMPO)" if diff <= 0.001 else "+%.3f s respecto al líder de tramo" % diff
		var sub_col := C_GOLD if diff <= 0.001 else C_BLUE
		hero_content_vbox.add_child(_create_card("Tiempo en la especial", clock(p_ms), sub, C_GOLD_HI, sub_col))
	else:
		hero_content_vbox.add_child(_create_card("Tiempo en la especial", "ABANDONO", "No completó el recorrido oficial", C_ROSE, C_DIM))

	# 2. Posición en Especial
	if not retired and player_stage_ms != null:
		var stage_rank := 1
		for r: Dictionary in rows:
			if not bool(r.get("player", false)) and not bool(r.get("retired", false)):
				var other_ms = r.get("stage_ms")
				if other_ms != null and int(other_ms) < int(player_stage_ms):
					stage_rank += 1
		var rank_color := C_GOLD if stage_rank == 1 else (C_SILVER if stage_rank == 2 else (C_BRONZE if stage_rank == 3 else C_TEXT))
		hero_content_vbox.add_child(_create_card("Posición de tramo", "P%d" % stage_rank, "de %d pilotos clasificados" % total_classified, rank_color, C_DIM))
	else:
		hero_content_vbox.add_child(_create_card("Posición de tramo", "DNF", "Sin posición válida en este tramo", C_ROSE, C_DIM))

	# 3. Clasificación General
	if not retired and player_total_ms != null:
		var pos_str := "P%d EN LA GENERAL" % player_pos if player_pos > 0 else "SIN CLASIFICAR"
		hero_content_vbox.add_child(_create_card("Clasificación general", pos_str, "Tiempo acumulado: %s" % clock(player_total_ms), C_TEXT, C_DIM))
	else:
		hero_content_vbox.add_child(_create_card("Clasificación general", "REENGANCHE", "Tiempo acumulado con +300 s de penalización", C_ROSE, C_DIM))

	# 4. Estado y Sanciones
	if penalty_ms > 0:
		hero_content_vbox.add_child(_create_card("Incidencias / Estado", "+%.0f s PENALIZACIÓN" % (float(penalty_ms) / 1000.0), str(player_row.get("status", "Sanción aplicada")), C_ROSE, C_DIM))
	elif retired:
		hero_content_vbox.add_child(_create_card("Incidencias / Estado", "ABANDONO REGISTRADO", "Reenganche aplicado para continuar el evento", C_ROSE, C_DIM))
	else:
		hero_content_vbox.add_child(_create_card("Incidencias / Estado", "ESPECIAL LIMPIA", "Sin sanciones ni incidencias de carrera", C_GREEN, C_DIM))


# =============================================================================
# PANTALLA FINAL DEL RALLY (RESULTADOS COMPLETOS Y PODIO)
# =============================================================================

func _present_final(state: Dictionary) -> void:
	var rows: Array = state.get("event_final_rows", [])
	var points: Dictionary = state.get("event_points", {})
	var mode_name: String = str(state.get("session_mode", "rally"))
	if mode_name == "championship":
		title.text = "RESULTADO FINAL · CAMPEONATO DE RUSIA"
	else:
		title.text = "RESULTADO FINAL · RALLY DE RUSIA"
	header_subtitle.text = "EVENTO DE 10 ESPECIALES FINALIZADO · PUNTUACIÓN SEGÚN BAREMO OFICIAL WRC"

	var winner_id := str(points.get("winner", ""))
	var winner_name := ""
	for row: Dictionary in rows:
		if str(row.id) == winner_id:
			winner_name = str(row.name)

	badge_label.text = "GANADOR DEL RALLY"
	badge_value.text = winner_name if not winner_name.is_empty() else "SIN GANADOR"
	badge_value.add_theme_color_override("font_color", C_GOLD)

	notice.text = "Ganador: %s · Diez especiales completadas · Puntos: general + domingo + Power Stage." % winner_name if not winner_name.is_empty() else "Rally finalizado sin participantes clasificados."

	# En pantalla final, el botón de reinicio/finalización pasa a ser el botón principal dorado
	restart_button.text = "FINALIZAR / NUEVO RALLY ▶"
	_style_gold_button(restart_button)
	shortcuts_label.text = "[ ENTER / ESC ] FINALIZAR EVENTO"

	table_title.text = "CLASIFICACIÓN FINAL Y PUNTOS DE CAMPEONATO"

	# --- Actualizar panel izquierdo con Podio y Resumen del Jugador ---
	_update_final_podium(rows, points)

	# --- Tabla completa de 7 columnas ---
	table.clear()
	table.columns = 7
	var headers := ["Pos.", "Piloto", "Tiempo acumulado", "General", "Domingo", "Power Stage", "Puntos"]
	for i in headers.size():
		table.set_column_title(i, headers[i])
		table.set_column_expand(i, true)
		table.set_column_clip_content(i, true)
		table.set_column_custom_minimum_width(i, [45, 130, 110, 65, 65, 85, 65][i])
		table.set_column_expand_ratio(i, [1, 3, 3, 1, 1, 1, 1][i])

	var root := table.create_item()
	var row_idx := 0
	for row: Dictionary in rows:
		var id := str(row.id)
		var is_player := (id == "player")
		var rank_val := int(row.get("position", 0))
		var columns := [str(row.position), str(row.name), clock(row.grand_total_ms)]
		for category in ["general", "sunday", "power", "total"]:
			columns.append(str((points.get(category, {}) as Dictionary).get(id, 0)))

		var item := table.create_item(root)
		var base_bg := Color(0.06, 0.09, 0.12, 0.7) if (row_idx % 2 == 0) else Color(0.045, 0.065, 0.085, 0.7)
		for i in columns.size():
			item.set_text(i, columns[i])
			item.set_tooltip_text(i, columns[i])
			if is_player:
				item.set_custom_color(i, Color("#ffd700"))
				item.set_custom_bg_color(i, Color("#3b3324"))
			else:
				item.set_custom_bg_color(i, base_bg)
				if i == 0:
					if rank_val == 1:
						item.set_custom_color(0, Color("#ffd700"))
					elif rank_val == 2:
						item.set_custom_color(0, Color("#d0dbe5"))
					elif rank_val == 3:
						item.set_custom_color(0, Color("#e29b63"))
					else:
						item.set_custom_color(0, C_DIM)
				elif i == 1:
					item.set_custom_color(1, C_TEXT)
				else:
					item.set_custom_color(i, C_TEXT)
		row_idx += 1


func _update_final_podium(rows: Array, points: Dictionary) -> void:
	hero_header_label.text = "PODIO FINAL DEL EVENTO"
	for child in hero_content_vbox.get_children():
		child.queue_free()

	var total_points_dict: Dictionary = points.get("total", {})
	var player_in_top3 := false

	# Renderizar los 3 primeros clasificados
	for i in mini(3, rows.size()):
		var r: Dictionary = rows[i]
		var pid := str(r.get("id", ""))
		var is_player := (pid == "player")
		if is_player:
			player_in_top3 = true
		var rank := i + 1
		var pts_val := int(total_points_dict.get(pid, 0))
		var pts_str := "%d PTS" % pts_val
		var car_team := str(r.get("car", "Ford Escort RS2000")) + " · " + str(r.get("team", "Ford Rally Works"))
		hero_content_vbox.add_child(_create_podium_card(rank, str(r.get("name", "")), car_team, clock(r.get("grand_total_ms")), pts_str, is_player))

	# Si el jugador no quedó en el top 3, mostrar su tarjeta de campeonato
	if not player_in_top3:
		var player_row: Dictionary = {}
		for r: Dictionary in rows:
			if str(r.get("id", "")) == "player":
				player_row = r
				break
		if not player_row.is_empty():
			var p_rank := int(player_row.get("position", 0))
			var p_total := int(total_points_dict.get("player", 0))
			var p_gen := int((points.get("general", {}) as Dictionary).get("player", 0))
			var p_sun := int((points.get("sunday", {}) as Dictionary).get("player", 0))
			var p_pwr := int((points.get("power", {}) as Dictionary).get("player", 0))
			var p_sub := "General: %d pts · Domingo: %d pts · Power Stage: %d pts" % [p_gen, p_sun, p_pwr]
			hero_content_vbox.add_child(_create_card("Tu posición final: P%d" % p_rank, "%d PUNTOS TOTALES" % p_total, p_sub, C_GOLD_HI, C_CHROME_DIM))


# =============================================================================
# DIBUJO DEL BLOQUE EN CARRERA (HUD DE TRAMO)
# =============================================================================

func _draw() -> void:
	if state_cache.is_empty() or results.visible:
		return
	var factor := minf(size.x / 1920.0, size.y / 1080.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * factor)
	_glass(BLOCK_RECT)
	var body := Rect2(
		BLOCK_RECT.position.x + 8, BLOCK_RECT.position.y + 8, BLOCK_RECT.size.x - 16, BLOCK_RECT.size.y - 16
	)
	draw_rect(body, C_FIELD)
	_sunken(body)

	var sector := int(state_cache.get("sector", 0))
	var sector_count := int(state_cache.get("sector_count", 0))
	var heading := "GENERAL" if sector <= 0 else "GENERAL · PARCIAL %d/%d" % [sector, sector_count]
	_text(Rect2(body.position.x + 4, body.position.y + 2, 210, 14), heading, 9, Color("#6db2e8"), true)
	draw_rect(Rect2(body.position.x + 3, body.position.y + 18, body.size.x - 6, 1), C_SHADOW)

	var visible_rows := _window_rows()
	var row_h := 37.0
	for slot in visible_rows.size():
		var entry: Dictionary = visible_rows[slot]
		var row: Dictionary = entry.row
		var row_rect := Rect2(
			body.position.x + 3, body.position.y + 21 + float(slot) * (row_h + 1.0), body.size.x - 6, row_h
		)
		var is_player := bool(row.player)
		if is_player:
			draw_rect(row_rect, C_SEL)
			draw_rect(Rect2(row_rect.position.x, row_rect.position.y, 3, row_rect.size.y), C_GOLD)
			draw_rect(Rect2(row_rect.position.x, row_rect.position.y, row_rect.size.x, 1), C_GOLD)
			draw_rect(Rect2(row_rect.position.x, row_rect.end.y - 1, row_rect.size.x, 1), C_GOLD)
			draw_rect(Rect2(row_rect.end.x - 1, row_rect.position.y, 1, row_rect.size.y), C_GOLD)
		var rank := "%d" % int(row.get("position", 0)) if int(row.get("position", 0)) > 0 else "—"
		_num(Rect2(row_rect.position.x + 8, row_rect.position.y, 22, row_h), rank, 14, C_TEXT if is_player else C_DIM)
		_text(
			Rect2(row_rect.position.x + 32, row_rect.position.y, 130, row_h),
			str(row.get("name", "")),
			11,
			C_TEXT if is_player else C_DIM,
			is_player
		)
		var partial_index := int(row.get("partial_index", 0))
		var partial := clock(row.get("partial_ms")) if partial_index > 0 else "—"
		_num(
			Rect2(row_rect.position.x + 158, row_rect.position.y, 78, row_h),
			partial,
			13,
			C_TEXT if is_player else C_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT,
			78
		)
	draw_set_transform(Vector2.ZERO)


func _window_rows() -> Array:
	var rows: Array = rows_cache
	if rows.is_empty():
		return []
	var player_index := -1
	for i in rows.size():
		if bool(rows[i].get("player", false)):
			player_index = i
			break
	if player_index < 0:
		player_index = 0
	var result: Array = []
	for offset in [-1, 0, 1]:
		var index: int = player_index + offset
		if index >= 0 and index < rows.size():
			result.append({"row": rows[index], "offset": offset})
	return result


# =============================================================================
# PRIMITIVAS DE DIBUJO
# =============================================================================

func _glass(rect: Rect2) -> void:
	var body := StyleBoxFlat.new()
	body.bg_color = Color(C_GLASS, 0.90)
	body.border_color = Color(C_RIM, 0.40)
	body.set_border_width_all(1)
	body.set_corner_radius_all(10)
	draw_style_box(body, rect)


func _sunken(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 1), C_SHADOW)
	draw_rect(Rect2(rect.position.x, rect.position.y, 1, rect.size.y), C_SHADOW)
	draw_rect(Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1), C_HI)
	draw_rect(Rect2(rect.end.x - 1, rect.position.y, 1, rect.size.y), C_HI)


func _num(
	rect: Rect2,
	value: String,
	size_px: int,
	color: Color,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	width_override: float = -1.0
) -> void:
	if value.is_empty():
		return
	var width: float = rect.size.x if width_override < 0.0 else width_override
	var line_height := BOLD.get_height(size_px)
	var baseline := rect.position.y + (rect.size.y + line_height) * 0.5 - BOLD.get_descent(size_px)
	draw_string(BOLD, Vector2(round(rect.position.x), round(baseline)), value, align, width, size_px, color)


func _text(
	rect: Rect2,
	value: String,
	size_px: int,
	color: Color,
	bold: bool = false,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	width_override: float = -1.0
) -> void:
	if value.is_empty():
		return
	var font: Font = BOLD if bold else FONT
	var width: float = rect.size.x if width_override < 0.0 else width_override
	var line_height := font.get_height(size_px)
	var baseline := rect.position.y + (rect.size.y + line_height) * 0.5 - font.get_descent(size_px)
	draw_string(font, Vector2(round(rect.position.x), round(baseline)), value, align, width, size_px, color)


# =============================================================================
# HELPERS DE DATOS Y ETIQUETAS
# =============================================================================

func _stage_number(state: Dictionary) -> int:
	if state.has("event_cursor"):
		return int(state["event_cursor"]) + 1
	return int(state.get("leg", 1))


func _stage_id(state: Dictionary) -> String:
	if state.has("event_stage_id"):
		return str(state["event_stage_id"])
	var leg := int(state.get("leg", 1))
	return "russia_stage%d" % leg


func _event_title(state: Dictionary) -> String:
	var total := int(state.get("event_total", 10))
	var num := _stage_number(state)
	var sid := _stage_id(state)
	var sched: Dictionary = state.get("event_schedule", {})
	var when := ""
	if not sched.is_empty():
		when = " · %s %s" % [str(sched.get("day_label", "")), str(sched.get("start", ""))]
	return "RESULTADOS · Especial %d/%d · %s%s · Clasificación general" % [num, total, sid, when]


func _next_label(state: Dictionary) -> String:
	if not state.has("event_stage_id"):
		return "REPETIR ESPECIAL (PRÁCTICA)"
	if bool(state.get("event_is_last", false)) or _stage_number(state) >= int(state.get("event_total", 10)):
		return "VER RESULTADO FINAL ▶"
	var nxt := _stage_number(state) + 1
	return "CONTINUAR A STAGE %d ▶" % nxt


func _next_disabled(state: Dictionary) -> bool:
	if state.has("event_stage_id"):
		return false
	return bool(state.get("player_retired", false))


func _event_notice(state: Dictionary) -> String:
	if bool(state.get("single_stage_mode", false)):
		var sid := _stage_id(state)
		return "Especial %s completada. Modo Single Stage finalizado. Usa «Reintentar tramo» para reiniciar o «Nuevo Rally» para volver al menú." % sid
	if state.has("event_stage_id"):
		var sid := _stage_id(state)
		var sched: Dictionary = state.get("event_schedule", {})
		var next_info := ""
		if not bool(state.get("event_is_last", false)):
			next_info = " Próxima especial: Stage %d." % (_stage_number(state) + 1)
		else:
			next_info = " Última especial completada: selecciona «Ver resultado final» para la clasificación definitiva."
		var base := "Especial %s completada y cronometrada oficialmente." % sid
		if not sched.is_empty():
			base += " Horario %s %s." % [str(sched.get("day_label", "")), str(sched.get("start", ""))]
		if bool(state.get("event_player_retired", state.get("player_retired", false))):
			base += " Se ha registrado abandono: aplica reenganche (+300 s) para la siguiente especial."
		if not str(state.get("error", "")).is_empty():
			base += "  " + str(state.get("error", ""))
		return base + next_info
	if bool(state.get("player_retired", false)):
		return "El intento de práctica finaliza al abandonar. Usa 'Reintentar especial' para reiniciar con la misma configuración."
	return "Continuar avanza a la siguiente prueba conservando tiempos acumulados; reintentar reinicia la especial de práctica."
