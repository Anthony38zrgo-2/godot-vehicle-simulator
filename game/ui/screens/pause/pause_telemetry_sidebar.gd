class_name PauseTelemetrySidebar
extends PanelContainer
## Live damage & running-gear diagnostics sidebar composed from UIProgressMeter and UITokenRegistry.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")
const _MeterScript := preload("res://ui/atoms/ui_progress_meter.gd")

var telemetry_vbox: VBoxContainer
var _initialized: bool = false


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _initialized:
		return
	_initialized = true
	custom_minimum_size = Vector2(280, 0)
	add_theme_stylebox_override("panel", _Theme.make_panel_from_preset("panel.window"))

	var margin := get_node_or_null("SidebarMargin") as MarginContainer
	if margin == null:
		margin = MarginContainer.new()
		margin.name = "SidebarMargin"
		add_child(margin)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)

	var scroll := margin.get_node_or_null("SidebarScroll") as ScrollContainer
	if scroll == null:
		scroll = ScrollContainer.new()
		scroll.name = "SidebarScroll"
		margin.add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	telemetry_vbox = scroll.get_node_or_null("TelemetryVBox") as VBoxContainer
	if telemetry_vbox == null:
		telemetry_vbox = VBoxContainer.new()
		telemetry_vbox.name = "TelemetryVBox"
		scroll.add_child(telemetry_vbox)
	telemetry_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	telemetry_vbox.add_theme_constant_override("separation", 8)


