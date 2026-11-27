class_name UIButton
extends Button
## Semantic Motorsport button atom configured via UITokenRegistry tone or component preset.

const _Factory := preload("res://scripts/ui/core/ui_component_factory.gd")

@export var preset_id: String = ""
@export var tone: String = "chrome"
@export var font_size_override: int = 0
@export var pad_h_override: int = -1
@export var pad_v_override: int = -1


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	refresh_style()


func set_tone(new_tone: String) -> void:
	tone = new_tone
	preset_id = ""
	refresh_style()


func apply_preset(new_preset_id: String, overrides: Dictionary = {}) -> void:
	preset_id = new_preset_id
	var ov := overrides.duplicate()
	if font_size_override > 0 and not ov.has("font_size"):
		ov["font_size"] = font_size_override
	if pad_h_override >= 0 and not ov.has("pad_h"):
		ov["pad_h"] = pad_h_override
	if pad_v_override >= 0 and not ov.has("pad_v"):
		ov["pad_v"] = pad_v_override
	_Factory.apply_button_preset(self, preset_id, ov)


func refresh_style() -> void:
	var ov := {}
	if font_size_override > 0:
		ov["font_size"] = font_size_override
	if pad_h_override >= 0:
		ov["pad_h"] = pad_h_override
	if pad_v_override >= 0:
		ov["pad_v"] = pad_v_override
	var key := preset_id if not preset_id.is_empty() else tone
	_Factory.apply_button_preset(self, key, ov)
