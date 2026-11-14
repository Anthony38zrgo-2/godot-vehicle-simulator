class_name RallyUITheme
extends RefCounted

# =============================================================================
# SISTEMA DE DISEÑO MOTORSPORT UNIFICADO (FLAT PRECISION)
# =============================================================================
# Fuente única de verdad visual para todos los menús del juego:
# paleta Dark Carbon + Brass Gold, geometría plana con chaflán técnico de 2 px,
# bordes finos de 1 px sin sombras ni biseles, y tipografía estricta
# Montserrat (UI) + D-DIN (telemetría y cifras).
# =============================================================================

const CORNER_RADIUS: int = 2

# --- 1. PALETA FUNCIONAL UNIFICADA (DARK CARBON + BRASS GOLD) ---

# Fondos (jerarquía por luminosidad mate)
const BG_BASE := Color("#0a0e14")                    # Carbono profundo de lienzo
const BG_SHELL := Color("#0c1118")                   # Marcos, cabeceras y pies de menú
const BG_SURFACE := Color("#11161f")                 # Cuerpo principal de paneles y ventanas
const BG_CARD := Color("#18202c")                    # Tarjetas, grupos y botones base
const BG_ELEVATED := Color("#1c2635")                # Tarjetas seleccionadas / pestañas activas
const BG_HOVER := Color("#202a38")                   # Superficie en hover
const BG_PRESSED := Color("#080c10")                 # Estado presionado ultra-oscuro
const BG_WELL := Color("#080c11")                    # Contenedores hundidos de telemetría / inputs
const BG_OVERLAY := Color(0.03, 0.05, 0.08, 0.88)    # Oscurecido modal

# Bordes (1 px plano, sin relieves)
const BORDER_SUBTLE := Color(1.0, 1.0, 1.0, 0.10)
const BORDER_CARD := Color(1.0, 1.0, 1.0, 0.14)
const BORDER_HOVER := Color(1.0, 1.0, 1.0, 0.24)
const BORDER_FOCUS := Color("#ffffff")
const BORDER_ACCENT := Color("#e5a93c")

# Tipografía
const TEXT_PRIMARY := Color("#f0f4f8")
const TEXT_MUTED := Color("#8393a5")
const TEXT_DIM := Color("#536071")
const TEXT_WHITE := Color("#ffffff")
const TEXT_GOLD_SOFT := Color("#f5d799")

# Semántica Motorsport
const ACCENT_RALLY := Color("#e5a93c")
const ACCENT_RALLY_DARK := Color("#b37f22")
const ACCENT_RALLY_SOFT := Color(0.898, 0.663, 0.235, 0.15)
const ACCENT_ALERT := Color("#f59e0b")
const STATUS_DANGER := Color("#ef4444")
const STATUS_SUCCESS := Color("#22c55e")
const STATUS_INFO := Color("#38bdf8")

# --- 2. ALIAS WORKBENCH CONSOLIDADOS ---
# Conservan los símbolos WB_* existentes mapeados directamente a Dark Carbon.
const WB_BG_SHELL := BG_SHELL
const WB_BG_HEADER := BG_SHELL
const WB_BG_FOOTER := BG_SHELL
const WB_BG_TAB_INACTIVE := BG_SURFACE
const WB_BG_TAB_ACTIVE := BG_CARD
const WB_BG_CONTENT := BG_SURFACE
const WB_BG_CARD := BG_CARD
const WB_BG_CARD_HOVER := BG_HOVER
const WB_BG_WELL := BG_WELL
const WB_BORDER_SUBTLE := BORDER_SUBTLE
const WB_BORDER_HOVER := BORDER_HOVER
const WB_BORDER_FOCUS := BORDER_FOCUS
const WB_BORDER_ACCENT := BORDER_ACCENT
const WB_SLIDER_TRACK := BG_WELL
const WB_SLIDER_FILL := Color("#d49b35")
const WB_SLIDER_THUMB := Color("#f0f4f8")
const WB_SLIDER_STEPPER := BG_CARD
const WB_TEXT_TITLE := TEXT_PRIMARY
const WB_TEXT_LABEL := TEXT_MUTED
const WB_TEXT_DATA := TEXT_WHITE
const WB_TEXT_ACCENT := ACCENT_RALLY

