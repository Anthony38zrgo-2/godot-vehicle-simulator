extends SceneTree

const EscortScene := preload("res://scenes/rally/ford_escort_rs2000_1971.tscn")
const GarageScript := preload("res://scripts/rally/rally_garage_panel.gd")
const ServicePanelScript := preload("res://scripts/rally/rally_service_panel.gd")
const StrategyScreenScript := preload("res://scripts/rally/rally_tire_strategy_screen.gd")
const PauseInventoryScript := preload("res://scripts/rally/rally_pause_inventory.gd")
const EventManagerScript := preload("res://scripts/rally/rally_event_manager.gd")

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("REGRESSION FAILURE: " + label)


func _initialize() -> void:
	call_deferred("_run")


func _populate_pool(vehicle: RallyEscortVehicle) -> void:
	vehicle.ensure_tire_inventory()
	var inv: RallyTireInventory = vehicle.tire_inventory
	inv.mounted.clear()
	inv.spares.clear()
	inv.service_stock.clear()
	inv.discarded.clear()
	inv.next_id = 1
	for i in 4:
		inv.mounted.append(inv.item("gravel_normal", vehicle.fresh_tire_state("gravel_normal", i)))
	for i in 2:
		inv.spares.append(inv.item("gravel_normal", vehicle.fresh_tire_state("gravel_normal")))
	for cid in ["gravel_normal", "gravel_wet", "gravel_normal", "gravel_wet"]:
		inv.service_stock.append(inv.item(cid, vehicle.fresh_tire_state(cid)))
	vehicle.apply_tire_inventory()


func _collect_label_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += (node as Label).text + "\n"
	elif node is RichTextLabel:
		out += (node as RichTextLabel).text + "\n"
	for child in node.get_children():
		out += _collect_label_text(child)
	return out


func _make_host(vehicle: RallyEscortVehicle) -> Node:
	var script := GDScript.new()
	script.source_code = """extends Node
var vehicle: Node = null
var allow_service: bool = true
var session_ready: bool = true
var awaiting_setup: bool = false
var stage_transition_running: bool = false
var competition = null
var course = null
var garage_panel = null
var session_track_id: String = "russia_stage1"
func may_service_tires() -> bool:
	return allow_service
func on_vehicle_reset_requested() -> void:
	pass
func retire_competition_player() -> void:
	pass
func on_quick_repair_radiator_requested(_heavy: bool = false) -> bool:
	return false
"""
	script.reload()
	var host: Node = script.new()
	host.vehicle = vehicle
	var comp := preload("res://scripts/rally/rally_competition.gd").new()
	comp.save_path = ""
	comp.configure("res://data/competition/stages/russia_stage1.json", 1974)
	comp.player_penalty_ms = 0
	host.competition = comp
	var course := preload("res://scripts/rally/rally_stage_progress.gd").new()
	course.elapsed_s = 12.345
	host.course = course
	return host


