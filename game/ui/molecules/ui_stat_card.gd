class_name UIStatCard
extends PanelContainer
## Compact Motorsport KPI/telemetry card unifying spec items, telemetry cards, and results hero cards.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")

var title_label: Label
var value_label: Label
var subtitle_label: Label
var _vbox: VBoxContainer


func _ready() -> void:
	_ensure_nodes()
	_apply_style()


func _ensure_nodes() -> void:
	if _vbox != null:
		return
	_vbox = get_node_or_null("CardVBox") as VBoxContainer
	if _vbox == null:
		_vbox = VBoxContainer.new()
		_vbox.name = "CardVBox"
		_vbox.add_theme_constant_override("separation", 3)
		add_child(_vbox)

	title_label = _vbox.get_node_or_null("TitleLabel") as Label
	if title_label == null:
		title_label = Label.new()
		title_label.name = "TitleLabel"
		_vbox.add_child(title_label)

	value_label = _vbox.get_node_or_null("ValueLabel") as Label
	if value_label == null:
		value_label = Label.new()
		value_label.name = "ValueLabel"
		_vbox.add_child(value_label)

	subtitle_label = _vbox.get_node_or_null("SubtitleLabel") as Label
	if subtitle_label == null:
		subtitle_label = Label.new()
		subtitle_label.name = "SubtitleLabel"
		_vbox.add_child(subtitle_label)


func _apply_style() -> void:
	add_theme_stylebox_override("panel", _Theme.make_panel_from_preset("card.stat_telemetry"))
	_Theme.apply_label(title_label, "muted", 11, false, true)
	_Theme.apply_label(value_label, "data", 18, true, true)
	_Theme.apply_label(subtitle_label, "muted", 11, false, false)


func set_stat(title_text: String, primary_text: String, sub_text: String = "", primary_color: Color = Color(-1, -1, -1, -1), sub_color: Color = Color(-1, -1, -1, -1)) -> void:
	_ensure_nodes()
	_apply_style()
	title_label.text = title_text
	value_label.text = primary_text
	subtitle_label.text = sub_text
	subtitle_label.visible = not sub_text.is_empty()
	if primary_color.r >= 0.0:
		value_label.add_theme_color_override("font_color", primary_color)
	if sub_color.r >= 0.0:
		subtitle_label.add_theme_color_override("font_color", sub_color)