# --- 3. TIPOGRAFÍA DE MENÚS (Bungee, Big Shoulders, Science Gothic) ---

const FONT_LOGO: Font = preload("res://assets/fonts/variants/bungee_regular.tres")
const FONT_LOGO_INLINE: Font = preload("res://assets/fonts/variants/bungee_inline.tres")

const FONT_TITLE: Font = preload("res://assets/fonts/variants/big_shoulders_display_black.tres")
const FONT_SUBTITLE: Font = preload("res://assets/fonts/variants/big_shoulders_display_bold.tres")
const FONT_MENU_OPTION: Font = preload("res://assets/fonts/variants/big_shoulders_text_bold.tres")
const FONT_BUTTON: Font = preload("res://assets/fonts/variants/big_shoulders_text_semibold.tres")

const FONT_REGULAR: Font = preload("res://assets/fonts/variants/science_gothic_regular.tres")
const FONT_MEDIUM: Font = preload("res://assets/fonts/variants/science_gothic_medium.tres")
const FONT_MEDIUM_TIGHT: Font = preload("res://assets/fonts/variants/science_gothic_medium_tight.tres")

const FONT_DATA: Font = FONT_MEDIUM
const FONT_DATA_BOLD: Font = preload("res://assets/fonts/variants/science_gothic_bold.tres")
const FONT_DATA_BOLD_TIGHT: Font = preload("res://assets/fonts/variants/science_gothic_bold_tight.tres")
const FONT_DATA_COND: Font = FONT_SUBTITLE
const FONT_DATA_COND_BOLD: Font = FONT_TITLE

# --- 4. FACTORIES PLANOS (STYLEBOXFLAT) ---

