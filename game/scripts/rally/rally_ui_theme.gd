class_name RallyUITheme
extends RefCounted

# =============================================================================
# SISTEMA DE DISEÑO MOTORSPORT MINIMALISTA UNIFICADO (FLAT PRECISION)
# =============================================================================
# Reglas unificadas para todos los menús, pantallas, HUDs y paneles del juego.
# Reemplaza completamente Aero Glass, relieves 3D/biseles y tipografías Serif.
# =============================================================================

# --- 2.1. PALETA DE COLORES FUNCIONAL ---

# Fondos
const BG_BASE := Color("#0a0e14")         # Negro carbón mate (fondo principal)
const BG_SURFACE := Color("#121820")      # Superficie de tarjetas y paneles
const BG_HOVER := Color("#1c2430")        # Interacción y hover/selección
const BG_PRESSED := Color("#080c10")      # Estado presionado ultra-oscuro
const BG_OVERLAY := Color(0.04, 0.06, 0.08, 0.88) # Capa de oscurecido modal
const BG_CARD := Color("#0e141c")         # Tarjetas secundarias y contenedores interiores

# Líneas y Divisores
const BORDER_SUBTLE := Color(1.0, 1.0, 1.0, 0.08) # 1 px de grosor, sin relieves ni biseles
const BORDER_HOVER := Color(1.0, 1.0, 1.0, 0.18)  # Borde iluminado sutil en hover
const BORDER_FOCUS := Color("#ffffff")              # Blanco puro para elemento con foco activo
const BORDER_ACCENT := Color("#e5a93c")             # Acento dorado para elemento seleccionado

# Tipografía
const TEXT_PRIMARY := Color("#f0f4f8")    # Blanco suave, contraste óptimo
const TEXT_MUTED := Color("#6b7a8d")      # Gris medio para etiquetas secundarias y unidades
const TEXT_DIM := Color("#4b5768")        # Gris atenuado para divisores y etiquetas terciarias
const TEXT_WHITE := Color("#ffffff")      # Blanco puro para titulares y datos destacados

# Semántica / Acentos de Carrera
const ACCENT_RALLY := Color("#e5a93c")    # Dorado histórico sobrio
const ACCENT_ALERT := Color("#f59e0b")    # Ámbar rally alertas y avisos
const STATUS_DANGER := Color("#ef4444")   # Pinchazos, sobrecalentamiento, abandonos, errores
const STATUS_SUCCESS := Color("#22c55e")  # Tiempos récord, verde de salida, confirmaciones
const STATUS_INFO := Color("#38bdf8")     # Azul cian informativo suave

# --- 2.3. PALETA WORKBENCH MOTORSPORT (VENTANAS Y PANELES EN JUEGO) ---
# Diseñada para garaje, servicio, inventario de neumáticos y pausas técnicas.
# Combina un marco exterior dark con un cuerpo de trabajo azul acero medio y wells de telemetría de alto contraste.
const WB_BG_SHELL := Color("#090e15")        # Armazón y fondo exterior oscuro
const WB_BG_HEADER := Color("#0d141e")       # Barra superior / título
const WB_BG_FOOTER := Color("#0d141e")       # Barra inferior de acciones
const WB_BG_TAB_INACTIVE := Color("#111822") # Pestaña inactiva oscura
const WB_BG_TAB_ACTIVE := Color("#1a2636")   # Pestaña activa (conectada con el contenido)
const WB_BG_CONTENT := Color("#1a2636")      # Fondo principal del área de contenido (azul acero medio)
const WB_BG_CARD := Color("#223246")         # Superficie de tarjetas y grupos interiores
const WB_BG_CARD_HOVER := Color("#2a3d54")   # Hover en tarjetas interiores
const WB_BG_WELL := Color("#0c141e")         # Wells técnicos oscuros para displays de valores
const WB_BORDER_SUBTLE := Color(1.0, 1.0, 1.0, 0.10) # Borde plano 1 px
const WB_BORDER_HOVER := Color(1.0, 1.0, 1.0, 0.20)  # Borde 1 px iluminado
const WB_BORDER_FOCUS := Color("#ffffff")              # Borde de foco blanco
const WB_BORDER_ACCENT := Color("#e5a93c")             # Acento rally dorado
const WB_SLIDER_TRACK := Color("#0c141e")              # Riel del deslizador (well oscuro)
const WB_SLIDER_FILL := Color("#4a7bb0")               # Relleno del deslizador azul acero vivo
const WB_SLIDER_THUMB := Color("#eaf2fa")              # Manecilla del deslizador
const WB_SLIDER_STEPPER := Color("#25364b")            # Botones [+] [-]
const WB_TEXT_TITLE := Color("#f0f5fa")      # Títulos y encabezados de alta legibilidad
const WB_TEXT_LABEL := Color("#9ab0c7")      # Etiquetas, pistas y unidades gris-azuladas
const WB_TEXT_DATA := Color("#ffffff")       # Números y telemetría D-DIN blanco puro
const WB_TEXT_ACCENT := Color("#e5a93c")     # Resaltados dorados


