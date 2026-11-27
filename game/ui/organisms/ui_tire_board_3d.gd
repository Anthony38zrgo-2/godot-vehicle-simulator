class_name UITireBoard3D
extends VBoxContainer
## Unified interactive tire pool board (Mounted 4 + Spares + Service Stock) supporting
## drag & drop, click-to-swap, and D-Pad/keyboard focus navigation.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _SlotScript := preload("res://ui/organisms/ui_tire_slot_card.gd")

signal slot_activated(group_name: String, index: int)
signal transfer_requested(src_group: String, src_index: int, dst_group: String, dst_index: int)

const MOUNTED_LABELS := ["FL", "FR", "RL", "RR"]

var mounted_grid: GridContainer
var spares_row: HBoxContainer
var stock_grid: GridContainer
var slots: Array = []
var selected_group: String = ""
var selected_index: int = -1


func _init() -> void:
	_ensure_nodes()


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if mounted_grid != null:
		return
	add_theme_constant_override("separation", 10)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 12)
	add_child(top_hbox)

	var mounted_panel := _make_section_box("MONTADAS (4)")
	mounted_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(mounted_panel)
	mounted_grid = GridContainer.new()
	mounted_grid.columns = 2
	mounted_grid.add_theme_constant_override("h_separation", 8)
	mounted_grid.add_theme_constant_override("v_separation", 8)
	mounted_panel.get_child(0).add_child(mounted_grid)

	var spares_panel := _make_section_box("REPUESTOS (MALETERO)")
	spares_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spares_panel)
	spares_row = HBoxContainer.new()
	spares_row.add_theme_constant_override("separation", 8)
	spares_panel.get_child(0).add_child(spares_row)

	var stock_panel := _make_section_box("STOCK DE ASISTENCIA")
	add_child(stock_panel)
	stock_grid = GridContainer.new()
	stock_grid.columns = 4
	stock_grid.add_theme_constant_override("h_separation", 8)
	stock_grid.add_theme_constant_override("v_separation", 8)
	stock_panel.get_child(0).add_child(stock_grid)


func _make_section_box(title_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _Theme.make_flat_panel("bg_well", "border_subtle", 1, _Tokens.get_radius("technical"), 10, 8))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var lbl := Label.new()
	lbl.text = title_text
	_Theme.apply_label(lbl, "muted", 11, false, true)
	vb.add_child(lbl)
	return panel


func populate(mounted: Array, spares: Array, stock: Array, label_lookup: Callable = Callable()) -> void:
	_ensure_nodes()
	for box in [mounted_grid, spares_row, stock_grid]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	slots.clear()

	for i in 4:
		var td: Dictionary = mounted[i] as Dictionary if i < mounted.size() and mounted[i] is Dictionary else {}
		_add_slot(mounted_grid, "mounted", i, MOUNTED_LABELS[i], td, label_lookup)

	var spare_slots := maxi(2, spares.size())
	for i in spare_slots:
		var td: Dictionary = spares[i] as Dictionary if i < spares.size() and spares[i] is Dictionary else {}
		_add_slot(spares_row, "spares", i, "REP %d" % (i + 1), td, label_lookup)

	for i in stock.size():
		var td: Dictionary = stock[i] as Dictionary if stock[i] is Dictionary else {}
		_add_slot(stock_grid, "stock", i, "STK %d" % (i + 1), td, label_lookup)

	refresh_selection()


func _add_slot(parent: Control, group: String, idx: int, title: String, td: Dictionary, label_lookup: Callable) -> void:
	var card := _SlotScript.new()
	var cid := str(td.get("compound_id", ""))
	var cname := str(label_lookup.call(cid)) if (not cid.is_empty() and label_lookup.is_valid()) else cid
	card.configure_slot(group, idx, title, td, cname)
	card.slot_clicked.connect(_on_slot_clicked)
	card.slot_drop_requested.connect(_on_slot_drop)
	parent.add_child(card)
	slots.append(card)


func set_selected(group: String, idx: int) -> void:
	selected_group = group
	selected_index = idx
	refresh_selection()


func refresh_selection() -> void:
	for s in slots:
		var sel: bool = (str(s.group_name) == selected_group and int(s.slot_index) == selected_index)
		s.set_selected_state(sel, false)


func _on_slot_clicked(group: String, idx: int) -> void:
	if selected_group.is_empty() or selected_index < 0:
		set_selected(group, idx)
		slot_activated.emit(group, idx)
		return
	if selected_group == group and selected_index == idx:
		set_selected("", -1)
		slot_activated.emit(group, idx)
		return
	var src_g := selected_group
	var src_i := selected_index
	set_selected("", -1)
	transfer_requested.emit(src_g, src_i, group, idx)


func _on_slot_drop(payload: Dictionary, dst_group: String, dst_idx: int) -> void:
	var src_g := str(payload.get("group", ""))
	var src_i := int(payload.get("index", -1))
	if src_g.is_empty() or src_i < 0:
		return
	if src_g == dst_group and src_i == dst_idx:
		return
	set_selected("", -1)
	transfer_requested.emit(src_g, src_i, dst_group, dst_idx)