## Crea un StyleBoxFlat plano con chaflán técnico por defecto y cero sombras.
static func make_flat_panel(
	bg: Color = BG_SURFACE,
	border_col: Color = BORDER_SUBTLE,
	border_w: int = 1,
	corner_r: int = CORNER_RADIUS,
	pad_h: int = -1,
	pad_v: int = -1
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_col
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(maxi(0, corner_r))
	sb.shadow_size = 0
	sb.anti_aliasing = true
	if pad_h >= 0:
		sb.content_margin_left = pad_h
		sb.content_margin_right = pad_h
	if pad_v >= 0:
		sb.content_margin_top = pad_v
		sb.content_margin_bottom = pad_v
	return sb


static func make_window_panel(
	bg: Color = BG_SURFACE,
	border_col: Color = BORDER_CARD,
	corner_r: int = CORNER_RADIUS
) -> StyleBoxFlat:
	return make_flat_panel(bg, border_col, 1, corner_r)


static func make_card_panel(
	bg: Color = BG_CARD,
	border_col: Color = BORDER_SUBTLE,
	pad_h: int = 12,
	pad_v: int = 10,
	corner_r: int = CORNER_RADIUS
) -> StyleBoxFlat:
	return make_flat_panel(bg, border_col, 1, corner_r, pad_h, pad_v)


static func make_well_panel(
	border_col: Color = BORDER_SUBTLE,
	pad_h: int = 10,
	pad_v: int = 8,
	corner_r: int = CORNER_RADIUS
) -> StyleBoxFlat:
	return make_flat_panel(BG_WELL, border_col, 1, corner_r, pad_h, pad_v)


static func _tone_spec(tone: String) -> Dictionary:
	match tone:
		"gold", "primary":
			return {
				"bg": ACCENT_RALLY,
				"bg_hover": Color("#f2bb54"),
				"bg_pressed": Color("#c88e24"),
				"border": Color("#f6c96e"),
				"border_hover": Color("#fff3d1"),
				"text": Color("#0a0e14"),
				"text_hover": Color("#0a0e14"),
				"text_pressed": Color("#0a0e14"),
			}
		"accent":
			return {
				"bg": Color("#2a2010"),
				"bg_hover": Color("#382b15"),
				"bg_pressed": Color("#1b150b"),
				"border": ACCENT_RALLY,
				"border_hover": Color("#f3be5a"),
				"text": TEXT_GOLD_SOFT,
				"text_hover": TEXT_WHITE,
				"text_pressed": ACCENT_RALLY,
			}
		"caution":
			return {
				"bg": Color("#2b1e0e"),
				"bg_hover": Color("#3b2812"),
				"bg_pressed": Color("#1c1308"),
				"border": ACCENT_ALERT,
				"border_hover": Color("#fbbf24"),
				"text": Color("#fde68a"),
				"text_hover": TEXT_WHITE,
				"text_pressed": ACCENT_ALERT,
			}
		"danger":
			return {
				"bg": Color("#2b1316"),
				"bg_hover": Color("#3c1a1f"),
				"bg_pressed": Color("#1c0c0f"),
				"border": STATUS_DANGER,
				"border_hover": Color("#f87171"),
				"text": Color("#fecaca"),
				"text_hover": TEXT_WHITE,
				"text_pressed": STATUS_DANGER,
			}
		"selected", "success":
			return {
				"bg": Color("#13281d"),
				"bg_hover": Color("#193627"),
				"bg_pressed": Color("#0d1b14"),
				"border": STATUS_SUCCESS,
				"border_hover": Color("#4ade80"),
				"text": Color("#bbf7d0"),
				"text_hover": TEXT_WHITE,
				"text_pressed": STATUS_SUCCESS,
			}
		"muted":
			return {
				"bg": BG_SURFACE,
				"bg_hover": BG_CARD,
				"bg_pressed": BG_PRESSED,
				"border": BORDER_SUBTLE,
				"border_hover": BORDER_HOVER,
				"text": TEXT_MUTED,
				"text_hover": TEXT_PRIMARY,
				"text_pressed": TEXT_WHITE,
			}
		_:
			return {
				"bg": BG_CARD,
				"bg_hover": BG_HOVER,
				"bg_pressed": BG_PRESSED,
				"border": BORDER_CARD,
				"border_hover": BORDER_HOVER,
				"text": TEXT_PRIMARY,
				"text_hover": TEXT_WHITE,
				"text_pressed": ACCENT_RALLY,
			}


## Estiliza cualquier botón según un tono semántico único.
static func style_tone_button(
	btn: Button,
	tone: String = "chrome",
	font_size: int = 14,
	pad_h: int = 14,
	pad_v: int = 8,
	corner_r: int = CORNER_RADIUS,
	font_res: Font = FONT_BUTTON
) -> void:
	if btn == null:
		return
	var spec := _tone_spec(tone)
	var normal := make_flat_panel(spec["bg"], spec["border"], 1, corner_r, pad_h, pad_v)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = spec["bg_hover"]
	hover.border_color = spec["border_hover"]

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = spec["bg_pressed"]
	pressed.border_color = ACCENT_RALLY if tone == "chrome" else spec["border_hover"]

	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = spec["bg_hover"]
	focus.border_color = BORDER_FOCUS
	focus.set_border_width_all(2)

	var disabled := make_flat_panel(
		Color(BG_SURFACE.r, BG_SURFACE.g, BG_SURFACE.b, 0.55),
		Color(1.0, 1.0, 1.0, 0.05),
		1,
		corner_r,
		pad_h,
		pad_v
	)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_font_override("font", font_res)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", spec["text"])
	btn.add_theme_color_override("font_hover_color", spec["text_hover"])
	btn.add_theme_color_override("font_pressed_color", spec["text_pressed"])
	btn.add_theme_color_override("font_focus_color", TEXT_WHITE)
	btn.add_theme_color_override("font_disabled_color", TEXT_DIM)
	btn.add_theme_constant_override("outline_size", 0)
	btn.remove_theme_color_override("font_shadow_color")


## Estiliza un botón interactivo según el estándar minimalista.
static func style_button(
	btn: Button,
	font_size: int = 14,
	pad_h: int = 18,
	pad_v: int = 12,
	is_primary: bool = false
) -> void:
	style_tone_button(btn, "gold" if is_primary else "chrome", font_size, pad_h, pad_v)


static func style_gold_button(btn: Button, font_size: int = 13, pad_h: int = 14, pad_v: int = 8) -> void:
	style_tone_button(btn, "gold", font_size, pad_h, pad_v)


static func style_chrome_button(btn: Button, font_size: int = 13, pad_h: int = 14, pad_v: int = 8) -> void:
	style_tone_button(btn, "chrome", font_size, pad_h, pad_v)


static func style_caution_button(btn: Button, font_size: int = 13, pad_h: int = 14, pad_v: int = 8) -> void:
	style_tone_button(btn, "caution", font_size, pad_h, pad_v)


static func style_danger_button(btn: Button, font_size: int = 13, pad_h: int = 14, pad_v: int = 8) -> void:
	style_tone_button(btn, "danger", font_size, pad_h, pad_v)


static func style_selected_button(btn: Button, font_size: int = 13, pad_h: int = 14, pad_v: int = 8) -> void:
	style_tone_button(btn, "selected", font_size, pad_h, pad_v)


static func style_muted_button(btn: Button, font_size: int = 13, pad_h: int = 14, pad_v: int = 8) -> void:
	style_tone_button(btn, "muted", font_size, pad_h, pad_v)


## Estiliza un botón tipo tarjeta (tramos, climatología, ranuras interactivas).
static func style_card_surface(
	btn: Button,
	selected: bool = false,
	font_size: int = 14,
	pad_h: int = 14,
	pad_v: int = 10,
	accent_col: Color = ACCENT_RALLY
) -> void:
	if btn == null:
		return
	var bg := BG_ELEVATED if selected else BG_CARD
	var border := accent_col if selected else BORDER_CARD
	var normal := make_flat_panel(bg, border, 2 if selected else 1, CORNER_RADIUS, pad_h, pad_v)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = BG_HOVER
	hover.border_color = accent_col if selected else BORDER_HOVER
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = BG_PRESSED
	pressed.border_color = accent_col
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = BG_HOVER
	focus.border_color = BORDER_FOCUS
	focus.set_border_width_all(2)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_font_override("font", FONT_BUTTON)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", TEXT_WHITE if selected else TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", TEXT_WHITE)
	btn.add_theme_color_override("font_focus_color", TEXT_WHITE)
	btn.add_theme_color_override("font_pressed_color", accent_col)


