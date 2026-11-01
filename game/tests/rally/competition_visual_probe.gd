extends SceneTree
const Competition = preload("res://scripts/rally/rally_competition.gd")
const CompetitionPanel = preload("res://scripts/rally/rally_competition_panel.gd")
var panel: Control
func _initialize() -> void:
	call_deferred("run")
func capture(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	var sim = Competition.new()
	sim.save_path = ""
	assert(sim.configure())
	panel = CompetitionPanel.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var course = preload("res://scripts/rally/rally_stage_progress.gd").new()
	assert(course.configure(sim.stage.route_path))
	assert(course.configure_timing_gates(sim.stage.timing_gates))
	var map_panel = preload("res://scripts/rally/formula_hud_panels.gd").new()
	root.add_child(map_panel)
	root.move_child(map_panel, 0)
	map_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_panel.present({"course": course.readout()}, {})
	root.size = Vector2i(1280,720)
	panel.present(sim.readout(), Vector2(1280,720))
	await capture("user://competition_hud_720.png")
	var lights = preload("res://scripts/rally/rally_start_lights.gd").new()
	root.add_child(lights)
	lights.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for phase in ["off", "ready", "go"]:
		lights.present({"visible": true, "phase": phase})
		await capture("user://rally_start_%s_720.png" % phase)
	lights.visible = false
	sim.add_penalty("player", 10000, "Salida anticipada")
	sim.update({"splits": [{"time_ms": 19000}], "current_s": 19.0, "running": true})
	panel.present(sim.readout(), Vector2(1280,720))
	await capture("user://competition_penalty_720.png")
	sim.retire_player()
	panel.present(sim.readout(), Vector2(1280,720))
	await capture("user://competition_results_720.png")
	root.size = Vector2i(1920,1080)
	panel.present(sim.readout(), Vector2(1920,1080))
	await capture("user://competition_results_1080.png")
	print("COMPETITION_VISUAL_PROBE PASS ", ProjectSettings.globalize_path("user://"))
	quit()

