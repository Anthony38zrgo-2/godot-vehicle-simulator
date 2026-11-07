extends SceneTree

const Competition = preload("res://scripts/rally/rally_competition.gd")
const CompetitionPanel = preload("res://scripts/rally/rally_competition_panel.gd")

var panel: Control
var frame_count := 0
var out_dir := "user://results_redesign/"
var brain_dir := "C:/Users/bill/.gemini/antigravity/brain/f555cd39-d09d-485e-9ac7-83b5ba3bd42a/"
var sim

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)

	sim = Competition.new()
	sim.save_path = ""
	assert(sim.configure())

	panel = CompetitionPanel.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		# 1. Presentar resultados de etapa (Stage Results)
		sim.complete = true
		sim.player_ms = 161542 # 2:41.542
		sim.player_previous_ms = 0
		sim.player_penalty_ms = 0
		sim.player_retired = false
		var state: Dictionary = sim.readout()
		state["event_stage_id"] = "russia_stage1"
		state["event_cursor"] = 0
		state["event_total"] = 10
		state["event_schedule"] = {"day_label": "Viernes", "start": "08:30"}
		state["event_player_retired"] = false
		state["event_is_last"] = false
		state["event_status"] = "running"
		panel.present(state, Vector2(1280, 720))
		print("Stage results presented")
	elif frame_count == 6:
		_save_capture("new_stage_results_720.png")
		# 2. Presentar resultados finales del Rally (Final Results)
		var final_state: Dictionary = {}
		final_state["complete"] = true
		final_state["event_status"] = "finished"
		final_state["event_stage_id"] = "russia_stage10"
		final_state["event_cursor"] = 9
		final_state["event_total"] = 10
		final_state["event_schedule"] = {"day_label": "Domingo", "start": "15:45"}
		final_state["event_player_retired"] = false
		final_state["event_is_last"] = true
		final_state["event_points"] = {
			"winner": "timo_makinen",
			"general": {"timo_makinen": 18, "sandro_munari": 15, "player": 13, "waldegard": 10},
			"sunday": {"timo_makinen": 7, "sandro_munari": 6, "player": 5, "waldegard": 4},
			"power": {"player": 5, "timo_makinen": 4, "sandro_munari": 3, "waldegard": 2},
			"total": {"timo_makinen": 29, "sandro_munari": 24, "player": 23, "waldegard": 16}
		}
		final_state["event_final_rows"] = [
			{"id": "timo_makinen", "name": "Timo Mäkinen", "car": "Ford Escort RS1600", "team": "Ford Motor Co.", "position": 1, "grand_total_ms": 1642850},
			{"id": "sandro_munari", "name": "Sandro Munari", "car": "Lancia Stratos HF", "team": "Lancia Marlboro", "position": 2, "grand_total_ms": 1655120},
			{"id": "player", "name": "Jugador", "car": "Ford Escort RS2000", "team": "Ford Rally Works", "position": 3, "grand_total_ms": 1661200},
			{"id": "waldegard", "name": "Björn Waldegård", "car": "Porsche 911 Carrera RS", "team": "Privado", "position": 4, "grand_total_ms": 1673400},
			{"id": "rohrl", "name": "Walter Röhrl", "car": "Opel Ascona 1.9 SR", "team": "Privado", "position": 5, "grand_total_ms": 1689500}
		]
		panel.present(final_state, Vector2(1280, 720))
		print("Final results presented")
	elif frame_count == 9:
		_save_capture("new_final_results_720.png")
		print("RESULTS_UI_VISUAL_PROBE PASS")
		quit(0)
	return false

func _save_capture(filename: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if img != null:
		var p := out_dir + filename
		img.save_png(p)
		var p_brain := brain_dir + filename
		img.save_png(p_brain)
		print("Saved capture: ", filename)