## Estiliza un botón editorial de índice con acento de 3 px a la izquierda.
static func style_editorial_item(
	btn: Button,
	is_active: bool,
	font_size: int = 14,
	pad_v: int = 10
) -> void:
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(0)
	normal.shadow_size = 0
	normal.content_margin_top = pad_v
	normal.content_margin_bottom = pad_v
	normal.content_margin_right = 14

	if is_active:
		normal.bg_color = Color(1.0, 1.0, 1.0, 0.05)
		normal.border_color = ACCENT_RALLY
		normal.border_width_left = 3
		normal.border_width_top = 0
		normal.border_width_right = 0
		normal.border_width_bottom = 0
		normal.content_margin_left = 18
		btn.add_theme_color_override("font_color", TEXT_WHITE)
		btn.add_theme_font_size_override("font_size", font_size + 1)
	else:
		normal.bg_color = Color(0, 0, 0, 0)
		normal.border_width_left = 0
		normal.border_width_top = 0
		normal.border_width_right = 0
		normal.border_width_bottom = 0
		normal.content_margin_left = 14
		btn.add_theme_color_override("font_color", TEXT_MUTED)
		btn.add_theme_font_size_override("font_size", font_size)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.07)
	hover.border_color = TEXT_WHITE
	hover.border_width_left = 3

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", FONT_MENU_OPTION)
	btn.add_theme_color_override("font_hover_color", TEXT_WHITE)
	btn.add_theme_color_override("font_focus_color", TEXT_WHITE)


