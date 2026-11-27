class_name FinalPodiumView
extends VBoxContainer
## Final rally podium hero cards composed from UIPodiumCard and UIStatCard.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _PodiumCardScript := preload("res://ui/molecules/ui_podium_card.gd")
const _StatCardScript := preload("res://ui/molecules/ui_stat_card.gd")


func populate_podium_cards(target_vbox: VBoxContainer, rows: Array, points: Dictionary, clock_cb: Callable) -> void:
	for child in target_vbox.get_children():
		child.queue_free()

	var total_points_dict: Dictionary = points.get("total", {})
	var player_in_top3 := false

	for i in mini(3, rows.size()):
		var r: Dictionary = rows[i]
		var pid := str(r.get("id", ""))
		var is_player := (pid == "player")
		if is_player:
			player_in_top3 = true
		var rank := i + 1
		var pts_str := "%d PTS" % int(total_points_dict.get(pid, 0))
		var car_team := str(r.get("car", "")) + " · " + str(r.get("team", ""))
		var card := _PodiumCardScript.new()
		card.configure(rank, str(r.get("name", "")), car_team, str(clock_cb.call(r.get("grand_total_ms"))), pts_str, is_player)
		target_vbox.add_child(card)

	if not player_in_top3:
		var player_row: Dictionary = {}
		for r: Dictionary in rows:
			if str(r.get("id", "")) == "player":
				player_row = r
				break
		if not player_row.is_empty():
			var p_rank := int(player_row.get("position", 0))
			var p_total := int(total_points_dict.get("player", 0))
			var p_gen := int((points.get("general", {}) as Dictionary).get("player", 0))
			var p_sun := int((points.get("sunday", {}) as Dictionary).get("player", 0))
			var p_pwr := int((points.get("power", {}) as Dictionary).get("player", 0))
			var p_sub := "General: %d pts · Domingo: %d pts · Power Stage: %d pts" % [p_gen, p_sun, p_pwr]
			var card := _StatCardScript.new()
			card.set_stat(
				("Tu posición final: P%d" % p_rank).to_upper(),
				"%d PUNTOS TOTALES" % p_total,
				p_sub,
				_Tokens.get_color("text_gold_soft"),
				_Tokens.get_color("text_muted")
			)
			target_vbox.add_child(card)
