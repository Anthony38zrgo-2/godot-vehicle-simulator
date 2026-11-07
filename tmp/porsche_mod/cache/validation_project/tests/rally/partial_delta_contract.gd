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
	var hud = load("res://scenes/rally/rally_f1_head_up_display.tscn").instantiate()
	root.add_child(hud)
	await process_frame
	hud.show_partial(2, -100)
	assert(hud.partial_message.text == "Parcial 2,  -0.100")
	assert(hud.partial_message.modulate == hud.hud_palette.thermal_optimal_color)
	assert(is_equal_approx(hud.partial_message.anchor_top, 0.25))
	hud.show_partial(3, 100)
	assert(hud.partial_message.text == "Parcial 3,  +0.100")
	assert(hud.partial_message.modulate == hud.hud_palette.thermal_hot_color)
	hud.show_partial(4, 0)
	assert(hud.partial_message.text == "Parcial 4,  +0.000")
	hud.show_partial(5, null)
	assert(hud.partial_message.text == "Parcial 5,  —")
	hud.queue_free()
	print("PARTIAL_DELTA_CONTRACT PASS")
	quit()
