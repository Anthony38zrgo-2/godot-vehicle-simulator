class_name UIBadge
extends PanelContainer
## Single- or two-line header/tag badge styled from UITokenRegistry presets.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")

@export var preset_id: String = "badge.header"
@export var top_text: String = ""
@export var bottom_text: String = ""

var top_label: Label
var bottom_label: Label
var _vbox: VBoxContainer


func _init() -> void:
	_ensure_nodes()


func _ready() -> void:
	_ensure_nodes()
	apply_preset(preset_id)
	set_texts(top_text, bottom_text)


func _ensure_nodes() -> void:
	if _vbox != null:
		return
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 1)
	add_child(_vbox)

	top_label = Label.new()
	top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_vbox.add_child(top_label)

	bottom_label = Label.new()
	bottom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_vbox.add_child(bottom_label)


func apply_preset(new_preset_id: String) -> void:
	_ensure_nodes()
	preset_id = new_preset_id
	var spec := _Tokens.resolve_preset(preset_id)
	add_theme_stylebox_override(
		"panel",
		_Theme.make_flat_panel(
			spec.get("bg", "bg_well"),
			spec.get("border", "border_card"),
			1,
			_Tokens.get_radius("technical"),
			10,
			4
		)
	)
	_Theme.apply_label(top_label, str(spec.get("top_tone", "muted")), int(spec.get("top_size", 10)), true, false)
	_Theme.apply_label(bottom_label, str(spec.get("bottom_tone", "accent")), int(spec.get("bottom_size", 13)), false, true)


func set_texts(top: String, bottom: String = "") -> void:
	_ensure_nodes()
	top_text = top
	bottom_text = bottom
	top_label.text = top
	top_label.visible = not top.is_empty()
	bottom_label.text = bottom
	bottom_label.visible = not bottom.is_empty()


func set_alignment(align: HorizontalAlignment) -> void:
	_ensure_nodes()
	top_label.horizontal_alignment = align
	bottom_label.horizontal_alignment = align
