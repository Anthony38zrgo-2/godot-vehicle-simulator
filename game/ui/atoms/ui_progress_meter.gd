class_name UIProgressMeter
extends VBoxContainer
## Semantic progress/damage/time meter with label, readout text, and threshold coloring.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")

var title_label: Label
var value_label: Label
var progress_bar: ProgressBar


func _init() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if progress_bar != null:
		return
	add_theme_constant_override("separation", 4)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	add_child(header)

	title_label = Label.new()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_Theme.apply_label(title_label, "muted", 12, false, false)
	header.add_child(title_label)

	value_label = Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_Theme.apply_label(value_label, "data", 12, true, true)
	header.add_child(value_label)

	progress_bar = ProgressBar.new()
	progress_bar.show_percentage = false
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.custom_minimum_size = Vector2(0, 8)
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(progress_bar)
	set_fill_color(_Tokens.get_color("accent_rally"))


func set_meter(title_text: String, ratio: float, readout: String = "", invert_severity: bool = false) -> void:
	_ensure_nodes()
	var clamped := clampf(ratio, 0.0, 1.0)
	title_label.text = title_text
	value_label.text = readout if not readout.is_empty() else ("%d%%" % int(roundf(clamped * 100.0)))
	progress_bar.value = clamped * 100.0
	var severity := clamped if invert_severity else (1.0 - clamped)
	var fill_col := _Tokens.get_color("status_success")
	if severity >= 0.70:
		fill_col = _Tokens.get_color("status_danger")
	elif severity >= 0.35:
		fill_col = _Tokens.get_color("accent_alert")
	set_fill_color(fill_col)


func set_fill_color(color: Color) -> void:
	_ensure_nodes()
	var r := _Tokens.get_radius("technical")
	progress_bar.add_theme_stylebox_override("background", _Theme.make_flat_panel("bg_well", "border_subtle", 1, r))
	progress_bar.add_theme_stylebox_override("fill", _Theme.make_flat_panel(color, color, 0, r))
