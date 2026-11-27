class_name UIModalShell
extends Control
## Standard Motorsport modal shell: Backdrop + centered window PanelContainer + UIPanelHeader +
## optional UITabBar slot + UINoticeBanner + body ContentBox + UIPanelFooter.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _HeaderScript := preload("res://ui/molecules/ui_panel_header.gd")
const _FooterScript := preload("res://ui/molecules/ui_panel_footer.gd")
const _NoticeScript := preload("res://ui/atoms/ui_notice_banner.gd")

var backdrop: ColorRect
var window_panel: PanelContainer
var header: _HeaderScript
var top_bar_slot: VBoxContainer
var notice_banner: _NoticeScript
var body_box: VBoxContainer
var footer: _FooterScript
var _margin: MarginContainer
var _root_vbox: VBoxContainer


func _ready() -> void:
	_ensure_nodes()
	_apply_style()


func _ensure_nodes() -> void:
	if window_panel != null:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	backdrop = get_node_or_null("Backdrop") as ColorRect
	if backdrop == null:
		backdrop = ColorRect.new()
		backdrop.name = "Backdrop"
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(backdrop)

	_margin = get_node_or_null("WindowMargin") as MarginContainer
	if _margin == null:
		_margin = MarginContainer.new()
		_margin.name = "WindowMargin"
		_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_margin)

	window_panel = _margin.get_node_or_null("WindowPanel") as PanelContainer
	if window_panel == null:
		window_panel = PanelContainer.new()
		window_panel.name = "WindowPanel"
		window_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		window_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_margin.add_child(window_panel)

	_root_vbox = window_panel.get_node_or_null("RootVBox") as VBoxContainer
	if _root_vbox == null:
		_root_vbox = VBoxContainer.new()
		_root_vbox.name = "RootVBox"
		_root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_root_vbox.add_theme_constant_override("separation", 8)
		window_panel.add_child(_root_vbox)

	header = _root_vbox.get_node_or_null("Header") as _HeaderScript
	if header == null:
		header = _HeaderScript.new()
		header.name = "Header"
		_root_vbox.add_child(header)

	top_bar_slot = _root_vbox.get_node_or_null("TopBarSlot") as VBoxContainer
	if top_bar_slot == null:
		top_bar_slot = VBoxContainer.new()
		top_bar_slot.name = "TopBarSlot"
		top_bar_slot.add_theme_constant_override("separation", 4)
		_root_vbox.add_child(top_bar_slot)

	notice_banner = _root_vbox.get_node_or_null("NoticeBanner") as _NoticeScript
	if notice_banner == null:
		notice_banner = _NoticeScript.new()
		notice_banner.name = "NoticeBanner"
		_root_vbox.add_child(notice_banner)

	body_box = _root_vbox.get_node_or_null("BodyBox") as VBoxContainer
	if body_box == null:
		body_box = VBoxContainer.new()
		body_box.name = "BodyBox"
		body_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body_box.add_theme_constant_override("separation", 10)
		_root_vbox.add_child(body_box)

	footer = _root_vbox.get_node_or_null("Footer") as _FooterScript
	if footer == null:
		footer = _FooterScript.new()
		footer.name = "Footer"
		_root_vbox.add_child(footer)


func _apply_style() -> void:
	theme = _Theme.get_menu_theme()
	backdrop.color = _Tokens.get_color("bg_overlay")
	set_window_margins(24, 20)
	window_panel.add_theme_stylebox_override("panel", _Theme.make_panel_from_preset("panel.window", {"pad_h": 12, "pad_v": 10}))


func set_window_margins(margin_h: int, margin_v: int) -> void:
	_ensure_nodes()
	_margin.add_theme_constant_override("margin_left", margin_h)
	_margin.add_theme_constant_override("margin_right", margin_h)
	_margin.add_theme_constant_override("margin_top", margin_v)
	_margin.add_theme_constant_override("margin_bottom", margin_v)


func show_notice(msg: String, is_error: bool = false) -> void:
	_ensure_nodes()
	notice_banner.show_notice(msg, is_error)


func clear_notice() -> void:
	_ensure_nodes()
	notice_banner.clear_notice()


func clear_body() -> void:
	_ensure_nodes()
	for child in body_box.get_children():
		body_box.remove_child(child)
		child.queue_free()