static func style_option_button(
	opt: OptionButton,
	font_size: int = 12,
	pad_h: int = 12,
	pad_v: int = 7
) -> void:
	if opt == null:
		return
	style_tone_button(opt, "chrome", font_size, pad_h, pad_v)
	var popup := opt.get_popup()
	if popup != null:
		popup.add_theme_stylebox_override("panel", make_flat_panel(BG_SURFACE, BORDER_CARD, 1, CORNER_RADIUS, 6, 6))
		popup.add_theme_stylebox_override("hover", make_flat_panel(BG_HOVER, ACCENT_RALLY, 1, CORNER_RADIUS))
		popup.add_theme_font_override("font", FONT_MEDIUM)
		popup.add_theme_font_size_override("font_size", maxi(10, font_size - 1))
		popup.add_theme_color_override("font_color", TEXT_PRIMARY)
		popup.add_theme_color_override("font_hover_color", TEXT_WHITE)


static func style_tree(tree: Tree, font_size: int = 13) -> void:
	if tree == null:
		return
	tree.add_theme_stylebox_override("panel", make_flat_panel(BG_WELL, BORDER_SUBTLE, 1, CORNER_RADIUS, 8, 8))
	tree.add_theme_stylebox_override("focus", make_flat_panel(BG_WELL, BORDER_HOVER, 1, CORNER_RADIUS, 8, 8))
	tree.add_theme_stylebox_override("selected", make_flat_panel(ACCENT_RALLY_SOFT, ACCENT_RALLY, 1, CORNER_RADIUS))
	tree.add_theme_stylebox_override("selected_focus", make_flat_panel(ACCENT_RALLY_SOFT, BORDER_FOCUS, 1, CORNER_RADIUS))
	tree.add_theme_stylebox_override("title_button_normal", make_flat_panel(BG_SHELL, BORDER_SUBTLE, 1, CORNER_RADIUS, 8, 6))
	tree.add_theme_stylebox_override("title_button_hover", make_flat_panel(BG_CARD, BORDER_HOVER, 1, CORNER_RADIUS, 8, 6))
	tree.add_theme_stylebox_override("title_button_pressed", make_flat_panel(BG_CARD, ACCENT_RALLY, 1, CORNER_RADIUS, 8, 6))
	tree.add_theme_font_override("font", FONT_MEDIUM_TIGHT)
	tree.add_theme_font_override("title_button_font", FONT_SUBTITLE)
	tree.add_theme_font_size_override("font_size", maxi(10, font_size - 2))
	tree.add_theme_font_size_override("title_button_font_size", font_size)
	tree.add_theme_color_override("font_color", TEXT_PRIMARY)
	tree.add_theme_color_override("font_selected_color", TEXT_WHITE)
	tree.add_theme_color_override("title_button_color", TEXT_MUTED)
	tree.add_theme_color_override("guide_color", Color(1.0, 1.0, 1.0, 0.04))


## Estiliza etiquetas sin sombras heredadas según jerarquía tipográfica.
static func style_label(
	lbl: Label,
	tone: String = "primary",
	font_size: int = 14,
	use_data_font: bool = false,
	bold: bool = false
) -> void:
	if lbl == null:
		return
	var col := TEXT_PRIMARY
	match tone:
		"white", "title", "data":
			col = TEXT_WHITE
		"muted", "label":
			col = TEXT_MUTED
		"dim":
			col = TEXT_DIM
		"accent", "gold":
			col = ACCENT_RALLY
		"success":
			col = STATUS_SUCCESS
		"danger":
			col = STATUS_DANGER
		"alert":
			col = ACCENT_ALERT
		"info":
			col = STATUS_INFO
	var font_res := FONT_DATA_BOLD if (use_data_font and bold) else (FONT_DATA if use_data_font else (FONT_SUBTITLE if bold else FONT_REGULAR))
	lbl.add_theme_font_override("font", font_res)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 0)
	lbl.add_theme_constant_override("outline_size", 0)
	lbl.remove_theme_color_override("font_shadow_color")


