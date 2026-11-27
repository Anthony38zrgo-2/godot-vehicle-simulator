class_name RallyUITheme
extends RefCounted
## Compatibility facade over UITokenRegistry and UIThemeBuilder (Flat Precision Motorsport Design System).
## All visual tokens, cached StyleBoxFlat resources, and Theme construction live in res://scripts/ui/core/
## and res://data/ui/tokens.json.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _Factory := preload("res://scripts/ui/core/ui_component_factory.gd")

const CORNER_RADIUS: int = 2

# --- 1. PALETA FUNCIONAL UNIFICADA (DARK CARBON + BRASS GOLD) ---
const BG_BASE := Color("#0a0e14")
const BG_SHELL := Color("#0c1118")
const BG_SURFACE := Color("#11161f")
const BG_CARD := Color("#18202c")
const BG_ELEVATED := Color("#1c2635")
const BG_HOVER := Color("#202a38")
const BG_PRESSED := Color("#080c10")
const BG_WELL := Color("#080c11")
const BG_OVERLAY := Color(0.03, 0.05, 0.08, 0.88)

const BORDER_SUBTLE := Color(1.0, 1.0, 1.0, 0.10)
const BORDER_CARD := Color(1.0, 1.0, 1.0, 0.14)
const BORDER_HOVER := Color(1.0, 1.0, 1.0, 0.24)
const BORDER_FOCUS := Color("#ffffff")
const BORDER_ACCENT := Color("#e5a93c")

const TEXT_PRIMARY := Color("#f0f4f8")
const TEXT_MUTED := Color("#8393a5")
const TEXT_DIM := Color("#536071")
const TEXT_WHITE := Color("#ffffff")
const TEXT_GOLD_SOFT := Color("#f5d799")

const ACCENT_RALLY := Color("#e5a93c")
const ACCENT_RALLY_DARK := Color("#b37f22")
const ACCENT_RALLY_SOFT := Color(0.898, 0.663, 0.235, 0.15)
const ACCENT_ALERT := Color("#f59e0b")
const STATUS_DANGER := Color("#ef4444")
const STATUS_SUCCESS := Color("#22c55e")
const STATUS_INFO := Color("#38bdf8")

# --- 2. ALIAS WORKBENCH CONSOLIDADOS ---
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

# --- 3. TIPOGRAFÍA DE MENÚS ---
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


static func make_flat_panel(
	bg: Color = BG_SURFACE,
	border_col: Color = BORDER_SUBTLE,
	border_w: int = 1,
	corner_r: int = CORNER_RADIUS,
	pad_h: int = -1,
	pad_v: int = -1
) -> StyleBoxFlat:
	return _Tokens.get_flat_stylebox(bg, border_col, border_w, corner_r, pad_h, pad_v)


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


static func style_tone_button(
	btn: Button,
	tone: String = "chrome",
	font_size: int = 14,
	pad_h: int = 14,
	pad_v: int = 8,
	corner_r: int = CORNER_RADIUS,
	font_res: Font = FONT_BUTTON
) -> void:
	_Theme.apply_tone_button(btn, tone, font_size, pad_h, pad_v, corner_r, font_res)


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


static func style_card_surface(
	btn: Button,
	selected: bool = false,
	font_size: int = 14,
	pad_h: int = 14,
	pad_v: int = 10,
	accent_col: Color = ACCENT_RALLY
) -> void:
	_Theme.apply_card_surface(btn, selected, font_size, pad_h, pad_v, accent_col)


static func style_editorial_item(
	btn: Button,
	is_active: bool,
	font_size: int = 14,
	pad_v: int = 10
) -> void:
	_Theme.apply_editorial_item(btn, is_active, font_size, pad_v)


static func style_option_button(
	opt: OptionButton,
	font_size: int = 12,
	pad_h: int = 12,
	pad_v: int = 7
) -> void:
	_Theme.apply_option_button(opt, font_size, pad_h, pad_v)


static func style_tree(tree: Tree, font_size: int = 13) -> void:
	_Theme.apply_tree(tree, font_size)


static func style_label(
	lbl: Label,
	tone: String = "primary",
	font_size: int = 14,
	use_data_font: bool = false,
	bold: bool = false
) -> void:
	_Theme.apply_label(lbl, tone, font_size, use_data_font, bold)


static func build_menu_theme() -> Theme:
	return _Theme.get_menu_theme()


static func make_divider(vertical: bool = false, color: Color = BORDER_SUBTLE) -> ColorRect:
	return _Factory.create_divider(vertical, color)


static func transition_control(target: Control, fade_in: bool = true, duration: float = 0.14) -> void:
	_Theme.transition_control(target, fade_in, duration)