# --- 2.2. ESTANDARIZACIÓN TIPOGRÁFICA ---

# Títulos, Navegación, Etiquetas y Botones: Montserrat
const FONT_TITLE: Font = preload("res://fonts/montserrat/Montserrat-Bold.ttf")
const FONT_REGULAR: Font = preload("res://fonts/montserrat/Montserrat-Regular.ttf")

# Datos, Tiempos, Marchas y Telemetría: D-DIN / D-DIN-Bold
const FONT_DATA: Font = preload("res://fonts/D-DIN.ttf")
const FONT_DATA_BOLD: Font = preload("res://fonts/D-DIN-Bold.ttf")
const FONT_DATA_COND: Font = preload("res://fonts/D-DINCondensed.ttf")
const FONT_DATA_COND_BOLD: Font = preload("res://fonts/D-DINCondensed-Bold.ttf")


# --- MÉTODOS FACTORY PARA ESTILOS PLANOS (STYLEBOXFLAT) ---

## Crea un StyleBoxFlat minimalista sin relieves ni sombras
static func make_flat_panel(
	bg: Color = BG_SURFACE,
	border_col: Color = BORDER_SUBTLE,
	border_w: int = 1,
	corner_r: int = 0
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_col
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(corner_r)
	sb.shadow_size = 0
	sb.anti_aliasing = true
	return sb


## Estiliza un botón interactivo según el estándar minimalista
static func style_button(
	btn: Button,
	font_size: int = 14,
	pad_h: int = 18,
	pad_v: int = 12,
	is_primary: bool = false
) -> void:
	var normal := make_flat_panel(
		BG_CARD if not is_primary else BG_SURFACE,
		BORDER_SUBTLE if not is_primary else Color(BORDER_ACCENT.r, BORDER_ACCENT.g, BORDER_ACCENT.b, 0.4),
		1,
		0
	)
	normal.content_margin_left = pad_h
	normal.content_margin_right = pad_h
	normal.content_margin_top = pad_v
	normal.content_margin_bottom = pad_v

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = BG_HOVER
	hover.border_color = ACCENT_RALLY if is_primary else BORDER_HOVER
	hover.set_border_width_all(1)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = BG_PRESSED
	pressed.border_color = ACCENT_RALLY

	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = BG_HOVER
	focus.border_color = BORDER_FOCUS
	focus.set_border_width_all(2)

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(BG_CARD.r, BG_CARD.g, BG_CARD.b, 0.4)
	disabled.border_color = Color(BORDER_SUBTLE.r, BORDER_SUBTLE.g, BORDER_SUBTLE.b, 0.2)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_font_override("font", FONT_TITLE)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", TEXT_WHITE)
	btn.add_theme_color_override("font_pressed_color", ACCENT_RALLY)
	btn.add_theme_color_override("font_focus_color", TEXT_WHITE)
	btn.add_theme_color_override("font_disabled_color", TEXT_MUTED)


## Estiliza un botón editorial de índice con acento de 2-3px a la izquierda
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
		normal.bg_color = Color(1.0, 1.0, 1.0, 0.04)
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
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.06)
	hover.border_color = TEXT_WHITE
	hover.border_width_left = 3

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_font_override("font", FONT_TITLE)
	btn.add_theme_color_override("font_hover_color", TEXT_WHITE)
	btn.add_theme_color_override("font_focus_color", TEXT_WHITE)


## Crea un divisor ultra-fino de 1 px
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