## Construye un Theme nativo de Godot unificado para cualquier pantalla de menú.
static func build_menu_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT_REGULAR
	t.default_font_size = 12

	t.set_color("font_color", "Label", TEXT_PRIMARY)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 0)

	t.set_stylebox("panel", "PanelContainer", make_window_panel())
	t.set_stylebox("panel", "Panel", make_window_panel())
	t.set_stylebox("panel", "PopupMenu", make_flat_panel(BG_SURFACE, BORDER_CARD, 1, CORNER_RADIUS, 6, 6))
	t.set_stylebox("hover", "PopupMenu", make_flat_panel(BG_HOVER, ACCENT_RALLY, 1, CORNER_RADIUS))
	t.set_font("font", "PopupMenu", FONT_MEDIUM)
	t.set_font_size("font_size", "PopupMenu", 11)
	t.set_color("font_color", "PopupMenu", TEXT_PRIMARY)
	t.set_color("font_hover_color", "PopupMenu", TEXT_WHITE)

	t.set_font("font", "Button", FONT_BUTTON)
	t.set_font_size("font_size", "Button", 15)
	t.set_color("font_color", "Button", TEXT_PRIMARY)
	t.set_color("font_hover_color", "Button", TEXT_WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT_RALLY)
	t.set_color("font_focus_color", "Button", TEXT_WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_stylebox("normal", "Button", make_flat_panel(BG_CARD, BORDER_CARD, 1, CORNER_RADIUS, 14, 8))
	t.set_stylebox("hover", "Button", make_flat_panel(BG_HOVER, BORDER_HOVER, 1, CORNER_RADIUS, 14, 8))
	t.set_stylebox("pressed", "Button", make_flat_panel(BG_PRESSED, ACCENT_RALLY, 1, CORNER_RADIUS, 14, 8))
	t.set_stylebox("focus", "Button", make_flat_panel(BG_HOVER, BORDER_FOCUS, 2, CORNER_RADIUS, 14, 8))
	t.set_stylebox("disabled", "Button", make_flat_panel(Color(BG_SURFACE, 0.55), Color(1, 1, 1, 0.05), 1, CORNER_RADIUS, 14, 8))

	t.set_stylebox("normal", "LineEdit", make_well_panel(BORDER_CARD, 10, 6))
	t.set_stylebox("focus", "LineEdit", make_well_panel(ACCENT_RALLY, 10, 6))
	t.set_font("font", "LineEdit", FONT_REGULAR)
	t.set_color("font_color", "LineEdit", TEXT_WHITE)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)

	t.set_stylebox("scroll", "VScrollBar", make_flat_panel(BG_WELL, BORDER_SUBTLE, 0, CORNER_RADIUS))
	t.set_stylebox("grabber", "VScrollBar", make_flat_panel(Color("#324155"), BORDER_SUBTLE, 0, CORNER_RADIUS))
	t.set_stylebox("grabber_highlight", "VScrollBar", make_flat_panel(ACCENT_RALLY, BORDER_SUBTLE, 0, CORNER_RADIUS))
	t.set_stylebox("grabber_pressed", "VScrollBar", make_flat_panel(ACCENT_RALLY, BORDER_SUBTLE, 0, CORNER_RADIUS))

	t.set_icon("unchecked", "CheckBox", _make_checkbox_icon(false, false))
	t.set_icon("checked", "CheckBox", _make_checkbox_icon(true, false))
	t.set_icon("unchecked_disabled", "CheckBox", _make_checkbox_icon(false, true))
	t.set_icon("checked_disabled", "CheckBox", _make_checkbox_icon(true, true))
	t.set_constant("h_separation", "CheckBox", 8)
	t.set_font("font", "CheckBox", FONT_MEDIUM)
	t.set_font_size("font_size", "CheckBox", 11)
	t.set_color("font_color", "CheckBox", TEXT_PRIMARY)
	t.set_color("font_hover_color", "CheckBox", TEXT_WHITE)
	t.set_color("font_pressed_color", "CheckBox", TEXT_WHITE)
	t.set_color("font_hover_pressed_color", "CheckBox", TEXT_WHITE)
	t.set_color("font_focus_color", "CheckBox", TEXT_WHITE)
	t.set_color("font_disabled_color", "CheckBox", TEXT_DIM)
	t.set_stylebox("normal", "CheckBox", make_flat_panel(BG_CARD, BORDER_CARD, 1, CORNER_RADIUS, 10, 6))
	t.set_stylebox("hover", "CheckBox", make_flat_panel(BG_HOVER, BORDER_HOVER, 1, CORNER_RADIUS, 10, 6))
	t.set_stylebox("pressed", "CheckBox", make_flat_panel(Color("#2a2010"), ACCENT_RALLY, 1, CORNER_RADIUS, 10, 6))
	t.set_stylebox("hover_pressed", "CheckBox", make_flat_panel(Color("#2a2010"), ACCENT_RALLY, 1, CORNER_RADIUS, 10, 6))
	t.set_stylebox("focus", "CheckBox", make_flat_panel(BG_HOVER, BORDER_FOCUS, 2, CORNER_RADIUS, 10, 6))
	return t