func populate(session: Node, compound_label_cb: Callable) -> void:
	_ensure_nodes()
	for child in telemetry_vbox.get_children():
		child.queue_free()
	if session == null:
		return

	var v: Variant = session.get("vehicle")
	var sim: Variant = v.get("simulation") if v != null else null
	var tm: Variant = sim.get("thermal_model") if sim != null else null
	var pm: Variant = sim.get("powertrain_model") if sim != null else null
	var pub: Dictionary = v.get("published_state") if v != null and v.get("published_state") is Dictionary else {}
	var pub_dmg: Dictionary = pub.get("damage", {})
	var pub_eng: Dictionary = pub.get("engine", {})

	var rad_dmg := float(tm.radiator_damage) if tm != null and tm.get("radiator_damage") != null else float(pub_dmg.get("radiator", pub_eng.get("radiator_damage", 0.0)))
	var eng_dmg := float(tm.engine_damage) if tm != null and tm.get("engine_damage") != null else float(pub_dmg.get("engine", pub_eng.get("engine_damage", 0.0)))
	var trans_dmg := float(pm.transmission_damage) if pm != null and pm.get("transmission_damage") != null else float(pub_dmg.get("transmission", 0.0))

	var dmg_card := PanelContainer.new()
	dmg_card.add_theme_stylebox_override("panel", _Theme.make_flat_panel("bg_card", "border_subtle", 1, -1, 10, 6))
	var d_vbox := VBoxContainer.new()
	d_vbox.add_theme_constant_override("separation", 7)
	dmg_card.add_child(d_vbox)

	var d_title := Label.new()
	d_title.text = "DAÑOS"
	d_title.add_theme_font_override("font", _Tokens.get_font("subtitle"))
	d_title.add_theme_font_size_override("font_size", 14)
	d_title.add_theme_color_override("font_color", _Tokens.get_color("text_muted"))
	d_vbox.add_child(d_title)

	var rad_hint := "FUGA" if rad_dmg >= 0.05 and rad_dmg < 0.70 else ("CRÍTICO" if rad_dmg >= 0.70 else "")
	var eng_hint := "CRÍTICO" if eng_dmg >= 0.70 else ""
	var trans_hint := "CRÍTICO" if trans_dmg >= 0.70 else ""
	d_vbox.add_child(_create_damage_bar_row("RADIADOR", rad_dmg, rad_hint))
	d_vbox.add_child(_create_damage_bar_row("MOTOR", eng_dmg, eng_hint))
	d_vbox.add_child(_create_damage_bar_row("TRANS.", trans_dmg, trans_hint))
	telemetry_vbox.add_child(dmg_card)

	if v != null and v.get("tire_inventory") != null and v.tire_inventory.get("mounted") != null:
		var inv = v.tire_inventory
		var mounted: Array = inv.mounted
		var brake_losses: Array = sim.brake_collision_loss if sim != null and sim.get("brake_collision_loss") != null else pub_dmg.get("brake_collision_loss", [])
		var align_dmgs: Array = sim.alignment_collision_damage if sim != null and sim.get("alignment_collision_damage") != null else pub_dmg.get("alignment_collision_damage", [])

		var tire_card := PanelContainer.new()
		tire_card.add_theme_stylebox_override("panel", _Theme.make_flat_panel("bg_card", "border_subtle", 1, -1, 10, 6))
		var t_vbox := VBoxContainer.new()
		t_vbox.add_theme_constant_override("separation", 5)
		tire_card.add_child(t_vbox)

		var t_title := Label.new()
		t_title.text = "NEUMÁTICOS Y TREN DE RODAJE"
		t_title.add_theme_font_override("font", _Tokens.get_font("subtitle"))
		t_title.add_theme_font_size_override("font_size", 13)
		t_title.add_theme_color_override("font_color", _Tokens.get_color("text_muted"))
		t_vbox.add_child(t_title)

		var corners := ["FL", "FR", "RL", "RR"]
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 4)
		t_vbox.add_child(grid)

		var c_green := _Tokens.get_color("status_success")
		var c_gold := _Tokens.get_color("accent_rally")
		var c_danger := _Tokens.get_color("status_danger")
		for i in mini(4, mounted.size()):
			var tire: Dictionary = mounted[i]
			var st: Dictionary = tire.get("state", {})
			var wear := clampf(float(st.get("wear_fraction", 0.0)) * 100.0, 0.0, 100.0)
			var life := maxf(0.0, 100.0 - wear)
			var is_dest: bool = (inv.has_method("is_carcass_destroyed") and bool(inv.is_carcass_destroyed(tire))) or float(st.get("carcass_failure", 0.0)) >= 0.99
			var has_leak: bool = (inv.has_method("is_punctured") and bool(inv.is_punctured(tire))) or float(st.get("leak_per_second", 0.0)) > 0.0
			var has_rim: bool = (inv.has_method("is_rim_damaged") and bool(inv.is_rim_damaged(tire))) or float(st.get("rim_deformation", 0.0)) > 0.005
			var brake_loss := clampf(float(brake_losses[i]), 0.0, 1.0) if i < brake_losses.size() else 0.0
			var align_dmg := clampf(float(align_dmgs[i]), 0.0, 1.0) if i < align_dmgs.size() else 0.0

			var c_stat := "VIDA %.0f%%" % life
			var col := c_green if wear < 30.0 else (c_gold if wear < 65.0 else c_danger)
			if is_dest:
				c_stat = "DESTALONADO · %.0f%%" % life
				col = c_danger
			elif has_leak:
				c_stat = "FUGA · %.0f%%" % life
				col = c_danger
			elif has_rim:
				c_stat = "ARO · %.0f%%" % life
				col = c_danger if wear >= 50.0 else c_gold

			var extras := PackedStringArray()
			if align_dmg > 0.005:
				extras.append("ALIN %d%%" % roundi(align_dmg * 100.0))
			if brake_loss > 0.005:
				extras.append("FREN -%d%%" % roundi(brake_loss * 100.0))
			var extra_suffix := (" · " + " ".join(extras)) if not extras.is_empty() else ""

			var cid := str(tire.get("compound_id", ""))
			var comp_lbl := str(compound_label_cb.call(cid, true)) if compound_label_cb.is_valid() else cid
			var lbl := Label.new()
			lbl.text = "%s: %s [%s]%s" % [corners[i], comp_lbl, c_stat, extra_suffix]
			lbl.add_theme_font_override("font", _Tokens.get_font("data_bold_tight"))
			lbl.add_theme_font_size_override("font_size", 9)
			lbl.add_theme_color_override("font_color", col)
			grid.add_child(lbl)

		var spares_info := Label.new()
		if inv.has_method("is_pool_mode") and inv.is_pool_mode():
			spares_info.text = "Repuestos: %d de %d · Quedan %d / 10 en el rally" % [inv.spares.size(), inv.capacity, inv.total_count()]
		else:
			spares_info.text = "Repuestos disponibles: %d de %d" % [inv.spares.size(), inv.capacity]
		spares_info.add_theme_font_override("font", _Tokens.get_font("regular"))
		spares_info.add_theme_font_size_override("font_size", 10)
		spares_info.add_theme_color_override("font_color", _Tokens.get_color("text_muted"))
		t_vbox.add_child(spares_info)
		telemetry_vbox.add_child(tire_card)


func _damage_color(ratio: float) -> Color:
	if ratio < 0.25:
		return _Tokens.get_color("status_success")
	if ratio < 0.50:
		return _Tokens.get_color("accent_rally")
	if ratio < 0.75:
		return _Tokens.get_color("status_warning")
	return _Tokens.get_color("status_danger")


func _create_damage_bar_row(label_text: String, ratio: float, status_hint: String = "") -> Control:
	var clamped := clampf(ratio, 0.0, 1.0)
	var pct_int := roundi(clamped * 100.0)
	var readout := ("%d%% · %s" % [pct_int, status_hint]) if not status_hint.is_empty() else ("%d%%" % pct_int)
	var meter := _MeterScript.new()
	meter.set_meter(label_text, clamped, readout, true)
	var col := _damage_color(clamped)
	meter.set_fill_color(col)
	meter.title_label.add_theme_font_size_override("font_size", 10)
	meter.value_label.add_theme_font_size_override("font_size", 10)
	meter.value_label.add_theme_color_override("font_color", _Tokens.get_color("text_primary") if clamped < 0.05 else col)
	return meter
