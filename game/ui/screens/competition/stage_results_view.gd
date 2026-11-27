class_name StageResultsView
extends VBoxContainer
## Stage completion hero summary cards composed from UIStatCard.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _StatCardScript := preload("res://ui/molecules/ui_stat_card.gd")


func populate_stage_cards(target_vbox: VBoxContainer, state: Dictionary, clock_cb: Callable) -> void:
	for child in target_vbox.get_children():
		child.queue_free()

	var rows: Array = state.get("rows", [])
	var player_row: Dictionary = {}
	var best_stage_ms: int = 999999999
	var total_classified := 0

	for r: Dictionary in rows:
		if bool(r.get("player", false)):
			player_row = r
		var s_ms = r.get("stage_ms")
		if s_ms != null and int(s_ms) > 0 and not bool(r.get("retired", false)):
			total_classified += 1
			if int(s_ms) < best_stage_ms:
				best_stage_ms = int(s_ms)

	var retired := bool(player_row.get("retired", false))
	var player_stage_ms = player_row.get("stage_ms")
	var player_total_ms = player_row.get("total_ms")
	var player_pos := int(player_row.get("position", 0))
	var penalty_ms := int(player_row.get("penalty_ms", 0))

	var c_gold := _Tokens.get_color("accent_rally")
	var c_gold_hi := _Tokens.get_color("text_gold_soft")
	var c_info := _Tokens.get_color("status_info")
	var c_danger := _Tokens.get_color("status_danger")
	var c_success := _Tokens.get_color("status_success")
	var c_text := _Tokens.get_color("text_primary")
	var c_dim := _Tokens.get_color("text_muted")
	var c_silver := _Tokens.get_color("podium_silver")
	var c_bronze := _Tokens.get_color("podium_bronze")

	# 1. Tiempo de Especial
	if not retired and player_stage_ms != null:
		var p_ms := int(player_stage_ms)
		var diff := (p_ms - best_stage_ms) / 1000.0
		var sub := "★ SCRATCH DE ESPECIAL (MEJOR TIEMPO)" if diff <= 0.001 else "+%.3f s respecto al líder de tramo" % diff
		var sub_col := c_gold if diff <= 0.001 else c_info
		target_vbox.add_child(_make_card("Tiempo en la especial", str(clock_cb.call(p_ms)), sub, c_gold_hi, sub_col))
	else:
		target_vbox.add_child(_make_card("Tiempo en la especial", "ABANDONO", "No completó el recorrido oficial", c_danger, c_dim))

	# 2. Posición en Especial
	if not retired and player_stage_ms != null:
		var stage_rank := 1
		for r: Dictionary in rows:
			if not bool(r.get("player", false)) and not bool(r.get("retired", false)):
				var other_ms = r.get("stage_ms")
				if other_ms != null and int(other_ms) < int(player_stage_ms):
					stage_rank += 1
		var rank_color := c_gold if stage_rank == 1 else (c_silver if stage_rank == 2 else (c_bronze if stage_rank == 3 else c_text))
		target_vbox.add_child(_make_card("Posición de tramo", "P%d" % stage_rank, "de %d pilotos clasificados" % total_classified, rank_color, c_dim))
	else:
		target_vbox.add_child(_make_card("Posición de tramo", "DNF", "Sin posición válida en este tramo", c_danger, c_dim))

	# 3. Clasificación General
	if not retired and player_total_ms != null:
		var pos_str := "P%d EN LA GENERAL" % player_pos if player_pos > 0 else "SIN CLASIFICAR"
		target_vbox.add_child(_make_card("Clasificación general", pos_str, "Tiempo acumulado: %s" % str(clock_cb.call(player_total_ms)), c_text, c_dim))
	else:
		target_vbox.add_child(_make_card("Clasificación general", "REENGANCHE", "Tiempo acumulado con +300 s de penalización", c_danger, c_dim))

	# 4. Estado y Sanciones
	if penalty_ms > 0:
		target_vbox.add_child(_make_card("Incidencias / Estado", "+%.0f s PENALIZACIÓN" % (float(penalty_ms) / 1000.0), str(player_row.get("status", "Sanción aplicada")), c_danger, c_dim))
	elif retired:
		target_vbox.add_child(_make_card("Incidencias / Estado", "ABANDONO REGISTRADO", "Reenganche aplicado para continuar el evento", c_danger, c_dim))
	else:
		target_vbox.add_child(_make_card("Incidencias / Estado", "ESPECIAL LIMPIA", "Sin sanciones ni incidencias de carrera", c_success, c_dim))


func _make_card(title_text: String, primary_text: String, sub_text: String, primary_color: Color, sub_color: Color) -> PanelContainer:
	var card := _StatCardScript.new()
	card.set_stat(title_text.to_upper(), primary_text, sub_text, primary_color, sub_color)
	return card