static func _make_checkbox_icon(checked: bool, disabled: bool) -> ImageTexture:
	var s := 16
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var bg := Color(BG_WELL.r, BG_WELL.g, BG_WELL.b, 0.55 if disabled else 1.0)
	var border := Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.45 if disabled else 0.90)
	if checked:
		bg = Color(ACCENT_RALLY.r, ACCENT_RALLY.g, ACCENT_RALLY.b, 0.45 if disabled else 1.0)
		border = bg
	img.fill(bg)
	for x in s:
		img.set_pixel(x, 0, border)
		img.set_pixel(x, s - 1, border)
		img.set_pixel(0, x, border)
		img.set_pixel(s - 1, x, border)
	if checked:
		var ink := Color(BG_BASE.r, BG_BASE.g, BG_BASE.b, 0.7 if disabled else 1.0)
		var pts := [
			Vector2i(3, 8), Vector2i(4, 9), Vector2i(5, 10), Vector2i(6, 11),
			Vector2i(7, 10), Vector2i(8, 9), Vector2i(9, 8), Vector2i(10, 7),
			Vector2i(11, 6), Vector2i(12, 5)
		]
		for p in pts:
			for dy in [0, 1]:
				if p.y + dy < s - 1:
					img.set_pixel(p.x, p.y + dy, ink)
	return ImageTexture.create_from_image(img)


## Crea un divisor ultra-fino de 1 px.
static func make_divider(vertical: bool = false, color: Color = BORDER_SUBTLE) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		rect.custom_minimum_size = Vector2(1, 0)
		rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		rect.custom_minimum_size = Vector2(0, 1)
		rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rect


## Aplica transicion nativa ligera (Tween) con degradado seguro en headless.
static func transition_control(target: Control, fade_in: bool = true, duration: float = 0.14) -> void:
	if target == null or not is_instance_valid(target):
		return
	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		target.modulate.a = 1.0 if fade_in else 0.0
		return
	var from_a := 0.0 if fade_in else target.modulate.a
	var to_a := 1.0 if fade_in else 0.0
	target.modulate.a = from_a
	var tw := target.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(target, "modulate:a", to_a, clampf(duration, 0.05, 0.25)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
