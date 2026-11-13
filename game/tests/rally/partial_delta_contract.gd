extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var competition = preload("res://scripts/rally/rally_competition.gd").new()
	competition.player_splits = [10000]
	competition.rows = [{"splits": [10100]}, {"splits": [10200]}, {"splits": []}]
	assert(competition.partial_delta_ms() == -100)
	competition.player_splits = [10200]
	assert(competition.partial_delta_ms() == 100)
	competition.player_splits = [10100]
	assert(competition.partial_delta_ms() == 0)
	competition.player_splits = [10100, 20000]
	assert(competition.partial_delta_ms() == null)
	competition.player_splits = [10000]
	competition.rows[0]["name"] = "Sandro Munari"
	competition.rows[1]["name"] = "Hannu Mikkola"
	var summary := competition.readout()
	assert(summary.get("sector_deltas_ms", []) == [-100])
	var split_rows: Array = summary.get("split_standings", [])
	assert(split_rows.size() == 3)
	assert(bool(split_rows[0].player) and int(split_rows[0].position) == 1)
	var hud = load("res://scenes/rally/rally_f1_head_up_display.tscn").instantiate()
	root.add_child(hud)
	await process_frame
	assert(hud.get_node_or_null("AidMessage") == null)
	hud.show_status("SHOULD NOT APPEAR", Color.RED, 2.0)
	assert(hud.partial_banner != null)
	hud.show_partial(2, -100)
	assert(hud.partial_banner.formatted_text == "-00:00.10")
	assert(hud.partial_banner.box_color().is_equal_approx(Color(Color("#2efaa4").r, Color("#2efaa4").g, Color("#2efaa4").b, hud.partial_banner.BACKGROUND_ALPHA)))
	assert(is_equal_approx(hud.partial_banner.CENTER_Y_RATIO, 0.48))
	hud.show_partial(3, 100)
	assert(hud.partial_banner.formatted_text == "+00:00.10")
	assert(hud.partial_banner.box_color().is_equal_approx(Color(Color("#8a0000").r, Color("#8a0000").g, Color("#8a0000").b, hud.partial_banner.BACKGROUND_ALPHA)))
	hud.show_partial(4, 0)
	assert(hud.partial_banner.formatted_text == "-00:00.00")
	hud.show_partial(5, null)
	assert(hud.partial_banner.formatted_text == "--:--.--")
	assert(hud.retro_hud != null)
	assert(hud.retro_hud.is_cmr2_digital_style())
	assert(not hud.retro_hud.is_ribbon_style())
	hud.published["steering"] = -0.5
	hud.published["throttle"] = 0.8
	hud.published["brake"] = 0.2
	hud.update_thermal_readout()
	hud.update_driving_controls()
	assert(hud.retro_hud.size.is_equal_approx(hud.retro_hud.get_cmr2_dash_size()))
	assert(hud.driving_controls != null and hud.driving_controls.visible)
	assert(is_equal_approx(hud.driving_controls.steering_fraction, -0.5))
	assert(is_equal_approx(hud.driving_controls.accelerator_fraction, 0.8))
	assert(is_equal_approx(hud.driving_controls.brake_fraction, 0.2))
	hud.queue_free()
	print("PARTIAL_DELTA_CONTRACT PASS")
	quit()
