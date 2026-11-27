class_name UIDamageOverview
extends PanelContainer
## Reusable vehicle chassis summary and subsystem damage meters (shared by Pause & Service screens).

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _MeterScript := preload("res://ui/atoms/ui_progress_meter.gd")

var vehicle_name_label: Label
var drivetrain_label: Label
var mass_label: Label
var meters_box: VBoxContainer
var _root_vbox: VBoxContainer


func _ready() -> void:
	_ensure_nodes()
	_apply_style()


func _ensure_nodes() -> void:
	if _root_vbox != null:
		return
	_root_vbox = get_node_or_null("RootVBox") as VBoxContainer
	if _root_vbox == null:
		_root_vbox = VBoxContainer.new()
		_root_vbox.name = "RootVBox"
		_root_vbox.add_theme_constant_override("separation", 8)
		add_child(_root_vbox)

	var header_box := _root_vbox.get_node_or_null("VehicleInfo") as VBoxContainer
	if header_box == null:
		header_box = VBoxContainer.new()
		header_box.name = "VehicleInfo"
		header_box.add_theme_constant_override("separation", 2)
		_root_vbox.add_child(header_box)

	vehicle_name_label = header_box.get_node_or_null("VehicleNameLabel") as Label
	if vehicle_name_label == null:
		vehicle_name_label = Label.new()
		vehicle_name_label.name = "VehicleNameLabel"
		vehicle_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header_box.add_child(vehicle_name_label)

	drivetrain_label = header_box.get_node_or_null("DrivetrainLabel") as Label
	if drivetrain_label == null:
		drivetrain_label = Label.new()
		drivetrain_label.name = "DrivetrainLabel"
		drivetrain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header_box.add_child(drivetrain_label)

	mass_label = header_box.get_node_or_null("MassLabel") as Label
	if mass_label == null:
		mass_label = Label.new()
		mass_label.name = "MassLabel"
		mass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header_box.add_child(mass_label)

	meters_box = _root_vbox.get_node_or_null("MetersBox") as VBoxContainer
	if meters_box == null:
		meters_box = VBoxContainer.new()
		meters_box.name = "MetersBox"
		meters_box.add_theme_constant_override("separation", 6)
		_root_vbox.add_child(meters_box)


func _apply_style() -> void:
	add_theme_stylebox_override("panel", _Theme.make_flat_panel("bg_well", "border_card", 1, _Tokens.get_radius("technical"), 10, 10))
	_Theme.apply_label(vehicle_name_label, "gold", 13, false, true)
	_Theme.apply_label(drivetrain_label, "muted", 10, false, false)
	_Theme.apply_label(mass_label, "success", 11, true, true)


func set_vehicle_summary(display_name: String, drivetrain_text: String, mass_kg: float) -> void:
	_ensure_nodes()
	_apply_style()
	vehicle_name_label.text = display_name.to_upper()
	drivetrain_label.text = drivetrain_text
	mass_label.text = "Masa: %.0f kg" % mass_kg


func set_damage_entries(entries: Array[Dictionary]) -> void:
	## Each entry: {"label": String, "ratio": float (0=healthy, 1=destroyed), "hint": String}
	_ensure_nodes()
	for child in meters_box.get_children():
		meters_box.remove_child(child)
		child.queue_free()
	for item in entries:
		var meter := _MeterScript.new()
		var ratio := clampf(float(item.get("ratio", 0.0)), 0.0, 1.0)
		var health := 1.0 - ratio
		var hint := str(item.get("hint", "%d%%" % int(roundf(health * 100.0))))
		meter.set_meter(str(item.get("label", "")), health, hint, false)
		meters_box.add_child(meter)
