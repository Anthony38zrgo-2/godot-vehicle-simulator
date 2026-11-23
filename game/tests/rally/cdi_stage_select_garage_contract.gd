extends SceneTree

const FRONT_DUCT := "brakes.thermal.front_duct.opening"
const REAR_DUCT := "brakes.thermal.rear_duct.opening"


func _initialize() -> void:
	call_deferred("_verify")


func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok


func _verify() -> void:
	var menu := (load("res://scenes/rally/rally_maniac_menu.tscn") as PackedScene).instantiate() as RallyManiacMenu
	root.add_child(menu)
	current_scene = menu
	if not _require(menu.current_screen == "stage_select" and menu.stage_buttons.size() == 4,
			"CDI did not start with the four stages"):
		return
	for i in range(4):
		var stage_id := "cdi_stage%d" % (i + 1)
		menu.stage_buttons[i].pressed.emit()
		if not _require(menu.selected_stage_id == stage_id and menu.current_screen == "car_select"
				and not (menu.stage_routes_cache.get(stage_id) as PackedVector2Array).is_empty(),
				"Stage card did not load its route and open car selection"):
			return
		menu.btn_car_back.pressed.emit()
		if not _require(menu.current_screen == "stage_select" and menu.selected_stage_id == stage_id,
				"Back did not return to the chosen stage"):
			return
	menu.stage_buttons[2].pressed.emit()
	menu.btn_car_confirm.pressed.emit()
	if not _require(menu.current_screen == "weather_select", "Car confirmation did not open weather"):
		return
	menu.btn_weather_confirm.pressed.emit()
	var session: RallyRussiaStageSession
	var strategy: RallyTireStrategyScreen
	for i in range(1800):
		await process_frame
		session = current_scene as RallyRussiaStageSession
		if session != null:
			strategy = session.find_child("RallyTireStrategyScreen", true, false) as RallyTireStrategyScreen
			if strategy != null:
				break
	if not _require(session != null and session.session_track_id == "cdi_stage3"
			and session.stage_place == "Chinchán Asfalto"
			and session.event_manager.stage_order == ["cdi_stage3", "cdi_stage4"]
			and strategy != null and paused and not session.garage_panel.visible,
			"Launching from SS03 did not reach the tire strategy"):
		return
	var expected_cids := ["gravel_normal", "asphalt_dry", "asphalt_mixed"]
	var strategy_board := strategy.get_node_or_null("StrategyBoard3D")
	if not _require(strategy.allowed_compounds == expected_cids
			and str(strategy.compound_labels.get("gravel_normal", "")) == "Grava"
			and str(strategy.compound_labels.get("asphalt_dry", "")) == "Asfalto"
			and str(strategy.compound_labels.get("asphalt_mixed", "")) == "Mixto"
			and strategy_board != null
			and strategy_board._compound_short_label("gravel_normal") == "GRAVA"
			and strategy_board._compound_short_label("asphalt_dry") == "ASFALTO"
			and strategy_board._compound_short_label("asphalt_mixed") == "MIXTO",
			"CDI strategy screen must expose only Grava, Asfalto, and Mixto"):
		return
	strategy.set_step(1)
	strategy._on_confirm()
	for i in range(180):
		await process_frame
		if session.garage_panel.visible:
			break
	var garage := session.garage_panel as RallyGaragePanel
	if not _require(garage.visible and session.awaiting_setup and session.vehicle.freeze and garage.page == 0
			and FRONT_DUCT in garage._page_field_paths and REAR_DUCT in garage._page_field_paths,
			"Tire confirmation did not open the garage with both duct sliders"):
		return
	if not _require(garage._available_compound_ids() == expected_cids
			and garage._compound_label("gravel_normal") == "Grava"
			and garage._compound_label("gravel_normal", true) == "GRAVA"
			and garage._compound_label("asphalt_dry") == "Asfalto"
			and garage._compound_label("asphalt_dry", true) == "ASFALTO"
			and garage._compound_label("asphalt_mixed") == "Mixto"
			and garage._compound_label("asphalt_mixed", true) == "MIXTO"
			and RallyTireCompound.compound_label("gravel_normal") == "Grava-Seco",
			"CDI garage must restrict and rename compounds without altering global catalog"):
		return
	var thermal := session.vehicle.simulation.thermal_model as VehicleThermalModel
	var track := Rect2(0, 0, 100, 10)
	garage._set_from_slider(FRONT_DUCT, 0.0, track)
	garage._set_from_slider(REAR_DUCT, 0.0, track)
	var front_closed := float(thermal._brake_heat_losses(0, 400.0, 30.0, 20.0).cooling_w)
	var rear_closed := float(thermal._brake_heat_losses(2, 400.0, 30.0, 20.0).cooling_w)
	garage._set_from_slider(FRONT_DUCT, 75.0, track)
	if not _require(float(thermal._brake_heat_losses(0, 400.0, 30.0, 20.0).cooling_w) > front_closed
			and is_equal_approx(float(thermal._brake_heat_losses(2, 400.0, 30.0, 20.0).cooling_w), rear_closed),
			"Front duct must cool the front brakes independently"):
		return
	garage._set_from_slider(REAR_DUCT, 35.0, track)
	if not _require(float(thermal._brake_heat_losses(2, 400.0, 30.0, 20.0).cooling_w) > rear_closed,
			"Rear duct must cool the rear brakes"):
		return
	garage.close_garage(true)
	var setup: Dictionary = session.event_manager.setup_values
	if not _require(not session.awaiting_setup and session.event_manager.get_pending_window().is_empty()
			and is_equal_approx(float(setup.get(FRONT_DUCT, 0.0)), 0.75)
			and is_equal_approx(float(setup.get(REAR_DUCT, 0.0)), 0.35),
			"Confirmed duct openings did not persist with the event setup"):
		return
	var legacy_setup := setup.duplicate()
	legacy_setup.erase(FRONT_DUCT)
	legacy_setup.erase(REAR_DUCT)
	if not _require(bool(session.vehicle.apply_setup_values(legacy_setup).get("ok", false))
			and is_equal_approx(float(thermal.brake_thermal_config.front_duct.opening), 0.75)
			and is_equal_approx(float(thermal.brake_thermal_config.rear_duct.opening), 0.35),
			"An older setup without ducts must preserve the current openings"):
		return
	print("CDI_STAGE_SELECT_AND_GARAGE_OK")
	var music := root.get_node_or_null("RallyMusic")
	if music != null:
		music.call("on_start_rally")
	session.queue_free()
	await create_timer(0.2).timeout
	quit()
