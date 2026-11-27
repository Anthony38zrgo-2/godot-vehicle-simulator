class_name UIPanelHeader
extends PanelContainer
## Standard Motorsport panel header: title, subtitle, optional right-side extra slot, and badge.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _BadgeScript := preload("res://ui/atoms/ui_badge.gd")

var title_label: Label
var subtitle_label: Label
var extra_slot: HBoxContainer
var badge: _BadgeScript
var _row: HBoxContainer


func _ready() -> void:
	_ensure_nodes()
	_apply_style()


func _ensure_nodes() -> void:
	if _row != null:
		return
	_row = get_node_or_null("HeaderRow") as HBoxContainer
	if _row == null:
		_row = HBoxContainer.new()
		_row.name = "HeaderRow"
		_row.add_theme_constant_override("separation", 12)
		add_child(_row)

	var left := _row.get_node_or_null("TitleBox") as VBoxContainer
	if left == null:
		left = VBoxContainer.new()
		left.name = "TitleBox"
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation", 2)
		_row.add_child(left)

	title_label = left.get_node_or_null("TitleLabel") as Label
	if title_label == null:
		title_label = Label.new()
		title_label.name = "TitleLabel"
		left.add_child(title_label)

	subtitle_label = left.get_node_or_null("SubtitleLabel") as Label
	if subtitle_label == null:
		subtitle_label = Label.new()
		subtitle_label.name = "SubtitleLabel"
		left.add_child(subtitle_label)

	extra_slot = _row.get_node_or_null("ExtraSlot") as HBoxContainer
	if extra_slot == null:
		extra_slot = HBoxContainer.new()
		extra_slot.name = "ExtraSlot"
		extra_slot.alignment = BoxContainer.ALIGNMENT_END
		extra_slot.add_theme_constant_override("separation", 10)
		_row.add_child(extra_slot)

	badge = _row.get_node_or_null("HeaderBadge") as _BadgeScript
	if badge == null:
		badge = _BadgeScript.new()
		badge.name = "HeaderBadge"
		_row.add_child(badge)


func _apply_style() -> void:
	add_theme_stylebox_override("panel", _Theme.make_flat_panel("bg_shell", "border_subtle", 1, _Tokens.get_radius("technical"), 16, 10))
	_Theme.apply_label(title_label, "title", 22, false, true)
	title_label.add_theme_font_override("font", _Tokens.get_font("title"))
	_Theme.apply_label(subtitle_label, "muted", 12, false, false)


func configure(title_text: String, subtitle_text: String = "", badge_top: String = "", badge_bottom: String = "") -> void:
	_ensure_nodes()
	_apply_style()
	title_label.text = title_text
	subtitle_label.text = subtitle_text
	subtitle_label.visible = not subtitle_text.is_empty()
	if badge_top.is_empty() and badge_bottom.is_empty():
		badge.visible = false
	else:
		badge.visible = true
		badge.set_texts(badge_top, badge_bottom)