func _run() -> void:
	print("--- UI AND INVENTORY REGRESSION CONTRACT ---")
	await _test_garage_pool_swap_blocking_and_sqlite()
	await _test_atomic_service_tire_inventory_rejection()
	await _test_service_panel_repairs_stock_tires()
	await _test_strategy_screen_nav_and_lossless_pool()
	await _test_pause_telemetry_and_workshop_cancel_color()
	var music := root.get_node_or_null("RallyMusic")
	if music != null and music.has_method("stop_menu_music"):
		music.call("stop_menu_music")
	await process_frame
	await process_frame
	print("UI_AND_INVENTORY_REGRESSION_CONTRACT ", "PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)


func _test_garage_pool_swap_blocking_and_sqlite() -> void:
	var vehicle := EscortScene.instantiate() as RallyEscortVehicle
	var host := _make_host(vehicle)
	host.add_child(vehicle)
	var garage := GarageScript.new()
	garage.vehicle = vehicle
	host.garage_panel = garage
	host.add_child(garage)
	root.add_child(host)
	await process_frame

	_populate_pool(vehicle)
	var inv: RallyTireInventory = vehicle.tire_inventory
	# Set distinct wear on FL and a same-compound stock tire + wet tire in stock
	inv.mounted[0]["state"]["wear_fraction"] = 0.12
	vehicle.sync_tire_inventory()
	var stock_same_idx := -1
	var stock_wet_idx := -1
	for i in inv.service_stock.size():
		var td: Dictionary = inv.service_stock[i]
		if str(td.get("compound_id", "")) == str(inv.mounted[0].get("compound_id", "")) and stock_same_idx < 0:
			stock_same_idx = i
			td["state"]["wear_fraction"] = 0.45
		elif str(td.get("compound_id", "")) == "gravel_wet" and stock_wet_idx < 0:
			stock_wet_idx = i
			td["state"]["wear_fraction"] = 0.05
	check(stock_same_idx >= 0 and stock_wet_idx >= 0, "pool has both matching-compound and gravel_wet stock tires")

	var orig_fl_id := int(inv.mounted[0]["id"])
	var same_stock_id := int(inv.service_stock[stock_same_idx]["id"])
	var wet_stock_id := int(inv.service_stock[stock_wet_idx]["id"])

	# Verify open_garage_for_event restricts, and subsequent open_garage resets restriction flags
	garage.open_garage_for_event({
		"confirmation_required": true,
		"compound_change_allowed": false,
		"allowed_compound_ids": ["gravel_wet"],
		"initial_tab": "strategy",
	})
	check(garage.mandatory_confirmation and not garage.compound_change_allowed, "event options apply restrictions")
	garage._pool_interact("mounted", 0)
	check(garage.selected_pool_tire_id == -1 and garage.notice_is_error, "compound_change_allowed=false blocks pool pick")
	garage.close_garage(true)
	garage.open_garage()
	check(not garage.mandatory_confirmation and garage.compound_change_allowed and garage.allowed_compound_ids.is_empty(), "open_garage resets stale event restrictions")

	# Verify may_service_tires()==false blocks pool edits
	host.allow_service = false
	garage._set_page(2)
	garage._pool_interact("mounted", 0)
	check(garage.selected_pool_tire_id == -1 and garage.notice_is_error, "may_service_tires()==false blocks pool pick")
	host.allow_service = true

	# Swap FL with same-compound stock tire -> verify exact ID swap even when compound matches
	garage._pool_interact("mounted", 0)
	check(garage.selected_pool_tire_id == orig_fl_id, "selected FL tire id")
	garage._pool_interact("stock", stock_same_idx)
	check(int(garage.draft_mounted_ids[0]) == same_stock_id, "same-compound swap replaces mounted ID in draft")
	# Now swap FL (now same_stock_id) with wet stock tire (gravel_wet) -> mixed compounds on car
	garage._pool_interact("mounted", 0)
	garage._pool_interact("stock", stock_wet_idx)
	check(int(garage.draft_mounted_ids[0]) == wet_stock_id, "mixed-compound swap puts wet tire ID on FL")
	check(garage.draft_wheel_compounds["FL"] == "gravel_wet", "FL draft compound reflects gravel_wet")

	# Save to SQLite setup store, reset, and reload
	var save_name := "_REGRESSION_TEST_MIXED_%d" % Time.get_ticks_usec()
	garage.modal_text = save_name
	garage._commit_new_setup()
	var saved_id := garage.active_setup_id
	check(saved_id > 0, "mixed strategy setup saves to SQLite store")
	# Change strategy draft before loading back
	garage._pool_interact("mounted", 0)
	garage._pool_interact("stock", stock_wet_idx)
	check(garage.draft_wheel_compounds["FL"] != "gravel_wet", "FL draft changed away from gravel_wet")
	# Restore via _load_selected_setup
	for idx in garage.setup_rows.size():
		if int(garage.setup_rows[idx].get("id", -1)) == saved_id:
			garage.selected_setup_index = idx
			garage.selected_setup_id = saved_id
			break
	garage._load_selected_setup()
	check(garage.draft_wheel_compounds["FL"] == "gravel_wet", "_load_selected_setup restores strategy.wheel_compound.FL")
	garage.database.delete_setup(garage._database_context(), saved_id)

	# Explicitly select wet_stock_id in pool after loading setup so _pool_plan_dirty = true preserves exact ID on confirm
	var target_stock_pos := garage.draft_stock_ids.find(wet_stock_id)
	if target_stock_pos >= 0:
		garage._pool_interact("mounted", 0)
		garage._pool_interact("stock", target_stock_pos)
	# Confirm close_garage(true) applies mixed pool plan without overwriting compounds
	garage.close_garage(true)
	check(int(inv.mounted[0]["id"]) == wet_stock_id, "close_garage(true) mounted exact wet stock tire ID")
	check(vehicle.simulation.thermal_model.compound_for_wheel(0).id == "gravel_wet", "FL physics compound stays gravel_wet")
	check(vehicle.simulation.thermal_model.compound_for_wheel(1).id == "gravel_normal", "FR physics compound stays gravel_normal")

	host.queue_free()
	await process_frame
	await process_frame


func _test_atomic_service_tire_inventory_rejection() -> void:
	var vehicle := EscortScene.instantiate() as RallyEscortVehicle
	root.add_child(vehicle)
	await process_frame
	_populate_pool(vehicle)
	var inv: RallyTireInventory = vehicle.tire_inventory

	# Ruin every gravel_wet tire across mounted/spares/stock so request for 4x gravel_wet + 2 spares must fail atomically
	for group in [inv.mounted, inv.spares, inv.service_stock]:
		for i in (group as Array).size():
			var td: Dictionary = group[i]
			if str(td.get("compound_id", "")) == "gravel_wet":
				td["state"]["leak_per_second"] = 0.05

	var before_snap := JSON.stringify(inv.snapshot())
	var res := vehicle.service_tire_inventory({"FL": "gravel_wet", "FR": "gravel_wet", "RL": "gravel_wet", "RR": "gravel_wet"}, 2)
	check(not bool(res.get("ok", true)), "service_tire_inventory rejects exhausted healthy stock atomically")
	check(JSON.stringify(inv.snapshot()) == before_snap, "failed service_tire_inventory leaves inventory untouched")

	var snap_fail := vehicle.apply_setup_snapshot({
		"values": {},
		"wheel_compounds": {"FL": "gravel_wet", "FR": "gravel_wet", "RL": "gravel_wet", "RR": "gravel_wet"},
		"spare_wheels": 2,
	})
	check(not bool(snap_fail.get("ok", true)), "apply_setup_snapshot propagates service_tire_inventory failure")

	vehicle.queue_free()
	await process_frame
	await process_frame


func _test_service_panel_repairs_stock_tires() -> void:
	var vehicle := EscortScene.instantiate() as RallyEscortVehicle
	root.add_child(vehicle)
	await process_frame
	_populate_pool(vehicle)
	var inv: RallyTireInventory = vehicle.tire_inventory
	check(not inv.service_stock.is_empty(), "service_stock populated")
	var stock_tire: Dictionary = inv.service_stock[0]
	var stock_id := int(stock_tire["id"])
	stock_tire["state"]["leak_per_second"] = 0.04
	stock_tire["state"]["pressure_loss_fraction"] = 0.5
	stock_tire["state"]["rim_deformation"] = 0.35

	var manager := EventManagerScript.new()
	manager.save_path = ""
	manager.begin_event({"preview": true})

	var sp := ServicePanelScript.new()
	var done := {"ok": false}
	sp.confirmed.connect(func(): done["ok"] = true)
	root.add_child(sp)
	sp.open(vehicle, manager, {
		"window_key": "stage1_to_stage2",
		"repair_minutes": 30,
		"repair_penalty_seconds_per_minute": 10,
	})
	await process_frame

	var inflate_box: CheckBox = null
	var rim_box: CheckBox = null
	for act in sp.tire_actions:
		if int(act.get("tire_id", -1)) == stock_id:
			if str(act.get("kind", "")) == "inflate":
				inflate_box = act.get("box") as CheckBox
			elif str(act.get("kind", "")) == "rim":
				rim_box = act.get("box") as CheckBox
	check(inflate_box != null and rim_box != null, "ServicePanel lists PARQUE stock tire Inflar and Rin checkboxes")
	if inflate_box != null and rim_box != null:
		inflate_box.button_pressed = true
		rim_box.button_pressed = true
		sp._refresh()
		check(sp._minutes() == sp.cost_inflate + sp.cost_rim, "ServicePanel _minutes counts stock tire repairs")
	sp._commit()
	await process_frame

	var updated := inv.find_tire(stock_id)
	check(is_zero_approx(float(updated["state"].get("leak_per_second", 1.0))), "stock tire puncture repaired")
	check(is_zero_approx(float(updated["state"].get("rim_deformation", 1.0))), "stock tire rim repaired")
	check(bool(done["ok"]), "ServicePanel completion callback ran")

	if is_instance_valid(sp):
		sp.queue_free()
	vehicle.queue_free()
	await process_frame
	await process_frame


func _test_strategy_screen_nav_and_lossless_pool() -> void:
	var scr := StrategyScreenScript.new()
	root.add_child(scr)
	await process_frame

	check(scr._focus_id == "mounted:0", "initial focus starts at mounted:0")
	var key_right := InputEventKey.new()
	key_right.keycode = KEY_RIGHT
	key_right.pressed = true
	scr._input(key_right)
	check(scr._focus_id == "mounted:1", "KEY_RIGHT moves focus to mounted:1")

	var dpad_down := InputEventJoypadButton.new()
	dpad_down.button_index = JOY_BUTTON_DPAD_DOWN
	dpad_down.pressed = true
	scr._input(dpad_down)
	check(scr._focus_id == "count:1", "DPAD_DOWN moves focus from mounted row to spare count row")

	# Test lossless spare <-> stock transfer across 2 -> 0 -> 2 spares
	scr.carried_spares_count = 2
	scr.spare_compounds = ["gravel_wet", "gravel_normal"]
	scr.service_extra_compounds = ["gravel_normal", "gravel_wet", "gravel_normal", "gravel_wet"]
	var multiset_before := (scr.spare_compounds + scr.service_extra_compounds).duplicate()
	multiset_before.sort()

	scr.carried_spares_count = 0
	scr._reconcile_pool()
	check(scr.spare_compounds.is_empty() and scr.service_extra_compounds.size() == 6, "0 spares shifts both to service stock cleanly")
	scr.carried_spares_count = 2
	scr._reconcile_pool()
	var multiset_after := (scr.spare_compounds + scr.service_extra_compounds).duplicate()
	multiset_after.sort()
	check(multiset_after == multiset_before, "_reconcile_pool preserves exact compound multiset across 2->0->2")

	var emitted := {}
	scr.strategy_confirmed.connect(func(payload: Dictionary): emitted.merge(payload, true))
	scr._focus_id = "confirm"
	var joy_a := InputEventJoypadButton.new()
	joy_a.button_index = JOY_BUTTON_A
	joy_a.pressed = true
	scr._input(joy_a)
	check(int(emitted.get("mounted_compounds", []).size()) + int(emitted.get("spares_compounds", []).size()) + int(emitted.get("service_compounds", []).size()) == 10, "JOY_BUTTON_A on confirm emits 10-tire pool")

	scr.queue_free()
	await process_frame


func _test_pause_telemetry_and_workshop_cancel_color() -> void:
	var vehicle := EscortScene.instantiate() as RallyEscortVehicle
	var host := _make_host(vehicle)
	host.add_child(vehicle)
	var pause := PauseInventoryScript.new()
	pause.session = host
	host.add_child(pause)
	root.add_child(host)
	await process_frame

	_populate_pool(vehicle)
	vehicle.simulation.thermal_model.tire_states[0]["carcass_failure"] = 1.0
	vehicle.simulation.thermal_model.tire_states[0]["wear_fraction"] = 0.35
	vehicle.sync_tire_inventory()
	pause.modal.show()
	pause._update_telemetry_panel()
	var telemetry_text := _collect_label_text(pause.telemetry_panel)
	check("DESTALONADO" in telemetry_text and "65%" in telemetry_text, "telemetry surfaces DESTALONADO and remaining life %")

	# Check workshop 3D spare slot color reset on cancel_transfer()
	pause.show_inventory()
	var workshop := pause.content.get_child(0)
	workshop.select_slot(0)
	workshop.activate()
	check(workshop.held == 0 and workshop.buttons[0].modulate != Color.WHITE, "held workshop tile highlights tint")
	workshop.cancel_transfer()
	var all_white := true
	for b in workshop.buttons:
		if not b.modulate.is_equal_approx(Color.WHITE):
			all_white = false
	check(all_white, "cancel_transfer resets modulate to Color.WHITE on all buttons")

	# Verify no dead "+ <compound>" buttons exist in stock list and ID-based "+ #<id>" buttons render
	vehicle.tire_inventory.spares.clear()
	pause.show_inventory()
	var has_dead_compound_btn := false
	var has_id_stock_btn := false
	for child in pause.content.get_children():
		if child is HBoxContainer:
			for sub in child.get_children():
				if sub is Button:
					var txt := (sub as Button).text
					if txt.begins_with("+ ") and not txt.begins_with("+ #"):
						has_dead_compound_btn = true
					elif txt.begins_with("+ #"):
						has_id_stock_btn = true
	check(not has_dead_compound_btn and has_id_stock_btn, "pause stock uses ID-based + #<id> load buttons without dead + <compound> buttons")

	host.queue_free()
	await process_frame
	await process_frame
